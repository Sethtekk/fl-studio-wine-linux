#!/bin/bash
# ============================================================
# Starts the Splice desktop app in the FL Studio prefix.
# Splice and FL Studio can run at the same time.
#
# Self-healing before every start (only if Splice isn't running yet):
#  1) app.asar: the "Conveyor" migration is switched off. Otherwise Splice
#     quits after 10 minutes idle, runs the Conveyor installer (fails under
#     Wine -> error dialog) and sets upgradeState, so the next start hangs
#     without a window. The original is kept as app.asar.orig.
#  2) appState.json: upgradeState=null, conveyorMigration.isComplete=true
#
#   --repair   also kill hanging Splice processes first
# ============================================================
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/config.sh"

export WINEFSYNC=1 WINEESYNC=1
export WINE_LARGE_ADDRESS_AWARE=1
export WINEDEBUG=-all

LOCAL="$USERPROFILE/AppData/Local"
SPLICE_EXE="$LOCAL/splice/Splice.exe"
[ -f "$SPLICE_EXE" ] || die "Splice is not installed in $WINEPREFIX (install it with: $REPO_DIR/install.sh --splice-installer ~/Downloads/SpliceSetup.exe)"

if [ "${1:-}" = "--repair" ]; then
    pkill -9 -f 'Local\\splice\\' 2>/dev/null
    rm -f "$SPLICE_SETTINGS/lockfile"
    sleep 1
fi

if ! pgrep -f 'Local\\splice\\app-.*Splice\.exe$' >/dev/null 2>&1; then
    python3 - "$SPLICE_SETTINGS/appState.json" "$LOCAL/splice" <<'PY'
import json, sys, glob, os, shutil
appstate, splice_dir = sys.argv[1], sys.argv[2]

# 1) disable the Conveyor migration in the app code (same-length replacement)
old = b'onMigrationReady(){Ar.log.info("Migration ready."),'
new = b'onMigrationReady(){return Ar.log.info("noConveyo");'
for asar in glob.glob(os.path.join(splice_dir, "app-*", "resources", "app.asar")):
    data = open(asar, "rb").read()
    if data.count(old) == 1:
        if not os.path.exists(asar + ".orig"):
            shutil.copy2(asar, asar + ".orig")
        open(asar, "wb").write(data.replace(old, new))
        print("splice: Conveyor migration disabled in", asar)

# 2) repair appState.json
try:
    with open(appstate, encoding="utf-8") as f:
        d = json.load(f)
except (OSError, ValueError):
    sys.exit(0)
cm = d.get("conveyorMigration")
if d.get("upgradeState") is not None or not (isinstance(cm, dict) and cm.get("isComplete") is True):
    shutil.copy2(appstate, appstate + ".bak-autostart")
    d["upgradeState"] = None
    if isinstance(cm, dict):
        cm["isComplete"] = True
    else:
        d["conveyorMigration"] = {"isComplete": True}
    with open(appstate, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, separators=(",", ":"))
    print("splice: appState.json repaired")
PY
fi

exec wine "$SPLICE_EXE"
