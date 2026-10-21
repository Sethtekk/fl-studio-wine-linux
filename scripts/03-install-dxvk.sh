#!/bin/bash
# ============================================================
# Step 3: install DXVK (Direct3D 9/10/11 -> Vulkan) into the prefix.
# Needs a working Vulkan driver (NVIDIA, or Mesa RADV/ANV).
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/config.sh"

DXVK_VERSION="${DXVK_VERSION:-2.7.1}"
step "Installing DXVK $DXVK_VERSION"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 3 -o "$TMP/dxvk.tar.gz" \
    "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz"
tar xf "$TMP/dxvk.tar.gz" -C "$TMP"
D="$TMP/dxvk-$DXVK_VERSION"

# Same as DXVK's former setup script: copy the DLLs, set native overrides.
for dll in d3d8 d3d9 d3d10core d3d11 dxgi; do
    cp "$D/x64/$dll.dll" "$SYS32/$dll.dll"
    cp "$D/x32/$dll.dll" "$WINEPREFIX/drive_c/windows/syswow64/$dll.dll"
    WINEDEBUG=-all wine reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /d native /f >/dev/null 2>&1
done
ok "DXVK DLLs installed (64 + 32 bit)"

mkdir -p "$HOME/.config/dxvk"
cp "$REPO_DIR/config/dxvk.conf" "$HOME/.config/dxvk/dxvk.conf"
ok "config: ~/.config/dxvk/dxvk.conf"
