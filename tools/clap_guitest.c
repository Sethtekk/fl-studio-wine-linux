// Minimaler CLAP-Host: laedt ein Plugin, aktiviert es und bettet seine GUI
// in ein Win32-Fenster ein (wie ein DAW-Host). Laeuft N Sekunden, pumpt Messages.
// Aufruf: clap_guitest.exe <plugin.clap> <sekunden>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <clap/clap.h>

static const void *host_get_extension(const clap_host_t *h, const char *id) { return NULL; }
static void host_noop(const clap_host_t *h) {}
static const clap_host_t host = {
    CLAP_VERSION_INIT, NULL, "clap_guitest", "test", "", "1.0",
    host_get_extension, host_noop, host_noop, host_noop,
};

int main(int argc, char **argv)
{
    int secs = argc > 2 ? atoi(argv[2]) : 10;
    HMODULE lib = LoadLibraryA(argv[1]);
    if (!lib) { printf("LoadLibrary fehlgeschlagen %lu\n", GetLastError()); return 1; }
    const clap_plugin_entry_t *entry = (const clap_plugin_entry_t *)GetProcAddress(lib, "clap_entry");
    if (!entry || !entry->init(argv[1])) { printf("clap_entry fehlt/init failed\n"); return 1; }
    const clap_plugin_factory_t *fac = entry->get_factory(CLAP_PLUGIN_FACTORY_ID);
    const clap_plugin_descriptor_t *desc = fac->get_plugin_descriptor(fac, 0);
    printf("Plugin: %s\n", desc->name); fflush(stdout);
    const clap_plugin_t *p = fac->create_plugin(fac, &host, desc->id);
    if (!p || !p->init(p)) { printf("create/init failed\n"); return 1; }
    p->activate(p, 44100, 32, 512);

    const clap_plugin_gui_t *gui = p->get_extension(p, CLAP_EXT_GUI);
    if (!gui) { printf("keine GUI\n"); return 1; }
    if (!gui->is_api_supported(p, CLAP_WINDOW_API_WIN32, false) || !gui->create(p, CLAP_WINDOW_API_WIN32, false))
    { printf("gui create failed\n"); return 1; }
    uint32_t w = 600, h = 400; gui->get_size(p, &w, &h);
    RECT r = {0, 0, (LONG)w, (LONG)h}; AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
    HWND hwnd = CreateWindowA("STATIC", desc->name, WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                              60, 60, r.right - r.left, r.bottom - r.top, 0, 0, 0, 0);
    clap_window_t win = { CLAP_WINDOW_API_WIN32 }; win.win32 = hwnd;
    gui->set_parent(p, &win);
    gui->show(p);
    printf("GUI offen (%ux%u)\n", w, h); fflush(stdout);

    DWORD t0 = GetTickCount(); MSG m;
    while (GetTickCount() - t0 < (DWORD)secs * 1000) {
        while (PeekMessageA(&m, 0, 0, 0, PM_REMOVE)) { TranslateMessage(&m); DispatchMessageA(&m); }
        p->on_main_thread(p);
        Sleep(10);
    }
    gui->destroy(p); p->deactivate(p); p->destroy(p); entry->deinit();
    printf("OK sauber beendet\n");
    return 0;
}
