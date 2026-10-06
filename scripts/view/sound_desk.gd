class_name SoundDesk
extends Node
## Everything you hear: sound effects out on the course, the clicks and
## chimes of the interface, the ambience that follows the weather and the
## time of day, and the music.
##
## The simulation only announces what happened (Sim.sound). This decides
## whether the camera is near enough to hear it, and how loud it is.
##
## Sound effects, ambience and voices are made by tools/make_sounds.py. The
## music is other people's, CC0 (data/music.json). Everything is Ogg Vorbis.
##
## Two switches for checking it without ears (the bus meters read even when
## a test run is muted):
##   --soundcheck  plays the golf sounds and the voices through the real path
##                 at four zooms and prints what reached the Sound bus
##   --soundlog    counts what the game announced against what was played,
##                 and how loud, and prints the table when the game closes

const WORLD_VOICES := 18
const UI_VOICES := 6
const TALKERS := 3                  # people heard at once. More than that is a crowd
const VOICE_FADE := 6.0             # decibels a voice loses, on top of everything else, by its far distance
const CHECK_IDS: Array[String] = ["drive", "iron", "chip", "putt", "strike_sand", "strike_rough", "cup", "sizzle", "land_soft", "oob", "chat", "cheer", "groan", "boo"]
const DIR := "res://assets/sounds/"
const MUSIC_DIR := "res://assets/music/"

static var desk: SoundDesk          # the one desk, so anything can ask for a click

var sim: Sim
var rig: CameraRig
var lamps_out := 0                  # how many lights the course has, for the click as they come on
var now_playing := ""               # "Title by Composer", for the menu
var plays := {}                     # id -> times played, for tests
var announced := {}                 # id -> times the game announced it, heard or not
var levels := {}                    # id -> [quietest, loudest, total] in decibels, of what was played
var skipped := {}                   # id -> {why: times}
var start_cost: Array[int] = [0, 0, 0]   # starting a sound: how many, total and slowest, in microseconds
var unpack_ms := 0                  # how long unpacking the effects took when the game opened
var _defs := {}
var _last := {}
var _world: Array[AudioStreamPlayer3D] = []
var _world_i := 0
var _ui: Array[AudioStreamPlayer] = []
var _ui_i := 0
var _amb := {}                      # name -> {player, db, level}
var _mower := AudioStreamPlayer3D.new()
var _mower_level := 0.0
var _decks: Array[AudioStreamPlayer] = []    # two, so one track can fade into the next
var _fade: Array[float] = [0.0, 0.0]         # where each deck's fader is, 0 to 1
var _aim: Array[float] = [0.0, 0.0]          # and where it is heading
var _gain: Array[float] = [0.0, 0.0]
var _live := 0                      # the deck playing the current track
var _list := ""
var _track := ""
var _recent: Array[String] = []
var _quiet := 2.5                   # seconds of quiet before the next track
var _pending := ""                  # a track still loading
var _thunder_in := -1.0
var _was_dark := false
var _later: Array[Dictionary] = []  # sounds waiting for their moment: {at, id, pos, power} and for talk {stream, who, pitch}
var _talking: Array[float] = []     # when each voice now being heard will finish
var _chat := {}                     # the chatter settings (data/sounds.json)
var _lines := {}                    # voice name -> the lines it can say
var _chat_in := 3.0                 # seconds until the next conversation may start
var _chat_last := {}                # group id -> when it last had a conversation
var _check := {}                    # where a --soundcheck run has got to
var _seen := 0.0                    # the game's clock at the last frame that was drawn


static func _bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


