class_name PlayMode
extends Node
## Play your own course. Aim, pick a club, then the three-click swing: one
## press starts the marker up the bar, a second sets the power where you
## stop it, and it comes straight back down for a third press on the line.
## Early hooks, late slices, and there are no second goes. A controller can
## swing with the right stick instead: pull back, push forward. The ball
## flies with the same physics the computer golfers use, and yes, you can
## hit them.

signal started()
signal ended()
signal changed()
signal hole_done(index: int, score: int, par: int)
signal round_done(card: Array, pars: Array)

enum S { OFF, WALK, AIM, POWER, ACCURACY, SWING, FLIGHT, PAUSE }

const MAX_PUTT := 30.0     # metres a full-power putt rolls on a flat dry green
const METER_RATE := 1.0    # bar units a second: one second from rest to full power, and one back
const OVER := 1.12         # the bar's end; past 1.0 is an overswing
const LATE := -0.14        # the marker gets this far past the line before the swing goes anyway
const ZONE := 0.17         # bar units early or late that make a full hook or slice
const GOOD := 0.06         # within this of the line the shot flies all but straight
const PERFECT := 0.02      # bar units either side of the line that count as flush
const GOOD_MISS := 0.15    # the most a shot inside the good band can bend
const STICK_PULL := 0.55   # how far back the stick must go to start a swing
## Shot shapes. `need` is the golfer skill effect that unlocks one.
const SHAPES := [
	{"id": "straight", "name": "Straight", "need": "", "mods": {}, "power": 1.0},
	{"id": "draw", "name": "Draw (curves left)", "need": "shape", "mods": {"side": -0.04}, "power": 1.03},
	{"id": "fade", "name": "Fade (curves right)", "need": "shape", "mods": {"side": 0.04, "spin": 0.1}, "power": 0.98},
	{"id": "spin", "name": "High backspin", "need": "backspin", "mods": {"loft": 1.14, "spin": 0.4, "lift": 1.1}, "power": 0.95},
	{"id": "punch", "name": "Low punch", "need": "", "mods": {"loft": 0.55, "lift": 0.55, "wind": 0.55}, "power": 0.9},
	{"id": "flop", "name": "Flop (high and soft)", "need": "flop", "mods": {"loft": 1.4, "lift": 1.15, "spin": 0.3}, "power": 0.72},
]

var sim: Sim
var rig: CameraRig
var state: int = S.OFF
var g: Golfer
var group: Group
var hole_i := 0
var last_hole := 0
var club_i := 0
var aim := 0.0
var power := 0.0
var meter := 0.0
var meter_dir := 1.0
var needle := 0.0               # how the last swing was timed: -1 early (hook) .. 1 late (slice)
var needle_dir := 1.0
var target_power := -1.0
var swing_word := ""            # what the third press earned: "Flush", "A touch late"...
var zone := ZONE                # this shot's margin, in bar units, before a full hook or slice
var good := GOOD                # the band that still flies straight
var perfect := PERFECT          # and its flush window
var stick_phase := 0            # analog swing: 0 not swinging, 1 pulling back, 2 coming forward
var _stick_t := 0.0             # seconds since the stick left the back position
var _stick_x := 0.0             # where the stick sat sideways during the backswing
var _late := false              # the third press never came
var putting := false
var lie := 0
var lie_read := {}              # how the ball is sitting: see Lie.read
var out_of_bounds := false      # the shot as aimed finishes off the property
var pin_dist := 0.0
var max_dist := 0.0
var card: Array[int] = []
var pars: Array[int] = []
var message := ""
var shape_i := 0
var pad_turn := 0.0             # a controller's aim, -1 (left) to 1 (right); see Gamepad
var tournament := false         # this round counts in the tournament being held
var match_play := {}            # a money match against a visiting pro
var summary := ""               # one line for the end-of-round dialog
var _timer := 0.0
var _walk_speed := 16.0
var _saved_view := {}
var _preview_dirty := true
var _preview_shown := false
var _preview_t := 0.0
var _landing := Vector3.ZERO
var _path: Array[Vector3] = []
var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _mat := StandardMaterial3D.new()
var _ring := MeshInstance3D.new()
var _calm_rest := Vector3.ZERO  # where the shot just struck would finish in still air
var _cam_cut := false           # the broadcast camera has cut to the green for this shot
var _cam_pitch := 0.0           # the pitch the chase camera is easing toward
var _furthest := 0.0            # how far past its pitch mark the ball got before spin pulled it back
var _shot_clean := false        # nothing got in the way, so the wind report means something


func _ready() -> void:
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = true
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	var torus := TorusMesh.new()
	torus.inner_radius = 1.6
	torus.outer_radius = 2.0
	torus.rings = 28
	torus.ring_segments = 5
	_ring.mesh = torus
	_ring.material_override = WorldView.glow(Color(1.0, 0.85, 0.2))
	_ring.visible = false
	add_child(_ring)


func active() -> bool:
	return state != S.OFF


func hole() -> Hole:
	return sim.course.holes[hole_i]


func club() -> Dictionary:
	return sim.db.clubs[club_i]


