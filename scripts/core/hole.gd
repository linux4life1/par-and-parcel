class_name Hole
extends RefCounted
## One golf hole: a tee, a pin, and a routing field the golfer AI steers by.

var tee := Vector3.ZERO
var pin := Vector3.ZERO
var par := 4
var length := 0.0
var earned := 0.0               # green fees golfers have paid for this hole
var payers := 0                 # how many times a golfer has finished it and been asked
var plays := 0
var strokes_total := 0
var best := 0
var tally := {}                 # score against par -> how many times: "-2", "-1", "0", "1", "2", "3" (3 is three over or worse)
var aces := 0
var fun := 60.0                 # running golfer opinion of this hole, 0..100
var name := ""
var comments := {}              # mood tag -> summed effect on golfers here
var award := ""                 # "", "top100" or "top18"
# What the hole tests, measured by HoleLab in strokes of advantage.
var lab_ready := false
var lab_sig := -1
var test_length := 0.0
var test_accuracy := 0.0
var test_imagination := 0.0
var kind := 0                   # bit 1 length, 2 accuracy, 4 imagination
var expect := {}                # expected score for a beginner, average, expert
var teeing_group: Group = null  # the group holding the tee box
var _lit := 0.0
var _lit_rev := -1
var _lit_sig := Vector3.ZERO
## A hole needs this much of its length lit to be played after dark.
const LIT_ENOUGH := 0.7
var groups: Array[Group] = []   # every group currently playing the hole

# Routing field: "effective metres to the pin" for tiles in a box around the hole.
var _field := PackedFloat32Array()
var _fx := 0
var _fy := 0
var _fw := 0
var _fh := 0
var _field_rev := -1
var _field_time := -1000.0
# scratch heap
var _hk := PackedFloat32Array()
var _hv := PackedInt32Array()
var _hn := 0
var _pop_key := 0.0


func update_metrics() -> void:
	length = Vector2(pin.x - tee.x, pin.z - tee.z).length()
	if length <= 225.0:
		par = 3
	elif length <= 430.0:
		par = 4
	else:
		par = 5


func snap_to_ground(course: Course) -> void:
	tee.y = course.height_at(tee.x, tee.z)
	pin.y = course.height_at(pin.x, pin.z)


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
	if _field_rev != course.revision and (_field_rev < 0 or now - _field_time > 4.0):
		_compute_field(course)
		_field_time = now
	var tx := int(floor(x / Defs.TILE)) - _fx
	var ty := int(floor(z / Defs.TILE)) - _fy
	if tx < 0 or ty < 0 or tx >= _fw or ty >= _fh:
		return Vector2(pin.x - x, pin.z - z).length() * 1.35 + 20.0
	return _field[ty * _fw + tx]


func _compute_field(course: Course) -> void:
	_field_rev = course.revision
	var margin := 14
	var tt := course.tile_of(tee.x, tee.z)
	var pt := course.tile_of(pin.x, pin.z)
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
	var sig := tee + pin * 3.0
	if _lit_rev == course.lights_rev and sig == _lit_sig:
		return _lit
	_lit_rev = course.lights_rev
	_lit_sig = sig
	var n := maxi(6, int(length / 12.0))
	var lit := 0
	for k in n + 1:
		var p := tee.lerp(pin, float(k) / n)
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


func to_dict() -> Dictionary:
	return {
		"tee": [tee.x, tee.y, tee.z], "pin": [pin.x, pin.y, pin.z],
		"earned": earned, "payers": payers, "plays": plays, "strokes": strokes_total, "best": best, "fun": fun,
		"tally": tally, "aces": aces,
		"name": name, "award": award, "comments": comments,
	}


static func from_dict(d: Dictionary) -> Hole:
	var hole := Hole.new()
	hole.tee = Vector3(d.tee[0], d.tee[1], d.tee[2])
	hole.pin = Vector3(d.pin[0], d.pin[1], d.pin[2])
	hole.earned = float(d.get("earned", 0.0))
	hole.payers = int(d.get("payers", 0))
	hole.plays = int(d.get("plays", 0))
	hole.strokes_total = int(d.get("strokes", 0))
	hole.best = int(d.get("best", 0))
	hole.fun = float(d.get("fun", 60.0))
	hole.aces = int(d.get("aces", 0))
	var tl: Dictionary = d.get("tally", {})
	for k: String in tl:
		hole.tally[k] = int(tl[k])
	hole.name = str(d.get("name", ""))
	hole.award = str(d.get("award", ""))
	hole.comments = d.get("comments", {})
	hole.update_metrics()
	return hole
