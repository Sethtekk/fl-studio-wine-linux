# d2d1 Geometry Fix – Technische Dokumentation

**Datei:** `dlls/d2d1/geometry.c` · **Stand:** Wine 11.19 (2026-10-13) · Upstream-Bug: [60115](https://bugs.winehq.org/show_bug.cgi?id=60115)

Wines Direct2D trianguliert jede gefüllte Pfad-Geometrie (Constrained Delaunay Triangulation, „CDT"). Plugin-Oberflächen, die über Direct2D zeichnen (JUCE-8-Plugins wie Serum 2, Ozone 11 usw.), erzeugen dabei regelmäßig **degenerierte Geometrie**: doppelte oder kollineare Eckpunkte, deckungsgleiche Bézierkurven. Mehrere Stellen in `geometry.c` terminieren bei solchen Eingaben nicht.

**Symptom:** FL Studio friert ein, sobald ein Plugin-Fenster gezeichnet wird. Audio läuft weiter, die GUI ist tot (Main-Thread im Stack-Overflow → Zombie, oder er dreht in einer Endlosschleife). Einziger Ausweg: `wineserver -k`.

## Die fünf Fehlerstellen

Gefunden per Live-Debugging (2026-05) bzw. per Fuzzing mit zufälligen degenerierten Pfaden (2026-10, siehe unten).

| # | Funktion | Fehler (Stock-Wine) | Fix |
|---|---|---|---|
| 1 | `d2d_cdt_insert_segment` | Endlos-Rekursion zwischen zwei Ursprüngen A→B→A → Stack-Overflow | Tail-Rekursion → `goto restart` + Iterationslimit `16 * edge_count + 0x10000` |
| 2 | `d2d_cdt_insert_segment` (Skip-Pfade) | Der bisherige Patch übersprang ein Segment mit `return TRUE`, **ohne `*edge` zu setzen** → der Aufrufer setzte mit einem veralteten/freigegebenen Edge fort → Page-Fault | Skip-Pfade liefern über `d2d_cdt_find_vertex_edge()` einen gültigen Edge am Zielvertex (oder brechen sauber ab) |
| 3 | `d2d_cdt_cut_edges` | Unbegrenzte (nicht-Tail-)Rekursion bei zyklischer Topologie → Stack-Overflow | Iterativ: gekreuzte Kanten erst sammeln, dann in umgekehrter Reihenfolge löschen (identisch zur Rekursion), Abbruch nach `edge_count` Schritten |
| 4 | `d2d_cdt_fixup` | Face-Umlauf erreicht den Ursprung nie → Endlosschleife | Abbruch nach `2 * edge_count + 16` Schritten → `FALSE` (wie upstreams „Degenerate face") |
| 5 | `d2d_geometry_resolve_beziers` | Überlappende Kontrolldreiecke werden endlos halbiert (jeder Split erzeugt neue Überlappungen), Speicher wächst ohne Ende | Gesamt-Budget `16 * Bézier-Anzahl + 1024` Splits pro Geometrie; danach bleibt die Restüberlappung (minimal ungenaue Füllung statt Hänger) |

Ein abgebrochener Pfad führt immer in einen bestehenden Fehlerpfad: Entweder wird ein Segment übersprungen oder die Füllung dieser einen Geometrie verworfen (`E_FAIL`, Geometrie wird nicht gefüllt). Nie ein Absturz, nie ein Hänger.

## Speicherleck (upstream behoben, kam mit dem Rebuild)

Die alte DLL (Wine 11.9) gab `figure->vertex_types` nie frei. Gemessen: **+17,5 KB pro Pfad-Geometrie**, mit der neuen DLL 0. Bei Plugin-UIs, die pro Frame Geometrien neu bauen, war das ein Dauerleck, solange das Fenster offen war.

## Verifikation (2026-10-13)

**Fuzzing** — zufällige Pfade auf einem 6×6-Raster (viele Duplikate/Kollinearitäten), 1–4 Figuren, Linien + Béziers, beide Füllmodi:

| DLL | Ergebnis |
|---|---|
| Stock Wine 11.19 (builtin) | Stack-Overflows und Hänger in jedem 10.000er-Block |
| Alte Patch-DLL (Wine 11.9) | Hänger in jedem 10.000er-Block (erster bei Seed 940) |
| **Neue Patch-DLL (Wine 11.19)** | **240.000 Seeds: 0 Hänger, 0 Abstürze** |

**Wine-Testsuite** `dlls/d2d1/tests` (17.475 Einzeltests): Stock und gepatcht liefern **identische** Ergebnisse → keine Regression bei korrekter Geometrie.

## Die vorkompilierte DLL

`assets/d2d1.dll.patched` — Wine Staging 11.19, x86_64, Builtin-Signatur bei 0x40 genullt.
- **MD5:** `826992aa3b34cc9fd6f232719eb8c3c0`
- d2d1 ist eine reine PE-DLL; sie funktioniert auch unter anderen Wine-Versionen. Neu bauen lohnt sich, wenn upstream in `dlls/d2d1/` Fehler behebt (wie das Leck oben).

## Neu bauen für eine neue Wine-Version

```bash
# Quellbaum (bei Staging: patchinstall vorher), dann:
cd wine-X.Y && patch -p1 < .../patches/d2d1-geometry-fix.patch
mkdir ../build && cd ../build && ../wine-X.Y/configure --enable-win64
make -j$(nproc) dlls/d2d1/x86_64-windows/d2d1.dll
cp dlls/d2d1/x86_64-windows/d2d1.dll .../assets/d2d1.dll.patched
bash .../scripts/04-apply-d2d1-patch.sh   # kopiert + nullt 0x40 + DllOverride
```

Prüfen, ob upstream d2d1 geändert hat (dann lohnt der Rebuild):

```bash
diff -rq wine-ALT/dlls/d2d1/ wine-NEU/dlls/d2d1/ \
     --exclude="*.o" --exclude="*.dll" --exclude="Makefile" \
     --exclude="version.res" --exclude="x86_64-windows"
```

Zwischen 11.9 und 11.19 hat upstream u. a. `device.c`, `effect.c`, `command_list.c` geändert und `sprite_batch.c` ergänzt — die alte DLL war also zehn Versionen hinterher.

## Bekannte Restgrenze

`d2d_device_context_DrawGeometry` ignoriert Strichstile (Strichelung, runde Enden/Ecken) — Wine zeichnet sie als durchgezogene Linien mit Standard-Enden. Das ist eine fehlende Funktion in Wine, kein Absturzrisiko. Der Launcher setzt `WINEDEBUG=fixme-all`, weil Wine dazu sonst pro Linie eine fixme-Zeile schreibt (gemessen 11.000 Zeilen/s bei offenem Plugin-Fenster).
