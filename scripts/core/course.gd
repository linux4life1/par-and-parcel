class_name Course
extends RefCounted
## The course as data: a tile grid with a height at every tile corner.
## World x = tile x * TILE, world z = tile y * TILE, y is up.

signal tiles_changed(rect: Rect2i)
signal heights_changed(rect: Rect2i)
signal holes_changed()
signal objects_changed()

var w: int
var h: int
var heights := PackedFloat32Array()   # (w + 1) * (h + 1) corner heights
var terrain := PackedByteArray()      # Defs.T per tile
var objects := PackedByteArray()      # Defs.O per tile
var closed := PackedByteArray()       # 1 where that object is switched off
var open_month := PackedByteArray()    # 1 if it was open at any point this month, so the bill still includes it
var wet := PackedFloat32Array()       # 0 dry .. 1 flooded
var health := PackedFloat32Array()    # 0 dead .. 1 perfect turf
var weeds := PackedFloat32Array()     # 0 .. 1
var pests := PackedFloat32Array()     # 0 .. 1
var litter := PackedFloat32Array()    # 0 clean .. 1 buried in cups and wrappers
var repair := PackedByteArray()       # 1 where a window is waiting on a board
var litter_rev := 0                   # bumps when a tile starts or stops looking littered
var mood := PackedFloat32Array()      # recent feelings on this tile: negative annoys, positive pleases; fades over a couple of days
var holes: Array[Hole] = []
var clubhouse := Vector2i.ZERO
var revision := 0                     # bumps on any edit that changes play
var biome_id := "lush"
var volcanoes: Array[Dictionary] = [] # {x, z, radius, crater_r, floor}
var locked := PackedByteArray()       # 1 where the land is not yours yet
var hot := PackedByteArray()          # 1 on the volcano: nothing can be built
var guard := false                    # when set, edits skip locked and hot tiles
var clear_cost := 0.0                 # extra cost run up by the last paint call
var _edit_tile := Callable()           # told before a tile changes, so a stroke can be undone
var _edit_height := Callable()
var _drop_history := Callable()        # an edit this history does not record
var green_decel := 1.0                # tournament setup: multiplies how fast a putt stops
var rough_power := 1.0                # tournament setup: multiplies the rough's share of a full swing
var _objects_dirty := false
var biome: Dictionary = {}            # what the land is; decides what each object looks like
var _solids: Solids = null
var _solids_all := true
var _solids_pending := PackedInt32Array()
var lights_rev := 0                   # bumps when anything that gives light is added or removed
var _light := PackedFloat32Array()    # per tile: how well lit it is after dark, 0 to 1
var _light_rev := -1

const PARCEL := 16                    # land is bought in squares this many tiles wide


func _init(width: int = 128, height: int = 128) -> void:
	w = width
	h = height
	heights.resize((w + 1) * (h + 1))
	heights.fill(0.0)
	terrain.resize(w * h)
	terrain.fill(Defs.T.ROUGH)
	objects.resize(w * h)
	objects.fill(0)
	closed.resize(w * h)
	closed.fill(0)
	open_month.resize(w * h)
	open_month.fill(0)
	wet.resize(w * h)
	wet.fill(0.2)
	health.resize(w * h)
	health.fill(1.0)
	weeds.resize(w * h)
	weeds.fill(0.0)
	pests.resize(w * h)
	pests.fill(0.0)
	litter.resize(w * h)
	litter.fill(0.0)
	repair.resize(w * h)
	repair.fill(0)
	mood.resize(w * h)
	mood.fill(0.0)
	locked.resize(w * h)
	locked.fill(0)
	hot.resize(w * h)
	hot.fill(0)
	clubhouse = Vector2i(w / 2, h - 8)


# ---------------------------------------------------------------- queries

## The kind of model an object is in this biome: an oak here is a palm in
## the desert. Collision shapes and models are both looked up by this name.
func kind_of(o: int) -> String:
	var over: Dictionary = biome.get("objects", {}).get(str(o), {})
	if over.has("mesh"):
		return str(over.mesh)
	match o:
		Defs.O.OAK:
			return "oak"
		Defs.O.PINE:
			return "pine"
		Defs.O.BUSH:
			return "bush"
		Defs.O.BOULDER:
			return "boulder"
	return "o%d" % o


