extends Node
## Global game state: the data files, the running simulation and its clock.
## The simulation advances in fixed steps; views interpolate between them
## using `alpha`, so motion stays smooth at any refresh rate.

signal sim_changed()
signal quality_changed()
signal volume_changed()

const STEP := 1.0 / 60.0
const SAVE_FILE := "user://save.json"
const TEST_SAVE_FILE := "user://save_test.json"   # screenshot and test runs never touch the real slot
var SAVE_PATH := SAVE_FILE
const CAREER_FILE := "user://career.json"
const TEST_CAREER_FILE := "user://career_test.json"
var CAREER_PATH := CAREER_FILE
var _session_live := false   # the owner has started or loaded a game; the hidden first layout is not one
const SETTINGS_PATH := "user://settings.cfg"
## Graphics presets, lightest first. See Main._apply_quality.
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]

var db: DataDB
var gear: Gear
var sim: Sim
var speed := 1
var paused := false
var alpha := 0.0
var args := {}
var _acc := 0.0
var prof_sum := {}
var prof_max := {}
var prof_frame := {}           # microseconds per section in the frame being built
var steps_this_frame := 0
var quality := 2
var scroll_pans := false       # a swipe or two-finger scroll moves the map instead of zooming
var pad_rumble := true         # a controller buzzes when the player strikes the ball
var hold_rate := true          # soften the 3D picture a little when the frame rate cannot be held
var fullscreen := true         # own the whole screen, so frames go straight to the display instead of through the desktop compositor
var window_size := Vector2i.ZERO   # the window's size in pixels when not full screen; zero fits the screen
var render_lines := 0          # lines the 3D picture is drawn at: 0 lets the preset decide, -1 is the window's own
var ui_scale := 1.0            # the interface's size, on top of the window's own scaling
var tutorial_done := false     # the guided first round has been finished or put away
var difficulty := 2            # the difficulty slider, 0 relaxed .. 4 brutal; a new game starts on it
var vol_music := 0.75          # 0 to 1
var vol_sound := 0.8


## Record how long a section of a frame took (only used with --perf).
func prof(section: String, start_usec: int) -> void:
	var dt := Time.get_ticks_usec() - start_usec
	prof_sum[section] = int(prof_sum.get(section, 0)) + dt
	prof_max[section] = maxi(int(prof_max.get(section, 0)), dt)
	prof_frame[section] = int(prof_frame.get(section, 0)) + dt


func _ready() -> void:
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	db = DataDB.new()
	gear = Gear.new(db)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("shot") or args.has("exit"):
		SAVE_PATH = TEST_SAVE_FILE
		CAREER_PATH = TEST_CAREER_FILE
	_migrate_saves()
	if args.has("quality"):
		quality = clampi(int(args.quality), 0, QUALITY_NAMES.size() - 1)
	else:
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK:
			quality = clampi(int(cfg.get_value("graphics", "quality", 2)), 0, QUALITY_NAMES.size() - 1)
	var saved := ConfigFile.new()
	if saved.load(SETTINGS_PATH) == OK:
		scroll_pans = bool(saved.get_value("controls", "scroll_pans", false))
		difficulty = clampi(int(saved.get_value("game", "difficulty", int(db.difficulty.get("default", 2)))), 0, 4)
		pad_rumble = bool(saved.get_value("controls", "pad_rumble", true))
		hold_rate = bool(saved.get_value("graphics", "hold_rate", true))
		fullscreen = bool(saved.get_value("graphics", "fullscreen", true))
		window_size = Vector2i(int(saved.get_value("graphics", "window_w", 0)), int(saved.get_value("graphics", "window_h", 0)))
		render_lines = int(saved.get_value("graphics", "render_lines", 0))
		ui_scale = clampf(float(saved.get_value("graphics", "ui_scale", 1.0)), 0.8, 1.1)
		tutorial_done = bool(saved.get_value("game", "tutorial_done", false))
		vol_music = clampf(float(saved.get_value("audio", "music", 0.75)), 0.0, 1.0)
		vol_sound = clampf(float(saved.get_value("audio", "sound", 0.8)), 0.0, 1.0)
	if args.has("holdrate"):
		hold_rate = int(args.holdrate) != 0
	if args.has("win"):
		# --win=3200x1800: a window of exactly this size, for measuring
		var wh := str(args.win).split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		get_window().position = Vector2i(40, 60)
	elif not args.has("shot") and DisplayServer.get_name() != "headless":
		_fit_window()
	# Test and measuring runs stay in a window unless they ask otherwise.
	var test_run := args.has("shot") or args.has("exit") or args.has("perf") or args.has("win") or args.has("demo")
	if args.has("fullscreen"):
		fullscreen = int(args.fullscreen) != 0
	elif test_run or args.has("windowed"):
		fullscreen = false
	if DisplayServer.get_name() != "headless":
		get_window().content_scale_factor = ui_scale
	if fullscreen and DisplayServer.get_name() != "headless":
		_fullscreen_once_open()


