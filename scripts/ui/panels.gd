class_name Panels
extends RefCounted
## Builds the contents of the side panel. Each builder fills the panel once
## and returns a function that keeps its numbers up to date.

const TITLES := {
	"build": "Build", "holes": "Holes and Green Fees", "staff": "Staff", "money": "Finances",
	"tournaments": "Tournaments", "skills": "Manager Skills", "golfer": "My Golfer", "shop": "Pro Shop", "goals": "Goals and Records",
	"members": "Club Members",
	"feed": "Birdie Feed", "play": "Play a Round",
}
## What a Build button says when the mouse rests on it, for the things that
## need a word of explanation.
const OBJECT_TIPS := {
	Defs.O.VENDING: "Cans and snacks at the push of a button. Cheap to run, open all night, and nobody raves about it. Golfers use it when no stand is near.",
	Defs.O.BAR: "Drinkers tip well and forgive a lot, but they play slowly, spray the ball and lose their tempers faster. A gamble, and the house takes $14 a round.",
}

var hud: Hud
var _skill_branch := "manager"
var _skill_pick := ""
var _shop_cat := "woods"
var feed_tab := "posts"         # the Feed panel shows posts or the long stories


func _init(h: Hud) -> void:
	hud = h


func title(panel: String) -> String:
	return TITLES.get(panel, panel.capitalize())


func build(panel: String, body: VBoxContainer) -> Callable:
	match panel:
		"build":
			return _build(body)
		"holes":
			return _holes(body)
		"staff":
			return _staff(body)
		"money":
			return _money(body)
		"tournaments":
			return _tournaments(body)
		"skills":
			return _skills(body)
		"golfer":
			return _golfer(body)
		"shop":
			return _shop(body)
		"goals":
			return _goals(body)
		"feed":
			return _feed(body)
		"members":
			return _members(body)
		"play":
			return _play(body)
	return Callable()


