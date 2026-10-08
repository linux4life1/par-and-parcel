class_name ShotAI
extends RefCounted
## Decides where a computer golfer aims and with which club, then swings
## with errors that depend on their ability, their clubs and the lie.

const ANGLES: Array[float] = [0.0, -0.1, 0.1, -0.2, 0.2, -0.32, 0.32, -0.46, 0.46, -0.62, 0.62, -0.8, 0.8]
## What a lie costs, in metres of the hole's cost field: about 150 m is a
## stroke for an average golfer, so these are the strokes a lie adds.
const COST_ROUGH := 26.0
const COST_DEEP := 65.0
const COST_BUNKER := 75.0
const COST_WATER := 240.0
const COST_OUT := 300.0
const COST_TREE := 48.0
const GAIN_GREEN := 10.0
const REACH: Array[float] = [1.0, 0.9, 0.78, 0.64, 0.5]

static var _scratch := Ball.new()
static var calm := false      # ignore wind: used when a hole is being rated


static func plan(sim: Sim, g: Golfer, hole: Hole) -> Dictionary:
	var course := sim.course
	var p := g.ball.pos
	var lie := course.terrain_at(p.x, p.z)
	if lie < 0:
		lie = Defs.T.ROUGH
	var p2 := Vector2(p.x, p.z)
	var to_pin := Vector2(hole.aim_at().x - p.x, hole.aim_at().z - p.z)
	var d := to_pin.length()
	if Defs.is_green(lie):
		return _plan_putt(sim, g, hole)

	var gear := sim.gear
	var base_ang := to_pin.angle()
	var maxd := gear.max_total(g, lie, course)
	var dists: Array[float] = []
	if d <= maxd:
		dists.append(d)
	for f in REACH:
		var r := maxd * f
		if r < d - 12.0:
			dists.append(r)
	if dists.is_empty():
		dists.append(minf(d, maxd))
	var sig := g.spread() * Lie.terrain_spread(lie)
	# How much trouble weighs on the choice: a thoughtful golfer plays for
	# the fairway, a duffer aims at the flag and hopes.
	var care := lerpf(0.55, 1.35, g.imagination)
	var best_cost := INF
	var best_target := p2 + to_pin.normalized() * dists[0]
	for r in dists:
		var at_pin := is_equal_approx(r, d)
		for a in ANGLES:
			if at_pin and a != 0.0:
				continue
			var ang := base_ang + a
			var dir := Vector2(cos(ang), sin(ang))
			var perp := Vector2(-dir.y, dir.x)
			var lat := r * sig * 1.3
			var lon := r * 0.07
			var c := _spot_cost(sim, hole, p2 + dir * r, care) * 2.0
			c += _spot_cost(sim, hole, p2 + dir * r + perp * lat, care)
			c += _spot_cost(sim, hole, p2 + dir * r - perp * lat, care)
			c += _spot_cost(sim, hole, p2 + dir * (r + lon), care)
			c += _spot_cost(sim, hole, p2 + dir * (r - lon), care)
			c /= 6.0
			c += _line_block(course, p2, dir, r) * (1.0 - 0.3 * g.imagination)
			if c < best_cost:
				best_cost = c
				best_target = p2 + dir * r

	var aim := best_target - p2
	var dist := aim.length()
	var heading := aim.angle()
	var pick := gear.pick(g, dist, lie, course)
	var ci: int = pick[0]
	var speed: float = pick[1]
	# Golfers allow for the lie, the wind, the slope and wet ground: the
	# better ones for nearly all of it, and even a novice knows a ball in
	# the rough will not behave.
	if g.imagination > 0.05:
		var comp := clampf(0.35 + 0.65 * g.imagination, 0.0, 1.0)
		var rest := predict(sim, g, ci, speed, heading, true, Lie.blend(Lie.read(sim, g, heading)))
		var miss := Vector2(rest.x - best_target.x, rest.z - best_target.y)
		if miss.length() > dist * 0.4:
			miss = miss.normalized() * dist * 0.4
		aim = best_target - miss * comp - p2
		heading = aim.angle()
		pick = gear.pick(g, aim.length(), lie, course)
		ci = pick[0]
		speed = pick[1]
	return {"putt": false, "ci": ci, "speed": speed, "heading": heading, "dist": dist,
		"target": Vector3(best_target.x, course.height_at(best_target.x, best_target.y), best_target.y)}


