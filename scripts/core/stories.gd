class_name Stories
extends RefCounted
## The long stories: a romance that needs a bench by the water, a grudge
## that ends in a money match, a tour pro finding his swing, an heiress
## waiting for a view. Each is data in data/stories.json, told by real
## returning golfers (club members made or borrowed for the part) over
## weeks of visits, and each stage waits for something the game does:
## a visit, a round, a birdie, a tournament, a request the club can meet.
##
## Stories roll their own dice. Every hook saves and restores the game's
## random state, so a story never changes what the rest of the game would
## have done next.

var sim: Sim
var rng := RandomNumberGenerator.new()
var running: Array[Dictionary] = []     # the stories under way
var finished: Array[Dictionary] = []    # the ones that ended, newest last
var used := {}                          # story id -> the day it last started
var flags := {}                         # lasting gifts: cheap_pro, rating_bias
var enabled := true
var last_event := ""                    # the last tournament's name, for {event}
var _uid := 1
var _match_wins := 0                    # the owner's match wins when a match was offered

const CAST_CHANCE := 0.12               # a day, while there is room for another story
const FIRST_DAY := 6                    # no stories before the club has found its feet
const REPEAT_DAYS := 2 * Defs.DAYS_PER_YEAR


func _init(s: Sim) -> void:
	sim = s
	rng.seed = int(s.rng.seed) ^ 0x51a7e5
	s.hole_finished.connect(_on_hole)
	s.golfer_removed.connect(_on_leave)
	s.month_ended.connect(func(_label: String) -> void: _guarded(_on_month))
	s.tourney.finished.connect(_on_tournament)


func defs() -> Array:
	return sim.db.stories.get("stories", [])


func def_of(r: Dictionary) -> Dictionary:
	return DataDB.find(defs(), str(r.def))


# ------------------------------------------------------------------ hooks

## Run `f` without moving the game's own random numbers.
func _guarded(f: Callable) -> void:
	var state := sim.rng.state
	f.call()
	sim.rng.state = state


## Once a day: time passes for every story, and now and then a new one starts.
func on_day(d: int) -> void:
	if not enabled:
		return
	_guarded(func() -> void:
		for r in running.duplicate():
			_tick_day(r, d)
		if d >= FIRST_DAY and running.size() < cap() and rng.randf() < CAST_CHANCE:
			cast_one())


## Members who are due a round, chosen so that a story's characters get on
## the course: two a story wants together arrive together, and any one of
## them goes to the front of the queue. Empty when the stories have no say.
func pair_due(_due: Array) -> Array:
	if not enabled:
		return []
	var today := sim.day()
	for r in running:
		var def := def_of(r)
		var pair: Array = def.get("together", [])
		if pair.size() < 2:
			continue
		var both: Array = []
		for role: String in pair:
			var m := sim.members.find_member(int((r.cast as Dictionary).get(role, -1)))
			if not m.is_empty() and not bool(m.on_course) and int(m.next_visit) <= today:
				both.append(m)
		if both.size() == pair.size():
			return both
	for r in running:
		for role: String in r.cast:
			var m := sim.members.find_member(int((r.cast as Dictionary)[role]))
			if not m.is_empty() and not bool(m.on_course) and int(m.next_visit) <= today and def_of(r).get("together", []).is_empty():
				return [m]
	return []


## A group has arrived. Characters in it move their stories on.
func on_arrive(gr: Group) -> void:
	if not enabled:
		return
	_guarded(func() -> void:
		for g in gr.members:
			var role_r := _role_of(g)
			if role_r.is_empty():
				continue
			var r: Dictionary = role_r.story
			_show_bubble(r, g)
			_try(r, "visit", {"role": str(role_r.role), "golfer": g}))


func _on_hole(g: Golfer, hole_i: int, score: int) -> void:
	if not enabled:
		return
	_guarded(func() -> void:
		var role_r := _role_of(g)
		if role_r.is_empty():
			return
		var par := sim.course.holes[hole_i].par if hole_i < sim.course.holes.size() else 4
		_try(role_r.story, "hole", {"role": str(role_r.role), "golfer": g, "rel": score - par, "hole": hole_i + 1}))


