# Installation

Diese Anleitung richtet FL Studio in einem eigenen Wine-Prefix ein. Alle Pfade werden zentral in [`scripts/config.sh`](../scripts/config.sh) festgelegt.

## Voraussetzungen

- Arch-basierte Distribution mit aktiviertem `multilib`-Repository
- Aktueller Vulkan-Treiber (NVIDIA oder Mesa)
- FL-Studio-Installer für Windows (`flstudio_win64_*.exe`)
- Optional: Audio-Interface mit mehreren Kanälen, Splice-Installer

## 1. Wine Staging

```bash
bash scripts/01-install-wine.sh
wine --version    # wine-11.x (Staging)
```

## 2. Prefix

```bash
$EDITOR scripts/config.sh          # WINEPREFIX, z. B. /run/media/$USER/WinVM/.wine
bash scripts/02-setup-prefix.sh
```

Das Skript installiert die benötigten Laufzeiten (VC++, .NET, Core-Fonts) und setzt `HKCU\Software\Wine\X11 Driver\UseEGL = Y`. Unter GLX teilen sich alle Threads eine Xlib-Verbindung; FLs OpenGL-Oberfläche verklemmt sich dort mit dem GL-Lock des NVIDIA-Treibers ([Wine-Bug 60113](https://bugs.winehq.org/show_bug.cgi?id=60113)). EGL ist der Default von Wine und vermeidet diesen Pfad.

## 3. DXVK

```bash
bash scripts/03-install-dxvk.sh
```

Installiert DXVK 2.7.x ins Prefix und legt `config/dxvk.conf` ab.

## 4. d2d1-Patch

```bash
bash scripts/04-apply-d2d1-patch.sh
```

1. kopiert `assets/d2d1.dll.patched` nach `system32/`,
2. nullt die Wine-Builtin-Signatur bei Offset `0x40`, damit Wine die DLL als *native* lädt,
3. setzt `DllOverrides\d2d1 = native,builtin`.

Ohne diesen Schritt friert FL beim Öffnen von Direct2D-Plugins (Serum 2 u. a.) ein. Hintergrund: [`patches/d2d1-geometry-fix.md`](../patches/d2d1-geometry-fix.md).

## 5. wineserver-Pool-Fix

```bash
sudo bash scripts/install-fl-wine-automation.sh
```

Ersetzt `/usr/bin/wineserver` durch eine Variante mit größerem Shared-Session-Pool und installiert einen Pacman-Hook, der den Fix nach jedem `wine-staging`-Update automatisch wieder einspielt – bei Bedarf inklusive Neubau und Protokolltest mit automatischem Rollback. Hintergrund: [`patches/wineserver-pool-size.md`](../patches/wineserver-pool-size.md).

Ohne root-Hook (manuell, nach jedem Wine-Update):

```bash
bash scripts/08-apply-wineserver-poolfix.sh
```

## 6. Launcher

```bash
bash scripts/05-install-launchers.sh
```

Erzeugt `~/start-flstudio.sh`, `~/start-splice.sh` und die zugehörigen Desktop-Einträge. Der FL-Launcher

- setzt die Umgebungsvariablen (siehe unten),
- warnt, wenn der installierte `wineserver` nicht im Pool-Fix-Manifest steht,
- erkennt die installierte FL-Version automatisch,
- beendet beim Schließen den wineserver des Prefix.

| Variable | Wert | Zweck |
|---|---|---|
| `WINEFSYNC`, `WINEESYNC` | `1` | Synchronisation über Futexes/Events |
| `STAGING_AUDIO_PERIOD` | `10000` | Audio-Periode 10 ms |
| `__GL_THREADED_OPTIMIZATIONS` | `0` | Kein GL-Threading im NVIDIA-Treiber |
| `__EGL_VENDOR_LIBRARY_FILENAMES` | `…/10_nvidia.json` | NVIDIA-EGL statt Mesa-EGL (nur bei NVIDIA) |
| `WINEDEBUG` | `fixme-all` | Unterdrückt `fixme`-Ausgaben; d2d1 erzeugt sonst bis zu 11 000 Zeilen/s |
| `PIPEWIRE_RUNTIME_DIR` | `/run/user/$UID` | PipeWire-Socket für WineASIO |
| `JACK_NO_AUDIO_RESERVATION` | `1` | Keine D-Bus-Gerätereservierung |

## 7. FL Studio

```bash
WINEPREFIX=... wine ~/Downloads/flstudio_win64_*.exe
~/start-flstudio.sh
```

## 8. WineASIO (empfohlen)

```bash
sudo pacman -S wineasio
bash scripts/07-setup-wineasio.sh
```

In FL: *Options → Audio Settings → Device → WineASIO*. Einzelheiten und typische Fallstricke: [`audio.md`](audio.md).

## 9. Splice (optional)

```bash
WINEPREFIX=... wine ~/Downloads/SpliceSetup.exe
bash scripts/06-setup-splice.sh
```

## 10. nih-plug-Plugins (optional)

Wer Spectral Compressor, Diopser oder Crisp nutzt, baut sie mit dem baseview-Fix neu:

```bash
bash scripts/09-build-nih-plug.sh
```

Siehe [`plugins.md`](plugins.md#nih-plug).

## Skript-Übersicht

| Skript | Zweck |
|---|---|
| `01-install-wine.sh` | Wine Staging und Abhängigkeiten |
| `02-setup-prefix.sh` | Prefix anlegen, Laufzeiten, `UseEGL=Y` |
| `03-install-dxvk.sh` | DXVK installieren |
| `04-apply-d2d1-patch.sh` | Gepatchte `d2d1.dll` einspielen |
| `05-install-launchers.sh` | Launcher und Desktop-Einträge |
| `06-setup-splice.sh` | Splice-Konfiguration reparieren |
| `07-setup-wineasio.sh` | WineASIO und PipeWire-Rate |
| `08-apply-wineserver-poolfix.sh` | Pool-Fix manuell einspielen |
| `09-build-nih-plug.sh` | nih-plug-Plugins mit baseview-Fix bauen |
| `install-fl-wine-automation.sh` | Pool-Fix + Pacman-Hook (root) |
| `pacman-hook-apply.sh` | Vom Hook aufgerufen: Pool-Fix bauen/einspielen/testen |
| `restore-d2d1-patch.sh` | `d2d1.dll` nach Prefix-Updates wiederherstellen |
