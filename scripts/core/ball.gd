class_name Ball
extends RefCounted
## A golf ball and its physics: drag and lift in the air, bounce on landing,
## and a roll that follows the slope. Wet ground kills bounce and roll.
## Backspin bites on landing and can pull the ball back, sidespin kicks it
## sideways, and the air it flies through is the wind as it really blows:
## stronger aloft, slack behind trees, lifted over rising ground.

enum S { REST, FLIGHT, ROLL, HOLED, WATER, OOB }
## TREE is a brush with branches or a bush; HIT is a ricochet off something solid.
enum E { NONE, LANDED, STOPPED, HOLED, WATER, OOB, TREE, HIT }

const KD := 0.018719      # 0.5 * air density * ball area / ball mass
const G := 9.81
const CUP_R := 0.07       # a little wider than a real cup, for fun
const CUP_SPEED := 1.9    # fastest roll the cup will swallow
const RADIUS := 0.0213    # of the ball itself
const MAX_HITS := 14      # after this many ricochets in one shot the ball just drops
const SPIN_FULL := 30.0   # the most backspin a clean full swing puts on, as the speed of the ball's surface in m/s
const SPIN_BITE := 0.3    # share of that speed a clean bounce takes off the ball's forward speed
const SPIN_BACK := 1.5    # fastest spin can pull a ball back, m/s: a couple of yards on a flat green

var pos := Vector3.ZERO
var prev := Vector3.ZERO
var vel := Vector3.ZERO
var state: int = S.REST
var lift := 0.0           # backspin lift coefficient
var side := 0.0           # sidespin: positive curves right
var spin := 0.0           # 0..1, how much backspin the shot was given
var back := 0.0           # backspin still on the ball, as surface speed in m/s. Negative is topspin.
var spin_fwd := Vector2.RIGHT   # the way the ball was travelling when the spin last gripped
var plugged := false      # buried in the sand where it landed
var air_seed := -1.0      # set for a real shot: the eddies it will meet. Below zero the air is steady.
var struck_from := 1      # the ground the last shot was played off (Defs.T)
var air_time := 0.0
var move_time := 0.0
var bounces := 0
var start := Vector3.ZERO
var carry := Vector3.ZERO
var last_land := Vector3.ZERO
var skips := 0
var tree_tile := -1       # tile of the last tree or bush the ball got tangled in
var hits := 0             # ricochets off solid things this shot
var hit_obj := 0          # what it last bounced off (Defs.O), the tile it stands on, and what it is made of
var hit_tile := -1
var hit_mat := ""
var hit_speed := 0.0      # how hard it struck, in m/s
var def: Dictionary = {}
var owner: Golfer = null
# modifiers from the ball type
var m_speed := 1.0
var m_wind := 1.0
var m_roll := 1.0
var m_bounce := 1.0
var m_wet := 1.0
var m_cup := 1.0
var m_sand := 1.0
var m_spin := 1.0
var m_curve := 1.0
var shot_wind := 1.0     # wind share let through by the club brand
var lava := false        # the hazard is lava: nothing skips across it
var dodge := 0.0         # chance a well-shaped shot threads through a tree


func set_def(d: Dictionary) -> void:
	def = d
	m_speed = d.get("speed", 1.0)
	m_wind = d.get("wind", 1.0)
	m_roll = d.get("roll", 1.0)
	m_bounce = d.get("bounce", 1.0)
	m_wet = d.get("wet", 1.0)
	m_cup = d.get("cup", 1.0)
	m_sand = d.get("sand", 1.0)
	m_spin = d.get("spin", 1.0)
	m_curve = d.get("curve", 1.0)


func place(p: Vector3) -> void:
	pos = p
	prev = p
	vel = Vector3.ZERO
	state = S.REST


func moving() -> bool:
	return state == S.FLIGHT or state == S.ROLL


