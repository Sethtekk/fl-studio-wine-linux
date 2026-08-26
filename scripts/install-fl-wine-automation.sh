#!/bin/bash
# ============================================================
# EINMALIGE Installation der FL-Wine-Automatik. Als root ausfuehren:
#   sudo bash ~/fl-studio-wine-linux/scripts/install-fl-wine-automation.sh
#
# 1) installiert den pacman-Hook (re-appliziert Pool-Fix nach jedem
#    wine-staging-Update automatisch)
# 2) spielt den Pool-Fix fuer die aktuelle Wine-Version JETZT ein
# 3) testet Protokoll-Kompatibilitaet und macht bei Mismatch automatisch
#    rueckgaengig (damit wine NIE kaputt zurueckbleibt)
# ============================================================
if [ "$EUID" -ne 0 ]; then
    echo "Bitte mit sudo ausfuehren:  sudo bash $0"
    exit 1
fi
RUSER="${SUDO_USER:-sethtekk}"
REPO="/home/$RUSER/fl-studio-wine-linux"
TARGET=/usr/bin/wineserver

echo "== 1) Pacman-Hook installieren =="
install -Dm644 "$REPO/hooks/zz-wineserver-poolfix.hook" \
        /etc/pacman.d/hooks/zz-wineserver-poolfix.hook
echo "   -> /etc/pacman.d/hooks/zz-wineserver-poolfix.hook"
echo

echo "== 2) Pool-Fix fuer aktuelle Wine-Version einspielen =="
bash "$REPO/scripts/pacman-hook-apply.sh"
echo

echo "== 3) Protokoll-Kompatibilitaet testen =="
# gegen den bereits initialisierten FL-Prefix -> schnell, nicht-destruktiv
OUT="$(sudo -u "$RUSER" env WINEPREFIX=/run/media/sethtekk/WinVM/.wine \
        WINEDEBUG=-all WINEDLLOVERRIDES='mscoree,mshtml=' \
        timeout 40 wine cmd /c ver 2>&1)"
if printf '%s' "$OUT" | grep -qi "version mismatch"; then
    echo "   [!] PROTOKOLL-MISMATCH erkannt:"
    printf '       %s\n' "$OUT" | grep -i "mismatch"
    if [ -f "$TARGET.orig" ]; then
        cp "$TARGET.orig" "$TARGET"
        echo "   [!] wineserver auf STOCK zurueckgesetzt (wine bleibt funktionsfaehig)."
    fi
    echo "   [!] Bitte Claude informieren - Neu-Build noetig."
    exit 1
else
    echo "   [OK] wine antwortet sauber: $(printf '%s' "$OUT" | tr -d '\r' | tail -1)"
    echo "   [OK] Pool-Fix aktiv und protokoll-kompatibel."
fi
echo
echo "== Fertig - FL-Wine-Automatik installiert. =="
echo "Ab jetzt spielt jedes wine-staging-Update den Pool-Fix automatisch wieder ein"
echo "(bzw. warnt, wenn fuer eine neue Version erst neu gebaut werden muss)."
