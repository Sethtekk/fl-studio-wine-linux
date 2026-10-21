#!/bin/bash
# Shared helpers for all scripts: logging, prompts, distro and GPU detection.
# Source it, don't run it:  source "$(dirname "$0")/lib/common.sh"

if [ -t 1 ]; then
    C_BOLD=$'\e[1m'; C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_OFF=$'\e[0m'
else
    C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_OFF=""
fi

step() { echo; echo "${C_BOLD}${C_BLUE}==>${C_OFF}${C_BOLD} $*${C_OFF}"; }
info() { echo "    $*"; }
ok()   { echo "    ${C_GREEN}✔${C_OFF} $*"; }
warn() { echo "    ${C_YELLOW}!${C_OFF} $*" >&2; }
die()  { echo "${C_RED}✘ $*${C_OFF}" >&2; exit 1; }

# ask "Question?" default(y|n) -> returns 0 for yes. ASSUME_YES=1 accepts the default.
ask() {
    local q="$1" def="${2:-y}" hint reply
    [ "$def" = y ] && hint="[Y/n]" || hint="[y/N]"
    if [ "${ASSUME_YES:-0}" = 1 ] || [ ! -t 0 ]; then
        [ "$def" = y ]; return
    fi
    read -r -p "    $q $hint " reply
    reply="${reply:-$def}"
    [[ "$reply" =~ ^[YyJj] ]]
}

# Run a command as root (sudo unless we already are root).
as_root() {
    if [ "$EUID" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# Sets DISTRO_FAMILY (arch|debian|fedora|suse|unknown), DISTRO_NAME, DISTRO_CODENAME.
detect_distro() {
    DISTRO_FAMILY=unknown; DISTRO_NAME=unknown; DISTRO_CODENAME=""
    [ -r /etc/os-release ] || return 0
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_NAME="${PRETTY_NAME:-$ID}"
    local ids=" ${ID:-} ${ID_LIKE:-} "
    case "$ids" in
        *" arch "*|*" archlinux "*|*" cachyos "*|*" manjaro "*|*" endeavouros "*) DISTRO_FAMILY=arch ;;
        *" fedora "*|*" rhel "*|*" nobara "*)                                   DISTRO_FAMILY=fedora ;;
        *" opensuse"*|*" suse "*|*" sles "*)                                     DISTRO_FAMILY=suse ;;
        *" ubuntu "*)
            DISTRO_FAMILY=debian
            # Mint, Pop!_OS, Zorin, elementary ... use the Ubuntu base codename
            DISTRO_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
            DISTRO_BASE=ubuntu ;;
        *" debian "*)
            DISTRO_FAMILY=debian
            DISTRO_CODENAME="${DEBIAN_CODENAME:-${VERSION_CODENAME:-}}"
            DISTRO_BASE=debian ;;
    esac
    export DISTRO_FAMILY DISTRO_NAME DISTRO_CODENAME DISTRO_BASE
}

# Sets GPU_VENDOR (nvidia|amd|intel|unknown) from the kernel driver in use.
detect_gpu() {
    GPU_VENDOR=unknown
    if [ -r /proc/driver/nvidia/version ]; then
        GPU_VENDOR=nvidia; export GPU_VENDOR; return
    fi
    local d
    for d in /sys/class/drm/card*/device/driver; do
        [ -e "$d" ] || continue
        case "$(basename "$(readlink -f "$d")")" in
            amdgpu|radeon) GPU_VENDOR=amd; break ;;
            i915|xe)       GPU_VENDOR=intel ;;
            nouveau)       GPU_VENDOR=nouveau ;;
        esac
    done
    export GPU_VENDOR
}

# "11.19" from "wine-11.19 (Staging)"; empty if wine is missing.
wine_version() { wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1; }
wine_is_staging() { wine --version 2>/dev/null | grep -qi staging; }

# Newest installed FL Studio executable in the prefix (empty if none).
find_fl_exe() {
    local prefix="${1:-$WINEPREFIX}"
    { ls -d "$prefix/drive_c/Program Files/Image-Line/FL Studio "*/FL64.exe 2>/dev/null || true; } | sort -V | tail -1
}

# winetricks may live in ~/.local/bin (installed by step 1 on Debian)
winetricks() {
    if [ -n "$(type -P winetricks)" ]; then command winetricks "$@"
    else "$HOME/.local/bin/winetricks" "$@"; fi
}
