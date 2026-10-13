# Updates

## Was ein `pacman -Syu` betrifft

| Komponente | Ort | Bei Wine-Update |
|---|---|---|
| `d2d1.dll` | `$WINEPREFIX/drive_c/windows/system32/` | bleibt erhalten |
| `wineserver` (Pool-Fix) | `/usr/bin/wineserver` | wird überschrieben → Pacman-Hook spielt den Fix wieder ein |
| Registry (`UseEGL`, `DllOverrides`) | Prefix | bleibt erhalten |
| Launcher | `~/start-flstudio.sh` | bleibt erhalten |

## Pool-Fix-Automatik

`hooks/zz-wineserver-poolfix.hook` ruft nach jeder `wine-staging`-Transaktion `scripts/pacman-hook-apply.sh` auf:

1. Liegt für die neue Version kein Binary in `assets/`, wird es als Repository-Besitzer gebaut (`runuser`, Log unter `~/wine-build/hook-build-<VER>.log`).
2. Das Binary wird gegen das MD5-Manifest `assets/poolfix-md5.txt` geprüft und eingespielt.
3. Ein Protokolltest in einem Wegwerf-Prefix startet `wine cmd /c echo`. Schlägt er fehl, wird der Stock-`wineserver` wiederhergestellt.

Der Hook endet immer mit Exit-Code 0, ein Fehlschlag blockiert also kein Systemupdate. Der Launcher warnt beim Start, wenn der laufende `wineserver` nicht im Manifest steht.

## d2d1 neu bauen

Die `d2d1.dll` ist eine reine PE-DLL und läuft auch unter neueren Wine-Versionen weiter. Neu bauen lohnt sich, wenn upstream `dlls/d2d1/` ändert:

```bash
diff -rq wine-ALT/dlls/d2d1 wine-NEU/dlls/d2d1 \
     --exclude='*.o' --exclude='*.dll' --exclude=Makefile --exclude=x86_64-windows
```

Bauen:

```bash
cd wine-X.Y && patch -p1 < /pfad/zu/patches/d2d1-geometry-fix.patch
mkdir ../build && cd ../build && ../wine-X.Y/configure --enable-win64
make -j"$(nproc)" dlls/d2d1/x86_64-windows/d2d1.dll
cp dlls/d2d1/x86_64-windows/d2d1.dll /pfad/zu/assets/d2d1.dll.patched
bash /pfad/zu/scripts/04-apply-d2d1-patch.sh
```

Vor dem Einspielen empfohlen: Wines Testsuite (`make dlls/d2d1/tests/x86_64-windows/d2d1_test.exe`) gegen Stock und Patch vergleichen und `tools/d2d1_fuzz.exe` laufen lassen.

## Wiederherstellung

Nach `wineboot -u` oder einem Prefix-Update kann Wine die builtin-`d2d1.dll` zurückschreiben:

```bash
bash scripts/restore-d2d1-patch.sh
```
