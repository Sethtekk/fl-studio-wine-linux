#!/bin/bash
# ============================================================
# Schritt 8: wineserver Shared-Session-Pool-Fix anwenden
#
# WARUM: Wine's wineserver dimensioniert den gemeinsamen
# Session-Speicher (Fenster + Klassen + Queues) initial auf
# nur 512 Objekte. Grosse FL-Projekte (viele Tracks/Plugins)
# sprengen das Limit → Fehler 1411 "Klasse existiert nicht"
# bzw. Haenger beim Projektwechsel.
#
# DIE LOESUNG: Ein vorkompilierter wineserver mit Pool=32768
# ersetzt /usr/bin/wineserver. Details: patches/wineserver-pool-size.md
#
# WICHTIG: Pro Wine-Version ein eigenes Binary (Server-Protokoll!).
# wine-staging 11.10 = Protokoll 943, 11.9 = 942. Ein unpassendes
# Binary gibt "wine client error:0: version mismatch". Dieses Script
# erkennt die installierte Version und waehlt das richtige Binary.
#
# ACHTUNG: Jedes wine-staging-Update ueberschreibt
# /usr/bin/wineserver -> dieses Script danach erneut ausfuehren.
# ============================================================
set -e
source "$(dirname "$0")/config.sh"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET=/usr/bin/wineserver

# --- Wine-Version erkennen (z.B. "wine-11.10 (Staging)" -> 11.10) ---
WV_RAW="$(wine --version 2>/dev/null || true)"
WV="$(printf '%s' "$WV_RAW" | grep -oE '[0-9]+\.[0-9]+' | head -1)"

echo "=== wineserver Pool-Fix anwenden ==="
echo "[i] Installierte Wine-Version: ${WV_RAW:-unbekannt} (erkannt: ${WV:-?})"

# --- passendes Binary + MD5 zur Version waehlen ---
case "$WV" in
    11.9)
        POOLFIX="$REPO_DIR/assets/wineserver-poolfix"
        EXPECTED_MD5=da13506f620709fb5dab7d11186c6a93
        ;;
    11.10)
        POOLFIX="$REPO_DIR/assets/wineserver-poolfix-11.10-staging"
        EXPECTED_MD5=2cd976da97a88f0d4f9cba592fe18d3f
        ;;
    11.11)
        POOLFIX="$REPO_DIR/assets/wineserver-poolfix-11.11-staging"
        EXPECTED_MD5=337819d33dfaf98620be030a24626163
        ;;
    11.12)
        POOLFIX="$REPO_DIR/assets/wineserver-poolfix-11.12-staging"
        EXPECTED_MD5=6919781269e83923d784e28a2234a750
        ;;
    *)
        echo "FEHLER: Fuer Wine '${WV_RAW:-?}' liegt kein vorgebautes Pool-Fix-Binary bei."
        echo "        Vorhanden: 11.9, 11.10, 11.11 (Staging). Neu bauen: patches/wineserver-pool-size.md (Variante B)."
        exit 1
        ;;
esac

echo "[i] Passendes Binary: $(basename "$POOLFIX") (MD5 $EXPECTED_MD5)"

if [ ! -f "$POOLFIX" ]; then
    echo "FEHLER: $POOLFIX nicht gefunden! Repository vollstaendig geklont?"
    exit 1
fi

if [ "$(md5sum "$POOLFIX" | cut -d' ' -f1)" != "$EXPECTED_MD5" ]; then
    echo "FEHLER: $(basename "$POOLFIX") hat unerwarteten MD5 – Abbruch."
    exit 1
fi

# Schon aktuell?
if [ "$(md5sum "$TARGET" 2>/dev/null | cut -d' ' -f1)" = "$EXPECTED_MD5" ]; then
    echo "[i] $TARGET ist bereits der passende Pool-Fix – nichts zu tun."
    exit 0
fi

# Original einmalig sichern (nicht ueberschreiben, falls schon vorhanden)
if [ ! -f "$TARGET.orig" ]; then
    sudo cp -a "$TARGET" "$TARGET.orig"
    echo "[1/2] Original gesichert: $TARGET.orig"
else
    echo "[1/2] Backup $TARGET.orig existiert bereits – bleibt unangetastet."
fi

sudo cp "$POOLFIX" "$TARGET"
echo "[2/2] Pool-Fix nach $TARGET kopiert."

echo ""
echo "Verifizierung:"
echo "  MD5:      $(md5sum "$TARGET" | cut -d' ' -f1)"
echo "  Erwartet: $EXPECTED_MD5"
echo ""
echo "=== wineserver Pool-Fix erfolgreich angewendet! ==="
echo "Hinweis: Nach jedem wine-staging-Update erneut ausfuehren."
