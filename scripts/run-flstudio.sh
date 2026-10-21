#!/bin/bash
# ============================================================
# Starts FL Studio in the prefix with all fixes active.
# Called by ~/.local/bin/flstudio-wine and the desktop entry.
# Extra arguments are passed to FL64.exe (e.g. a .flp file).
# ============================================================
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/config.sh"

export WINEFSYNC=1 WINEESYNC=1
export WINE_LARGE_ADDRESS_AWARE=1
export STAGING_AUDIO_PERIOD=10000
# Wine's d2d1 prints a "fixme" per drawn line for JUCE plugin UIs
# (measured: 11,000 lines/s, each a write() from the UI thread).
export WINEDEBUG="${WINEDEBUG:-fixme-all}"
export DXVK_CONFIG_FILE="$HOME/.config/dxvk/dxvk.conf"
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export JACK_NO_AUDIO_RESERVATION=1

detect_gpu
if [ "$GPU_VENDOR" = nvidia ]; then
    export __GL_THREADED_OPTIMIZATIONS=0
    # GL runs through EGL (UseEGL=Y); make glvnd pick NVIDIA's EGL, not Mesa's.
    nv=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
    [ -f "$nv" ] && export __EGL_VENDOR_LIBRARY_FILENAMES="$nv"
fi

notify() {
    echo "$1: $2" >&2
    command -v notify-send >/dev/null && notify-send -a "FL Studio (Wine)" "$1" "$2" 2>/dev/null
}

FL_EXE="$(find_fl_exe)"
if [ -z "$FL_EXE" ]; then
    notify "FL Studio is not installed" "Install it with: $REPO_DIR/install.sh --fl-installer ~/Downloads/flstudio_win64_*.exe"
    exit 1
fi

# d2d1 self-heal: a prefix update (wineboot -u) can replace the patched DLL.
D2D1_REF="$REPO_DIR/assets/d2d1.dll.patched"
if [ -f "$D2D1_REF" ] && ! cmp -s "$D2D1_REF" "$SYS32/d2d1.dll"; then
    cp "$D2D1_REF" "$SYS32/d2d1.dll.new" && mv -f "$SYS32/d2d1.dll.new" "$SYS32/d2d1.dll" \
        && echo "d2d1 patch restored."
fi

# Pool fix check (only relevant once it was installed, see docs/updating.md)
if [ -f "${FLW_CONFIG_FILE%/*}/poolfix-enabled" ]; then
    ws="$(readlink -f "$(command -v wineserver)")"
    if ! awk '{print $1}' "$REPO_DIR/assets/poolfix-md5.txt" 2>/dev/null | grep -qx "$(md5sum "$ws" | cut -d' ' -f1)"; then
        notify "Pool fix missing ($(wine --version))" "Large projects may fail with error 1411. Fix: sudo bash $REPO_DIR/scripts/pacman-hook-apply.sh --build"
    fi
fi

# On exit: clean up the prefix, but never kill other programs that still use it.
cleanup() {
    # MIDI "All Notes Off" so no hardware synth keeps hanging notes
    if command -v amidi >/dev/null; then
        for port in $(amidi -l 2>/dev/null | awk 'NR>1 {print $2}'); do
            for ch in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
                amidi -p "$port" -S "B${ch} 7B 00" 2>/dev/null
            done
        done
    fi
    # A second FL start hands over to the running one and exits at once -
    # a blind "wineserver -k" would also kill that FL and Splice.
    pgrep -f 'FL64\.exe' >/dev/null 2>&1 && return
    if [ -n "${PW_PINNED:-}" ]; then
        pw-metadata -n settings 0 clock.force-quantum 0 >/dev/null
        pw-metadata -n settings 0 clock.force-rate 0 >/dev/null
    fi
    if pgrep -f 'Local\\splice\\' >/dev/null 2>&1; then
        pkill -9 -i -f 'Image-Line\\|ilbridge|ilminihost' 2>/dev/null
        return
    fi
    wineserver -k 2>/dev/null
}
trap cleanup EXIT

# Local additions that only fit your own setup (fixed routing, mixer levels
# of your interface, ...) go into this file instead of this script, so that
# `git pull` never overwrites them. It is sourced, so it sees WINEPREFIX etc.;
# put anything that waits for FL's ports in a background subshell ( ... ) &.
FLW_HOOK="${FLW_CONFIG_FILE%/*}/pre-start.sh"
# shellcheck source=/dev/null
[ -f "$FLW_HOOK" ] && source "$FLW_HOOK"

# With WineASIO, run through PipeWire's JACK layer so FL sees all channels.
# WineASIO uses a fixed buffer; if PipeWire's quantum differs, FL plays at the
# wrong speed (quantum/buffer, e.g. 2048/512 = 4x too slow). So pin quantum and
# rate while FL runs. (A config file can't do this: force-* only works at runtime.)
if command -v pw-jack >/dev/null && grep -qi 'wineasio' "$WINEPREFIX/system.reg" 2>/dev/null; then
    buf="$(grep -i '"Preferred buffersize"' "$WINEPREFIX/user.reg" | grep -oE '[0-9a-f]{8}' | head -1)"
    if [ -n "$buf" ] && command -v pw-metadata >/dev/null; then
        rate="$(pw-metadata -n settings 0 clock.rate 2>/dev/null | grep -oE "value:'[0-9]+'" | grep -oE '[0-9]+')"
        pw-metadata -n settings 0 clock.force-quantum "$((16#$buf))" >/dev/null
        [ -n "$rate" ] && pw-metadata -n settings 0 clock.force-rate "$rate" >/dev/null
        PW_PINNED=1
    fi
    pw-jack wine "$FL_EXE" "$@"
else
    wine "$FL_EXE" "$@"
fi
