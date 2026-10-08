class_name Slope
extends RefCounted
## How the ground falls. Percent is the grade (a rise of one metre in a
## hundred), and the fall is the downhill direction. Greens are read on a
## finer scale than the rest of the course; the numbers live in data/slope.json.

## Next overlay after lights. The view bar and the terrain shader share it.
const OVERLAY := 7

static var _book: Dictionary = {}


## The shared data loader hands this the slope file. Slope does not read it itself.
static func use(data: Dictionary) -> void:
	_book = data


static func book() -> Dictionary:
	return _book


## Grade and downhill direction at a point. Flat ground is 0, with no fall.
static func read(course: Course, x: float, z: float) -> Dictionary:
	var g := course.gradient_at(x, z)
	var mag := g.length()
	var fall := Vector2.ZERO
	if mag > 1e-8:
		fall = -g / mag
	return {"percent": mag * 100.0, "fall": fall}


## The same reading averaged along the line, staying on the green.
static func along(course: Course, from: Vector3, to: Vector3) -> Dictionary:
	var n: int = maxi(int(book().get("line_samples", 4)), 1)
	var acc := Vector2.ZERO
	var count := 0
	for k in n:
		var q := from.lerp(to, float(k + 1) / float(n))
		if not Defs.is_green(course.terrain_at(q.x, q.z)):
			continue
		acc += course.gradient_at(q.x, q.z)
		count += 1
	if count == 0:
		return read(course, from.x, from.z)
	var g := acc / float(count)
	var mag := g.length()
	var fall := Vector2.ZERO
	if mag > 1e-8:
		fall = -g / mag
	return {"percent": mag * 100.0, "fall": fall}


## True when the ball is on a green, or within the data's near distance of one.
static func near_green(course: Course, x: float, z: float) -> bool:
	if Defs.is_green(course.terrain_at(x, z)):
		return true
	var reach := float(book().get("near", 10.0))
	var r := int(ceil(reach / Defs.TILE))
	var tx := int(floor(x / Defs.TILE))
	var ty := int(floor(z / Defs.TILE))
	var reach2 := reach * reach
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx := tx + dx
			var ny := ty + dy
			if not course.in_bounds(nx, ny):
				continue
			if not Defs.is_green(course.terrain[ny * course.w + nx]):
				continue
			var c := course.tile_center(nx, ny)
			var ddx := c.x - x
			var ddz := c.z - z
			if ddx * ddx + ddz * ddz <= reach2:
				return true
	return false


## How far apart the downhill marks sit, and how long they are.
static func mark(percent: float) -> Dictionary:
	var data := book()
	if percent < float(data.get("arrow_min", 0.4)):
		return {"show": false, "space": 0.0, "length": 0.0}
	var steep := maxf(float(data.get("steep_at", 4.0)), 0.001)
	var t := clampf(percent / steep, 0.0, 1.0)
	var space := lerpf(float(data.get("space_flat", 5.0)), float(data.get("space_steep", 2.2)), t)
	var length := lerpf(float(data.get("len_flat", 0.85)), float(data.get("len_steep", 1.15)), t)
	return {"show": true, "space": space, "length": length}


static func percent_text(pct: float) -> String:
	if pct < 0.05:
		return "0%"
	if pct < 10.0:
		return "%.1f%%" % pct
	return "%d%%" % roundi(pct)


## The fall in plain words, relative to a direction (the line to the hole).
## It names the slope. It does not choose a place to aim.
static func words(read: Dictionary, toward: Vector2) -> String:
	var pct := float(read.get("percent", 0.0))
	if pct < 0.05:
		return "flat"
	var fall: Vector2 = read.get("fall", Vector2.ZERO)
	var said := percent_text(pct)
	if toward.length_squared() < 1e-6 or fall.length_squared() < 1e-8:
		return said
	var dir := toward.normalized()
	var right := Vector2(-dir.y, dir.x)
	var along := fall.dot(dir)
	var side := fall.dot(right)
	var bits := PackedStringArray()
	if absf(along) >= 0.35:
		bits.append("downhill" if along > 0.0 else "uphill")
	if absf(side) >= 0.35:
		bits.append("to the right" if side > 0.0 else "to the left")
	if bits.is_empty():
		if absf(along) >= absf(side):
			bits.append("downhill" if along > 0.0 else "uphill")
		else:
			bits.append("to the right" if side > 0.0 else "to the left")
	return "%s %s" % [said, " ".join(bits)]


## The aim line's ink while putting: the map's own colours, pale uphill and
## deeper downhill. A flat putt keeps the ordinary line.
static func aim_tint(along: float, percent: float, ink: Color) -> Color:
	var data := book()
	# Only the part of the fall that runs along the aim. A side slope, and
	# flat ground, keep the ink the aim line already uses.
	if percent < float(data.get("arrow_min", 0.4)) or absf(along) < 0.25:
		return ink
	var stops: Array = data.get("stops", [])
	if stops.is_empty():
		return ink
	var row: Array = stops[2] if along > 0.0 and stops.size() > 2 else stops[0]
	return Color(float(row[0]), float(row[1]), float(row[2]), 0.82)


static func legend() -> String:
	var data := book()
	return "Greens: flat to %d%%. Elsewhere: flat to %d%%." % [int(data.get("green_full", 4)), int(data.get("course_full", 20))]


static func fair_line() -> String:
	var data := book()
	return "A fair green is about %d to %d%%." % [int(data.get("fair_lo", 1)), int(data.get("fair_hi", 3))]
