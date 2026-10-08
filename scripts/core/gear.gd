class_name Gear
extends RefCounted
## Club distance tables, measured by firing balls down a flat test range with
## the real physics. The AI and the aiming preview both read from them.

const STEPS := 12

var db: DataDB
var n_clubs := 0
var putter_i := 0
var _speed: Array[PackedFloat32Array] = []
var _total: Array[PackedFloat32Array] = []
var _carry: Array[PackedFloat32Array] = []


func _init(data: DataDB) -> void:
	db = data
	n_clubs = db.clubs.size()
	var lane := Course.new(160, 3)
	lane.terrain.fill(Defs.T.FAIRWAY)
	var ball := Ball.new()
	for ci in n_clubs:
		var c: Dictionary = db.clubs[ci]
		var sp := PackedFloat32Array()
		var tot := PackedFloat32Array()
		var car := PackedFloat32Array()
		if c.id == "putter":
			putter_i = ci
		else:
			var base: float = c.speed
			for k in STEPS:
				var v := base * (0.25 + 0.1 * k)
				ball.place(Vector3(10.0, 0.0, 7.5))
				ball.launch(v, 0.0, deg_to_rad(c.loft), c.lift, 0.0, c.spin)
				var n := 0
				while ball.moving() and n < 3000:
					ball.step(1.0 / 60.0, lane, Vector3.ZERO, Vector3.ZERO, false)
					n += 1
				sp.append(v)
				tot.append(ball.pos.x - 10.0)
				car.append(ball.carry.x - 10.0)
		_speed.append(sp)
		_total.append(tot)
		_carry.append(car)


func total_at(ci: int, speed: float) -> float:
	return _lookup(_speed[ci], _total[ci], speed)


func carry_at(ci: int, speed: float) -> float:
	return _lookup(_speed[ci], _carry[ci], speed)


## Launch speed that sends this club a given total distance on flat fairway.
func speed_for(ci: int, total: float) -> float:
	var sp := _speed[ci]
	var tot := _total[ci]
	if sp.is_empty():
		return 0.0
	if total <= tot[0]:
		return sp[0] * sqrt(maxf(total, 0.05) / maxf(tot[0], 0.1))
	return _lookup(tot, sp, total)


static func _lookup(xs: PackedFloat32Array, ys: PackedFloat32Array, x: float) -> float:
	var n := xs.size()
	if n == 0:
		return 0.0
	if x <= xs[0]:
		return ys[0] * x / maxf(xs[0], 0.001)
	for i in range(1, n):
		if x <= xs[i]:
			var t := (x - xs[i - 1]) / maxf(xs[i] - xs[i - 1], 0.0001)
			return lerpf(ys[i - 1], ys[i], t)
	return ys[n - 1]


## A golfer's flat-out ball speed with a club.
func full_speed(g: Golfer, ci: int) -> float:
	var c: Dictionary = db.clubs[ci]
	var base: float = c.speed
	var bp: float = g.brand_of(c.cat).get("power", 1.0)
	return base * g.power * bp


func _first_club(lie: int) -> int:
	if lie == Defs.T.TEE:
		return 0
	if lie == Defs.T.BUNKER or lie == Defs.T.DEEP_ROUGH:
		return mini(5, n_clubs - 2)   # nothing longer than a 6 iron from trouble
	return 1                          # no driver off the deck


## The longest total distance this golfer can hit from a lie.
func max_total(g: Golfer, lie: int, course: Course = null) -> float:
	var ci := _first_club(lie)
	return total_at(ci, full_speed(g, ci) * g.lie_power(lie, course))


## Shortest club that covers the distance. Returns [club index, launch speed].
func pick(g: Golfer, dist: float, lie: int, course: Course = null) -> Array:
	var first := _first_club(lie)
	var lp := g.lie_power(lie, course)
	for ci in range(n_clubs - 1, first - 1, -1):
		if ci == putter_i:
			continue
		if total_at(ci, full_speed(g, ci) * lp) >= dist:
			return [ci, speed_for(ci, dist)]
	return [first, full_speed(g, first) * lp]
