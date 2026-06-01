# FL Studio 2025 + Splice unter Linux (Wine)

Vollständige Installations- und Wiederherstellungsanleitung für **FL Studio 2025** und **Splice** unter Linux mit Wine Staging.

Diese Anleitung basiert auf einem **CachyOS**-System mit **KDE Plasma**, **NVIDIA RTX 3080** und **Wine Staging 11.9**. Die meisten Schritte funktionieren auf jedem Arch-basierten System.

---

## Das Problem & die Lösung

FL Studio friert ohne diese Anleitung beim Öffnen von Plugins (z.B. Serum 2) komplett ein. Ursache: ein **Stack-Overflow in `d2d1.dll`** (Funktion `d2d_cdt_insert_segment`), der bei bestimmten Plugin-GUIs einen endlosen Rekursions-Absturz auslöst.

**Fix:** Eine neu kompilierte, gepatchte Version von `d2d1.dll` aus dem Wine-Quellbaum, bei der die Rekursion durch eine Iteration ersetzt wurde.

---

## Voraussetzungen

- Arch-basiertes Linux (CachyOS, Manjaro, EndeavourOS, etc.)
- `multilib`-Repository in `/etc/pacman.conf` aktiviert
- NVIDIA- oder AMD-GPU mit aktuellem Vulkan-Treiber
- FL Studio 2025 Windows-Installer (`.exe`) — selbst besorgen
- Splice Desktop App — von [splice.com](https://splice.com) herunterladen (Windows-Installer)

---

## Schnellstart (Neu-Installation)

```bash
git clone https://github.com/sethtekk/fl-studio-wine-linux.git
cd fl-studio-wine-linux

# Schritt 1: Wine + Abhängigkeiten installieren
bash scripts/01-install-wine.sh

# Schritt 2: WINEPREFIX anlegen + konfigurieren
bash scripts/02-setup-prefix.sh

# Schritt 3: DXVK installieren (DirectX → Vulkan)
bash scripts/03-install-dxvk.sh

# Schritt 4: d2d1-Patch anwenden (WICHTIG: verhindert FL-Freeze)
bash scripts/04-apply-d2d1-patch.sh

# Schritt 5: Launcher-Scripts installieren
bash scripts/05-install-launchers.sh

# Schritt 6: FL Studio installieren (Installer-Pfad anpassen)
wine ~/Downloads/fl_studio_2025_installer.exe

# Schritt 7: Splice installieren (optional)
wine ~/Downloads/SpliceSetup.exe
bash scripts/06-setup-splice.sh
```

---

## Detaillierte Schritt-für-Schritt Anleitung

### 1. Wine Staging installieren

```bash
# multilib aktivieren (falls nicht schon aktiv):
sudo nano /etc/pacman.conf
# → [multilib] und die folgende Zeile einkommentieren

sudo pacman -Syu
sudo pacman -S wine-staging wine-mono winetricks
```

Wine Version überprüfen:
```bash
wine --version   # sollte: wine-11.9 (Staging) oder neuer
```

### 2. WINEPREFIX anlegen

Das WINEPREFIX ist der "Windows-Container" wo alle Programme und DLLs leben.

```bash
export WINEPREFIX=~/.wine-flstudio   # oder eigenen Pfad wählen
wine64 wineboot --init
```

> **Hinweis:** Wenn du ein externes Laufwerk nutzt (wie `/run/media/user/WinVM/.wine`), passe den Pfad in allen Scripts entsprechend an. Die Änderung erfolgt einmalig in `scripts/config.sh`.

### 3. DXVK installieren

DXVK ersetzt DirectX durch Vulkan → deutlich bessere Stabilität und Performance.

```bash
# DXVK herunterladen (aktuell 2.7.x)
# https://github.com/doitsujin/dxvk/releases
# Entpacken und ins Prefix installieren:
bash scripts/03-install-dxvk.sh
```

### 4. d2d1-Patch anwenden ⚠️

**Dieser Schritt ist zwingend notwendig** — ohne ihn friert FL Studio beim Öffnen von Plugins wie Serum 2 komplett ein.

```bash
bash scripts/04-apply-d2d1-patch.sh
```

Der Patch tut folgendes:
1. Kopiert die vorkompilierte gepatchte `d2d1.dll` (Wine 11.9, x86_64) in `system32/`
2. Setzt 16 Bytes bei Offset `0x40` auf `0x00` → Wine lädt sie als "native" statt "builtin"
3. Setzt den Registry-Eintrag `HKCU\Software\Wine\DllOverrides\d2d1 = native,builtin`

**Was wurde im Quellcode geändert?**

In `dlls/d2d1/geometry.c`, Funktion `d2d_cdt_insert_segment` (CDT = Constrained Delaunay Triangulation): Die ursprüngliche Implementierung rief sich selbst rekursiv auf, was bei Plugin-GUIs mit komplexen Geometrien zu einem Stack-Overflow führte. Der Fix ersetzt die Rekursion durch eine `goto`-basierte Iteration mit einem Sicherheitslimit.

### 5. Launcher installieren

```bash
bash scripts/05-install-launchers.sh
```

Installiert:
- `~/start-flstudio.sh` — FL Studio Launcher
- `~/start-splice.sh` — Splice Launcher  
- `~/.local/share/applications/fl-studio-wine.desktop` — KDE-Icon
- `~/.local/share/applications/splice-wine.desktop` — KDE-Icon

### 6. FL Studio installieren

```bash
WINEPREFIX=~/.wine-flstudio wine ~/Downloads/fl_studio_2025_installer.exe
```

Nach der Installation: FL Studio über den Launcher starten:
```bash
~/start-flstudio.sh
```

### 7. WineASIO einrichten (empfohlen für Multi-Channel-Interfaces)

Ohne WineASIO zeigt FL Studio nur 2 Eingänge (Wine WASAPI-Einschränkung). Mit WineASIO werden alle Kanäle deines Interfaces sichtbar.

```bash
sudo pacman -S wineasio
bash scripts/07-setup-wineasio.sh
systemctl --user restart pipewire pipewire-pulse wireplumber
```

Dann in FL Studio: `Options → Audio Settings → ASIO → WineASIO`.

> **Hinweis:** Das Input-Monitoring-Symbol (grüner Lautsprecher) im Mixer deaktivieren um Rückkopplungen zu vermeiden.

### 8. Splice installieren (optional)

Splice wird für iZotope-Plugins (z.B. Ozone 11) und Sample-Downloads benötigt.

```bash
WINEPREFIX=~/.wine-flstudio wine ~/Downloads/SpliceSetup.exe
bash scripts/06-setup-splice.sh
```

---

## Scripts Referenz

| Script | Zweck |
|--------|-------|
| `scripts/01-install-wine.sh` | Wine Staging + Abhängigkeiten installieren |
| `scripts/02-setup-prefix.sh` | WINEPREFIX erstellen und konfigurieren |
| `scripts/03-install-dxvk.sh` | DXVK 2.7.x installieren |
| `scripts/04-apply-d2d1-patch.sh` | Gepatchte d2d1.dll anwenden (Anti-Freeze-Fix) |
| `scripts/05-install-launchers.sh` | Launcher-Scripts + Desktop-Icons installieren |
| `scripts/06-setup-splice.sh` | Splice-Konfiguration reparieren |
| `scripts/07-setup-wineasio.sh` | WineASIO einrichten (alle Interface-Eingänge) |
| `scripts/restore-d2d1-patch.sh` | d2d1-Patch wiederherstellen (nach Wine-Update) |

---

## Wichtige Umgebungsvariablen

Diese sind in den Launchers bereits gesetzt:

| Variable | Wert | Bedeutung |
|----------|------|-----------|
| `WINEFSYNC` | `1` | Futex-basierte Synchronisation (bessere Performance) |
| `WINEESYNC` | `1` | Event-basierte Synchronisation |
| `STAGING_AUDIO_PERIOD` | `10000` | Audio-Latenz-Optimierung (10ms) |
| `DXVK_ASYNC` | `1` | Asynchrone Shader-Kompilierung |
| `__GL_THREADED_OPTIMIZATIONS` | `0` | Verhindert OpenGL-Threading-Konflikte |
| `PIPEWIRE_RUNTIME_DIR` | `/run/user/1000` | PipeWire-Socket für WineASIO/JACK |
| `JACK_NO_AUDIO_RESERVATION` | `1` | Verhindert JACK-Audiosystem-Reservierung |

---

## Update-Sicherheit

### Wine-Updates (normale pacman -Syu)

**Sicher** — der Patch liegt im WINEPREFIX (`system32/d2d1.dll`), nicht im System-Wine. `pacman -Syu` überschreibt nur `/usr/lib/wine/...`, nicht das Prefix.

### Wine-Major-Upgrade (z.B. 11.x → 12.x)

In diesem Fall muss d2d1.dll neu kompiliert werden:
1. Wine-Quellcode der neuen Version herunterladen
2. `dlls/d2d1/geometry.c` → Funktion `d2d_cdt_insert_segment` anpassen (Rekursion → Iteration)
3. `make -j$(nproc) dlls/d2d1/x86_64-windows/d2d1.dll`
4. `bash scripts/restore-d2d1-patch.sh` mit der neuen DLL

### Schnell-Wiederherstellung

Falls der Patch verloren geht (z.B. nach `wineboot`):
```bash
bash scripts/restore-d2d1-patch.sh
```

---

## Fehlerbehebung

### FL Studio friert ein

```bash
# Sofort Wine-Server killen:
WINEPREFIX=~/.wine-flstudio wineserver -k
```

Dann prüfen ob die gepatchte d2d1.dll noch da ist:
```bash
bash scripts/restore-d2d1-patch.sh
```

### Splice öffnet sich nicht

```bash
# Alte Instanz killen und Lockfile entfernen:
WINEPREFIX=~/.wine-flstudio wineserver -k
rm -f ~/.wine-flstudio/drive_c/users/$(whoami)/AppData/Local/SpliceSettings/lockfile
~/start-splice.sh
```

Falls Splice weiterhin hängt → Service Worker Cache löschen:
```bash
rm -rf ~/.wine-flstudio/drive_c/users/$(whoami)/AppData/Local/SpliceSettings/Service\ Worker
rm -rf ~/.wine-flstudio/drive_c/users/$(whoami)/AppData/Local/SpliceSettings/Code\ Cache
~/start-splice.sh
```

### Kein Sound / nur 2 Eingänge in FL Studio

Für alle Interface-Kanäle WineASIO verwenden:
```bash
bash scripts/07-setup-wineasio.sh
systemctl --user restart pipewire pipewire-pulse wireplumber
```
Dann in FL Studio: `Options → Audio Settings → ASIO → WineASIO`.

### Sample-Rate-Fehler beim Start (44100 Hz)

PipeWire läuft standardmäßig auf 48000 Hz. Fix:
```bash
mkdir -p ~/.config/pipewire/pipewire.conf.d/
# Datei 10-sample-rate.conf anlegen (wird von 07-setup-wineasio.sh automatisch erledigt)
systemctl --user restart pipewire pipewire-pulse wireplumber
```

---

## System-Informationen (Referenz-Setup)

Getestet und stabil mit:
- **OS:** CachyOS Linux (Kernel 7.x)
- **Desktop:** KDE Plasma 6 + Wayland
- **GPU:** NVIDIA RTX 3080 10GB (Treiber 610.x)
- **Wine:** wine-staging 11.9-1.1
- **DXVK:** 2.7.1
- **FL Studio:** 2025 (aktuell)
- **Splice:** 5.3.2

---

## Lizenz

Scripts und Dokumentation: MIT  
Die gepatchte `d2d1.dll` basiert auf Wine (LGPL 2.1).  
FL Studio und Splice sind proprietäre Software — eigene Lizenzen erforderlich.