## Heading is the angle in the ground plane: direction = (cos, 0, sin).
func launch(speed: float, heading: float, loft: float, lift_c: float, side_c: float, spin_c: float) -> void:
	start = pos
	prev = pos
	last_land = pos
	air_time = 0.0
	move_time = 0.0
	bounces = 0
	tree_tile = -1
	hits = 0
	hit_obj = 0
	hit_tile = -1
	hit_mat = ""
	hit_speed = 0.0
	skips = int(def.get("skips", 0))
	lift = lift_c
	side = side_c * m_curve
	spin = clampf(spin_c * m_spin, 0.0, 1.0)
	speed *= m_speed
	plugged = false
	spin_fwd = Vector2(cos(heading), sin(heading))
	# a harder swing puts more spin on; a half shot much less
	# and spin builds faster than loft: a wedge has far more than a driver
	var sc := clampf(spin_c * m_spin, -0.5, 1.25)
	back = signf(sc) * pow(absf(sc), 1.5) * SPIN_FULL * clampf(speed / 36.0, 0.2, 1.15) if loft >= 0.01 else 0.0
	if loft < 0.01:
		vel = Vector3(cos(heading), 0.0, sin(heading)) * speed
		state = S.ROLL
	else:
		var ch := cos(loft)
		vel = Vector3(cos(heading) * ch, sin(loft), sin(heading) * ch) * speed
		pos.y += 0.03
		state = S.FLIGHT


func step(dt: float, course: Course, wind: Vector3, pin: Vector3, has_pin: bool) -> int:
	prev = pos
	if state == S.FLIGHT:
		return _fly(dt, course, wind, pin, has_pin)
	if state == S.ROLL:
		return _roll(dt, course, pin, has_pin)
	return E.NONE


