class_name PlayerProfile
extends RefCounted
## Your own golfer: the clubs and balls you own, and your playing record.

signal changed()

var sim: Sim
var golfer := Golfer.new()
var owned := {}            # "category:brand" -> true
var equipped := {}         # category -> brand id
var ball_stock := {}       # ball id -> count
var ball_id := "standard"
var holes_played := 0
var best_scores := {}      # hole count -> best total to par
var last_card: Array[int] = []


func _init(s: Sim) -> void:
	sim = s
	golfer.kind = "player"
	golfer.name = "You"
	golfer.handle = "TheBoss"
	golfer.skill = 0.5
	golfer.power = 0.92
	golfer.accuracy = 0.5
	golfer.putting = 0.5
	golfer.shirt = Color("f5f5f5")
	golfer.pants = Color("263238")
	golfer.hat = Color("c62828")
	golfer.skin = Color("e0ac69")
	for cat: Dictionary in sim.db.categories:
		equipped[cat.id] = "rental"
		owned["%s:rental" % cat.id] = true
	refresh()


## Push skills and equipment into the golfer the game actually swings with.
func refresh() -> void:
	var sk := sim.skills
	golfer.power = 0.92 * sk.mult("power")
	golfer.bonus_rough = sk.bonus("rough")
	golfer.bonus_sand = sk.bonus("sand")
	golfer.bonus_spread = sk.bonus("spread")
	for cat: Dictionary in sim.db.categories:
		golfer.brands[cat.id] = sim.db.brand(str(equipped[cat.id]))
	golfer.ball.set_def(sim.db.ball(ball_id))
	golfer.ball.lava = sim.is_lava()
	golfer.ball.m_wet *= sk.mult("wet")
	golfer.ball.m_cup *= 1.0 + sk.bonus("cup")
	golfer.ball.m_spin *= 1.0 + sk.bonus("spin_add")
	changed.emit()


func price(cat_id: String, brand_id: String) -> int:
	var cat := DataDB.find(sim.db.categories, cat_id)
	var brand := sim.db.brand(brand_id)
	return int(round(float(brand.price) * float(cat.get("share", 0.25)) / 10.0)) * 10


func owns(cat_id: String, brand_id: String) -> bool:
	return owned.has("%s:%s" % [cat_id, brand_id])


func buy(cat_id: String, brand_id: String) -> bool:
	if owns(cat_id, brand_id):
		return equip(cat_id, brand_id)
	var cost := float(price(cat_id, brand_id))
	if not sim.economy.can_afford(cost):
		return false
	sim.economy.spend("equipment", cost)
	owned["%s:%s" % [cat_id, brand_id]] = true
	return equip(cat_id, brand_id)


func equip(cat_id: String, brand_id: String) -> bool:
	if not owns(cat_id, brand_id):
		return false
	equipped[cat_id] = brand_id
	refresh()
	return true


func ball_count(id: String) -> int:
	return 999 if id == "standard" else int(ball_stock.get(id, 0))


## Balls come in sleeves of three.
func buy_balls(id: String) -> bool:
	var def := sim.db.ball(id)
	var cost := float(def.get("price", 0))
	if cost <= 0.0 or not sim.economy.can_afford(cost):
		return false
	sim.economy.spend("equipment", cost)
	ball_stock[id] = int(ball_stock.get(id, 0)) + 3
	changed.emit()
	return true


func use_ball(id: String) -> bool:
	if ball_count(id) <= 0:
		return false
	ball_id = id
	refresh()
	return true


## A special ball is gone for good when it finds water or leaves the course.
func lose_ball() -> void:
	if ball_id == "standard":
		return
	ball_stock[ball_id] = maxi(0, int(ball_stock.get(ball_id, 0)) - 1)
	if int(ball_stock[ball_id]) <= 0:
		sim.toast.emit("That was your last %s. Back to the Range Rock." % sim.db.ball(ball_id).name, "info")
		ball_id = "standard"
	refresh()


func to_dict() -> Dictionary:
	return {"owned": owned.keys(), "equipped": equipped, "balls": ball_stock, "ball": ball_id, "holes": holes_played, "best": best_scores}


func from_dict(d: Dictionary) -> void:
	owned = {}
	for k: String in d.get("owned", []):
		owned[k] = true
	for k: String in d.get("equipped", {}):
		equipped[k] = str(d.equipped[k])
	ball_stock = {}
	for k: String in d.get("balls", {}):
		ball_stock[k] = int(d.balls[k])
	ball_id = str(d.get("ball", "standard"))
	holes_played = int(d.get("holes", 0))
	best_scores = d.get("best", {})
	refresh()
