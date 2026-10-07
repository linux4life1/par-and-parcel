class_name CourseGen
extends RefCounted
## Builds the land for a new game, and optionally routes a few starter holes.

# Tee and pin positions as fractions of the map: [tee x, tee y, pin x, pin y].
const LAYOUTS := {
	3: [[0.38, 0.84, 0.14, 0.42], [0.14, 0.33, 0.24, 0.12], [0.30, 0.14, 0.52, 0.66]],
	4: [[0.38, 0.84, 0.14, 0.42], [0.14, 0.33, 0.24, 0.12], [0.33, 0.10, 0.74, 0.16], [0.80, 0.24, 0.58, 0.74]],
	5: [[0.38, 0.84, 0.14, 0.42], [0.14, 0.33, 0.24, 0.12], [0.33, 0.10, 0.78, 0.14], [0.86, 0.20, 0.84, 0.46], [0.88, 0.56, 0.62, 0.86]],
}


static func generate(spec: Dictionary, rng: RandomNumberGenerator, biome: Dictionary = {}) -> Course:
	var w := int(spec.get("w", 128))
	var h := int(spec.get("h", 128))
	var c := Course.new(w, h)
	c.biome_id = str(biome.get("id", "lush"))
	var gen: Dictionary = biome.get("gen", {})
	var amp: float = gen.get("amp", 5.5)
	var bump: float = gen.get("bump", 0.5)
	var deep_at: float = gen.get("deep", 0.34)
	var tree_density: float = gen.get("trees", 0.3)
	var tree_mix: float = gen.get("mix", 0.4)
	var bush_density: float = gen.get("bushes", 0.012)
	var rock_density: float = gen.get("rocks", 0.0)
	var sparse := tree_density < 0.15
	var n1 := FastNoiseLite.new()
	n1.seed = rng.randi()
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = gen.get("freq", 0.011)
	n1.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = rng.randi()
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n2.frequency = 0.035
	for vy in h + 1:
		for vx in w + 1:
			c.heights[vy * (w + 1) + vx] = n1.get_noise_2d(vx, vy) * amp + n2.get_noise_2d(vx, vy) * bump

	# ground cover, wild trees, bushes and boulders
	for ty in h:
		for tx in w:
			var i := ty * w + tx
			var edge := mini(mini(tx, ty), mini(w - 1 - tx, h - 1 - ty))
			if edge < 3 or n2.get_noise_2d(tx * 0.7 + 300.0, ty * 0.7) > deep_at:
				c.terrain[i] = Defs.T.DEEP_ROUGH
			var tv := n1.get_noise_2d(tx * 2.0 + 900.0, ty * 2.0 + 500.0)
			var r := rng.randf()
			if tv > 0.15 and r < tree_density:
				c.objects[i] = Defs.O.PINE if rng.randf() < tree_mix else Defs.O.OAK
			elif r > 1.0 - bush_density:
				c.objects[i] = Defs.O.BUSH
			elif r > 1.0 - bush_density - rock_density:
				c.objects[i] = Defs.O.BOULDER

	# a coastline along the west edge
	if spec.get("coast", false):
		for ty in h:
			var shore := 5 + int(n2.get_noise_2d(ty * 1.5, 77.0) * 3.0)
			for tx in shore:
				c.set_terrain(tx, ty, Defs.T.WATER)

	if gen.has("volcano"):
		_make_volcano(c, gen.volcano, rng)

	# the clubhouse sits on a level pad near the bottom edge
	c.clubhouse = Vector2i(w / 2, h - 8)
	var cc := c.tile_center(c.clubhouse.x, c.clubhouse.y)
	for pass_i in 4:
		c.flatten(cc.x, cc.z, 34.0, cc.y, 0.8)
	for ty in range(c.clubhouse.y - 5, c.clubhouse.y + 5):
		for tx in range(c.clubhouse.x - 6, c.clubhouse.x + 7):
			if c.in_bounds(tx, ty):
				var i := ty * w + tx
				c.objects[i] = 0
				if c.terrain[i] != Defs.T.WATER:
					c.terrain[i] = Defs.T.ROUGH
	for ty in range(c.clubhouse.y - 3, c.clubhouse.y):
		for tx in range(c.clubhouse.x - 2, c.clubhouse.x + 3):
			c.terrain[ty * w + tx] = Defs.T.PATH
	c.objects[c.clubhouse.y * w + c.clubhouse.x] = Defs.O.CLUBHOUSE

	var n := int(spec.get("holes", 0))
	if LAYOUTS.has(n):
		for l: Array in LAYOUTS[n]:
			var tee := Vector2i(int(float(l[0]) * w), int(float(l[1]) * h))
			var pin := Vector2i(int(float(l[2]) * w), int(float(l[3]) * h))
			route_hole(c, tee, pin, rng, sparse)

	# Ponds (or lava pools) go in the low spots, placed after the holes so
	# they sit beside the fairways as hazards and never on a green or a tee.
	for k in int(gen.get("ponds", 2)):
		var best := Vector2i(-1, -1)
		var low := INF
		var r := rng.randi_range(2, 4)
		for s in 80:
			var tx := rng.randi_range(w / 6, w * 5 / 6)
			var ty := rng.randi_range(h / 6, h * 3 / 4)
			if not _pond_fits(c, Vector2i(tx, ty), r):
				continue
			var hv := c.corner(tx, ty) + (0.0 if k == 0 else rng.randf() * 2.0)
			if hv < low:
				low = hv
				best = Vector2i(tx, ty)
		if best.x < 0:
			continue
		_blob(c, best, r, Defs.T.WATER, rng)
		var bc := c.tile_center(best.x, best.y)
		for pass_i in 3:
			c.smooth(bc.x, bc.z, (r + 5) * Defs.TILE, 0.5)
	for hole in c.holes:
		hole.snap_to_ground(c)

	var neglect: float = spec.get("neglect", 0.0)
	if neglect > 0.0:
		for i in w * h:
			if Defs.T_WEED[c.terrain[i]] > 0.0:
				if rng.randf() < neglect * 0.45:
					c.weeds[i] = rng.randf_range(0.3, 1.0)
				c.health[i] = clampf(1.0 - neglect * rng.randf_range(0.2, 0.8), 0.1, 1.0)
				if rng.randf() < neglect * 0.012:
					c.pests[i] = rng.randf_range(0.4, 0.9)
	if str(spec.get("land", "all")) == "starter":
		_starter_land(c)
	# Holes were measured as each one was laid, before later holes and the
	# starter fence. Measure them again on the finished ground.
	for hole in c.holes:
		hole.update_metrics(c)
	c.guard = true
	c.revision += 1
	return c