func _ready() -> void:
	desk = self
	process_mode = Node.PROCESS_MODE_ALWAYS       # music and clicks carry on while the game is paused
	_bus("Music")
	_bus("Sound")
	_bus("Ambience")
	if AudioServer.get_bus_effect_count(0) == 0:
		# many things at once must never clip
		var limit := AudioEffectHardLimiter.new()
		limit.ceiling_db = -0.8
		AudioServer.add_bus_effect(0, limit)
	# Test runs are silent unless asked: nobody wants a robot's golf game
	# coming out of their speakers. The meters still read, so tests still work.
	if (Game.args.has("shot") or Game.args.has("exit")) and not Game.args.has("sound"):
		AudioServer.set_bus_mute(0, true)
	var table: Dictionary = Game.db.sounds.get("sounds", {})
	var t0 := Time.get_ticks_msec()
	var ready := {}                 # file -> unpacked, so a file used twice is unpacked once
	for id: String in table:
		var d: Dictionary = table[id]
		var streams: Array[AudioStream] = []
		for f: String in d.files:
			if not ready.has(f):
				ready[f] = _unpacked(load(DIR + f + ".ogg"))
			var st: AudioStream = ready[f]
			if st != null:
				streams.append(st)
			else:
				push_warning("Missing sound " + f)
		var after: Dictionary = d.get("then", {})
		_defs[id] = {"streams": streams, "db": float(d.get("db", -6)), "pitch": float(d.get("pitch", 0.0)), "gap": float(d.get("gap", 0.05)),
			"delay": float(d.get("delay", 0.0)), "voice": bool(d.get("voice", false)), "far": float(d.get("far", 0.0)),
			"then": str(after.get("id", "")), "chance": float(after.get("chance", 1.0))}
	_chat = Game.db.sounds.get("chatter", {})
	var cast: Dictionary = _chat.get("voices", {})
	for who: String in cast:
		var said: Array[AudioStream] = []
		for f: String in cast[who]:
			if not ready.has(f):
				ready[f] = _unpacked(load(DIR + f + ".ogg"))
			var st: AudioStream = ready[f]
			if st != null:
				said.append(st)
		if not said.is_empty():
			_lines[who] = said
	unpack_ms = Time.get_ticks_msec() - t0
	for i in WORLD_VOICES:
		var v := AudioStreamPlayer3D.new()
		v.bus = "Sound"
		# loudness is worked out by hand from the zoom; the 3D only places it left or right
		v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		# Godot muffles a 3D sound more the quieter it is set. That swallowed
		# every club strike: the sharp part of the sound is all there is.
		v.attenuation_filter_db = 0.0
		v.attenuation_filter_cutoff_hz = 20500.0
		v.panning_strength = 0.6
		v.max_polyphony = 1
		add_child(v)
		_world.append(v)
	for i in UI_VOICES:
		var u := AudioStreamPlayer.new()
		u.bus = "Sound"
		add_child(u)
		_ui.append(u)
	var beds: Dictionary = Game.db.sounds.get("ambience", {})
	for bed_name: String in beds:
		var b: Dictionary = beds[bed_name]
		var st := _looping(DIR + str(b.file) + ".ogg")
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = st
		p.volume_db = -80.0
		add_child(p)
		_amb[bed_name] = {"player": p, "db": float(b.get("db", -12)), "level": 0.0}
	_mower.bus = "Sound"
	_mower.stream = _looping(DIR + "mower.ogg")
	_mower.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_mower.attenuation_filter_db = 0.0
	_mower.attenuation_filter_cutoff_hz = 20500.0
	_mower.panning_strength = 0.6
	_mower.volume_db = -80.0
	add_child(_mower)
	for i in 2:
		var deck := AudioStreamPlayer.new()
		deck.bus = "Music"
		deck.volume_db = -80.0
		add_child(deck)
		_decks.append(deck)
	Game.volume_changed.connect(_apply_volumes)
	_apply_volumes()


