class_name YardageCard
extends RefCounted
## A printed yardage diagram for one hole. Drawn once into an image and kept
## until that hole's ground, tee, placed pin or the day's cup changes. The
## line runs to the pin that was placed. The flag is the day's cup. The size
## and the colours live in data/yardage.json.

const GLYPHS: Array[String] = [
	"111101101101111",
	"010110010010111",
	"111001111100111",
	"111001111001111",
	"101101111001001",
	"111100111001111",
	"111100111101111",
	"111001010010010",
	"111101111101111",
	"111101111001111",
]

var image: Image
var draws := 0
var tee_px := Vector2.ZERO
var pin_px := Vector2.ZERO
## Player-marked turning points, in picture pixels. Empty when the hole has none.
var turn_px: Array[Vector2] = []
## Length, in metres, of the line drawn on the card.
var path_metres := 0.0

var _book: Dictionary = {}
var _sig := 0
var _have := false
## Course revision and a hash of the tee, the pin and the line. The tile
## hash is rebuilt only when one of those has changed.
var _rev := -1
var _mark := 0
var _scale := 1.0
var _left := 0.0
var _top := 0.0
var _min_c := 0.0
var _max_a := 0.0
var _anchor := Vector2.ZERO
var _up := Vector2(0.0, -1.0)
var _right := Vector2(1.0, 0.0)


func _init(book: Dictionary) -> void:
	_book = book


## The card already drawn for this hole, or a new one. Keyed by the hole
## itself, so rebuilding the panel does not hand one hole another's picture.
static func for_hole(cards: Dictionary, hole: Hole, book: Dictionary) -> YardageCard:
	var got: Variant = cards.get(hole, null)
	if got is YardageCard:
		return got
	var made := YardageCard.new(book)
	cards[hole] = made
	return made


## The cached image. The tile hash runs only when the course revision or
## this hole's tee, placed pin, day's cup or line has changed, and the
## picture is redrawn only when that hash changes.
func ensure(course: Course, hole: Hole) -> Image:
	var ends := _ends(hole)
	if _have and image != null and course.revision == _rev and ends == _mark:
		return image
	var sig := _signature(course, hole)
	_rev = course.revision
	_mark = ends
	if _have and sig == _sig and image != null:
		return image
	_draw(course, hole)
	_sig = sig
	_have = true
	draws += 1
	return image


func _ends(hole: Hole) -> int:
	var h := 2166136261
	var end := hole.design_pin()
	h = _mix(h, int(round(hole.tee.x * 10.0)))
	h = _mix(h, int(round(hole.tee.z * 10.0)))
	h = _mix(h, int(round(end.x * 10.0)))
	h = _mix(h, int(round(end.z * 10.0)))
	h = _mix(h, int(round(hole.pin.x * 10.0)))
	h = _mix(h, int(round(hole.pin.z * 10.0)))
	h = _mix(h, hole.route.size())
	for p in hole.route:
		h = _mix(h, int(round(p.x * 10.0)))
		h = _mix(h, int(round(p.y * 10.0)))
	h = _mix_turns(h, hole)
	return h


func _signature(course: Course, hole: Hole) -> int:
	var h := 2166136261
	var end := hole.design_pin()
	h = _mix(h, int(round(hole.tee.x * 10.0)))
	h = _mix(h, int(round(hole.tee.z * 10.0)))
	h = _mix(h, int(round(end.x * 10.0)))
	h = _mix(h, int(round(end.z * 10.0)))
	h = _mix(h, int(round(hole.pin.x * 10.0)))
	h = _mix(h, int(round(hole.pin.z * 10.0)))
	h = _mix(h, hole.route.size())
	for p in hole.route:
		h = _mix(h, int(round(p.x * 10.0)))
		h = _mix(h, int(round(p.y * 10.0)))
	h = _mix_turns(h, hole)
	var box := _region(course, hole)
	var x0 := int(box.x0)
	var y0 := int(box.y0)
	var x1 := int(box.x1)
	var y1 := int(box.y1)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var i := ty * course.w + tx
			h = _mix(h, course.terrain[i])
			h = _mix(h, course.objects[i])
	return h


func _mix(h: int, v: int) -> int:
	return (h * 16777619) ^ v


func _mix_turns(h: int, hole: Hole) -> int:
	h = _mix(h, hole.turns.size())
	for m in hole.turns:
		h = _mix(h, int(round(m.x * 10.0)))
		h = _mix(h, int(round(m.z * 10.0)))
	return h


