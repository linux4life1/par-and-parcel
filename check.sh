#!/bin/sh
# Rebuild Godot's class cache, run the headless tests, and print the result.
# A script error can leave Godot waiting forever, so a watchdog stops it.
#   ./check.sh            summary only
#   ./check.sh full       everything the tests print
cd "$(dirname "$0")"
LOG="${TMPDIR:-/tmp}/parandparcel-test.log"
LIMIT="${LIMIT:-150}"
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . res://tests/run_tests.tscn >"$LOG" 2>&1 &
PID=$!
T=0
while kill -0 "$PID" 2>/dev/null; do
	sleep 1
	T=$((T + 1))
	if [ "$T" -ge "$LIMIT" ]; then
		kill -9 "$PID" 2>/dev/null
		echo "TIMED OUT after ${LIMIT}s (usually a script error; see below)"
		break
	fi
done
if [ "$1" = "full" ]; then
	grep -v "^$" "$LOG" | grep -v -E "ObjectDB instances|resources still in use|at: cleanup|at: clear"
else
	grep -E "Parse Error|SCRIPT ERROR|^ +at: |FAIL|checks," "$LOG" | grep -v -E "Failed to compile depended|at: cleanup|at: clear" | head -40
fi
