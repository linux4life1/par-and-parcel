class_name CourseFile
extends RefCounted
## A course shared as a file, and the pro who travels to play it. The file is
## the ground and the holes only. Money, members and staff stay at home.


const KIND := "ppcourse"
const VERSION := 1


static func pack(sim: Sim) -> Dictionary:
	var course: Dictionary = sim.course_dict()
	var slim: Array = []
	for h in course.get("holes", []):
		if h is Dictionary:
			slim.append(_slim_hole(h))
	course["holes"] = slim
	return {
		"kind": KIND,
		"version": VERSION,
		"name": sim.course_name,
		"biome": str(sim.biome.get("id", "lush")),
		"course": course,
	}


static func text_of(sim: Sim) -> String:
	return JSON.stringify(pack(sim))


## Empty when the text is not a shared course. A saved game is refused, so a
## friend's bank balance cannot ride in with their holes.
static func parse(text: String) -> Dictionary:
	if not text.begins_with("{"):
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	if str(d.get("kind", "")) != KIND or int(d.get("version", 0)) != VERSION:
		return {}
	if not (d.get("course") is Dictionary):
		return {}
	var course: Dictionary = d.course
	if not _course_safe(course):
		return {}
	return d


## A course the game can build: a map no bigger than the ones it makes,
## a two-number clubhouse, and every layer the same size as a new course
## of that width and height. Locked and hot are checked only when the file
## carries them, and a locked layer without its hot layer is refused,
## because loading reads both. Closed and open_month are checked the same
## way when the file carries them: a bad byte string would break the load.
## Litter is one float per tile. Repair is one byte per tile. A shared
## course keeps both only when they are that size.
static func _course_safe(course: Dictionary) -> bool:
	var w := int(course.get("w", 0))
	var h := int(course.get("h", 0))
	var limit := _map_limit()
	if w < 2 or h < 2 or w > limit or h > limit:
		return false
	if not _holes_safe(course.get("holes", null), w, h):
		return false
	if not _two_numbers(course.get("clubhouse", null)):
		return false
	var tiles := w * h
	if not _bytes(course.get("heights", ""), (w + 1) * (h + 1) * 4):
		return false
	if not _kinds(course.get("terrain", ""), tiles, Defs.T_NAMES.size()):
		return false
	if not _kinds(course.get("objects", ""), tiles, Defs.O_NAMES.size()):
		return false
	for key in ["wet", "health", "weeds", "pests"]:
		if not _bytes(course.get(str(key), ""), tiles * 4):
			return false
	if course.has("locked"):
		if not course.has("hot") or not _bytes(course.get("locked", ""), tiles) or not _bytes(course.get("hot", ""), tiles):
			return false
	elif course.has("hot") and not _bytes(course.get("hot", ""), tiles):
		return false
	if course.has("mood") and not _bytes(course.get("mood", ""), tiles * 4):
		return false
	if course.has("closed") and not _bytes(course.get("closed", ""), tiles):
		return false
	if course.has("open_month") and not _bytes(course.get("open_month", ""), tiles):
		return false
	if course.has("litter") and not _bytes(course.get("litter", ""), tiles * 4):
		return false
	if course.has("repair") and not _bytes(course.get("repair", ""), tiles):
		return false
	if course.has("volcanoes"):
		var vols: Variant = course.get("volcanoes", [])
		if not (vols is Array):
			return false
		for item in vols:
			if not (item is Dictionary):
				return false
	return true


## The hole a shared file is allowed to keep. Awards, plays and earnings
## stay at the club that earned them.
static func _slim_hole(hd: Dictionary) -> Dictionary:
	return {
		"tee": hd.get("tee", []),
		"pin": hd.get("pin", []),
		"par": int(hd.get("par", 4)),
		"length": float(hd.get("length", 0.0)),
		"name": str(hd.get("name", "")),
		"open": bool(hd.get("open", true)),
		"gap": float(hd.get("gap", 0.0)),
	}


## Each hole needs a tee and a pin of three numbers, standing on the map.
## x runs across the width and z down the height. A missing tee, or a pin
## off the map, is refused rather than breaking the load.
static func _holes_safe(v: Variant, w: int, h: int) -> bool:
	if not (v is Array):
		return false
	var holes: Array = v
	var x_max := float(w) * Defs.TILE
	var z_max := float(h) * Defs.TILE
	for hole in holes:
		if not (hole is Dictionary):
			return false
		var hd: Dictionary = hole
		if not _spot(hd.get("tee", null), x_max, z_max):
			return false
		if not _spot(hd.get("pin", null), x_max, z_max):
			return false
	return true


static func _spot(v: Variant, x_max: float, z_max: float) -> bool:
	if not (v is Array):
		return false
	var p: Array = v
	if p.size() != 3:
		return false
	if not (_number(p[0]) and _number(p[1]) and _number(p[2])):
		return false
	var x := float(p[0])
	var z := float(p[2])
	return x >= 0.0 and x <= x_max and z >= 0.0 and z <= z_max


static func _two_numbers(v: Variant) -> bool:
	if not (v is Array):
		return false
	var pair: Array = v
	if pair.size() != 2:
		return false
	return _number(pair[0]) and _number(pair[1])


static func _number(v: Variant) -> bool:
	return v is int or v is float


static func _kinds(v: Variant, n: int, limit: int) -> bool:
	if not _bytes(v, n):
		return false
	var raw := Marshalls.base64_to_raw(str(v))
	for b in raw:
		if int(b) >= limit:
			return false
	return true


static func _bytes(v: Variant, n: int) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s := str(v)
	if s.length() > n * 2 + 8:
		return false
	return Marshalls.base64_to_raw(s).size() == n


## The widest map a scenario lays out. A shared course bigger than that
## is not one this game made.
static func _map_limit() -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios.json"))
	var limit := 0
	if parsed is Dictionary:
		for scen in parsed.get("scenarios", []):
			if scen is Dictionary:
				var map: Dictionary = scen.get("map", {})
				limit = maxi(limit, maxi(int(map.get("w", 0)), int(map.get("h", 0))))
	return limit


## A file name made of the course's name, with anything unsafe left out.
static func file_name(course_name: String) -> String:
	var out := ""
	for i in course_name.length():
		var ch := course_name.substr(i, 1)
		var ok := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == " " or ch == "-"
		if ok:
			out += ch
	out = out.strip_edges()
	if out == "":
		return "course"
	return out


## A new club on a friend's course. The purse is a new game's. The pro, the
## bag and the career come across in the career book, not from this file.
static func host(data: DataDB, pack: Dictionary, gear: Gear = null, seed_value: int = 0) -> Sim:
	var scen := DataDB.find(data.scenarios, "free_play")
	if scen.is_empty():
		scen = data.scenarios[0]
	var blank: Dictionary = scen.duplicate(true)
	blank["map"] = {"w": 8, "h": 8, "holes": 0}
	var biome := str(pack.get("biome", "lush"))
	var sim := Sim.new(data, blank, seed_value, gear, biome)
	var course_d: Dictionary = (pack.course as Dictionary).duplicate(true)
	course_d["green_decel"] = 1.0
	course_d["rough_power"] = 1.0
	var slim: Array = []
	for h in course_d.get("holes", []):
		if h is Dictionary:
			slim.append(_slim_hole(h))
	course_d["holes"] = slim
	sim.install_course(course_d)
	sim.course_name = str(pack.get("name", sim.course_name))
	sim.clubhouse_level = sim.level_for_holes(sim.course.holes.size())
	sim._update_rating(0.0)
	return sim
