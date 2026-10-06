class_name CrowdView
extends Node3D
## The gallery at a tournament: hundreds of spectators drawn as one
## instanced crowd. The simulation says where each one stands
## (Tournaments.gallery); this draws them, turns the ones on the followed
## hole to watch the ball, and has them raise their arms when the crowd
## sounds say so. Everything that moves is done in the vertex shader, so a
## crowd of four hundred costs eight draw calls and no per-frame work.

const MAX := 480
const PALETTE_HAIR: Array[Color] = [Color(0.2, 0.13, 0.08), Color(0.55, 0.38, 0.18), Color(0.75, 0.74, 0.72), Color(0.1, 0.09, 0.09)]

var sim: Sim
var rig: CameraRig
var _mm := MultiMesh.new()
var _mi := MultiMeshInstance3D.new()
var _mats: Array[ShaderMaterial] = []
var _rev := -1
var _cheer := 0.0
var _dismay := 0.0
var _look := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var sh := Shader.new()
	sh.code = _shader_code()
	var mesh := ArrayMesh.new()
	# surface order: trousers, shoes, torso, arm left, arm right, head, hand left, hand right, cap
	var specs := [[1, 0], [4, 0], [0, 0], [0, 1], [0, 2], [2, 0], [2, 1], [2, 2], [3, 0]]
	_build_body(mesh)
	for i in specs.size():
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("part", int(specs[i][0]))
		m.set_shader_parameter("arm", int(specs[i][1]))
		m.set_shader_parameter("shirts", _linear(Golfer.SHIRTS))
		m.set_shader_parameter("trousers", _linear(Golfer.PANTS))
		m.set_shader_parameter("skins", _linear(Golfer.SKINS))
		m.set_shader_parameter("hair", _linear(PALETTE_HAIR))
		mesh.surface_set_material(i, m)
		_mats.append(m)
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	_mi.multimesh = _mm
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.visibility_range_end = 760.0
	_mi.visibility_range_end_margin = 80.0
	_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_mi.custom_aabb = AABB(Vector3(-4000, -200, -4000), Vector3(8000, 800, 8000))
	add_child(_mi)


