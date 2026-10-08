class_name TerrainView
extends Node3D
## Draws the course as chunked meshes. Geometry only changes when the land is
## reshaped; everything else goes through a data texture read by the shader.

const CHUNK := 16

var course: Course
var sim: Sim
var material := ShaderMaterial.new()
var _chunks := {}
var _dirty := {}
var _bytes := PackedByteArray()
var _img: Image
var _tex: ImageTexture
var _row := 0
var _upload := false
var _indices := PackedInt32Array()
var _skirt: MeshInstance3D
var _base: MeshInstance3D
var _bare := PackedByteArray()        # 1 where something stands, so no grass grows
var _height_img: Image
var _height_tex: ImageTexture
var _heights_stale := false
var _shown_overlay := 0
var palette := PackedVector3Array()   # linear colours, in PALETTE_KEYS order
## Things big enough to cover the tiles around them.
const WIDE: Array[int] = [Defs.O.CLUBHOUSE, Defs.O.HOTEL, Defs.O.DRIVING_RANGE, Defs.O.MARINA, Defs.O.CART_BARN,
	Defs.O.PUTTING_GREEN, Defs.O.TENNIS, Defs.O.AIRSTRIP, Defs.O.LANDMARK]
const PLANTS: Array[int] = [Defs.O.OAK, Defs.O.PINE, Defs.O.BUSH, Defs.O.BOULDER]


func _init() -> void:
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("noise_tex", Surfaces.noise())
	for z in CHUNK:
		for x in CHUNK:
			var a := z * (CHUNK + 1) + x
			var b := a + 1
			var c := a + CHUNK + 1
			var d := c + 1
			_indices.append_array([a, b, d, a, d, c])


func bind(c: Course) -> void:
	if course != null:
		course.tiles_changed.disconnect(_on_tiles)
		course.heights_changed.disconnect(_on_heights)
		course.objects_changed.disconnect(_on_objects)
	for child in get_children():
		child.queue_free()
	_chunks.clear()
	_dirty.clear()
	course = c
	c.tiles_changed.connect(_on_tiles)
	c.heights_changed.connect(_on_heights)
	c.objects_changed.connect(_on_objects)
	_bytes.resize(c.w * c.h * 4)
	_mark_bare()
	_height_img = Image.create_from_data(c.w + 1, c.h + 1, false, Image.FORMAT_RF, c.heights.to_byte_array())
	_height_tex = ImageTexture.create_from_image(_height_img)
	_heights_stale = false
	for ty in c.h:
		_fill_row(ty)
	_img = Image.create_from_data(c.w, c.h, false, Image.FORMAT_RGBA8, _bytes)
	_tex = ImageTexture.create_from_image(_img)
	material.set_shader_parameter("tile_tex", _tex)
	material.set_shader_parameter("map_size", Vector2(c.w, c.h))
	material.set_shader_parameter("tile_size", Defs.TILE)
	for cy in range(0, c.h, CHUNK):
		for cx in range(0, c.w, CHUNK):
			var mi := MeshInstance3D.new()
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_chunks[Vector2i(cx / CHUNK, cy / CHUNK)] = mi
			_build_chunk(cx / CHUNK, cy / CHUNK)
	_build_surround()


func _frame_terrain(_delta: float) -> void:
	if course == null:
		return
	if not _dirty.is_empty():
		var n := 0
		for key: Vector2i in _dirty.keys():
			_build_chunk(key.x, key.y)
			_dirty.erase(key)
			n += 1
			if n >= 6:
				break
	# Mood, lot value and light borrow the weeds channel. Refill at once when switched.
	var shown := int(material.get_shader_parameter("overlay"))
	if shown != _shown_overlay:
		_shown_overlay = shown
		for ty in course.h:
			_fill_row(ty)
		_upload = true
	# Refresh wetness, health and weeds a few rows per frame.
	var rows := maxi(1, course.h / 90)
	for i in rows:
		_fill_row(_row)
		_row += 1
		if _row >= course.h:
			_row = 0
			_upload = true
	if _upload:
		_upload = false
		_img.set_data(course.w, course.h, false, Image.FORMAT_RGBA8, _bytes)
		_tex.update(_img)
	if _heights_stale:
		_heights_stale = false
		_height_img.set_data(course.w + 1, course.h + 1, false, Image.FORMAT_RF, course.heights.to_byte_array())
		_height_tex.update(_height_img)


## The per-tile data texture: r type (+128 not owned, +64 nothing grows),
## g wetness, b turf health, a weeds.
func data_texture() -> ImageTexture:
	return _tex


## Corner heights, one texel per corner, for anything that must sit on the land.
func height_texture() -> ImageTexture:
	return _height_tex


