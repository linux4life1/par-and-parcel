class_name UIKit
extends RefCounted
## Colours, the theme, and small helpers for building the interface in code.

const BG := Color(0.07, 0.10, 0.09, 0.94)
const BG_SOFT := Color(0.13, 0.17, 0.15, 1.0)
const BG_ROW := Color(1.0, 1.0, 1.0, 0.045)
const ACCENT := Color(0.36, 0.78, 0.45)
const TEXT := Color(0.93, 0.96, 0.93)
const MUTED := Color(0.62, 0.70, 0.65)
const GOOD := Color(0.48, 0.88, 0.55)
const BAD := Color(0.97, 0.45, 0.40)
const WARN := Color(1.0, 0.78, 0.32)
const GOLD := Color(1.0, 0.84, 0.3)
const BLUE := Color(0.45, 0.72, 1.0)


static func box(color: Color, radius: int = 8, pad_h: int = 10, pad_v: int = 8, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	sb.anti_aliasing = true
	return sb


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(BG, 10, 12, 10, Color(1, 1, 1, 0.08)))
	t.set_stylebox("normal", "Button", box(Color(0.17, 0.22, 0.19), 6, 12, 6, Color(1, 1, 1, 0.07)))
	t.set_stylebox("hover", "Button", box(Color(0.23, 0.30, 0.26), 6, 12, 6, Color(1, 1, 1, 0.14)))
	t.set_stylebox("pressed", "Button", box(Color(0.20, 0.46, 0.28), 6, 12, 6, Color(0.5, 0.9, 0.6, 0.5)))
	t.set_stylebox("disabled", "Button", box(Color(0.12, 0.14, 0.13), 6, 12, 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.5, 0.47))
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.4), 5, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 5, 0, 0))
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.35), 5, 8, 4, Color(1, 1, 1, 0.1)))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.45), 5, 8, 4, Color(0.5, 0.9, 0.6, 0.5)))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.03, 0.05, 0.04, 0.97), 6, 10, 6, Color(1, 1, 1, 0.15)))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 6)
	return t


static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A label that wraps, for body text inside the side panel.
static func para(text: String, size: int = 14, color: Color = MUTED) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func heading(text: String) -> Label:
	var l := label(text.to_upper(), 12, ACCENT)
	return l


static func button(text: String, on_press: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	# callers that wire the button up themselves pass an empty Callable
	if on_press.is_valid():
		b.pressed.connect(on_press)
	b.pressed.connect(func() -> void: SoundDesk.ui("click"))
	return b


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A rounded card to group a few rows.
static func card(color: Color = BG_ROW) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, 8, 10, 8))
	return p


