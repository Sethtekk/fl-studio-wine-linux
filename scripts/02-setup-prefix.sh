#!/bin/bash
# ============================================================
# Schritt 2: WINEPREFIX anlegen und konfigurieren
# ============================================================
set -e
source "$(dirname "$0")/config.sh"

echo "=== WINEPREFIX Setup ==="
echo "Prefix-Pfad: $WINEPREFIX"
echo ""

# Prefix erstellen
WINEARCH=win64 wine64 wineboot --init

# Windows-Version auf Windows 10 setzen (für moderne Software nötig)
WINEPREFIX="$WINEPREFIX" winetricks win10

# Wichtige Windows-Komponenten installieren
WINEPREFIX="$WINEPREFIX" winetricks \
    vcrun2019 \
    vcrun2022 \
    dotnet48 \
    corefonts

# ptrace_scope für Wine-Debugging setzen (optional, aber empfohlen)
if [ -f /proc/sys/kernel/yama/ptrace_scope ]; then
    current=$(cat /proc/sys/kernel/yama/ptrace_scope)
    if [ "$current" != "0" ]; then
        echo ""
        echo "Hinweis: ptrace_scope ist auf $current gesetzt."
        echo "Für Wine-Debugging empfohlen: sudo sysctl kernel.yama.ptrace_scope=0"
        echo "Dauerhaft: echo 'kernel.yama.ptrace_scope = 0' | sudo tee /etc/sysctl.d/10-ptrace.conf"
    fi
fi

echo ""
echo "=== Fertig! Weiter mit: bash scripts/03-install-dxvk.sh ==="
