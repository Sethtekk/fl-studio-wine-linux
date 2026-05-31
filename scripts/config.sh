#!/bin/bash
# ============================================================
# KONFIGURATION – hier alle Pfade anpassen
# ============================================================

# WINEPREFIX: Wo dein "Windows-Container" liegt
# Beispiele:
#   Auf dem Heimverzeichnis:   export WINEPREFIX="$HOME/.wine-flstudio"
#   Auf externem Laufwerk:     export WINEPREFIX="/run/media/$USER/WinVM/.wine"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-flstudio}"

# Windows-Benutzername im Prefix (normalerweise gleich wie Linux-User)
export WINE_USER="${WINE_USER:-$USER}"

# Pfad zu diesem Repository
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Abgeleitete Pfade (nicht ändern)
SYS32="$WINEPREFIX/drive_c/windows/system32"
USERPROFILE="$WINEPREFIX/drive_c/users/$WINE_USER"
SPLICE_SETTINGS="$USERPROFILE/AppData/Local/SpliceSettings"
