#!/bin/bash
# ============================================================
# Logs a running FL Studio every 2 seconds:
#   Main%    CPU of FL's main (UI) thread, in % of one core
#   FL%      CPU of the whole FL process
#   WS%      CPU of the wineserver
#   CSW/s    context switches per second of the main thread
#   RSS_GB   memory of the FL process
#   ERR_FL / ERR_IN   PipeWire error counters (xruns) of FL and the
#                     audio interface input, BUSY_FL = FL's busy time
#
# How to read it:
#   Main% high with normal CSW/s   -> something draws or computes in the UI
#                                     thread (e.g. a visualizer plugin)
#   Main% 0 and no progress        -> deadlock, see docs/troubleshooting.md
#   WS% far above normal (e.g. 80 % instead of ~15 %), UI not responding
#                                  -> message storm between FL and another
#                                     window (e.g. the Gopher WebView2 panel)
#   CSW/s alone says little: ~20,000/s is normal for a running FL; compare
#   against a run of your own setup.
#
#   bash tools/fl-perf-log.sh [seconds]      (default 600)
# ============================================================
export LC_ALL=C
P=$(pgrep -f 'FL64\.exe' | while read -r p; do grep -qa 'webview' /proc/"$p"/cmdline || { echo "$p"; break; }; done)
[ -n "$P" ] || { echo "FL Studio is not running"; exit 1; }
WS=$(pgrep -x wineserver | head -1); DUR=${1:-600}; HZ=$(getconf CLK_TCK)
tick() { awk '{print $14+$15}' "$1" 2>/dev/null; }
csw()  { awk '/^voluntary_ctxt_switches/{print $2}' "$1" 2>/dev/null; }
printf "%-8s %6s %6s %6s %7s %6s %7s %7s %8s\n" Time Main% FL% WS% CSW/s RSS_GB ERR_FL ERR_IN BUSY_FL
pm=$(tick /proc/$P/task/$P/stat); pa=$(tick /proc/$P/stat); pw=$(tick /proc/$WS/stat); pc=$(csw /proc/$P/task/$P/status)
end=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt $end ] && [ -d /proc/$P ]; do
  sleep 2
  m=$(tick /proc/$P/task/$P/stat); a=$(tick /proc/$P/stat); w=$(tick /proc/$WS/stat); c=$(csw /proc/$P/task/$P/status)
  s=$(pw-top -b -n 2 2>/dev/null | tail -40)
  ef=$(echo "$s" | grep -F '+ FL64' | tail -1 | awk '{print $9}'); bf=$(echo "$s" | grep -F '+ FL64' | tail -1 | awk '{print $6}')
  ei=$(echo "$s" | grep -F 'input' | grep -v FL64 | tail -1 | awk '{print $9}')
  printf "%-8s %6d %6d %6d %7d %6.2f %7s %7s %8s\n" "$(date +%T)" $(( (m-pm)*100/(2*HZ) )) $(( (a-pa)*100/(2*HZ) )) $(( (w-pw)*100/(2*HZ) )) \
    $(( (c-pc)/2 )) "$(awk '/VmRSS/{print $2/1048576}' /proc/$P/status)" "$ef" "$ei" "$bf"
  pm=$m; pa=$a; pw=$w; pc=$c
done
