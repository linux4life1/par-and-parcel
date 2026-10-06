class_name Wildlife
extends RefCounted
## A few animals that live in the rough. They wander, keep out of the way,
## and bolt when a ball lands near them. Golfers enjoy spotting them.

class Animal:
	extends RefCounted
	var kind := "deer"
	var pos := Vector3.ZERO
	var prev := Vector3.ZERO
	var home := Vector3.ZERO
	var target := Vector3.ZERO
	var facing := 0.0
	var timer := 0.0
	var walking := false
	var bolt := 0.0

const NAMES := {
	"deer": "deer", "duck": "duck", "sheep": "sheep", "stag": "stag", "roadrunner": "roadrunner",
	"tortoise": "tortoise", "goat": "mountain goat", "lizard": "lava lizard",
}
const SPEED := {"deer": 3.0, "duck": 1.2, "sheep": 1.2, "stag": 3.2, "roadrunner": 6.0, "tortoise": 0.25, "goat": 2.4, "lizard": 1.6}

var sim: Sim
var animals: Array[Animal] = []


func _init(s: Sim) -> void:
	sim = s


func populate() -> void:
	animals.clear()
	var course := sim.course
	var kinds: Array = sim.db.names.get("animals", {}).get(str(sim.biome.get("id", "lush")), ["deer"])
	var want := 5 + (course.w * course.h) / 6000
	var tries := 0
	while animals.size() < want and tries < 400:
		tries += 1
		var tx := sim.rng.randi_range(4, course.w - 5)
		var ty := sim.rng.randi_range(4, course.h - 5)
		var i := ty * course.w + tx
		var t: int = course.terrain[i]
		if (t != Defs.T.ROUGH and t != Defs.T.DEEP_ROUGH) or course.hot[i] != 0:
			continue
		var a := Animal.new()
		a.kind = str(kinds[sim.rng.randi() % kinds.size()])
		a.pos = course.tile_center(tx, ty)
		a.prev = a.pos
		a.home = a.pos
		a.target = a.pos
		a.timer = sim.rng.randf_range(1.0, 8.0)
		animals.append(a)


func step(dt: float) -> void:
	var course := sim.course
	for a in animals:
		a.prev = a.pos
		if a.bolt > 0.0:
			a.bolt -= dt
		a.timer -= dt
		if a.timer <= 0.0 and not a.walking:
			# amble somewhere near home, staying out of the hazard
			var p := a.home + Vector3(sim.rng.randf_range(-45.0, 45.0), 0.0, sim.rng.randf_range(-45.0, 45.0))
			if sim.nav.passable(p.x, p.z) and sim.nav.clear_line(a.pos, p):
				a.target = course.on_ground(p.x, p.z)
				a.walking = true
			a.timer = sim.rng.randf_range(4.0, 14.0)
		if a.walking:
			var d := Vector2(a.target.x - a.pos.x, a.target.z - a.pos.z)
			var l := d.length()
			var speed: float = float(SPEED.get(a.kind, 2.0)) * (2.6 if a.bolt > 0.0 else 1.0)
			if l < 0.6:
				a.walking = false
			else:
				var stride := minf(speed * dt, l)
				a.facing = d.angle()
				a.pos.x += d.x / l * stride
				a.pos.z += d.y / l * stride
				a.pos.y = course.height_at(a.pos.x, a.pos.z)


## A ball has landed: anything nearby runs for it.
func startle(p: Vector3) -> void:
	for a in animals:
		if a.pos.distance_squared_to(p) < 18.0 * 18.0 and a.kind != "tortoise":
			var away := a.pos - p
			away.y = 0.0
			var q := a.pos + away.normalized() * 30.0
			if sim.nav.passable(q.x, q.z):
				a.target = sim.course.on_ground(q.x, q.z)
				a.walking = true
				a.bolt = 4.0


## The nearest animal within range of a point, or null.
func near(p: Vector3, radius: float) -> Animal:
	for a in animals:
		if a.pos.distance_squared_to(p) < radius * radius:
			return a
	return null
