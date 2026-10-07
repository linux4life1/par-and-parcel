class_name Visitors
extends RefCounted
## Everyone on the course who is not staff: arrivals, green fees, moods,
## flying balls, and people getting hit by them.

const GOOD_REASONS := {
	"scenery": "Beautiful scenery.", "score": "Played the round of my life.", "drink": "Cold drinks out on the course.",
	"greens": "The greens were perfect.", "celebrity": "I even spotted a celebrity.",
	"shot": "Hit some of my best shots ever.",
}
const BAD_REASONS := {
	"weeds": "Weeds everywhere.", "pests": "Gopher mounds all over the place.", "wet": "The course was a swamp.",
	"wait": "Painfully slow play.", "hit": "I got hit by a golf ball.",
	"hard": "Unfair, punishing holes.", "thirst": "Nowhere to buy a drink.", "rain": "Rained on all day.",
	"greens_bad": "The greens were in terrible shape.", "water": "Lost too many balls in the water.",
	"bare": "Dull, featureless holes.", "bunker": "Bunkers everywhere.", "rough": "Spent the day hacking out of rough.",
	"oob": "Too easy to hit it off the property.", "storm": "Caught in a thunderstorm.",
	"eruption": "The volcano erupted while I was on the course.", "restroom": "Not a restroom in sight.",
	"hungry": "Nothing to eat out there.", "tired": "Nowhere to sit down.",
}

var sim: Sim
var groups: Array[Group] = []
var golfers: Array[Golfer] = []
var balls: Array[Ball] = []
var pins: Array[Vector3] = []
var recent: Array[float] = []     # satisfaction of the last golfers to leave
var spawn_t := 0.05            # arrivals expected before the next group turns up
var facilities := {}              # kind -> Array of world positions
var amenities := {}               # kind -> how many the course has

## Why a group is out together. Finishing the story is a memory they keep.
const STORIES := [
	{"id": "business", "who": "a business contact", "goal": "Closing a deal", "done": "Shook hands on a big deal", "tip": 120.0},
	{"id": "friends", "who": "old friends", "goal": "Catching up", "done": "Caught up with old friends", "tip": 0.0},
	{"id": "date", "who": "a first date", "goal": "A first date", "done": "The first date could not have gone better", "tip": 0.0},
	{"id": "family", "who": "family", "goal": "A family day out", "done": "Got the whole family round without one argument", "tip": 0.0},
	{"id": "rivals", "who": "an old rival", "goal": "Settling a score", "done": "Settled an old score, and stayed friends", "tip": 40.0},
	{"id": "interview", "who": "a job candidate", "goal": "A job interview", "done": "Hired my new sales director by the last green", "tip": 80.0},
]
const FACILITY := {
	Defs.O.DRINK_STAND: "drink", Defs.O.SNACK_BAR: "snack", Defs.O.RESTROOM: "restroom", Defs.O.BENCH: "bench",
	Defs.O.BALL_WASHER: "washer", Defs.O.PUTTING_GREEN: "putting", Defs.O.DRIVING_RANGE: "range",
	Defs.O.CART_BARN: "cart_barn", Defs.O.FOUNTAIN: "fountain", Defs.O.LANDMARK: "landmark",
	Defs.O.HOME_SITE: "lot", Defs.O.HOUSE: "house", Defs.O.TENNIS: "tennis", Defs.O.HOTEL: "hotel",
	Defs.O.MARINA: "marina", Defs.O.AIRSTRIP: "airstrip",
	Defs.O.VENDING: "vending", Defs.O.BAR: "bar",
}
## What a drinker says on the way back to the tee.
const BAR_LINES: Array[String] = [
	"One more at the turn and I'll find my swing.",
	"Everything's fine. Everything's great.",
	"Best bar on any course I've played. Best course, too.",
	"I love this place. I love these people.",
	"The green's moving a bit, but so am I.",
]
var _gid := 1
var _amen_rev := -1


func _init(s: Sim) -> void:
	sim = s


func step(dt: float) -> void:
	for g in golfers:
		g.prev = g.pos
		_tick_golfer(g, dt)
	var i := 0
	while i < groups.size():
		var gr := groups[i]
		gr.step(dt, sim)
		if gr.state == Group.S.GONE:
			for hole in sim.course.holes:
				hole.groups.erase(gr)
				if hole.teeing_group == gr:
					hole.teeing_group = null
			groups.remove_at(i)
		else:
			i += 1
	_step_balls(dt)
	_spawn(dt)


# ------------------------------------------------------------- arrivals

func _spawn(dt: float) -> void:
	if not sim.open or sim.course.holes.is_empty():
		return
	# The timer counts expected arrivals, not seconds, so it runs at the
	# rate of the moment: a timer wound up in the afternoon slows down
	# when night falls instead of bringing a group in at midnight.
	spawn_t -= dt * sim.arrival_rate()
	if spawn_t > 0.0:
		return
	spawn_t = sim.rng.randf_range(0.6, 1.4)
	var public := 0
	var at_first := 0
	for gr in groups:
		if gr.kind == "public" and gr.state != Group.S.LEAVING:
			public += 1
		if gr.hole_i == 0 and (gr.state == Group.S.TO_TEE or gr.state == Group.S.QUEUE):
			at_first += 1
	if public >= int(sim.course.holes.size() * 1.5) + 1 or at_first >= 2:
		return
	# Members who are due a round get the tee time first.
	var due := sim.members.due(4)
	if not due.is_empty() and sim.rng.randf() < 0.65:
		# two characters a story wants together arrive together
		var pick := sim.stories.pair_due(due)
		add_member_group(pick if not pick.is_empty() else due.slice(0, sim.rng.randi_range(1, due.size())))
		return
	var r := sim.rng.randf()
	var n := 1 if r < 0.2 else (2 if r < 0.55 else (3 if r < 0.75 else 4))
	var base := clampf(sim.rng.randfn(0.3 + sim.reputation / 350.0, 0.17), 0.03, 0.95)
	add_group("public", n, base)


