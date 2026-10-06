class_name Solids
extends RefCounted
## Everything a golf ball can hit apart from the ground: trunks and posts,
## walls and roofs, boulders, and the leaves of trees and bushes.
##
## The shapes come from data/solids.json, one list per kind of object. They
## are kept in a grid, one bucket per tile, so a flying ball only ever looks
## at the handful of shapes around it. Heights are measured from the ground
## where the object stands and are looked up as needed, so reshaping the
## land never leaves a shape floating.
##
## Nothing here is random. The computer golfers play shots forward in their
## heads with this same code before they swing.

enum K { POST, ROCK, BOX, ROOF, LEAVES }

class Shape:
	extends RefCounted
	var kind := 0
	var bx := 0.0          # where the object stands; its heights are measured from the ground here
	var bz := 0.0
	var x := 0.0           # centre of this shape
	var z := 0.0
	var r := 0.0           # radius, or half the width along x for a box or roof
	var hz := 0.0          # half the depth along z for a box or roof
	var y0 := 0.0          # bottom (the centre height, for a rock)
	var y1 := 0.0          # top (the ridge, for a roof)
	var r1 := -1.0         # leaves: the radius at the top, when they taper like a conifer
	var along_x := false   # roof: the ridge runs along x
	var grounded := false  # reaches the ground, so a rolling ball meets it too
	var bounce := 0.4      # share of speed into the surface that comes back out
	var keep := 0.7        # share of speed along the surface that is kept
	var scatter := 0.1     # how unevenly it throws the ball, in radians
	var thick := 0.0       # leaves: chance per metre of meeting a branch
	var drag := 0.0        # leaves: share of speed lost per metre
	var mat := ""
	var owner := -1        # tile the object stands on
	var obj := 0           # Defs.O

static var _data := {}

var course: Course
var hit_t := 0.0                    # how far along the last sweep the hit was, 0 to 1
var hit_n := Vector3.UP             # which way the surface faced
var _buckets: Array = []            # per tile: null, or the shapes that reach into it
var _owned := {}                    # tile -> shapes of the object standing there
var _n := Vector3.UP


func _init(c: Course) -> void:
	course = c
	_buckets.resize(c.w * c.h)


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/solids.json"))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("Could not read res://data/solids.json")
			_data = {"materials": {}, "kinds": {}}
	return _data


## What a material is like: bounce, keep, scatter and the word for the noise.
static func material(id: String) -> Dictionary:
	return data().materials.get(id, {})


# ------------------------------------------------------------ the index

func rebuild() -> void:
	_buckets.clear()
	_buckets.resize(course.w * course.h)
	_owned.clear()
	for i in course.objects.size():
		if course.objects[i] != 0:
			_add(i)


## The object on one tile changed: forget its old shapes, learn the new.
func set_tile(i: int) -> void:
	if _owned.has(i):
		for s: Shape in _owned[i]:
			_each_bucket(s, false)
		_owned.erase(i)
	if i >= 0 and i < course.objects.size() and course.objects[i] != 0:
		_add(i)


func _add(i: int) -> void:
	var o := course.objects[i]
	var kind := course.kind_of(o)
	var list: Array = data().kinds.get(kind, [])
	if list.is_empty():
		return
	var mats: Dictionary = data().materials
	var tx := i % course.w
	var tz := i / course.w
	var cx := (tx + 0.5) * Defs.TILE
	var cz := (tz + 0.5) * Defs.TILE
	var sc := 1.0
	var sy := 1.0
	var yaw := 0.0
	if Defs.PLANT_KINDS.has(kind):
		# plants are nudged, turned and sized a little differently each (see Defs.plant_*)
		var off := Defs.plant_offset(i)
		cx += off.x
		cz += off.y
		var s2 := Defs.plant_scale(i)
		sc = s2.x
		sy = s2.y
		yaw = Defs.plant_yaw(i)
	elif o == Defs.O.HOUSE:
		yaw = Defs.house_turns(i) * PI * 0.5
	var quarter := int(round(yaw / (PI * 0.5))) if o == Defs.O.HOUSE else 0
	var ca := cos(yaw)
	var sa := sin(yaw)
	var mine: Array = []
	for d: Dictionary in list:
		var s := Shape.new()
		var k := str(d.k)
		var lx := float(d.get("x", 0.0)) * sc
		var lz := float(d.get("z", 0.0)) * sc
		# a turn about the vertical, the same way the model is turned
		s.x = cx + lx * ca + lz * sa
		s.z = cz - lx * sa + lz * ca
		s.bx = cx
		s.bz = cz
		s.owner = i
		s.obj = o
		s.mat = str(d.get("m", ""))
		var m: Dictionary = mats.get(s.mat, {})
		s.bounce = float(m.get("bounce", 0.4))
		s.keep = float(m.get("keep", 0.7))
		s.scatter = float(m.get("scatter", 0.1))
		s.thick = float(m.get("thick", 0.0))
		s.drag = float(m.get("drag", 0.0))
		s.y0 = float(d.get("y0", 0.0)) * sy
		s.y1 = float(d.get("y1", 0.0)) * sy
		s.grounded = s.y0 < 0.3
		match k:
			"post":
				s.kind = K.POST
				s.r = float(d.r) * sc
			"rock":
				s.kind = K.ROCK
				s.r = float(d.r) * sc
				s.y0 = float(d.get("y", 0.0)) * sy
				s.grounded = true
			"box", "roof":
				s.kind = K.BOX if k == "box" else K.ROOF
				s.r = float(d.hx)
				s.hz = float(d.hz)
				if quarter % 2 != 0:
					s.r = float(d.hz)
					s.hz = float(d.hx)
					s.along_x = true
			"leaves":
				s.kind = K.LEAVES
				s.r = float(d.r) * sc
				s.r1 = float(d.get("r1", -1.0)) * (sc if d.has("r1") else 1.0)
		mine.append(s)
		_each_bucket(s, true)
	_owned[i] = mine


