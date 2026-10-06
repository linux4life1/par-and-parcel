#!/bin/sh
# Write a version into the project and the export presets: tools/stamp_version.sh 1.2.0
set -eu
V="${1:?version}"
cd "$(dirname "$0")/.."
sed -i.bak -E "s/^application\/short_version=.*/application\/short_version=\"$V\"/; s/^application\/version=.*/application\/version=\"$V\"/" export_presets.cfg
W="$V"
case "$W" in *.*.*.*) ;; *.*.*) W="$V.0" ;; *.*) W="$V.0.0" ;; *) W="$V.0.0.0" ;; esac
sed -i.bak -E "s/^application\/file_version=.*/application\/file_version=\"$W\"/; s/^application\/product_version=.*/application\/product_version=\"$W\"/" export_presets.cfg
if grep -q '^config/version=' project.godot; then
	sed -i.bak -E "s/^config\/version=.*/config\/version=\"$V\"/" project.godot
else
	sed -i.bak -E "s/^config\/name=(.*)$/config\/name=\1\nconfig\/version=\"$V\"/" project.godot
fi
rm -f export_presets.cfg.bak project.godot.bak
grep -n "version" export_presets.cfg project.godot | head -5
