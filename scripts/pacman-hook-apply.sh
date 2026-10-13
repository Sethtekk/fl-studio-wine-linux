#!/bin/bash
# ============================================================
# Spielt den Pool-Fix-wineserver für die installierte wine-staging-
# Version ein. Aufrufer:
#   - Pacman-Hook (root, nach jedem wine-staging-Update)
#   - poolfix-maintain.sh (root, systemd-Timer)
#   - manuell:  sudo bash scripts/pacman-hook-apply.sh [--build]
#
# Ohne --build arbeitet das Skript rein offline: Liegt das Binary
# vor, wird es eingespielt; fehlt es, wird der Wartungsdienst
# angestoßen, der nach der Transaktion mit Netz baut. Während einer
# großen pacman-Transaktion ist das Netz oft kurz weg (Updates von
# NetworkManager, systemd, VPN-Daemons) - deshalb kein Download hier.
#
# Nach dem Einspielen: Protokolltest in einem Wegwerf-Prefix, bei
# Fehlschlag Rollback auf das Stock-Binary. Exit immer 0 im Hook.
# ============================================================
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$REPO/assets"
MANIFEST="$ASSETS/poolfix-md5.txt"
TARGET=/usr/bin/wineserver
SERVICE=wineserver-poolfix-maintain.service
BUILD_USER="$(stat -c '%U' "$REPO")"
BUILD_HOME="$(getent passwd "$BUILD_USER" | cut -d: -f6)"
MODE="${1:-}"

log() { echo "[poolfix] $*"; }

as_user() {
    if [ "$EUID" -eq 0 ]; then
        runuser -u "$BUILD_USER" -- env HOME="$BUILD_HOME" USER="$BUILD_USER" \
            PATH=/usr/local/bin:/usr/bin:/bin "$@"
    else
        "$@"
    fi
}

in_manifest() { awk '{print $1}' "$MANIFEST" 2>/dev/null | grep -qx "$1"; }

VER="$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
[ -n "$VER" ] || { log "Wine-Version nicht erkennbar - übersprungen."; exit 0; }
NAME="wineserver-poolfix-$VER-staging"
BIN="$ASSETS/$NAME"
CUR_MD5="$(md5sum "$TARGET" 2>/dev/null | awk '{print $1}')"

# --- 1) Binary fehlt -----------------------------------------------------------
if [ ! -f "$BIN" ]; then
    if [ "$MODE" = "--build" ]; then
        LOG="$BUILD_HOME/wine-build/poolfix-build-$VER.log"
        as_user mkdir -p "$BUILD_HOME/wine-build"
        log "Baue Pool-Fix für $VER (Log: $LOG) ..."
        if ! as_user bash -c "bash '$REPO/scripts/build-wineserver-poolfix.sh' '$VER' > '$LOG' 2>&1"; then
            tail -3 "$LOG" 2>/dev/null | sed 's/^/[poolfix]   /'
            log "Build für $VER fehlgeschlagen."
            exit 1
        fi
    else
        log "Für wine-staging $VER liegt noch kein Pool-Fix bereit."
        if [ "$EUID" -eq 0 ] && systemctl cat "$SERVICE" >/dev/null 2>&1; then
            systemctl start --no-block "$SERVICE"
            log "Wartungsdienst gestartet: baut und spielt den Fix nach der Transaktion ein"
            log "(Fortschritt: journalctl -u $SERVICE -f)."
        else
            log "Nachholen: sudo bash $REPO/scripts/pacman-hook-apply.sh --build"
        fi
        exit 0
    fi
fi

# --- 2) Integrität ---------------------------------------------------------------
GOT="$(md5sum "$BIN" | awk '{print $1}')"
if ! awk -v n="$NAME" '$2 == n {print $1}' "$MANIFEST" 2>/dev/null | grep -qx "$GOT"; then
    log "$NAME: md5 $GOT steht nicht im Manifest - nicht eingespielt."
    exit 0
fi
if [ "$CUR_MD5" = "$GOT" ]; then
    log "wineserver ist bereits der Pool-Fix für $VER."
    exit 0
fi
[ "$EUID" -eq 0 ] || { log "Zum Einspielen root nötig: sudo bash $0"; exit 0; }

# --- 3) Stock-Backup (pro Version, nur wenn das Ziel wirklich Stock ist) ---------
BACKUP="$TARGET.stock-$VER"
if [ ! -f "$BACKUP" ] && ! in_manifest "$CUR_MD5"; then
    cp -a "$TARGET" "$BACKUP"
    log "Stock-Binary gesichert: $BACKUP"
fi

# Atomar ersetzen: ein laufender wineserver behält seine alte Datei,
# ein In-place-Kopieren scheitert sonst mit "Text file busy".
install -m 755 -o root -g root "$BIN" "$TARGET.poolfix-new"
mv -f "$TARGET.poolfix-new" "$TARGET"
log "Pool-Fix für wine-staging $VER eingespielt (md5 $GOT)."

# --- 4) Protokolltest, sonst Rollback ----------------------------------------------
TESTPFX="$(as_user mktemp -d /tmp/poolfix-test.XXXXXX)"
OUT="$(as_user env WINEPREFIX="$TESTPFX" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
       DISPLAY= WAYLAND_DISPLAY= timeout 180 wine cmd /c echo POOLFIX_OK 2>&1)"
as_user env WINEPREFIX="$TESTPFX" wineserver -k >/dev/null 2>&1
rm -rf "$TESTPFX"

if printf '%s' "$OUT" | grep -q POOLFIX_OK; then
    log "Protokolltest OK."
    exit 0
fi
printf '%s\n' "$OUT" | grep -i -m3 -E 'mismatch|err|fail' | sed 's/^/[poolfix]   /'
if [ -f "$BACKUP" ]; then
    install -m 755 -o root -g root "$BACKUP" "$TARGET.poolfix-new" && mv -f "$TARGET.poolfix-new" "$TARGET"
    log "Protokolltest fehlgeschlagen - Stock-wineserver wiederhergestellt."
else
    log "Protokolltest fehlgeschlagen, kein Backup vorhanden. Reparatur: sudo pacman -S wine-staging"
fi
exit 0
