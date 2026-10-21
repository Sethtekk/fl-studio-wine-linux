# d2d1 geometry fix – technical notes

**File:** `dlls/d2d1/geometry.c` · **Based on:** Wine 11.19 (2026-10-13), applies unchanged to 11.15–11.20 · **Upstream bug:** [60115](https://bugs.winehq.org/show_bug.cgi?id=60115)

Wine's Direct2D triangulates every filled path geometry (constrained Delaunay triangulation, "CDT"). Plugin interfaces that draw through Direct2D (JUCE 8 plugins such as Serum 2, Ozone 11 and others) regularly produce **degenerate geometry**: duplicate or collinear vertices, coincident Bézier curves. Several places in `geometry.c` never terminate on such input.

**Symptom:** FL Studio freezes as soon as a plugin window is drawn. Audio keeps playing, the GUI is dead (the main thread died of a stack overflow and the process is a zombie, or it spins in an infinite loop). The only way out is `wineserver -k`.

## The five defects

(plus a performance change, see below)

Found by live debugging (2026-05) and by fuzzing with random degenerate paths (2026-10, see below).

| # | Function | Defect (stock Wine) | Fix |
|---|---|---|---|
| 1 | `d2d_cdt_insert_segment` | Unbounded recursion between two origins A→B→A → stack overflow | Tail recursion → `goto restart` + iteration limit `16 * edge_count + 0x10000` |
| 2 | `d2d_cdt_insert_segment` (skip paths) | The previous version of this patch skipped a segment with `return TRUE` **without setting `*edge`** → the caller continued with a stale/freed edge → page fault | The skip paths return a valid edge at the target vertex via `d2d_cdt_find_vertex_edge()` (or fail cleanly) |
| 3 | `d2d_cdt_cut_edges` | Unbounded (non-tail) recursion on cyclic topology → stack overflow | Iterative: collect the crossed edges first, then delete them in reverse order (same order as the recursion), stop after `edge_count` steps |
| 4 | `d2d_cdt_fixup` | The face walk never gets back to its origin → infinite loop | Stop after `2 * edge_count + 16` steps → `FALSE` (like upstream's "degenerate face" path) |
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
| **New patched DLL (Wine 11.19)** | **240,000 seeds: 0 hangs, 0 crashes** |

**Wine test suite** `dlls/d2d1/tests` (17,475 tests): stock and patched give **identical** results (0 failures in a clean prefix) → no regression on well-formed geometry.

## The prebuilt DLL

`assets/d2d1.dll.patched` - Wine Staging 11.19, x86_64, builtin marker at offset 0x40 zeroed.
- **MD5:** `fd197f30b36451714e5fc5a7afc148c9`
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

## Known remaining limitation

`d2d_device_context_DrawGeometry` ignores stroke styles (dashes, round caps/joins) - Wine draws them as solid lines with default caps. That is a missing feature in Wine, not a crash risk. The launcher sets `WINEDEBUG=fixme-all` because Wine otherwise writes one fixme line per line drawn (measured 11,000 lines/s with a plugin window open).
