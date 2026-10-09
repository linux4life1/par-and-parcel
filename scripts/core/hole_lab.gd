class_name HoleLab
extends RefCounted
## Works out what kind of test each hole is by playing it. Test golfers who
## have, or lack, each of the three skills (length, accuracy, imagination)
## play the hole many times with the real physics. The gap in their average
## scores is how much the hole rewards that skill. A little work is done on
## each tick so the game never stalls.

signal rated(hole: Hole)

## [label, power skill, accuracy, imagination, runs]
const CLASSES := [
	["all", 0.82, 0.82, 0.82, 8],
	["no_length", 0.22, 0.82, 0.82, 8],
	["no_accuracy", 0.82, 0.22, 0.82, 8],
	["no_imagination", 0.82, 0.82, 0.12, 8],
	["beginner", 0.15, 0.15, 0.15, 5],
	["average", 0.42, 0.42, 0.42, 5],
]
const TYPES := {
	0: ["Breather", "A gentle hole that lets everyone recover."],
	1: ["Freeway", "Rewards the long hitter."],
	2: ["Precise", "Rewards accuracy."],
	4: ["Creative", "Rewards imagination: shaping shots, reading wind and slopes."],
	3: ["Challenge", "Demands both length and accuracy."],
	5: ["Heroic", "Demands length and imagination."],
	6: ["Strategic", "Demands accuracy and imagination."],
	7: ["Classic", "Tests every part of a golfer's game."],
}
const THRESHOLD := 0.55      # strokes of gap for a skill to count

var sim: Sim
var queue: Array[Hole] = []
var _job := {}
var _check_t := 0.0
var _checked_rev := -1
var _tick := 0


func _init(s: Sim) -> void:
	sim = s


static func type_name(code: int) -> String:
	return str(TYPES.get(code, TYPES[0])[0])


static func type_blurb(code: int) -> String:
	return str(TYPES.get(code, TYPES[0])[1])


## A cheap fingerprint of the ground a hole is played over. The day's cup
## is left out: moving it is not a new hole, so the test golfers are not
## sent round again.
func _signature(hole: Hole) -> int:
	var c := sim.course
	var end := hole.design_pin()
	var a := c.tile_of(hole.tee.x, hole.tee.z)
	var b := c.tile_of(end.x, end.z)
	var x0 := clampi(mini(a.x, b.x) - 9, 0, c.w - 1)
	var x1 := clampi(maxi(a.x, b.x) + 9, 0, c.w - 1)
	var y0 := clampi(mini(a.y, b.y) - 9, 0, c.h - 1)
	var y1 := clampi(maxi(a.y, b.y) + 9, 0, c.h - 1)
	var sig := int(hole.tee.x * 7.0 + end.z * 13.0)
	for y in range(y0, y1 + 1):
		var row := y * c.w
		for x in range(x0, x1 + 1):
			var i := row + x
			sig = (sig * 31 + c.terrain[i] * 7 + c.objects[i] * 3 + int(c.heights[i + y] * 4.0)) & 0x3fffffff
	return sig


## Called every simulation step. Now and then it checks for holes whose
## ground has changed, and every few steps it plays one test shot.
func step(dt: float) -> void:
	_tick += 1
	if _tick % 6 != 0:
		return
	dt *= 6.0
	_check_t -= dt
	if _check_t <= 0.0 and _checked_rev != sim.course.revision and not sim.eruption.active():
		_check_t = 4.0
		_checked_rev = sim.course.revision
		for hole in sim.course.holes:
			var sig := _signature(hole)
			if sig != hole.lab_sig:
				hole.lab_sig = sig
				hole.lab_ready = false
				if not queue.has(hole):
					queue.append(hole)
	if _job.is_empty():
		while not queue.is_empty() and not sim.course.holes.has(queue[0]):
			queue.pop_front()
		if queue.is_empty():
			return
		_begin(queue.pop_front())
	_shot()


## Rate one hole right now, without spreading the work out. For tests.
func rate_now(hole: Hole) -> void:
	hole.lab_sig = _signature(hole)
	_begin(hole)
	var guard := 0
	while not _job.is_empty() and guard < 5000:
		_shot()
		guard += 1


func _begin(hole: Hole) -> void:
	hole.spots = PackedVector2Array()
	_job = {"hole": hole, "class": 0, "run": 0, "sums": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "g": null}
	_new_run()


