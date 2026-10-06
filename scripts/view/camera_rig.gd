class_name CameraRig
extends Node3D
## An orbiting camera that looks at a point on the ground. Zoomed out it sees
## the whole property from above; zoomed in it drops down beside the golfers.
##
## Every move can be made with a one-button mouse, a trackpad, the keyboard
## or the buttons on screen:
##   move   drag the ground, W A S D, arrow keys, middle-drag
##   zoom   scroll or swipe, pinch, + and -
##   turn   swipe sideways, Q and E, Option-drag, right-drag
##   tilt   Option-drag or right-drag up and down, T and G
## A build tool takes over the plain drag; hold Command to move the map then.

const MIN_DIST := 9.0
const MAX_DIST := 1300.0

var cam := Camera3D.new()
var course: Course
var focus := Vector3.ZERO
var yaw := PI * 0.5
var dist := 430.0
var target_dist := 430.0
var follow: Variant = null     # any object with `pos` and `prev`
var locked := false            # play mode takes over the camera
var pitch_override := -1.0
var v_shift := 0.0              # push the view up the screen, as a share of distance
var tilt := 0.0                 # degrees the player has tipped the view away from its usual angle
var tool_active := false        # a build tool owns the plain left-drag
var nudge := Vector3.ZERO       # held on-screen buttons: x turn, y tilt, z zoom, each -1 to 1
var pad := Vector3.ZERO         # a controller's right stick and triggers: x turn, y tilt, z zoom, each -1 to 1
var push := Vector2.ZERO        # a controller pushing the map along: x right, y forward, each -1 to 1
var dragged := false            # the last left press became a drag, so it was not a click
var _grab := ""                 # what a held mouse button is doing: "", "pan" or "orbit"
var _grab_button := 0
var _grab_travel := 0.0
var _gesture_frame := -1
var _gesture_what := Vector3.ZERO
var _gesture_at := Vector2.ZERO
var _gesture_open := false
var _shake := 0.0

const CLICK_SLOP := 6.0         # pixels a press may wander and still count as a click
const PITCH_MIN := 8.0
const PITCH_MAX := 86.0


func _ready() -> void:
	add_child(cam)
	cam.fov = 38.0
	cam.near = 0.4
	cam.far = 6000.0
	cam.current = true


func bind(c: Course) -> void:
	course = c
	follow = null
	var size := c.size_m()
	focus = c.on_ground(size.x * 0.5, size.y * 0.58)
	target_dist = maxf(size.x, size.y) * 1.12
	dist = target_dist
	yaw = PI * 0.5
	tilt = 0.0
	_grab = ""


## Rattle the camera, 0 to 1. Used for eruptions.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func center_on(p: Vector3, distance: float = -1.0) -> void:
	follow = null
	focus = p
	if distance > 0.0:
		target_dist = distance


func zoom_level() -> float:
	return clampf(inverse_lerp(log(MIN_DIST), log(MAX_DIST), log(dist)), 0.0, 1.0)


## The angle the camera looks down at when left alone: low beside the
## golfers, high over the whole property. Degrees.
func usual_pitch() -> float:
	return lerpf(13.0, 58.0, smoothstep(0.0, 0.7, zoom_level()))


## Tip the view: positive looks from higher up, negative from lower down.
func tilt_by(degrees: float) -> void:
	var usual := usual_pitch()
	tilt = clampf(tilt + degrees, PITCH_MIN - usual, PITCH_MAX - usual)


## Back to the usual angle, facing the way the course was first shown.
func reset_view() -> void:
	tilt = 0.0
	yaw = PI * 0.5


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _process(delta: float) -> void:
	if course == null:
		return
	if not locked and not _typing():
		var mv := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			mv.y += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			mv.y -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			mv.x += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			mv.x -= 1.0
		if mv != Vector2.ZERO:
			follow = null
			_pan(mv.normalized() * dist * 0.9 * delta)
		if Input.is_key_pressed(KEY_Q):
			yaw += 1.6 * delta
		if Input.is_key_pressed(KEY_E):
			yaw -= 1.6 * delta
		if Input.is_key_pressed(KEY_T) or Input.is_key_pressed(KEY_PAGEUP):
			tilt_by(42.0 * delta)
		if Input.is_key_pressed(KEY_G) or Input.is_key_pressed(KEY_PAGEDOWN):
			tilt_by(-42.0 * delta)
	# buttons held on screen
	if nudge != Vector3.ZERO:
		if not locked:
			yaw += nudge.x * 1.6 * delta
			tilt_by(nudge.y * 42.0 * delta)
		if nudge.z > 0.0:
			target_dist *= pow(0.3, delta)
		elif nudge.z < 0.0:
			target_dist *= pow(3.3, delta)
	if not _typing():
		if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
			target_dist *= pow(0.3, delta)
		if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
			target_dist *= pow(3.3, delta)
	# a controller (see Gamepad): the same moves, by as much as the stick is pushed
	if pad != Vector3.ZERO or push != Vector2.ZERO:
		if not locked:
			yaw += pad.x * 2.0 * delta
			tilt_by(pad.y * 48.0 * delta)
			if push != Vector2.ZERO:
				follow = null
				_pan(push * dist * 0.9 * delta)
		if pad.z > 0.0:
			target_dist *= pow(0.3, pad.z * delta)
		elif pad.z < 0.0:
			target_dist *= pow(3.3, -pad.z * delta)
	target_dist = clampf(target_dist, MIN_DIST, MAX_DIST)
	dist = lerpf(dist, target_dist, 1.0 - exp(-delta * 9.0))
	if follow != null:
		var p: Vector3 = follow.prev.lerp(follow.pos, Game.alpha)
		focus = focus.lerp(p, 1.0 - exp(-delta * 8.0))
	else:
		var size := course.size_m()
		focus.x = clampf(focus.x, 0.0, size.x)
		focus.z = clampf(focus.z, 0.0, size.y)
		focus.y = lerpf(focus.y, course.height_at(focus.x, focus.z), 1.0 - exp(-delta * 6.0))
	var t := zoom_level()
	var pitch := deg_to_rad(clampf(usual_pitch() + tilt, PITCH_MIN, PITCH_MAX))
	if pitch_override >= 0.0:
		pitch = pitch_override
	var off := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)) * dist
	var look := focus + Vector3(0.0, lerpf(1.6, 0.0, t), 0.0)
	var cp := look + off
	cp.y = maxf(cp.y, course.height_at(cp.x, cp.z) + 1.2)
	if _shake > 0.001:
		var amp := _shake * dist * 0.012
		cp += Vector3(randf_range(-amp, amp), randf_range(-amp, amp) * 0.6, randf_range(-amp, amp))
		_shake = maxf(0.0, _shake - delta * 1.6)
	cam.global_position = cp
	cam.look_at(look, Vector3.UP)
	cam.v_offset = -dist * v_shift