func shape() -> Dictionary:
	return SHAPES[shape_i]


func shape_available(i: int) -> bool:
	var need := str(SHAPES[i].need)
	return need == "" or sim.skills.bonus(need) > 0.0


## Step through the shot shapes this golfer has learned.
func cycle_shape(dir: int) -> void:
	if state != S.AIM or putting:
		return
	for k in SHAPES.size():
		shape_i = wrapi(shape_i + dir, 0, SHAPES.size())
		if shape_available(shape_i):
			break
	_refresh_numbers()
	_preview_t = 0.0
	changed.emit()


## A money match: most holes won takes the stake.
func start_match(s: Sim, camera: CameraRig, offer: Dictionary) -> bool:
	if not start(s, camera, 0, int(offer.holes)):
		return false
	var rival := Golfer.new()
	s.tag_eddy(rival)
	rival.kind = "lab"
	rival.name = str(offer.rival)
	rival.roll_stats(float(offer.skill), s.rng, s.members.progress)
	for cat: Dictionary in s.db.categories:
		rival.brands[cat.id] = s.db.brands[4]
	rival.ball.set_def(s.db.balls[0])
	rival.ball.lava = s.is_lava()
	match_play = {"rival": str(offer.rival), "stake": float(offer.stake), "golfer": rival, "won": 0, "lost": 0}
	message = "Match against %s for %s." % [str(offer.rival), Defs.money(float(offer.stake))]
	return true


func start(s: Sim, camera: CameraRig, first: int = 0, count: int = -1, in_tournament: bool = false) -> bool:
	if s.course.holes.is_empty() or active():
		return false
	sim = s
	rig = camera
	tournament = in_tournament
	match_play = {}
	summary = ""
	shape_i = 0
	sim.player.refresh()
	g = sim.player.golfer
	g.scores.clear()
	g.pars.clear()
	g.satisfaction = 80.0
	g.hit_t = 0.0
	card.clear()
	pars.clear()
	hole_i = clampi(first, 0, sim.course.holes.size() - 1)
	last_hole = sim.course.holes.size() - 1 if count < 0 else mini(hole_i + count - 1, sim.course.holes.size() - 1)
	group = Group.new()
	group.kind = "player"
	group.state = Group.S.PLAY
	group.members.append(g)
	g.group = group
	sim.visitors.add_existing(g)
	Game.speed = 1
	Game.paused = false
	_saved_view = {"yaw": rig.yaw, "dist": rig.target_dist, "focus": rig.focus}
	rig.locked = true
	sim.career.begin_round(hole_i == 0 and last_hole == sim.course.holes.size() - 1)
	sim.playing_round = true
	_begin_hole()
	started.emit()
	return true


func stop() -> void:
	if not active():
		return
	if sim != null:
		sim.playing_round = false
	# walking off mid-round forfeits whatever was at stake
	if not match_play.is_empty():
		_settle_match(true)
	if tournament:
		tournament = false
		sim.tourney.player_finished([], [])
	for h in sim.course.holes:
		h.groups.erase(group)
	sim.visitors.remove_existing(g)
	state = S.OFF
	rig.locked = false
	rig.pitch_override = -1.0
	rig.v_shift = 0.0
	rig.follow = null
	if not _saved_view.is_empty():
		rig.yaw = _saved_view.yaw
		rig.target_dist = _saved_view.dist
		rig.focus = _saved_view.focus
	_mesh.clear_surfaces()
	_ring.visible = false
	ended.emit()


func _begin_hole() -> void:
	var h := hole()
	group.hole_i = hole_i
	if not h.groups.has(group):
		h.groups.append(group)
	g.begin_hole()
	sim.career.begin_hole(h)
	g.ball.place(sim.course.on_ground(h.tee.x, h.tee.z))
	g.pos = Group.stance(g, h)
	g.pos.y = sim.course.height_at(g.pos.x, g.pos.z)
	g.prev = g.pos
	message = "Hole %d  ·  Par %d  ·  %d yards" % [hole_i + 1, h.par, Defs.yards(h.length)]
	_setup_shot()


func _setup_shot() -> void:
	var h := hole()
	var b := g.ball
	lie = maxi(sim.course.terrain_at(b.pos.x, b.pos.z), 0)
	var to := Vector2(h.pin.x - b.pos.x, h.pin.z - b.pos.z)
	pin_dist = to.length()
	aim = to.angle()
	lie_read = Lie.read(sim, g, aim)
	if Defs.is_green(lie):
		club_i = sim.gear.putter_i
	else:
		club_i = int(sim.gear.pick(g, pin_dist, lie, sim.course)[0])
	putting = club_i == sim.gear.putter_i
	power = 0.0
	meter = 0.0
	state = S.WALK
	# never more than a second or so of jogging between shots
	_walk_speed = maxf(16.0, g.pos.distance_to(b.pos) / 1.2)
	_refresh_numbers()
	_frame_camera()
	changed.emit()


