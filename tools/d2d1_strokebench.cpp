// JUCE-artige Last: pro Frame neue Pfade (Wellenform/Huellkurve) bauen und nur umranden
#include <windows.h>
#include <d2d1.h>
#include <wincodec.h>
#include <stdio.h>
#include <math.h>
static double now(){LARGE_INTEGER f,c;QueryPerformanceFrequency(&f);QueryPerformanceCounter(&c);return c.QuadPart*1000.0/f.QuadPart;}
int main(int argc,char**argv){
  int N=atoi(argv[1]), segs=atoi(argv[2]); int bez=argc>3?atoi(argv[3]):0;
  CoInitialize(0); IWICImagingFactory *wic; CoCreateInstance(CLSID_WICImagingFactory,0,CLSCTX_INPROC_SERVER,IID_IWICImagingFactory,(void**)&wic);
  IWICBitmap *bmp; wic->CreateBitmap(800,400,GUID_WICPixelFormat32bppPBGRA,WICBitmapCacheOnLoad,&bmp);
  ID2D1Factory *f; D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,__uuidof(ID2D1Factory),0,(void**)&f);
  ID2D1RenderTarget *rt; f->CreateWicBitmapRenderTarget(bmp,D2D1::RenderTargetProperties(),&rt);
  ID2D1SolidColorBrush *br; rt->CreateSolidColorBrush(D2D1::ColorF(0,1,1),&br);
  ID2D1StrokeStyle *ss; f->CreateStrokeStyle(D2D1::StrokeStyleProperties(D2D1_CAP_STYLE_ROUND,D2D1_CAP_STYLE_ROUND,D2D1_CAP_STYLE_ROUND,D2D1_LINE_JOIN_ROUND),0,0,&ss);
  double tb=0,tc=0,td=0;
  for(int i=0;i<N;i++){
    double a=now(); ID2D1PathGeometry *g; f->CreatePathGeometry(&g); ID2D1GeometrySink *s; g->Open(&s);
    s->BeginFigure(D2D1::Point2F(0,200),D2D1_FIGURE_BEGIN_HOLLOW);
    for(int j=1;j<=segs;j++){ float x=j*800.f/segs, y=200+150*sinf(j*0.07f+i*0.1f);
      if(bez) s->AddBezier(D2D1::BezierSegment(D2D1::Point2F(x-2,y-5),D2D1::Point2F(x-1,y+5),D2D1::Point2F(x,y))); else s->AddLine(D2D1::Point2F(x,y)); }
    s->EndFigure(D2D1_FIGURE_END_OPEN);
    double b=now(); s->Close(); s->Release(); double c=now();
    if(i==0)rt->BeginDraw(); rt->DrawGeometry(g,br,1.5f,ss); if(i==N-1)rt->EndDraw(); double d=now();
    g->Release(); tb+=b-a; tc+=c-b; td+=d-c;
  }
  printf("segs=%d bez=%d: Aufbau %.3f ms, Close %.3f ms, Draw %.3f ms pro Pfad\n",segs,bez,tb/N,tc/N,td/N);
}
