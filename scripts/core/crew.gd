class_name Crew
extends RefCounted
## Hired staff. Greenkeepers mow and weed, exterminators clear pests,
## marshals keep play moving, and a porter picks up the litter.

class Member:
	extends RefCounted
	var id := 0
	var role: Dictionary = {}
	var name := ""
	var pos := Vector3.ZERO
	var prev := Vector3.ZERO
	var facing := 0.0
	var state := 0          # 0 idle, 1 walking, 2 working
	var timer := 0.0
	var target := Vector3.ZERO
	var target_i := -1
	var hit_t := 0.0
	var walking := false
	var jobs_done := 0
	var level := 1          # 2 once promoted: faster, and better at the job
	var has_home := false   # stationed: work stays inside the circle around home
	var home := Vector3.ZERO
	var route := PackedVector2Array()
	var route_i := 0
	var route_goal := Vector3.ZERO
	var cup_cut := false       # this job is the morning mow of a new cup

var sim: Sim
var members: Array[Member] = []
var _claimed := {}
var _next_id := 1
## Cups a greenkeeper still has to mow, after the morning move. One tile
## each, then they go back to the weeds.
var pin_cuts: Array[int] = []


func _init(s: Sim) -> void:
	sim = s


func post_pins(points: Array[Vector3]) -> void:
	pin_cuts.clear()
	if points.is_empty():
		return
	var seen := {}
	for p in points:
		var t := sim.course.tile_of(p.x, p.z)
		if not sim.course.in_bounds(t.x, t.y):
			continue
		var i := t.y * sim.course.w + t.x
		if seen.has(i):
			continue
		seen[i] = true
		pin_cuts.append(i)


func count(role_id: String) -> int:
	var n := 0
	for m in members:
		if m.role.id == role_id:
			n += 1
	return n


func hire(role_id: String) -> Member:
	var role := sim.db.role(role_id)
	if role.is_empty():
		return null
	var m := Member.new()
	m.id = _next_id
	_next_id += 1
	m.role = role
	m.name = sim.db.pick("staff_first", sim.rng) + " " + sim.db.pick("last", sim.rng)
	var door := sim.clubhouse_door()
	m.pos = sim.course.on_ground(door.x + sim.rng.randf_range(-4.0, 4.0), door.z + sim.rng.randf_range(-2.0, 4.0))
	m.prev = m.pos
	members.append(m)
	sim.staff_changed.emit()
	return m


func fire(m: Member) -> void:
	if m.target_i >= 0:
		_claimed.erase(m.target_i)
	members.erase(m)
	sim.staff_changed.emit()


func fire_one(role_id: String) -> bool:
	for i in range(members.size() - 1, -1, -1):
		if members[i].role.id == role_id:
			fire(members[i])
			return true
	return false


func monthly_wages() -> float:
	var t := 0.0
	for m in members:
		# a club pro who owes the place works for less (see the Comeback story)
		var deal := 0.4 if (str(m.role.id) == "club_pro" and sim.stories.cheap_pro()) else 1.0
		t += float(m.role.wage) * (1.6 if m.level > 1 else 1.0) * deal
	return t * sim.skills.mult("wage") * sim.diff("wages")


## How far, in metres, a stationed member looks for work.
func home_radius() -> float:
	return sim.db.home_radius


## Park this member. They look for work inside the circle and walk back
## when there is none, instead of roaming the course.
func station(m: Member, at: Vector3) -> void:
	m.has_home = true
	m.home = sim.course.on_ground(at.x, at.z)
	sim.staff_changed.emit()


func clear_station(m: Member) -> void:
	m.has_home = false
	sim.staff_changed.emit()


func _in_home(m: Member, p: Vector3) -> bool:
	if not m.has_home:
		return true
	var r := home_radius()
	return Vector2(p.x - m.home.x, p.z - m.home.z).length_squared() <= r * r


## Walk back to the post, or wait there if they have already arrived.
func _go_home(m: Member) -> void:
	if m.pos.distance_squared_to(m.home) > 4.0:
		m.target = m.home
		m.target_i = -1
		m.state = 1
	else:
		m.timer = 2.5


## Promote someone: they work faster and better, for more pay.
func promote(m: Member) -> bool:
	var cost := float(m.role.wage) * 3.0 * sim.diff("wages")
	if m.level > 1 or not sim.economy.can_afford(cost):
		return false
	sim.economy.spend("wages", cost)
	m.level = 2
	sim.staff_changed.emit()
	return true


