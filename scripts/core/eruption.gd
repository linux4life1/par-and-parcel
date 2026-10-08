class_name Eruption
extends RefCounted
## A live volcano. Most of the time it only smokes. Now and then it erupts:
## lava bombs rain down and leave craters and scorched ground, rivers of lava
## run downhill across the course, and when it is over the lava cools into
## bare rock. The map is permanently different afterwards.

signal started()
signal ended(summary: Dictionary)
signal bomb_landed(pos: Vector3)

enum S { QUIET, RUMBLING, ERUPTING, COOLING }

var sim: Sim
var state: int = S.QUIET
var timer := 0.0
var bombs: Array[Dictionary] = []    # {pos, vel, age}
var flows: Array[Dictionary] = []    # {tile, steps, t, dir, ride}
var fresh: Array[int] = []           # lava tiles laid by this eruption, oldest first
var volcano: Dictionary = {}
var summary := {}
var _bomb_t := 0.0
var _cool_t := 0.0


func _init(s: Sim) -> void:
	sim = s


func has_volcano() -> bool:
	return not sim.course.volcanoes.is_empty()


func active() -> bool:
	return state == S.RUMBLING or state == S.ERUPTING


## Begin the countdown to an eruption. False if there is no volcano or one
## is already going off.
func start(warning: float = 14.0) -> bool:
	if not has_volcano() or state == S.RUMBLING or state == S.ERUPTING:
		return false
	volcano = sim.course.volcanoes[sim.rng.randi() % sim.course.volcanoes.size()]
	state = S.RUMBLING
	timer = warning
	sim.toast.emit("The ground is shaking. The volcano is about to blow!", "bad")
	return true


func crater() -> Vector3:
	return Vector3(float(volcano.x), float(volcano.rim) + 2.0, float(volcano.z))


func step(dt: float) -> void:
	if state == S.QUIET:
		return
	_step_bombs(dt)
	match state:
		S.RUMBLING:
			timer -= dt
			if timer <= 0.0:
				_begin()
		S.ERUPTING:
			timer -= dt
			_bomb_t -= dt
			if _bomb_t <= 0.0 and timer > 2.0:
				_bomb_t = sim.rng.randf_range(0.35, 0.8)
				_launch()
			for f in flows:
				if int(f.steps) > 0:
					f.t = float(f.t) - dt
					if float(f.t) <= 0.0:
						_advance(f)
			if timer <= 0.0 and bombs.is_empty():
				_finish()
		S.COOLING:
			_cool_t -= dt
			if _cool_t <= 0.0:
				_cool_t = 1.2
				_cool_one()


func _begin() -> void:
	var course := sim.course
	state = S.ERUPTING
	timer = 26.0
	_bomb_t = 0.3
	summary = {"bombs": 0, "craters": 0, "trees": 0, "lava": 0, "hit": 0}
	sim.weather.ash = 1.0
	# hot ash settles on everything near the mountain
	var c := Vector2(float(volcano.x), float(volcano.z))
	for i in course.w * course.h:
		if Defs.T_GRASS[course.terrain[i]]:
			var p := Vector2((i % course.w + 0.5) * Defs.TILE, (i / course.w + 0.5) * Defs.TILE)
			if p.distance_squared_to(c) < 450.0 * 450.0:
				course.health[i] = maxf(0.0, course.health[i] - 0.12)
	# two or three rivers of lava set off down the mountain
	flows.clear()
	var base := sim.rng.randf() * TAU
	for k in sim.rng.randi_range(2, 3):
		var ang := base + k * TAU / 3.0 + sim.rng.randf_range(-0.5, 0.5)
		var r := float(volcano.crater_r) / Defs.TILE + 0.5
		var tx := int(c.x / Defs.TILE + cos(ang) * r)
		var ty := int(c.y / Defs.TILE + sin(ang) * r)
		if course.in_bounds(tx, ty):
			flows.append({
				"tile": ty * course.w + tx, "steps": sim.rng.randi_range(30, 52), "t": 0.5 + k * 0.4,
				"dir": ang, "ride": int(float(volcano.radius) / Defs.TILE - r),
			})
	sim.toast.emit("The volcano is erupting!", "bad")
	if not sim.course.volcanoes.is_empty():
		var vol: Dictionary = sim.course.volcanoes[0]
		sim.sound.emit("boom", Vector3(float(vol.x), 0.0, float(vol.z)), 1.0)
	sim.feed.say("eruption", null, {}, true, "County Weather", "CountyWeather")
	started.emit()


