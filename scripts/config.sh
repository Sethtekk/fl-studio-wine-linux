#!/bin/bash
# shellcheck disable=SC2034  # variables are used by the scripts that source this file
# ============================================================
# Settings shared by all scripts. Override any of them from the
# environment, e.g.:  WINEPREFIX=/mnt/ssd/fl-wine ./install.sh
# The installer remembers your choice in ~/.config/fl-studio-wine/config.
# ============================================================
_saved="${XDG_CONFIG_HOME:-$HOME/.config}/fl-studio-wine/config"
# shellcheck disable=SC1090
[ -z "${WINEPREFIX:-}" ] && [ -r "$_saved" ] && . "$_saved"

# Where the Windows environment for FL Studio lives (own prefix, not ~/.wine)
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-flstudio}"

# Windows user name inside the prefix (Wine uses your Linux user name)
export WINE_USER="${WINE_USER:-$USER}"

# Path of this repository
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Derived paths (don't change)
SYS32="$WINEPREFIX/drive_c/windows/system32"
USERPROFILE="$WINEPREFIX/drive_c/users/$WINE_USER"
SPLICE_SETTINGS="$USERPROFILE/AppData/Local/SpliceSettings"
FLW_CONFIG_FILE="$_saved"
