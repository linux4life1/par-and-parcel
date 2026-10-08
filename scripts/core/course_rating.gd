class_name CourseRating
extends RefCounted
## A scratch score and a slope, in the public shape of a course rating.
## The 0–100 reputation rating is a different number and is left alone.
## Weights live in data/rating.json. Nothing here is drawn.

static var book: Dictionary = {}


static func use(d: Dictionary) -> void:
	book = d


var _rev := -2
var _scratch := 0.0
var _scratch_sum := 0.0
var _bogey := 0.0
var _slope := 0
var ready := false


func ensure(sim: Sim) -> void:
	var rev := sim.course.revision
	if rev == _rev:
		return
	sim.refresh_hole_lines()
	_rev = sim.course.revision
	_fill(sim.course)


func scratch_text() -> String:
	if not ready:
		return "–"
	return "%.1f" % _scratch


func slope_text() -> String:
	if not ready:
		return "–"
	return str(_slope)


func scratch_score() -> float:
	return _scratch


## The scratch total before it is snapped to a tenth. Two copies of a hole
## double this, even when the shown tenth would round the other way.
func scratch_sum() -> float:
	return _scratch_sum


func bogey_score() -> float:
	return _bogey


func slope_score() -> int:
	return _slope


func _fill(course: Course) -> void:
	var holes := course.holes
	if holes.is_empty():
		ready = false
		_scratch = 0.0
		_scratch_sum = 0.0
		_bogey = 0.0
		_slope = 0
		return
	var scratch := 0.0
	var bogey := 0.0
	for hole in holes:
		var pair := _hole(course, hole)
		scratch += pair.x
		bogey += pair.y
	_scratch_sum = scratch
	_bogey = bogey
	_scratch = round(scratch * 10.0) / 10.0
	var n := holes.size()
	var gap := (bogey - scratch) * float(_i("standard_holes", 18)) / float(n)
	var raw := int(round(gap * _f("scale", 5.381)))
	_slope = clampi(raw, _i("slope_min", 55), _i("slope_max", 155))
	ready = true


func _hole(course: Course, hole: Hole) -> Vector2:
	var end := hole.design_pin()
	var climb := end.y - hole.tee.y
	var eff := hole.length
	if climb > 0.0:
		eff += climb * _f("uphill", 1.0)
	else:
		eff += climb * _f("downhill", 0.5)
	eff = maxf(eff, _f("min_length", 10.0))
	var scratch := eff / _f("scratch_run", 83.0)
	var bogey := eff / _f("bogey_run", 64.5)
	var carry := _carry(course, hole)
	scratch += carry * _f("carry_scratch", 0.01)
	bogey += carry * _f("carry_bogey", 0.028)
	var landings: Array = book.get("landing", [])
	var width_sum := 0.0
	var width_n := 0
	var seen := {}
	for mark in landings:
		var t := float(mark)
		var at := hole.point_along(t, course)
		_tally(course, at.x, at.z, seen)
		width_sum += _width(course, hole, t)
		width_n += 1
	var pin := hole.point_along(1.0, course)
	_tally(course, pin.x, pin.z, seen)
	var narrow := maxf(0.0, _f("fairway_wide", 28.0) - width_sum / maxf(float(width_n), 1.0))
	scratch += narrow * _f("narrow_scratch", 0.02)
	bogey += narrow * _f("narrow_bogey", 0.05)
	var bunkers: int = mini(int(seen.get("bunker", 0)), _i("bunker_cap", 6))
	var ponds: int = mini(int(seen.get("water", 0)), _i("water_cap", 6))
	var trees: int = mini(int(seen.get("tree", 0)), _i("tree_cap", 8))
	var outs: int = mini(int(seen.get("oob", 0)), _i("oob_cap", 6))
	scratch += float(bunkers) * _f("bunker_scratch", 0.03)
	bogey += float(bunkers) * _f("bunker_bogey", 0.08)
	scratch += float(ponds) * _f("water_scratch", 0.04)
	bogey += float(ponds) * _f("water_bogey", 0.1)
	scratch += float(trees) * _f("tree_scratch", 0.015)
	bogey += float(trees) * _f("tree_bogey", 0.04)
	scratch += float(outs) * _f("oob_scratch", 0.03)
	bogey += float(outs) * _f("oob_bogey", 0.08)
	var shy := maxf(0.0, _f("green_room", 450.0) - _green_area(course, hole))
	scratch += shy * _f("green_scratch", 0.0005)
	bogey += shy * _f("green_bogey", 0.0012)
	var grade := course.gradient_at(end.x, end.z).length() * 100.0
	var steep := maxf(0.0, grade - _f("slope_flat", 2.0))
	scratch += steep * _f("grade_scratch", 0.03)
	bogey += steep * _f("grade_bogey", 0.08)
	return Vector2(scratch, bogey)