## An effect, decoded once and kept in memory as plain audio.
##
## Starting a Vorbis decoder takes about a fifth of a millisecond, on the
## main thread, every time a sound plays; plain audio starts in no time at
## all. Effects are short and there are many a second, so they are unpacked
## when the game opens (a few tenths of a second for all of them). The
## ambience and the music are long: they stay packed and decode as they play.
static func _unpacked(src: AudioStream) -> AudioStream:
	if src == null:
		return null
	var pb := src.instantiate_playback()
	if pb == null:
		return src
	var rate := AudioServer.get_mix_rate()
	pb.start(0.0)
	var frames := pb.mix_audio(1.0, int(src.get_length() * rate) + 64)
	pb.stop()
	if frames.is_empty():
		return src
	var n := frames.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	var stereo := false
	for i in n:
		var f := frames[i]
		if absf(f.x - f.y) > 0.0002:
			stereo = true
			break
		data.encode_s16(i * 2, clampi(int(roundf(f.x * 32767.0)), -32768, 32767))
	if stereo:
		data.resize(n * 4)
		for i in n:
			var f := frames[i]
			data.encode_s16(i * 4, clampi(int(roundf(f.x * 32767.0)), -32768, 32767))
			data.encode_s16(i * 4 + 2, clampi(int(roundf(f.y * 32767.0)), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(rate)
	wav.stereo = stereo
	wav.data = data
	return wav


## A sound set to repeat end to end. It shares the audio of the one on disk,
## which stays as it is. The files are made so that the end runs into the
## beginning (make_sounds.py checks the join after encoding).
static func _looping(path: String) -> AudioStream:
	var src := load(path) as AudioStreamOggVorbis
	if src == null:
		push_warning("Missing sound " + path)
		return null
	var st := AudioStreamOggVorbis.new()
	st.packet_sequence = src.packet_sequence
	st.loop = true
	st.loop_offset = 0.0
	return st


func _apply_volumes() -> void:
	_set_bus("Music", Game.vol_music)
	_set_bus("Sound", Game.vol_sound)
	_set_bus("Ambience", Game.vol_sound)


static func _set_bus(bus_name: String, level: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(i, level <= 0.005)
	# squared, so the middle of the slider sounds like half
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(level * level, 0.0001)))


func bind(s: Sim, camera: CameraRig) -> void:
	sim = s
	rig = camera
	_seen = s.time
	_was_dark = s.darkness() > 0.5
	s.sound.connect(play_at)
	s.month_ended.connect(func(_label: String) -> void: play("cash"))


# ------------------------------------------------------------ sound effects

## A sound somewhere on the course. Heard at full strength up close, fainter
## as the camera pulls back, and fainter still off to the side of the view.
## A reaction (a cheer, a groan) waits a moment first, as people do.
func play_at(id: String, pos: Vector3, power: float = 1.0) -> void:
	if rig == null or not _defs.has(id):
		return
	# Time that was skipped over (a test fast-forwarding the game) was never
	# seen, so it is never heard either.
	if sim.time - _seen > 1.5:
		return
	announced[id] = int(announced.get(id, 0)) + 1
	var wait := float(_defs[id].delay)
	if wait > 0.0:
		_later.append({"at": Time.get_ticks_msec() / 1000.0 + wait * randf_range(0.8, 1.3), "id": id, "pos": pos, "power": power})
	else:
		_sound(id, pos, power)


## Play it now. `line` is what to say, for talk; otherwise one of the sound's
## files is picked. Returns how long it will last, or 0 if it was not played.
func _sound(id: String, pos: Vector3, power: float, line: AudioStream = null, pitch: float = 0.0) -> float:
	var d: Dictionary = _defs[id]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(id, -9.0)) < float(d.gap):
		return _skip(id, "too soon after the last one")
	# A shot has to be heard whenever its golfer can be seen, so pulling the
	# camera back only takes the edge off: about 2 dB for each doubling.
	var db := float(d.db) - minf(2.2 * log(maxf(rig.dist, 40.0) / 40.0) / log(2.0), 12.0) + linear_to_db(clampf(power, 0.05, 1.0)) * 0.5
	var far := float(d.far)
	if far > 0.0:
		# talk is for when the camera is down among the golfers
		if rig.dist > far:
			return _skip(id, "camera too far away")
		db -= VOICE_FADE * smoothstep(far * 0.2, far, rig.dist)
	var away := Vector2(pos.x - rig.focus.x, pos.z - rig.focus.z).length()
	var view := maxf(rig.dist * 0.9, 25.0)
	if away > view:
		db -= (away / view - 1.0) * 12.0
	if db < -46.0:
		return _skip(id, "outside the view")
	var streams: Array = d.streams
	if streams.is_empty():
		return _skip(id, "no file")
	if bool(d.voice):
		for i in range(_talking.size() - 1, -1, -1):
			if _talking[i] <= now:
				_talking.remove_at(i)
		if _talking.size() >= TALKERS:
			return _skip(id, "enough people talking already")
	_last[id] = now
	plays[id] = int(plays.get(id, 0)) + 1
	var lv: Array = levels.get(id, [db, db, 0.0])
	levels[id] = [minf(float(lv[0]), db), maxf(float(lv[1]), db), float(lv[2]) + db]
	var v := _world[_world_i]
	_world_i = (_world_i + 1) % _world.size()
	var t0 := Time.get_ticks_usec()
	v.stream = line if line != null else streams[randi() % streams.size()]
	v.position = pos
	v.volume_db = db
	v.pitch_scale = (pitch if pitch > 0.0 else 1.0) + randf_range(-1.0, 1.0) * float(d.pitch)
	v.play()
	var took := int(Time.get_ticks_usec() - t0)
	start_cost = [start_cost[0] + 1, start_cost[1] + took, maxi(start_cost[2], took)]
	var length := v.stream.get_length() / v.pitch_scale
	if bool(d.voice):
		_talking.append(now + length)
	# what follows: a groan after a splash, a boo after someone is hit
	var next := str(d.then)
	if next != "" and _defs.has(next) and randf() < float(d.chance):
		play_at(next, pos, power)
	return length