func _on_leave(g: Golfer) -> void:
	if not enabled or g.holes_played == 0:
		return
	_guarded(func() -> void:
		var role_r := _role_of(g)
		if role_r.is_empty():
			return
		var r: Dictionary = role_r.story
		var counts: Dictionary = r.rounds
		var role := str(role_r.role)
		counts[role] = int(counts.get(role, 0)) + 1
		(r.moods as Dictionary)[role] = g.satisfaction
		_keep_together(r)
		_try(r, "round", {"role": role, "golfer": g, "count": int(counts[role]), "satisfaction": g.satisfaction}))


## Characters a story wants together book the same tee time next visit.
func _keep_together(r: Dictionary) -> void:
	var pair: Array = def_of(r).get("together", [])
	if pair.size() < 2:
		return
	var latest := 0
	var records: Array[Dictionary] = []
	for role: String in pair:
		var m := sim.members.find_member(int((r.cast as Dictionary).get(role, -1)))
		if m.is_empty():
			return
		records.append(m)
		latest = maxi(latest, int(m.next_visit))
	for m in records:
		m.next_visit = maxi(latest, sim.day() + 3)


func _on_tournament(result: Dictionary) -> void:
	if not enabled:
		return
	_guarded(func() -> void:
		var def: Dictionary = result.get("def", {})
		last_event = str(def.get("name", result.get("name", "the tournament")))
		for r in running.duplicate():
			_try(r, "tournament", {}))


func _on_month() -> void:
	for r in running.duplicate():
		_try(r, "month", {})


# ---------------------------------------------------------------- casting

## How many stories can run at once: one on a tiny course, four on a big one.
func cap() -> int:
	return clampi(1 + sim.course.holes.size() / 3, 1, 4)


## Start whichever story fits the club today, if any. Returns its id or "".
func cast_one() -> String:
	var day := sim.day()
	var pool: Array[Dictionary] = []
	var total := 0.0
	for def: Dictionary in defs():
		var id := str(def.id)
		if int(used.get(id, -REPEAT_DAYS)) + REPEAT_DAYS > day and used.has(id):
			continue
		if _is_running(id):
			continue
		if sim.course.holes.size() < int(def.get("min_holes", 0)) or sim.members.count() < int(def.get("min_members", 0)):
			continue
		pool.append(def)
		total += float(def.get("weight", 1.0))
	if pool.is_empty():
		return ""
	var pick := rng.randf() * total
	var chosen: Dictionary = pool[0]
	for def in pool:
		pick -= float(def.get("weight", 1.0))
		if pick <= 0.0:
			chosen = def
			break
	return start(str(chosen.id))


## Start a story by id. Returns the id, or "" if it could not be cast.
## Casting makes club members, which the club's own code does with the
## game's dice, so the game's random state is put back afterwards.
func start(id: String) -> String:
	var out := [""]
	_guarded(func() -> void: out[0] = _start(id))
	return str(out[0])


func _start(id: String) -> String:
	var def := DataDB.find(defs(), id)
	if def.is_empty() or _is_running(id):
		return ""
	var r := {"uid": _uid, "def": id, "stage": "", "cast": {}, "names": {}, "started": sim.day(), "since": sim.day(),
		"rounds": {}, "moods": {}, "hole": 0, "log": [], "request": ""}
	_uid += 1
	var roles: Dictionary = def.get("roles", {})
	var taken: Array[int] = []
	for role: String in roles:
		var spec: Dictionary = roles[role]
		var m := _cast_role(spec, taken)
		if m.is_empty():
			return ""
		taken.append(int(m.id))
		(r.cast as Dictionary)[role] = int(m.id)
		(r.names as Dictionary)[role] = str(m.name)
	# the hole the story is about, if it is about one
	match str(def.get("choose_hole", "")):
		"least_scenic":
			var worst := 1.0e9
			for i in sim.course.holes.size():
				var sc := sim.scenery_score(sim.course.holes[i])
				if sc < worst:
					worst = sc
					r.hole = i + 1
		"random":
			r.hole = 1 + rng.randi() % maxi(sim.course.holes.size(), 1)
	# characters a story wants together come together, and soon
	for role: String in def.get("together", []):
		var m := sim.members.find_member(int((r.cast as Dictionary)[role]))
		if not m.is_empty():
			m.next_visit = sim.day() + 1
	used[id] = sim.day()
	running.append(r)
	var stages: Array = def.get("stages", [])
	if not stages.is_empty():
		_enter(r, str((stages[0] as Dictionary).id))
	return id


func _is_running(id: String) -> bool:
	for r in running:
		if str(r.def) == id:
			return true
	return false