func _refresh_numbers() -> void:
	var h := hole()
	if putting:
		max_dist = MAX_PUTT
		var v := ShotAI.putt_speed(sim, g, g.ball.pos, h.pin, 0.3)
		target_power = clampf(v / _putt_full_speed(), 0.0, 1.0)
	else:
		var full := _full_speed()
		max_dist = sim.gear.total_at(club_i, full)
		if pin_dist <= max_dist:
			target_power = clampf(sim.gear.speed_for(club_i, pin_dist) / full, 0.0, 1.0)
		else:
			target_power = -1.0
	_preview_t = 0.0


## Ball speed of a flat-out swing from here: the club, the golfer, the
## shot shape and the lie.
func _full_speed() -> float:
	return sim.gear.full_speed(g, club_i) * g.lie_power(lie, sim.course) * float(shape().power) * float(lie_read.get("power", 1.0))


## The lie in a few words: "Rough, sitting down".
func lie_name() -> String:
	return str(lie_read.get("name", sim.terrain_name(lie)))


## The wind as the golfer feels it over this shot.
func wind_text() -> String:
	var w := sim.weather
	var mph := w.wind_mph()
	if mph < 2:
		return "No wind"
	var rel := wrapf(w.wind_dir - aim, -PI, PI)      # 0 is straight behind the shot
	var along := cos(rel)
	var across := sin(rel)                           # positive pushes the ball right
	var words: Array[String] = []
	if along > 0.38:
		words.append("behind you")
	elif along < -0.38:
		words.append("in your face")
	if across > 0.38:
		words.append("blowing left to right")
	elif across < -0.38:
		words.append("blowing right to left")
	return "Wind %d mph, %s" % [mph, " and ".join(PackedStringArray(words))]


## What the golfer should know before swinging: the wind, and what the lie
## will do to the shot.
func advice() -> String:
	if not active():
		return ""
	var parts: Array[String] = []
	if not putting:
		parts.append(wind_text())
		var lt := Lie.text(lie_read)
		if lt != "":
			parts.append(lt)
		if out_of_bounds:
			parts.append("That line finishes out of bounds.")
	var slope := green_read()
	if slope != "":
		parts.append(slope)
	return "  ·  ".join(PackedStringArray(parts))


## Slope under the ball and along the line to the hole. A reading, not an aim.
func green_read() -> String:
	if g == null or not Defs.is_green(lie):
		return ""
	var b := g.ball.pos
	var h := hole()
	var toward := Vector2(h.pin.x - b.x, h.pin.z - b.z)
	var here := Slope.read(sim.course, b.x, b.z)
	var line := Slope.along(sim.course, b, h.pin)
	return "Under the ball, %s. Along the line, %s." % [Slope.words(here, toward), Slope.words(line, toward)]


func _putt_full_speed() -> float:
	var ground: int = lie if Defs.is_green(lie) else Defs.T.GREEN
	return sqrt(2.0 * sim.course.roll_decel(ground) * 1.32 * MAX_PUTT)


func _frame_camera() -> void:
	var b := g.ball
	var look := clampf(minf(pin_dist, max_dist) * 0.45, 4.0, 110.0)
	rig.follow = null
	rig.focus = b.pos + Vector3(cos(aim), 0.0, sin(aim)) * look
	rig.yaw = aim + PI
	rig.target_dist = clampf(look * 2.3 + 10.0, 16.0, 260.0)
	rig.pitch_override = deg_to_rad(38.0 if putting else 24.0)
	rig.v_shift = 0.13


func change_club(step: int) -> void:
	if state != S.AIM:
		return
	# The putter is always available on the green and from just off it.
	var first := 0 if lie == Defs.T.TEE else 1
	var last := sim.gear.n_clubs - 2
	if Defs.is_green(lie) or pin_dist < 35.0:
		last = sim.gear.putter_i
	club_i = clampi(club_i + step, first, last)
	putting = club_i == sim.gear.putter_i
	_refresh_numbers()
	_frame_camera()
	changed.emit()


func cycle_ball() -> void:
	if state != S.AIM:
		return
	var ids: Array[String] = []
	for def: Dictionary in sim.db.balls:
		if sim.player.ball_count(str(def.id)) > 0:
			ids.append(str(def.id))
	var i := ids.find(sim.player.ball_id)
	sim.player.use_ball(ids[(i + 1) % ids.size()])
	_refresh_numbers()
	changed.emit()


## Stop the marker before power is set and go back to aiming. A
## controller's back button. Once power is set the swing is on.
func cancel_swing() -> bool:
	if state != S.POWER:
		return false
	state = S.AIM
	meter = 0.0
	stick_phase = 0
	changed.emit()
	return true


## The one button, three times: start the marker, set power, stop it on the line.
func press() -> void:
	match state:
		S.AIM:
			SoundDesk.ui("click")
			_begin_swing()
		S.POWER:
			SoundDesk.ui("click")
			_set_power(meter)
		S.ACCURACY:
			_commit(_timing(meter))
	changed.emit()


func _begin_swing() -> void:
	state = S.POWER
	meter = 0.0
	meter_dir = 1.0
	stick_phase = 0
	_late = false
	swing_word = ""
	_set_margins()