func _skip(id: String, why: String) -> float:
	var s: Dictionary = skipped.get(id, {})
	s[why] = int(s.get(why, 0)) + 1
	skipped[id] = s
	return 0.0


## A sound with no place: the interface, or something heard everywhere.
func play(id: String, power: float = 1.0) -> void:
	if not _defs.has(id):
		return
	var d: Dictionary = _defs[id]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(id, -9.0)) < float(d.gap):
		return
	var streams: Array = d.streams
	if streams.is_empty():
		return
	_last[id] = now
	plays[id] = int(plays.get(id, 0)) + 1
	var u := _ui[_ui_i]
	_ui_i = (_ui_i + 1) % _ui.size()
	u.stream = streams[randi() % streams.size()]
	u.volume_db = float(d.db) + linear_to_db(clampf(power, 0.05, 1.0)) * 0.5
	u.pitch_scale = 1.0 + randf_range(-1.0, 1.0) * float(d.pitch)
	u.play()


## For anything without a desk to hand: SoundDesk.ui("click").
static func ui(id: String) -> void:
	if desk != null:
		desk.play(id)


## Lightning has struck: the thunder follows after a moment.
func thunder() -> void:
	if _thunder_in < 0.0:
		_thunder_in = randf_range(0.3, 1.8)


# ------------------------------------------------------- ambience and music

func _process(delta: float) -> void:
	if sim == null or rig == null:
		return
	delta = minf(delta, 0.1)
	_seen = sim.time
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0:
			play("thunder", randf_range(0.5, 1.0))
	var dark := sim.darkness()
	if dark > 0.5 and not _was_dark and lamps_out > 0:
		play("lamp_on")
	_was_dark = dark > 0.5
	_ambience(delta, dark)
	_mowing(delta)
	_music(delta, dark)
	_due()
	_chatter(delta)
	if Game.args.has("soundcheck"):
		_soundcheck()


## How loud each background bed should be right now, 0 to 1.
func ambience_levels(dark: float) -> Dictionary:
	var rain := sim.weather.rain
	var near := 1.0 - smoothstep(60.0, 600.0, rig.dist)          # 1 down among the trees
	var hot := sim.is_lava()
	var erupting := sim.eruption.active()
	return {
		"birds": (1.0 - dark) * (1.0 - rain) * lerpf(0.3, 1.0, near) * (0.35 if hot else 1.0) * (0.0 if erupting else 1.0),
		"crickets": dark * (1.0 - rain * 0.8) * lerpf(0.55, 1.0, near),
		"wind": clampf(sim.weather.wind_mph() / 24.0, 0.1, 1.0) * lerpf(1.0, 0.55, near),
		"rain": clampf(rain * 1.2, 0.0, 1.0),
		"lava": (0.45 + (0.55 if erupting else 0.0)) if hot else 0.0,
	}


