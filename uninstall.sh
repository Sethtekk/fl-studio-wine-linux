#!/bin/bash
# ============================================================
# Removes launchers, menu entries and settings of this project.
#   ./uninstall.sh           keeps the Wine prefix (your FL install, plugins, projects)
#   ./uninstall.sh --purge   also deletes the Wine prefix (asks first)
# Wine itself and other distro packages stay installed.
# ============================================================
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/scripts/lib/common.sh"
source "$REPO_DIR/scripts/config.sh"

APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"

step "Removing launchers and menu entries"
# only files this project generated (they carry its name)
for f in "$HOME/.local/bin/flstudio-wine" "$HOME/.local/bin/splice-wine" \
         "$APPS_DIR/fl-studio-wine.desktop" "$APPS_DIR/splice-wine.desktop" "$APPS_DIR/splice-repair-wine.desktop"; do
    grep -q 'fl-studio-wine-linux' "$f" 2>/dev/null && rm -f "$f"
done
rm -f "$ICON_DIR/fl-studio-wine.png" "$ICON_DIR/splice-wine.png"
update-desktop-database "$APPS_DIR" 2>/dev/null || true
ok "done"

if [ -f /etc/pacman.d/hooks/zz-wineserver-poolfix.hook ]; then
    step "Removing the pool-fix automation"
    sudo bash "$REPO_DIR/scripts/install-fl-wine-automation.sh" --remove
    info "To get the stock wineserver back: sudo pacman -S wine-staging"
fi

if [ "${1:-}" = "--purge" ]; then
    [ "$(realpath -m "$WINEPREFIX")" != "$(realpath -m "$HOME/.wine")" ] \
        || die "Refusing to delete ~/.wine (shared default prefix). Delete it yourself if you really want to."
    step "Wine prefix: $WINEPREFIX"
    du -sh "$WINEPREFIX" 2>/dev/null | sed 's/^/    size: /'
    if ask "Delete it with FL Studio, all plugins and anything saved inside? This cannot be undone." n; then
        wineserver -k 2>/dev/null || true
        rm -rf "${WINEPREFIX:?}"
        ok "prefix deleted"
    fi
fi
rm -rf "$(dirname "$FLW_CONFIG_FILE")"
ok "settings removed"
