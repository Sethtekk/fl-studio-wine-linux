#!/bin/bash
# ============================================================
# Schritt 7: WineASIO einrichten – alle Eingänge in FL Studio
# ============================================================
# Voraussetzung: wineasio-Paket installiert (pacman -S wineasio)
#
# Problem: Wine's ASIO-Emulation (FL Studio ASIO) gibt immer
# nur 2 Kanäle zurück (WASAPI-Einschränkung). WineASIO
# überbrückt Wine direkt zu PipeWire/JACK → alle Hardware-
# Eingänge werden sichtbar.
# ============================================================
set -e
source "$(dirname "$0")/config.sh"

echo "=== WineASIO Setup ==="

# ── 1. Paket prüfen ─────────────────────────────────────────
if ! pacman -Q wineasio &>/dev/null; then
    echo "FEHLER: wineasio ist nicht installiert."
    echo "Bitte installieren: sudo pacman -S wineasio"
    exit 1
fi
echo "[1/6] wineasio-Paket vorhanden."

# ── 2. Packaging-Bug-Fix: fehlender Symlink ─────────────────
# Der Wine-Stub wineasio64.dll hat intern den DLL-Namen
# "wineasio.dll" eingebaut. Wine sucht deshalb nach
# wineasio.dll.so als Builtin-Library – diese existiert im
# Paket aber nicht (nur wineasio64.dll.so). Ohne diesen
# Symlink schlägt CoCreateInstance lautlos fehl.
SO_DIR="/usr/lib/wine/x86_64-unix"
if [ ! -e "$SO_DIR/wineasio.dll.so" ]; then
    echo "[2/6] Symlink fehlt – sudo benötigt..."
    sudo ln -s "$SO_DIR/wineasio64.dll.so" "$SO_DIR/wineasio.dll.so"
    echo "[2/6] Symlink erstellt: wineasio.dll.so -> wineasio64.dll.so"
else
    echo "[2/6] Symlink bereits vorhanden."
fi

# ── 3. DLL in Prefix kopieren und registrieren ──────────────
cp /usr/lib/wine/x86_64-windows/wineasio64.dll \
   "$WINEPREFIX/drive_c/windows/system32/wineasio64.dll"
cp /usr/lib/wine/x86_64-windows/wineasio64.dll \
   "$WINEPREFIX/drive_c/windows/system32/wineasio.dll"

WINEPREFIX="$WINEPREFIX" WINEDEBUG=-all \
    wine regsvr32 /s /usr/lib/wine/x86_64-unix/wineasio64.dll.so
echo "[3/6] WineASIO registriert (ASIO-Treiber + CLSID)."

# ── 4. DLL-Overrides setzen ─────────────────────────────────
WINEPREFIX="$WINEPREFIX" WINEDEBUG=-all \
    wine reg add "HKCU\Software\Wine\DllOverrides" \
    /v wineasio64 /d "builtin" /f 2>/dev/null
WINEPREFIX="$WINEPREFIX" WINEDEBUG=-all \
    wine reg add "HKCU\Software\Wine\DllOverrides" \
    /v wineasio /d "native,builtin" /f 2>/dev/null
echo "[4/6] DLL-Overrides gesetzt (wineasio64=builtin)."

# ── 5. WineASIO konfigurieren ───────────────────────────────
# Anzahl Ein-/Ausgänge ans Interface anpassen.
# UMC404HD: 4 Eingänge, 4 Ausgänge.
# Für andere Interfaces die Werte entsprechend ändern.
INPUTS=4
OUTPUTS=4
BUFSIZE=256   # Samples (Latenz: ~5.8ms @ 44100 Hz)

cat > /tmp/wineasio-setup.reg << EOF
REGEDIT4

[HKEY_CURRENT_USER\Software\Wine\WineASIO]
"Autostart server"=dword:00000000
"Connect to hardware"=dword:00000001
"Fixed buffersize"=dword:00000001
"Number of inputs"=dword:$(printf '%08x' $INPUTS)
"Number of outputs"=dword:$(printf '%08x' $OUTPUTS)
"Preferred buffersize"=dword:$(printf '%08x' $BUFSIZE)
EOF

WINEPREFIX="$WINEPREFIX" WINEDEBUG=-all \
    wine regedit /tmp/wineasio-setup.reg 2>/dev/null
rm /tmp/wineasio-setup.reg
echo "[5/6] WineASIO konfiguriert: $INPUTS In / $OUTPUTS Out / ${BUFSIZE} Samples Buffer."

# ── 6. PipeWire auf 44100 Hz konfigurieren ──────────────────
# WineASIO meldet FL Studio die JACK-Sample-Rate. PipeWire
# muss auf 44100 Hz laufen damit kein Rate-Mismatch entsteht.
PW_CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$PW_CONF_DIR"
cat > "$PW_CONF_DIR/10-sample-rate.conf" << 'EOF'
context.properties = {
    default.clock.rate          = 44100
    default.clock.allowed-rates = [ 44100 48000 ]
    default.clock.quantum       = 1024
    default.clock.min-quantum   = 32
    default.clock.max-quantum   = 2048
}
EOF
echo "[6/6] PipeWire auf 44100 Hz konfiguriert."
echo "      Neustart nötig: systemctl --user restart pipewire pipewire-pulse wireplumber"

# ── Abschluss ────────────────────────────────────────────────
echo ""
echo "=== WineASIO Setup abgeschlossen ==="
echo ""
echo "Nächste Schritte:"
echo "  1. PipeWire neu starten:"
echo "     systemctl --user restart pipewire pipewire-pulse wireplumber"
echo "  2. FL Studio starten: ~/start-flstudio.sh"
echo "  3. In FL Studio: Options → Audio Settings → ASIO → WineASIO"
echo "  4. Alle $INPUTS Eingänge deines Interfaces sind jetzt verfügbar."
echo ""
echo "HINWEIS: Input-Monitoring (grünes Lautsprecher-Symbol im Mixer)"
echo "  deaktivieren um Rückkopplungen zu vermeiden!"
