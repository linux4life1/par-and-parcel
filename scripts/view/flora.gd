class_name Flora
extends RefCounted
## Builds the trees, bushes and rocks. A canopy is a dark solid core wrapped
## in many small cards, each painted with a spray of leaves, a conifer bough
## or a palm frond (see tools/make_foliage.py and shaders/foliage.gdshader).
## Every kind comes in a detailed version for close up and a light one for
## the far distance.

const BROAD := 0
const NEEDLE := 1
const FROND := 2
const GRASS := 3

static var _cache := {}
static var foliage: ShaderMaterial
static var bark: StandardMaterial3D
static var bark_pine: StandardMaterial3D
static var bark_palm: StandardMaterial3D
static var skin: StandardMaterial3D
static var rock: StandardMaterial3D
static var shade: StandardMaterial3D     # plain and solid, for the shapes that only cast shadows
static var _sphere_hi: Array = []
static var _sphere_lo: Array = []


static func setup() -> void:
	if foliage != null:
		return
	foliage = ShaderMaterial.new()
	foliage.shader = load("res://shaders/foliage.gdshader")
	foliage.set_shader_parameter("atlas", Surfaces.picture("foliage_atlas.png"))
	foliage.set_shader_parameter("cell_mean", Surfaces.atlas_means("foliage_atlas.png"))
	# real bark and stone, coloured by each plant
	bark = Surfaces.detail("bark_brown_02", 0.55, 0.95)
	bark_pine = Surfaces.detail("pine_bark", 0.6, 0.95)
	bark_palm = Surfaces.detail("palm_tree_bark", 0.9, 0.9)
	rock = Surfaces.detail("cliff_side", 0.3, 0.9, 1.0, 0.1)
	skin = StandardMaterial3D.new()
	skin.vertex_color_use_as_albedo = true
	skin.roughness = 0.6
	shade = StandardMaterial3D.new()
	shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shade.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hi := SphereMesh.new()
	hi.radius = 1.0
	hi.height = 2.0
	hi.radial_segments = 14
	hi.rings = 8
	_sphere_hi = hi.get_mesh_arrays()
	var lo := SphereMesh.new()
	lo.radius = 1.0
	lo.height = 2.0
	lo.radial_segments = 8
	lo.rings = 4
	_sphere_lo = lo.get_mesh_arrays()


## Is this object kind drawn by Flora (with levels of detail)?
static func handles(kind: String) -> bool:
	return Defs.PLANT_KINDS.has(kind)


static func mesh(kind: String, detail: bool) -> ArrayMesh:
	setup()
	var key := kind + ("_hi" if detail else "_lo")
	if _cache.has(key):
		return _cache[key]
	var m := _build(kind, detail)
	_cache[key] = m
	return m


## The shape a plant casts its shadow with: the same outline as the plant,
## but solid and simple. Drawing every leaf card into the shadow maps was
## the single most expensive thing in the picture; a shadow does not need it.
static func shadow_mesh(kind: String) -> ArrayMesh:
	setup()
	var key := kind + "_shadow"
	if _cache.has(key):
		return _cache[key]
	var m := _build(kind, false, true)
	_cache[key] = m
	return m


# ------------------------------------------------------------ mesh pieces

class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	func commit(to: ArrayMesh, material: Material) -> void:
		if verts.is_empty():
			return
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = norms
		a[Mesh.ARRAY_COLOR] = cols
		a[Mesh.ARRAY_TEX_UV] = uvs
		a[Mesh.ARRAY_INDEX] = idx
		to.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		to.surface_set_material(to.get_surface_count() - 1, material)


## Colours in this file are written as they should look on screen; meshes
## store them in linear light.
static func _lin(c: Color) -> Color:
	return c.srgb_to_linear()


## Where a cell of the foliage atlas sits: Rect2 in UV space.
static func _cell(cell: int) -> Rect2:
	var inset := 0.006
	return Rect2((cell % 2) * 0.5 + inset, (cell / 2) * 0.5 + inset, 0.5 - inset * 2.0, 0.5 - inset * 2.0)


