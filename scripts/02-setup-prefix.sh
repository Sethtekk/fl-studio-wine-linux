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

# OpenGL über EGL statt GLX (= Wine-Default seit 11.x, hier explizit gesetzt).
# Unter GLX teilen sich alle Threads EINE Xlib-Verbindung; FLs OpenGL-UI
# (SmoothAnimation-Threads) und NVIDIAs GL-Lock verklemmen sich dort zum
# Deadlock - UI friert ein, Audio laeuft weiter. Mit EGL: 0 Deadlocks in
# 6 Wochen Alltag (vorher bis zu 27 Watchdog-Eingriffe pro Tag).
WINEPREFIX="$WINEPREFIX" wine reg add "HKCU\\Software\\Wine\\X11 Driver" \
    /v UseEGL /t REG_SZ /d Y /f >/dev/null 2>&1
echo "Registry: X11 Driver\\UseEGL = Y (GL-Deadlock-Schutz)"

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
