class_name UndoLog
extends RefCounted
## Build steps that can be taken back: a paint stroke, a raise or lower, an
## object placed or removed, a hole laid out. Only the tiles and corners a
## step changed are kept. The refund is the sum of the build calls spent
## while the stroke was open, booked against construction, and redo charges
## that same amount again, refusing if it cannot be paid. Wetness, health,
## weeds, pests, litter and a repair mark are put back only where they are
## still what the step left. If the ground, the object, the switch or a
## corner is no longer what the step left, undo and redo change nothing and
## drop the history. A round being played refuses both.


var sim: Sim
var depth := 30
var past: Array[Dictionary] = []
var future: Array[Dictionary] = []
var applying := false
var _stroking := false
var _open: Dictionary = {}


func _init(s: Sim) -> void:
	sim = s
	depth = maxi(int(s.db.undo.get("depth", 30)), 1)


func limit() -> int:
	return depth


func steps() -> int:
	return past.size()


func can_undo() -> bool:
	return not past.is_empty()


func can_redo() -> bool:
	return not future.is_empty()


## Drop every step. A loaded course, a save, and an edit this log does not
## record all start from an empty history.
func clear() -> void:
	past.clear()
	future.clear()
	_stroking = false
	_open = {}


## Start a stroke. A stroke already open (a drag) is left as it is, and the
## caller that did not start it must not finish it.
func begin() -> bool:
	if _stroking:
		return false
	_stroking = true
	_open = {
		"charged": 0.0,
		"tiles": {},
		"heights": {},
		"holes": sim.course.holes.size(),
		"used": {},
		"built": int(sim.stats.get("holes_built", 0)),
	}
	return true


func commit() -> void:
	if not _stroking:
		return
	_stroking = false
	var c := sim.course
	var noted: Dictionary = _open["tiles"]
	var tile_rec := {}
	var any := false
	for key in noted:
		var i := int(key)
		var before: Dictionary = noted[key]
		var after := _read_tile(c, i)
		if not _tile_same(before, after):
			any = true
			tile_rec[i] = {"before": before, "after": after}
	var noted_h: Dictionary = _open["heights"]
	var height_rec := {}
	for key in noted_h:
		var vi := int(key)
		var was := float(noted_h[key])
		var now := c.heights[vi]
		if not is_equal_approx(was, now):
			any = true
			height_rec[vi] = {"before": was, "after": now}
	var hole_added := c.holes.size() > int(_open["holes"])
	var charged := float(_open["charged"])
	var gifts: Dictionary = _open["used"]
	var built := int(sim.stats.get("holes_built", 0)) - int(_open["built"])
	var have_turn := _open.has("turn_mark")
	var have_tee := _open.has("tee_set")
	if not any and not hole_added and is_zero_approx(charged) and gifts.is_empty() and built == 0 and not have_turn and not have_tee:
		_open = {}
		return
	var entry := {
		"tiles": tile_rec,
		"heights": height_rec,
		"charged": charged,
		"gifts": gifts,
		"built": built,
	}
	if hole_added:
		entry["hole"] = _snap_hole(c.holes[c.holes.size() - 1])
	if have_turn:
		entry["turn_mark"] = _open["turn_mark"]
	if have_tee:
		entry["tee_set"] = _open["tee_set"]
	past.append(entry)
	while past.size() > depth:
		past.pop_front()
	future.clear()
	_open = {}


## Remember a tile before the stroke changes it. Later edits of the same
## tile in this stroke keep the first reading.
func note_tile(i: int) -> void:
	if not _stroking:
		return
	var tiles: Dictionary = _open["tiles"]
	if tiles.has(i):
		return
	tiles[i] = _read_tile(sim.course, i)


func note_height(vi: int) -> void:
	if not _stroking:
		return
	var hs: Dictionary = _open["heights"]
	if hs.has(vi):
		return
	hs[vi] = sim.course.heights[vi]


## A paint, a placement, a raise, a lower or a hole, charged while this
## stroke is open. Fees and bills that land in the same moment are not part
## of it.
func note_charge(amount: float) -> void:
	if not _stroking or amount <= 0.0:
		return
	_open["charged"] = float(_open["charged"]) + amount


## A free placement this stroke actually spent. A gift that arrives while the
## stroke is open is not part of the step.
func note_gift(o: int) -> void:
	if not _stroking:
		return
	var used: Dictionary = _open["used"]
	used[o] = int(used.get(o, 0)) + 1


