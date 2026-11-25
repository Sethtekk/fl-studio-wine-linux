#!/usr/bin/env python3
"""Large, regular path geometries for tools/d2d1_runpath.exe.

The grid fuzzer (d2d1_fuzz.cpp) only builds small degenerate paths. These
families are well-formed but big, which is what overflowed the stack in
d2d_cdt_cut_edges() and d2d_cdt_fixup() (one recursion level per crossed edge
or split-off triangle).

Usage: d2d1_pathgen.py <family> <n> > path.txt
  band     two offset rows of n vertices and a long thin triangle between them
           (unpatched Wine: stack overflow from n ~9,500; old patch: from ~25,000)
  bandw    the same with winding fill and five crossing bars
  circle   n vertices on a circle and a triangle across it
  comb     n teeth and a bar across them
  spiral   one spiral figure with n vertices, winding fill
  star     2n vertices alternating between two radii
  bezier   a wave of n cubic Béziers
  grid     ~n overlapping squares
"""
import math
import sys

fam, n = sys.argv[1], int(sys.argv[2])
out = []

def fig(pts):
    out.append("F %.9g %.9g" % pts[0])
    out.extend("L %.9g %.9g" % p for p in pts[1:])
    out.append("E")

def band(mode, bars):
    out.append("M %d" % mode)
    fig([(0, 0)] + [(i, 0) for i in range(1, n + 1)] + [(i + 0.5, 2) for i in range(n - 1, -1, -1)])
    for k in range(bars):
        y = 1 if bars == 1 else 0.5 + 0.25 * k
        fig([(0.75, y), (n - 0.75, y), (n - 0.75, y + 0.01)])

if fam == "band":
    band(0, 1)
elif fam == "bandw":
    band(1, 5)
elif fam == "circle":
    out.append("M 0")
    fig([(1000 * math.cos(2 * math.pi * i / n), 1000 * math.sin(2 * math.pi * i / n)) for i in range(n)])
    fig([(-990, 0.3), (990, -0.3), (990, 0.5)])
elif fam == "comb":
    out.append("M 0")
    p = [(0, 0)]
    for i in range(n):
        p += [(2 * i + 0.5, 10), (2 * i + 1, 10), (2 * i + 1.5, 0.1)]
    fig(p + [(2 * n + 1, 0), (2 * n + 1, -1), (0, -1)])
    fig([(0.2, 5), (2 * n, 5.01), (2 * n, 5.2)])
elif fam == "spiral":
    out.append("M 1")
    fig([(i * math.cos(i * 0.1), i * math.sin(i * 0.1)) for i in range(1, n)])
elif fam == "star":
    out.append("M 0")
    fig([((1000 if i % 2 else 1) * math.cos(math.pi * i / n), (1000 if i % 2 else 1) * math.sin(math.pi * i / n))
         for i in range(2 * n)])
elif fam == "bezier":
    out += ["M 0", "F 0 0"]
    out += ["B %g 5 %g -5 %g 0" % (i + 0.3, i + 0.7, i + 1) for i in range(n)]
    out += ["L %d -10" % n, "L 0 -10", "E"]
elif fam == "grid":
    out.append("M 0")
    m = int(math.sqrt(n))
    for i in range(m):
        for j in range(m):
            fig([(i * 1.5, j * 1.5), (i * 1.5 + 2, j * 1.5), (i * 1.5 + 2, j * 1.5 + 2), (i * 1.5, j * 1.5 + 2)])
else:
    sys.exit(__doc__)
print("\n".join(out))
