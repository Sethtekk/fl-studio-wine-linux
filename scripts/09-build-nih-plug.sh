#!/bin/bash
# ============================================================
# Step 9 (optional): rebuild the nih-plug plugins with GUI for Wine/EGL
#
# WHY: The official builds of Spectral Compressor, Diopser and Crisp
# request an OpenGL pixel format with 8-bit alpha. NVIDIA's EGL only
# offers that with a 32-bit ARGB visual, which Wine does not allow for
# windows. baseview finds no format, panics inside a function that must
# not unwind, and takes FL Studio down with it (c0000409).
#
# FIX: baseview falls back to a format without alpha
# (patches/baseview-alpha-fallback.patch). The editors are opaque, so
# nothing is lost.
#
# Requirements: git, rustup, mingw-w64-gcc
# Output:       build/nih-plug-src/nih-plug/target/bundled/*.vst3 / *.clap
# ============================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$REPO_DIR/build/nih-plug-src}"
if [ $# -gt 0 ]; then PLUGINS=("$@"); else PLUGINS=(spectral_compressor diopser crisp); fi
# Diopser needs portable_simd; current nightlies have changed that API.
TOOLCHAIN="${TOOLCHAIN:-nightly-2025-06-01}"
# Tested upstream revision; newer commits need a newer nightly.
NIH_PLUG_REV="${NIH_PLUG_REV:-28b149ec}"
BASEVIEW_URL="https://github.com/john-parton/baseview.git"
BASEVIEW_BRANCH="bugfix/srgb-not-supported"

echo "=== Building nih-plug with the baseview alpha fallback ==="
mkdir -p "$WORK"
cd "$WORK"

if [ ! -d baseview ]; then
    git clone -q --branch "$BASEVIEW_BRANCH" "$BASEVIEW_URL" baseview
fi
if ! grep -q 'falling back to alpha 0' baseview/src/gl/win.rs; then
    git -C baseview apply "$REPO_DIR/patches/baseview-alpha-fallback.patch"
fi
echo "[1/4] baseview ready ($(git -C baseview rev-parse --short HEAD) + patch)"

if [ ! -d nih-plug ]; then
    git clone -q https://github.com/robbert-vdh/nih-plug.git nih-plug
    git -C nih-plug checkout -q "$NIH_PLUG_REV"
fi
# Point both references at the same local baseview tree, otherwise two
# baseview versions end up in the dependency graph (type error E0308).
BV_PATH="$WORK/baseview"
sed -i -E "s#^baseview = \{ git = \"$BASEVIEW_URL\", branch = \"$BASEVIEW_BRANCH\" \}#baseview = { path = \"$BV_PATH\" }#" nih-plug/Cargo.toml
sed -i -E "s#^baseview = \{ git = \"$BASEVIEW_URL\", branch = \"$BASEVIEW_BRANCH\" \}#baseview = { path = \"$BV_PATH\", features = [\"opengl\"] }#" nih-plug/nih_plug_vizia/Cargo.toml
if ! grep -q "path = \"$BV_PATH\"" nih-plug/Cargo.toml; then
    printf '\n[patch."https://github.com/RustAudio/baseview.git"]\nbaseview = { path = "%s" }\n' "$BV_PATH" >> nih-plug/Cargo.toml
fi
echo "[2/4] nih-plug switched to the local baseview"

rustup toolchain install "$TOOLCHAIN" --profile minimal --target x86_64-pc-windows-gnu >/dev/null
echo "[3/4] Toolchain $TOOLCHAIN ready"

ARGS=()
for p in "${PLUGINS[@]}"; do ARGS+=(-p "$p"); done
(cd nih-plug && cargo +"$TOOLCHAIN" xtask bundle "${ARGS[@]}" --release --target x86_64-pc-windows-gnu)
echo "[4/4] Done: $WORK/nih-plug/target/bundled/"
echo ""
echo "To install (quit FL Studio first, keep a copy of the originals):"
echo "  VST3: \$WINEPREFIX/drive_c/Program Files/Common Files/VST3/"
echo "  CLAP: \$WINEPREFIX/drive_c/Program Files/Common Files/CLAP/"
echo "Test without FL: tools/clap_guitest.exe <plugin.clap> 10"
