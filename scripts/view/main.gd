extends Node3D
class_name Main
## The scene root: builds the 3D world and the interface, and wires them to
## whichever simulation is running.

var terrain := TerrainView.new()
var grass := GrassView.new()
var world := WorldView.new()
var arrows := SlopeArrows.new()
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
var driver: DemoDriver = null
var _autosave_month := -1
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
	add_child(arrows)
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
	arrows.rig = rig
	arrows.play = play
	hud.arrows = arrows
	tools.selection_changed.connect(hud.inspect)
	tools.hole_added.connect(func(_i: int) -> void: hud.open_dock("holes"))
	play.started.connect(func() -> void:
		tools.set_mode("")
		tools.enabled = false
		hud.close_dock())
	play.ended.connect(func() -> void: tools.enabled = true)
	play.round_done.connect(hud.show_round_summary)
	loading = LoadingScreen.new()
	add_child(loading)
	hud.loading = loading
	hud.new_game_requested.connect(func(id: String, biome_id: String) -> void:
		hud.hide_modal()
		await loading.run("Laying out the land", func() -> void: Game.new_game(id, 0, biome_id))
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
	Game.new_game(scen, int(Game.args.get("seed", "0")), str(Game.args.get("biome", "")), false)
	if not scripted:
		hud.show_scenarios(true)
	_attach_driver()



func _attach_driver() -> void:
	if not DemoDriver.wanted(Game.args):
		return
	driver = DemoDriver.new()
	driver.rig = rig
	driver.hud = hud
	driver.tools = tools
	driver.play = play
	driver.desk = desk
	driver.pad = pad
	driver.world = world
	driver.fx = fx
	driver.loading = loading
	driver.terrain = terrain
	driver.sky = sky
	add_child(driver)
	driver.apply()


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
	if play.active():
		play.state = PlayMode.S.OFF
		rig.locked = false
		rig.pitch_override = -1.0
		rig.v_shift = 0.0
	tools.enabled = true
	terrain.set_biome(sim.biome)
	sky.set_biome(sim.biome)
	terrain.bind(sim.course)
	terrain.sim = sim
	grass.bind(terrain, sim.course, sim.biome)
	rig.bind(sim.course)
	world.bind(sim, rig)
	crowd.bind(sim, rig)
	fx.bind(sim, rig)
	volcano.bind(sim, rig, terrain)
	tools.bind(sim)
	arrows.set_sim(sim)
	hud.bind(sim)
	var fresh := sim.course.holes.is_empty() and sim.time < 1.0
	var scripted_run := Game.args.has("shot") or Game.args.has("exit")
	if Game.args.has("tutorial") or (fresh and not Game.tutorial_done and not scripted_run and str(sim.scenario.def.get("mode", "free")) == "free"):
		# the first time on empty land, the coach walks through the first hole
		hud.start_tutorial()
	elif fresh and not scripted_run:
		hud.show_toast("This land is yours and there is not a hole on it yet. Open Build to paint a tee and a green, then Holes to lay out the first hole. The Build panel also sells the land round you.", "info", 16.0)
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


var loading: LoadingScreen
var _season_day := -1




func _process(delta: float) -> void:
	if Game.sim == null:
		return
	_govern()
	if driver != null:
		driver.tests(delta)
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
	if driver != null:
		driver.advance(delta)
		driver.count_down()


