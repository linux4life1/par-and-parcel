extends Node
## Prints a two year ledger for a lightly managed free-play course, to judge
## whether the economy is in a sensible place. Run with ./balance.sh

func _ready() -> void:
	var db := DataDB.new()
	var gear := Gear.new(db)
	var plans := ["one greenkeeper, a drink stand", "no staff at all", "two greenkeepers, exterminator, marshal, stand"]
	var months := 16.0
	if OS.get_cmdline_user_args().has("--quick"):
		plans = ["lean: one greenkeeper, one exterminator, stand"]
		months = 10.0
	for plan: String in plans:
		var sim := Sim.new(db, DataDB.find(db.scenarios, "three_holes"), 2024, gear)
		if plan.begins_with("one"):
			sim.hire("greenkeeper")
			_stand(sim)
		elif plan.begins_with("lean"):
			sim.hire("greenkeeper")
			sim.hire("exterminator")
			_stand(sim)
		elif plan.begins_with("two"):
			sim.hire("greenkeeper")
			sim.hire("greenkeeper")
			sim.hire("exterminator")
			sim.hire("marshal")
			_stand(sim)
		print("== ", plan)
		sim.month_ended.connect(func(label: String) -> void:
			var row: Dictionary = sim.economy.history[-1]
			var earned := 0.0
			var payers := 0
			for hole in sim.course.holes:
				earned += hole.earned
				payers += hole.payers
			print("  %-18s net %8s  fees %7s  bank %8s | rating %2d  happy %2d%%  condition %3d%%  weeds %2d%%  rounds %4d  hits %2d  a hole pays %s  unpaid %3d" % [
				label, Defs.money(float(row.net)), Defs.money(float(row.income.get("green_fees", 0.0))), Defs.money(sim.economy.money),
				int(sim.rating), int(sim.visitors.average_satisfaction()), int(sim.grounds.condition * 100.0), int(sim.grounds.weed_cover * 100.0),
				sim.stats.rounds, sim.stats.hits, Defs.money(earned / maxf(payers, 1.0)), sim.stats.refusals]))
		for i in int(months * 28.0 * Defs.DAY_SECONDS * 60.0) + 60:
			sim.step(1.0 / 60.0)
		print("  events: ", sim.events.history)
	get_tree().quit(0)


func _stand(sim: Sim) -> void:
	var hole := sim.course.holes[1]
	var t := sim.course.tile_of(hole.tee.x + 15.0, hole.tee.z + 15.0)
	sim.place_object(t.x, t.y, Defs.O.DRINK_STAND)