## Fill one role: borrow a member who fits, or make a new regular.
func _cast_role(spec: Dictionary, taken: Array[int]) -> Dictionary:
	if str(spec.get("from", "new")) == "member":
		var fits: Array[Dictionary] = []
		for m in sim.members.roster:
			if taken.has(int(m.id)) or _in_a_story(int(m.id)):
				continue
			if float(m.skill) < float(spec.get("skill_min", 0.0)) or float(m.skill) > float(spec.get("skill_max", 1.0)):
				continue
			if float(m.wealth) < float(spec.get("wealth_min", 0.0)) or int(m.tier) < int(spec.get("tier_min", 0)):
				continue
			fits.append(m)
		if not fits.is_empty():
			var m := fits[rng.randi() % fits.size()]
			m.next_visit = mini(int(m.next_visit), sim.day() + rng.randi_range(1, 4))
			return m
		if spec.has("fallback"):
			return _new_character(spec.fallback)
		return {}
	return _new_character(spec)


## A named regular who joins the club for the story. Their looks and
## abilities come from the story's dice; joining uses the club's own code.
func _new_character(spec: Dictionary) -> Dictionary:
	var g := Golfer.new()
	g.kind = "public"
	g.roll_stats(float(spec.get("skill", 0.4)), rng)
	g.wealth = float(spec.get("wealth", g.wealth))
	var first := sim.db.pick("first", rng)
	var last := sim.db.pick("last", rng)
	g.name = str(spec.get("name", "%s %s" % [first, last]))
	g.handle = str(spec.get("handle", "%s%s%d" % [first, last.left(1), rng.randi_range(2, 99)]))
	var persona := DataDB.find(sim.db.personalities, str(spec.get("persona", "easygoing")))
	if not persona.is_empty():
		g.set_persona(persona)
	g.satisfaction = 70.0
	var m := sim.members.enroll(g, true)
	m.next_visit = sim.day() + rng.randi_range(1, 3)
	return m


func _in_a_story(member_id: int) -> bool:
	for r in running:
		for role: String in r.cast:
			if int((r.cast as Dictionary)[role]) == member_id:
				return true
	return false


## The story and role a golfer on the course is playing, or {}.
func _role_of(g: Golfer) -> Dictionary:
	if g.member.is_empty():
		return {}
	var mid := int(g.member.get("id", -1))
	for r in running:
		for role: String in r.cast:
			if int((r.cast as Dictionary)[role]) == mid:
				return {"story": r, "role": role}
	return {}


## The character for a role, if they are on the course right now.
func golfer_of(r: Dictionary, role: String) -> Golfer:
	var mid := int((r.cast as Dictionary).get(role, -1))
	for g in sim.visitors.golfers:
		if not g.member.is_empty() and int(g.member.get("id", -2)) == mid:
			return g
	return null


# ----------------------------------------------------------------- stages

func stage_of(r: Dictionary) -> Dictionary:
	var def := def_of(r)
	for s: Dictionary in def.get("stages", []):
		if str(s.id) == str(r.stage):
			return s
	return {}


## Move to a stage. Stages that wait for nothing fire at once.
func _enter(r: Dictionary, stage_id: String) -> void:
	var guard := 0
	r.stage = stage_id
	r.since = sim.day()
	while guard < 12:
		guard += 1
		var s := stage_of(r)
		if s.is_empty():
			_end(r, "quiet", "The story ran out of pages.")
			return
		var when: Dictionary = s.get("when", {})
		r.request = _request_text(r, s)
		match str(when.get("type", "")):
			"now":
				if not _fire(r, s, {}):
					return
			"if":
				var ok := _need_met(str(when.get("need", "")), r)
				var to := str(when.get("then", "")) if ok else str(when.get("else", ""))
				if to == "":
					_end(r, "quiet", "The story lost its way.")
					return
				r.stage = to
				r.since = sim.day()
			_:
				return


## Does what happened match what the current stage is waiting for? If so, fire it.
func _try(r: Dictionary, kind: String, what: Dictionary) -> void:
	var s := stage_of(r)
	if s.is_empty():
		return
	var when: Dictionary = s.get("when", {})
	if str(when.get("type", "")) != kind:
		return
	match kind:
		"visit":
			if str(when.get("role", "")) != str(what.get("role", "")):
				return
		"round":
			if str(when.get("role", "")) != str(what.get("role", "")):
				return
			if int(what.get("count", 1)) < int(when.get("count", 1)):
				return
			if float(what.get("satisfaction", 100.0)) < float(when.get("sat_min", -1.0)):
				return
		"hole":
			if str(when.get("role", "")) != str(what.get("role", "")):
				return
			if int(what.get("rel", 0)) > int(when.get("rel", 99)):
				return
			r.hole = int(what.get("hole", r.hole))
	_fire(r, s, what)


