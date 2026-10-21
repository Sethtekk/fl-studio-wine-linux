# Installation per distribution

The short version for every distribution:

```bash
git clone https://github.com/Sethtekk/fl-studio-wine-linux.git
cd fl-studio-wine-linux
./install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe
```

This page explains what `install.sh` does on your distribution, and how to do it by hand if you prefer.

**Before you start**

- A 64-bit PC (x86_64). ARM computers (Raspberry Pi, Apple Silicon) can't run FL Studio for Windows.
- A working **Vulkan** driver: NVIDIA's proprietary driver, or Mesa (RADV for AMD, ANV for Intel). Check with `vulkaninfo --summary`.
- The **FL Studio installer for Windows** (`flstudio_win64_<version>.exe`) from [image-line.com](https://www.image-line.com/fl-studio-download/).
- About 5 GB of free disk space.
- Run everything as your **normal user**, not with `sudo` – the scripts ask for the password where needed.

Contents: [Arch](#arch-cachyos-endeavouros-manjaro) · [Ubuntu / Mint / Pop!_OS](#ubuntu-linux-mint-pop_os-zorin) · [Debian](#debian) · [Fedora](#fedora-nobara) · [openSUSE](#opensuse-tumbleweed) · [Other](#other-distributions) · [Steps in detail](#the-steps-in-detail)

---

## Arch, CachyOS, EndeavourOS, Manjaro

```bash
sudo pacman -S --needed git
git clone https://github.com/Sethtekk/fl-studio-wine-linux.git && cd fl-studio-wine-linux
./install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe
```

Packages installed: `wine-staging wine-mono wine-gecko winetricks cabextract python curl pipewire-jack icoutils imagemagick samba`.

- `wine-staging` is a WoW64 build in the `extra` repository – the `multilib` repository is **not** needed anymore.
- **WineASIO** (`--wineasio`) comes from the AUR. With `paru` or `yay` installed, the script uses them; otherwise it builds WineASIO from source.
- **Pool fix** (`--pool-fix`, only for `System Error 1411` with very large projects): replaces `/usr/bin/wineserver` and installs a pacman hook plus a timer that keep it in place across Wine updates. Details: [updating.md](updating.md).

## Ubuntu, Linux Mint, Pop!_OS, Zorin

Ubuntu 24.04 or newer (Mint 22+, Pop!_OS 24.04, Zorin 18).

```bash
sudo apt install git
git clone https://github.com/Sethtekk/fl-studio-wine-linux.git && cd fl-studio-wine-linux
./install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe
```

Ubuntu's own Wine is too old (24.04 ships Wine 9.0), so the installer adds the official **WineHQ** repository and installs `winehq-staging`:

```bash
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key
. /etc/os-release
sudo curl -fsSL -o /etc/apt/sources.list.d/winehq-$UBUNTU_CODENAME.sources \
  https://dl.winehq.org/wine-builds/ubuntu/dists/$UBUNTU_CODENAME/winehq-$UBUNTU_CODENAME.sources
sudo apt update
sudo apt install --install-recommends winehq-staging
sudo apt install winetricks cabextract unzip python3 curl pipewire-jack icoutils imagemagick
```

Mint, Pop!_OS and Zorin are detected through `UBUNTU_CODENAME` in `/etc/os-release`, so the matching Ubuntu repository is used.

**Audio:** Ubuntu uses PipeWire since 22.10. If `pw-jack` is missing, install `pipewire-jack`.

## Debian

Debian 12 (bookworm) and 13 (trixie).

```bash
sudo apt install git
git clone https://github.com/Sethtekk/fl-studio-wine-linux.git && cd fl-studio-wine-linux
./install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe
```

Same as Ubuntu, with the WineHQ repository for Debian (`https://dl.winehq.org/wine-builds/debian/dists/<codename>/…`).

- `winetricks` is in Debian's `contrib` section, which is often disabled. If apt can't find it, the installer downloads the official script to `~/.local/bin/winetricks`.
- Debian 12 still uses PulseAudio by default. For WineASIO you need PipeWire: `sudo apt install pipewire-audio pipewire-jack`, then log out and back in.
- The optional pool-fix binaries need glibc 2.38 and don't run on Debian 12.

## Fedora, Nobara

Fedora 41 or newer.

```bash
sudo dnf install git
git clone https://github.com/Sethtekk/fl-studio-wine-linux.git && cd fl-studio-wine-linux
./install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe
```

Packages installed: `wine winetricks cabextract python3 curl pipewire-jack-audio-connection-kit icoutils ImageMagick`.

Fedora's own `wine` package is recent (Fedora 42: Wine 10.x), so no extra repository is needed. It's not the Staging variant; everything works except the optional pool fix.

**NVIDIA users:** install the driver from RPM Fusion (`akmod-nvidia`) – DXVK needs Vulkan.

## openSUSE Tumbleweed

```bash
sudo zypper install git
git clone https://github.com/Sethtekk/fl-studio-wine-linux.git && cd fl-studio-wine-linux
./install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe
```

Packages installed: `wine winetricks cabextract python3 curl pipewire-libjack-0_3 icoutils ImageMagick`. Tumbleweed ships a current Wine (11.x).

Leap is not tested; its Wine may be too old. Use Tumbleweed, or install a newer Wine from the [Emulators:Wine](https://build.opensuse.org/project/show/Emulators:Wine) repository and run `./install.sh --skip-packages`.

## Other distributions

Install these yourself, then run `./install.sh --skip-packages`:

- Wine **10 or newer** (Staging recommended), `winetricks`, `cabextract`
- `python3`, `curl`
- for WineASIO: PipeWire with its JACK library (`pw-jack` command)
- optional for menu icons: `icoutils` (`wrestool`) and ImageMagick

**Flatpak / Bottles / Lutris:** this project uses a plain Wine prefix. You can point Bottles or Lutris at the prefix, but the launchers here won't manage it.

---

## The steps in detail

`install.sh` runs these scripts in order. Each one can be run on its own and is safe to run again.

| Step | Script | What it does |
|---|---|---|
| 1 | `scripts/01-install-wine.sh` | Wine and helper packages for your distribution (`--dry-run` shows the commands) |
| 2 | `scripts/02-setup-prefix.sh` | Creates the prefix, installs `win10 vcrun2022 corefonts` (+ `dotnet48` with `--dotnet`), sets `UseEGL=Y` |
| 3 | `scripts/03-install-dxvk.sh` | DXVK 2.7.1 (Direct3D → Vulkan) into the prefix |
| 4 | `scripts/04-apply-d2d1-patch.sh` | Patched `d2d1.dll` + DLL override `native,builtin` |
| – | (FL installer) | Runs `flstudio_win64_*.exe` in the prefix |
| 5 | `scripts/05-install-launchers.sh` | Commands `flstudio-wine`/`splice-wine` in `~/.local/bin`, menu entries, icons |
| 6 | `scripts/06-setup-splice.sh [SpliceSetup.exe]` | Optional: Splice |
| 7 | `scripts/07-setup-wineasio.sh` | Optional: WineASIO (installs or builds it, registers it in the prefix) |
| – | `scripts/install-fl-wine-automation.sh` | Optional, Arch: pool fix + update automation (root) |

Settings (prefix path) are stored in `~/.config/fl-studio-wine/config`. To use a different prefix for a single command: `WINEPREFIX=/path bash scripts/doctor.sh`.

### What the FL launcher does

`flstudio-wine` (= `scripts/run-flstudio.sh`) sets the environment and starts the newest FL Studio found in the prefix:

| Variable | Value | Why |
|---|---|---|
| `WINEFSYNC`, `WINEESYNC` | `1` | faster synchronisation |
| `STAGING_AUDIO_PERIOD` | `10000` | 10 ms audio period |
| `WINEDEBUG` | `fixme-all` | Wine's d2d1 otherwise logs up to 11,000 lines/s with JUCE plugins |
| `__GL_THREADED_OPTIMIZATIONS` | `0` | NVIDIA only: no GL threading |
| `__EGL_VENDOR_LIBRARY_FILENAMES` | `…/10_nvidia.json` | NVIDIA only: use NVIDIA's EGL, not Mesa's |
| `PIPEWIRE_RUNTIME_DIR`, `JACK_NO_AUDIO_RESERVATION` | | PipeWire/JACK for WineASIO |

It also

- puts the patched `d2d1.dll` back if a Wine update replaced it,
- with WineASIO: starts FL through `pw-jack` and pins PipeWire's quantum to the WineASIO buffer while FL runs (otherwise playback speed is wrong),
- sends MIDI "All Notes Off" on exit,
- stops leftover Wine processes on exit – but only when no other FL window or Splice still uses the prefix.

### Plugins

Install Windows plugins into the same prefix:

```bash
WINEPREFIX=~/.wine-flstudio wine ~/Downloads/PluginSetup.exe
```

VST3 plugins go to `C:\Program Files\Common Files\VST3` automatically. Then *Options → Manage plugins → Find plugins* in FL.
