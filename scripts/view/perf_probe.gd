class_name PerfProbe
extends Node
## Measures how smoothly the game really runs. Started by --perf.
##
## Frame times are taken from the wall clock, not from the `delta` the
## engine hands to scripts: that value is smoothed toward the display's
## refresh rate and hides both slow frames and hitches.
##
##   --perf=still   camera held where it is
##   --perf=pan     camera slides back and forth across the course
##   --perf=tour    slides, turns and zooms, the way a person looks around
##   --perf=ab      camera held still while parts of the picture are switched
##                  off and on in turn, to price each one: --ab=terrain,shadow,...
##   --perfsecs=N   how long to measure, after a short warm-up (default 10)
##   --off=a,b      switch parts of the picture off for the whole run
##                  (names as in _ab_set: terrain, shadow, grass, trees, ...)

const WARMUP := 3.0
## A frame this much longer than the typical one is a hitch you can see.
const HITCH := 1.6

var rig: CameraRig
var main: Node                  # the scene root, for switching parts of the picture off
var mode := "still"
var seconds := 10.0
var done := false
var _last := 0
var _clock := 0.0
var _frames := PackedFloat32Array()       # milliseconds, one per frame
var _rows: Array[Dictionary] = []         # what the scripts spent in each frame
var _dir := 1.0
var _phase := 0.0
var _draws := 0.0
var _prims := 0.0
var _started := false
# pricing parts of the picture
var _ab_list: Array = []
var _ab_i := -1
var _ab_on := true
var _ab_t := 0.0
var _ab_skip := 0
var _ab_with := PackedFloat32Array()
var _ab_without := PackedFloat32Array()
const AB_SLICE := 0.6          # seconds in each state before flipping
const AB_FLIPS := 12           # states measured per part
var _ab_flips := 0


func _ready() -> void:
	# run after everything else, so a frame's script costs are all in
	process_priority = 1000
	mode = str(Game.args.get("perf", "still"))
	if mode == "1":
		mode = "still"
	seconds = float(Game.args.get("perfsecs", "10"))
	if mode == "ab":
		_ab_list = str(Game.args.get("ab", "terrain,shadow,grass,trees,people,ssao,ssil,dof,glow,fog,msaa")).split(",")


func _process(delta: float) -> void:
	if done or Game.sim == null or rig == null:
		return
	var now := Time.get_ticks_usec()
	var took := (now - _last) / 1000.0
	_last = now
	_clock += took / 1000.0 if _started else 0.0
	if not _started:
		_started = true
		Game.prof_frame.clear()
		for what: String in str(Game.args.get("off", "")).split(",", false):
			_ab_set(what, false)
		return
	if mode == "ab":
		if _clock >= WARMUP:
			_ab_step(took)
		return
	_drive(delta)
	if _clock >= WARMUP:
		_frames.append(took)
		var row := Game.prof_frame.duplicate()
		row["steps"] = Game.steps_this_frame
		_rows.append(row)
		_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	Game.prof_frame.clear()
	if _clock >= WARMUP + seconds:
		done = true
		_report()
		if Game.args.has("exit") or Game.args.has("shot"):
			get_tree().quit()


## Move the camera the way the chosen test asks.
func _drive(delta: float) -> void:
	if mode == "still" or rig.course == null:
		return
	var size := rig.course.size_m()
	rig.follow = null
	# slide across at the speed of a held arrow key
	rig.focus.x += _dir * rig.dist * 0.9 * delta
	if rig.focus.x > size.x * 0.86:
		_dir = -1.0
	elif rig.focus.x < size.x * 0.14:
		_dir = 1.0
	if mode == "tour":
		_phase += delta
		rig.focus.z = size.y * (0.5 + 0.3 * sin(_phase * 0.23))
		rig.yaw += 0.35 * delta
		rig.target_dist = lerpf(30.0, 320.0, 0.5 + 0.5 * sin(_phase * 0.31))


## Switch one part of the picture on or off.
func _ab_set(what: String, on: bool) -> void:
	var m := main
	match what:
		"terrain":
			m.terrain.visible = on
		"shadow":
			m.sky.sun.shadow_enabled = on
		"grass":
			m.grass.visible = on
		"trees":
			m.world._obj_root.visible = on
		"people":
			m.world._people_root.visible = on
		"ssao":
			m.sky.env.ssao_enabled = on
		"ssil":
			m.sky.env.ssil_enabled = on
		"dof":
			m.sky._dof_allowed = on
		"glow":
			m.sky.env.glow_enabled = on
		"fog":
			m.sky.env.fog_enabled = on
		"msaa":
			get_viewport().msaa_3d = Viewport.MSAA_4X if on else Viewport.MSAA_DISABLED
		"msaa2":
			get_viewport().msaa_3d = Viewport.MSAA_4X if on else Viewport.MSAA_2X
		"fxaa":
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if on else Viewport.SCREEN_SPACE_AA_DISABLED
		"softsun":
			m.sky.soft_sun = on
		"softq":
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if on else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		"softmed":
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if on else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		"dofq":
			RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_MEDIUM if on else RenderingServer.DOF_BLUR_QUALITY_VERY_LOW, false)
		"splits":
			m.sky.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if on else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		"atlas":
			RenderingServer.directional_shadow_atlas_set_size(8192 if on else 4096, true)
		"aniso":
			m.terrain.material.set_shader_parameter("detail_on", 1.0 if on else 0.0)
		"hud":
			m.hud.visible = on
		"sky":
			m.sky.env.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR


