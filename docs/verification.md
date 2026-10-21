# Verification

What each change is backed by, how it was measured and what is still open. Reference system: CachyOS, KDE Plasma 6 (Wayland/XWayland), NVIDIA RTX 3080 with driver 615, wine-staging 11.19, FL Studio 26.1.1.

Levels of evidence:

| Level | Meaning |
|---|---|
| **daily FL use** | shown in real FL use through logs or measurements |
| **FL session** | observed in an FL session (screenshot, log), without targeted load |
| **isolated** | tested reproducibly outside FL (test host, benchmark, fuzzer) |
| **open** | not shown yet |

## Overview

| Change | Level | Evidence |
|---|---|---|
| EGL instead of GLX (GL deadlock) | daily FL use | watchdog log: 88 deadlocks up to 2026-08-31 22:18, none since (more than 130 sessions) |
| d2d1 fixes (hangs/crashes) | isolated + FL session | fuzzer, Wine test suite; FL sessions with Serum 2 without a crash |
| d2d1 memory leak | isolated + FL session | test program; 15 min of FL with Serum 2 open: +0.37 MB/min |
| d2d1 performance (hollow figures) | measured in FL | benchmark 11× faster, **no measurable effect with Serum 2 in FL** (55 % vs. 56 %) |
| nih-plug crash (baseview) | FL session | Spectral Compressor, Diopser, Crisp opened and rendered in FL, alpha fallback logged 3×, no crash |
| Update automation | system | self-test as root passed |
| `WINEDEBUG=fixme-all` | FL session | 11,000 log lines/s measured; cost 1–4 µs per draw call |
| Disconnecting the Brio microphone | logic | filter tested against real and synthetic `pw-link` output; device was not connected during the test |

## GL deadlock

The `fl-unfreeze` watchdog checks every 5 s whether FL's main thread is stuck in a lock cycle between the NVIDIA GL mutex and an Xlib reply, and logs every intervention.

- Up to 2026-08-31: 88 detected deadlocks, up to 27 interventions on a single day.
- Switched to `UseEGL=Y` on 2026-08-31; the last deadlock was the same evening at 22:18.
- Since then more than 130 FL sessions without a deadlock.

## d2d1

**Fuzzer** (`tools/d2d1_fuzz.cpp`): random paths on a 6×6 grid, 1–4 figures, lines and Béziers, both fill modes.

| DLL | Result |
|---|---|
| Stock Wine 11.19 | stack overflows and hangs in every block of 10,000 cases |
| earlier patched DLL (Wine 11.9) | hangs in every block, first one at seed 940 |
| current patched DLL | 240,000 cases without a failure (another 120,000 after the performance fix) |

**Wine test suite** `dlls/d2d1/tests`: 17,475 tests, identical results for stock and patched (0 failures in a clean prefix).

**Memory:** creating and releasing 2,000 path geometries - Wine 11.9 DLL +35 MB, 11.19 DLL +0.2 MB. In FL (11.19 DLL) with a project and the Serum 2 interface open for 15 min: RSS 6886 → 6892 MB.

**Performance** (`tools/d2d1_strokebench.cpp`, 400 Bézier segments, outline only): `Close()` 3.32 ms → < 0.01 ms, total per path 3.58 → 0.31 ms.

**Observed in FL:** while Serum 2 was drawing (up to 11,000 Direct2D calls/s), FL's main thread was at 64–82 % instead of 24 % when idle (session from 19:42, DLL without the performance fix). However, a large project was loading during the same minutes (RSS 1.9 → 6.8 GB), so Serum's share cannot be separated cleanly. See the targeted measurement below.

## Plugins

**Crash observed in FL** (2026-10-13, 20:12:56, old builds):

```
panicked at 'Could not create OpenGL context: CreationFailed(())' … baseview/src/win/window.rs:703
thread caused non-unwinding panic. aborting.
err:seh:NtRaiseException Unhandled exception code c0000409
```

**In the CLAP test host** (`tools/clap_guitest.c`, EGL, NVIDIA):

| Plugin | Official build | Rebuilt with the baseview patch |
|---|---|---|
| Spectral Compressor | crash | editor 1360×530 rendered, exits cleanly |
| Diopser | crash | editor 600×490 rendered, exits cleanly |
| Crisp | crash | editor 400×390 rendered, exits cleanly |

