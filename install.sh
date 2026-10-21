#!/bin/bash
# ============================================================
# FL Studio on Linux – one-command installer
#
#   ./install.sh                                   interactive
#   ./install.sh --fl-installer ~/Downloads/flstudio_win64_25.2.4.exe
#   ./install.sh --yes --prefix ~/fl --wineasio    unattended
#
# Run as your normal user (it asks for sudo when installing packages).
# Every step can also be run on its own: see scripts/0*.sh
# ============================================================
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
S="$REPO_DIR/scripts"
source "$S/lib/common.sh"

usage() {
    cat <<EOF
Usage: ./install.sh [options]

  --prefix DIR             Wine prefix for FL Studio (default: ~/.wine-flstudio)
  --fl-installer FILE      FL Studio installer (flstudio_win64_*.exe) to run
  --splice-installer FILE  also install Splice (SpliceSetup.exe)
  --wineasio               set up WineASIO (multi-channel audio interfaces, low latency)
  --pool-fix               Arch only: install the wineserver pool fix + update automation
  --dotnet                 also install .NET 4.8 into the prefix (slow; rarely needed)
  --skip-packages          don't install distro packages (Wine etc. already installed)
  -y, --yes                don't ask, accept the defaults
  -h, --help               this help
EOF
}

FL_INSTALLER=""; SPLICE_INSTALLER=""; WITH_ASIO=""; WITH_POOL=""; SKIP_PKGS=0
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)           WINEPREFIX="$(realpath -m "$2")"; export WINEPREFIX; shift ;;
        --fl-installer)     FL_INSTALLER="$(realpath "$2")"; shift ;;
        --splice-installer) SPLICE_INSTALLER="$(realpath "$2")"; shift ;;
        --wineasio)         WITH_ASIO=1 ;;
        --pool-fix)         WITH_POOL=1 ;;
        --dotnet)           export WITH_DOTNET=1 ;;
        --skip-packages)    SKIP_PKGS=1 ;;
        -y|--yes)           export ASSUME_YES=1 ;;
        -h|--help)          usage; exit 0 ;;
        *)                  usage; die "Unknown option: $1" ;;
    esac
    shift
done

[ "$EUID" -ne 0 ] || die "Don't run this as root - run it as your normal user (sudo is used where needed)."
[ "$(uname -m)" = x86_64 ] || die "FL Studio for Windows needs an x86_64 PC (this is $(uname -m))."
for f in "$FL_INSTALLER" "$SPLICE_INSTALLER"; do
    [ -z "$f" ] || [ -f "$f" ] || die "File not found: $f"
done

source "$S/config.sh"
detect_distro; detect_gpu

cat <<EOF

${C_BOLD}FL Studio on Linux – installer${C_OFF}

    Distribution:  $DISTRO_NAME
    GPU driver:    $GPU_VENDOR
    Wine prefix:   $WINEPREFIX
EOF
[ "$DISTRO_FAMILY" != unknown ] || warn "Unknown distribution - install Wine yourself, then use --skip-packages."
[ "$GPU_VENDOR" != nouveau ] || warn "nouveau driver: DXVK needs Vulkan; use NVIDIA's proprietary driver."
echo
ask "Continue?" y || exit 0

# ── 1. packages ──────────────────────────────────────────────
if [ "$SKIP_PKGS" = 1 ]; then
    [ -n "$(wine_version)" ] || die "--skip-packages, but wine is not installed."
    step "Skipping packages ($(wine --version))"
else
    bash "$S/01-install-wine.sh"
fi

# ── 2.–4. prefix, DXVK, d2d1 ─────────────────────────────────
if [ -f "$WINEPREFIX/system.reg" ]; then
    step "Prefix exists: $WINEPREFIX"
    info "keeping it (delete the folder for a fresh start)"
    # no Wine menu clutter from installers (see 02-setup-prefix.sh)
    WINEDEBUG=-all wine reg add 'HKCU\Software\Wine\DllOverrides' /v winemenubuilder.exe /d '' /f >/dev/null 2>&1 || true
else
    bash "$S/02-setup-prefix.sh"
fi
bash "$S/03-install-dxvk.sh"
bash "$S/04-apply-d2d1-patch.sh"

# ── FL Studio ────────────────────────────────────────────────
if [ -n "$FL_INSTALLER" ]; then
    step "Running the FL Studio installer"
    info "Click through the installer with the default settings."
    WINEDEBUG=-all wine "$FL_INSTALLER" || true
    wineserver -w
    [ -n "$(find_fl_exe)" ] && ok "installed: $(basename "$(dirname "$(find_fl_exe)")")" \
        || warn "FL64.exe not found in the prefix - did the installer finish?"
fi

# ── optional parts ───────────────────────────────────────────
if [ -z "$WITH_ASIO" ] && [ "${ASSUME_YES:-0}" != 1 ]; then
    echo
    info "WineASIO gives FL all channels of an audio interface and low latency."
    ask "Set up WineASIO?" n && WITH_ASIO=1
fi
[ "$WITH_ASIO" = 1 ] && bash "$S/07-setup-wineasio.sh"

[ -n "$SPLICE_INSTALLER" ] && bash "$S/06-setup-splice.sh" "$SPLICE_INSTALLER"

if [ "$WITH_POOL" = 1 ]; then
    [ "$DISTRO_FAMILY" = arch ] || die "--pool-fix is only automated on Arch-based systems (see docs/updating.md)."
    step "Pool fix (replaces /usr/bin/wineserver, keeps it updated)"
    sudo bash "$S/install-fl-wine-automation.sh"
    mkdir -p "$(dirname "$FLW_CONFIG_FILE")" && touch "$(dirname "$FLW_CONFIG_FILE")/poolfix-enabled"
fi

# ── launchers ────────────────────────────────────────────────
bash "$S/05-install-launchers.sh"

step "Done"
if [ -n "$(find_fl_exe)" ]; then
    info "Start FL Studio from your application menu, or run:  flstudio-wine"
else
    info "Next: install FL Studio itself:"
    info "  ./install.sh --skip-packages --fl-installer ~/Downloads/flstudio_win64_*.exe"
fi
info "Something wrong? Run:  bash scripts/doctor.sh"
