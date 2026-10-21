# Updates

## Was ein `pacman -Syu` betrifft

| Komponente | Ort | Bei Wine-Update |
|---|---|---|
| `d2d1.dll` | `$WINEPREFIX/drive_c/windows/system32/` | bleibt erhalten; der Launcher stellt sie bei Abweichung wieder her |
| `wineserver` (Pool-Fix) | `/usr/bin/wineserver` | wird überschrieben → Hook bzw. Wartungsdienst spielt den Fix wieder ein |
| Registry (`UseEGL`, `DllOverrides`) | Prefix | bleibt erhalten |
| Launcher | `~/.local/bin/flstudio-wine` → `scripts/run-flstudio.sh` | bleibt erhalten; `git pull` aktualisiert ihn |

## Update-Automatik (nur Arch, optional)

Der Pool-Fix ist nur bei sehr großen Projekten nötig (Fehler 1411). Einmalig installieren:

```bash
sudo bash scripts/install-fl-wine-automation.sh          # --remove zum Entfernen
```

| Baustein | Wann | Was |
|---|---|---|
| Pacman-Hook `zz-wineserver-poolfix.hook` | nach jedem `wine-staging`-Update | spielt das vorhandene Pool-Fix-Binary **offline** ein; fehlt es, wird der Wartungsdienst angestoßen |
| `wineserver-poolfix-maintain.timer` | 5 min nach dem Booten, danach alle 3 h | **Reparatur**, falls `/usr/bin/wineserver` kein Pool-Fix ist; **Vorab-Build** für in den Repos anstehende wine-staging-Versionen (`checkupdates`) |
| Launcher | bei jedem FL-Start | stellt eine ersetzte `d2d1.dll` wieder her, warnt per Desktop-Benachrichtigung bei fehlendem Pool-Fix |

**Warum nicht im Hook bauen?** Während großer pacman-Transaktionen ist das Netz oft kurz weg – etwa wenn NetworkManager, systemd oder ein VPN-Daemon im selben Lauf aktualisiert werden. Der Download der Wine-Quellen schlug deshalb im Hook wiederholt fehl. Mit dem Vorab-Build liegt das Binary in der Regel schon bereit, bevor das Update installiert wird; andernfalls holt der Wartungsdienst den Build nach der Transaktion nach (wartet auf die pacman-Sperre und auf Netz, wiederholt bei Fehlschlag nach 20 Minuten, zusätzlich bei jedem Timer-Lauf).

Jedes Einspielen läuft gleich ab:

1. MD5 gegen `assets/poolfix-md5.txt` prüfen (mehrere Hashes pro Version zulässig, Builds sind nicht bitgleich reproduzierbar),
2. Stock-Binary versionsbezogen sichern (`/usr/bin/wineserver.stock-<VER>`),
3. atomar ersetzen (ein laufender wineserver behält seine Datei),
4. Protokolltest in einem Wegwerf-Prefix; schlägt er fehl, wird der Stock-wineserver wiederhergestellt.

Builds laufen als Besitzer des Repositorys mit niedriger CPU- und IO-Priorität. Status und Logs:

```bash
systemctl list-timers wineserver-poolfix-maintain.timer
journalctl -u wineserver-poolfix-maintain.service
ls ~/wine-build/poolfix-build-*.log
```

Manuell (ohne Automatik): `bash scripts/08-apply-wineserver-poolfix.sh`

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
