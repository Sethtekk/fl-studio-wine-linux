#!/bin/bash
# ============================================================
# Step 4: install the patched d2d1.dll
#
# Wine's Direct2D triangulation can recurse/loop forever on some plugin
# geometry -> FL Studio freezes when opening Serum 2, Ozone and others.
# assets/d2d1.dll.patched is Wine 11.19's d2d1 with those bugs fixed
# (source: patches/d2d1-geometry-fix.patch). Its Wine "builtin" marker at
# offset 0x40 is zeroed so Wine loads it as a native DLL.
#
# Safe to run again any time (e.g. after a Wine update reset it).
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/config.sh"

DLL="$REPO_DIR/assets/d2d1.dll.patched"
[ -f "$DLL" ] || die "$DLL is missing - clone the full repository."
[ -d "$SYS32" ] || die "No prefix at $WINEPREFIX - run step 2 first."

step "Installing the patched d2d1.dll"
if [ -f "$SYS32/d2d1.dll" ] && ! cmp -s "$DLL" "$SYS32/d2d1.dll" && [ ! -f "$SYS32/d2d1.dll.wine-orig" ]; then
    cp -a "$SYS32/d2d1.dll" "$SYS32/d2d1.dll.wine-orig"
    ok "original kept as d2d1.dll.wine-orig"
fi
cp "$DLL" "$SYS32/d2d1.dll"
WINEDEBUG=-all wine reg add 'HKCU\Software\Wine\DllOverrides' /v d2d1 /d native,builtin /f >/dev/null 2>&1
ok "d2d1.dll installed, override d2d1 = native,builtin (md5 $(md5sum "$SYS32/d2d1.dll" | cut -c1-8))"