## Note the tiles that buildings and props stand on.
func _mark_bare() -> void:
	var w := course.w
	_bare.resize(w * course.h)
	_bare.fill(0)
	for i in course.objects.size():
		var o := course.objects[i]
		if o == 0 or o in PLANTS:
			continue
		var tx := i % w
		var ty := i / w
		var rx := 0
		var ry := 0
		if o == Defs.O.CLUBHOUSE:
			rx = 2
			ry = 2
		elif o in WIDE:
			rx = 1
			ry = 1
		for y in range(maxi(ty - ry, 0), mini(ty + ry + 1, course.h)):
			for x in range(maxi(tx - rx, 0), mini(tx + rx + 1, w)):
				_bare[y * w + x] = 1


func _on_objects() -> void:
	_mark_bare()
	for ty in course.h:
		_fill_row(ty)
	_upload = true


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame_terrain(_delta)
	Game.prof("terrain", t0)


func _fill_row(ty: int) -> void:
	var w := course.w
	var j := ty * w * 4
	var i := ty * w
	var shade := PackedByteArray()
	if _shown_overlay == 5 and sim != null:
		shade = sim.lot_shade()
	for tx in w:
		_bytes[j] = course.terrain[i] | (128 if (course.locked[i] != 0 and course.hot[i] == 0) else 0) | (64 if _bare[i] != 0 else 0)
		_bytes[j + 1] = int(course.wet[i] * 255.0)
		_bytes[j + 2] = int(course.health[i] * 255.0)
		if _shown_overlay == 4:
			var m := clampf(course.mood[i] / 12.0, -1.0, 1.0)
			_bytes[j + 3] = int((m * 0.5 + 0.5) * 255.0)
		elif shade.size() > 0:
			_bytes[j + 3] = shade[i]
		elif _shown_overlay == 6:
			var at := course.tile_center(tx, ty)
			_bytes[j + 3] = int(clampf(course.light_at(at.x, at.z), 0.0, 1.0) * 255.0)
		else:
			_bytes[j + 3] = int(course.weeds[i] * 255.0)
		j += 4
		i += 1


func _on_tiles(rect: Rect2i) -> void:
	for ty in range(maxi(rect.position.y, 0), mini(rect.end.y, course.h)):
		_fill_row(ty)
	_upload = true


func _on_heights(rect: Rect2i) -> void:
	_heights_stale = true
	var x0 := maxi(rect.position.x - 1, 0) / CHUNK
	var y0 := maxi(rect.position.y - 1, 0) / CHUNK
	var x1 := mini(rect.end.x + 1, course.w - 1) / CHUNK
	var y1 := mini(rect.end.y + 1, course.h - 1) / CHUNK
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if _chunks.has(Vector2i(cx, cy)):
				_dirty[Vector2i(cx, cy)] = true


func _build_chunk(cx: int, cy: int) -> void:
	var mi: MeshInstance3D = _chunks[Vector2i(cx, cy)]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var n := CHUNK + 1
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var x0 := cx * CHUNK
	var y0 := cy * CHUNK
	var k := 0
	var lo := INF
	var hi := -INF
	for z in n:
		for x in n:
			var vx := mini(x0 + x, course.w)
			var vy := mini(y0 + z, course.h)
			var hgt := course.corner(vx, vy)
			lo = minf(lo, hgt)
			hi = maxf(hi, hgt)
			verts[k] = Vector3(vx * Defs.TILE, hgt, vy * Defs.TILE)
			normals[k] = Vector3(course.corner(vx - 1, vy) - course.corner(vx + 1, vy), 2.0 * Defs.TILE, course.corner(vx, vy - 1) - course.corner(vx, vy + 1)).normalized()
			# Relief: hollows sit a little darker and crests a little lighter
			# than the ground around them, which is what makes hills read
			# from above.
			var ring := course.corner(vx - 3, vy) + course.corner(vx + 3, vy) + course.corner(vx, vy - 3) + course.corner(vx, vy + 3)
			ring += course.corner(vx - 2, vy - 2) + course.corner(vx + 2, vy - 2) + course.corner(vx - 2, vy + 2) + course.corner(vx + 2, vy + 2)
			var relief := clampf(0.5 + (hgt - ring * 0.125) * 0.22, 0.0, 1.0)
			colors[k] = Color(relief, relief, relief)
			k += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh


## A dark apron around the property so the map does not float in the sky.
func _build_surround() -> void:
	var size := course.size_m()
	_base = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x + 6000.0, size.y + 6000.0)
	_base.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _apron_color
	mat.roughness = 1.0
	_base.material_override = mat
	_base.position = Vector3(size.x * 0.5, -14.0, size.y * 0.5)
	_base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_base)
	# skirt: walls from the edge of the map down to the apron
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := course.w
	var h := course.h
	for i in w:
		_skirt_quad(st, Vector2i(i, 0), Vector2i(i + 1, 0))
		_skirt_quad(st, Vector2i(i + 1, h), Vector2i(i, h))
	for i in h:
		_skirt_quad(st, Vector2i(0, i + 1), Vector2i(0, i))
		_skirt_quad(st, Vector2i(w, i), Vector2i(w, i + 1))
	st.generate_normals()
	_skirt = MeshInstance3D.new()
	_skirt.mesh = st.commit()
	var smat := StandardMaterial3D.new()
	smat.albedo_color = _skirt_color
	smat.roughness = 1.0
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_skirt.material_override = smat
	add_child(_skirt)


