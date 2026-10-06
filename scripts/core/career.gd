class_name Career
extends RefCounted
## Your own golfer's career, in the spirit of the golfer creators in the
## golf games of the early 2000s. Eight attributes are bought up one level
## at a time with skill points. The points come from playing: medals for
## your best score on each hole, challenges met once each, good rounds, and
## golfer levels. Everything here is driven by what happens when you play
## your own course (see PlayMode), and it runs without a screen for tests.
##
## Attributes and challenges are data: data/golfer.json.

signal changed()
## Skill points were earned. `why` is a short line for the player.
signal earned(points: int, why: String)

const MAX_LEVEL := 10
const MEDAL_NAMES: Array[String] = ["", "Bronze", "Silver", "Gold"]
## Holes shorter than this (metres) pay no medals: no farming a pitch and putt.
const MEDAL_MIN_LENGTH := 90.0

var sim: Sim
var levels := {}        # attribute id -> level, 0 to 10
var done := {}          # challenge id -> the day it was met
var medals := {}        # hole key -> 1 bronze (par), 2 silver (birdie), 3 gold (eagle or better)
var marks := {}         # career bests and totals, by name (see value())
var rd := {}            # the round being played
var hl := {}            # the hole being played
var sh := {}            # the shot in the air


func _init(s: Sim) -> void:
	sim = s
	for a: Dictionary in sim.db.attributes:
		levels[str(a.id)] = 0
	_reset_round()


# ------------------------------------------------------------ attributes

func level(id: String) -> int:
	return int(levels.get(id, 0))


func points() -> int:
	return int(sim.skills.points.golfer)


## What the next level of an attribute costs. Levels get dearer as they go.
static func cost_of(next_level: int) -> int:
	return 1 + (next_level - 1) / 3


func cost(id: String) -> int:
	return cost_of(level(id) + 1)


func can_raise(id: String) -> bool:
	return levels.has(id) and level(id) < MAX_LEVEL and points() >= cost(id)


func raise(id: String) -> bool:
	if not can_raise(id):
		return false
	sim.skills.points.golfer = points() - cost(id)
	levels[id] = level(id) + 1
	apply()
	changed.emit()
	return true


## Skill points sunk into attributes so far.
func spent() -> int:
	var n := 0
	for id: String in levels:
		for l in range(1, level(id) + 1):
			n += cost_of(l)
	return n


## The perks an attribute has switched on.
func perks(a: Dictionary) -> Array:
	var out := []
	for p: Dictionary in a.get("perks", []):
		if level(str(a.id)) >= int(p.at):
			out.append(p)
	return out


## Everything the attributes add up to, as the effects the rest of the game
## reads through Skills.bonus(): power, spread, putt and so on.
func effects() -> Dictionary:
	var fx := {}
	for a: Dictionary in sim.db.attributes:
		var lv := level(str(a.id))
		var per: Dictionary = a.get("fx", {})
		for k: String in per:
			fx[k] = float(fx.get(k, 0.0)) + float(per[k]) * lv
		for p: Dictionary in perks(a):
			var extra: Dictionary = p.get("fx", {})
			for k: String in extra:
				fx[k] = float(fx.get(k, 0.0)) + float(extra[k])
	fx["spread"] = maxf(float(fx.get("spread", 0.0)), -0.6)
	fx["approach"] = maxf(float(fx.get("approach", 0.0)), -0.65)
	fx["rough"] = minf(float(fx.get("rough", 0.0)), 0.85)
	fx["sand"] = minf(float(fx.get("sand", 0.0)), 0.85)
	return fx


## Push the attributes into the game.
func apply() -> void:
	sim.skills.set_extra(effects())


func _award(n: int, why: String) -> void:
	if n <= 0:
		return
	sim.skills.points.golfer = points() + n
	sim.skills.changed.emit()
	earned.emit(n, why)
	sim.toast.emit("%s  +%d skill point%s for your golfer." % [why, n, "" if n == 1 else "s"], "medal")
	changed.emit()


# ------------------------------------------------------------- challenges

## A number the challenges can test: a career best, a career total, or a
## count from the round being played.
func value(test: String) -> float:
	if test.begins_with("round_"):
		return float(rd.get(test.trim_prefix("round_"), 0))
	match test:
		"matches_won":
			return float(sim.stats.get("matches_won", 0))
		"tourney_wins":
			return float(sim.stats.get("player_wins", 0))
		"medal_holes":
			return float(medals.size())
		"gold_holes":
			var n := 0
			for k: String in medals:
				if int(medals[k]) >= 3:
					n += 1
			return float(n)
	return float(marks.get(test, 0.0))