## The margins for this shot: a bad lie, a long club and an overswing all
## shrink them; a golfer's Ball Striking widens the flush window.
func _set_margins() -> void:
	var ease := 1.0
	if not putting:
		match str(club().cat):
			"woods":
				ease = 0.85
			"wedges":
				ease = 1.1
		ease /= 0.6 + 0.4 * Lie.terrain_spread(lie) * float(lie_read.get("spread", 1.0))
	else:
		ease = 1.15
	if power > 1.0:
		ease *= 1.0 - (power - 1.0) / (OVER - 1.0) * 0.45
	ease *= sim.diff("swing")
	zone = ZONE * ease
	good = GOOD * ease
	perfect = PERFECT * (1.0 + sim.skills.bonus("sweet") * 12.0) * ease


func _set_power(at: float) -> void:
	power = clampf(at, 0.04, OVER)
	_set_margins()
	state = S.ACCURACY
	meter = power
	meter_dir = -1.0


## Turn where the marker was stopped (bar units above the line) into the
## swing's timing: 0 flush, -1 a full hook, 1 a full slice.
## Flush inside the perfect window; a shade of bend across the good band;
## only beyond it does the shot start to hook or slice in earnest.
func _timing(at: float) -> float:
	var e := -at          # early is negative, late positive
	var a := absf(e)
	if a <= perfect:
		return 0.0
	if a <= good:
		return signf(e) * GOOD_MISS * (a - perfect) / maxf(good - perfect, 0.001)
	return signf(e) * (GOOD_MISS + (1.0 - GOOD_MISS) * clampf((a - good) / maxf(zone - good, 0.001), 0.0, 1.0))


func _commit(timing: float) -> void:
	needle = timing
	if _late:
		swing_word = "Way late. Hold on to your hat."
	elif timing == 0.0:
		swing_word = "Flush."
	elif absf(timing) <= GOOD_MISS + 0.001:
		swing_word = "Good. A shade %s." % ("early" if timing < 0.0 else "late")
	elif absf(timing) < 0.5:
		swing_word = "A touch %s." % ("early" if timing < 0.0 else "late")
	elif absf(timing) < 1.0:
		swing_word = "Early: it will hook." if timing < 0.0 else "Late: it will slice."
	else:
		swing_word = "Snapped it shut. Duck hook." if timing < 0.0 else "Wide open. Big slice."
	message = swing_word
	state = S.SWING
	_timer = 0.6
	g.swing_t = 0.0
	g.plan = {"putt": putting, "heading": aim, "dist": pin_dist, "ci": club_i}
	changed.emit()


## How fast the marker travels: faster coming down the harder the swing,
## slower for a golfer with Tempo, a shade slower for a putt.
func _meter_rate() -> float:
	var r := METER_RATE / (1.0 + sim.skills.bonus("tempo"))
	if putting:
		r *= 0.85
	return r


## Swing with a stick (see Gamepad): pull it back to start the backswing,
## which gets longer the longer you hold it, then push it forward to hit.
## Push straight for a straight shot; a push off to one side bends it.
## Letting the stick settle without pushing forward calls the swing off.
func stick(x: float, y: float, delta: float) -> void:
	match state:
		S.AIM:
			if y > STICK_PULL and stick_phase == 0:
				SoundDesk.ui("click")
				_begin_swing()
				stick_phase = 1
				_stick_x = x
		S.POWER:
			if stick_phase != 1:
				return
			if y > STICK_PULL * 0.6:
				_stick_x = lerpf(_stick_x, x, 0.2)
			else:
				# the stick is on its way forward: the backswing is done
				_set_power(meter)
				stick_phase = 2
				_stick_t = 0.0
		S.ACCURACY:
			if stick_phase != 2:
				return
			_stick_t += delta
			if y < -STICK_PULL:
				# the hit: sideways drift of the push is the error, and a
				# slow change of direction loses power
				var e := clampf((x - _stick_x) * 1.2, -1.0, 1.0)
				if _stick_t > 0.45:
					power *= 0.85
					e = clampf(e + 0.25, -1.0, 1.0)
				meter = -e * zone
				_commit(e)
			elif _stick_t > 0.6 and absf(y) < 0.25:
				# settled back to the middle: never mind
				state = S.AIM
				stick_phase = 0
				meter = 0.0
				changed.emit()


