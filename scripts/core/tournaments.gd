class_name Tournaments
extends RefCounted
## Hosting tournaments. You put up the purse; sponsors and the gate pay you
## back, more so when the pros like the course.

signal board_changed()
signal finished(result: Dictionary)

var sim: Sim
var scheduled: Dictionary = {}     # {def, day}
var active: Dictionary = {}        # {def, to_spawn, spawn_t, groups}
var board: Array[Dictionary] = []  # {g, name, to_par, thru, total}
var hosted := {}                   # tournament id -> times hosted
var hosted_year := {}              # tournament id -> last year it was held
var last_result: Dictionary = {}
var rest_until_day := 0
var player_in := false       # the owner is playing in the current event
var player_done := true
## The gallery: where the spectators stand. They follow one group, the
## owner's if the owner is playing, otherwise the leader's, and a few
## scatter along the other holes in play. Rebuilt when that group moves to a
## new hole and every so often as the field gets round the course.
## Each entry: {pos: Vector3, face: float, hole: int, green: bool}.
var gallery: Array[Dictionary] = []
var gallery_hole := -1       # the hole the crowd is following, -1 for none
var gallery_rev := 0         # goes up whenever the gallery is rebuilt
var _gallery_t := 0.0
var _gallery_rng := RandomNumberGenerator.new()   # its own dice: the crowd never disturbs the golf
var size_override := 0       # tests and screenshots: force the gallery's size
var _knot := {}              # the knot of spectators being filled while the gallery is laid out
var _knot_left := 0
var _pin_home: Dictionary = {}   # Hole -> Vector3, where that pin was before the tuck


func _init(s: Sim) -> void:
	sim = s


## Empty string when the event can be booked, otherwise the reason it can't.
func can_host(def: Dictionary) -> String:
	if not active.is_empty():
		return "A tournament is in progress."
	if not scheduled.is_empty():
		return "Another event is already booked."
	if sim.day() < rest_until_day:
		return "The course needs %d more days to recover." % (rest_until_day - sim.day())
	if int(hosted_year.get(def.id, 0)) == sim.year():
		return "Already held this year."
	if sim.course.holes.size() < int(def.min_holes):
		return "Needs %d holes." % int(def.min_holes)
	if sim.rating < float(def.min_rating):
		return "Needs a course rating of %d." % int(def.min_rating)
	if sim.economy.money < float(def.purse):
		return "You need the %s purse in the bank." % Defs.money(float(def.purse))
	return ""


func setup_of(id: String) -> Dictionary:
	var found := DataDB.find(sim.db.setups, id)
	if not found.is_empty():
		return found
	return DataDB.find(sim.db.setups, "standard")


func expected_income(def: Dictionary, setup_id: String = "standard") -> float:
	var gate := float(def.gate) * float(setup_of(setup_id).get("gate", 1.0))
	return (float(def.sponsor) + gate * sim.rating) * sim.skills.mult("tourney_income")


func schedule(id: String, setup_id: String = "standard") -> bool:
	var def := DataDB.find(sim.db.tournaments, id)
	if def.is_empty() or can_host(def) != "":
		return false
	if DataDB.find(sim.db.setups, setup_id).is_empty():
		return false
	scheduled = {"def": def, "day": sim.day() + int(def.lead_days), "setup": setup_id}
	sim.feed.say("tournament_announce", null, {"event": def.name}, true)
	sim.toast.emit("%s booked for %s." % [def.name, Defs.date_text(int(scheduled.day))], "good")
	return true


func cancel() -> void:
	if not scheduled.is_empty():
		scheduled = {}
		sim.buzz -= 4.0
		sim.toast.emit("Tournament cancelled. The organisers are not pleased.", "bad")


func on_day(d: int) -> void:
	if not scheduled.is_empty() and d >= int(scheduled.day) and active.is_empty():
		_start()


func _start() -> void:
	var def: Dictionary = scheduled.def
	var setup_id := str(scheduled.get("setup", "standard"))
	scheduled = {}
	if sim.course.holes.is_empty():
		sim.toast.emit("%s was called off: there are no holes to play." % def.name, "bad")
		return
	active = {"def": def, "to_spawn": int(def.field), "spawn_t": 6.0, "groups": [], "setup": setup_id}
	apply_setup(setup_id)
	board.clear()
	sim.open = false
	player_in = false
	player_done = true
	sim.toast.emit("The %s is under way. The course is closed to the public." % def.name, "good")
	sim.feed.say("tournament_start", null, {"event": def.name}, true)
	board_changed.emit()
	sim.events.pending = {
		"id": "tournament_entry", "title": str(def.name),
		"text": "The field is heading for the first tee. As the owner you have an exemption: do you want to play in it yourself? Finish in the top three and you keep a share of the purse.",
		"options": [{"id": "accept", "text": "Tee it up myself"}, {"id": "decline", "text": "Just watch"}],
	}
	sim.dialog.emit(sim.events.pending)