func add_group(kind: String, count: int, base_skill: float, spread: float = 0.1) -> Group:
	var gr := Group.new()
	gr.id = _gid
	_gid += 1
	gr.kind = kind
	gr.free_play = kind == "tournament"
	for i in count:
		var g := make_golfer("pro" if kind == "tournament" else "public", clampf(base_skill + sim.rng.randfn(0.0, spread), 0.03, 0.99))
		_join(gr, g)
	_outfit_group(gr)
	groups.append(gr)
	return gr


## A group of returning club members, sometimes with a guest in tow.
func add_member_group(list: Array) -> Group:
	var gr := Group.new()
	gr.id = _gid
	_gid += 1
	gr.kind = "public"
	var top := 0
	for m: Dictionary in list:
		_join(gr, sim.members.make_golfer(m))
		top = maxi(top, int(m.tier))
	if top >= 5 and gr.members.size() < 4 and sim.rng.randf() < 0.5:
		var guest := make_golfer("public", clampf(sim.rng.randfn(0.4, 0.15), 0.05, 0.95))
		guest.satisfaction += 4.0
		_join(gr, guest)
	_outfit_group(gr)
	groups.append(gr)
	sim.stories.on_arrive(gr)
	return gr


func _join(gr: Group, g: Golfer) -> void:
	var door := sim.clubhouse_door()
	g.group = gr
	g.ball.lava = sim.is_lava()
	if g.brands.is_empty():
		_equip(g)
	g.pos = sim.course.on_ground(door.x + sim.rng.randf_range(-3.0, 3.0), door.z + sim.rng.randf_range(-3.0, 3.0))
	g.prev = g.pos
	gr.members.append(g)
	_register(g)


## Carts and a reason to be out together.
func _outfit_group(gr: Group) -> void:
	_refresh_amenities()
	if gr.kind == "tournament":
		return
	var wealth := 0.0
	for m in gr.members:
		wealth += m.wealth
	wealth /= gr.members.size()
	if int(amenities.get("cart_barn", 0)) > 0 and sim.rng.randf() < 0.3 + wealth * 0.5:
		gr.has_cart = true
		sim.economy.earn("carts", 8.0 * gr.members.size())
	if gr.members.size() >= 2:
		var st: Dictionary = STORIES[sim.rng.randi() % STORIES.size()]
		gr.story = {"id": st.id, "who": st.who, "goal": st.goal, "done_text": st.done, "tip": st.tip, "progress": 0.0, "done": false, "stopped": false}


func _pick_persona() -> Dictionary:
	var list := sim.db.personalities
	if list.is_empty():
		return {}
	var total := 0.0
	for p: Dictionary in list:
		total += float(p.get("weight", 1.0))
	var r := sim.rng.randf() * total
	for p: Dictionary in list:
		r -= float(p.get("weight", 1.0))
		if r <= 0.0:
			return p
	return list[0]


func _equip(g: Golfer) -> void:
	var rng := sim.rng
	# wealthier and better golfers bring nicer gear
	var b: Dictionary = sim.db.brands[0]
	if rng.randf() + g.wealth * 0.6 + (0.4 if g.kind == "pro" else 0.0) > 0.75:
		b = sim.db.brands[1 + rng.randi() % (sim.db.brands.size() - 1)]
	for cat: Dictionary in sim.db.categories:
		g.brands[cat.id] = b
	if rng.randf() < 0.15 + g.wealth * 0.2:
		g.ball.set_def(sim.db.balls[rng.randi() % sim.db.balls.size()])
	else:
		g.ball.set_def(sim.db.balls[0])


func make_golfer(kind: String, base_skill: float) -> Golfer:
	var rng := sim.rng
	var g := Golfer.new()
	g.kind = kind
	g.ball.lava = sim.is_lava()
	g.roll_stats(base_skill, rng)
	var first := sim.db.pick("pro_first" if kind == "pro" else "first", rng)
	var last := sim.db.pick("last", rng)
	g.name = first + " " + last
	g.handle = "%s%s%d" % [first, last.left(1), rng.randi_range(2, 99)]
	g.satisfaction = clampf(58.0 + rng.randfn(0.0, 6.0) + sim.skills.bonus("welcome"), 20.0, 90.0)
	if kind == "pro":
		g.satisfaction = 66.0
		g.pace = 0.8
	else:
		g.set_persona(_pick_persona())
	_equip(g)
	set_temper(g)
	return g


## Give a golfer the difficulty slider's temper: how hard bad moments hit
## and how much good ones lift. The player's own golfer is left alone.
func set_temper(g: Golfer) -> void:
	if g.kind == "player" or g.kind == "lab":
		return
	g.mood_bad = sim.diff("mood_bad")
	g.mood_good = sim.diff("mood_good")


## The slider moved: everyone already on the course feels it from now on.
func apply_difficulty() -> void:
	for g in golfers:
		set_temper(g)


func _register(g: Golfer) -> void:
	golfers.append(g)
	sim.golfer_added.emit(g)
	if g.kind != "public":
		return
	_refresh_amenities()
	var shop := sim.skills.mult("retail") * (1.0 + 0.12 * sim.clubhouse_level)
	if sim.rng.randf() < 0.14 * shop:
		sim.economy.earn("pro_shop", sim.rng.randf_range(15.0, 90.0) * shop)
	# a warm-up before the round
	if int(amenities.get("putting", 0)) > 0:
		g.putting = minf(0.99, g.putting + 0.05)
		g.feel(1.5, "Rolled a few on the practice green first.", "practice")
	if int(amenities.get("range", 0)) > 0:
		g.accuracy = minf(0.99, g.accuracy + 0.03)
		sim.economy.earn("range", 4.0)
		g.feel(1.5, "Hit a bucket of balls on the range first.", "practice")
	if sim.clubhouse_level > 0:
		g.feel(0.4 * sim.clubhouse_level, "", "prestige")
	if sim.crew.count("club_pro") > 0:
		g.accuracy = minf(0.99, g.accuracy + 0.02)
		g.feel(2.5, "Got a quick tip from the club pro.", "practice")
	if sim.resort.has("tennis") and g.satisfaction < 55.0:
		g.satisfaction = 55.0


func add_existing(g: Golfer) -> void:
	if not golfers.has(g):
		golfers.append(g)
		sim.golfer_added.emit(g)


func remove_existing(g: Golfer) -> void:
	untrack(g.ball)
	if golfers.has(g):
		golfers.erase(g)
		sim.golfer_removed.emit(g)