func _fly(dt: float, course: Course, wind: Vector3, pin: Vector3, has_pin: bool) -> int:
	air_time += dt
	move_time += dt
	var ti0 := course.index_at(pos.x, pos.z)
	var rel := vel - _air(course, ti0, wind)
	var sp := rel.length()
	var acc := Vector3(0.0, -G, 0.0)
	if sp > 0.01:
		acc -= rel * (KD * (0.20 + 0.45 * lift) * sp)
		var vh := rel / sp
		var right := vh.cross(Vector3.UP)
		var rl := right.length()
		if rl > 0.001:
			right /= rl
			acc += (right.cross(vh) * lift + right * side) * (KD * sp * sp)
	vel += acc * dt
	pos += vel * dt
	var decay := 1.0 - dt * 0.12
	lift *= decay
	side *= decay
	back *= 1.0 - dt * 0.04

	var ti := course.index_at(pos.x, pos.z)
	var gh := course.height_at(pos.x, pos.z)
	if ti < 0:
		if pos.y <= gh or move_time > 30.0:
			pos.y = maxf(pos.y, gh)
			state = S.OOB
			vel = Vector3.ZERO
			return E.OOB
		return E.NONE
	var t: int = course.terrain[ti]
	if t != Defs.T.WATER:
		last_land = pos

	# anything solid in the way, and any foliage to get through
	var sol := course.solids
	var here: Variant = sol.bucket(ti)
	var behind: Variant = sol.bucket(ti0) if (ti0 != ti and ti0 >= 0) else null
	if here != null or behind != null:
		var shape: Solids.Shape = null
		var at := 2.0
		var n := Vector3.UP
		if here != null:
			shape = sol.sweep(here, prev, pos, RADIUS)
			if shape != null:
				at = sol.hit_t
				n = sol.hit_n
		if behind != null:
			var other := sol.sweep(behind, prev, pos, RADIUS)
			if other != null and sol.hit_t < at:
				shape = other
				at = sol.hit_t
				n = sol.hit_n
		if shape != null:
			return _ricochet(shape, prev.lerp(pos, at), n)
		if here != null:
			var lf := sol.leaves(here, pos)
			if lf != null and _through_leaves(lf, dt):
				return E.TREE
	if move_time > 40.0:
		vel = Vector3(0.0, minf(vel.y, -2.0), 0.0)

	if pos.y > gh:
		return E.NONE

	# touchdown
	pos.y = gh
	bounces += 1
	var ev := E.NONE
	if bounces == 1:
		carry = pos
		ev = E.LANDED
	# Land that is not the club's is out of bounds, but only a ball that
	# comes to rest there is lost: it may yet bounce or roll back in.
	if t == Defs.T.WATER:
		if course.locked[ti] != 0:
			state = S.OOB
			vel = Vector3.ZERO
			return E.OOB
		var flat := Vector2(vel.x, vel.z).length()
		if skips > 0 and not lava and flat > 9.0 and absf(vel.y) < flat * 0.9:
			skips -= 1
			vel = Vector3(vel.x * 0.72, absf(vel.y) * 0.45 + 1.5, vel.z * 0.72)
			return ev
		state = S.WATER
		vel = Vector3.ZERO
		return E.WATER
	var wetv := course.wet[ti] * m_wet
	var n := course.normal_at(pos.x, pos.z)
	var vn := vel.dot(n)
	var vt := vel - n * vn
	if wetv > 0.85 and vn < -9.0:
		# plugged in soggy ground
		_stop(course)
		return E.OOB if state == S.OOB else E.STOPPED
	if t == Defs.T.BUNKER and bounces == 1 and vn < -14.0 and _noise(pos * 1.3) < 0.28 + 0.4 * wetv:
		# dropped out of the sky into soft sand: a fried egg
		plugged = true
		vel = Vector3.ZERO
		back = 0.0
		state = S.ROLL
		return ev
	var e: float = Defs.T_BOUNCE[t] * m_bounce * (1.0 - 0.7 * wetv)
	var keep: float = Defs.T_KEEP[t] * (1.0 - 0.45 * wetv)
	if wetv < 0.12:
		e *= 1.12
		keep = minf(keep * 1.06, 0.95)
	var out_n := -vn * e
	# The spin is about an axis set when the ball was struck: follow the ball
	# while it still travels forward, but not once the spin has turned it round.
	var flat_v := Vector2(vt.x, vt.z)
	if flat_v.length_squared() > 0.0025 and flat_v.dot(spin_fwd) >= 0.0:
		spin_fwd = flat_v.normalized()
	if absf(back) > 0.05:
		var f3 := Vector3(spin_fwd.x, 0.0, spin_fwd.y)
		f3 = (f3 - n * f3.dot(n)).normalized()
		var s := vt.dot(f3)
		var across := vt - f3 * s
		# The spinning ball grips the turf. Off a green the first bounce
		# skids; later ones bite. Only short grass lets a ball come back.
		var bite: float = Defs.T_GRIP[t] * (1.0 - 0.35 * wetv)
		if bounces == 1:
			bite *= 0.8 if t == Defs.T.GREEN else 0.55
		var s2 := s * keep - back * SPIN_BITE * bite
		var short_grass := t == Defs.T.GREEN or t == Defs.T.FAIRWAY or t == Defs.T.TEE
		s2 = maxf(s2, -SPIN_BACK if short_grass else minf(s * keep, 0.0))
		back *= 1.0 - 0.6 * bite
		vel = across * keep + f3 * s2 + n * out_n
	else:
		vel = vt * keep + n * out_n
	if absf(side) > 0.002:
		# Sidespin kicks the ball the way it was curving. A shot that was
		# all but straight lands straight.
		if bounces == 1 and absf(side) > 0.012:
			var bend := clampf((side - signf(side) * 0.012) * 6.0, -0.25, 0.25)
			vel = Vector3(vel.x * cos(bend) - vel.z * sin(bend), vel.y, vel.x * sin(bend) + vel.z * cos(bend))
		side *= 0.3
	if t == Defs.T.ROCK:
		# bare rock sends the ball anywhere
		var kick := (_noise(pos) - 0.5) * 1.6
		vel = Vector3(vel.x * cos(kick) - vel.z * sin(kick), vel.y, vel.x * sin(kick) + vel.z * cos(kick))
	if has_pin and Vector2(pos.x - pin.x, pos.z - pin.z).length() < CUP_R * m_cup:
		return _hole_out(pin)
	if out_n < 1.2:
		vel -= n * vel.dot(n)
		state = S.ROLL
	return ev


