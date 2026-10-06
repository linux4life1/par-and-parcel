class_name Gamepad
extends CanvasLayer
## Controller support. The left stick moves a pointer that works the
## interface exactly as a mouse does (it sends the same events), so every
## panel, menu and build tool works with no code of its own. The sticks,
## triggers and buttons with a plainer job (turn the view, zoom, go back,
## pause, swing) do it directly.
##
## Building and managing
##   left stick    the pointer; pushed against a screen edge it moves the map
##   A             click; hold to paint, sculpt or drag the map
##   B             back: put the tool away, close the panel, let go of a golfer
##   X             follow the golfer who is selected
##   Y             the usual camera angle
##   right stick   turn and tilt the view
##   triggers      zoom in (right) and out (left)
##   bumpers       step through the panels
##   d-pad         left and right change the speed, up and down scroll a list;
##                 in a menu it steps from button to button (scrolling to
##                 reach one), and left and right move a slider
##   Start, Select the menu, and pause
## Playing a round
##   left stick or d-pad aims, A swings (three presses), bumpers or d-pad up
##   and down change club, X shot shape, Y ball, B stops the power meter,
##   B twice leaves the round.
##
## Buttons are named by where they sit (Godot's JOY_BUTTON_A is the bottom
## face button on every make of pad); `label` gives the name printed on the
## pad that is plugged in.

const STICK_DEAD := 0.22         # slack round the centre of a stick that counts as nothing
const TRIGGER_DEAD := 0.08
const CURVE := 1.8               # above 1, a light push is slower and more exact
const POINTER_SPEED := 1150.0    # interface units a second with the stick right over
const MOUSE_ID := 30             # device number on the pointer events made here, to tell them from a real mouse
const REPEAT_WAIT := 0.38        # seconds a d-pad direction is held before it repeats
const REPEAT_EVERY := 0.11
const SCROLL_SPEED := 900.0
const SPEEDS: Array[int] = [0, 1, 2, 4, 8]    # game speeds in order; 0 is paused
const LABELS := {
	"xbox": {"a": "A", "b": "B", "x": "X", "y": "Y", "lb": "LB", "rb": "RB", "lt": "LT", "rt": "RT", "start": "Menu", "back": "View"},
	"sony": {"a": "Cross", "b": "Circle", "x": "Square", "y": "Triangle", "lb": "L1", "rb": "R1", "lt": "L2", "rt": "R2", "start": "Options", "back": "Create"},
	"nintendo": {"a": "B", "b": "A", "x": "Y", "y": "X", "lb": "L", "rb": "R", "lt": "ZL", "rt": "ZR", "start": "Plus", "back": "Minus"},
}

static var pad: Gamepad          # the one in the scene, for the interface to ask

var hud: Hud
var rig: CameraRig
var tools: BuildTools
var play: PlayMode
var world: WorldView
var active := false              # the controller was the last thing used, so its pointer shows
var device := -1                 # the pad last heard from
var pos := Vector2(-1.0, -1.0)   # the pointer, in interface units
var _axes := {}                  # axis -> latest reading from `device`
var _held := {}                  # button -> seconds until it next repeats
var _a_down := false             # A is being held as a mouse button
var _real_pos := Vector2.ZERO    # where the real mouse was last seen
var _real_moved := false
var _hid_mouse := false
var _leave_t := 0.0              # seconds left in which a second B leaves the round
var _last_state := 0
var _greeted := false
var _scroll_carry := 0.0
var _land_in := 0                # frames until the pointer jumps to a button that is still finding its place
var _land_on: Control = null     # that button; none means the first one in the open menu
var _land_dir := Vector2.ZERO
var _dot := Pointer.new()


## The pointer: an arrow with its tip at the node's position.
class Pointer extends Control:
	const SHAPE: Array[Vector2] = [Vector2(0, 0), Vector2(0, 17), Vector2(4, 13.2), Vector2(7, 20), Vector2(9.6, 18.9), Vector2(6.7, 12.2), Vector2(12, 12)]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pts := PackedVector2Array()
		var shade := PackedVector2Array()
		for p in SHAPE:
			pts.append(p * 1.3)
			shade.append(p * 1.3 + Vector2(1.5, 2.5))
		draw_colored_polygon(shade, Color(0, 0, 0, 0.3))
		draw_colored_polygon(pts, Color(1.0, 0.98, 0.9))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.05, 0.08, 0.06), 1.7, true)