# ---------------------------------------------------------- green fees
#
# Nobody sets a price. A golfer pays as they walk off each green, and what
# they pay depends on how much they enjoyed the hole they just played.

## What this golfer would hand over for a hole they thoroughly enjoyed: a
## matter of how deep their pockets are, the kind of person they are, and
## the standing of the course and of the hole.
func worth(g: Golfer, hole: Hole) -> float:
	var v := (6.0 + 22.0 * g.wealth) * (0.5 + sim.rating / 100.0)
	v *= 0.75 + hole.par * 0.0833
	v *= float(g.persona.get("fee", 1.0))
	if hole.award == "top18":
		v *= 1.4
	elif hole.award == "top100":
		v *= 1.2
	if sim.resort.has("airstrip"):
		v *= 1.2
	return v * sim.skills.mult("generosity")


## How much a golfer enjoyed the hole they have just finished, 0 to 1. Mostly
## what happened on this hole, coloured a little by the day so far.
func enjoyment(g: Golfer) -> float:
	var this_hole := clampf(55.0 + (g.satisfaction - g.sat_at_tee) * 4.0, 0.0, 100.0) / 100.0
	return this_hole * 0.75 + g.satisfaction / 100.0 * 0.25


## The share of `worth` a golfer pays for a given enjoyment: nothing for a
## hole they hated, the full amount for one they liked, and a tip on top for
## one they loved.
static func pay_share(joy: float) -> float:
	return clampf((joy - 0.22) / 0.48, 0.0, 1.45)


## Collect one golfer's green fee for the hole they have just played.
## Returns what they paid.
func collect_fee(g: Golfer, hole: Hole, hole_i: int) -> float:
	var n := hole_i + 1
	var share := pay_share(enjoyment(g))
	# members get their tier's discount
	var fee := float(int(round(worth(g, hole) * share * (1.0 - sim.members.discount(g)) * sim.diff("fee"))))
	hole.payers += 1
	if fee <= 0.0:
		sim.stats.refusals += 1
		g.feel(0.0, "I'm not paying a cent for hole %d." % n)
		sim.feed.say("no_pay", g, {"hole": n})
		return 0.0
	hole.earned += fee
	sim.economy.earn("green_fees", fee)
	g.paid += fee
	sim.popup.emit(g.pos, "+" + Defs.money(fee), "money")
	sim.sound.emit("coin", g.pos, 1.0)
	if share >= 1.2:
		g.feel(0.0, "Hole %d was worth every bit of %s." % [n, Defs.money(fee)])
		sim.feed.say("tip", g, {"hole": n, "fee": Defs.money(fee)})
	elif share < 0.45:
		g.feel(0.0, "Hole %d was barely worth %s." % [n, Defs.money(fee)])
	return fee


func send_home(g: Golfer) -> void:
	var old := g.group
	var gr := Group.new()
	gr.id = _gid
	_gid += 1
	gr.kind = old.kind if old != null else "public"
	gr.state = Group.S.LEAVING
	gr.members.append(g)
	g.group = gr
	g.phase = Golfer.P.IDLE
	groups.append(gr)


func quit(g: Golfer) -> void:
	var old := g.group
	if old != null:
		old.members.erase(g)
		if old.turn == g:
			old.turn = null
	untrack(g.ball)
	send_home(g)


func depart(g: Golfer) -> void:
	untrack(g.ball)
	golfers.erase(g)
	if g.kind != "pro" and g.holes_played > 0:
		recent.append(g.satisfaction)
		if recent.size() > 40:
			recent.pop_front()
		sim.stats.rounds += 1
		if g.satisfaction >= 60.0:
			sim.skills.add_xp("manager", 2 if g.satisfaction >= 80.0 else 1)
		var loud := float(g.persona.get("review", 1.0))
		if g.kind == "public" and sim.rng.randf() < 0.3 * loud:
			_review(g)
			if loud > 1.5:
				# a golf blogger's verdict travels
				sim.buzz += clampf((g.satisfaction - 55.0) / 8.0, -5.0, 5.0)
	if g.kind == "celebrity":
		sim.events.celebrity_left(g)
	sim.members.on_depart(g)
	sim.golfer_removed.emit(g)


func _review(g: Golfer) -> void:
	if g.satisfaction >= 70.0:
		var tag := g.top_tag(true)
		sim.feed.say("review_good", g, {"reason": GOOD_REASONS.get(tag, "Great day out.")})
	elif g.satisfaction <= 40.0:
		var tag := g.top_tag(false)
		sim.feed.say("review_bad", g, {"reason": BAD_REASONS.get(tag, "Just not good enough.")})
	elif sim.rng.randf() < 0.4:
		var tag := g.top_tag(false)
		sim.feed.say("review_mid", g, {"reason": BAD_REASONS.get(tag, "Nothing special.")})


func reason_for(g: Golfer) -> String:
	var tag := g.top_tag(false)
	return BAD_REASONS.get(tag, "It just wasn't for me.")


func average_satisfaction() -> float:
	if recent.is_empty():
		return 55.0
	var t := 0.0
	for v in recent:
		t += v
	# blend toward neutral until there are enough opinions to trust
	var wgt := minf(recent.size() / 8.0, 1.0)
	return lerpf(55.0, t / recent.size(), wgt)


# --------------------------------------------------- moods and reactions

func _tick_golfer(g: Golfer, dt: float) -> void:
	if g.hit_t > 0.0:
		g.hit_t -= dt
	if g.swing_t >= 0.0:
		g.swing_t += dt
		if g.swing_t > 1.3:
			g.swing_t = -1.0
	if g.cheer_t > 0.0:
		g.cheer_t -= dt
	if g.sulk_t > 0.0:
		g.sulk_t -= dt
	if g.bubble_t > 0.0:
		g.bubble_t -= dt
	if g.kind == "player":
		return
	var riding := g.group != null and g.group.has_cart
	g.thirst += dt * sim.thirst_rate() * g.need_rate("thirst")
	g.hunger += dt / 900.0 * g.need_rate("hunger")
	g.bladder += dt / 760.0 * g.need_rate("bladder")
	g.fatigue += dt / 1000.0 * g.need_rate("fatigue") * (0.3 if riding else 1.0) * (0.5 if sim.resort.has("hotel") else 1.0)
	if g.drunk > 0.0:
		g.drunk = maxf(0.0, g.drunk - dt * 0.0018)
	g.slow_t -= dt
	if g.slow_t <= 0.0:
		g.slow_t = 1.0
		_slow_check(g)


