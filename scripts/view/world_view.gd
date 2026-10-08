class_name WorldView
extends Node3D
## Everything standing on the terrain: trees and buildings, flags, golfers,
## staff, balls and their tracers, pest mounds, and floating pop-up text.

static var _mats := {}
static var _meshes := {}

var sim: Sim
var rig: CameraRig
var selected: Variant = null       # a Golfer or a Crew.Member
var _figs := {}
var _staff_figs := {}
var _balls := {}
var _ball_turn := {}               # golfer id -> Basis: how far each ball has turned
var _trails := {}
var _dt := 0.0
var _stakes := MultiMeshInstance3D.new()   # white out of bounds stakes round the property
var _stakes_owned := -1
var _objects_dirty := true
var _holes_dirty := true
var _obj_root := Node3D.new()
var _hole_root := Node3D.new()
var _people_root := Node3D.new()
var _fx_root := Node3D.new()
var _flags: Array[Node3D] = []
var _hole_nodes: Array[Node3D] = []
var _hole_labels: Array[Label3D] = []
var _popups: Array[Dictionary] = []
const TRAIL_POOL := 640
## How big the ball is drawn, as a share of its distance from the camera.
const BALL_ON_GROUND := 0.001
const BALL_IN_AIR := 0.0017
var _trail_mm := MultiMesh.new()
var _trail_mi := MultiMeshInstance3D.new()
var _trail_mat := StandardMaterial3D.new()
var _trail_n := 0
var _ring := MeshInstance3D.new()
var _mounds := MultiMeshInstance3D.new()
var _litter: MultiMeshInstance3D
var _litter_rev := -1
var _spots: MultiMeshInstance3D
var _mound_set := {}
var _mound_cursor := 0
var _mound_changed := false
var _clock := 0.0
var _bubbles := {}             # golfer id -> Label3D
var _carts := {}               # group id -> MeshInstance3D
var _tosses: Array[Dictionary] = []   # clubs in the air after a tantrum: {node, from, vel, t, id}
var _tossed := {}              # golfer id -> true once their club has been thrown this hole
var _animals := {}             # Wildlife.Animal -> MeshInstance3D
var _lod_scale := 1.0          # how far the detailed trees reach, by graphics preset
var _lamps: Array = []         # [light, full energy] for everything that shines at night
var _dark_shown := -1.0


# ------------------------------------------------------- shared resources

