class_name Nav
extends RefCounted
## Path finding for people on the course. Cart paths are quick, greens and
## bunkers are avoided, and the hazard is impassable unless bridged.

const MAX_EXPAND := 16000
const MAX_CACHE := 500

var course: Course
var _rev := -1
var _cost := PackedFloat32Array()     # effort per tile, or -1 if impassable
var _g := PackedFloat32Array()
var _from := PackedInt32Array()
var _closed := PackedByteArray()
var _cache := {}
var _hk := PackedFloat32Array()
var _hv := PackedInt32Array()
var _hn := 0
var searches := 0


func _init(c: Course) -> void:
	course = c


func _refresh() -> void:
	if _rev == course.revision:
		return
	_rev = course.revision
	_cache.clear()
	var n := course.w * course.h
	_cost.resize(n)
	_g.resize(n)
	_from.resize(n)
	_closed.resize(n)
	for i in n:
		var c: float = Defs.T_WALK[course.terrain[i]]
		var o := course.objects[i]
		if o == Defs.O.BRIDGE:
			c = 0.45
		elif Defs.O_BUILDING[o]:
			c = 6.0
		elif o == Defs.O.OAK or o == Defs.O.PINE or o == Defs.O.BOULDER:
			c += 0.6
		if c > 0.0 and course.locked[i] != 0:
			c *= 2.0
		_cost[i] = c
	if _hk.size() < 512:
		_hk.resize(512)
		_hv.resize(512)


func passable(x: float, z: float) -> bool:
	_refresh()
	var i := course.index_at(x, z)
	return i >= 0 and _cost[i] > 0.0


## How fast someone moves across the ground at a point, relative to normal.
func speed_at(x: float, z: float, cart: bool) -> float:
	var i := course.index_at(x, z)
	if i < 0:
		return 1.0
	var on_path := course.terrain[i] == Defs.T.PATH or course.objects[i] == Defs.O.BRIDGE
	if cart:
		return 2.4 if on_path else 1.25
	return 1.35 if on_path else 1.0


## True if a straight walk between two points crosses nothing impassable.
func clear_line(a: Vector3, b: Vector3) -> bool:
	_refresh()
	var d := Vector2(b.x - a.x, b.z - a.z)
	var steps := int(d.length() / 2.5) + 1
	for s in steps + 1:
		var t := float(s) / steps
		var i := course.index_at(a.x + d.x * t, a.z + d.y * t)
		if i >= 0 and _cost[i] < 0.0:
			return false
	return true


## Waypoints from one place to another, ending exactly at the destination.
## With `prefer_paths` the route is always searched, so cart paths get used.
func path(from: Vector3, to: Vector3, prefer_paths: bool = false) -> PackedVector2Array:
	_refresh()
	var out := PackedVector2Array()
	var w := course.w
	var a := course.index_at(from.x, from.z)
	var b := course.index_at(to.x, to.z)
	if a < 0 or b < 0 or a == b:
		out.append(Vector2(to.x, to.z))
		return out
	if not prefer_paths and clear_line(from, to):
		out.append(Vector2(to.x, to.z))
		return out
	var key := a * 65536 + b if prefer_paths else -1
	if key >= 0 and _cache.has(key):
		out = (_cache[key] as PackedVector2Array).duplicate()
		out.append(Vector2(to.x, to.z))
		return out
	var tiles := _search(a, b)
	if tiles.is_empty():
		out.append(Vector2(to.x, to.z))
		return out
	# tile centres, dropping the start and any point on a straight run
	var last_dir := Vector2i(99, 99)
	for k in range(1, tiles.size() - 1):
		var cur := tiles[k]
		var nxt := tiles[k + 1]
		var dir := Vector2i(nxt % w - cur % w, nxt / w - cur / w)
		if dir != last_dir:
			out.append(Vector2((cur % w + 0.5) * Defs.TILE, (cur / w + 0.5) * Defs.TILE))
			last_dir = dir
	if key >= 0:
		if _cache.size() > MAX_CACHE:
			_cache.clear()
		_cache[key] = out.duplicate()
	out.append(Vector2(to.x, to.z))
	return out