## The owner has answered the invitation to play.
func player_decided(play: bool) -> void:
	if active.is_empty():
		return
	player_in = play
	player_done = not play
	sim.tournament_entry.emit(play)


## The owner's round is over. An empty card means they withdrew.
func player_finished(card: Array, pars: Array) -> void:
	if not player_in or player_done:
		return
	player_done = true
	if card.size() < sim.course.holes.size():
		sim.toast.emit("You withdrew from the tournament.", "info")
		return
	var total := 0
	var to_par := 0
	for i in card.size():
		total += int(card[i])
		to_par += int(card[i]) - int(pars[i])
	board.append({"g": null, "name": "You (owner)", "to_par": to_par, "thru": card.size(), "total": total})
	_sort()
	board_changed.emit()


func step(dt: float) -> void:
	if active.is_empty():
		if gallery_hole != -1 or not gallery.is_empty():
			gallery.clear()
			gallery_hole = -1
			gallery_rev += 1
		return
	_step_gallery(dt)
	var def: Dictionary = active.def
	if int(active.to_spawn) > 0:
		active.spawn_t = float(active.spawn_t) - dt
		if float(active.spawn_t) <= 0.0:
			var n := mini(2, int(active.to_spawn))
			var lo: float = def.skill[0]
			var hi: float = def.skill[1]
			var gr := sim.visitors.add_group("tournament", n, sim.rng.randf_range(lo, hi), 0.02)
			for g in gr.members:
				board.append({"g": g, "name": g.name, "to_par": 0, "thru": 0, "total": 0})
			var groups: Array = active.groups
			groups.append(gr)
			active.to_spawn = int(active.to_spawn) - n
			active.spawn_t = 30.0
			board_changed.emit()
		return
	for gr: Group in active.groups:
		if gr.state != Group.S.GONE:
			return
	if player_in and not player_done:
		return      # the owner is still out there
	_finish()


## How far round the course the followed group has got, 0 to 1.
func progress() -> float:
	var gr := followed_group()
	if gr == null or sim.course.holes.is_empty():
		return 0.0
	return clampf(float(gr.hole_i) / float(sim.course.holes.size()), 0.0, 1.0)


## The group the crowd follows: the owner's when the owner is out there,
## otherwise the leader's, otherwise whoever is still playing.
func followed_group() -> Group:
	if active.is_empty():
		return null
	if player_in and not player_done:
		for g in sim.visitors.golfers:
			if g.kind == "player" and g.group != null and g.group.state == Group.S.PLAY:
				return g.group
	for e in board:
		if e.g != null:
			var g: Golfer = e.g
			if g.group != null and g.group.state == Group.S.PLAY:
				return g.group
	for gr: Group in active.groups:
		if gr.state == Group.S.PLAY:
			return gr
	return null


## How many spectators line the followed hole: a few dozen at a club
## championship, a few hundred at the majors, and more as the event goes on.
func gallery_size() -> int:
	if active.is_empty():
		return 0
	if size_override > 0:
		return size_override
	var def: Dictionary = active.def
	var base := 20.0 + float(def.prestige) * 9.0
	return int(base * (0.55 + 0.45 * progress()))


func _step_gallery(dt: float) -> void:
	_gallery_t -= dt
	var gr := followed_group()
	var h := gr.hole_i if gr != null else -1
	if h != gallery_hole or _gallery_t <= 0.0:
		_gallery_t = 25.0
		_build_gallery(h)


func _build_gallery(h: int) -> void:
	gallery.clear()
	gallery_hole = h
	gallery_rev += 1
	var holes := sim.course.holes
	if h < 0 or h >= holes.size():
		return
	_gallery_rng.seed = sim.rng.seed ^ (h * 7919) ^ (sim.day() * 131) ^ 0x3a7c
	_knot = {}
	_knot_left = 0
	_line_hole(h, gallery_size(), true)
	var def: Dictionary = active.def
	var few := 3 + int(def.prestige) / 4
	for gr: Group in active.groups:
		if gr.state == Group.S.PLAY and gr.hole_i != h and gr.hole_i < holes.size():
			_line_hole(gr.hole_i, few, false)


