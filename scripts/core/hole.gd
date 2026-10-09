class_name Hole
extends RefCounted
## One golf hole: a tee, a pin, the line of play between them, and a routing
## field the golfer AI steers by.

var tee := Vector3.ZERO
## Middle and forward tees. `tee` is the back tee the hole was laid out on,
## and par and length stay measured from it. A zero x/z means that set was
## never placed.
var tee_middle := Vector3.ZERO
var tee_forward := Vector3.ZERO
var length_middle := 0.0
var length_forward := 0.0
var pin := Vector3.ZERO
## Where the pin was placed. Par and length are measured to here, so the
## day's cup can move along the green without rewriting the card.
var placed := Vector3.ZERO
## 0 middle, 1 front, 2 back. The names live in data/pins.json.
var pin_spot := 0
## The owner asked the greenkeepers to leave this cup where it is.
var pin_locked := false
## The morning's spot, waiting because a group is still playing the hole.
## -1 when nothing is waiting.
var pin_due := -1
var par := 4
var length := 0.0
## Centreline of the hole the way it is meant to be played, tee to pin, in
## world x/z. Par and yardage are the length of this line, not the chord.
## Named route because `line` is the queue of parties waiting on the tee.
var route := PackedVector2Array()
## Stakes on the line of play, where the player says a dogleg changes
## direction. Ordered from the tee. Par and length do not use them.
var turns: Array[Vector3] = []
## False while the hole is a draft. Paying golfers skip it until it is opened.
## Generated holes and old saves stay open.
var open := true
## Where the expert test golfers' tee shots came to rest, the last time the
## hole was rated. The picture uses the Test marks instead of these.
var spots := PackedVector2Array()
## The Test button's balls: where each first landed, where it stopped, what
## it finished in, which class hit it, and the hole's signature at the time.
## Not saved. Cleared when that signature changes, or when the marks are dismissed.
var test_marks: Array[Dictionary] = []
## Fingerprint of the ground the line was measured on. -1 until then.
var line_sig := -1
var earned := 0.0               # green fees golfers have paid for this hole
var payers := 0                 # how many times a golfer has finished it and been asked
var plays := 0
## Real shots that have come to rest on this hole, and how many of them
## finished in trouble. The share is trouble over shots. Both zero means
## there is no share yet, which is also how an older save loads.
var shots_n := 0
var trouble_n := 0
var strokes_total := 0
var best := 0
var tally := {}                 # score against par -> how many times: "-2", "-1", "0", "1", "2", "3" (3 is three over or worse)
var aces := 0
var fun := 60.0                 # running golfer opinion of this hole, 0..100
var name := ""
var comments := {}              # mood tag -> summed effect on golfers here
var award := ""                 # "", "top100" or "top18"
## Themed awards this hole holds ("par3", "water", "night"). One hole
## per theme. Taken back when the hole no longer deserves it.
var themes: Array[String] = []
## Seconds the starter holds the next party after the one ahead begins.
## Zero sends them out as soon as the tee is free.
var gap := 0.0
## When the party now playing began the hole. Far in the past until then,
## so the first party is never held.
var tee_at := -1.0e9
# What the hole tests, measured by HoleLab in strokes of advantage.
var lab_ready := false
var lab_sig := -1
var test_length := 0.0
var test_accuracy := 0.0
var test_imagination := 0.0
var kind := 0                   # bit 1 length, 2 accuracy, 4 imagination
var expect := {}                # expected score for a beginner, average, expert
var teeing_group: Group = null  # the group holding the tee box
## Recent parties' time on this hole, in sim seconds, newest last. The
## scorecard shows the average on the course clock.
var play_times: Array[float] = []
const PACE_KEEP := 12
var _lit := 0.0
var _lit_rev := -1
var _lit_stamp := 0
## A hole needs this much of its length lit to be played after dark.
const LIT_ENOUGH := 0.7
## Par 3 up to this, par 4 up to the next, par 5 after that. Metres.
const PAR_3 := 225.0
const PAR_4 := 430.0
## A route longer than this times the straight line is a detour, not the hole.
const ROUTE_CAP := 1.6
## Step cost for choosing the line of play. Fairway, tee and green are cheap.
## Everything else is dearer, never infinite, so a carry still connects.
const PLAY_COST: Array[float] = [3.0, 1.0, 1.0, 1.0, 4.0, 8.0, 5.0, 2.0, 6.0, 4.0, 1.0, 1.0, 3.5, 8.0]
const PLAY_TREE := 6.0
var groups: Array[Group] = []   # every group currently playing the hole
## Parties waiting to tee off, in the order they arrived. The front of the
## line is the next party up; the party on the tee is teeing_group, not here.
var line: Array[Group] = []


