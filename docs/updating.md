# Updates

## What a `pacman -Syu` affects

| Component | Location | On a Wine update |
|---|---|---|
| `d2d1.dll` | `$WINEPREFIX/drive_c/windows/system32/` | stays; the launcher restores it if it has changed |
| `wineserver` (pool fix) | `/usr/bin/wineserver` | is overwritten → the hook or the maintenance service reinstalls the fix |
| Registry (`UseEGL`, `DllOverrides`) | prefix | stays |
| Launcher | `~/.local/bin/flstudio-wine` → `scripts/run-flstudio.sh` | stays; `git pull` updates it |

## Update automation (Arch only, optional)

The pool fix is only needed for very large projects (error 1411). Install it once:

```bash
sudo bash scripts/install-fl-wine-automation.sh          # --remove to uninstall
```

| Part | When | What |
|---|---|---|
| pacman hook `zz-wineserver-poolfix.hook` | after every `wine-staging` update | installs the existing pool-fix binary **offline**; if there is none, it triggers the maintenance service |
| `wineserver-poolfix-maintain.timer` | 5 min after boot, then every 3 h | **repair** if `/usr/bin/wineserver` is not the pool fix; **pre-build** for wine-staging versions waiting in the repos (`checkupdates`) |
| Launcher | on every FL start | restores a replaced `d2d1.dll` and shows a desktop notification if the pool fix is missing |

**Why not build in the hook?** During large pacman transactions the network is often down for a moment - for example when NetworkManager, systemd or a VPN daemon are updated in the same run. Downloading the Wine sources from inside the hook failed repeatedly for that reason. With the pre-build, the binary is usually ready before the update is installed; otherwise the maintenance service builds it after the transaction (it waits for the pacman lock and for the network, retries after 20 minutes on failure, and again on every timer run).

Every installation follows the same steps:

1. check the MD5 against `assets/poolfix-md5.txt` (several hashes per version are allowed, because builds are not bit-for-bit reproducible),
2. back up the stock binary per version (`/usr/bin/wineserver.stock-<VER>`),
3. replace it atomically (a running wineserver keeps its file),
4. run a protocol test in a throwaway prefix; if it fails, the stock wineserver is restored.

Builds run as the owner of the repository with low CPU and I/O priority. Status and logs:

```bash
systemctl list-timers wineserver-poolfix-maintain.timer
journalctl -u wineserver-poolfix-maintain.service
ls ~/wine-build/poolfix-build-*.log
```

By hand (without the automation): `bash scripts/08-apply-wineserver-poolfix.sh`

## Rebuilding d2d1

`d2d1.dll` is a pure PE DLL and keeps working with newer Wine versions. Rebuilding is worthwhile when upstream changes `dlls/d2d1/`:

```bash
diff -rq wine-OLD/dlls/d2d1 wine-NEW/dlls/d2d1 \
     --exclude='*.o' --exclude='*.dll' --exclude=Makefile --exclude=x86_64-windows
```

To build:

```bash
cd wine-X.Y && patch -p1 < /path/to/patches/d2d1-geometry-fix.patch
mkdir ../build && cd ../build && ../wine-X.Y/configure --enable-win64
make -j"$(nproc)" dlls/d2d1/x86_64-windows/d2d1.dll
cp dlls/d2d1/x86_64-windows/d2d1.dll /path/to/assets/d2d1.dll.patched
bash /path/to/scripts/04-apply-d2d1-patch.sh
```

Recommended before installing: compare Wine's test suite (`make dlls/d2d1/tests/x86_64-windows/d2d1_test.exe`) between stock and patched, and run `tools/d2d1_fuzz.exe`.

## Restoring

After `wineboot -u` or a prefix update, Wine may write its builtin `d2d1.dll` back:

```bash
bash scripts/restore-d2d1-patch.sh
```
