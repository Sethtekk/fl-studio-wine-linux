# d2d1 Geometry Fix – Technische Dokumentation

## Problem

**Datei:** `dlls/d2d1/geometry.c`  
**Funktion:** `d2d_cdt_insert_segment()`  
**Wine-Version:** 11.9 (und viele frühere)

Die Funktion `d2d_cdt_insert_segment` ist Teil von Wine's Direct2D 1 Implementation und wird beim Rendern von Vektor-Geometrien aufgerufen. Bei bestimmten Plugin-GUIs (z.B. Serum 2, Ozone 11) mit komplexen oder degenerierten Geometrien (kollineare/duplizierte Eckpunkte) rief sich die Funktion endlos selbst auf, bis der Stack-Speicher erschöpft war.

**Symptom:** FL Studio friert beim Öffnen eines Plugins komplett ein (kein Crash-Dialog, keine Fehlermeldung). Audio läuft weiter, GUI ist tot. Einziger Ausweg: `wineserver -k`.

## Ursache

Die ursprüngliche Implementierung nutzte echte Rekursion:

```c
// ORIGINAL (problematisch):
static BOOL d2d_cdt_insert_segment(struct d2d_cdt *cdt, ...)
{
    // ... wenn ein bestimmter Zustand eintritt ...
    return d2d_cdt_insert_segment(cdt, geometry, &new_origin, edge, end_vertex);
    //     ^^^ REKURSION → Stack Overflow bei degenerierten Geometrien
}
```

## Fix

Die Rekursion wurde durch eine `goto`-basierte Iteration mit einem Sicherheitslimit ersetzt:

```c
// GEPATCHT (stabil):
static BOOL d2d_cdt_insert_segment(struct d2d_cdt *cdt, ...)
{
    unsigned int iterations = 0;

restart:
    // ... Iterationsguard ...
    if (++iterations > 16 * cdt->edge_count + 0x10000)
    {
        WARN("Iteration limit exceeded, skipping segment.\n");
        return TRUE;  // statt rekursivem Aufruf → Segment überspringen
    }

    // ... wenn ein bestimmter Zustand eintritt ...
    origin = &new_origin;
    goto restart;  // statt: return d2d_cdt_insert_segment(...)
}
```

## Anwenden auf eine neue Wine-Version

Falls du auf Wine 12.x oder neuer upgradesd:

1. Wine-Quellcode herunterladen:
   ```bash
   wget https://dl.winehq.org/wine/source/12.x/wine-12.X.tar.xz
   tar xf wine-12.X.tar.xz
   cd wine-12.X
   ```

2. `dlls/d2d1/geometry.c` öffnen und die Funktion `d2d_cdt_insert_segment` finden:
   ```bash
   grep -n "d2d_cdt_insert_segment" dlls/d2d1/geometry.c
   ```

3. Alle rekursiven `return d2d_cdt_insert_segment(...)` Aufrufe durch `goto restart` ersetzen.
   Einen `iterations`-Zähler und das Guard-Limit hinzufügen (wie im Fix oben).

4. Neu kompilieren:
   ```bash
   ./configure --enable-win64
   make -j$(nproc) dlls/d2d1/x86_64-windows/d2d1.dll
   ```

5. Patch anwenden:
   ```bash
   cp dlls/d2d1/x86_64-windows/d2d1.dll "$WINEPREFIX/drive_c/windows/system32/d2d1.dll"
   bash scripts/04-apply-d2d1-patch.sh
   ```

## Die vorkompilierte DLL

`assets/d2d1.dll.patched` ist die für **Wine 11.9, x86_64** kompilierte Version.
- **MD5:** `83d47ffb76f5d7248474b6aaa546b46b`
- **Größe:** 5.8 MB
- **Basis:** Wine Staging 11.9-1.1

Diese DLL funktioniert nur mit Wine 11.9. Bei anderen Versionen muss neu kompiliert werden.
