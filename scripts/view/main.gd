extends Node3D
## The scene root: builds the 3D world and the interface, and wires them to
## whichever simulation is running.

var terrain := TerrainView.new()
var grass := GrassView.new()
var world := WorldView.new()
var crowd := CrowdView.new()    # the gallery at a tournament
var fx := FxView.new()          # sand, turf, water and ember bursts
var rig := CameraRig.new()
var sky := WeatherView.new()
var volcano := VolcanoView.new()
var tools := BuildTools.new()
var play := PlayMode.new()
var hud := Hud.new()
var desk := SoundDesk.new()
var pad := Gamepad.new()
var _shot_frames := -1
var _autosave_month := -1
var _demo := ""
var _demo_t := 0.0
var _demo_step := 0
var _demo_mem := {}
var _hinted := false
var _scale_cap := 1.0          # the sharpest the preset allows the 3D picture to be
var _scale_now := 1.0
const GOV_LEVELS := 4
const GOV_WINDOW := 120        # frames looked at
var _gov_level := 0            # how far the governor has dialled the picture back
var _gov_last := 0
var _gov_late: Array[bool] = []
var _gov_late_n := 0
var _gov_i := 0
var _gov_samples := -360       # frames counted since the last change; starts negative to skip loading
var _gov_clean := 0.0          # seconds since the last late frame
var _gov_wait := 10.0          # clean seconds needed before stepping back up
var _gov_raised := 99.0        # seconds since the last step back up
var _gov_trial := -1           # late frames that prompted the last step down, while it is being judged
var _gov_suspend := 0.0        # seconds the governor is standing down
var _gov_rest := 30.0          # how long it stands down after a step that did not help


func _ready() -> void:
	add_child(sky)
	add_child(terrain)
	add_child(grass)
	add_child(world)
	add_child(crowd)
	add_child(fx)
	add_child(volcano)
	add_child(rig)
	add_child(tools)
	add_child(play)
	add_child(hud)
	add_child(desk)
	add_child(pad)
	pad.hud = hud
	pad.rig = rig
	pad.tools = tools
	pad.play = play
	pad.world = world
	sky.lightning.connect(desk.thunder)
	rig.cam.attributes = sky.lens
	tools.terrain = terrain
	tools.rig = rig
	tools.world = world
	hud.tools = tools
	hud.play = play
	hud.rig = rig
	hud.world = world
	hud.terrain = terrain
	tools.selection_changed.connect(hud.inspect)
	tools.hole_added.connect(func(_i: int) -> void: hud.open_dock("holes"))
	play.started.connect(func() -> void:
		tools.set_mode("")
		tools.enabled = false
		hud.close_dock())
	play.ended.connect(func() -> void: tools.enabled = true)
	play.round_done.connect(hud.show_round_summary)
	hud.new_game_requested.connect(func(id: String, biome_id: String) -> void:
		Game.new_game(id, 0, biome_id)
		_hint_controls())
	Game.sim_changed.connect(_on_sim_changed)
	if Game.args.has("perf"):
		var probe := PerfProbe.new()
		probe.rig = rig
		probe.main = self
		add_child(probe)
	Game.quality_changed.connect(_apply_quality)
	get_window().size_changed.connect(_apply_quality)
	_apply_quality()

	var scripted := Game.args.has("shot") or Game.args.has("scenario")
	var scen: String = Game.args.get("scenario", "three_holes")
	Game.new_game(scen, int(Game.args.get("seed", "0")), str(Game.args.get("biome", "")))
	if not scripted:
		hud.show_scenarios(true)
	_apply_test_args()


## Once per launch, as the first game starts: how to work the camera with
## whatever is plugged in.
func _hint_controls() -> void:
	if _hinted:
		return
	_hinted = true
	var alt_key := "Option" if OS.get_name() == "macOS" else "Alt"
	hud.show_toast("Drag the ground to move the map. Scroll or swipe to zoom. Hold %s and drag to turn and tilt. The Camera bar at the bottom right does all of it too." % alt_key, "info", 14.0)


## Graphics presets. Low is for integrated graphics; High is the default;
## Ultra adds bounce light, the softest shadows and the sharpest picture.
## What each part costs was measured with ./perf.sh.
func _apply_quality() -> void:
	var q := Game.quality
	var vp := get_viewport()
	# The 3D picture is drawn at up to this many lines and scaled to the
	# window; the interface is always drawn at full sharpness.
	var lines: float = [810.0, 945.0, 1080.0, 1440.0][q]
	var tall := float(get_window().size.y)
	if Game.render_lines > 0:
		lines = float(Game.render_lines)
	elif Game.render_lines < 0:
		lines = tall
	if Game.args.has("x_lines"):
		lines = float(Game.args.x_lines)
	_scale_cap = clampf(lines / maxf(tall, 1.0), 0.4, 1.0)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	sky.apply_quality(q)
	world.set_quality(q)
	if not Game.hold_rate:
		_gov_level = 0
	_apply_load_level()
	# switches for measuring what each effect costs: --x_grass=0..1 --x_ssil=0 --x_ssao=0 --x_msaa=0..3 --x_dof=0
	var a := Game.args
	if a.has("x_grass"):
		grass.set_thickness(float(a.x_grass))
	if a.has("x_ssil"):
		sky.env.ssil_enabled = int(a.x_ssil) != 0
	if a.has("x_ssao"):
		sky.env.ssao_enabled = int(a.x_ssao) != 0
	if a.has("x_msaa"):
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][int(a.x_msaa)]
	if a.has("x_dof"):
		sky._dof_allowed = int(a.x_dof) != 0
	if a.has("x_glow"):
		sky.env.glow_enabled = int(a.x_glow) != 0


## The parts of a preset that can be dialled back in an instant when the
## frame rate cannot be held. `_gov_level` 0 is the preset as chosen; each
## level above takes a little more away. Nothing here rebuilds anything.
func _apply_load_level() -> void:
	var q := Game.quality
	var lv := _gov_level
	var vp := get_viewport()
	var msaa: int = [0, 1, 2, 2][q]
	if lv >= 3:
		msaa = mini(msaa, 1)
	if lv >= 4:
		msaa = 0
	var want_msaa: int = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][msaa]
	if vp.msaa_3d != want_msaa:
		vp.msaa_3d = want_msaa as Viewport.MSAA
	var k := _scale_cap
	if lv >= 1:
		k -= 0.1
	if lv >= 3:
		k -= 0.08
	_scale_now = clampf(k, minf(0.4, _scale_cap), _scale_cap)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if _scale_now < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = 0.35
	if not is_equal_approx(vp.scaling_3d_scale, _scale_now):
		vp.scaling_3d_scale = _scale_now
	sky.set_load_level(q, lv)
	var thick: float = [0.0, 0.5, 0.8, 1.0][q]
	grass.set_thickness(thick * (0.5 if lv >= 3 else 1.0))


## The frame-rate governor. When a third of recent frames arrive late it
## dials the picture back one level and checks whether that helped. If it
## did not, the cause is something else (another program hogging the
## machine, say): it puts the level back and stands down for a while.
func _govern() -> void:
	var now := Time.get_ticks_usec()
	var took := (now - _gov_last) / 1000000.0
	_gov_last = now
	if not Game.hold_rate:
		return
	# an unfocused window is slowed down by the system, not by the game
	var focused := DisplayServer.window_is_focused() or Game.args.has("govtest")
	if took > 0.25 or not focused or hud.modal_open():
		_gov_samples = mini(_gov_samples, 0)
		return
	var budget := 1.0 / maxf(DisplayServer.screen_get_refresh_rate(), 30.0)
	var late := took > budget * 1.12
	if _gov_late.size() < GOV_WINDOW:
		_gov_late.resize(GOV_WINDOW)
		_gov_late.fill(false)
	if _gov_late[_gov_i]:
		_gov_late_n -= 1
	_gov_late[_gov_i] = late
	if late:
		_gov_late_n += 1
	_gov_i = (_gov_i + 1) % GOV_WINDOW
	_gov_samples += 1
	_gov_clean = 0.0 if late else _gov_clean + took
	_gov_raised += took
	if _gov_suspend > 0.0:
		_gov_suspend -= took
		return
	if _gov_samples < GOV_WINDOW:
		return
	if _gov_trial >= 0:
		var helped := _gov_late_n <= int(_gov_trial * 0.7)
		_gov_trial = -1
		if not helped:
			_gov_set(_gov_level - 1)
			_gov_suspend = _gov_rest
			_gov_rest = minf(_gov_rest * 2.0, 600.0)
			return
		_gov_rest = 30.0
	if _gov_late_n >= GOV_WINDOW / 3 and _gov_level < GOV_LEVELS:
		if _gov_raised < 6.0:
			_gov_wait = minf(_gov_wait * 2.0, 180.0)     # the last step back up did not stick
		_gov_trial = _gov_late_n
		_gov_set(_gov_level + 1)
	elif _gov_level > 0 and _gov_clean >= _gov_wait:
		_gov_raised = 0.0
		_gov_set(_gov_level - 1)


