#!/bin/sh
# Build the game for macOS, Windows and Linux into build/.
# Needs Godot's export templates for this version, installed once from the
# editor: Editor menu, Manage Export Templates, Download and Install.
#   ./build.sh            all three
#   ./build.sh "Linux"    just one (preset names are in export_presets.cfg)
cd "$(dirname "$0")"
TEMPLATES="$HOME/Library/Application Support/Godot/export_templates"
[ -d "$HOME/.local/share/godot/export_templates" ] && TEMPLATES="$HOME/.local/share/godot/export_templates"
if [ ! -d "$TEMPLATES" ] || [ -z "$(ls "$TEMPLATES" 2>/dev/null)" ]; then
	echo "Godot's export templates are not installed, so nothing can be built yet."
	echo "Open the project in the Godot editor, then: Editor, Manage Export Templates, Download and Install."
	exit 1
fi
mkdir -p build
godot --headless --path . --import >/dev/null 2>&1
if [ -n "$1" ]; then
	godot --headless --path . --export-release "$1" 2>&1 | grep -E "ERROR|WARNING|Saving|savepack" | head -20
else
	for PRESET in "macOS" "Windows Desktop" "Linux"; do
		echo "== $PRESET"
		godot --headless --path . --export-release "$PRESET" 2>&1 | grep -E "ERROR|WARNING" | head -20
	done
fi
ls -la build
