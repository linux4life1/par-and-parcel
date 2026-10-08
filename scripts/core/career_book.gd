class_name CareerBook
extends RefCounted
## What follows the owner from one course to the next: the profit, the pro,
## the golfer's experience, and the album of aces and wins. The manager's
## perks stay behind. Only what was earned above the club's
## opening purse travels, and a club's bank is taken once. A debt stays
## behind. The new course still starts with its own purse.


static func pack(sim: Sim, previous: Dictionary = {}) -> Dictionary:
	var profit := maxf(sim.economy.money - sim.opening_money, 0.0)
	var taken: Array = []
	var prev_taken: Variant = previous.get("taken", [])
	if prev_taken is Array:
		taken = (prev_taken as Array).duplicate()
	var from_id := sim.club_id
	for id in taken:
		if str(id) == from_id:
			profit = 0.0
			break
	return {
		"money": profit,
		"from": from_id,
		"taken": taken,
		"career": sim.career.to_dict(),
		"player": sim.player.to_dict(),
		"golfer_xp": int(sim.skills.xp.golfer),
		"golfer_level": int(sim.skills.level.golfer),
		"golfer_points": int(sim.skills.points.golfer),
		"album": sim.album.duplicate(true),
	}


## Puts the book onto the new club. The dictionary it returns is the book
## with this take recorded, so the same club cannot pay its bank again.
static func apply(sim: Sim, d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	if d.is_empty():
		return out
	var from_id := str(d.get("from", ""))
	var taken: Array = []
	var listed: Variant = out.get("taken", [])
	if listed is Array:
		taken = listed
	var already := false
	if from_id != "":
		for id in taken:
			if str(id) == from_id:
				already = true
				break
	var carried := float(d.get("money", 0.0))
	if already:
		out["money"] = 0.0
	elif carried > 0.0:
		sim.economy.money += carried
		if from_id != "":
			taken.append(from_id)
		out["taken"] = taken
		out["money"] = 0.0
		out["from"] = ""
	if d.has("golfer_xp"):
		sim.skills.xp["golfer"] = int(d.golfer_xp)
	if d.has("golfer_level"):
		sim.skills.level["golfer"] = int(d.golfer_level)
	if d.has("golfer_points"):
		sim.skills.points["golfer"] = int(d.golfer_points)
	var career: Dictionary = d.get("career", {})
	if not career.is_empty():
		sim.career.from_dict(career)
	var player: Dictionary = d.get("player", {})
	if not player.is_empty():
		sim.player.from_dict(player)
	sim.album = []
	for page in d.get("album", []):
		if page is Dictionary:
			sim.album.append(page.duplicate(true))
	return out