## A turning point placed during this stroke. Undo takes the stake off and
## refunds the charge; redo puts the same spot back.
func note_turn(hole: Hole, at: Vector3) -> void:
	if not _stroking:
		return
	var layout := hole.design_pin()
	_open["turn_mark"] = {
		"name": hole.name,
		"tee": [hole.tee.x, hole.tee.y, hole.tee.z],
		"pin": [layout.x, layout.y, layout.z],
		"at": [at.x, at.y, at.z],
	}


## A middle or forward tee placed during this stroke. Undo removes it and
## refunds the charge; redo puts the same spot back.
func note_tee(hole: Hole, which: String, at: Vector3, metres: float) -> void:
	if not _stroking:
		return
	var layout := hole.design_pin()
	_open["tee_set"] = {
		"name": hole.name,
		"tee": [hole.tee.x, hole.tee.y, hole.tee.z],
		"pin": [layout.x, layout.y, layout.z],
		"which": which,
		"at": [at.x, at.y, at.z],
		"metres": metres,
	}


func undo() -> bool:
	if _blocked() or past.is_empty():
		return false
	var e: Dictionary = past[past.size() - 1]
	past.remove_at(past.size() - 1)
	if not _intact(e, false) or (e.has("hole") and _find_hole(e["hole"]) < 0) or (e.has("turn_mark") and _find_hole(e["turn_mark"]) < 0) or (e.has("tee_set") and _find_hole(e["tee_set"]) < 0):
		clear()
		return false
	if not _apply(e, false):
		past.append(e)
		return false
	future.append(e)
	return true


func redo() -> bool:
	if _blocked() or future.is_empty():
		return false
	var e: Dictionary = future[future.size() - 1]
	future.remove_at(future.size() - 1)
	if not _intact(e, true):
		clear()
		return false
	if not _afford(e) or not _apply(e, true):
		future.append(e)
		return false
	past.append(e)
	return true


## The ground, object, switch and corners are still what this step left
## (the after side on undo, the before side on redo).
func _intact(e: Dictionary, forward: bool) -> bool:
	var side := "before" if forward else "after"
	var c := sim.course
	var tiles: Dictionary = e["tiles"]
	for key in tiles:
		var i := int(key)
		var rec: Dictionary = tiles[key]
		var was: Dictionary = rec[side]
		if int(c.terrain[i]) != int(was["terrain"]) or int(c.objects[i]) != int(was["object"]) or int(c.closed[i]) != int(was["closed"]):
			return false
	var heights: Dictionary = e["heights"]
	for key in heights:
		var vi := int(key)
		var rec: Dictionary = heights[key]
		if not is_equal_approx(c.heights[vi], float(rec[side])):
			return false
	return _turn_intact(e, forward) and _tee_intact(e, forward)


func _blocked() -> bool:
	return _stroking or applying or sim.playing_round


## Redo pays the same charge and uses the same gifts. It does not look the
## price up again, and it does not run if either is short.
func _afford(e: Dictionary) -> bool:
	var charged := float(e.get("charged", 0.0))
	if charged > sim.economy.money + 0.001:
		return false
	var used: Dictionary = e.get("gifts", {})
	for k in used:
		var n := int(used[k])
		if n > 0 and int(sim.gifts.get(k, 0)) < n:
			return false
	return true


