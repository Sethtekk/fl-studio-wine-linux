# Plugins

## Kompatibilität

Getestet unter wine-staging 11.19, EGL, NVIDIA 615, KDE Plasma 6 (Wayland/XWayland). „GUI-Test" bedeutet: Plugin geladen, Editor in einem Host-Fenster geöffnet, gerendert und sauber geschlossen – mit den Testhosts aus [`tools/`](../tools).

| Plugin | Format | Grafik | Status | Hinweis |
|---|---|---|---|---|
| Serum 2 | VST3 | Direct2D (JUCE 8) | ✅ läuft in FL | Benötigt den d2d1-Patch. Strichstile (runde Enden, Strichelung) zeichnet Wine als einfache Linien. |
| Serum 1 | VST2 | GDI+ / D3D | ✅ GUI-Test | Erstes Zeichnen ~1 s (DXVK-Initialisierung) |
| CamelCrusher | VST2 | GDI+ | ✅ GUI-Test | |
| Spectral Compressor | VST3/CLAP | OpenGL (nih-plug/vizia) | ⚠️ Neubau nötig | Offizieller Build stürzt unter EGL ab, siehe [nih-plug](#nih-plug) |
| Diopser | VST3/CLAP | OpenGL (nih-plug/vizia) | ⚠️ Neubau nötig | dto. |
| Crisp | VST3/CLAP | OpenGL (nih-plug/vizia) | ⚠️ Neubau nötig | dto. |
| Safety Limiter, Soft Vacuum, Puberty Simulator, Loudness War Winner, Buffr Glitch, Crossover | VST3 | ohne eigene GUI | ✅ | Kein baseview-Code enthalten |
| Kickstart 2, Youlean Loudness Meter 2, GrapHack, iZotope Neutron 4 / Tonal Balance Control 2 | VST2/VST3 | OpenGL (JUCE u. a.) | ✅ Pixelformat geprüft | JUCE wählt per `ChoosePixelFormat` ein Format ohne Alpha; einzelne GUIs nicht im Testhost geprüft |

## nih-plug

Plugins auf Basis von [nih-plug](https://github.com/robbert-vdh/nih-plug) mit vizia- oder egui-Editor zeichnen über [baseview](https://github.com/RustAudio/baseview) mit OpenGL.

**Fehlerbild:** Beim Öffnen des Editors beendet sich FL Studio ohne Rückfrage. Im Log:

```
panicked at 'Could not create OpenGL context: CreationFailed(())' … baseview/src/win/window.rs
panicked at 'panic in a function that cannot unwind'
Unhandled exception code c0000409
```

**Ursache:** baseview verlangt ein Fenster-Pixelformat mit 8 Bit Alpha. NVIDIAs EGL-Implementierung bietet Alpha-Formate nur mit einem 32-Bit-ARGB-Visual an. Wine (`x11drv_egl_describe_pixel_format`) entfernt bei Visuals, deren Tiefe nicht der Bildschirmtiefe entspricht, `PFD_DRAW_TO_WINDOW`, damit Kindfenster per `XCopyArea` kopiert werden können. Es bleibt kein passendes Format; baseview panict in einem FFI-Callback, der nicht abwickeln darf, und der Prozess bricht ab.

Unter GLX tritt der Fehler nicht auf, dort gibt es Alpha-Formate mit 24-Bit-Visual – GLX ist mit NVIDIA aber anfällig für den GL-Deadlock. Wine anzupassen hätte unter KWin echte Fenstertransparenz zur Folge; die gezielte Korrektur gehört daher in baseview.

**Lösung:** [`patches/baseview-alpha-fallback.patch`](../patches/baseview-alpha-fallback.patch) – findet `wglChoosePixelFormatARB` kein Format, wird ohne Alpha erneut gesucht. Die Editoren sind deckend, optisch ändert sich nichts.

```bash
bash scripts/09-build-nih-plug.sh                       # Spectral Compressor, Diopser, Crisp
bash scripts/09-build-nih-plug.sh spectral_compressor   # einzelnes Plugin
```

Ergebnisse liegen unter `build/nih-plug-src/nih-plug/target/bundled/`. Vor dem Ersetzen FL beenden und die Originale sichern. Parameter-IDs bleiben gleich, bestehende Projekte laden unverändert.

Verifikation im CLAP-Testhost (EGL, NVIDIA):

| Plugin | Offizieller Build | Mit Patch |
|---|---|---|
| Spectral Compressor | Absturz (`CreationFailed`) | Editor 1360×530, sauber beendet |
| Diopser | Absturz | Editor 600×490, sauber beendet |
| Crisp | Absturz | Editor 400×390, sauber beendet |

## Direct2D-Leistung (Serum 2 und andere JUCE-8-Plugins)

JUCE 8 zeichnet unter Windows über Direct2D. `Direct2DGraphicsContext::strokePath()` erzeugt bei **jedem** Aufruf eine neue Pfad-Geometrie mit `D2D1_FIGURE_BEGIN_HOLLOW` und zeichnet nur deren Umriss. Wine berechnete beim `Close()` trotzdem alle Selbstüberschneidungen der Figur (O(n²)) – Arbeit, die nur für Füllflächen gebraucht wird.

Der d2d1-Patch überspringt Hollow-Figuren in `d2d_geometry_intersect_self`. Gemessen mit [`tools/d2d1_strokebench.cpp`](../tools/d2d1_strokebench.cpp) (Pfad mit 400 Bézier-Segmenten, nur Umriss):

| | `Close()` | gesamt pro Pfad |
|---|---|---|
| vorher | 3,32 ms | 3,58 ms |
| nachher | < 0,01 ms | 0,31 ms |

Wine meldet außerdem pro Aufruf `fixme:d2d:d2d_device_context_DrawGeometry Ignoring stroke style`. Der Launcher setzt deshalb `WINEDEBUG=fixme-all`.

## Testwerkzeuge

```bash
cd tools
git clone --depth 1 https://github.com/free-audio/clap.git
make
```

| Werkzeug | Zweck |
|---|---|
| `clap_guitest.exe <plugin.clap> <s>` | Lädt ein CLAP-Plugin, bettet den Editor in ein Win32-Fenster ein |
| `vst2_guitest.exe <plugin.dll> <s>` | Dasselbe für VST2; misst die längste Idle-Runde des Editors |
| `d2d1_fuzz.exe <seed> <anzahl>` | Erzeugt degenerierte Pfade, findet Hänger und Abstürze in d2d1 |
| `d2d1_strokebench.exe <n> <segmente> <bezier>` | Misst Aufbau, `Close()` und `DrawGeometry` von Umriss-Pfaden |

Ein Testlauf in einem separaten Prefix beeinflusst eine laufende FL-Sitzung nicht.