func _roll(dt: float, course: Course, pin: Vector3, has_pin: bool) -> int:
	move_time += dt
	var ti := course.index_at(pos.x, pos.z)
	if ti < 0:
		state = S.OOB
		vel = Vector3.ZERO
		return E.OOB
	var t: int = course.terrain[ti]
	if t == Defs.T.WATER:
		state = S.OOB if course.locked[ti] != 0 else S.WATER
		vel = Vector3.ZERO
		return E.OOB if state == S.OOB else E.WATER
	if course.locked[ti] == 0:
		last_land = pos
	var wetv := course.wet[ti] * m_wet
	var decel: float = Defs.T_DECEL[t] * (1.0 + 1.6 * wetv) / m_roll
	decel *= 1.0 + course.weeds[ti] * 0.8
	if wetv < 0.12:
		decel *= 0.88
	var g := course.gradient_at(pos.x, pos.z)
	var sa := g * (-G / (1.0 + g.length_squared()))
	var hv := Vector2(vel.x, vel.z)
	if absf(back) > 0.05:
		# Whatever spin is left keeps dragging at the ball until it has
		# rolled off. On short grass it can bring the ball back.
		var short_grass := t == Defs.T.GREEN or t == Defs.T.FAIRWAY or t == Defs.T.TEE
		if back < 0.0 or hv.dot(spin_fwd) > (-SPIN_BACK if short_grass else 0.3):
			sa -= spin_fwd * (back * 2.4 * Defs.T_GRIP[t])
		back *= exp(-dt * 3.0)
	if course.pests[ti] > 0.4:
		# pest mounds knock a rolling ball off line
		var jig := (_noise(pos) - 0.5) * 6.0 * dt
		hv = hv.rotated(jig)
	var sp := hv.length()
	if sp < 0.12:
		if sa.length() <= decel * 0.85 or move_time > 40.0:
			return _stop(course)
		hv += sa * dt
	else:
		var nv := hv + (sa - hv * (decel / sp)) * dt
		if nv.dot(hv) <= 0.0 and sa.length() <= decel:
			return _stop(course)
		hv = nv
	if move_time > 45.0:
		return _stop(course)
	var a := Vector2(pos.x, pos.z)
	var b := a + hv * dt
	var ev := E.NONE
	var sol := course.solids
	var near: Variant = sol.bucket(course.index_at(b.x, b.y))
	if near != null:
		var y := pos.y + RADIUS
		var shape := sol.sweep(near, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), RADIUS)
		if shape != null and absf(sol.hit_n.y) < 0.6:
			var n2 := Vector2(sol.hit_n.x, sol.hit_n.z).normalized()
			var into := hv.dot(n2)
			if into < 0.0:
				_note_hit(shape, -into)
				hv = (hv - n2 * into) * shape.keep - n2 * (into * shape.bounce * 0.8)
				ev = E.HIT
			b = a.lerp(b, sol.hit_t) + n2 * 0.03
			sp = hv.length()
		else:
			var lf := sol.leaves(near, Vector3(b.x, y + 0.12, b.y))
			if lf != null and lf.thick > 0.4:
				# a bush swallows a rolling ball
				hv *= exp(-dt * 9.0)
				tree_tile = lf.owner
	if has_pin:
		var d := _seg_dist(a, b, Vector2(pin.x, pin.z))
		if d < CUP_R * m_cup and sp < CUP_SPEED * (0.8 + 0.2 * m_cup):
			return _hole_out(pin)
	pos.x = b.x
	pos.z = b.y
	pos.y = course.height_at(pos.x, pos.z)
	vel = Vector3(hv.x, 0.0, hv.y)
	return ev


## Bounce off something solid: speed into the surface comes back out reduced,
## speed along it is mostly kept, and the spin is knocked off the ball.
func _ricochet(s: Solids.Shape, at: Vector3, n: Vector3) -> int:
	pos = at + n * 0.03
	var into := vel.dot(n)
	_note_hit(s, maxf(-into, 0.0))
	if into < 0.0:
		var along := vel - n * into
		vel = along * s.keep - n * (into * s.bounce)
		# bark, stone and tile are never quite flat
		var turn := (_noise(pos * 3.1) - 0.5) * 2.0 * s.scatter
		vel = Vector3(vel.x * cos(turn) - vel.z * sin(turn), vel.y, vel.x * sin(turn) + vel.z * cos(turn))
	lift *= 0.25
	side *= 0.25
	back *= 0.25
	if hits > MAX_HITS:
		# trapped between things: let it drop
		vel = Vector3(0.0, minf(vel.y, -1.0), 0.0)
	elif n.y > 0.7 and absf(vel.y) < 1.0:
		# come to rest on top of something: it trickles off the edge
		var out := Vector3(pos.x - s.x, 0.0, pos.z - s.z)
		if out.length_squared() < 0.01:
			out = Vector3(cos(_noise(pos) * TAU), 0.0, sin(_noise(pos) * TAU))
		vel = out.normalized() * 1.8 + Vector3(0.0, 0.7, 0.0)
	return E.HIT


