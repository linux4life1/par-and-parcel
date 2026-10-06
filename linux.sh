#!/bin/sh
# Run Par & Parcel on the Linux box and bring the results back.
#   ./linux.sh            sync, lint, headless tests, four demos, screenshots into build/linux-shots
#   ./linux.sh sync       copy the project over only
#   ./linux.sh shot out.png [switches]    one screenshot run on the Linux display
#   ./linux.sh export     export a Linux build there and run it once
# The box is reached as "$LINUX_HOST" (default mediaserver, from ~/.ssh/config).
# It has Godot under ~/opt/godot and a GPU-backed virtual display, started by
# this script if need be (TigerVNC's Xvnc on :21, loopback only, port 5921).
# A virtual display never signals a frame, so every run there needs
# --novsync; without a sound server the audio driver falls back to a dummy.
cd "$(dirname "$0")"
HOST="${LINUX_HOST:-mediaserver}"
R='cd ~/parandparcel && export PATH=$HOME/opt/godot:$PATH DISPLAY=:21 TMPDIR=$HOME/simgolf-tmp && mkdir -p ~/parandparcel-tmp ~/parandparcel-shots'
MODE="${1:-all}"

sync_project() {
	echo "== syncing to $HOST"
	ssh "$HOST" 'mkdir -p ~/parandparcel ~/parandparcel-tmp' || exit 1
	tar czf - --exclude .godot --exclude build --exclude "*.orig" --exclude "*.rej" . | ssh "$HOST" 'tar xzf - -C ~/parandparcel' 2>&1 | grep -v LIBARCHIVE
}

display_up() {
	ssh "$HOST" 'pgrep -f "Xvnc :21" >/dev/null || { cat > ~/parandparcel-tmp/xvnc21.sh <<"X"
#!/bin/sh
exec Xvnc :21 -geometry 1920x1080 -depth 24 -dpi 96 -rfbport 5921 -localhost -SecurityTypes None -desktop parandparcel
X
chmod +x ~/parandparcel-tmp/xvnc21.sh; setsid nohup ~/parandparcel-tmp/xvnc21.sh > ~/parandparcel-tmp/xvnc21.log 2>&1 < /dev/null & sleep 2; }; DISPLAY=:21 xdpyinfo >/dev/null 2>&1 && echo "display :21 up" || echo "display :21 NOT up"'
}

case "$MODE" in
	sync)
		sync_project ;;
	shot)
		shift
		OUT="$1"
		shift
		display_up
		ssh "$HOST" "$R && LIMIT=${LIMIT:-120} ./shot.sh ~/parandparcel-shots/remote.png --novsync $*" | cut -c1-200
		scp -q "$HOST:~/parandparcel-shots/remote.png" "$OUT" && echo "saved $OUT" ;;
	export)
		display_up
		ssh "$HOST" "$R"' && V=4.7.2.stable && T=~/.local/share/godot/export_templates/$V && if [ ! -f "$T/linux_release.x86_64" ]; then echo "== fetching export templates"; mkdir -p ~/opt/godot-dl "$T" && cd ~/opt/godot-dl && [ -s Godot_v4.7.2-stable_export_templates.tpz ] || curl -sSL -o Godot_v4.7.2-stable_export_templates.tpz https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz; grep "stable_export_templates.tpz" SHA512-SUMS.txt | grep -v mono | sha512sum -c - && unzip -o -q Godot_v4.7.2-stable_export_templates.tpz -d ~/opt/godot-dl/tpl && mv ~/opt/godot-dl/tpl/templates/* "$T"/; fi; cd ~/parandparcel && mkdir -p build/linux && godot --headless --path . --import >/dev/null 2>&1; godot --headless --path . --export-release "Linux" build/linux/simgolf.x86_64 2>&1 | grep -v "ObjectDB\|still in use\|at: " | tail -5; ls -la build/linux/ && echo "== running the export" && timeout 180 build/linux/simgolf.x86_64 --audio-driver Dummy -- --exit --frames=300 --sizes --novsync --scenario=three_holes --seed=7 2>&1 | grep "DEMO\|Vulkan\|ERROR" | grep -v "ObjectDB\|still in use" | head -6' ;;
	all)
		sync_project
		display_up
		echo "== lint and headless tests"
		ssh "$HOST" "$R"' && ./lint.sh | tail -1 && LIMIT=600 ./check.sh full > ~/parandparcel-tmp/check_linux.log 2>&1; grep -n "FAIL\|checks,\|SCRIPT ERROR\|Parse\|TIMED" ~/parandparcel-tmp/check_linux.log | head -20'
		echo "== demos on the Linux display"
		ssh "$HOST" "$R"' && for d in "play --play=0 --frames=3300 --fast=60 --weather=1" "panels --frames=1000" "camera --frames=1000" "gamepad"; do set -- $d; name=$1; shift; echo "--- $name"; LIMIT=150 ./shot.sh ~/parandparcel-shots/$name.png --scenario=three_holes --seed=7 --novsync --demo=$name "$@" 2>&1 | grep -v "audio_server\|audio_driver_alsa\|ERR_CANT_OPEN" | cut -c1-200 | tail -30; done'
		mkdir -p build/linux-shots
		scp -q "$HOST:~/parandparcel-shots/*.png" build/linux-shots/ && echo "screenshots in build/linux-shots/" ;;
	*)
		echo "usage: ./linux.sh [all|sync|shot out.png switches|export]"; exit 2 ;;
esac