func _ready() -> void:
	pad = self
	layer = 60
	_dot.visible = false
	add_child(_dot)
	Input.joy_connection_changed.connect(_on_plug)


func _exit_tree() -> void:
	if pad == self:
		pad = null


# ------------------------------------------------------ rules, as plain maths

## A stick reading with the slack round the centre taken out and a curve put
## on it, so a light push is slow and exact and a full push is fast.
static func shape(v: Vector2, dead: float = STICK_DEAD, curve: float = CURVE) -> Vector2:
	var m := v.length()
	if m <= dead:
		return Vector2.ZERO
	var k := minf((m - dead) / (1.0 - dead), 1.0)
	return v / m * pow(k, curve)


## Which of `rects` one d-pad step in direction `dir` (a unit step along one
## axis) from `from` lands on, or -1. Only rectangles lying wholly that way
## count; the nearest wins, and one in line beats one off to the side.
static func pick_toward(from: Vector2, dir: Vector2, rects: Array[Rect2]) -> int:
	var best := -1
	var least := INF
	for i in rects.size():
		var r := rects[i]
		var along := 0.0     # how far off its near edge is
		var across := 0.0    # how far to the side it sits
		if dir.x == 0.0:
			along = r.position.y - from.y if dir.y > 0.0 else from.y - r.end.y
			across = maxf(0.0, maxf(r.position.x - from.x, from.x - r.end.x))
		else:
			along = r.position.x - from.x if dir.x > 0.0 else from.x - r.end.x
			across = maxf(0.0, maxf(r.position.y - from.y, from.y - r.end.y))
		if along <= 0.0:
			continue
		var cost := along + across * 2.0
		if cost < least:
			least = cost
			best = i
	return best


## The place in SPEEDS one step faster (dir 1) or slower (dir -1).
static func speed_after(paused: bool, speed: int, dir: int) -> int:
	var now := 0 if paused else maxi(SPEEDS.find(speed), 1)
	return clampi(now + dir, 0, SPEEDS.size() - 1)


## Whose button names a pad uses, going by what it calls itself.
static func family(pad_name: String) -> String:
	var n := pad_name.to_lower()
	for word: String in ["ps3", "ps4", "ps5", "dualsense", "dualshock", "sony", "playstation"]:
		if n.contains(word):
			return "sony"
	for word: String in ["nintendo", "switch", "joy-con", "joycon"]:
		if n.contains(word):
			return "nintendo"
	return "xbox"


# ----------------------------------------------------------- what is plugged in

## True when a controller is plugged in or has been used.
func present() -> bool:
	return device >= 0 or not Input.get_connected_joypads().is_empty()


func pad_name() -> String:
	var d := device
	if d < 0 and not Input.get_connected_joypads().is_empty():
		d = Input.get_connected_joypads()[0]
	return Input.get_joy_name(d) if d >= 0 else ""


## The name printed on a button of the pad in use: a, b, x, y, lb, rb, lt,
## rt, start or back.
func label(button: String) -> String:
	var names: Dictionary = LABELS[family(pad_name())]
	return str(names.get(button, button))


## The Controls card's lines for a controller: [what, how] pairs.
func card_lines() -> Array:
	return [
		["Pointer and click", "The left stick moves a pointer. %s clicks. Hold %s to paint, sculpt or drag the map." % [label("a"), label("a")]],
		["Camera", "Right stick turns and tilts  ·  %s and %s zoom  ·  push the pointer against a screen edge to move the map  ·  %s for the usual angle" % [label("lt"), label("rt"), label("y")]],
		["Panels, and going back", "%s and %s step through the panels  ·  %s closes a panel, puts a tool away or goes back" % [label("lb"), label("rb"), label("b")]],
		["Speed, pause, menu", "D-pad left and right  ·  %s pauses  ·  %s opens the menu" % [label("back"), label("start")]],
		["Lists and menus", "D-pad up and down scrolls the list under the pointer. In a menu the d-pad steps from button to button, left and right move a slider, and the right stick scrolls."],
		["Follow a golfer", "Click them, then %s" % label("x")],
		["Playing a round", "Stick or d-pad aims  ·  %s swings  ·  %s and %s club  ·  %s shot shape  ·  %s ball  ·  %s stops the meter, twice leaves the round" % [label("a"), label("lb"), label("rb"), label("x"), label("y"), label("b")]],
	]