## Go full screen once the window is on screen and in front. macOS notes
## a request made while the window is still opening, or while another app
## is in front, and then never makes the switch.
func _fullscreen_once_open() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	while fullscreen and not get_window().has_focus():
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(0.25).timeout
	if fullscreen:
		_apply_fullscreen()


## Full screen or a window. Remembered.
##
## In a window every frame is handed to the desktop's compositor, which
## blends it with everything else on screen before it is shown: a frame
## later, and at the compositor's pace. A game that owns the whole screen
## can have its frames sent straight to the display.
func set_fullscreen(on: bool) -> void:
	fullscreen = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "fullscreen", on)
	cfg.save(SETTINGS_PATH)
	_apply_fullscreen()


func _apply_fullscreen() -> void:
	var win := get_window()
	if fullscreen:
		win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	elif win.mode != Window.MODE_WINDOWED:
		win.mode = Window.MODE_WINDOWED
		_fit_window()


## Move the difficulty slider. Remembered for the next new game, and the
## game being played feels it at once.
func set_difficulty(level: int) -> void:
	difficulty = clampi(level, 0, 4)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.save(SETTINGS_PATH)
	if sim != null:
		sim.set_difficulty(difficulty)


## Whether a swipe moves the map (true) or zooms (false). Remembered.
func set_scroll_pans(on: bool) -> void:
	scroll_pans = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("controls", "scroll_pans", on)
	cfg.save(SETTINGS_PATH)


## Whether a controller buzzes on the player's own shots. Remembered.
func set_pad_rumble(on: bool) -> void:
	pad_rumble = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("controls", "pad_rumble", on)
	cfg.save(SETTINGS_PATH)


## Music and sound levels, 0 to 1. Remembered.
func set_volumes(music: float, sound: float) -> void:
	vol_music = clampf(music, 0.0, 1.0)
	vol_sound = clampf(sound, 0.0, 1.0)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music", vol_music)
	cfg.set_value("audio", "sound", vol_sound)
	cfg.save(SETTINGS_PATH)
	volume_changed.emit()


## Whether the game may soften the 3D picture to hold the frame rate. Remembered.
func set_hold_rate(on: bool) -> void:
	hold_rate = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "hold_rate", on)
	cfg.save(SETTINGS_PATH)
	quality_changed.emit()


## Choose a graphics preset and remember it for next time.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, QUALITY_NAMES.size() - 1)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "quality", quality)
	cfg.save(SETTINGS_PATH)
	quality_changed.emit()


## Godot sizes windows in physical pixels, so on a high-density display the
## default window comes out tiny. Scale it up and centre it, or use the size
## the player chose if it fits.
func _fit_window() -> void:
	var win := get_window()
	var screen := win.current_screen
	var density := DisplayServer.screen_get_scale(screen)
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var want := Vector2(1600.0, 900.0) * density
	if window_size.x > 0 and window_size.y > 0 and window_size.x <= usable.size.x and window_size.y <= usable.size.y:
		want = Vector2(window_size)
	else:
		var fit := minf(usable.size.x * 0.96 / want.x, usable.size.y * 0.9 / want.y)
		if fit < 1.0:
			want *= fit
	win.size = Vector2i(want)
	win.position = usable.position + (usable.size - Vector2i(want)) / 2


## Window sizes worth offering on this screen, largest last. Zero means
## "fit the screen", which is the default.
func window_sizes() -> Array[Vector2i]:
	var usable := DisplayServer.screen_get_usable_rect(get_window().current_screen)
	var out: Array[Vector2i] = [Vector2i.ZERO]
	for s: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3440, 1440), Vector2i(3840, 2160), Vector2i(5120, 2880)]:
		if s.x <= usable.size.x and s.y <= usable.size.y:
			out.append(s)
	return out


## Pick a window size (zero fits the screen). Remembered; applied when not full screen.
func set_window_size(size: Vector2i) -> void:
	window_size = size
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "window_w", size.x)
	cfg.set_value("graphics", "window_h", size.y)
	cfg.save(SETTINGS_PATH)
	if not fullscreen and DisplayServer.get_name() != "headless":
		_fit_window()


