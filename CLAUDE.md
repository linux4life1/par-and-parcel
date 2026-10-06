# Par & Parcel

A golf course builder, management sim and golf game in Godot 4.7, typed
GDScript. Explain changes in plain language and verify them by running the
game or the tests, not by reading the code back.

`docs/DESIGN.md` has the full feature list with status. Keep it current when
features land.

## Commands

```sh
./lint.sh       # every script parses. Run after any edit. Seconds.
./check.sh      # headless tests. `./check.sh full` prints everything.
./balance.sh    # two year economy ledger, about four minutes
./perf.sh tour  # frame times in the full-size window: still | pan | tour | ab
./build.sh      # export builds (needs Godot's export templates)
./linux.sh      # sync, test and screenshot on the owner's Linux box; `./linux.sh export` builds there
tools/mac_release.sh build/ParAndParcel.zip   # sign, notarize, staple, disk image (needs the Apple secrets in the environment)
tools/stamp_version.sh 1.2.0                  # version into project and presets
./shot.sh out.png [switches]   # launch, screenshot, quit
godot --path .  # play
```

`shot.sh` switches are listed above `_apply_test_args` in
`scripts/view/main.gd`. Screenshots are taken at 3 PM unless `--clock=hours`
says otherwise; `--lights=N` floodlights the first N holes.
`--demo=paint|hole|play|panels|start|saveload|biomes|camera|sound|gamepad`
(most want `--scenario=three_holes`, which has a course to work on)
drives the game with synthetic input, which is how the real input paths get
tested. A demo only runs as long as `--frames=N` lets it: panels needs about
1000, sound 1400, a played hole (`--play=0 --demo=play`) about 14000; the
play demo prints what the golfer is told before and after each shot.
`--demo=gamepad` ends itself, needs `LIMIT=150`, and takes `--menu` to test
the start screen. `--wind=mph` holds the wind for a screenshot or a round.

Looking at the graphics: `--models=60` puts one of everything on cleared
ground, `--look=<object number>` centres on the first object of a kind
(8 is the clubhouse), `--pitch`, `--yaw`, `--nohud`, `--quality=0..3`.
`--perf --frames=760` prints frame times.

```sh
python3 tools/make_foliage.py       # repaint the leaf, needle, frond and grass atlas
python3 tools/make_sounds.py        # remake every sound effect, voice and ambience loop (needs oggenc)
python3 tools/make_sounds.py facilities   # only the burp, flush and slurp
python3 -I tools/fetch_music.py     # download the CC0 music again (checksummed)
python3 -I tools/fetch_textures.py  # download the CC0 ground and building textures again
```

## Releasing

CI (`.github/workflows/ci.yml`) is lint plus `check.sh full` on Ubuntu. A
`v*` tag (`release.yml`) exports all three platforms and notarizes the Mac
build; the Apple secrets carry the same names as the owner's other repo.
The product is **Par & Parcel** (`Defs.TITLE`, `project.godot`,
`export_presets.cfg`); the folder keeps its old name. No Snap or Flathub:
the owner does not want them. The icon and disk image art come from
`tools/make_art.gd`; rerun it rather than editing the PNGs.

## Rules

- **The ball's physics and collisions are the game's own** (`ball.gd`,
  `solids.gd`, `data/solids.json`), deterministic, with no engine rigid
  bodies. The golfer AI simulates shots ahead with the same code. Anything
  that writes to `course.objects` directly must call
  `course.objects_touched(tile)`.
- **A new object needs four things:** its entries in the `Defs.O_*` tables,
  a model in `world_view.gd` (`_built`), collision shapes in
  `data/solids.json` under the same kind name, and a button in the build
  menu. A test checks that every solid object in every biome has shapes.
- **Golfers never stop for the night.** A round outlasts a day, so after dark
  they play on: unlit holes are less fun and pay less. Do not make darkness
  end a round.
- **The lie is read in one place** (`Lie.read`, numbers in `data/lies.json`)
  and used by the computer golfers' swing, the player's swing, the aiming
  preview and the play panel. Do not add a lie effect to one of them alone.
- **Out of bounds is decided when the ball stops** (`Ball._stop`), not when
  it lands: it may bounce or roll back in. The penalty is stroke and
  distance. Only a ball that leaves the map is out at once.
- **Gusts and eddies have their own random numbers** (`Weather._gust_rng`,
  `Ball.air_seed`). Never draw them from `sim.rng`: one extra draw changes
  every game that follows it, and the tests with it. A golfer planning a
  shot sees the steady wind; only a real shot gets eddies.
- **A controller works the interface through `Gamepad`'s pointer**, which
  sends mouse events. A new panel or button needs no pad code, but it must
  be reachable by a click and must fit on a 1600 by 900 screen.
