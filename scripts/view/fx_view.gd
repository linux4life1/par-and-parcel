class_name FxView
extends Node3D
## Small bursts where the ball meets the ground: sand off a bunker shot and
## a bunker landing, a divot and a spray of grass from an iron, a ring and
## droplets from water, embers and smoke from lava, dust off a cart path.
## Nothing here is simulated: the view listens to the sounds the
## simulation announces and puts a burst where each one happened. Each kind
## has a small pool of GPU particle emitters, so many balls can land at once.

const POOL := 3

var sim: Sim
var rig: CameraRig
var _pools := {}       # kind -> Array[GPUParticles3D]
var _next := {}        # kind -> which emitter to use next
static var _dot: ImageTexture
static var _ring: ImageTexture


func _ready() -> void:
	_make("sand", 34, 0.9, Color(0.74, 0.64, 0.44, 0.55), Color(0.74, 0.64, 0.44, 0.0), 1.4, 3.4, -7.0, 0.04, 0.11, 55.0, Vector3.UP, 1.8)
	_make("spray", 30, 0.75, Color(0.8, 0.7, 0.5, 0.6), Color(0.8, 0.7, 0.5, 0.0), 4.0, 7.0, -9.0, 0.03, 0.08, 24.0, Vector3(0.6, 0.8, 0.0), 1.3)
	_make("divot", 9, 1.1, Color(0.3, 0.21, 0.1), Color(0.28, 0.2, 0.1), 3.5, 6.0, -9.8, 0.05, 0.1, 16.0, Vector3(0.7, 0.72, 0.0), 1.0)
	_make("grass", 22, 0.8, Color(0.36, 0.52, 0.18, 0.9), Color(0.34, 0.5, 0.17, 0.0), 2.5, 5.0, -8.0, 0.035, 0.08, 26.0, Vector3(0.6, 0.8, 0.0), 1.0)
	_make("drops", 40, 0.85, Color(0.8, 0.9, 1.0, 0.85), Color(0.8, 0.9, 1.0, 0.0), 3.5, 6.5, -9.8, 0.04, 0.09, 30.0, Vector3.UP, 1.2)
	_make("splash", 1, 0.9, Color(0.9, 0.96, 1.0, 0.6), Color(0.9, 0.96, 1.0, 0.0), 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, Vector3.UP, 1.0, true)
	_make("embers", 30, 1.3, Color(1.0, 0.72, 0.22), Color(0.5, 0.06, 0.02, 0.0), 1.5, 3.5, -1.5, 0.035, 0.08, 40.0, Vector3.UP, 1.3)
	_make("smoke", 8, 1.8, Color(0.3, 0.28, 0.27, 0.35), Color(0.3, 0.28, 0.27, 0.0), 0.6, 1.4, 0.6, 0.4, 1.0, 25.0, Vector3.UP, 2.4)
	_make("dust", 16, 1.1, Color(0.66, 0.62, 0.54, 0.4), Color(0.66, 0.62, 0.54, 0.0), 0.6, 1.6, -0.5, 0.2, 0.5, 50.0, Vector3.UP, 2.0)


func bind(s: Sim, camera_rig: CameraRig) -> void:
	if sim != null and sim.sound.is_connected(_on_sound):
		sim.sound.disconnect(_on_sound)
	sim = s
	rig = camera_rig
	sim.sound.connect(_on_sound)


func _on_sound(id: String, pos: Vector3, _power: float) -> void:
	if rig == null or rig.cam.global_position.distance_to(pos) > 900.0:
		return
	match id:
		"land_sand":
			_burst("sand", pos)
		"strike_sand":
			var hit := _struck_at(pos)
			_burst("spray", hit[0], hit[1])
			_burst("sand", hit[0])
		"iron", "chip":
			var hit := _struck_at(pos)
			var at: Vector3 = hit[0]
			var t := sim.course.terrain_at(at.x, at.z)
			if Defs.is_fairway(t) or t == Defs.T.ROUGH or t == Defs.T.DEEP_ROUGH:
				_burst("divot", at, hit[1])
				_burst("grass", at, hit[1])
		"splash":
			_burst("drops", pos)
			_burst("splash", pos)
		"sizzle":
			_burst("embers", pos)
			_burst("smoke", pos)
		"land_hard":
			_burst("dust", pos)