func _process(delta: float) -> void:
	if state == S.OFF:
		return
	if sim.course.holes.is_empty() or hole_i >= sim.course.holes.size():
		stop()
		return
	var h := hole()
	match state:
		S.WALK:
			g.prev = g.pos
			if g.walk_to(Group.stance(g, h), delta, sim.course, _walk_speed):
				state = S.AIM
				g.facing = aim
				changed.emit()
		S.AIM:
			var turn := 0.0
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
				turn -= 1.0
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
				turn += 1.0
			turn = clampf(turn + pad_turn, -1.0, 1.0)
			if turn != 0.0:
				var rate := 0.12 if Input.is_key_pressed(KEY_SHIFT) else (0.35 if putting else 0.6)
				aim = wrapf(aim + turn * rate * delta, -PI, PI)
				_preview_t = 0.0
				_frame_camera()
			g.facing = aim
			g.plan = {"putt": putting, "heading": aim, "dist": pin_dist, "ci": club_i}
			g.phase = Golfer.P.AIM
		S.POWER:
			# up the bar; at the very top the swing goes anyway, overswung
			meter += delta * _meter_rate()
			if meter >= OVER:
				_set_power(OVER)
				if stick_phase == 1:
					stick_phase = 2
					_stick_t = 0.0
		S.ACCURACY:
			# straight back down to the line, and past it if nobody presses
			if stick_phase == 0:
				meter -= delta * _meter_rate()
				if meter <= LATE:
					_late = true
					_commit(1.0)
		S.SWING:
			_timer -= delta
			if _timer <= 0.0:
				_strike()
		S.FLIGHT:
			var b := g.ball
			if b.moving():
				_broadcast(b, delta)
				if b.bounces > 0:
					_furthest = maxf(_furthest, Vector2(b.pos.x - b.start.x, b.pos.z - b.start.z).length())
			else:
				_resolve()
		S.PAUSE:
			_timer -= delta
			if _timer <= 0.0:
				_next()
	_preview_t -= delta
	if state == S.AIM and _preview_t <= 0.0:
		_preview_t = 0.12
		_update_preview()
		_preview_dirty = true
	var want := state == S.AIM or state == S.POWER or state == S.ACCURACY
	if want != _preview_shown or (want and _preview_dirty):
		_preview_shown = want
		_preview_dirty = false
		_draw_preview()
	if want:
		_ring.scale = Vector3.ONE * clampf(rig.dist / 90.0, 0.6, 3.0)


## The broadcast camera. It flies along behind a long shot, pulling in as
## the ball climbs, and once the ball is down near the green it cuts to the
## reverse angle: from the ball toward the flag, the way television shows
## an approach. A putt keeps the putting view.
func _broadcast(b: Ball, delta: float) -> void:
	if putting:
		rig.focus = rig.focus.lerp(b.pos, 1.0 - exp(-delta * 6.0))
		return
	var h := hole()
	var to_pin := Vector2(h.pin.x - b.pos.x, h.pin.z - b.pos.z)
	var pin_d := to_pin.length()
	if b.state == Ball.S.FLIGHT and not _cam_cut:
		# chase: follow the ball, drawn in as it rises, from a little higher
		var k := 1.0 - exp(-delta * 5.0)
		rig.focus = rig.focus.lerp(b.pos, k)
		var up := b.pos.y - sim.course.height_at(b.pos.x, b.pos.z)
		var want_d := clampf(26.0 + up * 1.6 + pin_dist * 0.08, 30.0, 110.0)
		rig.target_dist = lerpf(rig.target_dist, want_d, k)
		_cam_pitch = lerpf(_cam_pitch if _cam_pitch > 0.0 else rig.pitch_override, deg_to_rad(20.0 + clampf(up, 0.0, 30.0) * 0.4), k)
		rig.pitch_override = _cam_pitch
		# keep a high ball in the frame
		rig.v_shift = lerpf(rig.v_shift, clampf(up / maxf(rig.dist, 1.0) * 0.6, 0.08, 0.3), k)
		return
	if not _cam_cut:
		_cam_cut = true
		if pin_d < 60.0 and pin_d > 2.0:
			# reverse angle on the green: look from the ball toward the flag
			rig.yaw = to_pin.angle() + PI
			rig.target_dist = clampf(18.0 + pin_d * 0.5, 22.0, 50.0)
			rig.pitch_override = deg_to_rad(26.0)
			rig.v_shift = 0.08
	var k2 := 1.0 - exp(-delta * 4.0)
	if pin_d < 60.0:
		rig.focus = rig.focus.lerp(b.pos.lerp(h.pin, 0.4), k2)
	else:
		rig.focus = rig.focus.lerp(b.pos, k2)


