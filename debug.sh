#!/bin/sh
# Run tests/debug.gd headless with a watchdog. A scratch pad for investigations.
cd "$(dirname "$0")"
LOG="${TMPDIR:-/tmp}/parandparcel-debug.log"
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . res://tests/debug.tscn >"$LOG" 2>&1 &
PID=$!
T=0
while kill -0 "$PID" 2>/dev/null; do
	sleep 1
	T=$((T + 1))
	if [ "$T" -ge "${LIMIT:-120}" ]; then
		kill -9 "$PID" 2>/dev/null
		echo "TIMED OUT"
		break
	fi
done
grep -v -E "^$|ObjectDB|still in use|at: cleanup|at: clear|^Godot" "$LOG" | cut -c1-400 | head -${LINES_MAX:-60}