static func mat(color: Color, tinted: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + ("t" if tinted else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.vertex_color_use_as_albedo = tinted
	_mats[key] = m
	return m


static func glow(color: Color) -> StandardMaterial3D:
	var key := color.to_html() + "g"
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


## A golf ball you can watch turning: white, with a painted line down one
## side and the maker's mark on the other. It carries a little light of its
## own so it can be found in shade and at night.
static func ball_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html() + "ball"
	if _mats.has(key):
		return _mats[key]
	if not _mats.has("balltex"):
		var img := Image.create(64, 32, false, Image.FORMAT_RGB8)
		for y in 32:
			for x in 64:
				var u := (x + 0.5) / 64.0
				var v := (y + 0.5) / 32.0
				var c := Color.WHITE
				if (u < 0.055 or u > 0.945) and v > 0.14 and v < 0.86:
					c = Color(0.80, 0.09, 0.10)
				elif absf(u - 0.5) < 0.06 and absf(v - 0.5) < 0.13:
					c = Color(0.10, 0.13, 0.22)
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		var keep := StandardMaterial3D.new()
		keep.albedo_texture = ImageTexture.create_from_image(img)
		_mats["balltex"] = keep
	var tex: Texture2D = (_mats["balltex"] as StandardMaterial3D).albedo_texture
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = tex
	m.roughness = 0.32
	m.emission_enabled = true
	m.emission = color
	m.emission_texture = tex
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.emission_energy_multiplier = 0.5
	_mats[key] = m
	return m


static func mesh(id: String) -> Mesh:
	if _meshes.has(id):
		return _meshes[id]
	var m: Mesh
	match id:
		"legs":
			var b := BoxMesh.new()
			b.size = Vector3(0.3, 0.84, 0.34)
			m = b
		"torso":
			var c := CapsuleMesh.new()
			c.radius = 0.23
			c.height = 0.76
			c.radial_segments = 10
			c.rings = 3
			m = c
		"head":
			m = _sphere(0.17, 10, 6)
		"hat":
			var c := CylinderMesh.new()
			c.top_radius = 0.16
			c.bottom_radius = 0.21
			c.height = 0.11
			c.radial_segments = 10
			m = c
		"club":
			var c := CylinderMesh.new()
			c.top_radius = 0.022
			c.bottom_radius = 0.035
			c.height = 1.1
			c.radial_segments = 5
			m = c
		"mower":
			var b := BoxMesh.new()
			b.size = Vector3(0.9, 0.5, 0.75)
			m = b
		"tank":
			var b := BoxMesh.new()
			b.size = Vector3(0.22, 0.5, 0.34)
			m = b
		"star":
			m = _sphere(0.07, 6, 3)
		"ball":
			m = _sphere(1.0, 16, 8)
		"stake":
			var st := BoxMesh.new()
			st.size = Vector3(0.11, 1.15, 0.11)
			m = st
		"gem":
			m = _sphere(0.2, 4, 2)
		"blob":
			var c := CylinderMesh.new()
			c.top_radius = 1.0
			c.bottom_radius = 1.0
			c.height = 0.02
			c.radial_segments = 14
			m = c
		"mound":
			m = _sphere(0.8, 8, 4)
		"cart_gold":
			m = compose([
				[_box(2.3, 0.5, 1.2), Vector3(0, 0.65, 0), Color(0.95, 0.78, 0.2)],
				[_box(2.1, 0.08, 1.25), Vector3(0, 1.95, 0), Color(0.2, 0.2, 0.2)],
				[_box(0.08, 1.2, 0.08), Vector3(0.95, 1.35, 0.55), Color(0.3, 0.3, 0.3)],
				[_box(0.08, 1.2, 0.08), Vector3(0.95, 1.35, -0.55), Color(0.3, 0.3, 0.3)],
				[_box(0.08, 1.2, 0.08), Vector3(-0.95, 1.35, 0.55), Color(0.3, 0.3, 0.3)],
				[_box(0.08, 1.2, 0.08), Vector3(-0.95, 1.35, -0.55), Color(0.3, 0.3, 0.3)],
				[_box(0.5, 0.5, 1.4), Vector3(0.7, 0.3, 0), Color(0.12, 0.12, 0.12)],
				[_box(0.5, 0.5, 1.4), Vector3(-0.7, 0.3, 0), Color(0.12, 0.12, 0.12)],
				[_box(0.7, 0.5, 1.0), Vector3(-0.2, 1.05, 0), Color(0.3, 0.2, 0.15)],
			], false)
		"animal_deer", "animal_stag", "animal_goat", "animal_sheep":
			var coat := Color(0.62, 0.44, 0.26)
			if id == "animal_stag":
				coat = Color(0.45, 0.3, 0.18)
			elif id == "animal_goat":
				coat = Color(0.75, 0.74, 0.7)
			elif id == "animal_sheep":
				coat = Color(0.95, 0.94, 0.9)
			var parts := [
				[_box(1.3, 0.6, 0.5), Vector3(0, 0.95, 0), coat],
				[_box(0.4, 0.4, 0.35), Vector3(0.8, 1.35, 0), coat.darkened(0.3) if id == "animal_sheep" else coat],
				[_box(0.14, 0.7, 0.14), Vector3(0.5, 0.35, 0.16), coat.darkened(0.3)],
				[_box(0.14, 0.7, 0.14), Vector3(0.5, 0.35, -0.16), coat.darkened(0.3)],
				[_box(0.14, 0.7, 0.14), Vector3(-0.5, 0.35, 0.16), coat.darkened(0.3)],
				[_box(0.14, 0.7, 0.14), Vector3(-0.5, 0.35, -0.16), coat.darkened(0.3)],
			]
			if id == "animal_sheep":
				parts[0] = [_sphere(0.6, 7, 4), Vector3(0, 0.95, 0), coat]
			if id == "animal_stag" or id == "animal_goat":
				parts.append([_box(0.06, 0.6, 0.06), Vector3(0.85, 1.8, 0.14), Color(0.85, 0.8, 0.7)])
				parts.append([_box(0.06, 0.6, 0.06), Vector3(0.85, 1.8, -0.14), Color(0.85, 0.8, 0.7)])
			m = compose(parts, false)
		"animal_duck":
			m = compose([
				[_sphere(0.3, 7, 4), Vector3(0, 0.3, 0), Color(0.95, 0.95, 0.92)],
				[_sphere(0.16, 6, 3), Vector3(0.28, 0.6, 0), Color(0.15, 0.4, 0.2)],
				[_box(0.18, 0.06, 0.1), Vector3(0.46, 0.58, 0), Color(0.95, 0.6, 0.1)],
			], false)
		"animal_roadrunner":
			m = compose([
				[_box(0.6, 0.3, 0.25), Vector3(0, 0.55, 0), Color(0.5, 0.42, 0.32)],
				[_box(0.7, 0.08, 0.12), Vector3(-0.6, 0.7, 0), Color(0.3, 0.26, 0.2), Basis(Vector3(0, 0, 1), -0.35)],
				[_box(0.2, 0.2, 0.16), Vector3(0.38, 0.85, 0), Color(0.5, 0.42, 0.32)],
				[_box(0.25, 0.05, 0.06), Vector3(0.58, 0.85, 0), Color(0.2, 0.2, 0.2)],
				[_box(0.05, 0.4, 0.05), Vector3(0.05, 0.2, 0.08), Color(0.3, 0.3, 0.5)],
				[_box(0.05, 0.4, 0.05), Vector3(0.05, 0.2, -0.08), Color(0.3, 0.3, 0.5)],
			], false)
		"animal_tortoise":
			m = compose([
				[_sphere(0.45, 7, 4), Vector3(0, 0.25, 0), Color(0.3, 0.38, 0.2), Basis.from_scale(Vector3(1.0, 0.6, 0.85))],
				[_box(0.2, 0.14, 0.16), Vector3(0.48, 0.2, 0), Color(0.45, 0.45, 0.3)],
			], false)
		"animal_lizard":
			m = compose([
				[_box(0.9, 0.16, 0.26), Vector3(0, 0.16, 0), Color(0.15, 0.13, 0.12)],
				[_box(0.7, 0.1, 0.12), Vector3(-0.75, 0.14, 0), Color(0.15, 0.13, 0.12)],
				[_box(0.3, 0.14, 0.22), Vector3(0.55, 0.2, 0), Color(0.95, 0.4, 0.1)],
				[_box(0.5, 0.05, 0.1), Vector3(0, 0.25, 0), Color(0.95, 0.4, 0.1)],
			], false)
		"cart":
			m = compose([
				[_box(2.3, 0.5, 1.2), Vector3(0, 0.65, 0), Color(0.95, 0.95, 0.92)],
				[_box(2.1, 0.08, 1.25), Vector3(0, 1.95, 0), Color(0.2, 0.5, 0.3)],
				[_box(0.08, 1.2, 0.08), Vector3(0.95, 1.35, 0.55), Color(0.3, 0.3, 0.3)],
				[_box(0.08, 1.2, 0.08), Vector3(0.95, 1.35, -0.55), Color(0.3, 0.3, 0.3)],
				[_box(0.08, 1.2, 0.08), Vector3(-0.95, 1.35, 0.55), Color(0.3, 0.3, 0.3)],
				[_box(0.08, 1.2, 0.08), Vector3(-0.95, 1.35, -0.55), Color(0.3, 0.3, 0.3)],
				[_box(0.5, 0.5, 1.4), Vector3(0.7, 0.3, 0), Color(0.12, 0.12, 0.12)],
				[_box(0.5, 0.5, 1.4), Vector3(-0.7, 0.3, 0), Color(0.12, 0.12, 0.12)],
				[_box(0.7, 0.5, 1.0), Vector3(-0.2, 1.05, 0), Color(0.85, 0.8, 0.7)],
			], false)
		_:
			m = BoxMesh.new()
	_meshes[id] = m
	return m


static func _sphere(r: float, seg: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s


static func _cyl(top: float, bottom: float, height: float, seg: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = seg
	c.rings = 1
	return c


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


## Merge simple shapes into one mesh, one surface per material.
## Each part is [mesh, offset, colour or material] with an optional fourth
## item: a turn about Y in radians, or a full Basis. A ready-made mesh (from
## Flora) brings its own surfaces and materials; pass null for its colour.
static func compose(parts: Array, tinted: bool) -> ArrayMesh:
	var groups := {}        # material -> {verts, norms, cols, uvs, idx, colored}
	var order: Array[Material] = []
	for part: Array in parts:
		var src: Mesh = part[0]
		var off: Vector3 = part[1]
		var turn := Basis.IDENTITY
		if part.size() > 3:
			if part[3] is Basis:
				turn = part[3]
			else:
				turn = Basis(Vector3.UP, float(part[3]))
		var nb := turn.orthonormalized()
		var ready := src is ArrayMesh
		var surfaces := src.get_surface_count() if ready else 1
		for surface in surfaces:
			var arrays: Array = src.surface_get_arrays(surface) if ready else src.get_mesh_arrays()
			var material: Material
			if ready:
				material = src.surface_get_material(surface)
			elif part[2] is Material:
				material = part[2]
			else:
				material = mat(part[2], tinted)
			if not groups.has(material):
				groups[material] = {"verts": PackedVector3Array(), "norms": PackedVector3Array(), "cols": PackedColorArray(),
					"uvs": PackedVector2Array(), "idx": PackedInt32Array(), "colored": false}
				order.append(material)
			var g: Dictionary = groups[material]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var gv: PackedVector3Array = g.verts
			var gn: PackedVector3Array = g.norms
			var gc: PackedColorArray = g.cols
			var gu: PackedVector2Array = g.uvs
			var gi: PackedInt32Array = g.idx
			var base := gv.size()
			for i in verts.size():
				gv.append(turn * verts[i] + off)
				gn.append(nb * norms[i])
			if arrays[Mesh.ARRAY_COLOR] != null:
				gc.append_array(arrays[Mesh.ARRAY_COLOR])
				g.colored = true
			else:
				for i in verts.size():
					gc.append(Color.WHITE)
			if arrays[Mesh.ARRAY_TEX_UV] != null:
				gu.append_array(arrays[Mesh.ARRAY_TEX_UV])
			else:
				for i in verts.size():
					gu.append(Vector2.ZERO)
			if arrays[Mesh.ARRAY_INDEX] != null:
				for k: int in arrays[Mesh.ARRAY_INDEX]:
					gi.append(base + k)
			else:
				for i in verts.size():
					gi.append(base + i)
			g.verts = gv
			g.norms = gn
			g.cols = gc
			g.uvs = gu
			g.idx = gi
	var out := ArrayMesh.new()
	for material in order:
		var g: Dictionary = groups[material]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_NORMAL] = g.norms
		arrays[Mesh.ARRAY_TEX_UV] = g.uvs
		arrays[Mesh.ARRAY_INDEX] = g.idx
		if g.colored:
			arrays[Mesh.ARRAY_COLOR] = g.cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, material)
	return out


## A pin flag: a strip of cloth fine enough to ripple.
static func flag_mesh() -> Mesh:
	if _meshes.has("pinflag"):
		return _meshes["pinflag"]
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.62, 0.42)
	plane.subdivide_width = 12
	plane.subdivide_depth = 2
	plane.orientation = PlaneMesh.FACE_Z
	plane.center_offset = Vector3(0.31, 0.0, 0.0)
	_meshes["pinflag"] = plane
	return plane


static func flag_material() -> ShaderMaterial:
	if _mats.has("pinflag"):
		return _mats["pinflag"]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 cloth : source_color = vec3(0.85, 0.08, 0.08);
uniform float wind = 1.0;
varying float fold;
void vertex() {
	// pinned at the pole, free at the fly end
	float free = clamp(VERTEX.x / 0.62, 0.0, 1.0);
	float phase = VERTEX.x * 11.0 - TIME * (5.0 + wind * 2.0) + VERTEX.y * 2.0;
	float wave = sin(phase) * 0.045 * free * (0.5 + wind * 0.5);
	VERTEX.z += wave;
	VERTEX.y -= free * free * 0.05 * (1.2 - min(wind, 1.0));
	fold = cos(phase) * free;
	NORMAL = normalize(NORMAL + vec3(-cos(phase) * 0.5 * free, 0.0, 0.0));
}
void fragment() {
	ALBEDO = cloth * (0.86 + 0.2 * fold);
	ROUGHNESS = 0.85;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = cloth * 0.4;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_mats["pinflag"] = m
	return m


## A framed window with glazing bars, on a wall facing along z (or along x
## when `side` is set).
static func _window(parts: Array, at: Vector3, w: float, h: float, side: bool = false) -> void:
	var white := paint(Color(0.96, 0.96, 0.94), 0.5)
	if side:
		parts.append([_box(0.12, h, w), at, glass()])
		parts.append([_box(0.22, 0.1, w + 0.24), at + Vector3(0, h * 0.5 + 0.05, 0), white])
		parts.append([_box(0.3, 0.1, w + 0.34), at - Vector3(0, h * 0.5 + 0.05, 0), white])
		parts.append([_box(0.22, h, 0.1), at + Vector3(0, 0, w * 0.5 + 0.05), white])
		parts.append([_box(0.22, h, 0.1), at - Vector3(0, 0, w * 0.5 + 0.05), white])
		parts.append([_box(0.17, h, 0.05), at, white])
		parts.append([_box(0.17, 0.05, w), at, white])
	else:
		parts.append([_box(w, h, 0.12), at, glass()])
		parts.append([_box(w + 0.24, 0.1, 0.22), at + Vector3(0, h * 0.5 + 0.05, 0), white])
		parts.append([_box(w + 0.34, 0.1, 0.3), at - Vector3(0, h * 0.5 + 0.05, 0), white])
		parts.append([_box(0.1, h, 0.22), at + Vector3(w * 0.5 + 0.05, 0, 0), white])
		parts.append([_box(0.1, h, 0.22), at - Vector3(w * 0.5 + 0.05, 0, 0), white])
		parts.append([_box(0.05, h, 0.17), at, white])
		parts.append([_box(w, 0.05, 0.17), at, white])


static func glass() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.2, 0.28)
	m.roughness = 0.04
	m.metallic = 0.7
	m.metallic_specular = 0.9
	# windows light up at night (see _show_night)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.78, 0.46)
	m.emission_energy_multiplier = 0.0
	_mats["glass"] = m
	return m


## The lit front of a vending machine: a cool white lightbox, faintly on by
## day and bright after dark (see _show_night).
static func vend_glow() -> StandardMaterial3D:
	if _mats.has("vend_glow"):
		return _mats["vend_glow"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.92, 0.98)
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = Color(0.78, 0.9, 1.0)
	m.emission_energy_multiplier = 0.35
	_mats["vend_glow"] = m
	return m


## The glass of a lamp: pale by day, glowing at night.
static func lamp_glow() -> StandardMaterial3D:
	if _mats.has("lamp_glow"):
		return _mats["lamp_glow"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.94, 0.88)
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = Color(1.0, 0.9, 0.68)
	m.emission_energy_multiplier = 0.0
	_mats["lamp_glow"] = m
	return m


static func pond() -> StandardMaterial3D:
	if _mats.has("pond"):
		return _mats["pond"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.5, 0.75)
	m.roughness = 0.03
	m.metallic = 0.3
	_mats["pond"] = m
	return m


static func paint(color: Color, rough: float = 0.6) -> StandardMaterial3D:
	var key := "paint" + color.to_html() + str(rough)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	_mats[key] = m
	return m


## Buildings with real materials: plaster, brick, roof tiles, timber, glass.
static func _built(kind: String) -> Array:
	var plaster := Surfaces.material("painted_plaster_wall", 0.3, Color(1.25, 1.22, 1.14))
	var brick := Surfaces.material("red_brick_03", 0.45, Color(1.2, 1.1, 1.05))
	var tiles := Surfaces.material("clay_roof_tiles_02", 0.4, Color(1.1, 0.95, 0.9))
	var slate := Surfaces.material("roof_slates_02", 0.45, Color(0.9, 0.95, 1.05))
	var timber := Surfaces.material("brown_planks_03", 0.55, Color(1.35, 1.0, 0.7))
	var dark_timber := Surfaces.material("brown_planks_03", 0.55, Color(0.75, 0.55, 0.4))
	var stone := Surfaces.material("stone_pathway", 0.35, Color(1.25, 1.22, 1.18))
	var white := paint(Color(0.96, 0.96, 0.94), 0.5)
	var parts := []
	match kind:
		"o8":   # clubhouse: a gabled hall with a veranda
			var roof := PrismMesh.new()
			roof.size = Vector3(18.4, 3.8, 11.2)
			var dormer := PrismMesh.new()
			dormer.size = Vector3(2.6, 1.3, 2.4)
			parts = [
				[_box(17.0, 0.7, 10.0), Vector3(0, 0.35, 0), stone],
				[_box(16.0, 4.6, 9.0), Vector3(0, 3.0, 0), plaster],
				[_box(16.3, 0.25, 9.3), Vector3(0, 5.25, 0), white],
				[roof, Vector3(0, 7.25, 0), tiles],
				[_box(13.0, 0.22, 3.8), Vector3(0, 0.6, -6.3), timber],
				[_box(13.6, 0.28, 4.4), Vector3(0, 3.95, -6.5), tiles, Basis(Vector3(1, 0, 0), 0.16)],
				[_box(2.2, 3.0, 0.22), Vector3(0, 2.2, -4.56), dark_timber],
				[_box(2.6, 0.25, 0.3), Vector3(0, 3.8, -4.6), white],
				[_box(1.5, 2.6, 1.5), Vector3(5.5, 8.4, 2.0), brick],
				[_box(1.8, 0.25, 1.8), Vector3(5.5, 9.8, 2.0), stone],
				[dormer, Vector3(-4.2, 7.4, -3.6), tiles],
				[dormer, Vector3(4.2, 7.4, -3.6), tiles],
				[_box(1.9, 1.0, 0.2), Vector3(-4.2, 6.6, -4.75), glass()],
				[_box(1.9, 1.0, 0.2), Vector3(4.2, 6.6, -4.75), glass()],
				[_box(4.0, 0.2, 1.2), Vector3(0, 0.2, -8.6), stone],
				[_cyl(0.05, 0.05, 7.0, 6), Vector3(-8.6, 3.5, -6.0), white],
				[_box(1.5, 0.9, 0.04), Vector3(-7.8, 6.4, -6.0), paint(Color(0.1, 0.4, 0.2))],
			]
			for cx: float in [-6.2, -3.7, -1.3, 1.3, 3.7, 6.2]:
				parts.append([_cyl(0.16, 0.19, 3.2, 10), Vector3(cx, 2.3, -8.0), white])
			for wx: float in [-6.0, -3.5, 3.5, 6.0]:
				_window(parts, Vector3(wx, 2.9, -4.52), 1.6, 2.1)
				_window(parts, Vector3(wx, 2.9, 4.52), 1.6, 2.1)
			for wz: float in [-2.5, 0.5, 3.0]:
				_window(parts, Vector3(8.02, 2.9, wz), 1.6, 2.1, true)
				_window(parts, Vector3(-8.02, 2.9, wz), 1.6, 2.1, true)
			# gable ends, a lantern over the door and planters by the steps
			for gz: float in [-5.62, 5.62]:
				parts.append([_cyl(0.62, 0.62, 0.1, 20), Vector3(0, 6.9, gz), white, Basis(Vector3(1, 0, 0), PI * 0.5)])
				parts.append([_cyl(0.5, 0.5, 0.14, 20), Vector3(0, 6.9, gz), glass(), Basis(Vector3(1, 0, 0), PI * 0.5)])
			for px: float in [-2.6, 2.6]:
				parts.append([_box(0.9, 0.6, 0.9), Vector3(px, 0.3, -8.9), stone])
				parts.append([Flora.mesh("bush", true), Vector3(px, 0.45, -8.9), null, Basis.from_scale(Vector3(0.55, 0.6, 0.55))])
		"o5":   # bench
			parts = [
				[_box(2.2, 0.1, 0.62), Vector3(0, 0.5, 0), timber],
				[_box(2.2, 0.5, 0.09), Vector3(0, 0.88, -0.3), timber, Basis(Vector3(1, 0, 0), -0.14)],
				[_box(0.1, 0.5, 0.56), Vector3(-0.95, 0.25, 0), paint(Color(0.15, 0.15, 0.16), 0.4)],
				[_box(0.1, 0.5, 0.56), Vector3(0.95, 0.25, 0), paint(Color(0.15, 0.15, 0.16), 0.4)],
			]
		"o6":   # drink stand: a kiosk with a striped awning
			parts = [
				[_box(3.0, 0.3, 3.0), Vector3(0, 0.15, 0), stone],
				[_box(2.8, 2.3, 2.8), Vector3(0, 1.45, 0), plaster],
				[_box(3.3, 0.14, 0.9), Vector3(0, 1.25, -1.6), timber],
				[_box(2.2, 0.9, 0.12), Vector3(0, 1.95, -1.42), glass()],
				[_cyl(0.0, 2.7, 1.5, 4), Vector3(0, 3.35, 0), tiles, PI * 0.25],
				[_box(3.4, 0.1, 1.5), Vector3(0, 2.5, -2.0), paint(Color(0.15, 0.45, 0.8)), Basis(Vector3(1, 0, 0), -0.3)],
			]
			for k in 4:
				parts.append([_box(0.42, 0.11, 1.52), Vector3(-1.27 + k * 0.85, 2.52, -2.0), white, Basis(Vector3(1, 0, 0), -0.3)])
		"o9":   # snack bar
			var roof := PrismMesh.new()
			roof.size = Vector3(5.6, 1.5, 4.8)
			parts = [
				[_box(5.0, 0.3, 4.2), Vector3(0, 0.15, 0.3), stone],
				[_box(4.6, 2.5, 3.6), Vector3(0, 1.55, 0.4), plaster],
				[roof, Vector3(0, 3.55, 0.4), tiles],
				[_box(4.4, 0.14, 0.8), Vector3(0, 1.2, -1.75), timber],
				[_box(3.6, 1.0, 0.12), Vector3(0, 2.0, -1.42), glass()],
				[_box(5.0, 0.1, 1.9), Vector3(0, 2.75, -2.2), paint(Color(0.9, 0.45, 0.1)), Basis(Vector3(1, 0, 0), -0.28)],
				[_box(2.4, 0.7, 0.14), Vector3(0, 4.0, -1.6), paint(Color(0.8, 0.15, 0.15))],
				[_cyl(0.5, 0.5, 0.06, 12), Vector3(-2.9, 0.75, -3.2), white],
				[_cyl(0.05, 0.05, 0.75, 6), Vector3(-2.9, 0.38, -3.2), paint(Color(0.2, 0.2, 0.2))],
				[_cyl(0.5, 0.5, 0.06, 12), Vector3(2.9, 0.75, -3.2), white],
				[_cyl(0.05, 0.05, 0.75, 6), Vector3(2.9, 0.38, -3.2), paint(Color(0.2, 0.2, 0.2))],
			]
			for k in 5:
				parts.append([_box(0.5, 0.11, 1.92), Vector3(-2.0 + k * 1.0, 2.77, -2.2), white, Basis(Vector3(1, 0, 0), -0.28)])
		"o7":   # restroom
			parts = [
				[_box(4.2, 0.3, 3.4), Vector3(0, 0.15, 0), stone],
				[_box(4.0, 2.5, 3.2), Vector3(0, 1.55, 0), brick],
				[_box(4.6, 0.22, 3.8), Vector3(0, 2.95, 0), slate, Basis(Vector3(1, 0, 0), 0.08)],
				[_box(0.95, 2.0, 0.12), Vector3(-0.95, 1.3, -1.62), paint(Color(0.2, 0.35, 0.55), 0.4)],
				[_box(0.95, 2.0, 0.12), Vector3(0.95, 1.3, -1.62), paint(Color(0.6, 0.25, 0.35), 0.4)],
				[_box(3.2, 0.4, 0.1), Vector3(0, 2.55, -1.62), glass()],
			]
		"o26":  # vending machine: a red cabinet, a lit window full of cans, a coin panel
			var red := paint(Color(0.72, 0.1, 0.1), 0.35)
			var dark := paint(Color(0.1, 0.1, 0.11), 0.5)
			var steel := paint(Color(0.6, 0.62, 0.65), 0.3)
			parts = [
				[_box(0.96, 0.12, 0.88), Vector3(0, 0.06, 0.02), dark],
				[_box(0.9, 1.78, 0.7), Vector3(0, 1.01, 0.05), red],
				[_box(0.9, 0.06, 0.82), Vector3(0, 1.93, 0.0), dark],
				# the frame round the window, and the side panel with the slot
				[_box(0.08, 1.78, 0.12), Vector3(-0.44, 1.01, -0.36), red],
				[_box(0.64, 0.12, 0.12), Vector3(-0.12, 1.86, -0.36), red],
				[_box(0.64, 0.5, 0.12), Vector3(-0.12, 0.37, -0.36), dark],
				[_box(0.3, 1.78, 0.12), Vector3(0.3, 1.01, -0.36), red],
				# the lit back of the window, the cans in front of it, the lit header
				[_box(0.56, 1.14, 0.03), Vector3(-0.12, 1.21, -0.285), vend_glow()],
				[_box(0.62, 0.1, 0.01), Vector3(-0.12, 1.86, -0.425), vend_glow()],
				[_box(0.4, 0.17, 0.02), Vector3(-0.12, 0.3, -0.425), paint(Color(0.22, 0.22, 0.24), 0.4)],
				[_box(0.18, 0.3, 0.02), Vector3(0.3, 1.45, -0.425), steel],
				[_box(0.03, 0.08, 0.01), Vector3(0.3, 1.5, -0.44), dark],
			]
			var cans := [Color(0.85, 0.12, 0.12), Color(0.12, 0.35, 0.8), Color(0.15, 0.6, 0.25), Color(0.95, 0.55, 0.1), Color(0.5, 0.2, 0.7), Color(0.95, 0.85, 0.2)]
			for r in 4:
				parts.append([_box(0.56, 0.02, 0.1), Vector3(-0.12, 0.7 + r * 0.27, -0.32), steel])
				for col in 3:
					var c: Color = cans[(r * 3 + col) % cans.size()]
					parts.append([_cyl(0.045, 0.045, 0.13, 8), Vector3(-0.31 + col * 0.19, 0.78 + r * 0.27, -0.34), paint(c, 0.3)])
			for k in 4:
				parts.append([_box(0.1, 0.04, 0.02), Vector3(0.3, 1.02 + k * 0.08, -0.425), vend_glow()])
		"o27":  # bar: an open-fronted pavilion with a counter, stools, bottles and a pint sign
			var roof := PrismMesh.new()
			roof.size = Vector3(6.8, 1.6, 6.0)
			var polished := paint(Color(0.3, 0.17, 0.1), 0.25)
			var leather := paint(Color(0.45, 0.1, 0.1), 0.5)
			var steel := paint(Color(0.6, 0.62, 0.65), 0.3)
			var amber := paint(Color(0.9, 0.55, 0.12), 0.2)
			parts = [
				[_box(6.2, 0.3, 5.2), Vector3(0, 0.15, 0.2), stone],
				[_box(5.6, 2.6, 0.3), Vector3(0, 1.6, 2.2), dark_timber],
				[_box(0.3, 2.6, 4.2), Vector3(-2.8, 1.6, 0.3), dark_timber],
				[_box(0.3, 2.6, 4.2), Vector3(2.8, 1.6, 0.3), dark_timber],
				[roof, Vector3(0, 3.7, 0.2), slate],
				[_box(6.9, 0.18, 0.2), Vector3(0, 2.95, -2.85), timber],
				# a timber awning out over the stools, on two posts with lanterns
				[_box(6.4, 0.08, 1.7), Vector3(0, 2.72, -3.55), timber, Basis(Vector3(1, 0, 0), -0.18)],
				[_cyl(0.08, 0.08, 2.6, 8), Vector3(-2.9, 1.3, -4.2), timber],
				[_cyl(0.08, 0.08, 2.6, 8), Vector3(2.9, 1.3, -4.2), timber],
				[_sphere(0.11, 8, 4), Vector3(-2.9, 2.45, -4.2), lamp_glow()],
				[_sphere(0.11, 8, 4), Vector3(2.9, 2.45, -4.2), lamp_glow()],
				# the counter, its polished top, and two taps
				[_box(4.6, 1.05, 0.7), Vector3(0, 0.82, -1.6), dark_timber],
				[_box(4.8, 0.08, 0.86), Vector3(0, 1.38, -1.6), polished],
				[_cyl(0.03, 0.03, 0.3, 6), Vector3(0.7, 1.55, -1.5), steel],
				[_box(0.05, 0.14, 0.05), Vector3(0.7, 1.77, -1.5), paint(Color(0.1, 0.1, 0.1), 0.4)],
				[_cyl(0.03, 0.03, 0.3, 6), Vector3(1.1, 1.55, -1.5), steel],
				[_box(0.05, 0.14, 0.05), Vector3(1.1, 1.77, -1.5), paint(Color(0.1, 0.1, 0.1), 0.4)],
				# the back bar: a warm lit panel behind two shelves of bottles
				[_box(4.4, 1.0, 0.03), Vector3(0, 1.95, 2.03), lamp_glow()],
				[_box(4.4, 0.06, 0.35), Vector3(0, 1.5, 1.88), timber],
				[_box(4.4, 0.06, 0.35), Vector3(0, 2.0, 1.88), timber],
				# the sign on the gable: a pint with a head on it
				[_box(1.8, 0.6, 0.1), Vector3(0, 3.5, -2.88), paint(Color(0.08, 0.3, 0.16), 0.5)],
				[_box(1.9, 0.7, 0.06), Vector3(0, 3.5, -2.85), paint(Color(0.9, 0.85, 0.7), 0.5)],
				[_cyl(0.11, 0.09, 0.3, 10), Vector3(0, 3.45, -2.97), amber],
				[_cyl(0.12, 0.12, 0.07, 10), Vector3(0, 3.63, -2.97), white],
			]
			var bottles := [Color(0.65, 0.4, 0.12), Color(0.12, 0.4, 0.2), Color(0.3, 0.12, 0.08), Color(0.85, 0.8, 0.7), Color(0.55, 0.12, 0.15)]
			for row in 2:
				for k in 9:
					var bc: Color = bottles[(k + row * 2) % bottles.size()]
					parts.append([_cyl(0.045, 0.05, 0.3, 6), Vector3(-1.9 + k * 0.475, 1.68 + row * 0.5, 1.88), paint(bc, 0.2)])
					parts.append([_cyl(0.018, 0.03, 0.09, 6), Vector3(-1.9 + k * 0.475, 1.87 + row * 0.5, 1.88), paint(bc, 0.2)])
			for k in 4:
				var sx := -1.5 + k * 1.0
				parts.append([_cyl(0.21, 0.21, 0.07, 10), Vector3(sx, 0.78, -2.35), leather])
				parts.append([_cyl(0.04, 0.04, 0.72, 6), Vector3(sx, 0.39, -2.35), steel])
				parts.append([_cyl(0.17, 0.17, 0.03, 10), Vector3(sx, 0.25, -2.35), steel])
		"o12":  # bridge
			parts = [[_box(5.3, 0.22, 5.3), Vector3(0, 0.56, 0), timber]]
			for sx: float in [-2.45, 2.45]:
				parts.append([_box(0.14, 0.14, 5.3), Vector3(sx, 1.5, 0), dark_timber])
				for sz: float in [-2.4, -0.8, 0.8, 2.4]:
					parts.append([_box(0.18, 1.0, 0.18), Vector3(sx, 1.05, sz), dark_timber])
		"o13":  # cart barn
			var roof := PrismMesh.new()
			roof.size = Vector3(7.8, 1.9, 5.8)
			parts = [
				[_box(7.2, 0.25, 5.2), Vector3(0, 0.12, 0), stone],
				[_box(7.0, 3.0, 5.0), Vector3(0, 1.75, 0), timber],
				[roof, Vector3(0, 4.2, 0), slate],
				[_box(3.4, 2.4, 0.14), Vector3(-1.3, 1.45, -2.52), white],
				[_box(1.2, 0.9, 0.12), Vector3(2.3, 2.2, -2.52), glass()],
			]
		"o14":  # putting green
			var turf := Surfaces.material("grass_ground", 0.5, Color(1.25, 2.6, 1.3))
			parts = [
				[_cyl(4.6, 4.7, 0.1, 24), Vector3(0, 0.05, 0), Surfaces.material("grass_ground", 0.5, Color(0.9, 1.9, 0.9))],
				[_cyl(4.2, 4.2, 0.13, 24), Vector3(0, 0.07, 0), turf],
			]
			for k in 3:
				var a := k * TAU / 3.0 + 0.4
				var at := Vector3(cos(a) * 2.3, 0, sin(a) * 2.3)
				parts.append([_cyl(0.02, 0.02, 1.1, 5), at + Vector3(0, 0.65, 0), white])
				parts.append([_box(0.36, 0.24, 0.02), at + Vector3(0.18, 1.06, 0), paint(Color(0.92, 0.75, 0.1))])
				parts.append([_cyl(0.07, 0.07, 0.02, 8), at + Vector3(0, 0.14, 0), paint(Color(0.03, 0.03, 0.03))])
		"o15":  # driving range
			parts = [
				[_box(8.4, 0.2, 3.4), Vector3(0, 0.1, 1.2), stone],
				[_box(8.4, 0.25, 3.4), Vector3(0, 2.85, 1.2), slate, Basis(Vector3(1, 0, 0), -0.1)],
				[_box(8.2, 2.6, 0.2), Vector3(0, 1.5, 2.7), timber],
			]
			for px: float in [-4.0, -1.35, 1.35, 4.0]:
				parts.append([_box(0.2, 2.7, 0.2), Vector3(px, 1.45, -0.3), dark_timber])
			for k in 3:
				parts.append([_box(1.5, 0.06, 1.7), Vector3(-2.7 + k * 2.7, 0.23, 0.7), Surfaces.material("grass_ground", 0.6, Color(1.0, 2.2, 1.1))])
				parts.append([_cyl(0.3, 0.26, 0.4, 10), Vector3(-3.4 + k * 2.7, 0.4, 1.8), paint(Color(0.2, 0.45, 0.25), 0.5)])
		"o16":  # fountain
			parts = [
				[_cyl(2.3, 2.4, 0.5, 24), Vector3(0, 0.25, 0), stone],
				[_cyl(2.0, 2.0, 0.12, 24), Vector3(0, 0.5, 0), pond()],
				[_cyl(0.24, 0.34, 1.7, 12), Vector3(0, 1.3, 0), stone],
				[_cyl(1.0, 0.45, 0.3, 16), Vector3(0, 2.25, 0), stone],
				[_cyl(0.85, 0.85, 0.06, 16), Vector3(0, 2.4, 0), pond()],
				[_cyl(0.1, 0.16, 0.7, 8), Vector3(0, 2.75, 0), stone],
				[_sphere(0.2, 10, 6), Vector3(0, 3.2, 0), pond()],
			]
		"o18":  # house
			var roof := PrismMesh.new()
			roof.size = Vector3(5.2, 2.0, 4.9)
			parts = [
				[_box(4.6, 0.3, 4.2), Vector3(0, 0.15, 0), stone],
				[_box(4.4, 2.8, 4.0), Vector3(0, 1.7, 0), plaster],
				[roof, Vector3(0, 4.1, 0), tiles],
				[_box(0.95, 2.0, 0.14), Vector3(0, 1.3, -2.02), dark_timber],
				[_box(0.6, 1.5, 0.6), Vector3(1.3, 4.6, 0.9), brick],
				[_box(1.5, 0.12, 1.0), Vector3(0, 0.2, -2.6), stone],
			]
			_window(parts, Vector3(-1.4, 2.0, -2.0), 0.95, 1.05)
			_window(parts, Vector3(1.4, 2.0, -2.0), 0.95, 1.05)
			_window(parts, Vector3(2.2, 2.0, 0.4), 0.95, 1.05, true)
			_window(parts, Vector3(-2.2, 2.0, -0.4), 0.95, 1.05, true)
		"o21":  # resort hotel
			var roof := PrismMesh.new()
			roof.size = Vector3(11.2, 2.6, 8.2)
			parts = [
				[_box(10.6, 0.5, 7.6), Vector3(0, 0.25, 0), stone],
				[_box(10.0, 9.6, 7.0), Vector3(0, 5.3, 0), plaster],
				[roof, Vector3(0, 11.4, 0), slate],
				[_box(4.4, 0.3, 3.2), Vector3(0, 3.4, -4.8), tiles],
				[_cyl(0.16, 0.18, 2.9, 10), Vector3(-1.9, 1.95, -6.1), white],
				[_cyl(0.16, 0.18, 2.9, 10), Vector3(1.9, 1.95, -6.1), white],
				[_box(2.2, 2.6, 0.2), Vector3(0, 1.8, -3.55), glass()],
			]
			for fl in 3:
				for wx: float in [-3.6, -1.2, 1.2, 3.6]:
					_window(parts, Vector3(wx, 4.75 + fl * 2.5, -3.5), 1.4, 1.3)
					_window(parts, Vector3(wx, 4.75 + fl * 2.5, 3.5), 1.4, 1.3)
				parts.append([_box(9.4, 0.14, 0.9), Vector3(0, 3.75 + fl * 2.5, -3.9), white])
		"o4":   # flower bed
			var soil := Surfaces.material("burned_ground_01", 0.5, Color(1.5, 1.2, 1.0))
			parts = [
				[_cyl(2.25, 2.35, 0.32, 24), Vector3(0, 0.16, 0), stone],
				[_cyl(2.0, 2.0, 0.36, 24), Vector3(0, 0.18, 0), soil],
				[Flora.flowers_mesh(), Vector3(0, 0.3, 0), null],
			]
		"o10":  # ball washer
			var red := paint(Color(0.72, 0.1, 0.1), 0.35)
			var steel := paint(Color(0.2, 0.2, 0.22), 0.4)
			parts = [
				[_cyl(0.42, 0.46, 0.08, 14), Vector3(0, 0.04, 0), stone],
				[_cyl(0.045, 0.055, 1.15, 8), Vector3(0, 0.62, 0), steel],
				[_cyl(0.17, 0.17, 0.5, 12), Vector3(0, 1.4, 0), red],
				[_sphere(0.17, 12, 6), Vector3(0, 1.65, 0), red],
				[_cyl(0.03, 0.03, 0.34, 6), Vector3(0, 1.9, 0), paint(Color(0.85, 0.85, 0.87), 0.3)],
				[_sphere(0.06, 8, 4), Vector3(0, 2.08, 0), paint(Color(0.1, 0.1, 0.1), 0.4)],
				[_box(0.2, 0.42, 0.03), Vector3(0.3, 1.2, 0), white],
				[_box(0.02, 0.02, 0.3), Vector3(0.3, 1.42, 0), steel],
				[_box(0.46, 0.3, 0.03), Vector3(0, 0.9, -0.08), paint(Color(0.1, 0.35, 0.18), 0.5)],
			]
		"o17":  # home site, for sale
			var earth := Surfaces.material("dry_ground_01", 0.35, Color(1.15, 1.0, 0.85))
			parts = [[_box(4.7, 0.05, 4.7), Vector3(0, 0.03, 0), earth]]
			for sx: float in [-2.2, 2.2]:
				for sz: float in [-2.2, 2.2]:
					parts.append([_cyl(0.04, 0.05, 0.9, 6), Vector3(sx, 0.45, sz), dark_timber])
					parts.append([_box(0.14, 0.1, 0.02), Vector3(sx + 0.07, 0.82, sz), paint(Color(0.95, 0.45, 0.1))])
				parts.append([_box(0.02, 0.02, 4.4), Vector3(sx, 0.7, 0), white])
			for sz: float in [-2.2, 2.2]:
				parts.append([_box(4.4, 0.02, 0.02), Vector3(0, 0.7, sz), white])
			parts.append([_box(0.09, 1.7, 0.09), Vector3(-0.62, 0.85, 0), timber])
			parts.append([_box(0.09, 1.7, 0.09), Vector3(0.62, 0.85, 0), timber])
			parts.append([_box(1.4, 0.85, 0.05), Vector3(0, 1.3, 0), white])
			parts.append([_box(1.4, 0.26, 0.06), Vector3(0, 1.58, 0), paint(Color(0.75, 0.12, 0.12))])
			parts.append([_box(0.9, 0.08, 0.06), Vector3(0, 1.22, 0), paint(Color(0.15, 0.15, 0.18))])
			parts.append([_box(0.6, 0.08, 0.06), Vector3(0, 1.05, 0), paint(Color(0.15, 0.15, 0.18))])
		"o20":  # tennis court
			var hard := paint(Color(0.16, 0.36, 0.55), 0.75)
			var apron := paint(Color(0.2, 0.42, 0.28), 0.8)
			var steel := paint(Color(0.25, 0.27, 0.28), 0.4)
			parts = [
				[_box(12.4, 0.08, 7.0), Vector3(0, 0.04, 0), apron],
				[_box(9.6, 0.09, 4.4), Vector3(0, 0.05, 0), hard],
				[_box(0.05, 0.8, 4.9), Vector3(0, 0.5, 0), paint(Color(0.9, 0.9, 0.9, 1.0), 0.9)],
				[_box(0.06, 0.06, 4.9), Vector3(0, 0.92, 0), white],
				[_cyl(0.05, 0.05, 1.0, 8), Vector3(0, 0.5, -2.5), steel],
				[_cyl(0.05, 0.05, 1.0, 8), Vector3(0, 0.5, 2.5), steel],
				[_box(1.2, 0.5, 0.4), Vector3(0, 0.25, 3.2), timber],
			]
			# court markings
			for lz: float in [-2.2, 2.2, -1.65, 1.65]:
				parts.append([_box(9.6, 0.1, 0.05), Vector3(0, 0.055, lz), white])
			for lx: float in [-4.8, 4.8, -2.6, 2.6]:
				parts.append([_box(0.05, 0.1, 4.4 if absf(lx) > 3.0 else 3.3), Vector3(lx, 0.055, 0), white])
			parts.append([_box(5.2, 0.1, 0.05), Vector3(0, 0.055, 0), white])
			# fence posts and rails at each end
			for ex: float in [-6.1, 6.1]:
				for ez: float in [-3.4, -1.7, 0.0, 1.7, 3.4]:
					parts.append([_cyl(0.04, 0.04, 2.6, 6), Vector3(ex, 1.3, ez), steel])
				parts.append([_box(0.04, 0.04, 6.8), Vector3(ex, 2.6, 0), steel])
				parts.append([_box(0.04, 0.04, 6.8), Vector3(ex, 1.3, 0), steel])
		"o23":  # airstrip
			var tarmac := Surfaces.material("gravel_floor_02", 0.5, Color(0.42, 0.42, 0.45))
			var hull := paint(Color(0.95, 0.95, 0.93), 0.3)
			var trim := paint(Color(0.75, 0.12, 0.12), 0.3)
			var body := CapsuleMesh.new()
			body.radius = 0.55
			body.height = 5.4
			body.radial_segments = 14
			body.rings = 6
			var lay := Basis(Vector3(1, 0, 0), PI * 0.5)
			parts = [
				[_box(7.0, 0.07, 26.0), Vector3(0, 0.035, 0), tarmac],
				[_cyl(0.06, 0.07, 4.2, 8), Vector3(5.0, 2.1, 10.0), paint(Color(0.8, 0.8, 0.82), 0.3)],
				[_cyl(0.42, 0.14, 1.7, 10), Vector3(5.85, 4.0, 10.0), paint(Color(0.95, 0.5, 0.1)), Basis(Vector3(0, 0, 1), PI * 0.5)],
				# a small plane parked at the far end
				[body, Vector3(-0.5, 1.25, -6.2), hull, lay],
				[_box(8.4, 0.12, 1.3), Vector3(-0.5, 1.75, -5.4), hull],
				[_box(8.4, 0.13, 0.3), Vector3(-0.5, 1.75, -4.9), trim],
				[_box(2.8, 0.1, 0.8), Vector3(-0.5, 1.5, -8.5), hull],
				[_box(0.1, 1.2, 0.9), Vector3(-0.5, 2.0, -8.5), trim],
				[_box(1.0, 0.5, 1.2), Vector3(-0.5, 1.72, -5.6), glass()],
				[_cyl(0.16, 0.24, 0.5, 10), Vector3(-0.5, 1.25, -3.4), paint(Color(0.15, 0.15, 0.17), 0.4), lay],
				[_box(2.0, 0.16, 0.05), Vector3(-0.5, 1.25, -3.12), paint(Color(0.1, 0.1, 0.1), 0.4), Basis(Vector3(0, 0, 1), 0.5)],
				[_cyl(0.24, 0.24, 0.14, 10), Vector3(-1.5, 0.3, -5.2), paint(Color(0.08, 0.08, 0.08), 0.8), Basis(Vector3(0, 0, 1), PI * 0.5)],
				[_cyl(0.24, 0.24, 0.14, 10), Vector3(0.5, 0.3, -5.2), paint(Color(0.08, 0.08, 0.08), 0.8), Basis(Vector3(0, 0, 1), PI * 0.5)],
				[_cyl(0.03, 0.03, 0.9, 6), Vector3(-1.5, 0.75, -5.2), paint(Color(0.6, 0.6, 0.62), 0.3)],
				[_cyl(0.03, 0.03, 0.9, 6), Vector3(0.5, 0.75, -5.2), paint(Color(0.6, 0.6, 0.62), 0.3)],
				[_cyl(0.14, 0.14, 0.1, 8), Vector3(-0.5, 0.2, -8.3), paint(Color(0.08, 0.08, 0.08), 0.8), Basis(Vector3(0, 0, 1), PI * 0.5)],
			]
			for k in 9:
				parts.append([_box(0.3, 0.08, 1.6), Vector3(0, 0.04, -10.4 + k * 2.6), white])
			for k in 6:
				parts.append([_box(0.45, 0.08, 2.2), Vector3(-2.6 + k * 1.04, 0.04, 11.4), white])
		"windmill":
			var cap := _cyl(0.0, 2.0, 1.9, 16)
			parts = [
				[_cyl(2.7, 2.8, 0.5, 16), Vector3(0, 0.25, 0), stone],
				[_cyl(1.55, 2.45, 8.0, 16), Vector3(0, 4.4, 0), plaster],
				[_cyl(1.9, 1.9, 0.18, 16), Vector3(0, 3.4, 0), dark_timber],
				[cap, Vector3(0, 9.35, 0), slate],
				[_box(1.0, 1.9, 0.2), Vector3(0, 1.45, -2.32), dark_timber],
				[_cyl(0.14, 0.14, 1.6, 8), Vector3(0, 7.4, -1.9), dark_timber, Basis(Vector3(1, 0, 0), PI * 0.5)],
				[_sphere(0.3, 10, 5), Vector3(0, 7.4, -2.7), paint(Color(0.2, 0.17, 0.15))],
			]
			_window(parts, Vector3(0, 5.6, -1.92), 0.6, 0.8)
			_window(parts, Vector3(1.98, 5.2, 0), 0.6, 0.8, true)
			for k in 4:
				var ang := k * PI * 0.5 + 0.35
				var bz := Basis(Vector3(0, 0, 1), ang)
				var hub := Vector3(0, 7.4, -2.62)
				parts.append([_box(0.12, 5.6, 0.1), hub + bz * Vector3(0, 2.9, 0), dark_timber, bz])
				parts.append([_box(0.06, 4.4, 0.06), hub + bz * Vector3(0.95, 3.4, 0), timber, bz])
				for rung in 9:
					parts.append([_box(0.95, 0.05, 0.05), hub + bz * Vector3(0.47, 1.3 + rung * 0.52, 0), timber, bz])
				parts.append([_box(0.9, 4.3, 0.02), hub + bz * Vector3(0.48, 3.4, 0.04), paint(Color(0.9, 0.87, 0.78), 0.9), bz])
		"stones":
			var grey := Color(0.5, 0.5, 0.47)
			for k in 8:
				var a := k * TAU / 8.0 + 0.2
				var hgt := 1.5 + (k * 7 % 4) * 0.28
				parts.append([Flora.stone_mesh(Vector3(0.62, hgt, 0.42), grey.darkened((k % 3) * 0.06), 20 + k), Vector3(cos(a) * 3.4, 0.0, sin(a) * 3.4), null, -a + PI * 0.5])
			parts.append([Flora.stone_mesh(Vector3(1.7, 0.36, 0.5), grey.lightened(0.04), 41), Vector3(cos(0.59) * 3.4, 3.0, sin(0.59) * 3.4), null, -0.59 + PI * 0.5])
			parts.append([Flora.stone_mesh(Vector3(1.3, 0.4, 0.8), grey.darkened(0.1), 43), Vector3(0.2, 0.0, 0.1), null, 0.4])
		"arch":
			var sand := Color(0.74, 0.44, 0.27)
			parts = [
				[Flora.stone_mesh(Vector3(1.3, 3.6, 1.2), sand, 51), Vector3(-3.0, 0.0, 0.0), null],
				[Flora.stone_mesh(Vector3(1.1, 3.2, 1.1), sand.darkened(0.06), 52), Vector3(3.1, 0.0, 0.1), null],
				[Flora.stone_mesh(Vector3(4.6, 0.95, 1.25), sand.lightened(0.05), 53), Vector3(0.0, 5.3, 0.0), null, Basis(Vector3(0, 0, 1), -0.05)],
				[Flora.stone_mesh(Vector3(1.4, 0.8, 1.2), sand.darkened(0.12), 54), Vector3(-4.2, 0.0, 1.1), null],
				[Flora.stone_mesh(Vector3(0.8, 0.5, 0.7), sand.darkened(0.08), 55), Vector3(4.3, 0.0, -1.0), null],
			]
		"tiki":
			var ember := glow(Color(1.0, 0.5, 0.08))
			parts = [
				[_cyl(1.3, 1.4, 0.5, 14), Vector3(0, 0.25, 0), Flora.rock],
				[_cyl(0.85, 1.0, 1.3, 14), Vector3(0, 1.15, 0), dark_timber],
				[_cyl(1.0, 0.9, 2.5, 14), Vector3(0, 3.05, 0), timber],
				[_cyl(1.15, 1.05, 0.4, 14), Vector3(0, 4.5, 0), dark_timber],
				[_cyl(0.0, 1.0, 1.5, 10), Vector3(0, 5.45, 0), paint(Color(0.7, 0.16, 0.1))],
				[_box(0.46, 0.34, 0.2), Vector3(-0.42, 3.5, -0.9), ember],
				[_box(0.46, 0.34, 0.2), Vector3(0.42, 3.5, -0.9), ember],
				[_box(0.9, 0.12, 0.2), Vector3(-0.42, 3.78, -0.92), dark_timber, Basis(Vector3(0, 0, 1), -0.25)],
				[_box(0.9, 0.12, 0.2), Vector3(0.42, 3.78, -0.92), dark_timber, Basis(Vector3(0, 0, 1), 0.25)],
				[_box(0.34, 0.8, 0.34), Vector3(0, 3.0, -1.0), dark_timber],
				[_box(1.3, 0.42, 0.2), Vector3(0, 2.25, -0.92), paint(Color(0.93, 0.9, 0.8))],
				[_box(1.3, 0.05, 0.22), Vector3(0, 2.25, -0.93), dark_timber],
			]
			for tooth in 5:
				parts.append([_box(0.04, 0.42, 0.22), Vector3(-0.44 + tooth * 0.22, 2.25, -0.93), dark_timber])
		"o24":  # floodlight: a steel mast with a rack of lamps facing both ways
			var steel := paint(Color(0.56, 0.58, 0.6), 0.35)
			var iron := paint(Color(0.12, 0.13, 0.14), 0.5)
			parts = [
				[_cyl(0.34, 0.38, 0.5, 12), Vector3(0, 0.25, 0), stone],
				[_cyl(0.09, 0.17, 13.6, 10), Vector3(0, 7.2, 0), steel],
				[_box(2.9, 0.1, 0.1), Vector3(0, 13.95, 0), steel],
				[_box(2.9, 0.1, 0.1), Vector3(0, 13.3, 0), steel],
				[_box(0.08, 0.75, 0.08), Vector3(-1.42, 13.62, 0), steel],
				[_box(0.08, 0.75, 0.08), Vector3(1.42, 13.62, 0), steel],
			]
			for row in 2:
				for col in 3:
					var at := Vector3(-0.95 + col * 0.95, 13.95 - row * 0.65, 0.0)
					for face: float in [-1.0, 1.0]:
						var tilt := Basis(Vector3(1, 0, 0), face * 0.6)
						var head := at + Vector3(0, 0, face * 0.24)
						parts.append([_box(0.52, 0.38, 0.3), head, iron, tilt])
						parts.append([_box(0.44, 0.3, 0.04), head + tilt * Vector3(0, 0, face * 0.16), lamp_glow(), tilt])
		"o25":  # lamp post
			var iron := paint(Color(0.09, 0.1, 0.11), 0.45)
			parts = [
				[_cyl(0.12, 0.16, 0.45, 10), Vector3(0, 0.22, 0), iron],
				[_cyl(0.045, 0.065, 2.75, 10), Vector3(0, 1.8, 0), iron],
				[_cyl(0.1, 0.05, 0.12, 10), Vector3(0, 3.2, 0), iron],
				[_cyl(0.17, 0.11, 0.36, 6), Vector3(0, 3.44, 0), lamp_glow()],
				[_cyl(0.03, 0.22, 0.16, 6), Vector3(0, 3.7, 0), iron],
				[_sphere(0.04, 8, 4), Vector3(0, 3.8, 0), iron],
			]
		"o22":  # marina
			parts = [
				[_box(9.0, 0.26, 2.2), Vector3(0, 0.5, 0), timber],
				[_box(2.2, 0.26, 6.0), Vector3(-3.0, 0.5, -3.6), timber],
				[_box(2.2, 0.26, 6.0), Vector3(3.0, 0.5, -3.6), timber],
				[_box(3.0, 2.3, 2.4), Vector3(0, 1.75, 1.6), plaster],
				[_cyl(0.0, 2.4, 1.2, 4), Vector3(0, 3.5, 1.6), slate, PI * 0.25],
				[_box(1.4, 0.7, 3.6), Vector3(-0.2, 0.55, -4.0), white],
				[_cyl(0.05, 0.05, 4.2, 6), Vector3(-0.2, 2.7, -4.0), paint(Color(0.75, 0.75, 0.78), 0.3)],
				[_box(0.04, 2.8, 1.7), Vector3(-0.2, 3.1, -3.15), paint(Color(0.95, 0.95, 0.9))],
			]
		"o28":  # litter bin: a dark tub with an open top
			var dark := paint(Color(0.12, 0.13, 0.14), 0.55)
			var lid := paint(Color(0.22, 0.24, 0.22), 0.5)
			parts = [
				[_box(0.7, 0.08, 0.55), Vector3(0, 0.04, 0), dark],
				[_box(0.62, 0.9, 0.48), Vector3(0, 0.52, 0), dark],
				[_box(0.66, 0.06, 0.52), Vector3(0, 0.98, 0), lid],
				[_box(0.4, 0.04, 0.08), Vector3(0, 0.78, -0.26), lid],
			]
	return parts


static func _unused() -> void:
	pass


static var biome: Dictionary = {}


## The model for an object type. Trees, bushes, boulders and the landmark
## change with the biome.
static func object_mesh(o: int) -> Mesh:
	var over: Dictionary = biome.get("objects", {}).get(str(o), {})
	var kind := str(over.get("mesh", "o%d" % o))
	var id := "obj_" + kind
	if _meshes.has(id):
		return _meshes[id]
	var m := compose(_parts(kind), o != Defs.O.CLUBHOUSE)
	_meshes[id] = m
	return m


static func _tilt(yaw: float, pitch: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), pitch)