static func bar(value: float, color: Color = ACCENT, height: int = 8) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(60, height)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("fill", box(color, 4, 0, 0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Two labels on one row: a name on the left, a value on the right.
static func row(name: String, value: String, value_color: Color = TEXT) -> HBoxContainer:
	var h := hbox()
	h.add_child(label(name, 14, MUTED))
	h.add_child(spacer())
	var v := label(value, 14, value_color)
	v.name = "Value"
	h.add_child(v)
	return h


static func mood_color(v: float) -> Color:
	if v >= 62.0:
		return GOOD
	if v >= 42.0:
		return WARN
	return BAD


class StarBar:
	extends Control
	## Five stars, filled in proportion to a 0..5 value.
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(92, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in 5:
			var c := Vector2(9 + i * 18.5, size.y * 0.5)
			var fill := clampf(value - i, 0.0, 1.0)
			draw_colored_polygon(_star(c, 8.0), Color(1, 1, 1, 0.16))
			if fill > 0.99:
				draw_colored_polygon(_star(c, 8.0), UIKit.GOLD)
			elif fill > 0.2:
				draw_colored_polygon(_star(c, 8.0 * (0.45 + 0.55 * fill)), UIKit.GOLD)

	func _star(c: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0
			var rr := r if k % 2 == 0 else r * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		return pts


class WindDial:
	extends Control
	## An arrow showing where the wind is blowing, relative to the screen.
	var angle := 0.0:
		set(v):
			angle = v
			queue_redraw()
	var strength := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(30, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 14.0, Color(0, 0, 0, 0.35))
		draw_arc(c, 14.0, 0.0, TAU, 32, Color(1, 1, 1, 0.25), 1.0, true)
		var d := Vector2(cos(angle), sin(angle))
		var n := Vector2(-d.y, d.x)
		var col := UIKit.BLUE.lerp(UIKit.BAD, clampf(strength / 14.0, 0.0, 1.0))
		var tip := c + d * 11.0
		var tail := c - d * 9.0
		draw_line(tail, tip - d * 4.0, col, 2.5, true)
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 8.0 + n * 5.0, tip - d * 8.0 - n * 5.0]), col)


class Meter:
	extends Control
	## The three-click swing meter: one bar. The line near the left end is
	## where the swing starts and must be stopped; the marker runs up to the
	## right (full power at the white 100 mark, an overswing in the red
	## beyond it) and comes straight back. Green and amber bands round the
	## line show the flush and the forgivable timing.
	const LOW := -0.1          # bar units drawn left of the line
	const HIGH := 1.12         # and the right end
	var marker := 0.0          # where the marker is, in bar units (1 is full power)
	var target := -1.0         # the power that reaches the pin, gold
	var locked := -1.0         # the power set by the second press
	var running := false       # the marker is on the move
	var result := 0.0          # -1 early .. 1 late, shown once the swing is struck
	var show_result := false
	var zone := 0.17           # bar units either side of the line: amber band
	var good := 0.06           # the band that still flies straight: pale green
	var perfect := 0.02        # and the flush window: bright green
	var over := 1.0            # the bar units past 1.0 that are an overswing

	func _init() -> void:
		custom_minimum_size = Vector2(460, 34)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _x(u: float) -> float:
		return size.x * (u - LOW) / (HIGH - LOW)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.55))
		var x0 := _x(0.0)
		var x1 := _x(1.0)
		# the power set, or being set
		var p := locked if locked >= 0.0 else (marker if running else 0.0)
		if p > 0.0:
			var col := UIKit.ACCENT.lerp(UIKit.BAD, smoothstep(0.8, 1.12, p))
			draw_rect(Rect2(x0, 0, _x(minf(p, HIGH)) - x0, size.y), col)
		# the overswing region, the tenths, and the 100 mark
		draw_rect(Rect2(x1, 0, size.x - x1, size.y), Color(0.6, 0.1, 0.1, 0.25))
		for k in range(1, 10):
			var tx := _x(k / 10.0)
			draw_line(Vector2(tx, size.y - 6), Vector2(tx, size.y), Color(1, 1, 1, 0.3), 1.0)
		draw_line(Vector2(x1, 0), Vector2(x1, size.y), Color(1, 1, 1, 0.6), 2.0)
		if target >= 0.0:
			var tx := _x(clampf(target, 0.0, 1.0))
			draw_line(Vector2(tx, 0), Vector2(tx, size.y), UIKit.GOLD, 3.0)
		# the timing bands and the line itself
		var zx := _x(zone) - x0
		var gx := _x(good) - x0
		var px := _x(perfect) - x0
		draw_rect(Rect2(x0 - zx, size.y, zx * 2.0, 6), Color(0.95, 0.7, 0.2, 0.7))
		draw_rect(Rect2(x0 - gx, size.y, gx * 2.0, 6), Color(0.55, 0.8, 0.5, 0.9))
		draw_rect(Rect2(x0 - px, size.y, px * 2.0, 6), UIKit.GOOD)
		# the good band shows on the bar itself too, where the eye is
		draw_rect(Rect2(x0 - gx, 0, gx * 2.0, size.y), Color(0.55, 0.9, 0.55, 0.12))
		draw_line(Vector2(x0, -4), Vector2(x0, size.y + 6), Color.WHITE, 2.5)
		draw_rect(r, Color(1, 1, 1, 0.35), false, 1.5)
		# the marker
		if running:
			var mx := _x(clampf(marker, LOW, HIGH))
			draw_line(Vector2(mx, 0), Vector2(mx, size.y), Color.WHITE, 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(mx, 0), Vector2(mx - 6, -12), Vector2(mx + 6, -12)]), Color.WHITE)
		elif show_result:
			# where the third press landed: left of the line was early
			var rx := x0 - result * zx
			var col := UIKit.GOOD if result == 0.0 else (Color(0.6, 0.85, 0.55) if absf(result) <= 0.16 else (Color(0.95, 0.7, 0.2) if absf(result) < 0.5 else UIKit.BAD))
			draw_colored_polygon(PackedVector2Array([Vector2(rx, 0), Vector2(rx - 6, -12), Vector2(rx + 6, -12)]), col)
