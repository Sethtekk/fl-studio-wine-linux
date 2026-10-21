#!/bin/bash
# ============================================================
# Builds the patched crypt32.dll (patches/crypt32-authattr-order.patch)
# for one Wine version and stores it in assets/crypt32-fix/<version>/.
#
#   bash scripts/build-crypt32-fix.sh            # installed Wine version
#   bash scripts/build-crypt32-fix.sh 10.20      # any version
#
# Only the Windows-side DLL is built, so the result works for every
# distribution and for Staging and non-Staging builds of that version
# (wine-staging doesn't touch crypt32). Needs: gcc, make, flex, bison,
# curl and the MinGW cross compiler (x86_64-w64-mingw32-gcc).
# Work directory: $WINE_BUILD_DIR (default ~/wine-build).
# ============================================================
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/scripts/lib/common.sh"

VER="${1:-$(wine_version)}"
[ -n "$VER" ] || die "Wine version unknown - pass it as argument."
MAJOR="${VER%%.*}"
[ "$MAJOR" -ge 10 ] 2>/dev/null || die "Wine $VER: version 10 or newer needed."
OUT="$REPO/assets/crypt32-fix/$VER"
BR="${WINE_BUILD_DIR:-$HOME/wine-build}"
SRC="$BR/wine-$VER-crypt32src"
BLD="$BR/build-$VER-crypt32"

for t in gcc make flex bison curl x86_64-w64-mingw32-gcc; do
    command -v "$t" >/dev/null || die "$t is missing (Arch: base-devel flex bison mingw-w64-gcc; Debian/Ubuntu: build-essential flex bison gcc-mingw-w64-x86-64; Fedora: gcc make flex bison mingw64-gcc)."
done

step "Building the patched crypt32.dll for Wine $VER"
mkdir -p "$BR"
if ! xz -t "$BR/wine-$VER.tar.xz" 2>/dev/null; then
    info "downloading wine-$VER ..."
    curl -fL --retry 6 --retry-delay 10 --connect-timeout 20 -o "$BR/wine-$VER.tar.xz.part" \
        "https://dl.winehq.org/wine/source/$MAJOR.x/wine-$VER.tar.xz"
    mv "$BR/wine-$VER.tar.xz.part" "$BR/wine-$VER.tar.xz"
fi
rm -rf "$SRC" "$BLD"
mkdir -p "$SRC" "$BLD"
tar xf "$BR/wine-$VER.tar.xz" -C "$SRC" --strip-components=1
patch -d "$SRC" -p1 --quiet < "$REPO/patches/crypt32-authattr-order.patch" \
    || die "The patch doesn't apply to Wine $VER."
ok "patch applied"

info "configure (minimal, only the build tools and PE DLLs are needed) ..."
(cd "$BLD" && "$SRC/configure" --enable-win64 --enable-archs=x86_64 --without-x --without-freetype \
    --without-wayland --without-gstreamer --without-vulkan --without-opengl --without-alsa \
    --without-pulse --without-dbus --without-cups --without-sane --without-krb5 --without-gnutls \
    --without-unwind --without-usb --without-v4l2 --without-pcap --without-netapi --without-sdl \
    --without-udev --without-capi --without-gphoto --without-fontconfig --without-xkbcommon \
    > configure.log 2>&1) || { tail -20 "$BLD/configure.log"; die "configure failed."; }
info "make crypt32.dll (a few minutes) ..."
make -C "$BLD" -j"$(nproc)" dlls/crypt32/x86_64-windows/crypt32.dll > "$BLD/make.log" 2>&1 \
    || { tail -20 "$BLD/make.log"; die "build failed."; }

mkdir -p "$OUT"
x86_64-w64-mingw32-strip -o "$OUT/crypt32.dll" "$BLD/dlls/crypt32/x86_64-windows/crypt32.dll"
ok "$OUT/crypt32.dll ($(md5sum "$OUT/crypt32.dll" | cut -c1-8))"
rm -rf "$SRC" "$BLD"
