class_name Golfer
extends RefCounted
## One person with a bag of clubs: a paying visitor, a touring pro, a
## celebrity, or the player.

enum P { IDLE, WALK, AIM, SWING, WATCH, PAUSE }

const SHIRTS: Array[Color] = [
	Color("e53935"), Color("fb8c00"), Color("fdd835"), Color("43a047"), Color("00897b"), Color("1e88e5"),
	Color("5e35b1"), Color("d81b60"), Color("f5f5f5"), Color("90a4ae"), Color("6d4c41"), Color("26c6da"),
]
const PANTS: Array[Color] = [Color("37474f"), Color("efebe9"), Color("1e3a5f"), Color("263238"), Color("b0bec5"), Color("c2b280")]
const SKINS: Array[Color] = [Color("ffdbac"), Color("f1c27d"), Color("e0ac69"), Color("c68642"), Color("8d5524"), Color("5c3a21")]

## Which broad kind of experience each mood tag belongs to. A golfer's
## personality scales whole categories up or down.
const CATEGORY := {
	"scenery": "scenery", "bare": "scenery",
	"score": "play", "shot": "play", "putt": "play", "suits": "play",
	"hard": "difficulty", "water": "difficulty", "bunker": "difficulty", "rough": "difficulty", "oob": "difficulty",
	"wait": "pace",
	"weeds": "condition", "pests": "condition", "wet": "condition", "greens": "condition", "greens_bad": "condition",
	"rain": "weather", "storm": "weather",
	"hit": "danger", "eruption": "danger",
	"thirst": "comfort", "hungry": "comfort", "restroom": "comfort", "tired": "comfort", "drink": "comfort",
	"snack": "comfort", "amenity": "comfort", "rest": "comfort", "practice": "comfort",
	"celebrity": "prestige", "prestige": "prestige",
	"story": "social", "social": "social",
}
## What a thrill seeker says when the same thing happens to them.
const THRILL := {
	"hit": "I got hit by a golf ball! What a story!",
	"eruption": "LAVA! This is the best course in the world!",
	"storm": "Golf in a thunderstorm. Now we're talking.",
	"rain": "A bit of weather makes it interesting.",
}

static var _next_id := 1

var id := 0
## Which set of eddies this golfer's real shots meet. Numbered inside one
## simulation, from 1. It is not `id`: that counter lives for the whole
## process, so a test or a loaded game would reshuffle every later round.
var eddy := 1
var name := ""
var handle := ""
var kind := "public"            # public, pro, celebrity, player
var title := ""
var skill := 0.3
var power := 0.9
var accuracy := 0.3
var putting := 0.3
var patience := 0.5
var wealth := 0.5
var pace := 0.5
var satisfaction := 60.0
var thoughts: Array[Dictionary] = []
var course: Course = null      # set when the golfer joins a game, so a feeling can mark the ground
var gripes := {}                # tag -> summed mood change, for reviews
var pos := Vector3.ZERO
var prev := Vector3.ZERO
var facing := 0.0
var walking := false
var ball := Ball.new()
var brands := {}                # club category -> brand dictionary
var group: Group = null
var phase: int = P.IDLE
var timer := 0.0
var plan := {}
var strokes := 0
var done := false
var teed := false
var picked_up := false
var mishit := false
var scores: Array[int] = []
var pars: Array[int] = []
var paid := 0.0
var waited := 0.0
var wait_said := false          # complained about this hole's wait already
var thirst := 0.0
var hit_t := 0.0                # seconds left flat on the grass
var swing_t := -1.0             # swing animation clock, -1 when idle
var cheer_t := 0.0
var sulk_t := 0.0               # seconds left hanging the head after a bad hole
var rage_t := 0.0               # seconds left of a tantrum: stamping, shouting, a club in the air
var tossed := false             # the club went in the lake; nothing to carry until the next hole
var storming := false           # walking off the course in a fury
var slow_t := 0.5
var hits_taken := 0
var holes_played := 0
var sat_at_tee := 60.0
var gripes_at_tee := {}
var tantrum := false
var drunk := 0.0                # 0 sober .. 1 legless; set at the bar, wears off over the round
var vip := ""                   # commissioner, heiress or investor
var last_kind := -1             # the kind of hole they played last
var last_par := 0
var seen_animals := {}
var saw_celebrity := false
var shirt := Color.WHITE
var pants := Color.DIM_GRAY
var hat := Color.WHITE
var skin := Color.BISQUE
# shot modifiers the player earns from the skill tree
var bonus_rough := 0.0
var bonus_sand := 0.0
var bonus_spread := 0.0
var imagination := 0.3          # shot shaping, reading wind and slopes, recovery
var mood_good := 1.0            # the difficulty slider: how much a good moment lifts this golfer
var mood_bad := 1.0             # and how hard a bad one hits
var persona: Dictionary = {}    # personality, from data/personalities.json
var member: Dictionary = {}     # their club membership record, if they have one
var hunger := 0.0
var bladder := 0.0
var fatigue := 0.0
var clean_ball := false
var bubble := ""                # the thought shown over their head
var bubble_t := 0.0
var bubble_mood := 0
var rd := {"waited": 0.0, "served": 0, "grumbles": 0, "scare": 0, "lost_balls": 0, "storm": 0}
# path following
var route := PackedVector2Array()
var route_i := 0
var route_goal := Vector3.ZERO


