class_name Grounds
extends RefCounted
## The living course: how wet each tile is, how healthy the turf is, and how
## weeds and pests take hold and spread. Works through the map a slice at a
## time so the cost per frame stays tiny.

const SLICES := 16
## A feeling painted on a tile halves in about two calendar days.
const MOOD_FADE := 0.023
const SEASON_WEEDS: Array[float] = [1.3, 1.6, 1.4, 1.0, 0.9, 0.9, 0.8, 0.5]
const SEASON_PESTS: Array[float] = [0.6, 0.9, 1.2, 1.6, 1.8, 1.5, 1.0, 0.5]

var sim: Sim
var condition := 1.0        # 0..1 state of the tees, fairways and greens
var avg_wet := 0.2
var weed_cover := 0.0       # share of in-play tiles with visible weeds
var pest_cover := 0.0
var play_tiles := PackedInt32Array()
var pool := PackedFloat32Array()   # 0..1 how much each tile collects water
var _cursor := 0
var _rev := -1
var _acc_c := 0.0
var _acc_w := 0.0
var _acc_n := 0.0
var _acc_weed := 0.0
var _acc_pest := 0.0
var _acc_wet := 0.0
var _warned_at := -1000.0   # sim time the owner was last told about unrest and weeds
var _acc_all := 0.0


func _init(s: Sim) -> void:
	sim = s


## The course was swapped for another. Rebuild the tile index even when the
## new course's revision number matches the one just thrown away.
func reset_layout() -> void:
	_rev = -1
	refresh_layout()


func refresh_layout() -> void:
	var course := sim.course
	if _rev == course.revision:
		return
	_rev = course.revision
	var lava: bool = sim.biome.get("lava", false)
	var w := course.w
	var h := course.h
	play_tiles.clear()
	pool.resize(w * h)
	for ty in h:
		for tx in w:
			var i := ty * w + tx
			var t := course.terrain[i]
			if Defs.is_short(t):
				play_tiles.append(i)
			# hollows hold water: compare with a ring two tiles out
			var c := course.corner(tx, ty)
			var ring := course.corner(tx - 2, ty) + course.corner(tx + 3, ty) + course.corner(tx, ty - 2) + course.corner(tx, ty + 3)
			var p := clampf((ring * 0.25 - c) / 1.2, 0.0, 1.0)
			if not lava and _near_water(course, tx, ty):
				p = maxf(p, 0.5)
			pool[i] = p


func _near_water(course: Course, tx: int, ty: int) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx := tx + d.x
		var ny := ty + d.y
		if course.in_bounds(nx, ny) and course.terrain[ny * course.w + nx] == Defs.T.WATER:
			return true
	return false


## How the mood of the course bears on the weeds. Unhappy golfers tramp
## the rough, leave divots and kick up the bunkers; happy ones look after
## the place. Below 60% satisfaction weeds come faster, three times as fast
## at 30%; above 60% a little slower, down to 0.7 at 85%.
func weed_mood() -> float:
	var s := sim.visitors.average_satisfaction()
	if s < 60.0:
		return lerpf(1.0, 3.0, clampf((60.0 - s) / 30.0, 0.0, 1.0))
	return lerpf(1.0, 0.7, clampf((s - 60.0) / 25.0, 0.0, 1.0))


## Tell the owner once when unhappy golfers start costing them the turf,
## and again if it happens after a long calm.
func _mood_warning(mood: float) -> void:
	if mood >= 1.8 and sim.time > _warned_at + 400.0 and sim.visitors.recent.size() >= 4:
		_warned_at = sim.time
		sim.toast.emit("Unhappy golfers are letting the course go: weeds are coming up %.1f times as fast. Cheer them up, or hire greenkeepers." % mood, "bad")
		sim.feed.say("weeds_unrest", null, {}, true)
	elif mood < 1.2:
		_warned_at = minf(_warned_at, sim.time - 300.0)


