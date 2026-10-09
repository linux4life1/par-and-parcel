class_name Weather
extends RefCounted
## Weather that drifts with the season: sun, cloud, rain and storms, a wind
## that shifts and gusts, and a temperature.

enum K { CLEAR, CLOUDY, DRIZZLE, RAIN, STORM }

const NAMES: Array[String] = ["Clear", "Cloudy", "Drizzle", "Rain", "Thunderstorm"]
const RAIN_AMT: Array[float] = [0.0, 0.0, 0.3, 0.7, 1.0]
const CLOUD_AMT: Array[float] = [0.05, 0.6, 0.8, 0.95, 1.0]
const WIND_BASE: Array[float] = [2.5, 4.0, 4.5, 6.0, 9.5]
const DURATION: Array[Vector2] = [Vector2(40, 110), Vector2(30, 70), Vector2(25, 50), Vector2(25, 60), Vector2(12, 25)]
const BASE_TEMP: Array[float] = [10.0, 14.0, 19.0, 24.0, 28.0, 27.0, 21.0, 13.0]
const SEASON_WIND: Array[float] = [1.15, 1.05, 0.9, 0.8, 0.8, 0.9, 1.2, 1.35]
# chance weights for the next spell of weather: spring, summer, autumn
const ODDS := [[35.0, 25.0, 15.0, 20.0, 5.0], [55.0, 22.0, 8.0, 9.0, 6.0], [30.0, 30.0, 15.0, 18.0, 7.0]]

var kind: int = K.CLEAR
var rain := 0.0            # 0..1 how hard it is raining right now
var cloud := 0.1           # 0..1 cloud cover
var wind_dir := 0.8        # radians, the direction the wind blows toward
var wind_speed := 3.0      # m/s
var temp := 14.0           # Celsius
var rain_mult := 1.0       # climate, from the scenario
var wind_mult := 1.0
var temp_offset := 0.0     # the biome's climate
var ash := 0.0             # 0..1 volcanic ash in the air
var heat_until := -1.0     # sim time a heat wave ends
var forced: int = -1       # a spell queued by an event
var gust := 0.0            # 0..1, a gust blowing through right now
var _next_change := 35.0
var _gust := 0.0
var _gust_wait := 14.0     # seconds until the next gust
var _gust_len := 0.0
var _gust_t := 0.0
var _gust_peak := 0.0
var _gust_turn := 0.0      # radians a gust swings the wind round
var _gust_rng := RandomNumberGenerator.new()
var _gust_seeded := false

const GUST_GAIN := 0.55    # a full gust blows this much harder than the steady wind


## Keep the weather from rolling on, for a held screenshot.
func hold_off(seconds: float) -> void:
	_next_change = seconds


func step(dt: float, sim: Sim) -> void:
	var month := sim.month()
	_next_change -= dt
	if _next_change <= 0.0:
		_roll(sim, month)
	rain = move_toward(rain, RAIN_AMT[kind], dt * 0.07)
	cloud = move_toward(cloud, CLOUD_AMT[kind], dt * 0.05)
	_gust = clampf(_gust * (1.0 - dt * 0.08) + sim.rng.randfn(0.0, 0.35) * sqrt(dt), -1.0, 1.0)
	var target := WIND_BASE[kind] * wind_mult * SEASON_WIND[month] * (1.0 + 0.35 * _gust)
	wind_speed = maxf(0.0, lerpf(wind_speed, target, minf(dt * 0.2, 1.0)))
	wind_dir = wrapf(wind_dir + sim.rng.randfn(0.0, 0.05) * sqrt(dt), -PI, PI)
	if not _gust_seeded:
		# gusts draw from their own dice, so they never disturb anything else
		_gust_seeded = true
		_gust_rng.seed = sim.rng.seed ^ 0x5bd1e995
	# Gusts: every so often the wind picks up for a few seconds and swings
	# round a little. They come more often, and harder, in rough weather.
	if _gust_len > 0.0:
		_gust_t += dt
		gust = _gust_peak * sin(PI * clampf(_gust_t / _gust_len, 0.0, 1.0))
		if _gust_t >= _gust_len:
			_gust_len = 0.0
			gust = 0.0
			_gust_wait = _gust_rng.randf_range(7.0, 28.0) / (0.7 + 0.25 * kind)
	else:
		_gust_wait -= dt
		if _gust_wait <= 0.0:
			_gust_len = _gust_rng.randf_range(2.5, 6.0)
			_gust_t = 0.0
			_gust_peak = clampf(_gust_rng.randf_range(0.3, 0.8) + 0.08 * kind, 0.0, 1.0)
			_gust_turn = _gust_rng.randf_range(-0.35, 0.35)
	var t := BASE_TEMP[month] + temp_offset - 4.0 * cloud - 3.0 * rain
	ash = maxf(0.0, ash - dt * 0.01)
	if sim.time < heat_until:
		t += 9.0
	temp = lerpf(temp, t, minf(dt * 0.04, 1.0))


func _roll(sim: Sim, month: int) -> void:
	var old := kind
	if forced >= 0:
		kind = forced
		forced = -1
	else:
		var season := 0 if month <= 2 else (1 if month <= 5 else 2)
		var odds: Array = ODDS[season]
		var total := 0.0
		var wts: Array[float] = []
		for i in odds.size():
			var wv: float = odds[i]
			if i >= K.DRIZZLE:
				wv *= rain_mult
			if sim.time < heat_until and i >= K.DRIZZLE:
				wv *= 0.2
			wts.append(wv)
			total += wv
		var r := sim.rng.randf() * total
		kind = K.CLEAR
		for i in wts.size():
			r -= wts[i]
			if r <= 0.0:
				kind = i
				break
	var dur := DURATION[kind]
	_next_change = sim.rng.randf_range(dur.x, dur.y)
	if kind == K.STORM and old != K.STORM:
		sim.toast.emit("A thunderstorm is rolling in.", "bad")


func force(k: int, delay: float) -> void:
	forced = k
	_next_change = delay


## The wind this instant, gusts and all. `wind_speed` and `wind_dir` are the
## steady wind the forecast reports.
func wind_vec() -> Vector3:
	var d := wind_dir + _gust_turn * gust
	return Vector3(cos(d), 0.0, sin(d)) * (wind_speed * (1.0 + GUST_GAIN * gust))


func wind_mph() -> int:
	return int(round(wind_speed * 2.237))


func temp_f() -> int:
	return int(round(temp * 1.8 + 32.0))


func label() -> String:
	return NAMES[kind]