func marshal_near(p: Vector3) -> bool:
	for m in members:
		if m.role.id == "marshal" and m.pos.distance_squared_to(p) < 80.0 * 80.0:
			return true
	return false


## Golfers take less time over the ball when a marshal is watching.
func pace_factor(p: Vector3) -> float:
	return 0.7 if marshal_near(p) else 1.0


func step(dt: float) -> void:
	var course := sim.course
	for m in members:
		m.prev = m.pos
		if m.hit_t > 0.0:
			m.hit_t -= dt
			m.walking = false
			continue
		match m.state:
			0:
				m.walking = false
				m.timer -= dt
				if m.timer <= 0.0:
					_find_job(m)
			1:
				if _walk(m, dt, course):
					m.state = 2
					m.timer = _work_time(m)
			2:
				m.walking = false
				m.timer -= dt
				if m.timer <= 0.0:
					_finish_job(m)
					m.state = 0
					m.timer = 0.2


func _walk(m: Member, dt: float, _course: Course) -> bool:
	var speed: float = m.role.speed
	if m.level > 1:
		speed *= 1.25
	var riding: bool = m.role.id == "beverage"
	return Nav.advance(m, m.target, dt, sim, speed, riding, riding)


func _work_time(m: Member) -> float:
	var base := 3.0
	if m.cup_cut:
		base = float(sim.db.pins.get("mow", 0.6))
	else:
		match m.role.id:
			"exterminator":
				base = 4.0
			"marshal":
				base = 6.0
			"beverage":
				base = 3.0
			"club_pro":
				base = 5.0
	return base / (sim.skills.mult("staff_eff") * (1.5 if m.level > 1 else 1.0))


func _find_job(m: Member) -> void:
	var course := sim.course
	m.cup_cut = false
	if m.target_i >= 0:
		_claimed.erase(m.target_i)
		m.target_i = -1
	if m.role.id == "marshal":
		_find_marshal_job(m)
		return
	if m.role.id == "beverage":
		_find_drinks_job(m)
		return
	if m.role.id == "porter":
		_find_porter_job(m)
		return
	if m.role.id == "club_pro":
		# the pro stays by the clubhouse, greeting arrivals, unless posted
		if m.has_home:
			m.target = m.home
		else:
			var door := sim.clubhouse_door()
			m.target = course.on_ground(door.x + sim.rng.randf_range(-8.0, 8.0), door.z + sim.rng.randf_range(-3.0, 6.0))
		m.state = 1
		return
	if m.has_home:
		_find_home_job(m)
		return
	sim.grounds.refresh_layout()
	var pests: bool = m.role.id == "exterminator"
	var best := -1
	var best_score := 0.1
	var rng := sim.rng
	var n := course.w * course.h
	var play := sim.grounds.play_tiles
	var here := course.index_at(m.pos.x, m.pos.z)
	for k in 150:
		var i := 0
		if k < 24 and here >= 0:
			# look at the ground right around first, so work spreads out in strips
			var ox := (k % 5) - 2
			var oy := (k / 5) - 2
			i = here + ox + oy * course.w
			if i < 0 or i >= n:
				continue
		elif k < 110 and not play.is_empty():
			i = play[rng.randi() % play.size()]
		else:
			i = rng.randi() % n
		if _claimed.has(i):
			continue
		var t: int = course.terrain[i]
		var need := 0.0
		if pests:
			need = course.pests[i] * 3.0 if course.pests[i] > 0.05 else 0.0
		else:
			need = ((1.0 - course.health[i]) + course.weeds[i] * 1.3) * Defs.T_CARE[t]
		if need <= 0.1:
			continue
		var cx := (i % course.w + 0.5) * Defs.TILE
		var cz := (i / course.w + 0.5) * Defs.TILE
		var dist := Vector2(cx - m.pos.x, cz - m.pos.z).length()
		var score := need - dist / 300.0
		if score > best_score:
			best_score = score
			best = i
	# A new cup is posted under a weedy patch, and mowed only when the
	# keeper has not found weeds. The number lives in pins.json.
	if m.role.id == "greenkeeper":
		var cut_base := float(sim.db.pins.get("cut", 0.12))
		for ci in pin_cuts.size():
			var cut := pin_cuts[ci]
			if _claimed.has(cut):
				continue
			var cut_x := (cut % course.w + 0.5) * Defs.TILE
			var cut_z := (int(cut / course.w) + 0.5) * Defs.TILE
			var cut_score := cut_base - Vector2(cut_x - m.pos.x, cut_z - m.pos.z).length() / 300.0
			if cut_score > best_score:
				best_score = cut_score
				best = cut
	if best < 0:
		m.timer = 2.5
		return
	m.target_i = best
	_claimed[best] = true
	var posted := pin_cuts.find(best)
	if posted >= 0:
		pin_cuts.remove_at(posted)
		m.cup_cut = true
	m.target = course.tile_center(best % course.w, best / course.w)
	m.state = 1