func _apply(e: Dictionary, forward: bool) -> bool:
	if forward and not _afford(e):
		return false
	applying = true
	var c := sim.course
	var tiles: Dictionary = e["tiles"]
	var obj_changed := false
	var litter_edge := false
	var x0 := c.w
	var y0 := c.h
	var x1 := -1
	var y1 := -1
	var dest_key := "after" if forward else "before"
	var from_key := "before" if forward else "after"
	var show := float(sim.db.litter.get("show", 0.45))
	for key in tiles:
		var i := int(key)
		var rec: Dictionary = tiles[key]
		var dest: Dictionary = rec[dest_key]
		var from: Dictionary = rec[from_key]
		var prev_o := int(c.objects[i])
		var new_o := int(dest["object"])
		var prev_closed := int(c.closed[i])
		c.terrain[i] = int(dest["terrain"])
		c.objects[i] = new_o
		c.closed[i] = int(dest["closed"])
		c.open_month[i] = int(dest["open_month"])
		if not forward and new_o == 0 and prev_o != 0:
			# The building is gone, so the empty tile carries no broken window.
			# The mark stays on the step: redo puts the building back still broken.
			var mark := int(c.repair[i])
			if mark != int(from["repair"]):
				from["repair"] = mark
			c.repair[i] = 0
		elif int(c.repair[i]) == int(from["repair"]):
			c.repair[i] = int(dest["repair"])
		if is_equal_approx(float(c.litter[i]), float(from["litter"])):
			var litter := float(dest["litter"])
			var was_litter := float(c.litter[i])
			if not is_equal_approx(was_litter, litter):
				c.litter[i] = litter
				if (was_litter < show and litter >= show) or (was_litter >= show and litter < show):
					litter_edge = true
		if is_equal_approx(c.wet[i], float(from["wet"])):
			c.wet[i] = float(dest["wet"])
		if is_equal_approx(c.health[i], float(from["health"])):
			c.health[i] = float(dest["health"])
		if is_equal_approx(c.weeds[i], float(from["weeds"])):
			c.weeds[i] = float(dest["weeds"])
		if is_equal_approx(c.pests[i], float(from["pests"])):
			c.pests[i] = float(dest["pests"])
		if prev_o != new_o or prev_closed != int(dest["closed"]):
			obj_changed = true
			if prev_o != new_o:
				var lit := Defs.O_LIGHT[prev_o] > 0.0 or Defs.O_LIGHT[new_o] > 0.0
				c.objects_touched(i, lit)
		var tx := i % c.w
		var ty := int(i / c.w)
		x0 = mini(x0, tx)
		y0 = mini(y0, ty)
		x1 = maxi(x1, tx)
		y1 = maxi(y1, ty)
	if x1 >= 0:
		c.tiles_changed.emit(Rect2i(x0 - 1, y0 - 1, x1 - x0 + 3, y1 - y0 + 3))
	if obj_changed:
		c.objects_changed.emit()
	if litter_edge:
		c.litter_rev += 1
	var heights: Dictionary = e["heights"]
	var hw := c.w + 1
	var hx0 := hw
	var hy0 := c.h + 1
	var hx1 := -1
	var hy1 := -1
	for key in heights:
		var vi := int(key)
		var rec: Dictionary = heights[key]
		c.heights[vi] = float(rec[dest_key])
		var vx := vi % hw
		var vy := int(vi / hw)
		hx0 = mini(hx0, vx)
		hy0 = mini(hy0, vy)
		hx1 = maxi(hx1, vx)
		hy1 = maxi(hy1, vy)
	if hx1 >= 0:
		c.heights_changed.emit(Rect2i(hx0 - 1, hy0 - 1, hx1 - hx0 + 3, hy1 - hy0 + 3))
		for hole in c.holes:
			hole.snap_to_ground(c)
	if e.has("hole"):
		if forward:
			_redo_hole(e["hole"])
		else:
			var at := _find_hole(e["hole"])
			if at >= 0:
				sim.remove_hole(at)
	if not _apply_turn(e, forward):
		applying = false
		return false
	if not _apply_tee(e, forward):
		applying = false
		return false
	_books(e, forward)
	if x1 >= 0 or hx1 >= 0 or e.has("hole") or e.has("turn_mark") or e.has("tee_set"):
		c.revision += 1
	applying = false
	return true


func _turn_intact(e: Dictionary, forward: bool) -> bool:
	if not e.has("turn_mark"):
		return true
	var snap: Dictionary = e["turn_mark"]
	var at := _find_hole(snap)
	if at < 0:
		return false
	var hole := sim.course.holes[at]
	var ad: Array = snap["at"]
	var pos := Vector3(float(ad[0]), float(ad[1]), float(ad[2]))
	var there := hole.has_turn(pos)
	if forward:
		return not there
	return there


func _tee_intact(e: Dictionary, forward: bool) -> bool:
	if not e.has("tee_set"):
		return true
	var snap: Dictionary = e["tee_set"]
	var at := _find_hole(snap)
	if at < 0:
		return false
	var hole := sim.course.holes[at]
	var which := str(snap["which"])
	var ad: Array = snap["at"]
	var recorded := Vector3(float(ad[0]), float(ad[1]), float(ad[2]))
	var cur := hole.tee_pos(which)
	if forward:
		return not hole.has_tee(which)
	return hole.has_tee(which) and Vector2(cur.x - recorded.x, cur.z - recorded.z).length_squared() < 0.05


func _apply_turn(e: Dictionary, forward: bool) -> bool:
	if not e.has("turn_mark"):
		return true
	var snap: Dictionary = e["turn_mark"]
	var at := _find_hole(snap)
	if at < 0:
		return false
	var hole := sim.course.holes[at]
	var ad: Array = snap["at"]
	var pos := Vector3(float(ad[0]), float(ad[1]), float(ad[2]))
	if forward:
		if hole.has_turn(pos):
			return false
		hole.add_turn(pos)
	else:
		if not hole.remove_turn(pos):
			return false
	return true


