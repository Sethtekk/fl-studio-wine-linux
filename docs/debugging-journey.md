# Debugging journal: FL Studio under Wine – from freeze to fix

This document describes the full debugging process that led to the fix for FL Studio's freezes. It explains **why** the patch is needed and **how** the problem was tracked down, so that anyone can understand the fix and adapt it to new Wine versions.

Some steps describe the state at the time; where the current scripts do things differently, this is noted.

---

## The original problem

**Symptom:** FL Studio 2025 runs stable under Wine overall - until you step through presets in a second plugin window (e.g. Serum 2). At some point the whole GUI freezes. The window stops responding and no click does anything. Interestingly, **audio keeps playing** - the running project still makes sound, only the interface is dead.

The only way out was always:
```bash
wineserver -k
```

---

## Phase 1: What actually freezes?

### Observation: audio runs, the GUI doesn't

The first important clue was that audio kept playing. That means the Wine process as a whole isn't stuck, only one particular thread. Under Wine, FL Studio and all its plugins share **a single process** - but audio runs in separate threads (`audio_client*`).

Conclusion: the **main thread** (GUI/message thread) is blocked while the audio threads keep running.

### Checking the Linux process state

```bash
# Find the PID of FL64.exe
pgrep -a wine | grep FL64

# Read the thread states
cat /proc/PID/task/*/stat | awk '{print $1, $3}'
```

Result: the main thread was in state **`R`** (running/spinning) - not `S` (sleeping) as you would expect in a deadlock. The thread was active and using CPU, but doing nothing useful. That is the typical sign of an **infinite loop or unbounded recursion**.

---

## Phase 2: What is the main thread doing?

### GDB backtrace

With `ptrace_scope=0`, a live backtrace of the frozen process was possible:

```bash
sudo sysctl kernel.yama.ptrace_scope=0

gdb -p PID -ex "thread apply all bt" -ex quit 2>/dev/null
```

The backtrace showed hundreds of identical stack frames:

```
#0  d2d_cdt_insert_segment (cdt=..., geometry=...) at geometry.c:2339
#1  d2d_cdt_insert_segment (cdt=..., geometry=...) at geometry.c:2339
#2  d2d_cdt_insert_segment (cdt=..., geometry=...) at geometry.c:2339
#3  d2d_cdt_insert_segment (cdt=..., geometry=...) at geometry.c:2339
... (repeated thousands of times)
```

**Found it.** The function `d2d_cdt_insert_segment` in `dlls/d2d1/geometry.c` kept calling itself recursively without end.

### What is CDT?

CDT = **constrained Delaunay triangulation** - a geometric algorithm that splits vector shapes into triangles so the GPU can render them. Direct2D (d2d1) uses it to draw the vector geometry that plugin GUIs such as Serum 2 or Ozone 11 produce.

---

## Phase 3: Finding the bug in the source

### Downloading and reading the Wine source

```bash
wget https://dl.winehq.org/wine/source/11.x/wine-11.9.tar.xz
tar xf wine-11.9.tar.xz
```

Looking for `d2d_cdt_insert_segment` in `dlls/d2d1/geometry.c`:

```bash
grep -n "d2d_cdt_insert_segment" dlls/d2d1/geometry.c
```

The function looked roughly like this (simplified):

```c
static BOOL d2d_cdt_insert_segment(struct d2d_cdt *cdt,
        struct d2d_geometry *geometry,
        const struct d2d_cdt_edge_ref *origin,
        struct d2d_cdt_edge_ref *edge,
        size_t end_vertex)
{
    // ... geometric calculations ...

    // Problem 1: a vertex lies on an edge
    if (collinear_condition) {
        // recursive call with a new origin
        return d2d_cdt_insert_segment(cdt, geometry, &new_origin, edge, end_vertex);
        //                             ^^^ UNBOUNDED RECURSION
    }

    // Problem 2: while walking on through the triangulation
    if (other_condition) {
        // another recursive call
        return d2d_cdt_insert_segment(cdt, geometry, &new_origin, edge, end_vertex);
        //                             ^^^ RECURSION AGAIN
    }
}
```

The only exit, the "Triangle not found" check, detects a full turn around the origin **of the current call**. Both recursive calls start with a new origin, so when the walk alternates between two origins (A → B → A → …), no call level ever completes a turn and the check never fires.

**Why does this happen with Serum 2?** Plugin GUIs such as Serum 2 (JUCE-based) or Ozone 11 render complex vector shapes. Certain shapes contain **collinear or duplicate vertices** - and that triggers the endless recursion.

---

## Phase 4: Developing the fix

### Approach: recursion → iteration

The fix was simple in concept: replace the recursion with a `goto`-based loop and add a safety counter that stops after a reasonable number of iterations.

