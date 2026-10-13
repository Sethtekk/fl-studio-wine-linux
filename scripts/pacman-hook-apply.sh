#!/bin/bash
# ============================================================
# Pacman-Hook-Applier (laeuft als ROOT im Hook, oder via sudo manuell)
# Spielt den passenden Pool-Fix-wineserver (Pool 32768) fuer die
# AKTUELL installierte wine-staging-Version ein.
# Version-generisch: sucht assets/wineserver-poolfix-<VER>-staging.
# Fehlt es (neue Wine-Version) und wir laufen als root -> baut es
# AUTOMATISCH als normaler User (build-wineserver-poolfix.sh).
# Nach dem Einspielen: Protokoll-Test in einem Wegwerf-Prefix,
# bei Fehlschlag automatischer Rollback auf das Stock-Binary.
# Beendet IMMER mit 0 (bricht die pacman-Transaktion nie ab).
# ============================================================
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$REPO/assets"
MANIFEST="$ASSETS/poolfix-md5.txt"
TARGET=/usr/bin/wineserver
# Besitzer des Repos = der User, als der gebaut und getestet wird (nie als root bauen)
BUILD_USER="$(stat -c '%U' "$REPO")"
BUILD_HOME="$(getent passwd "$BUILD_USER" | cut -d: -f6)"
BUILD_SCRIPT="$BUILD_HOME/wine-build/build-wineserver-poolfix.sh"

VER="$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
if [ -z "$VER" ]; then
    echo "[poolfix] Wine-Version nicht erkennbar - uebersprungen."
    exit 0
fi
BIN="$ASSETS/wineserver-poolfix-$VER-staging"

warn_stock() {
    echo "======================================================================"
    echo "[poolfix] ACHTUNG: $1"
    echo "[poolfix] /usr/bin/wineserver ist STOCK (Pool 512)."
    echo "[poolfix]  -> FL-Studio Fehler 1411 bei grossen Projekten moeglich."
    echo "[poolfix] MANUELL:  bash ~/wine-build/build-wineserver-poolfix.sh"
    echo "[poolfix] DANN:     sudo bash $REPO/scripts/pacman-hook-apply.sh"
    echo "======================================================================"
}

# als Build-User ausfuehren (im Hook sind wir root, manuell evtl. schon der User)
as_user() {
    if [ "$EUID" -eq 0 ]; then
        runuser -u "$BUILD_USER" -- env HOME="$BUILD_HOME" USER="$BUILD_USER" PATH=/usr/local/bin:/usr/bin:/bin "$@"
    else
        "$@"
    fi
}

# --- 1) Binary fehlt -> automatisch bauen -------------------------------------
if [ ! -f "$BIN" ]; then
    if [ ! -x "$BUILD_SCRIPT" ] && [ ! -f "$BUILD_SCRIPT" ]; then
        warn_stock "kein Pool-Fix fuer $VER und kein Build-Skript ($BUILD_SCRIPT)."
        exit 0
    fi
    LOG="$BUILD_HOME/wine-build/hook-build-$VER.log"
    echo "[poolfix] Kein Binary fuer wine-staging $VER - baue automatisch (ca. 1-2 min, braucht Internet)..."
    echo "[poolfix] Log: $LOG"
    if as_user bash -c "bash '$BUILD_SCRIPT' '$VER' > '$LOG' 2>&1"; then
        echo "[poolfix] Build fuer $VER erfolgreich."
    else
        tail -5 "$LOG" 2>/dev/null | sed 's/^/[poolfix]   /'
        warn_stock "automatischer Build fuer $VER fehlgeschlagen (siehe $LOG)."
        exit 0
    fi
    if [ ! -f "$BIN" ]; then
        warn_stock "Build lief, aber $BIN fehlt."
        exit 0
    fi
fi

# --- 2) Integritaet gegen Manifest --------------------------------------------
EXP="$(awk -v f="wineserver-poolfix-$VER-staging" '$2==f{print $1}' "$MANIFEST" 2>/dev/null)"
GOT="$(md5sum "$BIN" | awk '{print $1}')"
if [ -n "$EXP" ] && [ "$EXP" != "$GOT" ]; then
    warn_stock "$BIN md5 $GOT != erwartet $EXP - nicht eingespielt."
    exit 0
fi

if [ "$(md5sum "$TARGET" 2>/dev/null | awk '{print $1}')" = "$GOT" ]; then
    echo "[poolfix] wineserver ist bereits der Pool-Fix fuer $VER - nichts zu tun."
    exit 0
fi

# Root noetig zum Schreiben nach /usr/bin
SUDO=""
[ "$EUID" -ne 0 ] && SUDO="sudo"

# --- 3) Backup des Stock-Binaries, VERSIONSBEHAFTET ---------------------------
# Ein Backup pro Wine-Version, und nur wenn das aktuelle Ziel wirklich Stock ist
# (also KEIN bekannter Pool-Fix aus dem Manifest) - sonst waere der Rollback
# ein Protokoll-Mismatch.
TARGET_MD5="$(md5sum "$TARGET" 2>/dev/null | awk '{print $1}')"
BACKUP="$TARGET.stock-$VER"
if [ -f "$BACKUP" ]; then
    :
elif awk '{print $1}' "$MANIFEST" 2>/dev/null | grep -qx "$TARGET_MD5"; then
    echo "[poolfix] Hinweis: /usr/bin/wineserver ist bereits ein Pool-Fix - kein Stock-Backup moeglich."
else
    $SUDO cp -a "$TARGET" "$BACKUP"
    echo "[poolfix] Stock-Binary gesichert: $BACKUP (md5 $TARGET_MD5)"
fi

$SUDO cp "$BIN" "$TARGET"
echo "[poolfix] Pool-Fix fuer wine-staging $VER eingespielt (md5 $GOT)."

# --- 4) Protokoll-Test in Wegwerf-Prefix, sonst Rollback ----------------------
# Passt das Binary nicht zur installierten Wine-Version, meldet wine
# "version mismatch" und startet gar nicht. Getestet wird NIE im FL-Prefix.
TESTPFX="$(as_user mktemp -d /tmp/poolfix-test.XXXXXX)"
OUT="$(as_user env WINEPREFIX="$TESTPFX" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" DISPLAY= WAYLAND_DISPLAY= \
       timeout 180 wine cmd /c echo POOLFIX_OK 2>&1)"
as_user env WINEPREFIX="$TESTPFX" wineserver -k >/dev/null 2>&1
rm -rf "$TESTPFX"

if printf '%s' "$OUT" | grep -q POOLFIX_OK; then
    echo "[poolfix] Protokoll-Test OK - Wine startet mit dem Pool-Fix."
    [ -f "$BACKUP" ] && echo "[poolfix] Rollback-Ziel: $BACKUP"
else
    printf '%s\n' "$OUT" | grep -i -m3 -E "mismatch|err|fail" | sed 's/^/[poolfix]   /'
    if [ -f "$BACKUP" ]; then
        $SUDO cp "$BACKUP" "$TARGET"
        warn_stock "Protokoll-Test fuer $VER fehlgeschlagen - Stock-Binary wiederhergestellt."
    else
        echo "[poolfix] FEHLER: Protokoll-Test fehlgeschlagen und kein Backup $BACKUP!"
        echo "[poolfix]   Wine reparieren: sudo pacman -S wine-staging"
    fi
fi
exit 0
