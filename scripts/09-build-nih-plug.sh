#!/bin/bash
# ============================================================
# Schritt 9 (optional): nih-plug-Plugins mit GUI für Wine/EGL neu bauen
#
# WARUM: Die offiziellen Builds von Spectral Compressor, Diopser und
# Crisp verlangen ein OpenGL-Pixelformat mit 8 Bit Alpha. NVIDIAs EGL
# bietet das nur mit 32-Bit-ARGB-Visual an, das Wine für Fenster nicht
# zulässt. baseview findet kein Format, panict in einer Funktion, die
# nicht abwickeln darf, und reißt FL Studio mit (c0000409).
#
# LÖSUNG: baseview fällt auf ein Format ohne Alpha zurück
# (patches/baseview-alpha-fallback.patch). Die Editoren sind deckend,
# es geht nichts verloren.
#
# Voraussetzungen: git, rustup, mingw-w64-gcc
# Ergebnis:        build/nih-plug-src/nih-plug/target/bundled/*.vst3 / *.clap
# ============================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$REPO_DIR/build/nih-plug-src}"
if [ $# -gt 0 ]; then PLUGINS=("$@"); else PLUGINS=(spectral_compressor diopser crisp); fi
# Diopser braucht portable_simd; aktuelle Nightlies haben die API geändert.
TOOLCHAIN="${TOOLCHAIN:-nightly-2025-06-01}"
# Getesteter Upstream-Stand; neuere Commits brauchen eine neuere Nightly.
NIH_PLUG_REV="${NIH_PLUG_REV:-28b149ec}"
BASEVIEW_URL="https://github.com/john-parton/baseview.git"
BASEVIEW_BRANCH="bugfix/srgb-not-supported"

echo "=== nih-plug mit baseview-Alpha-Fallback bauen ==="
mkdir -p "$WORK"
cd "$WORK"

if [ ! -d baseview ]; then
    git clone -q --branch "$BASEVIEW_BRANCH" "$BASEVIEW_URL" baseview
fi
if ! grep -q 'falling back to alpha 0' baseview/src/gl/win.rs; then
    git -C baseview apply "$REPO_DIR/patches/baseview-alpha-fallback.patch"
fi
echo "[1/4] baseview vorbereitet ($(git -C baseview rev-parse --short HEAD) + Patch)"

if [ ! -d nih-plug ]; then
    git clone -q https://github.com/robbert-vdh/nih-plug.git nih-plug
    git -C nih-plug checkout -q "$NIH_PLUG_REV"
fi
# Beide Stellen auf denselben lokalen baseview-Baum lenken, sonst landen
# zwei baseview-Versionen im Abhängigkeitsgraph (Typfehler E0308).
BV_PATH="$WORK/baseview"
sed -i -E "s#^baseview = \{ git = \"$BASEVIEW_URL\", branch = \"$BASEVIEW_BRANCH\" \}#baseview = { path = \"$BV_PATH\" }#" nih-plug/Cargo.toml
sed -i -E "s#^baseview = \{ git = \"$BASEVIEW_URL\", branch = \"$BASEVIEW_BRANCH\" \}#baseview = { path = \"$BV_PATH\", features = [\"opengl\"] }#" nih-plug/nih_plug_vizia/Cargo.toml
if ! grep -q "path = \"$BV_PATH\"" nih-plug/Cargo.toml; then
    printf '\n[patch."https://github.com/RustAudio/baseview.git"]\nbaseview = { path = "%s" }\n' "$BV_PATH" >> nih-plug/Cargo.toml
fi
echo "[2/4] nih-plug auf lokalen baseview umgestellt"

rustup toolchain install "$TOOLCHAIN" --profile minimal --target x86_64-pc-windows-gnu >/dev/null
echo "[3/4] Toolchain $TOOLCHAIN bereit"

ARGS=()
for p in "${PLUGINS[@]}"; do ARGS+=(-p "$p"); done
(cd nih-plug && cargo +"$TOOLCHAIN" xtask bundle "${ARGS[@]}" --release --target x86_64-pc-windows-gnu)
echo "[4/4] Fertig: $WORK/nih-plug/target/bundled/"
echo ""
echo "Einspielen (FL Studio vorher beenden, Originale sichern):"
echo "  VST3: \$WINEPREFIX/drive_c/Program Files/Common Files/VST3/"
echo "  CLAP: \$WINEPREFIX/drive_c/Program Files/Common Files/CLAP/"
echo "Prüfen ohne FL: tools/clap_guitest.exe <plugin.clap> 10"