func _skirt_quad(st: SurfaceTool, a: Vector2i, b: Vector2i) -> void:
	var pa := Vector3(a.x * Defs.TILE, course.corner(a.x, a.y), a.y * Defs.TILE)
	var pb := Vector3(b.x * Defs.TILE, course.corner(b.x, b.y), b.y * Defs.TILE)
	var qa := Vector3(pa.x, -14.0, pa.z)
	var qb := Vector3(pb.x, -14.0, pb.z)
	st.add_vertex(pa)
	st.add_vertex(pb)
	st.add_vertex(qb)
	st.add_vertex(pa)
	st.add_vertex(qb)
	st.add_vertex(qa)


## Where a ray from the camera meets the ground, or null if it misses the map.
func pick(cam: Camera3D, screen: Vector2) -> Variant:
	if course == null:
		return null
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var t := 0.0
	var last := 0.0
	var size := course.size_m()
	for i in 400:
		var p := o + d * t
		var gh := course.height_at(p.x, p.z)
		if p.y <= gh:
			var lo := last
			var hi := t
			for k in 14:
				var mid := (lo + hi) * 0.5
				var q := o + d * mid
				if q.y <= course.height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			var hit := o + d * hi
			if hit.x < 0.0 or hit.z < 0.0 or hit.x >= size.x or hit.z >= size.y:
				return null
			return hit
		last = t
		t += maxf(0.5, (p.y - gh) * 0.4)
		if t > 6000.0:
			break
	return null


const PALETTE_KEYS: Array[String] = ["rough", "fairway", "green", "tee", "bunker", "water", "deep", "path", "rock", "ash", "firm", "fast", "water2"]
var _apron_color := Color(0.13, 0.22, 0.11)
var _skirt_color := Color(0.25, 0.2, 0.14)


## Colour the land for a biome. Call before bind().
func set_biome(biome: Dictionary) -> void:
	var pal: Dictionary = biome.get("palette", {})
	var colors := PackedVector3Array()
	for key in PALETTE_KEYS:
		var c := Color(str(pal.get(key, "808080"))).srgb_to_linear()
		colors.append(Vector3(c.r, c.g, c.b))
	palette = colors
	material.set_shader_parameter("pal", colors)
	material.set_shader_parameter("lava", 1.0 if biome.get("lava", false) else 0.0)
	material.set_shader_parameter("heat", 0.0)
	# photographic ground: which picture each surface uses in this biome
	var g := Surfaces.ground()
	material.set_shader_parameter("ground_tex", g[0])
	material.set_shader_parameter("ground_nor", g[1])
	material.set_shader_parameter("ground_mean", g[2])
	var layers: Array = biome.get("layers", [0, 1, 1, 1, 2, 2, 5, 4, 3, 6, 1, 1])
	var layer_of := PackedFloat32Array()
	for v: Variant in layers:
		layer_of.append(float(v))
	material.set_shader_parameter("layer_of", layer_of)
	#                                              rough fair  green tee   sand  water deep  path  rock  ash   firm  fast
	material.set_shader_parameter("layer_size", PackedFloat32Array([4.2, 3.0, 2.0, 2.4, 3.4, 4.0, 5.2, 2.2, 8.0, 6.0, 2.6, 1.6]))
	material.set_shader_parameter("layer_bump", PackedFloat32Array([0.9, 0.45, 0.2, 0.3, 0.6, 0.0, 1.1, 0.7, 1.3, 1.0, 0.35, 0.15]))
	_apron_color = Color(str(pal.get("apron", "213821")))
	_skirt_color = Color(str(pal.get("skirt", "40332a")))


## Highlight one land parcel, or pass an empty rect to clear it.
func set_land_rect(r: Rect2i, color: Color = Color.WHITE) -> void:
	if r.size.x <= 0:
		material.set_shader_parameter("land_rect", Vector4.ZERO)
		return
	material.set_shader_parameter("land_rect", Vector4(r.position.x, r.position.y, r.end.x, r.end.y) * Defs.TILE)
	material.set_shader_parameter("brush_color", color)


func set_brush(pos: Vector3, radius: float, color: Color = Color.WHITE) -> void:
	material.set_shader_parameter("brush", Vector3(pos.x, pos.z, radius))
	material.set_shader_parameter("brush_color", color)


func hide_brush() -> void:
	material.set_shader_parameter("brush", Vector3(0.0, 0.0, -1.0))
