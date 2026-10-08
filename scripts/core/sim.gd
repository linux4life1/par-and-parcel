class_name Sim
extends RefCounted
## The whole game world, with no rendering in it. The view watches this and
## draws it; tests run it headless.

signal toast(text: String, kind: String)
signal dialog(d: Dictionary)
signal golfer_added(g: Golfer)
signal golfer_removed(g: Golfer)
signal staff_changed()
signal person_hit(pos: Vector3, hitter: Golfer)
signal hole_finished(g: Golfer, hole_i: int, score: int)
signal month_ended(label: String)
signal scenario_ended(won: bool)
signal popup(pos: Vector3, text: String, kind: String)
## Something made a noise at a place. `id` names the sound (data/sounds.json)
## and `power` is how hard, 0 to 1. The simulation only says what happened;
## what it sounds like is the view's business.
signal sound(id: String, pos: Vector3, power: float)
signal match_accepted(offer: Dictionary)
signal tournament_entry(play: bool)

var db: DataDB
var rng := RandomNumberGenerator.new()
## Next eddy number to hand a golfer. Starts at 1 in every simulation.
var _eddy := 1
var course: Course
var undo: UndoLog              # build steps that Ctrl+Z can take back; not saved
var gear: Gear
var weather := Weather.new()
var grounds: Grounds
var economy := Economy.new()
var opening_money := 0.0       # the purse the club started with, after any bank carried in
var club_id := ""              # this club, so a bank is taken from it only once
var feed: Feed
var skills: Skills
var events: Events
var tourney: Tournaments
var scenario: Scenario
var crew: Crew
var visitors: Visitors
var player: PlayerProfile
var eruption: Eruption
var nav: Nav
var members: Members
var stories: Stories          # the long golfer stories, see stories.gd
var clubhouse_level := 0     # a rung of the ladder in data/clubhouse.json: it sets how many holes the club may have
var difficulty := 2          # index into data/difficulty.json: 0 relaxed .. 4 brutal
var gifts := {}              # object type -> free placements you are owed
var homes := 0               # houses sold on the course
var resort := {}             # resort buildings on the course: id -> true
var lab: HoleLab
var feats: Accomplishments
var wildlife: Wildlife
var rivals: Array = []       # [name, rating] of the courses you are ranked against
var best_rank := 0           # best year-end ranking so far, 0 before the first
var last_rank := 0
var land_credits := 0        # parcels the county has agreed to let you have free
var debt_years := 0
var course_name := "Pine Hollow Golf Club"
var biome: Dictionary = {}
var time := 0.0
var open := true
var playing_round := false   # a round is on the course; build history will not move
var rating := 45.0          # 0..100 quality of the course as golfers see it
var design := 0.0           # the layout's share of the rating
var reputation := 30.0      # follows the rating slowly; drives how many turn up
var buzz := 0.0             # short-lived publicity, good or bad
var last_hit_time := -999.0
var stats := {
	"rounds": 0, "hits": 0, "player_hits": 0, "aces": 0, "holes_played": 0, "refusals": 0, "eruptions": 0, "stories": 0,
	"holes_built": 0, "player_wins": 0, "matches_won": 0, "homes": 0, "celebrity_homes": 0, "tantrums": 0, "windows": 0, "ricochets": 0, "night_holes": 0,
}
var career: Career
var album: Array = []          # aces and tournament wins, kept for the golfer panel and the next course
var clock := 7.0                # hour of the day, 0 to 24
var clock_rate := 1.0           # 0 stops the clock (tests, screenshots)
var told_dark := false          # the player has been told why golfers leave at dusk
var _light_ids: Array[int] = []
var _light_ready := false
var _slow := 0.0
var _day := 0
var _scenery := {}
var _lines_rev := -1
var _lot_rev := -2
var _lot_funs := PackedFloat32Array()
var _lot_builds := 0
var _lot_shade := PackedByteArray()
var _lot_sat := PackedFloat32Array()
var _lot_cellv := PackedFloat32Array()
var _lot_price := PackedFloat32Array()
var _lot_lava := false
var _lot_marina := false
var _mark_rev := -2
var _marks: Array = []
var _mark_scale := PackedFloat32Array()


static var _fresh_n := 0


## A seed for a new club. The clock alone repeats inside one second, so each
## call takes its own tick and two clubs started together do not share dice.
static func fresh_seed() -> int:
	_fresh_n += 1
	var n := int(Time.get_ticks_usec()) + _fresh_n
	if n <= 0:
		n = _fresh_n
	return n


## An id for a new club. It does not draw on the simulation's dice: one extra
## draw there would change every game that follows it. The same counter as
## fresh_seed, so two calls in one tick still differ.
static func fresh_club_id() -> String:
	_fresh_n += 1
	return "%d-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), _fresh_n]


## A save from before clubs had ids. The same file must produce the same id
## on every load, or its bank could be taken again.
static func legacy_club_id(d: Dictionary) -> String:
	return "legacy-%s-%s" % [str(d.get("rng_seed", "")), str(d.get("name", ""))]


func _init(data: DataDB, scen: Dictionary, seed_value: int = 0, shared_gear: Gear = null, biome_id: String = "") -> void:
	db = data
	rng.seed = seed_value if seed_value != 0 else fresh_seed()
	gear = shared_gear if shared_gear != null else Gear.new(db)
	skills = Skills.new(db)
	feed = Feed.new(self)
	grounds = Grounds.new(self)
	crew = Crew.new(self)
	visitors = Visitors.new(self)
	events = Events.new(self)
	tourney = Tournaments.new(self)
	eruption = Eruption.new(self)
	scenario = Scenario.new(scen)
	difficulty = int(db.difficulty.get("default", 2))
	economy.money = float(scen.get("money", 30000))
	opening_money = economy.money
	club_id = fresh_club_id()
	var map: Dictionary = scen.get("map", {})
	biome = db.biome(biome_id if biome_id != "" else str(map.get("biome", "lush")))
	_apply_climate(scen)
	course_name = "%s %s %s" % [db.pick("course_first", rng), db.pick("course_second", rng), db.pick("course_suffix", rng)]
	course = CourseGen.generate(map, rng, biome)
	course.biome = biome
	nav = Nav.new(course)
	undo = UndoLog.new(self)
	_bind_undo()
	members = Members.new(self)
	stories = Stories.new(self)
	lab = HoleLab.new(self)
	feats = Accomplishments.new(self)
	wildlife = Wildlife.new(self)
	wildlife.populate()
	for r: Array in db.names.get("rival_courses", []):
		rivals.append([str(r[0]), float(r[1])])
	for hole in course.holes:
		name_hole(hole)
	# a scenario that hands you more holes than a starter clubhouse allows comes with the clubhouse to match
	clubhouse_level = level_for_holes(course.holes.size())
	career = Career.new(self)
	player = PlayerProfile.new(self)
	player.golfer.course = course
	tag_eddy(player.golfer)
	skills.changed.connect(player.refresh)
	skills.leveled.connect(func(branch: String, lvl: int) -> void:
		toast.emit("%s level %d! You have a new skill point." % ["Manager" if branch == "manager" else "Golfer", lvl], "good"))
	grounds.refresh_layout()
	_update_rating(0.0)
	reputation = rating * 0.7


func _apply_climate(scen: Dictionary) -> void:
	var extra: Dictionary = scen.get("climate", {})
	var c: Dictionary = biome.get("climate", {})
	weather.rain_mult = float(c.get("rain", 1.0)) * float(extra.get("rain", 1.0))
	weather.wind_mult = float(c.get("wind", 1.0)) * float(extra.get("wind", 1.0))
	weather.temp_offset = float(c.get("temp", 0.0))


func is_lava() -> bool:
	return biome.get("lava", false)


## What the player should call a terrain type or an object in this biome.
func terrain_name(t: int) -> String:
	if t == Defs.T.WATER:
		return str(biome.get("hazard", "Water"))
	return Defs.T_NAMES[t]


