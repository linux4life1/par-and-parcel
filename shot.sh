#!/bin/sh
# Launch the game, wait a moment, save a screenshot, and quit.
#   ./shot.sh out.png [extra game args, e.g. --zoom=60 --fast=120]
# See _apply_test_args in scripts/view/main.gd for every switch.
cd "$(dirname "$0")"
OUT="$1"
shift
LOG="${TMPDIR:-/tmp}/parandparcel-shot.log"
godot --path . -- --shot="$OUT" "$@" >"$LOG" 2>&1 &
PID=$!
T=0
while kill -0 "$PID" 2>/dev/null; do
	sleep 1
	T=$((T + 1))
	if [ "$T" -ge "${LIMIT:-60}" ]; then
		kill -9 "$PID" 2>/dev/null
		echo "TIMED OUT"
		break
	fi
done
grep -E "ERROR|Parse Error|SCRIPT ERROR|^ +at: |DEMO" "$LOG" | grep -v -E "at: cleanup|at: clear|still in use|ObjectDB" | sort | uniq -c | head -30