func _on_plug(dev: int, connected: bool) -> void:
	if hud == null:
		return
	if connected:
		_greeted = true
		var called := Input.get_joy_name(dev)
		hud.show_toast("%s connected. The left stick moves a pointer and %s clicks. Menu, then Controls, lists the rest." % [
			called if called != "" else "Controller", str((LABELS[family(called)] as Dictionary).a)], "info", 10.0)
	else:
		if dev == device:
			device = -1
			_axes.clear()
			_held.clear()
			_sleep()
		hud.show_toast("Controller disconnected.", "info")


## A short buzz, if the pad can and the player has not turned it off.
func rumble(weak: float, strong: float, seconds: float) -> void:
	if device < 0 or not Game.pad_rumble:
		return
	Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)


# ------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if hud == null or Game.sim == null:
		return
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		get_viewport().set_input_as_handled()
		if jm.device != device:
			# a second pad takes over once it is really being used
			if absf(jm.axis_value) < 0.5 or not _listening():
				return
			_adopt(jm.device)
		_axes[int(jm.axis)] = jm.axis_value
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		get_viewport().set_input_as_handled()
		var b := int(jb.button_index)
		if jb.pressed:
			if not _listening():
				return
			if jb.device != device:
				_adopt(jb.device)
			_wake()
			if not _held.has(b):
				_held[b] = REPEAT_WAIT
				_press(b, false)
		elif jb.device == device:
			_held.erase(b)
			if b == JOY_BUTTON_A and _a_down:
				_click(false)
	elif event is InputEventMouse and event.device != MOUSE_ID:
		# the real mouse: it takes the pointer back
		_real_pos = (event as InputEventMouse).position
		if event is InputEventMouseButton or (event as InputEventMouseMotion).relative.length_squared() > 0.0:
			_real_moved = true
			if active:
				_sleep()


## A pad keeps sending while the game is behind another window. It is only
## obeyed while the game is the window in front (scripted test runs excepted,
## since they must work on a screen the owner is using for something else).
func _listening() -> bool:
	return get_window().has_focus() or Game.args.has("demo")


func _adopt(dev: int) -> void:
	device = dev
	_axes.clear()
	_held.clear()


func _wake() -> void:
	if active:
		return
	active = true
	var size := _size()
	if _real_moved and Rect2(Vector2.ZERO, size).has_point(_real_pos):
		pos = _real_pos
	elif pos.x < 0.0:
		pos = size * 0.5
	_real_moved = false
	# scripted test runs leave the owner's own mouse pointer alone
	if not (Game.args.has("shot") or Game.args.has("exit")):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_hid_mouse = true
	_point(Vector2.ZERO)
	if not _greeted and hud != null:
		_greeted = true
		hud.show_toast("Controller ready. The left stick moves a pointer and %s clicks. Menu, then Controls, lists the rest." % label("a"), "info", 10.0)


func _sleep() -> void:
	if _a_down:
		_click(false)
	active = false
	_dot.visible = false
	if _hid_mouse:
		_hid_mouse = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _axis(axis: int) -> float:
	return float(_axes.get(axis, 0.0))


func _trigger(axis: int) -> float:
	var v := _axis(axis)
	return 0.0 if v < TRIGGER_DEAD else (v - TRIGGER_DEAD) / (1.0 - TRIGGER_DEAD)


func _size() -> Vector2:
	return get_viewport().get_visible_rect().size


## Window pixels per interface unit: raw input is in window pixels.
func _to_window() -> Vector2:
	return Vector2(get_window().size) / _size()


func _menu_open() -> bool:
	return hud.modal_open()


func _playing() -> bool:
	return play != null and play.active() and not hud.modal_open()