```c
static BOOL d2d_cdt_insert_segment(struct d2d_cdt *cdt, ...)
{
    unsigned int iterations = 0;  // NEW: counter

restart:                           // NEW: jump label instead of recursion
    // NEW: safety guard - O(n) is the theoretical upper bound
    if (++iterations > 16 * cdt->edge_count + 0x10000)
    {
        WARN("Iteration limit exceeded, skipping segment.\n");
        return TRUE;  // skip the segment instead of crashing
    }

    // ... geometric calculations ...

    if (collinear_condition) {
        origin = &new_origin;
        goto restart;  // instead of: return d2d_cdt_insert_segment(...)
    }

    if (other_condition) {
        origin = &new_origin;
        goto restart;  // instead of: return d2d_cdt_insert_segment(...)
    }
}
```

The limit `16 * edge_count + 0x10000` is deliberately generous: well-formed geometry finishes in O(n) steps, far below it. Only pathological (degenerate) cases reach the limit - and those are now skipped instead of overflowing the stack.

Both recursive calls are tail calls, so turning them into a loop changes nothing about what the function does. With the loop in place, the stack overflow turned into an endless spin at 100 % CPU at the same spot - proof that the function really never terminates, rather than just recursing very deeply.

> The skip paths in this first version had a bug of their own (they didn't set `*edge`), which the fuzzer found later - see phase 8. The current patch is described in [patches/d2d1-geometry-fix.md](../patches/d2d1-geometry-fix.md).

### Building

```bash
cd wine-11.9
./configure --enable-win64
make -j$(nproc) dlls/d2d1/x86_64-windows/d2d1.dll
```

---

## Phase 5: Getting the DLL into the prefix

### Problem: Wine prefers its own DLLs

Wine has a built-in detection mechanism: DLLs compiled from the Wine source tree carry a **builtin marker** at file offset `0x40` (the 16 bytes `Wine builtin DLL`). If the marker is present, Wine loads the DLL as "builtin" - that is, it ignores the copy in the prefix and uses the system version from `/usr/lib/wine/`.

So simply copying the new DLL into `system32/` is not enough. Wine would ignore it.

### Fix: remove the marker

```python
# Set the 16 bytes at offset 0x40 to 0x00
with open("system32/d2d1.dll", "r+b") as f:
    f.seek(0x40)
    f.write(b"\x00" * 16)
```

Now Wine treats it as a non-builtin DLL and loads it as "native" from the prefix.

### Setting the registry entry

The DLL override has to be set as well:

```bash
wine reg add "HKCU\Software\Wine\DllOverrides" /v d2d1 /d "native,builtin" /f
```

`native,builtin` means: try the native (prefix) version first and fall back to the builtin (system) version if it isn't there.

`scripts/04-apply-d2d1-patch.sh` does both steps today; the DLL in `assets/` already has the marker zeroed.

### Checking

```bash
# MD5 of the patched DLL (the 11.9 build at the time)
md5sum system32/d2d1.dll
# → 83d47ffb76f5d7248474b6aaa546b46b

# Marker check: must be 16 × 0x00
python3 -c "
f = open('system32/d2d1.dll','rb')
f.seek(0x40)
print(f.read(16).hex())
# → 00000000000000000000000000000000  ✓
"
```

---

## Phase 6: Testing and confirmation

After the patch:

1. Started FL Studio with the launcher
2. Loaded Serum 2
3. Stepped through several presets
4. Loaded a second Serum 2 instance
5. Stepped through presets again

**Result:** no freeze. The worst case now is that after very many preset changes Serum's **own** GUI becomes sluggish - but FL Studio stays stable and keeps running. That is a separate issue (Serum 2's JUCE GUI repaints very heavily) and no longer critical.

---

## Side quest: debugging Splice

### Problem

Splice (an Electron app for plugin management and sample downloads) seemed not to open. The process started, but no window appeared.

### Diagnosis

```bash
WINEDEBUG=fixme-all wine Splice.exe 2>/dev/null
tail -f SpliceSettings/logs/log-ui.log
```

The log showed:

1. **`"UI not ready, enqueueing message..."`** - the Electron renderer never signalled "ready"
2. **`"The current refresh token is invalid"`** - the login token had expired
3. **`"Failed to delete the database: Database IO error"`** - the service worker cache was corrupted
4. **`upgradeState: "Conveyor Migration"`** - Splice tried to migrate itself to a new update system automatically, which hangs under Wine

### Fixes at the time

