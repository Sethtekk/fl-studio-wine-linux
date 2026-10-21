#!/bin/bash
# ============================================================
# Step 2: create and configure the Wine prefix
#   - Windows 10 mode, VC++ runtimes, core fonts
#   - OpenGL via EGL instead of GLX (UseEGL=Y)
# Optional: WITH_DOTNET=1 also installs .NET 4.8 (slow, only some
# plugin installers need it).
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/config.sh"

step "Creating Wine prefix: $WINEPREFIX"
mkdir -p "$WINEPREFIX"
# Current Wine builds are WoW64: one "wine" binary runs 32- and 64-bit programs.
# winemenubuilder off: otherwise every installer (FL, plugins) litters the app
# menu with Wine entries - the launchers of this project replace them.
WINEDLLOVERRIDES="winemenubuilder.exe=d" WINEDEBUG=-all wine wineboot --init >/dev/null 2>&1
WINEDEBUG=-all wine reg add 'HKCU\Software\Wine\DllOverrides' /v winemenubuilder.exe /d '' /f >/dev/null 2>&1
wineserver -w
ok "prefix ready"

step "Installing Windows components (takes a few minutes)"
VERBS=(win10 vcrun2022 corefonts)
[ "${WITH_DOTNET:-0}" = 1 ] && VERBS+=(dotnet48)
WINEDEBUG=-all winetricks -q --unattended "${VERBS[@]}"
ok "${VERBS[*]}"

# OpenGL through EGL instead of GLX (Wine's default since 11.x, set explicitly).
# With GLX all threads share ONE Xlib connection; FL's OpenGL UI and NVIDIA's GL
# lock can deadlock there - the UI freezes while audio keeps playing.
WINEDEBUG=-all wine reg add 'HKCU\Software\Wine\X11 Driver' /v UseEGL /t REG_SZ /d Y /f >/dev/null 2>&1
ok "UseEGL = Y (protection against the GL deadlock)"
wineserver -w