func _find_marshal_job(m: Member) -> void:
	var worst: Group = null
	var ww := 8.0
	for gr in sim.visitors.groups:
		if gr.wait > ww and not gr.members.is_empty():
			if not _in_home(m, gr.members[0].pos):
				continue
			ww = gr.wait
			worst = gr
	var course := sim.course
	if worst != null:
		var p := worst.members[0].pos
		m.target = course.on_ground(p.x + 8.0, p.z + 8.0)
		m.state = 1
	elif m.has_home:
		_go_home(m)
	elif not course.holes.is_empty():
		var hole := course.holes[sim.rng.randi() % course.holes.size()]
		var mid := hole.point_along(sim.rng.randf())
		m.target = course.on_ground(mid.x + sim.rng.randf_range(-20.0, 20.0), mid.z + sim.rng.randf_range(-20.0, 20.0))
		m.state = 1
	else:
		m.timer = 3.0


## Grounds crew with a post only take tiles inside the circle. Scanning the
## circle keeps the choice off the dice, so a roaming keeper still draws the
## same numbers as before.
func _find_home_job(m: Member) -> void:
	var course := sim.course
	sim.grounds.refresh_layout()
	var pests: bool = m.role.id == "exterminator"
	var r := home_radius()
	var reach := int(ceil(r / Defs.TILE))
	var hx := int(m.home.x / Defs.TILE)
	var hz := int(m.home.z / Defs.TILE)
	var best := -1
	var best_score := 0.1
	for oy in range(-reach, reach + 1):
		for ox in range(-reach, reach + 1):
			var x := hx + ox
			var y := hz + oy
			if not course.in_bounds(x, y):
				continue
			var i := y * course.w + x
			if _claimed.has(i):
				continue
			var cx := (x + 0.5) * Defs.TILE
			var cz := (y + 0.5) * Defs.TILE
			if Vector2(cx - m.home.x, cz - m.home.z).length_squared() > r * r:
				continue
			var t: int = course.terrain[i]
			var need := 0.0
			if pests:
				need = course.pests[i] * 3.0 if course.pests[i] > 0.05 else 0.0
			else:
				need = ((1.0 - course.health[i]) + course.weeds[i] * 1.3) * Defs.T_CARE[t]
			if need <= 0.1:
				continue
			var dist := Vector2(cx - m.pos.x, cz - m.pos.z).length()
			var score := need - dist / 300.0
			if score > best_score:
				best_score = score
				best = i
	if best < 0:
		_go_home(m)
		return
	m.target_i = best
	_claimed[best] = true
	m.target = course.tile_center(best % course.w, best / course.w)
	m.state = 1


## Litter and a broken window, nearest first. The whole map, no dice.
func _find_porter_job(m: Member) -> void:
	var course := sim.course
	var spec: Dictionary = sim.db.litter
	var show := float(spec.get("show", 0.45))
	var window := float(spec.get("window", 1.0))
	var reach := float(spec.get("score_reach", 400.0))
	var n := course.w * course.h
	var best := -1
	var best_score := float(spec.get("score_floor", 0.05))
	for i in n:
		if _claimed.has(i):
			continue
		var mess := 0.0
		if course.repair[i] != 0:
			mess = window
		elif course.litter[i] >= show:
			mess = course.litter[i]
		else:
			continue
		var cx := (i % course.w + 0.5) * Defs.TILE
		var cz := (int(i / course.w) + 0.5) * Defs.TILE
		if not _in_home(m, Vector3(cx, 0.0, cz)):
			continue
		var dist := Vector2(cx - m.pos.x, cz - m.pos.z).length()
		var score := mess - dist / reach
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		if m.has_home:
			_go_home(m)
		else:
			m.timer = 2.5
		return
	m.target_i = best
	_claimed[best] = true
	m.target = course.tile_center(best % course.w, int(best / course.w))
	m.state = 1