func _ambience(delta: float, dark: float) -> void:
	var want := ambience_levels(dark)
	for bed_name: String in _amb:
		var bed: Dictionary = _amb[bed_name]
		var p: AudioStreamPlayer = bed.player
		if p.stream == null:
			continue
		bed.level = move_toward(float(bed.level), float(want.get(bed_name, 0.0)), delta * 0.5)
		var level := float(bed.level)
		if level > 0.004:
			if not p.playing:
				p.play(randf() * p.stream.get_length())
			p.volume_db = float(bed.db) + linear_to_db(level)
		elif p.playing:
			p.stop()


## A mower can be heard when a greenkeeper is at work near the middle of the view.
func _mowing(delta: float) -> void:
	var best: Crew.Member = null
	var best_d := INF
	if rig.dist < 260.0 and not Game.paused:
		for m in sim.crew.members:
			if m.state == 2 and str(m.role.id) == "greenkeeper":
				var d := Vector2(m.pos.x - rig.focus.x, m.pos.z - rig.focus.z).length()
				if d < best_d:
					best_d = d
					best = m
	var want := 0.0
	if best != null:
		var view := maxf(rig.dist * 0.9, 25.0)
		want = clampf(1.3 - best_d / view, 0.0, 1.0) * (1.0 - smoothstep(40.0, 260.0, rig.dist))
		_mower.position = best.pos
	_mower_level = move_toward(_mower_level, want, delta * 1.5)
	if _mower_level > 0.01 and _mower.stream != null:
		if not _mower.playing:
			_mower.play()
		_mower.volume_db = -20.0 + linear_to_db(_mower_level)
	elif _mower.playing:
		_mower.stop()


func _music(delta: float, dark: float) -> void:
	var tracks: Array = Game.db.music.get("tracks", [])
	if tracks.is_empty():
		return
	# the faders
	for i in 2:
		_fade[i] = move_toward(_fade[i], _aim[i], delta / (6.0 if _aim[i] < _fade[i] else 2.5))
		var deck := _decks[i]
		if deck.playing:
			deck.volume_db = _gain[i] + linear_to_db(maxf(_fade[i], 0.0001))
			if _aim[i] <= 0.0 and _fade[i] <= 0.001:
				deck.stop()
	var want := "night" if dark > 0.6 else "day"
	var deck := _decks[_live]
	if _pending != "":
		_start_when_loaded()
		return
	if deck.playing and _aim[_live] > 0.0:
		var left := deck.stream.get_length() - deck.get_playback_position()
		# The light has changed: let a track that is nearly done finish, but
		# hand a long one over gently to something that suits the hour.
		if want != _list and deck.get_playback_position() > 25.0 and left > 40.0:
			_aim[_live] = 0.0
			_quiet = 3.0
		elif left < 5.0:
			_aim[_live] = 0.0
			_quiet = randf_range(8.0, 20.0)
		return
	_quiet -= delta
	if _quiet <= 0.0:
		_queue(want)


func _queue(list_name: String) -> void:
	var ids: Array = Game.db.music.get(list_name, [])
	if ids.is_empty():
		return
	var pool: Array = ids.filter(func(id: String) -> bool: return not _recent.has(id))
	if pool.is_empty():
		_recent.clear()
		pool = ids.duplicate()
	var id := str(pool[randi() % pool.size()])
	if Game.args.has("track"):
		id = str(Game.args.track)
	_list = list_name
	_recent.append(id)
	if _recent.size() > maxi(1, ids.size() - 1):
		_recent.pop_front()
	_pending = id
	var t := DataDB.find(Game.db.music.get("tracks", []), id)
	if t.is_empty():
		_pending = ""
		_quiet = 5.0
		return
	# loaded off to the side, so a long track never stalls a frame
	ResourceLoader.load_threaded_request(MUSIC_DIR + str(t.file))


func _start_when_loaded() -> void:
	var t := DataDB.find(Game.db.music.get("tracks", []), _pending)
	var path := MUSIC_DIR + str(t.file)
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var id := _pending
	_pending = ""
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_warning("Could not load music " + path)
		_quiet = 10.0
		return
	var stream: AudioStream = ResourceLoader.load_threaded_get(path)
	_live = 1 - _live
	var deck := _decks[_live]
	deck.stream = stream
	_gain[_live] = float(Game.db.music.get("level_db", -9)) + float(t.get("gain_db", 0.0))
	_fade[_live] = 0.0
	_aim[_live] = 1.0
	deck.volume_db = -80.0
	deck.play()
	_track = id
	now_playing = "%s by %s" % [str(t.title), str(t.by)]