func _each_bucket(s: Shape, add: bool) -> void:
	var ex := s.r + 0.3
	var ez := (s.hz if (s.kind == K.BOX or s.kind == K.ROOF) else s.r) + 0.3
	var x0 := clampi(int(floor((s.x - ex) / Defs.TILE)), 0, course.w - 1)
	var x1 := clampi(int(floor((s.x + ex) / Defs.TILE)), 0, course.w - 1)
	var z0 := clampi(int(floor((s.z - ez) / Defs.TILE)), 0, course.h - 1)
	var z1 := clampi(int(floor((s.z + ez) / Defs.TILE)), 0, course.h - 1)
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			var j := tz * course.w + tx
			if add:
				if _buckets[j] == null:
					_buckets[j] = []
				(_buckets[j] as Array).append(s)
			elif _buckets[j] != null:
				var b: Array = _buckets[j]
				b.erase(s)
				if b.is_empty():
					_buckets[j] = null


## The shapes reaching into a tile, or null when there are none.
func bucket(tile: int) -> Variant:
	if tile < 0 or tile >= _buckets.size():
		return null
	return _buckets[tile]


## How many shapes there are, for tests.
func count() -> int:
	var n := 0
	for i: int in _owned:
		n += (_owned[i] as Array).size()
	return n


# ------------------------------------------------------------- the tests

## The first solid thing a ball of radius `rad` meets going from a to b.
## Returns the shape, or null. `hit_t` and `hit_n` describe the contact.
func sweep(shapes: Array, a: Vector3, b: Vector3, rad: float) -> Shape:
	var best: Shape = null
	var best_t := 2.0
	var best_n := Vector3.UP
	for s: Shape in shapes:
		var t := -1.0
		match s.kind:
			K.POST:
				t = _post(s, a, b, rad)
			K.ROCK:
				t = _rock(s, a, b, rad)
			K.BOX:
				t = _box(s, a, b, rad)
			K.ROOF:
				t = _roof(s, a, b, rad)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = s
			best_n = _n
	hit_t = clampf(best_t, 0.0, 1.0)
	hit_n = best_n
	return best


## The foliage a point is inside, or null.
func leaves(shapes: Array, p: Vector3) -> Shape:
	for s: Shape in shapes:
		if s.kind != K.LEAVES:
			continue
		var gy := course.height_at(s.bx, s.bz)
		var y0 := gy + s.y0
		var y1 := gy + s.y1
		if p.y < y0 or p.y > y1:
			continue
		var dx := p.x - s.x
		var dz := p.z - s.z
		var d2 := dx * dx + dz * dz
		if s.r1 >= 0.0:
			var rr := lerpf(s.r, s.r1, (p.y - y0) / (y1 - y0))
			if d2 < rr * rr:
				return s
		else:
			var ry := (y1 - y0) * 0.5
			var dy := (p.y - (y0 + y1) * 0.5) / ry
			if d2 / (s.r * s.r) + dy * dy < 1.0:
				return s
	return null


