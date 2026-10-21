#!/bin/bash
# ============================================================
# Wartung des wineserver-Pool-Fix (root, via systemd-Timer und
# vom Pacman-Hook angestoßen). Zwei Aufgaben:
#
#   1. Reparatur: Ist /usr/bin/wineserver kein Pool-Fix, wird das
#      passende Binary gebaut (falls nötig) und eingespielt.
#   2. Vorab-Build: Steht in den Repos eine neue wine-staging-Version
#      bereit (checkupdates), wird ihr Pool-Fix schon jetzt gebaut.
#      Der Pacman-Hook spielt ihn beim Update dann offline ein.
#
# Exit 1 nur, wenn die Reparatur scheitert - der Timer versucht es
# dann nach 20 Minuten erneut (Restart=on-failure).
# ============================================================
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$REPO/assets"
MANIFEST="$ASSETS/poolfix-md5.txt"
BUILD_USER="$(stat -c '%U' "$REPO")"
BUILD_HOME="$(getent passwd "$BUILD_USER" | cut -d: -f6)"
BUILD_UID="$(id -u "$BUILD_USER")"

log() { echo "[poolfix-maintain] $*"; }

as_user() {
    runuser -u "$BUILD_USER" -- env HOME="$BUILD_HOME" USER="$BUILD_USER" \
        PATH=/usr/local/bin:/usr/bin:/bin "$@"
}

notify() {   # Desktop-Hinweis, falls der Benutzer angemeldet ist
    local bus="/run/user/$BUILD_UID/bus"
    [ -S "$bus" ] || return 0
    as_user env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
        notify-send -a "FL Studio (Wine)" -i fl-studio "$1" "$2" 2>/dev/null || true
}

in_manifest() { awk '{print $1}' "$MANIFEST" 2>/dev/null | grep -qx "$1"; }

wait_for_pacman() {
    local _
    for _ in $(seq 1 180); do
        [ -e /var/lib/pacman/db.lck ] || return 0
        sleep 10
    done
    log "pacman ist seit 30 min gesperrt - Abbruch."
    return 1
}

wait_for_network() {
    local _
    for _ in $(seq 1 20); do
        curl -fsI --connect-timeout 10 https://dl.winehq.org/ >/dev/null 2>&1 && return 0
        sleep 30
    done
    log "dl.winehq.org nicht erreichbar."
    return 1
}

wait_for_pacman || exit 1

# --- 1) Reparatur ----------------------------------------------------------------
VER="$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
CUR="$(md5sum /usr/bin/wineserver 2>/dev/null | awk '{print $1}')"
if [ -n "$VER" ] && ! in_manifest "$CUR"; then
    log "wineserver ($VER) ist kein Pool-Fix - repariere."
    if [ ! -f "$ASSETS/wineserver-poolfix-$VER-staging" ]; then
        wait_for_network || { notify "Pool-Fix fehlt" "Kein Netz – neuer Versuch in 20 Minuten."; exit 1; }
    fi
    if bash "$REPO/scripts/pacman-hook-apply.sh" --build; then
        NEW="$(md5sum /usr/bin/wineserver | awk '{print $1}')"
        if in_manifest "$NEW"; then
            notify "Pool-Fix aktiv" "wineserver für wine-staging $VER automatisch gepatcht."
        else
            notify "Pool-Fix fehlgeschlagen" "Protokolltest für $VER fehlgeschlagen, Stock-wineserver aktiv."
        fi
    else
        notify "Pool-Fix fehlgeschlagen" "Build für wine-staging $VER fehlgeschlagen – neuer Versuch in 20 Minuten."
        exit 1
    fi
else
    log "wineserver ${VER:+($VER) }ist der Pool-Fix."
fi

# --- 2) Vorab-Build für anstehende Updates ---------------------------------------
PENDING="$(as_user checkupdates 2>/dev/null | awk '$1 == "wine-staging" {print $4}' | grep -oE '^[0-9]+\.[0-9]+')"
if [ -n "$PENDING" ] && [ ! -f "$ASSETS/wineserver-poolfix-$PENDING-staging" ]; then
    log "wine-staging $PENDING steht bereit - baue Pool-Fix vorab."
    if wait_for_network && as_user bash -c "mkdir -p '$BUILD_HOME/wine-build' && \
            bash '$REPO/scripts/build-wineserver-poolfix.sh' '$PENDING' > '$BUILD_HOME/wine-build/poolfix-build-$PENDING.log' 2>&1"; then
        log "Vorab-Build für $PENDING fertig."
    else
        log "Vorab-Build für $PENDING fehlgeschlagen (Log: $BUILD_HOME/wine-build/poolfix-build-$PENDING.log)."
    fi
fi
exit 0
