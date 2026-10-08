class_name Members
extends RefCounted
## The club's membership. Golfers who love their round join at the Basic
## tier and come back as regulars. Each tier above that is unlocked by a
## different hidden wish, personal to that member: one wants scenery, the
## next a faster round, the next a driving range. Give a member a round
## that grants the wish and they move up, paying higher dues.

signal changed()

var sim: Sim
var tiers: Array = []
var factors: Array = []
var progress: Dictionary = {}  # how a member's game grows, data/membership.json
var warmup: Dictionary = {}    # the one-round warm-up, same file
var roster: Array[Dictionary] = []
var joined_total := 0
var quit_total := 0
var _next_id := 1


func _init(s: Sim) -> void:
	sim = s
	var txt := FileAccess.get_file_as_string("res://data/membership.json")
	var d: Variant = JSON.parse_string(txt)
	if d is Dictionary:
		tiers = d.get("tiers", [])
		factors = d.get("factors", [])
		progress = d.get("progress", {})
		warmup = d.get("warmup", {})


## The length scale. 0 is a short hitter, 1 a long one. The numbers live in
## progress in data/membership.json, and every place that rolls or shows
## length reads them here.
static func length_bounds(progress: Dictionary) -> Vector2:
	return Vector2(float(progress.get("power_floor", 0.74)), float(progress.get("power_cap", 1.06)))


static func power_at(t: float, progress: Dictionary) -> float:
	var bounds := length_bounds(progress)
	return lerpf(bounds.x, bounds.y, clampf(t, 0.0, 1.0))


static func power_share(power: float, progress: Dictionary) -> float:
	var bounds := length_bounds(progress)
	if is_equal_approx(bounds.x, bounds.y):
		return 0.0
	return inverse_lerp(bounds.x, bounds.y, power)


func count() -> int:
	return roster.size()


func count_tier(t: int) -> int:
	var n := 0
	for m in roster:
		if int(m.tier) == t:
			n += 1
	return n


func count_at_least(t: int) -> int:
	var n := 0
	for m in roster:
		if int(m.tier) >= t:
			n += 1
	return n


func capacity() -> int:
	return 12 + 8 * sim.course.holes.size() + 5 * sim.clubhouse_level


func monthly_dues() -> float:
	var t := 0.0
	for m in roster:
		t += float(tiers[int(m.tier)].dues)
	return t


## The index of a tier by its id ("silver"), or 0.
func tier_index(id: String) -> int:
	for i in tiers.size():
		if str((tiers[i] as Dictionary).get("id", "")) == id:
			return i
	return 0


func tier_name(t: int) -> String:
	return str(tiers[clampi(t, 0, tiers.size() - 1)].name)


func tier_color(t: int) -> Color:
	return Color(str(tiers[clampi(t, 0, tiers.size() - 1)].color))


func factor(id: String) -> Dictionary:
	return DataDB.find(factors, id)


func discount(g: Golfer) -> float:
	if g.member.is_empty():
		return 0.0
	return float(tiers[int(g.member.tier)].discount)


# ----------------------------------------------------------------- joining

## Called when any golfer leaves. Non-members may join; members may move up
## a tier, drop a hint about what they want, or resign.
func on_depart(g: Golfer) -> void:
	if not g.member.is_empty():
		_member_visit(g)
		return
	if g.kind != "public" or g.holes_played < mini(3, sim.course.holes.size()):
		return
	if g.satisfaction < 70.0 or roster.size() >= capacity():
		return
	var chance := clampf((g.satisfaction - 62.0) / 45.0, 0.0, 0.75)
	chance *= float(g.persona.get("join", 1.0)) * sim.skills.mult("membership")
	if sim.rng.randf() < chance:
		enroll(g)


## The member record with this id, or {}.
func find_member(id: int) -> Dictionary:
	for m in roster:
		if int(m.id) == id:
			return m
	return {}


