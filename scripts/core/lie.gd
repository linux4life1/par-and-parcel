class_name Lie
extends RefCounted
## How the ball is sitting, and what that does to the next shot.
##
## The ground under the ball sets the terms (data/lies.json): rough takes
## spin off, sand makes a clean strike harder. On top of that a ball can sit
## up or sit down, be plugged where it landed, be wet, or lie on a slope.
## The computer golfers and the player both read the same lie.


## Read the lie for a shot heading this way. Returns
##   t       the terrain (Defs.T)
##   name    "Rough, sitting down"
##   sit     the id of the sit, or ""
##   power   share of the swing that reaches the ball, on top of the terrain's own
##   spread  multiplies how wild the shot is
##   spin    multiplies backspin
##   lift    multiplies the lift that holds the ball up
##   loft    radians added to the launch (uphill is positive)
##   side    sidespin added (positive curves right)
##   mishit  multiplies the odds of a fat, thin or shanked shot
##   notes   plain sentences for the player
static func read(sim: Sim, g: Golfer, heading: float) -> Dictionary:
	var course := sim.course
	var b := g.ball
	var t := maxi(course.terrain_at(b.pos.x, b.pos.z), 0)
	var notes: Array[String] = []
	var out := {"t": t, "name": sim.terrain_name(t), "sit": "", "power": 1.0, "spread": 1.0, "spin": 1.0,
		"lift": 1.0, "loft": 0.0, "side": 0.0, "mishit": 1.0, "notes": notes}
	if t == Defs.T.GREEN or t == Defs.T.WATER:
		return out
	var all: Dictionary = sim.db.lies.get("lies", {})
	var d: Dictionary = all.get(Defs.T_KEYS[t], {})
	out.spin = float(d.get("spin", 1.0))
	out.lift = float(d.get("lift", 1.0))
	out.mishit = float(d.get("mishit", 1.0))

	# how it is sitting
	var sit := {}
	var sits: Array = d.get("sits", [])
	if b.plugged:
		sit = DataDB.find(sits, "plugged")
	elif not g.teed:
		pass      # on the tee it sits on a peg
	else:
		var r := Ball._noise(b.pos * 0.71 + Vector3(3.3, 0.0, 7.7))
		for s: Dictionary in sits:
			var c := float(s.get("chance", 0.0))
			if r < c:
				sit = s
				break
			r -= c
	if not sit.is_empty():
		# knowing how to play out of trouble takes the sting out of a bad one
		var knack := 0.45 * g.imagination
		if t == Defs.T.BUNKER:
			knack = 1.0 - (1.0 - knack) * (1.0 - g.bonus_sand)
		elif t == Defs.T.ROUGH or t == Defs.T.DEEP_ROUGH:
			knack = 1.0 - (1.0 - knack) * (1.0 - g.bonus_rough)
		var p := float(sit.get("power", 1.0))
		out.power = p if p >= 1.0 else 1.0 - (1.0 - p) * (1.0 - knack)
		var sp := float(sit.get("spread", 1.0))
		out.spread = sp if sp <= 1.0 else 1.0 + (sp - 1.0) * (1.0 - knack)
		out.spin = float(out.spin) * float(sit.get("spin", 1.0))
		out.lift = float(out.lift) * float(sit.get("lift", 1.0))
		out.mishit = float(out.mishit) * float(sit.get("mishit", 1.0))
		out.sit = str(sit.get("id", ""))
		out.name = "%s, %s" % [out.name, str(sit.get("name", ""))]
		if sit.has("note"):
			notes.append(str(sit.note))

	# wet grass between the club and the ball
	var ti := course.index_at(b.pos.x, b.pos.z)
	if ti >= 0:
		var wet: Dictionary = sim.db.lies.get("wet", {})
		var from := float(wet.get("from", 0.45))
		var wetv := course.wet[ti] * b.m_wet
		if wetv > from:
			out.spin = float(out.spin) * lerpf(1.0, float(wet.get("spin", 0.6)), clampf((wetv - from) / (1.0 - from), 0.0, 1.0))
			notes.append("Wet. Less spin, and it will stop where it lands.")

	# a sloping stance
	if t != Defs.T.TEE:
		var sl: Dictionary = sim.db.lies.get("slope", {})
		var grad := course.gradient_at(b.pos.x, b.pos.z)
		var dir := Vector2(cos(heading), sin(heading))
		var up := grad.dot(dir)                              # positive climbs along the line
		var right := grad.dot(Vector2(-dir.y, dir.x))        # positive rises to the right of it
		var flat := float(sl.get("flat", 0.035))
		var lm := float(sl.get("loft_max", 0.12))
		var cm := float(sl.get("curve_max", 0.05))
		if absf(up) > flat:
			out.loft = clampf(atan(up) * float(sl.get("loft", 0.7)), -lm, lm)
			notes.append("Uphill lie. It flies higher and lands short." if up > 0.0 else "Downhill lie. It flies lower and runs.")
		if absf(right) > flat:
			# a golfer stands to the left of the line: ground rising to the
			# right puts the ball above their feet, and that shot draws
			out.side = clampf(-right * float(sl.get("curve", 0.4)), -cm, cm)
			notes.append("Ball above your feet. It will draw left." if right > 0.0 else "Ball below your feet. It will fade right.")
	return out


## Fold a lie into a shot shape (see ShotAI.predict for the keys).
static func blend(lie: Dictionary, shape: Dictionary = {}) -> Dictionary:
	var out := shape.duplicate()
	out["lift"] = float(shape.get("lift", 1.0)) * float(lie.get("lift", 1.0))
	out["side"] = float(shape.get("side", 0.0)) + float(lie.get("side", 0.0))
	out["loft_add"] = float(shape.get("loft_add", 0.0)) + float(lie.get("loft", 0.0))
	out["spin_mul"] = float(shape.get("spin_mul", 1.0)) * float(lie.get("spin", 1.0))
	return out


## One line for the play panel: the lie and what to expect from it.
static func text(lie: Dictionary) -> String:
	var notes: Array = lie.get("notes", [])
	if notes.is_empty():
		return ""
	return " ".join(PackedStringArray(notes))