func _wide(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


# ------------------------------------------------------------------ build

func _build(body: VBoxContainer) -> Callable:
	var tools := hud.tools
	var toggles: Array = []      # [button, mode, value]
	body.add_child(UIKit.heading("Terrain"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for t: int in [Defs.T.FAIRWAY, Defs.T.FIRM, Defs.T.GREEN, Defs.T.FAST_GREEN, Defs.T.TEE, Defs.T.BUNKER, Defs.T.WATER, Defs.T.ROUGH, Defs.T.DEEP_ROUGH, Defs.T.PATH]:
		var b := UIKit.button("%s   %s" % [hud.sim.terrain_name(t), Defs.money(Defs.T_COST[t])], func() -> void:
			tools.terrain_type = t
			tools.set_mode("terrain"))
		b.toggle_mode = true
		_wide(b)
		grid.add_child(b)
		toggles.append([b, "terrain", t])
	var bh := UIKit.hbox(6)
	body.add_child(bh)
	bh.add_child(UIKit.label("Brush", 14, UIKit.MUTED))
	var sizes := [[0, "Small"], [1, "Medium"], [2, "Large"], [4, "Huge"]]
	for s: Array in sizes:
		var r: int = s[0]
		var b := UIKit.button(str(s[1]), func() -> void:
			tools.brush = r
			tools.tool_changed.emit())
		b.toggle_mode = true
		bh.add_child(b)
		toggles.append([b, "brush", r])

	body.add_child(UIKit.gap(4))
	body.add_child(UIKit.heading("Shape the land"))
	var sh := UIKit.hbox(6)
	body.add_child(sh)
	for m: Array in [["raise", "Raise"], ["lower", "Lower"], ["smooth", "Smooth"], ["flatten", "Level"]]:
		var id := str(m[0])
		var b := UIKit.button(str(m[1]), func() -> void:
			tools.sculpt_mode = id
			tools.set_mode("sculpt"))
		b.toggle_mode = true
		_wide(b)
		sh.add_child(b)
		toggles.append([b, "sculpt", id])
	body.add_child(UIKit.para("Slopes change how every ball bounces and rolls. Tilt a green and putts will break. Hollows hold rainwater.", 13))

	var groups := [
		["Scenery", [Defs.O.OAK, Defs.O.PINE, Defs.O.BUSH, Defs.O.BOULDER, Defs.O.FLOWERS, Defs.O.FOUNTAIN, Defs.O.LANDMARK],
			"Scenery makes holes prettier, and golfers notice. Trees and boulders also knock down wayward shots."],
		["On the course", [Defs.O.BENCH, Defs.O.BALL_WASHER, Defs.O.DRINK_STAND, Defs.O.VENDING, Defs.O.SNACK_BAR, Defs.O.BAR, Defs.O.RESTROOM, Defs.O.BRIDGE],
			"Golfers get thirsty, hungry and tired, and sooner or later need a restroom. Put these where they pass between holes. Benches and ball washers belong beside tees. Bridges carry golfers over the hazard. A vending machine is the cheap answer to thirst and hunger both. A bar is a gamble: drinkers tip well and forgive a lot, but they play slowly, spray the ball and lose their tempers faster."],
		["Lighting", [Defs.O.FLOODLIGHT, Defs.O.LAMP],
			"Golfers play on after dark, but on an unlit hole they see poorly, enjoy it less and pay less, and few new golfers turn up at night. Light a hole from tee to green and it plays as well as by day. A floodlight lights a wide circle, shown as you place it. Lamp posts light paths and odd corners. Holes shows how much of each hole is lit."],
		["Club facilities", [Defs.O.PUTTING_GREEN, Defs.O.DRIVING_RANGE, Defs.O.CART_BARN, Defs.O.HOME_SITE],
			"A putting green helps putting and a driving range adds length. A member who plays keeps a little of that, so regulars get longer and better on the greens the more they come. A cart barn rents carts that fly along cart paths. Home sites are lots that Silver members and above will buy: they are worth more with a view and less in the line of fire."],
		["Resort", [Defs.O.TENNIS, Defs.O.MARINA, Defs.O.HOTEL, Defs.O.AIRSTRIP],
			"Big investments that lift the whole club. Tennis courts put every arrival in a good mood. A marina raises home values and draws celebrities. A hotel brings more golfers and keeps them fresh. An airstrip brings the kind who pay more for every hole."],
	]
	var object_buttons: Array = []
	var bz: Button = null
	for grp: Array in groups:
		body.add_child(UIKit.gap(4))
		body.add_child(UIKit.heading(str(grp[0])))
		var og := GridContainer.new()
		og.columns = 2
		og.add_theme_constant_override("h_separation", 6)
		og.add_theme_constant_override("v_separation", 6)
		body.add_child(og)
		for o: int in grp[1]:
			var b := UIKit.button("%s   %s" % [hud.sim.object_name(o), Defs.money(Defs.O_COST[o])], func() -> void:
				tools.object_type = o
				tools.set_mode("object"))
			b.toggle_mode = true
			b.add_theme_font_size_override("font_size", 14)
			if OBJECT_TIPS.has(o):
				b.tooltip_text = str(OBJECT_TIPS[o])
			_wide(b)
			og.add_child(b)
			toggles.append([b, "object", o])
			object_buttons.append([b, o])
		if bz == null:
			bz = UIKit.button("Bulldoze", func() -> void: tools.set_mode("bulldoze"))
			bz.toggle_mode = true
			_wide(bz)
			og.add_child(bz)
			toggles.append([bz, "bulldoze", 0])
		body.add_child(UIKit.para(str(grp[2]), 13))

	body.add_child(UIKit.gap(4))
	body.add_child(UIKit.heading("Clubhouse"))
	var club_now := UIKit.para("", 13)
	body.add_child(club_now)
	var needs_box := UIKit.vbox(2)
	body.add_child(needs_box)
	var need_lines: Array[Label] = []
	for k in 4:
		var nl := UIKit.label("", 13)
		nl.visible = false
		needs_box.add_child(nl)
		need_lines.append(nl)
	var club := UIKit.button("", func() -> void:
		if not hud.sim.upgrade_clubhouse():
			hud.sim.toast.emit("The club is not ready for that yet.", "bad"))
	body.add_child(club)
	body.add_child(UIKit.para("Each step up the ladder lets the club lay out more holes. A better clubhouse also sells more in the pro shop, lifts every arrival's mood, impresses members who care about prestige, and makes room for more members.", 13))

	body.add_child(UIKit.gap(4))
	body.add_child(UIKit.heading("Land"))
	var land := UIKit.button("Buy land", func() -> void: tools.set_mode("land"))
	land.toggle_mode = true
	body.add_child(land)
	toggles.append([land, "land", 0])
	var land_note := UIKit.para("", 13)
	body.add_child(land_note)

	body.add_child(UIKit.gap(4))
	body.add_child(UIKit.heading("Holes"))
	var nh := UIKit.button("Lay out a new hole   $250", func() -> void: tools.set_mode("hole"))
	nh.toggle_mode = true
	body.add_child(nh)
	toggles.append([nh, "hole", 0])
	var hole_note := UIKit.para("Paint a green first. Then click where the tee goes, and click the green to plant the pin. Par is set by the length.", 13)
	body.add_child(hole_note)

	return func() -> void:
		for tg: Array in toggles:
			var b: Button = tg[0]
			var on := false
			match str(tg[1]):
				"terrain":
					on = tools.mode == "terrain" and tools.terrain_type == int(tg[2])
				"brush":
					on = tools.brush == int(tg[2])
				"sculpt":
					on = tools.mode == "sculpt" and tools.sculpt_mode == str(tg[2])
				"object":
					on = tools.mode == "object" and tools.object_type == int(tg[2])
				"bulldoze":
					on = tools.mode == "bulldoze"
				"hole":
					on = tools.mode == "hole"
				"land":
					on = tools.mode == "land"
			b.set_pressed_no_signal(on)
		for ob: Array in object_buttons:
			var ob_btn: Button = ob[0]
			var ob_o: int = ob[1]
			var why := hud.sim.build_block(ob_o)
			var owed := int(hud.sim.gifts.get(ob_o, 0))
			ob_btn.disabled = why != ""
			if owed > 0:
				ob_btn.text = "%s   FREE x%d" % [hud.sim.object_name(ob_o), owed]
			elif why != "":
				ob_btn.text = "%s   %s" % [hud.sim.object_name(ob_o), why]
			else:
				ob_btn.text = "%s   %s" % [hud.sim.object_name(ob_o), Defs.money(Defs.O_COST[ob_o])]
		var sim := hud.sim
		var cap := sim.hole_cap()
		var n_holes := sim.course.holes.size()
		club_now.text = "%s: %d of %d holes." % [sim.clubhouse_name(), n_holes, cap]
		if sim.open_build():
			club_now.text = "%s. Build what you like: nothing is gated in the sandbox." % sim.clubhouse_name()
		var needs := sim.clubhouse_needs()
		for k in need_lines.size():
			var nl := need_lines[k]
			nl.visible = k < needs.size()
			if k < needs.size():
				var nd := needs[k]
				var have := Defs.money(float(nd.have)) if str(nd.what) == "cash" else str(int(float(nd.have)))
				nl.text = "%s  %s  (%s now)" % ["\u2713" if bool(nd.met) else "\u25cb", str(nd.text), have]
				nl.add_theme_color_override("font_color", UIKit.GOOD if bool(nd.met) else UIKit.MUTED)
		if sim.clubhouse_top():
			club.text = "%s: the best there is" % sim.clubhouse_name()
			club.disabled = true
		else:
			var nxt := sim.clubhouse_def(sim.clubhouse_level + 1)
			club.text = "Upgrade to %s   %s" % [str(nxt.get("name", "")).to_lower(), Defs.money(float(nxt.get("cost", 0.0)))]
			club.disabled = not sim.can_upgrade_clubhouse()
			club.tooltip_text = str(nxt.get("blurb", ""))
		if n_holes >= cap and not sim.open_build():
			nh.disabled = true
			nh.text = "Lay out a new hole   %d of %d" % [n_holes, cap]
			hole_note.text = "The %s allows %d holes. Upgrade the clubhouse (above) to lay out more." % [sim.clubhouse_name().to_lower(), cap]
		else:
			nh.disabled = false
			nh.text = "Lay out a new hole   $250   (%d of %d)" % [n_holes, cap]
			hole_note.text = "Paint a green first. Then click where the tee goes, and click the green to plant the pin. Par is set by the length."
		if hud.sim.land_credits > 0:
			land.text = "Claim land   %d free parcel%s" % [hud.sim.land_credits, "" if hud.sim.land_credits == 1 else "s"]
		else:
			land.text = "Buy land   %s a parcel" % Defs.money(hud.sim.land_price())
		land_note.text = "You own %d parcels. Greyed-out land is not yours: nothing can be built there, and a ball that lands on it is out of bounds." % hud.sim.course.owned_parcels()


# ------------------------------------------------------------------ holes

const COMMENT_WORDS := {
	"scenery": "the scenery", "bare": "it being bare", "score": "scoring well", "shot": "hitting good shots", "suits": "how it suits their game",
	"hard": "how hard it is", "water": "balls lost in the hazard", "bunker": "the bunkers", "rough": "the rough", "oob": "going out of bounds",
	"wait": "waiting", "weeds": "weeds", "pests": "pest damage", "wet": "wet ground",
	"greens": "the greens", "greens_bad": "poor greens", "hit": "being hit by balls", "eruption": "the volcano", "tired": "the walk",
	"amenity": "the facilities", "rest": "the bench", "prestige": "its reputation", "story": "the company", "putt": "missed putts",
	"easy": "it being too easy",
	"dark": "unlit holes", "night": "golf under the lights", "drink": "the drinks", "snack": "the food",
	"rain": "the rain", "storm": "the storms", "celebrity": "seeing a celebrity",
	"thirst": "nowhere to drink", "hungry": "nothing to eat", "restroom": "no restroom",
}


func _hole_report(hole: Hole) -> String:
	var best := ""
	var best_v := 1.5
	var worst := ""
	var worst_v := -1.5
	for tag: String in hole.comments:
		var v := float(hole.comments[tag])
		if not COMMENT_WORDS.has(tag):
			continue
		if v > best_v:
			best_v = v
			best = tag
		if v < worst_v:
			worst_v = v
			worst = tag
	var out := ""
	if best != "":
		out += "Golfers like %s." % COMMENT_WORDS[best]
	if worst != "":
		out += (" " if out != "" else "") + "They complain about %s." % COMMENT_WORDS[worst]
	var tip := _design_tip(hole, worst)
	if tip != "":
		out += (" " if out != "" else "") + tip
	return out


## A word from the course designer: what would make this hole better, from
## what the test golfers found and what the paying ones say. The original
## game's designer tips, in spirit.
func _design_tip(hole: Hole, worst: String) -> String:
	var sim := hud.sim
	if not hole.lab_ready or hole.plays < 3:
		return ""
	if worst == "easy":
		return "Designer's tip: the better golfers are bored. A bunker where the drives land, or water short of the green, would make it a test."
	if hole.fun >= 72.0:
		return "Designer's tip: they love it. Leave it be."
	var scenery := sim.scenery_score(hole)
	var gap := 0.0
	if not hole.expect.is_empty():
		gap = float(hole.expect.beginner) - float(hole.expect.expert)
	if hole.kind == 0 and hole.fun < 62.0:
		return "Designer's tip: nothing here asks a question. A bunker where the drives land, or water short of the green, would make it a test, and golfers pay more for a test they enjoy."
	if hole.fun < 50.0 and (worst == "water" or worst == "bunker" or worst == "hard"):
		return "Designer's tip: it punishes more than it tests. Widen the landing area or move the hazard out of the line a long drive takes."
	if hole.fun < 50.0 and worst == "rough":
		return "Designer's tip: too much rough along the way. Mow a wider fairway, or give the rough a path round it."
	if scenery < 0.25 and hole.fun < 65.0:
		return "Designer's tip: a bare hole. Trees, flower beds and water along it lift the mood, and the fee with it."
	if gap < 0.7 and hole.par >= 4:
		return "Designer's tip: everyone scores the same here. A risk-and-reward line, a short cut over trouble for the brave, would separate the field."
	if hole.par == 3 and hole.length > 200.0 and hole.fun < 60.0:
		return "Designer's tip: a long par three wears people down. Shorten it, or give the green room to run a ball onto."
	return ""


func _holes(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	body.add_child(UIKit.para("You don't set green fees. Golfers pay as they walk off each green, and how much depends on how much they enjoyed the hole. Build holes people love, keep them in good shape, and they pay more. A hole you lay out starts closed. Test plays it with the lab golfers and marks their tee shots; Open lets the public on."))
	var top := UIKit.hbox()
	body.add_child(top)
	var takings := UIKit.label("", 14, UIKit.MUTED)
	top.add_child(takings)
	top.add_child(UIKit.spacer())
	var at_cap := sim.course.holes.size() >= sim.hole_cap() and not sim.open_build()
	var new_btn := UIKit.button("New hole" if not at_cap else "New hole (%d of %d)" % [sim.course.holes.size(), sim.hole_cap()], func() -> void:
		hud.open_dock("build")
		hud.tools.set_mode("hole"))
	new_btn.disabled = at_cap
	top.add_child(new_btn)
	if at_cap:
		body.add_child(UIKit.para("The %s allows %d holes. Upgrade the clubhouse in Build to lay out more." % [sim.clubhouse_name().to_lower(), sim.hole_cap()], 13, UIKit.WARN))
	var card_box := UIKit.vbox(2)
	body.add_child(card_box)
	var rows: Array = []
	var count := sim.course.holes.size()
	var order := ""
	for hole in sim.course.holes:
		order += hole.name
	if count == 0:
		body.add_child(UIKit.para("No holes yet. Open Build, paint a green, then lay out a hole.", 15, UIKit.WARN))
	for i in count:
		var hole := sim.course.holes[i]
		var card := UIKit.card()
		body.add_child(card)
		var cv := UIKit.vbox(4)
		card.add_child(cv)
		var h := UIKit.hbox(6)
		cv.add_child(h)
		var num := UIKit.label(str(i + 1), 24, UIKit.ACCENT)
		num.custom_minimum_size = Vector2(26, 0)
		h.add_child(num)
		var name_edit := LineEdit.new()
		name_edit.text = hole.name
		name_edit.custom_minimum_size = Vector2(130, 0)
		name_edit.tooltip_text = "Rename this hole"
		name_edit.text_changed.connect(func(t: String) -> void: hole.name = t)
		name_edit.text_submitted.connect(func(_t: String) -> void: name_edit.release_focus())
		h.add_child(name_edit)
		h.add_child(UIKit.spacer())
		var paid := UIKit.label("", 15, UIKit.GOOD)
		paid.mouse_filter = Control.MOUSE_FILTER_STOP
		paid.tooltip_text = "What golfers pay for this hole on average. They decide, by how much they enjoyed it."
		h.add_child(paid)
		var h2 := UIKit.hbox(6)
		cv.add_child(h2)
		var kind := UIKit.label("", 14, UIKit.GOLD)
		kind.mouse_filter = Control.MOUSE_FILTER_STOP
		h2.add_child(kind)
		h2.add_child(UIKit.label("Par %d  ·  %d yd" % [hole.par, Defs.yards(hole.length)], 14))
		h2.add_child(UIKit.spacer())
		var up := UIKit.button("Up", func() -> void:
			sim.move_hole(i, -1)
			hud.rebuild_dock(), "Play this hole earlier in the round")
		up.disabled = i == 0
		up.add_theme_font_size_override("font_size", 12)
		h2.add_child(up)
		var down := UIKit.button("Down", func() -> void:
			sim.move_hole(i, 1)
			hud.rebuild_dock(), "Play this hole later in the round")
		down.disabled = i == count - 1
		down.add_theme_font_size_override("font_size", 12)
		h2.add_child(down)
		var view := UIKit.button("View", func() -> void:
			hud.rig.center_on(hole.point_along(0.5, sim.course), clampf(hole.length * 1.1, 80.0, 500.0)), "Move the camera to this hole")
		view.add_theme_font_size_override("font_size", 12)
		h2.add_child(view)
		if not hole.open:
			var draft_row := UIKit.hbox(6)
			cv.add_child(draft_row)
			var test_btn := UIKit.button("Test", func() -> void:
				sim.lab.rate_now(hole)
				hud.rebuild_dock(), "Play the hole now with test golfers, and mark where their tee shots land")
			test_btn.add_theme_font_size_override("font_size", 12)
			draft_row.add_child(test_btn)
			var open_btn := UIKit.button("Open", func() -> void:
				sim.course.set_open(hole, true)
				hud.rebuild_dock(), "Let paying golfers onto this hole")
			open_btn.add_theme_font_size_override("font_size", 12)
			draft_row.add_child(open_btn)
		var close := UIKit.button("X", func() -> void:
			hud.show_dialog("Close hole %d?" % (i + 1), "The tee and pin are removed. The grass stays. Golfers on the hole move on.", [
				["Keep it", Callable()],
				["Close the hole", func() -> void:
					sim.remove_hole(i)
					hud.rebuild_dock()],
			], false), "Remove this hole")
		close.add_theme_font_size_override("font_size", 12)
		h2.add_child(close)
		var gap_row := UIKit.hbox(6)
		cv.add_child(gap_row)
		gap_row.add_child(UIKit.label("Starter", 12, UIKit.MUTED))
		gap_row.add_child(UIKit.label(sim.starter_text(hole), 12))
		var gap_less := UIKit.button("-", func() -> void:
			sim.nudge_gap(hole, -1)
			hud.rebuild_dock(), "Send the next party out sooner")
		gap_less.add_theme_font_size_override("font_size", 12)
		gap_less.disabled = hole.gap <= 0.0
		gap_row.add_child(gap_less)
		var gap_more := UIKit.button("+", func() -> void:
			sim.nudge_gap(hole, 1)
			hud.rebuild_dock(), "Hold the next party longer, so the hole ahead can clear. Waiting still wears on them.")
		gap_more.add_theme_font_size_override("font_size", 12)
		gap_more.disabled = hole.gap >= sim.starter_max()
		gap_row.add_child(gap_more)
		# what the hole tests
		var tests := UIKit.hbox(6)
		cv.add_child(tests)
		var bars: Array[ProgressBar] = []
		for nm: String in ["Length", "Accuracy", "Imagination"]:
			tests.add_child(UIKit.label(nm, 11, UIKit.MUTED))
			var b := UIKit.bar(0.0, UIKit.BLUE, 6)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tests.add_child(b)
			bars.append(b)
		var st := UIKit.para("", 12)
		cv.add_child(st)
		var report := UIKit.para("", 12, UIKit.TEXT)
		cv.add_child(report)
		rows.append([kind, bars, st, report, paid])
	var card_plays := -1
	return func() -> void:
		var now := ""
		for hole in sim.course.holes:
			now += hole.name
		if sim.course.holes.size() != count:
			hud.rebuild_dock()
			return
		var total_plays := 0
		for hole in sim.course.holes:
			total_plays += hole.plays
		if total_plays != card_plays:
			card_plays = total_plays
			_scorecard(card_box)
		var round_total := 0.0
		var rated := 0
		for hole in sim.course.holes:
			if hole.payers > 0:
				round_total += hole.average_paid()
				rated += 1
		if rated == 0:
			takings.text = "No green fees paid yet"
		else:
			takings.text = "A full round earns about %s a golfer" % Defs.money(round_total / rated * count)
		for i in count:
			var hole := sim.course.holes[i]
			var row: Array = rows[i]
			var kind: Label = row[0]
			var bars: Array = row[1]
			if not hole.open and not hole.lab_ready:
				kind.text = "Draft"
				kind.tooltip_text = "The public cannot play this yet. Test it, then open it."
			elif hole.lab_ready:
				var honour := ""
				if hole.award == "top100":
					honour = "  ·  Top 100"
				elif hole.award == "top18":
					honour = "  ·  Dream Eighteen"
				for tid in hole.themes:
					honour += "  ·  " + sim.theme_name(tid)
				kind.text = ("Draft  ·  " if not hole.open else "") + HoleLab.type_name(hole.kind) + honour
				kind.tooltip_text = HoleLab.type_blurb(hole.kind)
				(bars[0] as ProgressBar).value = clampf(hole.test_length / 1.5, 0.0, 1.0)
				(bars[1] as ProgressBar).value = clampf(hole.test_accuracy / 1.5, 0.0, 1.0)
				(bars[2] as ProgressBar).value = clampf(hole.test_imagination / 1.5, 0.0, 1.0)
			else:
				kind.text = "Being test-played"
				kind.tooltip_text = "Test golfers are playing this hole to see what it asks of a golfer."
			var txt := "No rounds yet"
			if hole.plays > 0:
				txt = "Average %.1f  ·  %d played  ·  best %d" % [hole.average_score(), hole.plays, hole.best]
			txt += "  ·  fun %d" % int(hole.fun)
			var lit := int(round(hole.lit_share(sim.course) * 100.0))
			if hole.lit_enough(sim.course):
				txt += "\nLit for night golf (%d%% of the hole)" % lit
			elif lit > 0:
				txt += "\nLights reach %d%% of the hole. It needs %d%% for night golf." % [lit, int(Hole.LIT_ENOUGH * 100.0)]
			else:
				txt += "\nNo lights. Golfers pay less for it after dark."
			if hole.lab_ready and not hole.expect.is_empty():
				txt += "\nExpected score: beginner %.1f, average %.1f, expert %.1f" % [float(hole.expect.beginner), float(hole.expect.average), float(hole.expect.expert)]
			if not hole.play_times.is_empty():
				txt += "\nAbout %s a group, waiting included" % Defs.pace_text(hole.average_time())
			(row[2] as Label).text = txt
			(row[3] as Label).text = _hole_report(hole)
			var paid: Label = row[4]
			if hole.payers == 0:
				paid.text = "No fees yet"
				paid.add_theme_color_override("font_color", UIKit.MUTED)
			else:
				var avg := hole.average_paid()
				paid.text = "%s a golfer" % Defs.money(avg)
				paid.add_theme_color_override("font_color", UIKit.GOOD if hole.fun >= 55.0 else (UIKit.WARN if hole.fun >= 40.0 else UIKit.BAD))


## The course scorecard: every hole's par, yardage, average score and how
## the scores fell, with the hardest, the easiest and the favourite called
## out. Rebuilt when another hole has been played.
func _scorecard(box: VBoxContainer) -> void:
	UIKit.clear(box)
	var sim := hud.sim
	var holes := sim.course.holes
	if holes.is_empty():
		return
	var card := UIKit.card()
	box.add_child(card)
	var cv := UIKit.vbox(3)
	card.add_child(cv)
	cv.add_child(UIKit.label("SCORECARD", 12, UIKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	cv.add_child(grid)
	for head: String in ["Hole", "Par", "Yards", "Average", "Birdies", "Bogeys", "Fun", "Pays", "Time"]:
		var hl := UIKit.label(head, 11, UIKit.MUTED)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if head != "Hole" else HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(hl)
	var par_total := 0
	var yards_total := 0
	var avg_total := 0.0
	var played_all := true
	var hardest := -1
	var easiest := -1
	var favourite := -1
	var least := -1
	var slow := sim.course.bottleneck()
	for i in holes.size():
		var h := holes[i]
		par_total += h.par
		yards_total += Defs.yards(h.length)
		var over := h.average_score() - h.par if h.plays > 0 else 0.0
		if h.plays >= 3:
			avg_total += h.average_score()
			if hardest < 0 or over > holes[hardest].average_score() - holes[hardest].par:
				hardest = i
			if easiest < 0 or over < holes[easiest].average_score() - holes[easiest].par:
				easiest = i
		else:
			played_all = false
		if favourite < 0 or h.fun > holes[favourite].fun:
			favourite = i
		if least < 0 or h.fun < holes[least].fun:
			least = i
		var cells: Array[String] = [
			"%d  %s" % [i + 1, h.name], str(h.par), str(Defs.yards(h.length)),
			("%.1f" % h.average_score()) if h.plays > 0 else "–",
			("%d%%" % int(round(h.share(["-2", "-1"]) * 100.0))) if h.plays > 0 else "–",
			("%d%%" % int(round(h.share(["1", "2", "3"]) * 100.0))) if h.plays > 0 else "–",
			str(int(h.fun)),
			Defs.money(h.average_paid()) if h.payers > 0 else "–",
			Defs.pace_text(h.average_time(), true) if not h.play_times.is_empty() else "–",
		]
		for c in cells.size():
			var cl := UIKit.label(cells[c], 12, UIKit.TEXT if c > 0 else UIKit.GOLD)
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if c > 0 else HORIZONTAL_ALIGNMENT_LEFT
			if c == 0:
				cl.custom_minimum_size = Vector2(108, 0)
				cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if c == 8 and i == slow:
				cl.add_theme_color_override("font_color", UIKit.WARN)
				cl.tooltip_text = "The slowest hole on the course"
			grid.add_child(cl)
	var time_total := Defs.pace_text(sim.course.round_time(), true) if sim.course.times_complete() else "–"
	var foot: Array[String] = ["Out", str(par_total), str(yards_total), ("%.1f" % avg_total) if played_all else "–", "", "", "", "", time_total]
	for c in foot.size():
		var fl := UIKit.label(foot[c], 12, UIKit.MUTED)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if c > 0 else HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(fl)
	var notes: Array[String] = []
	if hardest >= 0 and easiest >= 0 and hardest != easiest:
		notes.append("Hardest: hole %d, %.1f over par. Easiest: hole %d, %+.1f." % [hardest + 1, holes[hardest].average_score() - holes[hardest].par, easiest + 1, holes[easiest].average_score() - holes[easiest].par])
	if favourite >= 0 and least >= 0 and favourite != least and holes[favourite].fun - holes[least].fun > 4.0:
		var gripe := _hole_gripe(holes[least])
		notes.append("Favourite: hole %d. Least liked: hole %d%s." % [favourite + 1, least + 1, (", " + gripe) if gripe != "" else ""])
	var aces := 0
	for h in holes:
		aces += h.aces
	if aces > 0:
		notes.append("%d hole-in-one%s on the course so far." % [aces, "" if aces == 1 else "s"])
	if sim.course.times_complete():
		var round_s := sim.course.round_time()
		var pace_note := "A round takes about %s." % Defs.pace_text(round_s)
		if round_s > Defs.ROUND_LONG:
			pace_note += " That is over five hours."
		notes.append(pace_note)
	elif sim.course.round_time() > 0.0:
		notes.append("Timed holes so far add up to %s." % Defs.pace_text(sim.course.round_time()))
	if slow >= 0:
		notes.append("Slowest: hole %d, %s a group." % [slow + 1, Defs.pace_text(holes[slow].average_time())])
	if not notes.is_empty():
		cv.add_child(UIKit.para("  ".join(PackedStringArray(notes)), 12))
	var said := sim.course.comment_report()
	if not said.is_empty():
		cv.add_child(UIKit.gap(4))
		cv.add_child(UIKit.label("WHAT GOLFERS SAY", 12, UIKit.ACCENT))
		for row in said:
			var tag := str(row.tag)
			if not COMMENT_WORDS.has(tag):
				continue
			var total := float(row.total)
			var words := str(COMMENT_WORDS[tag])
			var shown := "%+.1f" % total
			cv.add_child(UIKit.row(words, shown, UIKit.GOOD if total >= 0.0 else UIKit.BAD))


## The complaint golfers make most about a hole, in a few words.
func _hole_gripe(h: Hole) -> String:
	var worst := ""
	var worst_v := 0.0
	for tag: String in h.comments:
		var v := float(h.comments[tag])
		if v < worst_v:
			worst_v = v
			worst = tag
	var words := {"water": "too much water", "bunker": "too much sand", "rough": "the rough", "hard": "it is too hard", "oob": "out of bounds",
		"wait": "the wait", "weeds": "the weeds", "pests": "the pests", "wet": "the wet", "bare": "the bare ground", "dark": "the dark", "hit": "flying balls", "greens_bad": "the greens"}
	return str(words.get(worst, "")) if worst != "" else ""


# -------------------------------------------------------------- my golfer

func _golfer(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	var car := sim.career
	var sk := sim.skills
	body.add_child(UIKit.para("Skill points build your golfer. You earn them by playing your own course: a medal for your best score on each hole, challenges met, good full rounds, and golfer levels. The name and the kit go with you when you play a shared course.", 13))
	var g := sim.player.golfer
	var name_row := UIKit.hbox(8)
	body.add_child(name_row)
	name_row.add_child(UIKit.label("Name", 14, UIKit.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = g.name
	name_edit.custom_minimum_size = Vector2(160, 0)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.tooltip_text = "What your golfer is called"
	name_edit.text_changed.connect(func(t: String) -> void: g.name = t)
	name_edit.text_submitted.connect(func(_t: String) -> void: name_edit.release_focus())
	name_row.add_child(name_edit)
	var kit := UIKit.hbox(8)
	body.add_child(kit)
	_kit_swatch(kit, g, "shirt", "Shirt")
	_kit_swatch(kit, g, "pants", "Trousers")
	_kit_swatch(kit, g, "hat", "Hat")
	var lv := UIKit.hbox()
	body.add_child(lv)
	var lv_label := UIKit.label("", 15)
	lv.add_child(lv_label)
	var xp_bar := UIKit.bar(0.0, UIKit.BLUE)
	_wide(xp_bar)
	lv.add_child(xp_bar)
	var pts := UIKit.label("", 17, UIKit.GOLD)
	lv.add_child(pts)

	body.add_child(UIKit.gap(2))
	body.add_child(UIKit.heading("Attributes"))
	var rows := []
	for a: Dictionary in sim.db.attributes:
		var id := str(a.id)
		var card := UIKit.card()
		body.add_child(card)
		var cv := UIKit.vbox(3)
		card.add_child(cv)
		var top := UIKit.hbox(8)
		cv.add_child(top)
		var name := UIKit.label(str(a.name), 16)
		name.custom_minimum_size = Vector2(112, 0)
		top.add_child(name)
		var pips := Pips.new()
		pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(pips)
		var up := UIKit.button("", func() -> void:
			if car.raise(id):
				hud.rebuild_dock(), "Raise %s by one level" % str(a.name))
		up.custom_minimum_size = Vector2(92, 30)
		up.add_theme_font_size_override("font_size", 13)
		top.add_child(up)
		cv.add_child(UIKit.para(str(a.desc), 12))
		var perk_labels := []
		for pk: Dictionary in a.get("perks", []):
			var pl := UIKit.para("", 12)
			cv.add_child(pl)
			perk_labels.append([pl, pk])
		rows.append([id, pips, up, perk_labels])

	body.add_child(UIKit.gap(2))
	body.add_child(UIKit.heading("Album"))
	var album_line := UIKit.para("", 13, UIKit.TEXT)
	body.add_child(album_line)
	body.add_child(UIKit.gap(2))
	body.add_child(UIKit.heading("Medals"))
	var medal_line := UIKit.para("", 13, UIKit.TEXT)
	body.add_child(medal_line)
	body.add_child(UIKit.para("Par a hole of 100 yards or more for bronze (1 point), birdie it for silver (2 more), eagle it for gold (3 more).", 12))

	var groups := {}
	var order: Array[String] = []
	for c: Dictionary in sim.db.challenges:
		var gname := str(c.group)
		if not groups.has(gname):
			groups[gname] = []
			order.append(gname)
		(groups[gname] as Array).append(c)
	var ch_rows := []
	var left := UIKit.label("", 13, UIKit.MUTED)
	body.add_child(UIKit.gap(2))
	var ch_head := UIKit.hbox()
	body.add_child(ch_head)
	ch_head.add_child(UIKit.heading("Challenges"))
	ch_head.add_child(UIKit.spacer())
	ch_head.add_child(left)
	for gname in order:
		body.add_child(UIKit.label(gname, 13, UIKit.BLUE))
		for c: Dictionary in groups[gname]:
			var row := UIKit.hbox(8)
			body.add_child(row)
			var tv := UIKit.vbox(0)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(tv)
			var cname := UIKit.label(str(c.name), 14)
			tv.add_child(cname)
			tv.add_child(UIKit.para(str(c.desc), 12))
			var bar := UIKit.bar(0.0, UIKit.ACCENT, 6)
			bar.custom_minimum_size = Vector2(70, 6)
			row.add_child(bar)
			var reward := UIKit.label("+%d" % int(c.points), 15, UIKit.GOLD)
			reward.custom_minimum_size = Vector2(46, 0)
			reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(reward)
			ch_rows.append([c, cname, bar, reward])

	return func() -> void:
		var lvl := int(sk.level.golfer)
		lv_label.text = "Golfer level %d" % lvl
		xp_bar.value = float(int(sk.xp.golfer)) / float(Skills.need(lvl))
		var p := car.points()
		pts.text = "%d point%s" % [p, "" if p == 1 else "s"]
		for row: Array in rows:
			var id := str(row[0])
			var level := car.level(id)
			(row[1] as Pips).level = level
			var up: Button = row[2]
			if level >= Career.MAX_LEVEL:
				up.text = "Maxed"
				up.disabled = true
			else:
				var cost := car.cost(id)
				up.text = "+1  ·  %d pt%s" % [cost, "" if cost == 1 else "s"]
				up.disabled = not car.can_raise(id)
			for pair: Array in row[3]:
				var pk: Dictionary = pair[1]
				var got := level >= int(pk.at)
				var pl: Label = pair[0]
				pl.text = "%s  %s: %s" % ["Unlocked" if got else "At level %d" % int(pk.at), str(pk.name), str(pk.desc)]
				pl.add_theme_color_override("font_color", UIKit.GOLD if got else UIKit.MUTED)
		var counts := [0, 0, 0, 0]
		for k: String in car.medals:
			counts[int(car.medals[k])] += 1
		if car.medals.is_empty():
			medal_line.text = "No medals yet. Play a round."
		else:
			medal_line.text = "%d gold  ·  %d silver  ·  %d bronze" % [counts[3], counts[2], counts[1]]
		if sim.album.is_empty():
			album_line.text = "Aces and tournament wins are kept here, and they come with you to the next course."
		else:
			var lines := ""
			var start := maxi(sim.album.size() - 6, 0)
			for i in range(sim.album.size() - 1, start - 1, -1):
				var page: Dictionary = sim.album[i]
				lines += str(page.get("text", "")) + "\n"
			album_line.text = lines.strip_edges()
		left.text = "%d points still to win" % car.challenge_points_left()
		for row: Array in ch_rows:
			var c: Dictionary = row[0]
			var met := car.done.has(str(c.id))
			(row[1] as Label).add_theme_color_override("font_color", UIKit.GOOD if met else UIKit.TEXT)
			(row[2] as ProgressBar).value = car.progress(c)
			(row[2] as ProgressBar).visible = not met
			(row[3] as Label).text = "Done" if met else "+%d" % int(c.points)
			(row[3] as Label).add_theme_color_override("font_color", UIKit.GOOD if met else UIKit.GOLD)


## A coloured square that steps through the colours golfers already wear.
func _kit_swatch(row: HBoxContainer, g: Golfer, field: String, caption: String) -> void:
	var palette: Array[Color] = Golfer.SHIRTS
	if field == "pants":
		palette = Golfer.PANTS
	elif field == "hat":
		var hats: Array[Color] = []
		for c: Color in Golfer.SHIRTS:
			hats.append(c)
		hats.append(Color(0, 0, 0, 0))
		palette = hats
	var box := UIKit.vbox(2)
	row.add_child(box)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(36, 22)
	var current: Color = g.get(field)
	sw.color = current
	box.add_child(sw)
	var b := UIKit.button(caption, func() -> void:
		var now: Color = g.get(field)
		var at := -1
		for i in palette.size():
			if palette[i].is_equal_approx(now):
				at = i
				break
		var next: Color = palette[(at + 1) % palette.size()]
		g.set(field, next)
		sw.color = next, "Change the %s" % caption.to_lower())
	b.custom_minimum_size = Vector2(88, 28)
	box.add_child(b)


## Ten pips that fill as an attribute rises.
class Pips:
	extends Control
	var level := 0:
		set(v):
			if v != level:
				level = v
				queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(150, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := Career.MAX_LEVEL
		var gap := 3.0
		var w := (size.x - gap * (n - 1)) / n
		for i in n:
			var r := Rect2(i * (w + gap), 1.0, w, size.y - 2.0)
			draw_rect(r, UIKit.ACCENT if i < level else Color(1, 1, 1, 0.12))


# ------------------------------------------------------------------ staff

func _staff(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	var counts := {}
	for role: Dictionary in sim.db.roles:
		var id := str(role.id)
		var card := UIKit.card()
		body.add_child(card)
		var v := UIKit.vbox(4)
		card.add_child(v)
		var h := UIKit.hbox()
		v.add_child(h)
		var sw := ColorRect.new()
		sw.color = Color(str(role.color))
		sw.custom_minimum_size = Vector2(10, 20)
		h.add_child(sw)
		h.add_child(UIKit.label(str(role.name), 17))
		h.add_child(UIKit.spacer())
		var cl := UIKit.label("0", 17, UIKit.ACCENT)
		h.add_child(cl)
		counts[id] = cl
		v.add_child(UIKit.para(str(role.blurb), 13))
		var bh := UIKit.hbox()
		v.add_child(bh)
		bh.add_child(UIKit.label("%s a month each" % Defs.money(float(role.wage) * sim.skills.mult("wage")), 13, UIKit.MUTED))
		bh.add_child(UIKit.spacer())
		bh.add_child(UIKit.button("Fire", func() -> void: sim.crew.fire_one(id)))
		bh.add_child(UIKit.button("Hire", func() -> void:
			sim.hire(id)
			sim.toast.emit("Hired a %s." % str(role.name).to_lower(), "good")))
	var total := UIKit.row("Wages due at month end", "")
	body.add_child(total)
	var cond := UIKit.row("Course condition", "")
	body.add_child(cond)
	var weeds := UIKit.row("Weeds on tees, fairways and greens", "")
	body.add_child(weeds)
	var pests := UIKit.row("Pest damage", "")
	body.add_child(pests)
	body.add_child(UIKit.para("One greenkeeper keeps about three holes in fair shape, and a second keeps them pristine. Without an exterminator, pests will slowly overrun the course. Use the Turf view at the bottom right to see where the grass is suffering.", 13))
	return func() -> void:
		for id: String in counts:
			(counts[id] as Label).text = str(sim.crew.count(id))
		(total.get_node("Value") as Label).text = Defs.money(sim.crew.monthly_wages())
		var c := sim.grounds.condition * 100.0
		var cv := cond.get_node("Value") as Label
		cv.text = "%d%%" % int(c)
		cv.add_theme_color_override("font_color", UIKit.mood_color(c - 15.0))
		(weeds.get_node("Value") as Label).text = "%.0f%%" % (sim.grounds.weed_cover * 100.0)
		(pests.get_node("Value") as Label).text = "%.0f%%" % (sim.grounds.pest_cover * 100.0)


# ---------------------------------------------------------------- finances

func _money(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	var big := UIKit.label("", 30, UIKit.GOOD)
	body.add_child(big)
	var table := UIKit.vbox(3)
	body.add_child(table)
	body.add_child(UIKit.gap(4))
	body.add_child(UIKit.heading("Earlier months"))
	var legend := UIKit.hbox(12)
	body.add_child(legend)
	legend.add_child(UIKit.label("Rating", 12, UIKit.GOLD))
	legend.add_child(UIKit.label("Satisfaction", 12, UIKit.BLUE))
	var chart := UIKit.HistoryChart.new()
	body.add_child(chart)
	var hist := UIKit.vbox(3)
	body.add_child(hist)
	return func() -> void:
		var e := sim.economy
		big.text = Defs.money(e.money)
		big.add_theme_color_override("font_color", UIKit.GOOD if e.money >= 0.0 else UIKit.BAD)
		UIKit.clear(table)
		table.add_child(UIKit.heading("%s so far" % Defs.MONTH_NAMES[sim.month()]))
		for k: String in Economy.INCOME_NAMES:
			table.add_child(UIKit.row(str(Economy.INCOME_NAMES[k]), Defs.money(float(e.income.get(k, 0.0))), UIKit.GOOD))
		for k: String in Economy.EXPENSE_NAMES:
			var v := float(e.expense.get(k, 0.0))
			table.add_child(UIKit.row(str(Economy.EXPENSE_NAMES[k]), Defs.money(-v) if v > 0.0 else "$0", UIKit.BAD if v > 0.0 else UIKit.MUTED))
		table.add_child(UIKit.row("Net so far", Defs.money(e.net()), UIKit.GOOD if e.net() >= 0.0 else UIKit.BAD))
		table.add_child(UIKit.gap(4))
		table.add_child(UIKit.heading("Due at month end"))
		table.add_child(UIKit.row("Staff wages", Defs.money(sim.crew.monthly_wages())))
		table.add_child(UIKit.row("Upkeep", Defs.money(sim.monthly_upkeep())))
		UIKit.clear(hist)
		var rate := PackedFloat32Array()
		var happy := PackedFloat32Array()
		for past in e.history:
			var month: Dictionary = past
			rate.append(float(month.rating) if month.has("rating") else -1.0)
			happy.append(float(month.satisfaction) if month.has("satisfaction") else -1.0)
		chart.set_series(rate, happy)
		if e.history.is_empty():
			hist.add_child(UIKit.label("Nothing yet. Books close on the last day of each month.", 13, UIKit.MUTED))
		for i in range(e.history.size() - 1, maxi(e.history.size() - 9, -1), -1):
			var r: Dictionary = e.history[i]
			var net := float(r.net)
			hist.add_child(UIKit.row(str(r.label), Defs.money(net), UIKit.GOOD if net >= 0.0 else UIKit.BAD))


# ------------------------------------------------------------- tournaments

func _tournaments(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	var t := sim.tourney
	body.add_child(UIKit.para("You put up the prize purse. Sponsors and ticket sales pay you back, and pay more when the players like the course. The course closes to the public while an event is on. Each event can be held once a year."))
	var choice := ["standard"]
	var setup_ids: Array[String] = []
	var setup_blurbs: Array[String] = []
	var setup_btns: Array[Button] = []
	var setup_row := UIKit.hbox(4)
	body.add_child(setup_row)
	setup_row.add_child(UIKit.label("Setup", 13, UIKit.MUTED))
	for s: Dictionary in sim.db.setups:
		var sid := str(s.id)
		setup_ids.append(sid)
		setup_blurbs.append(str(s.blurb))
		var b := UIKit.button(str(s.name), func() -> void: choice[0] = sid)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		setup_row.add_child(b)
		setup_btns.append(b)
	var setup_blurb := UIKit.para("", 13, UIKit.MUTED)
	body.add_child(setup_blurb)
	var status := UIKit.card(Color(0.3, 0.7, 0.4, 0.14))
	body.add_child(status)
	var sv := UIKit.vbox(4)
	status.add_child(sv)
	var s_title := UIKit.label("", 16)
	sv.add_child(s_title)
	var s_body := UIKit.para("", 13, UIKit.TEXT)
	sv.add_child(s_body)
	var s_board := GridContainer.new()
	s_board.columns = 4
	s_board.add_theme_constant_override("h_separation", 14)
	s_board.add_theme_constant_override("v_separation", 2)
	sv.add_child(s_board)
	var board_sig := [""]
	var cancel := UIKit.button("Cancel the event", func() -> void: t.cancel())
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sv.add_child(cancel)
	var rows: Array = []
	for def: Dictionary in sim.db.tournaments:
		var card := UIKit.card()
		body.add_child(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		var h := UIKit.hbox()
		v.add_child(h)
		h.add_child(UIKit.label(str(def.name), 16))
		h.add_child(UIKit.spacer())
		var done := UIKit.label("", 12, UIKit.GOLD)
		h.add_child(done)
		v.add_child(UIKit.para(str(def.blurb), 13))
		v.add_child(UIKit.label("Needs %d holes and a rating of %d  ·  field of %d" % [int(def.min_holes), int(def.min_rating), int(def.field)], 13, UIKit.MUTED))
		var money := UIKit.label("", 13, UIKit.TEXT)
		v.add_child(money)
		var fh := UIKit.hbox()
		v.add_child(fh)
		var reason := UIKit.label("", 13, UIKit.WARN)
		fh.add_child(reason)
		fh.add_child(UIKit.spacer())
		var id := str(def.id)
		var host := UIKit.button("Host it", func() -> void: t.schedule(id, choice[0]))
		fh.add_child(host)
		rows.append([def, money, reason, host, done])
	return func() -> void:
		if not t.active.is_empty():
			var def: Dictionary = t.active.def
			s_title.text = "%s: in progress" % def.name
			s_body.text = "Players are heading to the first tee." if t.board.is_empty() else "Leaderboard"
			var sig := ""
			for e in t.board:
				sig += "%s%d%d" % [e.name, int(e.to_par), int(e.thru)]
			if sig != board_sig[0]:
				board_sig[0] = sig
				UIKit.clear(s_board)
				for i in mini(t.board.size(), 12):
					var e: Dictionary = t.board[i]
					var tp := int(e.to_par)
					s_board.add_child(UIKit.label(str(i + 1), 13, UIKit.MUTED))
					s_board.add_child(UIKit.label(str(e.name), 13))
					s_board.add_child(UIKit.label("E" if tp == 0 else ("%+d" % tp), 13, UIKit.GOOD if tp < 0 else UIKit.TEXT))
					s_board.add_child(UIKit.label("thru %d" % int(e.thru), 13, UIKit.MUTED))
			s_board.visible = true
			cancel.visible = false
			status.visible = true
		elif not t.scheduled.is_empty():
			var def: Dictionary = t.scheduled.def
			s_title.text = "%s: booked" % def.name
			var setup := t.setup_of(str(t.scheduled.get("setup", "standard")))
			s_body.text = "Starts %s, in %d days, %s setup. Get the course in shape." % [Defs.date_text(int(t.scheduled.day)), int(t.scheduled.day) - sim.day(), str(setup.get("name", "Standard"))]
			s_board.visible = false
			cancel.visible = true
			status.visible = true
		elif not t.last_result.is_empty():
			var r := t.last_result
			s_title.text = "Last event: %s" % r.name
			s_body.text = "%s won at %s. You netted %s." % [r.winner, r.score, Defs.money(float(r.net))]
			s_board.visible = false
			cancel.visible = false
			status.visible = true
		else:
			status.visible = false
		for i in setup_btns.size():
			setup_btns[i].set_pressed_no_signal(setup_ids[i] == choice[0])
			if setup_ids[i] == choice[0]:
				setup_blurb.text = setup_blurbs[i]
		for row: Array in rows:
			var def: Dictionary = row[0]
			var why := t.can_host(def)
			(row[1] as Label).text = "Purse %s  ·  expected income %s" % [Defs.money(float(def.purse)), Defs.money(t.expected_income(def, choice[0]))]
			(row[2] as Label).text = why
			(row[3] as Button).disabled = why != ""
			var n := int(t.hosted.get(str(def.id), 0))
			(row[4] as Label).text = "" if n == 0 else "Hosted %d time%s" % [n, "" if n == 1 else "s"]


# ------------------------------------------------------------------ skills

class SkillMap:
	extends Control
	## Draws the lines joining each skill to the ones it unlocks.
	var links: Array = []

	func _draw() -> void:
		for l: Array in links:
			draw_line(l[0], l[1], l[2], 2.0, true)


func _skills(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	var sk := sim.skills
	var branch := "manager"
	body.add_child(UIKit.para("You earn manager experience when golfers leave happy and when you host tournaments. Your own golfer has a page of their own: My Golfer.", 13))
	var lv := UIKit.hbox()
	body.add_child(lv)
	var lv_label := UIKit.label("", 15)
	lv.add_child(lv_label)
	var xp_bar := UIKit.bar(0.0, UIKit.BLUE)
	_wide(xp_bar)
	lv.add_child(xp_bar)
	var pts := UIKit.label("", 15, UIKit.GOLD)
	lv.add_child(pts)

	var map := SkillMap.new()
	var cw := 100.0
	var ch := 70.0
	var rows := 0
	var buttons := {}
	for s: Dictionary in sim.db.skills:
		if str(s.branch) != branch:
			continue
		rows = maxi(rows, int(s.row) + 1)
		var id := str(s.id)
		var b := UIKit.button(str(s.name), func() -> void:
			_skill_pick = id
			hud.rebuild_dock(), str(s.desc))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 12)
		b.position = Vector2(int(s.col) * cw, int(s.row) * ch)
		b.size = Vector2(cw - 10.0, ch - 14.0)
		b.clip_text = false
		map.add_child(b)
		buttons[id] = b
	map.custom_minimum_size = Vector2(cw * 4.0, rows * ch)
	body.add_child(map)

	var detail := UIKit.card(Color(1, 1, 1, 0.07))
	body.add_child(detail)
	var dv := UIKit.vbox(4)
	detail.add_child(dv)
	var d_name := UIKit.label("Pick a skill", 17)
	dv.add_child(d_name)
	var d_desc := UIKit.para("Click any skill to see what it does.", 14, UIKit.TEXT)
	dv.add_child(d_desc)
	var d_req := UIKit.label("", 13, UIKit.MUTED)
	dv.add_child(d_req)
	var d_btn := UIKit.button("Unlock", func() -> void:
		if sk.unlock(_skill_pick):
			sim.toast.emit("Skill unlocked: %s." % str(DataDB.find(sim.db.skills, _skill_pick).name), "good")
			hud.rebuild_dock())
	d_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	dv.add_child(d_btn)

	return func() -> void:
		var lvl := int(sk.level[branch])
		lv_label.text = "Level %d" % lvl
		xp_bar.value = float(int(sk.xp[branch])) / float(Skills.need(lvl))
		var p := int(sk.points[branch])
		pts.text = "%d point%s" % [p, "" if p == 1 else "s"]
		map.links.clear()
		for s: Dictionary in sim.db.skills:
			if str(s.branch) != branch:
				continue
			var id := str(s.id)
			var b: Button = buttons[id]
			var owned := sk.has(id)
			var can := sk.can_unlock(id)
			var bg := Color(0.13, 0.16, 0.15)
			var edge := Color(1, 1, 1, 0.08)
			var fg := UIKit.MUTED
			if owned:
				bg = Color(0.18, 0.45, 0.26)
				edge = Color(0.5, 0.9, 0.6, 0.6)
				fg = Color.WHITE
			elif can:
				bg = Color(0.22, 0.26, 0.2)
				edge = UIKit.GOLD
				fg = UIKit.TEXT
			if id == _skill_pick:
				edge = Color.WHITE
			var sb := UIKit.box(bg, 6, 6, 4, edge)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
			b.add_theme_stylebox_override("pressed", sb)
			b.add_theme_color_override("font_color", fg)
			b.add_theme_color_override("font_hover_color", fg)
			for r: String in s.req:
				if buttons.has(r):
					var from: Button = buttons[r]
					var col := Color(0.5, 0.9, 0.6, 0.8) if sk.has(r) else Color(1, 1, 1, 0.2)
					map.links.append([from.position + Vector2(from.size.x, from.size.y * 0.5), b.position + Vector2(0, b.size.y * 0.5), col])
		map.queue_redraw()
		if _skill_pick != "":
			var s := DataDB.find(sim.db.skills, _skill_pick)
			d_name.text = str(s.name)
			d_desc.text = str(s.desc)
			var needs: Array[String] = []
			for r: String in s.req:
				needs.append(str(DataDB.find(sim.db.skills, r).name))
			d_req.text = "Cost: %d point%s" % [int(s.cost), "" if int(s.cost) == 1 else "s"] + ("" if needs.is_empty() else "  ·  needs " + ", ".join(needs))
			d_btn.visible = true
			if sk.has(_skill_pick):
				d_btn.text = "Unlocked"
				d_btn.disabled = true
			else:
				d_btn.text = "Unlock"
				d_btn.disabled = not sk.can_unlock(_skill_pick)
		else:
			d_btn.visible = false


# ---------------------------------------------------------------- pro shop

func _stat(v: float, better_high: bool) -> String:
	var pct := int(round((v - 1.0) * 100.0))
	if pct == 0:
		return "standard"
	return "%+d%%" % (pct if better_high else pct)


func _shop(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	var pl := sim.player
	body.add_child(UIKit.para("Gear for your own golfer. Power clubs hit it further and wilder. Accuracy clubs find the fairway and give up yards. Mix brands across your bag."))
	var tabs := UIKit.hbox(6)
	body.add_child(tabs)
	for cat: Dictionary in sim.db.categories:
		var id := str(cat.id)
		var b := UIKit.button(str(cat.name), func() -> void:
			_shop_cat = id
			hud.rebuild_dock())
		b.toggle_mode = true
		b.set_pressed_no_signal(id == _shop_cat)
		_wide(b)
		tabs.add_child(b)
	var cat_id := _shop_cat
	var brand_rows: Array = []
	for brand: Dictionary in sim.db.brands:
		var bid := str(brand.id)
		var card := UIKit.card()
		body.add_child(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		var h := UIKit.hbox()
		v.add_child(h)
		h.add_child(UIKit.label(str(brand.name), 16))
		h.add_child(UIKit.label(str(brand.style), 12, UIKit.BLUE))
		h.add_child(UIKit.spacer())
		var btn := UIKit.button("", func() -> void:
			if not pl.buy(cat_id, bid):
				sim.toast.emit("You can't afford those.", "bad"))
		h.add_child(btn)
		brand_rows.append([bid, btn])
		v.add_child(UIKit.para(str(brand.blurb), 13))
		var stats := "Power %s  ·  stray shots %s  ·  mishits %s" % [_stat(float(brand.power), true), _stat(float(brand.spread), false), _stat(float(brand.forgive), false)]
		if cat_id == "putter":
			stats = "Putting precision %s" % _stat(float(brand.putt), true)
		elif float(brand.wind) != 1.0:
			stats += "  ·  wind effect %s" % _stat(float(brand.wind), false)
		v.add_child(UIKit.label(stats, 12, UIKit.MUTED))

	body.add_child(UIKit.gap(6))
	body.add_child(UIKit.heading("Golf balls"))
	body.add_child(UIKit.para("Special balls come in sleeves of three. Lose one in the water or out of bounds and it's gone.", 13))
	var ball_rows: Array = []
	for ball: Dictionary in sim.db.balls:
		var bid := str(ball.id)
		var card := UIKit.card()
		body.add_child(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		var h := UIKit.hbox()
		v.add_child(h)
		var sw := ColorRect.new()
		sw.color = Color(str(ball.color))
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		h.add_child(UIKit.label(str(ball.name), 15))
		var have := UIKit.label("", 13, UIKit.MUTED)
		h.add_child(have)
		h.add_child(UIKit.spacer())
		var buy: Button = null
		if int(ball.price) > 0:
			buy = UIKit.button("Buy 3  %s" % Defs.money(float(ball.price)), func() -> void:
				if not pl.buy_balls(bid):
					sim.toast.emit("You can't afford those.", "bad"))
			h.add_child(buy)
		var use := UIKit.button("Use", func() -> void: pl.use_ball(bid))
		h.add_child(use)
		v.add_child(UIKit.para(str(ball.blurb), 13))
		ball_rows.append([bid, have, use])

	return func() -> void:
		for row: Array in brand_rows:
			var bid := str(row[0])
			var btn: Button = row[1]
			if str(pl.equipped.get(cat_id, "")) == bid:
				btn.text = "In the bag"
				btn.disabled = true
			elif pl.owns(cat_id, bid):
				btn.text = "Equip"
				btn.disabled = false
			else:
				btn.text = "Buy  %s" % Defs.money(float(pl.price(cat_id, bid)))
				btn.disabled = false
		for row: Array in ball_rows:
			var bid := str(row[0])
			var n := pl.ball_count(bid)
			(row[1] as Label).text = "unlimited" if bid == "standard" else "x%d" % n
			var use: Button = row[2]
			use.disabled = n <= 0 or pl.ball_id == bid
			use.text = "In play" if pl.ball_id == bid else "Use"


# ------------------------------------------------------------------- goals

func _goals(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	var sc := sim.scenario
	var name_row := UIKit.hbox()
	body.add_child(name_row)
	name_row.add_child(UIKit.label("Course name", 13, UIKit.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = sim.course_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			sim.course_name = t.strip_edges())
	name_edit.text_submitted.connect(func(_t: String) -> void: name_edit.release_focus())
	name_row.add_child(name_edit)
	body.add_child(UIKit.label(str(sc.def.get("name", "Free Play")), 20))
	body.add_child(UIKit.para(str(sc.def.get("blurb", ""))))
	var status := UIKit.label("", 15, UIKit.GOLD)
	body.add_child(status)
	var goals := UIKit.vbox(4)
	body.add_child(goals)
	body.add_child(UIKit.gap(6))
	body.add_child(UIKit.heading("Standing"))
	var recs := UIKit.vbox(3)
	body.add_child(recs)
	body.add_child(UIKit.gap(6))
	body.add_child(UIKit.heading("Design checklist"))
	body.add_child(UIKit.para("Each line is part of the design score, and the next thing that would raise it. A round's length is listed too, and it does not change the score.", 12))
	var accred := UIKit.vbox(2)
	body.add_child(accred)
	body.add_child(UIKit.gap(6))
	body.add_child(UIKit.heading("World rankings"))
	var ranks := UIKit.vbox(2)
	body.add_child(ranks)
	body.add_child(UIKit.gap(6))
	var feat_head := UIKit.heading("Accomplishments")
	body.add_child(feat_head)
	body.add_child(UIKit.para("Each one earns a skill point for the manager and one for your golfer.", 12))
	var feats := UIKit.vbox(3)
	body.add_child(feats)
	var feat_sig := [-1]
	return func() -> void:
		match sc.status:
			"free":
				status.text = "No goals and no deadline. Enjoy."
			"won":
				status.text = "Scenario complete."
			"lost":
				status.text = "The scenario was lost. You can keep playing."
			_:
				status.text = "%s  ·  %d days left" % [sc.deadline_text(), sc.days_left(sim)]
		UIKit.clear(goals)
		for p in sc.progress(sim):
			var h := UIKit.hbox()
			h.add_child(UIKit.label("Done" if p.done else "To do", 12, UIKit.GOOD if p.done else UIKit.WARN))
			h.add_child(UIKit.label(str(p.text), 14))
			h.add_child(UIKit.spacer())
			h.add_child(UIKit.label(str(p.now), 14, UIKit.MUTED))
			goals.add_child(h)
		UIKit.clear(recs)
		recs.add_child(UIKit.row("Class", sim.course_class()))
		recs.add_child(UIKit.row("Land", str(sim.biome.get("name", ""))))
		recs.add_child(UIKit.row("Course rating", "%d / 100" % int(sim.rating)))
		recs.add_child(UIKit.row("   from golfer satisfaction", "%d%%" % int(sim.visitors.average_satisfaction())))
		recs.add_child(UIKit.row("   from course condition", "%d%%" % int(sim.grounds.condition * 100.0)))
		recs.add_child(UIKit.row("   from design and amenities", "%d / 100" % int(sim.design)))
		recs.add_child(UIKit.row("Reputation", "%d / 100" % int(sim.reputation)))
		recs.add_child(UIKit.row("Holes", "%d  (par %d)" % [sim.course.holes.size(), sim.course.total_par()]))
		recs.add_child(UIKit.row("Club members", str(sim.members.count())))
		recs.add_child(UIKit.row("Homes on the course", str(sim.homes)))
		recs.add_child(UIKit.row("Rounds hosted", str(sim.stats.rounds)))
		recs.add_child(UIKit.row("Stories with a happy ending", str(sim.stats.stories)))
		recs.add_child(UIKit.row("Holes in one", str(sim.stats.aces)))
		recs.add_child(UIKit.row("People hit by golf balls", "%d  (%d by you)" % [int(sim.stats.hits), int(sim.stats.player_hits)]))
		recs.add_child(UIKit.row("Tantrums", str(sim.stats.tantrums)))
		recs.add_child(UIKit.row("Holes a golfer would not pay for", str(sim.stats.refusals)))
		if sim.eruption.has_volcano():
			recs.add_child(UIKit.row("Eruptions survived", str(sim.stats.eruptions)))
		recs.add_child(UIKit.row("Your holes played", str(sim.player.holes_played)))
		UIKit.clear(accred)
		for row in sim.accreditation():
			var met := bool(row.met)
			var head := ("\u2713  " if met else "\u25cb  ") + str(row.text)
			accred.add_child(UIKit.para(head, 13, UIKit.GOOD if met else UIKit.TEXT))
			accred.add_child(UIKit.para(str(row.detail), 12, UIKit.MUTED))
		# the ranking table, with your course slotted in
		UIKit.clear(ranks)
		var table: Array = []
		for r: Array in sim.rivals:
			table.append([str(r[0]), float(r[1]), false])
		table.append([sim.course_name, sim.rating, true])
		table.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
		var mine := 0
		for i in table.size():
			if table[i][2]:
				mine = i
		for i in table.size():
			if i > 2 and absi(i - mine) > 1 and i < table.size() - 1:
				continue
			var row := UIKit.row("%d.  %s" % [i + 1, table[i][0]], "%d" % int(table[i][1]), UIKit.GOLD if table[i][2] else UIKit.TEXT)
			if table[i][2]:
				(row.get_child(0) as Label).add_theme_color_override("font_color", UIKit.GOLD)
			ranks.add_child(row)
		if sim.best_rank > 0:
			ranks.add_child(UIKit.label("Best year-end finish: number %d. Rankings are settled at the end of each year." % sim.best_rank, 12, UIKit.MUTED))
		else:
			ranks.add_child(UIKit.label("Rankings are settled at the end of each year.", 12, UIKit.MUTED))
		if feat_sig[0] != sim.feats.count():
			feat_sig[0] = sim.feats.count()
			feat_head.text = "ACCOMPLISHMENTS  %d / %d" % [sim.feats.count(), sim.db.accomplishments.size()]
			UIKit.clear(feats)
			for a: Dictionary in sim.db.accomplishments:
				var got := sim.feats.has(str(a.id))
				var h := UIKit.hbox()
				h.add_child(UIKit.label("Done" if got else "", 11, UIKit.GOOD))
				var nm := UIKit.label(str(a.name), 13, UIKit.TEXT if got else UIKit.MUTED)
				nm.tooltip_text = str(a.desc)
				nm.mouse_filter = Control.MOUSE_FILTER_STOP
				h.add_child(nm)
				h.add_child(UIKit.spacer())
				h.add_child(UIKit.label(str(a.desc), 11, UIKit.MUTED))
				feats.add_child(h)


# -------------------------------------------------------------------- feed

func _feed(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	# two tabs: what golfers post, and the long stories playing out
	var tabs := UIKit.hbox(6)
	body.add_child(tabs)
	for it: Array in [["posts", "Posts"], ["stories", "Stories"]]:
		var id := str(it[0])
		var tb := UIKit.button(str(it[1]), func() -> void:
			feed_tab = id
			hud.rebuild_dock())
		tb.custom_minimum_size = Vector2(90, 32)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.disabled = feed_tab == id
		tabs.add_child(tb)
	if feed_tab == "stories":
		return _stories(body)
	var list := UIKit.vbox(6)
	body.add_child(list)
	var shown := [-1]
	return func() -> void:
		var total := sim.feed.posts.size()
		var newest: int = 0 if total == 0 else int(sim.feed.posts[-1].get("day", 0)) * 1000 + total
		if newest == shown[0]:
			return
		shown[0] = newest
		UIKit.clear(list)
		if total == 0:
			list.add_child(UIKit.para("Nobody has posted yet. Open some holes and the opinions will follow."))
		for i in range(total - 1, maxi(total - 31, -1), -1):
			var p: Dictionary = sim.feed.posts[i]
			var card := UIKit.card()
			list.add_child(card)
			var v := UIKit.vbox(2)
			card.add_child(v)
			var h := UIKit.hbox(6)
			v.add_child(h)
			var dot := ColorRect.new()
			dot.color = p.color
			dot.custom_minimum_size = Vector2(10, 10)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(dot)
			h.add_child(UIKit.label(str(p.name), 14))
			if p.verified:
				h.add_child(UIKit.label("verified", 11, UIKit.BLUE))
			h.add_child(UIKit.label("@" + str(p.handle), 12, UIKit.MUTED))
			h.add_child(UIKit.spacer())
			h.add_child(UIKit.label(Defs.date_text(int(p.day)).split(",")[0], 12, UIKit.MUTED))
			var col := UIKit.TEXT
			v.add_child(UIKit.para(str(p.text), 14, col))
			var likes := int(p.likes)
			var mood := "" if int(p.mood) == 0 else ("  ·  good press" if int(p.mood) > 0 else "  ·  bad press")
			v.add_child(UIKit.label("%s likes%s" % [_short(likes), mood], 11, UIKit.GOOD if int(p.mood) > 0 else (UIKit.BAD if int(p.mood) < 0 else UIKit.MUTED)))


## The long stories: who is in them, where each has got to, and what the
## club could do to move it on.
func _stories(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	var list := UIKit.vbox(8)
	body.add_child(list)
	var shown := [""]
	return func() -> void:
		var st := sim.stories
		var key := "%d|%d|%d" % [st.running.size(), st.finished.size(), sim.day()]
		for r in st.running:
			key += "|" + str(r.stage)
		if key == shown[0]:
			return
		shown[0] = key
		UIKit.clear(list)
		list.add_child(UIKit.para("Some golfers come back with a story to tell. Watch the feed, meet what they ask for, and see how it ends.", 13))
		if st.running.is_empty():
			list.add_child(UIKit.para("No story is running right now. They start once the club has found its feet.", 14, UIKit.WARN))
		for r in st.running:
			var d := st.describe(r)
			var card := UIKit.card()
			list.add_child(card)
			var v := UIKit.vbox(4)
			card.add_child(v)
			var top := UIKit.hbox(8)
			v.add_child(top)
			top.add_child(UIKit.label(str(d.title), 16, UIKit.GOLD))
			top.add_child(UIKit.spacer())
			top.add_child(UIKit.label("day %d" % int(d.days), 12, UIKit.MUTED))
			# the characters, with a button for anyone on the course
			var who := UIKit.hbox(6)
			v.add_child(who)
			var cast: Dictionary = d.cast
			for role: String in cast:
				var g := st.golfer_of(r, role)
				var name := str((r.names as Dictionary).get(role, ""))
				if g != null:
					var fb := UIKit.button(name + "  (on the course)", func() -> void:
						hud.world.selected = g
						hud.rig.follow = g
						hud.rig.target_dist = minf(hud.rig.target_dist, 45.0)
						hud.inspect(g), "Follow them")
					fb.add_theme_font_size_override("font_size", 12)
					who.add_child(fb)
				else:
					who.add_child(UIKit.label(name, 13))
			v.add_child(UIKit.para(str(d.chapter), 14))
			if str(d.request) != "":
				var req := UIKit.vbox(2)
				v.add_child(req)
				var left := int(d.days_left)
				req.add_child(UIKit.label("They want %s%s" % [str(d.request), "  ·  %d days left" % left if left >= 0 else ""], 13, UIKit.WARN))
				for n: Dictionary in d.needs:
					var met := bool(n.met)
					req.add_child(UIKit.label("%s  %s" % ["✓" if met else "○", str(n.now)], 12, UIKit.GOOD if met else UIKit.MUTED))
		if not st.finished.is_empty():
			list.add_child(UIKit.gap(6))
			list.add_child(UIKit.label("HOW THEY ENDED", 12, UIKit.ACCENT))
			for i in range(st.finished.size() - 1, maxi(st.finished.size() - 9, -1), -1):
				var f: Dictionary = st.finished[i]
				var how := str(f.how)
				var col := UIKit.GOOD if how == "happy" else (UIKit.BAD if how == "sad" else UIKit.MUTED)
				var fc := UIKit.card(Color(1, 1, 1, 0.03))
				list.add_child(fc)
				var fv := UIKit.vbox(2)
				fc.add_child(fv)
				var ft := UIKit.hbox(8)
				fv.add_child(ft)
				ft.add_child(UIKit.label(str(f.title), 14, col))
				ft.add_child(UIKit.spacer())
				ft.add_child(UIKit.label(Defs.date_text(int(f.day)).split(",")[0], 12, UIKit.MUTED))
				fv.add_child(UIKit.para(str(f.ending), 13))


func _short(n: int) -> String:
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


# ----------------------------------------------------------------- members

func _members(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	var mem := sim.members
	body.add_child(UIKit.para("Golfers who love their round join the club and come back as regulars. Every tier above Basic is unlocked by a different private wish. Give a member a round that grants it and they move up and pay more in dues. Two miserable rounds in a row and they resign. Regulars get a little better every visit, and faster at the range and on the practice green, and they keep it."))
	var summary := UIKit.hbox(4)
	body.add_child(summary)
	var tier_labels: Array[Label] = []
	for t in mem.tiers.size():
		var chip := UIKit.card(Color(1, 1, 1, 0.06))
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.add_child(chip)
		var cv := UIKit.vbox(0)
		chip.add_child(cv)
		var n := UIKit.label("0", 18, mem.tier_color(t))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(n)
		var nm := UIKit.label(mem.tier_name(t), 10, UIKit.MUTED)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nm)
		tier_labels.append(n)
	var dues := UIKit.row("Dues collected each month", "")
	body.add_child(dues)
	var cap := UIKit.row("Members", "")
	body.add_child(cap)
	var gates := UIKit.para("", 12)
	body.add_child(gates)
	body.add_child(UIKit.heading("Roster"))
	var list := UIKit.vbox(6)
	body.add_child(list)
	var shown := [""]
	return func() -> void:
		for t in mem.tiers.size():
			tier_labels[t].text = str(mem.count_tier(t))
		(dues.get_node("Value") as Label).text = Defs.money(mem.monthly_dues())
		(cap.get_node("Value") as Label).text = "%d of %d places" % [mem.count(), mem.capacity()]
		var need := ""
		for t in range(3, mem.tiers.size()):
			var tier: Dictionary = mem.tiers[t]
			var ok := sim.rating >= float(tier.rating) and sim.course.holes.size() >= int(tier.holes)
			if not ok:
				need += "%s needs a rating of %d%s. " % [str(tier.name), int(tier.rating), "" if int(tier.holes) == 0 else " and %d holes" % int(tier.holes)]
		gates.text = need
		# rebuild the roster only when it changes
		var sig := ""
		for m in mem.roster:
			sig += "%d%d%d%s%d%d%d" % [int(m.id), int(m.tier), int(m.visits), str(m.known), int(m.strikes), int(float(m.get("power", 0.0)) * 1000.0), int(float(m.get("putting", 0.0)) * 1000.0)]
		if sig == shown[0]:
			return
		shown[0] = sig
		UIKit.clear(list)
		if mem.roster.is_empty():
			list.add_child(UIKit.para("Nobody has joined yet. Golfers who leave at 70% happy or better may sign up.", 14, UIKit.WARN))
		var sorted := mem.roster.duplicate()
		sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.tier) != int(b.tier):
				return int(a.tier) > int(b.tier)
			return int(a.visits) > int(b.visits))
		for i in mini(sorted.size(), 40):
			var m: Dictionary = sorted[i]
			var t := int(m.tier)
			var card := UIKit.card()
			list.add_child(card)
			var v := UIKit.vbox(2)
			card.add_child(v)
			var h := UIKit.hbox(6)
			v.add_child(h)
			var sw := ColorRect.new()
			sw.color = mem.tier_color(t)
			sw.custom_minimum_size = Vector2(8, 18)
			h.add_child(sw)
			h.add_child(UIKit.label(str(m.name), 14))
			h.add_child(UIKit.label(mem.tier_name(t), 12, mem.tier_color(t)))
			h.add_child(UIKit.spacer())
			var mood := float(m.last_mood)
			h.add_child(UIKit.label("%d visit%s  ·  last round %d%%" % [int(m.visits), "" if int(m.visits) == 1 else "s", int(mood)], 11, UIKit.mood_color(mood)))
			var prog := sim.members.progress
			var length := roundi(clampf(Members.power_share(float(m.get("power", 0.9)), prog), 0.0, 1.0) * 100.0)
			var putt := int(round(clampf(float(m.get("putting", 0.0)) / float(prog["skill_cap"]), 0.0, 1.0) * 100.0))
			v.add_child(UIKit.label("Length %d  ·  Putting %d" % [length, putt], 11, UIKit.MUTED))
			var persona := DataDB.find(sim.db.personalities, str(m.persona))
			var line := str(persona.get("name", ""))
			if m.home:
				line += "  ·  owns a home here"
			if int(m.strikes) > 0:
				line += "  ·  thinking of resigning"
			v.add_child(UIKit.label(line, 11, UIKit.BAD if int(m.strikes) > 0 else UIKit.MUTED))
			if t < mem.tiers.size() - 1:
				var want := str(m.wants[t])
				var next_name := mem.tier_name(t + 1)
				if m.known[t]:
					v.add_child(UIKit.para("To reach %s: %s." % [next_name, str(mem.factor(want).hint)], 12, UIKit.GOLD))
				else:
					v.add_child(UIKit.para("To reach %s: something they have not told you yet." % next_name, 12, UIKit.MUTED))
			else:
				v.add_child(UIKit.para("At the top tier. Keep them happy.", 12, UIKit.GOLD))
		if sorted.size() > 40:
			list.add_child(UIKit.label("and %d more" % (sorted.size() - 40), 12, UIKit.MUTED))


# -------------------------------------------------------------------- play

func _play(body: VBoxContainer) -> Callable:
	var sim := hud.sim
	body.add_child(UIKit.para("Take your own clubs out on the course you built. The simulation keeps running, so watch out for the group ahead. They will not enjoy being hit, but it does count toward your records."))
	var n := sim.course.holes.size()
	if n == 0:
		body.add_child(UIKit.para("There are no holes to play yet.", 15, UIKit.WARN))
		return Callable()
	var go := UIKit.button("Play all %d holes" % n, func() -> void:
		hud.close_dock()
		hud.play.start(sim, hud.rig, 0, -1))
	go.custom_minimum_size = Vector2(0, 44)
	body.add_child(go)
	body.add_child(UIKit.heading("Or play one hole"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for i in n:
		var hole := sim.course.holes[i]
		var b := UIKit.button("%d  ·  par %d  ·  %d yd" % [i + 1, hole.par, Defs.yards(hole.length)], func() -> void:
			hud.close_dock()
			hud.play.start(sim, hud.rig, i, 1))
		_wide(b)
		grid.add_child(b)
	body.add_child(UIKit.gap(6))
	body.add_child(UIKit.heading("How to play"))
	body.add_child(UIKit.para("A and D turn your aim. W and S change club. Press Space to start the marker up the bar, again to set the power where you stop it, and once more as it comes back to the line. Early hooks, late slices, and there are no second goes. With a controller, pull the right stick back and push it forward.\n\nThe gold line on the meter marks the power that reaches the pin. On the green, turn on Contours to read the break.", 14, UIKit.TEXT))
	var bag := UIKit.label("", 13, UIKit.MUTED)
	body.add_child(bag)
	return func() -> void:
		bag.text = "In the bag: %s woods, %s irons, %s ball." % [
			sim.db.brand(str(sim.player.equipped.woods)).name, sim.db.brand(str(sim.player.equipped.irons)).name, sim.db.ball(sim.player.ball_id).name]
