# d2d1 geometry fix – technical notes

**File:** `dlls/d2d1/geometry.c` · **Based on:** Wine 11.19 (2026-10-13), applies unchanged to 11.15–11.20 · **Upstream bug:** [60115](https://bugs.winehq.org/show_bug.cgi?id=60115)

Wine's Direct2D triangulates every filled path geometry (constrained Delaunay triangulation, "CDT"). Plugin interfaces that draw through Direct2D (JUCE 8 plugins such as Serum 2, Ozone 11 and others) regularly produce **degenerate geometry**: duplicate or collinear vertices, coincident Bézier curves. Several places in `geometry.c` never terminate on such input.

**Symptom:** FL Studio freezes as soon as a plugin window is drawn. Audio keeps playing, the GUI is dead (the main thread died of a stack overflow and the process is a zombie, or it spins in an infinite loop). The only way out is `wineserver -k`.

## The seven defects

(plus a performance change, see below)

Found by live debugging (2026-05), by fuzzing with random degenerate paths (2026-10) and with large regular paths (2026-11, see below).

| # | Function | Defect (stock Wine) | Fix |
|---|---|---|---|
| 1 | `d2d_cdt_insert_segment` | Unbounded recursion between two origins A→B→A → stack overflow | Tail recursion → `goto restart` + iteration limit `16 * edge_count + 0x10000` |
| 2 | `d2d_cdt_insert_segment` (skip paths) | The previous version of this patch skipped a segment with `return TRUE` **without setting `*edge`** → the caller continued with a stale/freed edge → page fault | The skip paths return a valid edge at the target vertex via `d2d_cdt_find_vertex_edge()` (or fail cleanly) |
| 3 | `d2d_cdt_cut_edges` | Unbounded (non-tail) recursion: one level per edge the new segment crosses → stack overflow, **even on regular input** (`tools/d2d1_pathgen.py band 9500`) | Iterative: collect the crossed edges first, then delete them in reverse order (same order as the recursion) |
| 3b | `d2d_cdt_cut_edges` (cycle) | On degenerate input the walk can cycle and reach the same edge twice. The previous version of this patch stopped only after `edge_count` steps, so that edge was **destroyed twice** → page fault (fuzzer seed 371,335; unpatched Wine returned `E_FAIL` there because it gave up earlier) | Every crossed edge is marked (`D2D_CDT_EDGE_FLAG_CUT`); reaching a marked edge stops the walk and leaves the triangulation untouched. A straight segment crosses each edge at most once, so this never triggers on valid input |
| 4 | `d2d_cdt_fixup` | The face walk never gets back to its origin → infinite loop | Stop after `2 * edge_count + 16` steps → `FALSE` (like upstream's "degenerate face" path) |
| 4b | `d2d_cdt_fixup` (recursion) | Re-triangulating the faces left after a segment recurses once per split-off triangle → stack overflow on large regular paths (`band 25000` crashed even with the previous version of this patch) | Pending edges on an explicit stack; the left side of each new edge is still processed before its right side, so the triangulation is unchanged (fill pixel-identical in 26 of 26 compared cases) |
| 5 | `d2d_geometry_resolve_beziers` | Overlapping control triangles are split forever (every split creates new overlaps), memory grows without bound | Budget of `16 * bezier_count + 1024` splits per geometry; after that the remaining overlap stays (a slightly imprecise fill instead of a hang) |

Every bail-out ends in an existing error path: either one segment is skipped, or the fill of that single geometry is dropped (`E_FAIL`, the geometry isn't filled). Never a crash, never a hang.

## Performance: stroked paths skip the fill preparation

`d2d_geometry_sink_Close()` computes the self-intersections of every figure (`d2d_geometry_intersect_self`, O(n²)), although they are only needed to triangulate the fill. The outline is already built in `EndFigure()`. In `strokePath()`, JUCE 8 creates a new geometry with `D2D1_FIGURE_BEGIN_HOLLOW` on every call and only draws its outline.

The patch skips hollow figures in `d2d_geometry_intersect_self` - triangulation and Bézier resolution already do the same. With 400 Bézier segments, `Close()` drops from 3.32 ms to under 0.01 ms and the total time per path from 3.58 to 0.31 ms. Inside FL Studio this made no measurable difference (see [docs/verification.md](../docs/verification.md)), so this hunk is independent of the fixes above.

## Memory leak (fixed upstream, came with the rebuild)

The old DLL (Wine 11.9) never freed `figure->vertex_types`. Measured: **+17.5 KB per path geometry**, 0 with the new DLL. For plugin interfaces that rebuild their geometry every frame, this was a constant leak for as long as the window was open.

## Verification (2026-10-13)

**Fuzzing** - random paths on a 6×6 grid (many duplicates/collinear points), 1–4 figures, lines + Béziers, both fill modes (`tools/d2d1_fuzz.cpp`):

| DLL | Result |
|---|---|
| Stock Wine 11.19 (builtin) | stack overflows and hangs in every block of 10,000 |
| Old patched DLL (Wine 11.9) | hangs in every block of 10,000 (first at seed 940) |
| Patched DLL of 2026-10-13 | 240,000 seeds without a failure; seed 371,335 (found 2026-11-25) crashes, see 3b |
| **Patched DLL of 2026-11-26** | **seeds 0–460,000: 0 hangs, 0 crashes** |

**Large regular paths** (`tools/d2d1_pathgen.py`, replayed with `tools/d2d1_runpath.exe`): all eight families at 10,000 vertices and `bandw` at 30,000 close without a failure. Unpatched Wine overflows the stack from `band 9500`. Very large paths are still slow (`bandw 30000`: ~28 s, `d2d_cdt_fixup` is O(n²)) - a speed limit, not a crash.

**Wine test suite** `dlls/d2d1/tests` (17,475 tests): stock and patched give **identical** results (0 failures in a clean prefix) → no regression on well-formed geometry. In freshly created prefixes the suite occasionally stops in the middle of the GL rendering tests with exit code 5 and no summary - measured with unpatched and patched DLLs alike (about one run in five to ten), so it's unrelated to this patch.

## The prebuilt DLL

`assets/d2d1.dll.patched` - Wine 11.19 source (`dlls/d2d1` is identical in 11.19, 11.20 and master up to 2026-11), x86_64, builtin marker at offset 0x40 zeroed. Built 2026-11-26.
- **MD5:** `9b485ac972415e8a9c07993bff5a4e27` (previous build of 2026-10-13: `fd197f30b36451714e5fc5a7afc148c9`)
- The launcher copies it into the prefix on the next start if the prefix still has an older one.
- d2d1 is a pure PE DLL, so it also works with other Wine versions. Rebuilding is worthwhile when upstream fixes bugs in `dlls/d2d1/` (like the leak above).

## Rebuilding for a new Wine version

```bash
# Source tree (for staging: run patchinstall first), then:
cd wine-X.Y && patch -p1 < .../patches/d2d1-geometry-fix.patch
mkdir ../build && cd ../build && ../wine-X.Y/configure --enable-win64
make -j$(nproc) dlls/d2d1/x86_64-windows/d2d1.dll
cp dlls/d2d1/x86_64-windows/d2d1.dll .../assets/d2d1.dll.patched
bash .../scripts/04-apply-d2d1-patch.sh   # copies, zeroes 0x40, sets the DllOverride
```

Check whether upstream changed d2d1 (then a rebuild is worthwhile):

```bash
diff -rq wine-OLD/dlls/d2d1/ wine-NEW/dlls/d2d1/ \
     --exclude="*.o" --exclude="*.dll" --exclude="Makefile" \
     --exclude="version.res" --exclude="x86_64-windows"
```

Between 11.9 and 11.19, upstream changed `device.c`, `effect.c` and `command_list.c` among others and added `sprite_batch.c` - so the old DLL was ten versions behind.

## Upstream submission (in progress, 2026-10-21, updated 2026-11-26)

The fix is being prepared as a merge request for Wine (announced in [bug 60115, comment 4](https://bugs.winehq.org/show_bug.cgi?id=60115#c4)). Against current Wine master (after 11.20) it is split into one commit per defect, without the hollow-figure change:

1. `d2d1: Factor out d2d_cdt_find_vertex_edge().` (no functional change)
2. `d2d1: Avoid unbounded recursion in d2d_cdt_insert_segment().`
3. `d2d1: Avoid unbounded recursion in d2d_cdt_cut_edges().`
4. `d2d1: Limit Bezier splitting in d2d_geometry_resolve_beziers().`
5. `d2d1: Bound the face walk in d2d_cdt_fixup().`

Each commit builds without warnings, and after each one the d2d1 test suite gives the same result as unpatched Wine (17,475 tests, 0 failures, 245 todo, 1 skipped). The final state is identical to `d2d1-geometry-fix.patch` minus the hollow-figure hunks.

**Which commit fixes what** - the fuzzer's first 14 failing seeds against unpatched Wine 11.20 (seeds 0–15,327), each replayed on its own:

| Seeds | Unpatched | Fixed by | `Close()` afterwards |
|---|---|---|---|
| 2619, 2935, 4855, 7037, 8500, 9620, 9708, 11154, 13065, 14118, 15327 | crash (stack overflow) | 2 – `d2d_cdt_insert_segment` | `S_OK` for 9, `E_FAIL` for 2935 and 14118 |
| 940 | hang | 5 – `d2d_cdt_fixup` | `E_FAIL` |
| 6819, 15155 | hang | 4 – Bézier limit | `S_OK` |

With commit 2 applied, the fuzzer (seeds 0 to ~56,000) found only hangs; the 12 that were replayed are all fixed by commits 4 and 5. **No input that needs commit 3 (`d2d_cdt_cut_edges`) has been found yet**, so that commit currently has no reproducer.

`E_FAIL` means the fill of that one geometry is dropped. Windows most likely returns `S_OK` for these paths, so regression tests for them will need `todo_wine`.

**Update 2026-11-26:** commit 3 now has a reproducer (`band 9500`, regular input), and its walk detects a cycle by marking crossed edges (defect 3b) instead of counting to `edge_count` - the commit as listed above caused the double-destroy crash. A sixth commit makes `d2d_cdt_fixup()` iterative (defect 4b). Both are applied to this repository's patch already; the upstream branch gets them before submission.

Related upstream work: [MR !11421](https://gitlab.winehq.org/wine/wine/-/merge_requests/11421) (open since 2026-07-17) treats near-collinear quadratic Béziers as straight lines, which fixes the same kind of hang as commit 4 from the other side. Its test case (512 near-coincident quadratic Béziers) hangs in unpatched Wine and closes in ~3 s with this patch. The two changes don't conflict.

Still open: regression tests from minimized seeds (the first one, from seed 4855, is down to two figures and seven segments) and the submission itself.

## Known remaining limitation

`d2d_device_context_DrawGeometry` ignores stroke styles (dashes, round caps/joins) - Wine draws them as solid lines with default caps. That is a missing feature in Wine, not a crash risk. The launcher sets `WINEDEBUG=fixme-all` because Wine otherwise writes one fixme line per line drawn (measured 11,000 lines/s with a plugin window open).