## Tell the course an object changed on a tile (or, with no tile, that many
## did). Anything that writes to `objects` directly must call this.
func objects_touched(i: int = -1, lights: bool = true) -> void:
	if i < 0:
		_solids_all = true
	else:
		_solids_pending.append(i)
	if lights:
		lights_rev += 1


## How well lit a spot is after dark: 0 pitch dark, 1 as good as daylight.
## Floodlights, lamp posts and buildings all throw light (Defs.O_LIGHT).
func light_at(x: float, z: float) -> float:
	var i := index_at(x, z)
	if i < 0:
		return 0.0
	_ensure_light()
	return _light[i]


## True when a water tile sits within `radius` metres of the spot.
func water_near(x: float, z: float, radius: float) -> bool:
	var cx := int(floor(x / Defs.TILE))
	var cz := int(floor(z / Defs.TILE))
	var r := int(ceil(radius / Defs.TILE))
	var r2 := radius * radius
	for tz in range(maxi(cz - r, 0), mini(cz + r + 1, h)):
		for tx in range(maxi(cx - r, 0), mini(cx + r + 1, w)):
			var dx := (float(tx) + 0.5) * Defs.TILE - x
			var dz := (float(tz) + 0.5) * Defs.TILE - z
			if dx * dx + dz * dz > r2:
				continue
			if Defs.is_liquid(terrain[tz * w + tx]):
				return true
	return false


func _ensure_light() -> void:
	if _light_rev == lights_rev and _light.size() == w * h:
		return
	_light_rev = lights_rev
	_light.resize(w * h)
	_light.fill(0.0)
	for i in objects.size():
		if is_closed(i):
			continue
		var reach: float = Defs.O_LIGHT[objects[i]]
		if reach <= 0.0:
			continue
		var cx := i % w
		var cz := i / w
		var rt := int(ceil(reach / Defs.TILE))
		for tz in range(maxi(cz - rt, 0), mini(cz + rt + 1, h)):
			for tx in range(maxi(cx - rt, 0), mini(cx + rt + 1, w)):
				var dist := Vector2(tx - cx, tz - cz).length() * Defs.TILE
				var v := 1.0 - smoothstep(reach * 0.6, reach, dist)
				var j := tz * w + tx
				if v > _light[j]:
					_light[j] = v


## Everything solid a ball can hit, always up to date.
var solids: Solids:
	get:
		if _solids == null:
			_solids = Solids.new(self)
			_solids_all = true
		if _solids_all:
			_solids_all = false
			_solids_pending.clear()
			_solids.rebuild()
		elif not _solids_pending.is_empty():
			for i in _solids_pending:
				_solids.set_tile(i)
			_solids_pending.clear()
		return _solids


func size_m() -> Vector2:
	return Vector2(w * Defs.TILE, h * Defs.TILE)


func in_bounds(tx: int, ty: int) -> bool:
	return tx >= 0 and ty >= 0 and tx < w and ty < h


func tile_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / Defs.TILE)), int(floor(z / Defs.TILE)))


func index_at(x: float, z: float) -> int:
	var tx := int(floor(x / Defs.TILE))
	var ty := int(floor(z / Defs.TILE))
	if tx < 0 or ty < 0 or tx >= w or ty >= h:
		return -1
	return ty * w + tx


## A golfer felt something here. The mood map reads this back; it fades in Grounds.
func note_mood(x: float, z: float, delta: float) -> void:
	if is_zero_approx(delta):
		return
	var i := index_at(x, z)
	if i < 0:
		return
	mood[i] = clampf(mood[i] + delta, -24.0, 24.0)


func terrain_at(x: float, z: float) -> int:
	var i := index_at(x, z)
	return -1 if i < 0 else terrain[i]


func tile_center(tx: int, ty: int) -> Vector3:
	var x := (tx + 0.5) * Defs.TILE
	var z := (ty + 0.5) * Defs.TILE
	return Vector3(x, height_at(x, z), z)


func on_ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