## `quiet` joins without the fanfare: a story brings its own.
func enroll(g: Golfer, quiet: bool = false) -> Dictionary:
	var rng := sim.rng
	# Five hidden wishes, one for each tier above Basic. A personality has
	# favourites, but the order and one wildcard are down to the individual.
	var pool: Array = (g.persona.get("wants", ["scenery", "pace", "condition", "comfort", "walk"]) as Array).duplicate()
	var all_ids: Array = []
	for f: Dictionary in factors:
		all_ids.append(str(f.id))
	var wild := str(all_ids[rng.randi() % all_ids.size()])
	if not pool.has(wild):
		pool[rng.randi() % pool.size()] = wild
	for i in range(pool.size() - 1, 0, -1):
		if rng.randf() < 0.5:
			var j := rng.randi() % (i + 1)
			var tmp: Variant = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
	var m := {
		"id": _next_id, "name": g.name, "handle": g.handle, "persona": str(g.persona.get("id", "easygoing")),
		"skill": g.skill, "power": g.power, "accuracy": g.accuracy, "putting": g.putting, "imagination": g.imagination,
		"patience": g.patience, "pace": g.pace, "wealth": g.wealth,
		"shirt": g.shirt.to_html(), "pants": g.pants.to_html(), "skin": g.skin.to_html(), "hat": g.hat.to_html(),
		"tier": 0, "wants": pool, "known": [false, false, false, false, false],
		"visits": 0, "visits_at_tier": 0, "misses": 0, "strikes": 0, "last_mood": g.satisfaction,
		"joined": sim.day(), "next_visit": sim.day() + rng.randi_range(5, 12), "on_course": false,
		"spent": g.paid, "home": false, "last_score": -1.0,
	}
	_next_id += 1
	roster.append(m)
	joined_total += 1
	sim.skills.add_xp("manager", 2)
	if not quiet:
		if joined_total <= 3 or joined_total % 10 == 0:
			sim.toast.emit("%s enjoyed the round so much they joined the club. You now have %d members." % [g.name, roster.size()], "good")
		sim.feed.say("member_join", g)
	changed.emit()
	return m


func _member_visit(g: Golfer) -> void:
	var m := g.member
	m.on_course = false
	if g.holes_played == 0:
		return
	var rng := sim.rng
	var t := int(m.tier)
	m.visits = int(m.visits) + 1
	m.visits_at_tier = int(m.visits_at_tier) + 1
	m.last_mood = g.satisfaction
	m.spent = float(m.spent) + g.paid
	m.next_visit = sim.day() + maxi(3, rng.randi_range(6, 14) - t - (3 if m.home else 0))
	# resigning
	if g.satisfaction < 35.0:
		m.strikes = int(m.strikes) + 1
		if int(m.strikes) >= 2:
			roster.erase(m)
			quit_total += 1
			sim.toast.emit("%s, a %s member, has resigned from the club: %s" % [m.name, tier_name(t), sim.visitors.reason_for(g)], "bad")
			sim.feed.say("member_quit", g, {"reason": sim.visitors.reason_for(g)}, true)
			changed.emit()
			return
	elif g.satisfaction >= 55.0:
		m.strikes = 0
	# moving up
	if t < tiers.size() - 1:
		var want := str(m.wants[t])
		var score := score_factor(g, want)
		m.last_score = score
		var next: Dictionary = tiers[t + 1]
		var gate := sim.rating >= float(next.rating) and sim.course.holes.size() >= int(next.holes)
		if score >= 0.6 and g.satisfaction >= 58.0 and gate and int(m.visits_at_tier) >= int(next.visits):
			m.tier = t + 1
			m.visits_at_tier = 0
			m.misses = 0
			m.known[t] = true
			sim.skills.add_xp("manager", 2 + t)
			sim.toast.emit("%s has upgraded to %s membership. What won them over: %s." % [m.name, str(next.name), str(factor(want).name).to_lower()], "good")
			sim.feed.say("member_up", g, {"tier": str(next.name)})
			if int(m.tier) >= 3:
				sim.sell_home(m)
		elif score < 0.6:
			m.misses = int(m.misses) + 1
			var patience := 1 if sim.skills.bonus("concierge") > 0.0 else 2
			if int(m.misses) >= patience and not m.known[t]:
				m.known[t] = true
				sim.toast.emit("%s told the starter what would make them upgrade: they %s." % [m.name, str(factor(want).hint)], "info")
	if int(m.tier) >= 3 and not m.home:
		sim.sell_home(m)
	_grow(m)
	changed.emit()


## A finished round sticks. A little of everything, and more length when
## there is a range, more putting when there is a practice green. Taken
## from the stored record, so a one-round warm-up is not what they keep.
func _grow(m: Dictionary) -> void:
	var step := float(progress.get("per_visit", 0.0))
	var skill_cap := float(progress.get("skill_cap", 0.99))
	var power_cap := length_bounds(progress).y
	_bump(m, "skill", step, skill_cap)
	_bump(m, "accuracy", step, skill_cap)
	_bump(m, "imagination", step, skill_cap)
	_bump(m, "putting", step, skill_cap)
	_bump(m, "power", step, power_cap)
	var am := sim.visitors.amenity_counts()
	if int(am.get("range", 0)) > 0:
		_bump(m, "power", float(progress.get("range", 0.0)), power_cap)
	if int(am.get("putting", 0)) > 0:
		_bump(m, "putting", float(progress.get("putting", 0.0)), skill_cap)


func _bump(m: Dictionary, key: String, add: float, cap: float) -> void:
	m[key] = minf(cap, float(m.get(key, 0.0)) + add)


