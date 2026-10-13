#!/bin/bash
# ============================================================
# Schritt 4: Gepatchte d2d1.dll anwenden
#
# WARUM: Wine's d2d1.dll hat einen Stack-Overflow-Bug in
# d2d_cdt_insert_segment() → FL Studio friert ein beim
# Öffnen von Plugins wie Serum 2, Ozone 11, etc.
#
# DIE LÖSUNG: Eine vorkompilierte d2d1.dll aus Wine 11.19
# mit dem Fix (Endlosschleifen/Rekursionen begrenzt) wird ins Prefix kopiert.
# Die Wine-Builtin-Signatur bei Offset 0x40 wird auf 0x00
# gesetzt, damit Wine sie als "native" DLL lädt.
# ============================================================
set -e
source "$(dirname "$0")/config.sh"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATCHED_DLL="$REPO_DIR/assets/d2d1.dll.patched"

echo "=== d2d1-Patch anwenden ==="
echo "Prefix: $WINEPREFIX"
echo ""

# Prüfen ob gepatchte DLL vorhanden
if [ ! -f "$PATCHED_DLL" ]; then
    echo "FEHLER: $PATCHED_DLL nicht gefunden!"
    echo "Stelle sicher, dass das Repository vollständig geklont wurde."
    exit 1
fi

# Backup der Original-DLL (falls vorhanden)
if [ -f "$SYS32/d2d1.dll" ]; then
    cp -a "$SYS32/d2d1.dll" "$SYS32/d2d1.dll.bak-$(date +%Y%m%d)" 2>/dev/null || true
    echo "[0/3] Backup der alten d2d1.dll erstellt."
fi

# 1) Gepatchte DLL kopieren
cp -a "$PATCHED_DLL" "$SYS32/d2d1.dll"
echo "[1/3] Gepatchte d2d1.dll nach system32 kopiert."

# 2) Wine-Builtin-Signatur bei Offset 0x40 auf 0x00 setzen
# → Wine erkennt die DLL nicht mehr als Builtin und lädt sie als Native
python3 - "$SYS32/d2d1.dll" <<'PY'
import sys
p = sys.argv[1]
with open(p, "r+b") as f:
    f.seek(0x40)
    f.write(b"\x00" * 16)
print("[2/3] Wine-Builtin-Signatur bei Offset 0x40 auf 0x00 gesetzt.")
PY

# 3) DllOverride in der Registry setzen
WINEPREFIX="$WINEPREFIX" wine reg add \
    "HKCU\\Software\\Wine\\DllOverrides" \
    /v d2d1 /d "native,builtin" /f >/dev/null 2>&1
echo "[3/3] Registry: d2d1 = native,builtin"

echo ""
echo "Verifizierung:"
echo "  MD5:    $(md5sum "$SYS32/d2d1.dll" | cut -d' ' -f1)"
echo "  Erwartet: 826992aa3b34cc9fd6f232719eb8c3c0"
echo "  Größe:  $(du -sh "$SYS32/d2d1.dll" | cut -f1)"
echo ""
echo "=== d2d1-Patch erfolgreich angewendet! ==="
echo "=== Fertig! Weiter mit: bash scripts/05-install-launchers.sh ==="