func _strike() -> void:
	var b := g.ball
	var c := club()
	var brand := g.brand_of(str(c.cat))
	var bs: float = brand.get("spread", 1.0)
	# The timing decides how far off line the shot starts and how much it curves.
	var miss := needle
	sim.career.shot_struck({"putt": putting, "lie": lie, "to_pin": pin_dist, "from": b.pos, "shape": str(shape().id), "stroke": g.strokes + 1})
	var swing := minf(power, 1.0) + maxf(power - 1.0, 0.0) * 0.5     # an overswing buys a little
	if putting:
		var hs := 0.07 / (float(brand.get("putt", 1.0)) * (1.0 + sim.skills.bonus("putt")))
		b.shot_wind = 1.0
		b.launch(_putt_full_speed() * swing, aim + miss * hs, 0.0, 0.0, 0.0, 0.0)
	else:
		lie_read = Lie.read(sim, g, aim)
		var mods: Dictionary = shape().mods
		var full := _full_speed()
		var sig := g.spread() * bs * Lie.terrain_spread(lie) * float(lie_read.spread) * 1.2
		if pin_dist < 150.0 / Defs.YARDS:
			# the Approach attribute tightens the scoring shots
			sig *= maxf(0.35, 1.0 + sim.skills.bonus("approach"))
		var speed := full * swing
		var loft := maxf(deg_to_rad(float(c.loft)) * float(mods.get("loft", 1.0)) + float(lie_read.loft), 0.03)
		var forgive: float = brand.get("forgive", 1.0)
		g.mishit = false
		var clean_lie := Defs.is_fairway(lie) or lie == Defs.T.TEE
		# a bad lie turns a poor swing into a poor strike more often, and so
		# do an overswing and a swing that was never stopped
		var odds := 0.35 * forgive * float(lie_read.mishit) + maxf(power - 1.0, 0.0) * 2.5 + (0.3 if _late else 0.0)
		if absf(miss) > 0.9 and sim.rng.randf() < minf(odds, 0.9) and not (clean_lie and sim.skills.bonus("pure") > 0.0):
			g.mishit = true
			speed *= 0.5
			loft *= 0.5
			message = "Chunked it."
			if lie == Defs.T.BUNKER:
				message = "Took far too much sand."
			elif lie == Defs.T.ROUGH or lie == Defs.T.DEEP_ROUGH:
				message = "The grass grabbed the club."
		b.shot_wind = float(brand.get("wind", 1.0)) * float(mods.get("wind", 1.0))
		b.dodge = sim.skills.bonus("luck")
		b.air_seed = g.air_phase(sim.time)
		b.struck_from = lie
		var from := b.pos
		var lift_c := float(c.lift) * float(mods.get("lift", 1.0)) * float(lie_read.lift)
		var side_c := miss * 0.05 * bs + float(mods.get("side", 0.0)) + float(lie_read.side)
		var spin_c := (float(c.spin) + float(mods.get("spin", 0.0))) * float(lie_read.spin)
		b.launch(speed, aim + miss * sig, loft, lift_c, side_c, spin_c)
		# the same swing in still air, so the golfer can be told what the wind did
		var calm := Ball.new()
		calm.set_def(b.def)
		calm.lava = b.lava
		calm.shot_wind = b.shot_wind
		calm.place(from)
		calm.launch(speed, aim + miss * sig, loft, lift_c, side_c, spin_c)
		var n := 0
		while calm.moving() and n < 2400:
			calm.step(1.0 / 60.0, sim.course, Vector3.ZERO, Vector3.ZERO, false)
			n += 1
		_calm_rest = calm.pos
		_shot_clean = calm.hits == 0 and calm.tree_tile < 0
	if putting:
		b.struck_from = Defs.T.GREEN
	_furthest = 0.0
	_cam_cut = false
	_cam_pitch = 0.0
	g.strokes += 1
	g.teed = true
	g.phase = Golfer.P.WATCH
	ShotAI.emit_strike(sim, g, clampf(0.4 + power * 0.6, 0.3, 1.0))
	sim.visitors.track_ball(b, hole())
	state = S.FLIGHT
	_ring.visible = false
	_mesh.clear_surfaces()
	rig.target_dist = clampf(rig.target_dist * 1.25, 20.0, 300.0)
	changed.emit()


func _resolve() -> void:
	var b := g.ball
	var h := hole()
	var away := Vector2(b.pos.x - h.pin.x, b.pos.z - h.pin.z).length()
	match b.state:
		Ball.S.HOLED:
			sim.career.shot_done(b, Defs.T.GREEN, 0.0, true)
			_finish_hole()
			return
		Ball.S.WATER, Ball.S.OOB:
			sim.career.shot_done(b, -1, away, false)
		_:
			sim.career.shot_done(b, sim.course.terrain_at(b.pos.x, b.pos.z), away, false)
	match b.state:
		Ball.S.WATER:
			g.strokes += 1
			var sunk := sim.course.terrain_at(b.pos.x, b.pos.z)
			var word := sim.terrain_name(Defs.T.STREAM if sunk == Defs.T.STREAM else Defs.T.WATER)
			message = "In the %s. One stroke penalty." % word.to_lower()
			sim.player.lose_ball()
			b.place(Group.drop_spot(sim.course, b))
		Ball.S.OOB:
			# stroke and distance: one penalty stroke, and play again from the same spot
			g.strokes += 1
			message = "Out of bounds. One stroke penalty: you play your %s from the same spot." % _ordinal(g.strokes + 1)
			sim.player.lose_ball()
			b.place(b.start)
		_:
			var t := sim.course.terrain_at(b.pos.x, b.pos.z)
			var d := Vector2(b.pos.x - h.pin.x, b.pos.z - h.pin.z).length()
			if Defs.is_green(t):
				message = "On the green, %d feet from the hole." % int(d * 3.281)
			elif t >= 0:
				message = "%s, %d yards to the pin." % [sim.terrain_name(t), Defs.yards(d)]
			if b.plugged:
				message = "Plugged in the sand, %d yards to the pin." % Defs.yards(d)
			message += _shot_report(b)
	if g.strokes >= h.par + 6:
		message = "That's enough. Picking up."
		g.picked_up = true
		_finish_hole()
		return
	state = S.PAUSE
	_timer = 0.9
	changed.emit()


