# Verifikation

Was jede Änderung belegt, wie es gemessen wurde und was noch offen ist. Referenzsystem: CachyOS, KDE Plasma 6 (Wayland/XWayland), NVIDIA RTX 3080 mit Treiber 615, wine-staging 11.19, FL Studio 26.1.1.

Belegstufen:

| Stufe | Bedeutung |
|---|---|
| **FL-Alltag** | im echten FL-Betrieb über Logs oder Messungen nachgewiesen |
| **FL-Sitzung** | in einer FL-Sitzung beobachtet (Screenshot, Log), ohne gezielte Last |
| **isoliert** | reproduzierbar außerhalb von FL getestet (Testhost, Benchmark, Fuzzer) |
| **offen** | noch nicht nachgewiesen |

## Übersicht

| Änderung | Belegstufe | Nachweis |
|---|---|---|
| EGL statt GLX (GL-Deadlock) | FL-Alltag | Watchdog-Log: 88 Deadlocks bis 31.08.2026 22:18, seitdem keiner (über 130 Sitzungen) |
| d2d1-Fixes (Hänger/Abstürze) | isoliert + FL-Sitzung | Fuzzer, Wine-Testsuite; FL-Sitzungen mit Serum 2 ohne Absturz |
| d2d1-Speicherleck | isoliert + FL-Sitzung | Testprogramm; 15 min FL mit offenem Serum 2: +0,37 MB/min |
| d2d1-Leistung (Hollow-Figuren) | FL gemessen | Benchmark 11× schneller, **in FL bei Serum 2 kein messbarer Effekt** (55 % vs. 56 %) |
| nih-plug-Absturz (baseview) | FL-Sitzung | Spectral Compressor, Diopser, Crisp in FL geöffnet und gerendert, 3× Alpha-Fallback im Log, kein Absturz |
| Update-Automatik | System | Selbsttest als root bestanden |
| `WINEDEBUG=fixme-all` | FL-Sitzung | 11 000 Logzeilen/s gemessen; Kosten 1–4 µs pro Zeichenaufruf |
| Brio-Mikrofon trennen | Logik | Filter gegen echte und synthetische `pw-link`-Ausgabe getestet; Gerät beim Test nicht angeschlossen |

## GL-Deadlock

Der Watchdog `fl-unfreeze` prüft alle 5 s, ob FLs Main-Thread in einem Lock-Zyklus aus NVIDIA-GL-Mutex und Xlib-Antwort hängt, und protokolliert jeden Eingriff.

- Bis zum 31.08.2026: 88 erkannte Deadlocks, an einzelnen Tagen bis zu 27 Eingriffe.
- Umstellung auf `UseEGL=Y` am 31.08.2026; letzter Deadlock am selben Abend um 22:18.
- Seitdem über 130 FL-Sitzungen ohne Deadlock.

## d2d1

**Fuzzer** (`tools/d2d1_fuzz.cpp`): zufällige Pfade auf einem 6×6-Raster, 1–4 Figuren, Linien und Béziers, beide Füllmodi.

| DLL | Ergebnis |
|---|---|
| Stock Wine 11.19 | Stack-Overflows und Hänger in jedem Block à 10 000 Fällen |
| frühere Patch-DLL (Wine 11.9) | Hänger in jedem Block, erster bei Seed 940 |
| aktuelle Patch-DLL | 240 000 Fälle ohne Fehler (nach dem Leistungsfix erneut 120 000) |

**Wine-Testsuite** `dlls/d2d1/tests`: 17 475 Tests, Stock und Patch mit identischem Ergebnis (0 Fehler im sauberen Prefix).

**Speicher:** 2000 Pfad-Geometrien erzeugen und freigeben – Wine-11.9-DLL +35 MB, 11.19-DLL +0,2 MB. In FL (11.19-DLL) mit Projekt und offener Serum-2-Oberfläche über 15 min: RSS 6886 → 6892 MB.

**Leistung** (`tools/d2d1_strokebench.cpp`, 400 Bézier-Segmente, nur Umriss): `Close()` 3,32 ms → < 0,01 ms, gesamt pro Pfad 3,58 → 0,31 ms.

**In FL beobachtet:** Während Serum 2 zeichnete (bis zu 11 000 Direct2D-Aufrufe/s), lag FLs Main-Thread bei 64–82 % statt 24 % im Leerlauf (Sitzung ab 19:42, DLL ohne Leistungsfix). In dieselben Minuten fiel allerdings das Laden eines großen Projekts (RSS 1,9 → 6,8 GB); der Anteil von Serum ist daraus nicht sauber abzugrenzen. Eine gezielte Vergleichsmessung mit dem Leistungsfix steht aus.

## Plugins

**Absturz in FL beobachtet** (13.10.2026, 20:12:56, alte Builds):

```
panicked at 'Could not create OpenGL context: CreationFailed(())' … baseview/src/win/window.rs:703
thread caused non-unwinding panic. aborting.
err:seh:NtRaiseException Unhandled exception code c0000409
```

**Im CLAP-Testhost** (`tools/clap_guitest.c`, EGL, NVIDIA):

| Plugin | offizieller Build | Neubau mit baseview-Patch |
|---|---|---|
| Spectral Compressor | Absturz | Editor 1360×530 gerendert, sauber beendet |
| Diopser | Absturz | Editor 600×490 gerendert, sauber beendet |
| Crisp | Absturz | Editor 400×390 gerendert, sauber beendet |

Der Neubau per `scripts/09-build-nih-plug.sh` wurde frisch aus Upstream wiederholt und im Testhost erneut bestätigt.

