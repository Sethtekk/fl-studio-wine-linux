#!/bin/bash
# ============================================================
# One-time setup of the update automation (root):
#   sudo bash scripts/install-fl-wine-automation.sh
#
#   1. pacman hook:    after every wine-staging update, installs the
#                      matching pool fix (offline)
#   2. systemd timer:  repairs the fix if it is missing and pre-builds
#                      it for upcoming wine-staging versions
#   3. runs the first maintenance pass right away
#
# Uninstall: sudo bash scripts/install-fl-wine-automation.sh --remove
# Self-test: sudo bash scripts/install-fl-wine-automation.sh --selftest
#            (briefly puts the stock wineserver back and checks that the
#            maintenance service restores the pool fix on its own)
# ============================================================
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "Please run with sudo:  sudo bash $0"; exit 1; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK=/etc/pacman.d/hooks/zz-wineserver-poolfix.hook
UNITS=(wineserver-poolfix-maintain.service wineserver-poolfix-maintain.timer)

if [ "${1:-}" = "--remove" ]; then
    systemctl disable --now wineserver-poolfix-maintain.timer 2>/dev/null || true
    rm -f "$HOOK" "${UNITS[@]/#//etc/systemd/system/}"
    systemctl daemon-reload
    echo "Automation removed. /usr/bin/wineserver is left as it is (to restore stock: sudo pacman -S wine-staging)."
    exit 0
fi

render() { sed "s#@REPO@#$REPO#g" "$1"; }

if [ "${1:-}" = "--selftest" ]; then
    VER="$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    STOCK="/usr/bin/wineserver.stock-$VER"
    [ -f "$STOCK" ] || { echo "No stock backup at $STOCK - cannot run the self-test."; exit 1; }
    BEFORE="$(md5sum /usr/bin/wineserver | awk '{print $1}')"
    echo "== Self-test: installing the stock wineserver $VER (atomic; running Wine processes are not affected)"
    install -m 755 "$STOCK" /usr/bin/wineserver.selftest && mv -f /usr/bin/wineserver.selftest /usr/bin/wineserver
    echo "== Starting the maintenance service"
    systemctl start wineserver-poolfix-maintain.service || true
    AFTER="$(md5sum /usr/bin/wineserver | awk '{print $1}')"
    journalctl -u wineserver-poolfix-maintain.service -n 8 --no-pager -o cat
    if awk '{print $1}' "$REPO/assets/poolfix-md5.txt" | grep -qx "$AFTER"; then
        echo "== RESULT: OK - pool fix restored automatically (md5 $AFTER)."
    else
        echo "== RESULT: FAILED - wineserver is $AFTER. Restoring the previous state ($BEFORE)."
        bash "$REPO/scripts/pacman-hook-apply.sh"
        exit 1
    fi
    exit 0
fi

echo "== 1) pacman hook =="
install -d /etc/pacman.d/hooks
render "$REPO/hooks/zz-wineserver-poolfix.hook" > "$HOOK"
chmod 644 "$HOOK"
echo "   $HOOK"

echo "== 2) systemd timer =="
for u in "${UNITS[@]}"; do
    render "$REPO/systemd/$u" > "/etc/systemd/system/$u"
    chmod 644 "/etc/systemd/system/$u"
done
systemctl daemon-reload
systemctl enable --now wineserver-poolfix-maintain.timer
systemctl list-timers --no-pager wineserver-poolfix-maintain.timer | sed -n '1,2p'

echo "== 3) First maintenance pass =="
systemctl start wineserver-poolfix-maintain.service || true
journalctl -u wineserver-poolfix-maintain.service -n 15 --no-pager -o cat

echo
echo "Done. Check the status any time: journalctl -u wineserver-poolfix-maintain.service"
