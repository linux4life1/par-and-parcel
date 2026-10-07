class_name Group
extends RefCounted
## A group of golfers going round together: walk to the tee, wait for it to
## clear, pay for the hole, play it out, move on.

enum S { TO_TEE, QUEUE, PLAY, LEAVING, GONE }

var id := 0
var members: Array[Golfer] = []
var hole_i := 0
var state: int = S.TO_TEE
var turn: Golfer = null
var wait := 0.0
var kind := "public"       # public, tournament, celebrity, outing, player
var tee_done := false
var forced := false        # someone hit into people out of impatience
var free_play := false     # pays no green fees (tournaments, prepaid outings, the owner)
var last_hole := -1        # stop after this hole index, -1 for the whole course
var has_cart := false      # rented a golf cart: quick on cart paths, easy on the feet
var stop := {}             # a facility to visit on the way to the next tee
var story := {}            # what brought these people out together


func step(dt: float, sim: Sim) -> void:
	if members.is_empty():
		state = S.GONE
		return
	match state:
		S.TO_TEE:
			_to_tee(dt, sim)
		S.QUEUE:
			_queue(dt, sim)
		S.PLAY:
			_play(dt, sim)
		S.LEAVING:
			_leave(dt, sim)


func current_hole(sim: Sim) -> Hole:
	if hole_i < 0 or hole_i >= sim.course.holes.size():
		return null
	return sim.course.holes[hole_i]


func _to_tee(dt: float, sim: Sim) -> void:
	var hole := current_hole(sim)
	if hole == null:
		state = S.LEAVING
		return
	# A stop on the way: restroom, snack bar or drink stand.
	if not stop.is_empty():
		var at: Vector3 = stop.pos
		var there := true
		for i in members.size():
			var m := members[i]
			if m.hit_t > 0.0:
				there = false
				continue
			if not m.travel(at + Vector3((i % 2) * 1.6 - 0.8, 0.0, (i / 2) * 1.6), dt, sim, m.walk_speed(), true):
				there = false
		if there:
			stop.timer = float(stop.timer) - dt
			if float(stop.timer) <= 0.0:
				sim.visitors.serve(self, str(stop.kind))
				stop = {}
		return
	var back := hole.tee - hole.pin
	back.y = 0.0
	back = back.normalized()
	var sidev := Vector3(-back.z, 0.0, back.x)
	var all := true
	for i in members.size():
		var m := members[i]
		if m.hit_t > 0.0:
			all = false
			continue
		var spot := hole.tee + back * (3.0 + (i / 2) * 1.8) + sidev * ((i % 2) * 2.4 + 2.0 + (id % 3) * 2.5)
		if not m.travel(spot, dt, sim, m.walk_speed(), true):
			all = false
	if all:
		state = S.QUEUE
		wait = 0.0


func _queue(dt: float, sim: Sim) -> void:
	var hole := current_hole(sim)
	if hole == null:
		state = S.LEAVING
		return
	var holder := hole.teeing_group
	if holder == null or holder == self or holder.state == S.GONE or holder.state == S.LEAVING:
		hole.teeing_group = self
		_begin_hole(sim, hole)
	else:
		wait += dt
		# A bench by the tee makes the wait easier on everyone.
		var seated := sim.visitors.facility_near("bench", hole.tee, 18.0)
		for m in members:
			var share := 0.5 if seated else 1.0
			m.waited += dt * share
			m.rd.waited = float(m.rd.waited) + dt * share
			if seated:
				m.fatigue = maxf(0.0, m.fatigue - dt * 0.03)
				if wait > 12.0 and not m.rd.has("sat"):
					m.rd["sat"] = true
					m.feel(0.8, "Nice to have a bench while we wait.", "rest")


func _begin_hole(sim: Sim, hole: Hole) -> void:
	# Nothing is charged here. Golfers pay as they leave each green, by how
	# much they enjoyed the hole (see Visitors.collect_fee).
	if members.is_empty():
		hole.teeing_group = null
		state = S.GONE
		return
	var washer := sim.visitors.facility_near("washer", hole.tee, 18.0)
	for m in members:
		m.begin_hole()
		m.ball.place(sim.course.on_ground(hole.tee.x, hole.tee.z))
		m.clean_ball = washer
		if washer and not m.rd.has("washer"):
			m.rd["washer"] = true
			m.feel(0.8, "A ball washer on the tee. Nice touch.", "amenity")
	# after dark, a lit hole is a treat and an unlit one a chore
	if sim.darkness() > 0.55:
		if hole.lit_enough(sim.course):
			sim.visitors.on_night_golf(self, hole_i)
		else:
			sim.visitors.on_dark_hole(self, hole_i)
	tee_done = false
	turn = null
	wait = 0.0
	forced = false
	if not hole.groups.has(self):
		hole.groups.append(self)
	state = S.PLAY