func _post(s: Shape, a: Vector3, b: Vector3, rad: float) -> float:
	var gy := course.height_at(s.bx, s.bz)
	var y0 := gy + s.y0 - (1.0 if s.grounded else 0.0)
	var y1 := gy + s.y1
	var rr := s.r + rad
	var dx := b.x - a.x
	var dz := b.z - a.z
	var ox := a.x - s.x
	var oz := a.z - s.z
	var c := ox * ox + oz * oz - rr * rr
	var best := -1.0
	var qb := ox * dx + oz * dz
	if c > 0.0:
		var qa := dx * dx + dz * dz
		if qa > 1e-12 and qb < 0.0:
			var disc := qb * qb - qa * c
			if disc >= 0.0:
				var t := (-qb - sqrt(disc)) / qa
				if t <= 1.0:
					var y := a.y + (b.y - a.y) * t
					if y >= y0 and y <= y1:
						_n = Vector3(ox + dx * t, 0.0, oz + dz * t).normalized()
						best = maxf(t, 0.0)
	elif qb < 0.0 and a.y >= y0 and a.y <= y1:
		# already touching and still heading in: turn it round at once
		var l := sqrt(ox * ox + oz * oz)
		_n = Vector3(ox / l, 0.0, oz / l) if l > 0.001 else Vector3(1.0, 0.0, 0.0)
		return 0.0
	# landing on top
	if a.y >= y1 + rad and b.y < y1 + rad:
		var t2 := (a.y - y1 - rad) / (a.y - b.y)
		if best < 0.0 or t2 < best:
			var px := a.x + dx * t2 - s.x
			var pz := a.z + dz * t2 - s.z
			if px * px + pz * pz <= s.r * s.r:
				_n = Vector3.UP
				best = t2
	return best


func _rock(s: Shape, a: Vector3, b: Vector3, rad: float) -> float:
	var gy := course.height_at(s.bx, s.bz)
	var o := a - Vector3(s.x, gy + s.y0, s.z)
	var d := b - a
	var qb := o.dot(d)
	if qb >= 0.0:
		return -1.0
	var rr := s.r + rad
	var c := o.length_squared() - rr * rr
	if c <= 0.0:
		_n = o.normalized() if o.length_squared() > 0.0001 else Vector3.UP
		return 0.0
	var qa := d.length_squared()
	var disc := qb * qb - qa * c
	if disc < 0.0 or qa < 1e-12:
		return -1.0
	var t := (-qb - sqrt(disc)) / qa
	if t > 1.0:
		return -1.0
	_n = (o + d * t).normalized()
	return maxf(t, 0.0)


func _box(s: Shape, a: Vector3, b: Vector3, rad: float) -> float:
	var gy := course.height_at(s.bx, s.bz)
	var lo := Vector3(s.x - s.r - rad, gy + s.y0 - (1.0 if s.grounded else rad), s.z - s.hz - rad)
	var hi := Vector3(s.x + s.r + rad, gy + s.y1 + rad, s.z + s.hz + rad)
	var tmin := 0.0
	var tmax := 1.0
	var axis := -1
	var face := 0.0
	for k in 3:
		var o := a[k]
		var d := b[k] - o
		if absf(d) < 1e-9:
			if o < lo[k] or o > hi[k]:
				return -1.0
		else:
			var t1 := (lo[k] - o) / d
			var t2 := (hi[k] - o) / d
			var sg := -1.0
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
				sg = 1.0
			if t1 > tmin:
				tmin = t1
				axis = k
				face = sg
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	if axis < 0:
		return -1.0            # began inside: let it out rather than trap it
	_n = Vector3.ZERO
	_n[axis] = face
	return tmin


func _roof(s: Shape, a: Vector3, b: Vector3, rad: float) -> float:
	# inside the footprint and under the slope at the end of the step?
	if absf(b.x - s.x) > s.r + rad or absf(b.z - s.z) > s.hz + rad:
		return -1.0
	var gy := course.height_at(s.bx, s.bz)
	var eave := gy + s.y0
	var rise := s.y1 - s.y0
	var fb := b.y - _roof_y(s, b, eave, rise) - rad
	if fb >= 0.0 or b.y < eave - 0.4:
		return -1.0
	var a_in := absf(a.x - s.x) <= s.r + rad and absf(a.z - s.z) <= s.hz + rad
	if a_in:
		var fa := a.y - _roof_y(s, a, eave, rise) - rad
		if fa < 0.0:
			return -1.0        # began under the slope: leave it be
		# came down onto the slope
		if s.along_x:
			_n = Vector3(0.0, s.hz, signf(b.z - s.z) * rise).normalized()
		else:
			_n = Vector3(signf(b.x - s.x) * rise, s.r, 0.0).normalized()
		return fa / (fa - fb)
	# flew in through a gable end or under the eave
	var nx := (a.x - s.x) / s.r
	var nz := (a.z - s.z) / s.hz
	_n = Vector3(signf(nx), 0.0, 0.0) if absf(nx) > absf(nz) else Vector3(0.0, 0.0, signf(nz))
	return 0.5


func _roof_y(s: Shape, p: Vector3, eave: float, rise: float) -> float:
	var u := absf(p.z - s.z) / s.hz if s.along_x else absf(p.x - s.x) / s.r
	return eave + rise * (1.0 - clampf(u, 0.0, 1.0))