## What finishing a shot here would cost: the way left to the pin, plus
## what the lie would add to the next shot. `care` scales the trouble.
static func _spot_cost(sim: Sim, hole: Hole, pt: Vector2, care: float = 1.0) -> float:
	var course := sim.course
	var i := course.index_at(pt.x, pt.y)
	if i < 0 or course.locked[i] != 0:
		return hole.field_at(course, pt.x, pt.y, sim.time) + COST_OUT * maxf(care, 0.8)
	var f := hole.field_at(course, pt.x, pt.y, sim.time)
	match course.terrain[i]:
		Defs.T.WATER, Defs.T.STREAM:
			f += COST_WATER * maxf(care, 0.8)
		Defs.T.WASTE:
			f += _waste_trouble(sim) * care
		Defs.T.BUNKER:
			f += COST_BUNKER * care
		Defs.T.DEEP_ROUGH:
			f += COST_DEEP * care
		Defs.T.ROUGH:
			f += COST_ROUGH * care
		Defs.T.ROCK, Defs.T.ASH:
			f += COST_DEEP * care
		Defs.T.GREEN, Defs.T.FAST_GREEN:
			f -= GAIN_GREEN
	if Defs.is_tree(course.objects[i]):
		f += COST_TREE * care
	return f


## Used only when data/ground.json has no trouble number. The test checks
## that it still matches the file.
const WASTE_TROUBLE_FALLBACK := 48.0


## What a waste area adds to a landing, from data/ground.json. It sits
## between the rough and a bunker, and it is not priced as water.
static func _waste_trouble(sim: Sim) -> float:
	var row: Dictionary = sim.db.ground.get("waste", {})
	if row.has("trouble"):
		return float(row["trouble"])
	return WASTE_TROUBLE_FALLBACK


## Penalty for trees standing in the way. A low ball pays the full price;
## one well above the canopy pays a little, in case the branch is taller
## than the guess. Carry and apex are a rough arc, not the real flight.
static func _line_block(course: Course, from: Vector2, dir: Vector2, length: float) -> float:
	var c := 0.0
	var carry := maxf(length * 0.87, 1.0)
	var apex := carry * 0.12
	var s := 6.0
	while s < length:
		var q := from + dir * s
		var i := course.index_at(q.x, q.y)
		if i >= 0 and Defs.is_tree(course.objects[i]):
			var u := clampf(s / carry, 0.0, 1.0)
			var h := 4.0 * apex * u * (1.0 - u)
			c += 22.0 if h < 10.0 else 4.0
		s += Defs.TILE
	return c


## Where a perfectly struck shot would finish.
## `shape` can bend the shot: keys side, loft, lift, spin, wind (multipliers
## for loft, lift and wind; added amounts for side and spin), and from the
## lie loft_add (radians) and spin_mul. See Lie.blend.
static func predict(sim: Sim, g: Golfer, ci: int, speed: float, heading: float, use_wind: bool, shape: Dictionary = {}) -> Vector3:
	var c: Dictionary = sim.db.clubs[ci]
	var b := _scratch
	b.set_def(g.ball.def)
	b.lava = g.ball.lava
	b.dodge = 0.0
	b.place(g.ball.pos)
	b.shot_wind = float(g.brand_of(c.cat).get("wind", 1.0)) * float(shape.get("wind", 1.0))
	b.launch(speed, heading, maxf(deg_to_rad(c.loft) * float(shape.get("loft", 1.0)) + float(shape.get("loft_add", 0.0)), 0.03),
		float(c.lift) * float(shape.get("lift", 1.0)), float(shape.get("side", 0.0)),
		(float(c.spin) + float(shape.get("spin", 0.0))) * float(shape.get("spin_mul", 1.0)))
	var wind := sim.weather.wind_vec() if (use_wind and not calm) else Vector3.ZERO
	var n := 0
	while b.moving() and n < 1800:
		b.step(1.0 / 60.0, sim.course, wind, Vector3.ZERO, false)
		n += 1
	return b.pos


static func predict_putt(sim: Sim, g: Golfer, speed: float, heading: float) -> Vector3:
	var b := _scratch
	b.set_def(g.ball.def)
	b.place(g.ball.pos)
	b.launch(speed, heading, 0.0, 0.0, 0.0, 0.0)
	var n := 0
	while b.moving() and n < 1500:
		b.step(1.0 / 60.0, sim.course, Vector3.ZERO, Vector3.ZERO, false)
		n += 1
	return b.pos


## Pace a putt to die just past the hole on this green.
static func putt_speed(sim: Sim, g: Golfer, from: Vector3, to: Vector3, over: float = 0.3) -> float:
	var course := sim.course
	var ti := course.index_at(from.x, from.z)
	var wetv := 0.2
	if ti >= 0:
		wetv = course.wet[ti] * g.ball.m_wet
	var ground := Defs.T.GREEN
	if ti >= 0 and Defs.is_green(int(course.terrain[ti])):
		ground = int(course.terrain[ti])
	var decel: float = course.roll_decel(ground) * (1.0 + 1.6 * wetv) / g.ball.m_roll
	if wetv < 0.12:
		decel *= 0.88
	var d := Vector2(to.x - from.x, to.z - from.z).length()
	return sqrt(maxf(0.15, 2.0 * (decel * (d + over) + Ball.G * (to.y - from.y))))