## One solid rounded mass. Used for the shaded heart of a canopy (alpha 0
## tells the shader it is not a leaf card) and for rounded bits of wood.
static func _lobe(b: Builder, src: Array, at: Vector3, size: Vector3, color: Color, crown: Vector3, crown_r: float, low: float, high: float, alpha: float = 1.0) -> void:
	var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var si: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var su: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
	var base := b.verts.size()
	color = _lin(color)
	for i in sv.size():
		var p := at + sv[i] * size
		var outward := (p - crown).normalized()
		var n := (sn[i] * 0.45 + outward * 0.55).normalized()
		var lift := smoothstep(low, high, p.y)
		var rim := clampf((p - crown).length() / crown_r, 0.0, 1.2)
		var shade := (0.4 + 0.6 * lift) * (0.6 + 0.4 * rim)
		b.verts.append(p)
		b.norms.append(n)
		b.cols.append(Color(color.r * shade, color.g * shade, color.b * shade, alpha))
		b.uvs.append(su[i])
	for k in si:
		b.idx.append(base + k)


## One card of leaves: a small arched sheet facing `face`, lit as part of
## the crown around `crown`.
static func _card(b: Builder, at: Vector3, face: Vector3, spin: float, w: float, h: float, cell: int, color: Color, crown: Vector3, arch: float = 0.12) -> void:
	var t := face.cross(Vector3.UP)
	if t.length_squared() < 0.0001:
		t = Vector3.RIGHT
	t = t.normalized()
	var bt := t.cross(face).normalized()
	var t2 := t * cos(spin) + bt * sin(spin)
	var bt2 := bt * cos(spin) - t * sin(spin)
	var uv := _cell(cell)
	var base := b.verts.size()
	for j in 3:
		var v := j * 0.5
		var bulge := arch * h * (1.0 - (2.0 * v - 1.0) * (2.0 * v - 1.0))
		for i in 2:
			var p := at + t2 * ((i - 0.5) * w) + bt2 * ((0.5 - v) * h) + face * bulge
			var n := ((p - crown).normalized() * 0.7 + Vector3.UP * 0.38 + face * 0.12).normalized()
			b.verts.append(p)
			b.norms.append(n)
			b.cols.append(color)
			b.uvs.append(Vector2(uv.position.x + uv.size.x * i, uv.position.y + uv.size.y * v))
	b.idx.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3,
		base + 2, base + 4, base + 3, base + 3, base + 4, base + 5])


## Leaf cards scattered over the outside of one rounded mass of the crown.
static func _spray(b: Builder, rng: RandomNumberGenerator, at: Vector3, size: Vector3, count: int, card: float, cell: int, colors: Array, crown: Vector3, crown_r: float, low: float, high: float) -> void:
	var away := at - crown
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.35, 1.2), rng.randf_range(-1, 1))
		if dir.length_squared() < 0.01:
			dir = Vector3.UP
		dir = dir.normalized()
		# keep leaves to the outside of the tree, where the light is
		if away.length_squared() > 0.01 and dir.dot(away.normalized()) < -0.25:
			dir = -dir
			dir.y = absf(dir.y)
		var p := at + dir * size * 0.86
		var face := (dir + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.1, 0.7), rng.randf_range(-0.6, 0.6))).normalized()
		var lift := smoothstep(low, high, p.y)
		var rim := clampf((p - crown).length() / crown_r, 0.0, 1.15)
		var shade := (0.52 + 0.48 * lift) * (0.62 + 0.38 * rim) * rng.randf_range(0.86, 1.1)
		var c: Color = _lin(colors[rng.randi() % colors.size()])
		var s := card * rng.randf_range(0.8, 1.2)
		_card(b, p, face, rng.randf() * TAU, s, s, cell, Color(c.r * shade, c.g * shade, c.b * shade, 1.0), crown)


## A long leaf sheet growing out from `from`: a conifer bough or a palm
## frond. It heads out along `dir` (flat), rising then drooping, and folds
## down either side of its midrib.
static func _strip(b: Builder, from: Vector3, dir: Vector3, length: float, width: float, rise: float, droop: float, segs: int, cell: int, color: Color, fold: float, tip_shade: float = 1.0) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var uv := _cell(cell)
	var base := b.verts.size()
	color = _lin(color)
	for k in segs + 1:
		var f := float(k) / segs
		var mid := from + dir * (length * f) + Vector3.UP * (rise * f - droop * f * f)
		var slope := (dir * length + Vector3.UP * (rise - 2.0 * droop * f)).normalized()
		var up := side.cross(slope).normalized()
		if up.y < 0.0:
			up = -up
		var shade := lerpf(0.7, tip_shade, f)
		var col := Color(color.r * shade, color.g * shade, color.b * shade, 1.0)
		for i in 3:
			var x := (i - 1) * 0.5
			var p := mid + side * (x * width) - up * (absf(x) * 2.0 * fold * width)
			var n := (up * 0.75 + side * x * 0.9 + dir * 0.25).normalized()
			b.verts.append(p)
			b.norms.append(n)
			b.cols.append(col)
			b.uvs.append(Vector2(uv.position.x + uv.size.x * (i * 0.5), uv.position.y + uv.size.y * (1.0 - f)))
	for k in segs:
		for i in 2:
			var a := base + k * 3 + i
			var c := a + 3
			b.idx.append_array([a, c, a + 1, a + 1, c, c + 1])


