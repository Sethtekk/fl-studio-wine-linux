#!/bin/bash
# ============================================================
# Einmalige Installation der Update-Automatik (root):
#   sudo bash scripts/install-fl-wine-automation.sh
#
#   1. Pacman-Hook:  spielt nach jedem wine-staging-Update den
#                    passenden Pool-Fix offline ein
#   2. systemd-Timer: repariert, falls der Fix fehlt, und baut ihn für
#                    anstehende wine-staging-Versionen vorab
#   3. erster Wartungslauf sofort
#
# Deinstallation: sudo bash scripts/install-fl-wine-automation.sh --remove
# Selbsttest:     sudo bash scripts/install-fl-wine-automation.sh --selftest
#                 (setzt kurz den Stock-wineserver ein und prüft, ob der
#                 Wartungsdienst den Pool-Fix selbstständig zurückholt)
# ============================================================
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "Bitte mit sudo ausführen:  sudo bash $0"; exit 1; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK=/etc/pacman.d/hooks/zz-wineserver-poolfix.hook
UNITS=(wineserver-poolfix-maintain.service wineserver-poolfix-maintain.timer)

if [ "${1:-}" = "--remove" ]; then
    systemctl disable --now wineserver-poolfix-maintain.timer 2>/dev/null || true
    rm -f "$HOOK" "${UNITS[@]/#//etc/systemd/system/}"
    systemctl daemon-reload
    echo "Automatik entfernt. /usr/bin/wineserver bleibt unverändert (Stock: sudo pacman -S wine-staging)."
    exit 0
fi

render() { sed "s#@REPO@#$REPO#g" "$1"; }

if [ "${1:-}" = "--selftest" ]; then
    VER="$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    STOCK="/usr/bin/wineserver.stock-$VER"
    [ -f "$STOCK" ] || { echo "Kein Stock-Backup $STOCK - Selbsttest nicht möglich."; exit 1; }
    BEFORE="$(md5sum /usr/bin/wineserver | awk '{print $1}')"
    echo "== Selbsttest: Stock-wineserver $VER einsetzen (atomar; laufende Wine-Prozesse bleiben unberührt)"
    install -m 755 "$STOCK" /usr/bin/wineserver.selftest && mv -f /usr/bin/wineserver.selftest /usr/bin/wineserver
    echo "== Wartungsdienst starten"
    systemctl start wineserver-poolfix-maintain.service || true
    AFTER="$(md5sum /usr/bin/wineserver | awk '{print $1}')"
    journalctl -u wineserver-poolfix-maintain.service -n 8 --no-pager -o cat
    if awk '{print $1}' "$REPO/assets/poolfix-md5.txt" | grep -qx "$AFTER"; then
        echo "== ERGEBNIS: OK - Pool-Fix automatisch wiederhergestellt (md5 $AFTER)."
    else
        echo "== ERGEBNIS: FEHLER - wineserver ist $AFTER. Zurück auf den vorherigen Stand ($BEFORE)."
        bash "$REPO/scripts/pacman-hook-apply.sh"
        exit 1
    fi
    exit 0
fi

echo "== 1) Pacman-Hook =="
install -d /etc/pacman.d/hooks
render "$REPO/hooks/zz-wineserver-poolfix.hook" > "$HOOK"
chmod 644 "$HOOK"
echo "   $HOOK"

echo "== 2) systemd-Timer =="
for u in "${UNITS[@]}"; do
    render "$REPO/systemd/$u" > "/etc/systemd/system/$u"
    chmod 644 "/etc/systemd/system/$u"
done
systemctl daemon-reload
systemctl enable --now wineserver-poolfix-maintain.timer
systemctl list-timers --no-pager wineserver-poolfix-maintain.timer | sed -n '1,2p'

echo "== 3) Erster Wartungslauf =="
systemctl start wineserver-poolfix-maintain.service || true
journalctl -u wineserver-poolfix-maintain.service -n 15 --no-pager -o cat

echo
echo "Fertig. Status jederzeit: journalctl -u wineserver-poolfix-maintain.service"
