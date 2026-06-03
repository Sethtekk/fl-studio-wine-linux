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
# ACHTUNG: Jedes wine-staging-Update ueberschreibt
# /usr/bin/wineserver -> dieses Script danach erneut ausfuehren.
# ============================================================
set -e
source "$(dirname "$0")/config.sh"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
POOLFIX="$REPO_DIR/assets/wineserver-poolfix"
EXPECTED_MD5=da13506f620709fb5dab7d11186c6a93
TARGET=/usr/bin/wineserver

echo "=== wineserver Pool-Fix anwenden ==="

if [ ! -f "$POOLFIX" ]; then
    echo "FEHLER: $POOLFIX nicht gefunden! Repository vollstaendig geklont?"
    exit 1
fi

if [ "$(md5sum "$POOLFIX" | cut -d' ' -f1)" != "$EXPECTED_MD5" ]; then
    echo "FEHLER: assets/wineserver-poolfix hat unerwarteten MD5 – Abbruch."
    exit 1
fi

# Schon aktuell?
if [ "$(md5sum "$TARGET" 2>/dev/null | cut -d' ' -f1)" = "$EXPECTED_MD5" ]; then
    echo "[i] $TARGET ist bereits der Pool-Fix – nichts zu tun."
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