## Tiles the picture covers: the line of play, plus a margin from the data.
func _region(course: Course, hole: Hole) -> Dictionary:
	var margin := int(_book.get("margin", 3))
	var end := hole.design_pin()
	var min_x := minf(hole.tee.x, minf(end.x, hole.pin.x))
	var max_x := maxf(hole.tee.x, maxf(end.x, hole.pin.x))
	var min_z := minf(hole.tee.z, minf(end.z, hole.pin.z))
	var max_z := maxf(hole.tee.z, maxf(end.z, hole.pin.z))
	for p in hole.route:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	var pad := float(margin) * Defs.TILE
	min_x -= pad
	max_x += pad
	min_z -= pad
	max_z += pad
	var x0 := clampi(int(floor(min_x / Defs.TILE)), 0, course.w - 1)
	var y0 := clampi(int(floor(min_z / Defs.TILE)), 0, course.h - 1)
	var x1 := clampi(int(floor(max_x / Defs.TILE)), 0, course.w - 1)
	var y1 := clampi(int(floor(max_z / Defs.TILE)), 0, course.h - 1)
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1}


func _draw(course: Course, hole: Hole) -> void:
	var width := int(_book.get("width", 64))
	var height := int(_book.get("height", 96))
	var pad := float(_book.get("pad", 5))
	var colours: Dictionary = _book.get("colours", {})
	var paper := _hex(str(colours.get("paper", "f4f0e6")))
	var ink := _hex(str(colours.get("ink", "1c1914")))
	var line_c := _hex(str(colours.get("line", "1c1914")))
	var tee_c := _hex(str(colours.get("tee_mark", "1c1914")))
	var pin_c := _hex(str(colours.get("pin", "8e2e2e")))
	var tree_c := _hex(str(colours.get("tree", "24361e")))
	var ground: Array[Color] = []
	ground.resize(Defs.T_KEYS.size())
	for i in Defs.T_KEYS.size():
		ground[i] = _hex(str(colours.get(Defs.T_KEYS[i], "f4f0e6")))
	image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(paper)
	var end := hole.design_pin()
	var line: PackedVector2Array = hole.route
	if line.size() < 2:
		line = PackedVector2Array([Vector2(hole.tee.x, hole.tee.z), Vector2(end.x, end.z)])
	path_metres = 0.0
	for i in range(1, line.size()):
		path_metres += line[i - 1].distance_to(line[i])
	_fit(line, hole, width, height, pad)
	var box := _region(course, hole)
	var x0 := int(box.x0)
	var y0 := int(box.y0)
	var x1 := int(box.x1)
	var y1 := int(box.y1)
	var tree_r := float(_book.get("tree", 1.6))
	for py in height:
		for px in width:
			var world := _to_world(float(px) + 0.5, float(py) + 0.5)
			var tx := int(floor(world.x / Defs.TILE))
			var ty := int(floor(world.y / Defs.TILE))
			if tx < x0 or ty < y0 or tx > x1 or ty > y1 or not course.in_bounds(tx, ty):
				continue
			var ti := ty * course.w + tx
			var t := int(course.terrain[ti])
			var col := paper
			if t >= 0 and t < ground.size():
				col = ground[t]
			if Defs.is_tree(int(course.objects[ti])):
				var centre := course.tile_center(tx, ty)
				var at := _to_px(Vector2(centre.x, centre.z))
				if at.distance_to(Vector2(px, py)) <= tree_r:
					col = tree_c
			image.set_pixel(px, py, col)
	var thick := float(_book.get("line", 1.15))
	for i in range(1, line.size()):
		_stroke(_to_px(line[i - 1]), _to_px(line[i]), thick, line_c)
	var tee_r := float(_book.get("tee_dot", 0.99))
	var pin_r := float(_book.get("pin_dot", 0.88))
	var flag := float(_book.get("flag", 4.84))
	tee_px = _to_px(Vector2(hole.tee.x, hole.tee.z))
	pin_px = _to_px(Vector2(hole.pin.x, hole.pin.z))
	_dot(tee_px, tee_r, tee_c)
	_dot(pin_px, pin_r, pin_c)
	_stroke(pin_px, pin_px + Vector2(0.0, -flag), 1.0, pin_c)
	_yards(line, ink, float(_book.get("label_gap", 8.0)))
	var turn_c := _hex(str(colours.get("turn_mark", "8a5a2b")))
	_turn_marks(hole, turn_c, ink)


func _fit(line: PackedVector2Array, hole: Hole, width: int, height: int, pad: float) -> void:
	_anchor = Vector2(hole.tee.x, hole.tee.z)
	var end := hole.design_pin()
	var away := Vector2(end.x - hole.tee.x, end.z - hole.tee.z)
	if away.length_squared() < 0.01:
		away = Vector2(0.0, 1.0)
	_up = away.normalized()
	_right = Vector2(_up.y, -_up.x)
	var min_c := 0.0
	var max_c := 0.0
	var min_a := 0.0
	var max_a := 0.0
	var pts: PackedVector2Array = line.duplicate()
	pts.append(Vector2(hole.tee.x, hole.tee.z))
	pts.append(Vector2(end.x, end.z))
	pts.append(Vector2(hole.pin.x, hole.pin.z))
	for m in hole.turns:
		pts.append(Vector2(m.x, m.z))
	for p in pts:
		var rel := p - _anchor
		var across := rel.dot(_right)
		var along := rel.dot(_up)
		min_c = minf(min_c, across)
		max_c = maxf(max_c, across)
		min_a = minf(min_a, along)
		max_a = maxf(max_a, along)
	var span_c := maxf(max_c - min_c, Defs.TILE)
	var span_a := maxf(max_a - min_a, Defs.TILE)
	var inner_w := maxf(float(width) - pad * 2.0, 1.0)
	var inner_h := maxf(float(height) - pad * 2.0, 1.0)
	_scale = minf(inner_w / span_c, inner_h / span_a)
	var content_w := span_c * _scale
	var content_h := span_a * _scale
	_left = (float(width) - content_w) * 0.5
	_top = (float(height) - content_h) * 0.5
	_min_c = min_c
	_max_a = max_a