func _launch() -> void:
	var course := sim.course
	var rng := sim.rng
	var from := crater()
	var ang := rng.randf() * TAU
	var dist := float(volcano.radius) * 0.45 + 430.0 * pow(rng.randf(), 1.5)
	var size := course.size_m()
	var tx := clampf(from.x + cos(ang) * dist, 4.0, size.x - 4.0)
	var tz := clampf(from.z + sin(ang) * dist, 4.0, size.y - 4.0)
	var target := course.on_ground(tx, tz)
	var tf := rng.randf_range(4.5, 8.0)
	var vel := Vector3((target.x - from.x) / tf, (target.y - from.y) / tf + 0.5 * 9.81 * tf, (target.z - from.z) / tf)
	bombs.append({"pos": from, "prev": from, "vel": vel, "age": 0.0})


func _step_bombs(dt: float) -> void:
	var course := sim.course
	var i := 0
	while i < bombs.size():
		var b := bombs[i]
		var vel: Vector3 = b.vel
		var pos: Vector3 = b.pos
		b.prev = pos
		vel.y -= 9.81 * dt
		pos += vel * dt
		b.vel = vel
		b.pos = pos
		b.age = float(b.age) + dt
		if float(b.age) > 0.6 and pos.y <= course.height_at(pos.x, pos.z):
			bombs.remove_at(i)
			_impact(course.on_ground(pos.x, pos.z))
		else:
			i += 1


func _protected(tx: int, ty: int) -> bool:
	# Leave the cup and the tee markers themselves alone so a hole survives.
	for hole in sim.course.holes:
		var aim := hole.aim_at()
		var pt := sim.course.tile_of(aim.x, aim.z)
		var tt := sim.course.tile_of(hole.tee.x, hole.tee.z)
		if (absi(pt.x - tx) <= 1 and absi(pt.y - ty) <= 1) or (tt.x == tx and tt.y == ty):
			return true
	return false


## A lava bomb lands: a crater, scorched ground, burnt trees, and anyone
## standing too close gets the fright of their life.
func _impact(p: Vector3) -> void:
	var course := sim.course
	var tile := course.tile_of(p.x, p.z)
	if not course.in_bounds(tile.x, tile.y):
		return
	summary.bombs = int(summary.bombs) + 1
	var i0 := tile.y * course.w + tile.x
	if course.hot[i0] == 0 and course.terrain[i0] != Defs.T.WATER:
		if sim.undo != null:
			sim.undo.clear()
		course.guard = false
		course.sculpt(p.x, p.z, 9.0, -1.1)
		var burnt := false
		for ty in range(tile.y - 2, tile.y + 3):
			for tx in range(tile.x - 2, tile.x + 3):
				if not course.in_bounds(tx, ty):
					continue
				var i := ty * course.w + tx
				var near := absi(tx - tile.x) <= 1 and absi(ty - tile.y) <= 1
				var scorched := 0.45
				if near:
					scorched = 0.0
				course.health[i] *= scorched
				if not near:
					continue
				var o := course.objects[i]
				if o != 0 and not Defs.O_BUILDING[o]:
					if Defs.is_tree(o):
						summary.trees = int(summary.trees) + 1
					course.objects[i] = 0
					course.closed[i] = 0
					course.objects_touched(i)
					burnt = true
				if course.terrain[i] != Defs.T.WATER and course.objects[i] == 0 and not _protected(tx, ty):
					if (tx == tile.x and ty == tile.y) or sim.rng.randf() < 0.6:
						course.terrain[i] = Defs.T.ASH
						course.weeds[i] = 0.0
						course.pests[i] = 0.0
		if sim.rng.randf() < 0.22 and course.objects[i0] == 0 and not _protected(tile.x, tile.y):
			course.terrain[i0] = Defs.T.WATER
			fresh.append(i0)
			summary.lava = int(summary.lava) + 1
		summary.craters = int(summary.craters) + 1
		course.guard = true
		course.revision += 1
		course.tiles_changed.emit(Rect2i(tile.x - 3, tile.y - 3, 7, 7))
		if burnt:
			course.objects_changed.emit()
	for g in sim.visitors.golfers:
		if g.pos.distance_squared_to(p) < 8.0 * 8.0 and g.hit_t <= 0.0:
			summary.hit = int(summary.hit) + 1
			sim.visitors.lava_scare(g, p)
	for s in sim.crew.members:
		if s.pos.distance_squared_to(p) < 8.0 * 8.0:
			s.hit_t = 3.0
	sim.popup.emit(p, "BOOM!", "hit")
	sim.sound.emit("bomb", p, 1.0)
	bomb_landed.emit(p)


