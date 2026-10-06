class_name WeatherView
extends Node3D
## Sky, sun, atmosphere and rain, driven by the simulated weather. This is
## also where the rendering quality is set up: ambient occlusion, bounce
## light, bloom, soft shadows, haze and depth of field.

signal lightning()

var env := Environment.new()
var sky_mat := ShaderMaterial.new()
var sun := DirectionalLight3D.new()
var rain := GPUParticles3D.new()
var wisps := GPUParticles3D.new()     # streaks of moving air that show which way the wind blows, and how hard
var lens := CameraAttributesPractical.new()
var cloud_offset := Vector2.ZERO      # metres the cloud field has drifted
var cloud_cover := 0.2
var _rain_mat := ParticleProcessMaterial.new()
var _wisp_mat := ParticleProcessMaterial.new()
var _wisps_allowed := true
var _gusting := false
var _flash := 0.0
var _sky_top := Color(0.16, 0.38, 0.78)
var _sky_horizon := Color(0.62, 0.76, 0.90)
var _lava := false


func _ready() -> void:
	var we := WorldEnvironment.new()
	var sky := Sky.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("noise_tex", Surfaces.noise())
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 7.0
	env.tonemap_exposure = 1.0
	# contact shadows and bounce light in the creases
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 2.4
	env.ssao_power = 1.4
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.9
	# a little bloom on bright water, sand and lava
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# distance haze that takes its colour from the sky
	env.fog_enabled = true
	env.fog_density = 0.00012
	env.fog_aerial_perspective = 0.7
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.12
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)

	sun.rotation_degrees = Vector3(-38.0, -40.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 700.0
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.8
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.2
	add_child(sun)

	# a gentle tilt-shift: the far distance and the very near foreground soften
	lens.dof_blur_amount = 0.045
	lens.dof_blur_far_enabled = false
	lens.dof_blur_near_enabled = false

	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(110.0, 1.0, 110.0)
	_rain_mat.direction = Vector3(0.0, -1.0, 0.0)
	_rain_mat.spread = 3.0
	_rain_mat.initial_velocity_min = 34.0
	_rain_mat.initial_velocity_max = 42.0
	_rain_mat.gravity = Vector3(0.0, -20.0, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.014, 0.75)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.albedo_color = Color(0.82, 0.9, 1.0, 0.2)
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.billboard_keep_scale = true
	quad.material = qm
	rain.process_material = _rain_mat
	rain.draw_pass_1 = quad
	rain.amount = 11000
	rain.lifetime = 1.3
	rain.visibility_aabb = AABB(Vector3(-140, -70, -140), Vector3(280, 90, 280))
	rain.emitting = false
	add_child(rain)

	# The wind made visible: thin pale streaks that ride it, wander in the
	# eddies and fade. Barely there in a breeze, plain in a gale.
	_wisp_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_wisp_mat.emission_box_extents = Vector3(90.0, 7.0, 90.0)
	_wisp_mat.spread = 4.0
	_wisp_mat.gravity = Vector3.ZERO
	_wisp_mat.turbulence_enabled = true
	_wisp_mat.turbulence_noise_strength = 0.5
	_wisp_mat.turbulence_noise_scale = 6.0
	_wisp_mat.turbulence_influence_min = 0.01
	_wisp_mat.turbulence_influence_max = 0.035
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	_wisp_mat.color_ramp = ramp
	var streak := QuadMesh.new()
	streak.size = Vector2(0.085, 1.5)     # about a pixel wide once scaled to the camera's distance
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(1.0, 1.0, 1.0, 0.15)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.albedo_texture = _streak_texture()
	streak.material = sm
	wisps.process_material = _wisp_mat
	wisps.draw_pass_1 = streak
	wisps.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	wisps.amount = 90
	wisps.lifetime = 2.6
	wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wisps.visibility_aabb = AABB(Vector3(-400, -80, -400), Vector3(800, 200, 800))
	wisps.emitting = false
	add_child(wisps)


## A streak that is soft at both ends and along both edges.
static func _streak_texture() -> ImageTexture:
	var img := Image.create(8, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 8:
			var along := sin(PI * (y + 0.5) / 64.0)
			var across := sin(PI * (x + 0.5) / 8.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, along * along * across))
	return ImageTexture.create_from_image(img)


## Apply a graphics preset: 0 low .. 3 ultra.
var _dof_allowed := true
var soft_sun := true           # shadows that soften with distance from what casts them (costly)
var _soft_now := -1


## What each preset pays for, measured on an Apple M5 Max (see ./perf.sh ab):
## bounce light and shadows that soften with distance cost about a
## millisecond each and add little, so only Ultra has them.
func apply_quality(level: int) -> void:
	env.ssao_enabled = level >= 1
	env.ssil_enabled = level >= 3
	env.glow_enabled = true
	_dof_allowed = level >= 2
	_wisps_allowed = level >= 1
	soft_sun = level >= 3
	var atlas: int = [2048, 4096, 8192, 8192][level]
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	_soft_now = -1
	var blur: int = RenderingServer.DOF_BLUR_QUALITY_MEDIUM if level >= 3 else RenderingServer.DOF_BLUR_QUALITY_LOW
	RenderingServer.camera_attributes_set_dof_blur_quality(blur as RenderingServer.DOFBlurQuality, false)


## Dial the costly extras back when the frame rate governor asks (see
## Main._apply_load_level). Level 0 is the preset as chosen.
func set_load_level(quality: int, level: int) -> void:
	env.ssao_enabled = quality >= 1 and level < 2
	env.ssil_enabled = quality >= 3 and level < 1
	_dof_allowed = quality >= 2 and level < 2
	soft_sun = quality >= 3 and level < 1
	var soft: int = [RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality]
	if level >= 2:
		soft = RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW
	if soft != _soft_now:
		_soft_now = soft
		RenderingServer.directional_soft_shadow_filter_set_quality(soft as RenderingServer.ShadowQuality)
	var splits := DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if (quality == 0 or level >= 4) else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	if sun.directional_shadow_mode != splits:
		sun.directional_shadow_mode = splits


func set_biome(biome: Dictionary) -> void:
	var sky: Dictionary = biome.get("sky", {})
	_sky_top = Color(str(sky.get("top", "2a61c7")))
	_sky_horizon = Color(str(sky.get("horizon", "9ec2e6")))
	_lava = biome.get("lava", false)
	env.glow_intensity = 0.75 if _lava else 0.42
	env.glow_bloom = 0.1 if _lava else 0.04


func update(sim: Sim, focus: Vector3, cam_dist: float, delta: float) -> void:
	var w := sim.weather
	var ash := w.ash
	var c := maxf(w.cloud, ash)
	var r := w.rain
	var wv := w.wind_vec()
	# clouds ride the wind, a good deal faster than it blows at ground level
	cloud_offset += Vector2(wv.x, wv.z) * delta * 4.0 * (0.0 if Game.paused else float(Game.speed))
	cloud_cover = lerpf(0.16, 1.0, c)
	# the time of day
	var dark := sim.darkness()
	var f := clampf((sim.clock - Defs.SUNRISE) / (Defs.SUNSET - Defs.SUNRISE), 0.0, 1.0)
	var elev := 12.0 + 34.0 * sin(PI * f)                 # the sun's height, in degrees
	var low := 1.0 - smoothstep(13.0, 32.0, elev)         # 1 with the sun on the horizon
	var glow_k := low * (1.0 - c * 0.7) * (1.0 - smoothstep(0.5, 1.0, dark))
	var top := _sky_top.lerp(Color(0.34, 0.37, 0.42), c).lerp(Color(0.20, 0.14, 0.13), ash * 0.85)
	var horizon := _sky_horizon.lerp(Color(0.56, 0.58, 0.61), c).lerp(Color(0.60, 0.32, 0.18), ash * 0.85)
	# sunrise and sunset colour the sky; night drains it
	horizon = horizon.lerp(Color(1.0, 0.56, 0.30), glow_k * 0.6)
	top = top.lerp(Color(0.30, 0.26, 0.48), glow_k * 0.45)
	top = top.lerp(Color(0.012, 0.02, 0.055), dark)
	horizon = horizon.lerp(Color(0.04, 0.06, 0.12).lerp(Color(0.2, 0.08, 0.04), ash), dark)
	var lit := Color(1.0, 1.0, 1.0).lerp(Color(0.62, 0.64, 0.68), c).lerp(Color(0.5, 0.3, 0.22), ash).lerp(Color(1.0, 0.72, 0.5), glow_k * 0.5)
	var shade := Color(0.6, 0.64, 0.72).lerp(Color(0.3, 0.32, 0.36), c).lerp(Color(0.2, 0.12, 0.1), ash)
	var dim := 1.0 - 0.92 * dark
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", horizon.darkened(0.55))
	sky_mat.set_shader_parameter("cloud_cover", cloud_cover)
	sky_mat.set_shader_parameter("cloud_offset", cloud_offset)
	sky_mat.set_shader_parameter("cloud_lit", Color(lit.r * dim, lit.g * dim, lit.b * dim))
	sky_mat.set_shader_parameter("cloud_dark", Color(shade.r * dim, shade.g * dim, shade.b * dim))
	sky_mat.set_shader_parameter("night", dark * (1.0 - c * 0.8))
	if w.kind == Weather.K.STORM and randf() < delta * 0.5 and _flash <= 0.0 and not Game.paused:
		_flash = 1.0
		lightning.emit()
	_flash = maxf(0.0, _flash - delta * 5.0)
	# One light does for both sun and moon: the sun fades out through dusk,
	# then the same light comes back from the other side as moonlight.
	if dark > 0.6:
		sun.rotation_degrees = Vector3(-52.0, 140.0, 0.0)
		sun.light_energy = 0.5 * smoothstep(0.6, 1.0, dark) * lerpf(1.0, 0.45, c) + _flash * 3.0
		sun.light_color = Color(0.58, 0.7, 1.0)
	else:
		sun.rotation_degrees = Vector3(-elev, lerpf(80.0, -160.0, f), 0.0)
		sun.light_energy = lerpf(2.1, 0.5, c) * (1.0 - smoothstep(0.0, 0.6, dark)) * lerpf(1.0, 0.8, low) + _flash * 3.0
		sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.66, 0.4), low * 0.85).lerp(Color(0.8, 0.85, 0.95), c).lerp(Color(1.0, 0.62, 0.42), ash * 0.75)
	env.glow_intensity = (0.75 if _lava else 0.42) + 0.3 * dark
	env.tonemap_exposure = 1.0 + 0.35 * dark
	sun.shadow_opacity = lerpf(0.92, 0.3, c)
	sun.directional_shadow_max_distance = clampf(cam_dist * 2.0 + 60.0, 140.0, 1700.0)
	# crisp shadows from far up, soft-edged ones close in
	var far_k := clampf((cam_dist - 60.0) / 400.0, 0.0, 1.0)
	sun.light_angular_distance = lerpf(0.9, 0.15, far_k) if soft_sun else 0.0
	sun.shadow_blur = lerpf(1.3, 0.6, far_k) if soft_sun else lerpf(2.2, 0.8, far_k)
	# a dark sky gives almost no light of its own: lift it a little so the
	# unlit course can still be made out
	env.ambient_light_energy = lerpf(0.85, 1.0, c) * (1.0 + 3.5 * dark) + _flash
	env.fog_density = lerpf(0.00010, 0.00050, r) + ash * 0.0004
	env.fog_light_color = horizon
	# depth of field: only when zoomed in, where it reads as a lens rather than a blur
	var close := cam_dist < 120.0 and _dof_allowed
	lens.dof_blur_far_enabled = close
	lens.dof_blur_far_distance = cam_dist * 2.6 + 25.0
	lens.dof_blur_far_transition = cam_dist * 3.0 + 40.0
	lens.dof_blur_near_enabled = cam_dist < 90.0 and _dof_allowed
	lens.dof_blur_near_distance = cam_dist * 0.42
	lens.dof_blur_near_transition = cam_dist * 0.3
	rain.emitting = r > 0.03
	rain.amount_ratio = clampf(r, 0.05, 1.0)
	var spread := clampf(cam_dist * 0.6, 60.0, 260.0)
	_rain_mat.emission_box_extents = Vector3(spread, 1.0, spread)
	rain.global_position = focus + Vector3(0.0, 45.0, 0.0)
	# the wind you can see: more streaks, faster, the harder it blows
	var ws := wv.length()
	var blow := clampf((ws - 1.2) / 9.0, 0.0, 1.0)
	# (rain already shows the wind, and the two together are a mess)
	wisps.emitting = _wisps_allowed and blow > 0.02 and r < 0.05
	if wisps.emitting:
		var size := clampf(cam_dist / 90.0, 0.7, 3.2)
		wisps.amount_ratio = clampf(0.15 + blow, 0.0, 1.0)
		wisps.global_position = focus + Vector3(0.0, 5.0 * size + 2.0, 0.0)
		_wisp_mat.emission_box_extents = Vector3(spread * 0.7, 4.0 * size, spread * 0.7)
		_wisp_mat.direction = wv / ws
		_wisp_mat.initial_velocity_min = ws * 1.6 * size
		_wisp_mat.initial_velocity_max = ws * 2.1 * size
		_wisp_mat.scale_min = size * 0.8
		_wisp_mat.scale_max = size * 1.2
	# a gust arriving can be heard
	if w.gust > 0.25 and not _gusting:
		_gusting = true
		if SoundDesk.desk != null and not Game.paused:
			SoundDesk.desk.play("gust", clampf(w.gust + 0.2, 0.3, 1.0))
	elif w.gust < 0.05:
		_gusting = false
	_rain_mat.gravity = Vector3(wv.x * 2.5, -20.0, wv.z * 2.5)