```bash
# 1. Disable the Conveyor migration
python3 -c "
import json
with open('appState.json') as f: s = json.load(f)
s['upgradeState'] = None
with open('appState.json','w') as f: json.dump(s, f)
"

# 2. Delete the corrupted cache
rm -rf "Service Worker/" "Code Cache/" "Session Storage/" "blob_storage/"

# 3. Remove the lock file (it prevents a restart)
rm -f lockfile
```

After these fixes, Splice opened, showed a login page, and plugins could be activated. The current Splice launcher disables the Conveyor migration permanently in `app.asar` and offers `--repair` for the cache steps.

### Key insight

`"UI not ready"` in the log does **not** mean "the window is empty". It only means the Electron main process is still waiting for an IPC signal from the renderer. The window still shows content (login page, loading screen). The real problem was that our test runs kept killing the window with timeouts before anyone could interact with it.

---

## Side quest 2: WineASIO – all inputs of the audio interface in FL Studio

### Problem

With a Behringer UMC404HD (4 inputs), FL Studio under Wine always showed only **2 inputs** - no matter which ASIO driver was selected.

### Cause: Wine's WASAPI is limited to stereo

FL Studio's own ASIO driver ("FL Studio ASIO") uses WASAPI internally. Wine's WASAPI implementation only ever returns the default stereo pair - a known limitation, not a configuration issue.

### Fix: WineASIO + PipeWire JACK