## Move one river of lava on by a tile: straight down the cone first, then
## wherever is lowest.
func _advance(f: Dictionary) -> void:
	var course := sim.course
	var w := course.w
	var cur: int = f.tile
	var cx := cur % w
	var cy := cur / w
	var best := -1
	if int(f.ride) > 0:
		f.ride = int(f.ride) - 1
		var nx := cx + int(round(cos(float(f.dir))))
		var ny := cy + int(round(sin(float(f.dir))))
		f.dir = float(f.dir) + sim.rng.randf_range(-0.12, 0.12)
		if course.in_bounds(nx, ny):
			best = ny * w + nx
	else:
		var best_h := course.tile_center(cx, cy).y + 0.15
		var options: Array[int] = []
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var nx := cx + ox
				var ny := cy + oy
				if (ox == 0 and oy == 0) or not course.in_bounds(nx, ny):
					continue
				var ni := ny * w + nx
				if course.terrain[ni] == Defs.T.WATER or Defs.O_BUILDING[course.objects[ni]] or _protected(nx, ny):
					continue
				var hgt := course.tile_center(nx, ny).y
				if hgt < best_h:
					options.append(ni)
					if hgt < best_h - 0.3:
						best_h = hgt + 0.3
						best = ni
		if best < 0 and not options.is_empty():
			best = options[sim.rng.randi() % options.size()]
	f.t = 0.9
	if best < 0:
		f.steps = 0
		return
	f.tile = best
	f.steps = int(f.steps) - 1
	if course.terrain[best] == Defs.T.WATER:
		return
	if sim.undo != null:
		sim.undo.clear()
	if course.objects[best] != 0:
		if Defs.is_tree(course.objects[best]):
			summary.trees = int(summary.trees) + 1
		course.objects[best] = 0
		course.objects_touched(best)
		course.objects_changed.emit()
	course.terrain[best] = Defs.T.WATER
	course.weeds[best] = 0.0
	course.pests[best] = 0.0
	fresh.append(best)
	summary.lava = int(summary.lava) + 1
	course.revision += 1
	var bx := best % w
	var by := best / w
	course.tiles_changed.emit(Rect2i(bx - 1, by - 1, 3, 3))
	var p := course.tile_center(bx, by)
	for g in sim.visitors.golfers:
		if g.pos.distance_squared_to(p) < 7.0 * 7.0 and g.hit_t <= 0.0:
			sim.visitors.lava_scare(g, p)


func _finish() -> void:
	state = S.COOLING
	_cool_t = 40.0
	flows.clear()
	sim.stats.eruptions = int(sim.stats.get("eruptions", 0)) + 1
	sim.buzz += 8.0
	sim.skills.add_xp("manager", 4)
	sim.toast.emit("The eruption is over: %d craters, %d tiles under fresh lava, %d trees burned. The lava will cool into rock." % [
		int(summary.craters), int(summary.lava), int(summary.trees)], "info")
	sim.feed.say("eruption_end", null, {}, true)
	ended.emit(summary)


func _cool_one() -> void:
	var course := sim.course
	if fresh.is_empty():
		state = S.QUIET
		return
	var i: int = fresh.pop_front()
	if course.terrain[i] != Defs.T.WATER:
		return
	if sim.undo != null:
		sim.undo.clear()
	course.terrain[i] = Defs.T.ROCK
	course.revision += 1
	course.tiles_changed.emit(Rect2i(i % course.w - 1, i / course.w - 1, 3, 3))
