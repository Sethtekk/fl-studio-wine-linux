#!/bin/bash
# ============================================================
# Installs the pool-fix wineserver for the installed wine-staging
# version. Called by:
#   - the pacman hook (root, after every wine-staging update)
#   - poolfix-maintain.sh (root, systemd timer)
#   - by hand:  sudo bash scripts/pacman-hook-apply.sh [--build]
#
# Without --build the script works fully offline: if the binary is
# there, it is installed; if not, the maintenance service is triggered
# and builds it after the transaction, once the network is back. During
# a large pacman transaction the network is often down for a moment
# (updates to NetworkManager, systemd, VPN daemons) - so no downloads
# here.
#
# After installing: protocol test in a throwaway prefix, rollback to
# the stock binary on failure. Always exits 0 in the hook.
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
[ -n "$VER" ] || { log "Cannot determine the Wine version - skipped."; exit 0; }
NAME="wineserver-poolfix-$VER-staging"
BIN="$ASSETS/$NAME"
CUR_MD5="$(md5sum "$TARGET" 2>/dev/null | awk '{print $1}')"

# --- 1) Binary missing ----------------------------------------------------------
if [ ! -f "$BIN" ]; then
    if [ "$MODE" = "--build" ]; then
        LOG="$BUILD_HOME/wine-build/poolfix-build-$VER.log"
        as_user mkdir -p "$BUILD_HOME/wine-build"
        log "Building the pool fix for $VER (log: $LOG) ..."
        if ! as_user bash -c "bash '$REPO/scripts/build-wineserver-poolfix.sh' '$VER' > '$LOG' 2>&1"; then
            tail -3 "$LOG" 2>/dev/null | sed 's/^/[poolfix]   /'
            log "Build for $VER failed."
            exit 1
        fi
    else
        log "No pool fix available yet for wine-staging $VER."
        if [ "$EUID" -eq 0 ] && systemctl cat "$SERVICE" >/dev/null 2>&1; then
            systemctl start --no-block "$SERVICE"
            log "Maintenance service started: it builds and installs the fix after the transaction"
            log "(progress: journalctl -u $SERVICE -f)."
        else
            log "To do it later: sudo bash $REPO/scripts/pacman-hook-apply.sh --build"
        fi
        exit 0
    fi
fi

# --- 2) Integrity -----------------------------------------------------------------
GOT="$(md5sum "$BIN" | awk '{print $1}')"
if ! awk -v n="$NAME" '$2 == n {print $1}' "$MANIFEST" 2>/dev/null | grep -qx "$GOT"; then
    log "$NAME: md5 $GOT is not in the manifest - not installed."
    exit 0
fi
if [ "$CUR_MD5" = "$GOT" ]; then
    log "wineserver already is the pool fix for $VER."
    exit 0
fi
[ "$EUID" -eq 0 ] || { log "Installing needs root: sudo bash $0"; exit 0; }

# --- 3) Stock backup (per version, only if the target really is stock) ----------
BACKUP="$TARGET.stock-$VER"
if [ ! -f "$BACKUP" ] && ! in_manifest "$CUR_MD5"; then
    cp -a "$TARGET" "$BACKUP"
    log "Stock binary saved: $BACKUP"
fi

# Replace atomically: a running wineserver keeps its old file; copying
# in place would fail with "Text file busy".
install -m 755 -o root -g root "$BIN" "$TARGET.poolfix-new"
mv -f "$TARGET.poolfix-new" "$TARGET"
log "Pool fix for wine-staging $VER installed (md5 $GOT)."

# --- 4) Protocol test, rollback on failure -----------------------------------------
TESTPFX="$(as_user mktemp -d /tmp/poolfix-test.XXXXXX)"
OUT="$(as_user env WINEPREFIX="$TESTPFX" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
       DISPLAY= WAYLAND_DISPLAY= timeout 180 wine cmd /c echo POOLFIX_OK 2>&1)"
as_user env WINEPREFIX="$TESTPFX" wineserver -k >/dev/null 2>&1
rm -rf "$TESTPFX"

if printf '%s' "$OUT" | grep -q POOLFIX_OK; then
    log "Protocol test OK."
    exit 0
fi
printf '%s\n' "$OUT" | grep -i -m3 -E 'mismatch|err|fail' | sed 's/^/[poolfix]   /'
if [ -f "$BACKUP" ]; then
    install -m 755 -o root -g root "$BACKUP" "$TARGET.poolfix-new" && mv -f "$TARGET.poolfix-new" "$TARGET"
    log "Protocol test failed - stock wineserver restored."
else
    log "Protocol test failed and there is no backup. To repair: sudo pacman -S wine-staging"
fi
exit 0