- **The swing is one pass of one bar** (`PlayMode.press`, `stick`): start,
  set power, stop on the line, no retries, and the marker runs past the
  line if nobody presses. Anything that makes it easier (a wider window, a
  slower marker) must come from a golfer attribute, not a constant. The
  owner found the old meter "way too easy".
- **Difficulty multipliers come from `sim.diff(key)`** (`data/difficulty.json`).
  A golfer's mood factors are fields set by `Visitors.set_temper`; a new
  golfer kind that should be exempt (like `player` and `lab`) must be
  listed there. `grounds.gd` applies weeds, pests and wear.
- **Weeds follow the mood of the course** (`Grounds.weed_mood`), and weeds
  sour moods: the loop is intended. Anything that makes golfers unhappy
  therefore also costs turf; balance new mood penalties with that in mind.
- **Holes are capped by the clubhouse** (`Sim.hole_cap`, data in
  `data/clubhouse.json`). A test or demo that lays out a fourth hole must
  upgrade the clubhouse or use the sandbox. `--scroll=pixels` scrolls the
  open panel for a screenshot; the Build panel is taller than the screen.
- **Free Play starts empty.** Tests, screenshots and measuring scripts that
  need a course use the hidden `three_holes` scenario (the old free play).
  A scenario with `"hidden": true` is kept off the start screen.

- **The player never sets a price.** Golfers pay after each hole by how much
  they enjoyed it (`Visitors.collect_fee`). Do not add fee controls.
- **Every camera move must work with one mouse button and no wheel.** The
  owner uses a Magic Mouse. `--demo=camera` checks it.

- **`scripts/core/` has no rendering and no nodes.** It must run headless.
  Views read the `Sim`; they never hold game state.
- **Game content goes in `data/*.json`**, not in code.
- Metres and seconds inside; yards, feet, mph and Fahrenheit on screen.
- Tabs for indentation. Static types everywhere.
- When a feature lands, add a headless test for its rules in
  `tests/run_tests.gd`.

## Gotchas that have already cost time

- **A script parse error makes a headless run hang forever.** Never call
  `godot --headless` on a scene directly; use the `.sh` wrappers, which have
  watchdogs.
- New `class_name` scripts are invisible until `godot --headless --path .
  --import` runs. The wrappers do this.
- `var x := something_returning_Variant` is a parse error. Dictionary reads,
  untyped array reads and `min`/`max` return Variant. Write the type, or use
  `minf`, `maxi`, `float(...)`.
- Do not rebuild an `ImmediateMesh` every frame. It stalled frames by 100 ms
  on Metal. Use a pooled `MultiMesh` (see ball tracers in `world_view.gd`).
- `shot.sh` opens a real window on the owner's screen. Keep those runs few.
  An unfocused window is throttled by macOS, so frame timings from it are
  not trustworthy.
- `Label3D` with `fixed_size` still scales with its parent node.
- `visibility_range` margins leave a gap where neither level of detail shows
  if the camera lands inside the margin. Trees use none.
- In zsh, `for x in "a b"; do set -- $x` does not split words. Write test
  commands out one per line.
- A slice-and-replace edit in a script removed two functions that sat inside
  the slice. Before replacing a range of a file, print what is in it.
- Godot dispatches every `InputEventPanGesture` and `InputEventMagnifyGesture`
  twice. `CameraRig._fresh_gesture` drops the echo; any new gesture handler
  needs the same.
- `ViewportTexture.get_size()` on the root viewport is multiplied by the
  interface scale. For the real pixel count ask a captured image, or use
  the `--sizes` switch.
- To measure frame rate in the real full-size window, run without `--shot`:
  `godot --path . -- --exit --perf --frames=760 --scenario=three_holes`.
- **Check that lint passed before opening a window.** A broken script leaves
  the game sitting on an empty scene until the watchdog fires, once per run.
  Write `./lint.sh | grep -q "LINT OK" && ./shot.sh ...`.
- `Image.srgb_to_linear()` and `Image.premultiply_alpha()` only work on 8-bit
  images and fail quietly otherwise. Convert to float afterwards.
- Vertex colours and shader colour uniforms are linear. Colours in
  `flora.gd` are written as they look on screen and converted once by
  `_lin`. Leaf and bark textures are evened out to neutral first
  (`Surfaces.atlas_means`, `Surfaces.detail`), so the mesh sets the colour.
- Triangles wind clockwise when seen from the front. A mesh built by hand
  that looks dark or inside-out has its indices the other way round.
- The grass shader repeats the terrain shader's edge maths. Change the
  coverage or the edge wobble in one and you must change it in the other.
