#!/bin/bash
# ============================================================
# Step 1: install Wine (Staging preferred) and helper tools
#
# Supported:
#   Arch family   Arch, CachyOS, EndeavourOS, Manjaro   -> wine-staging (extra)
#   Debian family Debian 12/13, Ubuntu 24.04+, Mint 22+, Pop!_OS, Zorin
#                                                        -> winehq-staging (WineHQ repo)
#   Fedora        Fedora 41+, Nobara                     -> wine (Fedora repo)
#   openSUSE      Tumbleweed, Leap 16                    -> wine (openSUSE repo)
#
# Usage: bash scripts/01-install-wine.sh [--dry-run]
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
run() { if [ "$DRY" = 1 ]; then echo "    + $*"; else "$@"; fi; }

detect_distro
step "Installing Wine for: $DISTRO_NAME ($DISTRO_FAMILY)"

# Tools every distro needs: winetricks (+cabextract), python3, curl,
# pipewire's JACK library (WineASIO), icoutils/imagemagick (menu icons).
case "$DISTRO_FAMILY" in
arch)
    # wine-staging is a WoW64 build in [extra] - no [multilib] needed anymore.
    run as_root pacman -Syu --needed --noconfirm \
        wine-staging wine-mono wine-gecko winetricks cabextract \
        python curl pipewire-jack icoutils imagemagick samba
    ;;
debian)
    [ -n "$DISTRO_CODENAME" ] || die "Could not determine the release codename (/etc/os-release)."
    # Distro wine packages are far too old (Ubuntu 24.04: wine 9.0) -> WineHQ repository.
    run as_root apt-get update
    run as_root apt-get install -y curl gpg ca-certificates
    url="https://dl.winehq.org/wine-builds/$DISTRO_BASE/dists/$DISTRO_CODENAME/winehq-$DISTRO_CODENAME.sources"
    if [ "$DRY" = 0 ] && ! curl -fsIL "$url" >/dev/null; then
        die "WineHQ has no packages for '$DISTRO_CODENAME' ($url). Use a newer release."
    fi
    run as_root dpkg --add-architecture i386
    run as_root mkdir -pm755 /etc/apt/keyrings
    if [ "$DRY" = 1 ]; then
        echo "    + curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor > /etc/apt/keyrings/winehq-archive.key"
    else
        curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | as_root gpg --dearmor --yes -o /etc/apt/keyrings/winehq-archive.key
    fi
    run as_root curl -fsSL -o "/etc/apt/sources.list.d/winehq-$DISTRO_CODENAME.sources" "$url"
    run as_root apt-get update
    run as_root apt-get install -y --install-recommends winehq-staging
    # winetricks is in Debian's "contrib" section, which is often disabled -> see below
    run as_root apt-get install -y cabextract unzip python3 curl \
        pipewire-jack icoutils imagemagick
    run as_root apt-get install -y winetricks || true
    ;;
fedora)
    run as_root dnf install -y wine winetricks cabextract python3 curl \
        pipewire-jack-audio-connection-kit icoutils ImageMagick
    ;;
suse)
    run as_root zypper --non-interactive install wine winetricks cabextract python3 curl \
        pipewire-libjack-0_3 icoutils ImageMagick
    ;;
*)
    warn "Unknown distribution. Install these yourself, then continue with step 2:"
    info "wine (>= 10, Staging recommended), winetricks, cabextract, python3, curl,"
    info "pipewire-jack, icoutils, imagemagick"
    exit 1
    ;;
esac

[ "$DRY" = 1 ] && exit 0

# winetricks from upstream if the distro has none (Debian without contrib)
if [ -z "$(type -P winetricks)" ] && [ ! -x "$HOME/.local/bin/winetricks" ]; then
    mkdir -p "$HOME/.local/bin"
    curl -fsSL -o "$HOME/.local/bin/winetricks" \
        https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
    chmod +x "$HOME/.local/bin/winetricks"
    ok "winetricks installed to ~/.local/bin (upstream)"
fi

v="$(wine_version)"
[ -n "$v" ] || die "wine is not on PATH after the installation."
ok "$(wine --version)"
if [ "${v%%.*}" -lt 10 ]; then
    warn "Wine $v is old. The patches are tested with Wine 11.x - expect problems."
fi
wine_is_staging || info "Note: this is not Wine Staging. Everything works except the optional pool fix binaries (they are built for Staging)."