## Raise a volcano: a steep cone of rock and ash with a lava lake in the
## crater and lava channels running down its flanks. Spec is
## [x fraction, y fraction, radius fraction, height in metres].
static func _make_volcano(c: Course, v: Array, rng: RandomNumberGenerator) -> void:
	var cx := float(v[0]) * c.w
	var cy := float(v[1]) * c.h
	var radius := float(v[2]) * minf(c.w, c.h)
	var height := float(v[3])
	var rc := 3.2
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.15
	var base := c.corner(int(cx), int(cy))
	var floor_h := base + height * pow(1.0 - rc / radius, 1.6) - 5.0
	for vy in range(int(cy - radius) - 2, int(cy + radius) + 3):
		for vx in range(int(cx - radius) - 2, int(cx + radius) + 3):
			if vx < 0 or vy < 0 or vx > c.w or vy > c.h:
				continue
			var d := Vector2(vx - cx, vy - cy).length()
			if d > radius:
				continue
			var i := vy * (c.w + 1) + vx
			if d < rc:
				c.heights[i] = floor_h
				continue
			var t := d / radius
			var ridge := 1.0 + 0.16 * noise.get_noise_2d(vx * 1.0, vy * 1.0) * t
			c.heights[i] = lerpf(base, c.heights[i], t * t) + height * pow(1.0 - t, 1.6) * ridge
	var reach := int(radius * 1.08) + 1
	for ty in range(int(cy) - reach, int(cy) + reach + 1):
		for tx in range(int(cx) - reach, int(cx) + reach + 1):
			if not c.in_bounds(tx, ty):
				continue
			var d := Vector2(tx + 0.5 - cx, ty + 0.5 - cy).length()
			if d > radius * 1.08:
				continue
			var i := ty * c.w + tx
			c.objects[i] = 0
			if d < rc - 0.4:
				c.terrain[i] = Defs.T.WATER
			elif d < radius * 0.7 or noise.get_noise_2d(tx * 2.0, ty * 2.0) > 0.25:
				c.terrain[i] = Defs.T.ROCK
			else:
				c.terrain[i] = Defs.T.ASH
			if d < radius:
				c.hot[i] = 1
	# lava channels down the flanks
	for k in 2:
		var ang := rng.randf() * TAU
		var phase := rng.randf() * TAU
		for s in int(radius * 0.92):
			var a := ang + sin(s * 0.33 + phase) * 0.13
			var tx := int(cx + cos(a) * (rc + s))
			var ty := int(cy + sin(a) * (rc + s))
			if c.in_bounds(tx, ty):
				c.terrain[ty * c.w + tx] = Defs.T.WATER
	c.volcanoes.append({
		"x": cx * Defs.TILE, "z": cy * Defs.TILE, "radius": radius * Defs.TILE,
		"crater_r": rc * Defs.TILE, "floor": floor_h, "rim": floor_h + 5.0,
	})