## What the spin and the wind did to the shot that just finished.
func _shot_report(b: Ball) -> String:
	if putting:
		return ""
	var out := ""
	var from := Vector2(b.start.x, b.start.z)
	var rest := Vector2(b.pos.x, b.pos.z)
	var came_back := _furthest - from.distance_to(rest)
	if came_back > 0.6 and Defs.is_green(sim.course.terrain_at(b.pos.x, b.pos.z)):
		out += "  It spun back %d feet." % int(round(came_back * 3.281))
	if _shot_clean and b.hits == 0 and b.tree_tile < 0 and sim.weather.wind_mph() >= 2:
		var line := Vector2(_calm_rest.x, _calm_rest.z) - from
		var l := line.length()
		if l > 5.0:
			line /= l
			var moved := rest - Vector2(_calm_rest.x, _calm_rest.z)
			var long := Defs.yards(absf(moved.dot(line)))
			var wide := Defs.yards(absf(moved.dot(Vector2(-line.y, line.x))))
			var bits: Array[String] = []
			if wide >= 2:
				bits.append("%d yards %s" % [wide, "right" if moved.dot(Vector2(-line.y, line.x)) > 0.0 else "left"])
			if long >= 2:
				bits.append("%d yards %s" % [long, "longer" if moved.dot(line) > 0.0 else "shorter"])
			if not bits.is_empty():
				out += "  The wind took it %s." % " and ".join(PackedStringArray(bits))
	return out


static func _ordinal(n: int) -> String:
	var words := ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth"]
	return str(words[n]) if n > 0 and n < words.size() else "%dth" % n


func _next() -> void:
	if g.done:
		if hole_i >= last_hole:
			_finish_round()
		else:
			hole().groups.erase(group)
			hole_i += 1
			_begin_hole()
	else:
		_setup_shot()


func _finish_hole() -> void:
	var h := hole()
	var score := h.par + 6 if g.picked_up else g.strokes
	h.record(score)
	g.done = true
	g.cheer_t = 2.0
	card.append(score)
	pars.append(h.par)
	g.scores.append(score)
	g.pars.append(h.par)
	sim.player.holes_played += 1
	var diff := score - h.par
	var names := {-3: "Albatross!", -2: "Eagle!", -1: "Birdie!", 0: "Par.", 1: "Bogey.", 2: "Double bogey."}
	var word: String = "Hole in one!" if score == 1 else str(names.get(diff, "%+d." % diff))
	message = "%s  %d on the par %d." % [word, score, h.par]
	sim.popup.emit(g.pos, word, "good" if diff <= 0 else "money")
	if score == 1:
		sim.sound.emit("cheer", g.pos, 1.0)
	elif diff <= -1:
		sim.sound.emit("clap", g.pos, 1.0)
	sim.skills.add_xp("golfer", clampi(8 - diff * 3, 2, 30))
	var won := sim.career.hole_done(h, score, g.picked_up)
	if won > 0:
		message += "  +%d skill point%s." % [won, "" if won == 1 else "s"]
	if not match_play.is_empty():
		# the rival plays the same hole, off screen
		var theirs := HoleLab.play_hole(sim, match_play.golfer, h)
		if score < theirs:
			match_play.won = int(match_play.won) + 1
			message += "  %s made %d: you win the hole." % [match_play.rival, theirs]
		elif score > theirs:
			match_play.lost = int(match_play.lost) + 1
			message += "  %s made %d: you lose the hole." % [match_play.rival, theirs]
		else:
			message += "  %s made %d too: hole halved." % [match_play.rival, theirs]
	hole_done.emit(hole_i, score, h.par)
	state = S.PAUSE
	_timer = 2.6
	changed.emit()


func _finish_round() -> void:
	var total := 0
	var par_total := 0
	for i in card.size():
		total += card[i]
		par_total += pars[i]
	var key := str(card.size())
	var best: int = int(sim.player.best_scores.get(key, 999))
	if total - par_total < best:
		sim.player.best_scores[key] = total - par_total
	sim.player.last_card = card.duplicate()
	var c := card.duplicate()
	var p := pars.duplicate()
	sim.career.round_done(c, p)
	if not match_play.is_empty():
		_settle_match(false)
	if tournament:
		tournament = false
		sim.tourney.player_finished(c, p)
		summary = "Your card is in. The leaderboard is in the Tournaments panel."
	stop()
	round_done.emit(c, p)


func _settle_match(forfeit: bool) -> void:
	var m := match_play
	match_play = {}
	var stake := float(m.stake)
	var rival := str(m.rival)
	if forfeit or int(m.lost) > int(m.won):
		sim.economy.spend("wagers", stake)
		sim.feed.say("match_loss", null, {"other": rival}, true, "Golf Enquirer", "GolfEnquirer")
		summary = "%s wins the match %d holes to %d. You pay %s." % [rival, int(m.lost), int(m.won), Defs.money(stake)]
		if forfeit:
			summary = "You walked off. %s takes the %s." % [rival, Defs.money(stake)]
	elif int(m.won) > int(m.lost):
		sim.economy.earn("events", stake)
		sim.stats.matches_won = int(sim.stats.matches_won) + 1
		sim.skills.add_xp("golfer", 20)
		sim.career.check()
		sim.feed.say("match_win", null, {"other": rival}, true, "Golf Enquirer", "GolfEnquirer")
		summary = "You beat %s %d holes to %d and collect %s." % [rival, int(m.won), int(m.lost), Defs.money(stake)]
	else:
		summary = "All square with %s. Nobody pays." % rival
	sim.toast.emit(summary, "good" if int(m.won) > int(m.lost) and not forfeit else "info")


