#!/bin/bash
# ============================================================
# Health check. Prints what works and what doesn't - paste the
# output into a GitHub issue when you ask for help.
#   bash scripts/doctor.sh
# ============================================================
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/config.sh"

PASS=0; FAIL=0
good() { ok "$*"; PASS=$((PASS+1)); }
bad()  { echo "    ${C_RED}✘${C_OFF} $*"; FAIL=$((FAIL+1)); }
hint() { echo "      → $*"; }

detect_distro; detect_gpu
step "System"
info "Distribution: $DISTRO_NAME ($DISTRO_FAMILY)"
info "Kernel:       $(uname -r)"
info "GPU driver:   $GPU_VENDOR"
info "Session:      ${XDG_SESSION_TYPE:-?} / ${XDG_CURRENT_DESKTOP:-?}"
info "Repository:   $REPO_DIR ($(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo 'no git'))"

step "Wine"
if [ -n "$(wine_version)" ]; then
    good "$(wine --version)"
    [ "$(wine_version | cut -d. -f1)" -ge 10 ] || { bad "Wine older than 10"; hint "bash scripts/01-install-wine.sh"; }
else
    bad "wine not found"; hint "bash scripts/01-install-wine.sh"
fi
if [ -n "$(type -P winetricks)" ] || [ -x "$HOME/.local/bin/winetricks" ]; then good "winetricks"; else bad "winetricks missing"; fi
if command -v vulkaninfo >/dev/null; then
    vulkaninfo --summary >/dev/null 2>&1 && good "Vulkan works (needed by DXVK)" || bad "vulkaninfo fails - Vulkan driver missing?"
else
    info "vulkaninfo not installed - Vulkan not checked"
fi

step "Prefix: $WINEPREFIX"
if [ -f "$WINEPREFIX/system.reg" ]; then
    good "prefix exists"
else
    bad "no prefix"; hint "./install.sh"
fi
if cmp -s "$REPO_DIR/assets/d2d1.dll.patched" "$SYS32/d2d1.dll"; then good "patched d2d1.dll active"
else bad "d2d1.dll is not the patched one (plugin windows may freeze)"; hint "bash scripts/04-apply-d2d1-patch.sh"; fi
grep -q '"d2d1"="native,builtin"' "$WINEPREFIX/user.reg" 2>/dev/null && good "d2d1 override native,builtin" \
    || { bad "d2d1 override missing"; hint "bash scripts/04-apply-d2d1-patch.sh"; }
grep -q -a -i dxvk "$SYS32/d3d11.dll" 2>/dev/null && good "DXVK installed" \
    || { bad "DXVK missing"; hint "bash scripts/03-install-dxvk.sh"; }
if grep -q '"UseEGL"="N"' "$WINEPREFIX/user.reg" 2>/dev/null; then
    bad "UseEGL=N (GLX) - risk of UI freezes on NVIDIA"; hint "wine reg add 'HKCU\\Software\\Wine\\X11 Driver' /v UseEGL /d Y /f"
else good "OpenGL via EGL"; fi

step "Programs"
FL="$(find_fl_exe)"
if [ -n "$FL" ]; then good "$(basename "$(dirname "$FL")") installed"; else bad "FL Studio not installed"; hint "./install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe"; fi
[ -x "$HOME/.local/bin/flstudio-wine" ] && good "launcher flstudio-wine" || { bad "launcher missing"; hint "bash scripts/05-install-launchers.sh"; }
if [ -f "$USERPROFILE/AppData/Local/splice/Splice.exe" ]; then
    good "Splice installed"
    python3 -c "import json,sys;d=json.load(open(sys.argv[1]));sys.exit(d.get('upgradeState') is not None)" \
        "$SPLICE_SETTINGS/appState.json" 2>/dev/null && good "Splice state clean" \
        || info "Splice upgradeState set - the launcher repairs it on next start"
fi

step "Audio"
command -v pw-jack >/dev/null && good "PipeWire JACK (pw-jack)" || info "pw-jack missing - only needed for WineASIO"
if grep -qi wineasio "$WINEPREFIX/system.reg" 2>/dev/null; then
    good "WineASIO registered"
    buf="$(grep -i '"Preferred buffersize"' "$WINEPREFIX/user.reg" | grep -oE '[0-9a-f]{8}' | head -1)"
    [ -n "$buf" ] && info "WineASIO buffer: $((16#$buf)) samples (the launcher pins PipeWire's quantum to it)"
else
    info "WineASIO not set up (optional: bash scripts/07-setup-wineasio.sh)"
fi

step "Pool fix (optional, error 1411 in big projects)"
ws="$(readlink -f "$(type -P wineserver)" 2>/dev/null)"
if [ -n "$ws" ] && awk '{print $1}' "$REPO_DIR/assets/poolfix-md5.txt" | grep -qx "$(md5sum "$ws" | cut -d' ' -f1)"; then
    good "pool fix active ($ws)"
else
    info "not active - only needed if FL shows 'error 1411' with very large projects (docs/updating.md)"
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "${C_GREEN}${C_BOLD}All $PASS checks passed.${C_OFF}"
else echo "${C_YELLOW}${C_BOLD}$PASS passed, $FAIL failed - see the hints above.${C_OFF}"; fi
exit "$FAIL"