func _slow_check(g: Golfer) -> void:
	var w := sim.weather
	var staying := g.kind == "public" and g.group != null and g.group.state != Group.S.LEAVING
	var bold := float(g.persona.get("tags", {}).get("danger", 1.0)) < 0.0
	if sim.eruption.active():
		g.rd.scare = int(g.rd.scare) + (0 if int(g.rd.scare) > 0 else 1)
		g.feel(-0.5, "The volcano is erupting. Why am I still out here?", "eruption")
		if staying and not bold and sim.rng.randf() < 0.03:
			quit(g)
			return
	if w.kind == Weather.K.STORM:
		g.rd.storm = 1
		g.feel(-0.4, "This storm is frightening.", "storm")
		if staying and not bold and sim.rng.randf() < 0.02:
			sim.feed.say("storm", g)
			quit(g)
			return
	elif w.rain > 0.45:
		g.feel(-0.12, "I'm getting soaked.", "rain")
		if sim.rng.randf() < 0.01:
			sim.feed.say("rain", g)
	# needs that nobody met
	if g.thirst > 1.0:
		g.thirst = 0.55
		_grumble(g, -3.0, "I'm parched. Is there nowhere to buy a drink?", "thirst", "thirsty")
	if g.hunger > 1.0:
		g.hunger = 0.6
		_grumble(g, -2.5, "I'm starving. Is there nowhere to eat out here?", "hungry", "hungry")
	if g.bladder > 1.0:
		g.bladder = 0.7
		_grumble(g, -3.5, "I really, really need a restroom.", "restroom", "restroom")
	if g.fatigue > 1.0:
		g.fatigue = 0.65
		_grumble(g, -2.0, "My feet are killing me. A bench or a cart would be nice.", "tired", "")
	var celeb := sim.events.celebrity
	if celeb != null and g.kind == "public" and not g.saw_celebrity:
		if g.pos.distance_squared_to(celeb.pos) < 70.0 * 70.0:
			g.saw_celebrity = true
			g.feel(6.0, "I just saw %s!" % celeb.name, "celebrity")
			sim.feed.say("celebrity_spotted", g, {"other": celeb.name, "hole": _hole_no(g)})
	# wildlife
	var animal := sim.wildlife.near(g.pos, 32.0)
	if animal != null and not g.seen_animals.has(animal.kind):
		g.seen_animals[animal.kind] = true
		var what := str(Wildlife.NAMES.get(animal.kind, animal.kind))
		g.feel(1.4, "Look, a %s!" % what, "scenery")
		if sim.rng.randf() < 0.15:
			sim.feed.say("animal", g, {"animal": what, "hole": _hole_no(g)})
	# a drinker's temper is shorter: the line where they snap sits higher
	if g.satisfaction < 18.0 + g.drunk * 20.0 and staying and not g.tantrum and sim.rng.randf() < 0.07:
		_tantrum(g)
		return
	if g.satisfaction < 7.0 + g.drunk * 8.0 and staying and g.member.is_empty():
		g.feel(0.0, "I've had enough of this place.")
		quit(g)


## A golfer at the end of their rope. A senior marshal nearby will walk them
## off quietly; otherwise something gets thrown.
func _tantrum(g: Golfer) -> void:
	g.tantrum = true
	for m in sim.crew.members:
		if m.role.id == "marshal" and m.level > 1 and m.pos.distance_squared_to(g.pos) < 90.0 * 90.0:
			sim.toast.emit("A marshal walked %s off the course before things got ugly." % g.name, "info")
			sim.feed.say("ejected", g)
			quit(g)
			return
	sim.stats.tantrums = int(sim.stats.tantrums) + 1
	var n := _hole_no(g)
	var partner: Golfer = null
	if g.group != null:
		for m in g.group.members:
			if m != g and m.hit_t <= 0.0:
				partner = m
				break
	if partner != null and sim.rng.randf() < 0.3:
		partner.hit_t = 2.6
		partner.feel(-10.0, "%s just punched me!" % g.name, "hit")
		g.bubble = "That's IT!"
		g.bubble_t = 3.0
		g.bubble_mood = -1
		sim.popup.emit(partner.pos, "POW!", "hit")
		sim.feed.say("tantrum_punch", partner, {"hole": n}, true)
		sim.toast.emit("%s punched a playing partner on hole %d." % [g.name, n], "bad")
	else:
		g.swing_t = 0.0
		g.bubble = "This club is going in the lake."
		g.bubble_t = 3.5
		g.bubble_mood = -1
		sim.popup.emit(g.pos, "CLUB TOSS!", "hit")
		sim.feed.say("tantrum_toss", g, {"hole": n}, true)
		for other in golfers:
			if other != g and other.pos.distance_squared_to(g.pos) < 30.0 * 30.0:
				other.feel(-1.5, "Somebody over there is having a meltdown.", "hit")
				if sim.rng.randf() < 0.15:
					sim.feed.say("tantrum_seen", other)
	if sim.rng.randf() < 0.6:
		quit(g)


func _grumble(g: Golfer, delta: float, text: String, tag: String, post: String) -> void:
	g.rd.grumbles = int(g.rd.grumbles) + 1
	g.feel(delta, text, tag)
	if post != "" and sim.rng.randf() < 0.3:
		sim.feed.say(post, g, {"hole": _hole_no(g)})


# ------------------------------------------------- facilities on the course

