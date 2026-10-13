#!/bin/bash
# ============================================================
# Baut den Pool-Fix-wineserver (Shared-Session-Pool 512 -> 32768)
# für eine wine-staging-Version und legt ihn in assets/ ab.
#
#   bash scripts/build-wineserver-poolfix.sh          # installierte Version
#   bash scripts/build-wineserver-poolfix.sh 11.20    # beliebige Version (Vorab-Build)
#
# Läuft als normaler Benutzer. Arbeitsverzeichnis: $WINE_BUILD_DIR
# (Default ~/wine-build). Rezept: patches/wineserver-pool-size.md.
# ============================================================
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$REPO/assets"
MANIFEST="$ASSETS/poolfix-md5.txt"
VER="${1:-$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)}"
[ -n "$VER" ] || { echo "Wine-Version unbekannt"; exit 1; }
MAJOR="${VER%%.*}"
BR="${WINE_BUILD_DIR:-$HOME/wine-build}"
NAME="wineserver-poolfix-$VER-staging"
mkdir -p "$BR"
cd "$BR"

echo "# Pool-Fix-wineserver für wine-staging $VER - Start $(date)"

# --- 1) Quellcode (Download mit Wiederholungen; Netz kann kurz weg sein) ---
if ! xz -t "wine-$VER.tar.xz" 2>/dev/null; then
    echo "[1/5] Lade wine-$VER ..."
    curl -fL --retry 6 --retry-delay 10 --retry-all-errors --connect-timeout 20 \
         -o "wine-$VER.tar.xz.part" "https://dl.winehq.org/wine/source/${MAJOR}.x/wine-$VER.tar.xz"
    mv "wine-$VER.tar.xz.part" "wine-$VER.tar.xz"
fi
rm -rf "wine-$VER"
tar xf "wine-$VER.tar.xz"

# --- 2) wine-staging-Patches (bringen das Server-Protokoll auf den Staging-Stand) ---
echo "[2/5] wine-staging v$VER ..."
rm -rf "wine-staging-src-$VER"
for i in 1 2 3 4 5 6; do
    git clone --quiet --branch "v$VER" --depth 1 \
        https://gitlab.winehq.org/wine/wine-staging.git "wine-staging-src-$VER" && break
    rm -rf "wine-staging-src-$VER"
    [ "$i" -eq 6 ] && { echo "FEHLER: wine-staging v$VER nicht ladbar"; exit 1; }
    sleep 15
done
python3 "wine-staging-src-$VER/staging/patchinstall.py" --all --destdir "wine-$VER" >/dev/null

# --- 3) Pool-Patch ---
echo "[3/5] Pool 512 -> 32768 ..."
MAPC="wine-$VER/server/mapping.c"
grep -q 'sizeof(object_shm_t) \* 512' "$MAPC" || { echo "FEHLER: Pool-Zeile nicht gefunden in $MAPC"; exit 1; }
sed -i 's/sizeof(object_shm_t) \* 512/sizeof(object_shm_t) * 32768/g' "$MAPC"

# --- 4) Nur den wineserver bauen ---
echo "[4/5] configure + make server/wineserver ..."
rm -rf "build-$VER-staging"
mkdir "build-$VER-staging"
cd "build-$VER-staging"
"../wine-$VER/configure" --prefix=/usr --enable-win64 --with-vulkan > configure.log 2>&1
make -j"$(nproc)" server/wineserver > make.log 2>&1
strip server/wineserver

# --- 5) Ablegen + Manifest ---
install -m 755 server/wineserver "$ASSETS/$NAME"
MD5="$(md5sum "$ASSETS/$NAME" | awk '{print $1}')"
# Builds sind nicht bitgleich reproduzierbar: ältere Hashes derselben Version
# bleiben gültig, damit ein bereits eingespieltes Binary nicht als fremd gilt.
{ cat "$MANIFEST" 2>/dev/null; echo "$MD5  $NAME"; } | sort -u | sort -V -k2 > "$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"
echo "[5/5] $ASSETS/$NAME  md5 $MD5"
echo "# Fertig $(date)"
