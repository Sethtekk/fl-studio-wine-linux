// Fuzzer for Wine's d2d1 path triangulation (Wine bug 60115).
// Builds random filled path geometries on a 6x6 grid - lots of duplicate and
// collinear points, 1-4 figures, lines and Beziers, both fill modes - and
// closes each one, which runs the triangulation. Stock Wine 11.19 overflowed
// the stack or hung in every block of 10,000 seeds we tried; the last
// "seed N" line printed is the culprit.
// Usage: d2d1_fuzz.exe <first seed> <count> [delay ms before start]
#include <windows.h>
#include <d2d1.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned s=1; static int r(int n){ s=s*1103515245+12345; return (s>>16)%n; }
int main(int argc,char**argv){
  int seed0=atoi(argv[1]), cnt=atoi(argv[2]); if(argc>3) Sleep(atoi(argv[3]));
  ID2D1Factory *f; D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,__uuidof(ID2D1Factory),0,(void**)&f);
  for(int seed=seed0; seed<seed0+cnt; seed++){
    s=seed; printf("seed %d\n",seed); fflush(stdout);
    ID2D1PathGeometry *g; f->CreatePathGeometry(&g); ID2D1GeometrySink *k; g->Open(&k);
    k->SetFillMode(r(2)?D2D1_FILL_MODE_WINDING:D2D1_FILL_MODE_ALTERNATE);
    int nf=1+r(4);
    for(int a=0;a<nf;a++){
      k->BeginFigure(D2D1::Point2F(r(6),r(6)),D2D1_FIGURE_BEGIN_FILLED);
      int nv=3+r(12);
      for(int b=0;b<nv;b++){ if(r(5)==0) k->AddBezier(D2D1::BezierSegment(D2D1::Point2F(r(6),r(6)),D2D1::Point2F(r(6),r(6)),D2D1::Point2F(r(6),r(6))));
        else k->AddLine(D2D1::Point2F(r(6),r(6))); }
      k->EndFigure(D2D1_FIGURE_END_CLOSED);
    }
    k->Close(); k->Release(); g->Release();
  }
  printf("DONE\n"); return 0;
}