## A* over the tile grid. Returns tile indices from start to goal, or empty.
func _search(start: int, goal: int) -> PackedInt32Array:
	searches += 1
	var w := course.w
	var h := course.h
	_g.fill(INF)
	_closed.fill(0)
	_hn = 0
	var gx := goal % w
	var gy := goal / w
	_g[start] = 0.0
	_from[start] = -1
	_push(0.0, start)
	var expanded := 0
	var found := false
	while _hn > 0:
		var cur := _pop()
		if cur == goal:
			found = true
			break
		if _closed[cur] != 0:
			continue      # an older, worse entry for a tile already dealt with
		_closed[cur] = 1
		expanded += 1
		if expanded > MAX_EXPAND:
			break
		var cx := cur % w
		var cy := cur / w
		var gc := _g[cur]
		var cc := maxf(_cost[cur], 0.45)
		for oy in range(-1, 2):
			var ny := cy + oy
			if ny < 0 or ny >= h:
				continue
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var nx := cx + ox
				if nx < 0 or nx >= w:
					continue
				var ni := ny * w + nx
				if _closed[ni] != 0:
					continue
				var nc := _cost[ni]
				if nc < 0.0 and ni != goal:
					continue
				if ox != 0 and oy != 0:
					# no squeezing diagonally between two blocked tiles
					if _cost[cy * w + nx] < 0.0 or _cost[ny * w + cx] < 0.0:
						continue
				var step := (cc + maxf(nc, 0.45)) * 0.5 * (1.41421 if (ox != 0 and oy != 0) else 1.0)
				var ng := gc + step
				if ng < _g[ni]:
					_g[ni] = ng
					_from[ni] = cur
					var dx := absi(nx - gx)
					var dy := absi(ny - gy)
					var est := (maxi(dx, dy) + 0.41421 * mini(dx, dy)) * 0.72
					_push(ng + est, ni)
	var out := PackedInt32Array()
	if not found:
		return out
	var k := goal
	while k >= 0:
		out.append(k)
		k = _from[k]
	out.reverse()
	return out


func _push(k: float, v: int) -> void:
	var i := _hn
	_hn += 1
	if _hn > _hk.size():
		_hk.resize(_hn * 2)
		_hv.resize(_hn * 2)
	while i > 0:
		var p := (i - 1) >> 1
		if _hk[p] <= k:
			break
		_hk[i] = _hk[p]
		_hv[i] = _hv[p]
		i = p
	_hk[i] = k
	_hv[i] = v


func _pop() -> int:
	var top := _hv[0]
	_hn -= 1
	if _hn > 0:
		var k := _hk[_hn]
		var v := _hv[_hn]
		var i := 0
		while true:
			var c := i * 2 + 1
			if c >= _hn:
				break
			if c + 1 < _hn and _hk[c + 1] < _hk[c]:
				c += 1
			if _hk[c] >= k:
				break
			_hk[i] = _hk[c]
			_hv[i] = _hv[c]
			i = c
		_hk[i] = k
		_hv[i] = v
	return top


## Move anything that has pos, facing, walking, route, route_i and
## route_goal toward a target along a found path. True on arrival.
static func advance(m: Variant, target: Vector3, dt: float, sim: Sim, speed: float, cart: bool = false, prefer_paths: bool = false) -> bool:
	var goal: Vector3 = m.route_goal
	var route: PackedVector2Array = m.route
	if route.is_empty() or Vector2(goal.x - target.x, goal.z - target.z).length_squared() > 2.25:
		route = sim.nav.path(m.pos, target, prefer_paths)
		m.route = route
		m.route_i = 0
		m.route_goal = target
	var i: int = m.route_i
	var pos: Vector3 = m.pos
	var budget := speed * dt * sim.nav.speed_at(pos.x, pos.z, cart)
	while i < route.size() and budget > 0.0:
		var wp := route[i]
		var dx := wp.x - pos.x
		var dz := wp.y - pos.z
		var d := sqrt(dx * dx + dz * dz)
		if d <= budget or d < 0.05:
			pos.x = wp.x
			pos.z = wp.y
			budget -= d
			i += 1
		else:
			m.facing = atan2(dz, dx)
			pos.x += dx / d * budget
			pos.z += dz / d * budget
			budget = 0.0
	pos.y = sim.course.height_at(pos.x, pos.z)
	m.pos = pos
	m.route_i = i
	var arrived := i >= route.size()
	m.walking = not arrived
	if arrived:
		m.route = PackedVector2Array()
	return arrived
