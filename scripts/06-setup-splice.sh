#!/bin/bash
# ============================================================
# Step 6 (optional): Splice desktop app
#
#   bash scripts/06-setup-splice.sh [~/Downloads/SpliceSetup.exe]
#
# Installs Splice into the FL prefix (if an installer is given), clears
# caches that are known to get corrupted under Wine and creates the
# "Splice (Wine)" launcher. The launcher itself keeps Splice healthy
# (see scripts/run-splice.sh: Conveyor migration off, appState repair).
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/config.sh"

step "Setting up Splice"
if [ -n "${1:-}" ]; then
    [ -f "$1" ] || die "Installer not found: $1"
    info "Running the Splice installer - log in when the window appears, then close Splice."
    WINEDEBUG=-all wine "$1" || true
    wineserver -w
fi
[ -f "$USERPROFILE/AppData/Local/splice/Splice.exe" ] \
    || die "Splice is not installed. Download SpliceSetup.exe from splice.com and pass it to this script."

pkill -9 -f 'Local\\splice\\' 2>/dev/null || true
# Corrupted service-worker databases freeze the renderer under Wine
for d in "Service Worker" "blob_storage" "Code Cache"; do
    rm -rf "${SPLICE_SETTINGS:?}/$d"
done
rm -f "$SPLICE_SETTINGS/lockfile"
ok "caches cleared"

bash "$(dirname "$0")/05-install-launchers.sh" >/dev/null
ok "launcher: Splice (Wine)  /  command: splice-wine"