static func _parts(kind: String) -> Array:
	var built := _built(kind)
	if not built.is_empty():
		return built
	var wood := Color(0.5, 0.35, 0.2)
	var cream := Color(0.95, 0.92, 0.82)
	var stone := Color(0.72, 0.72, 0.69)
	var parts := []
	match kind:
		"oak":
			parts = [
				[_cyl(0.28, 0.42, 3.4), Vector3(0, 1.7, 0), Color(0.36, 0.25, 0.15)],
				[_sphere(3.1, 9, 5), Vector3(0, 5.6, 0), Color(0.20, 0.44, 0.16)],
				[_sphere(2.1, 8, 4), Vector3(1.5, 4.5, 0.9), Color(0.23, 0.49, 0.18)],
				[_sphere(1.9, 8, 4), Vector3(-1.3, 4.8, -1.0), Color(0.17, 0.40, 0.15)],
			]
		"pine":
			parts = [
				[_cyl(0.2, 0.3, 2.0, 6), Vector3(0, 1.0, 0), Color(0.33, 0.22, 0.14)],
				[_cyl(0.0, 2.4, 5.0), Vector3(0, 4.0, 0), Color(0.10, 0.31, 0.19)],
				[_cyl(0.0, 1.8, 4.0), Vector3(0, 7.0, 0), Color(0.12, 0.35, 0.21)],
				[_cyl(0.0, 1.1, 3.0), Vector3(0, 9.6, 0), Color(0.14, 0.38, 0.23)],
			]
		"bush":
			parts = [
				[_sphere(1.2, 8, 4), Vector3(0, 0.7, 0), Color(0.22, 0.46, 0.2)],
				[_sphere(0.8, 7, 3), Vector3(0.8, 0.55, 0.4), Color(0.26, 0.5, 0.22)],
			]
		"birch":
			parts = [
				[_cyl(0.16, 0.24, 5.4, 6), Vector3(0, 2.7, 0), Color(0.92, 0.92, 0.87)],
				[_sphere(1.9, 8, 4), Vector3(0, 6.0, 0), Color(0.52, 0.70, 0.28)],
				[_sphere(1.4, 7, 4), Vector3(0.5, 7.5, 0.3), Color(0.58, 0.75, 0.32)],
				[_sphere(1.2, 7, 3), Vector3(-0.9, 5.2, -0.5), Color(0.48, 0.66, 0.26)],
			]
		"scots":
			parts = [
				[_cyl(0.22, 0.34, 7.4, 6), Vector3(0, 3.7, 0), Color(0.55, 0.32, 0.22)],
				[_sphere(3.0, 9, 4), Vector3(0, 8.2, 0), Color(0.11, 0.30, 0.22), Basis.from_scale(Vector3(1.0, 0.42, 1.0))],
				[_sphere(1.8, 8, 3), Vector3(1.4, 7.2, 0.8), Color(0.13, 0.34, 0.24), Basis.from_scale(Vector3(1.0, 0.45, 1.0))],
			]
		"gorse":
			parts = [
				[_sphere(1.2, 8, 4), Vector3(0, 0.6, 0), Color(0.22, 0.36, 0.14)],
				[_sphere(0.75, 7, 3), Vector3(0.2, 1.15, 0.1), Color(0.92, 0.80, 0.18)],
				[_sphere(0.5, 6, 3), Vector3(-0.7, 0.9, 0.5), Color(0.92, 0.80, 0.18)],
			]
		"palm":
			parts = [[_cyl(0.2, 0.32, 7.0, 6), Vector3(0, 3.5, 0), Color(0.62, 0.5, 0.32)]]
			for k in 6:
				var yaw := k * TAU / 6.0
				var b := _tilt(yaw, -0.45)
				parts.append([_box(3.4, 0.1, 0.8), Vector3(0, 7.0, 0) + Basis(Vector3.UP, yaw) * Vector3(1.5, -0.35, 0), Color(0.18, 0.52, 0.20), b])
			parts.append([_sphere(0.45, 6, 3), Vector3(0, 6.9, 0), Color(0.35, 0.26, 0.14)])
		"cactus":
			parts = [
				[_cyl(0.42, 0.48, 5.0, 8), Vector3(0, 2.5, 0), Color(0.24, 0.50, 0.26)],
				[_sphere(0.42, 8, 3), Vector3(0, 5.0, 0), Color(0.24, 0.50, 0.26)],
				[_cyl(0.26, 0.26, 1.3, 6), Vector3(0.75, 2.6, 0), Color(0.22, 0.47, 0.24), Basis(Vector3(0, 0, 1), PI * 0.5)],
				[_cyl(0.26, 0.28, 1.7, 6), Vector3(1.35, 3.4, 0), Color(0.24, 0.50, 0.26)],
				[_cyl(0.24, 0.24, 1.1, 6), Vector3(-0.65, 1.9, 0), Color(0.22, 0.47, 0.24), Basis(Vector3(0, 0, 1), PI * 0.5)],
				[_cyl(0.24, 0.26, 1.3, 6), Vector3(-1.15, 2.5, 0), Color(0.24, 0.50, 0.26)],
			]
		"scrub":
			parts = [
				[_sphere(0.9, 7, 3), Vector3(0, 0.35, 0), Color(0.50, 0.46, 0.26), Basis.from_scale(Vector3(1.0, 0.6, 1.0))],
				[_sphere(0.6, 6, 3), Vector3(0.7, 0.3, 0.3), Color(0.42, 0.44, 0.24), Basis.from_scale(Vector3(1.0, 0.6, 1.0))],
			]
		"deadtree":
			var char_c := Color(0.13, 0.11, 0.10)
			parts = [
				[_cyl(0.18, 0.4, 5.2, 6), Vector3(0, 2.6, 0), char_c],
				[_box(0.16, 2.4, 0.16), Vector3(0.75, 4.6, 0), char_c, Basis(Vector3(0, 0, 1), -0.75)],
				[_box(0.14, 2.0, 0.14), Vector3(-0.6, 3.9, 0.2), char_c, Basis(Vector3(0, 0, 1), 0.8)],
				[_box(0.12, 1.6, 0.12), Vector3(0.1, 5.4, -0.5), char_c, Basis(Vector3(1, 0, 0), 0.7)],
			]
		"fern":
			parts = [
				[_cyl(1.5, 0.15, 1.0, 7), Vector3(0, 0.5, 0), Color(0.14, 0.50, 0.22)],
				[_cyl(0.9, 0.1, 0.8, 6), Vector3(0, 0.9, 0), Color(0.18, 0.58, 0.26)],
			]
		"boulder", "boulder_red", "boulder_black":
			var rc := Color(0.55, 0.55, 0.52)
			if kind == "boulder_red":
				rc = Color(0.62, 0.36, 0.22)
			elif kind == "boulder_black":
				rc = Color(0.15, 0.13, 0.13)
			parts = [
				[_sphere(1.6, 6, 3), Vector3(0, 0.7, 0), rc, Basis.from_scale(Vector3(1.0, 0.75, 0.85))],
				[_sphere(0.9, 5, 3), Vector3(1.2, 0.4, 0.6), rc.darkened(0.15), Basis.from_scale(Vector3(1.0, 0.7, 1.0))],
			]
		"o4":   # flower bed
			parts = [[_box(4.2, 0.25, 4.2), Vector3(0, 0.12, 0), Color(0.3, 0.2, 0.12)]]
			var colors := [Color(0.95, 0.3, 0.4), Color(1.0, 0.8, 0.2), Color(0.75, 0.4, 0.9)]
			for k in 9:
				var a := k * 2.4
				var r := 0.6 + (k % 3) * 0.55
				parts.append([_sphere(0.38, 6, 3), Vector3(cos(a) * r, 0.45, sin(a) * r), colors[k % 3]])
		"o5":   # bench
			parts = [
				[_box(2.2, 0.12, 0.6), Vector3(0, 0.5, 0), wood],
				[_box(2.2, 0.55, 0.1), Vector3(0, 0.85, -0.3), wood],
				[_box(0.12, 0.5, 0.5), Vector3(-0.9, 0.25, 0), Color(0.2, 0.2, 0.2)],
				[_box(0.12, 0.5, 0.5), Vector3(0.9, 0.25, 0), Color(0.2, 0.2, 0.2)],
			]
		"o6":   # drink stand
			parts = [
				[_box(3.0, 2.2, 3.0), Vector3(0, 1.1, 0), cream],
				[_box(3.5, 0.14, 3.5), Vector3(0, 1.15, 0), Color(0.45, 0.3, 0.18)],
				[_cyl(0.0, 2.8, 1.5, 4), Vector3(0, 2.95, 0), Color(0.2, 0.5, 0.85), PI * 0.25],
			]
		"o7":   # restroom
			parts = [
				[_box(4.0, 2.6, 3.2), Vector3(0, 1.3, 0), Color(0.72, 0.8, 0.85)],
				[_box(4.4, 0.25, 3.6), Vector3(0, 2.72, 0), Color(0.25, 0.3, 0.35)],
				[_box(0.9, 1.9, 0.1), Vector3(-0.9, 0.95, -1.62), Color(0.2, 0.25, 0.3)],
				[_box(0.9, 1.9, 0.1), Vector3(0.9, 0.95, -1.62), Color(0.2, 0.25, 0.3)],
			]
		"o8":   # clubhouse
			var prism := PrismMesh.new()
			prism.size = Vector3(17.5, 3.4, 10.5)
			parts = [
				[_box(16.0, 5.0, 9.0), Vector3(0, 2.5, 0), Color(0.93, 0.9, 0.82)],
				[prism, Vector3(0, 6.7, 0), Color(0.5, 0.18, 0.14)],
				[_box(10.5, 0.3, 3.4), Vector3(0, 0.15, -6.0), wood],
				[_box(10.9, 0.25, 3.8), Vector3(0, 3.3, -6.0), Color(0.5, 0.18, 0.14)],
				[_box(0.3, 3.2, 0.3), Vector3(-5.0, 1.6, -7.5), Color(0.95, 0.95, 0.95)],
				[_box(0.3, 3.2, 0.3), Vector3(5.0, 1.6, -7.5), Color(0.95, 0.95, 0.95)],
				[_box(1.8, 2.7, 0.2), Vector3(0, 1.35, -4.6), Color(0.3, 0.2, 0.12)],
				[_box(2.4, 1.5, 0.2), Vector3(-4.6, 2.6, -4.6), Color(0.25, 0.4, 0.55)],
				[_box(2.4, 1.5, 0.2), Vector3(4.6, 2.6, -4.6), Color(0.25, 0.4, 0.55)],
			]
		"o9":   # snack bar
			parts = [
				[_box(4.6, 2.6, 3.6), Vector3(0, 1.3, 0.4), cream],
				[_box(5.0, 0.2, 4.2), Vector3(0, 2.7, 0.4), Color(0.35, 0.22, 0.14)],
				[_box(5.0, 0.16, 1.8), Vector3(0, 2.3, -2.0), Color(0.95, 0.55, 0.15), Basis(Vector3(1, 0, 0), -0.25)],
				[_box(4.4, 0.14, 0.7), Vector3(0, 1.1, -1.6), Color(0.45, 0.3, 0.18)],
				[_box(2.2, 0.8, 0.16), Vector3(0, 3.3, -1.2), Color(0.85, 0.2, 0.2)],
			]
		"o10":  # ball washer
			parts = [
				[_cyl(0.07, 0.09, 1.3, 6), Vector3(0, 0.65, 0), Color(0.2, 0.2, 0.22)],
				[_box(0.42, 0.55, 0.34), Vector3(0, 1.35, 0), Color(0.85, 0.15, 0.15)],
				[_cyl(0.05, 0.05, 0.4, 5), Vector3(0, 1.8, 0), Color(0.9, 0.9, 0.9)],
			]
		"o12":  # bridge
			parts = [
				[_box(5.3, 0.28, 5.3), Vector3(0, 0.55, 0), wood],
				[_box(0.3, 1.0, 0.3), Vector3(-2.4, 1.0, -2.4), wood.darkened(0.25)],
				[_box(0.3, 1.0, 0.3), Vector3(2.4, 1.0, -2.4), wood.darkened(0.25)],
				[_box(0.3, 1.0, 0.3), Vector3(-2.4, 1.0, 2.4), wood.darkened(0.25)],
				[_box(0.3, 1.0, 0.3), Vector3(2.4, 1.0, 2.4), wood.darkened(0.25)],
			]
		"o13":  # cart barn
			var roof := PrismMesh.new()
			roof.size = Vector3(7.6, 1.7, 5.6)
			parts = [
				[_box(7.0, 3.0, 5.0), Vector3(0, 1.5, 0), Color(0.42, 0.52, 0.44)],
				[roof, Vector3(0, 3.85, 0), Color(0.22, 0.26, 0.24)],
				[_box(3.2, 2.3, 0.14), Vector3(-1.4, 1.15, -2.52), Color(0.9, 0.9, 0.86)],
				[_box(1.5, 0.6, 1.0), Vector3(2.3, 0.6, -3.6), Color(0.95, 0.95, 0.95)],
				[_box(1.4, 0.08, 1.0), Vector3(2.3, 1.6, -3.6), Color(0.2, 0.5, 0.3)],
			]
		"o14":  # putting green
			parts = [[_cyl(4.4, 4.4, 0.14, 16), Vector3(0, 0.07, 0), Color(0.42, 0.78, 0.38)]]
			for k in 3:
				var a := k * TAU / 3.0 + 0.4
				var at := Vector3(cos(a) * 2.4, 0, sin(a) * 2.4)
				parts.append([_cyl(0.03, 0.03, 1.0, 5), at + Vector3(0, 0.6, 0), Color(0.95, 0.95, 0.9)])
				parts.append([_box(0.4, 0.26, 0.03), at + Vector3(0.2, 0.95, 0), Color(0.9, 0.75, 0.1)])
		"o15":  # driving range
			parts = [
				[_box(8.0, 0.3, 3.0), Vector3(0, 2.6, 1.2), Color(0.3, 0.38, 0.32)],
				[_box(8.0, 2.5, 0.2), Vector3(0, 1.25, 2.6), wood],
				[_box(0.25, 2.5, 0.25), Vector3(-3.8, 1.25, -0.2), wood],
				[_box(0.25, 2.5, 0.25), Vector3(3.8, 1.25, -0.2), wood],
			]
			for k in 4:
				parts.append([_box(1.3, 0.08, 1.6), Vector3(-3.0 + k * 2.0, 0.05, 0.6), Color(0.25, 0.6, 0.3)])
				parts.append([_sphere(0.28, 6, 3), Vector3(-3.4 + k * 2.0, 0.25, 1.9), Color(0.95, 0.9, 0.3)])
		"o16":  # fountain
			parts = [
				[_cyl(2.1, 2.2, 0.55, 14), Vector3(0, 0.28, 0), stone],
				[_cyl(1.85, 1.85, 0.12, 14), Vector3(0, 0.56, 0), Color(0.3, 0.6, 0.85)],
				[_cyl(0.22, 0.3, 1.7, 8), Vector3(0, 1.3, 0), stone],
				[_cyl(0.95, 0.5, 0.3, 10), Vector3(0, 2.2, 0), stone],
				[_sphere(0.35, 8, 4), Vector3(0, 2.55, 0), Color(0.55, 0.8, 0.95)],
			]
		"o17":  # home site, for sale
			parts = [[_box(4.6, 0.06, 4.6), Vector3(0, 0.03, 0), Color(0.45, 0.33, 0.22)]]
			for sx: float in [-2.1, 2.1]:
				for sz: float in [-2.1, 2.1]:
					parts.append([_cyl(0.05, 0.05, 0.9, 4), Vector3(sx, 0.45, sz), Color(0.9, 0.3, 0.2)])
			parts.append([_cyl(0.05, 0.05, 1.4, 5), Vector3(0, 0.7, 0), Color(0.9, 0.9, 0.9)])
			parts.append([_box(1.3, 0.8, 0.06), Vector3(0, 1.5, 0), Color(0.95, 0.95, 0.9)])
			parts.append([_box(1.1, 0.25, 0.07), Vector3(0, 1.55, 0), Color(0.85, 0.15, 0.15)])
		"o18":  # house
			var hroof := PrismMesh.new()
			hroof.size = Vector3(4.9, 1.9, 4.7)
			parts = [
				[_box(4.4, 2.9, 4.0), Vector3(0, 1.45, 0), cream],
				[hroof, Vector3(0, 3.85, 0), Color(0.62, 0.3, 0.2)],
				[_box(0.9, 1.9, 0.12), Vector3(0, 0.95, -2.02), Color(0.3, 0.2, 0.14)],
				[_box(0.9, 0.9, 0.12), Vector3(-1.4, 1.7, -2.02), Color(0.3, 0.45, 0.6)],
				[_box(0.9, 0.9, 0.12), Vector3(1.4, 1.7, -2.02), Color(0.3, 0.45, 0.6)],
				[_box(0.5, 1.4, 0.5), Vector3(1.3, 4.4, 0.8), Color(0.5, 0.3, 0.25)],
			]
		"o20":  # tennis courts
			parts = [
				[_box(11.0, 0.08, 6.0), Vector3(0, 0.04, 0), Color(0.2, 0.45, 0.7)],
				[_box(9.4, 0.1, 4.6), Vector3(0, 0.06, 0), Color(0.25, 0.6, 0.4)],
				[_box(0.08, 0.9, 4.8), Vector3(0, 0.5, 0), Color(0.95, 0.95, 0.95)],
				[_box(0.14, 2.6, 0.14), Vector3(-5.4, 1.3, -2.9), Color(0.3, 0.3, 0.3)],
				[_box(0.14, 2.6, 0.14), Vector3(5.4, 1.3, -2.9), Color(0.3, 0.3, 0.3)],
				[_box(0.14, 2.6, 0.14), Vector3(-5.4, 1.3, 2.9), Color(0.3, 0.3, 0.3)],
				[_box(0.14, 2.6, 0.14), Vector3(5.4, 1.3, 2.9), Color(0.3, 0.3, 0.3)],
			]
		"o21":  # resort hotel
			var top := PrismMesh.new()
			top.size = Vector3(10.6, 2.2, 7.6)
			parts = [
				[_box(10.0, 10.0, 7.0), Vector3(0, 5.0, 0), Color(0.95, 0.9, 0.8)],
				[top, Vector3(0, 11.1, 0), Color(0.45, 0.2, 0.18)],
				[_box(4.0, 0.3, 3.0), Vector3(0, 3.2, -4.6), Color(0.45, 0.2, 0.18)],
				[_box(2.0, 2.8, 0.2), Vector3(0, 1.4, -3.55), Color(0.25, 0.18, 0.12)],
			]
			for fl in 3:
				parts.append([_box(8.6, 1.1, 0.16), Vector3(0, 4.4 + fl * 2.4, -3.52), Color(0.3, 0.45, 0.6)])
		"o22":  # marina
			parts = [
				[_box(9.0, 0.3, 2.2), Vector3(0, 0.5, 0), wood],
				[_box(2.2, 0.3, 6.0), Vector3(-3.0, 0.5, -3.6), wood],
				[_box(2.2, 0.3, 6.0), Vector3(3.0, 0.5, -3.6), wood],
				[_box(3.0, 2.4, 2.4), Vector3(0, 1.7, 1.6), cream],
				[_cyl(0.0, 2.3, 1.2, 4), Vector3(0, 3.5, 1.6), Color(0.2, 0.4, 0.7), PI * 0.25],
				[_box(1.4, 0.7, 3.6), Vector3(-0.2, 0.55, -4.0), Color(0.95, 0.95, 0.95)],
				[_cyl(0.05, 0.05, 4.0, 5), Vector3(-0.2, 2.6, -4.0), Color(0.6, 0.6, 0.6)],
				[_box(0.05, 2.6, 1.6), Vector3(-0.2, 3.0, -3.2), Color(0.95, 0.3, 0.25)],
			]
		"o23":  # airstrip
			parts = [
				[_box(7.0, 0.08, 26.0), Vector3(0, 0.04, 0), Color(0.3, 0.3, 0.32)],
				[_box(0.3, 0.1, 22.0), Vector3(0, 0.06, 0), Color(0.95, 0.95, 0.9)],
				[_cyl(0.07, 0.07, 4.0, 5), Vector3(5.0, 2.0, 10.0), Color(0.8, 0.8, 0.8)],
				[_cyl(0.5, 0.15, 1.6, 6), Vector3(5.8, 3.8, 10.0), Color(0.95, 0.5, 0.1), Basis(Vector3(0, 0, 1), PI * 0.5)],
				[_box(1.1, 1.1, 5.0), Vector3(-0.5, 1.2, -6.0), Color(0.95, 0.95, 0.95)],
				[_box(8.0, 0.14, 1.3), Vector3(-0.5, 1.5, -5.5), Color(0.85, 0.2, 0.2)],
				[_box(2.6, 0.12, 0.8), Vector3(-0.5, 1.6, -8.2), Color(0.85, 0.2, 0.2)],
				[_box(0.12, 1.2, 0.9), Vector3(-0.5, 2.0, -8.2), Color(0.85, 0.2, 0.2)],
			]
		"windmill":
			parts = [
				[_cyl(1.5, 2.4, 8.0, 8), Vector3(0, 4.0, 0), Color(0.94, 0.93, 0.88)],
				[_cyl(0.0, 1.9, 1.8, 8), Vector3(0, 8.9, 0), Color(0.6, 0.2, 0.16)],
				[_box(0.9, 1.8, 0.15), Vector3(0, 0.9, -2.3), Color(0.3, 0.2, 0.14)],
				[_sphere(0.4, 6, 3), Vector3(0, 7.2, -1.9), Color(0.25, 0.2, 0.18)],
			]
			for k in 4:
				var ang := k * PI * 0.5 + 0.35
				var bz := Basis(Vector3(0, 0, 1), ang)
				parts.append([_box(0.7, 5.0, 0.08), Vector3(0, 7.2, -2.1) + bz * Vector3(0, 2.6, 0), Color(0.85, 0.8, 0.7), bz])
		"stones":
			for k in 7:
				var a := k * TAU / 7.0
				var hgt := 2.6 + (k % 3) * 0.6
				parts.append([_box(1.0, hgt, 0.6), Vector3(cos(a) * 3.3, hgt * 0.5, sin(a) * 3.3), Color(0.55, 0.56, 0.54), -a + PI * 0.5])
			parts.append([_box(2.6, 0.5, 0.7), Vector3(cos(0.45) * 3.3, 3.5, sin(0.45) * 3.3), Color(0.5, 0.51, 0.5), -0.45 + PI * 0.5])
			parts.append([_box(1.6, 0.5, 2.6), Vector3(0, 0.25, 0), Color(0.48, 0.49, 0.47)])
		"arch":
			var sand := Color(0.78, 0.47, 0.28)
			parts = [
				[_box(1.8, 6.0, 1.8), Vector3(-2.8, 3.0, 0), sand],
				[_box(1.5, 5.4, 1.6), Vector3(2.9, 2.7, 0), sand.darkened(0.08)],
				[_box(7.6, 1.5, 1.9), Vector3(0, 6.3, 0), sand.lightened(0.06), Basis(Vector3(0, 0, 1), -0.06)],
				[_sphere(1.2, 6, 3), Vector3(-3.4, 0.5, 1.0), sand.darkened(0.15)],
			]
		"tiki":
			var tw := Color(0.42, 0.26, 0.14)
			parts = [
				[_box(1.8, 1.2, 1.8), Vector3(0, 0.6, 0), tw.darkened(0.2)],
				[_box(2.2, 2.6, 2.0), Vector3(0, 2.5, 0), tw],
				[_box(2.5, 0.45, 2.2), Vector3(0, 3.55, 0), tw.darkened(0.3)],
				[_box(0.5, 0.4, 0.12), Vector3(-0.55, 3.0, -1.02), Color(1.0, 0.55, 0.1)],
				[_box(0.5, 0.4, 0.12), Vector3(0.55, 3.0, -1.02), Color(1.0, 0.55, 0.1)],
				[_box(1.4, 0.45, 0.12), Vector3(0, 1.8, -1.02), Color(0.95, 0.93, 0.85)],
				[_box(0.35, 0.9, 0.3), Vector3(0, 2.5, -1.1), tw.darkened(0.25)],
				[_cyl(0.0, 1.0, 1.6, 6), Vector3(0, 4.6, 0), Color(0.85, 0.2, 0.15)],
			]
		_:
			parts = [[_box(2.0, 2.0, 2.0), Vector3(0, 1.0, 0), Color(1, 0, 1)]]
	return parts


