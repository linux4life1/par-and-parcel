class_name Defs
extends RefCounted
## Shared constants and lookup tables. Everything is in metres and seconds.

const TITLE := "Par & Parcel"
const TILE := 5.0                 # metres per tile
const DAY_SECONDS := 15.0         # sim seconds per calendar day
const DAYS_PER_MONTH := 28
const MONTHS_PER_YEAR := 8        # the golf season: winter is skipped
const DAYS_PER_YEAR := 224
const MONTH_NAMES: Array[String] = ["March", "April", "May", "June", "July", "August", "September", "October"]
const YARDS := 1.09361
## The clock. A full day and night takes this long at normal speed. It runs
## apart from the calendar, which moves much faster, as in most park and
## city builders: the date says what season it is, the clock what the light
## is doing.
const CLOCK_DAY_SECONDS := 300.0
const SUNRISE := 5.5              # hours
const SUNSET := 20.5
const TWILIGHT := 1.0             # hours dusk and dawn each last

enum T { ROUGH, FAIRWAY, GREEN, TEE, BUNKER, WATER, DEEP_ROUGH, PATH, ROCK, ASH, FIRM, FAST_GREEN }
enum O {
	NONE, OAK, PINE, BUSH, FLOWERS, BENCH, DRINK_STAND, RESTROOM, CLUBHOUSE,
	SNACK_BAR, BALL_WASHER, BOULDER, BRIDGE, CART_BARN, PUTTING_GREEN, DRIVING_RANGE,
	FOUNTAIN, HOME_SITE, HOUSE, LANDMARK, TENNIS, HOTEL, MARINA, AIRSTRIP,
	FLOODLIGHT, LAMP, VENDING, BAR, BIN,
}

# WATER is the liquid hazard of the biome: water in most places, lava on the
# volcano. ROCK and ASH are left behind by eruptions and cannot be painted.
# FIRM and FAST_GREEN are paints: a firmer fairway, and a quicker green.
const T_NAMES: Array[String] = ["Rough", "Fairway", "Green", "Tee box", "Bunker", "Water", "Deep rough", "Cart path", "Rock", "Scorched ground", "Firm fairway", "Fast green"]
const T_COST: Array[int] = [1, 3, 15, 10, 5, 8, 1, 4, 0, 0, 4, 22]
## Extra cost per tile to build over what is already there.
const T_CLEAR: Array[int] = [0, 0, 0, 0, 0, 4, 0, 0, 12, 2, 0, 0]
## Rolling deceleration in m/s^2. Firm ground and a fast green stop the ball later.
const T_DECEL: Array[float] = [5.0, 2.0, 0.6, 1.8, 12.0, 0.0, 9.0, 1.0, 1.4, 8.0, 1.35, 0.38]
## Share of vertical speed kept on a bounce.
const T_BOUNCE: Array[float] = [0.25, 0.42, 0.36, 0.40, 0.05, 0.0, 0.14, 0.65, 0.68, 0.08, 0.48, 0.32]
## Share of forward speed kept on a bounce.
const T_KEEP: Array[float] = [0.50, 0.72, 0.62, 0.70, 0.15, 0.0, 0.35, 0.85, 0.8, 0.25, 0.80, 0.72]
## How well a spinning ball grips the surface: a green bites, a path does not.
const T_GRIP: Array[float] = [0.4, 0.7, 1.0, 0.7, 0.1, 0.0, 0.25, 0.3, 0.25, 0.2, 0.55, 1.05]
## The terrain's key in data/lies.json.
const T_KEYS: Array[String] = ["rough", "fairway", "green", "tee", "bunker", "water", "deep_rough", "path", "rock", "ash", "firm", "fast_green"]
## Shot power and spread multipliers for a ball lying on this terrain.
const T_LIE_POWER: Array[float] = [0.88, 1.0, 1.0, 1.0, 0.72, 0.0, 0.68, 0.95, 0.62, 0.8, 1.0, 1.0]
const T_LIE_SPREAD: Array[float] = [1.4, 1.0, 1.0, 0.9, 1.7, 1.0, 2.1, 1.1, 2.3, 1.5, 0.95, 1.0]
## How unattractive the terrain is as a route for the golfer AI.
const T_ROUTE: Array[float] = [1.25, 1.0, 1.0, 1.0, 1.9, 2.6, 1.7, 1.1, 2.2, 1.5, 1.0, 1.0]
const T_GRASS: Array[bool] = [true, true, true, true, false, false, true, false, false, false, true, true]
## Turf health lost per second without care.
const T_WEAR: Array[float] = [0.00003, 0.00012, 0.00025, 0.0002, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.00008, 0.00032]
## Drying speed multiplier.
const T_DRY: Array[float] = [1.0, 1.1, 1.35, 1.2, 1.8, 0.0, 0.8, 2.0, 2.0, 1.4, 1.25, 1.45]
## Weed pressure multiplier.
const T_WEED: Array[float] = [1.0, 0.8, 0.5, 0.6, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.45, 0.35]
## How much greenkeepers care about this terrain.
const T_CARE: Array[float] = [0.35, 1.5, 3.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.6, 3.4]
## Effort to walk across, for path finding. Negative means impassable.
const T_WALK: Array[float] = [1.1, 1.0, 2.0, 1.2, 2.2, -1.0, 1.6, 0.45, 2.2, 1.4, 0.95, 2.0]

