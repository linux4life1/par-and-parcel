class_name DataDB
extends RefCounted
## Loads the JSON data files. Game content lives in res://data so it can be
## tuned or extended without touching code.

var clubs: Array = []
var categories: Array = []
var brands: Array = []
var balls: Array = []
var roles: Array = []
var skills: Array = []
var tournaments: Array = []
var scenarios: Array = []
var biomes: Array = []
var personalities: Array = []
var accomplishments: Array = []
var attributes: Array = []      # your golfer's attributes
var challenges: Array = []      # and the challenges that earn skill points
var sounds: Dictionary = {}     # sound effects and ambience
var music: Dictionary = {}      # the playlist
var lies: Dictionary = {}       # what each kind of ground does to a shot
var difficulty: Dictionary = {} # the difficulty slider's levels
var clubhouse: Dictionary = {}  # clubhouse levels and what each unlocks
var tutorial: Dictionary = {}   # the guided first round
var tips: Dictionary = {}       # for the loading screen
var stories: Dictionary = {}    # the long golfer stories
var setups: Array = []          # how a tournament can be set up
var landmarks: Dictionary = {}  # area effects of landmark objects
var accreditation: Dictionary = {}  # the design-score checklist
var home_radius := 45.0         # how far a stationed member looks for work, metres
var names: Dictionary = {}
var feed: Dictionary = {}


func _init() -> void:
	var c := _load("clubs")
	clubs = c.get("clubs", [])
	categories = c.get("categories", [])
	brands = c.get("brands", [])
	balls = _load("balls").get("balls", [])
	var staff := _load("staff")
	roles = staff.get("roles", [])
	home_radius = float(staff.get("home_radius", 45.0))
	skills = _load("skills").get("skills", [])
	tournaments = _load("tournaments").get("tournaments", [])
	scenarios = _load("scenarios").get("scenarios", [])
	biomes = _load("biomes").get("biomes", [])
	personalities = _load("personalities").get("personalities", [])
	accomplishments = _load("accomplishments").get("accomplishments", [])
	var golfer := _load("golfer")
	attributes = golfer.get("attributes", [])
	challenges = golfer.get("challenges", [])
	sounds = _load("sounds")
	music = _load("music")
	lies = _load("lies")
	difficulty = _load("difficulty")
	clubhouse = _load("clubhouse")
	tutorial = _load("tutorial")
	tips = _load("tips")
	stories = _load("stories")
	setups = _load("setups").get("setups", [])
	landmarks = _load("landmarks")
	accreditation = _load("accreditation")
	names = _load("names")
	feed = _load("feed")


func _load(file: String) -> Dictionary:
	var path := "res://data/%s.json" % file
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	push_error("Could not read " + path)
	return {}


static func find(list: Array, id: String) -> Dictionary:
	for item: Dictionary in list:
		if item.get("id", "") == id:
			return item
	return {}


func brand(id: String) -> Dictionary:
	var b := find(brands, id)
	return b if not b.is_empty() else brands[0]


func ball(id: String) -> Dictionary:
	var b := find(balls, id)
	return b if not b.is_empty() else balls[0]


func biome(id: String) -> Dictionary:
	var b := find(biomes, id)
	return b if not b.is_empty() else biomes[0]


func role(id: String) -> Dictionary:
	return find(roles, id)


func pick(key: String, rng: RandomNumberGenerator) -> String:
	var list: Array = names.get(key, [])
	if list.is_empty():
		return "?"
	return str(list[rng.randi() % list.size()])