## Stand `count` people along a hole: round the green behind the rope, and
## in knots down both sides of the fairway. Nobody stands on a playing
## surface, in water, on something built, or on land the club does not own.
func _line_hole(h: int, count: int, main: bool) -> void:
	var hole: Hole = sim.course.holes[h]
	var rng := _gallery_rng
	var tee := Vector2(hole.tee.x, hole.tee.z)
	var pin := Vector2(hole.pin.x, hole.pin.z)
	var line := pin - tee
	var length := line.length()
	if length < 1.0:
		return
	var dir := line / length
	var perp := Vector2(-dir.y, dir.x)
	var at_green := int(count * (0.5 if main else 0.3))
	for k in count:
		var placed := false
		if k < at_green:
			# a ring round the green, as close in as the rough allows
			var ang := rng.randf() * TAU
			var out := Vector2(cos(ang), sin(ang))
			var r := 7.0
			while r < 24.0 and not placed:
				var p := pin + out * r + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
				if _standable(p):
					gallery.append({"pos": sim.course.on_ground(p.x, p.y), "face": (pin - p).angle(), "hole": h, "green": true})
					placed = true
				r += 1.5
		else:
			# knots of people down the sides of the fairway, facing the line of
			# play: every few people a new knot starts a little further along
			if _knot.is_empty() or _knot_left <= 0:
				var s := rng.randf_range(minf(35.0, length * 0.3), maxf(40.0, length - 30.0))
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var centre := tee + dir * s
				var d := 6.0
				_knot = {}
				while d < 42.0 and _knot.is_empty():
					var p := centre + perp * (side * d)
					if _standable(p):
						_knot = {"at": p, "centre": centre}
					d += 2.0
				_knot_left = 2 + rng.randi() % 4
			if not _knot.is_empty():
				_knot_left -= 1
				var at: Vector2 = _knot.at
				var centre: Vector2 = _knot.centre
				var p := at + dir * rng.randf_range(-2.4, 2.4) + perp * rng.randf_range(-0.4, 1.8) * signf((at - centre).dot(perp))
				if _standable(p):
					gallery.append({"pos": sim.course.on_ground(p.x, p.y), "face": (centre - p).angle(), "hole": h, "green": false})


func _standable(p: Vector2) -> bool:
	var course := sim.course
	var i := course.index_at(p.x, p.y)
	if i < 0 or course.locked[i] != 0 or course.objects[i] != 0:
		return false
	var t: int = course.terrain[i]
	return t == Defs.T.ROUGH or t == Defs.T.DEEP_ROUGH or t == Defs.T.PATH


func on_hole(g: Golfer) -> void:
	# the gallery has its say on the hole just finished
	if not gallery.is_empty() and g.group != null and not g.scores.is_empty() and g.scores.size() - 1 == gallery_hole:
		var diff: int = g.scores[-1] - g.pars[-1]
		var hole: Hole = sim.course.holes[gallery_hole]
		var loud := clampf(0.4 + gallery.size() / 200.0, 0.4, 1.0)
		if diff <= -2:
			sim.sound.emit("ovation", hole.pin, loud)
		elif diff == -1:
			sim.sound.emit("clap", hole.pin, loud)
		elif diff >= 2:
			sim.sound.emit("groan", hole.pin, loud * 0.8)
	for e in board:
		if e.g == g:
			e.thru = g.scores.size()
			e.to_par = g.to_par()
			var t := 0
			for s in g.scores:
				t += s
			e.total = t
			break
	_sort()
	board_changed.emit()


func _sort() -> void:
	board.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.to_par != b.to_par:
			return int(a.to_par) < int(b.to_par)
		return int(a.thru) > int(b.thru))


## Put the chosen setup on the course: green speed, rough, and tucked pins.
func apply_setup(id: String) -> void:
	if not _pin_home.is_empty():
		clear_setup()
	var s := setup_of(id)
	sim.course.green_decel = float(s.get("green_decel", 1.0))
	sim.course.rough_power = float(s.get("rough_power", 1.0))
	var tuck := float(s.get("pin_tuck", 0.0))
	_pin_home.clear()
	var moved := false
	for hole in sim.course.holes:
		var was := sim.course.tuck_pin(hole, tuck)
		if hole.pin.distance_squared_to(was) > 0.0001:
			moved = true
		_pin_home[hole] = was
	if moved and sim.undo != null:
		sim.undo.clear()