## The best stop for a group between holes: a restroom, a snack bar or a
## drink stand that is not too far out of their way. Empty if none is worth it.
func plan_stop(gr: Group) -> Dictionary:
	_refresh_amenities()
	var next := gr.current_hole(sim)
	if next == null or gr.members.is_empty():
		return {}
	var here := gr.members[0].pos
	var best := {}
	var best_score := 0.0
	for kind: String in ["restroom", "snack", "drink", "vending", "bar"]:
		var need := 0.0
		for m in gr.members:
			need += maxf(0.0, m.need_for(kind) - 0.45)
		if need <= 0.0:
			continue
		var spots: Array = facilities.get(kind, [])
		for spot: Vector3 in spots:
			var detour := here.distance_to(spot) + spot.distance_to(next.tee) - here.distance_to(next.tee)
			if detour > 150.0:
				continue
			var score := need * 120.0 - detour
			if kind == "vending":
				# the machine is what you use when nothing better is near
				score -= 25.0
			if score > best_score:
				best_score = score
				var toward := (here - spot)
				toward.y = 0.0
				var front := spot + toward.normalized() * 4.0 if toward.length() > 0.1 else spot
				best = {"kind": kind, "pos": sim.course.on_ground(front.x, front.z), "timer": 4.0}
	return best


## Everyone in the group who wants what this stop offers gets it.
func serve(gr: Group, kind: String) -> void:
	var retail := sim.skills.mult("retail")
	if not gr.story.is_empty():
		gr.story.stopped = true
	for g in gr.members:
		if g.need_for(kind) < 0.3:
			continue
		g.rd.served = int(g.rd.served) + 1
		match kind:
			"drink":
				g.thirst = 0.0
				g.bladder += 0.15
				sim.economy.earn("concessions", 6.0 * retail)
				sim.popup.emit(g.pos, "+$6", "money")
				g.feel(3.0, "That cold drink hit the spot.", "drink")
				sim.sound.emit("slurp", g.pos, 0.8)
				if sim.rng.randf() < 0.1:
					sim.feed.say("drink", g)
			"snack":
				g.hunger = 0.0
				g.thirst = minf(g.thirst, 0.2)
				g.bladder += 0.1
				sim.economy.earn("concessions", 11.0 * retail)
				sim.popup.emit(g.pos, "+$11", "money")
				g.feel(3.5, "A hot dog and a soda between holes. Perfect.", "snack")
				sim.sound.emit("burp", g.pos, 1.0)
				if sim.rng.randf() < 0.1:
					sim.feed.say("snack", g)
			"restroom":
				g.bladder = 0.0
				g.feel(2.0, "A clean restroom, right when I needed one.", "amenity")
				sim.sound.emit("flush", g.pos, 1.0)
			"vending":
				# a can and a bag of something: cheaper, and nobody raves about it
				var take := 0.0
				if g.thirst >= 0.3:
					g.thirst = 0.0
					g.bladder += 0.12
					take += 4.0
					sim.sound.emit("slurp", g.pos, 0.7)
				if g.hunger >= 0.3:
					g.hunger = 0.0
					take += 7.0
					sim.sound.emit("burp", g.pos, 0.8)
				if take > 0.0:
					sim.economy.earn("concessions", take * retail)
					sim.popup.emit(g.pos, "+$%d" % int(take), "money")
					g.feel(2.0 if take > 4.0 else 1.5, "Vending machine. It'll do.", "snack")
			"bar":
				g.thirst = 0.0
				g.bladder += 0.25
				g.drunk = minf(1.0, g.drunk + 0.35)
				g.rd.drinks = int(g.rd.get("drinks", 0)) + 1
				sim.economy.earn("concessions", 14.0 * retail)
				sim.popup.emit(g.pos, "+$14", "money")
				g.feel(4.0, BAR_LINES[sim.rng.randi() % BAR_LINES.size()], "drink")
				sim.sound.emit("bottle", g.pos, 1.0)
				if sim.rng.randf() < 0.15:
					sim.feed.say("bar", g)


func facility_near(kind: String, p: Vector3, radius: float) -> bool:
	_refresh_amenities()
	var spots: Array = facilities.get(kind, [])
	for spot: Vector3 in spots:
		if Vector2(spot.x - p.x, spot.z - p.z).length_squared() < radius * radius:
			return true
	return false


## A group's story moves on a little with every hole they finish.
func story_tick(gr: Group, hole_i: int) -> void:
	var st := gr.story
	if st.is_empty() or st.done or gr.members.is_empty():
		return
	var lift := 0.0
	for m in gr.members:
		lift += m.satisfaction - m.sat_at_tee
	lift /= gr.members.size()
	var gain := 0.2 + lift / 30.0
	if st.stopped:
		gain += 0.1
		st.stopped = false
	if hole_i < sim.course.holes.size():
		gain += sim.scenery_score(sim.course.holes[hole_i]) * 0.15
	st.progress = clampf(float(st.progress) + maxf(gain, 0.04), 0.0, 1.0)
	if float(st.progress) < 1.0:
		return
	st.done = true
	sim.stats.stories = int(sim.stats.get("stories", 0)) + 1
	for m in gr.members:
		m.feel(5.0, "%s. What a day." % st.done_text, "story")
	var teller := gr.members[sim.rng.randi() % gr.members.size()]
	sim.feed.say("story_done", teller, {"story": st.done_text})
	if float(st.tip) > 0.0:
		sim.economy.earn("events", float(st.tip))
		sim.popup.emit(teller.pos, "+" + Defs.money(float(st.tip)), "money")
		sim.toast.emit("%s on your course, and left a %s thank-you at the clubhouse." % [st.done_text, Defs.money(float(st.tip))], "good")


func _hole_no(g: Golfer) -> int:
	return g.group.hole_i + 1 if g.group != null else 1


func _refresh_amenities() -> void:
	var course := sim.course
	if _amen_rev == course.revision:
		return
	_amen_rev = course.revision
	facilities = {}
	amenities = {"drink": 0, "restroom": 0, "bench": 0, "snack": 0, "washer": 0, "putting": 0, "range": 0,
		"cart_barn": 0, "fountain": 0, "landmark": 0, "lot": 0, "house": 0, "tennis": 0, "hotel": 0, "marina": 0, "airstrip": 0,
		"vending": 0, "bar": 0}
	for i in course.objects.size():
		var o := course.objects[i]
		if o == 0 or not FACILITY.has(o):
			continue
		var kind: String = FACILITY[o]
		amenities[kind] = int(amenities[kind]) + 1
		if not facilities.has(kind):
			facilities[kind] = []
		(facilities[kind] as Array).append(course.tile_center(i % course.w, i / course.w))