# --------------------------------------------------------------- figures

# ----------------------------------------------------------------- setup

func _ready() -> void:
	add_child(_obj_root)
	add_child(_hole_root)
	add_child(_people_root)
	add_child(_fx_root)
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var seg := BoxMesh.new()
	seg.size = Vector3.ONE
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	_trail_mm.mesh = seg
	_trail_mm.instance_count = TRAIL_POOL
	_trail_mm.visible_instance_count = 0
	_trail_mi.multimesh = _trail_mm
	_trail_mi.material_override = _trail_mat
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mi.custom_aabb = AABB(Vector3(-4000, -200, -4000), Vector3(8000, 800, 8000))
	add_child(_trail_mi)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 0.95
	torus.rings = 40
	torus.ring_segments = 6
	_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.no_depth_test = true
	_ring.material_override = ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh("mound")
	_mounds.multimesh = mm
	_mounds.material_override = mat(Color(0.42, 0.3, 0.18))
	add_child(_mounds)
	var scrap := BoxMesh.new()
	scrap.size = Vector3(0.2, 0.02, 0.14)
	var lmm := MultiMesh.new()
	lmm.transform_format = MultiMesh.TRANSFORM_3D
	lmm.mesh = scrap
	_litter = MultiMeshInstance3D.new()
	_litter.multimesh = lmm
	var paper := StandardMaterial3D.new()
	paper.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paper.albedo_color = Color(0.92, 0.9, 0.84)
	_litter.material_override = paper
	_litter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_litter.visibility_range_end = 80.0
	add_child(_litter)
	_spots = MultiMeshInstance3D.new()
	var spots_mm := MultiMesh.new()
	spots_mm.transform_format = MultiMesh.TRANSFORM_3D
	spots_mm.mesh = _sphere(0.42, 10, 6)
	_spots.multimesh = spots_mm
	_spots.material_override = glow(Color(1.0, 0.95, 0.55))
	_spots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spots)
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = mesh("stake")
	_stakes.multimesh = smm
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.96, 0.96, 0.93)
	white.roughness = 0.6
	_stakes.material_override = white
	_stakes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stakes.visibility_range_end = 520.0
	_stakes.visibility_range_end_margin = 60.0
	_stakes.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_stakes)


