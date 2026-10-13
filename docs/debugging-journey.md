# Debugging-Journal: FL Studio unter Wine – vom Freeze zur Lösung

Dieses Dokument beschreibt den vollständigen Debugging-Prozess, der zur Lösung des FL-Studio-Freeze-Problems geführt hat. Es soll nachvollziehbar machen, **warum** der Patch notwendig ist und **wie** wir das Problem identifiziert haben — damit jeder die Lösung verstehen und bei neuen Wine-Versionen adaptieren kann.

---

## Das Ausgangsproblem

**Symptom:** FL Studio 2025 läuft unter Wine grundsätzlich stabil — bis man in einem zweiten Plugin-Fenster (z.B. Serum 2) Presets durchschaltet. Ab einem bestimmten Punkt friert die gesamte GUI ein. Das Fenster reagiert nicht mehr, kein Klick funktioniert. Interessanterweise läuft der **Audio weiter** — das laufende Projekt produziert weiter Sound, nur die Oberfläche ist tot.

Einziger Ausweg war immer:
```bash
wineserver -k
```

---

## Phase 1: Was friert eigentlich ein?

### Beobachtung: Audio läuft, GUI nicht

Der erste wichtige Hinweis war, dass Audio weiterläuft. Das bedeutet: nicht der gesamte Wine-Prozess hängt, sondern nur ein bestimmter Thread. Bei FL Studio unter Wine teilen sich FL und alle Plugins **einen einzigen Prozess** — aber Audio läuft in separaten Threads (`audio_client*`).

Schlussfolgerung: Der **Main-Thread** (GUI/Message-Thread) ist blockiert, die Audio-Threads laufen weiter.

### Linux-Prozess-Status prüfen

```bash
# PID von FL64.exe finden
pgrep -a wine | grep FL64

# Thread-Zustände lesen
cat /proc/PID/task/*/stat | awk '{print $1, $3}'
```

Ergebnis: Der Main-Thread zeigte Status **`R`** (running/spinning) — kein `S` (sleep) wie man es bei einem Deadlock erwarten würde. Der Thread war aktiv, verbrauchte CPU, aber tat nichts Sinnvolles. Das ist das typische Zeichen für eine **Endlosschleife oder endlose Rekursion**.

---

## Phase 2: Was macht der Main-Thread?

### GDB-Backtrace

Mit `ptrace_scope=0` konnte ein Live-Backtrace des eingefrorenen Prozesses gemacht werden:

```bash
sudo sysctl kernel.yama.ptrace_scope=0

gdb -p PID -ex "thread apply all bt" -ex quit 2>/dev/null
```

Der Backtrace zeigte hunderte identische Stack-Frames:

```
#0  d2d_cdt_insert_segment (cdt=..., geometry=...) at geometry.c:2339
#1  d2d_cdt_insert_segment (cdt=..., geometry=...) at geometry.c:2339
#2  d2d_cdt_insert_segment (cdt=..., geometry=...) at geometry.c:2339
#3  d2d_cdt_insert_segment (cdt=..., geometry=...) at geometry.c:2339
... (tausende Male wiederholt)
```

**Bingo.** Die Funktion `d2d_cdt_insert_segment` in `dlls/d2d1/geometry.c` rief sich selbst endlos rekursiv auf.

### Was ist CDT?

CDT = **Constrained Delaunay Triangulation** — ein geometrischer Algorithmus, der Vektorflächen in Dreiecke zerlegt, damit sie von der GPU gerendert werden können. Direct2D (d2d1) nutzt das zum Zeichnen von Vektor-Geometrien, die Plugin-GUIs wie Serum 2 oder Ozone 11 verwenden.

---

## Phase 3: Den Bug im Quellcode finden

### Wine-Quellcode herunterladen und analysieren

```bash
wget https://dl.winehq.org/wine/source/11.x/wine-11.9.tar.xz
tar xf wine-11.9.tar.xz
```

In `dlls/d2d1/geometry.c` die Funktion `d2d_cdt_insert_segment` gesucht:

```bash
grep -n "d2d_cdt_insert_segment" dlls/d2d1/geometry.c
```

Die Funktion sah in etwa so aus (vereinfacht):