func _test_golfer(c: Array) -> Golfer:
	var g := Golfer.new()
	g.kind = "lab"
	g.skill = (float(c[1]) + float(c[2]) + float(c[3])) / 3.0
	g.power = Members.power_at(float(c[1]), sim.members.progress)
	g.accuracy = float(c[2])
	g.imagination = float(c[3])
	g.putting = 0.55
	for cat: Dictionary in sim.db.categories:
		g.brands[cat.id] = sim.db.brands[0]
	g.ball.set_def(sim.db.balls[0])
	g.ball.lava = sim.is_lava()
	return g


func _new_run() -> void:
	var hole: Hole = _job.hole
	var g := _test_golfer(CLASSES[int(_job["class"])])
	g.begin_hole()
	g.ball.place(sim.course.on_ground(hole.tee.x, hole.tee.z))
	_job.g = g


## Play one shot of the current test round, then tidy up if that ends it.
func _shot() -> void:
	var hole: Hole = _job.hole
	if not sim.course.holes.has(hole):
		_job = {}
		return
	var g: Golfer = _job.g
	var tee_shot := int(_job["class"]) == 0 and g.strokes == 0
	play_shot(sim, g, hole)
	if tee_shot:
		hole.spots.append(Vector2(g.ball.pos.x, g.ball.pos.z))
	if g.done:
		var ci := int(_job["class"])
		var sums: Array = _job.sums
		sums[ci] = float(sums[ci]) + (hole.par + 5 if g.picked_up else g.strokes)
		_job.run = int(_job.run) + 1
		if int(_job.run) >= int(CLASSES[ci][4]):
			_job.run = 0
			_job["class"] = ci + 1
			if ci + 1 >= CLASSES.size():
				_finish()
				return
		_new_run()


## One planned, struck and fully resolved shot, with no walking and no wind.
static func play_shot(sim: Sim, g: Golfer, hole: Hole) -> void:
	ShotAI.calm = true
	g.plan = ShotAI.plan(sim, g, hole)
	ShotAI.strike(sim, g)
	ShotAI.calm = false
	var b := g.ball
	var n := 0
	while b.moving() and n < 2400:
		b.step(1.0 / 60.0, sim.course, Vector3.ZERO, hole.design_pin(), true)
		n += 1
	match b.state:
		Ball.S.HOLED:
			g.done = true
		Ball.S.WATER:
			g.strokes += 1
			b.place(Group.drop_spot(sim.course, b))
		Ball.S.OOB:
			g.strokes += 1
			b.place(b.start)
		_:
			if b.moving():
				b.place(sim.course.on_ground(b.pos.x, b.pos.z))
	if not g.done and g.strokes >= hole.par + 5:
		g.done = true
		g.picked_up = true


## Play a whole hole at once and return the score. Used for match opponents.
static func play_hole(sim: Sim, g: Golfer, hole: Hole) -> int:
	g.begin_hole()
	g.ball.place(sim.course.on_ground(hole.tee.x, hole.tee.z))
	var guard := 0
	while not g.done and guard < 40:
		play_shot(sim, g, hole)
		guard += 1
	return hole.par + 5 if g.picked_up else g.strokes


func _finish() -> void:
	var hole: Hole = _job.hole
	var sums: Array = _job.sums
	var avg: Array[float] = []
	for i in CLASSES.size():
		avg.append(float(sums[i]) / float(CLASSES[i][4]))
	hole.test_length = maxf(0.0, avg[1] - avg[0])
	hole.test_accuracy = maxf(0.0, avg[2] - avg[0])
	hole.test_imagination = maxf(0.0, avg[3] - avg[0])
	hole.expect = {"expert": avg[0], "beginner": avg[4], "average": avg[5]}
	var code := 0
	if hole.test_length >= THRESHOLD:
		code |= 1
	if hole.test_accuracy >= THRESHOLD:
		code |= 2
	if hole.test_imagination >= THRESHOLD:
		code |= 4
	hole.kind = code
	hole.lab_ready = true
	_job = {}
	rated.emit(hole)


## Hit the Test button's balls from the back tee and mark each one. This is
## not a rating: the hole's type, expected scores and expert spots stay as
## they were. The same ground, via the lab signature, always draws the same
## marks. The game's own random numbers are put back afterwards.
func test_shots(hole: Hole) -> void:
	if not sim.course.holes.has(hole):
		return
	var book: Dictionary = sim.db.test_hole
	var balls: int = int(book.get("balls", 0))
	var labels: Array = book.get("classes", [])
	var saved_seed := sim.rng.seed
	var saved_state := sim.rng.state
	var sig := _signature(hole)
	var seed_n := sig
	if seed_n == 0:
		seed_n = 1
	sim.rng.seed = seed_n
	var marks: Array[Dictionary] = []
	var n_cls := labels.size()
	if n_cls > 0 and balls > 0:
		var base: int = int(balls / n_cls)
		var extra: int = balls % n_cls
		for ci in n_cls:
			var count := base
			if ci < extra:
				count += 1
			var row := _class_named(str(labels[ci]))
			var label := str(labels[ci])
			for shot_i in count:
				var shot := _one_test_shot(hole, row)
				shot["class"] = label
				shot["sig"] = sig
				marks.append(shot)
	sim.rng.seed = saved_seed
	sim.rng.state = saved_state
	hole.test_marks = marks
	sim.course.holes_changed.emit()


