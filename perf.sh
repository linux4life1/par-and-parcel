#!/bin/sh
# Measure how smoothly the game runs, in its normal full-size window.
#   ./perf.sh [still|pan|tour|ab] [extra game args, e.g. --zoom=60 --quality=3 --off=shadow]
# Prints wall-clock frame times and hitches (scripts/view/perf_probe.gd), and
# the GPU's own time per frame as reported by Apple's Metal diagnostics.
# The GPU figure is the one to compare between runs: it does not depend on
# vsync, and it is far less disturbed by whatever else the machine is doing.
#   BRIEF=1 ./perf.sh ...   prints only the GPU line
cd "$(dirname "$0")"
MODE="${1:-tour}"
[ $# -gt 0 ] && shift
LOG="${TMPDIR:-/tmp}/parandparcel-perf.log"
MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1 godot --path . -- --exit --perf="$MODE" --scenario=three_holes --seed=7 --fast=300 --weather=0 --holdrate=0 "$@" >"$LOG" 2>&1 &
PID=$!
T=0
while kill -0 "$PID" 2>/dev/null; do
	sleep 1
	T=$((T + 1))
	if [ "$T" -ge "${LIMIT:-90}" ]; then
		kill -9 "$PID" 2>/dev/null
		echo "TIMED OUT"
		break
	fi
done
[ -z "$BRIEF" ] && grep -E "^PERF|SCRIPT ERROR|Parse Error" "$LOG" | cut -c1-260
python3 - "$LOG" <<'PY'
import sys
gpu, gap = [], []
for line in open(sys.argv[1], errors="replace"):
    at = line.find("metal-HUD:")
    if at < 0:
        continue
    f = line[at + 10:].strip().split(",")[3:]
    for i in range(0, len(f) - 1, 2):
        try:
            gap.append(float(f[i]))
            gpu.append(float(f[i + 1]))
        except ValueError:
            pass
# drop the first three seconds: loading and warm-up
skip = 0
total = 0.0
for i, g in enumerate(gap):
    total += g
    if total > 3000.0:
        skip = i
        break
gpu, gap = gpu[skip:], gap[skip:]
if len(gpu) < 30:
    print("GPU  no Metal figures in the log")
else:
    s = sorted(gpu)
    late = sum(1 for g in gap if g > 9.0)
    print("GPU  typical %.2f ms, slowest 5%% %.2f ms, worst %.1f ms  |  frames shown late %d%% of %d" % (
        s[len(s) // 2], s[int(len(s) * 0.95)], s[-1], round(100.0 * late / len(gap)), len(gap)))
PY