func _to_px(world: Vector2) -> Vector2:
	var rel := world - _anchor
	var across := rel.dot(_right)
	var along := rel.dot(_up)
	return Vector2(_left + (across - _min_c) * _scale, _top + (_max_a - along) * _scale)


func _to_world(px: float, py: float) -> Vector2:
	var across := _min_c + (px - _left) / _scale
	var along := _max_a - (py - _top) / _scale
	return _anchor + _right * across + _up * along


func _yards(line: PackedVector2Array, ink: Color, gap: float) -> void:
	var turn := deg_to_rad(float(_book.get("turn", 28.0)))
	var glyph := maxi(int(_book.get("glyph", 1)), 1)
	var carried := 0.0
	var prev := Vector2.ZERO
	if line.size() >= 2:
		prev = line[1] - line[0]
	var last := Vector2(-40.0, -40.0)
	for i in range(1, line.size()):
		var step := line[i] - line[i - 1]
		carried += step.length()
		var corner := i < line.size() - 1 and prev.length_squared() > 0.01 and step.length_squared() > 0.01 and absf(prev.angle_to(step)) >= turn
		var at_pin := i == line.size() - 1
		if corner or at_pin:
			var px := _to_px(line[i])
			if px.distance_to(last) >= gap or at_pin:
				_number(int(round(px.x)), int(round(px.y)), Defs.yards(carried), ink, glyph)
				last = px
		prev = step


func _turn_marks(hole: Hole, col: Color, ink: Color) -> void:
	turn_px.clear()
	var radius := float(_book.get("turn_dot", 2.2))
	var glyph := maxi(int(_book.get("glyph", 1)), 1)
	for m in hole.turns:
		var px := _to_px(Vector2(m.x, m.z))
		turn_px.append(px)
		_dot(px, radius, col)
	if hole.turns.is_empty():
		return
	var parts := hole.turn_lengths()
	var spots: Array[Vector2] = [Vector2(hole.tee.x, hole.tee.z)]
	for stake in hole.turns:
		spots.append(Vector2(stake.x, stake.z))
	var end := hole.design_pin()
	spots.append(Vector2(end.x, end.z))
	for i in parts.size():
		if i + 1 >= spots.size():
			break
		var mid := spots[i].lerp(spots[i + 1], 0.5)
		var at := _to_px(mid)
		_number(int(round(at.x)), int(round(at.y)), Defs.yards(parts[i]), ink, glyph)


func _number(x: int, y: int, n: int, ink: Color, glyph: int) -> void:
	var text := str(maxi(n, 0))
	var step := 4 * glyph
	var w := text.length() * step
	var h := 5 * glyph
	var ox := x + 3
	var oy := y - h - 1
	if ox + w >= image.get_width():
		ox = x - w - 2
	if oy < 1:
		oy = y + 2
	ox = clampi(ox, 1, maxi(image.get_width() - w - 1, 1))
	oy = clampi(oy, 1, maxi(image.get_height() - h - 1, 1))
	for i in text.length():
		_digit(ox + i * step, oy, int(text.substr(i, 1)), ink, glyph)


func _digit(x: int, y: int, d: int, ink: Color, glyph: int) -> void:
	if d < 0 or d >= GLYPHS.size():
		return
	var bits := GLYPHS[d]
	var n := 0
	for gy in 5:
		for gx in 3:
			if bits.substr(n, 1) == "1":
				for sy in glyph:
					for sx in glyph:
						_px(x + gx * glyph + sx, y + gy * glyph + sy, ink)
			n += 1


func _stroke(a: Vector2, b: Vector2, radius: float, col: Color) -> void:
	var span := a.distance_to(b)
	var steps := maxi(int(span * 2.0), 1)
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		_dot(p, radius, col)


func _dot(p: Vector2, radius: float, col: Color) -> void:
	var r := maxf(radius, 0.5)
	var ri := int(ceil(r))
	var cx := int(round(p.x))
	var cy := int(round(p.y))
	for oy in range(-ri, ri + 1):
		for ox in range(-ri, ri + 1):
			if float(ox * ox + oy * oy) <= r * r:
				_px(cx + ox, cy + oy, col)


func _px(x: int, y: int, col: Color) -> void:
	if image == null or x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	image.set_pixel(x, y, col)


func _hex(s: String) -> Color:
	if not s.begins_with("#"):
		s = "#" + s
	return Color.html(s)