## The lines the 3D picture is drawn at: 0 lets the preset decide, -1 draws
## at the window's own size, else the number given. Remembered.
func set_render_lines(lines: int) -> void:
	render_lines = lines
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "render_lines", lines)
	cfg.save(SETTINGS_PATH)
	quality_changed.emit()


## Remember that the guided first round was finished or put away.
func set_tutorial_done(done: bool) -> void:
	tutorial_done = done
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("game", "tutorial_done", done)
	cfg.save(SETTINGS_PATH)


## How big the interface is drawn, 0.8 to 1.1 of its usual size. Remembered.
func set_ui_scale(scale: float) -> void:
	ui_scale = clampf(scale, 0.8, 1.1)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "ui_scale", ui_scale)
	cfg.save(SETTINGS_PATH)
	if DisplayServer.get_name() != "headless":
		get_window().content_scale_factor = ui_scale


func new_game(scenario_id: String, seed_value: int = 0, biome_id: String = "", take_career: bool = true) -> void:
	if _session_live and sim != null:
		_store_career()
	var scen := DataDB.find(db.scenarios, scenario_id)
	if scen.is_empty():
		scen = db.scenarios[0]
	sim = Sim.new(db, scen, seed_value, gear, biome_id)
	sim.set_difficulty(difficulty)
	if take_career:
		_load_career()
	_session_live = take_career
	if not sim.scenario_ended.is_connected(_store_career):
		sim.scenario_ended.connect(_store_career)
	_acc = 0.0
	speed = 1
	paused = false
	sim_changed.emit()


func _process(delta: float) -> void:
	if sim == null:
		return
	# Painting while the game is paused still has to move par onto the new fairway.
	sim.refresh_hole_lines()
	if paused:
		return
	var t0 := Time.get_ticks_usec()
	_acc += minf(delta, 0.1) * speed
	var n := 0
	while _acc >= STEP and n < 48:
		sim.step(STEP)
		_acc -= STEP
		n += 1
	if n >= 48:
		_acc = 0.0
	alpha = _acc / STEP
	steps_this_frame = n
	prof("sim", t0)


## Run the simulation ahead without drawing, for tests and screenshots.
func fast_forward(seconds: float) -> void:
	if sim == null:
		return
	for i in int(seconds / STEP):
		sim.step(STEP)


## The game's folder was renamed twice in a day. Bring a save and settings
## left under an old name across, if they are newer than what is here.
func _migrate_saves() -> void:
	var here := OS.get_user_data_dir()
	var parent := here.get_base_dir()
	# Godot keeps a project's folder under Godot/app_userdata unless it has
	# a custom name, as this one now does; look in both places
	var olds: Array[String] = []
	for old_name in ["Par & Parcel", "Sim Golf", "ParAndParcel"]:
		olds.append(parent.path_join(old_name))
		olds.append(parent.path_join("Godot").path_join("app_userdata").path_join(old_name))
	for old in olds:
		if old == here or not DirAccess.dir_exists_absolute(old):
			continue
		for file in ["save.json", "settings.cfg"]:
			var src := old.path_join(file)
			var dst := here.path_join(file)
			if not FileAccess.file_exists(src):
				continue
			if FileAccess.file_exists(dst) and FileAccess.get_modified_time(dst) >= FileAccess.get_modified_time(src):
				continue
			if DirAccess.copy_absolute(src, dst) == OK:
				print("Brought %s across from %s." % [file, old])


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	if sim == null:
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(sim.to_dict()))
	f.close()
	_store_career()
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary) or not parsed.has("course"):
		return false
	sim = Sim.from_dict(db, parsed, gear)
	_session_live = true
	if not sim.scenario_ended.is_connected(_store_career):
		sim.scenario_ended.connect(_store_career)
	_acc = 0.0
	speed = 1
	paused = false
	sim_changed.emit()
	return true


func carried_money() -> float:
	if not FileAccess.file_exists(CAREER_PATH):
		return 0.0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAREER_PATH))
	if not (parsed is Dictionary):
		return 0.0
	return maxf(float(parsed.get("money", 0.0)), 0.0)


func _store_career(_won: bool = false) -> void:
	if sim == null:
		return
	var f := FileAccess.open(CAREER_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(CareerBook.pack(sim)))
	f.close()


func _load_career() -> void:
	if sim == null or not FileAccess.file_exists(CAREER_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAREER_PATH))
	if parsed is Dictionary:
		CareerBook.apply(sim, parsed)

