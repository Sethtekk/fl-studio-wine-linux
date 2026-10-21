# FL Studio on Linux

**Run FL Studio 2025/2026 on Linux with Wine – with plugin windows that don't freeze, multi-channel audio and Splice.**

One installer for Arch, Debian/Ubuntu, Fedora and openSUSE. It sets up Wine, a dedicated prefix, DXVK and a patched Direct2D library, and creates an "FL Studio" entry in your application menu. Every fix goes back to a root cause that was found and tested – see the [debugging journal](docs/debugging-journey.md).

[![ShellCheck](https://github.com/Sethtekk/fl-studio-wine-linux/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Sethtekk/fl-studio-wine-linux/actions/workflows/shellcheck.yml)
![Wine](https://img.shields.io/badge/wine-10%20%7C%2011-8f1b1b)
![FL Studio](https://img.shields.io/badge/FL%20Studio-2025%20%7C%202026-ff7b00)
![License](https://img.shields.io/badge/license-MIT-green)

🇩🇪 [Deutsche Version](README.de.md)

---

## Quick start

```bash
git clone https://github.com/Sethtekk/fl-studio-wine-linux.git
cd fl-studio-wine-linux
./install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe
```

Get the FL Studio installer for Windows from [image-line.com](https://www.image-line.com/fl-studio-download/). The script asks for your password once (to install packages) and a few questions. Afterwards start **FL Studio (Wine)** from your application menu, or run `flstudio-wine`.

| Option | What it does |
|---|---|
| `--wineasio` | WineASIO: all channels of your audio interface, low latency |
| `--splice-installer FILE` | Also installs the Splice desktop app |
| `--prefix DIR` | Where the Windows environment goes (default `~/.wine-flstudio`) |
| `--skip-packages` | Wine is already installed – don't touch packages |
| `--yes` | No questions, use the defaults |

Distribution-specific notes (what gets installed, from where): **[docs/installation.md](docs/installation.md)**

## Supported systems

| Distribution | Wine from | Status |
|---|---|---|
| **Arch**, CachyOS, EndeavourOS, Manjaro | `wine-staging` (official repo) | ✅ daily use by the author |
| **Ubuntu** 24.04+, Linux Mint 22+, Pop!_OS, Zorin | WineHQ `winehq-staging` | ✅ installer tested |
| **Debian** 12, 13 | WineHQ `winehq-staging` | ✅ installer tested |
| **Fedora** 41+, Nobara | Fedora `wine` | ✅ installer tested |
| **openSUSE** Tumbleweed | openSUSE `wine` | ✅ installer tested |
| others | install Wine ≥ 10 yourself, then `./install.sh --skip-packages` | should work |

"Installer tested" = the package step installs a working Wine in a clean container; the rest of the setup is distribution-independent. FL Studio itself has been run day-to-day on CachyOS with KDE Plasma 6 (Wayland) and an NVIDIA RTX 3080. **Reports from other setups are very welcome** – open an issue with the output of `bash scripts/doctor.sh`.

**GPU:** NVIDIA (proprietary driver), AMD and Intel all work through Vulkan (DXVK). The EGL settings below matter mostly for NVIDIA.

## What gets fixed

| Problem with plain Wine | Cause | Fix |
|---|---|---|
| FL freezes when opening plugin windows (Serum 2, Ozone, …) | endless recursion/loops in Wine's Direct2D triangulation | patched `d2d1.dll` ([details](patches/d2d1-geometry-fix.md)) |
| Plugin windows use lots of CPU / memory grows | outline paths triangulated needlessly; leak in Wine ≤ 11.9 | same `d2d1.dll`, based on Wine 11.19 |
| UI freezes while audio keeps playing (NVIDIA) | GL deadlock with GLX | OpenGL via EGL (`UseEGL=Y`) |
| Only 2 inputs, playback too slow/fast | WASAPI limit; buffer ≠ PipeWire quantum | WineASIO + launcher pins the quantum |
| Opening a second FL window kills everything | launcher ran `wineserver -k` on exit | launcher only cleans up when nothing else uses the prefix |
| Splice: error dialog after 10 min, next start hangs | Splice tries to migrate to "Conveyor", which fails under Wine | launcher disables the migration ([details](docs/troubleshooting.md#splice)) |
| `System Error 1411` with huge projects | wineserver's shared-session pool runs out | optional patched `wineserver` (`--pool-fix`, Arch) ([details](patches/wineserver-pool-size.md)) |
| Spectral Compressor, Diopser, Crisp crash FL | nih-plug/baseview finds no pixel format with alpha | rebuilt plugins ([details](docs/plugins.md#nih-plug)) |

## Daily use

```bash
flstudio-wine                      # start FL Studio (or use the menu entry)
flstudio-wine ~/Music/song.flp     # open a project
splice-wine                        # start Splice (if installed)
bash scripts/doctor.sh             # check that everything is in place
git pull && ./install.sh --skip-packages --yes    # update this project
```

**Installing plugins:** run the plugin's Windows installer in the same prefix:

```bash
WINEPREFIX=~/.wine-flstudio wine ~/Downloads/SomePluginSetup.exe
```

Then rescan in FL (*Options → Manage plugins → Find plugins*). Which plugins are tested: [docs/plugins.md](docs/plugins.md).

## Help

1. Run `bash scripts/doctor.sh` – it lists what's missing and how to fix it.
2. Check [troubleshooting](docs/troubleshooting.md).
3. Still stuck? [Open an issue](https://github.com/Sethtekk/fl-studio-wine-linux/issues/new/choose) and paste the doctor output.

Remove everything again: `./uninstall.sh` (keeps your prefix with FL and plugins) or `./uninstall.sh --purge`.

## Documentation

| Document | Content |
|---|---|
| [Installation per distribution](docs/installation.md) | What the installer does on your system, manual steps |
| [Troubleshooting](docs/troubleshooting.md) | Freezes, crashes, error 1411, Splice, audio |
| [Audio](docs/audio.md) 🇩🇪 | WineASIO, PipeWire quantum, routing |
| [Plugins](docs/plugins.md) 🇩🇪 | Tested plugins, nih-plug rebuild, test tools |
| [Updates](docs/updating.md) 🇩🇪 | Wine updates, pool-fix automation |
| [Verification](docs/verification.md) 🇩🇪 | What was tested how – and what's still open |
| [Debugging journal](docs/debugging-journey.md) 🇩🇪 | How the causes were found |
| [d2d1 patch](patches/d2d1-geometry-fix.md) · [pool patch](patches/wineserver-pool-size.md) 🇩🇪 | Technical details of the Wine patches |

🇩🇪 = currently German only. Translations welcome.

## Upstream reports

- [Wine bug 60113](https://bugs.winehq.org/show_bug.cgi?id=60113): winex11 GLX deadlock with NVIDIA
- [Wine bug 60114](https://bugs.winehq.org/show_bug.cgi?id=60114): shared-session objects (error 1411)
- [Wine bug 60115](https://bugs.winehq.org/show_bug.cgi?id=60115): d2d1 CDT recursion

## Contributing

Bug reports, test reports from other distributions/GPUs and pull requests are welcome – see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Scripts, tools and documentation: [MIT](LICENSE). The Wine patches and the binaries built from them (`d2d1.dll`, `wineserver`) are under Wine's LGPL 2.1; the baseview patch under baseview's license (MIT/Apache-2.0). FL Studio and Splice are proprietary software by Image-Line and Splice and are not part of this repository – you need your own copy/license. This project is not affiliated with Image-Line or Splice.
