class_name VolcanoView
extends Node3D
## Smoke, glow, flying lava bombs and fire for the volcano.

const MAX_BOMBS := 48

var sim: Sim
var rig: CameraRig
var terrain: TerrainView
var _smoke: Array[GPUParticles3D] = []
var _sparks: Array[GPUParticles3D] = []
var _lights: Array[OmniLight3D] = []
var _bombs: Array[MeshInstance3D] = []
var _embers: Array[MeshInstance3D] = []
var _heat := 0.0
var _puff: GradientTexture2D


func _ready() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	_puff = GradientTexture2D.new()
	_puff.gradient = grad
	_puff.fill = GradientTexture2D.FILL_RADIAL
	_puff.fill_from = Vector2(0.5, 0.5)
	_puff.fill_to = Vector2(1.0, 0.5)
	_puff.width = 64
	_puff.height = 64
	for i in MAX_BOMBS:
		var b := MeshInstance3D.new()
		b.mesh = WorldView.mesh("ball")
		b.material_override = _fire_mat(Color(1.0, 0.55, 0.12))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false
		add_child(b)
		_bombs.append(b)
		var e := MeshInstance3D.new()
		e.mesh = WorldView.mesh("ball")
		e.material_override = _fire_mat(Color(0.9, 0.25, 0.05))
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.visible = false
		add_child(e)
		_embers.append(e)


func _fire_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	return m


func _cloud(color: Color, amount: int, life: float, speed: Vector2, size: Vector2, spread: float, gravity: Vector3, glow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 7.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = gravity
	pm.scale_min = size.x
	pm.scale_max = size.y
	var fade := Gradient.new()
	fade.set_color(0, Color(color.r, color.g, color.b, 0.0))
	fade.add_point(0.15, color)
	fade.set_color(2, Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.billboard_keep_scale = true
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _puff
	if glow:
		qm.emission_enabled = true
		qm.emission = Color(1.0, 0.5, 0.1)
		qm.emission_energy_multiplier = 2.5
	quad.material = qm
	p.draw_pass_1 = quad
	p.amount = amount
	p.lifetime = life
	p.visibility_aabb = AABB(Vector3(-400, -60, -400), Vector3(800, 700, 800))
	return p


func bind(s: Sim, camera: CameraRig, ground: TerrainView) -> void:
	sim = s
	rig = camera
	terrain = ground
	for list: Array in [_smoke, _sparks, _lights]:
		for n: Node in list:
			n.queue_free()
		list.clear()
	for b in _bombs:
		b.visible = false
	for e in _embers:
		e.visible = false
	_heat = 0.0
	for v in sim.course.volcanoes:
		var at := Vector3(float(v.x), float(v.rim) + 1.0, float(v.z))
		var smoke := _cloud(Color(0.22, 0.2, 0.2, 0.55), 90, 14.0, Vector2(5, 9), Vector2(14, 30), 16.0, Vector3(1.5, 1.2, 0.6), false)
		smoke.position = at
		add_child(smoke)
		_smoke.append(smoke)
		var sparks := _cloud(Color(1.0, 0.6, 0.15, 0.95), 420, 3.2, Vector2(26, 52), Vector2(1.2, 3.2), 24.0, Vector3(0, -22, 0), true)
		sparks.position = at
		sparks.emitting = false
		add_child(sparks)
		_sparks.append(sparks)
		var light := OmniLight3D.new()
		light.position = at + Vector3(0, 6, 0)
		light.light_color = Color(1.0, 0.45, 0.12)
		light.omni_range = float(v.radius) * 1.3
		light.light_energy = 3.0
		add_child(light)
		_lights.append(light)
	sim.eruption.bomb_landed.connect(func(p: Vector3) -> void:
		if rig != null:
			rig.shake(clampf(1.2 - rig.focus.distance_to(p) / 300.0, 0.15, 1.0)))
	sim.eruption.started.connect(func() -> void:
		if rig != null:
			rig.shake(1.0))


func _process(delta: float) -> void:
	if sim == null or _smoke.is_empty():
		return
	var er := sim.eruption
	var erupting := er.state == Eruption.S.ERUPTING
	var rumbling := er.state == Eruption.S.RUMBLING
	_heat = move_toward(_heat, 1.0 if erupting else (0.4 if rumbling else 0.0), delta * 0.6)
	terrain.material.set_shader_parameter("heat", _heat)
	var wind := sim.weather.wind_vec()
	for i in _smoke.size():
		var pm := _smoke[i].process_material as ParticleProcessMaterial
		pm.gravity = Vector3(wind.x * 0.8, 1.2 + _heat * 3.0, wind.z * 0.8)
		pm.initial_velocity_max = 9.0 + _heat * 26.0
		_smoke[i].amount_ratio = 0.35 + 0.65 * _heat
		_sparks[i].emitting = erupting
		_lights[i].light_energy = 3.0 + _heat * 9.0 + (sin(Time.get_ticks_msec() * 0.02) * 2.0 if erupting else 0.0)
	if rumbling and randf() < delta * 2.0:
		rig.shake(0.25)
	# lava bombs in flight, each with a trailing ember
	var a := Game.alpha
	var cam := rig.cam.global_position
	for i in MAX_BOMBS:
		if i < er.bombs.size():
			var b := er.bombs[i]
			var prev: Vector3 = b.prev
			var pos: Vector3 = b.pos
			var p := prev.lerp(pos, a)
			var r := maxf(1.1, cam.distance_to(p) * 0.006)
			_bombs[i].visible = true
			_bombs[i].position = p
			_bombs[i].scale = Vector3.ONE * r
			var vel: Vector3 = b.vel
			_embers[i].visible = true
			_embers[i].position = p - vel.normalized() * r * 2.2
			_embers[i].scale = Vector3.ONE * r * 0.6
		else:
			_bombs[i].visible = false
			_embers[i].visible = false
