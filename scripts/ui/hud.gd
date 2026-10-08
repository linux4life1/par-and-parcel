class_name Hud
extends CanvasLayer
## The in-game interface: status bar, feed ticker, toolbar, the side panel,
## notifications, dialogs, and the controls shown while you play a round.

signal new_game_requested(scenario_id: String, biome_id: String)

var sim: Sim
var tools: BuildTools
var play: PlayMode
var rig: CameraRig
var world: WorldView
var terrain: TerrainView

var root := Control.new()
var panels: Panels
var dock: PanelContainer
var dock_title: Label
var dock_body: VBoxContainer
var dock_name := ""
var toolbar: VBoxContainer
var top_box: VBoxContainer
var _refresh := Callable()
var _refresh_t := 0.0
var _tool_buttons := {}

var l_name: Label
var l_date: Label
var l_clock: Label
var sky_icon := SkyIcon.new()
var l_money: Label
var l_weather: Label
var l_wind: Label
var l_golfers: Label
var l_sat: Label
var l_rating: Label
var stars := UIKit.StarBar.new()
var dial := UIKit.WindDial.new()
var speed_btns: Array[Button] = []

var ticker_clip: Control
var ticker_label: Label
var _ticker_queue: Array[Dictionary] = []
var _ticker_x := 0.0
var _ticker_idle := 0.0

var toasts: VBoxContainer
var hint_panel: PanelContainer
var hint_label: Label
var overlay_btns: Array[Button] = []
var contour_btn: Button
var bottom_right: VBoxContainer
var inspector: PanelContainer
var inspector_body: VBoxContainer
var _inspected: Variant = null
var _menu_was_paused := false

var play_panel: PanelContainer
var play_title: Label
var play_info: Label
var play_advice: Label
var tutorial: Tutorial
var loading: LoadingScreen        # shown while a game is laid out or read back
var play_msg: Label
var play_keys: Label
var meter := UIKit.Meter.new()

var modal: Control
var modal_card: VBoxContainer
var _goal_flag := ""


func _ready() -> void:
	layer = 5
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	panels = Panels.new(self)
	_build_top()
	_build_toolbar()
	_build_dock()
	_build_bottom()
	_build_play_panel()
	_build_modal()
	tutorial = Tutorial.new()
	tutorial.hud = self
	root.add_child(tutorial)
	root.move_child(tutorial, modal.get_index())   # above the panels, under the dialogs


func bind(s: Sim) -> void:
	sim = s
	close_dock()
	hide_modal()
	UIKit.clear(toasts)
	_ticker_queue.clear()
	_inspected = null
	inspector.visible = false
	sim.toast.connect(show_toast)
	sim.feed.posted.connect(func(p: Dictionary) -> void:
		_ticker_queue.append(p)
		if _ticker_queue.size() > 6:
			_ticker_queue.pop_front())
	sim.dialog.connect(_on_event_dialog)
	sim.scenario_ended.connect(_on_scenario_ended)
	sim.tourney.finished.connect(_on_tournament_finished)
	l_name.text = sim.course_name
	set_overlay(0)
	tutorial.bind(sim)


## The guided first round: a card that says what to do next and moves on
## when it sees it done.
func start_tutorial() -> void:
	close_dock()
	tutorial.start()


# ------------------------------------------------------------ status bar

func _build_top() -> void:
	top_box = UIKit.vbox(6)
	top_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_box.offset_left = 10
	top_box.offset_right = -10
	top_box.offset_top = 8
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_box)
	var bar := PanelContainer.new()
	top_box.add_child(bar)
	var h := UIKit.hbox(14)
	bar.add_child(h)
	l_name = UIKit.label("", 17)
	# the name gives way first when the interface is drawn large
	l_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l_name.custom_minimum_size = Vector2(70, 0)
	l_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l_name)
	h.add_child(stars)
	l_rating = UIKit.label("", 14, UIKit.MUTED)
	l_rating.tooltip_text = "Course rating out of 100: golfer satisfaction, course condition and design."
	l_rating.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(l_rating)
	h.add_child(_sep())
	l_date = UIKit.label("", 15)
	l_date.tooltip_text = "The season. Wages, upkeep and membership dues are settled at the end of each month."
	l_date.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(l_date)
	var ch := UIKit.hbox(5)
	ch.tooltip_text = "The time of day. After sunset golfers enjoy unlit holes less, and pay less for them."
	ch.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(ch)
	ch.add_child(sky_icon)
	l_clock = UIKit.label("", 15)
	l_clock.custom_minimum_size = Vector2(68, 0)
	ch.add_child(l_clock)
	var sp := UIKit.hbox(3)
	h.add_child(sp)
	var names := ["II", "1x", "2x", "4x", "8x"]
	for i in names.size():
		var b := UIKit.button(names[i], _set_speed.bind(i), "Pause (Space)" if i == 0 else "Game speed")
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(38, 0)
		sp.add_child(b)
		speed_btns.append(b)
	h.add_child(UIKit.spacer())
	l_weather = UIKit.label("", 15)
	h.add_child(l_weather)
	h.add_child(dial)
	l_wind = UIKit.label("", 15)
	h.add_child(l_wind)
	h.add_child(_sep())
	l_golfers = UIKit.label("", 15)
	h.add_child(l_golfers)
	l_sat = UIKit.label("", 15)
	l_sat.tooltip_text = "Average satisfaction of the golfers who recently left."
	l_sat.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(l_sat)
	h.add_child(_sep())
	l_money = UIKit.label("", 20, UIKit.GOOD)
	h.add_child(l_money)

	# the feed ticker
	var tp := PanelContainer.new()
	tp.add_theme_stylebox_override("panel", UIKit.box(Color(0.05, 0.08, 0.07, 0.85), 8, 10, 4))
	top_box.add_child(tp)
	var th := UIKit.hbox(10)
	tp.add_child(th)
	th.add_child(UIKit.label("BIRDIE", 12, UIKit.BLUE))
	ticker_clip = Control.new()
	ticker_clip.clip_contents = true
	ticker_clip.custom_minimum_size = Vector2(0, 22)
	ticker_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ticker_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	ticker_clip.tooltip_text = "What golfers are saying. Click to open the feed."
	ticker_clip.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open_dock("feed"))
	th.add_child(ticker_clip)
	ticker_label = UIKit.label("", 14)
	ticker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker_clip.add_child(ticker_label)


func _sep() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.12)
	c.custom_minimum_size = Vector2(1, 22)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _set_speed(i: int) -> void:
	if i == 0:
		Game.paused = not Game.paused
	else:
		Game.paused = false
		Game.speed = [1, 1, 2, 4, 8][i]


# --------------------------------------------------------------- toolbar