static func _plan_putt(sim: Sim, g: Golfer, hole: Hole) -> Dictionary:
	var p := g.ball.pos
	var to := Vector2(hole.aim_at().x - p.x, hole.aim_at().z - p.z)
	var d := to.length()
	var heading := to.angle()
	var over := 0.3
	var v := putt_speed(sim, g, p, hole.aim_at(), over)
	var read := 0.3 + 0.7 * g.putting
	for i in 2:
		var rest := predict_putt(sim, g, v, heading)
		var r := Vector2(rest.x - p.x, rest.z - p.z)
		if r.length() < 0.05:
			v *= 1.3
			continue
		heading -= wrapf(r.angle() - to.angle(), -PI, PI) * read
		var along := r.dot(to / maxf(d, 0.01))
		var ratio := clampf((d + over) / maxf(along, 0.2), 0.5, 1.8)
		v = lerpf(v, v * sqrt(ratio), read)
	return {"putt": true, "ci": sim.gear.putter_i, "speed": v, "heading": heading, "dist": d, "target": hole.aim_at()}


## Swing: turn a plan into a moving ball, with human error.
## The sound of the club this golfer is about to hit.
static func strike_sound(sim: Sim, g: Golfer) -> String:
	if g.plan.get("putt", false):
		return "putt"
	if g.ball.struck_from == Defs.T.BUNKER:
		return "strike_sand"
	match str(sim.db.clubs[int(g.plan.get("ci", 0))].cat):
		"woods":
			return "drive"
		"wedges":
			return "chip"
		"putter":
			return "putt"
	return "iron"


## Play the sound of the swing just made: the club, and the ground it came off.
static func emit_strike(sim: Sim, g: Golfer, power: float = 1.0) -> void:
	sim.sound.emit(strike_sound(sim, g), g.pos, power)
	var from := g.ball.struck_from
	if not g.plan.get("putt", false) and (from == Defs.T.ROUGH or from == Defs.T.DEEP_ROUGH):
		sim.sound.emit("strike_rough", g.pos, power)


static func strike(sim: Sim, g: Golfer) -> void:
	var rng := sim.rng
	var pl := g.plan
	var c: Dictionary = sim.db.clubs[pl.ci]
	var brand := g.brand_of(c.cat)
	var b := g.ball
	var speed: float = pl.speed
	var heading: float = pl.heading
	g.mishit = false
	# in the dark, away from any light, everything gets harder
	# (the test golfers who rate a new hole always play it in daylight)
	var blind := 0.0 if g.kind == "lab" else 1.0 - sim.sight_at(b.pos)
	if pl.putt:
		var hs := lerpf(0.06, 0.014, g.putting) / float(brand.get("putt", 1.0)) * (1.0 + blind * 0.35)
		speed *= 1.0 + rng.randfn(0.0, lerpf(0.16, 0.035, g.putting))
		b.shot_wind = 1.0
		b.struck_from = Defs.T.GREEN
		b.launch(speed, heading + rng.randfn(0.0, hs), 0.0, 0.0, 0.0, 0.0)
	else:
		var lie := maxi(sim.course.terrain_at(b.pos.x, b.pos.z), 0)
		# how the ball is sitting: see Lie
		var lr := Lie.read(sim, g, heading)
		var sit_power := float(lr.power)
		if sit_power < 1.0:
			# a golfer who reads the lie swings harder to make up for it
			speed = minf(speed / lerpf(1.0, sit_power, 0.75 * g.imagination), sim.gear.full_speed(g, pl.ci) * g.lie_power(lie, sim.course))
		speed *= sit_power
		var bs: float = brand.get("spread", 1.0)
		var sig := g.spread() * bs * Lie.terrain_spread(lie) * float(lr.spread) * (1.0 + blind * 0.45)
		speed *= 1.0 + rng.randfn(0.0, lerpf(0.08, 0.02, g.accuracy))
		heading += rng.randfn(0.0, sig)
		var side := rng.randfn(0.0, lerpf(0.06, 0.01, g.accuracy)) * bs + float(lr.side)
		var loft := maxf(deg_to_rad(c.loft) + float(lr.loft), 0.03)
		var forgive: float = brand.get("forgive", 1.0)
		if rng.randf() < lerpf(0.09, 0.004, g.accuracy) * forgive * float(lr.mishit):
			g.mishit = true
			match rng.randi() % 3:
				0:   # fat
					speed *= rng.randf_range(0.3, 0.55)
					loft *= 0.7
				1:   # shank
					heading += (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.45, 0.8)
					speed *= 0.7
				2:   # topped
					loft *= 0.15
					speed *= 0.6
		if g.clean_ball:
			heading = lerpf(pl.heading, heading, 0.94)
		b.shot_wind = brand.get("wind", 1.0)
		b.dodge = g.imagination * 0.45
		b.air_seed = g.air_phase(sim.time)
		b.struck_from = lie
		b.launch(speed, heading, loft, float(c.lift) * float(lr.lift), side, float(c.spin) * float(lr.spin))
	g.strokes += 1
