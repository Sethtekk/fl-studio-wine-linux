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

## Die vorkompilierte Binary

`assets/wineserver-poolfix` ist der für **Wine 11.9, x86_64** gebaute, gestrippte wineserver mit Pool=32768.
- **MD5:** `da13506f620709fb5dab7d11186c6a93`
- **Größe:** ~756 KB
- **Basis:** Wine Staging 11.9-1.1

Einspielen erledigt `scripts/08-apply-wineserver-poolfix.sh` (kopiert nach `/usr/bin/wineserver`, Backup als `/usr/bin/wineserver.orig`).

## ⚠️ Update-Sicherheit (WICHTIG)

`WINESERVER` als Umgebungsvariable **funktioniert auf Arch/CachyOS nicht** — Wine startet immer das fest verdrahtete `/usr/bin/wineserver`. Es gibt auch **keine** Registry-/Config-Option für die Pool-Größe (sie ist einkompiliert). Deshalb muss `/usr/bin/wineserver` direkt ersetzt werden.

**Jedes `wine-staging`-Update überschreibt `/usr/bin/wineserver`** → der Fix ist dann weg und Fehler 1411 kommt zurück. Nach jedem Wine-Update neu einspielen:

```bash
sudo cp assets/wineserver-poolfix /usr/bin/wineserver
```

Der Launcher `start-flstudio.sh` enthält einen md5-Wächter, der beim Start warnt, falls `/usr/bin/wineserver` nicht (mehr) die Pool-Version ist.

## Was es NICHT ist (ausgeschlossene Sackgassen)

- **ntsync** ist nicht die Ursache. Bei Pool-Erschöpfung hängt der Hauptthread zwar in `ntsync_char_ioctl` (Symptom: Hänger statt Absturz), aber Wine fällt bei fehlendem `/dev/ntsync` sauber zurück (`server/inproc_sync.c`: `if (get_inproc_device_fd() >= 0)`) und stürzt trotzdem mit 1411 ab. ntsync ist ein Performance-Feature → **nicht deaktivieren**.
- In Wine 11.9 gibt es **keine** `WINEFSYNC/WINEESYNC/WINENTSYNC`-Variablen mehr (neue, serverseitig entschiedene „inproc sync"). Solche Zeilen im Launcher sind wirkungslos.