# ----------------------------------------------------------- aim preview

func _update_preview() -> void:
	var h := hole()
	_path.clear()
	if putting:
		# Without the Green Reader skill you only get a straight line.
		var reach := minf(pin_dist + 1.5, MAX_PUTT)
		if sim.skills.bonus("read_greens") > 0.0 and target_power > 0.0:
			var b := Ball.new()
			b.set_def(g.ball.def)
			b.place(g.ball.pos)
			b.launch(_putt_full_speed() * target_power, aim, 0.0, 0.0, 0.0, 0.0)
			var n := 0
			_path.append(b.pos)
			while b.moving() and n < 900:
				b.step(1.0 / 60.0, sim.course, Vector3.ZERO, Vector3.ZERO, false)
				n += 1
				if n % 6 == 0:
					_path.append(b.pos)
			_path.append(b.pos)
		else:
			for k in 13:
				var q := g.ball.pos + Vector3(cos(aim), 0.0, sin(aim)) * reach * k / 12.0
				_path.append(sim.course.on_ground(q.x, q.z))
		_landing = _path[-1]
	else:
		# the slope under the ball matters differently as the golfer turns
		var was := float(lie_read.get("power", 1.0))
		lie_read = Lie.read(sim, g, aim)
		if not is_equal_approx(was, float(lie_read.power)):
			_refresh_numbers()
		var full := _full_speed()
		var speed := full * (target_power if target_power > 0.0 else 1.0)
		_landing = ShotAI.predict(sim, g, club_i, speed, aim, sim.skills.bonus("wind_read") > 0.0, Lie.blend(lie_read, shape().mods))
		var li := sim.course.index_at(_landing.x, _landing.z)
		var oob := li < 0 or sim.course.locked[li] != 0
		if oob != out_of_bounds:
			out_of_bounds = oob
			_ring.material_override = WorldView.glow(Color(1.0, 0.3, 0.25) if oob else Color(1.0, 0.85, 0.2))
			changed.emit()
		for k in 21:
			var q := g.ball.pos.lerp(_landing, k / 20.0)
			_path.append(sim.course.on_ground(q.x, q.z))
	# keep the pin distance honest as the player turns
	pin_dist = Vector2(h.pin.x - g.ball.pos.x, h.pin.z - g.ball.pos.z).length()


func _draw_preview() -> void:
	_mesh.clear_surfaces()
	if state != S.AIM and state != S.POWER and state != S.ACCURACY:
		_ring.visible = false
		return
	if _path.size() < 2:
		return
	var width := 0.05 if putting else maxf(0.25, rig.dist * 0.004)
	var col := Color(1.0, 0.9, 0.3, 0.75)
	var aim_v := Vector2(cos(aim), sin(aim))
	var on_green := putting and Defs.is_green(lie)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in _path.size() - 1:
		if i % 2 == 1 and not putting:
			continue
		var p0 := _path[i] + Vector3(0, 0.08, 0)
		var p1 := _path[i + 1] + Vector3(0, 0.08, 0)
		var dir := p1 - p0
		var side := Vector3(-dir.z, 0.0, dir.x)
		if side.length_squared() < 1e-8:
			continue
		side = side.normalized() * width
		var seg := col
		if on_green:
			var mid := (p0 + p1) * 0.5
			var here := Slope.read(sim.course, mid.x, mid.z)
			var fall: Vector2 = here.get("fall", Vector2.ZERO)
			seg = Slope.aim_tint(fall.dot(aim_v), float(here.get("percent", 0.0)), col)
		var chunk := PackedVector3Array([p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side])
		verts.append_array(chunk)
		for _k in chunk.size():
			cols.append(seg)
	if not verts.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
		for i in verts.size():
			_mesh.surface_set_color(cols[i])
			_mesh.surface_add_vertex(verts[i])
		_mesh.surface_end()
	_ring.visible = not putting
	_ring.position = _landing + Vector3(0, 0.3, 0)
	_ring.scale = Vector3.ONE * clampf(rig.dist / 90.0, 0.6, 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if state == S.OFF:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_SPACE, KEY_ENTER:
				press()
				get_viewport().set_input_as_handled()
			KEY_W, KEY_UP:
				change_club(-1)
				get_viewport().set_input_as_handled()
			KEY_S, KEY_DOWN:
				change_club(1)
				get_viewport().set_input_as_handled()
			KEY_TAB:
				cycle_ball()
				get_viewport().set_input_as_handled()
			KEY_Q:
				cycle_shape(-1)
				get_viewport().set_input_as_handled()
			KEY_E:
				cycle_shape(1)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				stop()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			press()
			get_viewport().set_input_as_handled()