func _note_hit(s: Solids.Shape, speed: float) -> void:
	hits += 1
	hit_obj = s.obj
	hit_tile = s.owner
	hit_mat = s.mat
	hit_speed = speed
	if Defs.is_tree(s.obj):
		tree_tile = s.owner


## Pass through foliage. Leaves slow the ball; now and then a branch stops
## it nearly dead. Returns true when a branch was met.
func _through_leaves(s: Solids.Shape, dt: float) -> bool:
	var path := vel.length() * dt
	var slow := exp(-path * s.drag)
	vel *= slow
	lift *= slow
	side *= slow
	var r := _noise(pos * 1.7)
	if r >= (1.0 - exp(-path * s.thick)) * (1.0 - dodge):
		return false
	var kick := (_noise(pos * 2.3 + Vector3(5.0, 1.0, 9.0)) - 0.5) * 2.4
	vel = Vector3(vel.x * 0.22 + vel.z * kick * 0.2, minf(vel.y, 0.0) * 0.3, vel.z * 0.22 - vel.x * kick * 0.2)
	lift = 0.0
	side = 0.0
	var first := tree_tile != s.owner
	tree_tile = s.owner
	return first


func _stop(course: Course) -> int:
	vel = Vector3.ZERO
	back = 0.0
	pos.y = course.height_at(pos.x, pos.z)
	var ti := course.index_at(pos.x, pos.z)
	if ti < 0 or course.locked[ti] != 0:
		# at rest beyond the boundary: out of bounds
		state = S.OOB
		return E.OOB
	state = S.REST
	return E.STOPPED


## The air the ball is flying through. The wind is stronger aloft and slack
## in the lee of trees, it rides up rising ground and sinks down the far
## side, it comes in eddies, and the heat off lava lifts whatever crosses it.
func _air(course: Course, ti: int, wind: Vector3) -> Vector3:
	var share := m_wind * shot_wind
	var ws := wind.length()
	var hot := lava and ti >= 0 and course.terrain[ti] == Defs.T.WATER
	if ws < 0.05 and not hot:
		return Vector3.ZERO
	var h := maxf(pos.y - course.height_at(pos.x, pos.z), 0.0)
	var w := wind * (Defs.wind_at(h) * share)
	if ws >= 0.05:
		if ti >= 0:
			if h < 9.0 and Defs.is_tree(course.objects[ti]):
				w *= 0.45
			var g := course.gradient_at(pos.x, pos.z)
			w.y += clampf(wind.x * g.x + wind.z * g.y, -3.0, 3.0) * exp(-h / 14.0) * share
		if air_seed >= 0.0:
			var ph := air_seed + move_time * 0.9
			w += Vector3(sin(ph * 1.7 + pos.x * 0.021), 0.3 * sin(ph * 2.3 + 1.0), sin(ph * 1.13 + pos.z * 0.021 + 2.0)) * (ws * 0.16 * share)
	if hot:
		w.y += 3.0 * exp(-h / 22.0) * share
	return w


## How the ball is turning, for drawing it: the axis, times radians a second.
func spin_vector() -> Vector3:
	var hv := Vector3(vel.x, 0.0, vel.z)
	var sp := hv.length()
	var f := Vector3(spin_fwd.x, 0.0, spin_fwd.y)
	if state == S.FLIGHT:
		if sp > 0.01:
			f = hv / sp
		return f.cross(Vector3.UP) * (back / RADIUS) - Vector3.UP * (side * 1500.0)
	if state == S.ROLL and sp > 0.01:
		return Vector3.UP.cross(hv / sp) * (sp / RADIUS) + f.cross(Vector3.UP) * (back / RADIUS)
	return Vector3.ZERO


func _hole_out(pin: Vector3) -> int:
	pos = pin
	vel = Vector3.ZERO
	state = S.HOLED
	return E.HOLED


static func _seg_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


static func _noise(p: Vector3) -> float:
	return absf(fposmod(sin(p.x * 12.9898 + p.z * 78.233 + p.y * 37.719) * 43758.5453, 1.0))