func _init() -> void:
	id = _next_id
	_next_id += 1
	ball.owner = self


## The air this golfer's shot will fly through, fixed when the shot is struck.
func air_phase(t: float) -> float:
	return fposmod(t * 7.31 + float(maxi(eddy, 1)) * 13.7, 600.0)


## Fill in abilities from one overall skill number, 0 beginner .. 1 tour pro.
func roll_stats(base_skill: float, rng: RandomNumberGenerator, progress: Dictionary) -> void:
	skill = clampf(base_skill, 0.02, 0.99)
	var t := clampf(skill + rng.randfn(0.0, 0.12), 0.0, 1.0)
	power = Members.power_at(t, progress) * rng.randf_range(0.97, 1.03)
	accuracy = clampf(skill + rng.randfn(0.0, 0.1), 0.02, 0.99)
	putting = clampf(skill + rng.randfn(0.0, 0.1), 0.02, 0.99)
	imagination = clampf(skill + rng.randfn(0.0, 0.14), 0.02, 0.99)
	patience = rng.randf()
	pace = rng.randf()
	wealth = clampf(rng.randf() * 0.8 + skill * 0.2, 0.0, 1.0)
	shirt = SHIRTS[rng.randi() % SHIRTS.size()]
	pants = PANTS[rng.randi() % PANTS.size()]
	skin = SKINS[rng.randi() % SKINS.size()]
	hat = SHIRTS[rng.randi() % SHIRTS.size()] if rng.randf() < 0.6 else Color(0, 0, 0, 0)


func handicap() -> int:
	return int(round(lerpf(36.0, -3.0, skill)))


func brand_of(cat: String) -> Dictionary:
	return brands.get(cat, {})


func spread() -> float:
	# drink loosens the swing in every direction
	return lerpf(0.105, 0.022, accuracy) * (1.0 + bonus_spread) * (1.0 + drunk * 0.9)


func walk_speed() -> float:
	# a drinker ambles; a golfer storming off marches
	return (6.0 + pace * 1.5) * (1.0 - drunk * 0.25) * (1.45 if storming else 1.0)


## How much longer than usual this golfer takes over a shot: a drinker
## dawdles, lines it up twice and tells a story in between.
func think_mult() -> float:
	return 1.0 + drunk * 1.2


## How much this golfer fancies a drink at the bar, from their personality
## (`bar` in data/personalities.json; 1 is ordinary). Pros in a tournament
## and the player never do.
func bar_taste() -> float:
	if kind == "player" or (group != null and group.kind == "tournament"):
		return 0.0
	return float(persona.get("bar", 1.0))


## Share of normal power available from a lie.
func lie_power(lie: int, course: Course = null) -> float:
	if lie < 0:
		return 1.0
	var p: float = Defs.T_LIE_POWER[lie]
	if course != null and (lie == Defs.T.ROUGH or lie == Defs.T.DEEP_ROUGH):
		p *= course.rough_power
	if lie == Defs.T.BUNKER:
		p = 1.0 - (1.0 - p) * (1.0 - bonus_sand)
		p = minf(1.0, p * ball.m_sand)
	elif lie == Defs.T.ROUGH or lie == Defs.T.DEEP_ROUGH:
		p = 1.0 - (1.0 - p) * (1.0 - bonus_rough)
	# imagination is also the knack of getting out of trouble
	if p < 1.0:
		p = 1.0 - (1.0 - p) * (1.0 - 0.45 * imagination)
	return p


## Give this golfer a personality. It shifts their starting mood and, from
## then on, how strongly each kind of experience moves them.
func set_persona(p: Dictionary) -> void:
	persona = p
	satisfaction = clampf(satisfaction + float(p.get("base", 0.0)), 5.0, 95.0)
	patience = clampf(patience + float(p.get("patience", 0.0)), 0.0, 1.0)
	pace = clampf(pace + float(p.get("pace", 0.0)), 0.0, 1.0)