## What one tile of this paint costs. Waste, stream and bunker read
## data/ground.json. Everything else keeps the table in Defs.
func terrain_price(t: int) -> int:
	var book: Dictionary = db.ground
	var key := ""
	if t == Defs.T.WASTE:
		key = "waste"
	elif t == Defs.T.STREAM:
		key = "stream"
	elif t == Defs.T.BUNKER:
		key = "bunker"
	else:
		return Defs.T_COST[t]
	var row: Dictionary = book.get(key, {})
	if row.has("cost"):
		return int(row["cost"])
	return Defs.T_COST[t]


## How much a greenkeeper cares about this ground. A waste area's care
## is in the data, and it is zero: nobody rakes it.
func terrain_care(t: int) -> float:
	if t != Defs.T.WASTE:
		return Defs.T_CARE[t]
	var row: Dictionary = db.ground.get("waste", {})
	if row.has("care"):
		return float(row["care"])
	return Defs.T_CARE[t]


func object_name(o: int) -> String:
	var over: Dictionary = biome.get("objects", {}).get(str(o), {})
	return str(over.get("name", Defs.O_NAMES[o]))


# ------------------------------------------------------------- the clock

func step(dt: float) -> void:
	refresh_hole_lines()
	time += dt
	clock = fposmod(clock + dt * clock_rate * 24.0 / Defs.CLOCK_DAY_SECONDS, 24.0)
	visitors.step(dt)
	crew.step(dt)
	eruption.step(dt)
	wildlife.step(dt)
	lab.step(dt)
	_slow += dt
	if _slow >= 0.25:
		var sdt := _slow
		_slow = 0.0
		weather.step(sdt, self)
		grounds.step(sdt)
		events.step(sdt)
		tourney.step(sdt)
		_update_rating(sdt)
	var d := day()
	if d != _day:
		_day = d
		_new_day(d)
	settle_pins()


func day() -> int:
	return int(time / Defs.DAY_SECONDS)


## Give a golfer their eddy number for this simulation.
func tag_eddy(g: Golfer) -> void:
	g.eddy = _eddy
	_eddy += 1


## 0 in daylight, 1 at night.
func darkness() -> float:
	return Defs.darkness(clock)


func clock_text() -> String:
	return Defs.clock_text(clock)


## How well a golfer can see at a spot: 1 in daylight or under lights, down
## to 0 on unlit ground in the dead of night.
func sight_at(p: Vector3) -> float:
	var dark := darkness()
	if dark <= 0.0:
		return 1.0
	return 1.0 - dark * (1.0 - course.light_at(p.x, p.z))


## Is this hole in darkness right now? Golfers still play it, but they see
## poorly, enjoy it less and so pay less for it.
func too_dark_for(hole: Hole) -> bool:
	return darkness() > 0.55 and not hole.lit_enough(course)


## The share of the holes that are lit well enough for night golf.
func lit_holes_share() -> float:
	if course.holes.is_empty():
		return 0.0
	var n := 0
	for hole in course.holes:
		if hole.lit_enough(course):
			n += 1
	return float(n) / course.holes.size()


func month() -> int:
	return (day() % Defs.DAYS_PER_YEAR) / Defs.DAYS_PER_MONTH


func year() -> int:
	return day() / Defs.DAYS_PER_YEAR + 1


func date_text() -> String:
	return Defs.date_text(day())


## One page of the album: an ace, or a tournament the owner won.
const ALBUM_MAX := 24


func remember(kind: String, text: String) -> void:
	album.append({"kind": kind, "text": text, "day": day()})
	while album.size() > ALBUM_MAX:
		album.pop_front()


func _new_day(d: int) -> void:
	buzz *= 0.97
	tourney.on_day(d)
	stories.on_day(d)
	_check_awards()
	feats.check()
	scenario.check(self)
	if d % Defs.DAYS_PER_MONTH == 0:
		_end_month(d)
	if d % Defs.DAYS_PER_YEAR == 0 and d > 0:
		_end_year(d / Defs.DAYS_PER_YEAR)
	move_pins()


# ------------------------------------------------------- names and standing

## Give a hole a name nobody else on the course has.
func name_hole(hole: Hole) -> void:
	if hole.name != "":
		return
	var pool: Array = db.names.get("hole_names", [])
	var taken := {}
	for other in course.holes:
		taken[other.name] = true
	for k in 40:
		var cand := str(pool[rng.randi() % pool.size()]) if not pool.is_empty() else "Hole"
		if not taken.has(cand):
			hole.name = cand
			return
	hole.name = "No. %d" % (course.holes.find(hole) + 1)


## Municipal, daily fee, country club or championship, by number of holes.
func course_class() -> String:
	var n := course.holes.size()
	if n >= 18:
		return "Championship course"
	if n >= 10:
		return "Country club"
	if n >= 6:
		return "Daily-fee course"
	return "Municipal course"


## Where the course stands among its rivals right now. 1 is best.
func rank() -> int:
	var r := 1
	for row: Array in rivals:
		if float(row[1]) > rating:
			r += 1
	return r


func _end_year(year_done: int) -> void:
	var r := rank()
	last_rank = r
	if best_rank == 0 or r < best_rank:
		best_rank = r
	toast.emit("Year %d rankings: your course finishes number %d of %d." % [year_done, r, rivals.size() + 1], "good" if r <= 5 else "info")
	feed.say("rank", null, {"rank": r, "total": rivals.size() + 1}, true, "Golf Enquirer", "GolfEnquirer")
	skills.add_xp("manager", maxi(0, 16 - r))
	# rivals do not stand still
	for row: Array in rivals:
		row[1] = clampf(float(row[1]) + rng.randf_range(-2.0, 2.0), 25.0, 97.0)
	if economy.money < 0.0:
		debt_years += 1
		if debt_years >= 2 and scenario.status == "active":
			scenario.status = "lost"
			toast.emit("Two years in debt. The board has run out of patience.", "bad")
			scenario_ended.emit(false)
		else:
			toast.emit("The club ended the year in debt. The board is watching.", "bad")
	else:
		debt_years = 0
	_judge_themes()
	feats.check()


## The golf magazines notice a hole that golfers love and that asks
## something of them.
func _check_awards() -> void:
	for i in course.holes.size():
		var hole := course.holes[i]
		if hole.plays < 25 or not hole.lab_ready:
			continue
		if hole.award == "" and hole.fun >= 70.0 and hole.kind != 0:
			hole.award = "top100"
			buzz += 6.0
			toast.emit("Hole %d, %s, has been named one of the Top 100 holes in golf. Golfers will pay more to play it." % [i + 1, hole.name], "good")
			feed.say("top100", null, {"hole": i + 1}, true, "Golf Enquirer", "GolfEnquirer")
		elif hole.award == "top100" and hole.fun >= 82.0 and hole.kind >= 5:
			hole.award = "top18"
			buzz += 12.0
			toast.emit("Hole %d, %s, is in the Dream Eighteen: the best eighteen holes anywhere." % [i + 1, hole.name], "good")
			feed.say("top18", null, {"hole": i + 1}, true, "Great Golf Holes", "GreatGolfHoles")
	_slip_themes()


func _end_month(d: int) -> void:
	economy.earn("memberships", members.monthly_dues())
	economy.earn("real_estate", homes * 45.0)
	economy.spend("wages", crew.monthly_wages())
	economy.spend("upkeep", monthly_upkeep())
	course.settle_month()
	if economy.money < 0.0:
		economy.spend("interest", -economy.money * 0.02)
	var prev := Defs.date_parts(d - 1)
	var label := "%s, Year %d" % [Defs.MONTH_NAMES[prev.month], prev.year]
	var net := economy.net()
	economy.close_month(label, rating, visitors.average_satisfaction() if not visitors.recent.is_empty() else -1.0)
	toast.emit("%s closed: %s%s." % [Defs.MONTH_NAMES[prev.month], "profit of " if net >= 0.0 else "loss of ", Defs.money(absf(net))], "good" if net >= 0.0 else "bad")
	month_ended.emit(label)


