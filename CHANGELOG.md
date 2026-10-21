# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/).

## [Unreleased]

### Für alle Distributionen (2026-10-16)
- `install.sh`: ein Befehl für die komplette Einrichtung (Distro- und GPU-Erkennung, Optionen `--fl-installer`, `--wineasio`, `--splice-installer`, `--pool-fix`, `--yes`); `uninstall.sh` (Prefix bleibt, `--purge` fragt nach).
- `01-install-wine.sh` unterstützt Arch-Familie, Debian/Ubuntu/Mint/Pop!_OS (WineHQ-Repo), Fedora und openSUSE; Paketschritt in frischen Containern getestet. Arch braucht kein `multilib` mehr (wine-staging ist WoW64).
- `scripts/doctor.sh`: Gesundheitscheck mit Lösungshinweisen, Ausgabe für Issues gedacht.
- Launcher neu: `~/.local/bin/flstudio-wine` / `splice-wine` rufen `scripts/run-*.sh` auf, `git pull` aktualisiert sie; Menüeinträge für jeden freedesktop-Desktop; fremde Dateien werden gesichert statt überschrieben.
- FL-Launcher: beim Beenden kein blindes `wineserver -k` mehr (ein zweiter FL-Start beendete die laufende Instanz und Splice); mit WineASIO wird das PipeWire-Quantum zur Laufzeit auf die Buffergröße fixiert.
- Splice-Launcher: Conveyor-Migration im `app.asar` abgeschaltet (Fehlermeldung nach 10 Min. Leerlauf, danach hängender Start), `--repair` statt eigenem Reparaturskript.
- WineASIO: Installation aus dem AUR oder Bau aus dem Quellcode für alle Distros; Standard-Buffer 512 (vorher 256 bei Quantum 1024 = falsche Wiedergabegeschwindigkeit).
- `02-setup-prefix.sh`: `wine64` existiert in WoW64-Builds nicht mehr → `wine wineboot`; `.NET 4.8` nur noch mit `--dotnet`.
- Englische README + `README.de.md`, Installationsanleitung pro Distribution, Fehlerbehebung auf Englisch, Issue-Vorlagen, CONTRIBUTING, ShellCheck-CI.

### Hinzugefügt
- `docs/verification.md`: Prüfbericht mit Belegstufen (FL-Alltag, FL-Sitzung, isoliert, offen), Sitzungsprotokoll vom 13.10.2026 und Ergebnis des Automatik-Selbsttests.
- Update-Automatik: Wartungs-Timer (`wineserver-poolfix-maintain`) baut den Pool-Fix für anstehende wine-staging-Versionen vorab und repariert, falls er fehlt. Der Pacman-Hook arbeitet nur noch offline – der Download im Hook scheiterte bei Transaktionen, die gleichzeitig Netzwerk-Komponenten aktualisierten.
- Launcher stellt eine ersetzte `d2d1.dll` selbst wieder her und warnt per Desktop-Benachrichtigung bei fehlendem Pool-Fix.
- `scripts/build-wineserver-poolfix.sh` (vorher nur lokal), mit Download-Wiederholungen.
- `scripts/09-build-nih-plug.sh` und `patches/baseview-alpha-fallback.patch`: Spectral Compressor, Diopser und Crisp stürzen unter EGL nicht mehr beim Öffnen des Editors ab.
- `tools/`: CLAP- und VST2-GUI-Testhost, d2d1-Fuzzer, Benchmark für Umriss-Pfade.
- Dokumentation unter `docs/` (Installation, Audio, Plugins, Updates, Fehlerbehebung), `LICENSE`.

### Geändert
- wineserver wird atomar ersetzt (vorher In-place-Kopie, scheitert bei laufendem wineserver mit „Text file busy“).
- Manifest erlaubt mehrere Hashes pro Version; `08-apply-wineserver-poolfix.sh` ist ein Wrapper um `pacman-hook-apply.sh --build`.
- Installer und Hook verwenden den Pfad des Repositorys statt eines festen Home-Verzeichnisses.
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