func bind(s: Sim, camera_rig: CameraRig) -> void:
	sim = s
	rig = camera_rig
	WorldView.biome = s.biome
	selected = null
	for dict: Dictionary in [_figs, _staff_figs, _balls, _bubbles, _carts, _animals]:
		for key: Variant in dict:
			dict[key].queue_free()
		dict.clear()
	_trails.clear()
	_ball_turn.clear()
	_stakes_owned = -1
	_mound_set.clear()
	_mound_cursor = 0
	_mound_changed = true
	_litter_rev = -1
	for p in _popups:
		p.node.queue_free()
	_popups.clear()
	_objects_dirty = true
	_holes_dirty = true
	sim.course.objects_changed.connect(func() -> void: _objects_dirty = true)
	sim.course.holes_changed.connect(func() -> void: _holes_dirty = true)
	sim.lab.rated.connect(func(_hole: Hole) -> void: _holes_dirty = true)
	sim.course.heights_changed.connect(func(_r: Rect2i) -> void:
		_objects_dirty = true
		_holes_dirty = true
		_stakes_owned = -1)
	sim.course.tiles_changed.connect(func(_r: Rect2i) -> void:
		# buying land moves the boundary
		if sim.course.owned_parcels() != _stakes_owned:
			_stakes_owned = -1)
	sim.golfer_removed.connect(_on_golfer_removed)
	sim.staff_changed.connect(_on_staff_changed)
	sim.popup.connect(add_popup)