## A solid cone: the dark heart of a conifer.
static func _cone(b: Builder, y0: float, y1: float, r0: float, color: Color, sides: int = 9) -> void:
	var base := b.verts.size()
	color = _lin(color)
	for ring in 2:
		for s in sides + 1:
			var a := TAU * s / sides
			var n := Vector3(cos(a), 0.35, sin(a)).normalized()
			var r := r0 if ring == 0 else 0.02
			b.verts.append(Vector3(cos(a) * r, y0 if ring == 0 else y1, sin(a) * r))
			b.norms.append(n)
			var shade := 0.55 + 0.45 * ring
			b.cols.append(Color(color.r * shade, color.g * shade, color.b * shade, 0.0))
			b.uvs.append(Vector2(float(s) / sides, ring))
	for s in sides:
		var i0 := base + s
		var j0 := base + sides + 1 + s
		b.idx.append_array([i0, j0, i0 + 1, i0 + 1, j0, j0 + 1])


## A tapering, slightly leaning trunk or branch. `flute` cuts ribs into it.
static func _limb(b: Builder, from: Vector3, to: Vector3, r0: float, r1: float, color: Color, sides: int = 8, flute: float = 0.0) -> void:
	var axis := (to - from)
	var length := axis.length()
	if length < 0.001:
		return
	axis /= length
	var side := axis.cross(Vector3(0.3, 0.1, 0.9)).normalized()
	var other := axis.cross(side)
	var base := b.verts.size()
	color = _lin(color)
	for ring in 2:
		var c := from if ring == 0 else to
		var r := r0 if ring == 0 else r1
		for s in sides + 1:
			var a := TAU * s / sides
			var n := side * cos(a) + other * sin(a)
			var rr := r * (1.0 + flute * (1.0 if s % 2 == 0 else -1.0))
			b.verts.append(c + n * rr)
			b.norms.append(n)
			var dark := (0.78 + 0.22 * ring) * (1.0 - flute * (2.2 if s % 2 == 1 else 0.0))
			b.cols.append(Color(color.r * dark, color.g * dark, color.b * dark))
			b.uvs.append(Vector2(float(s) / sides, float(ring) * length * 0.2))
	for s in sides:
		var i0 := base + s
		var i1 := base + s + 1
		var j0 := base + sides + 1 + s
		var j1 := j0 + 1
		b.idx.append_array([i0, j0, i1, i1, j0, j1])


## A trunk that flares into the ground and bends a little on the way up.
static func _trunk(b: Builder, points: Array, radii: Array, color: Color, sides: int = 9) -> void:
	_limb(b, points[0] + Vector3(0, -0.3, 0), points[0] + Vector3(0, 0.35, 0), radii[0] * 1.55, radii[0] * 1.05, color, sides)
	for i in points.size() - 1:
		var lo: Vector3 = points[i]
		if i == 0:
			lo += Vector3(0, 0.3, 0)
		_limb(b, lo, points[i + 1], radii[i], radii[i + 1], color, sides)