**Im VST2-Testhost** (`tools/vst2_guitest.c`, im FL-Prefix): CamelCrusher und Serum 1 rendern fehlerfrei; längste Idle-Runde 4 ms bzw. einmalig 1,3 s beim ersten Zeichnen (DXVK-Initialisierung).

**In FL-Sitzungen gesehen** (Screenshots): Serum 2, Fruity Parametric EQ 2, Youlean Loudness Meter 2, Voxengo SPAN und iZotope-Oberflächen ohne Darstellungsfehler.

## FL-Sitzungen am 13.10.2026

| Start | Ende | d2d1 | Ergebnis |
|---|---|---|---|
| 19:42 | 20:12 | 11.19-DLL ohne Leistungsfix | Absturz beim Öffnen eines nih-plug-Editors (alter Plugin-Build) |
| 20:14 | 20:33 | nicht geladen | regulär beendet, keine `err:`-Meldungen außer den bekannten Start-Meldungen |
| 20:41 | 20:53 | aktuelle DLL mit Leistungsfix, Serum 2 geladen | regulär beendet, kein Absturz, kein Deadlock |

Bekannte, harmlose Meldungen bei jedem Start: `err:hid:udev_bus_init`, `err:service:device_notify_proc`, `err:ole:… {4ce576fa-…} not registered`. Die Zeile `… Getötet pw-jack wine …` am Sitzungsende ist Wines Umsetzung von `TerminateProcess` und kein Absturz.

## Update-Automatik

Ursache der früheren Ausfälle (aus `/var/log/pacman.log`): Der Hook baute während der Transaktion, und der Download brach nach 27 bzw. 86 ms ab. Beide Transaktionen aktualisierten gleichzeitig Netzwerk-Komponenten (25.09.: `systemd`, `mullvad-vpn-daemon`; 13.10.: `networkmanager`, `openvpn`). Das wine-staging-Update selbst lief jeweils durch; der Pool-Fix musste von Hand nachgeholt werden.

Selbsttest nach der Installation (`install-fl-wine-automation.sh --selftest`):

```
[poolfix-maintain] wineserver (11.19) ist kein Pool-Fix - repariere.
[poolfix] Pool-Fix für wine-staging 11.19 eingespielt (md5 eb6884bc…).
[poolfix] Protokolltest OK.
== ERGEBNIS: OK - Pool-Fix automatisch wiederhergestellt
```

Ohne root getestet: alle Zweige des Hook-Appliers (Binary aktiv, fehlt, manipuliert, mehrere Hashes) sowie der Vorab-Build mit simulierter `checkupdates`-Ausgabe einschließlich Download (32 s).

Hinweis: `sudo` braucht ein Terminal für die Passworteingabe. Aus Werkzeugen ohne TTY (z. B. dem `!`-Präfix in Claude Code) scheitert es; dort hilft `pkexec`, das einen grafischen Dialog öffnet.

## Messung in FL am 13.10.2026, 21:16–21:21

Testprojekt mit Serum 2 (Init-Preset, 4 Steps, 140 BPM), Master stumm, Wiedergabe, Fenster per uinput-Eingaben bedient:

| Bedingung | Main-Thread | Gesamt-CPU | RSS |
|---|---|---|---|
| neue d2d1, Serum-Fenster offen | 55,5–56,3 % | ~75 % | flach |
| neue d2d1, Serum-Fenster zu | 16,3–16,6 % | ~23 % | flach |
| alte d2d1 (ohne Hollow-Fix), Serum-Fenster offen | 54,4–55,5 % | ~75 % | flach |

Serums Oberfläche kostet rund 40 Prozentpunkte eines Kerns; der Hollow-Fix ändert daran nichts. PC-Stichprobe (40 Samples): libc 19, d2d1 7, d3d11 (DXVK) 5, ntdll 4 – kein einzelner Hotspot in d2d1.

**Plugins in FL:** Spectral Compressor, Diopser und Crisp öffnen und rendern fehlerfrei, gleichzeitig offen, FL stabil.

**Neu gefundene Auffälligkeiten:**
- **MIDI-Startfehler (behoben):** `PipeWire-System - input` und `PipeWire-RT-Event - input` waren als MIDI-Eingänge aktiv und scheiterten bei jedem Start (zwei Dialoge „Der Treiber konnte nicht gestartet werden“, MIDI-Fenster öffnet sich). Beide in FL deaktiviert (`HKCU\Software\Image-Line\FL Studio 26\Devices\MIDI input\… Enabled=0`); nächster Start ohne Dialog.
- **Darstellungsfehler (offen):** Wird ein Plugin-Fenster mit Vulkan/D3D-Inhalt (Serum 2) innerhalb von FL verschoben, bleibt das alte Bild an der alten Stelle, bis das Plugin neu zeichnet. Bei Wiedergabe korrigiert es sich sofort, im Leerlauf erst bei Interaktion. Vermutete Ursache: Wine stößt nach dem Verschieben der client surface kein Neuzeichnen an.

## Offen

- Serums UI-Last (~40 Prozentpunkte) weiter aufschlüsseln (libc-Anteil, DXVK-Present).
- Darstellungsfehler beim Verschieben von Vulkan-Plugin-Fenstern in Wine beheben.
- Erstes echtes wine-staging-Update mit Vorab-Build abwarten.
- JUCE-OpenGL-Plugins (Kickstart 2, Youlean, GrapHack, iZotope): Pixelformat-Mechanismus geprüft, Oberflächen nicht einzeln im Testhost.
