class_name Surfaces
extends RefCounted
## Photographic materials. The ground textures are packed into arrays for the
## terrain shader; everything else becomes ordinary materials for trees and
## buildings. Sources are in assets/textures (CC0, from Poly Haven).

const DIR := "res://assets/textures/"
## Ground layers, in the order the terrain shader indexes them.
const GROUND: Array[String] = [
	"forrest_ground_01",   # 0 meadow grass
	"grass_ground",        # 1 mown turf
	"sand_01",             # 2 sand
	"cliff_side",          # 3 rock
	"gravel_floor_02",     # 4 gravel
	"sparse_grass",        # 5 thick wild grass
	"burned_ground_01",    # 6 scorched earth
	"dry_ground_01",       # 7 cracked dry ground
	"red_sand",            # 8 red desert sand
	"dark_rock",           # 9 black volcanic rock
]

static var _tex := {}
static var _mats := {}
static var _ground: Array = []


## A texture with mipmaps, so it does not shimmer in the distance.
static func texture(id: String, map: String) -> Texture2D:
	var key := id + "_" + map
	if _tex.has(key):
		return _tex[key]
	var img := image(id, map)
	var t: Texture2D = null
	if img != null:
		t = ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


static func image(id: String, map: String) -> Image:
	var src: Texture2D = load(DIR + "%s_%s.jpg" % [id, map])
	if src == null:
		push_warning("Missing texture " + id + "_" + map)
		return null
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != 1024 or img.get_height() != 1024:
		img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


## [albedo array, normal array, mean colour of each layer (linear)].
static func ground() -> Array:
	if not _ground.is_empty():
		return _ground
	var albedo: Array[Image] = []
	var normal: Array[Image] = []
	var means := PackedVector3Array()
	for id in GROUND:
		var a := image(id, "diff")
		var n := image(id, "nor")
		if a == null or n == null:
			a = Image.create(1024, 1024, true, Image.FORMAT_RGBA8)
			a.fill(Color(0.5, 0.5, 0.5))
			a.generate_mipmaps()
			n = Image.create(1024, 1024, true, Image.FORMAT_RGBA8)
			n.fill(Color(0.5, 0.5, 1.0))
			n.generate_mipmaps()
		albedo.append(a)
		normal.append(n)
		var tiny := a.duplicate() as Image
		tiny.clear_mipmaps()
		tiny.resize(1, 1, Image.INTERPOLATE_LANCZOS)
		var c := tiny.get_pixel(0, 0).srgb_to_linear()
		means.append(Vector3(maxf(c.r, 0.01), maxf(c.g, 0.01), maxf(c.b, 0.01)))
	var ta := Texture2DArray.new()
	ta.create_from_images(albedo)
	var tn := Texture2DArray.new()
	tn.create_from_images(normal)
	_ground = [ta, tn, means]
	return _ground


## The noise picture the shaders read (see tools/make_noise.py). Kept exactly
## as stored: no mipmaps, so a vertex shader and a pixel shader reading the
## same spot get the same number.
static func noise() -> Texture2D:
	if _tex.has("noise|raw"):
		return _tex["noise|raw"]
	var t: Texture2D = null
	var src: Texture2D = load(DIR + "noise.png")
	if src != null:
		var img := src.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		t = ImageTexture.create_from_image(img)
	else:
		push_warning("Missing texture noise.png. Run tools/make_noise.py")
	_tex["noise|raw"] = t
	return t


## Any picture in the textures folder, with mipmaps.
static func picture(file: String) -> Texture2D:
	if _tex.has(file):
		return _tex[file]
	var src: Texture2D = load(DIR + file)
	var t: Texture2D = null
	if src != null:
		var img := src.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		t = ImageTexture.create_from_image(img)
	else:
		push_warning("Missing texture " + file)
	_tex[file] = t
	return t


## Average colour (linear) of the leaves in each quarter of a 2x2 atlas, so a
## shader can even them out and let each plant set its own colour.
static func atlas_means(file: String) -> PackedVector3Array:
	var key := file + "|means"
	if _tex.has(key):
		return _tex[key]
	var out := PackedVector3Array([Vector3.ONE, Vector3.ONE, Vector3.ONE, Vector3.ONE])
	var src: Texture2D = load(DIR + file)
	if src != null:
		var img := src.get_image()
		if img.is_compressed():
			img.decompress()
		# both of these only work on 8-bit images
		img.convert(Image.FORMAT_RGBA8)
		img.srgb_to_linear()
		img.premultiply_alpha()
		img.convert(Image.FORMAT_RGBAF)
		while img.get_width() > 32:
			img.shrink_x2()
		var half := img.get_width() / 2
		for cell in 4:
			var sum := Color(0, 0, 0, 0)
			for y in half:
				for x in half:
					sum += img.get_pixel((cell % 2) * half + x, (cell / 2) * half + y)
			if sum.a > 0.0001:
				out[cell] = Vector3(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a)
	_tex[key] = out
	return out


## Average colour of a diffuse map (linear), for evening out materials.
static func mean_color(id: String) -> Color:
	var key := id + "|mean"
	if _tex.has(key):
		return _tex[key]
	var value := Color(0.25, 0.25, 0.25)
	var img := image(id, "diff")
	if img != null:
		var tiny := img.duplicate() as Image
		tiny.clear_mipmaps()
		tiny.srgb_to_linear()
		while tiny.get_width() > 1:
			tiny.shrink_x2()
		var c := tiny.get_pixel(0, 0)
		value = Color(maxf(c.r, 0.02), maxf(c.g, 0.02), maxf(c.b, 0.02))
	_tex[key] = value
	return value


## A material that keeps a texture's detail but takes its colour from the
## mesh: the texture is evened out to neutral grey, then vertex colour tints
## it. `keep` lets a little of the texture's own hue through.
static func detail(id: String, scale: float = 0.5, rough: float = 0.9, gain: float = 1.0, keep: float = 0.25) -> StandardMaterial3D:
	var mean := mean_color(id)
	var luma := mean.r * 0.3 + mean.g * 0.55 + mean.b * 0.15
	var flat := Color(gain / mean.r, gain / mean.g, gain / mean.b)
	var grey := Color(gain / luma, gain / luma, gain / luma)
	var tint := flat.lerp(grey, keep)
	return material(id, scale, tint.linear_to_srgb(), true, rough)


## A textured material. Mapped by position, so it needs no UVs and keeps the
## same scale on every surface. `tinted` lets vertex or instance colour
## multiply in.
static func material(id: String, scale: float = 0.5, tint: Color = Color.WHITE, tinted: bool = false, rough: float = 0.85) -> StandardMaterial3D:
	var key := "%s|%.3f|%s|%s" % [id, scale, tint.to_html(), str(tinted)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = texture(id, "diff")
	m.normal_enabled = true
	m.normal_texture = texture(id, "nor")
	m.normal_scale = 1.0
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.vertex_color_use_as_albedo = tinted
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m