func _play(dt: float, sim: Sim) -> void:
	var hole := current_hole(sim)
	if hole == null:
		state = S.LEAVING
		return
	# settle any ball that has come to rest
	var all_done := true
	var busy := false
	for m in members:
		if m.phase == Golfer.P.WATCH:
			if m.ball.moving():
				busy = true
			else:
				_resolve(sim, m, hole)
				m.phase = Golfer.P.IDLE
		if not m.done:
			all_done = false
	if all_done and not busy:
		_finish_hole(sim, hole)
		return
	# ready golf: whoever is ready and farthest away plays next
	if turn == null:
		turn = _pick_turn(hole)
		if turn != null:
			turn.phase = Golfer.P.WALK
	for m in members:
		if m == turn or m.hit_t > 0.0:
			continue
		if tee_done and not m.done and m.phase != Golfer.P.WATCH and m.ball.state == Ball.S.REST:
			m.travel(stance(m, hole), dt, sim, m.walk_speed())
		else:
			m.walking = false
	if turn != null:
		_turn_step(dt, sim, hole)


func _pick_turn(hole: Hole) -> Golfer:
	if not tee_done:
		for m in members:
			if not m.teed and not m.done:
				return m
		tee_done = true
		if hole.teeing_group == self:
			hole.teeing_group = null
	var best: Golfer = null
	var bd := -1.0
	for m in members:
		if m.done or m.phase == Golfer.P.WATCH or m.ball.moving():
			continue
		var d := m.ball.pos.distance_squared_to(hole.pin)
		if d > bd:
			bd = d
			best = m
	return best


## Where a golfer stands to address their ball.
static func stance(m: Golfer, hole: Hole) -> Vector3:
	var to := hole.pin - m.ball.pos
	to.y = 0.0
	var l := to.length()
	if l < 0.05:
		return m.ball.pos
	to /= l
	return m.ball.pos + Vector3(to.z, 0.0, -to.x) * 0.7


func _turn_step(dt: float, sim: Sim, hole: Hole) -> void:
	var g := turn
	if g.hit_t > 0.0:
		return
	match g.phase:
		Golfer.P.WALK:
			if g.travel(stance(g, hole), dt, sim, g.walk_speed()):
				g.plan = ShotAI.plan(sim, g, hole)
				g.phase = Golfer.P.AIM
				g.timer = (0.6 + (1.0 - g.pace) * 1.3) * (0.6 if g.plan.putt else 1.0) * sim.crew.pace_factor(g.pos) * g.think_mult()
				g.facing = g.plan.heading
		Golfer.P.AIM:
			g.timer -= dt
			if g.timer > 0.0:
				return
			if not g.plan.putt and g.plan.dist > 25.0 and _danger(sim, g):
				wait += dt
				for m in members:
					m.waited += dt
					m.rd.waited = float(m.rd.waited) + dt
				var limit := 25.0 + g.patience * 70.0
				# A marshal keeps tempers in check, but nobody waits for ever.
				if wait < limit or (wait < 150.0 and sim.crew.marshal_near(g.pos)):
					return
				forced = true
			g.phase = Golfer.P.SWING
			g.timer = 0.6
			g.swing_t = 0.0
		Golfer.P.SWING:
			g.timer -= dt
			if g.timer <= 0.0:
				ShotAI.strike(sim, g)
				ShotAI.emit_strike(sim, g)
				g.teed = true
				sim.visitors.track_ball(g.ball, hole)
				g.phase = Golfer.P.WATCH
				wait = 0.0
				turn = null
		_:
			g.phase = Golfer.P.WALK