## Greens, rough and pins go back to how the members play them.
## A hole taken out during the event is skipped: its home pin is not
## written onto whichever hole now sits at that index.
func clear_setup() -> void:
	var moved := false
	for hole in sim.course.holes:
		if not _pin_home.has(hole):
			continue
		var back: Vector3 = _pin_home[hole]
		if hole.pin.distance_squared_to(back) > 0.0001:
			hole.pin = back
			moved = true
	_pin_home.clear()
	sim.course.green_decel = 1.0
	sim.course.rough_power = 1.0
	if moved:
		sim.course.revision += 1
		sim.course.holes_changed.emit()
		if sim.undo != null:
			sim.undo.clear()


func _finish() -> void:
	var def: Dictionary = active.def
	var setup_id := str(active.get("setup", "standard"))
	clear_setup()
	active = {}
	sim.open = true
	var holes := sim.course.holes.size()
	var winner: Dictionary = {}
	var sat := 0.0
	var count := 0
	var finishers: Array[Dictionary] = []
	for e in board:
		if int(e.thru) >= holes:
			finishers.append(e)
			if winner.is_empty():
				winner = e
		if e.g == null:
			continue
		var g: Golfer = e.g
		sat += g.satisfaction
		count += 1
	if winner.is_empty() and not board.is_empty():
		winner = board[0]
	var avg_sat := sat / maxf(count, 1.0)
	var mult := sim.skills.mult("tourney_income")
	var sponsor := float(def.sponsor) * (0.6 + 0.8 * avg_sat / 100.0) * mult
	var gate := float(def.gate) * float(setup_of(setup_id).get("gate", 1.0)) * sim.rating * (1.0 - 0.4 * sim.weather.rain) * mult
	var purse := float(def.purse)
	# The owner keeps a share of the purse for a top-three finish.
	var place := -1
	for i in finishers.size():
		if finishers[i].g == null:
			place = i
	if place >= 0 and place < 3:
		var share: float = [0.5, 0.25, 0.12][place]
		purse *= 1.0 - share
		sim.skills.add_xp("golfer", 30 - place * 8)
		if place == 0:
			sim.stats.player_wins = int(sim.stats.player_wins) + 1
			sim.feed.say("owner_wins", null, {}, true, "Golf Enquirer", "GolfEnquirer")
			var mine := int(finishers[0].get("to_par", 0))
			var mine_text := "even par" if mine == 0 else ("%+d" % mine)
			sim.remember("win", "Won the %s at %s, %s." % [str(def.name), mine_text, sim.date_text()])
		sim.career.note("tourney_top3")
	player_in = false
	player_done = true
	sim.economy.earn("tournaments", sponsor + gate)
	sim.economy.spend("purses", purse)
	var liked := clampf((avg_sat - 40.0) / 40.0, -0.5, 1.0)
	var prestige := float(def.prestige)
	sim.reputation = clampf(sim.reputation + prestige * liked, 0.0, 100.0)
	sim.buzz += prestige * maxf(liked, 0.2)
	sim.skills.add_xp("manager", int(prestige * 2.0))
	hosted[def.id] = int(hosted.get(def.id, 0)) + 1
	hosted_year[def.id] = sim.year()
	rest_until_day = sim.day() + 10
	var wname := str(winner.get("name", "Nobody"))
	var wscore := int(winner.get("to_par", 0))
	var score_text := "even par" if wscore == 0 else ("%+d" % wscore)
	last_result = {
		"name": def.name, "winner": wname, "score": score_text, "income": sponsor + gate, "purse": purse,
		"net": sponsor + gate - purse, "pro_satisfaction": avg_sat,
	}
	sim.feed.say("tournament_winner", null, {"event": def.name, "other": wname, "score": score_text}, true)
	var voices: Array[Golfer] = []
	for e in board:
		if e.g != null:
			voices.append(e.g)
	if not voices.is_empty():
		sim.feed.say("tournament_pro_good" if avg_sat >= 60.0 else "tournament_pro_bad", voices[sim.rng.randi() % voices.size()], {}, true)
	sim.toast.emit("%s wins the %s at %s. You netted %s." % [wname, def.name, score_text, Defs.money(sponsor + gate - purse)], "good")
	finished.emit(last_result)
	board_changed.emit()