The rebuild with `scripts/09-build-nih-plug.sh` was repeated from a fresh upstream checkout and confirmed again in the test host.

**In the VST2 test host** (`tools/vst2_guitest.c`, in the FL prefix): CamelCrusher and Serum 1 render without errors; longest idle round 4 ms, and a one-off 1.3 s on the first draw (DXVK initialisation).

**Seen in FL sessions** (screenshots): Serum 2, Fruity Parametric EQ 2, Youlean Loudness Meter 2, Voxengo SPAN and iZotope interfaces without rendering errors.

## FL sessions on 2026-10-13

| Start | End | d2d1 | Result |
|---|---|---|---|
| 19:42 | 20:12 | 11.19 DLL without the performance fix | crash when opening a nih-plug editor (old plugin build) |
| 20:14 | 20:33 | not loaded | normal exit, no `err:` messages apart from the known start-up ones |
| 20:41 | 20:53 | current DLL with the performance fix, Serum 2 loaded | normal exit, no crash, no deadlock |

Known, harmless messages on every start: `err:hid:udev_bus_init`, `err:service:device_notify_proc`, `err:ole:… {4ce576fa-…} not registered`. A "Killed pw-jack wine …" line at the end of a session is how Wine implements `TerminateProcess`, not a crash.

## Update automation

Cause of the earlier failures (from `/var/log/pacman.log`): the hook built during the transaction, and the download aborted after 27 and 86 ms. Both transactions updated network components at the same time (2026-09-25: `systemd` and a VPN daemon; 2026-10-13: `networkmanager`, `openvpn`). The wine-staging update itself went through each time; the pool fix had to be reinstalled by hand.

Self-test after installation (`install-fl-wine-automation.sh --selftest`, output translated from the German messages used at the time):

```
[poolfix-maintain] wineserver (11.19) is not the pool fix - repairing.
[poolfix] Pool fix for wine-staging 11.19 installed (md5 eb6884bc…).
[poolfix] Protocol test OK.
== RESULT: OK - pool fix restored automatically
```

Tested without root: every branch of the hook script (binary active, missing, tampered with, several hashes) and the pre-build with simulated `checkupdates` output, including the download (32 s).

Note: `sudo` needs a terminal to ask for the password. It fails from tools without a TTY (e.g. the `!` prefix in Claude Code); `pkexec`, which opens a graphical dialog, works there.

## Measurement in FL on 2026-10-13, 21:16–21:21

Test project with Serum 2 (init preset, 4 steps, 140 BPM), master muted, playing; windows operated through uinput events:

| Condition | Main thread | Total CPU | RSS |
|---|---|---|---|
| new d2d1, Serum window open | 55.5–56.3 % | ~75 % | flat |
| new d2d1, Serum window closed | 16.3–16.6 % | ~23 % | flat |
| old d2d1 (without the hollow fix), Serum window open | 54.4–55.5 % | ~75 % | flat |

Serum's interface costs about 40 percentage points of one core; the hollow fix doesn't change that. PC sampling (40 samples): libc 19, d2d1 7, d3d11 (DXVK) 5, ntdll 4 - no single hotspot in d2d1.

**Plugins in FL:** Spectral Compressor, Diopser and Crisp open and render without errors, all open at the same time, FL stable.

**Newly found issues:**
- **MIDI start-up error (fixed):** `PipeWire-System - input` and `PipeWire-RT-Event - input` were enabled as MIDI inputs and failed on every start (two "the driver could not be started" dialogs, the MIDI window opens). Both disabled in FL (`HKCU\Software\Image-Line\FL Studio 26\Devices\MIDI input\… Enabled=0`); the next start showed no dialog.
- **Rendering glitch (open):** when a plugin window with Vulkan/D3D content (Serum 2) is moved inside FL, the old image stays at the old position until the plugin redraws. During playback it corrects itself immediately; when idle only on interaction. Suspected cause: Wine doesn't trigger a redraw after the client surface is moved.

## Open

- Break down Serum's UI load (~40 percentage points) further (libc share, DXVK present).
- Fix the rendering glitch when moving Vulkan plugin windows in Wine.
- Wait for the first real wine-staging update with a pre-build.
- JUCE OpenGL plugins (Kickstart 2, Youlean, GrapHack, iZotope): pixel-format mechanism checked, interfaces not tested one by one in the test host.
