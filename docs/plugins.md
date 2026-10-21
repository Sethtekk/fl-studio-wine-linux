# Plugins

## Compatibility

Tested with wine-staging 11.19, EGL, NVIDIA 615, KDE Plasma 6 (Wayland/XWayland). "GUI test" means: plugin loaded, editor opened in a host window, rendered and closed cleanly - using the test hosts in [`tools/`](../tools).

| Plugin | Format | Graphics | Status | Notes |
|---|---|---|---|---|
| Serum 2 | VST3 | Direct2D (JUCE 8) | ✅ runs in FL | Needs the d2d1 patch. Wine draws stroke styles (round caps, dashes) as plain lines. |
| Serum 1 | VST2 | GDI+ / D3D | ✅ GUI test | First draw takes ~1 s (DXVK initialisation) |
| CamelCrusher | VST2 | GDI+ | ✅ GUI test | |
| Spectral Compressor | VST3/CLAP | OpenGL (nih-plug/vizia) | ⚠️ rebuild needed | The official build crashes under EGL, see [nih-plug](#nih-plug) |
| Diopser | VST3/CLAP | OpenGL (nih-plug/vizia) | ⚠️ rebuild needed | same as above |
| Crisp | VST3/CLAP | OpenGL (nih-plug/vizia) | ⚠️ rebuild needed | same as above |
| Safety Limiter, Soft Vacuum, Puberty Simulator, Loudness War Winner, Buffr Glitch, Crossover | VST3 | no custom GUI | ✅ | Contain no baseview code |
| Kickstart 2, Youlean Loudness Meter 2, GrapHack, iZotope Neutron 4 / Tonal Balance Control 2 | VST2/VST3 | OpenGL (JUCE and others) | ✅ pixel format checked | JUCE picks a format without alpha via `ChoosePixelFormat`; not every GUI was tested in the test host |

## nih-plug

Plugins built on [nih-plug](https://github.com/robbert-vdh/nih-plug) with a vizia or egui editor draw through [baseview](https://github.com/RustAudio/baseview) using OpenGL.

**Symptom:** FL Studio quits without warning as soon as the editor opens. The log shows:

```
panicked at 'Could not create OpenGL context: CreationFailed(())' … baseview/src/win/window.rs
panicked at 'panic in a function that cannot unwind'
Unhandled exception code c0000409
```

**Cause:** baseview asks for a window pixel format with 8-bit alpha. NVIDIA's EGL implementation only offers alpha formats with a 32-bit ARGB visual. For visuals whose depth differs from the screen depth, Wine (`x11drv_egl_describe_pixel_format`) removes `PFD_DRAW_TO_WINDOW` so that child windows can be copied with `XCopyArea`. No suitable format is left; baseview panics inside an FFI callback that must not unwind, and the process aborts.

The problem doesn't occur under GLX, which has alpha formats with a 24-bit visual - but with NVIDIA, GLX is prone to the GL deadlock. Changing Wine would make windows truly transparent under KWin, so the targeted fix belongs in baseview.

**Fix:** [`patches/baseview-alpha-fallback.patch`](../patches/baseview-alpha-fallback.patch) - if `wglChoosePixelFormatARB` finds no format, it searches again without alpha. The editors are opaque, so nothing changes visually.

```bash
bash scripts/09-build-nih-plug.sh                       # Spectral Compressor, Diopser, Crisp
bash scripts/09-build-nih-plug.sh spectral_compressor   # a single plugin
```

The results are in `build/nih-plug-src/nih-plug/target/bundled/`. Quit FL and back up the originals before replacing them. Parameter IDs stay the same, so existing projects load unchanged.

Verified in the CLAP test host (EGL, NVIDIA):

| Plugin | Official build | With patch |
|---|---|---|
| Spectral Compressor | crash (`CreationFailed`) | editor 1360×530, exits cleanly |
| Diopser | crash | editor 600×490, exits cleanly |
| Crisp | crash | editor 400×390, exits cleanly |

## Direct2D performance (Serum 2 and other JUCE 8 plugins)

On Windows, JUCE 8 draws through Direct2D. `Direct2DGraphicsContext::strokePath()` creates a new path geometry with `D2D1_FIGURE_BEGIN_HOLLOW` on **every** call and only draws its outline. Wine still computed all self-intersections of the figure (O(n²)) in `Close()` - work that is only needed for filled areas.

The d2d1 patch skips hollow figures in `d2d_geometry_intersect_self`. Measured with [`tools/d2d1_strokebench.cpp`](../tools/d2d1_strokebench.cpp) (path with 400 Bézier segments, outline only):

| | `Close()` | total per path |
|---|---|---|
| before | 3.32 ms | 3.58 ms |
| after | < 0.01 ms | 0.31 ms |

Inside FL Studio this made no noticeable difference (see [verification.md](verification.md)).

Wine also logs `fixme:d2d:d2d_device_context_DrawGeometry Ignoring stroke style` for every call, which is why the launcher sets `WINEDEBUG=fixme-all`.

## Test tools

```bash
cd tools
git clone --depth 1 https://github.com/free-audio/clap.git
make
```

| Tool | Purpose |
|---|---|
| `clap_guitest.exe <plugin.clap> <s>` | Loads a CLAP plugin and embeds its editor in a Win32 window |
| `vst2_guitest.exe <plugin.dll> <s>` | The same for VST2; measures the editor's longest idle round |
| `d2d1_fuzz.exe <seed> <count>` | Generates degenerate paths and finds hangs and crashes in d2d1 |
| `d2d1_strokebench.exe <n> <segments> <bezier>` | Measures building, `Close()` and `DrawGeometry` of stroked paths |

A test run in a separate prefix does not affect a running FL session.