## Where this party stands in the line for the tee (0 is next up). A party
## not yet in the line joins the back of it; parties that have moved on, or
## gone home, are dropped on the way.
func line_index(gr: Group, hole_i: int) -> int:
	var k := line.size() - 1
	while k >= 0:
		var o := line[k]
		if o.state >= Group.S.PLAY or o.hole_i != hole_i or o.members.is_empty() or o == teeing_group:
			line.remove_at(k)
		k -= 1
	var at := line.find(gr)
	if at < 0:
		line.append(gr)
		at = line.size() - 1
	return at

# Routing field: "effective metres to the pin" for tiles in a box around the hole.
var _field := PackedFloat32Array()
var _fx := 0
var _fy := 0
var _fw := 0
var _fh := 0
var _field_rev := -1
var _field_time := -1000.0
var _field_cup := Vector2(-1.0e8, -1.0e8)
# scratch heap
var _hk := PackedFloat32Array()
var _hv := PackedInt32Array()
var _hn := 0
var _pop_key := 0.0
## True when the line of play reached the pin and is not a detour. The
## preview reads this. It is not stored: the route is measured again on load.
var playable := true


## The pin the hole was designed around. The day's cup is `pin`.
func design_pin() -> Vector3:
	if placed.length_squared() > 0.01:
		return placed
	return pin


## Where the ball is holed and the flag stands: the day's cup. A group
## already on the hole keeps the cup it teed off to, because that cup is
## not moved until the group has holed out. Par and length stay on the
## placed pin.
func aim_at() -> Vector3:
	return pin


func straight_length() -> float:
	var end := design_pin()
	return Vector2(end.x - tee.x, end.z - tee.z).length()


static func par_for(metres: float) -> int:
	if metres <= PAR_3:
		return 3
	if metres <= PAR_4:
		return 4
	return 5


## Par and yardage from the cheapest playable route, then smoothed so a
## staircase of tiles does not add length. Safe to call again: the scorecard
## is shifted only when par actually changes.
##
## Scores already recorded stay what they were against the new par (a 3 that
## was even on a wrongly short par 3 becomes a birdie once the hole is a par
## 4). The -2 and +3 tally buckets already mean "or better" and "or worse",
## so a shift can only pile more scores into those ends. Best and aces are
## stroke counts and are left alone. Medals already given are not taken back.
## Old saves stored no par; the straight-line par is assumed, which is what
## those rounds were scored against, and the same shift is applied on load.
func update_metrics(course: Course) -> void:
	var before := par
	var found: Dictionary = _route(course)
	var line: PackedVector2Array = found.line
	route = line
	var straight := straight_length()
	var walked := _polyline_length(route)
	if walked < straight:
		walked = straight
	# A route longer than ROUTE_CAP times the straight line is a detour, not
	# the hole. The length is capped, and the preview treats that as unplayable.
	playable = bool(found.reached)
	if straight > 1.0 and walked > straight * ROUTE_CAP:
		playable = false
		walked = straight * ROUTE_CAP
	length = walked
	var now := par_for(length)
	if now != before and plays > 0:
		_shift_tally(before, now)
	par = now
	if has_tee("middle"):
		length_middle = _remaining(tee_middle)
	if has_tee("forward"):
		length_forward = _remaining(tee_forward)
	var limit := turn_on_line()
	var stake_i := turns.size() - 1
	while stake_i >= 0:
		var stake := turns[stake_i]
		var stake_snap := route_snap(Vector2(stake.x, stake.z))
		if float(stake_snap["off"]) > limit:
			turns.remove_at(stake_i)
		stake_i -= 1
	_sort_turns()


## What a hole from tee to pin would be called, without touching this one.
static func measure(course: Course, tee_at: Vector3, pin_at: Vector3) -> Dictionary:
	var hole := Hole.new()
	hole.tee = tee_at
	hole.pin = pin_at
	hole.update_metrics(course)
	return {"par": hole.par, "length": hole.length, "line": hole.route, "playable": hole.playable}


func _shift_tally(from_par: int, to_par: int) -> void:
	var shift := from_par - to_par
	if shift == 0 or tally.is_empty():
		return
	var next: Dictionary = {}
	for k: String in tally:
		var bucket := clampi(int(k) + shift, -2, 3)
		var nk := str(bucket)
		next[nk] = int(next.get(nk, 0)) + int(tally[k])
	tally = next