func amenity_counts() -> Dictionary:
	_refresh_amenities()
	return amenities


func on_holed(g: Golfer, hole: Hole, hole_i: int) -> void:
	g.cheer_t = 2.0
	if g.strokes == 1:
		g.feel(30.0, "A HOLE IN ONE on hole %d!" % (hole_i + 1), "score")
		g.cheer_t = 5.0
		sim.stats.aces += 1
		sim.feed.say("hole_in_one", g, {"hole": hole_i + 1}, true)
		sim.toast.emit("%s made a hole in one on hole %d!" % [g.name, hole_i + 1], "good")
		sim.popup.emit(g.pos, "HOLE IN ONE!", "good")
		sim.sound.emit("cheer", g.pos, 1.0)
		sim.sound.emit("ovation", g.pos, 1.0)
	elif not bool(g.plan.get("putt", false)) or float(g.plan.get("dist", 0.0)) > 7.0:
		sim.sound.emit("cheer", g.pos, 0.55)      # a chip-in, or a putt from right across the green


## Mood after a shot comes to rest, driven by what the ball is sitting in.
func react_to_lie(g: Golfer, hole: Hole, hole_i: int) -> void:
	var course := sim.course
	var b := g.ball
	var n := hole_i + 1
	var ti := course.index_at(b.pos.x, b.pos.z)
	if ti < 0:
		return
	var t: int = course.terrain[ti]
	var d := Vector2(b.pos.x - hole.pin.x, b.pos.z - hole.pin.z).length()
	var was_putt: bool = g.plan.get("putt", false)
	var shot_len: float = g.plan.get("dist", 0.0)
	if was_putt:
		if shot_len < 2.5:
			g.feel(-1.5, "I can't believe I missed that putt.", "putt")
			sim.sound.emit("groan", g.pos, 0.7)
		if course.health[ti] < 0.45:
			g.feel(-1.5, "The green on hole %d is bumpy and bare." % n, "greens_bad")
			sim.feed.say("greens_bad", g, {"hole": n})
		elif course.health[ti] > 0.92 and sim.rng.randf() < 0.15:
			g.feel(0.8, "These greens roll beautifully.", "greens")
			sim.feed.say("greens_good", g, {"hole": n})
	else:
		match t:
			Defs.T.GREEN:
				if shot_len > 60.0:
					g.feel(2.5, "On the green from %d yards!" % Defs.yards(shot_len), "shot")
				if d < 2.5 and shot_len > 30.0:
					g.cheer_t = 1.5
					g.feel(2.0, "Stuck it close on hole %d." % n, "shot")
			Defs.T.BUNKER:
				g.feel(-0.6, "In the sand on hole %d." % n, "bunker")
			Defs.T.DEEP_ROUGH:
				g.feel(-0.6, "I'm in the thick stuff on hole %d." % n, "rough")
			Defs.T.FAIRWAY:
				if g.strokes == 1 and shot_len > 170.0:
					g.feel(1.5, "Striped that drive down the middle.", "shot")
		if g.mishit:
			g.feel(-0.6, "Ugh. Terrible contact.", "")
		if b.hits > 0 and b.hit_obj != 0 and not Defs.is_tree(b.hit_obj):
			# a ricochet: a gift or a curse, depending on where it finished
			var thing := sim.object_name(b.hit_obj).to_lower()
			if t == Defs.T.GREEN or t == Defs.T.FAIRWAY:
				g.feel(1.5, "A lucky bounce off the %s on hole %d!" % [thing, n], "shot")
				sim.feed.say("lucky_bounce", g, {"hole": n, "thing": thing})
			else:
				g.feel(-0.6, "Clattered off the %s on hole %d." % [thing, n], "")
		elif b.tree_tile >= 0:
			if Defs.is_tree(course.objects[b.tree_tile]):
				if b.hits > 0 and (t == Defs.T.GREEN or t == Defs.T.FAIRWAY):
					g.feel(1.2, "Off a tree and back into play on hole %d. I'll take it." % n, "shot")
					sim.feed.say("lucky_bounce", g, {"hole": n, "thing": "tree"})
				else:
					g.feel(-0.8, "Rattled around in the trees on hole %d." % n, "")
			else:
				g.feel(-0.6, "Buried in a bush on hole %d." % n, "")
	if t != Defs.T.BUNKER and course.wet[ti] > 0.75:
		g.feel(-1.3, "Hole %d is waterlogged." % n, "wet")
		sim.feed.say("wet", g, {"hole": n})
	if course.weeds[ti] > 0.5:
		g.feel(-1.5, "The weeds on hole %d are out of control." % n, "weeds")
		sim.feed.say("weeds", g, {"hole": n})
	if course.pests[ti] > 0.4:
		g.feel(-1.5, "Gopher mounds all over hole %d." % n, "pests")
		sim.feed.say("pests", g, {"hole": n})


