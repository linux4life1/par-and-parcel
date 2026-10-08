class_name CareerBook
extends RefCounted
## What follows the owner from one course to the next: the bank, the pro,
## and the album of aces and wins. A debt stays behind. The new course
## still starts with its own purse.


static func pack(sim: Sim) -> Dictionary:
	return {
		"money": sim.economy.money,
		"career": sim.career.to_dict(),
		"player": sim.player.to_dict(),
		"skills": sim.skills.to_dict(),
		"album": sim.album.duplicate(true),
	}


static func apply(sim: Sim, d: Dictionary) -> void:
	if d.is_empty():
		return
	var carried := float(d.get("money", 0.0))
	if carried > 0.0:
		sim.economy.money += carried
	var skills: Dictionary = d.get("skills", {})
	if not skills.is_empty():
		sim.skills.from_dict(skills)
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
