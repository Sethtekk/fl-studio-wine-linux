# Test and diagnostic tools (Windows binaries, cross-built with MinGW)
#
#   make            builds all tools into build/
#   make CLAP_INC=… path to the CLAP headers (https://github.com/free-audio/clap)
#
# Run under Wine, e.g.:
#   wine build/clap_guitest.exe "C:\\Program Files\\Common Files\\CLAP\\Diopser.clap" 10
#   wine build/vst2_guitest.exe "C:\\VST\\CamelCrusher.dll" 10
#   WINEDLLOVERRIDES=d2d1=n wine build/d2d1_fuzz.exe 1 10000

CC       := x86_64-w64-mingw32-gcc
CXX      := x86_64-w64-mingw32-g++
CLAP_INC ?= clap/include
OUT      := build

all: $(OUT)/clap_guitest.exe $(OUT)/vst2_guitest.exe $(OUT)/d2d1_fuzz.exe $(OUT)/d2d1_strokebench.exe

$(OUT):
	mkdir -p $@

$(OUT)/clap_guitest.exe: clap_guitest.c | $(OUT)
	$(CC) -O2 -I$(CLAP_INC) -o $@ $< -luser32 -lgdi32 -static

$(OUT)/vst2_guitest.exe: vst2_guitest.c | $(OUT)
	$(CC) -O2 -o $@ $< -luser32 -lgdi32 -static

$(OUT)/d2d1_fuzz.exe: d2d1_fuzz.cpp | $(OUT)
	$(CXX) -O2 -o $@ $< -ld2d1 -static

$(OUT)/d2d1_strokebench.exe: d2d1_strokebench.cpp | $(OUT)
	$(CXX) -O2 -o $@ $< -ld2d1 -lole32 -luuid -lwindowscodecs -static

clean:
	rm -rf $(OUT)

.PHONY: all clean