## Start with only the land the first holes and the clubhouse stand on.
static func _starter_land(c: Course) -> void:
	c.locked.fill(1)
	_unlock(c, c.clubhouse.x, c.clubhouse.y, 12)
	var door := c.tile_center(c.clubhouse.x, c.clubhouse.y)
	var last := door
	for hole in c.holes:
		_unlock_line(c, last, hole.tee, 5)
		_unlock_line(c, hole.tee, hole.pin, 13)
		last = hole.pin
	if c.holes.is_empty():
		_unlock(c, c.clubhouse.x, c.clubhouse.y - 14, 30)
	else:
		_unlock_line(c, last, door, 5)


static func _unlock_line(c: Course, a: Vector3, b: Vector3, r: int) -> void:
	var steps := maxi(1, int(a.distance_to(b) / (Defs.TILE * 6.0)))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		var t := c.tile_of(p.x, p.z)
		_unlock(c, t.x, t.y, r)


static func _unlock(c: Course, tx: int, ty: int, r: int) -> void:
	var p0 := c.parcel_of(maxi(tx - r, 0), maxi(ty - r, 0))
	var p1 := c.parcel_of(mini(tx + r, c.w - 1), mini(ty + r, c.h - 1))
	for py in range(p0.y, p1.y + 1):
		for px in range(p0.x, p1.x + 1):
			var rect := c.parcel_rect(Vector2i(px, py))
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					c.locked[y * c.w + x] = 0


## Lay out one hole between two tiles: clear a corridor, mow a fairway with a
## gentle bend, shape a green and a tee, then add bunkers and trees.
static func route_hole(c: Course, tee_t: Vector2i, pin_t: Vector2i, rng: RandomNumberGenerator, sparse: bool = false) -> Hole:
	var tee := c.tile_center(tee_t.x, tee_t.y)
	var pin := c.tile_center(pin_t.x, pin_t.y)
	var a := Vector2(tee.x, tee.z)
	var b := Vector2(pin.x, pin.z)
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var perp := Vector2(-dir.y, dir.x)
	var bend := rng.randf_range(-0.16, 0.16) * length if length > 230.0 else 0.0
	var mid := a.lerp(b, 0.5) + perp * bend
	var steps := maxi(4, int(length / 4.0))
	var half := rng.randi_range(2, 3)
	var start_t := 0.7 if length <= 225.0 else 55.0 / length

	for s in steps + 1:
		var t := float(s) / steps
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		var tile := c.tile_of(p.x, p.y)
		_clear(c, tile, half + 3)
		if t >= start_t:
			_disc(c, tile, half, Defs.T.FAIRWAY)
		if s % 4 == 0:
			c.smooth(p.x, p.y, (half + 2) * Defs.TILE, 0.35)

	# green: level it, then give it a gentle tilt so putts break
	var gr := rng.randi_range(2, 3)
	for pass_i in 3:
		c.flatten(pin.x, pin.z, (gr + 2.5) * Defs.TILE, c.height_at(pin.x, pin.z), 0.7)
	var tilt_dir := rng.randf() * TAU
	var tilt := Vector2(cos(tilt_dir), sin(tilt_dir)) * rng.randf_range(0.008, 0.02)
	var reach := gr + 2
	for vy in range(pin_t.y - reach, pin_t.y + reach + 2):
		for vx in range(pin_t.x - reach, pin_t.x + reach + 2):
			if vx < 0 or vy < 0 or vx > c.w or vy > c.h:
				continue
			var off := Vector2(vx * Defs.TILE - pin.x, vy * Defs.TILE - pin.z)
			if off.length() <= (gr + 1.5) * Defs.TILE and not c._corner_is_locked(vx, vy):
				c.heights[vy * (c.w + 1) + vx] += tilt.dot(off)
	_disc(c, pin_t, gr, Defs.T.GREEN, true)

	# tee box on a small raised pad
	for pass_i in 2:
		c.flatten(tee.x, tee.z, 11.0, c.height_at(tee.x, tee.z) + 0.25, 0.8)
	_disc(c, tee_t, 1, Defs.T.TEE, true)

	# bunkers guard the green, and sometimes the landing area
	for k in rng.randi_range(1, 4 if sparse else 3):
		var ang := rng.randf() * TAU
		var bp := b + Vector2(cos(ang), sin(ang)) * (gr + 1.8) * Defs.TILE
		_disc(c, c.tile_of(bp.x, bp.y), 1, Defs.T.BUNKER)
	if length > 250.0:
		var t := rng.randf_range(0.5, 0.7)
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t) + perp * (half + 1.6) * Defs.TILE * (1.0 if rng.randf() < 0.5 else -1.0)
		_disc(c, c.tile_of(p.x, p.y), 1, Defs.T.BUNKER)

	# trees and flowers frame the hole
	if true:
		for s in steps:
			if rng.randf() < (0.07 if sparse else 0.3):
				var t := float(s) / steps
				var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
				p += perp * (half + rng.randf_range(2.5, 5.0)) * Defs.TILE * (1.0 if rng.randf() < 0.5 else -1.0)
				var tile := c.tile_of(p.x, p.y)
				if c.in_bounds(tile.x, tile.y):
					var i := tile.y * c.w + tile.x
					var tt := c.terrain[i]
					if (tt == Defs.T.ROUGH or tt == Defs.T.DEEP_ROUGH) and c.objects[i] == 0:
						c.objects[i] = Defs.O.PINE if rng.randf() < 0.35 else Defs.O.OAK
	var fl := tee_t + Vector2i(2 if perp.x > 0.0 else -2, 1)
	if c.in_bounds(fl.x, fl.y) and c.terrain[fl.y * c.w + fl.x] == Defs.T.ROUGH:
		c.objects[fl.y * c.w + fl.x] = Defs.O.FLOWERS

	c.revision += 1
	return c.add_hole(tee, pin)


