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
var hole_time := 0.0       # sim seconds on the current hole, waiting included

const LINE_FIRST := 8.0    # metres behind the tee where the next party waits
const LINE_GAP := 6.0      # and between parties further back
const ARC_BACK := 3.4      # the teeing party's partners stand this far behind the marker
const WAIT_LIMIT := 150.0  # seconds a sober golfer will hold a shot for people in the way
const WAIT_PLAYER := 45.0  # when the only one in the way is the owner, standing still


func step(dt: float, sim: Sim) -> void:
	if members.is_empty():
		state = S.GONE
		return
	if _timing(sim):
		hole_time += dt
	match state:
		S.TO_TEE:
			_to_tee(dt, sim)
		S.QUEUE:
			_queue(dt, sim)
		S.PLAY:
			_play(dt, sim)
		S.LEAVING:
			_leave(dt, sim)


## Hole 1 starts once the party is already in the tee line, so the walk from
## the clubhouse door is not part of it. Later holes count from the moment
## the party heads there, including the walk from the previous green.
func _timing(sim: Sim) -> bool:
	if state == S.QUEUE or state == S.PLAY:
		return true
	if state != S.TO_TEE:
		return false
	if hole_i != 0:
		return true
	var hole := current_hole(sim)
	return hole != null and hole.line.has(self)


func current_hole(sim: Sim) -> Hole:
	if hole_i < 0 or hole_i >= sim.course.holes.size():
		return null
	return sim.course.holes[hole_i]


func _to_tee(dt: float, sim: Sim) -> void:
	skip_closed(sim)
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
				var spot: Vector3 = stop.pos
				if stop.get("spot") is Vector3:
					spot = stop.spot
				if sim.visitors.facility_near(str(stop.kind), spot, 1.0):
					sim.visitors.serve(self, str(stop.kind))
				stop = {}
		return
	# Join the line for the tee and walk to our place in it. The party at
	# the front walks straight on to the tee when it is free.
	var k := hole.line_index(self, hole_i)
	var tee_free := _tee_free(hole)
	var all := true
	for i in members.size():
		var m := members[i]
		if m.hit_t > 0.0:
			all = false
			continue
		var spot := arc_spot(hole, i, members.size()) if (k == 0 and tee_free) else line_spot(sim, hole, k, i)
		if not _settle(m, spot, hole, dt, sim, true):
			all = false
	if all:
		state = S.QUEUE
		wait = 0.0


## True when nobody holds the tee, or whoever did has gone.
func _tee_free(hole: Hole) -> bool:
	var holder := hole.teeing_group
	return holder == null or holder == self or holder.state == S.GONE or holder.state == S.LEAVING or holder.hole_i != hole_i


## The tee-to-pin line reversed, flat, and the direction across it.
static func tee_axes(hole: Hole) -> Array[Vector3]:
	var back := hole.tee - hole.aim_at()
	back.y = 0.0
	if back.length_squared() < 0.01:
		back = Vector3(1, 0, 0)
	back = back.normalized()
	return [back, Vector3(-back.z, 0.0, back.x)]


## Where member i of n stands while a partner tees off: a loose arc behind
## and beside the marker, never on the box.
static func arc_spot(hole: Hole, i: int, n: int) -> Vector3:
	var ax := tee_axes(hole)
	var off := i - (n - 1) * 0.5
	return hole.tee + ax[0] * (ARC_BACK + absf(off) * 0.5) + ax[1] * (off * 1.7)


## Where member i of the party at line position k waits: well back of the
## tee along the hole's own line, parties one behind the other, each a
## little to one side so two never share a spot. Where that runs off the
## land or into water the line bends to the side instead.
func line_spot(sim: Sim, hole: Hole, k: int, i: int) -> Vector3:
	var ax := tee_axes(hole)
	var c := sim.course
	var dist := LINE_FIRST + LINE_GAP * k
	var side := ((id % 3) - 1) * 0.6
	var anchor := hole.tee + ax[0] * dist + ax[1] * side
	if not _standable(c, anchor):
		anchor = hole.tee + ax[1] * (6.0 + 4.0 * k) + ax[0] * 2.0
		if not _standable(c, anchor):
			anchor = hole.tee - ax[1] * (6.0 + 4.0 * k) + ax[0] * 2.0
			if not _standable(c, anchor):
				anchor = hole.tee + ax[0] * dist
	var spot := anchor + ax[1] * ((i % 2) * 1.6 - 0.8) + ax[0] * ((i / 2) * 1.6)
	return c.on_ground(spot.x, spot.z)


static func _standable(c: Course, p: Vector3) -> bool:
	var t := c.terrain_at(p.x, p.z)
	if t < 0 or t == Defs.T.WATER:
		return false
	return c.locked[c.index_at(p.x, p.z)] == 0


## Walk a golfer to a spot, or if they are already there, have them stand
## facing the tee. Standing golfers do not re-plan a route every step.
func _settle(m: Golfer, spot: Vector3, hole: Hole, dt: float, sim: Sim, prefer_paths: bool = false) -> bool:
	var at := sim.visitors.clear_spot(m, spot)
	if Vector2(m.pos.x - at.x, m.pos.z - at.z).length_squared() < 0.09 and not m.walking:
		m.facing = atan2(hole.tee.z - m.pos.z, hole.tee.x - m.pos.x)
		return true
	var there := m.travel(spot, dt, sim, m.walk_speed(), prefer_paths)
	if there:
		m.facing = atan2(hole.tee.z - m.pos.z, hole.tee.x - m.pos.x)
	return there