func _polyline_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## Cheapest 8-connected tile path from tee to pin, then pulled tight wherever
## the straight segment stays on fairway, tee, green or cart path with no trees.
## `reached` is false only when the pin is off the map. Every on-map tile
## has a finite step cost, so a pin on the map is always reached, water
## ring or not.
func _route(course: Course) -> Dictionary:
	var end := design_pin()
	var a := Vector2(tee.x, tee.z)
	var b := Vector2(end.x, end.z)
	var chord := PackedVector2Array([a, b])
	if a.distance_to(b) < 1.0 or _segment_clear(course, a, b):
		return {"line": chord, "reached": true}
	var margin := 18
	var tt := course.tile_of(tee.x, tee.z)
	var pt := course.tile_of(end.x, end.z)
	if not course.in_bounds(tt.x, tt.y) or not course.in_bounds(pt.x, pt.y):
		return {"line": chord, "reached": false}
	var fx := clampi(mini(tt.x, pt.x) - margin, 0, course.w - 1)
	var fy := clampi(mini(tt.y, pt.y) - margin, 0, course.h - 1)
	var x1 := clampi(maxi(tt.x, pt.x) + margin, 0, course.w - 1)
	var y1 := clampi(maxi(tt.y, pt.y) + margin, 0, course.h - 1)
	var fw := x1 - fx + 1
	var fh := y1 - fy + 1
	var n := fw * fh
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	_hn = 0
	if _hk.size() < 256:
		_hk.resize(256)
		_hv.resize(256)
	var sx := clampi(tt.x - fx, 0, fw - 1)
	var sy := clampi(tt.y - fy, 0, fh - 1)
	var start := sy * fw + sx
	var gx := clampi(pt.x - fx, 0, fw - 1)
	var gy := clampi(pt.y - fy, 0, fh - 1)
	var goal := gy * fw + gx
	dist[start] = 0.0
	_heap_push(0.0, start)
	while _hn > 0:
		var cur := _heap_pop()
		var dcur := _pop_key
		if dcur > dist[cur]:
			continue
		if cur == goal:
			break
		var cx := cur % fw
		var cy := int(cur / fw)
		for oy in range(-1, 2):
			var ny := cy + oy
			if ny < 0 or ny >= fh:
				continue
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var nx := cx + ox
				if nx < 0 or nx >= fw:
					continue
				var ni := ny * fw + nx
				var step := _play_cost(course, fx + nx, fy + ny)
				if ox != 0 and oy != 0:
					step *= 1.41421356
				var nd := dcur + step
				if nd < dist[ni]:
					dist[ni] = nd
					parent[ni] = cur
					_heap_push(nd, ni)
	if dist[goal] == INF:
		return {"line": chord, "reached": false}
	var chain: Array[int] = []
	var guard := 0
	var walk := goal
	while walk >= 0 and guard < n + 2:
		chain.append(walk)
		if walk == start:
			break
		walk = parent[walk]
		guard += 1
	if chain.is_empty() or chain[chain.size() - 1] != start:
		return {"line": chord, "reached": false}
	chain.reverse()
	var pts := PackedVector2Array()
	pts.append(a)
	for k in range(1, chain.size() - 1):
		var idx: int = chain[k]
		var tx := fx + (idx % fw)
		var ty := fy + int(idx / fw)
		var center := course.tile_center(tx, ty)
		pts.append(Vector2(center.x, center.z))
	pts.append(b)
	return {"line": _smooth(course, pts), "reached": true}


func _play_cost(course: Course, tx: int, ty: int) -> float:
	if not course.in_bounds(tx, ty):
		return 30.0
	var i := ty * course.w + tx
	var c: float = PLAY_COST[course.terrain[i]]
	if Defs.is_tree(course.objects[i]):
		c += PLAY_TREE
	if course.locked[i] != 0:
		c += 10.0
	return c


