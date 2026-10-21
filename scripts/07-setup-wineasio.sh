#!/bin/bash
# ============================================================
# Step 7 (optional): WineASIO – low latency and all channels of
# your audio interface in FL Studio
#
# Without it Wine offers FL only 2 inputs (WASAPI). WineASIO talks to
# PipeWire's JACK layer directly. The FL launcher then pins PipeWire's
# quantum to WineASIO's buffer size while FL runs; a mismatch makes
# playback run at the wrong speed (e.g. 4x too slow).
#
# If no WineASIO is installed, it is built from source (needs a C compiler,
# Wine's winegcc and the JACK headers - installed here for your distro).
#
#   ASIO_INPUTS=4 ASIO_OUTPUTS=4 ASIO_BUFFER=512 bash scripts/07-setup-wineasio.sh
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/config.sh"

INPUTS="${ASIO_INPUTS:-16}"
OUTPUTS="${ASIO_OUTPUTS:-16}"
BUFSIZE="${ASIO_BUFFER:-512}"    # 512 @ 48 kHz = 10.7 ms
WINEASIO_VERSION="${WINEASIO_VERSION:-v1.3.0}"

step "Setting up WineASIO"

# Wine's library dir = the one that holds x86_64-unix/ntdll.so
find_wine_libdir() {
    local w d
    w="$(readlink -f "$(type -P wine)")"
    for d in "$(dirname "$w")/../lib/wine" "$(dirname "$w")/../lib64/wine" \
             /usr/lib/wine /usr/lib64/wine /usr/lib/x86_64-linux-gnu/wine \
             /opt/wine-staging/lib/wine /opt/wine-staging/lib64/wine; do
        [ -f "$d/x86_64-unix/ntdll.so" ] && { readlink -f "$d"; return; }
    done
}
LIBDIR="$(find_wine_libdir)"
[ -n "$LIBDIR" ] || die "Could not find Wine's library directory."
info "Wine libraries: $LIBDIR"

build_wineasio() {
    detect_distro
    info "Installing build dependencies ..."
    case "$DISTRO_FAMILY" in
        arch)   as_root pacman -S --needed --noconfirm base-devel git pipewire-jack ;;
        debian) as_root apt-get install -y build-essential git libjack-jackd2-dev wine-staging-dev ;;   # WineHQ package
        fedora) as_root dnf install -y gcc make git wine-devel pipewire-jack-audio-connection-kit-devel ;;
        suse)   as_root zypper --non-interactive install gcc make git wine-devel pipewire-libjack-0_3-devel ;;
        *)      die "Install a C compiler, git, winegcc (wine development package) and the JACK headers, then run this again." ;;
    esac
    local src; src="$(mktemp -d)"
    git clone --quiet --depth 1 --branch "$WINEASIO_VERSION" https://github.com/wineasio/wineasio.git "$src/wineasio"
    info "Building WineASIO $WINEASIO_VERSION ..."
    # WineHQ packages keep winegcc/winebuild in /opt/wine-*/bin
    PATH="/opt/wine-staging/bin:/opt/wine-devel/bin:/opt/wine-stable/bin:$PATH" \
        make -C "$src/wineasio" 64 >"$src/build.log" 2>&1 || { tail -20 "$src/build.log"; die "WineASIO build failed (log above)."; }
    as_root install -m 644 "$src/wineasio/build64/wineasio64.dll"    "$LIBDIR/x86_64-windows/wineasio64.dll"
    as_root install -m 755 "$src/wineasio/build64/wineasio64.dll.so" "$LIBDIR/x86_64-unix/wineasio64.dll.so"
    rm -rf "$src"
    ok "WineASIO built and installed into $LIBDIR"
}

if [ ! -f "$LIBDIR/x86_64-unix/wineasio64.dll.so" ]; then
    detect_distro
    if [ "$DISTRO_FAMILY" = arch ] && { command -v paru >/dev/null || command -v yay >/dev/null; }; then
        helper="$(command -v paru || command -v yay)"
        info "WineASIO comes from the AUR: $helper -S wineasio"
        "$helper" -S --needed wineasio
    else
        ask "WineASIO is not installed. Build it from source now?" y || die "Cancelled."
        build_wineasio
    fi
fi
[ -f "$LIBDIR/x86_64-unix/wineasio64.dll.so" ] || die "WineASIO is still missing in $LIBDIR."
ok "WineASIO found"

# The PE stub's internal name is "wineasio.dll", so Wine looks for
# wineasio.dll.so - add that name, or CoCreateInstance fails silently.
if [ ! -e "$LIBDIR/x86_64-unix/wineasio.dll.so" ]; then
    as_root ln -s wineasio64.dll.so "$LIBDIR/x86_64-unix/wineasio.dll.so"
    ok "compat link wineasio.dll.so -> wineasio64.dll.so"
fi

cp "$LIBDIR/x86_64-windows/wineasio64.dll" "$SYS32/wineasio64.dll"
cp "$LIBDIR/x86_64-windows/wineasio64.dll" "$SYS32/wineasio.dll"
export WINEDEBUG=-all
wine regsvr32 /s "$LIBDIR/x86_64-unix/wineasio64.dll.so" >/dev/null 2>&1 \
    || wine regsvr32 /s wineasio64.dll >/dev/null 2>&1
wine reg add 'HKCU\Software\Wine\DllOverrides' /v wineasio64 /d builtin /f >/dev/null 2>&1
wine reg add 'HKCU\Software\Wine\DllOverrides' /v wineasio /d native,builtin /f >/dev/null 2>&1
grep -qi wineasio "$WINEPREFIX/system.reg" || die "Registration failed (no WineASIO entry in system.reg)."
ok "registered in the prefix"

reg="$(mktemp --suffix=.reg)"
cat > "$reg" <<EOF
REGEDIT4

[HKEY_CURRENT_USER\\Software\\Wine\\WineASIO]
"Autostart server"=dword:00000000
"Connect to hardware"=dword:00000001
"Fixed buffersize"=dword:00000001
"Number of inputs"=dword:$(printf '%08x' "$INPUTS")
"Number of outputs"=dword:$(printf '%08x' "$OUTPUTS")
"Preferred buffersize"=dword:$(printf '%08x' "$BUFSIZE")
EOF
wine regedit "$reg" >/dev/null 2>&1
rm -f "$reg"
wineserver -w
ok "$INPUTS inputs / $OUTPUTS outputs / buffer $BUFSIZE samples"

echo
info "In FL Studio: Options → Audio Settings → Device → WineASIO"
info "The launcher pins PipeWire's quantum to $BUFSIZE while FL runs."
