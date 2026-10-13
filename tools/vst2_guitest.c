// Minimaler VST2-Host: laedt ein Plugin, oeffnet den Editor in einem Win32-Fenster
// und ruft effEditIdle wie ein Host. Misst die Zeit pro Idle-Runde (UI-Last).
// Aufruf: vst2_guitest.exe <plugin.dll> <sekunden>
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct AEffect AEffect;
typedef intptr_t (*audioMasterCallback)(AEffect *, int32_t, int32_t, intptr_t, void *, float);
typedef intptr_t (*dispatcherProc)(AEffect *, int32_t, int32_t, intptr_t, void *, float);
struct AEffect {
    int32_t magic; dispatcherProc dispatcher; void *process; void *setParameter; void *getParameter;
    int32_t numPrograms, numParams, numInputs, numOutputs, flags;
    intptr_t resvd1, resvd2; int32_t initialDelay, realQualities, offQualities; float ioRatio;
    void *object, *user; int32_t uniqueID, version; void *processReplacing, *processDoubleReplacing;
    char future[56];
};
typedef struct { int16_t top, left, bottom, right; } ERect;
enum { effOpen = 0, effClose = 1, effSetSampleRate = 10, effSetBlockSize = 11, effMainsChanged = 12,
       effEditGetRect = 13, effEditOpen = 14, effEditClose = 15, effEditIdle = 19 };

static intptr_t host_cb(AEffect *e, int32_t op, int32_t idx, intptr_t v, void *p, float o)
{
    switch (op) {
    case 1: return 2400;       // audioMasterVersion
    case 6: return 0;          // wantMidi
    case 7: return 0;          // getTime
    case 16: return 44100;     // getSampleRate
    case 17: return 512;       // getBlockSize
    case 32: strcpy(p, "test"); return 1; // vendor string
    case 33: strcpy(p, "vst2_guitest"); return 1;
    case 37: return 0;         // canDo
    default: return 0;
    }
}

int main(int argc, char **argv)
{
    int secs = argc > 2 ? atoi(argv[2]) : 10;
    HMODULE lib = LoadLibraryA(argv[1]);
    if (!lib) { printf("LoadLibrary fehlgeschlagen %lu\n", GetLastError()); return 1; }
    AEffect *(*entry)(audioMasterCallback) = (void *)GetProcAddress(lib, "VSTPluginMain");
    if (!entry) entry = (void *)GetProcAddress(lib, "main");
    AEffect *e = entry ? entry(host_cb) : NULL;
    if (!e || e->magic != 0x56737450) { printf("kein VST2-Plugin\n"); return 1; }
    e->dispatcher(e, effOpen, 0, 0, 0, 0);
    e->dispatcher(e, effSetSampleRate, 0, 0, 0, 44100.f);
    e->dispatcher(e, effSetBlockSize, 0, 512, 0, 0);
    e->dispatcher(e, effMainsChanged, 0, 1, 0, 0);
    ERect *r = NULL; e->dispatcher(e, effEditGetRect, 0, 0, &r, 0);
    int w = r ? r->right - r->left : 600, h = r ? r->bottom - r->top : 400;
    RECT wr = {0, 0, w, h}; AdjustWindowRect(&wr, WS_OVERLAPPEDWINDOW, FALSE);
    HWND hwnd = CreateWindowA("STATIC", argv[1], WS_OVERLAPPEDWINDOW | WS_VISIBLE, 60, 60,
                              wr.right - wr.left, wr.bottom - wr.top, 0, 0, 0, 0);
    e->dispatcher(e, effEditOpen, 0, 0, hwnd, 0);
    printf("Editor offen (%dx%d)\n", w, h); fflush(stdout);

    DWORD t0 = GetTickCount(); MSG m; int rounds = 0; double worst = 0;
    LARGE_INTEGER f, a, b; QueryPerformanceFrequency(&f);
    while (GetTickCount() - t0 < (DWORD)secs * 1000) {
        QueryPerformanceCounter(&a);
        while (PeekMessageA(&m, 0, 0, 0, PM_REMOVE)) { TranslateMessage(&m); DispatchMessageA(&m); }
        e->dispatcher(e, effEditIdle, 0, 0, 0, 0);
        QueryPerformanceCounter(&b);
        double ms = (b.QuadPart - a.QuadPart) * 1000.0 / f.QuadPart; if (ms > worst) worst = ms;
        rounds++; Sleep(15);
    }
    printf("%d Idle-Runden, langsamste %.1f ms\n", rounds, worst);
    e->dispatcher(e, effEditClose, 0, 0, 0, 0);
    e->dispatcher(e, effMainsChanged, 0, 0, 0, 0);
    e->dispatcher(e, effClose, 0, 0, 0, 0);
    printf("OK sauber beendet\n");
    return 0;
}