func _apply_tee(e: Dictionary, forward: bool) -> bool:
	if not e.has("tee_set"):
		return true
	var snap: Dictionary = e["tee_set"]
	var at := _find_hole(snap)
	if at < 0:
		return false
	var hole := sim.course.holes[at]
	var which := str(snap["which"])
	if forward:
		var ad: Array = snap["at"]
		var pos := Vector3(float(ad[0]), float(ad[1]), float(ad[2]))
		hole.restore_tee(which, pos, float(snap.get("metres", 0.0)))
	else:
		hole.clear_set(which)
	return true


## The hole this step added, matched by the details that were saved, wherever
## it now sits in the playing order.
func _find_hole(snap: Dictionary) -> int:
	var td: Array = snap["tee"]
	var pd: Array = snap["pin"]
	var want := str(snap["name"])
	for i in sim.course.holes.size():
		var h := sim.course.holes[i]
		if h.name != want:
			continue
		if not is_equal_approx(h.tee.x, float(td[0])) or not is_equal_approx(h.tee.z, float(td[2])):
			continue
		var layout := h.design_pin()
		if not is_equal_approx(layout.x, float(pd[0])) or not is_equal_approx(layout.z, float(pd[2])):
			continue
		return i
	return -1


func _redo_hole(snap: Dictionary) -> void:
	var td: Array = snap["tee"]
	var pd: Array = snap["pin"]
	var tee := Vector3(float(td[0]), float(td[1]), float(td[2]))
	var pin := Vector3(float(pd[0]), float(pd[1]), float(pd[2]))
	var hole := sim.course.add_hole(tee, pin)
	hole.name = str(snap["name"])
	hole.par = int(snap["par"])
	hole.length = float(snap["length"])
	hole.open = bool(snap["open"])
	if snap.has("cup"):
		var cd: Array = snap["cup"]
		hole.pin = Vector3(float(cd[0]), float(cd[1]), float(cd[2]))
		hole.pin_spot = int(snap.get("spot", 0))


func _snap_hole(h: Hole) -> Dictionary:
	var layout := h.design_pin()
	return {
		"tee": [h.tee.x, h.tee.y, h.tee.z],
		"pin": [layout.x, layout.y, layout.z],
		"cup": [h.pin.x, h.pin.y, h.pin.z],
		"spot": h.pin_spot,
		"name": h.name,
		"par": h.par,
		"length": h.length,
		"open": h.open,
	}


## Forward charges the step again. Back pays that charge into the cash and
## takes it off construction, whatever the books have done since.
func _books(e: Dictionary, forward: bool) -> void:
	var charged := float(e.get("charged", 0.0))
	var dir := 1.0 if forward else -1.0
	if not is_zero_approx(charged):
		sim.economy.money -= dir * charged
		var now := float(sim.economy.expense.get("construction", 0.0)) + dir * charged
		if is_zero_approx(now):
			sim.economy.expense.erase("construction")
		else:
			sim.economy.expense["construction"] = now
		sim.economy.changed.emit()
	var used: Dictionary = e.get("gifts", {})
	for k in used:
		var n := int(used[k])
		var have := int(sim.gifts.get(k, 0))
		sim.gifts[int(k)] = have - int(dir) * n
	var built := int(e.get("built", 0))
	if built != 0:
		sim.stats["holes_built"] = int(sim.stats.get("holes_built", 0)) + int(dir) * built


func _read_tile(c: Course, i: int) -> Dictionary:
	return {
		"terrain": int(c.terrain[i]),
		"object": int(c.objects[i]),
		"closed": int(c.closed[i]),
		"open_month": int(c.open_month[i]),
		"wet": c.wet[i],
		"health": c.health[i],
		"weeds": c.weeds[i],
		"pests": c.pests[i],
		"repair": int(c.repair[i]),
		"litter": c.litter[i],
	}


func _tile_same(a: Dictionary, b: Dictionary) -> bool:
	return int(a["terrain"]) == int(b["terrain"]) and int(a["object"]) == int(b["object"]) and int(a["closed"]) == int(b["closed"]) and int(a["open_month"]) == int(b["open_month"]) and int(a["repair"]) == int(b["repair"]) and is_equal_approx(float(a["wet"]), float(b["wet"])) and is_equal_approx(float(a["health"]), float(b["health"])) and is_equal_approx(float(a["weeds"]), float(b["weeds"])) and is_equal_approx(float(a["pests"]), float(b["pests"])) and is_equal_approx(float(a["litter"]), float(b["litter"]))


