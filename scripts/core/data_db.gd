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
var stories: Dictionary = {}    # the long golfer stories
var names: Dictionary = {}
var feed: Dictionary = {}


func _init() -> void:
	var c := _load("clubs")
	clubs = c.get("clubs", [])
	categories = c.get("categories", [])
	brands = c.get("brands", [])
	balls = _load("balls").get("balls", [])
	roles = _load("staff").get("roles", [])
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
	stories = _load("stories")
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
