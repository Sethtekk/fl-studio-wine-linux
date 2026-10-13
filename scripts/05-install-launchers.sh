#!/bin/bash
# ============================================================
# Schritt 5: Launcher-Scripts und KDE-Desktop-Icons installieren
# ============================================================
set -e
source "$(dirname "$0")/config.sh"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPS_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"

mkdir -p "$APPS_DIR" "$ICONS_DIR"

echo "=== Launchers und Desktop-Icons installieren ==="

# ── FL Studio Launcher ──────────────────────────────────────
cat > "$HOME/start-flstudio.sh" <<LAUNCHER
#!/bin/bash
# FL Studio unter Wine – stabiler Start
# d2d1.dll: gepatchte native Version (CDT-/Bezier-Fixes, siehe patches/d2d1-geometry-fix.md)
# Audio: WineASIO via PipeWire-JACK (pw-jack)
export WINEPREFIX=$WINEPREFIX
export WINEFSYNC=1
export WINEESYNC=1
export WINE_LARGE_ADDRESS_AWARE=1
export STAGING_AUDIO_PERIOD=10000
export __GL_THREADED_OPTIMIZATIONS=0
# GL ueber EGL (Registry UseEGL=Y, Schritt 2) loest den GL-Deadlock; diese Zeile
# erzwingt NVIDIAs EGL - ohne sie kann glvnd auf Mesa-EGL fallen.
[ -f /usr/share/glvnd/egl_vendor.d/10_nvidia.json ] && \
    export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
export DXVK_CONFIG_FILE=$HOME/.config/dxvk/dxvk.conf
# d2d1 schreibt bei Plugin-UIs pro Linie ein fixme (gemessen 11.000 Zeilen/s) -> aus.
export WINEDEBUG=fixme-all
export PIPEWIRE_RUNTIME_DIR=/run/user/\$(id -u)
export JACK_NO_AUDIO_RESERVATION=1
# Pool-Fix-Waechter: /usr/bin/wineserver muss die gepatchte Version sein (Pool 512->32768),
# sonst Fehler 1411 "Klasse existiert nicht" bei grossen Projekten. Die bekannten Hashes
# pflegt der Pacman-Hook im Manifest (assets/poolfix-md5.txt).
if ! awk '{print \$1}' "$REPO_DIR/assets/poolfix-md5.txt" 2>/dev/null \
        | grep -qx "\$(md5sum /usr/bin/wineserver 2>/dev/null | cut -d' ' -f1)"; then
    echo "WARNUNG: /usr/bin/wineserver (\$(wine --version)) ist NICHT der Pool-Fix. Fehler 1411 droht."
    echo "  -> nachholen: sudo bash $REPO_DIR/scripts/pacman-hook-apply.sh"
fi
FL_EXE="\$(ls -d "$WINEPREFIX/drive_c/Program Files/Image-Line/FL Studio "*/FL64.exe 2>/dev/null | sort -V | tail -1)"
trap 'wineserver -k' EXIT
pw-jack wine "\$FL_EXE" "\$@"
LAUNCHER
chmod +x "$HOME/start-flstudio.sh"
echo "[1/4] ~/start-flstudio.sh erstellt."

# ── Splice Launcher ─────────────────────────────────────────
cat > "$HOME/start-splice.sh" <<LAUNCHER
#!/bin/bash
# Splice Desktop App unter Wine – stabiler Start
export WINEPREFIX=$WINEPREFIX
export WINEFSYNC=1
export WINEESYNC=1
export WINE_LARGE_ADDRESS_AWARE=1
export WINEDEBUG=-all
exec wine "$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Local/splice/Splice.exe"
LAUNCHER
chmod +x "$HOME/start-splice.sh"
echo "[2/5] ~/start-splice.sh erstellt."

# ── Splice-Reparatur-Script (Conveyor-Migration-Haenger) ─────
# Quoted Heredoc -> innerer Python-Heredoc bleibt literal; Pfade per sed ersetzt.
cat > "$HOME/fix-splice.sh" <<'FIXEOF'
#!/bin/bash
# fix-splice.sh - behebt den haengenden Splice-Start (Conveyor-Migration unter Wine)
# Symptom: Splice "startet nicht" -> unsichtbare Zombie-Prozesse ohne Fenster.
# Fix: in appState.json upgradeState=null UND conveyorMigration.isComplete=true, dann neu starten.
#   ./fix-splice.sh            -> Fix anwenden und Splice starten
#   ./fix-splice.sh --no-start -> nur Fix anwenden
set -u
APPSTATE="__WINEPREFIX__/drive_c/users/__WINE_USER__/AppData/Local/SpliceSettings/appState.json"
LAUNCHER="$HOME/start-splice.sh"

echo "== Splice-Fix =="
echo "-> beende laufende/haengende Splice-Prozesse ..."
pkill -9 -f 'Local\\splice\\' 2>/dev/null
sleep 1

