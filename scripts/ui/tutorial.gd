class_name Tutorial
extends Control
## The guided first round. A card near the top of the screen says what to
## do next and why, the toolbar button it needs pulses gold, and the step
## moves on by itself when the game shows it was done: a tee painted, a
## hole laid out, a golfer paid, a greenkeeper hired. Steps are data
## (data/tutorial.json); the conditions are checked here.

signal finished(completed: bool)

const COUNT_TEE := 3
const COUNT_GREEN := 8
const COUNT_FAIRWAY := 16

var hud: Node               # the HUD, for the dock, the toolbar buttons and the camera
var sim: Sim
var steps: Array = []
var index := -1
var running := false

var _card := PanelContainer.new()
var _title := UIKit.label("", 18, UIKit.GOLD)
var _text := UIKit.para("", 14, UIKit.TEXT)
var _where := UIKit.label("", 12, UIKit.MUTED)
var _ok: Button
var _skip: Button
var _stop: Button
var _glow := Control.new()
var _t := 0.0
var _parcels_at := 0
var _check_t := 0.0
var _ack := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	# the pulse round the button the step needs
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	# the card
	_card.custom_minimum_size = Vector2(560, 0)
	_card.add_theme_stylebox_override("panel", UIKit.box(Color(0.06, 0.09, 0.07, 0.94), 10, 18, 14, Color(1.0, 0.84, 0.3, 0.55)))
	add_child(_card)
	var v := UIKit.vbox(6)
	_card.add_child(v)
	var head := UIKit.hbox(10)
	v.add_child(head)
	head.add_child(_title)
	head.add_child(UIKit.spacer())
	head.add_child(_where)
	_text.custom_minimum_size = Vector2(520, 0)
	v.add_child(_text)
	var row := UIKit.hbox(8)
	v.add_child(row)
	row.add_child(UIKit.spacer())
	_stop = UIKit.button("End tutorial", func() -> void: stop(false), "Put the coach away. Menu, Tutorial brings it back.")
	_stop.add_theme_font_size_override("font_size", 12)
	row.add_child(_stop)
	_skip = UIKit.button("Skip this step", func() -> void: _advance(), "Move on without doing it.")
	_skip.add_theme_font_size_override("font_size", 12)
	row.add_child(_skip)
	_ok = UIKit.button("Got it", func() -> void: _ack = true)
	_ok.custom_minimum_size = Vector2(110, 34)
	row.add_child(_ok)


func bind(s: Sim) -> void:
	sim = s
	if running:
		stop(false)


func start() -> void:
	steps = Game.db.tutorial.get("steps", [])
	if steps.is_empty():
		return
	running = true
	visible = true
	index = -1
	_advance()


func stop(completed: bool) -> void:
	if not running:
		return
	running = false
	visible = false
	index = -1
	# remembered, except in test and screenshot runs
	if (completed or index >= 2) and not (Game.args.has("shot") or Game.args.has("exit")):
		Game.set_tutorial_done(true)
	finished.emit(completed)


func step() -> Dictionary:
	return steps[index] if index >= 0 and index < steps.size() else {}


func _advance() -> void:
	index += 1
	_ack = false
	if index >= steps.size():
		stop(true)
		return
	var st := step()
	_title.text = str(st.get("title", ""))
	_text.text = str(st.get("text", ""))
	_where.text = "%d of %d" % [index + 1, steps.size()]
	_ok.visible = str(st.get("done", "")) == "ack"
	_ok.text = "Finish" if index == steps.size() - 1 else "Got it"
	_skip.visible = bool(st.get("skip", false))
	_parcels_at = sim.course.owned_parcels() if sim != null else 0
	if str(st.get("camera", "")) == "clubhouse" and hud != null and hud.rig != null and sim != null:
		var c := sim.course.tile_center(sim.course.clubhouse.x, sim.course.clubhouse.y)
		hud.rig.center_on(c, 230.0)
	SoundDesk.ui("chime")
	_glow.queue_redraw()


## Is the current step's condition met?
func _met(st: Dictionary) -> bool:
	var key := str(st.get("done", ""))
	if sim == null:
		return false
	var c := sim.course
	match key:
		"ack":
			return _ack
		"build_open":
			return hud.dock_name == "build"
		"tee":
			return c.terrain.count(Defs.T.TEE) >= COUNT_TEE
		"green":
			return c.terrain.count(Defs.T.GREEN) >= COUNT_GREEN
		"fairway":
			return c.terrain.count(Defs.T.FAIRWAY) >= COUNT_FAIRWAY
		"hole":
			return not c.holes.is_empty()
		"paid":
			for h in c.holes:
				if h.payers > 0:
					return true
			return false
		"facility":
			for o: int in [Defs.O.DRINK_STAND, Defs.O.SNACK_BAR, Defs.O.RESTROOM, Defs.O.BENCH, Defs.O.BALL_WASHER, Defs.O.VENDING, Defs.O.BAR]:
				if c.objects.count(o) > 0:
					return true
			return false
		"staff":
			return not sim.crew.members.is_empty()
		"land":
			return c.owned_parcels() > _parcels_at
		"play":
			return hud.play != null and hud.play.active()
	return false


func _process(delta: float) -> void:
	if not running:
		return
	_t += delta
	_glow.queue_redraw()
	# top centre, clear of the toolbar on the left and the top bar above
	_card.position = Vector2(maxf((size.x - _card.size.x) * 0.5, 150.0), 104.0)
	# the coach stays out of the way of a round being played
	_card.visible = not (hud.play != null and hud.play.active() and str(step().get("done", "")) != "play")
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.2
	if _met(step()):
		_advance()


## A soft gold pulse round the toolbar button the step points at.
func _draw_glow() -> void:
	var st := step()
	var key := str(st.get("target", ""))
	if key == "" or hud == null:
		return
	var b: Control = hud._tool_buttons.get(key)
	if b == null or not b.is_visible_in_tree():
		return
	var r := b.get_global_rect()
	var pulse := 0.55 + 0.45 * sin(_t * 4.0)
	var grow := 4.0 + 3.0 * pulse
	var rr := Rect2(r.position - Vector2(grow, grow), r.size + Vector2(grow * 2.0, grow * 2.0))
	_glow.draw_rect(rr, Color(1.0, 0.84, 0.3, 0.25 + 0.5 * pulse), false, 3.0)
	_glow.draw_rect(Rect2(rr.position - Vector2(3, 3), rr.size + Vector2(6, 6)), Color(1.0, 0.84, 0.3, 0.12 * pulse), false, 6.0)