WineASIO (`pacman -S wineasio`) is a Wine driver that connects directly to JACK (here: PipeWire's JACK compatibility layer). That makes every hardware channel visible.

### How the debugging went

**Step 1 - registration failed (silently)**

```bash
WINEPREFIX=... wine regsvr32 /s wineasio64.dll
# exit code 3 → failure, but no error message
```

The DLL `wineasio64.dll` could not be registered as a COM object, for no obvious reason.

**Step 2 - tracing the DLL load with debug output**

```bash
WINEDEBUG=+loaddll,+module wine regsvr32 /s wineasio64.dll 2>&1 | grep wineasio
```

Output:
```
looking for "wineasio.dll" for file "wineasio64.dll"
cannot find builtin library for wineasio64.dll
Failed to load module "wineasio64.dll"; status=c0000135
```

**Root cause:** the Wine stub `wineasio64.dll` (a 2 KB PE placeholder) has the name `wineasio.dll` built into its PE export table. Wine reads that name and therefore looks for `wineasio.dll.so` as the builtin library - but the `wineasio` package doesn't ship that file, only `wineasio64.dll.so`. That is a **packaging bug** in the wineasio package.

**Step 3 - fix: create a symlink**

```bash
sudo ln -s /usr/lib/wine/x86_64-unix/wineasio64.dll.so \
           /usr/lib/wine/x86_64-unix/wineasio.dll.so
```

After that, `wineasio64.dll` loads correctly as builtin:
```
Loaded "C:\windows\system32\wineasio64.dll" at 0x...: builtin  ✓
```

**Step 4 - sample rate conflict**

Once it loaded, the next error appeared:
```
Warning: The needed sample rate (44100 Hz) couldn't be set or is not supported by the ASIO driver.
```

PipeWire was running at 48000 Hz (its default). WineASIO reports the JACK sample rate to FL Studio - mismatch.

The fix at the time was a PipeWire user config:

```bash
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cat > ~/.config/pipewire/pipewire.conf.d/10-sample-rate.conf << 'EOF'
context.properties = {
    default.clock.rate          = 44100
    default.clock.allowed-rates = [ 44100 48000 ]
    default.clock.quantum       = 1024
    default.clock.min-quantum   = 32
    default.clock.max-quantum   = 2048
}
EOF
systemctl --user restart pipewire pipewire-pulse wireplumber
```

> This config later turned out to cause wrong playback speed (a quantum of 1024 against a WineASIO buffer of 256). The launcher now pins rate and quantum at runtime instead - see [audio.md](audio.md).

**Step 5 - adjusting the launcher**

FL Studio has to be started through `pw-jack` so that the Wine process runs in PipeWire's JACK context:

```bash
export PIPEWIRE_RUNTIME_DIR=/run/user/$(id -u)
export JACK_NO_AUDIO_RESERVATION=1
exec pw-jack wine "FL64.exe"
```

### Result

After all fixes, WineASIO shows up in FL Studio under `Options → Audio Settings → ASIO`, and all 4 inputs of the UMC404HD are visible and usable.

**Important:** turn off the green **input monitoring** button in FL Studio's mixer to avoid feedback. This is not a Wine bug - it behaves the same on Windows.

---

## Phase 7: GL deadlock with NVIDIA (August 2026)

A second kind of freeze: the UI stops, audio keeps playing, and the main thread uses **no** CPU. Reading `/proc/<pid>/task/*/syscall` and interpreting the futex addresses as `pthread_mutex_t` revealed a lock cycle: a `SmoothAnimation` thread holds the NVIDIA driver's recursive GL mutex and waits for an X reply that only the main thread can pick up - and the main thread is waiting for the GL mutex. The underlying cause is that winex11 routes all GLX calls through a single Xlib connection shared by every thread ([bug 60113](https://bugs.winehq.org/show_bug.cgi?id=60113)).

The prefix still had `UseEGL=N` from an earlier test. With EGL (Wine's default), six weeks of daily use passed without a single deadlock; before that, a watchdog had to step in up to 27 times a day.

## Phase 8: Fuzzing the d2d1 triangulation (October 2026)

The patched DLL was still based on Wine 11.9. Rebuilding it on 11.19 brought in upstream's fix for a memory leak. To check its robustness, a fuzzer was written (`tools/d2d1_fuzz.cpp`) that generates random paths on a 6×6 grid - as many duplicates and collinear points as possible. Within seconds it found four more defects, including one that our own patch had introduced: when skipping a segment, the returned edge was left unchanged, and the caller carried on with an edge that had already been freed. That matches three swallowed access violations right after Direct2D calls in an older log.

Every hang was located with `gdb` (only `$pc`) and `addr2line` against the DLL with debug information; stack overflows by counting the return addresses on the stack. After the fixes, 240,000 fuzz cases ran without a failure and Wine's test suite was unchanged.

## Phase 9: Crashes and performance of individual plugins (October 2026)

**nih-plug:** a live crash showed `Could not create OpenGL context: CreationFailed` in baseview. A small WGL test program showed that NVIDIA's EGL only offers formats with 8-bit alpha together with a 32-bit visual, and that Wine blocks those for windows. A minimal CLAP host (`tools/clap_guitest.c`) reproduced the crash outside FL; with the alpha fallback in baseview, every affected editor opens and renders.

**Serum 2:** while Serum 2 was drawing, Wine wrote 11,000 `fixme:d2d` lines per second, and FL's main thread was at 64–82 % instead of 24 % - but a large project was loading at the same time, so Serum's share can't be determined cleanly from that. JUCE's source shows that `strokePath()` creates a new hollow geometry on every call. A benchmark measured 3.3 ms per `Close()` - almost all of it in the self-intersection pass, which is only needed for filled areas. Skipping hollow figures cut the time per path by a factor of 11. A targeted measurement inside FL later showed no measurable difference, though (see [verification.md](verification.md)).

## Summary

| Layer | Problem | Fix |
|---------|---------|-----|
| Wine d2d1 | Stack overflow in the CDT triangulation | Recursion → iteration with a guard (plus four more fixes, see phase 8) |
| Wine DLL loading | Builtin marker stops the prefix DLL from loading | Zero the 16 bytes at 0x40 |
| Wine winex11 + NVIDIA | GL deadlock between the main thread and an animation thread | `UseEGL=Y` |
| Splice | Conveyor migration hangs under Wine | Disabled in the launcher |
| Splice | Corrupted service worker cache | Delete the cache directories (`--repair`) |
| Splice | Expired login token | Log in again once |
| WineASIO | wineasio64.dll doesn't load (packaging bug) | Symlink wineasio.dll.so → wineasio64.dll.so |
| WineASIO | Sample rate mismatch (48000 vs. 44100 Hz) | Launcher pins rate and quantum at runtime |
| WineASIO | Only 2 inputs visible (WASAPI limit) | WineASIO + pw-jack instead of FL Studio ASIO |

### What we learned

- **State `R` (running) instead of `S` (sleeping)** in a frozen Wine process points to an infinite loop or recursion, not a deadlock
- **A GDB backtrace of the live process** is the most powerful first tool for Wine freezes
- **Wine doesn't load prefix DLLs on its own** while the builtin marker is present - it has to be removed
- **Electron apps under Wine** often have GPU initialisation problems, but that is usually not the real issue - caches and login state are more often to blame
- **Audio keeps playing during the freeze** = the main thread is stuck while the audio threads run → narrows the search enormously
- **Wine DLL stubs** can carry an internal PE name that differs from the file name - `WINEDEBUG=+module` reveals load errors that otherwise fail silently
- **WASAPI under Wine** is limited to stereo - use WineASIO + JACK/PipeWire for multi-channel interfaces

---

## Further reading

- [Wine bug tracker](https://bugs.winehq.org/) - for similar d2d1 problems
- [Wine Staging](https://gitlab.winehq.org/wine/wine-staging) - fixes sometimes land here first
- [DXVK on GitHub](https://github.com/doitsujin/dxvk) - DirectX → Vulkan translation layer
- [ProtonDB](https://www.protondb.com/) - community reports on Wine/Proton compatibility
