# Troubleshooting

**Start here:** `bash scripts/doctor.sh` checks Wine, the prefix, the patches, the launchers and audio, and tells you which script fixes what is missing.

To see FL's output, start it from a terminal: `flstudio-wine`. FL's own logs are in
`~/.wine-flstudio/drive_c/users/$USER/Documents/Image-Line/FL Studio/Support/Logs/`.

Contents: [Freezes](#fl-studio-freezes) · [Crash when opening a plugin](#fl-studio-closes-when-opening-a-plugin) · [Error 1411](#error-1411-class-does-not-exist) · [High CPU](#high-cpu-load-with-plugin-windows-open) · [Audio](#audio) · [Splice](#splice) · [Driver error dialogs](#the-driver-could-not-be-started-on-every-start) · [Misc](#misc)

## FL Studio freezes

First find out which kind of freeze it is:

| What you see | Likely cause | What to do |
|---|---|---|
| Freeze when opening a plugin window | patched d2d1 missing (a Wine update can reset it) | `bash scripts/04-apply-d2d1-patch.sh` – the launcher normally does this itself |
| UI stuck, audio keeps playing, NVIDIA | GL deadlock (GLX) | check `UseEGL` (below) |
| Hangs while loading a big project | wineserver pool exhausted | see [error 1411](#error-1411-class-does-not-exist) |

```bash
WINEPREFIX=~/.wine-flstudio wine reg query 'HKCU\Software\Wine\X11 Driver' /v UseEGL   # must be Y (or absent)
```

Emergency exit: `WINEPREFIX=~/.wine-flstudio wineserver -k`. Autosaves are in `Documents/Image-Line/FL Studio/Projects/Backup` inside the prefix.

## FL Studio closes when opening a plugin

The log shows `panicked at 'Could not create OpenGL context: CreationFailed'` and `c0000409`: a plugin built with nih-plug (Spectral Compressor, Diopser, Crisp …). Fix: rebuild them with `bash scripts/09-build-nih-plug.sh`, details in [plugins.md](plugins.md#nih-plug).

## Error 1411 "Class does not exist"

Only with very large projects: the wineserver's shared-session pool runs out. On Arch: `./install.sh --skip-packages --pool-fix` installs a patched wineserver and keeps it in place across Wine updates. Background: [patches/wineserver-pool-size.md](../patches/wineserver-pool-size.md).

`wine client error:0: version mismatch` means the wineserver binary doesn't match the installed Wine version; `sudo bash scripts/pacman-hook-apply.sh --build` picks or builds the right one.

## High CPU load with plugin windows open

- Is `WINEDEBUG=fixme-all` set (the launcher does that)? Without it, d2d1 writes up to 11,000 log lines per second.
- Is the d2d1 patch current? `bash scripts/doctor.sh`.
- About 25 % of one core when idle is normal: FL redraws its UI at 60 Hz.

## Audio

| Problem | Fix |
|---|---|
| Only 2 inputs / high latency | set up WineASIO: `bash scripts/07-setup-wineasio.sh`, then in FL *Options → Audio Settings → Device → WineASIO* |
| Playback too slow or too fast, pitch is correct | PipeWire quantum ≠ WineASIO buffer. Start FL with `flstudio-wine` (it pins the quantum). Check with `pw-top`: QUANT must equal the buffer size shown by the doctor |
| No sound at all with WineASIO | in FL's audio settings pick WineASIO; check `pw-jack` exists (`pipewire-jack` package) |
| Webcam microphone mixed into input 1 | see [audio.md](audio.md#webcam-microphone-on-fl-input-1) |
| Crackling | raise the buffer: `ASIO_BUFFER=1024 bash scripts/07-setup-wineasio.sh` |

## Splice

The launcher (`splice-wine`) repairs Splice before every start:

- **Error dialog after ~10 minutes, then Splice won't start any more:** Splice tries to migrate to its new "Conveyor" client when idle. That installer fails under Wine and leaves a flag that makes the next start hang without a window. The launcher disables the migration in Splice's `app.asar` (original kept as `app.asar.orig`) and clears the flag in `appState.json`.
- **Splice doesn't open / runs invisibly:** use the menu entry **Splice – repair (Wine)** or `splice-wine --repair`. It kills the hanging processes and starts Splice again.
- **Still hanging:** `bash scripts/06-setup-splice.sh` clears the caches that can get corrupted under Wine (you may have to log in again).
- **Splice disappears when FL is closed:** fixed – older launchers ran `wineserver -k` on exit, which killed every program in the prefix.

## "The driver could not be started" on every start

FL shows two error dialogs and opens the MIDI settings because `PipeWire-System - input` and `PipeWire-RT-Event - input` are enabled as MIDI inputs. They are management ports of PipeWire's MIDI bridge. In *Options → MIDI Settings* select both and switch *Enable* off.

## Misc

- **"Killed" at the end of the session** (`… Killed pw-jack wine …`) appears on every normal exit: Wine implements `TerminateProcess` on itself with SIGKILL. Not a crash.
- **`sudo: a terminal is required to read the password`:** run the command in a normal terminal, or use `pkexec bash scripts/…` for a graphical password prompt.
- **Menu entry missing:** `bash scripts/05-install-launchers.sh`, then log out and in (some desktops cache the menu).