func monthly_upkeep() -> float:
	var t := course.holes.size() * 15.0
	var share := light_on_share()
	var objs := course.objects
	for i in objs.size():
		var o := int(objs[i])
		if o == 0:
			continue
		# Open now, or open earlier this month: closing just before the bill
		# does not make the month free.
		if course.is_closed(i) and course.open_month[i] == 0:
			continue
		var cost := float(Defs.O_UPKEEP[o])
		if _light_kind(o):
			cost *= share
		t += cost
	return t


## The share of a day the floodlights and lamp posts are switched on:
## sunset until sunrise. Their upkeep is that share of the listed amount.
## A building that also glows still pays in full.
func light_on_share() -> float:
	var hours := Defs.SUNRISE - Defs.SUNSET
	if hours <= 0.0:
		hours += 24.0
	return clampf(hours / 24.0, 0.0, 1.0)


func _light_kind(o: int) -> bool:
	if not _light_ready:
		_light_ready = true
		for name in db.lights.get("kinds", []):
			var i := Defs.O_NAMES.find(str(name))
			if i >= 0:
				_light_ids.append(i)
	return _light_ids.has(o)


## How long the starter holds the next party, in the steps the panel offers.
func starter_step() -> float:
	return float(db.starter.get("step", 15.0))


func starter_max() -> float:
	return float(db.starter.get("max", 90.0))


func nudge_gap(hole: Hole, dir: int) -> void:
	var step := starter_step()
	hole.gap = clampf(hole.gap + step * float(dir), 0.0, starter_max())


## "No hold", or the gap on the course clock.
func starter_text(hole: Hole) -> String:
	if hole.gap <= 0.0:
		return "No hold"
	return "Holds %s" % Defs.pace_text(hole.gap)


func theme_name(id: String) -> String:
	var row := _theme(id)
	if row.is_empty():
		return id
	return str(row.get("name", id))


## The extra share of a green fee a themed award adds. One award, one share.
func theme_fee(hole: Hole) -> float:
	var bonus := 0.0
	var seen := {}
	for id in hole.themes:
		var key := str(id)
		if seen.has(key):
			continue
		seen[key] = true
		bonus += float(_theme(key).get("fee", 0.0))
	return bonus


func _theme(id: String) -> Dictionary:
	for row in db.awards.get("themes", []):
		if row is Dictionary and str(row.get("id", "")) == id:
			return row
	return {}


## Still the hole the award was given for: loved, played, and still that kind.
func _theme_holds(hole: Hole, row: Dictionary) -> bool:
	if row.is_empty() or not hole.open or not hole.lab_ready or hole.kind == 0:
		return false
	if hole.plays < int(row.get("plays", 20)) or hole.fun < float(row.get("fun", 68.0)):
		return false
	var id := str(row.get("id", ""))
	if id == "par3":
		return hole.par == 3
	if id == "water":
		return hole.touches_water(course)
	if id == "night":
		return hole.lit_enough(course)
	return false


## Take a themed award back the day the hole stops deserving it.
func _slip_themes() -> void:
	for hole in course.holes:
		var i := hole.themes.size() - 1
		while i >= 0:
			var id := hole.themes[i]
			if not _theme_holds(hole, _theme(id)):
				hole.themes.remove_at(i)
				var who := hole.name if hole.name != "" else "Hole %d" % (course.holes.find(hole) + 1)
				toast.emit("%s no longer deserves the %s." % [who, theme_name(id)], "bad")
			i -= 1


## Once a year, name the best hole of each theme. A hole that has slipped
## already lost it. A better hole takes it over.
func _judge_themes() -> void:
	for row in db.awards.get("themes", []):
		if not (row is Dictionary):
			continue
		var spec: Dictionary = row
		var id := str(spec.get("id", ""))
		if id == "":
			continue
		var best: Hole = null
		var best_fun := -1.0
		for hole in course.holes:
			if not _theme_holds(hole, spec):
				continue
			if hole.fun > best_fun:
				best = hole
				best_fun = hole.fun
		for hole in course.holes:
			var has := hole.themes.has(id)
			if hole == best:
				if not has:
					hole.themes.append(id)
					var who := hole.name if hole.name != "" else "Hole %d" % (course.holes.find(hole) + 1)
					toast.emit("%s is named %s." % [who, theme_name(id)], "good")
					feed.say(id, null, {"hole": course.holes.find(hole) + 1}, true, "Golf Enquirer", "GolfEnquirer")
			elif has:
				hole.themes.erase(id)
				if best == null:
					var who := hole.name if hole.name != "" else "Hole %d" % (course.holes.find(hole) + 1)
					toast.emit("%s no longer deserves the %s." % [who, theme_name(id)], "bad")


# ------------------------------------------------------- course standing

func _update_rating(dt: float) -> void:
	var n := course.open_count()
	var pars := {}
	var scenery := 0.0
	for hole in course.holes:
		if hole.open:
			pars[hole.par] = true
			scenery += scenery_score(hole)
	if n == 0:
		rating = 0.0
		design = 0.0
		reputation = move_toward(reputation, 5.0, dt * 0.05)
		return
	var am := visitors.amenity_counts()
	resort = {}
	for key: String in ["tennis", "hotel", "marina", "airstrip"]:
		if int(am.get(key, 0)) > 0:
			resort[key] = true
	var d := 0.0
	var lines: Array = db.accreditation.get("lines", [])
	for item in lines:
		if item is Dictionary:
			d += _accredit_points(item, n, pars.size(), scenery, am)
	design = clampf(d, 0.0, 100.0)
	rating = clampf(0.4 * visitors.average_satisfaction() + 15.0 * grounds.condition + 0.45 * design + stories.rating_bias(), 0.0, 100.0)
	reputation = move_toward(reputation, rating, dt * 0.04)


## The design score, one line at a time: what the club has, what it is worth,
## and the next thing that line wants. The points are the score. A round's
## length is on the list and adds nothing. Nothing counts until a hole is open.
func accreditation() -> Array[Dictionary]:
	var n := course.open_count()
	var pars := {}
	var scenery := 0.0
	for hole in course.holes:
		if not hole.open:
			continue
		pars[hole.par] = true
		scenery += scenery_score(hole)
	var am := visitors.amenity_counts()
	var out: Array[Dictionary] = []
	var lines: Array = db.accreditation.get("lines", [])
	for item in lines:
		if item is Dictionary:
			out.append(_accredit_line(item, n, pars.size(), scenery, am))
	return out


func _accredit_points(line: Dictionary, n: int, kinds: int, scenery: float, am: Dictionary) -> float:
	match str(line.get("kind", "")):
		"holes":
			var cap := int(line.get("cap", 18))
			var full := float(line.get("points", 0.0))
			return minf(float(n), float(cap)) / float(cap) * full
		"pars":
			var steps: Array = line.get("points", [])
			if n == 0 or steps.is_empty():
				return 0.0
			return float(steps[mini(kinds, maxi(steps.size() - 1, 0))])
		"count", "any":
			if n == 0:
				return 0.0
			var cap := int(line.get("cap", 1))
			var each := float(line.get("each", 0.0))
			return float(mini(_accredit_have(line, am), cap)) * each
		"clubhouse":
			if n == 0:
				return 0.0
			return float(clubhouse_level) * float(line.get("each", 0.0))
		"scenery":
			if n == 0:
				return 0.0
			return scenery / float(n) * float(line.get("points", 0.0))
		_:
			return 0.0