func _carry(course: Course, hole: Hole) -> float:
	var total := hole.length
	if total < 1.0:
		return 0.0
	var step := _f("sample", 2.0)
	var run := 0.0
	var best := 0.0
	var walked := 0.0
	while walked <= total + 0.01:
		var at := hole.point_along(clampf(walked / total, 0.0, 1.0), course)
		var i := course.index_at(at.x, at.z)
		var wet := false
		if i >= 0:
			wet = int(course.terrain[i]) == Defs.T.WATER
		if wet:
			run += step
			if run > best:
				best = run
		else:
			run = 0.0
		walked += step
	return best


func _width(course: Course, hole: Hole, t: float) -> float:
	var at := hole.point_along(t, course)
	var dir := hole.direction_at(t)
	var perp := Vector2(-dir.y, dir.x)
	var limit := _f("side", 40.0)
	return _span(course, at, perp, limit) + _span(course, at, -perp, limit)


func _span(course: Course, at: Vector3, perp: Vector2, limit: float) -> float:
	var step := _f("sample", 2.0)
	var travelled := 0.0
	while travelled + step <= limit:
		var next := travelled + step
		var x := at.x + perp.x * next
		var z := at.z + perp.y * next
		var i := course.index_at(x, z)
		if i < 0:
			break
		var ground: int = course.terrain[i]
		if not (Defs.is_fairway(ground) or Defs.is_green(ground) or ground == Defs.T.TEE):
			break
		travelled = next
	return travelled


func _green_area(course: Course, hole: Hole) -> float:
	var reach := _f("green_reach", 24.0)
	var tiles := int(ceil(reach / Defs.TILE))
	var pin := hole.design_pin()
	var origin := course.tile_of(pin.x, pin.z)
	var n := 0
	for ty in range(origin.y - tiles, origin.y + tiles + 1):
		for tx in range(origin.x - tiles, origin.x + tiles + 1):
			if not course.in_bounds(tx, ty):
				continue
			var centre := course.tile_center(tx, ty)
			if Vector2(centre.x - pin.x, centre.z - pin.z).length() > reach:
				continue
			if Defs.is_green(int(course.terrain[ty * course.w + tx])):
				n += 1
	return float(n) * Defs.TILE * Defs.TILE


func _tally(course: Course, x: float, z: float, seen: Dictionary) -> void:
	var reach := _f("near", 18.0)
	var tiles := int(ceil(reach / Defs.TILE))
	var origin := course.tile_of(x, z)
	for ty in range(origin.y - tiles, origin.y + tiles + 1):
		for tx in range(origin.x - tiles, origin.x + tiles + 1):
			if not course.in_bounds(tx, ty):
				continue
			var centre := course.tile_center(tx, ty)
			if Vector2(centre.x - x, centre.z - z).length() > reach:
				continue
			var i := ty * course.w + tx
			var kind := ""
			if int(course.terrain[i]) == Defs.T.BUNKER:
				kind = "bunker"
			elif int(course.terrain[i]) == Defs.T.WATER:
				kind = "water"
			elif Defs.is_tree(int(course.objects[i])):
				kind = "tree"
			elif course.is_out(centre.x, centre.z):
				kind = "oob"
			if kind == "":
				continue
			var key := "%s:%d" % [kind, i]
			if seen.has(key):
				continue
			seen[key] = true
			seen[kind] = int(seen.get(kind, 0)) + 1


static func _f(key: String, fallback: float) -> float:
	return float(book.get(key, fallback))


static func _i(key: String, fallback: int) -> int:
	return int(book.get(key, fallback))
