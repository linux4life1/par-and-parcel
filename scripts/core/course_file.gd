class_name CourseFile
extends RefCounted
## A course shared as a file, and the pro who travels to play it. The file is
## the ground and the holes only. Money, members and staff stay at home.


const KIND := "ppcourse"
const VERSION := 1


static func pack(sim: Sim) -> Dictionary:
	return {
		"kind": KIND,
		"version": VERSION,
		"name": sim.course_name,
		"biome": str(sim.biome.get("id", "lush")),
		"course": sim.course_dict(),
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
	if int(course.get("w", 0)) < 2 or not (course.get("holes") is Array):
		return {}
	return d


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


## What travels with you: the career, the bag, the name and the kit.
static func pro_of(sim: Sim) -> Dictionary:
	var g := sim.player.golfer
	return {
		"name": g.name,
		"career": sim.career.to_dict(),
		"golfer_xp": int(sim.skills.xp.get("golfer", 0)),
		"golfer_level": int(sim.skills.level.get("golfer", 1)),
		"golfer_points": int(sim.skills.points.get("golfer", 0)),
		"player": sim.player.to_dict(),
		"shirt": g.shirt.to_html(true),
		"pants": g.pants.to_html(true),
		"hat": g.hat.to_html(true),
		"skin": g.skin.to_html(true),
	}


## A new club on a friend's course. The purse is a new game's, and your pro
## is the one in `pro`. An empty pro plays as a new golfer.
static func host(data: DataDB, pack: Dictionary, pro: Dictionary, gear: Gear = null) -> Sim:
	var scen := DataDB.find(data.scenarios, "free_play")
	if scen.is_empty():
		scen = data.scenarios[0]
	var blank: Dictionary = scen.duplicate(true)
	blank["map"] = {"w": 8, "h": 8, "holes": 0}
	var biome := str(pack.get("biome", "lush"))
	var sim := Sim.new(data, blank, 1, gear, biome)
	var course_d: Dictionary = pack.course
	sim.install_course(course_d)
	sim.course_name = str(pack.get("name", sim.course_name))
	sim.clubhouse_level = sim.level_for_holes(sim.course.holes.size())
	_apply_pro(sim, pro)
	sim._update_rating(0.0)
	return sim


static func _apply_pro(sim: Sim, pro: Dictionary) -> void:
	if pro.is_empty():
		return
	sim.skills.xp["golfer"] = int(pro.get("golfer_xp", sim.skills.xp.golfer))
	sim.skills.level["golfer"] = int(pro.get("golfer_level", sim.skills.level.golfer))
	sim.skills.points["golfer"] = int(pro.get("golfer_points", sim.skills.points.golfer))
	sim.career.from_dict(pro.get("career", {}))
	sim.player.from_dict(pro.get("player", {}))
	var g := sim.player.golfer
	g.name = str(pro.get("name", g.name))
	if str(pro.get("shirt", "")) != "":
		g.shirt = Color(str(pro.shirt))
	if str(pro.get("pants", "")) != "":
		g.pants = Color(str(pro.pants))
	if str(pro.get("hat", "")) != "":
		g.hat = Color(str(pro.hat))
	if str(pro.get("skin", "")) != "":
		g.skin = Color(str(pro.skin))
