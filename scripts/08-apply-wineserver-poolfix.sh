#!/bin/bash
# ============================================================
# Step 8: install the wineserver pool fix manually
#
# Replaces /usr/bin/wineserver with a build whose shared session pool
# holds 32768 objects instead of 512 - prevents error 1411 in large
# projects. If there is no binary for the installed Wine version yet,
# it is built. Includes a protocol test and automatic rollback.
#
# For permanent use, install the automation once instead:
#   sudo bash scripts/install-fl-wine-automation.sh
# ============================================================
exec sudo bash "$(dirname "$0")/pacman-hook-apply.sh" --build