func _on_golfer_removed(g: Golfer) -> void:
	if _figs.has(g.id):
		_figs[g.id].queue_free()
		_figs.erase(g.id)
	if _balls.has(g.id):
		_balls[g.id].queue_free()
		_balls.erase(g.id)
	_ball_turn.erase(g.id)
	if _bubbles.has(g.id):
		_bubbles[g.id].queue_free()
		_bubbles.erase(g.id)
	_trails.erase(g.id)
	if selected == g:
		selected = null


func _on_staff_changed() -> void:
	var alive := {}
	for m in sim.crew.members:
		alive[m.id] = true
	for id: int in _staff_figs.keys():
		if not alive.has(id):
			_staff_figs[id].queue_free()
			_staff_figs.erase(id)


# ------------------------------------------------------------ per frame

## Lamps come on, lenses glow and windows light up as night falls.
func _show_night() -> void:
	var dark := sim.darkness()
	if absf(dark - _dark_shown) < 0.004:
		return
	_dark_shown = dark
	var on := dark > 0.03
	for pair: Array in _lamps:
		var lamp: OmniLight3D = pair[0]
		lamp.visible = on
		lamp.light_energy = float(pair[1]) * dark
	lamp_glow().emission_energy_multiplier = 7.0 * dark
	glass().emission_energy_multiplier = 1.8 * dark
	vend_glow().emission_energy_multiplier = 0.35 + 3.0 * dark