- **`lint.sh`, `check.sh`, `shot.sh` and `balance.sh` share log files in
  `$TMPDIR`.** Two runs at once overwrite each other's results. Give each
  parallel run its own `TMPDIR`.
- **One game is not a measurement.** Scores, fees and satisfaction from a
  single seed swing by a third either way, and any change to the physics
  reshuffles the luck. To judge a balance change, play thousands of holes
  with fixed golfers (`HoleLab.play_hole`) or run twenty or more seeds with
  events and weather held still, old code against new.
- **A full screen request is lost unless the game is the front app.** macOS
  records the mode and never makes the switch. `Game._fullscreen_once_open`
  waits for focus. Windows opened by an agent never get focus, so full
  screen cannot be tested from a script. Do not try `open -a Godot.app` to
  get focus: launched that way the game never started, twice, and had to be
  killed.
- **Running on the Linux box** (`./linux.sh`, host `mediaserver`, Godot in
  `~/opt/godot`, the project in `~/parandparcel`, display `:21`): a virtual display never signals a frame, so
  every run there needs `--novsync` or the game blocks on the first present.
  There is no sound server, so the audio driver falls back to a dummy; the
  "All audio drivers failed" warning is expected there. The box has no
  `rsync`: `linux.sh` copies with tar over ssh.
- **Display settings live in `Game`** (`fullscreen`, `window_size`,
  `render_lines`, `ui_scale`) and the Menu's Display card edits them. The
  interface is laid out for 1600 by 900 logical units; at 110% the top bar
  is full, so the interface size stops there. Try a size with
  `--uiscale=1.1`, which does not save it.
- The modal card does not scroll and the Menu is two columns now; keep
  each column under about 600 units at 1600 by 900, and check new dialogs
  in the default window size.
- `make_golfer` does not put a golfer on the course; only `_register` and
  `add_group` do. Anything that walks `visitors.golfers` (like
  `apply_difficulty`) misses a golfer made with `make_golfer` alone.

## Sound

- The simulation never plays anything. It emits `Sim.sound(id, pos, power)`
  and `scripts/view/sound_desk.gd` does the rest. A new sound needs an entry
  in `data/sounds.json` and a recipe in `tools/make_sounds.py`.
- **You cannot hear.** Check a sound by its printed numbers (length, peak,
  loudness, brightness) and by looking at its spectrogram
  (`ffmpeg -i x.ogg -lavfi showspectrumpic x.png`), then say plainly that
  the owner has to judge it by ear.
- Test runs are muted (`--shot` or `--exit`); pass `--sound` to hear one.
  `--demo=sound` plays all 47 effects and reads the bus meters, which work
  even when muted. `--soundcheck` prints Sound-bus peaks for the golf sounds
  and voices at four zooms, and `--soundlog` prints announced-against-played
  counts at exit.
- **All audio is Ogg Vorbis**, as the owner asked, encoded with the
  reference encoder (`oggenc`, from `brew install vorbis-tools`): effects at
  quality 8, ambience beds at 6, music at 8. Never use ffmpeg's built-in
  Vorbis encoder, and never MP3. Music the composer published as Ogg is used
  untouched, and must be human-made and CC0. A test fails if any other audio
  format is left in `assets/sounds` or `assets/music`.
- Short effects are decoded once at load (`SoundDesk._unpacked`). Do not
  play an Ogg effect directly: starting a decoder costs 0.2 ms on the main
  thread. `python3 tools/make_sounds.py voices` remakes only the later
  sounds.
- Chatter is driven from the view (`SoundDesk` scans groups near the
  camera), so it never touches the simulation's random numbers.

## Performance

The target is 120 fps and the owner checks. Measure with `./perf.sh`, never
with the `delta` the engine hands to scripts: that is smoothed and hides
slow frames. `./perf.sh ab --ab=shadow,trees,...` prices parts of the picture
by switching them off and on inside one run. Check what else the machine is
doing first (`top`, and GPU use with
`ioreg -r -d 1 -c IOAccelerator | grep "Device Utilization"`): a busy
machine halves the numbers and no setting fixes that. The "GPU" line from
Apple's Metal log does not track workload (the chip slows itself down when
it has time to spare), so compare wall-clock frame times and late frames.
The owner has Apple's Metal overlay on, so every test window shows them an
fps counter: an unfocused or deliberately heavy test run looks like a slow
game to them. Say so when it matters.

## Looks matter

Visual quality is a requirement, not polish. Judge every visual change from
screenshots at three distances (about 15, 60 and 400 metres), in all four
biomes and in more than one season (`--day=0` is March, `--day=200` is
mid-October) before calling it done.