func on_hole_done(g: Golfer, hole: Hole, hole_i: int, group: Group) -> void:
	var n := hole_i + 1
	var score := hole.par + 5 if g.picked_up else g.strokes
	g.scores.append(score)
	g.pars.append(hole.par)
	if score >= hole.par + 2 and not g.picked_up:
		g.sulk_t = 3.0      # a double bogey or worse: the head drops
	elif score >= hole.par and g.strokes != 1:
		g.cheer_t = 0.0     # a par is nothing to celebrate
	g.holes_played += 1
	hole.record(score)
	sim.stats.holes_played += 1
	if sim.darkness() > 0.55:
		sim.stats["night_holes"] = int(sim.stats.get("night_holes", 0)) + 1
	# Golf is fun: finishing a hole is worth something by itself.
	g.feel(1.0)
	var vs_par := score - hole.par
	var vs_usual := float(vs_par) - (1.0 - g.skill) * 2.2
	if score > 1:
		if vs_par <= -2:
			g.feel(12.0, "An eagle on hole %d!" % n, "score")
			sim.feed.say("eagle", g, {"hole": n})
		elif vs_par == -1:
			g.feel(7.0, "Birdie on hole %d!" % n, "score")
			sim.feed.say("birdie", g, {"hole": n})
		if vs_par <= -1:
			sim.sound.emit("clap", g.pos, 1.0)
		elif vs_usual <= -0.5:
			g.feel(4.0, "A %d on hole %d. I'll take that." % [score, n], "score")
		elif vs_usual <= 0.6:
			g.feel(1.5)
		elif vs_usual <= 1.6:
			g.feel(-1.0, "Hole %d got the better of me." % n, "hard")
		elif vs_usual <= 2.6:
			g.feel(-3.0, "Made a mess of hole %d." % n, "hard")
		else:
			g.feel(-5.0, "A %d on hole %d. That hole is brutal." % [score, n], "hard")
			sim.feed.say("blowup", g, {"hole": n, "score": score})
			sim.sound.emit("groan", g.pos, 0.9)
	var sc := sim.scenery_score(hole)
	if sc > 0.45:
		g.feel(2.2 * sc, "Hole %d is beautiful." % n, "scenery")
		if sim.rng.randf() < 0.2:
			sim.feed.say("scenery", g, {"hole": n})
	elif sc < 0.08:
		g.feel(-0.8, "Hole %d is a bit bare." % n, "bare")
	if g.waited > 60.0:
		g.feel(-minf((g.waited - 60.0) / 30.0, 5.0), "Too much waiting around on hole %d." % n, "wait")
		sim.feed.say("wait", g, {"hole": n})
	g.waited = 0.0
	_judge_design(g, hole, n)
	# the state of the course colours the whole day
	var cond := sim.grounds.condition
	if cond > 0.88:
		g.feel(0.8, "This course is in beautiful shape.", "greens")
	elif cond < 0.5:
		g.feel(-2.0, "This course is in a sorry state.", "greens_bad")
	hole.fun = lerpf(hole.fun, clampf(55.0 + (g.satisfaction - g.sat_at_tee) * 4.0, 0.0, 100.0), 0.12)
	# remember what moved people on this hole, for the hole report
	for tag: String in g.gripes:
		var change := float(g.gripes[tag]) - float(g.gripes_at_tee.get(tag, 0.0))
		if absf(change) > 0.2:
			hole.comments[tag] = float(hole.comments.get(tag, 0.0)) + change
	# green fees: paid here, on the way off the green, for the hole just played
	if not group.free_play:
		collect_fee(g, hole, hole_i)
	if group.kind == "tournament":
		sim.tourney.on_hole(g)
	sim.hole_finished.emit(g, hole_i, score)


## How the design of a hole sits with this particular golfer: does it ask
## for the shots they have, is it a change from the last one, is it a slog?
func _judge_design(g: Golfer, hole: Hole, n: int) -> void:
	if hole.lab_ready:
		var best := maxf(maxf(inverse_lerp(0.74, 1.06, g.power), g.accuracy), g.imagination)
		var asks := [[1, inverse_lerp(0.74, 1.06, g.power), "length"], [2, g.accuracy, "accuracy"], [4, g.imagination, "imagination"]]
		var suited := false
		for a: Array in asks:
			if hole.kind & int(a[0]) == 0:
				continue
			var have: float = a[1]
			if have >= 0.55 and have >= best - 0.05 and not suited:
				suited = true
				g.feel(1.6, "Hole %d suits my game." % n, "suits")
			elif have < 0.3:
				g.feel(-1.5, "Hole %d asks for %s I just don't have." % [n, str(a[2])], "hard")
		if hole.kind == 0 and g.last_kind > 0 and g.last_kind != 0:
			g.feel(1.0, "A breather after that last hole. Lovely.", "suits")
		if g.last_kind >= 0:
			if g.last_kind == hole.kind and g.last_par == hole.par:
				g.feel(-0.6, "Hole %d is just like the last one." % n, "bare")
			else:
				g.feel(0.4, "", "suits")
		g.last_kind = hole.kind
	g.last_par = hole.par
	# a long climb takes it out of anyone on foot
	var climb := hole.pin.y - hole.tee.y
	if climb > 9.0 and not (g.group != null and g.group.has_cart):
		g.fatigue += 0.12
		g.feel(-0.8, "Hole %d is a steep walk." % n, "tired")
	if hole.award != "":
		g.feel(1.5, "I've read about this hole in the magazines.", "prestige")


# ------------------------------------------------------------ live balls

func track_ball(b: Ball, hole: Hole) -> void:
	var i := balls.find(b)
	if i >= 0:
		pins[i] = hole.pin
	else:
		balls.append(b)
		pins.append(hole.pin)


## A group is teeing off in the dark on a hole with no lights. They play it
## anyway, but it is no fun, and what they pay follows how much fun it was.
func on_dark_hole(gr: Group, hole_i: int) -> void:
	for m in gr.members:
		m.feel(-1.8, "Hole %d is pitch dark. I can barely follow my ball." % (hole_i + 1), "dark")
	if not gr.members.is_empty():
		sim.feed.say("too_dark", gr.members[0], {"hole": hole_i + 1})
	if not sim.told_dark and gr.kind != "player":
		sim.told_dark = true
		sim.toast.emit("Night has fallen. Golfers enjoy an unlit hole less and pay less for it, and few new ones turn up. Floodlights and lamp posts (Build, then Lighting) put that right.", "info")


## A group is teeing off on a lit hole after dark.
func on_night_golf(gr: Group, hole_i: int) -> void:
	for m in gr.members:
		if not m.rd.has("night"):
			m.rd["night"] = true
			m.feel(2.0, "Golf under the lights. Magic.", "night")
	if not gr.members.is_empty():
		sim.feed.say("night_golf", gr.members[0], {"hole": hole_i + 1})