## A strike sound is announced where the golfer stands. The ball, and the
## way it went, are a step away: find the golfer and read their shot.
func _struck_at(pos: Vector3) -> Array:
	for g in sim.visitors.golfers:
		if g.pos.distance_to(pos) < 2.5:
			var heading := float(g.plan.get("heading", 0.0))
			return [g.ball.start, Vector3(cos(heading), 0.0, sin(heading))]
	return [pos, Vector3.ZERO]


func burst(kind: String, at: Vector3, toward: Vector3 = Vector3.ZERO) -> void:
	_burst(kind, at, toward)


func _burst(kind: String, at: Vector3, toward: Vector3 = Vector3.ZERO) -> void:
	var pool: Array = _pools[kind]
	var i := int(_next.get(kind, 0))
	_next[kind] = (i + 1) % pool.size()
	var p: GPUParticles3D = pool[i]
	p.global_position = at + Vector3(0, 0.05, 0)
	var mat: ParticleProcessMaterial = p.process_material
	if toward != Vector3.ZERO:
		mat.direction = (toward * 0.7 + Vector3.UP * 0.75).normalized()
	# bigger when the camera is far, so it still reads as a puff and not a pixel
	var far := clampf(rig.dist / 110.0, 1.0, 3.2)
	p.scale = Vector3.ONE * far
	p.restart()
	p.emitting = true


## Build one kind of burst: a pool of emitters sharing a process material.
## `flat` draws a single ring lying on the ground that grows and fades.
func _make(kind: String, amount: int, life: float, from: Color, to: Color, v0: float, v1: float, grav: float, s0: float, s1: float, spread: float, dir: Vector3, grow: float, flat: bool = false) -> void:
	var mat := ParticleProcessMaterial.new()
	mat.direction = dir
	mat.spread = spread
	mat.initial_velocity_min = v0
	mat.initial_velocity_max = v1
	mat.gravity = Vector3(0.0, grav, 0.0)
	mat.scale_min = s0
	mat.scale_max = s1
	mat.damping_min = 0.4
	mat.damping_max = 1.2
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([from, from.lerp(to, 0.5), to])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	mat.color_ramp = tex
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0 if not flat else 0.15))
	curve.add_point(Vector2(1.0, grow))
	var ct := CurveTexture.new()
	ct.curve = curve
	mat.scale_curve = ct
	if flat:
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	else:
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 0.22
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _ring_texture() if flat else _dot_texture()
	qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if flat:
		quad.orientation = PlaneMesh.FACE_Y
		quad.size = Vector2(2.4, 2.4)
	else:
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = qm
	var pool: Array = []
	for i in POOL:
		var p := GPUParticles3D.new()
		p.process_material = mat
		p.draw_pass_1 = quad
		p.amount = amount
		p.lifetime = life
		p.one_shot = true
		p.explosiveness = 0.9 if not flat else 1.0
		p.emitting = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 30, 40))
		add_child(p)
		pool.append(p)
	_pools[kind] = pool


## A soft round speck.
static func _dot_texture() -> ImageTexture:
	if _dot == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x + 0.5 - 16.0, y + 0.5 - 16.0).length() / 16.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d * d, 0.0, 1.0)))
		_dot = ImageTexture.create_from_image(img)
	return _dot


## A thin ring, for the splash on water.
static func _ring_texture() -> ImageTexture:
	if _ring == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0).length() / 32.0
				var a := clampf(1.0 - absf(d - 0.78) / 0.14, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		_ring = ImageTexture.create_from_image(img)
	return _ring
