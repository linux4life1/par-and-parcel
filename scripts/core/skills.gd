class_name Skills
extends RefCounted
## The manager's skill tree, and the experience, levels and points of both
## the manager and your golfer. Your golfer's points are spent on attributes
## (see Career), whose effects arrive here through set_extra() so that
## everything reads bonuses from one place.

signal changed()
signal leveled(branch: String, level: int)

var db: DataDB
var unlocked := {}
var xp := {"manager": 0, "golfer": 0}
var level := {"manager": 1, "golfer": 1}
var points := {"manager": 1, "golfer": 1}
var _bonus := {}
var _extra := {}


func _init(data: DataDB) -> void:
	db = data


static func need(lvl: int) -> int:
	return int(12.0 * pow(lvl, 1.4)) + 8


func bonus(key: String) -> float:
	return _bonus.get(key, 0.0)


func mult(key: String) -> float:
	return maxf(0.0, 1.0 + bonus(key))


func has(id: String) -> bool:
	return unlocked.has(id)


func can_unlock(id: String) -> bool:
	var s := DataDB.find(db.skills, id)
	if s.is_empty() or unlocked.has(id):
		return false
	if int(points[s.branch]) < int(s.cost):
		return false
	for r: String in s.req:
		if not unlocked.has(r):
			return false
	return true


func unlock(id: String) -> bool:
	if not can_unlock(id):
		return false
	var s := DataDB.find(db.skills, id)
	points[s.branch] = int(points[s.branch]) - int(s.cost)
	unlocked[id] = true
	_rebuild()
	changed.emit()
	return true


func add_xp(branch: String, amount: int) -> void:
	xp[branch] = int(xp[branch]) + amount
	while int(xp[branch]) >= need(int(level[branch])):
		xp[branch] = int(xp[branch]) - need(int(level[branch]))
		level[branch] = int(level[branch]) + 1
		points[branch] = int(points[branch]) + 1
		leveled.emit(branch, int(level[branch]))
	changed.emit()


## Effects that come from somewhere other than the tree.
func set_extra(fx: Dictionary) -> void:
	_extra = fx
	_rebuild()
	changed.emit()


func _rebuild() -> void:
	_bonus = _extra.duplicate()
	for s: Dictionary in db.skills:
		if unlocked.has(s.id):
			var fx: Dictionary = s.fx
			for k: String in fx:
				_bonus[k] = float(_bonus.get(k, 0.0)) + float(fx[k])


func to_dict() -> Dictionary:
	return {"unlocked": unlocked.keys(), "xp": xp, "level": level, "points": points}


func from_dict(d: Dictionary) -> void:
	unlocked = {}
	for id: String in d.get("unlocked", []):
		unlocked[id] = true
	for b: String in ["manager", "golfer"]:
		xp[b] = int(d.get("xp", {}).get(b, 0))
		level[b] = int(d.get("level", {}).get(b, 1))
		points[b] = int(d.get("points", {}).get(b, 1))
	_rebuild()