if [ ! -f "$APPSTATE" ]; then
    echo "FEHLER: appState.json nicht gefunden: $APPSTATE"
    exit 1
fi
BAK="${APPSTATE}.bak-$(date +%Y%m%d-%H%M%S)"
cp "$APPSTATE" "$BAK" && echo "-> Backup: $BAK"

echo "-> setze upgradeState=null und conveyorMigration.isComplete=true ..."
python3 - "$APPSTATE" <<'PY'
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as f:
    d = json.load(f)
d["upgradeState"] = None
cm = d.get("conveyorMigration")
if isinstance(cm, dict):
    cm["isComplete"] = True
else:
    d["conveyorMigration"] = {"isComplete": True}
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, separators=(",", ":"))
print("   ok.")
PY
if [ $? -ne 0 ]; then
    echo "FEHLER beim Patchen - stelle Backup wieder her."; cp "$BAK" "$APPSTATE"; exit 1
fi

if [ "${1:-}" = "--no-start" ]; then
    echo "Fertig (kein Start angefordert). Starten mit: $LAUNCHER"; exit 0
fi
echo "-> starte Splice ..."
nohup bash "$LAUNCHER" >/dev/null 2>&1 &
echo "   gestartet. Fenster sollte in ~5-15 s erscheinen."
FIXEOF
sed -i -e "s|__WINEPREFIX__|$WINEPREFIX|g" -e "s|__WINE_USER__|$WINE_USER|g" "$HOME/fix-splice.sh"
chmod +x "$HOME/fix-splice.sh"
echo "[3/5] ~/fix-splice.sh erstellt."

# ── Icons konvertieren ───────────────────────────────────────
# FL Studio Icon
if [ -f "$WINEPREFIX/drive_c/Program Files/Image-Line/FL Studio 2025/FL64.exe" ]; then
    wrestool -x -t 14 "$WINEPREFIX/drive_c/Program Files/Image-Line/FL Studio 2025/FL64.exe" \
        -o /tmp/fl_icon.ico 2>/dev/null && \
    magick /tmp/fl_icon.ico[0] -resize 128x128 "$ICONS_DIR/fl-studio.png" 2>/dev/null || \
    cp "$REPO_DIR/assets/fl-studio-placeholder.png" "$ICONS_DIR/fl-studio.png" 2>/dev/null || true
fi

# Splice Icon (Original)
if [ -f "$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Local/splice/app.ico" ]; then
    magick "$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Local/splice/app.ico[4]" \
        -resize 128x128 "$ICONS_DIR/splice.png" 2>/dev/null || true
fi

# Splice Icon (abgewandelt, fuer den Reparatur-Launcher) - aus mitgeliefertem Asset
if [ -f "$REPO_DIR/assets/splice-fix.png" ]; then
    magick "$REPO_DIR/assets/splice-fix.png" -resize 128x128 "$ICONS_DIR/splice-fix.png" 2>/dev/null \
        || cp "$REPO_DIR/assets/splice-fix.png" "$ICONS_DIR/splice-fix.png"
fi

echo "[4/5] Icons konvertiert."

# ── Desktop-Einträge ─────────────────────────────────────────
cat > "$APPS_DIR/fl-studio-wine.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=FL Studio 2025 (Wine)
GenericName=Music Production
Comment=FL Studio 2025 unter Wine - stabiler Start (d2d1-Patch, fsync)
Exec=$HOME/start-flstudio.sh
Icon=$ICONS_DIR/fl-studio.png
Terminal=false
Categories=AudioVideo;Audio;Music;
StartupNotify=true
StartupWMClass=fl64.exe
DESKTOP

cat > "$APPS_DIR/splice-wine.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=Splice (Wine)
GenericName=Music Production
Comment=Splice Desktop App unter Wine
Exec=$HOME/start-splice.sh
Icon=$ICONS_DIR/splice.png
Terminal=false
Categories=AudioVideo;Audio;Music;
StartupNotify=true
StartupWMClass=splice.exe
DESKTOP

cat > "$APPS_DIR/splice-fix-wine.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=Splice reparieren (Wine)
GenericName=Music Production
Comment=Behebt den haengenden Splice-Start (Conveyor-Migration) und startet Splice
Exec=$HOME/fix-splice.sh
Icon=$ICONS_DIR/splice-fix.png
Terminal=false
Categories=AudioVideo;Audio;Music;
StartupNotify=true
StartupWMClass=splice.exe
DESKTOP

# Desktop-Datenbank aktualisieren
update-desktop-database "$APPS_DIR" 2>/dev/null || true
kbuildsycoca6 2>/dev/null || true

echo "[5/5] Desktop-Einträge für KDE registriert."
echo ""
echo "=== Fertig! ==="
echo "Starte FL Studio:     ~/start-flstudio.sh"
echo "Starte Splice:        ~/start-splice.sh"
echo "Splice reparieren:    ~/fix-splice.sh  (Launcher 'Splice reparieren')"
