#!/bin/bash
# ============================================================
# d2d1-Patch wiederherstellen
#
# Ausführen wenn FL Studio nach einem Wine-Update wieder
# einfriert. Idempotent – mehrfaches Ausführen schadet nicht.
# ============================================================
set -e
source "$(dirname "$0")/config.sh"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATCHED_DLL="$REPO_DIR/assets/d2d1.dll.patched"

echo "== d2d1-Patch Wiederherstellung =="

cp -a "$PATCHED_DLL" "$SYS32/d2d1.dll"
echo "[1/3] Gepatchte d2d1.dll nach system32 kopiert."

python3 - "$SYS32/d2d1.dll" <<'PY'
import sys
p = sys.argv[1]
with open(p, "r+b") as f:
    f.seek(0x40)
    f.write(b"\x00" * 16)
print("[2/3] Builtin-Signatur bei Offset 0x40 auf 0x00 gesetzt.")
PY

WINEPREFIX="$WINEPREFIX" wine reg add \
    "HKCU\\Software\\Wine\\DllOverrides" \
    /v d2d1 /d "native,builtin" /f >/dev/null 2>&1 || true
echo "[3/3] Registry: d2d1 = native,builtin"

echo ""
echo "== Fertig. MD5: $(md5sum "$SYS32/d2d1.dll" | cut -d' ' -f1) =="