func height_at(x: float, z: float) -> float:
	var fx := clampf(x / Defs.TILE, 0.0, w - 0.0001)
	var fz := clampf(z / Defs.TILE, 0.0, h - 0.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * (w + 1) + ix
	var a := lerpf(heights[i], heights[i + 1], tx)
	var b := lerpf(heights[i + w + 1], heights[i + w + 2], tx)
	return lerpf(a, b, tz)


## Slope as (dh/dx, dh/dz).
func gradient_at(x: float, z: float) -> Vector2:
	var fx := clampf(x / Defs.TILE, 0.0, w - 0.0001)
	var fz := clampf(z / Defs.TILE, 0.0, h - 0.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * (w + 1) + ix
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + w + 1]
	var h11 := heights[i + w + 2]
	var gx := ((h10 - h00) * (1.0 - tz) + (h11 - h01) * tz) / Defs.TILE
	var gz := ((h01 - h00) * (1.0 - tx) + (h11 - h10) * tx) / Defs.TILE
	return Vector2(gx, gz)


func normal_at(x: float, z: float) -> Vector3:
	var g := gradient_at(x, z)
	return Vector3(-g.x, 1.0, -g.y).normalized()


func corner(vx: int, vy: int) -> float:
	return heights[clampi(vy, 0, h) * (w + 1) + clampi(vx, 0, w)]


## True when a tile holds something a walker should go around.
func blocks_walk(tx: int, ty: int) -> bool:
	if not in_bounds(tx, ty):
		return true
	var i := ty * w + tx
	return Defs.is_liquid(terrain[i]) and objects[i] != Defs.O.BRIDGE


## False for land you do not own and for the slopes of a volcano.
func can_build(tx: int, ty: int) -> bool:
	if not in_bounds(tx, ty):
		return false
	var i := ty * w + tx
	return locked[i] == 0 and hot[i] == 0


## True when a world position is off the property: off the map, or on land
## that has not been bought.
func is_out(x: float, z: float) -> bool:
	var i := index_at(x, z)
	return i < 0 or locked[i] != 0


# ------------------------------------------------------------------- land

func parcel_of(tx: int, ty: int) -> Vector2i:
	return Vector2i(tx / PARCEL, ty / PARCEL)


func parcel_rect(p: Vector2i) -> Rect2i:
	return Rect2i(p.x * PARCEL, p.y * PARCEL, mini(PARCEL, w - p.x * PARCEL), mini(PARCEL, h - p.y * PARCEL))


func parcel_owned(p: Vector2i) -> bool:
	var r := parcel_rect(p)
	if r.size.x <= 0 or r.size.y <= 0:
		return true
	return locked[r.position.y * w + r.position.x] == 0


## A parcel can be bought if it is not owned and is not all volcano.
func parcel_for_sale(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x * PARCEL >= w or p.y * PARCEL >= h or parcel_owned(p):
		return false
	var r := parcel_rect(p)
	for ty in range(r.position.y, r.end.y):
		for tx in range(r.position.x, r.end.x):
			if hot[ty * w + tx] == 0:
				return true
	return false


func owned_parcels() -> int:
	var n := 0
	for py in range(0, h, PARCEL):
		for px in range(0, w, PARCEL):
			if locked[py * w + px] == 0:
				n += 1
	return n


func set_parcel(p: Vector2i, owned: bool) -> void:
	var r := parcel_rect(p)
	for ty in range(r.position.y, r.end.y):
		for tx in range(r.position.x, r.end.x):
			locked[ty * w + tx] = 0 if owned else 1
	revision += 1
	tiles_changed.emit(r)


func lock_all() -> void:
	locked.fill(1)


# ------------------------------------------------------------------ edits

## The build history watches edits. Empty until a game is running.
func watch_edits(on_tile: Callable, on_height: Callable, on_drop: Callable = Callable()) -> void:
	_edit_tile = on_tile
	_edit_height = on_height
	_drop_history = on_drop


func _note_tile(i: int) -> void:
	if _edit_tile.is_valid():
		_edit_tile.call(i)


func _note_height(vi: int) -> void:
	if _edit_height.is_valid():
		_edit_height.call(vi)


func _drop_unrecorded() -> void:
	if _drop_history.is_valid():
		_drop_history.call()


func set_terrain(tx: int, ty: int, t: int) -> bool:
	if not in_bounds(tx, ty):
		return false
	var i := ty * w + tx
	if terrain[i] == t:
		return false
	if objects[i] == Defs.O.CLUBHOUSE:
		return false
	if guard and (locked[i] != 0 or hot[i] != 0):
		return false
	_note_tile(i)
	clear_cost += Defs.T_CLEAR[terrain[i]]
	terrain[i] = t
	if objects[i] != 0 and t != Defs.T.ROUGH and t != Defs.T.DEEP_ROUGH and t != Defs.T.ASH:
		var gave_light: bool = Defs.O_LIGHT[objects[i]] > 0.0
		objects[i] = 0
		repair[i] = 0
		closed[i] = 0
		open_month[i] = 0
		_objects_dirty = true
		objects_touched(i, gave_light)
	if t == Defs.T.WATER:
		_level_water(tx, ty)
		wet[i] = 1.0
	elif t == Defs.T.STREAM:
		# A stream keeps the slope it was drawn on. It is not levelled into a pond.
		wet[i] = 1.0
	if Defs.T_GRASS[t]:
		health[i] = maxf(health[i], 0.9)
	else:
		weeds[i] = 0.0
		pests[i] = 0.0
	revision += 1
	return true


## Paint a round brush. Returns the tiles that actually changed.
func paint(cx: int, cy: int, radius: int, t: int) -> int:
	var n := 0
	clear_cost = 0.0
	var r2 := (radius + 0.4) * (radius + 0.4)
	for ty in range(cy - radius, cy + radius + 1):
		for tx in range(cx - radius, cx + radius + 1):
			var dx := tx - cx
			var dy := ty - cy
			if dx * dx + dy * dy <= r2 and set_terrain(tx, ty, t):
				n += 1
	if n > 0:
		var rect := Rect2i(cx - radius - 1, cy - radius - 1, radius * 2 + 3, radius * 2 + 3)
		tiles_changed.emit(rect)
		if t == Defs.T.WATER:
			heights_changed.emit(rect)
			for hole in holes:
				hole.snap_to_ground(self)
	if _objects_dirty:
		_objects_dirty = false
		objects_changed.emit()
	return n


## Tiles from a to b, one step at a time, both ends included.
static func tile_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x := a.x
	var y := a.y
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if b.x >= a.x else -1
	var sy := 1 if b.y >= a.y else -1
	var err := dx - dy
	while true:
		out.append(Vector2i(x, y))
		if x == b.x and y == b.y:
			break
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return out


## Height of the last tile this call accepted, and whether it accepted any.
## A drag passes the previous call's height back in as `follow`.
var stream_took := false
var stream_held := 0.0


## Paint a one-tile stream along these tiles, in the order they were dragged.
## `follow` is the height of the last tile already accepted on this drag, or
## a huge number when the drag has not accepted one yet. Every tile, including
## the first, has to be no higher than that. The ground is not flattened.
func lay_stream(tiles: Array[Vector2i], follow: float = 1.0e20) -> int:
	var n := 0
	clear_cost = 0.0
	var have := follow < 1.0e19
	var prev_h := follow
	stream_took = false
	stream_held = follow
	var minx := 100000
	var miny := 100000
	var maxx := -1
	var maxy := -1
	for tile in tiles:
		if not in_bounds(tile.x, tile.y):
			continue
		var h := tile_center(tile.x, tile.y).y
		if have and h > prev_h + 0.02:
			continue
		var i := tile.y * w + tile.x
		var already := terrain[i] == Defs.T.STREAM
		var changed := false
		if not already:
			changed = set_terrain(tile.x, tile.y, Defs.T.STREAM)
		if not already and not changed:
			continue
		if changed:
			n += 1
		have = true
		prev_h = h
		stream_took = true
		stream_held = h
		minx = mini(minx, tile.x)
		miny = mini(miny, tile.y)
		maxx = maxi(maxx, tile.x)
		maxy = maxi(maxy, tile.y)
	if n > 0:
		tiles_changed.emit(Rect2i(minx - 1, miny - 1, maxx - minx + 3, maxy - miny + 3))
	if _objects_dirty:
		_objects_dirty = false
		objects_changed.emit()
	return n


func _level_water(tx: int, ty: int) -> void:
	# Ponds stay flat: join the level of a neighbouring water tile if there is one.
	var level := INF
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var nx := tx + ox
			var ny := ty + oy
			if (ox != 0 or oy != 0) and in_bounds(nx, ny) and terrain[ny * w + nx] == Defs.T.WATER:
				level = minf(level, corner(nx, ny))
	if level == INF:
		level = minf(minf(corner(tx, ty), corner(tx + 1, ty)), minf(corner(tx, ty + 1), corner(tx + 1, ty + 1))) - 0.5
	for vy in [ty, ty + 1]:
		for vx in [tx, tx + 1]:
			var vi := int(vy) * (w + 1) + int(vx)
			_note_height(vi)
			heights[vi] = level


func set_object(tx: int, ty: int, o: int) -> bool:
	if not in_bounds(tx, ty):
		return false
	var i := ty * w + tx
	if objects[i] == o or objects[i] == Defs.O.CLUBHOUSE:
		return false
	if guard and (locked[i] != 0 or hot[i] != 0):
		return false
	# Only a bridge can stand in the water or a stream, and a bridge nowhere else.
	if o != 0 and Defs.is_liquid(terrain[i]) != (o == Defs.O.BRIDGE):
		return false
	_note_tile(i)
	var lights: bool = Defs.O_LIGHT[objects[i]] > 0.0 or Defs.O_LIGHT[o] > 0.0
	objects[i] = o
	repair[i] = 0
	closed[i] = 0
	open_month[i] = 1 if o != 0 else 0
	objects_touched(i, lights)
	revision += 1
	objects_changed.emit()
	return true


## A structure with a monthly bill can be switched off. The clubhouse,
## trees and anything else that costs nothing stay as they are. A bridge
## stays open: people are still walking it.
func can_switch(o: int) -> bool:
	if o == Defs.O.BRIDGE:
		return false
	return o > 0 and o < Defs.O_UPKEEP.size() and Defs.O_UPKEEP[o] > 0


## How many of this object are standing and open. A closed one does not
## count as built for the tutorial.
func count_open(o: int) -> int:
	var n := 0
	for i in objects.size():
		if objects[i] == o and not is_closed(i):
			n += 1
	return n


## True when the object on this tile has been switched off.
func is_closed(i: int) -> bool:
	return i >= 0 and i < closed.size() and i < objects.size() and objects[i] != 0 and closed[i] != 0


## Switch a structure off or back on. A closed one is still standing, but
## it costs nothing and nobody can use it.
func set_closed(tx: int, ty: int, off: bool) -> bool:
	if not in_bounds(tx, ty):
		return false
	var i := ty * w + tx
	var o := int(objects[i])
	if not can_switch(o):
		return false
	var bit := 1 if off else 0
	if int(closed[i]) == bit:
		return false
	_drop_unrecorded()
	closed[i] = bit
	if not off:
		open_month[i] = 1
	if Defs.O_LIGHT[o] > 0.0:
		lights_rev += 1
	revision += 1
	objects_changed.emit()
	return true


## The month's bill has been taken. A structure that is still closed starts
## the next month unpaid; one that is open is already on the next bill.
func settle_month() -> void:
	for i in open_month.size():
		open_month[i] = 0 if closed[i] != 0 else 1


## Raise or lower the ground with a soft round brush centred on a world point.
func sculpt(x: float, z: float, radius_m: float, delta: float) -> void:
	var r := int(ceil(radius_m / Defs.TILE))
	var cvx := int(round(x / Defs.TILE))
	var cvy := int(round(z / Defs.TILE))
	for vy in range(maxi(cvy - r, 0), mini(cvy + r, h) + 1):
		for vx in range(maxi(cvx - r, 0), mini(cvx + r, w) + 1):
			var d := Vector2(vx * Defs.TILE - x, vy * Defs.TILE - z).length()
			if d > radius_m:
				continue
			var fall := 0.5 + 0.5 * cos(PI * d / radius_m)
			if _corner_is_locked(vx, vy):
				continue
			var i := vy * (w + 1) + vx
			_note_height(i)
			heights[i] = clampf(heights[i] + delta * fall, -12.0, 40.0)
	_heights_edited(cvx, cvy, r)


## Relax the ground toward the average of its neighbours.
func smooth(x: float, z: float, radius_m: float, strength: float = 0.5) -> void:
	var r := int(ceil(radius_m / Defs.TILE))
	var cvx := int(round(x / Defs.TILE))
	var cvy := int(round(z / Defs.TILE))
	var updates := {}
	for vy in range(maxi(cvy - r, 0), mini(cvy + r, h) + 1):
		for vx in range(maxi(cvx - r, 0), mini(cvx + r, w) + 1):
			if Vector2(vx * Defs.TILE - x, vy * Defs.TILE - z).length() > radius_m:
				continue
			if _corner_is_locked(vx, vy):
				continue
			var avg := (corner(vx - 1, vy) + corner(vx + 1, vy) + corner(vx, vy - 1) + corner(vx, vy + 1)) * 0.25
			var i := vy * (w + 1) + vx
			updates[i] = lerpf(heights[i], avg, strength)
	for i: int in updates:
		_note_height(i)
		heights[i] = updates[i]
	_heights_edited(cvx, cvy, r)


## Pull the ground toward one level.
func flatten(x: float, z: float, radius_m: float, level: float, strength: float = 0.6) -> void:
	var r := int(ceil(radius_m / Defs.TILE))
	var cvx := int(round(x / Defs.TILE))
	var cvy := int(round(z / Defs.TILE))
	for vy in range(maxi(cvy - r, 0), mini(cvy + r, h) + 1):
		for vx in range(maxi(cvx - r, 0), mini(cvx + r, w) + 1):
			if Vector2(vx * Defs.TILE - x, vy * Defs.TILE - z).length() > radius_m:
				continue
			if _corner_is_locked(vx, vy):
				continue
			var i := vy * (w + 1) + vx
			_note_height(i)
			heights[i] = lerpf(heights[i], level, strength)
	_heights_edited(cvx, cvy, r)


func _corner_is_locked(vx: int, vy: int) -> bool:
	# Corners touching water stay put so ponds remain level. With the guard
	# on, so do corners on land that cannot be built on.
	for ty in [vy - 1, vy]:
		for tx in [vx - 1, vx]:
			if in_bounds(tx, ty):
				var i: int = ty * w + tx
				if Defs.is_liquid(terrain[i]):
					return true
				if guard and (locked[i] != 0 or hot[i] != 0):
					return true
	return false


func _heights_edited(cvx: int, cvy: int, r: int) -> void:
	revision += 1
	for hole in holes:
		hole.snap_to_ground(self)
	heights_changed.emit(Rect2i(cvx - r - 1, cvy - r - 1, r * 2 + 3, r * 2 + 3))


# ------------------------------------------------------------------ holes

func add_hole(tee: Vector3, pin: Vector3) -> Hole:
	var hole := Hole.new()
	hole.tee = on_ground(tee.x, tee.z)
	hole.pin = on_ground(pin.x, pin.z)
	hole.placed = hole.pin
	hole.pin_spot = 0
	hole.update_metrics(self)
	holes.append(hole)
	revision += 1
	holes_changed.emit()
	return hole


func remove_hole(i: int) -> void:
	if i < 0 or i >= holes.size():
		return
	holes.remove_at(i)
	revision += 1
	holes_changed.emit()


## Every comment tag on the course, summed across the holes, strongest first.
func comment_report() -> Array[Dictionary]:
	var sums := {}
	for hole in holes:
		for tag: String in hole.comments:
			sums[tag] = float(sums.get(tag, 0.0)) + float(hole.comments[tag])
	var rows: Array[Dictionary] = []
	for tag: String in sums:
		rows.append({"tag": str(tag), "total": float(sums[tag])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := absf(float(a.total))
		var db := absf(float(b.total))
		if not is_equal_approx(da, db):
			return da > db
		return str(a.tag) < str(b.tag))
	return rows


## Holes the public may play. Drafts are left out.
func open_count() -> int:
	var n := 0
	for hole in holes:
		if hole.open:
			n += 1
	return n


## Sim seconds a round takes, adding the recent average of each open hole
## that has been timed. Drafts are left out.
func round_time() -> float:
	var s := 0.0
	for hole in holes:
		if hole.open and not hole.play_times.is_empty():
			s += hole.average_time()
	return s


## Every open hole has been timed at least once.
func times_complete() -> bool:
	if open_count() == 0:
		return false
	for hole in holes:
		if hole.open and hole.play_times.is_empty():
			return false
	return true


## The open hole that is clearly the slowest, or -1 when nothing stands out.
func bottleneck() -> int:
	var best := -1
	var second := -1.0
	var top := -1.0
	for i in holes.size():
		var hole: Hole = holes[i]
		if not hole.open or hole.play_times.is_empty():
			continue
		var a := hole.average_time()
		if a > top:
			second = top
			top = a
			best = i
		elif a > second:
			second = a
	if best < 0 or second < 0.0 or top < second * 1.15:
		return -1
	return best


## Open or close a hole and tell the views, so the draft markers update.
func set_open(hole: Hole, on: bool) -> void:
	if hole.open == on:
		return
	hole.open = on
	holes_changed.emit()


## How quickly a rolling ball stops on this ground. A tournament can speed
## or slow the greens without touching any other surface.
func roll_decel(t: int) -> float:
	var d: float = Defs.T_DECEL[t]
	if Defs.is_green(t):
		d *= green_decel
	return d


## Where the day's cup sits. Spot 0 is the placed pin. Spot 1 is toward the
## tee, spot 2 is past the placed pin. A legal spot stays `edge` metres inside
## the green and no steeper than `slope_max` percent. The walk keeps the legal
## spot nearest the asked distance, or the middle when the front or the back
## has none. The first step whose centre is off the green ends the walk, so
## it cannot cross a gap and sit on a further lobe.
func day_cup(hole: Hole, spot: int, front_m: float = 6.0, back_m: float = 6.0, edge: float = 2.0, slope_max: float = 4.0) -> Vector3:
	var home := hole.placed if hole.placed.length_squared() > 0.01 else hole.pin
	if spot == 0:
		return on_ground(home.x, home.z)
	var away := Vector3(home.x - hole.tee.x, 0.0, home.z - hole.tee.z)
	if away.length_squared() < 0.01:
		away = Vector3(0.0, 0.0, 1.0)
	away = away.normalized()
	var dir := -away if spot == 1 else away
	var metres := front_m if spot == 1 else back_m
	var step := Defs.TILE * 0.5
	var best := home
	var best_d := -1.0
	var travelled := 0.0
	while travelled + 0.01 < metres:
		var next := minf(travelled + step, metres)
		var p := home + dir * next
		if not Defs.is_green(terrain_at(p.x, p.z)):
			break
		if _cup_clear(p.x, p.z, edge, slope_max):
			best = p
			best_d = next
		travelled = next
	if best_d < 0.0:
		return on_ground(home.x, home.z)
	return on_ground(best.x, best.z)


## True when a cup here is on the green, `edge` metres clear of the fringe,
## and no steeper than `slope_max` percent.
func _cup_clear(x: float, z: float, edge: float, slope_max: float) -> bool:
	if not Defs.is_green(terrain_at(x, z)):
		return false
	if edge > 0.0:
		for k in 8:
			var a := float(k) * TAU / 8.0
			if not Defs.is_green(terrain_at(x + cos(a) * edge, z + sin(a) * edge)):
				return false
	var grade := float(Slope.read(self, x, z)["percent"])
	return grade <= slope_max


## Move the pin off the centre line by metres, staying on the green.
## Returns where it was.
func tuck_pin(hole: Hole, metres: float) -> Vector3:
	var was := hole.pin
	if metres <= 0.05:
		return was
	var back := hole.tee - hole.pin
	back.y = 0.0
	if back.length_squared() < 0.01:
		back = Vector3(1, 0, 0)
	var side := Vector3(-back.z, 0.0, back.x).normalized()
	for i in 9:
		var dist := metres * (1.0 - float(i) / 8.0)
		var p := was + side * dist
		if Defs.is_green(terrain_at(p.x, p.z)):
			hole.pin = on_ground(p.x, p.z)
			revision += 1
			holes_changed.emit()
			return was
	return was


func total_par() -> int:
	var p := 0
	for hole in holes:
		p += hole.par
	return p


# ---------------------------------------------------------- save and load

func to_dict() -> Dictionary:
	var hs := []
	for hole in holes:
		hs.append(hole.to_dict())
	return {
		"w": w, "h": h,
		"heights": Marshalls.raw_to_base64(heights.to_byte_array()),
		"terrain": Marshalls.raw_to_base64(terrain),
		"objects": Marshalls.raw_to_base64(objects),
		"closed": Marshalls.raw_to_base64(closed),
		"open_month": Marshalls.raw_to_base64(open_month),
		"wet": Marshalls.raw_to_base64(wet.to_byte_array()),
		"health": Marshalls.raw_to_base64(health.to_byte_array()),
		"weeds": Marshalls.raw_to_base64(weeds.to_byte_array()),
		"pests": Marshalls.raw_to_base64(pests.to_byte_array()),
		"litter": Marshalls.raw_to_base64(litter.to_byte_array()),
		"repair": Marshalls.raw_to_base64(repair),
		"mood": Marshalls.raw_to_base64(mood.to_byte_array()),
		"clubhouse": [clubhouse.x, clubhouse.y],
		"holes": hs,
		"biome": biome_id,
		"volcanoes": volcanoes,
		"locked": Marshalls.raw_to_base64(locked),
		"hot": Marshalls.raw_to_base64(hot),
		"green_decel": green_decel,
		"rough_power": rough_power,
	}


static func from_dict(d: Dictionary) -> Course:
	var c := Course.new(int(d.w), int(d.h))
	c.heights = Marshalls.base64_to_raw(d.heights).to_float32_array()
	c.terrain = Marshalls.base64_to_raw(d.terrain)
	c.objects = Marshalls.base64_to_raw(d.objects)
	if d.has("closed"):
		c.closed = Marshalls.base64_to_raw(d.closed)
	if c.closed.size() != c.w * c.h:
		c.closed = PackedByteArray()
		c.closed.resize(c.w * c.h)
		c.closed.fill(0)
	if d.has("open_month"):
		c.open_month = Marshalls.base64_to_raw(d.open_month)
	if c.open_month.size() != c.w * c.h:
		c.open_month = PackedByteArray()
		c.open_month.resize(c.w * c.h)
		for i in c.open_month.size():
			c.open_month[i] = 0 if c.closed[i] != 0 else 1
	c.wet = Marshalls.base64_to_raw(d.wet).to_float32_array()
	c.health = Marshalls.base64_to_raw(d.health).to_float32_array()
	c.weeds = Marshalls.base64_to_raw(d.weeds).to_float32_array()
	c.pests = Marshalls.base64_to_raw(d.pests).to_float32_array()
	if d.has("litter"):
		c.litter = Marshalls.base64_to_raw(d.litter).to_float32_array()
	if c.litter.size() != c.w * c.h:
		c.litter = PackedFloat32Array()
		c.litter.resize(c.w * c.h)
		c.litter.fill(0.0)
	if d.has("repair"):
		c.repair = Marshalls.base64_to_raw(d.repair)
	if c.repair.size() != c.w * c.h:
		c.repair = PackedByteArray()
		c.repair.resize(c.w * c.h)
		c.repair.fill(0)
	if d.has("mood"):
		c.mood = Marshalls.base64_to_raw(d.mood).to_float32_array()
	if c.mood.size() != c.w * c.h:
		c.mood = PackedFloat32Array()
		c.mood.resize(c.w * c.h)
		c.mood.fill(0.0)
	c.clubhouse = Vector2i(int(d.clubhouse[0]), int(d.clubhouse[1]))
	c.biome_id = str(d.get("biome", "lush"))
	for v: Dictionary in d.get("volcanoes", []):
		c.volcanoes.append(v)
	if d.has("locked"):
		c.locked = Marshalls.base64_to_raw(d.locked)
		c.hot = Marshalls.base64_to_raw(d.hot)
	c.green_decel = float(d.get("green_decel", 1.0))
	c.rough_power = float(d.get("rough_power", 1.0))
	c.guard = true
	for hd: Dictionary in d.holes:
		var hole := Hole.from_dict(hd)
		c.holes.append(hole)
		# The ground is loaded, so par can follow the fairway. A save that
		# already stored par only shifts the scorecard if the ground disagrees.
		hole.update_metrics(c)
	return c
