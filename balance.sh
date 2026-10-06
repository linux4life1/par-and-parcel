#!/bin/sh
# Print a two year ledger for three management styles. Takes a few minutes.
#   ./balance.sh --quick   ten months of one lean plan, about a minute
cd "$(dirname "$0")"
LOG="${TMPDIR:-/tmp}/parandparcel-balance.log"
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . res://tests/balance.tscn -- "$@" >"$LOG" 2>&1 &
PID=$!
T=0
while kill -0 "$PID" 2>/dev/null; do
	sleep 2
	T=$((T + 2))
	if [ "$T" -ge "${LIMIT:-420}" ]; then
		kill -9 "$PID" 2>/dev/null
		echo "TIMED OUT"
		break
	fi
done
grep -v -E "^$|ObjectDB|still in use|at: cleanup|at: clear|^Godot" "$LOG"
