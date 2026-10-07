extends Node
## Headless checks on the simulation. Run with ./check.sh

var failures := 0
var checks := 0
var db: DataDB
var gear: Gear


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("  FAIL: ", what)


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	db = DataDB.new()
	gear = Gear.new(db)
	print("club tables built in %d ms" % (Time.get_ticks_msec() - t0))
	_test_physics()
	_test_generator()
	_test_equipment()
	_test_building()
	_test_clubhouse()
	_test_collisions()
	_test_spin_wind_lies()
	_test_seasons_and_scorecard()
	_test_planner()
	_test_tee_line()
	_test_night()
	_test_career()
	_test_gamepad()
	_test_sounds()
	_test_fees()
	_test_difficulty()
	_test_hit()
	_test_turf()
	_test_skills_and_goals()
	_test_events()
	_test_season()
	_test_save()
	_test_biomes()
	_test_land()
	_test_eruption()
	_test_paths()
	_test_personalities()
	_test_facilities()
	_test_bar_and_vending()
	_test_membership()
	_test_stories()
	_test_hole_lab()
	_test_club_life()
	_test_gallery()
	_test_dogleg()
	_test_mood_map()
	print("%d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


## A game for testing. The clock is stopped at noon so that tests about
## other things are not interrupted by nightfall; the day and night tests
## start it again.
func _sim(scenario: String, seed_value: int = 1) -> Sim:
	var sim := Sim.new(db, DataDB.find(db.scenarios, scenario), seed_value, gear)
	sim.clock = 12.0
	sim.clock_rate = 0.0
	# the long stories bring their own members and tee times; the tests that
	# are about them switch them on
	sim.stories.enabled = false
	return sim


func _run(sim: Sim, seconds: float) -> void:
	for i in int(seconds * 60.0):
		sim.step(1.0 / 60.0)


func _lane(terrain: int = Defs.T.FAIRWAY) -> Course:
	var lane := Course.new(160, 24)
	lane.terrain.fill(terrain)
	return lane


## Fire one shot down a flat lane and return the ball when it stops.
func _shoot(lane: Course, speed: float, loft_deg: float, lift: float, wind: Vector3 = Vector3.ZERO, def: Dictionary = {}, side: float = 0.0) -> Ball:
	var b := Ball.new()
	b.set_def(def)
	b.place(Vector3(10.0, 0.0, 60.0))
	b.launch(speed, 0.0, deg_to_rad(loft_deg), lift, side, 0.2)
	var n := 0
	while b.moving() and n < 5000:
		b.step(1.0 / 60.0, lane, wind, Vector3.ZERO, false)
		n += 1
	return b


func _test_physics() -> void:
	print("-- ball physics")
	var driver := gear.total_at(0, db.clubs[0].speed)
	var wedge := gear.total_at(10, db.clubs[10].speed)
	print("   driver %.0f m, sand wedge %.0f m" % [driver, wedge])
	check(driver > 200.0 and driver < 290.0, "driver distance is sensible")
	check(wedge > 60.0 and wedge < 110.0, "wedge distance is sensible")
	var lane := _lane()
	lane.wet.fill(0.05)
	var dry := _shoot(lane, 74.7, 12.0, 0.15).pos.x
	lane.wet.fill(0.9)
	var wet := _shoot(lane, 74.7, 12.0, 0.15).pos.x
	lane.wet.fill(0.2)
	print("   drive on dry ground %.0f m, on soaked ground %.0f m" % [dry - 10.0, wet - 10.0])
	check(wet < dry - 10.0, "soaked ground shortens the shot")
	var calm := _shoot(lane, 60.0, 16.0, 0.2).carry.x
	var head := _shoot(lane, 60.0, 16.0, 0.2, Vector3(-8.0, 0.0, 0.0)).carry.x
	var tail := _shoot(lane, 60.0, 16.0, 0.2, Vector3(8.0, 0.0, 0.0)).carry.x
	var cross := _shoot(lane, 60.0, 16.0, 0.2, Vector3(0.0, 0.0, 8.0))
	print("   carry calm %.0f, headwind %.0f, tailwind %.0f, crosswind drift %.1f m" % [calm - 10.0, head - 10.0, tail - 10.0, cross.carry.z - 60.0])
	check(head < calm - 8.0 and tail > calm + 4.0, "head and tail wind change the carry")
	check(cross.carry.z - 60.0 > 3.0, "a crosswind pushes the ball sideways")
	var slice := _shoot(lane, 60.0, 16.0, 0.2, Vector3.ZERO, {}, 0.06)
	check(slice.carry.z - 60.0 > 3.0, "sidespin curves the ball")
	# slopes
	var hill := Course.new(20, 20)
	hill.terrain.fill(Defs.T.GREEN)
	for vy in 21:
		for vx in 21:
			hill.heights[vy * 21 + vx] = vx * 0.3
	var b := Ball.new()
	b.place(hill.on_ground(50.0, 50.0))
	b.launch(1.0, PI * 0.5, 0.0, 0.0, 0.0, 0.0)
	var n := 0
	while b.moving() and n < 3000:
		b.step(1.0 / 60.0, hill, Vector3.ZERO, Vector3.ZERO, false)
		n += 1
	check(b.pos.x < 49.9, "a putt breaks down the slope")
	# the cup
	var green := _lane(Defs.T.GREEN)
	var putt := Ball.new()
	putt.place(Vector3(10.0, 0.0, 60.0))
	putt.launch(2.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	var pin := Vector3(12.0, 0.0, 60.0)
	n = 0
	while putt.moving() and n < 2000:
		putt.step(1.0 / 60.0, green, Vector3.ZERO, pin, true)
		n += 1
	check(putt.state == Ball.S.HOLED, "a putt on line at a sane pace drops")
	# special balls
	var windy := Vector3(0.0, 0.0, 9.0)
	var plain := _shoot(lane, 60.0, 16.0, 0.2, windy).carry.z
	var cutter := _shoot(lane, 60.0, 16.0, 0.2, windy, db.ball("windcutter")).carry.z
	check(cutter - 60.0 < (plain - 60.0) * 0.7, "the Windcutter ball drifts less")
	lane.wet.fill(0.9)
	var soggy := _shoot(lane, 74.7, 12.0, 0.15).pos.x
	var mud := _shoot(lane, 74.7, 12.0, 0.15, Vector3.ZERO, db.ball("mudder")).pos.x
	lane.wet.fill(0.2)
	check(mud > soggy + 8.0, "the Mudder ball ignores soggy ground")
	var pond := _lane()
	for tx in range(8, 12):
		for ty in 24:
			pond.terrain[ty * 160 + tx] = Defs.T.WATER
	var sunk := _shoot(pond, 40.0, 6.0, 0.02)
	var skip := _shoot(pond, 40.0, 6.0, 0.02, Vector3.ZERO, db.ball("skipper"))
	print("   into the pond: plain ball %s at %.0f m, Skipper %s at %.0f m with %d skips left" % [Ball.S.keys()[sunk.state], sunk.pos.x, Ball.S.keys()[skip.state], skip.pos.x, skip.skips])
	check(sunk.state == Ball.S.WATER, "a low shot into a pond sinks")
	check(skip.state != Ball.S.WATER and skip.pos.x > 60.0, "the Skipper ball skips across")
	var rocket := _shoot(lane, 60.0, 16.0, 0.2, Vector3.ZERO, db.ball("rocket")).carry.x
	check(rocket > calm + 4.0, "the Rocket Core ball flies further")
	# trees
	var woods := _lane()
	for ty in 24:
		woods.objects[ty * 160 + 12] = Defs.O.OAK
	var stopped := 0
	for i in 12:
		var tb := Ball.new()
		tb.place(Vector3(40.0 + i * 0.37, 0.0, 60.0 + i * 0.11))
		tb.launch(55.0, 0.0, deg_to_rad(13.0), 0.1, 0.0, 0.2)
		var k := 0
		while tb.moving() and k < 4000:
			tb.step(1.0 / 60.0, woods, Vector3.ZERO, Vector3.ZERO, false)
			k += 1
		if tb.pos.x < 150.0:
			stopped += 1
	check(stopped >= 4, "trees knock down low shots (%d of 12)" % stopped)


func _test_generator() -> void:
	print("-- generated courses")
	var rng := RandomNumberGenerator.new()
	var bad := 0
	var ponds := 0
	var made := 0
	for scen: Dictionary in db.scenarios:
		for seed_value in 12:
			rng.seed = 1000 + seed_value
			var c := CourseGen.generate(scen.map, rng)
			made += 1
			if c.terrain.has(Defs.T.WATER):
				ponds += 1
			if c.holes.size() != int(scen.map.holes):
				bad += 1
			for hole in c.holes:
				if c.terrain_at(hole.pin.x, hole.pin.z) != Defs.T.GREEN or c.terrain_at(hole.tee.x, hole.tee.z) != Defs.T.TEE:
					bad += 1
				# the middle of every fairway must be dry land
				for k in range(1, 10):
					var p := hole.tee.lerp(hole.pin, k / 10.0)
					if c.terrain_at(p.x, p.z) == Defs.T.WATER:
						bad += 1
				if absf(hole.pin.y - c.height_at(hole.pin.x, hole.pin.z)) > 0.01:
					bad += 1
				if c.gradient_at(hole.pin.x, hole.pin.z).length() > 0.06:
					bad += 1
	print("   %d courses generated, %d with water, %d problems" % [made, ponds, bad])
	check(bad == 0, "every generated hole has a dry tee, a green under the pin, and a puttable slope")
	check(ponds > made / 2, "most courses get a pond")


func _test_equipment() -> void:
	print("-- clubs and the pro shop")
	var sim := _sim("three_holes")
	var g := sim.player.golfer
	var rental := sim.gear.max_total(g, Defs.T.TEE)
	check(sim.player.buy("woods", "thunderhead"), "can buy Thunderhead woods")
	var power := sim.gear.max_total(g, Defs.T.TEE)
	check(sim.player.buy("woods", "pinpoint"), "can buy Pinpoint woods")
	var accurate := sim.gear.max_total(g, Defs.T.TEE)
	print("   driver reach: rentals %.0f m, Thunderhead %.0f m, Pinpoint %.0f m" % [rental, power, accurate])
	check(power > rental + 8.0 and accurate < rental, "power clubs go further, accuracy clubs shorter")
	check(float(db.brand("pinpoint").spread) < float(db.brand("thunderhead").spread), "accuracy clubs stray less")
	check(sim.economy.money < 30000.0, "clubs cost money")
	check(sim.player.buy_balls("skipper") and sim.player.ball_count("skipper") == 3, "balls come in threes")
	check(sim.player.use_ball("skipper") and g.ball.def.id == "skipper", "can put a special ball in play")
	for i in 3:
		sim.player.lose_ball()
	check(sim.player.ball_id == "standard", "running out of a ball falls back to the standard one")


func _test_building() -> void:
	print("-- building a hole from nothing")
	var sim := _sim("sandbox", 5)
	check(sim.course.holes.is_empty(), "sandbox starts with no holes")
	check(sim.rating == 0.0, "no holes, no rating")
	var before := sim.economy.money
	var cx := 60
	check(sim.paint(cx, 30, 2, Defs.T.GREEN) > 0, "can paint a green")
	for ty in range(34, 80, 2):
		sim.paint(cx, ty, 2, Defs.T.FAIRWAY)
	sim.paint(cx, 90, 1, Defs.T.TEE)
	check(sim.economy.money < before, "painting costs money")
	var tee := sim.course.tile_center(cx, 90)
	var pin := sim.course.tile_center(cx, 30)
	var hole := sim.add_hole(tee, pin)
	sim.reputation = 50.0
	check(hole != null and hole.par == 4, "a 300 m hole is a par 4")
	check(sim.course.terrain_at(pin.x, pin.z) == Defs.T.GREEN, "the pin sits on the green")
	# sculpting changes the ground and what a ball does on it
	var spot := sim.course.tile_center(cx + 20, 60)
	var h0 := sim.course.height_at(spot.x, spot.z)
	var g0 := sim.course.gradient_at(spot.x + 6.0, spot.z)
	for i in 8:
		sim.sculpt("raise", spot.x, spot.z, 15.0, 0.2)
	check(sim.course.height_at(spot.x, spot.z) > h0 + 1.0, "sculpting raises the land")
	check(sim.course.gradient_at(spot.x + 6.0, spot.z).distance_to(g0) > 0.05, "and changes the slope around it")
	check(sim.place_object(cx + 6, 60, Defs.O.OAK) == 1, "can plant a tree")
	check(sim.place_object(cx, 30, Defs.O.OAK) == 0, "cannot plant a tree on a green")
	check(sim.place_object(cx + 8, 62, Defs.O.DRINK_STAND) == 1, "can build a drink stand")
	_run(sim, 425.0)
	print("   after a month: %d plays, average %.1f, green fees %s" % [hole.plays, hole.average_score(), Defs.money(float(sim.economy.history[0].income.get("green_fees", 0.0)))])
	check(hole.plays >= 3, "golfers find and play the new hole")
	check(hole.average_score() < 7.5, "and can finish it in a sane number of shots")
	check(float(sim.economy.history[0].income.get("green_fees", 0.0)) > 0.0, "the hole earns green fees")
	sim.remove_hole(0)
	_run(sim, 60.0)
	check(sim.course.holes.is_empty(), "a hole can be closed while golfers are on it")


## Fly or roll a ball until it stops, noting what it bounced off.
func _fly(b: Ball, c: Course, limit: int = 6000) -> Dictionary:
	var seen := {"hit": false, "tree": false, "mat": "", "bounced_back": false, "inside": false, "max_side": 0.0}
	var k := 0
	while b.moving() and k < limit:
		var ev := b.step(1.0 / 60.0, c, Vector3.ZERO, Vector3.ZERO, false)
		if ev == Ball.E.HIT:
			if not seen.hit:
				seen.mat = b.hit_mat
				seen.bounced_back = b.vel.x < 0.0
				seen.max_side = absf(b.vel.z)
			seen.hit = true
		elif ev == Ball.E.TREE:
			seen.tree = true
		k += 1
	return seen


func _test_clubhouse() -> void:
	print("-- the clubhouse ladder")
	var sim := _sim("first_tee", 3)
	var levels: Array = sim.db.clubhouse.get("levels", [])
	check(levels.size() >= 5 and sim.clubhouse_level == 0 and sim.hole_cap() == 3, "a new club starts in a starter clubhouse that allows three holes")
	var last_holes := 0
	var last_cost := 0.0
	var climbs := true
	for i in levels.size():
		var lv: Dictionary = levels[i]
		if int(lv.holes) <= last_holes or (i > 0 and float(lv.get("cost", 0.0)) <= last_cost):
			climbs = false
		last_holes = int(lv.holes)
		last_cost = float(lv.get("cost", 0.0))
	check(climbs and last_holes == 18, "each step allows more holes and costs more, up to eighteen")
	var tiers_asked: Array[String] = []
	for lv: Dictionary in levels:
		if lv.has("tier"):
			tiers_asked.append(str(lv.tier))
	check(tiers_asked.size() >= 3 and tiers_asked.has("gold"), "the upper steps ask for members in the higher tiers (%s)" % ", ".join(PackedStringArray(tiers_asked)))
	# the cap holds
	var c := sim.course
	sim.economy.money = 500000.0
	sim.paint(40, 30, 2, Defs.T.GREEN)
	sim.paint(40, 60, 1, Defs.T.TEE)
	check(sim.add_hole(c.tile_center(40, 60), c.tile_center(40, 30)) == null and c.holes.size() == 3, "a fourth hole is refused with a starter clubhouse")
	# each requirement blocks on its own
	var needs := sim.clubhouse_needs()
	check(needs.size() >= 3, "the next step lists what it needs (%d things)" % needs.size())
	var cash_ok := false
	for n in needs:
		if str(n.what) == "cash":
			cash_ok = bool(n.met)
	check(cash_ok and not sim.can_upgrade_clubhouse(), "with only the money, the club is not ready")
	for k in 4:
		sim.members.enroll(sim.visitors.make_golfer("public", 0.5))
	sim.rating = 30.0
	check(not sim.can_upgrade_clubhouse(), "members without a reputation are not enough")
	sim.rating = 45.0
	var money := sim.economy.money
	check(sim.upgrade_clubhouse() and sim.clubhouse_level == 1 and sim.hole_cap() == 6, "money, members and a rating together open the next step")
	check(is_equal_approx(money - sim.economy.money, float((levels[1] as Dictionary).cost)), "and it costs what the data says")
	check(sim.add_hole(c.tile_center(40, 60), c.tile_center(40, 30)) != null and c.holes.size() == 4, "now a fourth hole can be laid out")
	# the step after wants members of a higher tier
	sim.economy.money = 500000.0
	sim.rating = 90.0
	for k in 12:
		sim.members.enroll(sim.visitors.make_golfer("public", 0.5))
	check(not sim.can_upgrade_clubhouse(), "plenty of Basic members do not satisfy a step that asks for Advanced ones")
	var want_tier := sim.members.tier_index(str((levels[2] as Dictionary).tier))
	for k in int((levels[2] as Dictionary).get("tier_count", 1)):
		sim.members.roster[k].tier = want_tier
	check(sim.can_upgrade_clubhouse() and sim.upgrade_clubhouse() and sim.hole_cap() == 9, "members who have moved up the tiers do")
	# starting levels fit starting holes
	var weedy := _sim("weed_patch", 2)
	check(weedy.course.holes.size() == 5 and weedy.clubhouse_level == 1 and weedy.hole_cap() >= 5, "a scenario that starts with five holes starts with the clubhouse to match")
	var box := _sim("sandbox", 2)
	check(box.open_build() and box.hole_cap() == 18 and box.clubhouse_needs().is_empty() or box.hole_cap() == 18, "the sandbox is not gated")
	# the level survives a save
	var back := Sim.from_dict(sim.db, JSON.parse_string(JSON.stringify(sim.to_dict())), gear)
	check(back.clubhouse_level == 2 and back.hole_cap() == 9, "the clubhouse level survives a save")


func _loose(at: Vector3, v: Vector3) -> Ball:
	var b := Ball.new()
	b.place(at)
	b.launch(1.0, 0.0, 0.5, 0.0, 0.0, 0.0)
	b.pos = at
	b.prev = at
	b.vel = v
	return b


func _test_collisions() -> void:
	print("-- collisions and ricochets")
	var c := _lane()
	var w := c.w
	# a tree trunk
	c.set_object(20, 12, Defs.O.OAK)
	var oak_i := 12 * w + 20
	var off := Defs.plant_offset(oak_i)
	var trunk := Vector3(102.5 + off.x, 0.0, 62.5 + off.y)
	check(c.solids.count() == 2, "an oak is a trunk and a crown of leaves to a golf ball")
	var b1 := Ball.new()
	b1.place(trunk + Vector3(-15.0, 0.0, 0.0))
	b1.launch(40.0, 0.0, deg_to_rad(3.0), 0.0, 0.0, 0.0)
	var r1 := _fly(b1, c)
	print("   low shot at an oak: hit %s, came back %s, finished %.1f m short of the trunk" % [r1.mat, str(r1.bounced_back), trunk.x - b1.pos.x])
	check(r1.hit and r1.mat == "wood", "a low shot at a trunk hits wood")
	check(r1.bounced_back and b1.pos.x < trunk.x, "and ricochets back the way it came")
	var b1b := Ball.new()
	b1b.place(trunk + Vector3(-15.0, 0.0, 0.0))
	b1b.launch(40.0, 0.0, deg_to_rad(3.0), 0.0, 0.0, 0.0)
	_fly(b1b, c)
	check(b1.pos.is_equal_approx(b1b.pos), "the same shot bounces the same way every time")
	var fast := Ball.new()
	fast.place(trunk + Vector3(-9.0, 0.0, 0.0))
	fast.launch(78.0, 0.0, deg_to_rad(2.0), 0.0, 0.0, 0.0)
	check(_fly(fast, c).hit, "a full-blooded drive cannot pass through a trunk between two moments")
	# a wall
	c.set_object(40, 12, Defs.O.RESTROOM)
	var b2 := Ball.new()
	b2.place(Vector3(185.0, 0.0, 62.5))
	b2.launch(35.0, 0.0, deg_to_rad(4.0), 0.0, 0.0, 0.0)
	var r2 := _fly(b2, c)
	print("   low shot at the restroom: hit %s, finished %.1f m in front of the wall" % [r2.mat, 200.5 - b2.pos.x])
	check(r2.hit and r2.mat == "wall" and b2.pos.x < 200.5, "a ball bounces off a wall and stays outside")
	# a roof
	c.set_object(60, 12, Defs.O.HOUSE)
	var b3 := _loose(Vector3(301.7, 12.0, 62.2), Vector3(0.4, -4.0, 0.3))
	var r3 := _fly(b3, c)
	var on_ground := b3.pos.y < 0.3
	var outside := absf(b3.pos.x - 302.5) > 2.1 or absf(b3.pos.z - 62.5) > 1.9
	print("   dropped on a house: hit %s, came to rest %.1f m from the middle of the house, %.2f m up" % [r3.mat, Vector2(b3.pos.x - 302.5, b3.pos.z - 62.5).length(), b3.pos.y])
	check(r3.hit and r3.mat == "roof", "a ball landing on a house hits the roof")
	check(on_ground and outside, "and runs off it down to the ground")
	# a glancing blow off a boulder
	c.set_object(80, 12, Defs.O.BOULDER)
	var rock: Solids.Shape = null
	for sh: Solids.Shape in c.solids.bucket(12 * w + 80):
		if sh.kind == Solids.K.ROCK and (rock == null or sh.r > rock.r):
			rock = sh
	var b4 := Ball.new()
	b4.place(Vector3(rock.x - 12.0, 0.0, rock.z + rock.r * 0.7))
	b4.launch(30.0, 0.0, deg_to_rad(2.0), 0.0, 0.0, 0.0)
	var r4 := _fly(b4, c)
	print("   glancing a boulder: hit %s, kicked sideways at %.1f m/s" % [r4.mat, r4.max_side])
	check(r4.hit and r4.mat == "stone" and r4.max_side > 3.0, "a glancing blow off a boulder kicks the ball sideways")
	# through the leaves
	c.set_object(100, 12, Defs.O.OAK)
	var crown: Solids.Shape = null
	for sh: Solids.Shape in c.solids.bucket(12 * w + 100):
		if sh.kind == Solids.K.LEAVES:
			crown = sh
	var mid := (crown.y0 + crown.y1) * 0.5
	var branches := 0
	var slowed := 0
	for k in 40:
		var start := Vector3(crown.x - 9.0, mid + (k % 5 - 2) * 0.6, crown.z + (k / 5 - 4) * 0.45)
		var lb := _loose(start, Vector3(34.0, 2.0, 0.0))
		var free := _loose(start + Vector3(0.0, 0.0, 30.0), Vector3(34.0, 2.0, 0.0))
		var met := false
		for step in 30:
			if lb.step(1.0 / 60.0, c, Vector3.ZERO, Vector3.ZERO, false) == Ball.E.TREE:
				met = true
			free.step(1.0 / 60.0, c, Vector3.ZERO, Vector3.ZERO, false)
		if met:
			branches += 1
		if lb.vel.length() < free.vel.length() * 0.97:
			slowed += 1
	print("   40 shots through an oak's crown: %d slowed by the leaves, %d stopped by a branch" % [slowed, branches])
	check(slowed >= 36, "leaves take speed off a ball")
	check(branches >= 6 and branches <= 36, "and some shots, not all, find a branch")
	# rolling into a post, then taking the post away
	c.set_object(120, 12, Defs.O.LAMP)
	var post := Vector3(602.5, 0.0, 62.5)
	var b6 := Ball.new()
	b6.place(post + Vector3(-5.0, 0.0, 0.0))
	b6.launch(6.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	var r6 := _fly(b6, c)
	check(r6.hit and r6.mat == "metal" and b6.pos.x < post.x, "a rolling ball bounces off a lamp post")
	c.set_object(120, 12, Defs.O.NONE)
	var b7 := Ball.new()
	b7.place(post + Vector3(-5.0, 0.0, 0.0))
	b7.launch(6.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	var r7 := _fly(b7, c)
	check(not r7.hit and b7.pos.x > post.x, "and rolls on through once the post is gone")
	# a bush swallows a rolling ball
	c.set_object(140, 12, Defs.O.BUSH)
	var boff := Defs.plant_offset(12 * w + 140)
	var bush := Vector3(702.5 + boff.x, 0.0, 62.5 + boff.y)
	var b8 := Ball.new()
	b8.place(bush + Vector3(-6.0, 0.0, 0.0))
	b8.launch(9.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	_fly(b8, c)
	check(b8.pos.distance_to(bush) < 1.6, "a ball rolling into a bush stays in it (stopped %.1f m from its middle)" % b8.pos.distance_to(bush))
	# every kind of object in every biome has its shapes
	var missing := []
	for bio: Dictionary in db.biomes:
		var probe := Course.new(8, 8)
		probe.biome = bio
		for o in range(1, Defs.O_NAMES.size()):
			var kind := probe.kind_of(o)
			if not Solids.data().kinds.has(kind) and Defs.O_COST[o] > 0 and not (o in [Defs.O.BRIDGE, Defs.O.PUTTING_GREEN, Defs.O.HOME_SITE, Defs.O.TENNIS]):
				missing.append("%s/%s" % [bio.id, kind])
	check(missing.is_empty(), "every solid object in every biome can be hit %s" % str(missing))
	# a whole course plays with it
	var sim := _sim("three_holes", 21)
	_run(sim, 400.0)
	print("   400 s on a real course: %d shapes to hit, %d ricochets, %d holes played" % [sim.course.solids.count(), int(sim.stats.ricochets), sim.stats.holes_played])
	check(sim.course.solids.count() > 100 and sim.stats.holes_played > 5, "golfers play on among things they can hit")


## Stand floodlights beside a hole from tee to green.
func _light_hole(sim: Sim, hole: Hole) -> int:
	var course := sim.course
	var placed := 0
	var n := maxi(2, int(hole.length / 35.0) + 1)
	for k in n + 1:
		var t := float(k) / n
		var p := hole.point_along(t)
		var dir2 := hole.direction_at(t)
		var side := Vector3(-dir2.y, 0.0, dir2.x)
		for off: float in [14.0, -14.0, 20.0, -20.0, 9.0, -9.0]:
			var q := p + side * off
			var tile := course.tile_of(q.x, q.z)
			if sim.place_object(tile.x, tile.y, Defs.O.FLOODLIGHT) == 1:
				placed += 1
				break
	return placed


func _test_night() -> void:
	print("-- day and night")
	check(Defs.darkness(12.0) == 0.0 and Defs.darkness(0.5) == 1.0, "noon is light and midnight is dark")
	check(Defs.darkness(Defs.SUNSET) > 0.3 and Defs.darkness(Defs.SUNSET) < 0.7, "sunset is somewhere in between")
	check(Defs.clock_text(15.67) == "3:40 PM" and Defs.clock_text(0.2) == "12:10 AM", "the clock reads like a clock (%s, %s)" % [Defs.clock_text(15.67), Defs.clock_text(0.2)])
	var sim := _sim("three_holes", 33)
	sim.events.timer = 99999.0
	sim.clock_rate = 1.0
	sim.clock = 7.0
	_run(sim, Defs.CLOCK_DAY_SECONDS * 0.5)
	check(absf(sim.clock - 19.0) < 0.05, "half a day later the clock has moved twelve hours (%.2f)" % sim.clock)
	# night on a course with no lights
	sim.clock_rate = 0.0
	sim.clock = 12.0
	var day_rate := sim.arrival_rate()
	sim.clock = 23.0
	var hole := sim.course.holes[0]
	var dark_rate := sim.arrival_rate()
	check(sim.darkness() == 1.0 and sim.sight_at(hole.pin) < 0.05, "at eleven at night an unlit green is in darkness")
	check(not hole.lit_enough(sim.course) and sim.too_dark_for(hole), "and the hole counts as dark")
	check(dark_rate > 0.0 and dark_rate < day_rate * 0.3, "few golfers turn up at night on an unlit course (%d%% of the daytime rate)" % int(dark_rate / day_rate * 100.0))
	_run(sim, 900.0)
	var dark_paid := 0.0
	var dark_payers := 0
	for hh in sim.course.holes:
		dark_paid += hh.earned
		dark_payers += hh.payers
	var grumbled := false
	for p in sim.feed.posts:
		if p.kind == "too_dark":
			grumbled = true
	check(dark_payers > 0, "the ones who do come play on in the dark")
	check(grumbled and sim.told_dark, "they complain about it, and the owner is told what would help")
	# light every hole
	sim.economy.money = 400000.0
	var masts := 0
	for hh in sim.course.holes:
		masts += _light_hole(sim, hh)
	print("   %d floodlights light hole 1 to %d%%, and %d%% of the holes are lit" % [masts, int(hole.lit_share(sim.course) * 100.0), int(sim.lit_holes_share() * 100.0)])
	check(hole.lit_enough(sim.course) and sim.lit_holes_share() == 1.0, "floodlights along the holes light them for night golf")
	check(sim.sight_at(hole.pin) > 0.9, "the green can be seen again")
	var lit_rate := sim.arrival_rate()
	sim.clock = 12.0
	var day_now := sim.arrival_rate()
	sim.clock = 23.0
	check(lit_rate > day_now * 0.7 and lit_rate < day_now, "a lit course is nearly as busy by night as by day (%d%%)" % int(lit_rate / day_now * 100.0))
	_run(sim, 900.0)
	var lit_paid := -dark_paid
	var lit_payers := -dark_payers
	for hh in sim.course.holes:
		lit_paid += hh.earned
		lit_payers += hh.payers
	var per_dark := dark_paid / maxf(dark_payers, 1.0)
	var per_lit := lit_paid / maxf(lit_payers, 1.0)
	print("   at night a hole earns %s a golfer unlit and %s lit; %d holes paid for in the dark, then %d under lights" % [Defs.money(per_dark), Defs.money(per_lit), dark_payers, lit_payers])
	check(lit_payers > 0, "golfers play on under the lights")
	# A few dozen golfers is too few to compare those two averages (the same
	# night can come out either way), so check the rule on one golfer: the
	# same round, on the same hole, lit and unlit.
	var twins := sim.visitors.add_group("public", 2, 0.5, 0.0)
	var in_dark := twins.members[0]
	var in_light := twins.members[1]
	for tw in twins.members:
		tw.persona = {}
		tw.wealth = 0.5
		tw.satisfaction = 60.0
		tw.begin_hole()
	var solo := sim.visitors.add_group("public", 1, 0.5, 0.0)
	solo.members.clear()
	solo.members.append(in_dark)
	sim.visitors.on_dark_hole(solo, 0)
	var joy_dark := sim.visitors.enjoyment(in_dark)
	var joy_lit := sim.visitors.enjoyment(in_light)
	var fee_dark := sim.visitors.worth(in_dark, hole) * Visitors.pay_share(joy_dark)
	var fee_lit := sim.visitors.worth(in_light, hole) * Visitors.pay_share(joy_lit)
	print("   the same golfer pays %s for a hole played in the dark and %s for one they can see" % [Defs.money(fee_dark), Defs.money(fee_lit)])
	check(fee_lit > fee_dark * 1.1, "golfers pay more for a hole they can see")
	check(lit_rate > dark_rate * 2.0, "and far more of them turn up (%d%% of the daytime rate against %d%%)" % [int(lit_rate / day_now * 100.0), int(dark_rate / day_rate * 100.0)])
	check(int(sim.stats.night_holes) > 0, "night golf is counted")
	var happy := false
	for p in sim.feed.posts:
		if p.kind == "night_golf":
			happy = true
	check(happy, "and golfers post about playing under the lights")
	# a light taken away darkens the hole again
	var lights0 := sim.course.lights_rev
	for i in sim.course.objects.size():
		if sim.course.objects[i] == Defs.O.FLOODLIGHT:
			sim.remove_object(i % sim.course.w, i / sim.course.w)
	check(sim.course.lights_rev != lights0 and not hole.lit_enough(sim.course), "take the lights away and the hole goes dark again")
	# the hour survives a save
	var copy := Sim.from_dict(db, sim.to_dict(), gear)
	check(absf(copy.clock - sim.clock) < 0.01, "a saved game remembers the time of day")
	# a whole day and night with the clock running
	var live := Sim.new(db, DataDB.find(db.scenarios, "three_holes"), 34, gear)
	live.events.timer = 99999.0
	var by_day := 0
	var by_night := 0
	var came_by_day := 0
	var came_by_night := 0
	var last := 0
	var last_gid := live.visitors._gid
	var arrivals := ""
	for i in int(Defs.CLOCK_DAY_SECONDS * 3.0 * 60.0):
		live.step(1.0 / 60.0)
		var dark := live.darkness() > 0.55
		if live.stats.holes_played != last:
			if dark:
				by_night += live.stats.holes_played - last
			else:
				by_day += live.stats.holes_played - last
			last = live.stats.holes_played
		if live.visitors._gid != last_gid:
			# a golfer who storms off gets a group of their own; only count
			# groups that have come to play
			var newest: Group = live.visitors.groups[-1]
			if newest.state != Group.S.LEAVING:
				arrivals += "%s%s " % [Defs.clock_text(live.clock).replace(" ", ""), "*" if dark else ""]
				if dark:
					came_by_night += 1
				else:
					came_by_day += 1
			last_gid = live.visitors._gid
	print("   three days with the clock running and no lights: %d groups arrived by day and %d after dark; %d holes played by day, %d finished after dark" % [came_by_day, came_by_night, by_day, by_night])
	print("   arrivals: " + arrivals)
	check(came_by_day > came_by_night * 2 and came_by_day > 6, "an unlit course does most of its business in daylight")
	check(by_night > 0, "and a round that runs into the night is played on, not abandoned")


## Play one hole of a career by hand: the strokes are described, not swung.
## Each entry is [lie hit from, metres to the pin, lie finished on, metres
## left, optional extras]. The last stroke holes out.
func _career_hole(sim: Sim, hole: Hole, strokes: Array) -> int:
	var car := sim.career
	car.begin_hole(hole)
	var b := Ball.new()
	for i in strokes.size():
		var st: Array = strokes[i]
		var extra: Dictionary = st[4] if st.size() > 4 else {}
		var from := hole.pin + Vector3(float(st[1]), 0.0, 0.0)
		b.place(from)
		b.hits = int(extra.get("hits", 0))
		car.shot_struck({"putt": int(st[0]) == Defs.T.GREEN, "lie": int(st[0]), "to_pin": float(st[1]), "from": from,
			"shape": str(extra.get("shape", "straight")), "stroke": i + 1})
		b.pos = hole.pin + Vector3(float(st[3]), 0.0, 0.0)
		var last := i == strokes.size() - 1
		car.shot_done(b, int(st[2]), float(st[3]), last)
	return car.hole_done(hole, strokes.size(), false)


func _test_career() -> void:
	print("-- your golfer: attributes, medals and challenges")
	var sim := _sim("three_holes", 41)
	var car := sim.career
	var T := Defs.T
	check(db.attributes.size() == 8 and db.challenges.size() >= 40, "there are eight attributes and %d challenges" % db.challenges.size())
	check(car.level("power") == 0 and sim.skills.bonus("power") == 0.0, "a new golfer starts with nothing")
	# attributes
	sim.skills.points.golfer = 3
	var reach := sim.gear.max_total(sim.player.golfer, T.TEE)
	check(car.cost("power") == 1 and car.raise("power") and car.raise("power") and car.raise("power"), "the first three levels of an attribute cost a point each")
	check(car.cost("power") == 2 and not car.raise("power"), "the fourth costs two, and you cannot buy what you cannot afford")
	check(sim.gear.max_total(sim.player.golfer, T.TEE) > reach * 1.05, "Power makes the ball go further (%d to %d yards off the tee)" % [Defs.yards(reach), Defs.yards(sim.gear.max_total(sim.player.golfer, T.TEE))])
	sim.skills.points.golfer = 200
	check(sim.skills.bonus("shape") == 0.0, "shot shaping starts locked")
	car.raise("spin")
	car.raise("spin")
	check(sim.skills.bonus("shape") > 0.0, "Spin level 2 unlocks the draw and the fade")
	var spread0 := sim.player.golfer.spread()
	for k in 10:
		car.raise("accuracy")
	check(car.level("accuracy") == 10 and not car.can_raise("accuracy"), "an attribute stops at level 10")
	check(sim.player.golfer.spread() < spread0 * 0.55 and sim.skills.bonus("wind_read") > 0.0, "Accuracy tightens your shots and teaches you to read the wind")
	for k in 8:
		car.raise("putting")
	check(sim.skills.bonus("read_greens") > 0.0 and sim.player.golfer.ball.m_cup > 1.2, "Putting shows the break and, at level 8, widens the hole")
	var total := 0
	for l in range(1, 11):
		total += Career.cost_of(l)
	check(total == 22, "an attribute costs 22 points to max (%d)" % total)
	# medals
	sim.skills.points.golfer = 0
	var hole := sim.course.holes[0]
	check(hole.par == 4 and hole.length >= Career.MEDAL_MIN_LENGTH, "the first hole is a par 4 long enough for medals")
	car.begin_round(false)
	var won := _career_hole(sim, hole, [[T.TEE, 311.0, T.FAIRWAY, 80.0], [T.FAIRWAY, 80.0, T.GREEN, 6.0], [T.GREEN, 6.0, T.GREEN, 0.5], [T.GREEN, 0.5, T.GREEN, 0.0]])
	print("   a par on hole 1 earned %d points; longest drive %d yards" % [won, int(car.value("longest_drive"))])
	check(car.medal(hole) == 1, "a par earns a bronze medal")
	check(car.done.has("drive1") and car.done.has("par"), "and meets the challenges it deserves (a 250-yard drive, a first par)")
	check(won >= 3, "medal and challenges pay skill points (%d)" % won)
	var again := _career_hole(sim, hole, [[T.TEE, 311.0, T.FAIRWAY, 80.0], [T.FAIRWAY, 80.0, T.GREEN, 6.0], [T.GREEN, 6.0, T.GREEN, 0.5], [T.GREEN, 0.5, T.GREEN, 0.0]])
	check(again == 0, "the same par again earns nothing new")
	var bird := _career_hole(sim, hole, [[T.TEE, 311.0, T.FAIRWAY, 110.0], [T.FAIRWAY, 110.0, T.GREEN, 1.2], [T.GREEN, 1.2, T.GREEN, 0.0]])
	check(car.medal(hole) == 2 and bird >= 2, "a birdie turns bronze to silver (%d points)" % bird)
	check(car.done.has("birdie") and car.done.has("stick2"), "a birdie from four feet after a 120-yard approach meets two more challenges")
	# a sand save, a chip-in and a ricochet
	_career_hole(sim, hole, [[T.TEE, 311.0, T.FAIRWAY, 90.0], [T.FAIRWAY, 90.0, T.BUNKER, 12.0], [T.BUNKER, 12.0, T.GREEN, 1.0], [T.GREEN, 1.0, T.GREEN, 0.0]])
	check(car.done.has("sandy"), "down in two from a bunker is a sandy")
	_career_hole(sim, hole, [[T.TEE, 311.0, T.ROUGH, 90.0, {"hits": 1}], [T.ROUGH, 90.0, T.ROUGH, 9.0], [T.ROUGH, 9.0, T.GREEN, 0.0]])
	check(car.done.has("chipin") and car.done.has("timber"), "a chip-in birdie after hitting a tree meets both of those")
	# rounds
	var pts0 := car.points()
	car.begin_round(true)
	var card: Array = []
	var pars: Array = []
	for hh in sim.course.holes:
		var plan: Array = [[T.TEE, hh.length, T.FAIRWAY, 60.0], [T.FAIRWAY, 60.0, T.GREEN, 3.0], [T.GREEN, 3.0, T.GREEN, 0.0]]
		if hh.par == 3:
			plan = [[T.TEE, hh.length, T.GREEN, 3.0], [T.GREEN, 3.0, T.GREEN, 0.0]]
		_career_hole(sim, hh, plan)
		card.append(plan.size())
		pars.append(hh.par)
	var round_pts := car.round_done(card, pars)
	print("   a three-hole round with birdies everywhere: %d points over the round, %d for finishing it" % [car.points() - pts0, round_pts])
	check(car.done.has("hattrick") and car.done.has("under3"), "three birdies in a round under par meets the round challenges")
	check(round_pts >= 1, "a full round at par or better is worth a point every time")
	check(int(car.value("round_birdies")) == 0, "the round counters start again afterwards")
	# off the course
	sim.stats.matches_won = 1
	car.check()
	check(car.done.has("match"), "winning a money match counts")
	car.note("tourney_top3")
	check(car.done.has("podium"), "and so does a podium in your own tournament")
	# a short hole pays no medals
	var stub := Hole.new()
	stub.tee = hole.tee
	stub.pin = hole.tee + Vector3(50.0, 0.0, 0.0)
	stub.par = 3
	stub.length = 50.0
	var m0 := car.medals.size()
	_career_hole(sim, stub, [[T.TEE, 50.0, T.GREEN, 0.0]])
	check(car.medals.size() == m0, "a 55-yard hole pays no medal, even for an ace")
	check(car.done.has("ace"), "though the ace itself still counts")
	# save and load
	var copy := Sim.from_dict(db, sim.to_dict(), gear)
	check(copy.career.level("accuracy") == 10 and copy.career.medal(copy.course.holes[0]) == 2 and copy.career.done.size() == car.done.size(),
		"a saved game keeps attributes, medals and challenges")
	check(copy.skills.bonus("wind_read") > 0.0 and is_equal_approx(copy.player.golfer.spread(), sim.player.golfer.spread()), "and the golfer plays the same after loading")
	print("   %d of %d challenges met in this test, %d points spent on attributes" % [car.done.size(), db.challenges.size(), car.spent()])


func _test_gamepad() -> void:
	print("-- a controller: sticks, menu steps and speed")
	check(Gamepad.shape(Vector2(0.15, 0.1)) == Vector2.ZERO, "a stick resting a little off centre does nothing")
	var light := Gamepad.shape(Vector2(0.4, 0.0))
	var full := Gamepad.shape(Vector2(1.0, 0.0))
	var corner := Gamepad.shape(Vector2(1.0, 1.0))
	check(light.x > 0.0 and light.x < 0.12 and is_equal_approx(light.y, 0.0), "a light push is slow, for exact pointing (%.3f of full speed)" % light.x)
	check(is_equal_approx(full.x, 1.0) and is_equal_approx(corner.length(), 1.0), "a full push is full speed, and a corner is no faster")
	check(Gamepad.shape(Vector2(0.0, -0.6)).y < 0.0 and is_zero_approx(Gamepad.shape(Vector2(0.0, -0.6)).x), "the push keeps its direction")
	# a menu: three buttons in a column, then a row of two below them
	var rects: Array[Rect2] = [Rect2(100, 100, 300, 40), Rect2(100, 150, 300, 40), Rect2(100, 200, 300, 40), Rect2(100, 250, 140, 40), Rect2(260, 250, 140, 40)]
	var down := Vector2(0, 1)
	check(Gamepad.pick_toward(Vector2(250, 120), down, rects) == 1, "d-pad down goes to the next button down, not past it")
	check(Gamepad.pick_toward(Vector2(250, 120), Vector2(0, -1), rects) == -1, "and nowhere from the top button going up")
	check(Gamepad.pick_toward(Vector2(350, 220), down, rects) == 4 and Gamepad.pick_toward(Vector2(150, 220), down, rects) == 3, "below a wide button it takes the one in line with the pointer")
	check(Gamepad.pick_toward(Vector2(170, 270), Vector2(1, 0), rects) == 4 and Gamepad.pick_toward(Vector2(330, 270), Vector2(-1, 0), rects) == 3, "left and right step along a row")
	check(Gamepad.pick_toward(Vector2(600, 20), down, rects) >= 0, "from open space it still finds a button that way")
	# game speed on the d-pad: paused, 1, 2, 4, 8
	check(Gamepad.speed_after(false, 1, 1) == 2 and Gamepad.SPEEDS[2] == 2, "d-pad right goes from normal speed to double")
	check(Gamepad.speed_after(false, 1, -1) == 0, "d-pad left from normal speed pauses")
	check(Gamepad.speed_after(true, 4, 1) == 1 and Gamepad.speed_after(false, 8, 1) == 4, "right from paused starts at normal speed, and the top speed is the limit")
	check(Gamepad.family("PS5 Controller") == "sony" and Gamepad.family("Nintendo Switch Pro Controller") == "nintendo" and Gamepad.family("Xbox Series X Controller") == "xbox",
		"button names follow the make of pad")


func _test_sounds() -> void:
	print("-- sound and music")
	var table: Dictionary = db.sounds.get("sounds", {})
	var missing := []
	for id: String in table:
		for f: String in table[id].files:
			if not FileAccess.file_exists("res://assets/sounds/%s.ogg" % f):
				missing.append(f)
	for bed: String in db.sounds.get("ambience", {}):
		if not FileAccess.file_exists("res://assets/sounds/%s.ogg" % str(db.sounds.ambience[bed].file)):
			missing.append(bed)
	check(table.size() >= 45 and missing.is_empty(), "all %d sound effects have their files %s" % [table.size(), str(missing)])
	# everything is Ogg Vorbis: no other kind of audio file is left in the game
	var strays := []
	for folder: String in ["res://assets/sounds", "res://assets/music"]:
		for f in DirAccess.get_files_at(folder):
			if not (f.ends_with(".ogg") or f.ends_with(".import")):
				strays.append(f)
	check(strays.is_empty(), "every audio file is Ogg Vorbis %s" % str(strays))
	for id: String in ["strike_sand", "strike_rough", "oob", "gust", "chat", "cheer", "groan", "boo", "ovation"]:
		check(table.has(id), "there is a sound for '%s'" % id)
	# what follows what must exist too
	var loose := []
	for id: String in table:
		var after: Dictionary = table[id].get("then", {})
		if not after.is_empty() and not table.has(str(after.get("id", ""))):
			loose.append(id)
	check(loose.is_empty(), "every sound that follows another exists %s" % str(loose))
	# the cast: several voices, each with lines to say, some high and some low
	var chatter: Dictionary = db.sounds.get("chatter", {})
	var cast: Dictionary = chatter.get("voices", {})
	var dumb := []
	for who: String in cast:
		if (cast[who] as Array).size() < 4:
			dumb.append(who)
		for f: String in cast[who]:
			if not FileAccess.file_exists("res://assets/sounds/%s.ogg" % f):
				dumb.append(f)
	for who: String in (chatter.get("high", []) as Array) + (chatter.get("low", []) as Array):
		if not cast.has(who):
			dumb.append(who)
	check(cast.size() >= 4 and dumb.is_empty() and not (chatter.get("high", []) as Array).is_empty() and not (chatter.get("low", []) as Array).is_empty(),
		"there are %d voices for the golfers' chatter, each with lines %s" % [cast.size(), str(dumb)])
	var tracks: Array = db.music.get("tracks", [])
	var lost := []
	for t: Dictionary in tracks:
		if not FileAccess.file_exists("res://assets/music/" + str(t.file)):
			lost.append(t.file)
	for list_name: String in ["day", "night"]:
		for id: String in db.music.get(list_name, []):
			if DataDB.find(tracks, id).is_empty():
				lost.append(id)
	check(tracks.size() >= 6 and lost.is_empty(), "all %d music tracks are present and listed %s" % [tracks.size(), str(lost)])
	check((db.music.get("day", []) as Array).size() >= 3 and (db.music.get("night", []) as Array).size() >= 2, "there is music for the day and for the night")
	# the game announces what happens; every announcement must be a sound that exists
	var sim := _sim("three_holes", 51)
	var heard := {}
	var unknown := {}
	sim.sound.connect(func(id: String, _pos: Vector3, power: float) -> void:
		heard[id] = int(heard.get(id, 0)) + 1
		if not table.has(id) or power <= 0.0 or power > 1.0:
			unknown[id] = true)
	_run(sim, 600.0)
	var strikes := int(heard.get("drive", 0)) + int(heard.get("iron", 0)) + int(heard.get("chip", 0)) + int(heard.get("putt", 0))
	var landings := int(heard.get("land_soft", 0)) + int(heard.get("land_sand", 0)) + int(heard.get("land_hard", 0))
	print("   in ten minutes of play: %d club strikes (%d putts), %d landings, %d balls in the cup, %d fees paid, %d kinds of sound in all" % [
		strikes, int(heard.get("putt", 0)), landings, int(heard.get("cup", 0)), int(heard.get("coin", 0)), heard.size()])
	check(unknown.is_empty(), "every sound the game announces exists %s" % str(unknown.keys()))
	check(strikes > 40 and int(heard.get("putt", 0)) > 10 and int(heard.get("drive", 0)) > 5, "every shot is heard, with the right club")
	check(landings > 20 and int(heard.get("cup", 0)) > 10, "balls are heard landing and dropping in the cup")
	check(int(heard.get("coin", 0)) > 10, "and green fees chink as they are paid")
	print("   reactions: %d cheers, %d groans, %d rounds of applause" % [int(heard.get("cheer", 0)), int(heard.get("groan", 0)), int(heard.get("clap", 0))])
	check(int(heard.get("groan", 0)) > 0, "golfers groan at a missed short putt or a ruined hole")
	# a chip-in is cheered, a tap-in is not
	var lucky := sim.visitors.golfers[0] if not sim.visitors.golfers.is_empty() else sim.visitors.make_golfer("public", 0.5)
	var before := int(heard.get("cheer", 0))
	lucky.strokes = 3
	lucky.plan = {"putt": true, "dist": 1.0}
	sim.visitors.on_holed(lucky, sim.course.holes[0], 0)
	var tap_in := int(heard.get("cheer", 0)) - before
	lucky.plan = {"putt": false, "dist": 22.0}
	sim.visitors.on_holed(lucky, sim.course.holes[0], 0)
	check(tap_in == 0 and int(heard.get("cheer", 0)) - before == 1, "a chip-in is cheered and a tap-in is not")
	# in the volcanic biome a ball in the lava sizzles, it does not splash
	var hot := Sim.new(db, DataDB.find(db.scenarios, "three_holes"), 7, gear, "volcanic")
	var said := {}
	hot.sound.connect(func(id: String, _pos: Vector3, _power: float) -> void: said[id] = int(said.get(id, 0)) + 1)
	var pool := -1
	for i in hot.course.terrain.size():
		if hot.course.terrain[i] == Defs.T.WATER and not hot.course.locked[i]:
			pool = i
			break
	if pool < 0:
		pool = hot.course.index_at(hot.course.holes[0].tee.x + 20.0, hot.course.holes[0].tee.z)
		hot.course.terrain[pool] = Defs.T.WATER
	var centre := hot.course.tile_center(pool % hot.course.w, pool / hot.course.w)
	var drop := Ball.new()
	drop.pos = Vector3(centre.x - 0.6, hot.course.height_at(centre.x, centre.z) + 14.0, centre.z)
	drop.launch(2.0, 0.0, deg_to_rad(50.0), 0.0, 0.0, 0.0)
	hot.visitors.track_ball(drop, hot.course.holes[0])
	for i in 900:
		hot.visitors._step_balls(1.0 / 60.0)
	check(hot.is_lava() and int(said.get("sizzle", 0)) >= 1 and int(said.get("splash", 0)) == 0,
		"a ball in the lava sizzles (%d sizzles, %d splashes, ball finished %s)" % [int(said.get("sizzle", 0)), int(said.get("splash", 0)), str(drop.pos)])
	# materials: every one a ball can hit has a sound of its own
	var mats := []
	for m: String in Solids.data().materials:
		if Solids.data().materials[m].has("bounce") and not table.has("hit_" + m):
			mats.append(m)
	check(mats.is_empty(), "every solid material has a ricochet sound %s" % str(mats))


func _test_fees() -> void:
	print("-- green fees by enjoyment")
	var sim := _sim("three_holes", 3)
	sim.events.timer = 99999.0      # no prepaid corporate outings in this test
	var hole := sim.course.holes[0]
	# one golfer, one hole, four different experiences of it
	var g := sim.visitors.make_golfer("public", 0.5)
	g.set_persona(DataDB.find(db.personalities, "easygoing"))
	g.wealth = 0.5
	var paid := {}
	for mood: Array in [["loved", 9.0], ["liked", 3.0], ["poor", -5.0], ["hated", -16.0]]:
		g.sat_at_tee = 60.0
		g.satisfaction = 60.0 + float(mood[1])
		paid[mood[0]] = sim.visitors.collect_fee(g, hole, 0)
	print("   one golfer pays: loved it %s, liked it %s, poor %s, hated it %s (a hole they like is worth %s to them)" % [
		Defs.money(float(paid.loved)), Defs.money(float(paid.liked)), Defs.money(float(paid.poor)), Defs.money(float(paid.hated)), Defs.money(sim.visitors.worth(g, hole))])
	check(float(paid.loved) > float(paid.liked) and float(paid.liked) > float(paid.poor), "the more a golfer enjoyed a hole, the more they pay")
	check(float(paid.hated) == 0.0, "a golfer who hated a hole pays nothing")
	check(float(paid.loved) > sim.visitors.worth(g, hole), "a hole they loved earns a tip on top")
	check(hole.payers == 4 and is_equal_approx(hole.earned, float(paid.loved) + float(paid.liked) + float(paid.poor)), "each hole keeps a tally of what it earns")
	check(sim.stats.refusals == 1, "and unpaid holes are counted")
	# a stretch of ordinary play: money comes in after holes, never on the tee
	var live := _sim("three_holes", 3)
	live.events.timer = 99999.0
	var early := false
	for i in int(500.0 * 60.0):
		live.step(1.0 / 60.0)
		if i % 120 == 0:
			for v in live.visitors.golfers:
				if v.holes_played == 0 and v.paid > 0.0:
					early = true
	var earned := 0.0
	var tally_ok := true
	for h in live.course.holes:
		earned += h.earned
		if h.payers != h.plays:
			tally_ok = false
	print("   500 s of play: %s in green fees from %d holes played, about %s a hole" % [Defs.money(earned), live.stats.holes_played, Defs.money(earned / maxf(live.stats.holes_played, 1.0))])
	check(earned > 0.0, "golfers pay green fees with nobody setting a price")
	check(not early, "nobody pays before they have played a hole")
	check(tally_ok, "every golfer who finishes a hole is asked to pay for it")
	var avg := earned / maxf(live.stats.holes_played, 1.0)
	check(avg > 6.0 and avg < 40.0, "a hole on the starter course earns a sensible amount (%s)" % Defs.money(avg))


func _test_difficulty() -> void:
	print("-- the difficulty slider")
	var sim := _sim("first_tee", 5)
	var hole := sim.course.holes[0]
	check(sim.difficulty == 2 and sim.difficulty_name() == "Normal", "a game starts on Normal")
	var g := sim.visitors.add_group("public", 1, 0.5, 0.0).members[0]     # on the course, so the slider reaches them
	g.persona = {}
	g.wealth = 0.5
	g.satisfaction = 62.0
	g.begin_hole()
	var fees := {}
	for level in [2, 4, 0]:
		sim.set_difficulty(level)
		var before := sim.economy.money
		sim.visitors.collect_fee(g, hole, 0)
		fees[level] = sim.economy.money - before
	print("   the same golfer pays %s on Normal, %s on Brutal, %s on Relaxed" % [Defs.money(float(fees[2])), Defs.money(float(fees[4])), Defs.money(float(fees[0]))])
	check(float(fees[4]) < float(fees[2]) * 0.85 and float(fees[0]) > float(fees[2]) * 1.15, "on Brutal golfers pay less, on Relaxed more")
	check(is_equal_approx(hole.average_paid() * hole.payers, float(fees[2]) + float(fees[4]) + float(fees[0])), "what the hole is said to earn is what was really paid")
	# the same bad moment hits harder, and a good one lifts less
	sim.set_difficulty(2)
	g.satisfaction = 60.0
	g.feel(-6.0, "", "test")
	var normal_drop := 60.0 - g.satisfaction
	g.satisfaction = 60.0
	g.feel(4.0, "", "test")
	var normal_lift := g.satisfaction - 60.0
	sim.set_difficulty(4)
	check(is_equal_approx(g.mood_bad, 1.45) and is_equal_approx(g.mood_good, 0.85), "moving the slider changes the temper of golfers already on the course")
	g.satisfaction = 60.0
	g.feel(-6.0, "", "test")
	var brutal_drop := 60.0 - g.satisfaction
	g.satisfaction = 60.0
	g.feel(4.0, "", "test")
	var brutal_lift := g.satisfaction - 60.0
	print("   a bad moment costs %.1f on Normal and %.1f on Brutal; a good one gives %.1f and %.1f" % [normal_drop, brutal_drop, normal_lift, brutal_lift])
	check(brutal_drop > normal_drop * 1.3 and brutal_lift < normal_lift * 0.9, "on Brutal golfers sour sooner and cheer up less")
	var newcomer := sim.visitors.make_golfer("public", 0.5)
	check(is_equal_approx(newcomer.mood_bad, 1.45), "and new arrivals share it")
	var lab := sim.lab._test_golfer(HoleLab.CLASSES[0])
	check(lab.mood_bad == 1.0 and lab.mood_good == 1.0, "a golfer made for rating holes is not touched")
	# wages
	sim.set_difficulty(2)
	sim.hire("greenkeeper")
	var wage_n := sim.crew.monthly_wages()
	sim.set_difficulty(4)
	var wage_b := sim.crew.monthly_wages()
	sim.set_difficulty(0)
	var wage_r := sim.crew.monthly_wages()
	print("   a greenkeeper costs %s a month on Normal, %s on Brutal, %s on Relaxed" % [Defs.money(wage_n), Defs.money(wage_b), Defs.money(wage_r)])
	check(wage_b > wage_n * 1.2 and wage_r < wage_n * 0.9, "staff cost more on Brutal and less on Relaxed")
	check(sim.diff("weeds") < 1.0 and sim.diff("pests") < 1.0 and sim.diff("wear") < 1.0, "weeds, pests and wear ease off on Relaxed")
	sim.set_difficulty(4)
	check(sim.diff("weeds") > 1.5 and sim.difficulty_blurb().contains("weeds"), "and run riot on Brutal, which the slider says in words")
	# the level survives a save
	var back := Sim.from_dict(db, JSON.parse_string(JSON.stringify(sim.to_dict())), gear)
	check(back.difficulty == 4 and back.difficulty_name() == "Brutal", "the difficulty survives a save")
	sim.set_difficulty(9)
	check(sim.difficulty == 4, "the slider stops at the ends")



func _test_hit() -> void:
	print("-- getting hit by a ball")
	var sim := _sim("three_holes", 4)
	var gr := sim.visitors.add_group("public", 2, 0.5)
	var hitter := gr.members[0]
	var victim := gr.members[1]
	var hole := sim.course.holes[0]
	hitter.pos = hole.tee
	hitter.ball.place(hole.tee)
	var dir := (hole.pin - hole.tee).normalized()
	victim.pos = sim.course.on_ground(hole.tee.x + dir.x * 30.0, hole.tee.z + dir.z * 30.0)
	victim.persona = {}      # a plain golfer: some personalities enjoy this
	var mood := victim.satisfaction
	hitter.ball.launch(50.0, atan2(dir.z, dir.x), deg_to_rad(1.5), 0.0, 0.0, 0.0)
	sim.visitors.track_ball(hitter.ball, hole)
	for i in 120:
		sim.visitors._step_balls(1.0 / 60.0)
	check(sim.stats.hits == 1, "the ball hits the golfer standing in the way")
	check(victim.hit_t > 0.0, "the victim goes down")
	check(victim.satisfaction < mood - 20.0, "and is very unhappy about it")
	check(sim.feed.posts.size() > 0 and sim.feed.posts[-1].kind in ["hit_victim", "hit_hitter"], "and it makes the feed")


func _test_turf() -> void:
	print("-- weeds, pests and staff")
	var wild := _sim("weed_patch", 6)
	wild.open = false
	_run(wild, 30.0)
	var c0 := wild.grounds.condition
	var staffed := _sim("weed_patch", 6)
	staffed.open = false
	for i in 4:
		staffed.hire("greenkeeper")
	staffed.hire("exterminator")
	_run(wild, 600.0)
	_run(staffed, 630.0)
	print("   neglected course: condition %.0f%% then %.0f%% unstaffed, %.0f%% with five staff" % [c0 * 100.0, wild.grounds.condition * 100.0, staffed.grounds.condition * 100.0])
	print("   weeds %.0f%% vs %.0f%%, pests %.1f%% vs %.1f%%" % [wild.grounds.weed_cover * 100.0, staffed.grounds.weed_cover * 100.0, wild.grounds.pest_cover * 100.0, staffed.grounds.pest_cover * 100.0])
	check(staffed.grounds.condition > wild.grounds.condition + 0.15, "staff restore a neglected course")
	check(staffed.grounds.weed_cover < wild.grounds.weed_cover * 0.5, "greenkeepers clear the weeds")
	check(staffed.grounds.pest_cover <= wild.grounds.pest_cover, "exterminators clear the pests")
	check(staffed.crew.monthly_wages() > 0.0 and staffed.economy.history.size() == 1, "and they get paid at month end")
	# rain makes the course wet, sun dries it
	var sim := _sim("three_holes", 8)
	sim.open = false
	sim.weather.kind = Weather.K.RAIN
	sim.weather._next_change = 9999.0
	_run(sim, 90.0)
	var soaked := sim.grounds.avg_wet
	sim.weather.kind = Weather.K.CLEAR
	_run(sim, 400.0)
	print("   wetness after rain %.2f, after a dry spell %.2f" % [soaked, sim.grounds.avg_wet])
	check(soaked > 0.5, "rain soaks the course")
	check(sim.grounds.avg_wet < soaked * 0.5, "it dries out afterwards")
	# unhappy golfers let the weeds in; the difficulty slider turns it up
	var cross := _sim("three_holes", 6)
	var glad := _sim("three_holes", 6)
	for s: Sim in [cross, glad]:
		s.open = false
		s.weather.kind = Weather.K.CLEAR
		s.weather._next_change = 1e9
		s.visitors.recent.clear()
		for i in 12:
			s.visitors.recent.append(35.0 if s == cross else 85.0)
	check(cross.grounds.weed_mood() > 2.5 and glad.grounds.weed_mood() < 0.8, "weeds follow the mood of the course (%.1f when golfers are miserable, %.1f when they are happy)" % [cross.grounds.weed_mood(), glad.grounds.weed_mood()])
	_run(cross, 600.0)
	_run(glad, 600.0)
	print("   weed cover after 600 s: %.1f%% with miserable golfers, %.1f%% with happy ones" % [cross.grounds.weed_cover * 100.0, glad.grounds.weed_cover * 100.0])
	check(cross.grounds.weed_cover > glad.grounds.weed_cover * 1.5 + 0.002, "unhappy golfers let the weeds in")
	check(cross.feed.posts.any(func(p: Dictionary) -> bool: return p.kind == "weeds_unrest"), "and the owner hears about it")
	var brutal := _sim("three_holes", 6)
	brutal.set_difficulty(4)
	check(brutal.difficulty_name() == "Brutal" and brutal.diff("weeds") > 2.0 and brutal.diff("fee") < 0.8 and brutal.diff("mood_bad") > 1.3, "the hardest setting means more weeds, less money and shorter tempers")
	brutal.set_difficulty(0)
	check(brutal.diff("weeds") < 0.6 and brutal.diff("fee") > 1.2, "the easiest means the opposite")
	brutal.set_difficulty(2)
	check(brutal.diff("weeds") == 1.0 and brutal.diff("fee") == 1.0 and brutal.diff("wages") == 1.0, "and normal changes nothing")


func _test_skills_and_goals() -> void:
	print("-- skills and scenario goals")
	var sim := _sim("first_tee", 9)
	sim.hire("greenkeeper")
	var wage := sim.crew.monthly_wages()
	check(sim.skills.unlock("frugal"), "can spend the starting point")
	check(sim.crew.monthly_wages() < wage, "Sharp Pencil lowers wages")
	check(not sim.skills.unlock("crew_chief"), "cannot unlock without points")
	sim.skills.add_xp("manager", 200)
	check(int(sim.skills.level.manager) > 1 and int(sim.skills.points.manager) > 0, "experience brings levels and points")
	check(sim.skills.unlock("crew_chief"), "prerequisites open up the next skill")
	sim.skills.add_xp("golfer", 100)
	var reach := sim.gear.max_total(sim.player.golfer, Defs.T.TEE)
	sim.career.raise("power")
	check(sim.gear.max_total(sim.player.golfer, Defs.T.TEE) > reach, "your golfer's attributes change your shots")
	var prog := sim.scenario.progress(sim)
	check(prog.size() == 2 and not prog[0].done, "the scenario lists unmet goals")
	var ended := [0]
	sim.scenario_ended.connect(func(won: bool) -> void: ended[0] = 1 if won else -1)
	sim.time = float(sim.scenario.deadline_day() + 1) * Defs.DAY_SECONDS
	sim.step(1.0 / 60.0)
	check(ended[0] == -1 and sim.scenario.status == "lost", "missing the deadline loses the scenario")
	var free := _sim("three_holes", 9)
	check(free.scenario.status == "free", "free play has no deadline")


func _test_events() -> void:
	print("-- random events")
	var sim := _sim("three_holes", 10)
	_run(sim, 5.0)
	for id: String in Events.GAP.keys():
		if id != "sponsor" and id != "match" and id != "eruption":
			sim.events.trigger(id)
	check(sim.events.celebrity != null and sim.events.celebrity.kind == "celebrity", "a celebrity turns up")
	sim.events.trigger("sponsor")
	check(sim.events.pending.get("id", "") == "sponsor", "a sponsor makes an offer")
	var money := sim.economy.money
	sim.events.choose("accept")
	check(sim.economy.money > money, "taking the sponsorship pays")
	check(sim.weather.heat_until > sim.time, "a heat wave starts")
	_run(sim, 400.0)
	check(sim.stats.rounds > 0, "play carries on through all of it")
	var kinds := {}
	var year := _sim("monsoon", 11)
	year.open = false
	for i in int(224.0 * Defs.DAY_SECONDS / 0.25):
		year.time += 0.25
		year.weather.step(0.25, year)
		kinds[year.weather.kind] = true
	check(kinds.size() == 5, "a year sees every kind of weather")


func _test_season() -> void:
	print("-- a four month season of free play")
	var sim := _sim("three_holes", 12345)
	check(sim.course.holes.size() == 3, "the starter course has three holes")
	sim.hire("greenkeeper")
	sim.hire("marshal")
	var start_money := sim.economy.money
	var t0 := Time.get_ticks_msec()
	var steps := int(4.0 * 28.0 * Defs.DAY_SECONDS * 60.0) + 120
	var on_course := 0.0
	for i in steps:
		sim.step(1.0 / 60.0)
		on_course += sim.visitors.golfers.size()
	var ms := Time.get_ticks_msec() - t0
	print("   simulated at %.0fx real time, %.1f golfers on course on average" % [steps / 60.0 / (ms / 1000.0), on_course / steps])
	print("   %s: money %s (started %s)" % [sim.date_text(), Defs.money(sim.economy.money), Defs.money(start_money)])
	print("   rounds %d, holes played %d, hit by balls %d, aces %d, unpaid holes %d" % [sim.stats.rounds, sim.stats.holes_played, sim.stats.hits, sim.stats.aces, sim.stats.refusals])
	print("   rating %.0f, satisfaction %.0f, condition %.0f%%, weeds %.1f%%" % [sim.rating, sim.visitors.average_satisfaction(), sim.grounds.condition * 100.0, sim.grounds.weed_cover * 100.0])
	for i in sim.course.holes.size():
		var hole := sim.course.holes[i]
		print("   hole %d: par %d, %d plays, average %.2f, best %d" % [i + 1, hole.par, hole.plays, hole.average_score(), hole.best])
		check(hole.plays > 10, "hole %d is played" % (i + 1))
		check(hole.average_score() > hole.par - 0.5 and hole.average_score() < hole.par + 3.0, "hole %d scoring is sane" % (i + 1))
	for row in sim.economy.history:
		print("   %s: net %s" % [row.label, Defs.money(float(row.net))])
	for p in sim.feed.posts.slice(-4):
		print("     @%s: %s" % [p.handle, p.text])
	check(sim.stats.rounds > 20, "golfers complete rounds")
	check(sim.economy.history.size() == 4, "four months of books closed")
	check(sim.feed.posts.size() > 5, "the feed fills up")
	check(sim.grounds.condition > 0.5, "one greenkeeper keeps three holes in shape")
	check(sim.visitors.average_satisfaction() > 40.0, "golfers are not miserable")

	print("-- hosting a tournament")
	sim.economy.money = 50000.0
	sim.rating = 60.0
	var def := DataDB.find(db.tournaments, "club")
	check(sim.tourney.can_host(def) == "", "the Club Championship can be booked")
	check(sim.tourney.schedule("club"), "it schedules")
	check(sim.tourney.can_host(DataDB.find(db.tournaments, "major")) != "", "the major is out of reach")
	var guard := 0
	var closed := false
	while sim.tourney.last_result.is_empty() and guard < 60 * 60 * 30:
		sim.step(1.0 / 60.0)
		guard += 1
		if not sim.tourney.active.is_empty() and not sim.open:
			closed = true
	check(not sim.tourney.last_result.is_empty(), "the tournament finishes")
	check(closed, "the course closes to the public during play")
	check(sim.open, "and reopens afterwards")
	check(int(sim.tourney.hosted.get("club", 0)) == 1, "it is recorded as hosted")
	check(sim.tourney.can_host(def) != "", "the same event cannot be held twice in a year")
	print("   %s won at %s, net %s" % [sim.tourney.last_result.winner, sim.tourney.last_result.score, Defs.money(float(sim.tourney.last_result.net))])


func _test_save() -> void:
	print("-- save and load")
	var sim := _sim("first_tee", 99)
	sim.hire("greenkeeper")
	sim.skills.unlock("frugal")
	sim.player.buy("irons", "bogey")
	_run(sim, 10.0)
	var text := JSON.stringify(sim.to_dict())
	var back := Sim.from_dict(db, JSON.parse_string(text), gear)
	check(str(back.rng.seed) == str(sim.rng.seed) and str(back.rng.state) == str(sim.rng.state), "a loaded game carries on from the same dice, not the clock")
	check(back.course.holes.size() == sim.course.holes.size(), "holes survive a save")
	check(is_equal_approx(back.economy.money, sim.economy.money), "money survives a save")
	check(back.crew.members.size() == 1, "staff survive a save")
	check(back.skills.has("frugal"), "skills survive a save")
	check(back.course.terrain == sim.course.terrain, "terrain survives a save")
	check(back.player.equipped.irons == "bogey", "your clubs survive a save")
	check(back.scenario.def.id == "first_tee" and back.day() == sim.day(), "the scenario and date survive a save")
	_run(back, 60.0)
	check(back.visitors.golfers.size() > 0, "a loaded game carries on")
	print("   save file is %d KB" % (text.length() / 1024))


func _count(course: Course, t: int) -> int:
	var n := 0
	for v in course.terrain:
		if v == t:
			n += 1
	return n


func _test_biomes() -> void:
	print("-- biomes")
	var relief := {}
	var water := {}
	for b: Dictionary in db.biomes:
		var id := str(b.id)
		var sim := Sim.new(db, DataDB.find(db.scenarios, "three_holes"), 31, gear, id)
		var c := sim.course
		check(sim.biome.id == id and c.biome_id == id, "%s: the course knows its biome" % id)
		var lo := INF
		var hi := -INF
		for i in c.heights.size():
			if c.hot[mini(i, c.hot.size() - 1)] == 0:
				lo = minf(lo, c.heights[i])
				hi = maxf(hi, c.heights[i])
		relief[id] = hi - lo
		water[id] = _count(c, Defs.T.WATER)
		var ok := true
		for hole in c.holes:
			if c.terrain_at(hole.pin.x, hole.pin.z) != Defs.T.GREEN or c.is_out(hole.pin.x, hole.pin.z) or c.is_out(hole.tee.x, hole.tee.z):
				ok = false
		check(ok and c.holes.size() == 3, "%s: three playable holes on land you own" % id)
		check(c.locked.has(1) and c.locked.has(0), "%s: some land is yours and some is for sale" % id)
		_run(sim, 300.0)
		check(sim.stats.holes_played > 3, "%s: golfers play it (%d holes)" % [id, sim.stats.holes_played])
		print("   %-10s relief %4.1f m, hazard tiles %3d, %s, holes played %d, wind %d mph, %d F" % [
			id, relief[id], water[id], sim.terrain_name(Defs.T.WATER), sim.stats.holes_played, sim.weather.wind_mph(), sim.weather.temp_f()])
	check(relief.highlands > relief.lush * 1.4, "the highlands are much hillier than parkland")
	var desert := Sim.new(db, DataDB.find(db.scenarios, "three_holes"), 31, gear, "desert")
	var lush := Sim.new(db, DataDB.find(db.scenarios, "three_holes"), 31, gear, "lush")
	check(desert.weather.rain_mult < lush.weather.rain_mult * 0.3, "the desert is far drier")
	check(desert.thirst_rate() >= lush.thirst_rate(), "and at least as thirsty")
	check(desert.object_name(Defs.O.PINE) != lush.object_name(Defs.O.PINE), "trees are named for their biome")
	var vol := Sim.new(db, DataDB.find(db.scenarios, "mount_bogey"), 5, gear)
	check(vol.is_lava() and vol.terrain_name(Defs.T.WATER) == "Lava", "on the volcano the hazard is lava")
	check(vol.course.volcanoes.size() == 1 and vol.course.hot.has(1), "there is a volcano, and its slopes are off limits")
	var v: Dictionary = vol.course.volcanoes[0]
	check(float(v.rim) > vol.course.height_at(float(v.x) + float(v.radius) + 20.0, float(v.z)) + 25.0, "the volcano towers over the course")
	check(vol.course.terrain_at(float(v.x), float(v.z)) == Defs.T.WATER, "with a lake of lava in the crater")
	check(vol.paint(int(float(v.x) / Defs.TILE) + 4, int(float(v.z) / Defs.TILE), 1, Defs.T.FAIRWAY) <= 0, "nothing can be built on the volcano")
	# lava swallows a ball that would skip across water
	var lane := _lane()
	for tx in range(8, 12):
		for ty in 24:
			lane.terrain[ty * 160 + tx] = Defs.T.WATER
	var skip := Ball.new()
	skip.set_def(db.ball("skipper"))
	skip.lava = true
	skip.place(Vector3(10.0, 0.0, 60.0))
	skip.launch(40.0, 0.0, deg_to_rad(6.0), 0.02, 0.0, 0.2)
	var n := 0
	while skip.moving() and n < 4000:
		skip.step(1.0 / 60.0, lane, Vector3.ZERO, Vector3.ZERO, false)
		n += 1
	check(skip.state == Ball.S.WATER, "nothing skips across lava")


func _test_land() -> void:
	print("-- buying land")
	var sim := _sim("three_holes", 14)
	var c := sim.course
	var locked := Vector2i(-1, -1)
	for py in range(0, c.h, Course.PARCEL):
		for px in range(0, c.w, Course.PARCEL):
			if c.locked[py * c.w + px] != 0 and locked.x < 0:
				locked = Vector2i(px, py)
	check(locked.x >= 0, "there is land to buy")
	var owned := c.owned_parcels()
	check(sim.paint(locked.x + 3, locked.y + 3, 1, Defs.T.FAIRWAY) == 0, "cannot build on land that is not yours")
	check(sim.place_object(locked.x + 3, locked.y + 3, Defs.O.OAK) == 0, "cannot plant there either")
	var p := c.tile_center(locked.x + 3, locked.y + 3)
	check(c.is_out(p.x, p.z), "a ball there is out of bounds")
	var b := Ball.new()
	b.place(Vector3(p.x, p.y + 20.0, p.z))
	b.state = Ball.S.FLIGHT
	b.vel = Vector3(0.0, -5.0, 0.0)
	var n := 0
	while b.moving() and n < 2000:
		b.step(1.0 / 60.0, c, Vector3.ZERO, Vector3.ZERO, false)
		n += 1
	check(b.state == Ball.S.OOB, "a ball landing on land you do not own is out of bounds")
	var price := sim.land_price()
	var money := sim.economy.money
	check(sim.buy_land(locked.x + 3, locked.y + 3) == 1, "the parcel can be bought")
	check(is_equal_approx(sim.economy.money, money - price), "at the quoted price")
	check(c.owned_parcels() == owned + 1 and sim.land_price() > price, "and the next one costs more")
	check(sim.paint(locked.x + 3, locked.y + 3, 1, Defs.T.FAIRWAY) > 0, "now it can be built on")
	check(sim.buy_land(locked.x + 3, locked.y + 3) == 0, "land you own is not for sale")
	sim.land_credits = 1
	money = sim.economy.money
	var again := Vector2i(-1, -1)
	for py in range(0, c.h, Course.PARCEL):
		for px in range(0, c.w, Course.PARCEL):
			if c.locked[py * c.w + px] != 0 and again.x < 0:
				again = Vector2i(px, py)
	check(sim.buy_land(again.x, again.y) == 1 and is_equal_approx(sim.economy.money, money), "a land grant from the county is free")


func _test_eruption() -> void:
	print("-- the volcano erupts")
	var sim := _sim("mount_bogey", 21)
	var c := sim.course
	sim.open = false
	check(not sim.eruption.active(), "the volcano starts quiet")
	var ash0 := _count(c, Defs.T.ASH)
	var lava0 := _count(c, Defs.T.WATER)
	var rock0 := _count(c, Defs.T.ROCK)
	var before := c.heights.duplicate()
	var objects0 := 0
	for o in c.objects:
		if o != 0:
			objects0 += 1
	var events := [0, 0]
	sim.eruption.started.connect(func() -> void: events[0] += 1)
	sim.eruption.ended.connect(func(_s: Dictionary) -> void: events[1] += 1)
	check(sim.eruption.start(2.0), "an eruption can be triggered")
	_run(sim, 3.0)
	check(sim.eruption.state == Eruption.S.ERUPTING and sim.weather.ash > 0.5, "it erupts and ash fills the sky")
	_run(sim, 40.0)
	var sm := sim.eruption.summary
	var moved := 0
	for i in before.size():
		if absf(before[i] - c.heights[i]) > 0.05:
			moved += 1
	var objects1 := 0
	for o in c.objects:
		if o != 0:
			objects1 += 1
	print("   %d bombs, %d craters, %d tiles of new lava, %d trees burned; %d height points moved; ash tiles %d -> %d" % [
		int(sm.bombs), int(sm.craters), int(sm.lava), int(sm.trees), moved, ash0, _count(c, Defs.T.ASH)])
	check(events[0] == 1 and events[1] == 1 and sim.stats.eruptions == 1, "it starts and ends once")
	check(int(sm.bombs) > 20, "lava bombs rain down")
	check(moved > 20, "bombs leave craters in the ground")
	check(_count(c, Defs.T.ASH) > ash0 + 10, "and scorch the land")
	check(_count(c, Defs.T.WATER) > lava0 + 20, "rivers of lava spread across the map")
	check(objects1 < objects0, "trees and scenery burn")
	var ok := true
	for hole in c.holes:
		if c.terrain_at(hole.pin.x, hole.pin.z) != Defs.T.GREEN:
			ok = false
	check(ok, "every pin survives on its green")
	_run(sim, 320.0)
	check(_count(c, Defs.T.ROCK) > rock0 + 15, "the lava cools into rock: the map is changed for good")
	check(sim.eruption.state == Eruption.S.QUIET, "and the volcano goes quiet again")
	var cost := sim.economy.money
	var rock_tile := -1
	for i in c.terrain.size():
		if c.terrain[i] == Defs.T.ROCK and c.hot[i] == 0 and c.locked[i] == 0:
			rock_tile = i
			break
	if rock_tile >= 0:
		sim.paint(rock_tile % c.w, rock_tile / c.w, 0, Defs.T.FAIRWAY)
		check(cost - sim.economy.money > Defs.T_COST[Defs.T.FAIRWAY], "clearing rock to rebuild costs extra")
	# people caught in it
	var open := _sim("mount_bogey", 22)
	_run(open, 240.0)
	var scared := 0
	open.eruption.start(0.5)
	_run(open, 35.0)
	for g in open.visitors.golfers:
		if int(g.rd.scare) > 0:
			scared += 1
	print("   with golfers out: %d on course, %d scared, %d caught by bombs" % [open.visitors.golfers.size(), scared, int(open.eruption.summary.hit)])
	check(open.arrival_rate() < 0.01 or not open.eruption.active(), "nobody new turns up mid-eruption")


func _test_paths() -> void:
	print("-- paths, bridges and carts")
	var sim := _sim("sandbox", 3)
	var c := sim.course
	var a := c.tile_center(40, 40)
	var b := c.tile_center(60, 40)
	for ty in range(20, 61):
		for tx in range(49, 52):
			c.terrain[ty * c.w + tx] = Defs.T.WATER
			c.objects[ty * c.w + tx] = 0
	for ty in range(36, 45):
		for tx in range(38, 63):
			if c.terrain[ty * c.w + tx] != Defs.T.WATER:
				c.terrain[ty * c.w + tx] = Defs.T.ROUGH
			c.objects[ty * c.w + tx] = 0
	c.revision += 1
	check(not sim.nav.clear_line(a, b), "a pond blocks the straight walk")
	var round_trip := _path_len(a, sim.nav.path(a, b))
	check(round_trip > a.distance_to(b) * 1.5, "so golfers walk round it (%.0f m against %.0f m straight)" % [round_trip, a.distance_to(b)])
	var crosses := false
	for wp in sim.nav.path(a, b):
		if c.terrain_at(wp.x, wp.y) == Defs.T.WATER:
			crosses = true
	check(not crosses, "and never through it")
	for tx in range(49, 52):
		check(sim.place_object(tx, 40, Defs.O.BRIDGE) == 1, "a bridge can be built on the water")
	check(sim.place_object(45, 40, Defs.O.BRIDGE) == 0, "but not on dry land")
	var bridged := _path_len(a, sim.nav.path(a, b))
	check(bridged < round_trip * 0.6, "with a bridge they walk straight across (%.0f m)" % bridged)
	# cart paths are quicker, and golfers go out of their way to use them
	check(sim.nav.speed_at(a.x, a.z, false) == 1.0, "normal walking pace on grass")
	sim.paint(40, 40, 0, Defs.T.PATH)
	check(sim.nav.speed_at(a.x, a.z, false) > 1.2, "faster on a path")
	check(sim.nav.speed_at(a.x, a.z, true) > sim.nav.speed_at(a.x, a.z, false) * 1.5, "much faster in a cart")
	var g := Golfer.new()
	g.pos = a
	var steps := 0
	while not g.travel(b, 1.0 / 60.0, sim, 6.0) and steps < 6000:
		steps += 1
	check(g.pos.distance_to(b) < 1.0, "a golfer follows the route and arrives")


func _path_len(from: Vector3, route: PackedVector2Array) -> float:
	var total := 0.0
	var last := Vector2(from.x, from.z)
	for wp in route:
		total += last.distance_to(wp)
		last = wp
	return total


func _test_personalities() -> void:
	print("-- personalities")
	check(db.personalities.size() >= 10, "there are at least ten personalities")
	var moods := {}
	for id: String in ["easygoing", "perfectionist", "thrill_seeker", "penny_pincher", "nature_lover", "zen"]:
		var g := Golfer.new()
		g.satisfaction = 60.0
		g.persona = DataDB.find(db.personalities, id)
		g.feel(-4.0, "weeds", "weeds")
		var weeds := g.satisfaction - 60.0
		g.satisfaction = 60.0
		g.feel(-20.0, "hit", "hit")
		var hit := g.satisfaction - 60.0
		g.satisfaction = 60.0
		g.feel(2.0, "scenery", "scenery")
		var scenery := g.satisfaction - 60.0
		moods[id] = {"weeds": weeds, "hit": hit, "scenery": scenery}
		print("   %-14s weeds %+5.1f  hit by ball %+6.1f  scenery %+5.1f" % [id, weeds, hit, scenery])
	check(moods.perfectionist.weeds < moods.easygoing.weeds * 2.0, "a perfectionist minds weeds far more than an easygoing golfer")
	check(moods.zen.hit > moods.easygoing.hit, "a zen master shrugs off more")
	check(moods.thrill_seeker.hit > 0.0, "a thrill seeker enjoys being hit")
	check(moods.nature_lover.scenery > moods.easygoing.scenery * 2.0, "a nature lover is moved by scenery")
	var sim := _sim("three_holes", 6)
	var seen := {}
	for i in 300:
		var g := sim.visitors.make_golfer("public", 0.4)
		seen[g.persona.id] = true
	check(seen.size() >= 10, "arrivals come in every personality (%d kinds seen)" % seen.size())
	var hole := sim.course.holes[0]
	var tight := sim.visitors.make_golfer("public", 0.4)
	tight.persona = DataDB.find(db.personalities, "penny_pincher")
	var loose := sim.visitors.make_golfer("public", 0.4)
	loose.persona = DataDB.find(db.personalities, "high_roller")
	loose.wealth = tight.wealth
	loose.satisfaction = tight.satisfaction
	check(sim.visitors.worth(loose, hole) > sim.visitors.worth(tight, hole) * 2.0, "a high roller pays far more than a penny pincher for the same hole")
	tight.sat_at_tee = 60.0
	tight.satisfaction = 63.0
	loose.sat_at_tee = 60.0
	loose.satisfaction = 63.0
	var from_tight := sim.visitors.collect_fee(tight, hole, 0)
	var from_loose := sim.visitors.collect_fee(loose, hole, 0)
	check(from_loose > from_tight and from_tight > 0.0, "and both still pay for a hole they liked (%s against %s)" % [Defs.money(from_loose), Defs.money(from_tight)])


func _test_facilities() -> void:
	print("-- needs and facilities")
	var sim := _sim("three_holes", 16)
	var holes := sim.course.holes
	var gr := sim.visitors.add_group("public", 3, 0.4)
	for m in gr.members:
		m.thirst = 0.9
		m.hunger = 0.2
		m.bladder = 0.2
	gr.hole_i = 1
	for m in gr.members:
		m.pos = holes[0].pin
	check(sim.visitors.plan_stop(gr).is_empty(), "with no facilities there is nowhere to stop")
	var mid := holes[0].pin.lerp(holes[1].tee, 0.5)
	var t := sim.course.tile_of(mid.x, mid.z)
	sim.course.guard = false
	sim.course.set_terrain(t.x, t.y, Defs.T.ROUGH)
	sim.course.set_terrain(t.x + 1, t.y, Defs.T.ROUGH)
	sim.course.set_terrain(t.x + 2, t.y, Defs.T.ROUGH)
	sim.course.guard = true
	check(sim.place_object(t.x, t.y, Defs.O.DRINK_STAND) == 1, "a drink stand goes up")
	var stop := sim.visitors.plan_stop(gr)
	check(stop.get("kind", "") == "drink", "a thirsty group plans a stop at it")
	var money := sim.economy.money
	sim.visitors.serve(gr, "drink")
	check(sim.economy.money > money and gr.members[0].thirst == 0.0, "they buy drinks and are no longer thirsty")
	check(int(gr.members[0].rd.served) == 1, "and remember being looked after")
	for m in gr.members:
		m.bladder = 0.95
		m.thirst = 0.0
	check(sim.place_object(t.x + 1, t.y, Defs.O.RESTROOM) == 1 and sim.visitors.plan_stop(gr).get("kind", "") == "restroom", "a restroom gets used when it is needed")
	for m in gr.members:
		m.bladder = 0.0
		m.hunger = 0.95
	check(sim.place_object(t.x + 2, t.y, Defs.O.SNACK_BAR) == 1 and sim.visitors.plan_stop(gr).get("kind", "") == "snack", "and a snack bar feeds the hungry")
	var tee := sim.course.tile_of(holes[1].tee.x, holes[1].tee.z)
	sim.course.guard = false
	sim.course.set_object(tee.x + 2, tee.y + 1, Defs.O.NONE)
	sim.course.guard = true
	check(not sim.visitors.facility_near("washer", holes[1].tee, 18.0), "no ball washer by the tee yet")
	var placed := false
	for dx in range(1, 4):
		if not placed and sim.place_object(tee.x + dx, tee.y + 1, Defs.O.BALL_WASHER) == 1:
			placed = true
	check(placed and sim.visitors.facility_near("washer", holes[1].tee, 18.0), "a ball washer by the tee is noticed")
	var am := sim.visitors.amenity_counts()
	check(int(am.drink) == 1 and int(am.restroom) == 1 and int(am.snack) == 1 and int(am.washer) == 1, "the club knows what it has")
	# a full month with facilities: concessions earn, and needs get met
	var before := sim.rating
	sim.hire("beverage")
	sim.hire("greenkeeper")
	_run(sim, 430.0)
	var row: Dictionary = sim.economy.history[0]
	print("   a month with a stand, snack bar, restroom and drinks cart: concessions %s, wages %s" % [Defs.money(float(row.income.get("concessions", 0.0))), Defs.money(float(row.expense.get("wages", 0.0)))])
	check(float(row.income.get("concessions", 0.0)) > 30.0, "food and drink earn money")
	var grumbles := 0
	var served := 0
	for g in sim.visitors.golfers:
		grumbles += int(g.rd.grumbles)
		served += int(g.rd.served)
	check(sim.crew.count("beverage") == 1 and sim.crew.monthly_wages() > 0.0, "the drinks cart is on the payroll")
	check(sim.rating >= before - 8.0, "the rating holds up")
	# staff can be promoted
	var keeper := sim.crew.members[1]
	var wages := sim.crew.monthly_wages()
	check(sim.crew.promote(keeper) and keeper.level == 2 and sim.crew.monthly_wages() > wages, "staff can be promoted for more pay")
	check(not sim.crew.promote(keeper), "but only once")


func _test_membership() -> void:
	print("-- club membership")
	var sim := _sim("three_holes", 18)
	var mem := sim.members
	check(mem.tiers.size() == 6 and mem.tier_name(0) == "Basic" and mem.tier_name(5) == "Platinum", "six tiers from Basic to Platinum")
	check(mem.factors.size() >= 10, "at least ten hidden wishes exist")
	# a golfer who had a miserable day never joins
	var sour := sim.visitors.make_golfer("public", 0.4)
	sour.holes_played = 3
	sour.satisfaction = 40.0
	mem.on_depart(sour)
	check(mem.count() == 0, "an unhappy golfer does not join")
	var joined := 0
	for i in 40:
		var g := sim.visitors.make_golfer("public", 0.4)
		g.holes_played = 3
		g.satisfaction = 95.0
		mem.on_depart(g)
	joined = mem.count()
	check(joined > 5 and joined < 40, "delighted golfers often join, but not always (%d of 40)" % joined)
	var m: Dictionary = mem.roster[0]
	check(int(m.tier) == 0 and (m.wants as Array).size() == 5, "a new member is Basic, with five private wishes")
	check(not m.known.has(true), "and has told you none of them")
	var kinds := {}
	for r in mem.roster:
		kinds[str(r.wants[0])] = true
	check(kinds.size() >= 3, "different members want different things (%d first wishes)" % kinds.size())
	check(mem.monthly_dues() == joined * float(mem.tiers[0].dues), "Basic members pay Basic dues")
	# a visit that does not grant the wish: no promotion, and after two the member says why
	m.wants[0] = "practice"
	var g1 := mem.make_golfer(m)
	check(not g1.member.is_empty() and m.on_course, "a member comes back to play")
	check(mem.discount(g1) == 0.0, "Basic members pay full green fees")
	g1.holes_played = 3
	g1.satisfaction = 80.0
	mem.on_depart(g1)
	check(int(m.tier) == 0 and int(m.visits) == 1 and not m.on_course, "a good round without the wish granted: still Basic")
	var g2 := mem.make_golfer(m)
	g2.holes_played = 3
	g2.satisfaction = 80.0
	mem.on_depart(g2)
	check(int(m.tier) == 0 and m.known[0] == true, "after two such rounds they tell you what they want")
	# grant the wish
	var c := sim.course
	var t := c.clubhouse + Vector2i(8, -6)
	c.guard = false
	c.set_terrain(t.x, t.y, Defs.T.ROUGH)
	c.set_terrain(t.x + 2, t.y, Defs.T.ROUGH)
	c.set_object(t.x, t.y, Defs.O.NONE)
	c.set_object(t.x + 2, t.y, Defs.O.NONE)
	c.guard = true
	sim.economy.money = 50000.0
	check(sim.place_object(t.x, t.y, Defs.O.PUTTING_GREEN) == 1 and sim.place_object(t.x + 2, t.y, Defs.O.DRIVING_RANGE) == 1, "build a putting green and a range")
	var g3 := mem.make_golfer(m)
	g3.holes_played = 3
	g3.satisfaction = 80.0
	check(mem.score_factor(g3, "practice") >= 0.99, "the practice wish is now granted in full")
	mem.on_depart(g3)
	check(int(m.tier) == 1, "and the member moves up to Advanced")
	check(mem.monthly_dues() > joined * float(mem.tiers[0].dues), "paying higher dues")
	var g4 := mem.make_golfer(m)
	check(mem.discount(g4) > 0.0, "and getting a discount on green fees")
	g4.holes_played = 3
	g4.satisfaction = 20.0
	mem.on_depart(g4)
	check(mem.roster.has(m) and int(m.strikes) == 1, "one terrible round and they think about leaving")
	var g5 := mem.make_golfer(m)
	g5.holes_played = 3
	g5.satisfaction = 20.0
	mem.on_depart(g5)
	check(not mem.roster.has(m), "two in a row and they resign")
	# upper tiers need the course itself to be good enough
	var hi: Dictionary = mem.roster[0]
	hi.tier = 2
	hi.visits_at_tier = 5
	hi.wants[2] = "practice"
	sim.rating = 30.0
	var g6 := mem.make_golfer(hi)
	g6.holes_played = 3
	g6.satisfaction = 85.0
	mem.on_depart(g6)
	check(int(hi.tier) == 2, "Silver is out of reach while the course rating is too low")
	# Silver members buy homes
	sim.rating = 70.0
	hi.visits_at_tier = 5
	check(sim.place_object(t.x + 5, t.y, Defs.O.HOME_SITE) == 1, "mark out a home site")
	var lot_value := sim.lot_value(t.x + 5, t.y)
	var money := sim.economy.money
	var g7 := mem.make_golfer(hi)
	g7.holes_played = 3
	g7.satisfaction = 85.0
	mem.on_depart(g7)
	check(int(hi.tier) == 3, "with a good enough course they reach Silver")
	check(hi.home == true and sim.homes == 1 and sim.economy.money >= money + lot_value - 1.0, "and buy the home site (%s)" % Defs.money(lot_value))
	check(c.objects[t.y * c.w + t.x + 5] == Defs.O.HOUSE, "the lot becomes a house")
	# the wishes are scored from what actually happened in the round
	var probe := sim.visitors.make_golfer("public", 0.4)
	probe.holes_played = 3
	check(mem.score_factor(probe, "safety") == 1.0, "a quiet round is a safe one")
	probe.hits_taken = 1
	check(mem.score_factor(probe, "safety") == 0.0, "being hit is not")
	probe.rd.waited = 400.0
	var slow := mem.score_factor(probe, "pace")
	probe.rd.waited = 10.0
	check(mem.score_factor(probe, "pace") > slow + 0.5, "waiting ruins the pace wish")
	# regulars really do come back in a running game
	var live := _sim("three_holes", 19)
	live.events.timer = 99999.0     # no outbreaks or storms: this is about regulars, not luck
	live.hire("greenkeeper")
	live.hire("exterminator")
	_run(live, 1300.0)
	var returning := 0
	for r in live.members.roster:
		if int(r.visits) > 0:
			returning += 1
	print("   three months in: %d members (%s), %d have been back, dues %s a month, satisfaction %d%%" % [
		live.members.count(), _tier_counts(live), returning, Defs.money(live.members.monthly_dues()), int(live.visitors.average_satisfaction())])
	check(live.members.count() >= 2, "a running course signs up members")
	check(returning >= 1, "and they come back")
	check(float(live.economy.history[-1].income.get("memberships", 0.0)) > 0.0, "dues arrive at month end")


func _tier_counts(sim: Sim) -> String:
	var out := ""
	for t in sim.members.tiers.size():
		var n := sim.members.count_tier(t)
		if n > 0:
			out += "%d %s " % [n, sim.members.tier_name(t)]
	return out.strip_edges()


## Put a story character on the course for a round, and take them off again.
func _story_visit(sim: Sim, member_id: int, satisfaction: float = 70.0, holes: int = 1) -> Golfer:
	var m := sim.members.find_member(member_id)
	var gr := sim.visitors.add_member_group([m])
	var g := gr.members[0]
	g.holes_played = holes
	g.satisfaction = satisfaction
	return g


func _story_leave(sim: Sim, g: Golfer) -> void:
	if g.group != null:
		sim.visitors.groups.erase(g.group)
	sim.visitors.depart(g)


func _test_stories() -> void:
	print("-- the long stories")
	var sim := _sim("three_holes", 5)
	sim.open = false
	var st := sim.stories
	st.enabled = true
	check(st.defs().size() >= 8, "there are at least eight stories to tell (%d)" % st.defs().size())
	var members_before := sim.members.count()
	var state := sim.rng.state
	check(st.start("romance") == "romance", "a story can be started")
	check(sim.rng.state == state, "casting a story leaves the game's dice where they were")
	check(st.running.size() == 1 and sim.members.count() == members_before + 2, "a romance casts two new regulars, who join the club")
	var r: Dictionary = st.running[0]
	var names: Array = (r.names as Dictionary).values()
	check(names.has("Dot Harrow") and names.has("Ray Tolliver") and str(r.stage) == "meet", "with their own names, waiting to meet (%s)" % str(r.stage))
	var d := st.describe(r)
	check(str(d.title) == "Love on the Links" and str(d.chapter) != "", "the Stories panel can say what is going on: %s" % str(d.chapter))
	# they arrive together and the story moves on
	var ma := sim.members.find_member(int(r.cast.a))
	var mb := sim.members.find_member(int(r.cast.b))
	check(int(ma.next_visit) <= sim.day() + 1 and int(mb.next_visit) <= sim.day() + 1, "both are booked in for tomorrow")
	ma.next_visit = sim.day()
	mb.next_visit = sim.day()
	var picked := st.pair_due([])
	check(picked.size() == 2, "when both are due, the starter sends them out together")
	var posts_before := sim.feed.posts.size()
	state = sim.rng.state
	var gr := sim.visitors.add_member_group([ma, mb])
	check(str(r.stage) == "again" and sim.feed.posts.size() == posts_before + 2, "their first round together is posted about by both of them")
	check(gr.members[0].bubble != "", "and the story's name floats over their heads")
	for g in gr.members:
		_story_leave(sim, g)
	gr = sim.visitors.add_member_group([ma, mb])
	check(str(r.stage) == "bench", "a second round and they are waiting on the club: %s" % str(st.describe(r).request))
	check((st.describe(r).needs as Array).size() == 1 and not bool((st.describe(r).needs as Array)[0].met), "the Stories panel shows the request as unmet")
	for g in gr.members:
		_story_leave(sim, g)
	# meet the request: a bench by the water
	var c := sim.course
	var placed := -1
	var tee := c.tile_of(c.holes[0].tee.x, c.holes[0].tee.z)
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var tx := tee.x + dx
			var ty := tee.y + dy
			if placed < 0 and c.in_bounds(tx, ty) and c.in_bounds(tx + 1, ty):
				var i := ty * c.w + tx
				if c.locked[i] == 0 and c.locked[i + 1] == 0 and c.objects[i] == 0 and c.objects[i + 1] == 0 and c.terrain[i] == Defs.T.ROUGH and c.terrain[i + 1] == Defs.T.ROUGH:
					c.terrain[i] = Defs.T.WATER
					c.objects[i + 1] = Defs.O.BENCH
					c.objects_touched(i + 1)
					c.revision += 1
					placed = i + 1
	check(placed >= 0, "a bench can be put beside the water")
	var money := sim.economy.money
	st.on_day(sim.day())
	check(str(r.stage) == "proposal", "the morning after the bench appears the story moves on (%s)" % str(r.stage))
	var ray := _story_visit(sim, int(r.cast.b))
	_story_leave(sim, ray)
	check(str(r.stage) == "wedding", "Ray proposes after his next round")
	members_before = sim.members.count()
	st.on_day(int(r.since) + 14)
	check(st.running.is_empty() and st.finished.size() == 1 and str(st.finished[0].how) == "happy", "two weeks later there is a wedding")
	check(sim.economy.money > money + 1000.0 and sim.members.count() == members_before + 3, "the wedding party pays for the room and three guests join")
	# a request that is never met runs out of time
	var sim2 := _sim("three_holes", 6)
	sim2.open = false
	sim2.stories.enabled = true
	check(sim2.stories.start("heiress") == "heiress", "the heiress comes to look at the view")
	var h: Dictionary = sim2.stories.running[0]
	var celestine := _story_visit(sim2, int(h.cast.a))
	_story_leave(sim2, celestine)
	check(str(h.stage) == "view" and int(h.hole) >= 1, "she has her eye on hole %d" % int(h.hole))
	sim2.stories.on_day(int(h.since) + 131)
	check(sim2.stories.running.is_empty() and str(sim2.stories.finished[0].how) == "quiet", "and buys in Tuscany when nothing changes for four months")
	# branches: the same story ends differently depending on the round
	var ends: Array[String] = []
	for sat in [40.0, 80.0]:
		var s3 := _sim("three_holes", 7)
		s3.open = false
		s3.stories.enabled = true
		s3.stories.start("influencer")
		var r3: Dictionary = s3.stories.running[0]
		var brix := _story_visit(s3, int(r3.cast.a), sat)
		_story_leave(s3, brix)
		ends.append(str(s3.stories.finished[0].how) if not s3.stories.finished.is_empty() else "?")
	check(ends[0] == "sad" and ends[1] == "happy", "the influencer's verdict follows her round (%s, %s)" % [ends[0], ends[1]])
	# lasting gifts: a cheap pro, a rating swing
	var s4 := _sim("three_holes", 8)
	s4.open = false
	s4.stories.enabled = true
	s4.stories.start("critic")
	var r4: Dictionary = s4.stories.running[0]
	for k in 2:
		var mp := _story_visit(s4, int(r4.cast.a), 80.0)
		_story_leave(s4, mp)
	check(s4.stories.finished.size() == 1 and s4.stories.rating_bias() > 5.0, "a rave review lifts the rating for a season")
	s4.stories.start("comeback")
	var r5: Dictionary = s4.stories.running[0]
	var hal := _story_visit(s4, int(r5.cast.a), 70.0)
	_story_leave(s4, hal)
	check(str(r5.stage) == "birdie", "Hal finds his swing when the round went well (%s)" % str(r5.stage))
	s4.stories._on_hole(hal, 0, s4.course.holes[0].par - 1)
	hal = _story_visit(s4, int(r5.cast.a), 70.0)
	_story_leave(s4, hal)
	check(s4.stories.cheap_pro() and s4.stories.running.is_empty(), "and offers to teach for less")
	s4.hire("club_pro")
	var cheap := s4.crew.monthly_wages()
	s4.stories.flags.erase("cheap_pro")
	check(cheap < s4.crew.monthly_wages() * 0.7, "which shows in the wage bill")
	s4.stories.flags["cheap_pro"] = true
	# everything survives a save
	s4.stories.start("quiet")
	var back := Sim.from_dict(db, JSON.parse_string(JSON.stringify(s4.to_dict())), gear)
	check(back.stories.running.size() == 1 and str(back.stories.running[0].stage) == str(s4.stories.running[0].stage) and back.stories.finished.size() == s4.stories.finished.size() and back.stories.cheap_pro(),
		"stories, their stage, their endings and their gifts survive a save")
	check(str((back.stories.running[0].names as Dictionary).a) == "Walter Pargeter", "and so do the characters")
	# a year of play on a small course starts a few stories and finishes some
	var live := _sim("three_holes", 21)
	live.stories.enabled = true
	live.hire("greenkeeper")
	live.events.timer = 999999.0
	var started := {}
	for i in int(Defs.DAYS_PER_YEAR * Defs.DAY_SECONDS * 60):
		live.step(1.0 / 60.0)
		for rr in live.stories.running:
			started[str(rr.def)] = true
	print("   a year on the three-hole course: %d stories started, %d finished, %d still running" % [started.size(), live.stories.finished.size(), live.stories.running.size()])
	for f in live.stories.finished:
		print("     %s (%s): %s" % [str(f.title), str(f.how), str(f.ending)])
	check(started.size() >= 3 and live.stories.finished.size() >= 2, "stories start on their own and some of them finish within a year")


func _test_hole_lab() -> void:
	print("-- what a hole tests")
	var sim := _sim("sandbox", 9)
	var c := sim.course
	# a long, wide-open hole and a short one, side by side on flat ground
	for i in c.heights.size():
		c.heights[i] = 0.0
	for i in c.terrain.size():
		if c.hot[i] == 0:
			c.terrain[i] = Defs.T.FAIRWAY
			c.objects[i] = 0
	c.clubhouse = Vector2i(80, 150)
	c.objects[150 * c.w + 80] = Defs.O.CLUBHOUSE
	c.revision += 1
	sim.paint(30, 20, 2, Defs.T.GREEN)
	sim.paint(30, 110, 1, Defs.T.TEE)
	var long_hole := sim.add_hole(c.tile_center(30, 110), c.tile_center(30, 20))
	sim.paint(70, 60, 2, Defs.T.GREEN)
	sim.paint(70, 80, 1, Defs.T.TEE)
	var short_hole := sim.add_hole(c.tile_center(70, 80), c.tile_center(70, 60))
	check(long_hole.par == 5 and short_hole.par == 3, "a par 5 and a par 3")
	check(long_hole.name != "" and long_hole.name != short_hole.name, "each hole gets its own name (%s, %s)" % [long_hole.name, short_hole.name])
	check(not long_hole.lab_ready, "a new hole has not been rated yet")
	var t0 := Time.get_ticks_msec()
	sim.lab.rate_now(long_hole)
	sim.lab.rate_now(short_hole)
	print("   rated two holes in %d ms" % (Time.get_ticks_msec() - t0))
	print("   %s (par 5, %d yd): length %.2f, accuracy %.2f, imagination %.2f -> %s; expected %.1f / %.1f / %.1f" % [
		long_hole.name, Defs.yards(long_hole.length), long_hole.test_length, long_hole.test_accuracy, long_hole.test_imagination,
		HoleLab.type_name(long_hole.kind), float(long_hole.expect.beginner), float(long_hole.expect.average), float(long_hole.expect.expert)])
	print("   %s (par 3, %d yd): length %.2f, accuracy %.2f, imagination %.2f -> %s; expected %.1f / %.1f / %.1f" % [
		short_hole.name, Defs.yards(short_hole.length), short_hole.test_length, short_hole.test_accuracy, short_hole.test_imagination,
		HoleLab.type_name(short_hole.kind), float(short_hole.expect.beginner), float(short_hole.expect.average), float(short_hole.expect.expert)])
	check(long_hole.lab_ready and short_hole.lab_ready, "both holes get rated")
	check(long_hole.test_length > short_hole.test_length + 0.3, "the long hole rewards length far more")
	check(long_hole.kind & 1 == 1, "so it counts as a test of length")
	check(float(long_hole.expect.beginner) > float(long_hole.expect.expert) + 0.5, "beginners are expected to score worse than experts")
	# hazards make a hole a test of accuracy: water hard against both
	# sides of the green and behind it
	for ty in range(57, 64):
		for tx in [66, 67, 68, 72, 73, 74]:
			c.terrain[ty * c.w + tx] = Defs.T.WATER
	for tx in range(66, 75):
		c.terrain[56 * c.w + tx] = Defs.T.WATER
	c.revision += 1
	# One rating is eight rounds a class, which is a coarse measure: take
	# the average of several, with and without the water.
	var water_acc := 0.0
	for k in 8:
		sim.lab.rate_now(short_hole)
		water_acc += short_hole.test_accuracy / 8.0
	for ty in range(56, 64):
		for tx in range(66, 75):
			if c.terrain[ty * c.w + tx] == Defs.T.WATER:
				c.terrain[ty * c.w + tx] = Defs.T.GREEN if (tx == 68 or tx == 72) and ty >= 58 and ty <= 62 else Defs.T.FAIRWAY
	c.revision += 1
	var open_acc := 0.0
	for k in 8:
		sim.lab.rate_now(short_hole)
		open_acc += short_hole.test_accuracy / 8.0
	print("   the par 3 over eight ratings: accuracy %.2f in the open, %.2f with water tight round the green" % [open_acc, water_acc])
	check(water_acc > open_acc + 0.15, "water round the green makes it a sterner test of accuracy")
	# the background queue picks up changed holes without being asked
	short_hole.lab_ready = false
	short_hole.lab_sig = -1
	sim.open = false
	_run(sim, 45.0)
	check(short_hole.lab_ready, "holes are re-rated in the background after the ground changes")
	# reordering
	check(sim.move_hole(0, 1) and c.holes[0] == short_hole and c.holes[1] == long_hole, "holes can be swapped in the playing order")
	check(not sim.move_hole(1, 1), "but not past the end")
	check(HoleLab.play_hole(sim, sim.visitors.make_golfer("public", 0.7), short_hole) <= short_hole.par + 5, "a whole hole can be played out for a match opponent")


func _test_club_life() -> void:
	print("-- visitors, rankings and accomplishments")
	var sim := _sim("three_holes", 27)
	_run(sim, 5.0)
	# VIPs
	var money := sim.economy.money
	sim.events.trigger("investor")
	var vip := sim.events.celebrity
	check(vip != null and vip.vip == "investor", "an investor comes to look the course over")
	vip.holes_played = 3
	vip.satisfaction = 80.0
	sim.events.celebrity_left(vip)
	check(sim.economy.money > money + 1000.0, "and invests if they enjoy it")
	sim.events.trigger("commissioner")
	vip = sim.events.celebrity
	vip.holes_played = 3
	vip.satisfaction = 80.0
	sim.events.celebrity_left(vip)
	check(sim.land_credits == 3, "a happy commissioner releases three parcels of land")
	sim.events.trigger("heiress")
	vip = sim.events.celebrity
	vip.holes_played = 3
	vip.satisfaction = 30.0
	sim.events.celebrity_left(vip)
	check(int(sim.gifts.get(Defs.O.LANDMARK, 0)) == 0, "an unimpressed heiress gives nothing")
	sim.events.trigger("heiress")
	vip = sim.events.celebrity
	vip.holes_played = 3
	vip.satisfaction = 85.0
	sim.events.celebrity_left(vip)
	check(int(sim.gifts.get(Defs.O.LANDMARK, 0)) == 1, "a delighted one donates a landmark")
	var c := sim.course
	var t := c.clubhouse + Vector2i(-8, -6)
	c.guard = false
	c.set_terrain(t.x, t.y, Defs.T.ROUGH)
	c.set_object(t.x, t.y, Defs.O.NONE)
	c.guard = true
	money = sim.economy.money
	check(sim.place_object(t.x, t.y, Defs.O.LANDMARK) == 1 and is_equal_approx(sim.economy.money, money), "which costs nothing to place")
	check(sim.object_name(Defs.O.LANDMARK) == "Old windmill", "parkland's landmark is a windmill")
	# a money match offer
	sim.events.pending = {}
	sim.events.trigger("match")
	check(sim.events.pending.get("id", "") == "match" and float(sim.events.pending.stake) > 0.0, "a visiting pro offers a money match")
	var accepted := [false]
	sim.match_accepted.connect(func(_o: Dictionary) -> void: accepted[0] = true)
	sim.events.choose("accept")
	check(accepted[0] and sim.events.pending.is_empty(), "accepting it starts the match")
	# resort buildings wait for a bigger course
	check(sim.build_block(Defs.O.HOTEL) != "" and sim.build_block(Defs.O.SNACK_BAR) == "", "a hotel needs a bigger course; a snack bar does not")
	# clubhouse: the first step up needs a few members and a modest rating as well as the cash
	sim.economy.money = 60000.0
	var cap := sim.members.capacity()
	for k in 4:
		sim.members.enroll(sim.visitors.make_golfer("public", 0.5))
	sim.rating = maxf(sim.rating, 45.0)
	check(sim.upgrade_clubhouse() and sim.clubhouse_level == 1 and sim.members.capacity() > cap, "the clubhouse can be upgraded, making room for more members")
	check(not sim.upgrade_clubhouse() and sim.clubhouse_level == 1, "but the next step wants more than money")
	# class, rank, accomplishments
	check(sim.course_class() == "Municipal course", "three holes is a municipal course")
	check(sim.rank() >= 1 and sim.rank() <= sim.rivals.size() + 1, "the course has a world ranking (%d of %d)" % [sim.rank(), sim.rivals.size() + 1])
	sim.rating = 99.0
	check(sim.rank() == 1, "the best course in the world is ranked first")
	var points := int(sim.skills.points.manager)
	sim.feats.check()
	check(sim.feats.has("rating60") and int(sim.skills.points.manager) > points, "accomplishments are earned and pay out skill points")
	check(not sim.feats.has("eighteen"), "but not ones you have not earned")
	sim._end_year(1)
	check(sim.best_rank >= 1 and sim.feats.has("rank1"), "year-end rankings are recorded")
	# the owner in their own tournament
	sim.tourney.schedule("club")
	sim.tourney._start()
	check(sim.events.pending.get("id", "") == "tournament_entry", "the owner is invited to play in their own tournament")
	sim.events.choose("accept")
	check(sim.tourney.player_in and not sim.tourney.player_done, "and can accept")
	var card: Array = []
	var pars: Array = []
	for hole in c.holes:
		card.append(hole.par - 1)
		pars.append(hole.par)
	sim.tourney.player_finished(card, pars)
	var found := false
	for e in sim.tourney.board:
		if e.g == null and int(e.to_par) == -c.holes.size():
			found = true
	check(found and sim.tourney.player_done, "their card goes on the leaderboard")
	var guard := 0
	while sim.tourney.last_result.is_empty() and guard < 60 * 60 * 30:
		sim.step(1.0 / 60.0)
		guard += 1
	check(not sim.tourney.last_result.is_empty(), "and the tournament still finishes")
	# tantrums and wildlife
	var gr := sim.visitors.add_group("public", 2, 0.3)
	var angry := gr.members[0]
	var partner := gr.members[1]      # taken now: a quitter leaves the group
	angry.persona = {}
	angry.satisfaction = 10.0
	var tantrums_before := int(sim.stats.tantrums)
	sim.visitors._tantrum(angry)
	check(angry.tantrum and int(sim.stats.tantrums) == tantrums_before + 1, "a furious golfer has a tantrum")
	check(angry.rage_t > 3.0 and angry.swing_t < 0.0, "and acts it out on the spot for a few seconds")
	var before_pos := angry.pos
	var moved := angry.travel(angry.pos + Vector3(20.0, 0.0, 0.0), 0.5, sim, angry.walk_speed())
	check(not moved and angry.pos.is_equal_approx(before_pos) and not angry.walking, "nobody storms anywhere until the fit is over")
	check(angry.tossed or partner.hit_t > 0.0, "the club flies or a partner gets punched")
	var calm := sim.visitors.make_golfer("public", 0.4)
	var normal := calm.walk_speed()
	calm.storming = true
	check(calm.walk_speed() > normal * 1.3, "a golfer storming off walks a good deal faster")
	calm.begin_hole()
	angry.tossed = true
	angry.begin_hole()
	check(not angry.tossed, "and a thrown club is back in the bag by the next hole")
	check(sim.wildlife.animals.size() >= 4, "there is wildlife on the course (%d animals)" % sim.wildlife.animals.size())
	var a := sim.wildlife.animals[0]
	var was := a.pos
	sim.wildlife.startle(a.pos + Vector3(1.0, 0.0, 1.0))
	_run(sim, 4.0)
	check(a.kind == "tortoise" or a.pos.distance_to(was) > 3.0, "animals bolt when a ball lands near them")
	# everything new survives a save
	sim.members.enroll(sim.visitors.make_golfer("public", 0.5))
	var text := JSON.stringify(sim.to_dict())
	var back := Sim.from_dict(db, JSON.parse_string(text), gear)
	check(back.members.count() == sim.members.count() and back.clubhouse_level == 1, "members and the clubhouse survive a save")
	check(back.feats.has("rating60") and back.best_rank == sim.best_rank and back.land_credits == sim.land_credits,
		"so do accomplishments, rankings and land grants (%s, rank %d/%d, credits %d/%d)" % [str(back.feats.has("rating60")), back.best_rank, sim.best_rank, back.land_credits, sim.land_credits])
	check(back.course.locked == sim.course.locked and back.biome.id == sim.biome.id, "so do the land you own and the biome")
	var vsim := _sim("mount_bogey", 4)
	var vback := Sim.from_dict(db, JSON.parse_string(JSON.stringify(vsim.to_dict())), gear)
	check(vback.is_lava() and vback.course.volcanoes.size() == 1 and vback.course.hot == vsim.course.hot, "a volcano survives a save")
	_run(vback, 30.0)
	check(vback.eruption.start(1.0), "and can still erupt afterwards")


## Fire one shot and report where it pitched, how far it got and where it stopped.
func _flight(lane: Course, speed: float, loft_deg: float, lift: float, spin: float, side: float = 0.0, wind: Vector3 = Vector3.ZERO, lava: bool = false, seed_value: float = -1.0) -> Dictionary:
	var b := Ball.new()
	b.lava = lava
	b.air_seed = seed_value
	b.place(Vector3(10.0, 0.0, 60.0))
	b.launch(speed, 0.0, deg_to_rad(loft_deg), lift, side, spin)
	var furthest := 0.0
	var top := 0.0
	var n := 0
	while b.moving() and n < 5000:
		b.step(1.0 / 60.0, lane, wind, Vector3.ZERO, false)
		n += 1
		top = maxf(top, b.pos.y)
		if b.bounces > 0:
			furthest = maxf(furthest, b.pos.x)
	return {"ball": b, "carry": b.carry.x - 10.0, "rest": b.pos.x - 10.0, "furthest": furthest - 10.0, "z": b.pos.z - 60.0, "top": top, "time": n / 60.0}


func _test_spin_wind_lies() -> void:
	print("-- spin, wind, lies and out of bounds")
	# ---- spin on landing
	var green := _lane(Defs.T.GREEN)
	var none := _flight(green, 36.0, 27.0, 0.26, 0.0)
	var usual := _flight(green, 36.0, 27.0, 0.26, 0.65)
	var lots := _flight(green, 36.0, 27.0, 0.26, 1.05)
	var over := _flight(green, 36.0, 27.0, 0.26, -0.4)
	var run_none: float = float(none.rest) - float(none.carry)
	var run_usual: float = float(usual.rest) - float(usual.carry)
	var run_lots: float = float(lots.rest) - float(lots.carry)
	var pulled: float = float(lots.furthest) - float(lots.rest)
	print("   a wedge onto a green runs %.1f m with no spin, %.1f m with its usual spin, %.1f m with all it can take (pulled back %.1f m); topspin runs %.1f m" % [
		run_none, run_usual, run_lots, pulled, float(over.rest) - float(over.carry)])
	check(is_equal_approx(float(none.carry), float(lots.carry)), "spin on landing does not change the carry")
	check(run_usual < run_none * 0.6, "backspin checks the ball on a green")
	check(run_lots < run_usual - 3.0 and pulled > 0.5, "a lot of backspin pulls it back")
	check(pulled < 5.0, "but only a couple of yards")
	check(float(over.rest) > float(none.rest) + 1.0, "topspin makes it run")
	var rough := _lane(Defs.T.ROUGH)
	var in_rough := _flight(rough, 36.0, 27.0, 0.26, 1.05)
	check(float(in_rough.furthest) - float(in_rough.rest) < 0.05, "nothing spins back out of rough")
	var fairway := _lane()
	var bent := _flight(fairway, 50.0, 19.0, 0.23, 0.38, 0.04)
	var straight := _flight(fairway, 50.0, 19.0, 0.23, 0.38, 0.0)
	var bb: Ball = bent.ball
	print("   a faded 7 iron finishes %.1f m right, %.1f m of it after pitching" % [float(bent.z), float(bent.z) - (bb.carry.z - 60.0)])
	check(absf(float(straight.z)) < 0.01 and float(bent.z) > 3.0, "sidespin bends the flight")
	check(float(bent.z) - (bb.carry.z - 60.0) > 0.5, "and kicks the ball the same way when it lands")
	var sb := Ball.new()
	sb.place(Vector3(10.0, 0.0, 60.0))
	sb.launch(36.0, 0.0, deg_to_rad(27.0), 0.26, 0.0, 0.8)
	sb.step(1.0 / 60.0, green, Vector3.ZERO, Vector3.ZERO, false)
	var turning := sb.spin_vector()
	check(turning.z > 100.0 and absf(turning.x) < 1.0, "in the air the ball turns backwards about the axis across its flight")
	sb.launch(3.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	sb.step(1.0 / 60.0, green, Vector3.ZERO, Vector3.ZERO, false)
	check(sb.spin_vector().z < -50.0, "a putt rolls forwards")

	# ---- wind
	var calm := _flight(fairway, 74.7, 12.0, 0.15, 0.05)
	var cross := _flight(fairway, 74.7, 12.0, 0.15, 0.05, 0.0, Vector3(0.0, 0.0, 5.0))
	var cross2 := _flight(fairway, 74.7, 12.0, 0.15, 0.05, 0.0, Vector3(0.0, 0.0, 10.0))
	var into := _flight(fairway, 74.7, 12.0, 0.15, 0.05, 0.0, Vector3(-8.0, 0.0, 0.0))
	var down := _flight(fairway, 74.7, 12.0, 0.15, 0.05, 0.0, Vector3(8.0, 0.0, 0.0))
	print("   a drive carries %.0f m in still air, %.0f m into 18 mph and %.0f m with it; an 11 mph crosswind moves it %.0f m, 22 mph %.0f m" % [
		float(calm.carry), float(into.carry), float(down.carry), float(cross.z), float(cross2.z)])
	check(float(cross.z) > 8.0 and float(cross2.z) > float(cross.z) * 1.7, "a crosswind carries the ball sideways, more the harder it blows")
	check(float(into.carry) < float(calm.carry) * 0.9 and float(down.carry) > float(calm.carry) * 1.03, "a headwind shortens a drive and a tailwind lengthens it")
	check(float(into.top) > float(calm.top), "into the wind the ball climbs")
	check(Defs.wind_at(10.0) == 1.0 and Defs.wind_at(30.0) > 1.2 and Defs.wind_at(1.0) < 0.65, "the wind blows harder high up than near the ground")
	var high := _flight(fairway, 45.0, 30.0, 0.26, 0.6, 0.0, Vector3(0.0, 0.0, 8.0))
	var low := _flight(fairway, 45.0, 13.0, 0.14, 0.6, 0.0, Vector3(0.0, 0.0, 8.0))
	print("   in a crosswind a high shot (%.0f m up, %.1f s) drifts %.1f m; a punch (%.0f m up, %.1f s) drifts %.1f m" % [
		float(high.top), float(high.time), float(high.z), float(low.top), float(low.time), float(low.z)])
	var hb: Ball = high.ball
	var lb: Ball = low.ball
	check(lb.carry.z - 60.0 < (hb.carry.z - 60.0) * 0.6, "a low punch is blown about far less than a high shot")
	# air currents: trees, slopes, eddies and the heat off lava
	var air := Ball.new()
	air.place(Vector3(402.5, 3.0, 62.5))
	var wind := Vector3(8.0, 0.0, 0.0)
	var open_air := air._air(fairway, fairway.index_at(402.5, 62.5), wind).length()
	fairway.objects[fairway.index_at(402.5, 62.5)] = Defs.O.OAK
	var lee := air._air(fairway, fairway.index_at(402.5, 62.5), wind).length()
	fairway.objects[fairway.index_at(402.5, 62.5)] = 0
	check(lee < open_air * 0.5, "there is shelter from the wind among trees")
	var hill := _lane()
	for vy in hill.h + 1:
		for vx in hill.w + 1:
			hill.heights[vy * (hill.w + 1) + vx] = vx * 0.5
	air.place(Vector3(200.0, hill.height_at(200.0, 60.0) + 2.0, 60.0))
	var rising := air._air(hill, hill.index_at(200.0, 60.0), wind)
	var sinking := air._air(hill, hill.index_at(200.0, 60.0), -wind)
	check(rising.y > 0.4 and sinking.y < -0.4, "wind blowing up a slope lifts the ball, and down a slope presses on it")
	var eddy_a := _flight(fairway, 74.7, 12.0, 0.15, 0.05, 0.0, Vector3(0.0, 0.0, 8.0), false, 11.0)
	var eddy_b := _flight(fairway, 74.7, 12.0, 0.15, 0.05, 0.0, Vector3(0.0, 0.0, 8.0), false, 157.0)
	var steady := _flight(fairway, 74.7, 12.0, 0.15, 0.05, 0.0, Vector3(0.0, 0.0, 8.0))
	var steady2 := _flight(fairway, 74.7, 12.0, 0.15, 0.05, 0.0, Vector3(0.0, 0.0, 8.0))
	check(absf(float(eddy_a.z) - float(eddy_b.z)) > 0.3, "no two shots meet the same eddies (%.1f m and %.1f m of drift)" % [float(eddy_a.z), float(eddy_b.z)])
	check(float(steady.z) == float(steady2.z), "a golfer planning a shot reckons on the steady wind")
	check(absf(float(eddy_a.z) - float(steady.z)) < float(steady.z) * 0.4, "eddies nudge a shot: they do not take it over")
	var molten := _lane(Defs.T.WATER)
	var over_lava := _flight(molten, 50.0, 19.0, 0.23, 0.38, 0.0, Vector3.ZERO, true)
	var over_water := _flight(molten, 50.0, 19.0, 0.23, 0.38, 0.0, Vector3.ZERO, false)
	print("   a 7 iron carries %.0f m over water and %.0f m on the heat rising off lava" % [float(over_water.carry), float(over_lava.carry)])
	check(float(over_lava.carry) > float(over_water.carry) + 3.0, "hot air over lava holds the ball up")
	var wsim := _sim("three_holes", 3)
	wsim.open = false
	var peak := 0.0
	var gusts := 0
	var was_gust := false
	var hardest := 0.0
	for i in 60 * 200:
		wsim.step(1.0 / 60.0)
		var gst := wsim.weather.gust
		peak = maxf(peak, gst)
		if gst > 0.25 and not was_gust:
			gusts += 1
		was_gust = gst > 0.25
		if gst > 0.25:
			hardest = maxf(hardest, wsim.weather.wind_vec().length() / maxf(wsim.weather.wind_speed, 0.01))
	print("   200 s of weather: %d gusts, the hardest %d%% over the steady wind" % [gusts, int((hardest - 1.0) * 100.0)])
	check(gusts >= 3 and gusts <= 40 and hardest > 1.12, "the wind gusts")

	# ---- lies
	var sim := _sim("sandbox", 9)
	sim.open = false
	var c := sim.course
	for i in c.heights.size():
		c.heights[i] = 0.0
	for i in c.terrain.size():
		if c.hot[i] == 0:
			c.terrain[i] = Defs.T.ROUGH
			c.objects[i] = 0
	c.wet.fill(0.1)
	c.revision += 1
	var g := sim.visitors.make_golfer("public", 0.5)
	g.imagination = 0.0
	g.teed = true
	var counts := {"": 0, "up": 0, "down": 0}
	var spin_up := 1.0
	var power_down := 1.0
	for i in 400:
		g.ball.place(c.on_ground(150.0 + i * 1.37, 150.0 + i * 0.71))
		var lr := Lie.read(sim, g, 0.0)
		counts[str(lr.sit)] = int(counts.get(str(lr.sit), 0)) + 1
		if str(lr.sit) == "up":
			spin_up = float(lr.spin)
		elif str(lr.sit) == "down":
			power_down = float(lr.power)
	print("   400 balls in the rough: %d sitting up, %d sitting down, %d ordinary" % [int(counts.up), int(counts.down), int(counts[""])])
	check(int(counts.up) > 60 and int(counts.up) < 140 and int(counts.down) > 80 and int(counts.down) < 160, "a ball in the rough can sit up or sit down")
	check(spin_up < 0.5 and power_down < 0.95, "a flyer has little spin and a ball sitting down loses distance")
	g.ball.place(c.on_ground(200.0, 200.0))
	var same := Lie.read(sim, g, 0.0)
	check(str(same.sit) == str(Lie.read(sim, g, 1.0).sit), "the lie is the same however you look at it")
	g.teed = false
	check(str(Lie.read(sim, g, 0.0).sit) == "", "on the tee the ball sits on a peg")
	g.teed = true
	c.terrain[c.index_at(200.0, 200.0)] = Defs.T.FAIRWAY
	var clean := Lie.read(sim, g, 0.0)
	check(float(clean.spin) == 1.0 and float(clean.power) == 1.0 and (clean.notes as Array).is_empty(), "a fairway lie is a clean one")
	c.terrain[c.index_at(200.0, 200.0)] = Defs.T.DEEP_ROUGH
	var thick := Lie.read(sim, g, 0.0)
	c.terrain[c.index_at(200.0, 200.0)] = Defs.T.ROUGH
	var semi := Lie.read(sim, g, 0.0)
	check(float(thick.spin) < float(semi.spin) and float(semi.spin) < 1.0, "the thicker the grass, the less spin")
	c.terrain[c.index_at(200.0, 200.0)] = Defs.T.BUNKER
	var sand := Lie.read(sim, g, 0.0)
	g.ball.plugged = true
	var buried := Lie.read(sim, g, 0.0)
	check(float(sand.mishit) > 1.2 and str(sand.sit) == "", "sand makes a clean strike harder")
	check(str(buried.sit) == "plugged" and float(buried.power) < 0.7 and float(buried.spin) < 0.2, "a plugged ball comes out weak and without spin (%s)" % str(buried.name))
	g.bonus_sand = 0.5
	check(float(Lie.read(sim, g, 0.0).power) > float(buried.power) + 0.1, "a golfer with sand skills gets more out of it")
	g.bonus_sand = 0.0
	g.plan = {"putt": false, "ci": 10, "speed": 20.0, "heading": 0.0, "dist": 30.0}
	var heard: Array[String] = []
	sim.sound.connect(func(id: String, _p: Vector3, _v: float) -> void: heard.append(id))
	ShotAI.strike(sim, g)
	ShotAI.emit_strike(sim, g)
	check(heard.has("strike_sand") and not g.ball.plugged, "a shot from sand sounds like one, and the ball is out of its hole")
	heard.clear()
	c.terrain[c.index_at(200.0, 200.0)] = Defs.T.ROUGH
	g.ball.place(c.on_ground(200.0, 200.0))
	ShotAI.strike(sim, g)
	ShotAI.emit_strike(sim, g)
	check(heard.has("strike_rough") and heard.has("chip"), "from rough you hear the grass as well as the club")
	# wet grass and sloping stances
	c.terrain[c.index_at(200.0, 200.0)] = Defs.T.FAIRWAY
	g.ball.place(c.on_ground(200.0, 200.0))
	c.wet.fill(0.95)
	check(float(Lie.read(sim, g, 0.0).spin) < 0.7, "a wet lie takes spin off")
	c.wet.fill(0.1)
	for vy in c.h + 1:
		for vx in c.w + 1:
			c.heights[vy * (c.w + 1) + vx] = vx * 0.5
	g.ball.place(c.on_ground(200.0, 200.0))
	var uphill := Lie.read(sim, g, 0.0)
	var downhill := Lie.read(sim, g, PI)
	var below := Lie.read(sim, g, PI * 0.5)
	var above := Lie.read(sim, g, -PI * 0.5)
	check(float(uphill.loft) > 0.03 and float(downhill.loft) < -0.03, "an uphill lie adds loft and a downhill one takes it off")
	check(float(below.side) > 0.02 and float(above.side) < -0.02, "the ball below your feet fades and above them draws")
	check((uphill.notes as Array).size() == 1 and (below.notes as Array).size() == 1, "and the golfer is told so (%s)" % Lie.text(below))
	var bl := Lie.blend(below, {"side": -0.04, "lift": 1.1})
	check(is_equal_approx(float(bl.side), -0.04 + float(below.side)) and float(bl.lift) == 1.1, "a lie folds into the shot shape")
	# dropping steeply into sand
	var beach := _lane(Defs.T.BUNKER)
	var plugs := 0
	var settled := 0.0
	for i in 60:
		var pb := Ball.new()
		pb.place(Vector3(20.0 + i * 3.3, 30.0, 60.0 + i * 0.37))
		pb.state = Ball.S.FLIGHT
		pb.vel = Vector3(6.0, -2.0, 0.0)
		var n := 0
		while pb.moving() and n < 2000:
			pb.step(1.0 / 60.0, beach, Vector3.ZERO, Vector3.ZERO, false)
			n += 1
		if pb.plugged:
			plugs += 1
			settled = maxf(settled, Vector2(pb.pos.x - pb.carry.x, pb.pos.z - pb.carry.z).length())
	print("   60 balls dropped into a bunker from 30 m: %d plugged" % plugs)
	check(plugs > 6 and plugs < 36 and settled < 0.05, "a ball dropping steeply into sand sometimes plugs, and stays where it lands")

	# ---- out of bounds
	var edge := _lane()
	for ty in 4:
		for tx in edge.w:
			edge.locked[ty * edge.w + tx] = 1
	# a bank beyond the boundary that throws the ball back
	for vy in 5:
		for vx in edge.w + 1:
			edge.heights[vy * (edge.w + 1) + vx] = (4 - vy) * 2.0
	var back_in := Ball.new()
	back_in.place(Vector3(100.0, 0.0, 30.0))
	back_in.launch(9.0, -PI * 0.5, 0.0, 0.0, 0.0, 0.0)
	var crossed := false
	var n2 := 0
	while back_in.moving() and n2 < 4000:
		back_in.step(1.0 / 60.0, edge, Vector3.ZERO, Vector3.ZERO, false)
		n2 += 1
		crossed = crossed or back_in.pos.z < 20.0
	check(crossed and back_in.state == Ball.S.REST and back_in.pos.z > 20.0, "a ball that crosses the boundary and rolls back in is still in play")
	var flat := _lane()
	for ty in 4:
		for tx in flat.w:
			flat.locked[ty * flat.w + tx] = 1
	var gone := Ball.new()
	gone.place(Vector3(100.0, 0.0, 30.0))
	gone.launch(9.0, -PI * 0.5, 0.0, 0.0, 0.0, 0.0)
	n2 = 0
	while gone.moving() and n2 < 4000:
		gone.step(1.0 / 60.0, flat, Vector3.ZERO, Vector3.ZERO, false)
		n2 += 1
	check(gone.state == Ball.S.OOB and gone.pos.z < 20.0, "one that comes to rest beyond it is out of bounds")
	var off := Ball.new()
	off.place(Vector3(100.0, 0.0, 10.0))
	off.launch(30.0, -PI * 0.5, deg_to_rad(30.0), 0.2, 0.0, 0.3)
	n2 = 0
	while off.moving() and n2 < 4000:
		off.step(1.0 / 60.0, flat, Vector3.ZERO, Vector3.ZERO, false)
		n2 += 1
	check(off.state == Ball.S.OOB, "and so is one hit clean off the map")
	# a water ball is never dropped on someone else's land
	for tx in flat.w:
		flat.terrain[5 * flat.w + tx] = Defs.T.WATER
	var wetb := Ball.new()
	wetb.start = Vector3(100.0, 0.0, 60.0)
	wetb.last_land = Vector3(100.0, 0.0, 12.0)
	var spot := Group.drop_spot(flat, wetb)
	check(flat.locked[flat.index_at(spot.x, spot.z)] == 0 and flat.terrain_at(spot.x, spot.z) != Defs.T.WATER, "a ball lost in water is dropped on the club's own dry land")
	# stroke and distance, for the computer golfers
	var osim := _sim("three_holes", 14)
	var gr := osim.visitors.add_group("public", 1, 0.5)
	var og := gr.members[0]
	var hole := osim.course.holes[0]
	og.ball.place(hole.tee)
	og.ball.start = hole.tee
	og.ball.pos = hole.tee + Vector3(40.0, 0.0, 0.0)
	og.ball.state = Ball.S.OOB
	og.strokes = 1
	gr._resolve(osim, og, hole)
	check(og.strokes == 2 and og.ball.pos.distance_to(hole.tee) < 0.01 and int(og.rd.lost_balls) == 1, "out of bounds costs a stroke and the shot is played again from the same spot")
	var called: Array[String] = []
	osim.sound.connect(func(id: String, _p: Vector3, _v: float) -> void: called.append(id))
	var oc := osim.course
	var lost_at := Vector2i(-1, -1)
	for py in range(0, oc.h, Course.PARCEL):
		for px in range(0, oc.w, Course.PARCEL):
			if oc.locked[py * oc.w + px] != 0 and oc.hot[py * oc.w + px] == 0 and oc.terrain[(py + 3) * oc.w + px + 3] != Defs.T.WATER and lost_at.x < 0:
				lost_at = Vector2i(px + 3, py + 3)
	var op := oc.tile_center(lost_at.x, lost_at.y)
	og.ball.place(Vector3(op.x, oc.height_at(op.x, op.z) + 6.0, op.z))
	og.ball.state = Ball.S.FLIGHT
	og.ball.vel = Vector3(0.0, -3.0, 0.0)
	osim.visitors.track_ball(og.ball, hole)
	for i in 600:
		osim.visitors._step_balls(1.0 / 60.0)
	check(og.ball.state == Ball.S.OOB and called.has("oob"), "the game calls a ball out of bounds when it stops there")


func _test_seasons_and_scorecard() -> void:
	print("-- seasons and the scorecard")
	check(Defs.spring_phase(0) == 1.0 and Defs.spring_phase(60) == 0.0, "spring freshness fades through April")
	check(Defs.autumn_phase(100) == 0.0 and Defs.autumn_phase(168) == 0.0 and Defs.autumn_phase(190) > 0.4 and Defs.autumn_phase(215) == 1.0, "the trees turn from September and are all turned by mid October")
	check(Defs.autumn_phase(224 + 200) == Defs.autumn_phase(200), "and the seasons come round again next year")
	var summer := Defs.season_grass(100)
	var fall := Defs.season_grass(220)
	check(is_equal_approx(summer.r, 1.0) and fall.b < 0.9 and fall.r > 1.0, "the grass is plain green in summer and golden in autumn")
	var sim := _sim("three_holes", 5)
	var h := sim.course.holes[0]
	for sc in [h.par - 1, h.par, h.par, h.par + 2, 1]:
		h.record(sc)
	check(h.plays == 5 and h.aces == 1 and int(h.tally.get("-1", 0)) == 1 and int(h.tally.get("2", 0)) == 1, "the scorecard counts every score against par and the aces")
	check(absf(h.share(["-2", "-1"]) - 0.4) < 0.01 and absf(h.share(["1", "2", "3"]) - 0.2) < 0.01, "and gives the share of birdies and bogeys")
	var back := Hole.from_dict(h.to_dict())
	check(back.aces == 1 and int(back.tally.get("-1", 0)) == 1 and back.plays == 5, "the tally survives a save")


func _test_gallery() -> void:
	print("-- the gallery at a tournament")
	var sim := _sim("three_holes", 7)
	sim.economy.money = 60000.0
	var t := sim.tourney
	check(t.gallery.is_empty() and t.gallery_hole == -1 and t.gallery_size() == 0, "no tournament, no gallery")
	check(t.schedule("club"), "the club championship can be booked")
	t._start()
	sim.events.choose("decline")
	Game_fast(sim, 200.0)
	var out := 0
	for gr: Group in t.active.groups:
		if gr.state == Group.S.PLAY:
			out += 1
	var followed := t.followed_group()
	print("   %d groups out, following hole %d, %d spectators" % [out, t.gallery_hole + 1, t.gallery.size()])
	check(followed != null and t.gallery_hole == followed.hole_i, "the gallery follows the leading group's hole")
	check(t.gallery.size() >= 20 and t.gallery.size() <= 80, "a club championship draws a few dozen spectators (%d)" % t.gallery.size())
	var on_hole := 0
	var at_green := 0
	var bad := 0
	var c := sim.course
	var pin: Vector3 = c.holes[t.gallery_hole].pin
	for e: Dictionary in t.gallery:
		var p: Vector3 = e.pos
		var i := c.index_at(p.x, p.z)
		var terrain: int = c.terrain[i] if i >= 0 else -1
		if i < 0 or c.locked[i] != 0 or c.objects[i] != 0 or not (terrain == Defs.T.ROUGH or terrain == Defs.T.DEEP_ROUGH or terrain == Defs.T.PATH):
			bad += 1
		if int(e.hole) == t.gallery_hole:
			on_hole += 1
			if Vector2(p.x - pin.x, p.z - pin.z).length() < 30.0:
				at_green += 1
	check(bad == 0, "nobody stands on a playing surface, in water, on something built or on land the club does not own (%d did)" % bad)
	check(on_hole >= t.gallery.size() * 0.7 and at_green >= 5, "most of them line the followed hole, with a ring round its green (%d on it, %d at the green)" % [on_hole, at_green])
	# more people for a bigger event, and as the field gets round
	var small := t.gallery_size()
	var def: Dictionary = t.active.def
	var club_prestige := int(def.prestige)
	def.prestige = 30
	var big := t.gallery_size()
	def.prestige = club_prestige
	check(big > small * 3, "a major draws several times the crowd of a club championship (%d against %d)" % [big, small])
	var was_on := followed.hole_i
	followed.hole_i = 0
	var early := t.gallery_size()
	followed.hole_i = c.holes.size() - 1
	var late := t.gallery_size()
	followed.hole_i = was_on
	check(late > early, "and the crowd grows as the leaders get round (%d then %d)" % [early, late])
	# the gallery moves with the leaders, and reacts to what they score
	var heard: Array[String] = []
	sim.sound.connect(func(id: String, _p: Vector3, _v: float) -> void: heard.append(id))
	var leader: Golfer = followed.members[0]
	leader.scores.append(c.holes[t.gallery_hole].par - 2)
	leader.pars.append(c.holes[t.gallery_hole].par)
	if leader.scores.size() - 1 != t.gallery_hole:
		leader.scores.clear()
		leader.pars.clear()
		for k in t.gallery_hole:
			leader.scores.append(4)
			leader.pars.append(4)
		leader.scores.append(c.holes[t.gallery_hole].par - 2)
		leader.pars.append(c.holes[t.gallery_hole].par)
	t.on_hole(leader)
	check(heard.has("ovation"), "an eagle on the followed hole gets an ovation")
	heard.clear()
	leader.scores[-1] = c.holes[t.gallery_hole].par + 2
	t.on_hole(leader)
	check(heard.has("groan"), "a double bogey gets a groan")
	var rev := t.gallery_rev
	# the whole field moves on a hole (whichever group leads, the gallery follows it)
	var next_hole := (t.gallery_hole + 1) % c.holes.size()
	for gr: Group in t.active.groups:
		if gr.state == Group.S.PLAY:
			gr.hole_i = next_hole
	t._step_gallery(0.1)
	check(t.gallery_rev == rev + 1 and t.gallery_hole == next_hole, "when the leaders move on, the gallery moves with them")
	# the owner playing draws the crowd to the owner
	var mine := sim.visitors.add_group("player", 1, 0.5)
	mine.members[0].kind = "player"
	mine.state = Group.S.PLAY
	mine.hole_i = 0
	t.player_in = true
	t.player_done = false
	check(t.followed_group() == mine, "when the owner is in the field, the crowd follows the owner")
	t.player_in = false
	t.player_done = true
	# when the event is over, everyone goes home
	for gr: Group in t.active.groups:
		gr.state = Group.S.GONE
	t.step(0.1)
	t.step(0.1)
	check(t.active.is_empty() and t.gallery.is_empty() and t.gallery_hole == -1, "when the event is over the gallery goes home")


static func Game_fast(sim: Sim, seconds: float) -> void:
	for i in int(seconds * 60.0):
		sim.step(1.0 / 60.0)


func _test_planner() -> void:
	print("-- where the computer golfers aim")
	# a dogleg: a leg north from the tee, a block of trees on the corner,
	# then a leg east to the green; the pin is straight over the trees
	var sim := _sim("sandbox", 5)
	var c := sim.course
	for i in c.heights.size():
		c.heights[i] = 0.0
	for i in c.terrain.size():
		if c.hot[i] == 0:
			c.terrain[i] = Defs.T.ROUGH
			c.objects[i] = 0
	c.revision += 1
	sim.paint(40, 100, 1, Defs.T.TEE)
	for ty in range(66, 98):
		for tx in range(38, 44):
			c.terrain[ty * c.w + tx] = Defs.T.FAIRWAY
	for tx in range(38, 70):
		for ty in range(60, 67):
			c.terrain[ty * c.w + tx] = Defs.T.FAIRWAY
	sim.paint(70, 63, 2, Defs.T.GREEN)
	for ty in range(68, 96):
		for tx in range(46, 66):
			if (tx + ty) % 2 == 0:
				c.objects[ty * c.w + tx] = Defs.O.OAK
	c.revision += 1
	c.objects_touched()
	var hole := sim.add_hole(c.tile_center(40, 100), c.tile_center(70, 63))
	var pin_line := Vector2(hole.pin.x - hole.tee.x, hole.pin.z - hole.tee.z).angle()
	var on_fairway := 0
	var down_the_leg := 0
	var n := 20
	for k in n:
		var g := sim.visitors.make_golfer("public", 0.55)
		g.persona = {}
		g.begin_hole()
		g.ball.place(c.on_ground(hole.tee.x, hole.tee.z))
		var plan := ShotAI.plan(sim, g, hole)
		var t: Vector3 = plan.target
		var tt := c.terrain_at(t.x, t.z)
		if tt == Defs.T.FAIRWAY or tt == Defs.T.GREEN:
			on_fairway += 1
		if absf(wrapf(float(plan.heading) - pin_line, -PI, PI)) > deg_to_rad(5.0):
			down_the_leg += 1
	print("   on a dogleg, %d of %d average golfers aim at the fairway and %d aim down the leg rather than at the flag" % [on_fairway, n, down_the_leg])
	check(on_fairway >= n * 0.8, "golfers aim for the fairway, not the trees between them and the flag")
	check(down_the_leg >= n * 0.6, "and follow the dogleg rather than aiming at the pin")
	var duffer := sim.visitors.make_golfer("public", 0.1)
	duffer.persona = {}
	duffer.imagination = 0.0
	duffer.begin_hole()
	duffer.ball.place(c.on_ground(hole.tee.x, hole.tee.z))
	var dp := ShotAI.plan(sim, duffer, hole)
	var pro := sim.visitors.make_golfer("pro", 0.95)
	pro.persona = {}
	pro.imagination = 1.0
	pro.begin_hole()
	pro.ball.place(c.on_ground(hole.tee.x, hole.tee.z))
	var pp := ShotAI.plan(sim, pro, hole)
	check(ShotAI._spot_cost(sim, hole, Vector2(c.tile_center(50, 80).x, c.tile_center(50, 80).z), 1.35) > ShotAI._spot_cost(sim, hole, Vector2(c.tile_center(50, 80).x, c.tile_center(50, 80).z), 0.55), "trouble weighs more on a thoughtful golfer than on a duffer")
	check(float(dp.dist) > 0.0 and float(pp.dist) > 0.0, "both still have a shot to play")


func _expert(sim: Sim) -> Golfer:
	var g := Golfer.new()
	g.kind = "lab"
	g.skill = 0.82
	g.power = lerpf(0.74, 1.06, 0.82)
	g.accuracy = 0.82
	g.imagination = 0.9
	g.putting = 0.55
	for cat: Dictionary in sim.db.categories:
		g.brands[cat.id] = sim.db.brands[0]
	g.ball.set_def(sim.db.balls[0])
	g.begin_hole()
	return g


func _trees_between(course: Course, a: Vector2, b: Vector2) -> int:
	var d := b - a
	var n := d.length()
	if n < 1.0:
		return 0
	d = d.normalized()
	var count := 0
	var s := 6.0
	while s < n:
		var q := a + d * s
		var i := course.index_at(q.x, q.y)
		if i >= 0 and Defs.is_tree(course.objects[i]):
			count += 1
		s += Defs.TILE
	return count


func _test_dogleg() -> void:
	print("-- par follows the fairway")
	var sim := _sim("sandbox", 11)
	var c := sim.course
	var sx := 130
	for ty in range(25, 96):
		for tx in range(sx - 2, sx + 3):
			var si := ty * c.w + tx
			c.terrain[si] = Defs.T.FAIRWAY
			c.objects[si] = 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var gi := (30 + dy) * c.w + (sx + dx)
			c.terrain[gi] = Defs.T.GREEN
			c.objects[gi] = 0
	c.terrain[90 * c.w + sx] = Defs.T.TEE
	var tee_t := Vector2i(70, 90)
	var pin_t := Vector2i(42, 60)
	for ty in range(48, 102):
		for tx in range(32, 82):
			var i := ty * c.w + tx
			c.terrain[i] = Defs.T.ROUGH
			c.objects[i] = 0
	for ty in range(60, 91):
		for tx in range(68, 73):
			c.terrain[ty * c.w + tx] = Defs.T.FAIRWAY
	for tx in range(42, 73):
		for ty in range(58, 63):
			c.terrain[ty * c.w + tx] = Defs.T.FAIRWAY
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if dx * dx + dy * dy <= 10:
				c.terrain[(pin_t.y + dy) * c.w + (pin_t.x + dx)] = Defs.T.GREEN
	c.terrain[tee_t.y * c.w + tee_t.x] = Defs.T.TEE
	c.objects[tee_t.y * c.w + tee_t.x] = 0
	c.revision += 1
	var tee := c.tile_center(tee_t.x, tee_t.y)
	var pin := c.tile_center(pin_t.x, pin_t.y)
	var hole := sim.add_hole(tee, pin)
	var chord := hole.straight_length()
	print("   dogleg straight %.0f m (%d yd), along the fairway %.0f m (%d yd), par %d" % [chord, Defs.yards(chord), hole.length, Defs.yards(hole.length), hole.par])
	check(chord <= Hole.PAR_3, "the straight line across a 30 by 28 dogleg is a par 3 distance (%.0f m)" % chord)
	check(hole.par == 4 and hole.length > Hole.PAR_3 and hole.length <= Hole.PAR_4, "a 30 by 28 tile dogleg is a par 4 (%d yd)" % Defs.yards(hole.length))
	var bend := c.tile_center(tee_t.x, pin_t.y)
	var mid := hole.point_along(0.5)
	var across := hole.tee.lerp(hole.pin, 0.5)
	check(Vector2(mid.x, mid.z).distance_to(Vector2(bend.x, bend.z)) < 40.0, "the line of play goes round the corner")
	check(Vector2(mid.x, mid.z).distance_to(Vector2(bend.x, bend.z)) < Vector2(across.x, across.z).distance_to(Vector2(bend.x, bend.z)), "and not across the rough in the corner")
	var straight_hole := sim.add_hole(c.tile_center(sx, 90), c.tile_center(sx, 30))
	check(straight_hole.par == 4 and absf(straight_hole.length - 300.0) < 2.0, "a straight 60-tile hole is still a 300 m par 4 (%.1f m)" % straight_hole.length)
	check(c.set_object(tee_t.x, pin_t.y, Defs.O.FLOODLIGHT), "a floodlight can stand at the corner")
	var share := hole.lit_share(c)
	check(share > 0.12, "night lighting is measured along the fairway, not the chord (%d%% lit)" % int(share * 100.0))
	var spot := hole.point_along(0.35)
	var st := c.tile_of(spot.x, spot.z)
	check(c.set_object(st.x, st.y, Defs.O.BENCH), "a bench can stand on the line of play")
	var benches := sim.stories._objects_along(hole, Defs.O.BENCH, 1)
	check(benches >= 1, "story checks follow the fairway (%d)" % benches)
	var expert := _expert(sim)
	expert.ball.place(c.on_ground(hole.tee.x, hole.tee.z))
	var open_plan := ShotAI.plan(sim, expert, hole)
	var open_target: Vector3 = open_plan.target
	check(open_target.distance_to(hole.pin) < 15.0, "with the corner open an expert goes for the green (%.0f m short)" % open_target.distance_to(hole.pin))
	var oaks := 0
	for ty in range(pin_t.y, tee_t.y + 1):
		for tx in range(pin_t.x, tee_t.x + 1):
			var oi := ty * c.w + tx
			if c.terrain[oi] == Defs.T.ROUGH or c.terrain[oi] == Defs.T.DEEP_ROUGH:
				c.objects[oi] = Defs.O.OAK
				oaks += 1
	c.revision += 1
	c.objects_touched()
	expert.ball.place(c.on_ground(hole.tee.x, hole.tee.z))
	var blocked := ShotAI.plan(sim, expert, hole)
	var blocked_target: Vector3 = blocked.target
	var pin_trees := _trees_between(c, Vector2(hole.tee.x, hole.tee.z), Vector2(hole.pin.x, hole.pin.z))
	var aim_trees := _trees_between(c, Vector2(hole.tee.x, hole.tee.z), Vector2(blocked_target.x, blocked_target.z))
	print("   corner of %d oaks: expert aims %.0f m from the pin, %d trees on the aim and %d on the chord" % [oaks, blocked_target.distance_to(hole.pin), aim_trees, pin_trees])
	check(blocked_target.distance_to(hole.pin) > 40.0 and aim_trees < pin_trees, "an expert does not drive through a tree-filled corner")
	hole.record(4)
	check(int(hole.tally.get("0", 0)) == 1, "a 4 on the par 4 is even")
	var modern := Sim.from_dict(db, JSON.parse_string(JSON.stringify(sim.to_dict())), gear)
	var mh: Hole = modern.course.holes[0]
	check(mh.par == 4 and int(mh.tally.get("0", 0)) == 1, "a save remembers the par the scores were played against")
	var raw: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var course_d: Dictionary = raw.course
	var hs: Array = course_d.holes
	var hd: Dictionary = hs[0]
	hd.erase("par")
	hd["tally"] = {"0": 1}
	hd["plays"] = 1
	var legacy := Sim.from_dict(db, raw, gear)
	var lh: Hole = legacy.course.holes[0]
	check(lh.par == 4 and int(lh.tally.get("-1", 0)) == 1, "an old save remeasures the dogleg and the old even par becomes a birdie")
	var tools := BuildTools.new()
	tools.sim = sim
	tools.mode = "terrain"
	check(tools.hint().contains("1 tile ≈ 5.5 yd."), "the build tools show the scale")
	tools.mode = "hole"
	tools._tee = hole.tee
	tools.hover = hole.pin
	var preview := tools.hint()
	check(preview.contains("Par 4") and preview.contains("yd") and preview.contains("1 tile ≈ 5.5 yd."), "laying out a hole previews par and yardage (%s)" % preview.replace("\n", " "))
	tools.free()
	var tutor := FileAccess.get_file_as_string("res://data/tutorial.json")
	check(tutor.contains("thirty-seven to fifty-five") and tutor.contains("five and a half") and not tutor.contains("eight to twelve"), "the tutorial gives the real scale of a tile")
	for ty in range(pin_t.y - 2, tee_t.y + 3):
		for tx in range(pin_t.x - 2, tee_t.x + 3):
			var fi := ty * c.w + tx
			c.terrain[fi] = Defs.T.FAIRWAY
			c.objects[fi] = 0
	c.revision += 1
	sim.refresh_hole_lines()
	check(hole.par == 3 and hole.length <= Hole.PAR_3, "painting the corner fairway shortens the hole to a par 3 (%d yd)" % Defs.yards(hole.length))
	check(int(hole.tally.get("1", 0)) == 1, "the 4 already recorded becomes a bogey on the new par")


func _test_mood_map() -> void:
	print("-- the mood map")
	var sim := _sim("sandbox", 3)
	var g := sim.visitors.make_golfer("public", 0.5)
	g.persona = {}
	g.mood_good = 1.0
	g.mood_bad = 1.0
	g.pos = sim.course.tile_center(40, 40)
	g.feel(6.0, "What a fairway.", "scenery")
	var tile := sim.course.tile_of(g.pos.x, g.pos.z)
	var i := tile.y * sim.course.w + tile.x
	check(sim.course.mood[i] > 1.0, "a happy thought paints the tile the golfer is standing on (%.1f)" % sim.course.mood[i])
	check(sim.course.mood[i + 3] == 0.0, "and nowhere else")
	var th: Dictionary = g.thoughts[g.thoughts.size() - 1]
	var at: Vector3 = th.pos
	check(at.distance_to(g.pos) < 0.1, "the thought remembers where it happened")
	var before: float = sim.course.mood[i]
	for n in 160:
		sim.grounds.step(0.25)
	check(sim.course.mood[i] < before * 0.55 and sim.course.mood[i] > 0.2, "the colour fades over a couple of days (%.1f to %.1f)" % [before, sim.course.mood[i]])
	var raw: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var back := Sim.from_dict(db, raw, gear)
	check(absf(back.course.mood[i] - sim.course.mood[i]) < 0.01, "a save keeps the mood on the ground")
	var course_d: Dictionary = raw.course
	course_d.erase("mood")
	var old := Sim.from_dict(db, raw, gear)
	check(old.course.mood[i] == 0.0, "an old save without a mood map loads as calm ground")


func _test_bar_and_vending() -> void:
	print("-- the vending machine and the bar")
	var sim := _sim("three_holes", 23)
	var holes := sim.course.holes
	var gr := sim.visitors.add_group("public", 3, 0.5)
	for m in gr.members:
		m.persona = {}
		m.thirst = 0.8
		m.hunger = 0.7
		m.bladder = 0.0
	gr.hole_i = 1
	for m in gr.members:
		m.pos = holes[0].pin
	var mid := holes[0].pin.lerp(holes[1].tee, 0.5)
	var t := sim.course.tile_of(mid.x, mid.z)
	sim.course.guard = false
	for dx in 3:
		sim.course.set_terrain(t.x + dx, t.y, Defs.T.ROUGH)
		sim.course.set_object(t.x + dx, t.y, Defs.O.NONE)
	sim.course.guard = true
	# the machine on its own
	check(sim.place_object(t.x, t.y, Defs.O.VENDING) == 1, "a vending machine goes up")
	check(sim.visitors.plan_stop(gr).get("kind", "") == "vending", "a hungry, thirsty group with nothing better stops at it")
	var money := sim.economy.money
	var mood := gr.members[0].satisfaction
	sim.visitors.serve(gr, "vending")
	var took := sim.economy.money - money
	print("   three golfers at the machine: %s taken, mood %.1f to %.1f" % [Defs.money(took), mood, gr.members[0].satisfaction])
	check(gr.members[0].thirst == 0.0 and gr.members[0].hunger == 0.0, "it answers thirst and hunger both")
	check(is_equal_approx(took, 33.0) and gr.members[0].satisfaction > mood, "at $11 a head, and they feel a little better for it")
	# a snack bar next to it wins
	for m in gr.members:
		m.thirst = 0.8
		m.hunger = 0.7
	check(sim.place_object(t.x + 1, t.y, Defs.O.SNACK_BAR) == 1 and sim.visitors.plan_stop(gr).get("kind", "") == "snack", "with a snack bar beside it, the stand gets the trade")
	# the bar
	check(sim.place_object(t.x + 2, t.y, Defs.O.BAR) == 1, "a bar goes up")
	var drinker := gr.members[0]
	drinker.persona = {"bar": 1.7}
	for m in gr.members:
		m.thirst = 0.8
		m.hunger = 0.0
	check(drinker.need_for("bar") > drinker.need_for("drink"), "a golfer with a taste for it wants the bar more than a soft drink")
	var pro := sim.visitors.add_group("tournament", 1, 0.9)
	pro.members[0].thirst = 0.9
	check(pro.members[0].need_for("bar") == 0.0, "a pro in a tournament never does")
	var think0 := drinker.think_mult()
	var spread0 := drinker.spread()
	var walk0 := drinker.walk_speed()
	money = sim.economy.money
	mood = drinker.satisfaction
	var heard := [0]      # a list, so the lambda can count into it
	sim.sound.connect(func(id: String, _pos: Vector3, _power: float) -> void:
		if id == "bottle":
			heard[0] += 1)
	sim.visitors.serve(gr, "bar")
	print("   a round of drinks: %s taken, %d bottles opened, mood %.1f to %.1f, drunk %.2f, thinks %.2fx, spread %.2fx" % [
		Defs.money(sim.economy.money - money), heard[0], mood, drinker.satisfaction, drinker.drunk, drinker.think_mult(), drinker.spread() / spread0])
	check(heard[0] == 3 and is_equal_approx(sim.economy.money - money, 42.0), "every drinker pops a bottle and pays $14")
	check(drinker.drunk > 0.3 and drinker.satisfaction > mood + 3.0, "and is drunk and much happier")
	check(drinker.think_mult() > think0 and drinker.spread() > spread0 * 1.2 and drinker.walk_speed() < walk0, "a drinker takes longer over a shot, sprays it and dawdles")
	# the good gets better, the little annoyances slide off, the big ones land harder
	var sober := sim.visitors.make_golfer("public", 0.5)
	sober.persona = {}
	var tipsy := sim.visitors.make_golfer("public", 0.5)
	tipsy.persona = {}
	tipsy.drunk = 1.0
	sober.satisfaction = 50.0
	tipsy.satisfaction = 50.0
	sober.feel(2.0)
	tipsy.feel(2.0)
	check(tipsy.satisfaction > sober.satisfaction, "a drinker enjoys the good things more")
	sober.feel(-0.5)
	tipsy.feel(-0.5)
	check(tipsy.satisfaction > sober.satisfaction, "and shrugs off a small gripe")
	var s0 := sober.satisfaction
	var t0 := tipsy.satisfaction
	sober.feel(-10.0)
	tipsy.feel(-10.0)
	check(t0 - tipsy.satisfaction > s0 - sober.satisfaction, "but a real blow hits them harder")
	# it wears off
	for i in 60 * 240:
		sim.visitors._tick_golfer(drinker, 1.0 / 60.0)
	check(drinker.drunk < 0.05, "and four minutes later it has worn off (drunk %.2f)" % drinker.drunk)
	var am := sim.visitors.amenity_counts()
	check(int(am.vending) == 1 and int(am.bar) == 1, "the club counts its machine and its bar")
	check(db.sounds.sounds.has("bottle") and FileAccess.file_exists("res://assets/sounds/bottle_1.ogg"), "the bottle has its sound")
	check(Defs.O_BUILDING[Defs.O.BAR] and not Defs.O_BUILDING[Defs.O.VENDING] and Defs.O_LIGHT[Defs.O.BAR] > 0.0, "the bar is a lit building; the machine is not")


## How far behind the tee marker a golfer stands, along the hole's line.
func _behind_tee(hole: Hole, g: Golfer) -> float:
	var ax := Group.tee_axes(hole)
	return (g.pos - hole.tee).dot(ax[0])


## The closest any two golfers from different parties stand.
func _closest_pair(parties: Array) -> float:
	var best := 1e9
	for a in parties.size():
		for b in parties.size():
			if a >= b:
				continue
			for p in (parties[a] as Group).members:
				for q in (parties[b] as Group).members:
					best = minf(best, Vector2(p.pos.x - q.pos.x, p.pos.z - q.pos.z).length())
	return best


func _test_tee_line() -> void:
	print("-- the line at the tee, shooting into people, and waiting")
	var sim := _sim("three_holes", 21)
	sim.open = false
	sim.events.timer = 99999.0
	var hole := sim.course.holes[0]
	# three parties arrive one after another
	var a := sim.visitors.add_group("public", 3, 0.5)
	_run(sim, 6.0)
	var b := sim.visitors.add_group("public", 2, 0.5)
	_run(sim, 6.0)
	var c := sim.visitors.add_group("public", 4, 0.5)
	var guard := 0
	var held := false
	while guard < 60 * 240 and not (a.state == Group.S.PLAY and b.state == Group.S.QUEUE and c.state == Group.S.QUEUE):
		sim.step(1.0 / 60.0)
		guard += 1
		# the first party's opening drive takes an age, so the line forms behind them
		if not held and a.state == Group.S.PLAY and a.turn != null and a.turn.phase == Golfer.P.AIM:
			a.turn.timer = 90.0
			held = true
	# the first party is on the tee; nobody from it stands on the box but the one hitting
	check(a.state == Group.S.PLAY and hole.teeing_group == a, "the first party to arrive takes the tee")
	var on_box := 0
	for m in a.members:
		if m != a.turn and Vector2(m.pos.x - hole.tee.x, m.pos.z - hole.tee.z).length() < 2.0:
			on_box += 1
	check(on_box == 0, "its partners stand clear of the tee box while one of them hits")
	var ba := 0.0
	for m in b.members:
		ba += _behind_tee(hole, m) / b.members.size()
	var ca := 0.0
	for m in c.members:
		ca += _behind_tee(hole, m) / c.members.size()
	var gap := _closest_pair([a, b, c])
	print("   party two waits %.1f m behind the tee, party three %.1f m; the closest two golfers from different parties stand %.2f m apart" % [ba, ca, gap])
	check(b.state == Group.S.QUEUE and ba > 6.0 and ba < 11.0, "the second party waits in line well back of the tee")
	check(c.state == Group.S.QUEUE and ca > ba + 3.0, "and the third party waits behind the second")
	check(gap >= 0.9, "no two golfers from different parties stand on each other")
	check(hole.line.size() == 2 and hole.line[0] == b and hole.line[1] == c, "the hole keeps the line in order of arrival")
	# the first party tees off and the line moves up
	if a.turn != null:
		a.turn.timer = 0.1
	guard = 0
	while guard < 60 * 240 and b.state != Group.S.PLAY:
		sim.step(1.0 / 60.0)
		guard += 1
	check(a.tee_done and b.state == Group.S.PLAY and hole.teeing_group == b, "when the first party has teed off, the second takes the tee")
	guard = 0
	while guard < 60 * 60 and not (b.turn != null and b.turn.phase == Golfer.P.AIM):
		sim.step(1.0 / 60.0)
		guard += 1
	if b.turn != null:
		b.turn.timer = 90.0
	_run(sim, 10.0)
	var ca2 := 0.0
	for m in c.members:
		ca2 += _behind_tee(hole, m) / c.members.size()
	print("   after the shuffle party three waits %.1f m behind the tee" % ca2)
	check(c.state == Group.S.QUEUE and ca2 < ca - 3.0 and ca2 > 6.0, "and the third party moves up to the front of the line")

	# nobody shoots into people
	var s2 := _sim("three_holes", 22)
	s2.open = false
	s2.events.timer = 99999.0
	var h2 := s2.course.holes[0]
	var x := s2.visitors.add_group("public", 1, 0.5)
	guard = 0
	while guard < 60 * 240 and not (x.state == Group.S.PLAY and x.turn != null and x.turn.phase == Golfer.P.AIM):
		s2.step(1.0 / 60.0)
		guard += 1
	check(x.state == Group.S.PLAY and x.turn != null and x.turn.phase == Golfer.P.AIM, "a lone golfer gets to the tee and lines up a drive")
	var hitter := x.turn
	var heading: float = hitter.plan.heading
	var dist: float = hitter.plan.dist
	# a party lying in the fairway where the drive would land
	var y := s2.visitors.add_group("public", 2, 0.5)
	y.hole_i = 0
	y.state = Group.S.PLAY
	var landing := hitter.pos + Vector3(cos(heading), 0.0, sin(heading)) * (dist * 0.85)
	for i in y.members.size():
		var m := y.members[i]
		m.pos = s2.course.on_ground(landing.x + i * 1.5, landing.z)
		m.ball.place(m.pos)
		m.hit_t = 1000.0          # flat out and going nowhere
	_run(s2, 100.0)
	check(not hitter.teed and not x.forced, "with people where the ball would land, a sober golfer holds the shot for a hundred seconds and more")
	check(hitter.satisfaction < hitter.sat_at_tee, "and the wait costs them some cheer")
	var behind := hitter.pos - Vector3(cos(heading), 0.0, sin(heading)) * 30.0
	for m in y.members:
		m.hit_t = 0.0
		m.pos = s2.course.on_ground(behind.x, behind.z)
		m.ball.place(m.pos)
	_run(s2, 6.0)
	check(hitter.teed, "once the fairway clears, the drive goes")
	# a drunk does not look
	var s3 := _sim("three_holes", 22)
	s3.open = false
	s3.events.timer = 99999.0
	var x3 := s3.visitors.add_group("public", 1, 0.5)
	x3.members[0].drunk = 1.0
	guard = 0
	while guard < 60 * 240 and not (x3.state == Group.S.PLAY and x3.turn != null and x3.turn.phase == Golfer.P.AIM):
		s3.step(1.0 / 60.0)
		guard += 1
	var h3 := x3.turn
	var y3 := s3.visitors.add_group("public", 2, 0.5)
	y3.hole_i = 0
	y3.state = Group.S.PLAY
	var land3 := h3.pos + Vector3(cos(float(h3.plan.heading)), 0.0, sin(float(h3.plan.heading))) * (float(h3.plan.dist) * 0.85)
	for i in y3.members.size():
		var m := y3.members[i]
		m.pos = s3.course.on_ground(land3.x + i * 1.5, land3.z)
		m.ball.place(m.pos)
		m.hit_t = 1000.0
	_run(s3, 8.0)
	check(h3.teed, "a drunk golfer swings away regardless")

	# waiting wears on a golfer only after the first few seconds
	var g := s2.visitors.make_golfer("public", 0.5)
	g.persona = {}
	g.patience = 0.5
	g.satisfaction = 60.0
	for i in 600:
		s2.visitors.wait_on(g, 1.0 / 60.0, "tee", 5.0, false)
	check(is_equal_approx(g.satisfaction, 60.0), "the first few seconds of a wait are free")
	for i in 600:
		s2.visitors.wait_on(g, 1.0 / 60.0, "tee", 25.0 + i / 60.0, false)
	var lost := 60.0 - g.satisfaction
	print("   ten seconds of waiting past the grace cost %.2f satisfaction" % lost)
	check(lost > 0.15 and lost < 0.4, "after that, every second of waiting costs a little")
	check(g.wait_said and g.thoughts.size() > 0 and str(g.thoughts[-1].text).begins_with("Waiting"), "and at half a minute they say so")
	var seated := s2.visitors.make_golfer("public", 0.5)
	seated.persona = {}
	seated.patience = 0.5
	seated.satisfaction = 60.0
	for i in 600:
		s2.visitors.wait_on(seated, 1.0 / 60.0, "tee", 25.0 + i / 60.0, true)
	check(60.0 - seated.satisfaction < lost * 0.6, "a bench makes the wait easier")