static func _linear(cols: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c: Color in cols:
		var l := c.srgb_to_linear()
		out.append(Vector3(l.r, l.g, l.b))
	return out


func bind(s: Sim, camera_rig: CameraRig) -> void:
	if sim != null and sim.sound.is_connected(_on_sound):
		sim.sound.disconnect(_on_sound)
	sim = s
	rig = camera_rig
	_rev = -1
	_cheer = 0.0
	_dismay = 0.0
	sim.sound.connect(_on_sound)


## The crowd reacts to what it hears happen on its hole.
func _on_sound(id: String, pos: Vector3, power: float) -> void:
	if sim == null or sim.tourney.gallery_hole < 0:
		return
	var hole: Hole = sim.course.holes[sim.tourney.gallery_hole]
	if pos.distance_to(hole.pin) > 90.0 and pos.distance_to(hole.tee) > 90.0:
		return
	if Game.args.has("cheertest"):
		print("DEMO crowd heard %s, cheer was %.2f" % [id, _cheer])
	match id:
		"ovation":
			_cheer = 1.0
		"cheer", "clap":
			_cheer = maxf(_cheer, 0.55 + 0.45 * power)
		"groan", "splash", "sizzle", "oob":
			_dismay = maxf(_dismay, 0.8)


func _process(delta: float) -> void:
	if sim == null or rig == null:
		return
	var t := sim.tourney
	if t.gallery_rev != _rev:
		_rev = t.gallery_rev
		_fill()
	if _mm.visible_instance_count == 0:
		return
	_cheer = maxf(0.0, _cheer - delta * 0.3)
	if Game.args.has("cheerhold"):
		_cheer = 1.0
	_dismay = maxf(0.0, _dismay - delta * 0.4)
	# where the crowd looks: the ball in the air, else the golfer about to play
	var gr := t.followed_group()
	if gr != null:
		var target := _look
		var best := INF
		for g in gr.members:
			if g.ball.moving():
				target = g.ball.pos
				best = -1.0
				break
			if g.phase == Golfer.P.AIM or g.phase == Golfer.P.SWING:
				target = g.pos
				best = 0.0
			elif best > 0.0:
				target = g.pos
				best = 1.0
		_look = _look.lerp(target, 1.0 - exp(-delta * 4.0))
	var k := lerpf(1.0, 1.45, smoothstep(22.0, 90.0, rig.dist)) * clampf(rig.dist / 210.0, 1.0, 3.0)
	for m in _mats:
		m.set_shader_parameter("look_at", _look)
		m.set_shader_parameter("cheer", _cheer)
		m.set_shader_parameter("dismay", _dismay)
		m.set_shader_parameter("people_scale", k)


## Put every spectator in place. Each one's clothes are drawn from the
## golfers' own palettes, chosen by a die seeded with their place in line.
func _fill() -> void:
	var list := sim.tourney.gallery
	var n := mini(list.size(), MAX)
	_mm.visible_instance_count = n
	if Game.args.has("tourney"):
		print("DEMO crowd drawn: %d spectators" % n)
	if n == 0:
		return
	var pin := Vector3.ZERO
	if sim.tourney.gallery_hole >= 0:
		pin = sim.course.holes[sim.tourney.gallery_hole].pin
	for i in n:
		var e: Dictionary = list[i]
		_rng.seed = i * 7919 + 17
		var shirt := _rng.randi() % Golfer.SHIRTS.size()
		var pants := _rng.randi() % Golfer.PANTS.size()
		var skin := _rng.randi() % Golfer.SKINS.size()
		var cap := _rng.randi() % Golfer.SHIRTS.size() if _rng.randf() < 0.55 else Golfer.SHIRTS.size() + _rng.randi() % PALETTE_HAIR.size()
		var packed := shirt + pants * 16 + skin * 128 + cap * 1024
		var flags := 0
		if int(e.hole) == sim.tourney.gallery_hole:
			flags |= 1
			if bool(e.green) or (e.pos as Vector3).distance_to(pin) < 45.0:
				flags |= 2
		var pos: Vector3 = e.pos
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		_mm.set_instance_custom_data(i, Color(float(packed), float(flags), float(e.face), _rng.randf()))
	_look = pin


## One standing figure, in the proportions of the golfers but with far fewer
## triangles: about six hundred, since there may be four hundred of them.
func _build_body(mesh: ArrayMesh) -> void:
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 8
	ball.rings = 4
	var leg := PersonFig._lathe("crowd_leg", PersonFig._pv([[0.085, 0.0], [0.08, -0.15], [0.066, -0.45], [0.06, -0.5], [0.055, -0.82], [0.04, -0.86], [0.0, -0.87]]), 8)
	var torso := PersonFig._lathe("crowd_torso", PersonFig._pv([[0.105, 0.0], [0.112, 0.1], [0.135, 0.26], [0.148, 0.38], [0.14, 0.44], [0.1, 0.49], [0.0, 0.52]]), 8)
	var arm := PersonFig._lathe("crowd_arm", PersonFig._pv([[0.058, 0.0], [0.052, -0.17], [0.044, -0.32], [0.034, -0.5], [0.0, -0.52]]), 8)
	var neck := PersonFig._lathe("crowd_neck", PersonFig._pv([[0.05, 0.0], [0.047, 0.1], [0.0, 0.11]]), 8)
	# trousers
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(ball, 0, _tr(Vector3(0, 0.95, 0), Vector3(0.105, 0.12, 0.155)))
	for side: float in [-1.0, 1.0]:
		st.append_from(leg, 0, _tr(Vector3(0, 0.9, 0.09 * side), Vector3.ONE))
	st.commit(mesh)
	# shoes
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		st.append_from(ball, 0, _tr(Vector3(0.05, 0.045, 0.09 * side), Vector3(0.1, 0.042, 0.052)))
	st.commit(mesh)
	# torso and shoulders
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(torso, 0, _tr(Vector3(0, 1.03, 0), Vector3(0.8, 1.0, 1.24)))
	for side: float in [-1.0, 1.0]:
		st.append_from(ball, 0, _tr(Vector3(0, 1.48, 0.18 * side), Vector3(0.062, 0.062, 0.062)))
	st.commit(mesh)
	# arms, one surface each so the shader can lift them
	for side: float in [-1.0, 1.0]:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(arm, 0, Transform3D(Basis(Vector3(1, 0, 0), -0.08 * side), Vector3(0, 1.5, 0.2 * side)))
		st.commit(mesh)
	# head and neck
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(ball, 0, _tr(Vector3(0, 1.68, 0), Vector3(0.124, 0.142, 0.117)))
	st.append_from(neck, 0, _tr(Vector3(0, 1.52, 0), Vector3.ONE))
	st.commit(mesh)
	# hands
	for side: float in [-1.0, 1.0]:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(ball, 0, _tr(Vector3(0.004, 0.97, 0.205 * side), Vector3(0.036, 0.052, 0.027)))
		st.commit(mesh)
	# cap, or hair
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(ball, 0, _tr(Vector3(-0.006, 1.715, 0), Vector3(0.13, 0.1, 0.126)))
	st.append_from(ball, 0, _tr(Vector3(0.12, 1.705, 0), Vector3(0.075, 0.01, 0.09)))
	st.commit(mesh)


static func _tr(at: Vector3, s: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(s), at)


static func _shader_code() -> String:
	return """shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform int part = 0;        // 0 shirt, 1 trousers, 2 skin, 3 cap or hair, 4 shoes
uniform int arm = 0;         // 0 none, 1 left arm, 2 right arm: lifted when the crowd cheers
uniform vec3 shirts[12];
uniform vec3 trousers[6];
uniform vec3 skins[6];
uniform vec3 hair[4];
uniform vec3 look_at = vec3(0.0);
uniform float cheer = 0.0;
uniform float dismay = 0.0;
uniform float people_scale = 1.0;
varying vec3 albedo;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	int packed = int(cd.x + 0.5);
	int si = packed & 15;
	int pi = (packed >> 4) & 7;
	int ki = (packed >> 7) & 7;
	int ci = (packed >> 10) & 31;
	if (part == 0) {
		albedo = shirts[min(si, 11)];
	} else if (part == 1) {
		albedo = trousers[min(pi, 5)];
	} else if (part == 2) {
		albedo = skins[min(ki, 5)];
	} else if (part == 3) {
		albedo = ci < 12 ? shirts[ci] : hair[min(ci - 12, 3)];
	} else {
		albedo = vec3(0.09, 0.08, 0.08);
	}
	int flags = int(cd.y + 0.5);
	bool follow = (flags & 1) == 1;
	bool near_green = (flags & 2) == 2;
	float eager = fract(cd.w * 7.31 + 0.13);
	float phase = cd.w * 6.2832;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	if (arm > 0 && follow) {
		// the keenest cheer first and highest; a groan brings hands halfway up
		float keen = step(0.3 - 0.2 * float(near_green), eager);
		float amt = max(cheer * keen * (near_green ? 1.0 : 0.6), dismay * 0.55 * step(0.5, eager));
		float ang = amt * (2.5 + 0.5 * eager);
		vec3 pivot = vec3(0.0, 1.5, arm == 1 ? -0.2 : 0.2);
		vec3 d = v - pivot;
		float c = cos(ang);
		float s = sin(ang);
		d = vec3(d.x * c - d.y * s, d.x * s + d.y * c, d.z);
		v = pivot + d;
		n = vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z);
	}
	if (follow) {
		float keen = step(0.3, eager);
		v.y += cheer * keen * abs(sin(TIME * 8.0 + phase)) * 0.1 * clamp(v.y, 0.0, 1.0);
		// a groan: the head drops a little
		if (v.y > 1.45) {
			v.x += dismay * 0.12 * (v.y - 1.45);
			v.y -= dismay * 0.06 * (v.y - 1.45);
		}
	}
	v.x += sin(TIME * 0.9 + phase) * 0.012 * v.y;
	v.z += sin(TIME * 0.7 + phase * 1.7) * 0.008 * v.y;
	// face the line of play, or the ball if this is the hole being followed
	float yaw = cd.z;
	if (follow) {
		vec2 to = look_at.xz - MODEL_MATRIX[3].xz;
		if (dot(to, to) > 1.0) {
			yaw = atan(to.y, to.x);
		}
	}
	float cy = cos(yaw);
	float sy = sin(yaw);
	v = vec3(v.x * cy - v.z * sy, v.y, v.x * sy + v.z * cy);
	n = vec3(n.x * cy - n.z * sy, n.y, n.x * sy + n.z * cy);
	VERTEX = v * people_scale * (0.94 + 0.12 * fract(cd.w * 3.17));
	NORMAL = n;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.86;
	SPECULAR = 0.2;
}
"""
