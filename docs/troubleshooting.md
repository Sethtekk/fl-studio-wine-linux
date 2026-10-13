# Fehlerbehebung

Erste Anlaufstelle sind die Logs:

```bash
journalctl --user -t start-flstudio.sh --since today      # Start über Desktop-Eintrag
ls "$WINEPREFIX/drive_c/users/$USER/Documents/Image-Line/FL Studio/Support/Logs/Startup/"
```

## FL Studio friert ein

Zuerst einordnen, welcher Freeze vorliegt:

| Beobachtung | Wahrscheinliche Ursache | Maßnahme |
|---|---|---|
| UI steht, Audio läuft, Main-Thread ohne CPU-Last, NVIDIA | GL-Deadlock (GLX) | `UseEGL` prüfen, siehe unten |
| Freeze beim Öffnen eines Plugin-Fensters, Main-Thread 100 % oder Zombie | d2d1-Patch fehlt | `bash scripts/restore-d2d1-patch.sh` |
| Hänger beim Laden großer Projekte | Pool erschöpft | siehe [Fehler 1411](#fehler-1411-klasse-existiert-nicht) |

```bash
wine reg query 'HKCU\Software\Wine\X11 Driver' /v UseEGL      # muss Y sein (oder fehlen)
ps -L -o tid,stat,pcpu,wchan -p "$(pgrep -x FL64.exe)" | head  # Thread-Zustände
```

Notausgang: `WINEPREFIX=… wineserver -k`. Autosaves liegen unter `Documents/Image-Line/FL Studio/Projects/Backup`.

## FL Studio beendet sich beim Öffnen eines Plugins

Im Log steht `panicked at 'Could not create OpenGL context: CreationFailed'` und `c0000409`: ein nih-plug-Plugin mit baseview-Editor. Lösung in [`plugins.md`](plugins.md#nih-plug).

## Fehler 1411 „Klasse existiert nicht"

Tritt bei großen Projekten auf, wenn der Shared-Session-Pool des wineservers erschöpft ist. Prüfen, ob der Pool-Fix aktiv ist:

```bash
grep -qx "$(md5sum /usr/bin/wineserver | cut -d' ' -f1)" <(awk '{print $1}' assets/poolfix-md5.txt) \
  && echo "Pool-Fix aktiv" || sudo bash scripts/pacman-hook-apply.sh
```

`wine client error:0: version mismatch` bedeutet: Das Binary passt nicht zur installierten Wine-Version. `pacman-hook-apply.sh` wählt bzw. baut automatisch das passende.

## Hohe CPU-Last bei offenen Plugin-Fenstern

- `WINEDEBUG=fixme-all` gesetzt? Ohne schreibt d2d1 bis zu 11 000 Zeilen pro Sekunde.
- d2d1-Patch aktuell? Ältere Builds triangulieren auch reine Umriss-Pfade (siehe [`plugins.md`](plugins.md#direct2d-leistung-serum-2-und-andere-juce-8-plugins)).
- Rund 25 % eines Kerns im Leerlauf sind normal: FL zeichnet seine Oberfläche mit 60 Hz (VSync).

## Splice öffnet sich nicht

```bash
WINEPREFIX=… wineserver -k
rm -f "$WINEPREFIX/drive_c/users/$USER/AppData/Local/SpliceSettings/lockfile"
~/start-splice.sh
```

Hängt Splice weiterhin, Service-Worker- und Code-Cache löschen (`SpliceSettings/Service Worker`, `SpliceSettings/Code Cache`) oder `bash scripts/06-setup-splice.sh` ausführen.

## Audio

Falsche Wiedergabegeschwindigkeit, fehlende Eingänge oder Webcam-Mikrofone auf Eingang 1: siehe [`audio.md`](audio.md).

## „Getötet" am Ende der Sitzung

Die Zeile `start-flstudio.sh: … Getötet pw-jack wine …` erscheint bei jedem normalen Beenden. Wine setzt `TerminateProcess` auf den eigenen Prozess per SIGKILL um; das ist kein Absturz.

## `sudo: Zum Lesen des Passworts ist ein Terminal erforderlich`

`sudo` fragt das Passwort über ein Terminal ab. Aus Umgebungen ohne TTY (Skripte, IDE-Integrationen, das `!`-Präfix in Claude Code) schlägt es fehl. Den Befehl in einem normalen Terminal ausführen oder `pkexec` verwenden, das einen grafischen Passwortdialog öffnet:

```bash
pkexec bash scripts/install-fl-wine-automation.sh
```

## „Der Treiber konnte nicht gestartet werden“ beim Start

FL öffnet zwei Fehlerdialoge und das MIDI-Fenster, weil `PipeWire-System - input` und `PipeWire-RT-Event - input` als MIDI-Eingänge aktiviert sind (Status FAIL). Das sind Verwaltungsports von PipeWires MIDI-Brücke. In *Options → MIDI Settings* beide Einträge auswählen und *Enable* ausschalten.