func music_playing() -> bool:
	return _decks[_live].playing and _aim[_live] > 0.0


## On to the next track.
func skip_track() -> void:
	_aim[_live] = 0.0
	_quiet = 1.5


# ------------------------------------------------------------------- voices

## Anything that was waiting for its moment.
func _due() -> void:
	if _later.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var i := 0
	while i < _later.size():
		var w: Dictionary = _later[i]
		if float(w.at) > now:
			i += 1
			continue
		_later.remove_at(i)
		if w.has("who"):
			var g: Golfer = w.who
			_sound("chat", g.pos, 1.0, w.stream, float(w.pitch))
		else:
			_sound(str(w.id), w.pos, float(w.power))


## Which of the voices a golfer has. It never changes, and the higher voices
## go to the figures with long hair (see PersonFig.build and where
## WorldView calls it: the same sum picks the hair).
func voice_of(g: Golfer) -> String:
	var long_hair := (g.id * 7 + 3) % 5 >= 3
	var pool: Array = _chat.get("high" if long_hair else "low", [])
	pool = pool.filter(func(v: String) -> bool: return _lines.has(v))
	if pool.is_empty():
		pool = _lines.keys()
	if pool.is_empty():
		return ""
	return str(pool[(g.id / 5 + g.id) % pool.size()])


## No two golfers sound quite alike: each speaks a little higher or lower.
static func pitch_of(g: Golfer) -> float:
	return 0.94 + float((g.id * 37) % 13) / 12.0 * 0.12


## Golfers talk among themselves while they walk and wait, when the camera
## is near enough to overhear. One says something; often another answers.
func _chatter(delta: float) -> void:
	if _lines.is_empty() or not _defs.has("chat"):
		return
	_chat_in -= delta
	if _chat_in > 0.0:
		return
	_chat_in = 1.0
	if Game.paused or rig.dist > float(_defs.chat.far):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var view := maxf(rig.dist * 0.9, 25.0)
	var quiet := float(_chat.get("quiet", 9.0))
	var near: Array[Group] = []
	for gr in sim.visitors.groups:
		if gr.members.size() < 2 or gr.state == Group.S.GONE:
			continue
		# nobody talks while one of them is over the ball
		if gr.turn != null and (gr.turn.phase == Golfer.P.AIM or gr.turn.phase == Golfer.P.SWING):
			continue
		if now - float(_chat_last.get(gr.id, -99.0)) < quiet:
			continue
		var lead := gr.members[0]
		if Vector2(lead.pos.x - rig.focus.x, lead.pos.z - rig.focus.z).length() > view:
			continue
		near.append(gr)
	if near.is_empty():
		return
	var gr := near[randi() % near.size()]
	converse(gr)
	var every: Array = _chat.get("every", [4.0, 11.0])
	# a busy course has more to say, but never a babble
	_chat_in = randf_range(float(every[0]), float(every[1])) / minf(sqrt(float(near.size())), 1.5)


## One short conversation in a group: a line, perhaps an answer, perhaps a
## last word. Returns how many lines were said.
func converse(gr: Group) -> int:
	var speakers: Array[Golfer] = []
	for m in gr.members:
		if m != gr.turn and voice_of(m) != "":
			speakers.append(m)
	if speakers.is_empty():
		return 0
	var now := Time.get_ticks_msec() / 1000.0
	_chat_last[gr.id] = now
	var first := speakers[randi() % speakers.size()]
	var second: Golfer = null
	if speakers.size() > 1:
		second = speakers[(speakers.find(first) + 1 + randi() % (speakers.size() - 1)) % speakers.size()]
	var reply := float(_chat.get("reply", 0.65))
	var count := 1
	if second != null and randf() < reply:
		count = 3 if randf() < reply * 0.5 else 2
	var at := now
	var said := {}
	for k in count:
		var g := first if k % 2 == 0 else second
		var mine: Array = _lines[voice_of(g)]
		var line: AudioStream = mine[randi() % mine.size()]
		if said.has(line):
			line = mine[(mine.find(line) + 1) % mine.size()]
		said[line] = true
		var pitch := pitch_of(g)
		_later.append({"at": at, "id": "chat", "who": g, "stream": line, "pitch": pitch})
		at += line.get_length() / pitch + randf_range(0.15, 0.5)
	return count


