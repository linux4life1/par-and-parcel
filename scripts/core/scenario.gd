class_name Scenario
extends RefCounted
## A challenge with goals and a deadline, or free play with neither.

var def: Dictionary = {}
var status := "active"     # active, won, lost, free


func _init(d: Dictionary) -> void:
	def = d
	if d.get("mode", "free") == "free" or d.get("goals", []).is_empty():
		status = "free"


func has_goals() -> bool:
	return not def.get("goals", []).is_empty()


func deadline_day() -> int:
	var dl: Dictionary = def.get("deadline", {})
	if dl.is_empty():
		return -1
	return (int(dl.year) - 1) * Defs.DAYS_PER_YEAR + int(dl.month) * Defs.DAYS_PER_MONTH


func deadline_text() -> String:
	var dl: Dictionary = def.get("deadline", {})
	if dl.is_empty():
		return "No deadline"
	return "By the end of %s, Year %d" % [Defs.MONTH_NAMES[int(dl.month) - 1], int(dl.year)]


func days_left(sim: Sim) -> int:
	var d := deadline_day()
	return -1 if d < 0 else maxi(0, d - sim.day())


## One entry per goal: its text, whether it is met, and where things stand.
func progress(sim: Sim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for goal: Dictionary in def.get("goals", []):
		var done := false
		var now := ""
		match str(goal.type):
			"holes":
				var n := sim.course.holes.size()
				done = n >= int(goal.value)
				now = "%d / %d" % [n, int(goal.value)]
			"rating":
				done = sim.rating >= float(goal.value)
				now = "%d / %d" % [int(sim.rating), int(goal.value)]
			"money":
				done = sim.economy.money >= float(goal.value)
				now = "%s / %s" % [Defs.money(sim.economy.money), Defs.money(float(goal.value))]
			"satisfaction":
				var s := sim.visitors.average_satisfaction()
				done = s >= float(goal.value)
				now = "%d%% / %d%%" % [int(s), int(goal.value)]
			"condition":
				var c := sim.grounds.condition * 100.0
				done = c >= float(goal.value)
				now = "%d%% / %d%%" % [int(c), int(goal.value)]
			"rounds":
				var r: int = sim.stats.rounds
				done = r >= int(goal.value)
				now = "%d / %d" % [r, int(goal.value)]
			"eruptions":
				var e := int(sim.stats.get("eruptions", 0))
				done = e >= int(goal.value)
				now = "%d / %d" % [e, int(goal.value)]
			"members":
				var m := sim.members.count()
				done = m >= int(goal.value)
				now = "%d / %d" % [m, int(goal.value)]
			"tournament":
				done = int(sim.tourney.hosted.get(str(goal.value), 0)) > 0
				now = "Hosted" if done else "Not yet"
		out.append({"text": str(goal.text), "done": done, "now": now})
	return out


func check(sim: Sim) -> void:
	if status != "active":
		return
	var all := true
	for p in progress(sim):
		if not p.done:
			all = false
			break
	if all:
		status = "won"
		sim.scenario_ended.emit(true)
	elif deadline_day() >= 0 and sim.day() >= deadline_day():
		status = "lost"
		sim.scenario_ended.emit(false)