func _pan(v: Vector2) -> void:
	var right := Vector3(sin(yaw), 0.0, -cos(yaw))
	var fwd := Vector3(-cos(yaw), 0.0, -sin(yaw))
	focus += right * v.x + fwd * v.y


## Where a point on the screen meets the ground at the height being looked
## at, or null when it points at the sky.
func _ground_under(px: Vector2) -> Variant:
	var from := cam.project_ray_origin(px)
	var dir := cam.project_ray_normal(px)
	if dir.y > -0.03:
		return null
	var along := (focus.y - from.y) / dir.y
	if along < 0.0 or along > dist * 9.0:
		return null
	return from + dir * along


## Drag the map: the ground that was under the pointer stays under it.
func _drag_map(from_px: Vector2, to_px: Vector2) -> void:
	follow = null
	var a: Variant = _ground_under(from_px)
	var b: Variant = _ground_under(to_px)
	if a == null or b == null:
		var rel := to_px - from_px
		_pan(Vector2(-rel.x, rel.y) * dist * 0.0012)
		return
	var move: Vector3 = (a as Vector3) - (b as Vector3)
	move.y = 0.0
	focus += move.limit_length(dist * 0.6)


## Godot hands every swipe and pinch gesture to the game twice in a row.
## This lets the first of each pair through and drops its echo.
func _fresh_gesture(what: Vector3, at: Vector2) -> bool:
	var frame := Engine.get_process_frames()
	if _gesture_open and frame == _gesture_frame and what == _gesture_what and at == _gesture_at:
		_gesture_open = false
		return false
	_gesture_frame = frame
	_gesture_what = what
	_gesture_at = at
	_gesture_open = true
	return true


func _begin_grab(kind: String, button: int) -> void:
	_grab = kind
	_grab_button = button
	_grab_travel = 0.0


## While a button is held the drag is followed here rather than in
## _unhandled_input, so it carries on over the panels and always ends.
func _input(event: InputEvent) -> void:
	if _grab == "":
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_grab_travel += mm.relative.length()
		if _grab_button == MOUSE_BUTTON_LEFT:
			# a press that barely moves is a click, and belongs to someone else
			if _grab_travel < CLICK_SLOP:
				return
			dragged = true
		if locked:
			return
		if _grab == "pan":
			_drag_map(mm.position - mm.relative, mm.position)
		else:
			yaw += mm.relative.x * 0.006
			tilt_by(mm.relative.y * 0.22)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed and mb.button_index == _grab_button:
			_grab = ""


func _unhandled_input(event: InputEvent) -> void:
	if course == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				target_dist *= 0.88
			MOUSE_BUTTON_WHEEL_DOWN:
				target_dist *= 1.136
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_begin_grab("pan", MOUSE_BUTTON_MIDDLE)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_begin_grab("orbit", MOUSE_BUTTON_RIGHT)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					dragged = false
					if mb.alt_pressed:
						_begin_grab("orbit", MOUSE_BUTTON_LEFT)
					elif mb.meta_pressed or not tool_active:
						_begin_grab("pan", MOUSE_BUTTON_LEFT)
	elif event is InputEventPanGesture:
		# a swipe on a Magic Mouse, or two fingers on a trackpad
		var d := (event as InputEventPanGesture).delta
		if not _fresh_gesture(Vector3(d.x, d.y, 0.0), (event as InputEventPanGesture).position):
			return
		var moves_map := Game.scroll_pans != Input.is_key_pressed(KEY_SHIFT)
		if Input.is_key_pressed(KEY_ALT):
			if not locked:
				yaw += d.x * 0.012
				tilt_by(d.y * 0.6)
		elif moves_map:
			if not locked:
				follow = null
				_pan(Vector2(d.x, -d.y) * dist * 0.004)
		elif absf(d.x) > absf(d.y) * 1.8:
			# a sideways swipe turns the view
			if not locked:
				yaw += d.x * 0.012
		else:
			target_dist *= exp(d.y * 0.04)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if _fresh_gesture(Vector3(0.0, 0.0, mg.factor), mg.position):
			target_dist /= mg.factor
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_HOME and not locked and not _typing():
			reset_view()