func _frame_world(delta: float) -> void:
	if sim == null or rig == null:
		return
	_clock += delta
	_dt = delta
	if _stakes_owned < 0:
		_rebuild_stakes()
	var wind_now := sim.weather.wind_vec()
	Flora.setup()
	Flora.foliage.set_shader_parameter("wind", Vector2(wind_now.x, wind_now.z) * 0.32)
	var t0 := Time.get_ticks_usec()
	if _objects_dirty:
		_objects_dirty = false
		_rebuild_objects()
		Game.prof("w.objects", t0)
	t0 = Time.get_ticks_usec()
	if _holes_dirty:
		_holes_dirty = false
		_rebuild_holes()
		Game.prof("w.holes", t0)
	_show_night()
	# life-size up close; larger than life from far away so people stay readable
	var k := lerpf(1.0, 1.45, smoothstep(22.0, 90.0, rig.dist)) * clampf(rig.dist / 210.0, 1.0, 3.0)
	var a := Game.alpha
	t0 = Time.get_ticks_usec()
	# People move at the simulation's pace: frozen when it is paused, and
	# striding faster when it runs fast, or the legs slide under them.
	var people_dt := 0.0 if Game.paused else delta * minf(float(Game.speed), 4.0)
	_update_people(k, a, people_dt)
	Game.prof("w.people", t0)
	_update_extras(k, a)
	t0 = Time.get_ticks_usec()
	_update_balls(k, a)
	Game.prof("w.balls", t0)
	t0 = Time.get_ticks_usec()
	_update_flags(k)
	_update_popups(delta)
	Game.prof("w.flags", t0)
	t0 = Time.get_ticks_usec()
	_scan_mounds()
	Game.prof("w.mounds", t0)
	_sync_litter()
	if selected != null:
		var p: Vector3 = selected.prev.lerp(selected.pos, a)
		_ring.visible = true
		_ring.position = p + Vector3(0, 0.06, 0)
		_ring.scale = Vector3.ONE * k * 0.6
	else:
		_ring.visible = false


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame_world(delta)
	Game.prof("world", t0)


func _update_people(k: float, a: float, delta: float) -> void:
	for g in sim.visitors.golfers:
		var fig: PersonFig = _figs.get(g.id)
		if fig == null:
			fig = PersonFig.new()
			fig.build(g.shirt, g.pants, g.skin, g.hat, "club", g.kind == "celebrity" or g.kind == "player", g.id * 7 + 3)
			_people_root.add_child(fig)
			_figs[g.id] = fig
			fig.rotation.y = -g.facing
		var facing := g.facing
		var putt: bool = g.plan.get("putt", false)
		if g.swing_t >= 0.0 or g.phase == Golfer.P.AIM or g.phase == Golfer.P.SWING:
			facing += PI * 0.5
		fig.pose(g.prev.lerp(g.pos, a), facing, k, g.walking, g.swing_t, putt, g.hit_t, g.cheer_t, false, delta, g.sulk_t, g.rage_t, g.storming, g.tossed)
		_throw_club(g, fig, k)
	_fly_clubs(delta)
	for m in sim.crew.members:
		var fig: PersonFig = _staff_figs.get(m.id)
		if fig == null:
			fig = PersonFig.new()
			var prop := "mower"
			if m.role.id == "exterminator":
				prop = "tank"
			elif m.role.id == "marshal":
				prop = "flag"
			elif m.role.id == "beverage":
				prop = "cart"
			elif m.role.id == "club_pro":
				prop = "club"
			elif m.role.id == "porter":
				prop = "bag"
			fig.build(Color(str(m.role.color)), Color(0.2, 0.22, 0.25), Golfer.SKINS[m.id % Golfer.SKINS.size()], Color(0.95, 0.95, 0.9), prop, false, m.id * 6)
			_people_root.add_child(fig)
			_staff_figs[m.id] = fig
		fig.pose(m.prev.lerp(m.pos, a), m.facing, k, m.walking, -1.0, false, m.hit_t, 0.0, m.state == 2, delta)


## A club leaves a golfer's hands once their tantrum has wound up, and
## sails off in the direction they are facing, tumbling, to lie where it
## lands for a while. The simulation only says the golfer threw it
## (`tossed`); where it goes is for show.
func _throw_club(g: Golfer, fig: PersonFig, k: float) -> void:
	if not g.tossed:
		_tossed.erase(g.id)
		return
	if _tossed.has(g.id) or g.rage_t > 2.6 or g.rage_t <= 0.0:
		return
	_tossed[g.id] = true
	var node := PersonFig.loose_club()
	node.scale = Vector3.ONE * k
	_people_root.add_child(node)
	var hand := fig.position + Vector3(0.0, 1.5 * k, 0.0)
	var dir := Vector3(cos(g.facing), 0.0, sin(g.facing))
	var vel := (dir * 7.5 + Vector3(0.0, 7.0, 0.0)) * k
	node.position = hand
	_tosses.append({"node": node, "vel": vel, "t": 0.0, "spin": Vector3(9.0, 2.0, 5.5), "down": false})
	sim.sound.emit("leaves", hand, 0.4)


func _fly_clubs(delta: float) -> void:
	var i := 0
	while i < _tosses.size():
		var c := _tosses[i]
		var node: Node3D = c.node
		c.t = float(c.t) + delta
		if not bool(c.down):
			var vel: Vector3 = c.vel
			vel.y -= 9.8 * delta
			node.position += vel * delta
			var spin: Vector3 = c.spin
			node.rotation += spin * delta
			c.vel = vel
			var off := sim.course.index_at(node.position.x, node.position.z) < 0
			var ground := -100.0 if off else sim.course.height_at(node.position.x, node.position.z)
			if node.position.y <= ground + 0.05 or ground < -50.0:
				c.down = true
				if ground < -50.0:
					node.visible = false
				else:
					node.position.y = ground + 0.03
					# lying flat, pointing the way it was going
					node.rotation = Vector3(0.0, -atan2(vel.z, vel.x), PI * 0.5 + 0.1)
					var t := sim.course.terrain_at(node.position.x, node.position.z)
					sim.sound.emit("splash" if t == Defs.T.WATER else "land_soft", node.position, 0.5)
					if t == Defs.T.WATER:
						node.visible = false
		elif float(c.t) > 14.0:
			node.queue_free()
			_tosses.remove_at(i)
			continue
		i += 1


## Thought bubbles, golf carts and wildlife.
func _update_extras(k: float, a: float) -> void:
	var close := rig.dist < 320.0
	for g in sim.visitors.golfers:
		var l: Label3D = _bubbles.get(g.id)
		if g.bubble_t <= 0.0 or not close or g.bubble == "":
			if l != null:
				l.visible = false
			continue
		if l == null:
			l = _label("", Vector3.ZERO, Color.WHITE)
			l.pixel_size = 0.00032
			l.font_size = 30
			l.outline_size = 9
			l.width = 420.0
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_fx_root.add_child(l)
			_bubbles[g.id] = l
		l.visible = true
		l.text = g.bubble
		l.position = g.prev.lerp(g.pos, a) + Vector3(0, 2.6 * k, 0)
		var col := Color(1, 1, 1)
		if g.bubble_mood > 0:
			col = Color(0.6, 1.0, 0.65)
		elif g.bubble_mood < 0:
			col = Color(1.0, 0.6, 0.55)
		col.a = clampf(g.bubble_t, 0.0, 1.0)
		l.modulate = col
		l.outline_modulate = Color(0, 0, 0, 0.8 * col.a)
	# carts
	var live := {}
	for gr in sim.visitors.groups:
		if not gr.has_cart or gr.members.is_empty():
			continue
		live[gr.id] = true
		var mi: MeshInstance3D = _carts.get(gr.id)
		if mi == null:
			mi = MeshInstance3D.new()
			var gold := false
			for m in gr.members:
				if not m.member.is_empty() and int(m.member.tier) >= 4:
					gold = true
			mi.mesh = mesh("cart_gold" if gold else "cart")
			_people_root.add_child(mi)
			_carts[gr.id] = mi
		var lead := gr.members[0]
		var p := lead.prev.lerp(lead.pos, a)
		var side := Vector3(-sin(lead.facing), 0.0, cos(lead.facing))
		mi.position = sim.course.on_ground(p.x + side.x * 2.2 * k * 0.6, p.z + side.z * 2.2 * k * 0.6)
		mi.rotation.y = lerp_angle(mi.rotation.y, -lead.facing, 0.2)
		mi.scale = Vector3.ONE * k * 0.62
	for id: int in _carts.keys():
		if not live.has(id):
			_carts[id].queue_free()
			_carts.erase(id)
	# wildlife
	for an in sim.wildlife.animals:
		var mi: MeshInstance3D = _animals.get(an)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.mesh = mesh("animal_" + an.kind)
			_people_root.add_child(mi)
			_animals[an] = mi
		var p := an.prev.lerp(an.pos, a)
		mi.position = p + Vector3(0, absf(sin(_clock * 9.0)) * 0.08 * k if an.walking else 0.0, 0)
		mi.rotation.y = lerp_angle(mi.rotation.y, -an.facing, 0.2)
		mi.scale = Vector3.ONE * k * 0.8
	if _animals.size() > sim.wildlife.animals.size():
		for key: Variant in _animals.keys():
			if not sim.wildlife.animals.has(key):
				_animals[key].queue_free()
				_animals.erase(key)


func _update_balls(k: float, a: float) -> void:
	var cam_pos := rig.cam.global_position
	_trail_n = 0
	for g in sim.visitors.golfers:
		var b := g.ball
		var show := g.group != null and g.group.state == Group.S.PLAY and b.state != Ball.S.HOLED and b.state != Ball.S.WATER and not g.done
		var mi: MeshInstance3D = _balls.get(g.id)
		if not show:
			if mi != null:
				mi.visible = false
			_trails.erase(g.id)
			continue
		if mi == null:
			mi = MeshInstance3D.new()
			mi.mesh = mesh("ball")
			mi.material_override = ball_material(Color(str(b.def.get("color", "ffffff"))))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_fx_root.add_child(mi)
			_balls[g.id] = mi
		var p := b.prev.lerp(b.pos, a) if b.moving() else b.pos
		# A real ball would vanish a few yards from the camera, so it is drawn
		# as a small dot of about the same size on screen at any zoom: a
		# touch bigger in the air, where there is nothing to judge it against,
		# and never smaller than twice life size.
		var aloft := 0.0
		if b.state == Ball.S.FLIGHT:
			aloft = clampf((p.y - sim.course.height_at(p.x, p.z)) / 3.0, 0.0, 1.0)
		var r := maxf(Ball.RADIUS * 2.0, cam_pos.distance_to(p) * lerpf(BALL_ON_GROUND, BALL_IN_AIR, aloft))
		# The spin, slowed down so the eye can follow it. A rolling ball turns
		# at the pace that fits the size it is drawn.
		var turn: Basis = _ball_turn.get(g.id, Basis.IDENTITY)
		var w := b.spin_vector()
		var rate := w.length()
		if rate > 0.01 and b.moving():
			var shown := minf(rate * Ball.RADIUS / r, 26.0) if b.state == Ball.S.ROLL else clampf(rate * 0.035, 4.0, 26.0)
			turn = (Basis(w / rate, shown * _dt) * turn).orthonormalized()
			_ball_turn[g.id] = turn
		mi.visible = true
		mi.transform = Transform3D(turn.scaled(Vector3.ONE * r), p + Vector3(0, r, 0))
		if b.state == Ball.S.FLIGHT:
			var trail: Array = _trails.get_or_add(g.id, [])
			trail.append(p)
			if trail.size() > 26:
				trail.pop_front()
			if trail.size() >= 2:
				_draw_trail(trail, r * 0.7)
		else:
			_trails.erase(g.id)
	_trail_mm.visible_instance_count = _trail_n


## Stand white stakes along the edge of the club's land, the way a real
## course marks out of bounds. A ball that comes to rest beyond them is lost.
func _rebuild_stakes() -> void:
	var course := sim.course
	_stakes_owned = course.owned_parcels()
	var spots: Array[Vector3] = []
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for ty in course.h:
		for tx in course.w:
			if course.locked[ty * course.w + tx] != 0:
				continue
			for s in steps:
				var nx := tx + s.x
				var ny := ty + s.y
				# one stake every other tile along each edge
				if (tx * absi(s.y) + ty * absi(s.x)) % 2 != 0:
					continue
				if course.in_bounds(nx, ny) and course.locked[ny * course.w + nx] == 0:
					continue
				var c := course.tile_center(tx, ty)
				var edge := Vector3(c.x + s.x * Defs.TILE * 0.5, 0.0, c.z + s.y * Defs.TILE * 0.5)
				if course.terrain_at(c.x, c.z) == Defs.T.WATER:
					continue
				spots.append(Vector3(edge.x, course.height_at(edge.x, edge.z) + 0.55, edge.z))
	var mm := _stakes.multimesh
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))
	_stakes.custom_aabb = AABB(Vector3(-100, -200, -100), Vector3(course.w * Defs.TILE + 200.0, 800.0, course.h * Defs.TILE + 200.0))


func _draw_trail(trail: Array, width: float) -> void:
	var n := trail.size()
	for i in n - 1:
		if _trail_n >= TRAIL_POOL:
			return
		var p0: Vector3 = trail[i]
		var p1: Vector3 = trail[i + 1]
		var d := p1 - p0
		var l := d.length()
		if l < 0.001:
			continue
		var x := d / l
		var y := x.cross(Vector3.UP)
		if y.length_squared() < 1e-6:
			y = Vector3.RIGHT
		y = y.normalized()
		var z := x.cross(y)
		var fade := float(i + 1) / n
		var wd := width * fade
		_trail_mm.set_instance_transform(_trail_n, Transform3D(Basis(x * l, y * wd, z * wd), (p0 + p1) * 0.5))
		_trail_mm.set_instance_color(_trail_n, Color(1, 1, 1, fade * 0.7))
		_trail_n += 1