func _accredit_line(line: Dictionary, n: int, kinds: int, scenery: float, am: Dictionary) -> Dictionary:
	var id := str(line.get("id", ""))
	var text := str(line.get("text", ""))
	var kind := str(line.get("kind", ""))
	var pts := _accredit_points(line, n, kinds, scenery, am)
	var have := 0
	var met := false
	var next := ""
	var detail := ""
	match kind:
		"holes":
			var cap := int(line.get("cap", 18))
			var full := float(line.get("points", 0.0))
			have = n
			met = n >= cap
			detail = "%d of %d, worth %s of %s." % [mini(n, cap), cap, _accredit_num(pts), _accredit_num(full)]
			if n == 0:
				next = str(line.get("next_none", ""))
			elif not met:
				next = str(line.get("next", ""))
		"pars":
			var steps: Array = line.get("points", [])
			var top := 0.0 if steps.is_empty() else float(steps[steps.size() - 1])
			have = kinds
			met = n > 0 and not steps.is_empty() and kinds >= steps.size() - 1
			var word := "No pars yet" if kinds == 0 else ("%d different par%s" % [kinds, "" if kinds == 1 else "s"])
			detail = "%s, worth %s of %s." % [word, _accredit_num(pts), _accredit_num(top)]
			if n > 0 and not met:
				next = str(line.get("next", ""))
		"count", "any":
			var cap := int(line.get("cap", 1))
			var each := float(line.get("each", 0.0))
			have = _accredit_have(line, am)
			var used := mini(have, cap)
			var full := float(cap) * each
			met = have >= cap
			detail = "%d of %d, worth %s of %s." % [used, cap, _accredit_num(pts), _accredit_num(full)]
			if n == 0 and met:
				detail += " It counts once a hole is open."
			elif not met:
				next = str(line.get("next", ""))
		"clubhouse":
			var each := float(line.get("each", 0.0))
			var top_level := maxi(clubhouse_levels().size() - 1, 0)
			have = clubhouse_level
			var full := float(top_level) * each
			met = clubhouse_top()
			detail = "%s, worth %s of %s." % [clubhouse_name(), _accredit_num(pts), _accredit_num(full)]
			if n == 0 and met:
				detail += " It counts once a hole is open."
			elif not met:
				next = str(line.get("next", ""))
		"scenery":
			var full := float(line.get("points", 0.0))
			met = n > 0 and pts >= full - 0.05
			detail = "Worth %s of %s." % [_accredit_num(pts), _accredit_num(full)]
			if n > 0 and not met:
				next = str(line.get("next", ""))
		"pace":
			if n == 0:
				detail = str(line.get("next_none", ""))
				next = detail
			elif not course.times_complete():
				detail = str(line.get("waiting", ""))
				if course.round_time() > 0.0:
					detail = "Timed holes so far add up to %s. %s" % [Defs.pace_text(course.round_time()), detail]
				next = str(line.get("waiting", ""))
			else:
				var secs := course.round_time()
				met = secs <= Defs.ROUND_LONG
				detail = "A round takes about %s." % Defs.pace_text(secs)
				if met:
					detail += " " + str(line.get("done", ""))
				else:
					next = str(line.get("next", ""))
					detail += " " + next
	if met and next == "" and str(line.get("done", "")) != "" and kind != "pace":
		detail += " " + str(line.get("done", ""))
	elif next != "" and kind != "pace":
		detail += " " + next
	return {"id": id, "text": text, "detail": detail, "points": pts, "have": have, "met": met, "next": next}


func _accredit_have(line: Dictionary, am: Dictionary) -> int:
	var n := 0
	if str(line.get("kind", "")) == "any":
		var keys: Array = line.get("keys", [])
		for key in keys:
			n += int(am.get(str(key), 0))
		var staff := str(line.get("staff", ""))
		if staff != "":
			n += crew.count(staff)
	else:
		n = int(am.get(str(line.get("key", "")), 0))
	return n


func _accredit_num(v: float) -> String:
	if absf(v - round(v)) < 0.001:
		return str(roundi(v))
	if absf(v * 10.0 - round(v * 10.0)) < 0.001:
		return "%.1f" % v
	return "%.2f" % v


func stars() -> float:
	return rating / 20.0


## A golfer's first impression of a club that owes money. Nothing while the
## balance is clear, and never drawn from the random numbers.
func debt_arrival() -> float:
	if economy.money >= 0.0:
		return 0.0
	return float(db.debt.get("arrival", -4.0))


## Groups arriving per second of sim time.
func arrival_rate() -> float:
	var pull := clampf((reputation + buzz) / 100.0, 0.0, 1.3)
	var r := (1.0 / 38.0) * (0.3 + pull * 1.2) * skills.mult("arrivals")
	match weather.kind:
		Weather.K.DRIZZLE:
			r *= 0.75
		Weather.K.RAIN:
			r *= 0.45
		Weather.K.STORM:
			r *= 0.08
		Weather.K.CLEAR:
			r *= 1.1
	if events.banners_up():
		r *= 0.95
	if resort.has("hotel"):
		r *= 1.15
	if eruption.active():
		r *= 0.1
	# Daylight is the busy time. After dark only the keen turn up, unless
	# the course is lit: a fully lit course is nearly as busy by night.
	r *= lerpf(1.2, 0.22 + 0.78 * lit_holes_share(), darkness())
	return r


func thirst_rate() -> float:
	var r := 1.0 / 400.0
	if weather.temp > 24.0:
		r *= 1.6
	if time < weather.heat_until:
		r *= 1.5
	return r


func clubhouse_door() -> Vector3:
	var c := course.tile_center(course.clubhouse.x, course.clubhouse.y)
	return course.on_ground(c.x, c.z - 9.0)


## Remeasure any hole whose ground has changed, so par follows the fairway
## as it is repainted. The fingerprint is the one the hole lab already uses.
func refresh_hole_lines() -> void:
	if _lines_rev == course.revision:
		return
	_lines_rev = course.revision
	for hole in course.holes:
		var sig := lab._signature(hole)
		if sig == hole.line_sig and hole.route.size() >= 2:
			continue
		hole.update_metrics(course)
		hole.line_sig = sig


## 0..1: how much there is to look at along a hole.
func scenery_score(hole: Hole) -> float:
	var cached: Array = _scenery.get(hole, [])
	if not cached.is_empty() and int(cached[0]) == course.revision:
		return cached[1]
	var total := 0.0
	var samples := 0
	var steps := maxi(2, int(hole.length / 15.0))
	for s in steps + 1:
		var p := hole.point_along(float(s) / steps)
		var tile := course.tile_of(p.x, p.z)
		samples += 1
		for ty in range(tile.y - 4, tile.y + 5):
			for tx in range(tile.x - 4, tile.x + 5):
				if not course.in_bounds(tx, ty):
					continue
				var i := ty * course.w + tx
				if not course.is_closed(i):
					total += Defs.O_SCENERY[course.objects[i]]
				if Defs.is_liquid(course.terrain[i]):
					total += 0.25
	var score := clampf(total / (samples * 9.0), 0.0, 1.0)
	_scenery[hole] = [course.revision, score]
	return score


func _ensure_marks() -> void:
	if _mark_rev == course.revision:
		return
	_mark_rev = course.revision
	_marks.clear()
	var by_obj := {}
	for kind in db.landmarks.get("kinds", []):
		if kind is Dictionary:
			by_obj[int(kind.get("object", -1))] = kind
	var objs := course.objects
	for i in objs.size():
		var o := int(objs[i])
		if not by_obj.has(o) or course.is_closed(i):
			continue
		var kind: Dictionary = by_obj[o]
		var p := course.tile_center(i % course.w, int(i / course.w))
		_marks.append({
			"x": p.x, "z": p.z,
			"radius": float(kind.get("radius", 42.0)),
			"mood": float(kind.get("mood", 0.0)),
			"weeds": float(kind.get("weeds", 1.0)),
			"story": float(kind.get("story", 0.0)),
		})
	var n := course.w * course.h
	_mark_scale = PackedFloat32Array()
	_mark_scale.resize(n)
	_mark_scale.fill(1.0)
	for m: Dictionary in _marks:
		var rad: float = float(m.radius)
		var reach := int(ceil(rad / Defs.TILE))
		var hx := int(float(m.x) / Defs.TILE)
		var hz := int(float(m.z) / Defs.TILE)
		var calm := float(m.weeds)
		for oy in range(-reach, reach + 1):
			for ox in range(-reach, reach + 1):
				var x := hx + ox
				var y := hz + oy
				if not course.in_bounds(x, y):
					continue
				var cx := (x + 0.5) * Defs.TILE
				var cz := (y + 0.5) * Defs.TILE
				if Vector2(cx - float(m.x), cz - float(m.z)).length_squared() > rad * rad:
					continue
				var ti := y * course.w + x
				_mark_scale[ti] = minf(_mark_scale[ti], calm)


