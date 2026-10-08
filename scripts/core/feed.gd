class_name Feed
extends RefCounted
## "Birdie", the course's social feed. Golfers post about what happens to
## them, which doubles as a running report on how the course is doing.

signal posted(post: Dictionary)

const COOLDOWN := {
	"water_ball": 50.0, "stream_ball": 50.0, "weeds": 45.0, "pests": 45.0, "wet": 45.0, "wait": 40.0, "no_pay": 45.0, "tip": 70.0, "lucky_bounce": 40.0, "night_golf": 80.0, "too_dark": 70.0,
	"birdie": 35.0, "eagle": 5.0, "blowup": 45.0, "scenery": 50.0, "hit_victim": 4.0, "hit_hitter": 10.0,
	"greens_bad": 50.0, "greens_good": 80.0, "thirsty": 50.0, "drink": 90.0, "rain": 60.0, "storm": 20.0,
	"lava_ball": 40.0, "lava_bomb": 6.0, "review_good": 22.0, "window": 30.0, "animal": 60.0, "tantrum_seen": 20.0,
	"snack": 90.0, "cart_drinks": 90.0, "restroom": 50.0, "hungry": 50.0, "member_join": 25.0, "member_up": 10.0, "story_done": 15.0, "review_bad": 22.0, "review_mid": 45.0, "celebrity_spotted": 15.0, "arrive": 70.0, "staff_hit": 20.0,
}
const MOOD := {
	"hole_in_one": 1, "eagle": 1, "birdie": 1, "tip": 1, "lucky_bounce": 1, "night_golf": 1, "scenery": 1, "drink": 1, "review_good": 1, "greens_good": 1,
	"celebrity_happy": 1, "news_good": 1, "tournament_pro_good": 1, "member_join": 1, "member_up": 1, "story_done": 1,
	"home": 1, "top100": 1, "top18": 1, "snack": 1, "cart_drinks": 1, "vip_happy": 1, "animal": 1, "celebrity_home": 1,
	"blowup": -1, "hit_victim": -1, "stream_ball": -1, "weeds": -1, "pests": -1, "wet": -1, "wait": -1, "no_pay": -1, "too_dark": -1,
	"thirsty": -1, "review_bad": -1, "celebrity_angry": -1, "celebrity_hit": -1, "greens_bad": -1, "news_bad": -1,
	"storm": -1, "tournament_pro_bad": -1, "staff_hit": -1, "lava_bomb": -1, "eruption": -1, "member_quit": -1,
	"tantrum_toss": -1, "tantrum_punch": -1, "tantrum_seen": -1, "window": -1, "restroom": -1, "hungry": -1, "vip_angry": -1,
}

var sim: Sim
var posts: Array[Dictionary] = []
var _last := {}


func _init(s: Sim) -> void:
	sim = s


## A line written by a story: no dice, the caller settles the likes.
func post(text: String, g: Golfer, by_name: String, by_handle: String, mood: int, likes: int, kind: String = "story") -> void:
	var p := {
		"name": by_name, "handle": by_handle, "text": text, "kind": kind, "day": sim.day(),
		"mood": mood, "likes": likes, "color": Color(0.85, 0.72, 0.45), "golfer_id": 0, "verified": false,
	}
	if g != null:
		p.color = g.shirt
		p.golfer_id = g.id
	posts.append(p)
	if posts.size() > 80:
		posts.pop_front()
	posted.emit(p)


## Post a line of the given kind, written by a golfer or a named account.
func say(kind: String, g: Golfer, vars: Dictionary = {}, force: bool = false, by_name: String = "", by_handle: String = "") -> void:
	if not force:
		var cd: float = COOLDOWN.get(kind, 8.0)
		if sim.time - float(_last.get(kind, -999.0)) < cd:
			return
	var lines: Array = sim.db.feed.get(kind, [])
	if lines.is_empty():
		return
	_last[kind] = sim.time
	var text := str(lines[sim.rng.randi() % lines.size()])
	var v := vars.duplicate()
	v["course"] = sim.course_name
	text = text.format(v)
	var post := {
		"name": by_name, "handle": by_handle, "text": text, "kind": kind, "day": sim.day(),
		"mood": int(MOOD.get(kind, 0)), "likes": sim.rng.randi_range(0, 40), "color": Color(0.55, 0.75, 0.6),
		"golfer_id": 0, "verified": false,
	}
	if g != null:
		post.name = g.name
		post.handle = g.handle
		post.color = g.shirt
		post.golfer_id = g.id
		if g.kind == "celebrity" or g.kind == "pro":
			post.verified = true
			post.likes = sim.rng.randi_range(4000, 90000)
	elif by_name == "":
		post.name = sim.course_name
		post.handle = sim.course_name.replace(" ", "")
		post.verified = true
		post.color = Color(0.3, 0.7, 0.4)
	posts.append(post)
	if posts.size() > 80:
		posts.pop_front()
	posted.emit(post)
