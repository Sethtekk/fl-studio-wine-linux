# wineserver shared session pool fix – technical notes

## Problem

**File:** `server/mapping.c`
**Function:** `create_session_mapping()` (around line 1428)
**Wine version:** 11.9 and later

For every session, Wine creates a shared memory area (the "shared session") that holds **windows, window classes and message queues** as objects. Its *initial* size is set to **512 objects**.

When FL Studio loads a project, it registers its own window classes for every mixer track, every stock plugin and every plugin GUI. In large projects (many tracks + sidechain routing + many plugins) the 512-object pool runs out before everything has loaded.

**Symptom:** FL Studio aborts with **`System Error. Code: 1411. Class does not exist`**, or hangs when switching projects. Stock plugins can no longer be opened.

## Cause (confirmed in the log)

With `WINEDEBUG=+seh,err+win`, the log at the moment of the crash shows:

```
err:class:NtUserRegisterClassExWOW Failed to get shared session object for window class
[ERROR] thread 'unnamed' panicked at 'panic in a function that cannot unwind'
thread caused non-unwinding panic. aborting.   (c0000409 = STATUS_STACK_BUFFER_OVERRUN)
```

`NtUserRegisterClassExWOW` gets no free slot from the shared session pool → class registration fails → FL reports 1411. The server can grow the pool (`grow_session_mapping`), but the reliable way to keep it stable is to make the **initial** pool large enough from the start.

## Fix

```c
// server/mapping.c, create_session_mapping():
-    size_t size = max( sizeof(*shared_session) + sizeof(object_shm_t) * 512, 0x10000 );
+    size_t size = max( sizeof(*shared_session) + sizeof(object_shm_t) * 32768, 0x10000 );
```

Pool size **512 → 32768** objects. With that, the initially mapped area is enough even for very large FL projects. The patch is included as `patches/wineserver-pool-size.patch`.

## Applying / rebuilding

The simplest way is the build script, which does all of the steps below for one wine-staging version:

```bash
bash scripts/build-wineserver-poolfix.sh          # installed version
bash scripts/build-wineserver-poolfix.sh 11.20    # any version
```

### Option A – vanilla Wine (e.g. exactly 11.9)

```bash
# Get the Wine source for the matching version
wget https://dl.winehq.org/wine/source/11.x/wine-11.9.tar.xz
tar xf wine-11.9.tar.xz && cd wine-11.9

# Apply the patch
patch -p1 < /path/to/patches/wineserver-pool-size.patch

# Build only the wineserver
./configure --enable-archs=i386,x86_64
make -j$(nproc) server/wineserver

# The result is server/wineserver
```

### Option B – wine-staging (REQUIRED from 11.10 on)

If **wine-staging** is installed (as on CachyOS), the wineserver must be built from the staging sources from 11.10 on, otherwise the server protocol won't match. Apply the staging patches first, **then** the pool patch:

```bash
# Vanilla tarball + matching wine-staging sources (same version!)
wget https://dl.winehq.org/wine/source/11.x/wine-11.10.tar.xz
tar xf wine-11.10.tar.xz
git clone --branch v11.10 --depth 1 https://gitlab.winehq.org/wine/wine-staging.git wine-staging-src

# 1) Apply the staging patches to the Wine tree (brings the protocol to 943)
python3 wine-staging-src/staging/patchinstall.py --all --destdir wine-11.10

# 2) THEN apply the pool patch
cd wine-11.10
patch -p1 < /path/to/patches/wineserver-pool-size.patch

# 3) Build only the wineserver, out of tree
cd .. && mkdir build-11.10 && cd build-11.10
../wine-11.10/configure --prefix=/usr --enable-win64 --with-vulkan
make -j$(nproc) server/wineserver
strip server/wineserver        # ~5.1 MB -> ~770 KB
```

## The prebuilt binaries

> ⚠️ **One binary per Wine version!** The wineserver must match the installed Wine
> version exactly, otherwise you get `wine client error:0: version mismatch`. Copying
> an older binary over it does NOT work.

`assets/` contains stripped pool-fix binaries for **wine-staging 11.9 to 11.20** (x86_64, pool = 32768). Their MD5 hashes are listed in [`assets/poolfix-md5.txt`](../assets/poolfix-md5.txt); every installation checks against that manifest.

### ⚠️ Protocol trap in 11.10

Wine **staging** 11.10 uses server protocol **943**, *vanilla* Wine 11.10 only **942**.
A 11.10 wineserver built from the **vanilla** sources fails against the installed staging
libraries with `wine client error:0: version mismatch 942/943`, and FL won't start.
That is why the binaries are built from the **wine-staging sources** (option B above).

`scripts/08-apply-wineserver-poolfix.sh` installs the fix: it detects the installed Wine
version, builds the binary if it is missing, backs up the stock binary as
`/usr/bin/wineserver.stock-<VER>`, replaces `/usr/bin/wineserver` atomically and runs a
protocol test (rollback on failure).

## ⚠️ Surviving updates (IMPORTANT)

Setting `WINESERVER` as an environment variable **does not work on Arch/CachyOS** - Wine always starts the hard-coded `/usr/bin/wineserver`. There is also **no** registry or config option for the pool size (it is compiled in). So `/usr/bin/wineserver` itself has to be replaced.

**Every `wine-staging` update overwrites `/usr/bin/wineserver`** → the fix is gone and error 1411 comes back. Either install the update automation once (see [docs/updating.md](../docs/updating.md)), or reinstall the fix after every Wine update:

```bash
bash scripts/08-apply-wineserver-poolfix.sh
```

The launcher (`scripts/run-flstudio.sh`) warns on start if `/usr/bin/wineserver` is not (or no longer) the pool version - once the pool fix has been set up with `./install.sh --pool-fix`.

## What it is NOT (ruled-out dead ends)

- **ntsync** is not the cause. When the pool runs out, the main thread does hang in `ntsync_char_ioctl` (symptom: hang instead of crash), but without `/dev/ntsync` Wine falls back cleanly (`server/inproc_sync.c`: `if (get_inproc_device_fd() >= 0)`) and still crashes with 1411. ntsync is a performance feature → **don't disable it**.
- Since Wine 11.9 there are **no** `WINEFSYNC`/`WINEESYNC`/`WINENTSYNC` variables any more (the new "inproc sync" is decided on the server side). Such lines in a launcher have no effect.