```c
static BOOL d2d_cdt_insert_segment(struct d2d_cdt *cdt,
        struct d2d_geometry *geometry,
        const struct d2d_cdt_edge_ref *origin,
        struct d2d_cdt_edge_ref *edge,
        size_t end_vertex)
{
    // ... geometrische Berechnungen ...

    // Problem 1: Wenn Eckpunkt auf einer Kante liegt
    if (kollinear_bedingung) {
        // rekursiver Aufruf mit neuem Startpunkt
        return d2d_cdt_insert_segment(cdt, geometry, &new_origin, edge, end_vertex);
        //                             ^^^ UNBESCHRÄNKTE REKURSION
    }

    // Problem 2: Beim Weiterlaufen der Triangulierung
    if (weitere_bedingung) {
        // noch ein rekursiver Aufruf
        return d2d_cdt_insert_segment(cdt, geometry, &new_origin, edge, end_vertex);
        //                             ^^^ NOCHMAL REKURSION
    }
}
```

**Warum tritt das bei Serum 2 auf?** Plugin-GUIs wie Serum 2 (JUCE-basiert) oder Ozone 11 rendern komplexe Vektorformen. Bei bestimmten Geometrien entstehen **kollineare oder duplizierte Eckpunkte** — das ist der Trigger für die Endlosrekursion.

---

## Phase 4: Den Fix entwickeln

### Ansatz: Rekursion → Iteration

Die Lösung war konzeptionell einfach: Die Rekursion durch eine `goto`-basierte Iteration ersetzen und einen Sicherheitszähler hinzufügen, der nach einer angemessenen Anzahl von Iterationen abbricht.

```c
static BOOL d2d_cdt_insert_segment(struct d2d_cdt *cdt, ...)
{
    unsigned int iterations = 0;  // NEU: Zähler

restart:                           // NEU: Sprungmarke statt Rekursion
    // NEU: Sicherheitsguard — O(n) ist die theoretische Obergrenze
    if (++iterations > 16 * cdt->edge_count + 0x10000)
    {
        WARN("Iteration limit exceeded, skipping segment.\n");
        return TRUE;  // Segment überspringen statt abstürzen
    }

    // ... geometrische Berechnungen ...

    if (kollinear_bedingung) {
        origin = &new_origin;
        goto restart;  // statt: return d2d_cdt_insert_segment(...)
    }

    if (weitere_bedingung) {
        origin = &new_origin;
        goto restart;  // statt: return d2d_cdt_insert_segment(...)
    }
}
```

Das Limit `16 * edge_count + 0x10000` ist großzügig gewählt: Legitime Geometrien beenden den Algorithmus in O(n) Schritten, also weit unter diesem Limit. Nur pathologische Fälle (degenerierten Geometrien) erreichen das Limit — und die werden dann einfach übersprungen statt einen Stack-Overflow auszulösen.

### Kompilieren

```bash
cd wine-11.9
./configure --enable-win64
make -j$(nproc) dlls/d2d1/x86_64-windows/d2d1.dll
```

---

## Phase 5: Die DLL ins Prefix bringen

### Problem: Wine lädt eigene DLLs bevorzugt

Wine hat ein internes Erkennungssystem: DLLs, die aus dem Wine-Quellbaum kompiliert wurden, tragen eine **Builtin-Signatur** bei Datei-Offset `0x40` (16 Bytes mit einem bestimmten Muster). Wenn diese Signatur vorhanden ist, lädt Wine die DLL als "builtin" — d.h. es ignoriert die Version im Prefix und nimmt die System-Version aus `/usr/lib/wine/`.

Das bedeutet: Einfach die neue DLL nach `system32/` kopieren reicht nicht. Wine würde sie trotzdem ignorieren.

### Lösung: Signatur löschen

```python
# Die 16 Bytes bei Offset 0x40 auf 0x00 setzen
with open("system32/d2d1.dll", "r+b") as f:
    f.seek(0x40)
    f.write(b"\x00" * 16)
```

Damit denkt Wine: "Das ist keine Builtin-DLL" → lädt sie als "native" aus dem Prefix.

### Registry-Eintrag setzen

Zusätzlich muss noch der DllOverride gesetzt werden:

```bash
wine reg add "HKCU\Software\Wine\DllOverrides" /v d2d1 /d "native,builtin" /f
```

`native,builtin` bedeutet: Erst die native (Prefix-)Version versuchen, falls nicht vorhanden auf builtin (System) zurückfallen.

### Verifizierung

```bash
# MD5 der gepatchten DLL
md5sum system32/d2d1.dll
# → 83d47ffb76f5d7248474b6aaa546b46b

# Signatur-Check: muss 16x 0x00 sein
python3 -c "
f = open('system32/d2d1.dll','rb')
f.seek(0x40)
print(f.read(16).hex())
# → 00000000000000000000000000000000  ✓
"
```