func met(c: Dictionary) -> bool:
	var test := str(c.test)
	if c.has("at_most"):
		return marks.has(test) and value(test) <= float(c.at_most)
	return value(test) >= float(c.get("at_least", 1))


## How far along a challenge is, 0 to 1, for a progress bar.
func progress(c: Dictionary) -> float:
	if done.has(str(c.id)):
		return 1.0
	var test := str(c.test)
	if c.has("at_most"):
		if not marks.has(test):
			return 0.0
		return clampf(float(c.at_most) / maxf(value(test), 0.01), 0.0, 1.0)
	return clampf(value(test) / maxf(float(c.get("at_least", 1)), 0.01), 0.0, 1.0)


## Pay out any challenges that have just been met.
func check() -> void:
	for c: Dictionary in sim.db.challenges:
		var id := str(c.id)
		if done.has(id) or not met(c):
			continue
		done[id] = sim.day()
		_award(int(c.points), "Challenge met: %s." % str(c.name))


func challenge_points_left() -> int:
	var n := 0
	for c: Dictionary in sim.db.challenges:
		if not done.has(str(c.id)):
			n += int(c.points)
	return n


func _bump(mark: String, by: float = 1.0) -> void:
	marks[mark] = float(marks.get(mark, 0.0)) + by


func _best(mark: String, v: float) -> void:
	if v > float(marks.get(mark, 0.0)):
		marks[mark] = v


func _least(mark: String, v: float) -> void:
	if not marks.has(mark) or v < float(marks[mark]):
		marks[mark] = v


## Something that happens off the course: a tournament finish, say.
func note(mark: String, by: float = 1.0) -> void:
	_bump(mark, by)
	check()
	changed.emit()


# ------------------------------------------------------- playing a round

func _reset_round() -> void:
	rd = {"holes": 0, "fairways": 0, "greens": 0, "birdies": 0, "one_putts": 0, "three_putts": 0, "bogeys": 0, "to_par": 0, "full": false}
	hl = {}
	sh = {}


## `full` is true when the round covers every hole on the course.
func begin_round(full: bool) -> void:
	_reset_round()
	rd.full = full


func begin_hole(hole: Hole) -> void:
	hl = {"putts": 0, "green_in": 0, "sand_at": -1, "solid": false, "par": hole.par, "strokes": 0, "points_at_tee": points()}
	sh = {}


## A shot is on its way. `info`: putt (bool), lie (Defs.T), to_pin (metres),
## from (Vector3), wood (bool: driver or fairway wood), shape (id), stroke
## (which stroke of the hole this is, from 1).
func shot_struck(info: Dictionary) -> void:
	sh = info.duplicate()
	hl.strokes = int(info.get("stroke", int(hl.get("strokes", 0)) + 1))
	if info.get("putt", false):
		hl.putts = int(hl.get("putts", 0)) + 1
	if int(info.get("lie", -1)) == Defs.T.BUNKER:
		hl.sand_at = int(hl.strokes)


## The ball has stopped, or dropped. `lie` is where it finished (Defs.T, or
## -1 for a penalty), `to_pin` how far from the hole in metres.
func shot_done(ball: Ball, lie: int, to_pin: float, holed: bool) -> void:
	if sh.is_empty():
		return
	var par := int(hl.get("par", 4))
	var stroke := int(hl.get("strokes", 1))
	var from: Vector3 = sh.get("from", ball.pos)
	var went := Vector2(ball.pos.x - from.x, ball.pos.z - from.z).length()
	if ball.hits > 0 or ball.tree_tile >= 0:
		hl.solid = true
	if stroke == 1 and par >= 4 and lie >= 0:
		# a tee shot on a hole long enough to need one
		_best("longest_drive", went * Defs.YARDS)
		if lie == Defs.T.FAIRWAY or lie == Defs.T.GREEN:
			rd.fairways = int(rd.fairways) + 1
	if sh.get("putt", false):
		if holed:
			_best("longest_putt", float(sh.get("to_pin", 0.0)) * 3.281)
	else:
		if holed and int(sh.get("lie", -1)) != Defs.T.GREEN:
			_bump("chip_ins")
		if (lie == Defs.T.GREEN or holed) and float(sh.get("to_pin", 0.0)) >= 100.0 / Defs.YARDS:
			_least("closest_100", to_pin * 3.281)
		if lie == Defs.T.GREEN or holed:
			if int(hl.get("green_in", 0)) == 0:
				hl.green_in = stroke
			var shape := str(sh.get("shape", "straight"))
			if shape == "draw" or shape == "fade":
				var seen: Dictionary = marks.get("_shapes", {})
				if not seen.has(shape):
					seen[shape] = true
					marks["_shapes"] = seen
					marks["shaped_greens"] = float(seen.size())
	sh = {}
	check()


