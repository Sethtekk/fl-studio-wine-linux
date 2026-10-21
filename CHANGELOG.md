# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Findings from daily use (2026-10-21)
- Troubleshooting: FL freezing after opening Gopher (WebView2 panel) and how to recover without losing the project.
- Troubleshooting and plugin list: ZGameEditor Visualizer keeps FL's UI thread busy even with its window closed.
- FL launcher: sources `~/.config/fl-studio-wine/pre-start.sh` before starting FL, for setup-specific steps such as fixed routing that `git pull` must not overwrite.
- `tools/fl-perf-log.sh`: logs UI thread, process and wineserver CPU, context switches, memory and PipeWire xruns of a running FL.

### Support for all distributions (2026-10-16)
- `install.sh`: one command for the complete setup (distro and GPU detection, options `--fl-installer`, `--wineasio`, `--splice-installer`, `--pool-fix`, `--yes`); `uninstall.sh` (keeps the prefix, `--purge` asks first).
- `01-install-wine.sh` supports the Arch family, Debian/Ubuntu/Mint/Pop!_OS (WineHQ repository), Fedora and openSUSE; the package step was tested in fresh containers. Arch no longer needs `multilib` (wine-staging is WoW64).
- `scripts/doctor.sh`: health check with hints for fixing problems; its output is meant to be pasted into issues.
- New launchers: `~/.local/bin/flstudio-wine` / `splice-wine` call `scripts/run-*.sh`, so `git pull` updates them; menu entries for every freedesktop desktop; existing files that aren't ours are backed up instead of overwritten.
- FL launcher: no more blind `wineserver -k` on exit (starting FL a second time used to kill the running instance and Splice); with WineASIO, the PipeWire quantum is pinned to the buffer size at runtime.
- Splice launcher: the Conveyor migration in `app.asar` is disabled (it caused an error message after 10 minutes idle and a hanging start afterwards); `--repair` replaces the separate repair script.
- WineASIO: installed from the AUR or built from source on every distro; default buffer 512 (previously 256 with a quantum of 1024, which meant wrong playback speed).
- `02-setup-prefix.sh`: `wine64` no longer exists in WoW64 builds → `wine wineboot`; .NET 4.8 only with `--dotnet`.
- English README + `README.de.md`, installation guide per distribution, troubleshooting in English, issue templates, CONTRIBUTING, ShellCheck CI.

### Added
- `docs/verification.md`: verification report with levels of evidence (daily FL use, FL session, isolated, open), session log from 2026-10-13 and the result of the automation self-test.
- Update automation: a maintenance timer (`wineserver-poolfix-maintain`) pre-builds the pool fix for upcoming wine-staging versions and repairs it if it is missing. The pacman hook now works offline only - downloading inside the hook failed in transactions that also updated network components.
- The launcher restores a replaced `d2d1.dll` by itself and shows a desktop notification if the pool fix is missing.
- `scripts/build-wineserver-poolfix.sh` (previously local only), with download retries.
- `scripts/09-build-nih-plug.sh` and `patches/baseview-alpha-fallback.patch`: Spectral Compressor, Diopser and Crisp no longer crash under EGL when the editor opens.
- `tools/`: CLAP and VST2 GUI test hosts, d2d1 fuzzer, benchmark for stroked paths.
- Documentation in `docs/` (installation, audio, plugins, updates, troubleshooting), `LICENSE`.

### Changed
- wineserver is replaced atomically (previously copied in place, which fails with "Text file busy" while a wineserver is running).
- The manifest allows several hashes per version; `08-apply-wineserver-poolfix.sh` is a wrapper around `pacman-hook-apply.sh --build`.
- Installer and hook use the repository's path instead of a hard-coded home directory.
- d2d1: hollow figures are skipped in the self-intersection pass. In a micro-benchmark, stroked paths (JUCE 8 `strokePath`) are about 11 times faster; inside FL Studio the difference was not noticeable (see `docs/verification.md`).
- README restructured, details moved to `docs/`.
- `config/dxvk.conf`: removed the ineffective `dxvk.enableAsync` option.

## 2026-10-13

### Fixed
- d2d1 rebuilt from Wine 11.19; includes upstream's fix for a memory leak in `d2d_figure_cleanup` (+17.5 KB per path geometry).
- Four more hangs/crashes in `geometry.c` (found by fuzzing): stale edge in the skip paths of the previous patch, recursion in `d2d_cdt_cut_edges`, infinite loop in `d2d_cdt_fixup`, endless splitting in `d2d_geometry_resolve_beziers`.

### Changed
- Launcher template: NVIDIA EGL, `WINEDEBUG=fixme-all`, pool-fix check against the MD5 manifest, automatic detection of the FL version.
- `02-setup-prefix.sh` sets `UseEGL=Y` (GL deadlock).
- Pool-fix binaries for wine-staging 11.17–11.19; the pacman hook builds missing binaries itself and rolls back on protocol errors.

## 2026-07 to 2026-09

- wineserver pool fix for wine-staging 11.10–11.16, pacman hook and manifest.
- WineASIO setup, documentation on the quantum/buffer mismatch.
- Splice launcher and repair script.

## 2026-05/06

- First version: d2d1 CDT fix (recursion → iteration), wineserver pool fix (error 1411), install scripts.