## The landmark covering this spot, or an empty dictionary.
func mark_at(x: float, z: float) -> Dictionary:
	_ensure_marks()
	var best: Dictionary = {}
	var best_d := 1.0e12
	for m: Dictionary in _marks:
		var dx: float = x - float(m.x)
		var dz: float = z - float(m.z)
		var rad: float = float(m.radius)
		var d2 := dx * dx + dz * dz
		if d2 <= rad * rad and d2 < best_d:
			best_d = d2
			best = m
	return best


## How much a landmark slows the weeds on this tile. 1 where nothing stands.
func weed_scale(i: int) -> float:
	_ensure_marks()
	if i < 0 or i >= _mark_scale.size():
		return 1.0
	return _mark_scale[i]


## Once a round, a golfer inside a landmark's circle feels it, and a story
## character takes a step toward a happy ending.
func touch_landmark(g: Golfer) -> bool:
	if g.rd.has("landmark"):
		return false
	var m := mark_at(g.pos.x, g.pos.z)
	if m.is_empty():
		return false
	g.rd["landmark"] = true
	var mood := float(m.get("mood", 0.0))
	if not is_zero_approx(mood):
		g.feel(mood, "That landmark is worth the walk.", "scenery")
	stories.note_landmark(g, float(m.get("story", 0.0)))
	return true


# ------------------------------------------------- building, with a budget

func _bind_undo() -> void:
	course.watch_edits(Callable(undo, "note_tile"), Callable(undo, "note_height"), Callable(undo, "clear"))


## Paint terrain with a round brush. Returns tiles changed, or -1 if broke.
func paint(tx: int, ty: int, radius: int, t: int) -> int:
	if t == Defs.T.STREAM:
		stream_drag_begin()
		var one: Array[Vector2i] = [Vector2i(tx, ty)]
		return paint_stream(one)
	var unit := float(terrain_price(t))
	if not economy.can_afford(unit):
		return -1
	var started := undo.begin()
	var n := course.paint(tx, ty, radius, t)
	if n > 0:
		var bill := n * unit + course.clear_cost
		economy.spend("construction", bill)
		undo.note_charge(bill)
		if Defs.is_green(t) or t == Defs.T.TEE:
			# Fresh greens and tees are graded as they are laid, so they are
			# playable straight away. Sculpt them afterwards to add break.
			var c := course.tile_center(tx, ty)
			for i in 2:
				course.smooth(c.x, c.z, (radius + 1.5) * Defs.TILE, 0.5)
	if started:
		undo.commit()
	return n


## The height of the last tile accepted on the stream drag in progress.
var _stream_have := false
var _stream_h := 0.0


## A new drag forgets the last stream, so the first tile is always taken.
func stream_drag_begin() -> void:
	_stream_have = false


## Draw a stream along a drag. One tile wide, downhill only. Each call is
## one move of the mouse, and it is judged against the last tile this drag
## accepted, including the first tile of the new line. The price is the
## stream's price in the data, once per tile that actually changes.
func paint_stream(tiles: Array[Vector2i]) -> int:
	var unit := float(terrain_price(Defs.T.STREAM))
	if not economy.can_afford(unit):
		return -1
	# A drag already has a stroke open. A single tile, from paint(), opens
	# its own and records the charge, so undo can give that money back.
	var started := undo.begin()
	var follow := 1.0e20
	if _stream_have:
		follow = _stream_h
	var n := course.lay_stream(tiles, follow)
	if course.stream_took:
		_stream_have = true
		_stream_h = course.stream_held
	if n > 0:
		var bill := n * unit + course.clear_cost
		economy.spend("construction", bill)
		undo.note_charge(bill)
	if started:
		undo.commit()
	return n


## Why an object cannot be built yet, or "" if it can.
func build_block(o: int) -> String:
	var need: int = Defs.O_MIN_HOLES[o]
	if course.holes.size() < need and str(scenario.def.get("id", "")) != "sandbox":
		return "Needs %d holes" % need
	if o == Defs.O.LANDMARK and _landmarks_standing() >= 2 and int(gifts.get(o, 0)) == 0:
		return "Two landmarks is the limit"
	return ""


## Landmarks standing on the course, open or closed. Closing one does not
## free the slot.
func _landmarks_standing() -> int:
	var n := 0
	for i in course.objects.size():
		if int(course.objects[i]) == Defs.O.LANDMARK:
			n += 1
	return n


func place_object(tx: int, ty: int, o: int) -> int:
	if build_block(o) != "":
		return 0
	var free := int(gifts.get(o, 0)) > 0
	var cost := 0.0 if free else float(Defs.O_COST[o])
	if not economy.can_afford(cost):
		return -1
	if not course.can_build(tx, ty):
		return 0
	var t := course.terrain[ty * course.w + tx]
	if Defs.is_green(t) or t == Defs.T.TEE or t == Defs.T.BUNKER:
		return 0
	var started := undo.begin()
	var placed := 0
	if course.set_object(tx, ty, o):
		economy.spend("construction", cost)
		undo.note_charge(cost)
		if free:
			gifts[o] = int(gifts[o]) - 1
			undo.note_gift(o)
		placed = 1
	if started:
		undo.commit()
	return placed


## What a home site is worth to a buyer: views, water and a good course push
## it up; a lot in the line of fire pushes it down.
func lot_value(tx: int, ty: int) -> float:
	var v := 1200.0 + rating * 22.0
	for y in range(ty - 4, ty + 5):
		for x in range(tx - 4, tx + 5):
			if not course.in_bounds(x, y) or (x == tx and y == ty):
				continue
			var i := y * course.w + x
			var o := course.objects[i]
			if not course.is_closed(i):
				v += Defs.O_SCENERY[o] * 55.0
			if o == Defs.O.HOUSE or o == Defs.O.HOME_SITE:
				v -= 60.0
			if Defs.is_liquid(course.terrain[i]) and not (is_lava() and course.terrain[i] == Defs.T.WATER):
				v += 22.0
	var p := Vector2((tx + 0.5) * Defs.TILE, (ty + 0.5) * Defs.TILE)
	for hole in course.holes:
		var end := hole.design_pin()
		var d := Ball._seg_dist(Vector2(hole.tee.x, hole.tee.z), Vector2(end.x, end.z), p)
		if d < 22.0:
			v -= 700.0
		elif d < 70.0:
			v += hole.fun * 4.0
	if resort.has("marina"):
		v *= 1.4
	return float(int(maxf(v, 500.0) / 50.0) * 50)


## 0 is the cheapest ground on the course right now, 255 the dearest.
## The shade is relative, so the course rating does not change it. Kept
## until the course changes, or any one hole's fun has moved by a point.
## The 9 by 9 neighbourhood is a summed-area table, so a rebuild does not
## walk those neighbours again for every tile. lot_value stays the reference.
func lot_shade() -> PackedByteArray:
	var n := course.w * course.h
	if _lot_rev == course.revision and _lot_fun_held() and _lot_shade.size() == n:
		return _lot_shade
	_lot_rev = course.revision
	_lot_funs.resize(course.holes.size())
	for i in course.holes.size():
		_lot_funs[i] = course.holes[i].fun
	_lot_builds += 1
	_build_lot_sat()
	_price_lots()
	var lo := 1.0e12
	var hi := -1.0e12
	for i in n:
		var v := _lot_price[i]
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_lot_shade.resize(n)
	var span := hi - lo
	for i in n:
		var t := 0.5 if span < 1.0 else (_lot_price[i] - lo) / span
		_lot_shade[i] = int(clampf(t, 0.0, 1.0) * 255.0)
	return _lot_shade


func _lot_fun_held() -> bool:
	if _lot_funs.size() != course.holes.size():
		return false
	for i in course.holes.size():
		if absf(course.holes[i].fun - _lot_funs[i]) >= 1.0:
			return false
	return true


