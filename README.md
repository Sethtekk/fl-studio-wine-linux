# FL Studio unter Linux (Wine)

Stabiler Betrieb von **FL Studio 2025/2026** unter Linux mit Wine Staging, inklusive Plugin-GUIs, Multi-Channel-Audio über WineASIO und Splice.

Das Repository enthält Patches für Wine-Komponenten, Installationsskripte, Launcher und Testwerkzeuge. Jeder Fix ist auf eine nachgewiesene Ursache zurückgeführt, in [`docs/debugging-journey.md`](docs/debugging-journey.md) dokumentiert und reproduzierbar getestet.

![Wine](https://img.shields.io/badge/wine--staging-11.19-8f1b1b)
![FL Studio](https://img.shields.io/badge/FL%20Studio-2025%20%7C%202026-ff7b00)
![Platform](https://img.shields.io/badge/platform-Arch%20Linux-1793d1)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Behobene Probleme

| Symptom unter Stock-Wine | Ursache | Lösung |
|---|---|---|
| FL friert beim Öffnen von Plugin-Fenstern ein (Serum 2, Ozone …) | Endlos-Rekursionen und -Schleifen in Wines Direct2D-Triangulierung | Gepatchte `d2d1.dll` ([Details](patches/d2d1-geometry-fix.md)) |
| Umriss-Pfade (JUCE `strokePath`) unnötig teuer | Wine trianguliert auch reine Umriss-Pfade | Hollow-Figuren überspringen: Pfadaufbau ~11× schneller (Benchmark; bei Serum 2 in FL kein messbarer Effekt) |
| Zwei Treiber-Fehlerdialoge bei jedem FL-Start | PipeWire-Verwaltungsports als MIDI-Eingänge aktiv | In FL deaktivieren ([Details](docs/troubleshooting.md)) |
| Arbeitsspeicher wächst bei offenen Plugin-Fenstern | Leck in `d2d_figure_cleanup` (Wine ≤ 11.9) | `d2d1.dll` auf Basis von Wine 11.19 |
| `System Error 1411: Klasse existiert nicht` bei großen Projekten | Shared-Session-Pool des wineservers erschöpft | Gepatchter `wineserver` ([Details](patches/wineserver-pool-size.md)) |
| UI hängt, Audio läuft weiter (NVIDIA) | GL-Deadlock zwischen NVIDIA-GL-Lock und gemeinsamer Xlib-Verbindung | EGL statt GLX (`UseEGL=Y`) |
| Absturz beim Öffnen von Spectral Compressor, Diopser, Crisp | nih-plug/baseview findet unter EGL kein Pixelformat mit Alpha | Neu gebaute Plugins ([Details](docs/plugins.md#nih-plug)) |
| Nur 2 Eingänge, falsche Wiedergabegeschwindigkeit | WASAPI-Limit, Buffer ≠ PipeWire-Quantum | WineASIO + fixiertes Quantum ([Details](docs/audio.md)) |

## Kompatibilität

| Komponente | Getestet | Hinweis |
|---|---|---|
| Distribution | CachyOS (Arch) | Andere Arch-Derivate sollten funktionieren |
| Desktop | KDE Plasma 6, Wayland (XWayland) | |
| GPU | NVIDIA RTX 3080, Treiber 615 | d2d1-, Pool- und Audio-Fixes sind GPU-unabhängig. EGL-Einstellungen und der baseview-Fix betreffen NVIDIA; AMD/Intel (Mesa) ist ungetestet. |
| Wine | wine-staging 11.9 – 11.19 | Pool-Fix-Binaries für jede Version unter `assets/` |
| DXVK | 2.7.1 | |
| FL Studio | 2025, 2026 (26.1.1) | |

## Schnellstart

```bash
git clone https://github.com/Sethtekk/fl-studio-wine-linux.git
cd fl-studio-wine-linux
$EDITOR scripts/config.sh                 # WINEPREFIX festlegen

bash scripts/01-install-wine.sh           # Wine Staging + Abhängigkeiten
bash scripts/02-setup-prefix.sh           # Prefix, Laufzeiten, UseEGL=Y
bash scripts/03-install-dxvk.sh           # DXVK
bash scripts/04-apply-d2d1-patch.sh       # d2d1-Patch
sudo bash scripts/install-fl-wine-automation.sh   # Pool-Fix + Update-Automatik
bash scripts/05-install-launchers.sh      # Launcher und Desktop-Einträge
wine ~/Downloads/flstudio_win64_*.exe     # FL Studio installieren
bash scripts/07-setup-wineasio.sh         # optional: WineASIO
```

Ausführliche Anleitung: [`docs/installation.md`](docs/installation.md)

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [Installation](docs/installation.md) | Schritt-für-Schritt-Einrichtung |
| [Audio](docs/audio.md) | WineASIO, PipeWire-Quantum, Routing, Webcam-Mikrofone |
| [Plugins](docs/plugins.md) | Getestete Plugins, nih-plug-Neubau, Testwerkzeuge |
| [Updates](docs/updating.md) | Verhalten bei Wine-Updates, Pacman-Hook, Neubau der Patches |
| [Fehlerbehebung](docs/troubleshooting.md) | Freezes, Abstürze, Fehler 1411, Splice |
| [Verifikation](docs/verification.md) | Was wie getestet ist – und was noch offen ist |
| [Debugging-Journal](docs/debugging-journey.md) | Wie die Ursachen gefunden wurden |
| [d2d1-Patch](patches/d2d1-geometry-fix.md) · [Pool-Patch](patches/wineserver-pool-size.md) | Technische Details der Wine-Patches |

## Repository-Aufbau

```
assets/     vorgebaute d2d1.dll und wineserver-Binaries (+ MD5-Manifest)
config/     dxvk.conf
docs/       Dokumentation
hooks/      Pacman-Hook für den Pool-Fix
patches/    Quell-Patches für Wine und baseview
scripts/    Installations- und Wartungsskripte
tools/      Testwerkzeuge: CLAP-/VST2-GUI-Testhost, d2d1-Fuzzer, Benchmark
```

## Upstream-Meldungen

- [Wine-Bug 60113](https://bugs.winehq.org/show_bug.cgi?id=60113): winex11 GLX-Deadlock mit NVIDIA
- [Wine-Bug 60114](https://bugs.winehq.org/show_bug.cgi?id=60114): Shared-Session-Objekte (Fehler 1411)
- [Wine-Bug 60115](https://bugs.winehq.org/show_bug.cgi?id=60115): d2d1 CDT-Rekursion

## Lizenz

Skripte, Werkzeuge und Dokumentation stehen unter der [MIT-Lizenz](LICENSE). Die Wine-Patches und die daraus gebauten Binaries (`d2d1.dll`, `wineserver`) unterliegen der LGPL 2.1 von Wine, der baseview-Patch der Lizenz von baseview (MIT/Apache-2.0). FL Studio und Splice sind proprietäre Software und nicht Teil dieses Repositorys.