static func _disc(c: Course, at: Vector2i, radius: int, t: int, force: bool = false) -> void:
	var r2 := (radius + 0.4) * (radius + 0.4)
	for ty in range(at.y - radius, at.y + radius + 1):
		for tx in range(at.x - radius, at.x + radius + 1):
			if not c.in_bounds(tx, ty):
				continue
			var dx := tx - at.x
			var dy := ty - at.y
			if dx * dx + dy * dy > r2:
				continue
			var i := ty * c.w + tx
			var cur := c.terrain[i]
			if cur == Defs.T.WATER or c.objects[i] == Defs.O.CLUBHOUSE:
				continue
			if not force and (cur == Defs.T.GREEN or cur == Defs.T.TEE or cur == Defs.T.BUNKER or cur == Defs.T.PATH):
				continue
			c.terrain[i] = t
			c.objects[i] = 0


static func _clear(c: Course, at: Vector2i, radius: int) -> void:
	for ty in range(at.y - radius, at.y + radius + 1):
		for tx in range(at.x - radius, at.x + radius + 1):
			if not c.in_bounds(tx, ty):
				continue
			var i := ty * c.w + tx
			if c.objects[i] != Defs.O.CLUBHOUSE:
				c.objects[i] = 0
			if c.terrain[i] == Defs.T.DEEP_ROUGH:
				c.terrain[i] = Defs.T.ROUGH


static func _blob(c: Course, at: Vector2i, radius: int, t: int, rng: RandomNumberGenerator) -> void:
	var wobble := rng.randf() * TAU
	for ty in range(at.y - radius - 1, at.y + radius + 2):
		for tx in range(at.x - radius - 1, at.x + radius + 2):
			var off := Vector2(tx - at.x, ty - at.y)
			var r := radius * (1.0 + 0.3 * sin(off.angle() * 3.0 + wobble))
			if off.length() <= r and c.in_bounds(tx, ty):
				var cur := c.terrain[ty * c.w + tx]
				if cur == Defs.T.ROUGH or cur == Defs.T.DEEP_ROUGH:
					c.set_terrain(tx, ty, t)


## A pond may sit beside a hole but not across its line of play, and not on
## the clubhouse lawn.
static func _pond_fits(c: Course, at: Vector2i, radius: int) -> bool:
	var p := Vector2((at.x + 0.5) * Defs.TILE, (at.y + 0.5) * Defs.TILE)
	var keep := (radius + 4.0) * Defs.TILE
	for hole in c.holes:
		var a := Vector2(hole.tee.x, hole.tee.z)
		var b := Vector2(hole.pin.x, hole.pin.z)
		if Ball._seg_dist(a, b, p) < keep:
			return false
		if p.distance_to(b) < keep + 3.0 * Defs.TILE or p.distance_to(a) < keep + 2.0 * Defs.TILE:
			return false
	for v in c.volcanoes:
		if p.distance_to(Vector2(float(v.x), float(v.z))) < float(v.radius) + keep:
			return false
	var ch := Vector2((c.clubhouse.x + 0.5) * Defs.TILE, (c.clubhouse.y + 0.5) * Defs.TILE)
	return p.distance_to(ch) > keep + 8.0 * Defs.TILE
