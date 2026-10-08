class_name UndoLog
extends RefCounted
## Build steps that can be taken back: a paint stroke, a raise or lower, an
## object placed or removed, a hole laid out. Only the tiles and corners a
## step changed are kept. The money is put back by the same amount, and
## putting the step back charges it again, so undo cannot be used to earn.

var sim: Sim
var depth := 30
var past: Array[Dictionary] = []
var future: Array[Dictionary] = []
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


## Drop every step. A loaded course has none of the history it was built with.
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
		"money": sim.economy.money,
		"expense": float(sim.economy.expense.get("construction", 0.0)),
		"tiles": {},
		"heights": {},
		"holes": sim.course.holes.size(),
		"gifts": _copy_gifts(sim.gifts),
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
	var money_moved := not is_equal_approx(sim.economy.money, float(_open["money"]))
	var gifts_now := _copy_gifts(sim.gifts)
	var gifts_moved := not _gifts_same(gifts_now, _open["gifts"])
	var built_now := int(sim.stats.get("holes_built", 0))
	var built_moved := built_now != int(_open["built"])
	if not any and not hole_added and not money_moved and not gifts_moved and not built_moved:
		_open = {}
		return
	var entry := {
		"tiles": tile_rec,
		"heights": height_rec,
		"before_money": float(_open["money"]),
		"after_money": sim.economy.money,
		"before_expense": float(_open["expense"]),
		"after_expense": float(sim.economy.expense.get("construction", 0.0)),
		"before_gifts": _open["gifts"],
		"after_gifts": gifts_now,
		"before_built": int(_open["built"]),
		"after_built": built_now,
		"before_holes": int(_open["holes"]),
	}
	if hole_added:
		entry["hole"] = _snap_hole(c.holes[c.holes.size() - 1])
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


func undo() -> bool:
	if _stroking or past.is_empty():
		return false
	var e: Dictionary = past[past.size() - 1]
	past.remove_at(past.size() - 1)
	_apply(e, false)
	future.append(e)
	return true


func redo() -> bool:
	if _stroking or future.is_empty():
		return false
	var e: Dictionary = future[future.size() - 1]
	future.remove_at(future.size() - 1)
	_apply(e, true)
	past.append(e)
	return true


func _apply(e: Dictionary, forward: bool) -> void:
	var c := sim.course
	var tiles: Dictionary = e["tiles"]
	var obj_changed := false
	var x0 := c.w
	var y0 := c.h
	var x1 := -1
	var y1 := -1
	var which := "after" if forward else "before"
	for key in tiles:
		var i := int(key)
		var rec: Dictionary = tiles[key]
		var side: Dictionary = rec[which]
		var prev := int(c.objects[i])
		var new_o := int(side["object"])
		var prev_closed := int(c.closed[i])
		c.terrain[i] = int(side["terrain"])
		c.objects[i] = new_o
		c.closed[i] = int(side["closed"])
		c.open_month[i] = int(side["open_month"])
		c.wet[i] = float(side["wet"])
		c.health[i] = float(side["health"])
		c.weeds[i] = float(side["weeds"])
		c.pests[i] = float(side["pests"])
		if prev != new_o or prev_closed != int(side["closed"]):
			obj_changed = true
			if prev != new_o:
				var lit := Defs.O_LIGHT[prev] > 0.0 or Defs.O_LIGHT[new_o] > 0.0
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
	var heights: Dictionary = e["heights"]
	var hw := c.w + 1
	var hx0 := hw
	var hy0 := c.h + 1
	var hx1 := -1
	var hy1 := -1
	for key in heights:
		var vi := int(key)
		var rec: Dictionary = heights[key]
		c.heights[vi] = float(rec[which])
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
			_drop_hole(int(e["before_holes"]))
	var mkey := "after_money" if forward else "before_money"
	var ekey := "after_expense" if forward else "before_expense"
	var gkey := "after_gifts" if forward else "before_gifts"
	var bkey := "after_built" if forward else "before_built"
	sim.economy.money = float(e[mkey])
	var cons := float(e[ekey])
	if cons <= 0.0:
		sim.economy.expense.erase("construction")
	else:
		sim.economy.expense["construction"] = cons
	sim.economy.changed.emit()
	var gifts: Dictionary = e[gkey]
	_restore_gifts(gifts)
	sim.stats["holes_built"] = int(e[bkey])
	if x1 >= 0 or hx1 >= 0 or e.has("hole"):
		c.revision += 1


func _drop_hole(before_holes: int) -> void:
	var n := sim.course.holes.size()
	if n > before_holes:
		sim.remove_hole(n - 1)


func _redo_hole(snap: Dictionary) -> void:
	var td: Array = snap["tee"]
	var pd: Array = snap["pin"]
	var tee := Vector3(float(td[0]), float(td[1]), float(td[2]))
	var pin := Vector3(float(pd[0]), float(pd[1]), float(pd[2]))
	var hole := sim.course.add_hole(tee, pin)
	hole.name = str(snap["name"])
	hole.open = bool(snap["open"])


func _snap_hole(h: Hole) -> Dictionary:
	return {
		"tee": [h.tee.x, h.tee.y, h.tee.z],
		"pin": [h.pin.x, h.pin.y, h.pin.z],
		"name": h.name,
		"par": h.par,
		"length": h.length,
		"open": h.open,
	}


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
	}


func _tile_same(a: Dictionary, b: Dictionary) -> bool:
	return int(a["terrain"]) == int(b["terrain"]) and int(a["object"]) == int(b["object"]) and int(a["closed"]) == int(b["closed"]) and int(a["open_month"]) == int(b["open_month"]) and is_equal_approx(float(a["wet"]), float(b["wet"])) and is_equal_approx(float(a["health"]), float(b["health"])) and is_equal_approx(float(a["weeds"]), float(b["weeds"])) and is_equal_approx(float(a["pests"]), float(b["pests"]))


func _copy_gifts(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[int(k)] = int(src[k])
	return out


func _gifts_same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if int(a[k]) != int(b.get(k, -999999)):
			return false
	return true


func _restore_gifts(src: Dictionary) -> void:
	sim.gifts.clear()
	for k in src:
		sim.gifts[int(k)] = int(src[k])
