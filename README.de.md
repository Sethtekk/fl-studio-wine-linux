# FL Studio unter Linux

**FL Studio 2025/2026 unter Linux mit Wine – ohne einfrierende Plugin-Fenster, mit Mehrkanal-Audio und Splice.**

Ein Installer für Arch, Debian/Ubuntu, Fedora und openSUSE. Er richtet Wine, einen eigenen Prefix, DXVK und eine gepatchte Direct2D-Bibliothek ein und legt einen Eintrag „FL Studio“ im Anwendungsmenü an. Jeder Fix geht auf eine gefundene und getestete Ursache zurück – siehe [Debugging-Journal](docs/debugging-journey.md).

🇬🇧 [English version](README.md)

---

## Schnellstart

```bash
git clone https://github.com/Sethtekk/fl-studio-wine-linux.git
cd fl-studio-wine-linux
./install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe
```

Den FL-Studio-Installer für Windows gibt es bei [image-line.com](https://www.image-line.com/fl-studio-download/). Das Skript fragt einmal nach dem Passwort (für die Pakete) und stellt ein paar Fragen. Danach **FL Studio (Wine)** im Anwendungsmenü starten oder `flstudio-wine` eingeben.

| Option | Wirkung |
|---|---|
| `--wineasio` | WineASIO: alle Kanäle des Audio-Interfaces, niedrige Latenz |
| `--splice-installer DATEI` | Installiert zusätzlich die Splice-App |
| `--prefix ORDNER` | Ort der Windows-Umgebung (Standard `~/.wine-flstudio`) |
| `--skip-packages` | Wine ist schon installiert – Pakete nicht anfassen |
| `--yes` | Keine Rückfragen, Standardwerte verwenden |

Was auf welcher Distribution installiert wird: **[docs/installation.md](docs/installation.md)** (Englisch, Befehle sind selbsterklärend).

## Unterstützte Systeme

| Distribution | Wine aus | Status |
|---|---|---|
| **Arch**, CachyOS, EndeavourOS, Manjaro | `wine-staging` (offizielles Repo) | ✅ täglich im Einsatz |
| **Ubuntu** 24.04+, Linux Mint 22+, Pop!_OS, Zorin | WineHQ `winehq-staging` | ✅ Installer getestet |
| **Debian** 12, 13 | WineHQ `winehq-staging` | ✅ Installer getestet |
| **Fedora** 41+, Nobara | Fedora `wine` | ✅ Installer getestet |
| **openSUSE** Tumbleweed | openSUSE `wine` | ✅ Installer getestet |
| andere | Wine ≥ 10 selbst installieren, dann `./install.sh --skip-packages` | sollte funktionieren |

„Installer getestet“ = der Paketschritt installiert in einem frischen Container ein funktionierendes Wine; der Rest ist distributionsunabhängig. FL Studio selbst läuft im Alltag unter CachyOS mit KDE Plasma 6 (Wayland) und NVIDIA RTX 3080. **Berichte von anderen Systemen sind sehr willkommen** – Issue mit der Ausgabe von `bash scripts/doctor.sh` öffnen.

## Was behoben wird

| Problem mit normalem Wine | Ursache | Lösung |
|---|---|---|
| FL friert beim Öffnen von Plugin-Fenstern ein (Serum 2, Ozone …) | Endlos-Rekursionen/-Schleifen in Wines Direct2D-Triangulierung | gepatchte `d2d1.dll` ([Details](patches/d2d1-geometry-fix.md)) |
| Plugin-Fenster mit hoher CPU-Last / Speicher wächst | Umriss-Pfade unnötig trianguliert; Leck bis Wine 11.9 | dieselbe `d2d1.dll`, Basis Wine 11.19 |
| UI hängt, Audio läuft weiter (NVIDIA) | GL-Deadlock mit GLX | OpenGL über EGL (`UseEGL=Y`) |
| Nur 2 Eingänge, Wiedergabe zu langsam/schnell | WASAPI-Grenze; Buffer ≠ PipeWire-Quantum | WineASIO + Launcher fixiert das Quantum |
| Zweiter FL-Start beendet alles | Launcher rief beim Beenden `wineserver -k` | Launcher räumt nur auf, wenn nichts anderes den Prefix nutzt |
| Splice: Fehlermeldung nach 10 Min., nächster Start hängt | Splice will auf „Conveyor“ migrieren, scheitert unter Wine | Launcher schaltet die Migration ab |
| `System Error 1411` bei riesigen Projekten | Shared-Session-Pool des wineservers erschöpft | optionaler gepatchter `wineserver` (`--pool-fix`, Arch) |
| Spectral Compressor, Diopser, Crisp lassen FL abstürzen | nih-plug/baseview findet kein Pixelformat mit Alpha | neu gebaute Plugins ([Details](docs/plugins.md#nih-plug)) |

## Alltag

```bash
flstudio-wine                      # FL Studio starten (oder Menüeintrag)
flstudio-wine ~/Musik/song.flp     # Projekt öffnen
splice-wine                        # Splice starten (falls installiert)
bash scripts/doctor.sh             # prüfen, ob alles passt
git pull && ./install.sh --skip-packages --yes    # dieses Projekt aktualisieren
```

**Plugins installieren:** den Windows-Installer im selben Prefix ausführen:

```bash
WINEPREFIX=~/.wine-flstudio wine ~/Downloads/PluginSetup.exe
```

Danach in FL *Options → Manage plugins → Find plugins*.

## Hilfe

1. `bash scripts/doctor.sh` – zeigt, was fehlt und wie man es behebt.
2. [Fehlerbehebung](docs/troubleshooting.md) lesen.
3. Weiter Probleme? [Issue öffnen](https://github.com/Sethtekk/fl-studio-wine-linux/issues/new/choose) und die Doctor-Ausgabe einfügen.

Alles entfernen: `./uninstall.sh` (behält den Prefix mit FL und Plugins) oder `./uninstall.sh --purge`.

## Lizenz

Skripte, Werkzeuge und Dokumentation: [MIT](LICENSE). Die Wine-Patches und die daraus gebauten Binaries (`d2d1.dll`, `wineserver`) stehen unter Wines LGPL 2.1, der baseview-Patch unter der Lizenz von baseview (MIT/Apache-2.0). FL Studio und Splice sind proprietäre Software von Image-Line bzw. Splice und nicht Teil dieses Repositorys – du brauchst eine eigene Kopie/Lizenz. Dieses Projekt steht in keiner Verbindung zu Image-Line oder Splice.
