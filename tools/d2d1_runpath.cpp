// Replays one path geometry from a text file and closes it, which runs Wine's
// d2d1 triangulation. Prints "CLOSE <hr>"; a crash or hang shows as no output.
// File format, one command per line:
//   M <0|1>                      fill mode (0 alternate, 1 winding)
//   F x y                        BeginFigure (filled)
//   L x y                        AddLine
//   B x1 y1 x2 y2 x3 y3          AddBezier (cubic)
//   Q x1 y1 x2 y2                AddQuadraticBezier
//   E                            EndFigure (closed)
// Usage: d2d1_runpath.exe path.txt   (inputs: tools/d2d1_pathgen.py)
#include <windows.h>
#include <d2d1.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    FILE *f = argc > 1 ? fopen(argv[1], "r") : NULL;
    if (!f) return 2;
    ID2D1Factory *fa; D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), 0, (void **)&fa);
    ID2D1PathGeometry *g; fa->CreatePathGeometry(&g);
    ID2D1GeometrySink *k; g->Open(&k);
    char c; float a, b, d, e, h, i;
    while (fscanf(f, " %c", &c) == 1)
    {
        if (c == 'M') { int m; fscanf(f, "%d", &m); k->SetFillMode(m ? D2D1_FILL_MODE_WINDING : D2D1_FILL_MODE_ALTERNATE); }
        else if (c == 'F') { fscanf(f, "%f %f", &a, &b); k->BeginFigure(D2D1::Point2F(a, b), D2D1_FIGURE_BEGIN_FILLED); }
        else if (c == 'L') { fscanf(f, "%f %f", &a, &b); k->AddLine(D2D1::Point2F(a, b)); }
        else if (c == 'B') { fscanf(f, "%f %f %f %f %f %f", &a, &b, &d, &e, &h, &i);
            k->AddBezier(D2D1::BezierSegment(D2D1::Point2F(a, b), D2D1::Point2F(d, e), D2D1::Point2F(h, i))); }
        else if (c == 'Q') { fscanf(f, "%f %f %f %f", &a, &b, &d, &e);
            D2D1_QUADRATIC_BEZIER_SEGMENT q = {D2D1::Point2F(a, b), D2D1::Point2F(d, e)}; k->AddQuadraticBezier(&q); }
        else if (c == 'E') k->EndFigure(D2D1_FIGURE_END_CLOSED);
    }
    HRESULT hr = k->Close();
    printf("CLOSE %08lx\n", hr); fflush(stdout);
    k->Release(); g->Release(); fa->Release();
    return 0;
}