func _build_toolbar() -> void:
	toolbar = UIKit.vbox(5)
	toolbar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	toolbar.offset_left = 10
	toolbar.offset_top = 104
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toolbar)
	var items := [
		["build", "Build", "Paint terrain, shape the land, place scenery (B)"],
		["holes", "Holes", "Hole list and green fees (H)"],
		["staff", "Staff", "Hire greenkeepers, exterminators and marshals"],
		["money", "Finances", "Income and costs"],
		["members", "Members", "The club's members, their tiers, and what each one wants"],
		["tournaments", "Tournaments", "Host events for prize money"],
		["skills", "Manager", "Spend skill points on how you run the club"],
		["golfer", "My Golfer", "Your golfer's attributes, challenges and medals"],
		["shop", "Pro Shop", "Clubs and balls for your own golfer"],
		["goals", "Goals", "Scenario objectives and course records"],
		["feed", "Feed", "What golfers are posting"],
	]
	for it: Array in items:
		var b := UIKit.button(str(it[1]), open_dock.bind(str(it[0])), str(it[2]))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(118, 34)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toolbar.add_child(b)
		_tool_buttons[it[0]] = b
	toolbar.add_child(UIKit.gap(6))
	var pb := UIKit.button("Play a Round", func() -> void: open_dock("play"), "Tee it up on your own course (P)")
	pb.custom_minimum_size = Vector2(118, 40)
	pb.add_theme_stylebox_override("normal", UIKit.box(Color(0.16, 0.42, 0.24), 6, 12, 6, Color(0.5, 0.9, 0.6, 0.4)))
	toolbar.add_child(pb)
	_tool_buttons["play"] = pb
	var mb := UIKit.button("Menu", func() -> void: show_menu(), "Save, load, new game (Esc)")
	mb.custom_minimum_size = Vector2(118, 30)
	toolbar.add_child(mb)


# ------------------------------------------------------------ side panel

func _build_dock() -> void:
	dock = PanelContainer.new()
	dock.anchor_left = 1.0
	dock.anchor_right = 1.0
	dock.anchor_top = 0.0
	dock.anchor_bottom = 1.0
	dock.offset_left = -470
	dock.offset_right = -10
	dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dock.offset_top = 104
	dock.offset_bottom = -108
	dock.visible = false
	root.add_child(dock)
	var v := UIKit.vbox(8)
	dock.add_child(v)
	var head := UIKit.hbox()
	v.add_child(head)
	dock_title = UIKit.label("", 19)
	head.add_child(dock_title)
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.button("Close", close_dock))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	dock_body = UIKit.vbox(8)
	dock_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(dock_body)


func open_dock(panel: String) -> void:
	if dock_name == panel:
		close_dock()
		return
	if panel != "build" and tools != null and tools.mode != "":
		tools.set_mode("")
	SoundDesk.ui("open")
	dock_name = panel
	UIKit.clear(dock_body)
	dock_title.text = panels.title(panel)
	_refresh = panels.build(panel, dock_body)
	dock.visible = true
	for key: String in _tool_buttons:
		var b: Button = _tool_buttons[key]
		if b.toggle_mode:
			b.set_pressed_no_signal(key == panel)
	if _refresh.is_valid():
		_refresh.call()


func close_dock() -> void:
	dock_name = ""
	dock.visible = false
	_refresh = Callable()
	UIKit.clear(dock_body)
	for key: String in _tool_buttons:
		var b: Button = _tool_buttons[key]
		if b.toggle_mode:
			b.set_pressed_no_signal(false)
	if tools != null and tools.mode != "":
		tools.set_mode("")


func rebuild_dock() -> void:
	if dock_name == "":
		return
	var n := dock_name
	dock_name = ""
	open_dock(n)


## On to the next panel in toolbar order, or back to the one before: a
## controller's bumpers.
func step_dock(dir: int) -> void:
	var names: Array = _tool_buttons.keys()
	var i := names.find(dock_name)
	if i < 0:
		i = -1 if dir > 0 else 0
	open_dock(str(names[wrapi(i + dir, 0, names.size())]))


# ------------------------------------------------- bottom of the screen

func _build_bottom() -> void:
	toasts = UIKit.vbox(6)
	toasts.anchor_top = 1.0
	toasts.anchor_bottom = 1.0
	toasts.offset_left = 140
	toasts.offset_right = 600
	toasts.offset_bottom = -16
	toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toasts.alignment = BoxContainer.ALIGNMENT_END
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)

	hint_panel = PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.offset_bottom = -64
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.visible = false
	root.add_child(hint_panel)
	hint_label = UIKit.label("", 14)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_panel.add_child(hint_label)

	bottom_right = UIKit.vbox(8)
	bottom_right.anchor_left = 1.0
	bottom_right.anchor_right = 1.0
	bottom_right.anchor_top = 1.0
	bottom_right.anchor_bottom = 1.0
	bottom_right.offset_right = -10
	bottom_right.offset_bottom = -12
	bottom_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_right.alignment = BoxContainer.ALIGNMENT_END
	bottom_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_right)

	inspector = PanelContainer.new()
	inspector.custom_minimum_size = Vector2(330, 0)
	inspector.visible = false
	root.add_child(inspector)
	inspector_body = UIKit.vbox(5)
	inspector.add_child(inspector_body)

	# Camera buttons: everything the camera can do, for anyone without a
	# scroll wheel, a right button or a keyboard to hand. Hold to keep going.
	var cp := PanelContainer.new()
	cp.add_theme_stylebox_override("panel", UIKit.box(UIKit.BG, 8, 8, 5, Color(1, 1, 1, 0.08)))
	cp.size_flags_horizontal = Control.SIZE_SHRINK_END
	bottom_right.add_child(cp)
	var ch := UIKit.hbox(4)
	cp.add_child(ch)
	ch.add_child(UIKit.label("Camera", 12, UIKit.MUTED))
	var alt_key := "Option" if OS.get_name() == "macOS" else "Alt"
	var pad := [
		["turn_left", "Turn the view left. Hold to keep turning. (Q, or %s-drag)" % alt_key, Vector3(1, 0, 0)],
		["turn_right", "Turn the view right. (E)", Vector3(-1, 0, 0)],
		["tilt_up", "Look from higher up. (T, or %s-drag up and down)" % alt_key, Vector3(0, 1, 0)],
		["tilt_down", "Look from lower down. (G)", Vector3(0, -1, 0)],
		["zoom_in", "Zoom in. (scroll, or +)", Vector3(0, 0, 1)],
		["zoom_out", "Zoom out. (scroll, or -)", Vector3(0, 0, -1)],
	]
	for it: Array in pad:
		var ib := IconButton.make(str(it[0]), str(it[1]))
		var push: Vector3 = it[2]
		ib.button_down.connect(func() -> void:
			if rig != null:
				rig.nudge = push)
		ib.button_up.connect(func() -> void:
			if rig != null:
				rig.nudge = Vector3.ZERO)
		ch.add_child(ib)
	var home := IconButton.make("reset", "Back to the usual angle. (Home)")
	home.pressed.connect(func() -> void:
		if rig != null and not rig.locked:
			rig.reset_view())
	ch.add_child(home)

	var op := PanelContainer.new()
	op.add_theme_stylebox_override("panel", UIKit.box(UIKit.BG, 8, 8, 5, Color(1, 1, 1, 0.08)))
	op.size_flags_horizontal = Control.SIZE_SHRINK_END
	bottom_right.add_child(op)
	var oh := UIKit.hbox(4)
	op.add_child(oh)
	oh.add_child(UIKit.label("View", 12, UIKit.MUTED))
	var names := ["Normal", "Moisture", "Turf", "Height", "Mood", "Lots", "Lights"]
	var tips := ["The course as golfers see it", "How wet the ground is. Wet ground kills bounce and roll.", "Turf health and weeds", "Elevation", "Where golfers have been pleased or annoyed. It fades over a couple of days.", "Where a home site is worth the most. Brighter ground is dearer.", "Where the floodlights and lamps reach. Brighter ground is lit after dark."]
	for i in names.size():
		var b := UIKit.button(names[i], set_overlay.bind(i), tips[i])
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		oh.add_child(b)
		overlay_btns.append(b)
	contour_btn = UIKit.button("Contours", func() -> void: _apply_contours(), "Height lines every 25 cm. Use them to read greens.")
	contour_btn.toggle_mode = true
	contour_btn.add_theme_font_size_override("font_size", 13)
	oh.add_child(contour_btn)


