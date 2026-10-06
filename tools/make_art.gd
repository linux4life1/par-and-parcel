extends Control
## Makes the release artwork and quits:
##   icon.png                      the app icon, 1024 square, a squircle of striped fairway with a flag and a ball
##   tools/dmg/background@2x.png   the disk image window's backdrop, 1320 by 800
##   tools/dmg/background.png      the same at 660 by 400
## Run windowed (drawing text needs a renderer):  godot --path . res://tools/make_art.tscn

const W := 1320
const H := 800

var _phase := 0


func _ready() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_factor = 1.0
	win.size = Vector2i(W, H)
	win.position = Vector2i(60, 60)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon()
	print("ART icon.png written")


func _process(_delta: float) -> void:
	_phase += 1
	if _phase == 4:
		queue_redraw()
	elif _phase == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://tools/dmg/background@2x.png")
		img.resize(W / 2, H / 2, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://tools/dmg/background.png")
		print("ART tools/dmg/background.png and @2x written")
		get_tree().quit()


# ------------------------------------------------------------- the backdrop

func _draw() -> void:
	var s := 2.0     # points to pixels
	# evening fairway: a deep green that darkens downward, with mowing stripes
	for y in range(0, H, 2):
		var t := float(y) / H
		var c := Color(0.11, 0.30, 0.17).lerp(Color(0.05, 0.16, 0.09), t)
		draw_rect(Rect2(0, y, W, 2), c)
	for k in range(-8, 20):
		var x0 := k * 120.0 - 400.0
		var poly := PackedVector2Array([Vector2(x0, H), Vector2(x0 + 60, H), Vector2(x0 + 60 + 520, 0), Vector2(x0 + 520, 0)])
		draw_colored_polygon(poly, Color(1, 1, 1, 0.035))
	# a soft light from the top left
	for i in 12:
		var r := 300.0 + i * 70.0
		draw_circle(Vector2(240, 120), r, Color(1, 1, 1, 0.012))
	# the title
	var font := ThemeDB.fallback_font
	var title := "Par & Parcel"
	var ts := int(52 * s)
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
	draw_string(font, Vector2((W - tw) / 2.0 + 3, 92 * s + 3), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(0, 0, 0, 0.35))
	draw_string(font, Vector2((W - tw) / 2.0, 92 * s), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(0.97, 0.96, 0.9))
	var sub := "Build the course. Run the club. Play the round."
	var ss := int(15 * s)
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
	draw_string(font, Vector2((W - sw) / 2.0, 124 * s), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(0.85, 0.9, 0.8, 0.8))
	# the arrow from the game to Applications, between where the two icons sit
	var a := Vector2(262 * s, 205 * s)
	var b := Vector2(398 * s, 205 * s)
	var col := Color(1, 1, 1, 0.75)
	draw_line(a, b - Vector2(18 * s, 0), col, 5.0 * s, true)
	draw_colored_polygon(PackedVector2Array([b, b - Vector2(26 * s, -16 * s), b - Vector2(26 * s, 16 * s)]), col)
	var hint := "Drag into Applications"
	var hs := int(13 * s)
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
	draw_string(font, Vector2((W - hw) / 2.0, 330 * s), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(0.85, 0.9, 0.8, 0.7))
	# a pin flag on the horizon, bottom right, as a signature
	var px := 596 * s
	var py := 372 * s
	draw_line(Vector2(px, py), Vector2(px, py - 46 * s), Color(0.9, 0.9, 0.88, 0.9), 2.0 * s, true)
	draw_colored_polygon(PackedVector2Array([Vector2(px, py - 46 * s), Vector2(px + 24 * s, py - 39 * s), Vector2(px, py - 32 * s)]), Color(0.85, 0.12, 0.1))
	draw_circle(Vector2(px, py), 3.0 * s, Color(0.05, 0.1, 0.06))


# ----------------------------------------------------------------- the icon

static func _sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length()


## Coverage of a shape from its signed distance, one pixel wide at the edge.
static func _cov(d: float) -> float:
	return clampf(0.5 - d, 0.0, 1.0)


func _icon() -> void:
	var n := 1024
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n * 0.5, n * 0.5)
	var half := n * 0.5 * 0.9       # the squircle's half width: macOS icons leave a margin
	var pin_a := Vector2(n * 0.615, n * 0.72)
	var pin_b := Vector2(n * 0.615, n * 0.26)
	var ball := Vector2(n * 0.37, n * 0.715)
	var ball_r := n * 0.072
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			# the squircle, as a superellipse
			var q := (p - c) / half
			var e := pow(absf(q.x), 5.0) + pow(absf(q.y), 5.0)
			var d_edge := (pow(e, 0.2) - 1.0) * half * 0.9
			var inside := _cov(d_edge)
			if inside <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# fairway: green that darkens downward, mowing stripes, a highlight top left
			var t := float(y) / n
			var col := Color(0.20, 0.52, 0.26).lerp(Color(0.08, 0.30, 0.14), t)
			var stripe := int(floor((x + y) / (n * 0.14)))
			if stripe % 2 == 0:
				col = col.lightened(0.07)
			var hl := clampf(1.0 - (p - Vector2(n * 0.3, n * 0.25)).length() / (n * 0.9), 0.0, 1.0)
			col = col.lightened(hl * 0.12)
			# the ball's shadow, then the ball
			var sh := _cov((p - (ball + Vector2(n * 0.012, n * 0.02))).length() - ball_r * 1.04)
			col = col.darkened(sh * 0.35)
			var bd := (p - ball).length() - ball_r
			var bc := _cov(bd)
			if bc > 0.0:
				var shade := clampf(0.55 + 0.45 * (1.0 - (p - (ball - Vector2(ball_r * 0.35, ball_r * 0.4))).length() / (ball_r * 1.6)), 0.4, 1.0)
				# dimples: a faint dot lattice
				var dim := 0.0
				var cell := ball_r * 0.28
				var lp := Vector2(fposmod(p.x, cell) - cell * 0.5, fposmod(p.y, cell) - cell * 0.5)
				if lp.length() < cell * 0.22 and bd < -ball_r * 0.12:
					dim = 0.06
				col = col.lerp(Color(0.97, 0.97, 0.95) * shade - Color(dim, dim, dim, 0.0), bc)
			# the pin's shadow and the pin
			var ps := _cov(_sd_segment(p, pin_a + Vector2(n * 0.02, n * 0.012), pin_b + Vector2(n * 0.04, n * 0.012)) - n * 0.009)
			col = col.darkened(ps * 0.3)
			var pd := _sd_segment(p, pin_a, pin_b) - n * 0.011
			var pc := _cov(pd)
			if pc > 0.0:
				var shine := 0.75 + 0.25 * clampf(1.0 - absf(p.x - (pin_b.x - n * 0.004)) / (n * 0.011), 0.0, 1.0)
				col = col.lerp(Color(0.92, 0.92, 0.9) * shine, pc)
			# the flag: a pennant to the right of the pin top
			var fa := pin_b + Vector2(n * 0.011, 0.0)
			var fb := fa + Vector2(n * 0.21, n * 0.055)
			var fc := fa + Vector2(0.0, n * 0.12)
			var e0 := (fb - fa).cross(p - fa)
			var e1 := (fc - fb).cross(p - fb)
			var e2 := (fa - fc).cross(p - fc)
			var in_tri := (e0 >= 0.0 and e1 >= 0.0 and e2 >= 0.0) or (e0 <= 0.0 and e1 <= 0.0 and e2 <= 0.0)
			var tri_d := minf(_sd_segment(p, fa, fb), minf(_sd_segment(p, fb, fc), _sd_segment(p, fc, fa)))
			var fcov := _cov(-tri_d) if in_tri else _cov(tri_d)
			if fcov > 0.0:
				var fold := 0.86 + 0.14 * sin((p.x - fa.x) / (n * 0.04))
				col = col.lerp(Color(0.86, 0.14, 0.11) * fold, fcov)
			# the cup under the pin
			var cup := _cov((Vector2((p.x - pin_a.x) * 1.0, (p.y - pin_a.y) * 2.4)).length() - n * 0.028)
			col = col.lerp(Color(0.04, 0.09, 0.05), cup)
			# a soft dark rim so the squircle reads on any background
			col = col.darkened(clampf((d_edge + n * 0.03) / (n * 0.03), 0.0, 1.0) * 0.18)
			col.a = inside
			img.set_pixel(x, y, col)
	img.save_png("res://icon.png")