static func _median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	return v[v.size() / 2]


## Flip one part off and on several times with the camera still, and compare
## the typical frame in each state. Flipping within one run cancels the
## drift that makes separate runs incomparable.
func _ab_step(took: float) -> void:
	if _ab_i < 0:
		_ab_i = 0
		_ab_on = false
		_ab_set(str(_ab_list[0]), false)
		_ab_skip = 10
		_ab_t = 0.0
		return
	if _ab_skip > 0:
		_ab_skip -= 1
		return
	if _ab_on:
		_ab_with.append(took)
	else:
		_ab_without.append(took)
	_ab_t += took / 1000.0
	if _ab_t < AB_SLICE:
		return
	_ab_t = 0.0
	_ab_flips += 1
	var what := str(_ab_list[_ab_i])
	if _ab_flips >= AB_FLIPS:
		var with_ms := _median(_ab_with)
		var without_ms := _median(_ab_without)
		print("PERF part %-8s costs %5.2f ms  (frame %.2f ms with it, %.2f ms without)" % [what, with_ms - without_ms, with_ms, without_ms])
		_ab_set(what, true)
		_ab_with.clear()
		_ab_without.clear()
		_ab_flips = 0
		_ab_i += 1
		if _ab_i >= _ab_list.size():
			done = true
			if Game.args.has("exit") or Game.args.has("shot"):
				get_tree().quit()
			return
		_ab_on = false
		_ab_set(str(_ab_list[_ab_i]), false)
		_ab_skip = 10
		return
	_ab_on = not _ab_on
	_ab_set(what, _ab_on)
	_ab_skip = 10


func _report() -> void:
	var n := _frames.size()
	if n < 10:
		print("PERF too few frames to judge")
		return
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for v in _frames:
		total += v
	var avg := total / n
	var median := sorted[n / 2]
	var p99 := sorted[mini(n - 1, int(n * 0.99))]
	var worst := sorted[n - 1]
	var hitches := 0
	var over_16 := 0
	var over_33 := 0
	for v in _frames:
		if v > median * HITCH:
			hitches += 1
		if v > 16.7:
			over_16 += 1
		if v > 33.4:
			over_33 += 1
	var win := get_window()
	print("PERF %s, %s preset, window %s, 3D ended at %.2f and governor level %d, focused %s, %d golfers" % [
		mode, Game.QUALITY_NAMES[Game.quality], str(win.size), get_viewport().scaling_3d_scale, int(main._gov_level),
		str(DisplayServer.window_is_focused()), Game.sim.visitors.golfers.size()])
	print("PERF frames %d in %.1f s: average %.1f fps, typical frame %.2f ms (%.0f fps), slowest 1%% %.2f ms (%.0f fps), worst %.1f ms" % [
		n, total / 1000.0, 1000.0 / avg, median, 1000.0 / median, p99, 1000.0 / p99, worst])
	print("PERF hitches (frames over %.1fx typical): %d, over 16.7 ms: %d, over 33 ms: %d" % [HITCH, hitches, over_16, over_33])
	print("PERF drawn per frame: %d draw calls, %d thousand triangles" % [int(_draws / n), int(_prims / n / 1000.0)])
	# where the scripts spend their time
	var sums := {}
	for row in _rows:
		for key: String in row:
			if key != "steps":
				sums[key] = float(sums.get(key, 0.0)) + float(row[key]) / 1000.0
	var keys := sums.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(sums[a]) > float(sums[b]))
	var line := ""
	var script_total := 0.0
	for key: String in keys:
		if not key.contains("."):
			script_total += float(sums[key]) / n
		line += "%s %.2f  " % [key, float(sums[key]) / n]
	print("PERF scripts average %.2f ms a frame: %s" % [script_total, line])
	# the worst frames, and what the scripts were doing in them
	var order := range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return _frames[a] > _frames[b])
	for k in mini(8, n):
		var i: int = order[k]
		if _frames[i] <= median * HITCH and k > 2:
			break
		var row := _rows[i]
		var parts := ""
		var spent := 0.0
		var rkeys := row.keys()
		rkeys.erase("steps")
		rkeys.sort_custom(func(a: String, b: String) -> bool: return float(row[a]) > float(row[b]))
		for key: String in rkeys:
			if not key.contains("."):
				spent += float(row[key]) / 1000.0
			if float(row[key]) > 300.0:
				parts += "%s %.1f  " % [key, float(row[key]) / 1000.0]
		print("PERF   frame %4d at %.1f s: %.1f ms, scripts %.1f ms (%s), sim steps %d" % [
			i, _when(i), _frames[i], spent, parts.strip_edges(), int(row.get("steps", 0))])


func _when(index: int) -> float:
	var t := 0.0
	for i in index:
		t += _frames[i]
	return t / 1000.0
