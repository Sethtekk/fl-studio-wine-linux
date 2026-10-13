# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/).

## [Unreleased]

### Hinzugefügt
- `scripts/09-build-nih-plug.sh` und `patches/baseview-alpha-fallback.patch`: Spectral Compressor, Diopser und Crisp stürzen unter EGL nicht mehr beim Öffnen des Editors ab.
- `tools/`: CLAP- und VST2-GUI-Testhost, d2d1-Fuzzer, Benchmark für Umriss-Pfade.
- Dokumentation unter `docs/` (Installation, Audio, Plugins, Updates, Fehlerbehebung), `LICENSE`.

### Geändert
- d2d1: Hollow-Figuren werden bei der Selbstüberschneidungs-Prüfung übersprungen. Umriss-Pfade (JUCE 8 `strokePath`) sind dadurch rund 11-mal schneller.
- README neu strukturiert, Detailinhalte nach `docs/` verschoben.
- `config/dxvk.conf`: wirkungslose Option `dxvk.enableAsync` entfernt.

## 2026-10-13

### Behoben
- d2d1 auf Basis von Wine 11.19 neu gebaut; enthält upstreams Fix für ein Speicherleck in `d2d_figure_cleanup` (+17,5 KB pro Pfad-Geometrie).
- Vier weitere Hänger/Abstürze in `geometry.c` (gefunden per Fuzzing): veralteter Edge in den Skip-Pfaden des bisherigen Patches, Rekursion in `d2d_cdt_cut_edges`, Endlosschleife in `d2d_cdt_fixup`, endloses Splitten in `d2d_geometry_resolve_beziers`.

### Geändert
- Launcher-Template: NVIDIA-EGL, `WINEDEBUG=fixme-all`, Pool-Fix-Prüfung über das MD5-Manifest, automatische Erkennung der FL-Version.
- `02-setup-prefix.sh` setzt `UseEGL=Y` (GL-Deadlock).
- Pool-Fix-Binaries für wine-staging 11.17–11.19; der Pacman-Hook baut fehlende Binaries selbst und rollt bei Protokollfehlern zurück.

## 2026-07 bis 2026-09

- wineserver-Pool-Fix für wine-staging 11.10–11.16, Pacman-Hook und Manifest.
- WineASIO-Einrichtung, Doku zu Quantum/Buffer-Mismatch.
- Splice-Launcher und Reparaturskript.

## 2026-05/06

- Erste Version: d2d1-CDT-Fix (Rekursion → Iteration), wineserver-Pool-Fix (Fehler 1411), Installationsskripte.