## The stage happens: posts, a thought, a toast, the effect, then onward.
## Returns false when the story ended here.
func _fire(r: Dictionary, s: Dictionary, what: Dictionary) -> bool:
	for line: Dictionary in s.get("say", []):
		_post(r, str(line.get("by", "")), str(line.get("text", "")), int(line.get("likes", -1)))
	if s.has("bubble"):
		var b: Dictionary = s.bubble
		var g := golfer_of(r, str(b.get("role", "")))
		if g != null:
			g.bubble = _fill(r, str(b.get("text", "")))
			g.bubble_t = 5.0
			g.bubble_mood = 0
	if s.has("toast"):
		var t: Dictionary = s.toast
		sim.toast.emit(_fill(r, str(t.get("text", ""))), str(t.get("kind", "info")))
	if s.has("effect"):
		_apply(r, s.effect)
	(r.log as Array).append(_fill(r, str(s.get("chapter", s.get("id", "")))))
	if s.has("end"):
		_end(r, str(s.end), _fill(r, str(s.get("ending", ""))))
		return false
	var next := str(s.get("next", ""))
	if next == "":
		_end(r, "quiet", "The story ran out of pages.")
		return false
	_enter(r, next)
	return true


## A day passes for a story: timed stages, met requests, deadlines, stalling.
func _tick_day(r: Dictionary, d: int) -> void:
	var s := stage_of(r)
	if s.is_empty():
		return
	var when: Dictionary = s.get("when", {})
	var waited := d - int(r.since)
	match str(when.get("type", "")):
		"days":
			if waited >= int(when.get("n", 1)):
				_fire(r, s, {})
				return
		"request":
			var all_met := true
			for need: String in (s.get("request", {}) as Dictionary).get("needs", []):
				if not _need_met(need, r):
					all_met = false
			if all_met:
				_fire(r, s, {})
				return
	if s.has("deadline") and waited > int(s.deadline):
		var to := str(s.get("else", ""))
		if to == "":
			_end(r, "quiet", "Time ran out.")
		else:
			_enter(r, to)
		return
	var stall := int(def_of(r).get("stall", 80))
	if waited > stall and not s.has("deadline"):
		_end(r, "quiet", "%s stopped coming." % str((r.names as Dictionary).values()[0]))


func _end(r: Dictionary, how: String, ending: String) -> void:
	running.erase(r)
	var done := {"uid": r.uid, "def": r.def, "title": str(def_of(r).get("title", r.def)), "how": how,
		"ending": ending, "names": r.names, "day": sim.day(), "started": r.started}
	finished.append(done)
	if finished.size() > 30:
		finished.pop_front()
	sim.stats.stories = int(sim.stats.get("stories", 0)) + 1


# ---------------------------------------------------------------- effects

func _apply(r: Dictionary, fx: Dictionary) -> void:
	for m: Dictionary in fx.get("mood", []):
		var g := golfer_of(r, str(m.get("role", "")))
		if g != null:
			g.feel(float(m.get("value", 0.0)), "", "story")
	if fx.has("tip"):
		sim.economy.earn("events", float(fx.tip))
	if fx.has("money"):
		var amount := float(fx.money)
		if amount >= 0.0:
			sim.economy.earn("events", amount)
		else:
			sim.economy.spend("events", -amount)
	if fx.has("members"):
		for i in int(fx.members):
			_new_character({"skill": 0.3 + 0.4 * rng.randf(), "wealth": rng.randf()})
	if fx.has("home"):
		var m := sim.members.find_member(int((r.cast as Dictionary).get(str(fx.home), -1)))
		if not m.is_empty():
			sim.sell_home(m)
	if fx.get("celebrity", false) and sim.events.celebrity == null:
		sim.events._celebrity()
	if fx.has("match"):
		var mt: Dictionary = fx.match
		var mid := int((r.cast as Dictionary).get(str(mt.get("role", "a")), -1))
		var m := sim.members.find_member(mid)
		var holes := mini(3, sim.course.holes.size())
		var stake := float(mt.get("stake", 300))
		var skill := clampf(float(m.get("skill", 0.5)), 0.3, 0.9) if not m.is_empty() else 0.5
		_match_wins = int(sim.stats.get("matches_won", 0))
		sim.events.pending = {
			"id": "match", "title": "A grudge match", "rival": str(m.get("name", "A member")), "holes": holes, "stake": stake, "skill": skill,
			"text": "%s wants the owner in the grudge match: %d hole%s, most holes won takes %s. They play to about a %d handicap." % [
				str(m.get("name", "A member")), holes, "" if holes == 1 else "s", Defs.money(stake), int(round(lerpf(36.0, -3.0, skill)))],
			"options": [{"id": "accept", "text": "You're on (%s)" % Defs.money(stake)}, {"id": "decline", "text": "Not today"}],
		}
		sim.dialog.emit(sim.events.pending)
	if fx.has("flag"):
		flags[str(fx.flag)] = true
	if fx.has("buzz"):
		sim.buzz += float(fx.buzz)
	if fx.has("rating_bias"):
		var rb: Dictionary = fx.rating_bias
		flags["rating_bias"] = {"value": float(rb.get("value", 0.0)), "until": sim.day() + int(rb.get("days", 60))}