## The hole is finished. Returns the skill points earned on it, from the
## tee shot onward.
func hole_done(hole: Hole, score: int, picked_up: bool) -> int:
	var before := int(hl.get("points_at_tee", points()))
	var par := hole.par
	var diff := score - par
	rd.holes = int(rd.holes) + 1
	rd.to_par = int(rd.to_par) + diff
	_bump("holes")
	if not picked_up:
		if diff <= 0:
			_bump("pars")
			if sim.weather.rain > 0.3:
				_bump("rain_pars")
			if sim.weather.wind_mph() >= 15:
				_bump("wind_pars")
			if hl.get("solid", false):
				_bump("bounce_pars")
			if hole.lab_ready and hole.kind in [3, 5, 6, 7]:
				_bump("hard_pars")
		if diff <= -1:
			_bump("birdies")
			rd.birdies = int(rd.birdies) + 1
			if sim.darkness() > 0.55:
				_bump("night_birdies")
		if diff <= -2 and score > 1:
			_bump("eagles")
		if score == 1:
			_bump("aces")
		# in two from the sand: the shot out, and one more
		var sand_at := int(hl.get("sand_at", -1))
		if sand_at > 0 and score - sand_at <= 1:
			_bump("sand_saves")
	if diff >= 1:
		rd.bogeys = int(rd.bogeys) + 1
	var putts := int(hl.get("putts", 0))
	if putts == 1:
		rd.one_putts = int(rd.one_putts) + 1
	elif putts >= 3:
		rd.three_putts = int(rd.three_putts) + 1
	var green_in := int(hl.get("green_in", 0))
	if green_in > 0 and green_in <= par - 2:
		rd.greens = int(rd.greens) + 1
	# a medal for your best score on this hole
	if not picked_up and hole.length >= MEDAL_MIN_LENGTH and diff <= 0:
		var medal := clampi(1 - diff, 1, 3)
		var key := hole_key(hole)
		var had := int(medals.get(key, 0))
		if medal > had:
			medals[key] = medal
			var pts := 0
			for m in range(had + 1, medal + 1):
				pts += m
			_award(pts, "%s medal on %s." % [MEDAL_NAMES[medal], hole.name if hole.name != "" else "this hole"])
	check()
	changed.emit()
	return points() - before


## The round is over. Returns the skill points it earned.
func round_done(card: Array, pars: Array) -> int:
	var before := points()
	var n := card.size()
	if n > 0 and n == int(rd.holes):
		var to_par := 0
		for i in n:
			to_par += int(card[i]) - int(pars[i])
		_bump("rounds")
		if to_par < 0:
			_best("under_par_holes", float(n))
		if int(rd.bogeys) == 0:
			_best("bogey_free_holes", float(n))
		if int(rd.three_putts) == 0:
			_best("no_three_putt_holes", float(n))
		# a whole round of the course, played well, is worth something every time
		if rd.full and n >= 3:
			if to_par <= 0:
				_award(1, "A round of %d holes at %s." % [n, "level par" if to_par == 0 else "%d under" % -to_par])
			var key := "best_%d" % n
			if not marks.has(key) or to_par < int(marks[key]):
				var first := not marks.has(key)
				marks[key] = to_par
				if not first:
					_award(1, "A new personal best over %d holes." % n)
	check()
	_reset_round()
	changed.emit()
	return points() - before


## What identifies a hole for its medal: where its tee and pin are.
static func hole_key(hole: Hole) -> String:
	return "%d,%d>%d,%d" % [int(hole.tee.x / Defs.TILE), int(hole.tee.z / Defs.TILE), int(hole.pin.x / Defs.TILE), int(hole.pin.z / Defs.TILE)]


func medal(hole: Hole) -> int:
	return int(medals.get(hole_key(hole), 0))


# ---------------------------------------------------------- save and load

func to_dict() -> Dictionary:
	return {"levels": levels, "done": done, "medals": medals, "marks": marks}


func from_dict(d: Dictionary) -> void:
	for id: String in levels:
		levels[id] = clampi(int(d.get("levels", {}).get(id, 0)), 0, MAX_LEVEL)
	done = d.get("done", {})
	medals = {}
	for k: String in d.get("medals", {}):
		medals[k] = int(d.medals[k])
	marks = d.get("marks", {})
	_reset_round()
	apply()
