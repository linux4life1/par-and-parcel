class_name Accomplishments
extends RefCounted
## Career milestones. Each one earned is worth a skill point for the manager
## and one for your golfer.

signal earned(a: Dictionary)

var sim: Sim
var done := {}


func _init(s: Sim) -> void:
	sim = s


func count() -> int:
	return done.size()


func has(id: String) -> bool:
	return done.has(id)


## Checked once a day.
func check() -> void:
	for a: Dictionary in sim.db.accomplishments:
		var id := str(a.id)
		if done.has(id) or not _met(a):
			continue
		done[id] = sim.day()
		sim.skills.points.manager = int(sim.skills.points.manager) + 1
		sim.skills.points.golfer = int(sim.skills.points.golfer) + 1
		sim.skills.changed.emit()
		sim.toast.emit("Accomplishment: %s. You earn a skill point for the manager and one for your golfer." % str(a.name), "good")
		earned.emit(a)


func _met(a: Dictionary) -> bool:
	var course := sim.course
	match str(a.type):
		"built":
			return int(sim.stats.get("holes_built", 0)) >= int(a.value)
		"holes":
			return course.holes.size() >= int(a.value)
		"kind":
			for hole in course.holes:
				if hole.lab_ready and hole.kind == int(a.value):
					return true
			return false
		"award":
			for hole in course.holes:
				if hole.award == str(a.value) or (str(a.value) == "top100" and hole.award == "top18"):
					return true
			return false
		"rating":
			return sim.rating >= float(a.value)
		"hosted_any":
			return not sim.tourney.hosted.is_empty()
		"hosted":
			return int(sim.tourney.hosted.get(str(a.value), 0)) > 0
		"stat":
			return int(sim.stats.get(str(a.stat), 0)) >= int(a.value)
		"members":
			return sim.members.joined_total >= int(a.value)
		"tier":
			return sim.members.count_at_least(int(a.value)) > 0
		"money":
			return sim.economy.money >= float(a.value)
		"rank":
			return sim.best_rank > 0 and sim.best_rank <= int(a.value)
	return false
