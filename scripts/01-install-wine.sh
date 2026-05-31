#!/bin/bash
# ============================================================
# Schritt 1: Wine Staging + Abhängigkeiten installieren
# Getestet auf: CachyOS, Manjaro, EndeavourOS, Arch Linux
# ============================================================
set -e

echo "=== Wine Staging Installation ==="

# multilib prüfen
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "FEHLER: [multilib] ist in /etc/pacman.conf nicht aktiviert."
    echo "Öffne /etc/pacman.conf, entferne das # vor [multilib] und der folgenden Zeile."
    exit 1
fi

# Pakete installieren
sudo pacman -Syu --needed \
    wine-staging \
    wine-mono \
    winetricks \
    lib32-glib2 \
    lib32-libpulse \
    lib32-alsa-lib \
    lib32-alsa-plugins \
    lib32-mpg123 \
    lib32-openal \
    lib32-libjpeg-turbo \
    lib32-libpng \
    lib32-giflib \
    lib32-libtiff \
    lib32-libldap \
    lib32-libxcomposite \
    lib32-libxinerama \
    lib32-ncurses \
    lib32-opencl-icd-loader \
    lib32-libxslt \
    lib32-fontconfig \
    lib32-freetype2 \
    lib32-gnutls \
    lib32-libva \
    samba \
    dosbox

echo ""
echo "Wine Version:"
wine --version
echo ""
echo "=== Fertig! Weiter mit: bash scripts/02-setup-prefix.sh ==="