## How well one round delivered on one hidden wish, 0 to 1.
func score_factor(g: Golfer, id: String) -> float:
	var holes := maxi(g.holes_played, 1)
	var course := sim.course
	var tags := g.gripes
	match id:
		"challenge":
			var good := float(tags.get("score", 0.0)) + float(tags.get("shot", 0.0)) + float(tags.get("suits", 0.0))
			var bad := float(tags.get("hard", 0.0))
			return clampf(0.45 + (good + bad * 1.5) / 22.0, 0.0, 1.0)
		"scenery":
			var total := 0.0
			for hole in course.holes:
				total += sim.scenery_score(hole)
			return clampf(total / maxi(course.holes.size(), 1) * 1.9, 0.0, 1.0)
		"pace":
			return 1.0 - clampf(float(g.rd.waited) / (holes * 45.0), 0.0, 1.0)
		"condition":
			return clampf((sim.grounds.condition - 0.5) / 0.4, 0.0, 1.0)
		"comfort":
			var am := sim.visitors.amenity_counts()
			var extras := 0.1 * minf(int(am.bench), 2) + 0.08 * minf(int(am.washer), 2)
			return clampf(0.3 + 0.3 * int(g.rd.served) - 0.35 * int(g.rd.grumbles) + extras, 0.0, 1.0)
		"walk":
			# sore feet count against it; a cart, paths and benches all help
			var sore := -float(tags.get("tired", 0.0))
			var eased := 0.25 if (g.group != null and g.group.has_cart) else 0.0
			if g.rd.has("sat"):
				eased += 0.1
			return clampf(0.75 + eased - sore / 5.0, 0.0, 1.0)
		"prestige":
			var s := sim.rating / 100.0 * 0.7 + 0.04 * sim.clubhouse_level
			if not sim.tourney.hosted.is_empty():
				s += 0.15
			if g.saw_celebrity:
				s += 0.15
			return clampf(s, 0.0, 1.0)
		"variety":
			var pars := {}
			for hole in course.holes:
				pars[hole.par] = true
			return clampf(minf(course.holes.size(), 12.0) / 12.0 * 0.65 + [0.0, 0.0, 0.2, 0.4][mini(pars.size(), 3)], 0.0, 1.0)
		"safety":
			return 0.0 if (g.hits_taken > 0 or int(g.rd.scare) > 0) else 1.0
		"social":
			if g.group == null or g.group.members.size() < 2:
				return 0.4
			return clampf(0.5 + 0.5 * float(g.group.story.get("progress", 0.0)), 0.0, 1.0)
		"practice":
			var am := sim.visitors.amenity_counts()
			return 0.5 * minf(int(am.putting), 1) + 0.5 * minf(int(am.range), 1)
		"thrills":
			var s := 0.2
			if g.hits_taken > 0 or int(g.rd.scare) > 0 or int(g.rd.storm) > 0:
				s += 0.5
			if int(g.rd.lost_balls) > 0:
				s += 0.2
			if sim.is_lava():
				s += 0.2
			return clampf(s, 0.0, 1.0)
	return 0.5


# ---------------------------------------------------------------- regulars

## Members who are due a visit and not already out on the course.
func due(limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var today := sim.day()
	for m in roster:
		if not m.on_course and int(m.next_visit) <= today:
			out.append(m)
			if out.size() >= limit:
				break
	return out


## Turn a member record back into a golfer for today's round.
func make_golfer(m: Dictionary) -> Golfer:
	var g := Golfer.new()
	sim.tag_eddy(g)
	g.kind = "public"
	g.course = sim.course
	g.name = str(m.name)
	g.handle = str(m.handle)
	g.skill = float(m.skill)
	g.power = float(m.power)
	g.accuracy = float(m.accuracy)
	g.putting = float(m.putting)
	g.imagination = float(m.imagination)
	g.patience = float(m.patience)
	g.pace = float(m.pace)
	g.wealth = float(m.wealth)
	g.shirt = Color(str(m.shirt))
	g.pants = Color(str(m.pants))
	g.skin = Color(str(m.skin))
	g.hat = Color(str(m.hat))
	g.satisfaction = clampf(60.0 + int(m.tier) * 1.5 + sim.rng.randfn(0.0, 4.0) + sim.skills.bonus("welcome") + sim.debt_arrival(), 30.0, 90.0)
	g.persona = DataDB.find(sim.db.personalities, str(m.persona))
	g.member = m
	m.on_course = true
	return g


func to_list() -> Array:
	return roster


func from_list(list: Array) -> void:
	roster.clear()
	for m: Dictionary in list:
		m.on_course = false
		m.tier = int(m.tier)
		roster.append(m)
		_next_id = maxi(_next_id, int(m.id) + 1)