func _gov_set(level: int) -> void:
	_gov_level = clampi(level, 0, GOV_LEVELS)
	_apply_load_level()
	_gov_clean = 0.0
	_gov_samples = -30          # let the change settle before counting again
	_gov_late.fill(false)
	_gov_late_n = 0
	if Game.args.has("govtest"):
		print("DEMO governor level ", _gov_level, " at ", snappedf(Time.get_ticks_msec() / 1000.0, 0.1), " s, 3D scale ", snappedf(_scale_now, 0.01))


func _on_sim_changed() -> void:
	var sim := Game.sim
	# Screenshots are taken in mid-afternoon light unless told otherwise:
	# --clock=22.5 holds a time of day, --clockrun lets the day pass.
	if Game.args.has("clock"):
		sim.clock = float(Game.args.clock)
		sim.clock_rate = 0.0
	elif Game.args.has("shot") and not Game.args.has("clockrun"):
		sim.clock = 15.0
		sim.clock_rate = 0.0
	if sim.course.holes.is_empty() and sim.time < 1.0 and not Game.args.has("shot") and not Game.args.has("exit"):
		# a fresh start on empty land
		hud.show_toast("This land is yours and there is not a hole on it yet. Open Build to paint a tee and a green, then Holes to lay out the first hole. The Build panel also sells the land round you.", "info", 16.0)
	if play.active():
		play.state = PlayMode.S.OFF
		rig.locked = false
		rig.pitch_override = -1.0
		rig.v_shift = 0.0
	tools.enabled = true
	terrain.set_biome(sim.biome)
	sky.set_biome(sim.biome)
	terrain.bind(sim.course)
	grass.bind(terrain, sim.course, sim.biome)
	rig.bind(sim.course)
	world.bind(sim, rig)
	crowd.bind(sim, rig)
	fx.bind(sim, rig)
	volcano.bind(sim, rig, terrain)
	tools.bind(sim)
	hud.bind(sim)
	desk.bind(sim, rig)
	_autosave_month = -1
	sim.match_accepted.connect(func(offer: Dictionary) -> void:
		hud.close_dock()
		play.start_match(sim, rig, offer))
	sim.tournament_entry.connect(func(wants: bool) -> void:
		if wants:
			hud.close_dock()
			play.start(sim, rig, 0, -1, true))
	sim.month_ended.connect(func(_label: String) -> void:
		if not Game.args.has("shot"):
			Game.save_game())


var _demo_play_state := -1
var _season_day := -1


var _fx_t := 0.0
var _pose_pair: Array[Golfer] = []