## Called a few times a second with the sim time that has passed.
func step(dt: float) -> void:
	refresh_layout()
	var course := sim.course
	var n := course.w * course.h
	var count := n / SLICES
	var edt := dt * SLICES
	var wx := sim.weather
	var month := sim.month()
	var turf: Dictionary = sim.biome.get("turf", {})
	var climate: Dictionary = sim.biome.get("climate", {})
	var lava: bool = sim.biome.get("lava", false)
	var wild_rough: bool = turf.get("wild_rough", false)
	var rain_in := wx.rain * 0.012 * edt
	var dry := (0.003 + 0.005 * clampf(wx.temp / 30.0, 0.0, 1.4) + 0.0004 * wx.wind_speed) * sim.skills.mult("drainage") * edt
	dry *= float(climate.get("dry", 1.0))
	if sim.time < wx.heat_until:
		dry *= 1.8
	var drought := sim.time < wx.heat_until     # turf only scorches in a heat wave
	# the mood of the course and the difficulty slider both bear on the turf
	var mood := weed_mood()
	var weed_p := 0.00006 * SEASON_WEEDS[month] * sim.skills.mult("weed_growth") * edt * float(turf.get("weeds", 1.0)) * mood * sim.diff("weeds")
	var pest_p := 0.000004 * SEASON_PESTS[month] * sim.skills.mult("pest_rate") * edt * float(turf.get("pests", 1.0)) * sim.diff("pests")
	var wear := sim.skills.mult("wear") * edt * float(turf.get("wear", 1.0)) * sim.diff("wear")
	var creep := 0.0035 * edt * sqrt(mood)
	_mood_warning(mood)
	var rng := sim.rng
	var w := course.w
	for k in count:
		var i := _cursor
		_cursor += 1
		if _cursor >= n:
			_cursor = 0
			_finish_pass()
		var t: int = course.terrain[i]
		var md := course.mood[i]
		if absf(md) > 0.02:
			course.mood[i] = md * exp(-MOOD_FADE * edt)
		else:
			course.mood[i] = 0.0
		if t == Defs.T.WATER:
			course.wet[i] = 0.0 if lava else 1.0
			continue
		var wv := course.wet[i]
		wv += rain_in - dry * Defs.T_DRY[t] * (1.0 - 0.6 * pool[i]) * wv
		wv = clampf(wv, 0.0, 1.0)
		course.wet[i] = wv
		_acc_wet += wv
		_acc_all += 1.0
		if not Defs.T_GRASS[t] or t == Defs.T.DEEP_ROUGH or (wild_rough and t == Defs.T.ROUGH):
			continue
		var hv := course.health[i]
		var pv := course.pests[i]
		var wd := course.weeds[i]
		hv -= Defs.T_WEAR[t] * wear
		if drought and wv < 0.1:
			hv -= 0.0006 * edt
		# weeds. A landmark nearby slows the sprout, the growth and the spread.
		var calm := sim.weed_scale(i)
		if wd <= 0.0:
			if rng.randf() < weed_p * Defs.T_WEED[t] * (0.5 + wv) * (1.5 - hv * 0.5) * calm:
				wd = 0.06
		else:
			wd = minf(1.0, wd + 0.003 * sim.skills.mult("weed_growth") * edt * calm)
			if wd > 0.6 and rng.randf() < creep * calm:
				var ni := _neighbour(i, w, n, rng)
				if ni >= 0 and Defs.T_WEED[course.terrain[ni]] > 0.0 and course.weeds[ni] <= 0.0:
					course.weeds[ni] = 0.06
		# pests
		if pv <= 0.0:
			var pw := 1.0 if t != Defs.T.ROUGH else 0.2
			if rng.randf() < pest_p * pw:
				pv = 0.08
		else:
			pv = minf(1.0, pv + 0.006 * edt)
			hv -= pv * 0.004 * edt
			if pv > 0.7 and rng.randf() < 0.003 * edt:
				var ni := _neighbour(i, w, n, rng)
				if ni >= 0 and Defs.T_GRASS[course.terrain[ni]] and course.pests[ni] <= 0.0:
					course.pests[ni] = 0.08
		hv = clampf(hv, 0.0, 1.0)
		course.health[i] = hv
		course.weeds[i] = wd
		course.pests[i] = pv
		if t != Defs.T.ROUGH:
			var wt := 3.0 if Defs.is_green(t) else 1.0
			_acc_c += hv * (1.0 - 0.5 * wd) * (1.0 - 0.5 * pv) * wt
			_acc_w += wt
			_acc_n += 1.0
			if wd > 0.3:
				_acc_weed += 1.0
			if pv > 0.3:
				_acc_pest += 1.0


func _neighbour(i: int, w: int, n: int, rng: RandomNumberGenerator) -> int:
	var ni := i
	match rng.randi() % 4:
		0:
			ni = i + 1
		1:
			ni = i - 1
		2:
			ni = i + w
		3:
			ni = i - w
	return ni if ni >= 0 and ni < n else -1


func _finish_pass() -> void:
	if _acc_w > 0.0:
		condition = _acc_c / _acc_w
		weed_cover = _acc_weed / _acc_n
		pest_cover = _acc_pest / _acc_n
	else:
		condition = 1.0
		weed_cover = 0.0
		pest_cover = 0.0
	if _acc_all > 0.0:
		avg_wet = _acc_wet / _acc_all
	_acc_c = 0.0
	_acc_w = 0.0
	_acc_n = 0.0
	_acc_weed = 0.0
	_acc_pest = 0.0
	_acc_wet = 0.0
	_acc_all = 0.0


## Start a pest outbreak or a weed bloom on turf that is in play.
func seed_trouble(what: String, count: int) -> void:
	refresh_layout()
	if play_tiles.is_empty():
		return
	for k in count:
		var i := play_tiles[sim.rng.randi() % play_tiles.size()]
		if what == "pests":
			sim.course.pests[i] = maxf(sim.course.pests[i], 0.5)
		else:
			sim.course.weeds[i] = maxf(sim.course.weeds[i], 0.4)