## What one tile adds to a neighbour's price. The centre tile is left out,
## the same way lot_value skips it.
func _lot_cell(i: int) -> float:
	var o := int(course.objects[i])
	var a := 0.0 if course.is_closed(i) else Defs.O_SCENERY[o] * 55.0
	if o == Defs.O.HOUSE or o == Defs.O.HOME_SITE:
		a -= 60.0
	if Defs.is_liquid(course.terrain[i]) and not (_lot_lava and course.terrain[i] == Defs.T.WATER):
		a += 22.0
	return a


func _build_lot_sat() -> void:
	_lot_lava = is_lava()
	_lot_marina = resort.has("marina")
	var w := course.w
	var h := course.h
	var stride := w + 1
	if _lot_sat.size() != stride * (h + 1):
		_lot_sat = PackedFloat32Array()
		_lot_sat.resize(stride * (h + 1))
	else:
		_lot_sat.fill(0.0)
	if _lot_cellv.size() != w * h:
		_lot_cellv = PackedFloat32Array()
		_lot_cellv.resize(w * h)
	for y in h:
		var run := 0.0
		var row := y * w
		var below := y * stride
		var dest := (y + 1) * stride
		for x in w:
			var cell := _lot_cell(row + x)
			_lot_cellv[row + x] = cell
			run += cell
			_lot_sat[dest + x + 1] = _lot_sat[below + x + 1] + run


## Prices every tile from the table. Hole geometry is cached so the inner
## loop does not build vectors or call out.
func _price_lots() -> void:
	var w := course.w
	var h := course.h
	var n := w * h
	var stride := w + 1
	var tile := Defs.TILE
	var base := 1200.0 + rating * 22.0
	var nh := course.holes.size()
	var hx := PackedFloat32Array()
	var hz := PackedFloat32Array()
	var abx := PackedFloat32Array()
	var abz := PackedFloat32Array()
	var inv := PackedFloat32Array()
	var fun := PackedFloat32Array()
	hx.resize(nh)
	hz.resize(nh)
	abx.resize(nh)
	abz.resize(nh)
	inv.resize(nh)
	fun.resize(nh)
	for hi in nh:
		var hole := course.holes[hi]
		hx[hi] = hole.tee.x
		hz[hi] = hole.tee.z
		var end := hole.design_pin()
		var dx := end.x - hole.tee.x
		var dz := end.z - hole.tee.z
		abx[hi] = dx
		abz[hi] = dz
		var l2 := dx * dx + dz * dz
		inv[hi] = 0.0 if l2 < 1e-9 else 1.0 / l2
		fun[hi] = hole.fun
	if _lot_price.size() != n:
		_lot_price = PackedFloat32Array()
		_lot_price.resize(n)
	var marina := _lot_marina
	for y in h:
		var pz := (float(y) + 0.5) * tile
		var y0 := maxi(y - 4, 0)
		var y1 := mini(y + 4, h - 1)
		var row := y * w
		for x in w:
			var x0 := maxi(x - 4, 0)
			var x1 := mini(x + 4, w - 1)
			var neigh := _lot_sat[(y1 + 1) * stride + (x1 + 1)] - _lot_sat[y0 * stride + (x1 + 1)] - _lot_sat[(y1 + 1) * stride + x0] + _lot_sat[y0 * stride + x0]
			var v := base + neigh - _lot_cellv[row + x]
			var px := (float(x) + 0.5) * tile
			for hi in nh:
				var d2: float
				if inv[hi] == 0.0:
					var ddx := hx[hi] - px
					var ddz := hz[hi] - pz
					d2 = ddx * ddx + ddz * ddz
				else:
					var tt := clampf(((px - hx[hi]) * abx[hi] + (pz - hz[hi]) * abz[hi]) * inv[hi], 0.0, 1.0)
					var qx := hx[hi] + abx[hi] * tt - px
					var qz := hz[hi] + abz[hi] * tt - pz
					d2 = qx * qx + qz * qz
				if d2 < 484.0:
					v -= 700.0
				elif d2 < 4900.0:
					v += fun[hi] * 4.0
			if marina:
				v *= 1.4
			_lot_price[row + x] = float(int(maxf(v, 500.0) / 50.0) * 50)


## A member buys a free home site, if there is one. The lot becomes a house.
func sell_home(m: Dictionary, celebrity: bool = false) -> bool:
	if m.get("home", false):
		return false
	var best := -1
	var best_v := 0.0
	for i in course.objects.size():
		if course.objects[i] == Defs.O.HOME_SITE:
			var v := lot_value(i % course.w, i / course.w)
			if v > best_v:
				best_v = v
				best = i
	if best < 0:
		return false
	if undo != null:
		undo.clear()
	if celebrity:
		best_v *= 3.0
	m["home"] = true
	homes += 1
	stats.homes = int(stats.homes) + 1
	if celebrity:
		stats.celebrity_homes = int(stats.celebrity_homes) + 1
	course.objects[best] = Defs.O.HOUSE
	course.objects_touched(best)
	course.revision += 1
	course.objects_changed.emit()
	economy.earn("real_estate", best_v)
	toast.emit("%s bought a home site on the course for %s." % [str(m.name), Defs.money(best_v)], "good")
	feed.say("home", null, {"hole": 1 + rng.randi() % maxi(course.holes.size(), 1)}, true, str(m.name), str(m.get("handle", "Member")))
	return true


## One of the difficulty slider's multipliers (see data/difficulty.json):
## fee, mood_bad, mood_good, weeds, pests, wear, wages.
func diff(key: String) -> float:
	var levels: Array = db.difficulty.get("levels", [])
	if levels.is_empty():
		return 1.0
	var lv: Dictionary = levels[clampi(difficulty, 0, levels.size() - 1)]
	return float(lv.get(key, 1.0))


## Move the difficulty slider. Takes effect at once.
func set_difficulty(level: int) -> void:
	var levels: Array = db.difficulty.get("levels", [])
	difficulty = clampi(level, 0, maxi(levels.size() - 1, 0))
	if visitors != null:
		visitors.apply_difficulty()


## One sentence on how this level differs from Normal, for a toast.
func difficulty_blurb() -> String:
	var levels: Array = db.difficulty.get("levels", [])
	if levels.is_empty():
		return ""
	var lv: Dictionary = levels[clampi(difficulty, 0, levels.size() - 1)]
	var bits: Array[String] = []
	var fee := float(lv.get("fee", 1.0))
	if not is_equal_approx(fee, 1.0):
		bits.append("golfers pay %d%% %s" % [int(round(absf(fee - 1.0) * 100.0)), "more" if fee > 1.0 else "less"])
	var bad := float(lv.get("mood_bad", 1.0))
	if not is_equal_approx(bad, 1.0):
		bits.append("bad moments hit %d%% %s" % [int(round(absf(bad - 1.0) * 100.0)), "harder" if bad > 1.0 else "softer"])
	var weeds := float(lv.get("weeds", 1.0))
	if not is_equal_approx(weeds, 1.0):
		bits.append("weeds and pests %s %d%% %s" % ["spread" if weeds > 1.0 else "come", int(round(absf(weeds - 1.0) * 100.0)), "faster" if weeds > 1.0 else "slower"])
	var wages := float(lv.get("wages", 1.0))
	if not is_equal_approx(wages, 1.0):
		bits.append("wages are %d%% %s" % [int(round(absf(wages - 1.0) * 100.0)), "higher" if wages > 1.0 else "lower"])
	if bits.is_empty():
		return "The game as it was balanced."
	var text := ", ".join(PackedStringArray(bits)) + "."
	return text.left(1).to_upper() + text.substr(1)


func difficulty_name() -> String:
	var levels: Array = db.difficulty.get("levels", [])
	if levels.is_empty():
		return "Normal"
	return str((levels[clampi(difficulty, 0, levels.size() - 1)] as Dictionary).get("name", "Normal"))


# ------------------------------------------------------------- clubhouse
# The clubhouse is the club's ambition made of brick: each step up the
# ladder in data/clubhouse.json allows more holes, and each step asks for
# money, members (some of them in the higher tiers) and a reputation.

const MAX_HOLES := 18


