#!/bin/bash
# ============================================================
# Schritt 8: wineserver-Pool-Fix manuell einspielen
#
# Ersetzt /usr/bin/wineserver durch eine Variante mit Shared-Session-
# Pool 32768 (statt 512) - verhindert Fehler 1411 bei großen Projekten.
# Fehlt das Binary für die installierte Wine-Version, wird es gebaut.
# Mit Protokolltest und automatischem Rollback.
#
# Für den Dauerbetrieb besser einmalig die Automatik installieren:
#   sudo bash scripts/install-fl-wine-automation.sh
# ============================================================
exec sudo bash "$(dirname "$0")/pacman-hook-apply.sh" --build
