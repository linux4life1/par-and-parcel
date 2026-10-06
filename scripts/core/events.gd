class_name Events
extends RefCounted
## Random happenings that keep a season from being predictable.

var sim: Sim
var celebrity: Golfer = null
var timer := 220.0
var pending: Dictionary = {}       # a dialog waiting for the player's choice
var sponsor_until := -1.0
var history: Array[String] = []
var _last := {}

# Shortest gap between two events of the same kind, in days.
const GAP := {
	"celebrity": 70, "heat_wave": 80, "pest_outbreak": 70, "weed_bloom": 60, "outing": 50,
	"magazine": 110, "storm_front": 50, "viral": 40, "sponsor": 110, "eruption": 80,
	"commissioner": 150, "heiress": 200, "investor": 120, "match": 90,
}


func _init(s: Sim) -> void:
	sim = s


func step(dt: float) -> void:
	timer -= dt
	if timer > 0.0:
		return
	timer = sim.rng.randf_range(140.0, 260.0)
	var options := _candidates()
	if options.is_empty():
		return
	var total := 0.0
	for o: Array in options:
		total += float(o[1])
	var r := sim.rng.randf() * total
	for o: Array in options:
		r -= float(o[1])
		if r <= 0.0:
			trigger(str(o[0]))
			return


func _candidates() -> Array:
	var out := []
	var holes := sim.course.holes.size()
	var month := sim.month()
	var quiet := sim.tourney.active.is_empty()
	if holes >= 3 and sim.rating >= 40.0 and celebrity == null and quiet:
		out.append(["celebrity", 3.0 * (1.0 + sim.skills.bonus("celebrity")) * (2.0 if sim.resort.has("marina") else 1.0)])
	if month >= 3 and month <= 5 and sim.time > sim.weather.heat_until:
		out.append(["heat_wave", 2.0])
	if holes >= 1:
		out.append(["pest_outbreak", 2.0])
		if month <= 2:
			out.append(["weed_bloom", 2.0])
	if holes >= 3 and quiet:
		if sim.rating >= 35.0:
			out.append(["outing", 3.0])
		out.append(["magazine", 2.0])
	out.append(["storm_front", 1.5])
	if sim.eruption.has_volcano() and sim.eruption.state == Eruption.S.QUIET and sim.day() > 20:
		out.append(["eruption", 4.0])
	if sim.time - sim.last_hit_time < 120.0:
		out.append(["viral", 3.0])
	if sim.rating >= 45.0 and pending.is_empty() and sim.time > sponsor_until:
		out.append(["sponsor", 2.0])
	# very important visitors, each with something to give if they enjoy it
	if holes >= 2 and celebrity == null and quiet:
		out.append(["investor", 2.0])
		if sim.course.locked.has(1):
			out.append(["commissioner", 2.0])
		if holes >= 4:
			out.append(["heiress", 1.5])
	if holes >= 2 and quiet and pending.is_empty():
		out.append(["match", 2.0])
	var today := sim.day()
	var ok := []
	for o: Array in out:
		var id := str(o[0])
		if today - int(_last.get(id, -9999)) >= int(GAP.get(id, 30)):
			ok.append(o)
	return ok