## Points the stories add to or take off the course rating right now.
func rating_bias() -> float:
	var rb: Dictionary = flags.get("rating_bias", {})
	if rb.is_empty() or sim.day() >= int(rb.get("until", 0)):
		return 0.0
	return float(rb.get("value", 0.0))


## Is the club's offer to a club pro the cheap one a story earned?
func cheap_pro() -> bool:
	return flags.get("cheap_pro", false)


# ------------------------------------------------------------------ needs

## Something the club has or has done, named in a story.
func _need_met(need: String, r: Dictionary) -> bool:
	var course := sim.course
	var parts := need.split(":")
	var hole_i := int(r.get("hole", 0)) - 1
	match parts[0]:
		"bench_near_water":
			for i in course.objects.size():
				if course.objects[i] == Defs.O.BENCH and _water_near(i % course.w, i / course.w, 3):
					return true
			return false
		"bench_on_hole":
			return hole_i >= 0 and hole_i < course.holes.size() and _objects_along(course.holes[hole_i], Defs.O.BENCH, 3) > 0
		"no_path_on_hole":
			return hole_i >= 0 and hole_i < course.holes.size() and _terrain_along(course.holes[hole_i], Defs.T.PATH, 3) == 0
		"scenery_hole":
			return hole_i >= 0 and hole_i < course.holes.size() and sim.scenery_score(course.holes[hole_i]) >= float(parts[1])
		"homesite":
			return course.objects.has(Defs.O.HOME_SITE)
		"rating":
			return sim.rating >= float(parts[1])
		"holes":
			return course.holes.size() >= int(parts[1])
		"members":
			return sim.members.count() >= int(parts[1])
		"facility":
			return int(sim.visitors.amenity_counts().get(parts[1], 0)) > 0
		"won_match":
			return int(sim.stats.get("matches_won", 0)) > _match_wins
		"role_happy":
			return float((r.moods as Dictionary).get(parts[1], 0.0)) >= float(parts[2])
	return false


## Plain words for what a need wants, and where the club stands.
func need_text(need: String, r: Dictionary) -> String:
	var parts := need.split(":")
	var met := _need_met(need, r)
	var hole := int(r.get("hole", 0))
	var now := ""
	match parts[0]:
		"scenery_hole":
			if hole > 0 and hole <= sim.course.holes.size():
				now = "hole %d scores %d%% for scenery, needs %d%%" % [hole, int(sim.scenery_score(sim.course.holes[hole - 1]) * 100.0), int(float(parts[1]) * 100.0)]
		"homesite":
			now = "a home site is for sale" if met else "no home site for sale (Build, On the course)"
		"bench_near_water":
			now = "there is a bench by the water" if met else "no bench within three tiles of water"
		"bench_on_hole":
			now = "hole %d has a bench" % hole if met else "no bench beside hole %d" % hole
		"no_path_on_hole":
			now = "no cart path near hole %d" % hole if met else "a cart path runs near hole %d" % hole
		"rating":
			now = "rating %d, needs %s" % [int(sim.rating), parts[1]]
		"members":
			now = "%d members, needs %s" % [sim.members.count(), parts[1]]
	return now


func _request_text(r: Dictionary, s: Dictionary) -> String:
	if not s.has("request"):
		return ""
	return _fill(r, str((s.request as Dictionary).get("text", "")))