# ------------------------------------------------------------------ checking

## --soundlog: what the game announced against what was actually played.
func log_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var ids := announced.keys()
	for id: String in plays:
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	for id: String in ids:
		var n := int(plays.get(id, 0))
		var text := "%-13s announced %4d, played %4d" % [id, int(announced.get(id, 0)), n]
		if levels.has(id) and n > 0:
			var lv: Array = levels[id]
			text += ", set between %5.1f and %5.1f dB (average %5.1f)" % [float(lv[0]), float(lv[1]), float(lv[2]) / float(maxi(1, n))]
		var why: Dictionary = skipped.get(id, {})
		for reason: String in why:
			text += "; %d %s" % [int(why[reason]), reason]
		out.append(text)
	if start_cost[0] > 0:
		out.append("starting a sound took %d microseconds on average and %d at the slowest, over %d sounds" % [start_cost[1] / start_cost[0], start_cost[2], start_cost[0]])
	out.append("unpacking the effects when the game opened took %d ms (mixing at %d Hz)" % [unpack_ms, int(AudioServer.get_mix_rate())])
	return out


func _exit_tree() -> void:
	if Game.args.has("soundlog"):
		for line in log_lines():
			print("SOUNDLOG " + line)


## --soundcheck: the golf sounds and the voices, through the same path the
## game uses, at the zoom the game opens at and three others.
func _soundcheck() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _check.is_empty():
		_check = {"home": rig.dist, "i": -1, "until": now + 4.0, "peak": -200.0, "zoom": rig.dist}
		return
	if int(_check.i) >= 0 and int(_check.i) < 4 * CHECK_IDS.size():
		_check.peak = maxf(float(_check.peak), float(meters().Sound))
	elif int(_check.i) == -1 and now > float(_check.until) - 1.5:
		# the beds have faded in by now; crickets come in pulses, so take the loudest moment
		_check.peak = maxf(float(_check.peak), float(meters().Ambience))
	if now < float(_check.until):
		return
	var i := int(_check.i)
	if i == -1:
		var lv := ambience_levels(sim.darkness())
		print("DEMO soundcheck ambience at %s (zoom %d m): birds %.2f, crickets %.2f, wind %.2f; Ambience meter peaked at %.1f dB" % [
			sim.clock_text(), int(rig.dist), float(lv.birds), float(lv.crickets), float(lv.wind), float(_check.peak)])
	elif i < 4 * CHECK_IDS.size():
		print("DEMO soundcheck zoom %4d m  %-13s peak %6.1f dB" % [int(float(_check.zoom)), CHECK_IDS[i % CHECK_IDS.size()], float(_check.peak)])
	i += 1
	_check.i = i
	if i >= 4 * CHECK_IDS.size():
		if i == 4 * CHECK_IDS.size():
			print("DEMO soundcheck done")
		_check.until = now + 9999.0
		return
	var zooms: Array[float] = [float(_check.home), 60.0, 16.0, 900.0]
	var zoom := zooms[i / CHECK_IDS.size()]
	var id := CHECK_IDS[i % CHECK_IDS.size()]
	rig.target_dist = zoom
	rig.dist = zoom
	_check.zoom = zoom
	_check.peak = -200.0
	_last.erase(id)
	_talking.clear()
	sim.sound.emit(id, rig.focus, 1.0)
	_check.until = now + (1.5 if _defs.has(id) and (float(_defs[id].delay) > 0.0 or bool(_defs[id].voice)) else 0.5)


## What the meters read right now, in decibels, for tests.
func meters() -> Dictionary:
	var out := {}
	for bus_name: String in ["Music", "Sound", "Ambience"]:
		var i := AudioServer.get_bus_index(bus_name)
		out[bus_name] = maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))
	return out