func _queue(dt: float, sim: Sim) -> void:
	var hole := current_hole(sim)
	if hole == null:
		state = S.LEAVING
		return
	var k := hole.line_index(self, hole_i)
	if k == 0 and _tee_free(hole) and not hole.starter_holds(sim.time):
		# The group leaving has holed out. Set a cup that was waiting
		# before this party tees off, so they play today's cup.
		sim.settle_pins()
		hole.teeing_group = self
		hole.line.erase(self)
		_begin_hole(sim, hole)
	else:
		wait += dt
		# A bench by the tee makes the wait easier on everyone.
		var seated := sim.visitors.facility_near("bench", hole.tee, 18.0)
		for i in members.size():
			var m := members[i]
			if m.hit_t > 0.0:
				continue
			# the line shuffles forward as the party ahead takes the tee
			_settle(m, line_spot(sim, hole, k, i), hole, dt, sim)
			sim.visitors.wait_on(m, dt, "tee", wait, seated)
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
	hole.line.erase(self)
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
	hole.tee_at = sim.time
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
	for i in members.size():
		var m := members[i]
		if m == turn or m.hit_t > 0.0:
			continue
		if tee_done and not m.done and m.phase != Golfer.P.WATCH and m.ball.state == Ball.S.REST:
			m.travel(stance(m, hole), dt, sim, m.walk_speed())
		elif not tee_done:
			# partners wait in an arc behind the marker, off the box
			_settle(m, arc_spot(hole, i, members.size()), hole, dt, sim)
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
		var d := m.ball.pos.distance_squared_to(hole.aim_at())
		if d > bd:
			bd = d
			best = m
	return best


## Where a golfer stands to address their ball.
static func stance(m: Golfer, hole: Hole) -> Vector3:
	var to := hole.aim_at() - m.ball.pos
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
				# a drunk decides now whether to bother looking down the fairway
				if g.drunk > 0.3:
					g.plan["reckless"] = sim.rng.randf() < g.drunk
				g.phase = Golfer.P.AIM
				g.timer = (0.6 + (1.0 - g.pace) * 1.3) * (0.6 if g.plan.putt else 1.0) * sim.crew.pace_factor(g.pos) * g.think_mult()
				g.facing = g.plan.heading
		Golfer.P.AIM:
			g.timer -= dt
			if g.timer > 0.0:
				return
			var in_way := 0
			if not g.plan.putt and g.plan.dist > 25.0 and not bool(g.plan.get("reckless", false)):
				in_way = _danger(sim, g)
			if in_way > 0:
				# Nobody hits into people. The whole party waits, and the wait
				# wears on them. Only a wait that never ends (a stuck golfer, or
				# the owner stood in the fairway thinking) is given up on.
				wait += dt
				for m in members:
					sim.visitors.wait_on(m, dt, "fairway", wait, false)
				var limit := WAIT_PLAYER if in_way == 2 else WAIT_LIMIT
				if wait < limit:
					return
				forced = true
				sim.feed.say("hit_into", g, {"hole": hole_i + 1})
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


## Who is standing where this shot is going: 0 nobody, 1 someone from
## another group, 2 only the owner's golfer, stood still. On the same hole a
## group only yields to players ahead of it, so two groups can never end up
## each waiting for the other.
func _danger(sim: Sim, g: Golfer) -> int:
	var heading: float = g.plan.heading
	var dir := Vector2(cos(heading), sin(heading))
	# Everyone waits until the landing area is clear; a careful golfer
	# allows for a shot that flies further than meant, a marshal insists.
	var reach: float = g.plan.dist * (0.95 + 0.25 * g.patience) + 14.0
	if sim.crew.marshal_near(g.pos):
		reach = g.plan.dist + 35.0
	var hole := current_hole(sim)
	var mine := 0.0
	if hole != null:
		mine = Vector2(g.pos.x - hole.aim_at().x, g.pos.z - hole.aim_at().z).length()
	var found := 0
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
			var theirs := Vector2(p.pos.x - hole.aim_at().x, p.pos.z - hole.aim_at().z).length()
			if theirs > mine - 6.0:
				continue      # level with us or behind: not ours to wait for
		if p.kind == "player" and not p.walking and p.swing_t < 0.0:
			if found == 0:
				found = 2
			continue
		return 1
	return found


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
	hole.note_time(hole_time)
	hole_time = 0.0
	for m in members:
		sim.visitors.on_hole_done(m, hole, hole_i, self)
	sim.visitors.story_tick(self, hole_i)
	leave_hole(hole)
	sim.settle_pins()
	if last_hole >= 0 and hole_i >= last_hole:
		state = S.LEAVING
		return
	hole_i += 1
	skip_closed(sim)
	state = S.TO_TEE if hole_i < sim.course.holes.size() else S.LEAVING
	if state == S.TO_TEE:
		stop = sim.visitors.plan_stop(self)


## Step past holes the public is not allowed on yet. A round that was only
## going as far as a closed hole ends instead of playing it.
func skip_closed(sim: Sim) -> void:
	var holes := sim.course.holes
	while hole_i < holes.size() and not holes[hole_i].open:
		hole_i += 1
		if last_hole >= 0 and hole_i > last_hole:
			hole_i = holes.size()
			return


func leave_hole(hole: Hole) -> void:
	hole.groups.erase(self)
	hole.line.erase(self)
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