## True when someone from another group is standing where this shot is
## going. On the same hole a group only yields to players ahead of it, so
## two groups can never end up each waiting for the other.
func _danger(sim: Sim, g: Golfer) -> bool:
	var heading: float = g.plan.heading
	var dir := Vector2(cos(heading), sin(heading))
	# Patient golfers wait until nobody is anywhere near their landing area.
	# Impatient ones decide the group ahead is "probably out of range".
	var reach: float = g.plan.dist * (0.72 + 0.4 * g.patience) + 12.0
	if sim.crew.marshal_near(g.pos):
		reach = g.plan.dist + 35.0
	var hole := current_hole(sim)
	var mine := 0.0
	if hole != null:
		mine = Vector2(g.pos.x - hole.pin.x, g.pos.z - hole.pin.z).length()
	for p in sim.visitors.golfers:
		if p.group == self or p.group == null:
			continue
		var v := Vector2(p.pos.x - g.pos.x, p.pos.z - g.pos.z)
		var along := v.dot(dir)
		if along < 8.0 or along > reach:
			continue
		if absf(v.cross(dir)) >= 6.0 + along * 0.14:
			continue
		if hole != null and p.group.hole_i == hole_i and p.group.state == S.PLAY:
			var theirs := Vector2(p.pos.x - hole.pin.x, p.pos.z - hole.pin.z).length()
			if theirs > mine - 6.0:
				continue      # level with us or behind: not ours to wait for
		return true
	return false


func _resolve(sim: Sim, g: Golfer, hole: Hole) -> void:
	var b := g.ball
	var n := hole_i + 1
	match b.state:
		Ball.S.HOLED:
			g.done = true
			sim.visitors.on_holed(g, hole, hole_i)
			return
		Ball.S.WATER:
			g.strokes += 1
			g.rd.lost_balls = int(g.rd.lost_balls) + 1
			if sim.is_lava():
				g.feel(-2.5, "My ball melted in the lava on hole %d." % n, "water")
				sim.feed.say("lava_ball", g, {"hole": n})
			else:
				g.feel(-2.5, "My ball is in the water on hole %d." % n, "water")
				sim.feed.say("water_ball", g, {"hole": n})
			b.place(drop_spot(sim.course, b))
		Ball.S.OOB:
			# stroke and distance: one penalty stroke, and play again from the same spot
			g.strokes += 1
			g.rd.lost_balls = int(g.rd.lost_balls) + 1
			g.feel(-2.5, "Out of bounds on hole %d. Hitting another from the same spot." % n, "oob")
			sim.feed.say("oob_ball", g, {"hole": n})
			b.place(b.start)
		_:
			sim.visitors.react_to_lie(g, hole, hole_i)
	if g.strokes >= hole.par + 5 and not g.done:
		g.done = true
		g.picked_up = true
		g.feel(-3.0, "I'm picking up on hole %d. That's enough." % n, "hard")


## Where to drop after a water ball: back on dry land near where it crossed.
static func drop_spot(course: Course, b: Ball) -> Vector3:
	var p := b.last_land
	var back := b.start - p
	back.y = 0.0
	var l := back.length()
	if l > 0.1:
		back /= l
	var q := p
	for i in 40:
		q = p + back * minf(2.0 + i * 2.0, l)
		var t := course.terrain_at(q.x, q.z)
		# on dry land, and on the club's own land
		if t >= 0 and t != Defs.T.WATER and course.locked[course.index_at(q.x, q.z)] == 0:
			break
	return course.on_ground(q.x, q.z)


func _finish_hole(sim: Sim, hole: Hole) -> void:
	for m in members:
		sim.visitors.on_hole_done(m, hole, hole_i, self)
	sim.visitors.story_tick(self, hole_i)
	leave_hole(hole)
	if last_hole >= 0 and hole_i >= last_hole:
		state = S.LEAVING
		return
	hole_i += 1
	state = S.TO_TEE if hole_i < sim.course.holes.size() else S.LEAVING
	if state == S.TO_TEE:
		stop = sim.visitors.plan_stop(self)


func leave_hole(hole: Hole) -> void:
	hole.groups.erase(self)
	if hole.teeing_group == self:
		hole.teeing_group = null
	turn = null


func _leave(dt: float, sim: Sim) -> void:
	var door := sim.clubhouse_door()
	var all := true
	for i in members.size():
		var m := members[i]
		if m.hit_t > 0.0:
			all = false
			continue
		if not m.travel(door + Vector3((i % 2) * 1.5, 0.0, (i / 2) * 1.5), dt, sim, m.walk_speed() * 1.2, true):
			all = false
	if all:
		for m in members.duplicate():
			sim.visitors.depart(m)
		members.clear()
		state = S.GONE