func clubhouse_levels() -> Array:
	return db.clubhouse.get("levels", [])


func clubhouse_def(level: int = clubhouse_level) -> Dictionary:
	var levels := clubhouse_levels()
	if levels.is_empty():
		return {"name": "Clubhouse", "holes": MAX_HOLES}
	return levels[clampi(level, 0, levels.size() - 1)]


func clubhouse_name(level: int = clubhouse_level) -> String:
	return str(clubhouse_def(level).get("name", "Clubhouse"))


func clubhouse_top() -> bool:
	return clubhouse_level >= clubhouse_levels().size() - 1


## The sandbox is for drawing holes, not running a club: nothing is gated.
func open_build() -> bool:
	return str(scenario.def.get("id", "")) == "sandbox" or bool(scenario.def.get("open_build", false))


## How many holes the club may have with the clubhouse it has.
func hole_cap() -> int:
	if open_build():
		return MAX_HOLES
	return mini(int(clubhouse_def().get("holes", MAX_HOLES)), MAX_HOLES)


## The smallest clubhouse that allows this many holes.
func level_for_holes(n: int) -> int:
	var levels := clubhouse_levels()
	for i in levels.size():
		if int((levels[i] as Dictionary).get("holes", MAX_HOLES)) >= n:
			return i
	return maxi(levels.size() - 1, 0)


## What the next step up asks for, and how the club measures up: a list of
## {what, text, have, need, met}. Empty at the top of the ladder.
func clubhouse_needs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if clubhouse_top():
		return out
	var nxt := clubhouse_def(clubhouse_level + 1)
	var cost := float(nxt.get("cost", 0.0))
	out.append({"what": "cash", "text": "%s in the bank" % Defs.money(cost), "have": economy.money, "need": cost,
		"met": economy.can_afford(cost)})
	if nxt.has("members"):
		var need := int(nxt.members)
		out.append({"what": "members", "text": "%d club members" % need, "have": members.count(), "need": need,
			"met": members.count() >= need})
	if nxt.has("tier"):
		var ti := members.tier_index(str(nxt.tier))
		var need := int(nxt.get("tier_count", 1))
		var have := members.count_at_least(ti)
		out.append({"what": "tier", "text": "%d %s member%s or better" % [need, members.tier_name(ti), "" if need == 1 else "s"],
			"have": have, "need": need, "met": have >= need})
	if nxt.has("rating"):
		var need := float(nxt.rating)
		out.append({"what": "rating", "text": "a course rating of %d" % int(need), "have": rating, "need": need, "met": rating >= need})
	return out


func can_upgrade_clubhouse() -> bool:
	if clubhouse_top():
		return false
	for n in clubhouse_needs():
		if not bool(n.met):
			return false
	return true


func upgrade_clubhouse() -> bool:
	if not can_upgrade_clubhouse():
		return false
	var nxt := clubhouse_def(clubhouse_level + 1)
	economy.spend("construction", float(nxt.get("cost", 0.0)))
	clubhouse_level += 1
	var cap := hole_cap()
	toast.emit("The clubhouse is now a %s. The club may have %d holes." % [clubhouse_name().to_lower(), cap], "good")
	feed.say("clubhouse_up", null, {"name": clubhouse_name().to_lower(), "holes": cap}, true)
	return true


func remove_object(tx: int, ty: int) -> bool:
	var started := undo.begin()
	var cleared := course.set_object(tx, ty, Defs.O.NONE)
	if started:
		undo.commit()
	return cleared


func sculpt(mode: String, x: float, z: float, radius_m: float, amount: float) -> bool:
	var cost := 3.0 + radius_m * 0.25
	if not economy.can_afford(cost):
		return false
	# Smoothing and flattening are not steps. They drop the history so a
	# later undo cannot put the ground back under a shape it did not record.
	if (mode == "smooth" or mode == "flatten") and undo != null:
		undo.clear()
	var started := false
	if mode == "raise" or mode == "lower":
		started = undo.begin()
	match mode:
		"raise":
			course.sculpt(x, z, radius_m, amount)
		"lower":
			course.sculpt(x, z, radius_m, -amount)
		"smooth":
			course.smooth(x, z, radius_m, 0.5)
		"flatten":
			course.flatten(x, z, radius_m, amount, 0.5)
	economy.spend("construction", cost)
	if mode == "raise" or mode == "lower":
		undo.note_charge(cost)
	if started:
		undo.commit()
	return true


## What the next parcel of land costs. Each one is dearer than the last.
func land_price() -> float:
	return float(int(250.0 * (1.0 + 0.035 * course.owned_parcels()) / 10.0) * 10)


## Buy the parcel under a tile. Returns 1 bought, 0 not for sale, -1 broke.
func buy_land(tx: int, ty: int) -> int:
	var p := course.parcel_of(tx, ty)
	if not course.parcel_for_sale(p):
		return 0
	if land_credits > 0:
		land_credits -= 1
		if undo != null:
			undo.clear()
		course.set_parcel(p, true)
		return 1
	var price := land_price()
	if not economy.can_afford(price):
		return -1
	if undo != null:
		undo.clear()
	economy.spend("land", price)
	course.set_parcel(p, true)
	return 1


func add_hole(tee: Vector3, pin: Vector3) -> Hole:
	if not economy.can_afford(250.0) or course.holes.size() >= hole_cap():
		return null
	var started := undo.begin()
	economy.spend("construction", 250.0)
	undo.note_charge(250.0)
	var hole := course.add_hole(tee, pin)
	name_hole(hole)
	stats.holes_built = int(stats.holes_built) + 1
	feed.say("new_hole", null, {"hole": course.holes.size(), "score": hole.par}, true)
	if started:
		undo.commit()
	return hole


func remove_hole(i: int) -> void:
	if i < 0 or i >= course.holes.size():
		return
	# Taking a hole off the card is not a step. Undo of a layout removes the
	# hole itself and sets applying so this does not wipe the step it is in.
	if undo != null and not undo.applying:
		undo.clear()
	course.remove_hole(i)
	visitors.on_hole_removed(i)


## Swap a hole with its neighbour in the playing order. Groups already out
## stay on the piece of ground they are on.
func move_hole(i: int, dir: int) -> bool:
	var j := i + dir
	if i < 0 or j < 0 or i >= course.holes.size() or j >= course.holes.size():
		return false
	if undo != null and not undo.applying:
		undo.clear()
	var tmp := course.holes[i]
	course.holes[i] = course.holes[j]
	course.holes[j] = tmp
	for gr in visitors.groups:
		if gr.hole_i == i:
			gr.hole_i = j
		elif gr.hole_i == j:
			gr.hole_i = i
	course.holes_changed.emit()
	return true


func hire(role_id: String) -> bool:
	return crew.hire(role_id) != null


## Move each cup to today's spot on the green. A greenkeeper has to be on
## staff, and a tournament that is holding the pins is left alone. A locked
## hole keeps its cup. A group already playing the hole keeps the cup it
## teed off to: today's spot waits in pin_due and is set when that group
## has holed out. Nobody is sent to walk the cup over. Par and length stay
## on the placed pin. A cup that actually moves drops the undo history, so
## the old spot cannot be put back.
func move_pins() -> void:
	if crew.count("greenkeeper") < 1 or tourney.pins_held():
		return
	var today := day()
	var moved := false
	for i in course.holes.size():
		var hole := course.holes[i]
		if hole.pin_locked:
			hole.pin_due = -1
			continue
		var spot := _cup_spot(i)
		if _hole_busy(hole):
			hole.pin_due = spot
			continue
		if _place_cup(hole, spot):
			moved = true
	if not moved:
		return
	_pins_moved()
	if today > 0 and today % Defs.DAYS_PER_MONTH == 0:
		toast.emit("The greenkeepers have moved the pins.", "info")