## A lumpy boulder: a sphere pushed about by noise.
static func _rock(b: Builder, src: Array, at: Vector3, size: Vector3, color: Color, seed_value: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var si: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var su: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
	var base := b.verts.size()
	color = _lin(color)
	var pts := PackedVector3Array()
	for i in sv.size():
		var d := sv[i]
		var k := 1.0 + noise.get_noise_3d(d.x * 2.0, d.y * 2.0, d.z * 2.0) * 0.32 + noise.get_noise_3d(d.x * 5.0, d.y * 5.0, d.z * 5.0) * 0.1
		var p := d * k * size
		p.y = maxf(p.y, -size.y * 0.35)
		pts.append(at + p)
	for i in sv.size():
		var p := pts[i]
		var n := ((p - at) / size).normalized()
		var shade := 0.6 + 0.4 * smoothstep(at.y - size.y * 0.4, at.y + size.y, p.y)
		b.verts.append(p)
		b.norms.append(n)
		b.cols.append(Color(color.r * shade, color.g * shade, color.b * shade))
		b.uvs.append(su[i])
	for k in si:
		b.idx.append(base + k)


static func _rand(i: int, salt: float) -> float:
	return fposmod(sin(i * 12.9898 + salt * 78.233) * 43758.5453, 1.0)


# ----------------------------------------------------- pieces for props

## A single weathered rock of a given size and colour: a boulder, a standing
## stone, the span of an arch.
static func stone_mesh(size: Vector3, color: Color, seed_value: int) -> ArrayMesh:
	setup()
	var out := ArrayMesh.new()
	var b := Builder.new()
	_rock(b, _sphere_hi, Vector3(0.0, size.y * 0.35, 0.0), size, color, seed_value)
	b.commit(out, rock)
	return out


## The planting for a flower bed: low greenery under drifts of blossom.
static func flowers_mesh() -> ArrayMesh:
	setup()
	var key := "flowers_piece"
	if _cache.has(key):
		return _cache[key]
	var out := ArrayMesh.new()
	var leaves := Builder.new()
	var petals := Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var greens := [Color(0.28, 0.46, 0.2), Color(0.33, 0.52, 0.22), Color(0.25, 0.41, 0.19)]
	var crown := Vector3(0.0, 0.1, 0.0)
	for i in 7:
		var a := i * 0.9
		var r := 0.0 if i == 0 else 1.05
		_spray(leaves, rng, Vector3(cos(a) * r, 0.22, sin(a) * r), Vector3(0.6, 0.26, 0.6), 7, 0.75, BROAD, greens, crown, 1.9, 0.0, 0.6)
	var drifts := [Color(0.9, 0.16, 0.22), Color(0.98, 0.8, 0.18), Color(0.62, 0.36, 0.86), Color(0.97, 0.96, 0.93), Color(0.96, 0.5, 0.7)]
	for d in drifts.size():
		var da := d * TAU / drifts.size() + 0.4
		var centre := Vector3(cos(da) * 0.95, 0.0, sin(da) * 0.95)
		for k in 16:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 0.72
			var p := centre + Vector3(cos(a) * r, rng.randf_range(0.42, 0.62), sin(a) * r)
			if Vector2(p.x, p.z).length() > 1.85:
				continue
			var s := rng.randf_range(0.085, 0.13)
			var c: Color = drifts[d]
			c = c.lerp(Color.WHITE, rng.randf() * 0.18)
			_lobe(petals, _sphere_lo, p, Vector3(s, s * 0.55, s), c, p - Vector3(0, 0.3, 0), 0.3, p.y - s, p.y + s * 0.2)
			_lobe(petals, _sphere_lo, p + Vector3(0, s * 0.3, 0), Vector3(s * 0.35, s * 0.3, s * 0.35), Color(0.95, 0.75, 0.15), p, 0.2, p.y, p.y + s)
	leaves.commit(out, foliage)
	petals.commit(out, skin)
	_cache[key] = out
	return out


# ------------------------------------------------------------------ trees

## A broadleaf crown: rounded masses, each with a dark heart and a coat of
## leaf cards.
static func _crown(leaves: Builder, rng: RandomNumberGenerator, detail: bool, masses: Array, colors: Array, crown: Vector3, crown_r: float, low: float, high: float, cell: int, per: int, card: float, heart: float, solid: Builder = null) -> void:
	var dark: Color = colors[0]
	dark = Color(dark.r * 0.6, dark.g * 0.64, dark.b * 0.6)
	for m: Array in masses:
		var at: Vector3 = m[0]
		var size: Vector3 = m[1]
		if solid != null:
			# the shadow shape: each mass of leaves as one plain ball
			_lobe(solid, _sphere_lo, at, size * 0.82, dark, crown, crown_r, low, high)
			continue
		if heart > 0.0:
			_lobe(leaves, _sphere_lo, at, size * heart, dark, crown, crown_r, low, high, 0.0)
		var n := per if detail else maxi(2, per / 3)
		if m.size() > 2:
			n = int(n * float(m[2]))
		var s := card * maxf(size.x, size.y) * (1.0 if detail else 1.75)
		_spray(leaves, rng, at, size, n, s, cell, colors, crown, crown_r, low, high)


static func _build(kind: String, detail: bool, shadow: bool = false) -> ArrayMesh:
	var out := ArrayMesh.new()
	var wood := Builder.new()
	var leaves := Builder.new()
	var stone := Builder.new()
	var plain := Builder.new()
	var solid: Builder = Builder.new() if shadow else null
	var wood_mat: Material = bark
	var src := _sphere_hi if detail else _sphere_lo
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + 11
	match kind:
		"oak":
			var trunk := Color(0.36, 0.3, 0.24)
			_trunk(wood, [Vector3.ZERO, Vector3(0.08, 1.4, 0.04), Vector3(0.12, 2.8, 0.06)], [0.44, 0.36, 0.3], trunk)
			_limb(wood, Vector3(0.12, 2.7, 0.06), Vector3(1.3, 4.9, 0.4), 0.24, 0.1, trunk, 6)
			_limb(wood, Vector3(0.12, 2.7, 0.06), Vector3(-1.1, 4.7, -0.7), 0.22, 0.09, trunk, 6)
			_limb(wood, Vector3(0.12, 2.7, 0.06), Vector3(0.0, 5.4, 0.9), 0.22, 0.09, trunk, 6)
			_limb(wood, Vector3(0.12, 2.7, 0.06), Vector3(-0.3, 5.2, -1.2), 0.18, 0.08, trunk, 6)
			var crown := Vector3(0.0, 5.7, 0.0)
			var greens := [Color(0.3, 0.44, 0.17), Color(0.35, 0.5, 0.2), Color(0.26, 0.4, 0.16), Color(0.4, 0.53, 0.2), Color(0.33, 0.47, 0.14)]
			var masses := [[crown + Vector3(0, 0.5, 0), Vector3(2.4, 2.1, 2.4), 2.6]]
			var n := 13 if detail else 6
			for i in n:
				var a := TAU * i / n + _rand(i, 1.0) * 0.6
				var rr := 1.5 + _rand(i, 2.0) * 1.4
				var y := 4.3 + _rand(i, 3.0) * 2.7
				var s := 1.2 + _rand(i, 4.0) * 0.7
				masses.append([Vector3(cos(a) * rr, y, sin(a) * rr), Vector3(s, s * 0.84, s)])
			_crown(leaves, rng, detail, masses, greens, crown, 3.9, 3.2, 8.2, BROAD, 10, 1.25, 0.66, solid)
		"birch":
			var white := Color(0.86, 0.85, 0.8)
			_trunk(wood, [Vector3.ZERO, Vector3(0.1, 1.8, 0.0), Vector3(0.16, 3.6, 0.03), Vector3(0.02, 6.8, 0.1)], [0.2, 0.17, 0.14, 0.05], white, 7)
			_limb(wood, Vector3(0.14, 3.4, 0.0), Vector3(0.9, 5.2, 0.3), 0.07, 0.03, white, 5)
			_limb(wood, Vector3(0.14, 4.0, 0.0), Vector3(-0.8, 5.6, -0.4), 0.07, 0.03, white, 5)
			var crown := Vector3(0.0, 5.9, 0.0)
			var greens := [Color(0.45, 0.58, 0.22), Color(0.52, 0.64, 0.25), Color(0.4, 0.53, 0.2), Color(0.58, 0.66, 0.24)]
			var masses := []
			var n := 11 if detail else 5
			for i in n:
				var a := TAU * i / n * 1.7 + _rand(i, 5.0)
				var rr := 0.45 + _rand(i, 6.0) * 1.0
				var y := 3.9 + float(i) / n * 3.6
				var s := 0.85 + _rand(i, 7.0) * 0.5
				masses.append([Vector3(cos(a) * rr, y, sin(a) * rr), Vector3(s, s * 1.1, s)])
			_crown(leaves, rng, detail, masses, greens, crown, 2.5, 3.4, 8.4, BROAD, 8, 1.2, 0.55, solid)
		"scots":
			wood_mat = bark_pine
			var red := Color(0.5, 0.36, 0.28)
			_trunk(wood, [Vector3.ZERO, Vector3(0.12, 2.2, 0.05), Vector3(0.22, 4.4, 0.12), Vector3(0.05, 7.6, 0.0)], [0.34, 0.29, 0.25, 0.12], red)
			_limb(wood, Vector3(0.14, 5.6, 0.04), Vector3(1.8, 7.3, 0.5), 0.13, 0.05, red, 6)
			_limb(wood, Vector3(0.12, 6.0, 0.02), Vector3(-1.7, 7.6, -0.7), 0.13, 0.05, red, 6)
			_limb(wood, Vector3(0.1, 6.4, 0.0), Vector3(0.3, 7.9, -1.6), 0.1, 0.04, red, 5)
			var crown := Vector3(0.0, 7.4, 0.0)
			var greens := [Color(0.27, 0.42, 0.3), Color(0.31, 0.47, 0.33), Color(0.24, 0.38, 0.28), Color(0.35, 0.49, 0.31)]
			var masses := []
			var n := 11 if detail else 6
			for i in n:
				var a := TAU * i / n + _rand(i, 8.0)
				var rr := 0.4 + _rand(i, 9.0) * 2.3
				var s := 1.15 + _rand(i, 10.0) * 0.65
				masses.append([Vector3(cos(a) * rr, 7.2 + _rand(i, 11.0) * 1.5, sin(a) * rr), Vector3(s * 1.3, s * 0.6, s * 1.3)])
			_crown(leaves, rng, detail, masses, greens, crown, 3.6, 6.4, 9.4, BROAD, 11, 0.8, 0.62, solid)
		"pine":
			wood_mat = bark_pine
			var trunk := Color(0.34, 0.26, 0.2)
			_trunk(wood, [Vector3.ZERO, Vector3(0.0, 3.0, 0.0), Vector3(0.0, 10.6, 0.0)], [0.3, 0.24, 0.04], trunk, 8)
			var greens := [Color(0.2, 0.37, 0.25), Color(0.24, 0.42, 0.28), Color(0.17, 0.33, 0.23), Color(0.27, 0.44, 0.27)]
			_cone(leaves, 1.7, 10.4, 1.25, Color(0.1, 0.19, 0.13))
			if shadow:
				# two stacked cones follow the outline of the boughs
				_cone(solid, 1.2, 6.2, 2.05, Color(0.1, 0.19, 0.13), 10)
				_cone(solid, 4.4, 10.7, 1.25, Color(0.1, 0.19, 0.13), 10)
			# whorls of boughs, long and drooping low down, short and perky on top
			var tiers := 0 if shadow else (11 if detail else 6)
			for t in tiers:
				var f := float(t) / (tiers - 1)
				var y := lerpf(1.5, 10.0, f)
				var reach := lerpf(3.0, 0.55, pow(f, 0.85))
				var per := (7 if detail else 5) - (2 if f > 0.75 else 0)
				for i in per:
					var a := TAU * (i + rng.randf_range(-0.2, 0.2)) / per + t * 1.9
					var dir := Vector3(cos(a), 0.0, sin(a))
					var c: Color = greens[rng.randi() % greens.size()]
					var shade := (0.62 + 0.38 * f) * rng.randf_range(0.88, 1.08)
					var col := Color(c.r * shade, c.g * shade, c.b * shade)
					var l := reach * rng.randf_range(0.88, 1.1)
					_strip(leaves, Vector3(0, y, 0), dir, l, l * 0.95, l * lerpf(0.12, 0.5, f), l * lerpf(0.5, 0.2, f), 3, NEEDLE, col, 0.1, 1.25)
					# a hanging skirt under each bough fills the tree out from the side
					if detail or i % 2 == 0:
						var hang := Vector3(0, y - 0.1, 0) + dir * (l * 0.28)
						_strip(leaves, hang, dir, l * 0.5, l * 0.9, -l * 0.5, l * 0.25, 2, NEEDLE, Color(col.r * 0.8, col.g * 0.8, col.b * 0.8), 0.04, 1.2)
			for k in (0 if shadow else 3):
				var a := k * TAU / 3.0
				_strip(leaves, Vector3(0, 9.9, 0), Vector3(cos(a), 0, sin(a)), 0.35, 1.0, 1.5, 0.2, 2, NEEDLE, greens[1], 0.0, 1.2)
		"palm":
			wood_mat = bark_palm
			var trunk := Color(0.5, 0.42, 0.32)
			# a trunk that curves as it climbs
			var pts: Array = []
			var radii: Array = []
			for i in 8:
				var f := i / 7.0
				pts.append(Vector3(f * f * 1.2, f * 7.4, f * 0.25))
				radii.append(lerpf(0.36, 0.22, sqrt(f)))
			_trunk(wood, pts, radii, trunk, 9)
			var top: Vector3 = pts[7]
			_lobe(wood, _sphere_lo, top + Vector3(0, -0.05, 0), Vector3(0.4, 0.42, 0.4), Color(0.36, 0.28, 0.18), top, 1.0, top.y - 1.0, top.y + 1.0)
			var greens := [Color(0.36, 0.52, 0.2), Color(0.42, 0.57, 0.22), Color(0.32, 0.47, 0.19), Color(0.48, 0.58, 0.24)]
			var fronds := 16 if detail else 9
			for fr in fronds:
				var a := TAU * fr / fronds * 2.4 + rng.randf_range(-0.25, 0.25)
				var dir := Vector3(cos(a), 0.0, sin(a))
				var young := float(fr) / fronds          # later fronds stand taller
				var l := rng.randf_range(3.3, 4.2) * lerpf(1.0, 0.8, young)
				var rise := lerpf(0.6, 3.0, young * young) + rng.randf_range(-0.2, 0.4)
				var droop := lerpf(3.4, 1.4, young)
				var c: Color = greens[rng.randi() % greens.size()]
				if shadow:
					_strip(solid, top + Vector3(0, 0.2, 0), dir, l * 0.92, 0.62, rise, droop, 3, FROND, c, 0.1)
				else:
					_strip(leaves, top + Vector3(0, 0.2, 0), dir, l, 1.5, rise, droop, 6 if detail else 3, FROND, c, 0.16, 1.15)
			for k in 4:
				var a := k * 1.7
				_lobe(wood, _sphere_lo, top + Vector3(cos(a) * 0.3, -0.42, sin(a) * 0.3), Vector3(0.17, 0.19, 0.17), Color(0.3, 0.22, 0.12), top, 1.0, top.y - 1.0, top.y + 1.0)
		"deadtree":
			var char_c := Color(0.2, 0.17, 0.15)
			_trunk(wood, [Vector3.ZERO, Vector3(0.1, 1.6, 0.0), Vector3(0.2, 3.2, 0.0), Vector3(0.0, 5.6, 0.2)], [0.4, 0.32, 0.26, 0.07], char_c)
			_limb(wood, Vector3(0.15, 2.6, 0.0), Vector3(1.7, 4.4, 0.5), 0.16, 0.04, char_c, 5)
			_limb(wood, Vector3(0.2, 3.3, 0.0), Vector3(-1.4, 5.0, -0.6), 0.14, 0.04, char_c, 5)
			_limb(wood, Vector3(1.1, 3.8, 0.3), Vector3(1.6, 5.4, -0.4), 0.07, 0.02, char_c, 4)
			_limb(wood, Vector3(-0.8, 4.3, -0.4), Vector3(-1.0, 5.8, 0.4), 0.06, 0.02, char_c, 4)
			_limb(wood, Vector3(0.1, 4.4, 0.1), Vector3(0.7, 5.9, 0.9), 0.06, 0.02, char_c, 4)
		"cactus":
			var green := Color(0.3, 0.5, 0.27)
			_limb(plain, Vector3(0, -0.2, 0), Vector3(0.0, 4.8, 0.0), 0.46, 0.4, green, 20, 0.07)
			_lobe(plain, src, Vector3(0.0, 4.8, 0.0), Vector3(0.4, 0.45, 0.4), green, Vector3(0, 4.8, 0), 0.5, 4.0, 5.4)
			_limb(plain, Vector3(0.3, 2.3, 0.0), Vector3(1.3, 2.7, 0.0), 0.26, 0.26, green, 16, 0.07)
			_lobe(plain, src, Vector3(1.32, 2.68, 0.0), Vector3(0.27, 0.27, 0.27), green, Vector3(1.3, 2.7, 0), 0.4, 2.2, 3.0)
			_limb(plain, Vector3(1.32, 2.6, 0.0), Vector3(1.35, 4.1, 0.0), 0.27, 0.24, green, 16, 0.07)
			_lobe(plain, src, Vector3(1.35, 4.1, 0.0), Vector3(0.24, 0.3, 0.24), green, Vector3(1.35, 4.1, 0), 0.4, 3.6, 4.5)
			_limb(plain, Vector3(-0.3, 1.7, 0.0), Vector3(-1.1, 2.0, 0.1), 0.23, 0.23, green, 16, 0.07)
			_lobe(plain, src, Vector3(-1.12, 1.98, 0.1), Vector3(0.24, 0.24, 0.24), green, Vector3(-1.1, 2.0, 0.1), 0.4, 1.6, 2.3)
			_limb(plain, Vector3(-1.12, 1.9, 0.1), Vector3(-1.15, 3.1, 0.1), 0.24, 0.21, green, 16, 0.07)
			_lobe(plain, src, Vector3(-1.15, 3.1, 0.1), Vector3(0.21, 0.27, 0.21), green, Vector3(-1.15, 3.1, 0.1), 0.4, 2.7, 3.5)
		"bush", "gorse", "scrub":
			var greens := [Color(0.3, 0.45, 0.2), Color(0.35, 0.5, 0.22), Color(0.26, 0.4, 0.18), Color(0.39, 0.52, 0.21)]
			var n := 6 if detail else 3
			var reach := 0.85
			var squash := 0.78
			var cell := BROAD
			var heart := 0.7
			if kind == "gorse":
				greens = [Color(0.26, 0.39, 0.18), Color(0.3, 0.43, 0.19), Color(0.23, 0.35, 0.17)]
			elif kind == "scrub":
				greens = [Color(0.55, 0.55, 0.38), Color(0.48, 0.5, 0.36), Color(0.6, 0.57, 0.39)]
				squash = 0.55
				heart = 0.0
				for k in 5:
					var a := k * 1.3
					_limb(wood, Vector3.ZERO, Vector3(cos(a) * 0.7, 0.55 + _rand(k, 2.0) * 0.4, sin(a) * 0.7), 0.05, 0.015, Color(0.4, 0.33, 0.25), 4)
			var crown := Vector3(0.0, 0.45, 0.0)
			var masses := []
			for i in n:
				var a := TAU * i / n + _rand(i, 15.0)
				var rr := _rand(i, 16.0) * reach
				var s := 0.6 + _rand(i, 17.0) * 0.45
				masses.append([Vector3(cos(a) * rr, s * squash * 0.8, sin(a) * rr), Vector3(s, s * squash, s)])
			_crown(leaves, rng, detail, masses, greens, crown, 1.8, 0.0, 1.5, cell, 9, 0.95, heart, solid)
			if kind == "gorse" and not shadow:
				# blossom: small bright sprays over the top
				var gold := [Color(0.98, 0.84, 0.2), Color(0.95, 0.78, 0.16)]
				for m: Array in masses:
					var size: Vector3 = m[1]
					_spray(leaves, rng, m[0] + Vector3(0, size.y * 0.25, 0), size * 0.95, 5 if detail else 2, 0.5 if detail else 0.8, BROAD, gold, crown, 1.8, 0.0, 1.5)
		"fern":
			var greens := [Color(0.3, 0.5, 0.24), Color(0.34, 0.56, 0.27), Color(0.26, 0.45, 0.22)]
			var fronds := 11 if detail else 6
			for fr in fronds:
				var a := TAU * fr / fronds * 1.6 + rng.randf_range(-0.2, 0.2)
				var young := float(fr) / fronds
				var l := rng.randf_range(1.0, 1.5)
				if shadow:
					_strip(solid, Vector3(0, 0.05, 0), Vector3(cos(a), 0, sin(a)), l * 0.9, 0.3, lerpf(0.5, 1.1, young), lerpf(0.8, 0.5, young), 2, FROND, greens[0], 0.1)
				else:
					_strip(leaves, Vector3(0, 0.05, 0), Vector3(cos(a), 0, sin(a)), l, 0.62, lerpf(0.5, 1.1, young), lerpf(0.8, 0.5, young), 4 if detail else 2, FROND,
						greens[fr % greens.size()], 0.12, 1.2)
		"boulder", "boulder_red", "boulder_black":
			var rc := Color(0.47, 0.47, 0.45)
			if kind == "boulder_red":
				rc = Color(0.66, 0.38, 0.24)
			elif kind == "boulder_black":
				rc = Color(0.17, 0.15, 0.15)
			_rock(stone, src, Vector3(0.0, 0.55, 0.0), Vector3(1.6, 1.1, 1.35), rc, 3)
			_rock(stone, src, Vector3(1.25, 0.3, 0.7), Vector3(0.85, 0.6, 0.8), rc.darkened(0.12), 8)
			if detail:
				_rock(stone, src, Vector3(-1.1, 0.2, -0.8), Vector3(0.55, 0.4, 0.6), rc.lightened(0.05), 15)
	if shadow:
		# everything in one plain surface: wood, rock and the solid crown
		for part: Builder in [wood, stone, plain]:
			var base := solid.verts.size()
			solid.verts.append_array(part.verts)
			solid.norms.append_array(part.norms)
			solid.cols.append_array(part.cols)
			solid.uvs.append_array(part.uvs)
			for k in part.idx:
				solid.idx.append(base + k)
		solid.commit(out, shade)
		return out
	wood.commit(out, wood_mat)
	leaves.commit(out, foliage)
	stone.commit(out, rock)
	plain.commit(out, skin)
	return out
