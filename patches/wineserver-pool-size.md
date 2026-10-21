# wineserver Shared-Session-Pool Fix – Technische Dokumentation

## Problem

**Datei:** `server/mapping.c`
**Funktion:** `create_session_mapping()` (Zeile ~1428)
**Wine-Version:** 11.9 (und neuere)

Wine legt für jede Session einen gemeinsam genutzten Speicherbereich („shared session") an, in dem **Fenster, Fensterklassen und Message-Queues** als Objekte abgelegt werden. Die *initiale* Größe ist auf **512 Objekte** dimensioniert.

FL Studio registriert beim Laden eines Projekts für jeden Mixer-Track, jedes Stock-Plugin und jede Plugin-GUI eigene Fensterklassen. Bei großen Projekten (viele Tracks + Sidechain-Routing + viele Plugins) ist der Pool mit 512 Objekten erschöpft, bevor alles geladen ist.

**Symptom:** FL Studio bricht mit **`System Error. Code: 1411. Klasse existiert nicht`** ab (oder hängt sich beim Projektwechsel auf). Stock-Plugins lassen sich nicht mehr öffnen.

## Ursache (per Log bewiesen)

Mit `WINEDEBUG=+seh,err+win` zeigt das Log im Crash-Moment:

```
err:class:NtUserRegisterClassExWOW Failed to get shared session object for window class
[ERROR] thread 'unnamed' panicked at 'panic in a function that cannot unwind'
thread caused non-unwinding panic. aborting.   (c0000409 = STATUS_STACK_BUFFER_OVERRUN)
```

`NtUserRegisterClassExWOW` bekommt keinen freien Slot mehr aus dem Shared-Session-Pool → Klassenregistrierung schlägt fehl → FL meldet 1411. Der serverseitige Pool wächst zwar (`grow_session_mapping`), aber zuverlässig stabil ist es, den **initialen** Pool von vornherein groß genug zu wählen.

## Fix

```c
// server/mapping.c, create_session_mapping():
-    size_t size = max( sizeof(*shared_session) + sizeof(object_shm_t) * 512, 0x10000 );
+    size_t size = max( sizeof(*shared_session) + sizeof(object_shm_t) * 32768, 0x10000 );
```

Pool von **512 → 32768** Objekten. Damit reicht der initial gemappte Bereich auch für sehr große FL-Projekte. Der Patch liegt als `patches/wineserver-pool-size.patch` bei.

## Anwenden / Neu bauen

### Variante A – Vanilla Wine (z. B. exakt 11.9)

```bash
# Wine-Quellcode zur passenden Version holen
wget https://dl.winehq.org/wine/source/11.x/wine-11.9.tar.xz
tar xf wine-11.9.tar.xz && cd wine-11.9

# Patch anwenden
patch -p1 < /pfad/zu/patches/wineserver-pool-size.patch

# Nur den wineserver bauen
./configure --enable-archs=i386,x86_64
make -j$(nproc) server/wineserver

# Ergebnis liegt in server/wineserver
```

### Variante B – wine-staging (PFLICHT für 11.10, Protokoll 943)

Da auf CachyOS **wine-staging** installiert ist, muss der wineserver ab 11.10 aus den
Staging-Quellen gebaut werden (sonst Protokoll-Mismatch). Erst Staging-Patches anwenden,
**dann** den Pool-Patch:

```bash
# Vanilla-Tarball + passende wine-staging-Quellen (gleiche Version!)
wget https://dl.winehq.org/wine/source/11.x/wine-11.10.tar.xz
tar xf wine-11.10.tar.xz
git clone --branch v11.10 --depth 1 https://gitlab.winehq.org/wine/wine-staging.git wine-staging-src

# 1) Staging-Patches in den Wine-Baum spielen (bringt Protokoll auf 943)
python3 wine-staging-src/staging/patchinstall.py --all --source-dir wine-11.10

# 2) DANACH den Pool-Patch anwenden
cd wine-11.10
patch -p1 < /pfad/zu/patches/wineserver-pool-size.patch

# 3) Out-of-tree nur den wineserver bauen
cd .. && mkdir build-11.10 && cd build-11.10
../wine-11.10/configure --prefix=/usr --enable-win64 --with-vulkan
make -j$(nproc) server/wineserver
strip server/wineserver        # ~5,1M -> ~767k

# Verifizieren, dass Protokoll 943 drinsteht:
strings server/wineserver | grep -i "protocol" | head
```

## Die vorkompilierten Binaries

> ⚠️ **Pro Wine-Version ein eigenes Binary!** Der wineserver muss exakt zur installierten
> Wine-Version passen, sonst: `wine client error:0: version mismatch`. Ein altes Binary
> drüberkopieren funktioniert NICHT.

| Datei | Wine-Version | MD5 | Server-Protokoll |
|---|---|---|---|
| `assets/wineserver-poolfix` | Wine **Staging 11.9**-1.1, x86_64 | `da13506f620709fb5dab7d11186c6a93` | 942 |
| `assets/wineserver-poolfix-11.10-staging` | Wine **Staging 11.10**-1.1, x86_64 | `2cd976da97a88f0d4f9cba592fe18d3f` | 943 |

Beide ~756 KB, gestrippt, Pool=32768.

### ⚠️ Protokoll-Falle bei 11.10 (wichtig!)

Wine-**Staging** 11.10 benutzt Server-Protokoll **943**, *vanilla* Wine 11.10 nur **942**.
Ein aus den **Vanilla**-Quellen gebauter 11.10-wineserver gibt gegen die installierten
Staging-Libs `wine client error:0: version mismatch 942/943` → FL startet nicht.
Das 11.10-Binary muss daher aus den **wine-staging-Quellen** gebaut werden (siehe unten).

Einspielen erledigt `scripts/08-apply-wineserver-poolfix.sh` — das Script erkennt die
installierte Wine-Version selbst und wählt das passende Binary (kopiert nach
`/usr/bin/wineserver`, Backup als `/usr/bin/wineserver.orig`).

## ⚠️ Update-Sicherheit (WICHTIG)

`WINESERVER` als Umgebungsvariable **funktioniert auf Arch/CachyOS nicht** — Wine startet immer das fest verdrahtete `/usr/bin/wineserver`. Es gibt auch **keine** Registry-/Config-Option für die Pool-Größe (sie ist einkompiliert). Deshalb muss `/usr/bin/wineserver` direkt ersetzt werden.

**Jedes `wine-staging`-Update überschreibt `/usr/bin/wineserver`** → der Fix ist dann weg und Fehler 1411 kommt zurück. Nach jedem Wine-Update neu einspielen — am einfachsten per Script (wählt automatisch das zur Version passende Binary):

```bash
bash scripts/08-apply-wineserver-poolfix.sh
```

Oder manuell das **zur installierten Version passende** Binary:

```bash
# wine --version pruefen!
sudo cp assets/wineserver-poolfix               /usr/bin/wineserver   # Wine 11.9
sudo cp assets/wineserver-poolfix-11.10-staging /usr/bin/wineserver   # wine-staging 11.10
```

Der Launcher (`scripts/run-flstudio.sh`) warnt beim Start, falls `/usr/bin/wineserver` nicht (mehr) die Pool-Version ist – sobald der Pool-Fix per `./install.sh --pool-fix` eingerichtet wurde.

## Was es NICHT ist (ausgeschlossene Sackgassen)

- **ntsync** ist nicht die Ursache. Bei Pool-Erschöpfung hängt der Hauptthread zwar in `ntsync_char_ioctl` (Symptom: Hänger statt Absturz), aber Wine fällt bei fehlendem `/dev/ntsync` sauber zurück (`server/inproc_sync.c`: `if (get_inproc_device_fd() >= 0)`) und stürzt trotzdem mit 1411 ab. ntsync ist ein Performance-Feature → **nicht deaktivieren**.
- In Wine 11.9 gibt es **keine** `WINEFSYNC/WINEESYNC/WINENTSYNC`-Variablen mehr (neue, serverseitig entschiedene „inproc sync"). Solche Zeilen im Launcher sind wirkungslos.
