#!/bin/sh
# Fast check that every script parses. Usage: ./lint.sh
cd "$(dirname "$0")"
LOG="${TMPDIR:-/tmp}/parandparcel-lint.log"
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . res://tests/lint.tscn >"$LOG" 2>&1 &
PID=$!
T=0
while kill -0 "$PID" 2>/dev/null; do
	sleep 1
	T=$((T + 1))
	if [ "$T" -ge "${LINT_LIMIT:-25}" ]; then
		kill -9 "$PID" 2>/dev/null
		echo "LINT TIMED OUT"
		break
	fi
done
grep -E "Parse Error|^ +at: GDScript|LINT" "$LOG" | grep -v "Failed to compile depended" | head -30
