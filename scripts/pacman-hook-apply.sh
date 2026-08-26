#!/bin/bash
# ============================================================
# Pacman-Hook-Applier (laeuft als ROOT im Hook, oder via sudo manuell)
# Spielt den passenden Pool-Fix-wineserver (Pool 32768) fuer die
# AKTUELL installierte wine-staging-Version ein.
# Version-generisch: sucht assets/wineserver-poolfix-<VER>-staging.
# Fehlt es (neue Wine-Version) -> laute Warnung + Hinweis zum Neu-Bauen,
# beendet aber mit 0 (bricht die pacman-Transaktion NICHT ab).
# ============================================================
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$REPO/assets"
MANIFEST="$ASSETS/poolfix-md5.txt"
TARGET=/usr/bin/wineserver

VER="$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
if [ -z "$VER" ]; then
    echo "[poolfix] Wine-Version nicht erkennbar - uebersprungen."
    exit 0
fi
BIN="$ASSETS/wineserver-poolfix-$VER-staging"

if [ ! -f "$BIN" ]; then
    echo "======================================================================"
    echo "[poolfix] ACHTUNG: kein Pool-Fix-wineserver fuer wine-staging $VER !"
    echo "[poolfix] /usr/bin/wineserver ist jetzt STOCK (Pool 512)."
    echo "[poolfix]  -> FL-Studio Fehler 1411 bei grossen Projekten moeglich."
    echo "[poolfix] NEU BAUEN:  bash ~/wine-build/build-wineserver-poolfix.sh"
    echo "[poolfix] DANN:       sudo bash $REPO/scripts/pacman-hook-apply.sh"
    echo "======================================================================"
    exit 0
fi

EXP="$(awk -v f="wineserver-poolfix-$VER-staging" '$2==f{print $1}' "$MANIFEST" 2>/dev/null)"
GOT="$(md5sum "$BIN" | awk '{print $1}')"
if [ -n "$EXP" ] && [ "$EXP" != "$GOT" ]; then
    echo "[poolfix] FEHLER: $BIN md5 $GOT != erwartet $EXP - Abbruch."
    exit 1
fi

if [ "$(md5sum "$TARGET" 2>/dev/null | awk '{print $1}')" = "$GOT" ]; then
    echo "[poolfix] wineserver ist bereits der Pool-Fix fuer $VER - nichts zu tun."
    exit 0
fi

# Root noetig zum Schreiben nach /usr/bin
SUDO=""
[ "$EUID" -ne 0 ] && SUDO="sudo"

# --- Backup des Stock-Binaries, VERSIONSBEHAFTET ---------------------------
# Frueher: [ -f "$TARGET.orig" ] || cp ...  -> das Backup wurde genau EINMAL
# angelegt und veraltete danach fuer immer. Ein Rollback darauf haette einen
# Protokoll-Mismatch gegeben (jede Wine-Version hat ihr eigenes Protokoll).
# Jetzt: ein Backup pro Wine-Version, und nur wenn das aktuelle Ziel wirklich
# Stock ist - also KEIN bekannter Pool-Fix aus dem Manifest.
TARGET_MD5="$(md5sum "$TARGET" 2>/dev/null | awk '{print $1}')"
BACKUP="$TARGET.stock-$VER"
if [ -f "$BACKUP" ]; then
    :
elif awk '{print $1}' "$MANIFEST" 2>/dev/null | grep -qx "$TARGET_MD5"; then
    echo "[poolfix] Hinweis: /usr/bin/wineserver ist bereits ein Pool-Fix - kein Stock-Backup moeglich."
else
    $SUDO cp -a "$TARGET" "$BACKUP"
    echo "[poolfix] Stock-Binary gesichert: $BACKUP (md5 $TARGET_MD5)"
fi

$SUDO cp "$BIN" "$TARGET"
echo "[poolfix] Pool-Fix fuer wine-staging $VER eingespielt (md5 $GOT)."
[ -f "$BACKUP" ] && echo "[poolfix] Rollback-Ziel: $BACKUP"
exit 0
