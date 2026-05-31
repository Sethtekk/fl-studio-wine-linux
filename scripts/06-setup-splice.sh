#!/bin/bash
# ============================================================
# Schritt 6: Splice-Konfiguration reparieren
#
# Splice hat zwei bekannte Probleme unter Wine:
# 1. "Conveyor Migration" hängt beim Start → UI öffnet sich nicht
# 2. Service Worker Cache kann korrumpiert werden → Renderer friert ein
#
# Dieses Script behebt beide Probleme.
# ============================================================
set -e
source "$(dirname "$0")/config.sh"

APPSTATE="$SPLICE_SETTINGS/appState.json"

echo "=== Splice-Konfiguration reparieren ==="

if [ ! -f "$APPSTATE" ]; then
    echo "appState.json nicht gefunden – Splice noch nicht installiert?"
    echo "Installiere Splice zuerst, dann führe dieses Script erneut aus."
    exit 1
fi

# Backup
cp "$APPSTATE" "${APPSTATE}.bak-$(date +%Y%m%d)"
echo "[1/3] Backup von appState.json erstellt."

# Conveyor-Migration deaktivieren + Fenster-Zustand zurücksetzen
python3 - "$APPSTATE" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    state = json.load(f)

# Verhindert Auto-Migration zu Conveyor (hängt unter Wine)
state["upgradeState"] = None

# Verhindert Fehler beim Wiederherstellen des Fenster-Zustands
if "windows" in state and "legacy" in state.get("windows", {}):
    state["windows"]["legacy"]["isOpen"] = False

with open(p, "w") as f:
    json.dump(state, f, indent=2)
print("  upgradeState = null")
print("  legacy.isOpen = false")
PY
echo "[2/3] appState.json konfiguriert."

# Service Worker Cache löschen (kann korrumpiert sein)
for dir in "Service Worker" "blob_storage" "Session Storage" "Code Cache"; do
    if [ -d "$SPLICE_SETTINGS/$dir" ]; then
        rm -rf "$SPLICE_SETTINGS/$dir"
        echo "  $dir/ gelöscht"
    fi
done
rm -f "$SPLICE_SETTINGS/lockfile" 2>/dev/null || true
echo "[3/3] Caches geleert."

echo ""
echo "=== Splice-Konfiguration repariert! ==="
echo "Starte Splice jetzt: ~/start-splice.sh"
echo ""
echo "Hinweis: Beim ersten Start musst du dich in Splice einloggen."
echo "Das Fenster erscheint nach ca. 5-10 Sekunden."