## A ball in play has just bounced off something solid.
func _on_ricochet(b: Ball) -> void:
	if b.hit_speed < 3.0:
		return
	sim.stats["ricochets"] = int(sim.stats.get("ricochets", 0)) + 1
	sim.sound.emit("hit_" + b.hit_mat, b.pos, clampf(b.hit_speed / 30.0, 0.2, 1.0))
	if b.hits <= 3:
		sim.popup.emit(b.pos, str(Solids.material(b.hit_mat).get("word", "Thud!")), "hit")
	# a hard one into a wall with windows in it can cost you
	if b.hit_mat != "wall" or b.hit_speed < 14.0:
		return
	var chance := 0.0
	match b.hit_obj:
		Defs.O.HOUSE:
			chance = 0.6
		Defs.O.CLUBHOUSE, Defs.O.HOTEL:
			chance = 0.25
	if sim.rng.randf() >= chance:
		return
	sim.stats.windows = int(sim.stats.windows) + 1
	sim.economy.spend("legal", 50.0)
	sim.popup.emit(b.pos, "SMASH!", "hit")
	sim.sound.emit("glass", b.pos, 1.0)
	if b.hit_obj == Defs.O.HOUSE:
		sim.feed.say("window", null, {}, false, "A homeowner", "FairwayLiving")
	else:
		sim.toast.emit("A golf ball went through a window at the %s. %s to fix." % [sim.object_name(b.hit_obj).to_lower(), Defs.money(50.0)], "bad")


func untrack(b: Ball) -> void:
	var i := balls.find(b)
	if i >= 0:
		balls.remove_at(i)
		pins.remove_at(i)


func _step_balls(dt: float) -> void:
	var wind := sim.weather.wind_vec()
	var course := sim.course
	var i := 0
	while i < balls.size():
		var b := balls[i]
		var ev := b.step(dt, course, wind, pins[i], true)
		if b.state == Ball.S.FLIGHT and b.air_time > 0.25:
			_check_people(b)
		match ev:
			Ball.E.LANDED:
				sim.wildlife.startle(b.pos)
				var lt := course.terrain_at(b.pos.x, b.pos.z)
				var what := "land_soft"
				if lt == Defs.T.BUNKER or lt == Defs.T.ASH:
					what = "land_sand"
				elif lt == Defs.T.PATH or lt == Defs.T.ROCK:
					what = "land_hard"
				sim.sound.emit(what, b.pos, clampf(b.air_time / 4.0, 0.25, 1.0))
			Ball.E.HIT:
				_on_ricochet(b)
			Ball.E.TREE:
				sim.sound.emit("leaves", b.pos, 0.8)
			Ball.E.WATER:
				sim.sound.emit("sizzle" if sim.is_lava() else "splash", b.pos, 1.0)
			Ball.E.OOB:
				sim.sound.emit("oob", b.pos, 1.0)
				sim.popup.emit(b.pos, "Out of bounds", "bad")
			Ball.E.HOLED:
				sim.sound.emit("cup", b.pos, 1.0)
		if b.moving():
			i += 1
		else:
			balls.remove_at(i)
			pins.remove_at(i)


func _check_people(b: Ball) -> void:
	if b.vel.length_squared() < 36.0:
		return
	if b.pos.y - sim.course.height_at(b.pos.x, b.pos.z) > 2.1:
		return
	for p in golfers:
		if p == b.owner or p.hit_t > 0.0:
			continue
		var dx := p.pos.x - b.pos.x
		var dz := p.pos.z - b.pos.z
		if dx * dx + dz * dz < 0.6:
			_bonk(b)
			_on_hit(p, b)
			return
	for s in sim.crew.members:
		if s.hit_t > 0.0:
			continue
		var dx := s.pos.x - b.pos.x
		var dz := s.pos.z - b.pos.z
		if dx * dx + dz * dz < 0.6:
			_bonk(b)
			s.hit_t = 3.0
			sim.stats.hits += 1
			sim.popup.emit(s.pos, "OUCH!", "hit")
			sim.feed.say("staff_hit", null, {}, false, s.name, s.name.replace(" ", ""))
			sim.person_hit.emit(s.pos, b.owner)
			sim.sound.emit("bonk", s.pos, 1.0)
			return


func _bonk(b: Ball) -> void:
	b.vel = Vector3(b.vel.x * 0.15, 2.5, b.vel.z * 0.15)
	b.lift = 0.0
	b.side = 0.0


func _on_hit(victim: Golfer, b: Ball) -> void:
	var hitter := b.owner
	victim.hit_t = 3.2
	victim.hits_taken += 1
	sim.stats.hits += 1
	sim.last_hit_time = sim.time
	var n := _hole_no(victim)
	var part := sim.db.pick("bodyparts", sim.rng)
	victim.feel(-28.0, "I just got hit by a golf ball!", "hit")
	if victim.kind == "celebrity":
		sim.feed.say("celebrity_hit", victim, {"bodypart": part}, true)
		sim.buzz -= 6.0
	else:
		sim.feed.say("hit_victim", victim, {"hole": n, "bodypart": part})
	if hitter != null:
		if hitter.kind == "player":
			sim.stats.player_hits += 1
		else:
			hitter.feel(-4.0, "I hit someone. Mortifying.", "")
			if sim.rng.randf() < 0.4:
				sim.feed.say("hit_hitter", hitter, {"hole": n})
	sim.toast.emit("%s was hit by a golf ball on hole %d!" % [victim.name, n], "bad")
	sim.popup.emit(victim.pos, "OUCH!", "hit")
	if victim.kind != "pro" and sim.rng.randf() < 0.06 * sim.skills.mult("lawsuit"):
		var cost := float(sim.rng.randi_range(4, 15) * 100)
		sim.economy.spend("legal", cost)
		sim.toast.emit("%s is suing over that golf ball. Settled for %s." % [victim.name, Defs.money(cost)], "bad")
	sim.person_hit.emit(victim.pos, hitter)
	sim.sound.emit("bonk", victim.pos, 1.0)


## A lava bomb or a river of lava arrives next to a golfer.
func lava_scare(g: Golfer, _at: Vector3) -> void:
	g.hit_t = 3.4
	g.rd.scare = int(g.rd.scare) + 1
	g.feel(-26.0, "A lava bomb just landed right next to me!", "eruption")
	sim.feed.say("lava_bomb", g, {"hole": _hole_no(g)})
	sim.popup.emit(g.pos, "YEOW!", "hit")


func on_hole_removed(i: int) -> void:
	for gr in groups:
		if gr.state == Group.S.LEAVING or gr.state == Group.S.GONE:
			continue
		if gr.hole_i == i:
			gr.turn = null
			for m in gr.members:
				untrack(m.ball)
				m.phase = Golfer.P.IDLE
			gr.state = Group.S.TO_TEE
		elif gr.hole_i > i:
			gr.hole_i -= 1