## The drinks cart heads for whichever group is thirstiest.
func _find_drinks_job(m: Member) -> void:
	var best: Group = null
	var worst := 0.7
	for gr in sim.visitors.groups:
		if gr.members.is_empty() or gr.state == Group.S.LEAVING:
			continue
		if not _in_home(m, gr.members[0].pos):
			continue
		var need := 0.0
		for g in gr.members:
			need += g.thirst + g.hunger * 0.5
		if need > worst:
			worst = need
			best = gr
	var course := sim.course
	if best != null:
		var p := best.members[0].pos
		m.target = course.on_ground(p.x + 4.0, p.z + 4.0)
		m.state = 1
	elif m.has_home:
		_go_home(m)
	elif not course.holes.is_empty():
		var hole := course.holes[sim.rng.randi() % course.holes.size()]
		var mid := hole.point_along(sim.rng.randf())
		m.target = course.on_ground(mid.x + 14.0, mid.z + 14.0)
		m.state = 1
	else:
		m.timer = 3.0


func _serve_drinks(m: Member) -> void:
	var retail := sim.skills.mult("retail")
	var reach := 26.0 if m.level > 1 else 20.0
	var served := 0
	for g in sim.visitors.golfers:
		if g.kind == "player" or g.pos.distance_squared_to(m.pos) > reach * reach:
			continue
		if g.thirst < 0.3 and g.hunger < 0.5 and m.level < 2:
			continue
		g.thirst = 0.0
		g.hunger = maxf(0.0, g.hunger - 0.3)
		g.bladder += 0.12
		g.rd.served = int(g.rd.served) + 1
		sim.economy.earn("concessions", 6.0 * retail)
		sim.popup.emit(g.pos, "+$6", "money")
		g.feel(2.5, "The drinks cart found us just in time.", "drink")
		served += 1
		if sim.rng.randf() < 0.08:
			sim.feed.say("cart_drinks", g)
	if served > 0:
		m.jobs_done += 1


func _finish_job(m: Member) -> void:
	var course := sim.course
	if m.role.id == "beverage":
		_serve_drinks(m)
		return
	var i := m.target_i
	if i < 0:
		return
	_claimed.erase(i)
	m.target_i = -1
	m.jobs_done += 1
	if m.role.id == "porter":
		_clear_mess(course, i)
		return
	if m.cup_cut:
		m.cup_cut = false
		if Defs.T_GRASS[course.terrain[i]]:
			var tidy := float(sim.db.pins.get("tidy", 0.02))
			course.health[i] = minf(1.0, course.health[i] + tidy)
		return
	var tx := i % course.w
	var ty := int(i / course.w)
	var reach := 2      # a mower pass or a treatment covers a five by five patch
	for y in range(ty - reach, ty + reach + 1):
		for x in range(tx - reach, tx + reach + 1):
			if not course.in_bounds(x, y):
				continue
			var j := y * course.w + x
			if m.role.id == "exterminator":
				course.pests[j] = 0.0
			elif Defs.T_GRASS[course.terrain[j]]:
				course.health[j] = minf(1.0, course.health[j] + 0.9)
				course.weeds[j] = 0.0


## Pick up the litter and board the window, on a small patch, then stop.
func _clear_mess(course: Course, i: int) -> void:
	var spec: Dictionary = sim.db.litter
	var clean := float(spec.get("clean", 1.0))
	var patch := int(spec.get("patch", 1))
	var show := float(spec.get("show", 0.45))
	var tx := i % course.w
	var ty := int(i / course.w)
	for y in range(ty - patch, ty + patch + 1):
		for x in range(tx - patch, tx + patch + 1):
			if not course.in_bounds(x, y):
				continue
			var j := y * course.w + x
			var before: float = course.litter[j]
			var after := clampf(before - clean, 0.0, 1.0)
			if not is_equal_approx(before, after):
				course.litter[j] = after
				if (before < show and after >= show) or (before >= show and after < show):
					course.litter_rev += 1
			course.repair[j] = 0
