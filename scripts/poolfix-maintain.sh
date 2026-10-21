#!/bin/bash
# ============================================================
# Maintenance of the wineserver pool fix (root, run by the systemd
# timer and triggered by the pacman hook). Two jobs:
#
#   1. Repair: if /usr/bin/wineserver is not the pool fix, the matching
#      binary is built (if needed) and installed.
#   2. Pre-build: if the repos already offer a new wine-staging version
#      (checkupdates), its pool fix is built now, so the pacman hook can
#      install it offline during the update.
#
# Exits 1 only if the repair fails - the service then retries after
# 20 minutes (Restart=on-failure).
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

notify() {   # desktop notification, if the user is logged in
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
    log "pacman has been locked for 30 minutes - giving up."
    return 1
}

wait_for_network() {
    local _
    for _ in $(seq 1 20); do
        curl -fsI --connect-timeout 10 https://dl.winehq.org/ >/dev/null 2>&1 && return 0
        sleep 30
    done
    log "dl.winehq.org is not reachable."
    return 1
}

wait_for_pacman || exit 1

# --- 1) Repair -------------------------------------------------------------------
VER="$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
CUR="$(md5sum /usr/bin/wineserver 2>/dev/null | awk '{print $1}')"
if [ -n "$VER" ] && ! in_manifest "$CUR"; then
    log "wineserver ($VER) is not the pool fix - repairing."
    if [ ! -f "$ASSETS/wineserver-poolfix-$VER-staging" ]; then
        wait_for_network || { notify "Pool fix missing" "No network - retrying in 20 minutes."; exit 1; }
    fi
    if bash "$REPO/scripts/pacman-hook-apply.sh" --build; then
        NEW="$(md5sum /usr/bin/wineserver | awk '{print $1}')"
        if in_manifest "$NEW"; then
            notify "Pool fix active" "wineserver for wine-staging $VER patched automatically."
        else
            notify "Pool fix failed" "Protocol test for $VER failed, stock wineserver is active."
        fi
    else
        notify "Pool fix failed" "Build for wine-staging $VER failed - retrying in 20 minutes."
        exit 1
    fi
else
    log "wineserver ${VER:+($VER) }is the pool fix."
fi

# --- 2) Pre-build for upcoming updates -------------------------------------------
PENDING="$(as_user checkupdates 2>/dev/null | awk '$1 == "wine-staging" {print $4}' | grep -oE '^[0-9]+\.[0-9]+')"
if [ -n "$PENDING" ] && [ ! -f "$ASSETS/wineserver-poolfix-$PENDING-staging" ]; then
    log "wine-staging $PENDING is available - pre-building the pool fix."
    if wait_for_network && as_user bash -c "mkdir -p '$BUILD_HOME/wine-build' && \
            bash '$REPO/scripts/build-wineserver-poolfix.sh' '$PENDING' > '$BUILD_HOME/wine-build/poolfix-build-$PENDING.log' 2>&1"; then
        log "Pre-build for $PENDING done."
    else
        log "Pre-build for $PENDING failed (log: $BUILD_HOME/wine-build/poolfix-build-$PENDING.log)."
    fi
fi
exit 0