func _update_flags(k: float) -> void:
	var w := sim.weather
	var flutter := sin(_clock * (1.5 + w.wind_speed * 0.4)) * 0.12
	flag_material().set_shader_parameter("wind", clampf(w.wind_speed / 5.0, 0.15, 1.6))
	for i in _flags.size():
		var f := _flags[i]
		f.rotation.y = -w.wind_dir + flutter + sin(_clock * 1.3 + i) * 0.06
	# true to scale up close, growing with distance so pins can be found from above
	var s := lerpf(1.0, 1.9, smoothstep(22.0, 90.0, rig.dist)) * clampf(rig.dist / 300.0, 1.0, 3.2)
	for n in _hole_nodes:
		n.scale = Vector3.ONE * s
	for l: Label3D in _hole_labels:
		l.position.y = float(l.get_meta("base_y")) * s
		l.visible = rig.dist < 900.0


# --------------------------------------------------- trees and buildings

## Graphics preset: detailed trees reach less far on the lighter ones.
func set_quality(level: int) -> void:
	var scale_now: float = [0.4, 0.55, 0.72, 1.2][level]
	if not is_equal_approx(scale_now, _lod_scale):
		_lod_scale = scale_now
		_objects_dirty = true


const TREE_CHUNK := 20        # trees are batched in squares this many tiles wide
const TREE_LOD := 230.0       # beyond this distance a batch draws its light version


static func mesh_kind(o: int) -> String:
	var over: Dictionary = biome.get("objects", {}).get(str(o), {})
	var fallback := "o%d" % o
	match o:
		Defs.O.OAK:
			fallback = "oak"
		Defs.O.PINE:
			fallback = "pine"
		Defs.O.BUSH:
			fallback = "bush"
		Defs.O.BOULDER:
			fallback = "boulder"
	return str(over.get("mesh", fallback))


func _rebuild_objects() -> void:
	for c in _obj_root.get_children():
		c.queue_free()
	var course := sim.course
	var w := course.w
	var plain := {}
	var flora := {}
	for i in course.objects.size():
		var o := course.objects[i]
		if o == 0:
			continue
		var kind := mesh_kind(o)
		if Flora.handles(kind):
			var key := "%s|%d" % [kind, ((i / w) / TREE_CHUNK) * 1000 + (i % w) / TREE_CHUNK]
			var fl: Array = flora.get_or_add(key, [])
			fl.append(i)
		else:
			var pl: Array = plain.get_or_add(o, [])
			pl.append(i)
	# Trees, bushes and rocks: batched by area, each batch in two levels of detail.
	for key: String in flora:
		var kind := key.get_slice("|", 0)
		var list: Array = flora[key]
		var xforms: Array[Transform3D] = []
		var tints: Array[Color] = []
		var rocky := kind.begins_with("boulder")
		for i: int in list:
			# the same nudge, size and turn the ball's collisions use
			var c0 := course.tile_center(i % w, i / w)
			var off := Defs.plant_offset(i)
			var p := course.on_ground(c0.x + off.x, c0.z + off.y)
			var sz := Defs.plant_scale(i)
			var b := Basis(Vector3.UP, Defs.plant_yaw(i)).scaled(Vector3(sz.x, sz.y, sz.x))
			if rocky:
				p.y -= 0.12
			xforms.append(Transform3D(b, p))
			tints.append(Defs.plant_tint(i))
		# Three draws per batch: the detailed plants up close, the light ones
		# far away, and a plain solid shape that casts the shadow for both,
		# since a shadow does not need every leaf.
		var lod_at := TREE_LOD * _lod_scale
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = Flora.mesh(kind, lod == 0)
			mm.instance_count = xforms.size()
			for n in xforms.size():
				mm.set_instance_transform(n, xforms[n])
				mm.set_instance_color(n, tints[n])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# No margins: with them, a camera that lands inside the margin
			# (a jump to a hole, a quick zoom) can find neither version showing.
			if lod == 0:
				mmi.visibility_range_end = lod_at
			else:
				mmi.visibility_range_begin = lod_at
			_obj_root.add_child(mmi)
		# shadows come from a plain solid stand-in, at every distance
		var sm := MultiMesh.new()
		sm.transform_format = MultiMesh.TRANSFORM_3D
		sm.mesh = Flora.shadow_mesh(kind)
		sm.instance_count = xforms.size()
		for n in xforms.size():
			sm.set_instance_transform(n, xforms[n])
		var caster := MultiMeshInstance3D.new()
		caster.multimesh = sm
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_obj_root.add_child(caster)
	# Whatever gives light after dark gets a real light.
	_lamps.clear()
	_dark_shown = -1.0
	for i in course.objects.size():
		var o := course.objects[i]
		if course.is_closed(i):
			continue
		var reach: float = Defs.O_LIGHT[o]
		if reach <= 0.0:
			continue
		var at := course.tile_center(i % w, i / w)
		var lamp := OmniLight3D.new()
		var energy := 2.6
		var height := 3.2
		lamp.light_color = Color(1.0, 0.8, 0.56)
		if o == Defs.O.FLOODLIGHT:
			energy = 13.0
			height = 13.4
			lamp.light_color = Color(1.0, 0.97, 0.9)
		elif o == Defs.O.LAMP:
			energy = 4.5
			height = 3.5
			lamp.light_color = Color(1.0, 0.86, 0.62)
		elif o == Defs.O.CLUBHOUSE:
			energy = 4.0
			height = 4.5
			at += Vector3(0.0, 0.0, -7.5)
		elif o == Defs.O.HOTEL or o == Defs.O.TENNIS or o == Defs.O.DRIVING_RANGE:
			energy = 4.0
			height = 6.0
		elif o == Defs.O.VENDING:
			# the cold spill of a lit front, no more
			energy = 1.1
			height = 1.4
			at += Vector3(0.0, 0.0, -0.9)
			lamp.light_color = Color(0.8, 0.9, 1.0)
		elif o == Defs.O.BAR:
			energy = 3.2
			height = 2.8
			at += Vector3(0.0, 0.0, -1.2)
		lamp.position = at + Vector3(0.0, height, 0.0)
		lamp.omni_range = reach * 1.2
		lamp.omni_attenuation = 0.55
		lamp.light_specular = 0.25
		lamp.shadow_enabled = false
		lamp.visible = false
		_obj_root.add_child(lamp)
		_lamps.append([lamp, energy])
	# Everything built by hand.
	for o: int in plain:
		var list: Array = plain[o]
		if o == Defs.O.CLUBHOUSE:
			var mi := MeshInstance3D.new()
			mi.mesh = object_mesh(o)
			var i: int = list[0]
			mi.position = course.tile_center(i % w, i / w)
			_obj_root.add_child(mi)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = object_mesh(o)
		mm.instance_count = list.size()
		for n in list.size():
			var i: int = list[n]
			var r1 := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
			var r2 := fposmod(sin(i * 78.233) * 12543.123, 1.0)
			var p := course.tile_center(i % w, i / w)
			var b := Basis.IDENTITY
			var tint := Color.WHITE
			if o == Defs.O.HOUSE:
				tint = Color(0.85 + r1 * 0.3, 0.85 + r2 * 0.25, 0.9)
				b = Basis(Vector3.UP, float(Defs.house_turns(i)) * PI * 0.5)
			elif o == Defs.O.BRIDGE:
				p.y += 0.1
			mm.set_instance_transform(n, Transform3D(b, p))
			if course.is_closed(i):
				tint = Color(0.38, 0.4, 0.45)
			mm.set_instance_color(n, tint)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		_obj_root.add_child(mmi)


func _rebuild_holes() -> void:
	for c in _hole_root.get_children():
		c.queue_free()
	_flags.clear()
	_hole_nodes.clear()
	_hole_labels.clear()
	for i in sim.course.holes.size():
		var hole := sim.course.holes[i]
		# pin
		var pin_at := Node3D.new()
		pin_at.position = hole.pin
		_hole_root.add_child(pin_at)
		var pin := Node3D.new()
		pin_at.add_child(pin)
		_hole_nodes.append(pin)
		var pole := MeshInstance3D.new()
		pole.mesh = _cyl(0.014, 0.018, 2.3, 8)
		pole.material_override = paint(Color(0.97, 0.95, 0.4), 0.4)
		pole.position.y = 1.15
		pin.add_child(pole)
		var band := MeshInstance3D.new()
		band.mesh = _cyl(0.02, 0.02, 0.3, 8)
		band.material_override = paint(Color(0.1, 0.1, 0.1), 0.5)
		band.position.y = 0.5
		pin.add_child(band)
		var pivot := Node3D.new()
		pivot.position.y = 2.02
		pin.add_child(pivot)
		var flag := MeshInstance3D.new()
		flag.mesh = flag_mesh()
		flag.material_override = flag_material()
		pivot.add_child(flag)
		_flags.append(pivot)
		var cup := MeshInstance3D.new()
		cup.mesh = mesh("blob")
		cup.material_override = glow(Color(0.05, 0.05, 0.05))
		cup.scale = Vector3(0.16, 1.0, 0.16)
		cup.position.y = 0.02
		pin.add_child(cup)
		var pl := _label(str(i + 1), Vector3(0, 3.6, 0), Color(1, 1, 1))
		pl.set_meta("base_y", 3.6)
		pin_at.add_child(pl)
		_hole_labels.append(pl)
		# tee
		var tee_at := Node3D.new()
		tee_at.position = hole.tee
		_hole_root.add_child(tee_at)
		var tee := Node3D.new()
		tee_at.add_child(tee)
		_hole_nodes.append(tee)
		var dir := (hole.pin - hole.tee)
		dir.y = 0.0
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		for sgn: float in [-1.0, 1.0]:
			var mk := MeshInstance3D.new()
			mk.mesh = _sphere(0.09, 14, 7)
			mk.material_override = paint(Color(0.12, 0.3, 0.8), 0.25)
			mk.position = side * sgn * 1.9 + Vector3(0, 0.08, 0)
			tee.add_child(mk)
		var title := "Hole %d  ·  Par %d  ·  %d yd" % [i + 1, hole.par, Defs.yards(hole.length)]
		if not hole.open:
			title = "Draft  ·  " + title
		var tl := _label(title, Vector3(0, 2.6, 0), Color(0.8, 0.92, 1.0))
		tl.pixel_size = 0.0003
		tl.set_meta("base_y", 2.6)
		tee_at.add_child(tl)
		_hole_labels.append(tl)
	_rebuild_spots()


## Gold discs where the expert test golfers' tee shots stopped, on drafts only.
func _rebuild_spots() -> void:
	if _spots == null:
		return
	var mm := _spots.multimesh
	var n := 0
	for hole in sim.course.holes:
		if not hole.open:
			n += hole.spots.size()
	mm.instance_count = n
	var k := 0
	for hole in sim.course.holes:
		if hole.open:
			continue
		for i in hole.spots.size():
			var p2: Vector2 = hole.spots[i]
			var p := sim.course.on_ground(p2.x, p2.y)
			p.y += 0.3
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, p))
			k += 1


func _label(text: String, at: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.pixel_size = 0.00042
	l.font_size = 30
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.8)
	return l


# ---------------------------------------------------------- pest mounds

func _scan_mounds() -> void:
	var course := sim.course
	var n := course.w * course.h
	for k in 700:
		var i := _mound_cursor
		_mound_cursor += 1
		if _mound_cursor >= n:
			_mound_cursor = 0
			if _mound_changed:
				_mound_changed = false
				_rebuild_mounds()
		var has := course.pests[i] > 0.3
		if has != _mound_set.has(i):
			_mound_changed = true
			if has:
				_mound_set[i] = true
			else:
				_mound_set.erase(i)


## Scraps appear when a tile crosses the line, and go when it is cleaned.
func _sync_litter() -> void:
	if sim.course.litter_rev == _litter_rev:
		return
	_litter_rev = sim.course.litter_rev
	var course := sim.course
	var show := float(sim.db.litter.get("show", 0.45))
	var xforms: Array[Transform3D] = []
	var n := course.w * course.h
	for i in n:
		if course.litter[i] < show:
			continue
		var scraps := 1 if fposmod(sin(float(i) * 1.7), 1.0) < 0.55 else 2
		for s in scraps:
			var ox := sin(float(i) * 2.1 + float(s) * 4.0) * 1.6
			var oz := cos(float(i) * 1.3 + float(s) * 2.2) * 1.4
			var p := course.tile_center(i % course.w, int(i / course.w))
			p = course.on_ground(p.x + ox, p.z + oz)
			p.y += 0.015
			var yaw := fposmod(sin(float(i) * 5.1 + float(s)), 1.0) * TAU
			xforms.append(Transform3D(Basis(Vector3.UP, yaw), p))
			if xforms.size() >= 600:
				break
		if xforms.size() >= 600:
			break
	var mm := _litter.multimesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])


func _rebuild_mounds() -> void:
	var course := sim.course
	var mm := _mounds.multimesh
	mm.instance_count = _mound_set.size()
	var k := 0
	for i: int in _mound_set:
		var r1 := fposmod(sin(i * 3.77) * 9173.3, 1.0)
		var p := course.tile_center(i % course.w, i / course.w)
		p = course.on_ground(p.x + (r1 - 0.5) * 2.5, p.z + (fposmod(r1 * 7.3, 1.0) - 0.5) * 2.5)
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 0.45, 1.0)), p))
		k += 1


# ------------------------------------------------------- floating text

func add_popup(pos: Vector3, text: String, kind: String) -> void:
	var color := Color(0.6, 1.0, 0.6)
	if kind == "hit":
		color = Color(1.0, 0.45, 0.35)
	elif kind == "good":
		color = Color(1.0, 0.9, 0.3)
	elif kind == "bad":
		color = Color(1.0, 0.55, 0.4)
	var l := _label(text, pos + Vector3(0, 3.5, 0), color)
	l.font_size = 36 if kind == "money" else 50
	_fx_root.add_child(l)
	_popups.append({"node": l, "life": 1.8})


func _update_popups(delta: float) -> void:
	var i := 0
	while i < _popups.size():
		var p := _popups[i]
		p.life = float(p.life) - delta
		var l: Label3D = p.node
		l.position.y += delta * 2.5 * clampf(rig.dist / 120.0, 1.0, 8.0)
		l.modulate.a = clampf(float(p.life), 0.0, 1.0)
		l.outline_modulate.a = l.modulate.a * 0.8
		if float(p.life) <= 0.0:
			l.queue_free()
			_popups.remove_at(i)
		else:
			i += 1


# --------------------------------------------------------------- picking

## The golfer or staff member nearest a screen position, or null.
func pick_person(screen: Vector2) -> Variant:
	var cam := rig.cam
	var best: Variant = null
	var bd := 34.0
	var people: Array = []
	people.append_array(sim.visitors.golfers)
	people.append_array(sim.crew.members)
	for p: Variant in people:
		var wp: Vector3 = p.pos + Vector3(0, 1.4, 0)
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(screen)
		if d < bd:
			bd = d
			best = p
	return best
