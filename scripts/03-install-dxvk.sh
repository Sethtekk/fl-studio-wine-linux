#!/bin/bash
# ============================================================
# Schritt 3: DXVK installieren (DirectX 9/10/11 → Vulkan)
# DXVK verhindert Grafik-Ruckler und verbessert Stabilität.
# ============================================================
set -e
source "$(dirname "$0")/config.sh"

echo "=== DXVK Installation ==="

# Aktuelle DXVK-Version von GitHub herunterladen
DXVK_VERSION="2.7.1"
DXVK_URL="https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz"
TMPDIR=$(mktemp -d)

echo "Lade DXVK ${DXVK_VERSION} herunter..."
curl -L "$DXVK_URL" -o "$TMPDIR/dxvk.tar.gz"
tar xf "$TMPDIR/dxvk.tar.gz" -C "$TMPDIR"

# DXVK ins Prefix installieren
echo "Installiere DXVK ins Prefix..."
WINEPREFIX="$WINEPREFIX" bash "$TMPDIR/dxvk-${DXVK_VERSION}/setup_dxvk.sh" install

# DXVK-Konfiguration kopieren
DXVK_CONF_DIR="$HOME/.config/dxvk"
mkdir -p "$DXVK_CONF_DIR"
cp "$(dirname "$0")/../config/dxvk.conf" "$DXVK_CONF_DIR/dxvk.conf"
echo "DXVK-Config nach $DXVK_CONF_DIR/dxvk.conf kopiert."

rm -rf "$TMPDIR"

echo ""
echo "DXVK ${DXVK_VERSION} installiert."
echo "=== Fertig! Weiter mit: bash scripts/04-apply-d2d1-patch.sh ==="