func _process(delta: float) -> void:
	if hud == null or rig == null or Game.sim == null:
		return
	var ls := shape(Vector2(_axis(JOY_AXIS_LEFT_X), _axis(JOY_AXIS_LEFT_Y)))
	var rs := shape(Vector2(_axis(JOY_AXIS_RIGHT_X), _axis(JOY_AXIS_RIGHT_Y)))
	var zoom := _trigger(JOY_AXIS_TRIGGER_RIGHT) - _trigger(JOY_AXIS_TRIGGER_LEFT)
	if not _listening():
		ls = Vector2.ZERO
		rs = Vector2.ZERO
		zoom = 0.0
		_held.clear()
		if _a_down:
			_click(false)
	if ls != Vector2.ZERO or rs != Vector2.ZERO or zoom != 0.0:
		_wake()
	var menu := _menu_open()
	var playing := _playing()
	# the camera: stick right turns the view right, stick up looks from higher
	rig.pad = Vector3.ZERO if menu else Vector3(-rs.x, -rs.y, zoom)
	rig.push = Vector2.ZERO
	# the round being played
	if play != null:
		var turn := 0.0
		if playing:
			turn = ls.x
			if _held.has(JOY_BUTTON_DPAD_LEFT):
				turn -= 0.25
			if _held.has(JOY_BUTTON_DPAD_RIGHT):
				turn += 0.25
		play.pad_turn = clampf(turn, -1.0, 1.0)
		if playing and not menu:
			# the right stick swings: pull back, push forward
			play.stick(rs.x, rs.y, delta)
		_watch_round(delta)
	# a d-pad direction held down
	for b: int in _held.keys():
		if b < JOY_BUTTON_DPAD_UP or b > JOY_BUTTON_DPAD_RIGHT:
			continue
		_held[b] = float(_held[b]) - delta
		if float(_held[b]) <= 0.0:
			_held[b] = REPEAT_EVERY
			_press(b, true)
	if not menu and not playing:
		var sy := 0.0
		if _held.has(JOY_BUTTON_DPAD_UP):
			sy -= 1.0
		if _held.has(JOY_BUTTON_DPAD_DOWN):
			sy += 1.0
		if sy != 0.0:
			var sc := _scroll_under(hud.root)
			if sc != null:
				_scroll_carry += sy * SCROLL_SPEED * delta
				var whole := int(_scroll_carry)
				_scroll_carry -= whole
				sc.scroll_vertical += whole
	# the pointer
	var moved := Vector2.ZERO
	if active and not playing and ls != Vector2.ZERO:
		var size := _size()
		var want := pos + ls * POINTER_SPEED * delta
		var kept := want.clamp(Vector2.ZERO, size - Vector2.ONE)
		if not menu:
			# pushed against an edge of the screen, it moves the map instead
			if want.x != kept.x:
				rig.push.x = ls.x
			if want.y != kept.y:
				rig.push.y = -ls.y
		moved = kept - pos
		pos = kept
	if menu and rs.y != 0.0:
		# with the game's view out of reach behind a menu, the right stick scrolls
		var list := _scroll_under(hud.modal)
		if list != null:
			_scroll_carry += rs.y * SCROLL_SPEED * delta
			var rows := int(_scroll_carry)
			_scroll_carry -= rows
			list.scroll_vertical += rows
	if _land_in > 0:
		_land_in -= 1
		if _land_in == 0 and menu:
			var on := _land_on
			_land_on = null
			if on == null:
				var first := _targets(hud.modal_card)
				if not first.is_empty():
					on = first[0]
			if is_instance_valid(on) and on.is_visible_in_tree():
				moved += _land(on, _land_dir)
	if active and not playing:
		# Tell the interface where the pointer is. While the view is moving
		# under a still pointer, keep telling it, so a brush keeps painting.
		var view_moving := rig.pad != Vector3.ZERO or rig.push != Vector2.ZERO or absf(rig.dist - rig.target_dist) > rig.dist * 0.002
		if moved != Vector2.ZERO or (view_moving and (_a_down or tools.mode != "")):
			_point(moved)
	_dot.visible = active and not playing
	_dot.position = pos


## Keep an eye on the player's round: buzz on the strike, time out the
## leave-the-round warning, and show the pad's buttons in the hints.
func _watch_round(delta: float) -> void:
	_leave_t = maxf(0.0, _leave_t - delta)
	var st := play.state
	if st != _last_state:
		if st == PlayMode.S.FLIGHT and _last_state == PlayMode.S.SWING:
			if play.putting:
				rumble(0.25, 0.0, 0.07)
			elif play.g != null and play.g.mishit:
				rumble(0.7, 0.5, 0.3)
			else:
				rumble(0.45 + play.power * 0.35, 0.2 + play.power * 0.6, 0.15)
		_last_state = st
	if not active or not play.active():
		return
	match st:
		PlayMode.S.AIM:
			hud.play_keys.text = "Left stick aims   ·   %s / %s club   ·   %s shape   ·   %s ball   ·   %s swing, or pull the right stick back and push it forward   ·   %s twice to leave" % [
				label("lb"), label("rb"), label("x"), label("y"), label("a"), label("b")]
		PlayMode.S.POWER:
			if play.stick_phase == 1:
				hud.play_keys.text = "Hold the stick back for more power, then push it straight forward to hit."
			else:
				hud.play_keys.text = "%s to set the power. The gold line reaches the pin; past the 100 mark is an overswing. %s stops the marker." % [label("a"), label("b")]
		PlayMode.S.ACCURACY:
			if play.stick_phase == 2:
				hud.play_keys.text = "Push the stick straight forward. Off to one side bends the shot."
			else:
				hud.play_keys.text = "%s as the marker comes back to the line. Early hooks, late slices." % label("a")