---

## Phase 6: Test und Bestätigung

Nach dem Patch:

1. FL Studio gestartet mit `start-flstudio.sh`
2. Serum 2 geladen
3. Mehrere Presets durchgeschalten
4. Zweite Serum 2 Instanz geladen
5. Wieder Presets geschalten

**Ergebnis:** Kein Freeze. Der schlimmste Fall ist jetzt, dass nach sehr vielen Preset-Wechseln Serum's **eigene** GUI langsam wird — aber FL Studio bleibt stabil und läuft weiter. Das ist normales Verhalten (Serum 2's JUCE-GUI hat ein eigenes WM_PAINT-Flut-Problem) und kein kritischer Fehler mehr.

Reaktion bei erstem Test: *„Krass!!! das funktioniert..."*

---

## Bonus: Splice-Debugging

### Problem

Splice (Electron-App für Plugin-Verwaltung und Sample-Downloads) öffnete scheinbar nicht. Der Prozess startete, aber die GUI erschien nicht.

### Diagnose

```bash
WINEDEBUG=fixme-all wine Splice.exe 2>/dev/null
tail -f SpliceSettings/logs/log-ui.log
```

Log-Analyse ergab:

1. **`"UI not ready, enqueueing message..."`** — Der Electron-Renderer signalisierte nie "ready"
2. **`"The current refresh token is invalid"`** — Auth-Token abgelaufen
3. **`"Failed to delete the database: Database IO error"`** — Service Worker Cache korrumpiert
4. **`upgradeState: "Conveyor Migration"`** — Splice versuchte sich automatisch auf ein neues System zu migrieren, was unter Wine hängt

### Lösungen

```bash
# 1. Conveyor-Migration deaktivieren
python3 -c "
import json
with open('appState.json') as f: s = json.load(f)
s['upgradeState'] = None
with open('appState.json','w') as f: json.dump(s, f)
"

# 2. Korrumpierten Cache löschen
rm -rf "Service Worker/" "Code Cache/" "Session Storage/" "blob_storage/"

# 3. Lockfile entfernen (verhindert Neustart)
rm -f lockfile
```

Nach diesen Fixes: Splice öffnet sich, zeigt eine Login-Seite, und Plugins können aktiviert werden.

### Wichtige Erkenntnis

`"UI not ready"` im Log bedeutet **nicht** "Fenster ist leer". Es bedeutet nur, dass der Electron-Hauptprozess noch auf ein IPC-Signal vom Renderer wartet. Das Fenster zeigt trotzdem Inhalt (Login-Seite, Loading-Screen). Der Fehler war, dass unsere Test-Sessions das Fenster mit Timeouts immer wieder abwürgten bevor der Nutzer reagieren konnte.

---

---

## Bonus 2: WineASIO – alle Eingänge des Audio-Interfaces in FL Studio

### Problem

FL Studio unter Wine zeigte beim Behringer UMC404HD (4 Eingänge) immer nur **2 Eingänge** — egal welcher ASIO-Treiber gewählt wurde.

### Ursache: Wine WASAPI ist auf Stereo begrenzt

Wine's eingebaute ASIO-Emulation ("FL Studio ASIO") nutzt intern WASAPI. Wine's WASAPI-Implementation gibt immer nur das Standard-Stereo-Paar zurück — das ist eine bekannte Einschränkung, keine Konfigurationssache.

### Lösung: WineASIO + PipeWire-JACK