func set_overlay(i: int) -> void:
	for k in overlay_btns.size():
		overlay_btns[k].set_pressed_no_signal(k == i)
	if terrain != null:
		terrain.material.set_shader_parameter("overlay", i)


func _apply_contours() -> void:
	if terrain != null:
		var on := contour_btn.button_pressed or (tools != null and (tools.mode == "sculpt" or tools.mode == "hole")) or (play != null and play.active() and play.putting)
		terrain.material.set_shader_parameter("contour_alpha", 1.0 if on else 0.0)


func show_toast(text: String, kind: String = "info", seconds: float = 6.0) -> void:
	var p := PanelContainer.new()
	var col := Color(0.10, 0.14, 0.13, 0.95)
	var edge := Color(1, 1, 1, 0.15)
	if kind == "good":
		edge = Color(0.4, 0.85, 0.5, 0.7)
		SoundDesk.ui("chime")
	elif kind == "medal":
		edge = Color(1.0, 0.84, 0.3, 0.8)
		SoundDesk.ui("medal")
	elif kind == "bad":
		edge = Color(0.95, 0.4, 0.35, 0.7)
		SoundDesk.ui("alert")
	else:
		SoundDesk.ui("pop")
	p.add_theme_stylebox_override("panel", UIKit.box(col, 8, 12, 8, edge))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > 5:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# -------------------------------------------------------- play controls

func _build_play_panel() -> void:
	play_panel = PanelContainer.new()
	play_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	play_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	play_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	play_panel.offset_bottom = -16
	play_panel.visible = false
	root.add_child(play_panel)
	var v := UIKit.vbox(3)
	play_panel.add_child(v)
	play_title = UIKit.label("", 17)
	play_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(play_title)
	play_info = UIKit.label("", 14, UIKit.MUTED)
	play_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(play_info)
	play_advice = UIKit.label("", 13, UIKit.MUTED)
	play_advice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(play_advice)
	v.add_child(UIKit.gap(10))
	var mh := UIKit.hbox()
	mh.alignment = BoxContainer.ALIGNMENT_CENTER
	mh.add_child(meter)
	v.add_child(mh)
	play_msg = UIKit.label("", 15, UIKit.GOLD)
	play_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(play_msg)
	play_keys = UIKit.label("", 12, UIKit.MUTED)
	play_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(play_keys)


func _update_play() -> void:
	var on := play != null and play.active()
	play_panel.visible = on
	toolbar.visible = not on
	if not on:
		return
	var p := play
	var h := p.hole()
	var c := p.club()
	var brand := p.g.brand_of(str(c.cat))
	play_title.text = "Hole %d  ·  Par %d  ·  Stroke %d" % [p.hole_i + 1, h.par, p.g.strokes + 1]
	var ball_name := str(sim.db.ball(sim.player.ball_id).name)
	if p.putting:
		play_info.text = "Putter (%s)  ·  %d feet to the hole  ·  %s" % [brand.get("name", ""), int(p.pin_dist * 3.281), ball_name]
	else:
		play_info.text = "%s (%s)  ·  %s  ·  reaches %d yd  ·  pin %d yd  ·  lie: %s  ·  %s" % [
			c.name, brand.get("name", ""), p.shape().name, Defs.yards(p.max_dist), Defs.yards(p.pin_dist), p.lie_name(), ball_name]
	play_advice.text = p.advice()
	play_advice.visible = play_advice.text != ""
	if not p.match_play.is_empty():
		play_title.text += "  ·  Match: you %d, %s %d" % [int(p.match_play.won), p.match_play.rival, int(p.match_play.lost)]
	elif p.tournament:
		play_title.text += "  ·  Tournament round"
	meter.running = p.state == PlayMode.S.POWER or p.state == PlayMode.S.ACCURACY
	meter.marker = p.meter
	meter.locked = p.power if (p.state == PlayMode.S.ACCURACY or p.state == PlayMode.S.SWING or p.state == PlayMode.S.FLIGHT) else -1.0
	meter.target = p.target_power
	meter.zone = p.zone
	meter.good = p.good
	meter.perfect = p.perfect
	meter.show_result = p.state == PlayMode.S.SWING or p.state == PlayMode.S.FLIGHT or p.state == PlayMode.S.PAUSE
	meter.result = p.needle
	play_msg.text = p.message
	match p.state:
		PlayMode.S.AIM:
			play_keys.text = "A / D aim   ·   W / S club   ·   Q / E shot shape   ·   Tab ball   ·   Space swing   ·   Esc quit the round"
		PlayMode.S.POWER:
			play_keys.text = "Space to set the power. The gold line reaches the pin; past the 100 mark is an overswing."
		PlayMode.S.ACCURACY:
			play_keys.text = "Space as the marker comes back to the line. Anywhere in the green band flies straight; the thin bright line is flush."
		_:
			play_keys.text = ""


# ---------------------------------------------------------------- dialogs

func _build_modal() -> void:
	modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	root.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(Color(0.07, 0.10, 0.09, 0.98), 14, 26, 22, Color(1, 1, 1, 0.12)))
	center.add_child(p)
	modal_card = UIKit.vbox(12)
	p.add_child(modal_card)


func hide_modal() -> void:
	modal.visible = false
	UIKit.clear(modal_card)


func modal_open() -> bool:
	return modal.visible


## A message with buttons. Each option is [label, Callable].
func show_dialog(title: String, text: String, options: Array, pause: bool = true) -> void:
	UIKit.clear(modal_card)
	modal_card.custom_minimum_size = Vector2(520, 0)
	modal_card.add_child(UIKit.label(title, 24))
	var body := UIKit.para(text, 16, UIKit.TEXT)
	modal_card.add_child(body)
	modal_card.add_child(UIKit.gap(6))
	var h := UIKit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_END
	modal_card.add_child(h)
	var was_paused := Game.paused
	if pause:
		Game.paused = true
	for o: Array in options:
		var cb: Callable = o[1]
		h.add_child(UIKit.button(str(o[0]), func() -> void:
			hide_modal()
			if pause:
				Game.paused = was_paused
			if cb.is_valid():
				cb.call()))
	modal.visible = true


func _on_event_dialog(d: Dictionary) -> void:
	var opts := []
	for o: Dictionary in d.options:
		var id := str(o.id)
		opts.append([str(o.text), func() -> void: sim.events.choose(id)])
	show_dialog(str(d.title), str(d.text), opts)


func _on_scenario_ended(won: bool) -> void:
	var name := str(sim.scenario.def.get("name", "Scenario"))
	if won:
		show_dialog("Scenario complete!", "You met every goal in \"%s\" with time to spare. The course is yours to keep building." % name, [["Keep playing", Callable()]])
	else:
		show_dialog("Out of time", "The deadline for \"%s\" has passed with goals unmet. You can keep playing, or start again from the menu." % name, [["Keep playing", Callable()], ["Menu", show_menu]])