func trigger(id: String) -> void:
	history.append(id)
	_last[id] = sim.day()
	match id:
		"celebrity":
			_celebrity()
		"heat_wave":
			sim.weather.heat_until = sim.time + 8.0 * Defs.DAY_SECONDS
			sim.toast.emit("A heat wave has arrived. The course will dry out fast and golfers will be thirsty.", "info")
			sim.feed.say("heat", null, {}, true, "County Weather", "CountyWeather")
		"pest_outbreak":
			sim.grounds.seed_trouble("pests", 7)
			sim.toast.emit("Gophers have been spotted digging up the course.", "bad")
		"weed_bloom":
			sim.grounds.seed_trouble("weeds", 30)
			sim.toast.emit("Spring showers have set off a bloom of weeds.", "bad")
		"outing":
			var fee := float(int(120.0 * sim.course.holes.size() * (0.6 + sim.rating / 100.0) / 10.0) * 10)
			sim.economy.earn("events", fee)
			for i in 3:
				var gr := sim.visitors.add_group("outing", 4, 0.25, 0.12)
				gr.free_play = true
			sim.toast.emit("A corporate outing has booked the course for %s." % Defs.money(fee), "good")
		"commissioner", "heiress", "investor":
			_vip(id)
		"match":
			_match_offer()
		"eruption":
			sim.eruption.start()
		"storm_front":
			sim.weather.force(Weather.K.STORM, 14.0)
			sim.toast.emit("Storm warning: a front is minutes away.", "bad")
		"magazine":
			if sim.rating >= 62.0:
				sim.buzz += 15.0
				sim.feed.say("news_good", null, {}, true, "Golf Weekly", "GolfWeekly")
				sim.toast.emit("Golf Weekly published a glowing review. Expect more visitors.", "good")
			elif sim.rating <= 42.0:
				sim.buzz -= 10.0
				sim.feed.say("news_bad", null, {}, true, "The County Gazette", "CountyGazette")
				sim.toast.emit("The local paper ran an unkind story about the course.", "bad")
			else:
				sim.toast.emit("A golf magazine visited and filed a lukewarm review.", "info")
		"viral":
			sim.buzz += 12.0
			sim.feed.say("viral", null, {}, true, "FailClips", "FailClips")
			sim.toast.emit("A clip of a golfer getting hit on your course has gone viral. Any publicity is good publicity.", "info")
		"sponsor":
			var amount := float(int(500.0 + sim.rating * 20.0) / 100 * 100)
			pending = {
				"id": "sponsor", "title": "Sponsorship offer", "amount": amount,
				"text": "Thunderhead Golf wants to line your fairways with banners for the next two months. Golfers find them tacky.",
				"options": [{"id": "accept", "text": "Take the money (%s)" % Defs.money(amount)}, {"id": "decline", "text": "Keep it classy"}],
			}
			sim.dialog.emit(pending)


func choose(option: String) -> void:
	if pending.is_empty():
		return
	if pending.id == "match":
		var offer := pending
		pending = {}
		if option == "accept":
			sim.match_accepted.emit(offer)
		else:
			sim.toast.emit("%s shrugs and heads for the bar." % str(offer.rival), "info")
		return
	if pending.id == "tournament_entry":
		var want := option == "accept"
		pending = {}
		sim.tourney.player_decided(want)
		return
	if pending.id == "sponsor":
		if option == "accept":
			sim.economy.earn("events", float(pending.amount))
			sponsor_until = sim.time + 56.0 * Defs.DAY_SECONDS
			sim.toast.emit("Banners are going up. %s banked." % Defs.money(float(pending.amount)), "good")
		else:
			sim.buzz += 3.0
			sponsor_until = sim.time + 28.0 * Defs.DAY_SECONDS
			sim.toast.emit("You turned the sponsor down. The regulars approve.", "info")
	pending = {}


func banners_up() -> bool:
	return sim.time < sponsor_until and history.has("sponsor")


func _celebrity() -> void:
	var list: Array = sim.db.names.get("celebrities", [])
	if list.is_empty():
		return
	var c: Dictionary = list[sim.rng.randi() % list.size()]
	var gr := sim.visitors.add_group("celebrity", sim.rng.randi_range(2, 3), 0.3, 0.12)
	var star := gr.members[0]
	star.kind = "celebrity"
	star.name = c.name
	star.handle = c.handle
	star.title = c.title
	star.wealth = 1.0
	star.shirt = Color("ffd54f")
	star.hat = Color("212121")
	star.satisfaction = 60.0
	celebrity = star
	sim.toast.emit("%s, the %s, has turned up to play your course!" % [star.name, star.title], "good")
	sim.feed.say("celebrity_arrive", star, {}, true)


## A VIP comes to look the place over. Send them home happy and they do
## you a favour: free land, a free landmark, or an investment.
func _vip(role: String) -> void:
	var who: Dictionary = sim.db.names.get("vips", {}).get(role, {})
	if who.is_empty():
		return
	var gr := sim.visitors.add_group("celebrity", 2, 0.35, 0.1)
	var star := gr.members[0]
	star.kind = "celebrity"
	star.vip = role
	star.name = str(who.name)
	star.handle = str(who.handle)
	star.title = str(who.title)
	star.wealth = 1.0
	star.shirt = Color("37474f")
	star.hat = Color("eceff1")
	star.satisfaction = 55.0
	celebrity = star
	var promise := {
		"commissioner": "Impress them and the county will release more land.",
		"heiress": "Impress them and they will donate a landmark.",
		"investor": "Impress them and they will invest in the club.",
	}
	sim.toast.emit("%s, %s, is here to look the course over. %s" % [star.name, star.title, promise[role]], "good")