WineASIO (`pacman -S wineasio`) ist ein Wine-Treiber, der direkt an JACK (hier: PipeWire's JACK-Kompatibilitätsschicht) andockt. Damit werden alle Hardware-Kanäle sichtbar.

### Debugging-Verlauf

**Schritt 1 — Registrierung fehlgeschlagen (lautlos)**

```bash
WINEPREFIX=... wine regsvr32 /s wineasio64.dll
# Exit: 3 → Fehler, aber keine Fehlermeldung
```

Die DLL `wineasio64.dll` konnte nicht als COM-Objekt registriert werden. Grund noch unklar.

**Schritt 2 — DLL-Ladevorgang mit Debug-Output verfolgt**

```bash
WINEDEBUG=+loaddll,+module wine regsvr32 /s wineasio64.dll 2>&1 | grep wineasio
```

Ausgabe:
```
looking for "wineasio.dll" for file "wineasio64.dll"
cannot find builtin library for wineasio64.dll
Failed to load module "wineasio64.dll"; status=c0000135
```

**Root Cause gefunden:** Der Wine-Stub `wineasio64.dll` (2 KB PE-Platzhalter) hat in seiner PE-Export-Tabelle intern den Namen `wineasio.dll` eingebaut. Wine liest diesen Namen und sucht deshalb nach `wineasio.dll.so` als Builtin-Library — diese existiert im `wineasio`-Paket aber nicht. Nur `wineasio64.dll.so` ist vorhanden. Das ist ein **Packaging-Bug** im wineasio-Paket.

**Schritt 3 — Fix: Symlink erstellen**

```bash
sudo ln -s /usr/lib/wine/x86_64-unix/wineasio64.dll.so \
           /usr/lib/wine/x86_64-unix/wineasio.dll.so
```

Danach lädt `wineasio64.dll` korrekt als Builtin:
```
Loaded "C:\windows\system32\wineasio64.dll" at 0x...: builtin  ✓
```

**Schritt 4 — Sample-Rate-Konflikt**

Nach erfolgreichem Laden kam die nächste Fehlermeldung:
```
Warning: The needed sample rate (44100 Hz) couldn't be set or is not supported by the ASIO driver.
```

PipeWire lief auf 48000 Hz (Standard). WineASIO meldet FL Studio die JACK-Sample-Rate — Mismatch.

Fix: PipeWire User-Config anlegen:

```bash
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cat > ~/.config/pipewire/pipewire.conf.d/10-sample-rate.conf << 'EOF'
context.properties = {
    default.clock.rate          = 44100
    default.clock.allowed-rates = [ 44100 48000 ]
    default.clock.quantum       = 1024
    default.clock.min-quantum   = 32
    default.clock.max-quantum   = 2048
}
EOF
systemctl --user restart pipewire pipewire-pulse wireplumber
```

**Schritt 5 — Launcher anpassen**

FL Studio muss über `pw-jack` gestartet werden, damit der Wine-Prozess im PipeWire-JACK-Kontext läuft:

```bash
export PIPEWIRE_RUNTIME_DIR=/run/user/$(id -u)
export JACK_NO_AUDIO_RESERVATION=1
exec pw-jack wine "FL64.exe"
```

### Ergebnis

Nach allen Fixes: WineASIO wird in FL Studio unter `Options → Audio Settings → ASIO` angezeigt, alle 4 Eingänge des UMC404HD sind sichtbar und verwendbar.

**Wichtig:** Das grüne **Input-Monitoring-Symbol** im FL Studio Mixer deaktivieren, um Rückkopplungen zu vermeiden. Das ist kein Wine-Bug — identisches Verhalten wie auf Windows.

---

## Phase 7: GL-Deadlock unter NVIDIA (August 2026)

Ein zweiter Freeze-Typ: UI steht, Audio läuft, der Main-Thread verbraucht **keine** CPU. Die Auswertung von `/proc/<pid>/task/*/syscall` und der Futex-Adressen als `pthread_mutex_t` zeigte einen Lock-Zyklus: Ein `SmoothAnimation`-Thread hält den rekursiven GL-Mutex des NVIDIA-Treibers und wartet auf eine X-Antwort, die nur der Main-Thread abholen kann – der wiederum auf den GL-Mutex wartet. Ursache ist, dass winex11 alle GLX-Aufrufe über eine einzige, von allen Threads geteilte Xlib-Verbindung führt ([Bug 60113](https://bugs.winehq.org/show_bug.cgi?id=60113)).

Im Prefix stand noch `UseEGL=N` aus einem früheren Test. Mit EGL (Wine-Default) trat in sechs Wochen Alltagsbetrieb kein Deadlock mehr auf; vorher griff ein Watchdog bis zu 27-mal pro Tag ein.

## Phase 8: Fuzzing der d2d1-Triangulierung (Oktober 2026)

Die gepatchte DLL stammte noch aus Wine 11.9. Ein Rebuild auf 11.19 brachte upstreams Fix für ein Speicherleck mit. Um die Robustheit zu prüfen, entstand ein Fuzzer (`tools/d2d1_fuzz.cpp`), der zufällige Pfade auf einem 6×6-Raster erzeugt – maximal viele Duplikate und Kollinearitäten. Er fand innerhalb von Sekunden vier weitere Fehlerstellen, darunter eine, die der eigene Patch eingeführt hatte: Beim Überspringen eines Segments blieb der Rückgabe-Edge unverändert, der Aufrufer arbeitete mit einem freigegebenen Edge weiter. Das passt zu drei verschluckten Access-Violations direkt nach Direct2D-Aufrufen in einem älteren Log.

Alle Hänger wurden mit `gdb` (nur `$pc`) und `addr2line` gegen die DLL mit Debug-Informationen lokalisiert, Stack-Overflows durch Zählen der Rücksprungadressen auf dem Stack. Nach den Fixes liefen 240 000 Fuzz-Fälle ohne Fehler, Wines Testsuite blieb unverändert.

## Phase 9: Abstürze und Leistung einzelner Plugins (Oktober 2026)

**nih-plug:** Ein Live-Absturz zeigte `Could not create OpenGL context: CreationFailed` in baseview. Ein nachgebautes WGL-Testprogramm belegte, dass NVIDIA-EGL Formate mit 8 Bit Alpha nur mit 32-Bit-Visual anbietet und Wine diese für Fenster sperrt. Ein minimaler CLAP-Host (`tools/clap_guitest.c`) reproduzierte den Absturz außerhalb von FL; mit dem Alpha-Fallback in baseview öffnen und rendern alle betroffenen Editoren.

**Serum 2:** Während Serum 2 zeichnete, schrieb Wine 11 000 `fixme:d2d`-Zeilen pro Sekunde, und FLs Main-Thread lag bei 64–82 % statt 24 % – allerdings lud zur selben Zeit ein großes Projekt, der Anteil von Serum ist daraus nicht sauber bestimmbar. Der JUCE-Quellcode zeigt, dass `strokePath()` pro Aufruf eine neue Hollow-Geometrie erzeugt. Ein Benchmark ergab 3,3 ms pro `Close()` – fast vollständig in der Selbstüberschneidungs-Prüfung, die nur für Füllflächen nötig ist. Das Überspringen von Hollow-Figuren senkte die Zeit pro Pfad um den Faktor 11.

## Zusammenfassung

| Schicht | Problem | Fix |
|---------|---------|-----|
| Wine d2d1 | Stack-Overflow in CDT-Triangulierung | Rekursion → Iteration mit Guard |
| Wine DLL-Loading | Builtin-Signatur verhindert Prefix-DLL | 16 Bytes bei 0x40 nullen |
| Splice | Conveyor-Migration hängt unter Wine | `upgradeState = null` in appState.json |
| Splice | Service Worker Cache korrumpiert | Cache-Verzeichnisse löschen |
| Splice | Auth-Token abgelaufen | Einmalig neu einloggen |
| WineASIO | wineasio64.dll lädt nicht (Packaging-Bug) | Symlink wineasio.dll.so → wineasio64.dll.so |
| WineASIO | Sample-Rate-Mismatch (48000 vs 44100 Hz) | PipeWire User-Config auf 44100 Hz |
| WineASIO | Nur 2 Inputs sichtbar (WASAPI-Limit) | WineASIO + pw-jack statt FL Studio ASIO |

### Was wir gelernt haben

- **`R`-Status (running) statt `S`-Status (sleep)** bei eingefrorenen Wine-Prozessen deutet auf Endlosschleife/Rekursion hin, nicht auf Deadlock
- **GDB-Backtrace auf laufenden Prozess** ist das mächtigste erste Tool bei Wine-Freezes
- **Wine lädt Prefix-DLLs nicht automatisch** wenn die Builtin-Signatur vorhanden ist — die muss aktiv entfernt werden
- **Electron-Apps unter Wine** haben oft GPU-Initialisierungsprobleme, aber das ist meistens nicht das eigentliche Problem — Caches und Auth-State sind häufiger schuld
- **Audio läuft weiter beim Freeze** = Main-Thread hängt, Audio-Threads laufen → präzisiert die Suche enorm
- **Wine DLL-Stubs** haben einen internen PE-Namen der von dem Dateinamen abweichen kann — `WINEDEBUG=+module` deckt solche Ladefehler auf, die sonst lautlos scheitern
- **WASAPI unter Wine** ist auf Stereo begrenzt — für Multi-Channel-Interfaces WineASIO + JACK/PipeWire verwenden

---

## Weiterführendes

- [Wine Bug Tracker](https://bugs.winehq.org/) — für ähnliche d2d1-Probleme
- [Wine Staging Patches](https://github.com/wine-staging/wine-staging) — manchmal sind solche Fixes hier früher verfügbar
- [DXVK GitHub](https://github.com/doitsujin/dxvk) — DirectX → Vulkan Übersetzungsschicht
- [ProtonDB](https://www.protondb.com/) — Community-Reports zu Wine/Proton-Kompatibilität