func _process(delta: float) -> void:
	if Game.sim == null:
		return
	_govern()
	if Game.args.has("fxtest"):
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 1.2
			for kind in str(Game.args.fxtest).split(","):
				fx._burst(kind, Game.sim.course.on_ground(rig.focus.x, rig.focus.z), Vector3(1, 0, 0))
	if Game.args.has("posetest"):
		# --posetest: a standing golfer hangs their head and the camera watches them;
		# the next standing golfer pumps a fist
		if _pose_pair.is_empty():
			for g in Game.sim.visitors.golfers:
				if not g.walking and g.swing_t < 0.0 and g.hit_t <= 0.0 and g.phase == Golfer.P.AIM:
					_pose_pair.append(g)
				if _pose_pair.size() == 2:
					break
		if _pose_pair.size() >= 1:
			_pose_pair[0].sulk_t = 1.0
			_pose_pair[0].timer = maxf(_pose_pair[0].timer, 5.0)     # stay over the ball a while
			rig.follow = _pose_pair[0]
		if _pose_pair.size() >= 2:
			_pose_pair[1].cheer_t = 1.0
			_pose_pair[1].timer = maxf(_pose_pair[1].timer, 5.0)
	if Game.args.has("cheertest") and Game.sim.tourney.gallery_hole >= 0:
		# the gallery hears an ovation every couple of seconds
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 2.5
			Game.sim.sound.emit(str(Game.args.cheertest), Game.sim.course.holes[Game.sim.tourney.gallery_hole].pin, 1.0)
	var t0 := Time.get_ticks_usec()
	sky.update(Game.sim, rig.focus, rig.dist, delta)
	terrain.material.set_shader_parameter("cloud_offset", sky.cloud_offset)
	terrain.material.set_shader_parameter("cloud_cover", sky.cloud_cover)
	# the season: spring freshness, autumn colour
	var today := Game.sim.day()
	if today != _season_day:
		_season_day = today
		var tint := Defs.season_grass(today)
		var autumn_k := float((Game.sim.biome.get("turf", {}) as Dictionary).get("autumn", 1.0))
		terrain.material.set_shader_parameter("season_grass", Vector3(tint.r, tint.g, tint.b))
		grass.material.set_shader_parameter("season_grass", Vector3(tint.r, tint.g, tint.b))
		Flora.setup()
		Flora.foliage.set_shader_parameter("autumn", Defs.autumn_phase(today) * autumn_k)
		Flora.foliage.set_shader_parameter("spring", Defs.spring_phase(today) * clampf(autumn_k * 1.5, 0.3, 1.0))
	Game.prof("sky", t0)
	t0 = Time.get_ticks_usec()
	var wind_now := Game.sim.weather.wind_vec()
	grass.update(rig.cam.global_position, rig.focus, Vector2(wind_now.x, wind_now.z) * 0.32, sky.cloud_offset, sky.cloud_cover)
	Game.prof("grass", t0)
	desk.lamps_out = world._lamps.size()
	if _demo != "":
		_run_demo(delta)
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			if Game.args.has("sizes"):
				# ViewportTexture.get_size() is multiplied by the interface
				# scale, so ask a captured frame for the real pixel count.
				print("DEMO sizes: window %s, frame %s, 3D drawn at %.2f of that, display density %.1f" % [
					str(get_window().size), str(get_viewport().get_texture().get_image().get_size()),
					get_viewport().scaling_3d_scale, DisplayServer.screen_get_scale()])
				print("DEMO renderer: %s on %s, %s" % [RenderingServer.get_current_rendering_method(),
					RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
			if Game.args.has("shot"):
				_save_shot()
			else:
				var modes := {Window.MODE_WINDOWED: "a window", Window.MODE_FULLSCREEN: "full screen", Window.MODE_EXCLUSIVE_FULLSCREEN: "exclusive full screen"}
				print("DEMO window %s on a screen of %s at density %.1f, menu open %s, shown as %s" % [
					str(get_window().size), str(DisplayServer.screen_get_size()), DisplayServer.screen_get_scale(), str(hud.modal_open()),
					str(modes.get(get_window().mode, get_window().mode))])
				print("DEMO display server says: mode %d, size %s, position %s; the picture is %s; usable screen %s" % [
					DisplayServer.window_get_mode(), str(DisplayServer.window_get_size()), str(DisplayServer.window_get_position()),
					str(get_viewport().get_texture().get_size()), str(DisplayServer.screen_get_usable_rect())])
				get_tree().quit()


# Command-line switches used for automated screenshots, after "--":
#   --shot=file.png --frames=90 --scenario=id --seed=N --fast=seconds
#   --zoom=metres --follow=index --weather=0..4 --panel=name --tool=mode
#   --models=dist (one of everything) --look=object --yaw=deg --pitch=deg --nohud
#   --quality=0..3 --win=WxH (window size in pixels) --sizes (print real render size)
#   --clock=hours (hold a time of day) --clockrun (let the day pass in a screenshot run)
#   --lights=N (floodlight the first N holes) --scroll=pixels (scroll the open panel down)
#   --wind=mph --winddir=degrees (hold the wind) --fullscreen=1 (go full screen in a test run)
#   --displaycard (open Display and graphics) --uiscale=1.1 (try an interface size)
#   --tourney=club --tourney_in=seconds --tourney_at=green|tee --crowd=N (a tournament under way, with its gallery)
#   --fxtest=sand|spray|divot|grass|drops|splash|embers|smoke|dust (fire that burst at the camera's focus every second)
#   --cheertest=ovation (the gallery hears it every 2.5 s) --cheerhold (arms stay up) --posetest (a sulk and a fist pump)
#   --day=N (jump to a day of the year: 0 March 1st, 168 the first of September)
#   --stories=<id|1> (the Feed panel's Stories tab, starting that story first)
#   --soundcheck --soundlog (see sound_desk.gd)
#   Without --shot the game opens its normal full-size window; add --exit to quit after --frames.
#   --play=hole --overlay=0..3 --staff=N --demo=name --perf=1
#   --exit=1 quits after --frames without a screenshot (tests a normal launch)
func _apply_test_args() -> void:
	var a := Game.args
	var sim := Game.sim
	if a.has("staff"):
		for i in int(a.staff):
			sim.hire("greenkeeper")
		sim.hire("exterminator")
		sim.hire("marshal")
	if a.has("lights"):
		# floodlight the first few holes and put lamp posts by their tees
		sim.economy.money = 9000000.0
		for hi in mini(int(a.lights), sim.course.holes.size()):
			var hole := sim.course.holes[hi]
			var dir := hole.pin - hole.tee
			dir.y = 0.0
			var side := Vector3(-dir.z, 0.0, dir.x).normalized()
			var n := maxi(2, int(hole.length / 35.0) + 1)
			for k in n + 1:
				var p := hole.tee.lerp(hole.pin, float(k) / n)
				for off: float in [14.0, -14.0, 20.0, -20.0]:
					var q := p + side * off * (1.0 if k % 2 == 0 else -1.0)
					var tile := sim.course.tile_of(q.x, q.z)
					if sim.place_object(tile.x, tile.y, Defs.O.FLOODLIGHT) == 1:
						break
			for off: float in [6.0, -6.0]:
				var q2 := hole.tee + side * off - dir.normalized() * 4.0
				var t2 := sim.course.tile_of(q2.x, q2.z)
				sim.place_object(t2.x, t2.y, Defs.O.LAMP)
	if a.has("fast"):
		Game.fast_forward(float(a.fast))
	if a.has("shot"):
		hud.hide_modal()
		sim.events.pending = {}
		Game.paused = false
	if a.has("crowd"):
		sim.tourney.size_override = int(a.crowd)     # --crowd=300: a gallery this big, whatever the event
	if a.has("tourney"):
		# --tourney=club: book an event, skip to its start, decline to play in it,
		# and let the first groups get out on the course (--tourney_in=seconds)
		sim.economy.money = 60000.0
		sim.tourney.schedule(str(a.tourney))
		Game.fast_forward(float(sim.tourney.scheduled.day - sim.day() + 1) * Defs.DAY_SECONDS)
		if str(sim.events.pending.get("id", "")) == "tournament_entry":
			sim.events.choose("decline")
			hud.hide_modal()
			Game.paused = false
		Game.fast_forward(float(a.get("tourney_in", "150")))
		var gr := sim.tourney.followed_group()
		print("DEMO tournament: %d spectators, following hole %d, %d groups out" % [sim.tourney.gallery.size(), sim.tourney.gallery_hole + 1, (sim.tourney.active.groups as Array).size()])
		if a.has("tourney_at") and sim.tourney.gallery_hole >= 0:
			# --tourney_at=green|tee: look at that end of the hole the crowd is following
			var gh: Hole = sim.course.holes[sim.tourney.gallery_hole]
			rig.follow = null
			rig.focus = gh.pin if str(a.tourney_at) == "green" else gh.tee
		elif gr != null and not gr.members.is_empty() and not a.has("follow"):
			rig.follow = gr.members[0]
	if a.has("zoom"):
		rig.target_dist = float(a.zoom)
		rig.dist = rig.target_dist
	if a.has("day"):
		# --day=N jumps the calendar to that day of the year (0 is March 1st; autumn starts at 168)
		sim.time = float(int(a.day)) * Defs.DAY_SECONDS
	if a.has("wind"):
		# --wind=mph holds the steady wind at this strength; --winddir=degrees turns it
		var want := float(a.wind) / 2.237
		var wkind := int(a.get("weather", str(sim.weather.kind)))
		sim.weather.wind_mult = want / maxf(Weather.WIND_BASE[wkind] * Weather.SEASON_WIND[sim.month()], 0.01)
		sim.weather.wind_speed = want
		if a.has("winddir"):
			sim.weather.wind_dir = deg_to_rad(float(a.winddir))
	if a.has("weather"):
		var wk := int(a.weather)
		sim.weather.kind = wk
		sim.weather.rain = Weather.RAIN_AMT[wk]
		sim.weather.cloud = Weather.CLOUD_AMT[wk]
		sim.weather._next_change = 9999.0
		if wk >= Weather.K.RAIN:
			sim.course.wet.fill(0.85)
	if a.has("follow") and not sim.visitors.golfers.is_empty():
		var list := sim.visitors.golfers
		var who := list[mini(int(a.follow), list.size() - 1)]
		rig.follow = who
		rig.focus = who.pos
		world.selected = who
		hud.inspect(who)
	if a.has("erupt"):
		sim.eruption.start(float(a.erupt))
	if a.has("volcano") and not sim.course.volcanoes.is_empty():
		var vv: Dictionary = sim.course.volcanoes[0]
		rig.center_on(sim.course.on_ground(float(vv.x) - 60.0, float(vv.z) + 60.0), float(a.volcano))
		rig.dist = rig.target_dist
		rig.yaw = PI * 0.75
		rig.pitch_override = deg_to_rad(float(a.get("pitch", "24")))
	if a.has("build"):
		# put up one of everything near the first tee, for a look at the models
		sim.economy.money = 9000000.0
		var t0 := sim.course.tile_of(sim.course.holes[0].tee.x, sim.course.holes[0].tee.z)
		var k := 0
		for o in range(Defs.O.SNACK_BAR, Defs.O.AIRSTRIP + 1):
			if o == Defs.O.BRIDGE or o == Defs.O.HOUSE:
				continue
			var tx := t0.x + 5 + (k % 5) * 4
			var ty := t0.y - 2 + (k / 5) * 5
			sim.course.guard = false
			sim.course.objects[ty * sim.course.w + tx] = o
			sim.course.guard = true
			k += 1
		sim.course.objects_touched()
		sim.course.revision += 1
		sim.course.objects_changed.emit()
		rig.center_on(sim.course.tile_center(t0.x + 12, t0.y + 4), float(a.build))
		rig.dist = rig.target_dist
	if a.has("models"):
		# one of every plant, prop and building on cleared ground
		var t0 := sim.course.tile_of(sim.course.holes[0].tee.x, sim.course.holes[0].tee.z)
		var cw := sim.course.w
		sim.course.guard = false
		for ty in range(t0.y - 9, t0.y + 16):
			for tx in range(t0.x + 2, t0.x + 30):
				if sim.course.in_bounds(tx, ty):
					sim.course.objects[ty * cw + tx] = 0
		var k := 0
		for o in range(1, Defs.O.LAMP + 1):
			if o == Defs.O.CLUBHOUSE or o == Defs.O.BRIDGE:
				continue
			var tx := t0.x + 5 + (k % 6) * 4
			var ty := t0.y - 6 + (k / 6) * 5
			if sim.course.in_bounds(tx, ty):
				sim.course.objects[ty * cw + tx] = o
			k += 1
		sim.course.guard = true
		sim.course.objects_touched()
		sim.course.revision += 1
		sim.course.objects_changed.emit()
		rig.center_on(sim.course.tile_center(t0.x + 15, t0.y + 3), float(a.models))
		rig.dist = rig.target_dist
	if a.has("look"):
		# centre on the first object of a kind, e.g. --look=8 for the clubhouse
		var want := int(a.look)
		var at := sim.course.objects.find(want)
		if at >= 0:
			rig.center_on(sim.course.tile_center(at % sim.course.w, at / sim.course.w), float(a.get("zoom", "60")))
			rig.dist = rig.target_dist
	if a.has("yaw"):
		rig.yaw = deg_to_rad(float(a.yaw))
	if a.has("pitch") and not a.has("volcano"):
		rig.pitch_override = deg_to_rad(float(a.pitch))
	if a.has("nohud"):
		hud.visible = false
	if a.has("overlay"):
		hud.set_overlay(int(a.overlay))
	if a.has("panel"):
		hud.open_dock(str(a.panel))
		if a.has("scroll"):
			# --scroll=pixels: look further down a long panel in a screenshot
			var stack: Array[Node] = [hud.dock]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if n is ScrollContainer:
					(n as ScrollContainer).set_deferred("scroll_vertical", int(a.scroll))
					break
				for ch in n.get_children():
					stack.append(ch)
	if a.has("tool"):
		hud.open_dock("build")
		tools.sculpt_mode = "raise"
		tools.set_mode(str(a.tool))
		tools.hover = sim.course.holes[0].pin if not sim.course.holes.is_empty() else null
	if a.has("play"):
		play.start(sim, rig, int(a.play), 1)
	if a.has("menu"):
		hud.show_scenarios(true)
	if a.has("pausemenu"):
		hud.show_menu()
	if a.has("uiscale"):
		# try an interface size without saving it as the owner's choice
		get_window().content_scale_factor = float(a.uiscale)
	if a.has("displaycard"):
		hud.show_display()
	if a.has("stories"):
		# open the Feed panel on its Stories tab, with a story started
		if str(a.stories) != "1":
			sim.stories.start(str(a.stories))
		hud.panels.feed_tab = "stories"
		hud.open_dock("feed")
	if a.has("controls"):
		hud.show_controls()
	if a.has("requality"):
		# switch preset while running, without saving it as the owner's choice
		Game.quality = clampi(int(a.requality), 0, 3)
		Game.quality_changed.emit()
	if a.has("speed"):
		Game.speed = int(a.speed)
	if a.has("demo"):
		_demo = str(a.demo)
	if a.has("novsync"):
		# lets a measurement show how much headroom there is above the display's rate
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if a.has("scale3d"):
		get_viewport().scaling_3d_scale = float(a.scale3d)
	if a.has("noshadow"):
		sky.sun.shadow_enabled = false
	if a.has("nomsaa"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if a.has("notrees"):
		world._obj_root.visible = false
	if a.has("noterrain"):
		terrain.visible = false
	if (a.has("shot") or a.has("exit")) and str(a.get("demo", "")) != "biomes":
		# a measurement ends itself (see PerfProbe); anything else ends after a set number of frames
		_shot_frames = int(a.get("frames", "999999" if a.has("perf") else "90"))


## Drives the game with synthetic input so the real input paths get tested.
func _run_demo(delta: float) -> void:
	_demo_t += delta
	var vp := get_viewport().get_visible_rect().size
	match _demo:
		"paint":
			# drag a fairway brush across the middle of the screen
			if _demo_step == 0 and _demo_t > 0.3:
				hud.open_dock("build")
				tools.terrain_type = Defs.T.FAIRWAY
				tools.brush = 2
				tools.set_mode("terrain")
				_mouse(Vector2(vp.x * 0.3, vp.y * 0.5), true, false)
				_demo_step = 1
				print("DEMO money before ", Game.sim.economy.money)
			elif _demo_step >= 1 and _demo_step < 30:
				_mouse(Vector2(vp.x * (0.3 + 0.012 * _demo_step), vp.y * 0.5), true, true)
				_demo_step += 1
			elif _demo_step == 30:
				_mouse(Vector2(vp.x * 0.66, vp.y * 0.5), false, false)
				_demo_step = 31
				print("DEMO money after ", Game.sim.economy.money)
		"hole":
			# paint a green, then lay out a hole with two clicks
			var a := Vector2(vp.x * 0.42, vp.y * 0.42)
			var b := Vector2(vp.x * 0.42, vp.y * 0.78)
			if _demo_step == 0 and _demo_t > 0.3:
				# the demo is about the tool, not the ladder: a clubhouse big enough for one more hole
				Game.sim.clubhouse_level = maxi(Game.sim.clubhouse_level, Game.sim.level_for_holes(Game.sim.course.holes.size() + 1))
				hud.open_dock("build")
				tools.terrain_type = Defs.T.GREEN
				tools.brush = 2
				tools.set_mode("terrain")
				_mouse(a, true, false)
				_demo_step = 1
			elif _demo_step == 1:
				_mouse(a, false, false)
				_demo_step = 2
			elif _demo_step == 2:
				tools.set_mode("hole")
				_mouse(b, true, false)
				_demo_step = 3
			elif _demo_step == 3:
				_mouse(b, false, false)
				_demo_step = 4
			elif _demo_step == 4:
				_mouse(a, true, false)
				_demo_step = 5
			elif _demo_step == 5:
				_mouse(a, false, false)
				_demo_step = 6
				var holes := Game.sim.course.holes
				print("DEMO holes ", holes.size(), " newest par ", holes[-1].par, " length ", Defs.yards(holes[-1].length), " money ", Game.sim.economy.money)
		"biomes":
			# one window, four screenshots: start each biome in turn
			var ids := ["lush", "highlands", "desert", "volcanic"]
			var phase := int(_demo_t / 1.6)
			if phase != _demo_step - 1 and phase < ids.size():
				_demo_step = phase + 1
				Game.new_game("three_holes", 7, ids[phase])
				Game.fast_forward(float(Game.args.get("fast", "90")))
				hud.hide_modal()
				Game.sim.events.pending = {}
				Game.paused = false
				if Game.args.has("zoom"):
					rig.target_dist = float(Game.args.zoom)
					rig.dist = rig.target_dist
				_shot_frames = -1
			elif phase == _demo_step - 1 and phase < ids.size() and fmod(_demo_t, 1.6) > 1.3 and _shot_frames == -1:
				_shot_frames = -2
				_grab(str(Game.args.shot).replace(".png", "_%s.png" % ids[phase]))
			elif phase >= ids.size():
				get_tree().quit()
		"start":
			# click Play on the third scenario card, as a player would
			if _demo_step == 0 and _demo_t > 0.5:
				_demo_step = 1
				print("DEMO before: scenario ", Game.sim.scenario.def.id, " paused ", Game.paused, " menu open ", hud.modal_open())
				_click_button_named("Play", 2)
			elif _demo_step == 1 and _demo_t > 1.2:
				_demo_step = 2
				print("DEMO after: scenario ", Game.sim.scenario.def.id, " paused ", Game.paused, " menu open ", hud.modal_open(), " money ", Game.sim.economy.money)
		"camera":
			# Work the camera the way someone with a one-button mouse would:
			# drags, swipes and the buttons on screen. No right button, no wheel.
			_demo_step += 1
			var mid := vp * Vector2(0.5, 0.55)
			var st := _demo_step
			if st == 4:
				_demo_mem = {"focus": rig.focus, "sel": world.selected}
			elif st >= 5 and st < 30:
				if _demo_drag(5, mid, Vector2(9.0, 4.0)):
					print("DEMO drag on the ground moved the map %.0f m and selected %s" % [(_demo_mem.focus as Vector3).distance_to(rig.focus), "nobody" if world.selected == null else "someone"])
					_demo_mem = {"yaw": rig.yaw, "tilt": rig.tilt, "focus": rig.focus}
			elif st >= 30 and st < 55:
				if _demo_drag(30, mid, Vector2(8.0, 5.0), true):
					print("DEMO Option-drag turned the view %.0f degrees and tilted it %.0f degrees, map moved %.1f m" % [
						rad_to_deg(rig.yaw - float(_demo_mem.yaw)), rig.tilt - float(_demo_mem.tilt), (_demo_mem.focus as Vector3).distance_to(rig.focus)])
					_demo_mem = {"dist": rig.target_dist}
			elif st >= 55 and st < 66:
				_swipe(mid, Vector2(0.0, -4.0))
			elif st == 66:
				print("DEMO swipe up and down zoomed from %.0f m to %.0f m" % [float(_demo_mem.dist), rig.target_dist])
				_demo_mem = {"yaw": rig.yaw, "dist": rig.target_dist}
			elif st >= 67 and st < 78:
				_swipe(mid, Vector2(5.0, 0.4))
			elif st == 78:
				print("DEMO swipe sideways turned the view %.0f degrees, zoom changed %.1f m" % [rad_to_deg(rig.yaw - float(_demo_mem.yaw)), rig.target_dist - float(_demo_mem.dist)])
				_demo_mem = {"focus": rig.focus, "dist": rig.target_dist}
				Game.scroll_pans = true
			elif st >= 79 and st < 90:
				_swipe(mid, Vector2(4.0, 3.0))
			elif st == 90:
				print("DEMO with swipe set to move the map, a swipe moved it %.0f m, zoom changed %.1f m" % [(_demo_mem.focus as Vector3).distance_to(rig.focus), rig.target_dist - float(_demo_mem.dist)])
				Game.scroll_pans = false
				hud.open_dock("build")
				tools.terrain_type = Defs.T.FAIRWAY
				tools.brush = 1
				tools.set_mode("terrain")
				_demo_mem = {"focus": rig.focus, "money": Game.sim.economy.money}
			elif st >= 92 and st < 117:
				if _demo_drag(92, mid, Vector2(6.0, 0.0)):
					print("DEMO with a brush out, a plain drag painted (spent %s) and moved the map %.1f m" % [Defs.money(float(_demo_mem.money) - Game.sim.economy.money), (_demo_mem.focus as Vector3).distance_to(rig.focus)])
					_demo_mem = {"focus": rig.focus, "money": Game.sim.economy.money}
			elif st >= 117 and st < 142:
				if _demo_drag(117, mid, Vector2(6.0, 3.0), false, true):
					print("DEMO with a brush out, a Command-drag moved the map %.0f m and spent %s" % [(_demo_mem.focus as Vector3).distance_to(rig.focus), Defs.money(float(_demo_mem.money) - Game.sim.economy.money)])
					tools.set_mode("")
					hud.close_dock()
					_demo_mem = {"yaw": rig.yaw, "tilt": rig.tilt, "dist": rig.target_dist}
			elif st == 143:
				_click_camera_button(0, true)
			elif st == 160:
				_click_camera_button(0, false)
				_click_camera_button(2, true)
			elif st == 177:
				_click_camera_button(2, false)
				_click_camera_button(4, true)
			elif st == 194:
				_click_camera_button(4, false)
				print("DEMO buttons on screen turned %.0f degrees, tilted %.0f degrees and zoomed from %.0f m to %.0f m" % [
					rad_to_deg(rig.yaw - float(_demo_mem.yaw)), rig.tilt - float(_demo_mem.tilt), float(_demo_mem.dist), rig.target_dist])
			elif st == 196:
				_click_camera_button(6, true)
				_click_camera_button(6, false)
			elif st == 200:
				print("DEMO the reset button put the tilt back to %.0f degrees" % rig.tilt)
			elif st == 204:
				# a click that does not move is still a click
				_mouse(mid, true, false)
			elif st == 205:
				_mouse(mid, false, false)
			elif st == 207:
				print("DEMO a click without moving counted as a %s" % ("drag" if rig.dragged else "click"))
		"sound":
			# Play every sound and read the meters. The speakers are muted in
			# test runs; the meters on each bus still show what was played.
			_demo_step += 1
			var ids: Array = Game.db.sounds.get("sounds", {}).keys()
			var st := _demo_step
			if st == 5:
				_demo_mem = {"heard": [], "silent": [], "i": 0, "peak": -200.0, "amb": {}, "music": -200.0}
			elif st > 5 and int(_demo_mem.i) < ids.size():
				var k := (st - 6) % 14
				var id := str(ids[int(_demo_mem.i)])
				if k == 0:
					_demo_mem.peak = -200.0
					desk._last.erase(id)
					desk.play(id)
				else:
					_demo_mem.peak = maxf(float(_demo_mem.peak), float(desk.meters().Sound))
				if k == 13:
					if float(_demo_mem.peak) > -70.0:
						(_demo_mem.heard as Array).append(id)
					else:
						(_demo_mem.silent as Array).append(id)
					_demo_mem.i = int(_demo_mem.i) + 1
					if int(_demo_mem.i) == ids.size():
						print("DEMO sound effects: %d of %d registered on the meter. Silent: %s" % [(_demo_mem.heard as Array).size(), ids.size(), str(_demo_mem.silent)])
						_demo_mem["t0"] = st
			elif _demo_mem.has("t0"):
				var since := st - int(_demo_mem.t0)
				_demo_mem.music = maxf(float(_demo_mem.music), float(desk.meters().Music))
				if since == 5:
					# out on the course: is a real shot heard, placed in the world?
					var before := int(desk.plays.get("drive", 0))
					Game.sim.sound.emit("drive", rig.focus, 1.0)
					print("DEMO a drive announced by the game at the middle of the view was %s" % ("played" if int(desk.plays.get("drive", 0)) > before else "not played"))
					var far := int(desk.plays.get("iron", 0))
					Game.sim.sound.emit("iron", rig.focus + Vector3(rig.dist * 9.0, 0.0, 0.0), 1.0)
					print("DEMO an iron shot far outside the view was %s" % ("played" if int(desk.plays.get("iron", 0)) > far else "left unplayed, as it should be"))
				if since == 240:
					var lv := desk.ambience_levels(Game.sim.darkness())
					print("DEMO by day: birds %.2f, crickets %.2f, wind %.2f, rain %.2f; ambience meter %.0f dB" % [float(lv.birds), float(lv.crickets), float(lv.wind), float(lv.rain), float(desk.meters().Ambience)])
					print("DEMO music by day: %s (deck playing %s, meter peaked at %.0f dB)" % [desk.now_playing, str(desk._decks[desk._live].playing), float(_demo_mem.music)])
					_demo_mem["day_track"] = desk.now_playing
					Game.sim.clock = 23.0
					Game.sim.weather.rain = 0.9
				if since == 700:
					var lv2 := desk.ambience_levels(Game.sim.darkness())
					print("DEMO at night in the rain: birds %.2f, crickets %.2f, rain %.2f; ambience meter %.0f dB" % [float(lv2.birds), float(lv2.crickets), float(lv2.rain), float(desk.meters().Ambience)])
				if since == 4300:
					print("DEMO music after dark: %s (changed from the day track: %s, list %s)" % [desk.now_playing, str(desk.now_playing != str(_demo_mem.day_track)), desk._list])
		"sound3d":
			# Sounds out on the course: do they reach the meter, and how loud, at each zoom?
			_demo_step += 1
			var st3 := _demo_step
			var zooms := [16.0, 60.0, 150.0, 430.0, 900.0]
			var names := ["drive", "putt", "cup", "sizzle", "land_soft"]
			var slot := (st3 - 10) / 16
			var ph := (st3 - 10) % 16
			if st3 >= 10 and slot < zooms.size() * names.size():
				var zi := slot / names.size()
				var id := str(names[slot % names.size()])
				rig.target_dist = zooms[zi]
				rig.dist = zooms[zi]
				if ph == 2:
					_demo_mem["peak"] = -200.0
					desk._last.erase(id)
					Game.sim.sound.emit(id, rig.focus, 1.0)
				elif ph > 2:
					_demo_mem["peak"] = maxf(float(_demo_mem.get("peak", -200.0)), float(desk.meters().Sound))
				if ph == 15:
					print("DEMO zoom %4d m  %-10s peak %6.1f dB" % [int(zooms[zi]), id, float(_demo_mem.peak)])
		"gamepad":
			_demo_gamepad()
		"saveload":
			if _demo_step == 0 and _demo_t > 0.5:
				_demo_step = 1
				Game.sim.hire("greenkeeper")
				Game.sim.economy.money = 12345.0
				var before := Game.sim.course.holes.size()
				print("DEMO saved ", Game.save_game(), " holes ", before)
				print("DEMO loaded ", Game.load_game(), " holes ", Game.sim.course.holes.size(), " money ", Game.sim.economy.money, " staff ", Game.sim.crew.members.size())
				DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
		"panels":
			# open every panel in turn and let each refresh a few times
			var names := ["build", "holes", "staff", "money", "members", "tournaments", "skills", "golfer", "shop", "goals", "feed", "play"]
			var i := int(_demo_t / 0.6)
			if i != _demo_step - 1 and i < names.size():
				_demo_step = i + 1
				hud.open_dock(names[i])
				if names[i] == "skills":
					hud.panels._skill_pick = "frugal"
					hud.rebuild_dock()
				print("DEMO opened ", names[i])
		"play":
			# say what the golfer is told before and after each shot
			if play.state != _demo_play_state:
				_demo_play_state = play.state
				if play.state == PlayMode.S.AIM and not play.putting:
					print("DEMO aim: %s, %s | %s" % [play.club().name, play.lie_name(), play.advice()])
				elif play.state == PlayMode.S.PAUSE:
					print("DEMO shot: ", play.message)
			if play.state == PlayMode.S.FLIGHT and _shot_frames == 2:
				# where the ball is on screen, for cropping a screenshot round it
				var pb := play.g.ball
				var at := rig.cam.unproject_position(pb.pos) * _to_window()
				print("DEMO ball at window pixel %d,%d: %.0f m up, %.0f m from the camera, window %s" % [
					int(at.x), int(at.y), pb.pos.y - Game.sim.course.height_at(pb.pos.x, pb.pos.z), rig.cam.global_position.distance_to(pb.pos), str(get_window().size)])
			# a simple bot: full routine, stop the meter on the gold line
			if play.state == PlayMode.S.AIM and _demo_t > 0.4:
				play.press()
			elif play.state == PlayMode.S.POWER:
				var want := play.target_power if play.target_power > 0.0 else 0.97
				if play.meter >= want - 0.01:
					play.press()
			elif play.state == PlayMode.S.ACCURACY and play.meter <= play.perfect * 0.6:
				play.press()
				_demo_t = 0.0
			if not play.active() and _demo_step == 0:
				_demo_step = 1
				print("DEMO round card ", Game.sim.player.last_card, " golfer xp ", Game.sim.skills.xp.golfer, " level ", Game.sim.skills.level.golfer)


## Press or release one of the buttons in the Camera bar, through real
## mouse events, so the same path runs as when a person holds it down.
func _click_camera_button(index: int, down: bool) -> void:
	var found: Array[IconButton] = []
	var stack: Array[Node] = [hud.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is IconButton:
			found.append(n)
		for c in n.get_children():
			stack.append(c)
	found.sort_custom(func(a: IconButton, b: IconButton) -> bool: return a.global_position.x < b.global_position.x)
	if index < found.size():
		var b := found[index]
		_mouse(b.global_position + b.size * 0.5, down, false)


func _click_button_named(text: String, index: int) -> void:
	var found: Array[Button] = []
	var stack: Array[Node] = [hud.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == text and (n as Button).is_visible_in_tree():
			found.append(n)
		for c in n.get_children():
			stack.append(c)
	found.sort_custom(func(a: Button, b: Button) -> bool:
		var pa := a.global_position
		var pb := b.global_position
		return pa.y < pb.y - 5.0 or (absf(pa.y - pb.y) <= 5.0 and pa.x < pb.x))
	if index < found.size():
		var b := found[index]
		var at := b.global_position + b.size * 0.5
		_mouse(at, true, false)
		_mouse(at, false, false)


func _mouse(at: Vector2, pressed: bool, motion: bool, rel: Vector2 = Vector2.ZERO, alt: bool = false, meta: bool = false) -> void:
	# Callers think in interface coordinates; raw input arrives in window
	# pixels, which are twice as many on a high-density display.
	var px := _to_window()
	at *= px
	rel *= px
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		mm.relative = rel
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		mm.alt_pressed = alt
		mm.meta_pressed = meta
		Input.parse_input_event(mm)
	else:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.alt_pressed = alt
		mb.meta_pressed = meta
		Input.parse_input_event(mb)


## Window pixels per interface unit.
func _to_window() -> Vector2:
	return Vector2(get_window().size) / get_viewport().get_visible_rect().size


## A swipe on a Magic Mouse or a two-finger scroll on a trackpad.
func _swipe(at: Vector2, delta: Vector2) -> void:
	var pg := InputEventPanGesture.new()
	pg.position = at * _to_window()
	pg.delta = delta
	Input.parse_input_event(pg)


## One left-button drag spread over frames `from`..`from + 22` of a demo:
## press, twenty moves, release. Returns true once it has finished.
func _demo_drag(from: int, start: Vector2, step: Vector2, alt: bool = false, meta: bool = false) -> bool:
	var k := _demo_step - from
	if k == 0:
		_mouse(start, true, false, Vector2.ZERO, alt, meta)
	elif k >= 1 and k <= 20:
		_mouse(start + step * k, false, true, step, alt, meta)
	elif k == 21:
		_mouse(start + step * 20.0, false, false, Vector2.ZERO, alt, meta)
	return k == 22


# ------------------------------------------------------ --demo=gamepad

func _pad_axis(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis as JoyAxis
	e.axis_value = value
	Input.parse_input_event(e)


func _pad_button(button: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button as JoyButton
	e.pressed = down
	e.pressure = 1.0 if down else 0.0
	Input.parse_input_event(e)


## Press a pad button now and let it go two frames later.
func _pad_tap(button: int) -> void:
	_pad_button(button, true)
	_demo_mem["up"] = [button, 2]


## Push the left stick toward a place on screen, as a hand would, easing off
## on the way in. True once the pointer is there and the stick is let go.
func _pad_steer(target: Vector2) -> bool:
	var to := target - pad.pos
	if to.length() < 5.0:
		_pad_axis(JOY_AXIS_LEFT_X, 0.0)
		_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
		return true
	var push := to.normalized() * clampf(to.length() / 150.0, 0.45, 1.0)
	_pad_axis(JOY_AXIS_LEFT_X, push.x)
	_pad_axis(JOY_AXIS_LEFT_Y, push.y)
	return false


## Steer the pointer to a place and tap A there. True a few frames after.
func _pad_tap_at(target: Vector2) -> bool:
	var c := int(_demo_mem.get("c", 0))
	if c == 0:
		if _pad_steer(target):
			_demo_mem["c"] = 1
		return false
	_demo_mem["c"] = c + 1
	if c == 3:
		_pad_tap(JOY_BUTTON_A)
	elif c >= 12:
		_demo_mem["c"] = 0
		return true
	return false


func _pad_next() -> void:
	_demo_mem["i"] = int(_demo_mem.i) + 1
	_demo_mem["t"] = _demo_t
	_demo_mem["n"] = 0


## The first button on show whose label starts with this.
func _button_starting(text: String) -> Button:
	var stack: Array[Node] = [hud.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text.begins_with(text) and (n as Button).is_visible_in_tree():
			return n as Button
		for c in n.get_children():
			stack.append(c)
	return null


## What the controller's pointer is resting on in the open dialog.
func _pad_over() -> String:
	for c in pad._targets(hud.modal_card):
		if c.get_global_rect().has_point(pad.pos):
			return (c as Button).text if c is Button else c.get_class()
	return "nothing"


## Work the game with a controller by sending the events a real pad sends:
## pointer, click, back, painting, camera, speed, panels, the menu, a shot.
func _demo_gamepad() -> void:
	var vp := get_viewport().get_visible_rect().size
	if _demo_mem.is_empty():
		if _demo_t < 0.6:
			return
		# with --menu it tries the start screen instead of the game
		_demo_mem = {"i": 100 if hud.modal_open() else 0, "t": _demo_t, "n": 0}
		_shot_frames = -1      # this demo ends the run itself
	if _demo_mem.has("up"):
		var up: Array = _demo_mem.up
		up[1] = int(up[1]) - 1
		if int(up[1]) <= 0:
			_pad_button(int(up[0]), false)
			_demo_mem.erase("up")
	var since := _demo_t - float(_demo_mem.t)
	var n := int(_demo_mem.n)
	_demo_mem["n"] = n + 1
	var sim := Game.sim
	var m := _demo_mem
	match int(m.i):
		0:
			if n == 0:
				print("DEMO 01 pads plugged in: %s" % str(Input.get_connected_joypads()))
				_pad_axis(JOY_AXIS_LEFT_X, 0.9)
			elif n == 4:
				m["from"] = pad.pos
				m["t0"] = _demo_t
			elif n > 4 and _demo_t - float(m.t0) > 0.5:
				print("DEMO 02 left stick held right for %.2f s moved the pointer %.0f units; Input.get_joy_axis reads %.2f; pointer showing: %s; notices on screen: %d" % [
					_demo_t - float(m.t0), pad.pos.x - (m.from as Vector2).x, Input.get_joy_axis(0, JOY_AXIS_LEFT_X), str(pad._dot.visible), hud.toasts.get_child_count()])
				_pad_axis(JOY_AXIS_LEFT_X, 0.0)
				_pad_next()
		1:
			var bb: Button = hud._tool_buttons["build"]
			if _pad_tap_at(bb.global_position + bb.size * 0.5):
				print("DEMO 03 A on the Build button: panel open is '%s'" % hud.dock_name)
				_pad_next()
		2:
			var fb := _button_starting("Fairway")
			if fb == null:
				print("DEMO 04 no Fairway button was found")
				_pad_next()
			elif _pad_tap_at(fb.global_position + fb.size * 0.5):
				print("DEMO 04 A on the Fairway button: tool out is '%s'" % tools.mode)
				m["money"] = sim.economy.money
				m["fair"] = sim.course.terrain.count(Defs.T.FAIRWAY)
				_pad_next()
		3:
			# hold A and steer: a brush stroke
			var ph := int(m.get("ph", 0))
			if ph == 0:
				if _pad_steer(vp * Vector2(0.34, 0.6)):
					_pad_button(JOY_BUTTON_A, true)
					m["ph"] = 1
			elif ph == 1:
				if _pad_steer(vp * Vector2(0.5, 0.62)):
					_pad_button(JOY_BUTTON_A, false)
					m["ph"] = 2
					m["n"] = 0
					if Game.args.has("shot"):
						_grab(str(Game.args.shot).replace(".png", "_paint.png"))
			elif n >= 6:
				print("DEMO 05 holding A and steering painted %d fairway tiles for %s" % [
					sim.course.terrain.count(Defs.T.FAIRWAY) - int(m.fair), Defs.money(float(m.money) - sim.economy.money)])
				_pad_next()
		4:
			if n == 0:
				_pad_tap(JOY_BUTTON_B)
			elif n == 6:
				m["mode"] = tools.mode
				m["dock"] = hud.dock_name
				_pad_tap(JOY_BUTTON_B)
			elif n == 12:
				print("DEMO 06 B put the tool away (tool '%s', panel still '%s'); B again closed the panel (panel '%s')" % [str(m.mode), str(m.dock), hud.dock_name])
				_pad_next()
		5:
			if n == 0:
				m["yaw"] = rig.yaw
				m["tilt"] = rig.tilt
				_pad_axis(JOY_AXIS_RIGHT_X, 1.0)
			elif since > 0.4 and not m.has("yaw1"):
				m["yaw1"] = rig.yaw
				_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
				_pad_axis(JOY_AXIS_RIGHT_Y, -1.0)
			elif since > 0.8:
				print("DEMO 07 right stick right turned the view %.0f degrees to the right; right stick up tilted it %.0f degrees higher" % [rad_to_deg(float(m.yaw) - float(m.yaw1)), rig.tilt - float(m.tilt)])
				_pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
				_pad_next()
		6:
			if n == 0:
				m["dist"] = rig.target_dist
				_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
			elif since > 0.5 and not m.has("dist1"):
				m["dist1"] = rig.target_dist
				_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
				_pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
			elif since > 0.9:
				print("DEMO 08 right trigger zoomed in from %.0f m to %.0f m; left trigger back out to %.0f m" % [float(m.dist), float(m.dist1), rig.target_dist])
				_pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
				_pad_next()
		7:
			if n == 0:
				m["focus"] = rig.focus
				_pad_axis(JOY_AXIS_LEFT_X, 1.0)
			elif since > 2.0:
				print("DEMO 09 pointer pushed against the right edge (x %.0f of %.0f) moved the map %.0f m" % [pad.pos.x, vp.x, (m.focus as Vector3).distance_to(rig.focus)])
				_pad_axis(JOY_AXIS_LEFT_X, 0.0)
				_pad_next()
		8:
			if n == 0:
				m["speed"] = Game.speed
				_pad_tap(JOY_BUTTON_DPAD_RIGHT)
			elif n == 6:
				m["speed1"] = Game.speed
				_pad_tap(JOY_BUTTON_BACK)
			elif n == 12:
				print("DEMO 10 d-pad right took the speed from %d to %d; Select paused the game: %s" % [int(m.speed), int(m.speed1), str(Game.paused)])
				Game.paused = false
				Game.speed = 1
				_pad_next()
		9:
			if n == 0:
				_pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
			elif n == 6:
				m["p1"] = hud.dock_name
				_pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
			elif n == 12:
				m["p2"] = hud.dock_name
				_pad_tap(JOY_BUTTON_LEFT_SHOULDER)
			elif n == 18:
				m["p3"] = hud.dock_name
				_pad_tap(JOY_BUTTON_B)
			elif n == 24:
				print("DEMO 11 right bumper opened '%s', again '%s', left bumper went back to '%s', B closed it ('%s')" % [str(m.p1), str(m.p2), str(m.p3), hud.dock_name])
				_pad_next()
		10:
			if n == 0:
				_pad_tap(JOY_BUTTON_START)
			elif n == 10:
				print("DEMO 12 Start opened the menu: %s; the pointer went to '%s'" % [str(hud.modal_open()), _pad_over()])
			elif n > 10 and n <= 34 and (n - 10) % 6 == 1:
				_pad_tap(JOY_BUTTON_DPAD_DOWN)
			elif n == 40:
				print("DEMO 13 d-pad down four times put the pointer on '%s'" % _pad_over())
				if Game.args.has("shot"):
					_grab(str(Game.args.shot).replace(".png", "_menu.png"))
				_pad_tap(JOY_BUTTON_A)
			elif n == 52:
				var title := ""
				if _modal_title() != null:
					title = _modal_title().text
				print("DEMO 14 A there opened the card titled '%s'" % title)
				if Game.args.has("shot"):
					_grab(str(Game.args.shot).replace(".png", "_controls.png"))
			elif n == 60:
				_pad_tap(JOY_BUTTON_B)
			elif n == 70:
				print("DEMO 15 B went back to the menu: Resume is %s" % ("there" if _button_starting("Resume") != null else "missing"))
				_pad_next()
		11:
			# a slider: steer onto it, then d-pad left and right
			var sl: HSlider = null
			for c in pad._targets(hud.modal_card):
				if c is HSlider:
					sl = c as HSlider
					break
			if m.has("closing"):
				if n == 8:
					print("DEMO 17 Start again closed the menu: %s" % str(not hud.modal_open()))
					_pad_next()
			elif sl == null:
				print("DEMO 16 no slider found")
				_pad_next()
			elif not m.has("vol"):
				var r := sl.get_global_rect()
				if _pad_steer(Vector2(lerpf(r.position.x + 8.0, r.end.x - 8.0, sl.ratio), r.get_center().y)):
					m["vol"] = sl.value
					m["n"] = 0
			elif n == 3:
				_pad_tap(JOY_BUTTON_DPAD_LEFT)
			elif n == 9:
				m["vol1"] = sl.value
				_pad_tap(JOY_BUTTON_DPAD_RIGHT)
			elif n == 15:
				print("DEMO 16 on the Music slider, d-pad left took it from %.2f to %.2f and d-pad right put it back to %.2f" % [float(m.vol), float(m.vol1), sl.value])
				_pad_tap(JOY_BUTTON_START)
				m["closing"] = true
				m["n"] = 0
		12:
			if n == 0:
				play.start(sim, rig, 0, 1)
			elif play.state == PlayMode.S.AIM and not m.has("aim"):
				m["aim"] = play.aim
				m["t1"] = _demo_t
				_pad_axis(JOY_AXIS_LEFT_X, 0.8)
			elif m.has("aim") and _demo_t - float(m.t1) > 0.4:
				print("DEMO 18 in a round, the stick turned the aim %.1f degrees; pointer showing: %s" % [rad_to_deg(play.aim - float(m.aim)), str(pad._dot.visible)])
				_pad_axis(JOY_AXIS_LEFT_X, 0.0)
				_pad_axis(JOY_AXIS_LEFT_X, -0.8)
				m["t2"] = _demo_t
				_pad_next()
		13:
			# turn back onto the pin, then try the club and shape buttons
			if not m.has("back"):
				if since > 0.4:
					_pad_axis(JOY_AXIS_LEFT_X, 0.0)
					m["back"] = true
					m["n"] = 0
					m["club"] = str(play.club().name)
			elif n == 2:
				_pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
			elif n == 8:
				m["club1"] = str(play.club().name)
				_pad_tap(JOY_BUTTON_LEFT_SHOULDER)
			elif n == 14:
				m["club2"] = str(play.club().name)
				_pad_tap(JOY_BUTTON_X)
			elif n == 20:
				print("DEMO 19 right bumper changed club from %s to %s, left bumper back to %s; X made the shot shape '%s'" % [str(m.club), str(m.club1), str(m.club2), str(play.shape().name)])
				play.shape_i = 0
				play.cycle_shape(0)
				_pad_tap(JOY_BUTTON_A)
			elif n == 30:
				m["st"] = play.state
				_pad_tap(JOY_BUTTON_B)
			elif n == 36:
				print("DEMO 20 A started the meter (power meter running: %s); B stopped it (back to aiming: %s)" % [str(int(m.st) == PlayMode.S.POWER), str(play.state == PlayMode.S.AIM)])
				_pad_next()
		14:
			# the swing: A, A on the gold line, A on the needle
			if play.state == PlayMode.S.AIM and n > 4 and not m.has("up") and not m.has("swung"):
				_pad_tap(JOY_BUTTON_A)
				m["swung"] = true
			elif play.state == PlayMode.S.POWER and not m.has("up") and not m.has("set"):
				var want := play.target_power if play.target_power > 0.0 else 0.97
				if play.meter >= want - 0.02:
					_pad_tap(JOY_BUTTON_A)
					m["set"] = true
			elif play.state == PlayMode.S.ACCURACY and not m.has("up") and not m.has("hit") and play.meter <= play.perfect * 0.6:
				_pad_tap(JOY_BUTTON_A)
				m["hit"] = true
			elif play.state == PlayMode.S.FLIGHT and not m.has("fly"):
				m["fly"] = n
			elif m.has("fly") and n == int(m.fly) + 3:
				print("DEMO 21 A three times played the shot: stroke %d, power %.2f, timing %.2f (%s), buzz asked of the pad %s" % [
					play.g.strokes, play.power, play.needle, play.swing_word, str(Input.get_joy_vibration_strength(0))])
			elif m.has("fly") and not m.has("rest") and (play.state == PlayMode.S.PAUSE or play.state == PlayMode.S.AIM or not play.active()):
				print("DEMO 22 the ball came to rest: %s" % play.message)
				m["rest"] = n
			# then a swing with the right stick: pull back, hold, push forward a shade to the right
			elif m.has("rest") and play.state == PlayMode.S.AIM and not m.has("pull"):
				_pad_axis(JOY_AXIS_RIGHT_Y, 1.0)
				m["pull"] = n
			elif m.has("pull") and not m.has("push") and play.state == PlayMode.S.POWER and play.meter >= 0.6:
				_pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
				_pad_axis(JOY_AXIS_RIGHT_X, 0.12)
				m["push"] = n
				m["pulled"] = play.meter
			elif m.has("push") and n == int(m.push) + 3:
				_pad_axis(JOY_AXIS_RIGHT_Y, -1.0)
			elif m.has("push") and not m.has("stick_done") and play.state == PlayMode.S.FLIGHT:
				_pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
				_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
				m["stick_done"] = n
				print("DEMO 22b the right stick swung: pulled back to %.2f, hit at power %.2f with timing %.2f (%s), stroke %d" % [
					float(m.pulled), play.power, play.needle, play.swing_word, play.g.strokes])
			elif m.has("stick_done") and (play.state == PlayMode.S.PAUSE or play.state == PlayMode.S.AIM or not play.active()):
				print("DEMO 22c and that ball came to rest: %s" % play.message)
				_pad_next()
		15:
			if play.state == PlayMode.S.AIM and not m.has("b1"):
				_pad_tap(JOY_BUTTON_B)
				m["b1"] = n
			elif m.has("b1") and n == int(m.b1) + 6:
				m["warn"] = play.message
				m["still"] = play.active()
				_pad_tap(JOY_BUTTON_B)
			elif m.has("b1") and n == int(m.b1) + 12:
				print("DEMO 23 B asked first ('%s', still playing: %s); B again left the round: %s" % [str(m.warn), str(m.still), str(not play.active())])
				_pad_next()
			elif not play.active() and not m.has("b1"):
				print("DEMO 23 the round ended before B could be tried")
				_pad_next()
		16:
			# the mouse takes the pointer back, and the pad takes it again
			if n == 10:
				_mouse(Vector2(400.0, 300.0), false, true, Vector2(6.0, 0.0))
			elif n == 14:
				m["asleep"] = not pad.active and not pad._dot.visible
				_pad_axis(JOY_AXIS_LEFT_Y, 0.9)
			elif n == 18:
				print("DEMO 24 moving the mouse hid the controller's pointer: %s; the stick brought it back where the mouse was: %s (pointer at %s)" % [
					str(m.asleep), str(pad.active and pad.pos.distance_to(Vector2(400.0, 300.0)) < 60.0), str(pad.pos.round())])
				_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
				m["notes"] = hud.toasts.get_child_count()
				Input.joy_connection_changed.emit(0, true)
			elif n == 22:
				print("DEMO 25 plugging a pad in put up a notice: %s" % str(hud.toasts.get_child_count() > int(m.notes)))
				_pad_next()
		17:
			# the keyboard's zoom keys, which share the camera code the pad uses
			if n == 0:
				m["zdist"] = rig.target_dist
				var key := InputEventKey.new()
				key.keycode = KEY_EQUAL
				key.pressed = true
				Input.parse_input_event(key)
			elif since > 0.4:
				var key_up := InputEventKey.new()
				key_up.keycode = KEY_EQUAL
				key_up.pressed = false
				Input.parse_input_event(key_up)
				print("DEMO 26 holding the + key zoomed in from %.0f m to %.0f m" % [float(m.zdist), rig.target_dist])
				_pad_next()
		18, 102:
			if n == 20:
				print("DEMO 27 gamepad demo finished; pointer showing: %s, toolbar on show: %s" % [str(pad._dot.visible), str(hud.toolbar.visible)])
				if Game.args.has("shot"):
					_save_shot()
				else:
					get_tree().quit()
		100:
			# the start screen: step about with the d-pad, down to the bottom row
			if n == 0:
				_pad_tap(JOY_BUTTON_DPAD_DOWN)
			elif n == 8:
				m["s1"] = _pad_over()
				m["y1"] = pad.pos.y
				_pad_tap(JOY_BUTTON_DPAD_RIGHT)
			elif n == 16:
				m["s2"] = _pad_over()
				_pad_tap(JOY_BUTTON_DPAD_DOWN)
			elif n == 30:
				print("DEMO 30 on the start screen the d-pad took the pointer to '%s' (y %.0f), right to '%s', down a row to '%s' (y %.0f of %.0f)" % [
					str(m.s1), float(m.y1), str(m.s2), _pad_over(), pad.pos.y, vp.y])
				if Game.args.has("shot"):
					_grab(str(Game.args.shot).replace(".png", "_start.png"))
			elif n == 40:
				m["before"] = str(Game.sim.scenario.def.id)
				_pad_tap(JOY_BUTTON_A)
			elif n == 60:
				print("DEMO 31 A there changed the scenario from '%s' to '%s'; start screen closed: %s" % [str(m.before), str(Game.sim.scenario.def.id), str(not hud.modal_open())])
				_demo_mem["i"] = 102
				_demo_mem["n"] = 0


## The heading of the open dialog.
func _modal_title() -> Label:
	for c in hud.modal_card.get_children():
		if c is Label:
			return c as Label
	return null


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if Game.args.has("crop"):
		# --crop=x,y,w,h in window pixels: keep one piece at full sharpness
		var c := str(Game.args.crop).split(",")
		img = img.get_region(Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
	elif img.get_width() > 1600:
		img.resize(1600, int(1600.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_png(path)


func _save_shot() -> void:
	await _grab(str(Game.args.shot))
	get_tree().quit()
