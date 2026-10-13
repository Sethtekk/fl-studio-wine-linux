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

# --- passendes Binary + MD5 aus dem Manifest waehlen ---
MANIFEST="$REPO_DIR/assets/poolfix-md5.txt"
NAME="wineserver-poolfix-$WV-staging"
[ "$WV" = "11.9" ] && NAME="wineserver-poolfix"
POOLFIX="$REPO_DIR/assets/$NAME"
EXPECTED_MD5="$(awk -v n="$NAME" '$2 == n {print $1}' "$MANIFEST" 2>/dev/null)"
if [ -z "$EXPECTED_MD5" ]; then
    echo "FEHLER: Fuer Wine '${WV_RAW:-?}' liegt kein vorgebautes Pool-Fix-Binary bei."
    echo "        Vorhanden: $(awk '{v=$2; sub(/^wineserver-poolfix-?/, "", v); sub(/-staging$/, "", v); printf "%s ", (v == "" ? "11.9" : v)}' "$MANIFEST")"
    echo "        Automatisch bauen und einspielen: sudo bash scripts/pacman-hook-apply.sh"
    exit 1
fi

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