## A cup that was waiting on a busy hole, once that hole is clear.
## The spot is the one the last morning asked for.
func settle_pins() -> void:
	if crew.count("greenkeeper") < 1 or tourney.pins_held():
		return
	var moved := false
	for hole in course.holes:
		if hole.pin_due < 0:
			continue
		if hole.pin_locked:
			hole.pin_due = -1
			continue
		if _hole_busy(hole):
			continue
		var waiting := hole.pin_due
		if _place_cup(hole, waiting):
			moved = true
	if moved:
		_pins_moved()


## A group has teed off and has not holed out. Parties still in line have
## not started, so the cup can move for them.
func _hole_busy(hole: Hole) -> bool:
	return not hole.groups.is_empty() or hole.teeing_group != null


func _cup_spot(i: int) -> int:
	var names: Array = db.pins.get("spots", [])
	if names.is_empty():
		return 0
	return (day() + i) % names.size()


func _place_cup(hole: Hole, spot: int) -> bool:
	var spec: Dictionary = db.pins
	var front_m := float(spec.get("front", 6.0))
	var back_m := float(spec.get("back", 6.0))
	var edge_m := float(spec.get("edge", 2.0))
	var slope_max := float(spec.get("slope", 4.0))
	var cup := course.day_cup(hole, spot, front_m, back_m, edge_m, slope_max)
	hole.pin_spot = spot
	hole.pin_due = -1
	if hole.pin.distance_squared_to(cup) <= 0.01:
		return false
	hole.pin = cup
	return true


func _pins_moved() -> void:
	if undo != null:
		undo.clear()
	# The routing field watches the cup itself. Bumping the revision here
	# would rebuild every path and reshuffle the round.
	course.holes_changed.emit()


## middle, front, back, or held while a tournament has the pins.
func pin_spot_name(hole: Hole) -> String:
	if tourney.pins_held():
		return "held"
	var names: Array = db.pins.get("spots", [])
	if hole.pin_spot < 0 or hole.pin_spot >= names.size():
		return "middle"
	return str(names[hole.pin_spot])


# ---------------------------------------------------------- save and load

## The ground and the holes, as a file should keep them. A tournament week
## tucks the pins and changes the greens and the rough. A save and a shared
## course both keep the course the members play.
func course_dict() -> Dictionary:
	var course_d := course.to_dict()
	if tourney._pin_home.is_empty():
		return course_d
	course_d["green_decel"] = 1.0
	course_d["rough_power"] = 1.0
	var hs: Array = course_d.get("holes", [])
	for i in course.holes.size():
		var hole: Hole = course.holes[i]
		if i >= hs.size() or not tourney._pin_home.has(hole):
			continue
		var pin: Vector3 = tourney._pin_home[hole]
		var hd: Dictionary = hs[i]
		hd["pin"] = [pin.x, pin.y, pin.z]
		hs[i] = hd
	return course_d


## Throw away the blank course this sim was built on, and play `course_d`.
func install_course(course_d: Dictionary) -> void:
	course = Course.from_dict(course_d)
	course.biome = biome
	nav = Nav.new(course)
	if undo != null:
		undo.clear()
		_bind_undo()
	player.golfer.course = course
	wildlife.populate()
	grounds.reset_layout()


func to_dict() -> Dictionary:
	var staff := []
	for m in crew.members:
		if m.has_home:
			staff.append({"role": m.role.id, "home": [m.home.x, m.home.y, m.home.z]})
		else:
			staff.append(m.role.id)
	var course_d := course_dict()
	var d := {
		"version": 1, "scenario": scenario.def.get("id", "free_play"), "status": scenario.status,
		"name": course_name, "time": time, "clock": clock, "career": career.to_dict(), "money": economy.money,
		"opening": opening_money, "club": club_id, "rating": rating, "reputation": reputation,
		"buzz": buzz, "stats": stats, "recent": visitors.recent, "staff": staff, "skills": skills.to_dict(),
		"player": player.to_dict(), "hosted": tourney.hosted, "history": economy.history,
		"weather": weather.kind, "course": course_d, "biome": str(biome.get("id", "lush")),
		"members": members.to_list(), "clubhouse": clubhouse_level, "homes": homes, "gifts": gifts,
		"feats": feats.done, "rivals": rivals, "best_rank": best_rank, "land_credits": land_credits, "debt_years": debt_years,
		"difficulty": difficulty, "rng_seed": str(rng.seed), "rng_state": str(rng.state),
		"album": album,
	}
	d["stories"] = stories.to_dict()
	if undo != null:
		undo.clear()
	return d


static func from_dict(data: DataDB, d: Dictionary, shared_gear: Gear = null) -> Sim:
	var scen := DataDB.find(data.scenarios, str(d.get("scenario", "free_play")))
	if scen.is_empty():
		scen = data.scenarios[0]
	var blank := scen.duplicate(true)
	blank["map"] = {"w": 8, "h": 8, "holes": 0}
	# Seed 0 would draw from the wall clock. A load must not: the blank
	# course is thrown away, and the saved dice are put back below.
	var sim := Sim.new(data, blank, 1, shared_gear, str(d.get("biome", "lush")))
	sim.scenario = Scenario.new(scen)
	sim.scenario.status = str(d.get("status", sim.scenario.status))
	var course_d: Dictionary = d.course
	sim.install_course(course_d)
	sim.members.from_list(d.get("members", []))
	sim.stories.from_dict(d.get("stories", {}))
	sim.clubhouse_level = int(d.get("clubhouse", 0))
	sim.homes = int(d.get("homes", 0))
	var gf: Dictionary = d.get("gifts", {})
	for k: String in gf:
		sim.gifts[int(k)] = int(gf[k])
	sim.feats.done = d.get("feats", {})
	if d.has("rivals"):
		sim.rivals = d.rivals
	sim.best_rank = int(d.get("best_rank", 0))
	sim.land_credits = int(d.get("land_credits", 0))
	sim.set_difficulty(int(d.get("difficulty", sim.db.difficulty.get("default", 2))))
	sim.debt_years = int(d.get("debt_years", 0))
	sim.course_name = str(d.get("name", sim.course_name))
	sim.time = float(d.get("time", 0.0))
	sim.clock = float(d.get("clock", 8.0))
	sim._day = sim.day()
	sim.economy.money = float(d.get("money", 0.0))
	# An older save never stored what the club started with. Treat the loaded
	# balance as the opening, so the whole purse is not suddenly profit.
	if d.has("opening"):
		sim.opening_money = float(d.get("opening", sim.economy.money))
	else:
		sim.opening_money = sim.economy.money
	var club := str(d.get("club", ""))
	sim.club_id = club if club != "" else legacy_club_id(d)
	for hrow: Dictionary in d.get("history", []):
		sim.economy.history.append(hrow)
	sim.rating = float(d.get("rating", 45.0))
	sim.reputation = float(d.get("reputation", 30.0))
	sim.buzz = float(d.get("buzz", 0.0))
	var st: Dictionary = d.get("stats", {})
	for k: String in st:
		sim.stats[k] = int(st[k])
	sim.album = []
	for page in d.get("album", []):
		if page is Dictionary:
			sim.album.append(page)
	for v: float in d.get("recent", []):
		sim.visitors.recent.append(v)
	sim.skills.from_dict(d.get("skills", {}))
	sim.career.from_dict(d.get("career", {}))
	sim.player.from_dict(d.get("player", {}))
	var hosted: Dictionary = d.get("hosted", {})
	for k: String in hosted:
		sim.tourney.hosted[k] = int(hosted[k])
	sim.weather.kind = int(d.get("weather", 0))
	for entry in d.get("staff", []):
		if entry is String:
			sim.crew.hire(str(entry))
		elif entry is Dictionary:
			var row: Dictionary = entry
			var hired := sim.crew.hire(str(row.get("role", "")))
			var hv: Array = row.get("home", [])
			if hired != null and hv.size() >= 3:
				sim.crew.station(hired, Vector3(float(hv[0]), float(hv[1]), float(hv[2])))
	# After everything that drew on the blank game's dice, so play continues
	# from the save and not from the clock.
	if d.has("rng_state"):
		sim.rng.seed = int(str(d.get("rng_seed", "1")))
		sim.rng.state = int(str(d.rng_state))
	else:
		sim.rng.seed = 1
	return sim