# ------------------------------------------------------------- the pointer

## Send the pointer's place to the interface as mouse movement.
func _point(rel: Vector2) -> void:
	var k := _to_window()
	var mm := InputEventMouseMotion.new()
	mm.device = MOUSE_ID
	mm.position = pos * k
	mm.global_position = pos * k
	mm.relative = rel * k
	if _a_down:
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mm)


## Press or let go of the left mouse button where the pointer is.
func _click(down: bool) -> void:
	_a_down = down
	var k := _to_window()
	var mb := InputEventMouseButton.new()
	mb.device = MOUSE_ID
	mb.position = pos * k
	mb.global_position = pos * k
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	if down:
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mb)


## Buttons and sliders that can be used right now, in reading order.
func _targets(under: Node) -> Array[Control]:
	var found: Array[Control] = []
	var stack: Array[Node] = [under]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c := n as Control
			if not c.is_visible_in_tree() or c.is_queued_for_deletion():
				continue
			if (c is BaseButton and not (c as BaseButton).disabled) or (c is Slider and (c as Slider).editable):
				found.append(c)
		for ch in n.get_children():
			stack.append(ch)
	found.sort_custom(func(a: Control, b: Control) -> bool:
		var pa := a.global_position
		var pb := b.global_position
		return pa.y < pb.y - 5.0 or (absf(pa.y - pb.y) <= 5.0 and pa.x < pb.x))
	return found


## Put the pointer on a button or slider. Returns how far it moved.
func _land(c: Control, dir: Vector2) -> Vector2:
	var r := c.get_global_rect()
	var to := r.get_center()
	# to the right of the middle, so the arrow does not sit on the label
	to.x += minf(r.size.x * 0.25, 110.0)
	if c is Slider:
		# on the handle, so that a click there changes nothing
		to.x = lerpf(r.position.x + 8.0, r.end.x - 8.0, (c as Slider).ratio)
	elif dir.y != 0.0 and r.size.x > 40.0:
		to.x = clampf(pos.x, r.position.x + 14.0, r.end.x - 14.0)
	elif dir.x != 0.0 and r.size.y > 20.0:
		to.y = clampf(pos.y, r.position.y + 6.0, r.end.y - 6.0)
	var rel := to - pos
	pos = to
	return rel


## One d-pad step in a menu: on to the next button that way.
func _snap(dir: Vector2) -> void:
	var list: Array[Control] = []
	var rects: Array[Rect2] = []
	var screen := Rect2(Vector2.ZERO, _size())
	for c in _targets(hud.modal_card):
		var r := c.get_global_rect()
		# one that is off the screen only counts if its list can scroll to it
		if screen.has_point(r.get_center()) or _scroller_of(c) != null:
			list.append(c)
			rects.append(r)
	if list.is_empty():
		return
	var i := pick_toward(pos, dir, rects)
	if i < 0:
		# nothing that way. If the pointer is not on a button yet, take the nearest.
		var nearest := INF
		for k in rects.size():
			if rects[k].has_point(pos):
				return
			var d := rects[k].get_center().distance_to(pos)
			if d < nearest:
				nearest = d
				i = k
	var sc := _scroller_of(list[i])
	if sc != null and not sc.get_global_rect().encloses(rects[i]):
		# scroll it into view first, and land on it once it has moved
		sc.ensure_control_visible(list[i])
		_land_on = list[i]
		_land_dir = dir
		_land_in = 2
		return
	_point(_land(list[i], dir))


## The scrolling list a control sits in, if it sits in one.
func _scroller_of(c: Control) -> ScrollContainer:
	var n: Node = c.get_parent()
	while n != null and n != hud.root:
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null