func need_rate(need: String) -> float:
	return float(persona.get("needs", {}).get(need, 1.0))


## How badly they want a kind of stop, 0 to 1 and beyond.
func need_for(kind: String) -> float:
	match kind:
		"restroom":
			return bladder
		"snack":
			return maxf(hunger, thirst * 0.6)
		"drink":
			return thirst
		"vending":
			# a machine answers either need, but nobody is excited about it
			return maxf(hunger, thirst) * 0.85
		"bar":
			return thirst * bar_taste()
	return 0.0


## Change mood, optionally recording a thought the player can read. The
## golfer's personality decides how much a given kind of thing matters.
func feel(delta: float, text: String = "", tag: String = "") -> void:
	if not persona.is_empty() and delta != 0.0:
		var k := float(persona.get("tags", {}).get(CATEGORY.get(tag, ""), 1.0))
		if k < 0.0 and text != "":
			text = THRILL.get(tag, text)
		delta *= k
		delta *= float(persona.get("pos", 1.0)) if delta > 0.0 else float(persona.get("neg", 1.0))
	delta *= mood_good if delta > 0.0 else mood_bad
	if drunk > 0.0:
		# Drink makes the good things better and the small annoyances slide
		# off, but anything that really goes wrong lands twice as hard.
		if delta > 0.0:
			delta *= 1.0 + drunk * 0.35
		elif delta > -1.0:
			delta *= 1.0 - drunk * 0.6
		else:
			delta *= 1.0 + drunk * 0.5
	satisfaction = clampf(satisfaction + delta, 0.0, 100.0)
	if tag != "":
		gripes[tag] = float(gripes.get(tag, 0.0)) + delta
	if course != null and not is_zero_approx(delta):
		course.note_mood(pos.x, pos.z, delta)
	if text == "":
		return
	if not thoughts.is_empty() and thoughts[-1].text == text:
		return
	var hole_i := -1
	if group != null:
		hole_i = group.hole_i
	thoughts.append({"text": text, "delta": delta, "pos": pos, "hole": hole_i})
	if thoughts.size() > 12:
		thoughts.pop_front()
	bubble = text
	bubble_t = 3.5
	bubble_mood = 1 if delta > 0.0 else (-1 if delta < 0.0 else 0)


func top_tag(positive: bool) -> String:
	var best := ""
	var bv := 0.0
	for tag: String in gripes:
		var v: float = gripes[tag]
		if (positive and v > bv) or (not positive and v < bv):
			bv = v
			best = tag
	return best


func walk_to(target: Vector3, dt: float, course: Course, speed: float = 4.0) -> bool:
	var dx := target.x - pos.x
	var dz := target.z - pos.z
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.35:
		walking = false
		return true
	var stride := minf(speed * dt, d)
	facing = atan2(dz, dx)
	pos.x += dx / d * stride
	pos.z += dz / d * stride
	pos.y = course.height_at(pos.x, pos.z)
	walking = true
	return false


## Walk to a target along a found path: round ponds, over bridges, and
## along cart paths when they help. True on arrival.
func travel(target: Vector3, dt: float, sim: Sim, speed: float, prefer_paths: bool = false) -> bool:
	if rage_t > 0.0:
		# a tantrum is had on the spot; nobody storms anywhere until it is over
		walking = false
		return false
	var cart := group != null and group.has_cart
	# on the last few metres, step round anyone already standing there
	if Vector2(pos.x - target.x, pos.z - target.z).length_squared() < 16.0:
		var clear := sim.visitors.clear_spot(self, target)
		if clear != target and route_goal.distance_squared_to(clear) > 0.0001:
			route = PackedVector2Array()      # a new end point: plan the last steps again
		target = clear
	return Nav.advance(self, target, dt, sim, speed, cart, prefer_paths)


func begin_hole() -> void:
	strokes = 0
	done = false
	teed = false
	picked_up = false
	mishit = false
	tossed = false
	waited = 0.0
	wait_said = false
	phase = P.IDLE
	sat_at_tee = satisfaction
	gripes_at_tee = gripes.duplicate()


func to_par() -> int:
	var t := 0
	for i in scores.size():
		t += scores[i] - pars[i]
	return t


func to_par_text() -> String:
	if scores.is_empty():
		return "-"
	var t := to_par()
	return "E" if t == 0 else ("%+d" % t)


func mood_word() -> String:
	if satisfaction >= 80.0:
		return "Delighted"
	if satisfaction >= 62.0:
		return "Happy"
	if satisfaction >= 45.0:
		return "Content"
	if satisfaction >= 28.0:
		return "Grumpy"
	return "Furious"