func _on_tournament_finished(r: Dictionary) -> void:
	var text := "%s won at %s.\n\nSponsors and gate: %s\nPurse paid: %s\nNet: %s\n\nThe field rated the course %d out of 100." % [
		r.winner, r.score, Defs.money(float(r.income)), Defs.money(float(r.purse)), Defs.money(float(r.net)), int(r.pro_satisfaction)]
	show_dialog(str(r.name), text, [["Nice", Callable()]])


func show_round_summary(card: Array, pars: Array) -> void:
	var total := 0
	var par_total := 0
	var lines := ""
	for i in card.size():
		total += int(card[i])
		par_total += int(pars[i])
		lines += "Hole %d:  %d  (par %d)\n" % [i + 1, card[i], pars[i]]
	var diff := total - par_total
	var verdict := "even par" if diff == 0 else ("%+d" % diff)
	var extra := "" if play.summary == "" else "\n\n" + play.summary
	show_dialog("Round complete", "%s\nTotal %d, %s.%s" % [lines, total, verdict, extra], [["Back to work", Callable()]], false)


## The pause menu. `again` is set when the menu redraws itself, so it keeps
## hold of whether the game was paused before it first opened.
func show_menu(again: bool = false) -> void:
	UIKit.clear(modal_card)
	modal_card.custom_minimum_size = Vector2(760, 0)
	modal_card.add_child(UIKit.label(Defs.TITLE, 30))
	modal_card.add_child(UIKit.label(sim.course_name if sim != null else "", 15, UIKit.MUTED))
	modal_card.add_child(UIKit.gap(2))
	if not again:
		_menu_was_paused = Game.paused
	Game.paused = true
	# two columns: the game on the left, settings on the right
	var cols := UIKit.hbox(28)
	modal_card.add_child(cols)
	var left := UIKit.vbox(8)
	left.custom_minimum_size = Vector2(290, 0)
	cols.add_child(left)
	var right := UIKit.vbox(6)
	right.custom_minimum_size = Vector2(410, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var items := [
		["Resume", func() -> void:
			hide_modal()
			Game.paused = _menu_was_paused],
		["Save game", func() -> void:
			hide_modal()
			Game.paused = _menu_was_paused
			show_toast("Game saved." if Game.save_game() else "Could not save the game.", "good")],
		["Load game", func() -> void:
			if not Game.has_save():
				hide_modal()
				Game.paused = _menu_was_paused
				show_toast("No saved game found.", "bad")
				return
			hide_modal()
			var ok: bool = await loading.run("Reading your course back", Game.load_game)
			if not ok:
				Game.paused = _menu_was_paused
				show_toast("The saved game could not be read.", "bad")],
		["New game", func() -> void: show_scenarios()],
		["Controls", func() -> void: show_controls()],
		["Display and graphics", func() -> void: show_display()],
		["Tutorial", func() -> void:
			hide_modal()
			Game.paused = _menu_was_paused
			start_tutorial()],
		["Quit to desktop", func() -> void: get_tree().quit()],
	]
	for it: Array in items:
		var b := UIKit.button(str(it[0]), it[1])
		b.custom_minimum_size = Vector2(0, 40)
		left.add_child(b)
	# sound
	right.add_child(UIKit.label("Sound", 14, UIKit.MUTED))
	var sliders := {}
	for pair: Array in [["Music", Game.vol_music], ["Effects", Game.vol_sound]]:
		var vr := UIKit.hbox(10)
		right.add_child(vr)
		var vl := UIKit.label(str(pair[0]), 14)
		vl.custom_minimum_size = Vector2(70, 0)
		vr.add_child(vl)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(pair[1])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.focus_mode = Control.FOCUS_NONE
		vr.add_child(sl)
		sliders[str(pair[0])] = sl
	var music_sl: HSlider = sliders["Music"]
	var sound_sl: HSlider = sliders["Effects"]
	music_sl.value_changed.connect(func(_v: float) -> void: Game.set_volumes(music_sl.value, sound_sl.value))
	sound_sl.value_changed.connect(func(_v: float) -> void:
		Game.set_volumes(music_sl.value, sound_sl.value)
		SoundDesk.ui("click"))
	var np := UIKit.hbox(8)
	right.add_child(np)
	var playing := SoundDesk.desk.now_playing if SoundDesk.desk != null else ""
	var np_label := UIKit.para("Playing: %s" % playing if playing != "" else "Between tracks.", 12)
	np_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	np.add_child(np_label)
	# keep the title current while the menu is open
	var tick := Timer.new()
	tick.wait_time = 0.5
	tick.autostart = true
	tick.timeout.connect(func() -> void:
		var title := SoundDesk.desk.now_playing if SoundDesk.desk != null else ""
		var live := SoundDesk.desk != null and SoundDesk.desk.music_playing()
		np_label.text = "Playing: %s" % title if (live and title != "") else "Between tracks.")
	np_label.add_child(tick)
	var skip := UIKit.button("Next track", func() -> void:
		if SoundDesk.desk != null:
			SoundDesk.desk.skip_track())
	skip.add_theme_font_size_override("font_size", 12)
	np.add_child(skip)
	# how a swipe on a Magic Mouse or trackpad behaves
	right.add_child(UIKit.gap(4))
	right.add_child(UIKit.label("A swipe or two-finger scroll", 14, UIKit.MUTED))
	var srow := UIKit.hbox()
	right.add_child(srow)
	var swipes := [["Zooms", false, "Swipe to zoom, and drag the ground to move the map."], ["Moves the map", true, "Swipe to move the map. Hold Shift and swipe to zoom."]]
	for it: Array in swipes:
		var on: bool = it[1]
		var sb := UIKit.button(str(it[0]), func() -> void:
			Game.set_scroll_pans(on)
			show_menu(true), str(it[2]))
		sb.custom_minimum_size = Vector2(80, 34)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.disabled = Game.scroll_pans == on
		srow.add_child(sb)
	# the difficulty slider: changing it here changes the game being played
	right.add_child(UIKit.gap(4))
	right.add_child(_difficulty_box(true))
	right.add_child(UIKit.gap(4))
	right.add_child(UIKit.para("Screen mode, window size, 3D resolution, graphics preset and the size of the interface are under Display and graphics.", 12))
	modal.visible = true


## A setting shown as a value between two arrows, which a mouse, a pad
## pointer or the d-pad can all work. `names` are the choices as shown;
## `at` is the current index; `pick` is called with the new index.
func _chooser(parent: Control, title: String, names: Array[String], at: int, pick: Callable, tip: String = "") -> void:
	var row := UIKit.hbox(8)
	parent.add_child(row)
	var lbl := UIKit.label(title, 14)
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.tooltip_text = tip
	row.add_child(lbl)
	var left := UIKit.button("◀", func() -> void: pick.call(wrapi(at - 1, 0, names.size())))
	left.custom_minimum_size = Vector2(36, 32)
	row.add_child(left)
	var val := UIKit.label(names[clampi(at, 0, names.size() - 1)] if not names.is_empty() else "", 14, UIKit.GOLD)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.custom_minimum_size = Vector2(250, 0)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.tooltip_text = tip
	row.add_child(val)
	var right := UIKit.button("▶", func() -> void: pick.call(wrapi(at + 1, 0, names.size())))
	right.custom_minimum_size = Vector2(36, 32)
	row.add_child(right)


## Screen mode, window size, 3D resolution, graphics preset and interface
## size: the settings a player expects to find in any game.
func show_display() -> void:
	UIKit.clear(modal_card)
	modal_card.custom_minimum_size = Vector2(620, 0)
	modal_card.add_child(UIKit.label("Display and graphics", 26))
	var win := get_window()
	var screen := DisplayServer.screen_get_size(win.current_screen)
	var density := DisplayServer.screen_get_scale(win.current_screen)
	modal_card.add_child(UIKit.para("This display is %d by %d pixels%s." % [screen.x, screen.y, " at %.0fx density" % density if density > 1.05 else ""], 12))
	modal_card.add_child(UIKit.gap(6))
	# screen mode
	modal_card.add_child(UIKit.label("SCREEN", 12, UIKit.ACCENT))
	_chooser(modal_card, "Mode", ["Full screen", "Window"], 0 if Game.fullscreen else 1, func(i: int) -> void:
		Game.set_fullscreen(i == 0)
		show_display(), "Full screen owns the display, so frames go straight to it instead of through the desktop compositor. F11 switches too. Apple's overlay only shows Direct when the display runs at its default scaling, not a scaled resolution, and in the released build, which may cover the camera housing.")
	# window size
	var sizes := Game.window_sizes()
	var size_names: Array[String] = []
	var size_at := 0
	for i in sizes.size():
		var s := sizes[i]
		size_names.append("Fit the screen" if s == Vector2i.ZERO else "%d by %d" % [s.x, s.y])
		if s == Game.window_size:
			size_at = i
	_chooser(modal_card, "Window size", size_names, size_at, func(i: int) -> void:
		Game.set_window_size(sizes[i])
		show_display(), "The window's size in pixels when not in full screen. Full screen always uses the whole display." + (" (Not in use now: the game is full screen.)" if Game.fullscreen else ""))
	modal_card.add_child(UIKit.gap(8))
	# the 3D picture
	modal_card.add_child(UIKit.label("THE 3D PICTURE", 12, UIKit.ACCENT))
	var preset_lines: int = [810, 945, 1080, 1440][Game.quality]
	var line_choices: Array[int] = [0, 720, 900, 1080, 1440, 2160, -1]
	var line_names: Array[String] = []
	var line_at := 0
	for i in line_choices.size():
		var l := line_choices[i]
		if l == 0:
			line_names.append("Preset default (%d lines)" % preset_lines)
		elif l < 0:
			line_names.append("Native (%d lines)" % win.size.y)
		else:
			line_names.append("%d lines" % l)
		if l == Game.render_lines:
			line_at = i
	_chooser(modal_card, "3D resolution", line_names, line_at, func(i: int) -> void:
		Game.set_render_lines(line_choices[i])
		show_display(), "How many lines the 3D view is drawn at before being scaled to the window. Text and buttons are always drawn at full sharpness. More lines cost frame rate.")
	var presets: Array[String] = []
	for n in Game.QUALITY_NAMES:
		presets.append(n)
	_chooser(modal_card, "Graphics preset", presets, Game.quality, func(i: int) -> void:
		Game.set_quality(i)
		show_display(), "Low is for integrated graphics. High is the default. Ultra adds bounce light, the softest shadows and the sharpest picture.")
	var hold := CheckBox.new()
	hold.text = "Hold the frame rate: soften the picture when needed"
	hold.button_pressed = Game.hold_rate
	hold.focus_mode = Control.FOCUS_NONE
	hold.add_theme_font_size_override("font_size", 13)
	hold.tooltip_text = "When the frame rate drops, the 3D view is drawn a little less sharply until it recovers. Text and buttons always stay sharp."
	hold.toggled.connect(func(on: bool) -> void: Game.set_hold_rate(on))
	modal_card.add_child(hold)
	modal_card.add_child(UIKit.gap(8))
	# the interface
	modal_card.add_child(UIKit.label("THE INTERFACE", 12, UIKit.ACCENT))
	var ui_row := UIKit.hbox(8)
	modal_card.add_child(ui_row)
	var ui_lbl := UIKit.label("Interface size", 14)
	ui_lbl.custom_minimum_size = Vector2(170, 0)
	ui_row.add_child(ui_lbl)
	var ui_sl := HSlider.new()
	ui_sl.min_value = 80.0
	ui_sl.max_value = 110.0
	ui_sl.step = 5.0
	ui_sl.tick_count = 7
	ui_sl.ticks_on_borders = true
	ui_sl.value = roundf(Game.ui_scale * 100.0)
	ui_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui_sl.focus_mode = Control.FOCUS_NONE
	ui_row.add_child(ui_sl)
	var ui_val := UIKit.label("%d%%" % int(roundf(Game.ui_scale * 100.0)), 14, UIKit.GOLD)
	ui_val.custom_minimum_size = Vector2(56, 0)
	ui_row.add_child(ui_val)
	ui_sl.value_changed.connect(func(v: float) -> void:
		Game.set_ui_scale(v / 100.0)
		ui_val.text = "%d%%" % int(v))
	modal_card.add_child(UIKit.para("Text, buttons and panels, from 80% to 110% of their usual size. The panels are laid out for 100%, and the top bar is full at 110%.", 12))
	modal_card.add_child(UIKit.gap(10))
	var back := UIKit.button("Back", func() -> void: show_menu(true))
	back.custom_minimum_size = Vector2(0, 40)
	modal_card.add_child(back)
	modal.visible = true


## The difficulty slider with the level's name beside it and a line on what
## it does. `live` means a game is being played and should feel the change
## at once, with a word about what changed.
func _difficulty_box(live: bool) -> VBoxContainer:
	var levels: Array = Game.db.difficulty.get("levels", [])
	var box := UIKit.vbox(2)
	var row := UIKit.hbox(10)
	box.add_child(row)
	var lbl := UIKit.label("Difficulty", 14, UIKit.MUTED)
	lbl.custom_minimum_size = Vector2(70, 0)
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = float(maxi(levels.size() - 1, 1))
	sl.step = 1.0
	sl.tick_count = maxi(levels.size(), 2)
	sl.ticks_on_borders = true
	sl.value = float(Game.difficulty)
	sl.custom_minimum_size = Vector2(150, 0)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	sl.tooltip_text = "How generous the golfers are, how quickly they sour, how fast weeds and pests spread, and what staff cost."
	row.add_child(sl)
	var name := UIKit.label("", 14, UIKit.GOLD)
	name.custom_minimum_size = Vector2(62, 0)
	row.add_child(name)
	var blurb := UIKit.para("", 12)
	box.add_child(blurb)
	var show := func(v: int) -> void:
		var lv: Dictionary = levels[clampi(v, 0, levels.size() - 1)] if not levels.is_empty() else {}
		name.text = str(lv.get("name", "Normal"))
		blurb.text = str(lv.get("blurb", ""))
	show.call(Game.difficulty)
	sl.value_changed.connect(func(v: float) -> void:
		var was := Game.difficulty
		Game.set_difficulty(int(v))
		show.call(int(v))
		SoundDesk.ui("click")
		if live and sim != null and int(v) != was:
			show_toast("Difficulty: %s. %s" % [sim.difficulty_name(), sim.difficulty_blurb()], "info", 8.0))
	return box


## Every way to work the camera and the game, on one card.
func show_controls() -> void:
	UIKit.clear(modal_card)
	modal_card.custom_minimum_size = Vector2(640, 0)
	modal_card.add_child(UIKit.label("Controls", 26))
	var mac := OS.get_name() == "macOS"
	var alt_key := "Option" if mac else "Alt"
	var cmd_key := "Command" if mac else "the Windows key"
	var swipe_zoom := not Game.scroll_pans
	var groups := [
		["THE CAMERA", [
			["Move the map", "Drag the ground  ·  W A S D or arrow keys" + ("" if swipe_zoom else "  ·  swipe")],
			["Zoom", ("Scroll or swipe" if swipe_zoom else "Shift and swipe, or scroll a wheel") + "  ·  pinch  ·  + and -"],
			["Turn", ("Swipe sideways  ·  " if swipe_zoom else "") + "%s-drag  ·  Q and E  ·  right-drag" % alt_key],
			["Tilt", "%s-drag up and down  ·  T and G  ·  right-drag" % alt_key],
			["While a build tool is out", "Hold %s and drag to move the map" % cmd_key],
			["Follow a golfer", "Click them, then F or the Follow button"],
			["Usual angle", "Home, or the round button in the Camera bar"],
		]],
		["THE GAME", [
			["Pause", "Space"],
			["Speed", "1, 2, 3, 4"],
			["Build, Holes, Play a round", "B, H, P"],
			["Close a panel, put a tool away, menu", "Esc"],
			["Full screen", "F11  ·  Control-Command-F"],
		]],
		["PLAYING A ROUND", [
			["Aim", "A and D. Hold Shift for fine aim."],
			["Club, ball, shot shape", "W and S  ·  Tab  ·  Q and E"],
			["Swing", "Space or click, three times: start, power, accuracy"],
		]],
	]
	if Gamepad.pad != null:
		groups.append(["A CONTROLLER", Gamepad.pad.card_lines()])
	# mouse and keyboard on the left, a controller on the right
	var cols := UIKit.hbox(36)
	modal_card.add_child(cols)
	var col := UIKit.vbox(12)
	col.custom_minimum_size = Vector2(640, 0)
	cols.add_child(col)
	var name_w := 250.0
	for grp: Array in groups:
		var for_pad := str(grp[0]) == "A CONTROLLER"
		if for_pad:
			col = UIKit.vbox(12)
			col.custom_minimum_size = Vector2(590, 0)
			cols.add_child(col)
			name_w = 180.0
		col.add_child(UIKit.gap(4))
		col.add_child(UIKit.heading(str(grp[0])))
		if for_pad:
			var plugged := Gamepad.pad.pad_name()
			col.add_child(UIKit.para(plugged if plugged != "" else "None is plugged in. Xbox, PlayStation and Switch pads all work, and one can be plugged in at any time.", 13))
		for line: Array in grp[1]:
			var r := UIKit.hbox(12)
			var name := UIKit.label(str(line[0]), 14, UIKit.MUTED)
			name.custom_minimum_size = Vector2(name_w, 0)
			r.add_child(name)
			r.add_child(UIKit.para(str(line[1]), 14, UIKit.TEXT))
			col.add_child(r)
		if for_pad:
			var buzz := CheckBox.new()
			buzz.text = "Rumble when you strike the ball"
			buzz.button_pressed = Game.pad_rumble
			buzz.focus_mode = Control.FOCUS_NONE
			buzz.add_theme_font_size_override("font_size", 13)
			buzz.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			buzz.toggled.connect(func(on: bool) -> void: Game.set_pad_rumble(on))
			col.add_child(buzz)
	modal_card.add_child(UIKit.gap(6))
	modal_card.add_child(UIKit.para("Every camera move is also a button in the Camera bar at the bottom right of the screen. Hold a button to keep going.", 13))
	var back := UIKit.button("Back", func() -> void: show_menu(true))
	back.custom_minimum_size = Vector2(0, 38)
	modal_card.add_child(back)
	modal.visible = true


## The start screen: pick free play or a challenge.
func show_scenarios(first_launch: bool = false) -> void:
	UIKit.clear(modal_card)
	Game.paused = true
	modal_card.custom_minimum_size = Vector2(980, 0)
	var head := UIKit.hbox()
	modal_card.add_child(head)
	var tv := UIKit.vbox(0)
	head.add_child(tv)
	tv.add_child(UIKit.label(Defs.TITLE, 40))
	tv.add_child(UIKit.label("Build the course. Run the club. Play the round.", 15, UIKit.MUTED))
	head.add_child(UIKit.spacer())
	if Game.has_save():
		head.add_child(UIKit.button("Continue saved game", func() -> void:
			hide_modal()
			var ok: bool = await loading.run("Reading your course back", Game.load_game)
			if not ok:
				show_toast("The saved game could not be read.", "bad")
				show_scenarios(first_launch)))
	if not first_launch:
		head.add_child(UIKit.button("Back", func() -> void:
			hide_modal()
			Game.paused = false))
	# the difficulty the new game starts on
	var drow := UIKit.hbox(12)
	modal_card.add_child(drow)
	var dbox := _difficulty_box(false)
	dbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(dbox)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	# Three rows of cards are taller than the window at its usual size, so
	# the cards scroll rather than run off the bottom of the screen.
	var cards := ScrollContainer.new()
	cards.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var shown: Array[Dictionary] = []
	for scen: Dictionary in Game.db.scenarios:
		if not bool(scen.get("hidden", false)):
			shown.append(scen)
	var card_rows := ceili(shown.size() / 3.0)
	cards.custom_minimum_size = Vector2(0, minf(root.size.y - 250.0, card_rows * 276.0))
	modal_card.add_child(cards)
	cards.add_child(grid)
	var brought := Game.carried_money()
	for scen: Dictionary in shown:
		var card := UIKit.card(Color(1, 1, 1, 0.06))
		card.custom_minimum_size = Vector2(310, 236)
		grid.add_child(card)
		var v := UIKit.vbox(6)
		card.add_child(v)
		var free: bool = scen.get("mode", "free") == "free"
		var map_biome := Game.db.biome(str(scen.map.get("biome", "lush")))
		var tag := "FREE PLAY" if free else "CHALLENGE  ·  %s" % str(map_biome.name).to_upper()
		v.add_child(UIKit.label(tag, 11, UIKit.BLUE if free else UIKit.GOLD))
		v.add_child(UIKit.label(str(scen.name), 20))
		v.add_child(UIKit.para(str(scen.blurb), 13))
		var chosen := [str(scen.map.get("biome", "lush"))]
		if scen.get("pick_biome", false):
			# free play lets you choose the land
			v.add_child(UIKit.label("Choose your land", 12, UIKit.MUTED))
			var bgrid := GridContainer.new()
			bgrid.columns = 2
			bgrid.add_theme_constant_override("h_separation", 4)
			bgrid.add_theme_constant_override("v_separation", 4)
			v.add_child(bgrid)
			var bbtns: Array[Button] = []
			for b: Dictionary in Game.db.biomes:
				var bid := str(b.id)
				var bb := UIKit.button(str(b.name), Callable(), str(b.blurb))
				bb.toggle_mode = true
				bb.add_theme_font_size_override("font_size", 13)
				bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				bb.set_pressed_no_signal(bid == chosen[0])
				bb.pressed.connect(func() -> void:
					chosen[0] = bid
					for other in bbtns:
						other.set_pressed_no_signal(other == bb))
				bgrid.add_child(bb)
				bbtns.append(bb)
		for goal: Dictionary in scen.get("goals", []):
			v.add_child(UIKit.label("•  " + str(goal.text), 13, UIKit.TEXT))
		var dl: Dictionary = scen.get("deadline", {})
		if not dl.is_empty():
			v.add_child(UIKit.label("By the end of %s, Year %d" % [Defs.MONTH_NAMES[int(dl.month) - 1], int(dl.year)], 13, UIKit.WARN))
		var filler := Control.new()
		filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(filler)
		var foot := UIKit.hbox()
		v.add_child(foot)
		if brought > 0.5:
			foot.add_child(UIKit.label("Start with %s, plus %s from your last club" % [Defs.money(float(scen.money)), Defs.money(brought)], 13, UIKit.MUTED))
		else:
			foot.add_child(UIKit.label("Start with %s" % Defs.money(float(scen.money)), 13, UIKit.MUTED))
		foot.add_child(UIKit.spacer())
		var id := str(scen.id)
		foot.add_child(UIKit.button("Play", func() -> void:
			hide_modal()
			new_game_requested.emit(id, chosen[0])))
	modal.visible = true


# -------------------------------------------------------- person inspector

## Centre the camera on where a thought happened, and show the mood map.
func _show_thought(th: Dictionary) -> void:
	if rig == null or not th.has("pos"):
		return
	var at: Vector3 = th.pos
	rig.center_on(at, 45.0)
	set_overlay(4)


func inspect(who: Variant) -> void:
	_inspected = who
	inspector.visible = who != null
	_update_inspector(true)


func _update_inspector(force: bool = false) -> void:
	if _inspected == null:
		return
	# Rebuilding a button between press and release would swallow the click,
	# so leave the panel alone while the mouse is over it.
	if not force and inspector.get_global_rect().has_point(root.get_global_mouse_position()):
		return
	UIKit.clear(inspector_body)
	if _inspected is Golfer:
		var g: Golfer = _inspected
		if not sim.visitors.golfers.has(g):
			inspect(null)
			return
		var head := UIKit.hbox()
		inspector_body.add_child(head)
		var swatch := ColorRect.new()
		swatch.color = g.shirt
		swatch.custom_minimum_size = Vector2(10, 22)
		head.add_child(swatch)
		head.add_child(UIKit.label(g.name, 17))
		head.add_child(UIKit.spacer())
		head.add_child(UIKit.button("Follow", func() -> void:
			rig.follow = g
			rig.target_dist = minf(rig.target_dist, 45.0), "Keep the camera on this golfer (F)"))
		if g.kind == "public" and g.group != null and g.group.state != Group.S.LEAVING:
			head.add_child(UIKit.button("Eject", func() -> void:
				g.feel(-15.0, "I've been thrown off the course!")
				sim.visitors.quit(g), "Send this golfer home"))
		var who := "Handicap %d" % g.handicap()
		if g.kind == "celebrity":
			who = g.title.capitalize()
		elif g.kind == "pro":
			who = "Tournament professional"
		elif g.kind == "player":
			who = "That's you"
		if not g.member.is_empty():
			var mt := int(g.member.tier)
			who += "  ·  %s member" % sim.members.tier_name(mt)
		inspector_body.add_child(UIKit.label(who, 13, sim.members.tier_color(int(g.member.tier)) if not g.member.is_empty() else UIKit.MUTED))
		if not g.persona.is_empty():
			var pl := UIKit.para("%s: %s" % [str(g.persona.name), str(g.persona.blurb)], 12, UIKit.BLUE)
			pl.custom_minimum_size = Vector2(300, 0)
			inspector_body.add_child(pl)
		var mh := UIKit.hbox()
		inspector_body.add_child(mh)
		mh.add_child(UIKit.label(g.mood_word(), 14, UIKit.mood_color(g.satisfaction)))
		var b := UIKit.bar(g.satisfaction / 100.0, UIKit.mood_color(g.satisfaction))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mh.add_child(b)
		var hole_no := g.group.hole_i + 1 if g.group != null else 0
		inspector_body.add_child(UIKit.row("Round", "Hole %d  ·  %s through %d" % [hole_no, g.to_par_text(), g.scores.size()]))
		inspector_body.add_child(UIKit.row("Game", "length %d  ·  accuracy %d  ·  imagination %d" % [
			roundi(clampf(Members.power_share(g.power, sim.members.progress), 0.0, 1.0) * 100.0), int(g.accuracy * 100.0), int(g.imagination * 100.0)]))
		inspector_body.add_child(UIKit.row("Clubs and ball", "%s  ·  %s" % [str(g.brand_of("irons").get("name", "?")), str(g.ball.def.get("name", "?"))]))
		inspector_body.add_child(UIKit.row("Paid so far", Defs.money(g.paid) + ("  ·  riding a cart" if g.group != null and g.group.has_cart else "")))
		if g.group != null and not g.group.story.is_empty():
			var st: Dictionary = g.group.story
			inspector_body.add_child(UIKit.row("Out with %s" % str(st.who), "%s: %s" % [str(st.goal), "happy ending" if st.done else "%d%%" % int(float(st.progress) * 100.0)]))
		if g.kind != "player" and g.kind != "pro":
			var needs := UIKit.hbox(5)
			inspector_body.add_child(needs)
			for nd: Array in [["Thirst", g.thirst], ["Hunger", g.hunger], ["Restroom", g.bladder], ["Tired", g.fatigue]]:
				needs.add_child(UIKit.label(str(nd[0]), 10, UIKit.MUTED))
				var v := clampf(float(nd[1]), 0.0, 1.0)
				var nb := UIKit.bar(v, UIKit.GOOD.lerp(UIKit.BAD, smoothstep(0.4, 0.9, v)), 6)
				nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nb.custom_minimum_size = Vector2(26, 6)
				needs.add_child(nb)
		if not g.thoughts.is_empty():
			inspector_body.add_child(UIKit.heading("Thinking"))
			for i in range(g.thoughts.size() - 1, maxi(g.thoughts.size() - 5, -1), -1):
				var th: Dictionary = g.thoughts[i]
				var col := UIKit.TEXT
				if float(th.delta) > 0.0:
					col = UIKit.GOOD
				elif float(th.delta) < 0.0:
					col = UIKit.BAD
				var line := UIKit.button("\"%s\"" % str(th.text), _show_thought.bind(th), "Show where this was thought")
				line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				line.alignment = HORIZONTAL_ALIGNMENT_LEFT
				line.add_theme_font_size_override("font_size", 13)
				line.add_theme_color_override("font_color", col)
				line.add_theme_color_override("font_hover_color", col)
				line.custom_minimum_size = Vector2(300, 0)
				inspector_body.add_child(line)
	else:
		var m: Crew.Member = _inspected
		if not sim.crew.members.has(m):
			inspect(null)
			return
		var head := UIKit.hbox()
		inspector_body.add_child(head)
		head.add_child(UIKit.label(m.name, 17))
		head.add_child(UIKit.spacer())
		if m.level < 2:
			head.add_child(UIKit.button("Promote  %s" % Defs.money(float(m.role.wage) * 3.0), func() -> void:
				if not sim.crew.promote(m):
					show_toast("You can't afford that.", "bad")
				_update_inspector(true), "Senior staff work faster and better, for 60% more pay. A senior marshal walks furious golfers off before they blow up."))
		head.add_child(UIKit.button("Fire", func() -> void:
			if tools != null and tools.station_for == m:
				tools.station_for = null
			sim.crew.fire(m)
			world.selected = null
			inspect(null)))
		var post := UIKit.hbox()
		inspector_body.add_child(post)
		var posting := tools != null and tools.station_for == m
		post.add_child(UIKit.button("Cancel" if posting else "Station", func() -> void:
			if tools == null:
				return
			if tools.station_for == m:
				tools.station_for = null
				tools.tool_changed.emit()
			else:
				tools.arm_station(m)
			_update_inspector(true), "Click the ground. They work inside that circle and walk back when it is quiet."))
		if m.has_home:
			post.add_child(UIKit.button("Roam", func() -> void:
				sim.crew.clear_station(m)
				_update_inspector(true), "Let them work anywhere on the course again."))
		inspector_body.add_child(UIKit.label(("Senior " + str(m.role.name).to_lower()) if m.level > 1 else str(m.role.name), 13, UIKit.GOLD if m.level > 1 else UIKit.MUTED))
		if m.has_home:
			inspector_body.add_child(UIKit.row("Post", "within %d yd" % Defs.yards(sim.crew.home_radius())))
		var doing: String = ["Looking for work", "On the way to a job", "Working"][m.state]
		if m.hit_t > 0.0:
			doing = "Recovering from a golf ball"
		inspector_body.add_child(UIKit.row("Status", doing))
		inspector_body.add_child(UIKit.row("Jobs done", str(m.jobs_done)))
		inspector_body.add_child(UIKit.row("Wage", "%s a month" % Defs.money(float(m.role.wage) * (1.6 if m.level > 1 else 1.0))))


# ------------------------------------------------------------- per frame

func _frame_hud(delta: float) -> void:
	if sim == null:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.25
		_update_top()
		_update_inspector()
		_apply_contours()
		if _refresh.is_valid():
			_refresh.call()
	_update_ticker(delta)
	_update_play()
	var hint := ""
	if tools != null and tools.mode != "":
		hint = tools.hint()
		if tools.hover != null:
			hint += "\n" + _tile_info(tools.hover)
	hint_panel.visible = hint != "" and not (play != null and play.active())
	hint_label.text = hint
	if inspector.visible:
		# sits at the bottom right, shifted left when the side panel is open
		var ms := inspector.get_combined_minimum_size()
		inspector.size = ms
		inspector.position = Vector2(root.size.x - (490.0 if dock.visible else 10.0) - ms.x, root.size.y - 108.0 - ms.y)
	dial.angle = _screen_wind_angle()
	dial.strength = sim.weather.wind_speed


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame_hud(delta)
	Game.prof("hud", t0)


func _tile_info(p: Vector3) -> String:
	var c := sim.course
	var i := c.index_at(p.x, p.z)
	if i < 0:
		return ""
	var t: int = c.terrain[i]
	var s := "%s  ·  height %.1f m  ·  moisture %d%%" % [sim.terrain_name(t), p.y, int(c.wet[i] * 100.0)]
	if c.objects[i] != 0:
		s = sim.object_name(c.objects[i]) + "  ·  " + s
		if c.objects[i] == Defs.O.HOME_SITE:
			s = "Lot worth %s to a buyer  ·  " % Defs.money(sim.lot_value(i % c.w, i / c.w)) + s
	if c.locked[i] != 0:
		s += "  ·  not your land"
	elif c.hot[i] != 0:
		s += "  ·  too hot to build on"
	if Defs.T_GRASS[t]:
		s += "  ·  turf %d%%" % int(c.health[i] * 100.0)
		if c.weeds[i] > 0.05:
			s += "  ·  weeds %d%%" % int(c.weeds[i] * 100.0)
		if c.pests[i] > 0.05:
			s += "  ·  pests"
	return s


func _screen_wind_angle() -> float:
	var w := sim.weather.wind_dir
	var wv := Vector2(cos(w), sin(w))
	var right := Vector2(sin(rig.yaw), -cos(rig.yaw))
	var fwd := Vector2(-cos(rig.yaw), -sin(rig.yaw))
	return atan2(-wv.dot(fwd), wv.dot(right))


func _update_top() -> void:
	l_name.text = sim.course_name
	stars.value = sim.stars()
	l_rating.text = "%d" % int(sim.rating)
	l_date.text = Defs.month_text(sim.day())
	l_clock.text = sim.clock_text()
	sky_icon.dark = sim.darkness()
	l_money.text = Defs.money(sim.economy.money)
	l_money.add_theme_color_override("font_color", UIKit.GOOD if sim.economy.money >= 0.0 else UIKit.BAD)
	l_weather.text = "%s  %d°F" % [sim.weather.label(), sim.weather.temp_f()]
	l_wind.text = ("%d mph, gusting" if sim.weather.gust > 0.3 else "%d mph") % sim.weather.wind_mph()
	var n := sim.visitors.golfers.size()
	l_golfers.text = "%d golfer%s" % [n, "" if n == 1 else "s"]
	if not sim.open:
		l_golfers.text += " (closed)"
	var sat := sim.visitors.average_satisfaction()
	l_sat.text = "%d%% happy" % int(sat)
	l_sat.add_theme_color_override("font_color", UIKit.mood_color(sat))
	var active: int = 0 if Game.paused else int({1: 1, 2: 2, 4: 3, 8: 4}.get(Game.speed, 1))
	for i in speed_btns.size():
		speed_btns[i].set_pressed_no_signal(i == active)


func _update_ticker(delta: float) -> void:
	var w := ticker_clip.size.x
	if ticker_label.text == "":
		if _ticker_queue.is_empty():
			_ticker_idle += delta
			if _ticker_idle > 6.0 and not sim.feed.posts.is_empty():
				_ticker_idle = 0.0
				_ticker_queue.append(sim.feed.posts[randi() % sim.feed.posts.size()])
			return
		var p: Dictionary = _ticker_queue.pop_front()
		ticker_label.text = "@%s   %s" % [p.handle, p.text]
		var col := UIKit.TEXT
		if int(p.mood) > 0:
			col = UIKit.GOOD
		elif int(p.mood) < 0:
			col = UIKit.BAD
		ticker_label.add_theme_color_override("font_color", col)
		ticker_label.reset_size()
		_ticker_x = w
	var speed := 130.0 + 60.0 * _ticker_queue.size()
	_ticker_x -= delta * speed
	ticker_label.position = Vector2(_ticker_x, 1.0)
	if _ticker_x < -ticker_label.size.x - 40.0:
		ticker_label.text = ""
		_ticker_idle = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if sim == null or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if modal.visible:
		return
	if play != null and play.active():
		return
	match k.keycode:
		KEY_SPACE:
			Game.paused = not Game.paused
		KEY_1:
			_set_speed(1)
		KEY_2:
			_set_speed(2)
		KEY_3:
			_set_speed(3)
		KEY_4:
			_set_speed(4)
		KEY_B:
			open_dock("build")
		KEY_H:
			open_dock("holes")
		KEY_P:
			open_dock("play")
		KEY_F:
			if k.meta_pressed and k.ctrl_pressed:
				# Control-Command-F, the Mac's own full screen shortcut
				Game.set_fullscreen(not Game.fullscreen)
			elif world != null and world.selected != null:
				rig.follow = world.selected
				rig.target_dist = minf(rig.target_dist, 45.0)
		KEY_F11:
			Game.set_fullscreen(not Game.fullscreen)
		KEY_ESCAPE:
			if dock_name != "":
				close_dock()
			elif world != null and world.selected != null:
				world.selected = null
				inspect(null)
			else:
				show_menu()
		_:
			return
	get_viewport().set_input_as_handled()