const O_NAMES: Array[String] = [
	"None", "Oak tree", "Pine tree", "Bush", "Flower bed", "Bench", "Drink stand", "Restroom", "Clubhouse",
	"Snack bar", "Ball washer", "Boulder", "Bridge", "Cart barn", "Putting green", "Driving range",
	"Fountain", "Home site", "House", "Landmark", "Tennis courts", "Resort hotel", "Marina", "Airstrip",
	"Floodlight", "Lamp post", "Vending machine", "Bar", "Litter bin",
]
const O_COST: Array[int] = [0, 30, 25, 10, 20, 40, 400, 500, 0, 700, 60, 15, 120, 1500, 900, 2000, 350, 400, 0, 2500, 3000, 12000, 8000, 20000, 450, 60, 150, 1200, 80]
const O_UPKEEP: Array[int] = [0, 0, 0, 0, 1, 0, 25, 20, 0, 40, 2, 0, 2, 60, 30, 70, 8, 0, 0, 25, 60, 200, 120, 300, 14, 2, 4, 45, 3]
const O_SCENERY: Array[float] = [0.0, 1.0, 0.8, 0.5, 1.6, 0.4, 0.0, 0.0, 0.0, 0.0, 0.2, 0.6, 0.5, 0.0, 0.5, 0.0, 3.0, 0.0, -0.4, 6.0, 0.3, 0.0, 1.5, -0.5, -0.2, 0.3, -0.1, 0.2, 0.1]
## Buildings: golfers walk around them, and they survive lava bombs.
const O_BUILDING: Array[bool] = [
	false, false, false, false, false, false, true, true, true,
	true, false, false, false, true, false, true, false, false, true, true,
	false, true, true, false, false, false, false, true, false,
]
## Holes the course needs before a resort building can go up (0 for none).
const O_MIN_HOLES: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 10, 6, 10, 0, 0, 0, 0, 0]
## How far each object throws light after dark, in metres (0 for none).
const O_LIGHT: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 9.0, 9.0, 26.0, 11.0, 0.0, 0.0, 0.0, 10.0, 0.0, 14.0, 0.0, 0.0, 7.0, 0.0, 16.0, 22.0, 10.0, 0.0, 44.0, 15.0, 3.0, 10.0, 0.0]
## Model kinds that are plants and rocks: each one stands a little off the
## middle of its tile, at its own size and turn (see plant_offset and friends).
const PLANT_KINDS: Array[String] = ["oak", "pine", "bush", "birch", "scots", "gorse", "palm", "cactus", "scrub", "deadtree", "fern",
	"boulder", "boulder_red", "boulder_black"]


static func _plant_r(i: int, k: float, m: float) -> float:
	return fposmod(sin(i * k) * m, 1.0)


## Where a plant stands relative to the middle of its tile. The models and
## the ball's collisions both use these, so what you see is what you hit.
static func plant_offset(i: int) -> Vector2:
	return Vector2((_plant_r(i, 12.9898, 43758.5453) - 0.5) * 2.4, (_plant_r(i, 78.233, 12543.123) - 0.5) * 2.4)


## A plant's size: x is its width, y its height, both around 1.
static func plant_scale(i: int) -> Vector2:
	var s := 0.78 + _plant_r(i, 12.9898, 43758.5453) * 0.5
	return Vector2(s, s * (0.88 + _plant_r(i, 39.425, 24634.633) * 0.3))


static func plant_yaw(i: int) -> float:
	return _plant_r(i, 78.233, 12543.123) * TAU


## Each plant its own shade.
static func plant_tint(i: int) -> Color:
	return Color(0.86 + _plant_r(i, 12.9898, 43758.5453) * 0.26, 0.9 + _plant_r(i, 39.425, 24634.633) * 0.2, 0.84 + _plant_r(i, 78.233, 12543.123) * 0.22)