func _vip_left(g: Golfer) -> void:
	if g.satisfaction < 58.0:
		if g.satisfaction < 40.0:
			sim.feed.say("vip_angry", g, {"reason": sim.visitors.reason_for(g)}, true)
		sim.toast.emit("%s left unimpressed. Nothing came of the visit." % g.name, "bad" if g.satisfaction < 40.0 else "info")
		return
	sim.feed.say("vip_happy", g, {}, true)
	sim.skills.add_xp("manager", 5)
	match g.vip:
		"commissioner":
			sim.land_credits += 3
			sim.toast.emit("%s enjoyed the round. The county has released three parcels of land to you, free." % g.name, "good")
		"heiress":
			sim.gifts[Defs.O.LANDMARK] = int(sim.gifts.get(Defs.O.LANDMARK, 0)) + 1
			sim.toast.emit("%s loved the course and has donated a landmark. Place it from the Build panel at no cost." % g.name, "good")
		"investor":
			var amount := float(int(1500.0 + 400.0 * sim.course.holes.size()) / 100 * 100)
			sim.economy.earn("events", amount)
			sim.toast.emit("%s liked what they saw and invested %s in the club." % [g.name, Defs.money(amount)], "good")


## A visiting pro wants a money match against the owner.
func _match_offer() -> void:
	var list: Array = sim.db.names.get("rival_pros", ["A visiting pro"])
	var rival := str(list[sim.rng.randi() % list.size()])
	var holes := mini(3, sim.course.holes.size())
	var stake := float(int(200.0 + sim.rating * 6.0) / 50 * 50)
	var skill := clampf(0.45 + int(sim.skills.level.golfer) * 0.04, 0.45, 0.9)
	pending = {
		"id": "match", "title": "A challenge", "rival": rival, "holes": holes, "stake": stake, "skill": skill,
		"text": "%s is in the clubhouse and fancies a money match against the owner: %d hole%s, most holes won takes %s. They play to about a %d handicap." % [
			rival, holes, "" if holes == 1 else "s", Defs.money(stake), int(round(lerpf(36.0, -3.0, skill)))],
		"options": [{"id": "accept", "text": "You're on (%s)" % Defs.money(stake)}, {"id": "decline", "text": "Not today"}],
	}
	sim.dialog.emit(pending)


func celebrity_left(g: Golfer) -> void:
	if celebrity == g:
		celebrity = null
	if g.holes_played == 0:
		return
	if g.vip != "":
		_vip_left(g)
		return
	if g.satisfaction >= 62.0:
		var bonus := float(int(600.0 + sim.rating * 25.0) / 100 * 100)
		sim.economy.earn("events", bonus)
		sim.buzz += 20.0
		sim.reputation = minf(100.0, sim.reputation + 3.0)
		sim.skills.add_xp("manager", 6)
		sim.feed.say("celebrity_happy", g, {}, true)
		sim.toast.emit("%s loved the course. The publicity is worth %s." % [g.name, Defs.money(bonus)], "good")
		# now and then a happy celebrity buys a place on the course
		var odds := 0.5 if sim.resort.has("marina") else 0.25
		if sim.rng.randf() < odds and sim.sell_home({"name": g.name, "handle": g.handle}, true):
			sim.reputation = minf(100.0, sim.reputation + 2.0)
			sim.feed.say("celebrity_home", g, {}, true)
	elif g.satisfaction < 42.0:
		sim.buzz -= 15.0
		sim.feed.say("celebrity_angry", g, {"reason": sim.visitors.reason_for(g)}, true)
		sim.toast.emit("%s left unhappy and is telling the world." % g.name, "bad")
	else:
		sim.toast.emit("%s finished their round and left without comment." % g.name, "info")