## True when the whole segment stays on the short grass (or a path) and out of the trees.
func _segment_clear(course: Course, a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := maxi(1, int(d / 1.25))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		var i := course.index_at(p.x, p.y)
		if i < 0:
			return false
		var t: int = course.terrain[i]
		if not Defs.is_short(t) and t != Defs.T.PATH:
			return false
		if Defs.is_tree(course.objects[i]):
			return false
	return true


func _smooth(course: Course, pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.is_empty():
		return out
	var i := 0
	out.append(pts[0])
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _segment_clear(course, pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out


## A point on the line of play. t is 0 at the tee and 1 at the pin.
## Pass the course to stand the point on the ground there.
func point_along(t: float, course: Course = null) -> Vector3:
	var p := _point_flat(t)
	var y := lerpf(tee.y, pin.y, clampf(t, 0.0, 1.0))
	if course != null:
		y = course.height_at(p.x, p.y)
	return Vector3(p.x, y, p.y)


## Unit direction of the line of play at t, in world x/z.
func direction_at(t: float) -> Vector2:
	var pa := _point_flat(maxf(t - 0.03, 0.0))
	var pb := _point_flat(minf(t + 0.03, 1.0))
	var d := pb - pa
	if d.length_squared() < 0.01:
		var end := design_pin()
		d = Vector2(end.x - tee.x, end.z - tee.z)
	if d.length_squared() < 0.01:
		return Vector2(1.0, 0.0)
	return d.normalized()


func _point_flat(t: float) -> Vector2:
	var pts := route
	if pts.size() < 2:
		var end := design_pin()
		return Vector2(tee.x, tee.z).lerp(Vector2(end.x, end.z), clampf(t, 0.0, 1.0))
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	if total < 0.01:
		return pts[0]
	var want := clampf(t, 0.0, 1.0) * total
	var walked := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if walked + seg >= want - 0.0001 or i == pts.size() - 1:
			var u := 0.0 if seg < 0.0001 else (want - walked) / seg
			return pts[i - 1].lerp(pts[i], clampf(u, 0.0, 1.0))
		walked += seg
	return pts[pts.size() - 1]


func _line_stamp() -> int:
	var s := route.size()
	if s == 0:
		return 0
	var mid := route[s / 2]
	return s * 17 + int(mid.x * 2.0) + int(mid.y * 8.0) + int(length)


func snap_to_ground(course: Course) -> void:
	tee.y = course.height_at(tee.x, tee.z)
	pin.y = course.height_at(pin.x, pin.z)
	if placed.length_squared() > 0.01:
		placed.y = course.height_at(placed.x, placed.z)
	if has_tee("middle"):
		tee_middle.y = course.height_at(tee_middle.x, tee_middle.z)
	if has_tee("forward"):
		tee_forward.y = course.height_at(tee_forward.x, tee_forward.z)


func average_score() -> float:
	return 0.0 if plays == 0 else float(strokes_total) / plays


## Count one finished score for the scorecard.
func record(score: int) -> void:
	plays += 1
	strokes_total += score
	if best == 0 or score < best:
		best = score
	if score == 1:
		aces += 1
	var key := str(clampi(score - par, -2, 3))
	tally[key] = int(tally.get(key, 0)) + 1


## Share of scores that were birdies or better, and bogeys or worse.
func share(keys: Array[String]) -> float:
	if plays == 0:
		return 0.0
	var n := 0
	for k in keys:
		n += int(tally.get(k, 0))
	return float(n) / plays


## Effective distance to the pin from a world position.
func field_at(course: Course, x: float, z: float, now: float = 0.0) -> float:
	var cup := Vector2(aim_at().x, aim_at().z)
	var cup_moved := cup.distance_squared_to(_field_cup) > 0.01
	if cup_moved or (_field_rev != course.revision and (_field_rev < 0 or now - _field_time > 4.0)):
		_compute_field(course)
		_field_time = now
	var tx := int(floor(x / Defs.TILE)) - _fx
	var ty := int(floor(z / Defs.TILE)) - _fy
	if tx < 0 or ty < 0 or tx >= _fw or ty >= _fh:
		var aim := aim_at()
		return Vector2(aim.x - x, aim.z - z).length() * 1.35 + 20.0
	return _field[ty * _fw + tx]


func _compute_field(course: Course) -> void:
	_field_rev = course.revision
	var margin := 14
	var aim := aim_at()
	_field_cup = Vector2(aim.x, aim.z)
	var tt := course.tile_of(tee.x, tee.z)
	var pt := course.tile_of(aim.x, aim.z)
	_fx = clampi(mini(tt.x, pt.x) - margin, 0, course.w - 1)
	_fy = clampi(mini(tt.y, pt.y) - margin, 0, course.h - 1)
	var x1 := clampi(maxi(tt.x, pt.x) + margin, 0, course.w - 1)
	var y1 := clampi(maxi(tt.y, pt.y) + margin, 0, course.h - 1)
	_fw = x1 - _fx + 1
	_fh = y1 - _fy + 1
	var n := _fw * _fh
	_field.resize(n)
	_field.fill(INF)
	# per-tile step cost
	var cost := PackedFloat32Array()
	cost.resize(n)
	for y in _fh:
		var row := (y + _fy) * course.w + _fx
		for x in _fw:
			var c: float = Defs.T_ROUTE[course.terrain[row + x]]
			if Defs.is_tree(course.objects[row + x]):
				c += 0.8
			cost[y * _fw + x] = c * Defs.TILE
	_hn = 0
	if _hk.size() < 256:
		_hk.resize(256)
		_hv.resize(256)
	var sx := clampi(pt.x - _fx, 0, _fw - 1)
	var sy := clampi(pt.y - _fy, 0, _fh - 1)
	var start := sy * _fw + sx
	_field[start] = 0.0
	_heap_push(0.0, start)
	while _hn > 0:
		var cur := _heap_pop()
		var dcur := _pop_key
		if dcur > _field[cur]:
			continue
		var cx := cur % _fw
		var cy := cur / _fw
		for oy in range(-1, 2):
			var ny := cy + oy
			if ny < 0 or ny >= _fh:
				continue
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var nx := cx + ox
				if nx < 0 or nx >= _fw:
					continue
				var ni := ny * _fw + nx
				var step := cost[ni] * (1.41421 if (ox != 0 and oy != 0) else 1.0)
				var nd := dcur + step
				if nd < _field[ni]:
					_field[ni] = nd
					_heap_push(nd, ni)


func _heap_push(k: float, v: int) -> void:
	var i := _hn
	_hn += 1
	if _hn > _hk.size():
		_hk.resize(_hn * 2)
		_hv.resize(_hn * 2)
	while i > 0:
		var p := (i - 1) >> 1
		if _hk[p] <= k:
			break
		_hk[i] = _hk[p]
		_hv[i] = _hv[p]
		i = p
	_hk[i] = k
	_hv[i] = v


func _heap_pop() -> int:
	var top := _hv[0]
	_pop_key = _hk[0]
	_hn -= 1
	if _hn > 0:
		var k := _hk[_hn]
		var v := _hv[_hn]
		var i := 0
		while true:
			var c := i * 2 + 1
			if c >= _hn:
				break
			if c + 1 < _hn and _hk[c + 1] < _hk[c]:
				c += 1
			if _hk[c] >= k:
				break
			_hk[i] = _hk[c]
			_hv[i] = _hv[c]
			i = c
		_hk[i] = k
		_hv[i] = v
	return top


## The share of the way from tee to green that is lit after dark.
func lit_share(course: Course) -> float:
	var stamp := _line_stamp()
	if _lit_rev == course.lights_rev and stamp == _lit_stamp:
		return _lit
	_lit_rev = course.lights_rev
	_lit_stamp = stamp
	var n := maxi(6, int(length / 12.0))
	var lit := 0
	for k in n + 1:
		var p := point_along(float(k) / n)
		if course.light_at(p.x, p.z) >= 0.45:
			lit += 1
	_lit = float(lit) / (n + 1)
	return _lit


## Lit well enough for golfers to play it at night.
func lit_enough(course: Course) -> bool:
	return lit_share(course) >= LIT_ENOUGH


## What a golfer pays for this hole on average. Zero until someone has.
func average_paid() -> float:
	return earned / payers if payers > 0 else 0.0


## Remember how long one party took, and forget the oldest once the window fills.
func note_time(seconds: float) -> void:
	if seconds <= 0.0:
		return
	play_times.append(seconds)
	while play_times.size() > PACE_KEEP:
		play_times.pop_front()


## Sim seconds a party has been taking lately. Zero until someone has finished.
func average_time() -> float:
	if play_times.is_empty():
		return 0.0
	var s := 0.0
	for t in play_times:
		s += t
	return s / float(play_times.size())


## True while the starter is still holding the next party. The gap is
## measured from when the party ahead began the hole.
func starter_holds(now: float) -> bool:
	return gap > 0.0 and now < tee_at + gap


## Water sits beside the line of play, close enough to be the hole's hazard.
## The tee itself is not tested: a pond behind the box is not in play.
func touches_water(course: Course) -> bool:
	var n := maxi(6, int(length / 10.0))
	for k in range(1, n + 1):
		var p := point_along(float(k) / float(n))
		if course.water_near(p.x, p.z, 14.0):
			return true
	var end := design_pin()
	return course.water_near(end.x, end.z, 14.0)


## Closest point of the line of play. `along` is metres from the tee,
## `off` is metres away from the line, `point` is on the line.
func route_snap(at: Vector2) -> Dictionary:
	var pts := route
	if pts.size() < 2:
		var end := design_pin()
		pts = PackedVector2Array([Vector2(tee.x, tee.z), Vector2(end.x, end.z)])
	var best_off := 1000000.0
	var best_along := 0.0
	var best_pt := pts[0]
	var walked := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := b - a
		var span := seg.length()
		var u := 0.0
		if span > 0.0001:
			u = clampf((at - a).dot(seg) / (span * span), 0.0, 1.0)
		var p := a.lerp(b, u)
		var off := at.distance_to(p)
		if off < best_off:
			best_off = off
			best_along = walked + span * u
			best_pt = p
		walked += span
	return {"along": best_along, "off": best_off, "point": best_pt}


## Metres of each stretch from the tee, through each stake, to the pin.
## They add up to the hole's length.
func turn_lengths() -> PackedFloat32Array:
	var cuts: Array[float] = []
	for m in turns:
		var snap := route_snap(Vector2(m.x, m.z))
		cuts.append(clampf(float(snap["along"]), 0.0, length))
	cuts.sort()
	var parts := PackedFloat32Array()
	var prev := 0.0
	for c in cuts:
		var step := c - prev
		if step < 0.0:
			step = 0.0
		parts.append(step)
		prev = c
	var tail := length - prev
	if tail < 0.0:
		tail = 0.0
	parts.append(tail)
	return parts


## Printed yards of each stretch. Rounding is of the running total, so the
## numbers add up to the hole's length in yards.
func turn_yards() -> PackedInt32Array:
	var cuts: Array[float] = []
	for mark in turns:
		var snap := route_snap(Vector2(mark.x, mark.z))
		cuts.append(clampf(float(snap["along"]), 0.0, length))
	cuts.sort()
	var shown := PackedInt32Array()
	var prev_y := 0
	for cut in cuts:
		var at_y := Defs.yards(cut)
		var step := at_y - prev_y
		if step < 0:
			step = 0
		shown.append(step)
		prev_y = at_y
	var tail := Defs.yards(length) - prev_y
	if tail < 0:
		tail = 0
	shown.append(tail)
	return shown


## Yardage between the tee, the stakes and the pin, for the hole card.
func turn_line() -> String:
	if turns.is_empty():
		return ""
	var bits: PackedStringArray = []
	for yard in turn_yards():
		bits.append("%d yd" % yard)
	return "  ·  ".join(bits)


func has_turn(at: Vector3) -> bool:
	for m in turns:
		if Vector2(m.x - at.x, m.z - at.z).length_squared() < 0.05:
			return true
	return false


func add_turn(at: Vector3) -> void:
	turns.append(at)
	_sort_turns()


func remove_turn(at: Vector3) -> bool:
	for i in turns.size():
		var m := turns[i]
		if Vector2(m.x - at.x, m.z - at.z).length_squared() < 0.05:
			turns.remove_at(i)
			return true
	return false


func _sort_turns() -> void:
	for i in range(1, turns.size()):
		var key := turns[i]
		var key_snap := route_snap(Vector2(key.x, key.z))
		var along := float(key_snap["along"])
		var j := i - 1
		while j >= 0:
			var other := route_snap(Vector2(turns[j].x, turns[j].z))
			if float(other["along"]) <= along:
				break
			turns[j + 1] = turns[j]
			j -= 1
		turns[j + 1] = key


## Empty when this spot may take a stake. Otherwise the reason it may not.
func refuse_turn(at: Vector3, on_line: float, gap: float, cap: int) -> String:
	if turns.size() >= cap:
		return "This hole has all the turning points it can take."
	var snap := route_snap(Vector2(at.x, at.z))
	if float(snap["off"]) > on_line:
		return "Put it on the line of play."
	var along := float(snap["along"])
	if along < gap or length - along < gap:
		return "Put it between the tee and the green."
	for m in turns:
		var other := route_snap(Vector2(m.x, m.z))
		if absf(float(other["along"]) - along) < gap:
			return "That turn is already marked."
	return ""


## True when that set has been placed. The back tee always has.
func has_tee(which: String) -> bool:
	if which == "back":
		return true
	var p := tee_pos(which)
	return Vector2(p.x, p.z).length_squared() > 0.25


func tee_pos(which: String) -> Vector3:
	if which == "middle":
		return tee_middle
	if which == "forward":
		return tee_forward
	return tee


## Metres from this set to the pin, along the line the par is measured on.
func metres_of(which: String) -> float:
	if which == "middle":
		return length_middle
	if which == "forward":
		return length_forward
	return length


## The same length, from a world position that is one of the tees.
func metres_at(at: Vector3) -> float:
	if has_tee("forward") and Vector2(at.x - tee_forward.x, at.z - tee_forward.z).length_squared() < 0.05:
		return length_forward
	if has_tee("middle") and Vector2(at.x - tee_middle.x, at.z - tee_middle.z).length_squared() < 0.05:
		return length_middle
	return length


## Back, and middle and forward when those have been placed.
func tee_line() -> String:
	var text := "Back %d yd" % Defs.yards(length)
	if has_tee("middle"):
		text += "  ·  Middle %d yd" % Defs.yards(length_middle)
	if has_tee("forward"):
		text += "  ·  Forward %d yd" % Defs.yards(length_forward)
	return text


func tee_button(which: String, price: String) -> String:
	var title := "Forward tee"
	if which == "middle":
		title = "Middle tee"
	if has_tee(which):
		return title
	return "%s  %s" % [title, price]


## Where a golfer of this skill tees off. Beginners use the forward tee,
## average golfers the middle, and the rest the back. A missing set falls
## back to the next tee back, never a tee further forward. The cuts are
## data/tees.json, grounded in the handicap scale.
func playing_tee(skill: float, book: Dictionary) -> Vector3:
	var forward_below := float(book.get("forward_below", 0.40))
	var middle_below := float(book.get("middle_below", 0.70))
	var want := "back"
	if skill < forward_below:
		want = "forward"
	elif skill < middle_below:
		want = "middle"
	var order: Array[String] = ["forward", "middle", "back"]
	var start := order.find(want)
	if start < 0:
		start = order.size() - 1
	for i in range(start, order.size()):
		var id: String = order[i]
		if has_tee(id):
			return tee_pos(id)
	return tee


## Empty when the spot may take this set. Otherwise the reason it may not.
## `on_line` is how far, in metres, the spot may sit off the line of play.
func refuse_tee(course: Course, which: String, at: Vector3, on_line: float) -> String:
	if which != "middle" and which != "forward":
		return "That is not a tee."
	if has_tee(which):
		return "That tee is already there."
	if course.terrain_at(at.x, at.z) != Defs.T.TEE:
		return "That has to be on a tee box."
	var tile := course.tile_of(at.x, at.z)
	if not course.can_build(tile.x, tile.y):
		return "You can't put a tee there."
	var measured := route_measure(at)
	if measured.y > on_line:
		return "Put it on the line of play."
	var left := length - measured.x
	if left < 0.0:
		left = 0.0
	var order: Array[String] = ["back", "middle", "forward"]
	var idx := order.find(which)
	var behind_left := length
	var behind_i := idx - 1
	while behind_i >= 0:
		var behind_name: String = order[behind_i]
		if has_tee(behind_name):
			behind_left = metres_of(behind_name)
			break
		behind_i -= 1
	if left >= behind_left - 0.05:
		return "It has to be closer to the green than the tee behind it."
	var front_i := idx + 1
	while front_i < order.size():
		var front_name: String = order[front_i]
		if has_tee(front_name):
			if left <= metres_of(front_name) + 0.05:
				return "It can't go past the tee in front."
			break
		front_i += 1
	return ""


func write_tee(which: String, at: Vector3) -> void:
	var metres := _remaining(at)
	if which == "middle":
		tee_middle = at
		length_middle = metres
	elif which == "forward":
		tee_forward = at
		length_forward = metres


func restore_tee(which: String, at: Vector3, metres: float) -> void:
	if which == "middle":
		tee_middle = at
		length_middle = metres
	elif which == "forward":
		tee_forward = at
		length_forward = metres


func clear_set(which: String) -> void:
	if which == "middle":
		tee_middle = Vector3.ZERO
		length_middle = 0.0
	elif which == "forward":
		tee_forward = Vector3.ZERO
		length_forward = 0.0


## Distance along the line of play from the back tee, and how far off it.
func route_measure(at: Vector3) -> Vector2:
	var pts := route
	var spot := Vector2(at.x, at.z)
	if pts.size() < 2:
		var end := design_pin()
		pts = PackedVector2Array([Vector2(tee.x, tee.z), Vector2(end.x, end.z)])
	var best_along := 0.0
	var best_off := 1.0e9
	var walked := 0.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg := b - a
		var seg_len := seg.length()
		var u := 0.0
		if seg_len > 0.0001:
			u = clampf((spot - a).dot(seg) / (seg_len * seg_len), 0.0, 1.0)
		var closest := a + seg * u
		var off := closest.distance_to(spot)
		if off < best_off:
			best_off = off
			best_along = walked + seg_len * u
		walked += seg_len
	return Vector2(best_along, best_off)


func _remaining(at: Vector3) -> float:
	var left := length - route_measure(at).x
	if left < 0.0:
		return 0.0
	return left


func to_dict() -> Dictionary:
	var d := {
		"tee": [tee.x, tee.y, tee.z], "pin": [pin.x, pin.y, pin.z],
		"placed": [placed.x, placed.y, placed.z], "pin_spot": pin_spot, "pin_locked": pin_locked,
		"pin_due": pin_due,
		"par": par, "length": length,
		"earned": earned, "payers": payers, "plays": plays, "strokes": strokes_total, "best": best, "fun": fun,
		"shots": shots_n, "trouble": trouble_n,
		"tally": tally, "aces": aces,
		"name": name, "award": award, "themes": themes, "gap": gap, "comments": comments, "open": open,
		"play_times": play_times,
	}
	if not turns.is_empty():
		var pts: Array = []
		for m in turns:
			pts.append([m.x, m.y, m.z])
		d["turns"] = pts
	var sets := {}
	if has_tee("middle"):
		sets["middle"] = [tee_middle.x, tee_middle.y, tee_middle.z]
		sets["length_middle"] = length_middle
	if has_tee("forward"):
		sets["forward"] = [tee_forward.x, tee_forward.y, tee_forward.z]
		sets["length_forward"] = length_forward
	if not sets.is_empty():
		d["tees"] = sets
	return d


static var _known_themes := {}
static var _known_themes_read := false

static var _cached_on_line := -1.0


## How far, in metres, a turning point may sit off the line. data/turns.json.
static func turn_on_line() -> float:
	if _cached_on_line >= 0.0:
		return _cached_on_line
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/turns.json"))
	var limit := 3.0
	if parsed is Dictionary:
		var book: Dictionary = parsed
		limit = float(book.get("on_line", 3.0))
	_cached_on_line = limit
	return _cached_on_line


## Theme ids from data/awards.json, read once. A load walks every hole.
static func _theme_ids() -> Dictionary:
	if _known_themes_read:
		return _known_themes
	_known_themes = {}
	var awards: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/awards.json"))
	if awards is Dictionary:
		for row in awards.get("themes", []):
			if row is Dictionary:
				_known_themes[str(row.get("id", ""))] = true
	_known_themes_read = true
	return _known_themes


static func from_dict(d: Dictionary) -> Hole:
	var hole := Hole.new()
	hole.tee = Vector3(d.tee[0], d.tee[1], d.tee[2])
	hole.pin = Vector3(d.pin[0], d.pin[1], d.pin[2])
	if d.has("placed"):
		var pl: Array = d.placed
		hole.placed = Vector3(float(pl[0]), float(pl[1]), float(pl[2]))
		hole.pin_spot = int(d.get("pin_spot", 0))
	else:
		hole.placed = hole.pin
		hole.pin_spot = 0
	hole.pin_locked = bool(d.get("pin_locked", false))
	hole.pin_due = int(d.get("pin_due", -1))
	if d.has("tees"):
		var sets: Dictionary = d["tees"]
		if sets.has("middle"):
			var mid_at: Array = sets["middle"]
			hole.tee_middle = Vector3(float(mid_at[0]), float(mid_at[1]), float(mid_at[2]))
			hole.length_middle = float(sets.get("length_middle", 0.0))
		if sets.has("forward"):
			var fwd_at: Array = sets["forward"]
			hole.tee_forward = Vector3(float(fwd_at[0]), float(fwd_at[1]), float(fwd_at[2]))
			hole.length_forward = float(sets.get("length_forward", 0.0))
	hole.earned = float(d.get("earned", 0.0))
	hole.payers = int(d.get("payers", 0))
	hole.plays = int(d.get("plays", 0))
	hole.shots_n = int(d.get("shots", 0))
	hole.trouble_n = int(d.get("trouble", 0))
	hole.strokes_total = int(d.get("strokes", 0))
	hole.best = int(d.get("best", 0))
	hole.fun = float(d.get("fun", 60.0))
	hole.aces = int(d.get("aces", 0))
	var tl: Dictionary = d.get("tally", {})
	for k: String in tl:
		hole.tally[k] = int(tl[k])
	hole.name = str(d.get("name", ""))
	hole.open = bool(d.get("open", true))
	var pt: Array = d.get("play_times", [])
	for x in pt:
		hole.play_times.append(float(x))
	while hole.play_times.size() > PACE_KEEP:
		hole.play_times.pop_front()
	hole.award = str(d.get("award", ""))
	hole.gap = float(d.get("gap", 0.0))
	var known := _theme_ids()
	var th: Array = d.get("themes", [])
	for id in th:
		var name := str(id)
		if name == "" or hole.themes.has(name):
			continue
		if not known.is_empty() and not known.has(name):
			continue
		hole.themes.append(name)
	hole.comments = d.get("comments", {})
	if d.has("turns"):
		var raw: Array = d["turns"]
		for row in raw:
			if row is Array:
				var rec: Array = row
				if rec.size() >= 3:
					hole.turns.append(Vector3(float(rec[0]), float(rec[1]), float(rec[2])))
	# Par is filled in properly once the ground is loaded (Course.from_dict).
	# Until then, a save that recorded one keeps it, and an older save keeps
	# the straight-line par its rounds were scored against.
	var straight := hole.straight_length()
	if d.has("par"):
		hole.par = int(d.par)
	else:
		hole.par = par_for(straight)
	hole.length = float(d.get("length", straight))
	return hole