## Houses face one of four ways.
static func house_turns(i: int) -> int:
	return int(_plant_r(i, 12.9898, 43758.5453) * 4.0)


static func is_tree(o: int) -> bool:
	return o == O.OAK or o == O.PINE


static func is_fairway(t: int) -> bool:
	return t == T.FAIRWAY or t == T.FIRM


static func is_green(t: int) -> bool:
	return t == T.GREEN or t == T.FAST_GREEN


## Fairway, green or tee: the short grass a ball can spin back on.
static func is_short(t: int) -> bool:
	return is_fairway(t) or is_green(t) or t == T.TEE


static func money(v: float) -> String:
	var n := int(round(absf(v)))
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if v < -0.5 else "$") + s + out


static func yards(m: float) -> int:
	return int(round(m * YARDS))


static func date_parts(day_index: int) -> Dictionary:
	var year := day_index / DAYS_PER_YEAR + 1
	var doy := day_index % DAYS_PER_YEAR
	return {"year": year, "month": doy / DAYS_PER_MONTH, "day": doy % DAYS_PER_MONTH + 1}


## The seasons as the course shows them. The year runs March to October:
## spring freshness fades through April, and from September the broad-leaved
## trees turn, all of them by the middle of October.
static func spring_phase(day_index: int) -> float:
	var d := day_index % DAYS_PER_YEAR
	return 1.0 - clampf(d / 45.0, 0.0, 1.0)


static func autumn_phase(day_index: int) -> float:
	var d := day_index % DAYS_PER_YEAR
	return clampf((d - 6 * DAYS_PER_MONTH) / 42.0, 0.0, 1.0)


## How the grass's colour shifts with the season: lusher in spring, a
## little tired and golden in autumn. Multiplies the summer colour.
static func season_grass(day_index: int) -> Color:
	var sp := spring_phase(day_index)
	var au := autumn_phase(day_index)
	var c := Color(1.0, 1.0, 1.0)
	c = c.lerp(Color(0.95, 1.04, 0.88), sp)
	c = c.lerp(Color(1.02, 0.97, 0.86), au)
	return c


## Share of the reported wind that blows at a height above the ground, in
## metres. The forecast is the wind at ten metres: it is half that in the
## grass and a third stronger at the top of a drive.
static func wind_at(height: float) -> float:
	return clampf(pow(maxf(height, 0.3) / 10.0, 0.22), 0.45, 1.4)


## How dark it is at an hour of the day: 0 in daylight, 1 at night, in
## between through dusk and dawn.
static func darkness(hours: float) -> float:
	var half := TWILIGHT * 0.5
	if hours <= SUNRISE - half or hours >= SUNSET + half:
		return 1.0
	if hours < SUNRISE + half:
		return 1.0 - smoothstep(SUNRISE - half, SUNRISE + half, hours)
	if hours > SUNSET - half:
		return smoothstep(SUNSET - half, SUNSET + half, hours)
	return 0.0


## How long a stretch of simulation is on the course clock. A full day and
## night is CLOCK_DAY_SECONDS, so pace is told in those hours and minutes.
const ROUND_LONG := 5.0 * CLOCK_DAY_SECONDS / 24.0


static func pace_minutes(seconds: float) -> int:
	return maxi(int(round(seconds * 24.0 * 60.0 / CLOCK_DAY_SECONDS)), 0)


## "12 min", "1 h", "1 h 12 min". Compact is for the scorecard column: "12m", "1h", "1h12".
static func pace_text(seconds: float, compact: bool = false) -> String:
	var mins := pace_minutes(seconds)
	var h := mins / 60
	var m := mins % 60
	if compact:
		if h == 0:
			return "%dm" % m
		if m == 0:
			return "%dh" % h
		return "%dh%02d" % [h, m]
	if h == 0:
		return "%d min" % m
	if m == 0:
		return "%d h" % h
	return "%d h %d min" % [h, m]


## "3:40 PM"
static func clock_text(hours: float) -> String:
	var total := int(floor(fposmod(hours, 24.0) * 60.0))
	var h := total / 60
	var m := (total % 60) / 10 * 10       # ten-minute steps read more calmly
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, "AM" if h < 12 else "PM"]


## "March, Year 1"
static func month_text(day_index: int) -> String:
	var p := date_parts(day_index)
	return "%s, Year %d" % [MONTH_NAMES[p.month], p.year]


static func date_text(day_index: int) -> String:
	var d := date_parts(day_index)
	return "%s %d, Year %d" % [MONTH_NAMES[d.month], d.day, d.year]
