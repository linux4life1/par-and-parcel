class_name GrassView
extends Node3D
## Standing grass in the rough near the camera, and standing weeds wherever
## the turf has gone to them. One patch of tufts is drawn many times over the
## ground around the point being looked at; the shader places each tuft on
## the land and decides whether grass or a weed grows there (see
## shaders/grass.gdshader). Nothing here is rebuilt when the course changes.

const PATCH := 24.0            # metres along one side of a patch
const RING := 4                # patches drawn each side of the focus
const PER_M2 := 3.0            # tufts per square metre at full thickness
const FADE_START := 62.0
const FADE_END := 94.0

var material := ShaderMaterial.new()
var _mm := MultiMesh.new()
var _patches: Array[MultiMeshInstance3D] = []
var _terrain: TerrainView
var _course: Course
var _enabled := true
var _thickness := 1.0


func _ready() -> void:
	Flora.setup()
	material.shader = load("res://shaders/grass.gdshader")
	material.set_shader_parameter("atlas", Surfaces.picture("foliage_atlas.png"))
	material.set_shader_parameter("noise_tex", Surfaces.noise())
	material.set_shader_parameter("fade", Vector2(FADE_START, FADE_END))
	material.set_shader_parameter("blade_mean", Surfaces.atlas_means("foliage_atlas.png")[3])
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _tuft()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var count := int(PATCH * PATCH * PER_M2)
	_mm.instance_count = count
	for i in count:
		var s := lerpf(0.34, 1.0, pow(rng.randf(), 1.6))
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, rng.randf_range(0.4, 0.72), s))
		_mm.set_instance_transform(i, Transform3D(b, Vector3(rng.randf() * PATCH, 0.0, rng.randf() * PATCH)))
	var side := RING * 2 + 1
	for i in side * side:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = _mm
		mmi.material_override = material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-2.0, -40.0, -2.0), Vector3(PATCH + 4.0, 260.0, PATCH + 4.0))
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.visible = false
		add_child(mmi)
		_patches.append(mmi)


## A tuft: three cards of blades rooted together and leaning outward, so it
## shows its leaves from above as well as from the side. About a metre
## across and tall; each tuft is scaled down from that.
func _tuft() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var cell := Rect2(0.5 + 0.006, 0.5 + 0.006, 0.5 - 0.012, 0.5 - 0.012)
	for k in 3:
		var a := k * TAU / 3.0 + 0.3
		var lean: float = [0.62, 0.3, 0.5][k]
		var out := Vector3(cos(a) * sin(lean), cos(lean), sin(a) * sin(lean))
		var across := Vector3(-sin(a), 0.0, cos(a))
		var root := Vector3(cos(a), 0.0, sin(a)) * -0.08
		var base := verts.size()
		for j in 2:
			for i in 2:
				verts.append(root + across * ((i - 0.5) * 0.9) + out * (1.0 - j))
				norms.append(Vector3.UP)
				uvs.append(Vector2(cell.position.x + cell.size.x * i, cell.position.y + cell.size.y * j))
				uv2.append(Vector2(i, j))
		idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Thin the grass out for lighter graphics presets: 0 none .. 1 all of it.
## Tufts are in random order, so drawing the first part thins it evenly.
func set_thickness(amount: float) -> void:
	_thickness = clampf(amount, 0.0, 1.0)
	_mm.visible_instance_count = int(_mm.instance_count * _thickness)


## Point the grass at a course. Call after the terrain view is bound.
func bind(terrain: TerrainView, course: Course, biome: Dictionary) -> void:
	_terrain = terrain
	_course = course
	var growth: Array = biome.get("grass", [0.4, 1.0, 1.0])
	# weeds can stand anywhere, so the layer is always on; where the biome
	# grows no standing grass only the weeds show
	_enabled = true
	material.set_shader_parameter("tile_tex", terrain.data_texture())
	material.set_shader_parameter("height_tex", terrain.height_texture())
	material.set_shader_parameter("map_size", Vector2(course.w, course.h))
	material.set_shader_parameter("tile_size", Defs.TILE)
	material.set_shader_parameter("growth", Vector3(float(growth[0]), float(growth[1]), float(growth[2])))
	if terrain.palette.size() > 6:
		material.set_shader_parameter("pal_rough", terrain.palette[0])
		material.set_shader_parameter("pal_deep", terrain.palette[6])


## Keep the patches around the point being looked at, and only those close
## enough to the camera for a blade of grass to show.
func update(cam_pos: Vector3, focus: Vector3, wind: Vector2, cloud_offset: Vector2, cloud_cover: float) -> void:
	if _course == null:
		return
	var overlay: Variant = _terrain.material.get_shader_parameter("overlay")
	var show := _enabled and _thickness > 0.01 and (overlay == null or int(overlay) == 0)
	material.set_shader_parameter("wind", wind)
	material.set_shader_parameter("cloud_offset", cloud_offset)
	material.set_shader_parameter("cloud_cover", cloud_cover)
	var size := _course.size_m()
	var bx := floorf(focus.x / PATCH)
	var bz := floorf(focus.z / PATCH)
	var side := RING * 2 + 1
	var reach := FADE_END + PATCH * 0.72
	var n := 0
	for j in side:
		for i in side:
			var mmi := _patches[n]
			n += 1
			var x := (bx + i - RING) * PATCH
			var z := (bz + j - RING) * PATCH
			var inside := x + PATCH > 0.0 and z + PATCH > 0.0 and x < size.x and z < size.y
			var mid := Vector3(x + PATCH * 0.5, focus.y, z + PATCH * 0.5)
			var on := show and inside and mid.distance_to(cam_pos) < reach
			mmi.visible = on
			if on:
				mmi.position = Vector3(x, 0.0, z)