func _water_near(tx: int, ty: int, reach: int) -> bool:
	var course := sim.course
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var x := tx + dx
			var y := ty + dy
			if course.in_bounds(x, y) and course.terrain[y * course.w + x] == Defs.T.WATER:
				return true
	return false


## How many objects of a kind stand within `reach` tiles of a hole's line.
func _objects_along(hole: Hole, kind: int, reach: int) -> int:
	var course := sim.course
	var seen := {}
	var steps := maxi(2, int(hole.length / Defs.TILE))
	for s in steps + 1:
		var p := hole.tee.lerp(hole.pin, float(s) / steps)
		var t := course.tile_of(p.x, p.z)
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var x := t.x + dx
				var y := t.y + dy
				if course.in_bounds(x, y) and course.objects[y * course.w + x] == kind:
					seen[y * course.w + x] = true
	return seen.size()


func _terrain_along(hole: Hole, kind: int, reach: int) -> int:
	var course := sim.course
	var seen := {}
	var steps := maxi(2, int(hole.length / Defs.TILE))
	for s in steps + 1:
		var p := hole.tee.lerp(hole.pin, float(s) / steps)
		var t := course.tile_of(p.x, p.z)
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var x := t.x + dx
				var y := t.y + dy
				if course.in_bounds(x, y) and course.terrain[y * course.w + x] == kind:
					seen[y * course.w + x] = true
	return seen.size()


# ------------------------------------------------------------------- words

## Fill {a}, {a_first}, {course}, {hole}, {event}, {stake} in a line.
func _fill(r: Dictionary, text: String) -> String:
	var v := {"course": sim.course_name, "hole": str(int(r.get("hole", 0))), "event": last_event, "stake": Defs.money(400.0)}
	for role: String in r.names:
		var name := str((r.names as Dictionary)[role])
		v[role] = name
		v[role + "_first"] = name.split(" ")[0]
	return text.format(v)


func _post(r: Dictionary, role: String, text: String, likes: int) -> void:
	var g := golfer_of(r, role)
	var name := str((r.names as Dictionary).get(role, ""))
	var handle := name.replace(" ", "")
	var m := sim.members.find_member(int((r.cast as Dictionary).get(role, -1)))
	if not m.is_empty():
		handle = str(m.get("handle", handle))
	var n := likes if likes >= 0 else rng.randi_range(3, 60)
	sim.feed.post(_fill(r, text), g, name, handle, 0, n, "story")


## What the Stories panel shows for a running story.
func describe(r: Dictionary) -> Dictionary:
	var def := def_of(r)
	var s := stage_of(r)
	var who: Array[String] = []
	for role: String in r.names:
		who.append(str((r.names as Dictionary)[role]))
	var needs: Array[Dictionary] = []
	if s.has("request"):
		for need: String in (s.request as Dictionary).get("needs", []):
			needs.append({"need": need, "met": _need_met(need, r), "now": need_text(need, r)})
	var left := -1
	if s.has("deadline"):
		left = int(s.deadline) - (sim.day() - int(r.since))
	return {"title": str(def.get("title", r.def)), "who": who, "chapter": _fill(r, str(s.get("chapter", def.get("blurb", "")))),
		"request": _fill(r, str((s.get("request", {}) as Dictionary).get("text", ""))), "needs": needs, "days_left": left,
		"days": sim.day() - int(r.started), "cast": r.cast}


## A character arriving carries their story's name over their head for a
## moment, so the owner can spot them.
func _show_bubble(r: Dictionary, g: Golfer) -> void:
	if g.bubble == "":
		g.bubble = str(def_of(r).get("title", "A story"))
		g.bubble_t = 4.0
		g.bubble_mood = 0


# ------------------------------------------------------------ save and load

func to_dict() -> Dictionary:
	return {"running": running, "finished": finished, "used": used, "flags": flags, "uid": _uid, "event": last_event,
		"match_wins": _match_wins, "rng": str(rng.state)}


func from_dict(d: Dictionary) -> void:
	running.clear()
	for r: Dictionary in d.get("running", []):
		running.append(r)
	finished.clear()
	for f: Dictionary in d.get("finished", []):
		finished.append(f)
	used = d.get("used", {})
	flags = d.get("flags", {})
	_uid = int(d.get("uid", 1))
	last_event = str(d.get("event", ""))
	_match_wins = int(d.get("match_wins", 0))
	if d.has("rng"):
		rng.state = int(str(d.rng))