## The Dismiss button. The marks go, and the picture is told.
func clear_test(hole: Hole) -> void:
	hole.test_marks.clear()
	sim.course.holes_changed.emit()


## Marks belong to the ground they were hit on. A new signature, from paint,
## sculpt or an object, drops them. One rule covers all three.
func drop_stale_marks() -> void:
	var dropped := false
	for hole in sim.course.holes:
		if hole.test_marks.is_empty():
			continue
		var live := _signature(hole)
		var stale := false
		for mark in hole.test_marks:
			if int(mark.get("sig", -1)) != live:
				stale = true
				break
		if stale:
			hole.test_marks.clear()
			dropped = true
	if dropped:
		sim.course.holes_changed.emit()


func _class_named(label: String) -> Array:
	for row in CLASSES:
		var item: Array = row
		if str(item[0]) == label:
			return item
	var first: Array = CLASSES[0]
	return first


## One tee shot, recorded where it first landed and where it stopped, before
## any drop or a return to the tee. Water and out of bounds keep the point
## where the ball went in or crossed.
func _one_test_shot(hole: Hole, row: Array) -> Dictionary:
	var g := _test_golfer(row)
	g.begin_hole()
	g.ball.place(sim.course.on_ground(hole.tee.x, hole.tee.z))
	ShotAI.calm = true
	g.plan = ShotAI.plan(sim, g, hole)
	ShotAI.strike(sim, g)
	ShotAI.calm = false
	var b := g.ball
	b.air_seed = -1.0
	var n := 0
	while b.moving() and n < 2400:
		b.step(1.0 / 60.0, sim.course, Vector3.ZERO, hole.design_pin(), true)
		n += 1
	return {
		"land": Vector2(b.carry.x, b.carry.z),
		"rest": Vector2(b.pos.x, b.pos.z),
		"outcome": test_outcome(b, sim.course),
	}


## What the ball finished in. A clip through a tree that stops on the
## fairway is fairway. Ground the card has no name for is called rough, so
## the summary still has a word, and it is not trouble unless listed.
## Shared with the trouble share, so the two never disagree.
static func test_outcome(b: Ball, course: Course) -> String:
	if b.state == Ball.S.WATER:
		return "water"
	if b.state == Ball.S.OOB:
		return "oob"
	var ti := course.index_at(b.pos.x, b.pos.z)
	if ti < 0 or course.locked[ti] != 0:
		return "oob"
	if Defs.is_tree(int(course.objects[ti])) or b.tree_tile == ti:
		return "trees"
	if b.state == Ball.S.HOLED or Defs.is_green(int(course.terrain[ti])):
		return "green"
	var ground: int = int(course.terrain[ti])
	if Defs.is_fairway(ground):
		return "fairway"
	if ground == Defs.T.ROUGH:
		return "rough"
	if ground == Defs.T.DEEP_ROUGH:
		return "deep_rough"
	if ground == Defs.T.BUNKER:
		return "bunker"
	if ground == Defs.T.WASTE:
		return "waste"
	return "rough"


## The hole card's line. Counts follow a fixed order and skip zeroes.
## Trouble is how many balls finished in the data's trouble list.
static func test_summary(hole: Hole, book: Dictionary) -> String:
	if hole.test_marks.is_empty():
		return ""
	var order: Array[String] = ["fairway", "green", "rough", "deep_rough", "bunker", "waste", "water", "oob", "trees"]
	var counts := {}
	var trouble_n := 0
	var trouble: Array = book.get("trouble", [])
	for mark in hole.test_marks:
		var outcome := str(mark.get("outcome", ""))
		counts[outcome] = int(counts.get(outcome, 0)) + 1
		if trouble.has(outcome):
			trouble_n += 1
	var parts: PackedStringArray = PackedStringArray()
	for name in order:
		var c: int = int(counts.get(name, 0))
		if c > 0:
			parts.append("%d %s" % [c, name.replace("_", " ")])
	return "%d test balls: %s. %d found trouble." % [hole.test_marks.size(), ", ".join(parts), trouble_n]