func _slider_under() -> Slider:
	for c in _targets(hud.root):
		if c is Slider and c.get_global_rect().grow(6.0).has_point(pos):
			return c as Slider
	return null


## The list the pointer is over, or the side panel's if it is over none.
func _scroll_under(under: Node) -> ScrollContainer:
	var best: ScrollContainer = null
	var stack: Array[Node] = [under]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and not (n as Control).is_visible_in_tree():
			continue
		if n is ScrollContainer and (n as ScrollContainer).get_global_rect().has_point(pos):
			best = n as ScrollContainer
		for ch in n.get_children():
			stack.append(ch)
	if best == null and under == hud.root and hud.dock.visible:
		best = hud.dock_body.get_parent() as ScrollContainer
	return best


## Press the first button in the open dialog that carries one of these labels.
func _press_named(names: Array) -> bool:
	var list := _targets(hud.modal_card)
	for want: String in names:
		for c in list:
			if c is Button and (c as Button).text == want:
				(c as Button).pressed.emit()
				return true
	return false


# ------------------------------------------------------------- the buttons

func _press(b: int, again: bool) -> void:
	var menu := _menu_open()
	var playing := _playing()
	match b:
		JOY_BUTTON_A:
			if playing:
				play.press()
			else:
				_point(Vector2.ZERO)
				_click(true)
		JOY_BUTTON_B:
			_back(menu, playing)
		JOY_BUTTON_X:
			if playing:
				play.cycle_shape(1)
			elif not menu and world != null and world.selected != null:
				rig.follow = world.selected
				rig.target_dist = minf(rig.target_dist, 45.0)
		JOY_BUTTON_Y:
			if playing:
				play.cycle_ball()
			elif not menu and not rig.locked:
				rig.reset_view()
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			var step := -1 if b == JOY_BUTTON_LEFT_SHOULDER else 1
			if playing:
				play.change_club(step)
			elif not menu:
				hud.step_dock(step)
		JOY_BUTTON_DPAD_UP:
			_dpad(Vector2(0.0, -1.0), menu, playing, again)
		JOY_BUTTON_DPAD_DOWN:
			_dpad(Vector2(0.0, 1.0), menu, playing, again)
		JOY_BUTTON_DPAD_LEFT:
			_dpad(Vector2(-1.0, 0.0), menu, playing, again)
		JOY_BUTTON_DPAD_RIGHT:
			_dpad(Vector2(1.0, 0.0), menu, playing, again)
		JOY_BUTTON_START:
			if menu:
				_press_named(["Resume"])
			else:
				hud.show_menu()
				# the new buttons have a place on screen two frames from now
				_land_on = null
				_land_dir = Vector2.ZERO
				_land_in = 2
		JOY_BUTTON_BACK:
			if not menu and not playing:
				Game.paused = not Game.paused


func _dpad(dir: Vector2, menu: bool, playing: bool, again: bool) -> void:
	if playing:
		# left and right aim, in _process
		if dir.y != 0.0 and not again:
			play.change_club(int(dir.y))
		return
	if dir.x != 0.0:
		var sl := _slider_under()
		if sl != null:
			var step := sl.step if sl.step > 0.0 else (sl.max_value - sl.min_value) / 20.0
			sl.value += step * dir.x
			_point(_land(sl, Vector2.ZERO))
			return
	if menu:
		_snap(dir)
	elif dir.x != 0.0 and not again:
		var next := speed_after(Game.paused, Game.speed, int(dir.x))
		Game.paused = next == 0
		if next > 0:
			Game.speed = SPEEDS[next]
	# up and down scroll a list, in _process


func _back(menu: bool, playing: bool) -> void:
	if menu:
		if not _press_named(["Back", "Resume"]):
			# a notice with one button: B acknowledges it
			var only: Array[Control] = []
			for c in _targets(hud.modal_card):
				if c is Button:
					only.append(c)
			if only.size() == 1:
				(only[0] as Button).pressed.emit()
		return
	if playing:
		if play.cancel_swing():
			return
		if _leave_t > 0.0:
			_leave_t = 0.0
			play.stop()
		else:
			_leave_t = 3.0
			play.message = "Press %s again to leave the round." % label("b")
			play.changed.emit()
		return
	if tools.mode != "":
		tools.set_mode("")
	elif hud.dock_name != "":
		hud.close_dock()
	elif world != null and world.selected != null:
		world.selected = null
		hud.inspect(null)
