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
# FL Studio 2025 unter Wine – stabiler Start
export WINEPREFIX=$WINEPREFIX
export WINEFSYNC=1
export WINEESYNC=1
export WINE_LARGE_ADDRESS_AWARE=1
export STAGING_AUDIO_PERIOD=10000
export __GL_THREADED_OPTIMIZATIONS=0
export DXVK_CONFIG_FILE=$HOME/.config/dxvk/dxvk.conf
export DXVK_ASYNC=1
exec wine "$WINEPREFIX/drive_c/Program Files/Image-Line/FL Studio 2025/FL64.exe" "\$@"
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
echo "[2/4] ~/start-splice.sh erstellt."

# ── Icons konvertieren ───────────────────────────────────────
# FL Studio Icon
if [ -f "$WINEPREFIX/drive_c/Program Files/Image-Line/FL Studio 2025/FL64.exe" ]; then
    wrestool -x -t 14 "$WINEPREFIX/drive_c/Program Files/Image-Line/FL Studio 2025/FL64.exe" \
        -o /tmp/fl_icon.ico 2>/dev/null && \
    magick /tmp/fl_icon.ico[0] -resize 128x128 "$ICONS_DIR/fl-studio.png" 2>/dev/null || \
    cp "$REPO_DIR/assets/fl-studio-placeholder.png" "$ICONS_DIR/fl-studio.png" 2>/dev/null || true
fi

# Splice Icon
if [ -f "$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Local/splice/app.ico" ]; then
    magick "$WINEPREFIX/drive_c/users/$WINE_USER/AppData/Local/splice/app.ico[4]" \
        -resize 128x128 "$ICONS_DIR/splice.png" 2>/dev/null || true
fi

echo "[3/4] Icons konvertiert."

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

# Desktop-Datenbank aktualisieren
update-desktop-database "$APPS_DIR" 2>/dev/null || true
kbuildsycoca6 2>/dev/null || true

echo "[4/4] Desktop-Einträge für KDE registriert."
echo ""
echo "=== Fertig! ==="
echo "Starte FL Studio: ~/start-flstudio.sh"
echo "Starte Splice:    ~/start-splice.sh"
