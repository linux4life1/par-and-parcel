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
var _litter_rev := -1
var _litter_ready := false
var _bins: Array[Vector2] = []
var _source_at := {}
## Plays already counted toward today's cup wear, per hole.
var _cup_seen := {}
## Cup wear applied to each tile. Mowing does not clear it, so a test can
## see where a stationary pin piled up and a moving pin spread out.
var cup_load := {}


func _init(s: Sim) -> void:
	sim = s


## A mower pass repaired this tile. The historical cup total is kept.
func repair_tile(i: int) -> void:
	sim.course.health[i] = minf(1.0, sim.course.health[i] + 0.9)


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
	_refresh_litter()
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
		var nick := Defs.T_WEAR[t] * wear
		hv -= nick
		if drought and wv < 0.1:
			hv -= 0.0006 * edt
		# weeds. A landmark nearby slows the sprout, the growth and the spread.
		# Cup wear is in this health, so a tired cup is a place weeds can take.
		var calm := sim.weed_scale(i)
		var seen := hv
		if seen > 1.0:
			seen = 1.0
		if wd <= 0.0:
			if rng.randf() < weed_p * Defs.T_WEED[t] * (0.5 + wv) * (1.5 - seen * 0.5) * calm:
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
			var bite := pv * 0.004 * edt
			hv -= bite
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
	wear_around_pins(dt)


## Extra wear on the green around each cup. A cup tires its own green every
## day, locked or rotating, and a hole that has been played today wears a
## little more. Moving the pin spreads that wear. It is real health: weeds,
## the keeper and the condition all read it. The rate uses the same
## difficulty and skill multipliers as the rest of the turf. `dt` is sim
## seconds.
func wear_around_pins(dt: float) -> void:
	var spec: Dictionary = sim.db.pins
	var base := float(spec.get("wear", 0.0)) * dt * sim.skills.mult("wear") * sim.diff("wear")
	if base <= 0.0 or sim.course.holes.is_empty():
		return
	var reach_m := float(spec.get("reach", 2.5))
	var reach := int(ceil(reach_m / Defs.TILE))
	var course := sim.course
	var seen := {}
	for hole in course.holes:
		var rate := base * _cup_play_scale(hole, spec)
		var t := course.tile_of(hole.pin.x, hole.pin.z)
		for ty in range(t.y - reach, t.y + reach + 1):
			for tx in range(t.x - reach, t.x + reach + 1):
				if not course.in_bounds(tx, ty):
					continue
				var i := ty * course.w + tx
				if seen.has(i) or not Defs.is_green(course.terrain[i]):
					continue
				var centre := course.tile_center(tx, ty)
				if Vector2(centre.x - hole.pin.x, centre.z - hole.pin.z).length() > reach_m:
					continue
				seen[i] = true
				cup_load[i] = float(cup_load.get(i, 0.0)) + rate
				course.health[i] = maxf(0.0, course.health[i] - rate)


## 1 on a quiet day, up to 1 + played once the hole has been played play_cap
## times today. The first look records the scorecard so far, so a hole is not
## charged for rounds that finished before the cup started wearing.
func _cup_play_scale(hole: Hole, spec: Dictionary) -> float:
	var id := hole.get_instance_id()
	var today := sim.day()
	var known := hole.plays
	var gain := 0
	var stamped := today
	if _cup_seen.has(id):
		var got: Variant = _cup_seen[id]
		var rec: Dictionary = got
		known = int(rec.get("plays", hole.plays))
		gain = int(rec.get("gain", 0))
		stamped = int(rec.get("day", today))
		if stamped != today:
			gain = maxi(0, hole.plays - known)
			stamped = today
		else:
			gain += maxi(0, hole.plays - known)
	_cup_seen[id] = {"day": stamped, "plays": hole.plays, "gain": gain}
	var cap := float(spec.get("play_cap", 4.0))
	if cap <= 0.0:
		return 1.0
	var bonus := float(spec.get("played", 0.0))
	return 1.0 + bonus * clampf(float(gain) / cap, 0.0, 1.0)


## Keep the bin and source lists current. Rebuilt only when an object moves,
## so a step does not walk the whole map.
func _refresh_litter() -> void:
	var course := sim.course
	if _litter_ready and _litter_rev == course.revision:
		return
	_litter_ready = true
	_litter_rev = course.revision
	_bins.clear()
	_source_at = {}
	var want := {}
	for name in sim.db.litter.get("sources", []):
		var id := Defs.O_NAMES.find(str(name))
		if id > 0:
			want[id] = true
	for i in course.objects.size():
		if _shut(course, i):
			continue
		var o := int(course.objects[i])
		if o == Defs.O.BIN:
			_bins.append(Vector2((i % course.w + 0.5) * Defs.TILE, (int(i / course.w) + 0.5) * Defs.TILE))
		elif want.has(o):
			_source_at[i] = true


func _shut(course: Course, i: int) -> bool:
	return course.is_closed(i)


## One sale at a stand. The 3 by 3 around it picks up a little litter. A bin
## nearby cuts that new litter. It does not take up what is already there.
func drop_litter(tile: int) -> void:
	_refresh_litter()
	var course := sim.course
	if not _source_at.has(tile):
		return
	var spec: Dictionary = sim.db.litter
	var add := float(spec.get("per_sale", 0.16))
	if add <= 0.0:
		return
	var radius := float(spec.get("bin_radius", 22.0))
	var sx := tile % course.w
	var sy := int(tile / course.w)
	if _bin_near(_bins, Vector2((sx + 0.5) * Defs.TILE, (sy + 0.5) * Defs.TILE), radius * radius):
		add *= float(spec.get("bin_cut", 0.12))
	var show := float(spec.get("show", 0.45))
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var x := sx + ox
			var y := sy + oy
			if not course.in_bounds(x, y):
				continue
			var i := y * course.w + x
			_set_litter(i, course.litter[i] + add, show)


func _bin_near(bins: Array[Vector2], p: Vector2, r2: float) -> bool:
	for b: Vector2 in bins:
		if b.distance_squared_to(p) <= r2:
			return true
	return false


func _set_litter(i: int, after: float, show: float) -> void:
	var before: float = sim.course.litter[i]
	after = clampf(after, 0.0, 1.0)
	if is_equal_approx(before, after):
		return
	sim.course.litter[i] = after
	if (before < show and after >= show) or (before >= show and after < show):
		sim.course.litter_rev += 1


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
