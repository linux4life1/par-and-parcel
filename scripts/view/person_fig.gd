class_name PersonFig
extends Node3D
## A jointed figure: hips, spine, head, two arms with elbows, two legs with
## knees. Everything is animated in code from what the person is doing:
## walking, standing over the ball, swinging, putting, celebrating, working,
## or lying on the grass after meeting a golf ball.
##
## Local axes: +X is forward, +Y is up, +Z is the figure's right.

static var _meshes := {}
static var _mats := {}

var body := Node3D.new()        # everything; tilts when the figure falls
var hips := Node3D.new()
var spine := Node3D.new()
var head := Node3D.new()
var swing := Node3D.new()       # shoulders, arms and club turn together
var arm_l := Node3D.new()
var arm_r := Node3D.new()
var fore_l := Node3D.new()
var fore_r := Node3D.new()
var leg_l := Node3D.new()
var leg_r := Node3D.new()
var shin_l := Node3D.new()
var shin_r := Node3D.new()
var club := Node3D.new()
var stars := Node3D.new()
var t := 0.0
var _has_club := false
var _stride := 0.0


static func _capsule(radius: float, length: float) -> Mesh:
	var key := "c%.3f_%.3f" % [radius, length]
	if _meshes.has(key):
		return _meshes[key]
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = length + radius * 2.0
	c.radial_segments = 12
	c.rings = 4
	_meshes[key] = c
	return c


static func _ball(radius: float) -> Mesh:
	var key := "s%.3f" % radius
	if _meshes.has(key):
		return _meshes[key]
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 9
	_meshes[key] = s
	return s


static func _block(size: Vector3) -> Mesh:
	var key := "b%s" % str(size)
	if _meshes.has(key):
		return _meshes[key]
	var b := BoxMesh.new()
	b.size = size
	_meshes[key] = b
	return b


static func _rod(r0: float, r1: float, length: float) -> Mesh:
	var key := "r%.3f_%.3f_%.3f" % [r0, r1, length]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = length
	c.radial_segments = 10
	_meshes[key] = c
	return c


static func _mat(color: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [color.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	# a soft edge light so figures lift off the grass
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	_mats[key] = m
	return m


func _add(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, scale_v: Vector3 = Vector3.ONE, turn: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	mi.scale = scale_v
	mi.rotation = turn
	parent.add_child(mi)
	return mi


## A shape turned on a lathe: `profile` lists (radius, height) from one end
## to the other. Used for limbs that taper and torsos that have shoulders.
static func _lathe(key: String, profile: PackedVector2Array, segs: int = 16) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := profile.size()
	var rising := profile[n - 1].y > profile[0].y
	for i in n:
		var prev := profile[maxi(i - 1, 0)]
		var next := profile[mini(i + 1, n - 1)]
		var tangent := (next - prev).normalized()
		var out := Vector2(tangent.y, -tangent.x)
		if not rising:
			out = -out
		if out.x < 0.0 and profile[i].x > 0.001:
			out.x = -out.x
		for sgm in segs + 1:
			var ang := TAU * sgm / segs
			verts.append(Vector3(cos(ang) * profile[i].x, profile[i].y, sin(ang) * profile[i].x))
			norms.append(Vector3(cos(ang) * out.x, out.y, sin(ang) * out.x).normalized())
	for i in n - 1:
		for sgm in segs:
			var p0 := i * (segs + 1) + sgm
			var p1 := p0 + 1
			var q0 := p0 + segs + 1
			var q1 := q0 + 1
			# front faces wind clockwise
			if rising:
				idx.append_array([p0, p1, q0, p1, q1, q0])
			else:
				idx.append_array([p0, q0, p1, p1, q0, q1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	return mesh


static func _pv(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in points:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## Build the figure. `variant` picks the small differences between people:
## shorts or trousers, the cut of the hair, the kind of hat.
func build(shirt: Color, pants: Color, skin: Color, hat: Color, prop: String, crown: bool = false, variant: int = 0) -> void:
	var cloth := _mat(shirt, 0.88)
	var trouser := _mat(pants, 0.9)
	var flesh := _mat(skin, 0.6)
	var shoe := _mat(Color(0.95, 0.95, 0.93) if variant % 3 != 1 else Color(0.2, 0.16, 0.13), 0.5)
	var sole := _mat(Color(0.12, 0.12, 0.12), 0.8)
	var hair_tones := [skin.darkened(0.74), Color(0.2, 0.13, 0.08), Color(0.55, 0.38, 0.18), Color(0.75, 0.74, 0.72), Color(0.1, 0.09, 0.09), Color(0.62, 0.26, 0.12)]
	var hair := _mat(hair_tones[variant % hair_tones.size()], 0.75)
	var dark := _mat(Color(0.08, 0.07, 0.07), 0.4)
	var shorts := variant % 4 == 2 and prop == "club"
	var long_hair := variant % 5 >= 3
	add_child(body)
	hips.position = Vector3(0, 0.93, 0)
	body.add_child(hips)
	# pelvis and belt
	_add(hips, _lathe("pelvis", _pv([[0.0, -0.17], [0.07, -0.16], [0.118, -0.08], [0.13, 0.0], [0.122, 0.08], [0.112, 0.14]])), trouser, Vector3.ZERO, Vector3(0.82, 1.0, 1.2))
	_add(hips, _lathe("belt", _pv([[0.114, 0.105], [0.118, 0.11], [0.118, 0.15], [0.112, 0.155]])), _mat(Color(0.14, 0.11, 0.09), 0.55), Vector3.ZERO, Vector3(0.83, 1.0, 1.2))
	_add(hips, _block(Vector3(0.02, 0.04, 0.05)), _mat(Color(0.8, 0.7, 0.3), 0.3, 0.8), Vector3(0.1, 0.13, 0))
	# legs
	for side: float in [-1.0, 1.0]:
		var leg := leg_l if side < 0.0 else leg_r
		var shin := shin_l if side < 0.0 else shin_r
		leg.position = Vector3(0, -0.04, 0.095 * side)
		hips.add_child(leg)
		_add(leg, _ball(0.092), trouser, Vector3(0, -0.02, 0), Vector3(0.95, 1.0, 0.95))
		_add(leg, _lathe("thigh", _pv([[0.092, -0.02], [0.09, -0.12], [0.072, -0.34], [0.064, -0.42], [0.0, -0.45]])), trouser, Vector3.ZERO, Vector3(1.0, 1.0, 0.94))
		shin.position = Vector3(0, -0.41, 0)
		leg.add_child(shin)
		var calf_mat := flesh if shorts else trouser
		_add(shin, _ball(0.064), calf_mat, Vector3.ZERO)
		_add(shin, _lathe("calf", _pv([[0.062, 0.0], [0.068, -0.1], [0.058, -0.22], [0.044, -0.37], [0.04, -0.42]])), calf_mat, Vector3.ZERO)
		if shorts:
			_add(shin, _lathe("sock", _pv([[0.05, -0.3], [0.046, -0.36], [0.043, -0.43]])), _mat(Color(0.96, 0.96, 0.96), 0.9), Vector3.ZERO)
		# shoe: a rounded toe box over a dark sole
		_add(shin, _ball(0.06), shoe, Vector3(0.055, -0.455, 0), Vector3(1.75, 0.72, 0.86))
		_add(shin, _ball(0.05), shoe, Vector3(-0.02, -0.45, 0), Vector3(1.0, 0.9, 0.9))
		_add(shin, _block(Vector3(0.24, 0.022, 0.092)), sole, Vector3(0.045, -0.497, 0))
	# torso: narrow at the waist, broad at the shoulders
	spine.position = Vector3(0, 0.12, 0)
	hips.add_child(spine)
	_add(spine, _lathe("torso", _pv([[0.108, 0.0], [0.112, 0.08], [0.134, 0.22], [0.15, 0.36], [0.146, 0.43], [0.11, 0.49], [0.06, 0.52], [0.0, 0.525]])), cloth, Vector3.ZERO, Vector3(0.8, 1.0, 1.24))
	_add(spine, _ball(0.062), cloth, Vector3(0, 0.45, 0.178))         # shoulder caps
	_add(spine, _ball(0.062), cloth, Vector3(0, 0.45, -0.178))
	_add(spine, _lathe("neck", _pv([[0.052, 0.5], [0.046, 0.56], [0.048, 0.63]])), flesh, Vector3.ZERO)
	_add(spine, _lathe("collar", _pv([[0.07, 0.5], [0.066, 0.545], [0.056, 0.55]])), cloth, Vector3.ZERO, Vector3(1.0, 1.0, 1.08))
	head.position = Vector3(0, 0.735, 0)
	spine.add_child(head)
	# a head a touch larger than life reads better from a distance
	var hs := 1.12
	_add(head, _ball(0.118), flesh, Vector3.ZERO, Vector3(0.96, 1.1, 0.9) * hs)
	_add(head, _ball(0.07), flesh, Vector3(0.035, -0.07, 0) * hs, Vector3(0.95, 0.8, 0.95) * hs)      # jaw
	_add(head, _ball(0.024), flesh, Vector3(0.118, -0.02, 0) * hs, Vector3(1.0, 1.2, 0.9) * hs)       # nose
	for side: float in [-1.0, 1.0]:
		_add(head, _ball(0.024), flesh, Vector3(-0.005, -0.012, 0.108 * side) * hs, Vector3(0.7, 1.2, 0.5) * hs)     # ears
		_add(head, _ball(0.0125), dark, Vector3(0.103, 0.018, 0.042 * side) * hs)                          # eyes
		_add(head, _block(Vector3(0.012, 0.008, 0.04)), hair, Vector3(0.106, 0.045, 0.042 * side) * hs)    # brows
	if hat.a > 0.5:
		var cap := _mat(hat, 0.8)
		_add(head, _ball(0.1), hair, Vector3(-0.03, -0.03, 0) * hs, Vector3(0.95, 0.85, 1.04) * hs)
		if variant % 6 == 4:
			# a wide-brimmed sun hat
			_add(head, _ball(0.122), cap, Vector3(0, 0.05, 0) * hs, Vector3(0.98, 0.7, 0.96) * hs)
			_add(head, _rod(0.2, 0.21, 0.012), cap, Vector3(0, 0.045, 0) * hs, Vector3(1.0, 1.0, 1.0) * hs)
		elif variant % 6 == 5:
			# a visor: band and peak, hair showing on top
			_add(head, _ball(0.121), hair, Vector3(-0.012, 0.035, 0) * hs, Vector3(1.0, 0.86, 0.97) * hs)
			_add(head, _lathe("band", _pv([[0.117, 0.03], [0.119, 0.045], [0.117, 0.07]])), cap, Vector3.ZERO, Vector3(0.98, 1.0, 0.93) * hs)
			_add(head, _rod(0.095, 0.095, 0.01), cap, Vector3(0.125, 0.04, 0) * hs, Vector3(1.0, 1.0, 0.92) * hs)
		else:
			_add(head, _ball(0.124), cap, Vector3(-0.004, 0.034, 0) * hs, Vector3(1.0, 0.8, 0.97) * hs)
			_add(head, _rod(0.098, 0.098, 0.012), cap, Vector3(0.122, 0.036, 0) * hs, Vector3(1.0, 1.0, 0.9) * hs)    # peak
			_add(head, _ball(0.016), cap, Vector3(0, 0.133, 0) * hs)
	else:
		_add(head, _ball(0.125), hair, Vector3(-0.02, 0.028, 0) * hs, Vector3(1.0, 0.92, 0.98) * hs)
	if long_hair:
		_add(head, _ball(0.1), hair, Vector3(-0.07, -0.06, 0) * hs, Vector3(0.7, 1.25, 0.98) * hs)
		_add(head, _ball(0.05), hair, Vector3(-0.13, -0.11, 0) * hs, Vector3(0.8, 1.9, 0.8) * hs)        # ponytail
	# arms hang from a node that turns as one piece in a golf swing
	swing.position = Vector3(0, 0.455, 0)
	spine.add_child(swing)
	for side: float in [-1.0, 1.0]:
		var arm := arm_l if side < 0.0 else arm_r
		var fore := fore_l if side < 0.0 else fore_r
		arm.position = Vector3(0, 0, 0.2 * side)
		swing.add_child(arm)
		_add(arm, _lathe("sleeve", _pv([[0.062, 0.0], [0.062, -0.08], [0.056, -0.16], [0.05, -0.165]])), cloth, Vector3.ZERO)
		_add(arm, _lathe("upper", _pv([[0.048, -0.12], [0.046, -0.2], [0.04, -0.29]])), flesh, Vector3.ZERO)
		fore.position = Vector3(0, -0.29, 0)
		arm.add_child(fore)
		_add(fore, _ball(0.041), flesh, Vector3.ZERO)
		_add(fore, _lathe("fore", _pv([[0.04, 0.0], [0.042, -0.07], [0.031, -0.24], [0.029, -0.26]])), flesh, Vector3.ZERO)
		var glove := _mat(Color(0.97, 0.97, 0.97), 0.7) if (side < 0.0 and prop == "club") else flesh
		_add(fore, _ball(0.046), glove, Vector3(0.004, -0.3, 0), Vector3(0.82, 1.15, 0.6))
	# the thing they carry
	club.position = Vector3(0.3, -0.52, 0)
	swing.add_child(club)
	match prop:
		"club", "flag":
			_has_club = true
			_build_club(club, prop == "flag")
		"mower":
			var red := _mat(Color(0.78, 0.13, 0.1), 0.45, 0.3)
			var tyre := _mat(Color(0.08, 0.08, 0.08), 0.9)
			var bar := _mat(Color(0.2, 0.2, 0.2), 0.4, 0.6)
			_add(body, _capsule(0.2, 0.42), red, Vector3(0.95, 0.3, 0), Vector3(1.0, 1.0, 1.35), Vector3(0, 0, PI * 0.5))
			_add(body, _block(Vector3(0.8, 0.06, 0.66)), _mat(Color(0.2, 0.2, 0.21), 0.6), Vector3(0.95, 0.16, 0))
			_add(body, _capsule(0.11, 0.12), _mat(Color(0.15, 0.15, 0.16), 0.5), Vector3(0.98, 0.52, 0))
			_add(body, _ball(0.06), _mat(Color(0.9, 0.75, 0.1), 0.5), Vector3(0.82, 0.5, 0.16))
			for wx: float in [0.66, 1.24]:
				for wz: float in [-0.35, 0.35]:
					_add(body, _rod(0.13, 0.13, 0.08), tyre, Vector3(wx, 0.13, wz), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
					_add(body, _rod(0.06, 0.06, 0.09), bar, Vector3(wx, 0.13, wz), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
			_add(body, _rod(0.016, 0.016, 0.95), bar, Vector3(0.45, 0.72, 0.2), Vector3.ONE, Vector3(0, 0, -0.75))
			_add(body, _rod(0.016, 0.016, 0.95), bar, Vector3(0.45, 0.72, -0.2), Vector3.ONE, Vector3(0, 0, -0.75))
			_add(body, _rod(0.018, 0.018, 0.44), bar, Vector3(0.12, 1.05, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
		"tank":
			_add(spine, _capsule(0.1, 0.24), _mat(Color(0.9, 0.72, 0.08), 0.4, 0.4), Vector3(-0.2, 0.3, 0))
			_add(spine, _block(Vector3(0.03, 0.34, 0.03)), _mat(Color(0.15, 0.15, 0.15), 0.6), Vector3(-0.06, 0.34, 0.12))
			_add(spine, _block(Vector3(0.03, 0.34, 0.03)), _mat(Color(0.15, 0.15, 0.15), 0.6), Vector3(-0.06, 0.34, -0.12))
			_has_club = true
			_add(club, _rod(0.012, 0.012, 0.8), _mat(Color(0.25, 0.25, 0.25), 0.4, 0.6), Vector3(0, -0.38, 0))
			_add(club, _rod(0.03, 0.012, 0.07), _mat(Color(0.25, 0.25, 0.25), 0.4, 0.6), Vector3(0, -0.8, 0))
		"cart":
			var cart := MeshInstance3D.new()
			cart.mesh = WorldView.mesh("cart")
			cart.scale = Vector3.ONE * 0.75
			cart.position = Vector3(0.2, 0, 0.9)
			body.add_child(cart)
		"bag":
			var sack := _mat(Color(0.28, 0.24, 0.18), 0.85)
			_add(spine, _capsule(0.11, 0.2), sack, Vector3(-0.16, 0.12, 0.06))
	club.visible = _has_club
	for k in 3:
		var s := MeshInstance3D.new()
		s.mesh = _ball(0.05)
		s.material_override = WorldView.glow(Color(1.0, 0.9, 0.2))
		s.position = Vector3(cos(k * TAU / 3.0) * 0.3, 1.98, sin(k * TAU / 3.0) * 0.3)
		stars.add_child(s)
	stars.visible = false
	add_child(stars)
	if crown:
		var gem := MeshInstance3D.new()
		gem.mesh = WorldView.mesh("gem")
		gem.material_override = WorldView.glow(Color(1.0, 0.82, 0.2))
		gem.position = Vector3(0, 2.25, 0)
		add_child(gem)


## Set the figure's position and strike the pose that matches what the
## person is doing right now.
## An iron (or the marshal's flag) on its own, for a club seen flying
## through the air after a tantrum. The grip end is at the origin and the
## head hangs a metre below it, as it does in a golfer's hands.
static func loose_club() -> Node3D:
	var fig := PersonFig.new()
	var node := Node3D.new()
	fig._build_club(node, false)
	return node


func _build_club(into: Node3D, flag: bool) -> void:
	var steel := _mat(Color(0.82, 0.84, 0.88), 0.25, 0.85)
	_add(into, _rod(0.007, 0.01, 0.98), steel, Vector3(0, -0.47, 0))
	_add(into, _rod(0.015, 0.013, 0.24), _mat(Color(0.1, 0.1, 0.1), 0.9), Vector3(0, -0.08, 0))     # grip
	if flag:
		_add(into, _block(Vector3(0.02, 0.26, 0.4)), _mat(Color(0.95, 0.8, 0.1), 0.8), Vector3(0, -0.84, 0.2))
	else:
		# an iron's head: a blade angled off the hosel
		_add(into, _rod(0.011, 0.011, 0.06), steel, Vector3(0, -0.94, 0))
		_add(into, _block(Vector3(0.095, 0.05, 0.022)), steel, Vector3(0.045, -0.972, 0), Vector3.ONE, Vector3(0, 0, 0.12))


func pose(at: Vector3, facing: float, k: float, walking: bool, swing_t: float, putt: bool, hit_t: float, cheer_t: float, working: bool, dt: float, sulk_t: float = 0.0, rage_t: float = 0.0, storming: bool = false, tossed: bool = false) -> void:
	t += dt
	position = at
	scale = Vector3.ONE * k
	rotation.y = lerp_angle(rotation.y, -facing, 1.0 - exp(-dt * 14.0))
	var ease_k := 1.0 - exp(-dt * 12.0)
	_stride = lerpf(_stride, 1.0 if walking else 0.0, 1.0 - exp(-dt * 9.0))
	club.visible = _has_club and not tossed

	# targets for every joint, then blend toward them
	var lean := 0.0             # spine forward
	var twist := 0.0            # spine about the vertical
	var arm_fwd_l := 0.0
	var arm_fwd_r := 0.0
	var arm_in := 0.06          # arms toward the middle
	var elbow_l := 0.12
	var elbow_r := 0.12
	var leg_fwd_l := 0.0
	var leg_fwd_r := 0.0
	var knee_l := 0.0
	var knee_r := 0.0
	var bob := 0.0
	var turn := 0.0             # the swing itself
	var hinge := 0.0            # wrist cock
	var crouch := 0.0
	var gripping := false
	var shake := 0.0            # the head, side to side

	if _stride > 0.02:
		# storming off is the same walk with the volume up: a faster, longer
		# stride, arms pumping, head down and forward
		var stomp := 1.35 if storming else 1.0
		var ph := t * (12.5 if storming else 9.5)
		var s := sin(ph) * _stride
		leg_fwd_l = s * 0.62 * stomp
		leg_fwd_r = -s * 0.62 * stomp
		knee_l = -maxf(0.0, -cos(ph + 0.6)) * 0.95 * _stride * stomp
		knee_r = -maxf(0.0, cos(ph + 0.6)) * 0.95 * _stride * stomp
		arm_fwd_l = -s * 0.5 * (1.9 if storming else 1.0)
		arm_fwd_r = s * 0.5 * (1.9 if storming else 1.0)
		elbow_l = 0.35 * _stride + 0.12 + (0.5 if storming else 0.0)
		elbow_r = 0.35 * _stride + 0.12 + (0.5 if storming else 0.0)
		bob = absf(cos(ph)) * 0.035 * _stride * stomp
		lean = (0.22 if storming else 0.07) * _stride
		twist = s * (0.2 if storming else 0.12)
	else:
		lean = 0.02 + sin(t * 1.7) * 0.012
		arm_fwd_l = sin(t * 1.3) * 0.03
		arm_fwd_r = -sin(t * 1.3) * 0.03

	if swing_t >= 0.0 and _has_club:
		# address, backswing, through the ball, finish
		gripping = true
		var amp := 0.42 if putt else 2.45
		lean = 0.36 if putt else 0.5
		crouch = 0.16
		if swing_t < 0.45:
			turn = -amp * smoothstep(0.0, 0.45, swing_t)
		elif swing_t < 0.6:
			turn = lerpf(-amp, 0.0, pow((swing_t - 0.45) / 0.15, 1.6))
		elif swing_t < 0.9:
			turn = lerpf(0.0, amp * 0.92, 1.0 - pow(1.0 - (swing_t - 0.6) / 0.3, 2.0))
		else:
			turn = amp * 0.92
		if not putt:
			hinge = sin(clampf(absf(turn) / amp, 0.0, 1.0) * PI * 0.5) * 1.25 * (-1.0 if turn < 0.0 else 0.6)
			twist = turn * 0.3
			lean -= clampf(turn, 0.0, 2.0) * 0.2
	elif rage_t > 0.0:
		# the tantrum: stamping one foot then the other, arms thrown about,
		# the head shaking; for the first stretch the club is wound up
		# behind the shoulder, then it is gone (the world view throws it)
		var f := t * 13.0
		var st := sin(f * 0.5)
		leg_fwd_l = maxf(st, 0.0) * 0.8
		leg_fwd_r = maxf(-st, 0.0) * 0.8
		knee_l = -maxf(st, 0.0) * 1.5
		knee_r = -maxf(-st, 0.0) * 1.5
		bob = absf(st) * 0.09
		if tossed and rage_t > 2.6:
			# winding up: right arm back over the shoulder, left arm out
			arm_fwd_r = -2.6
			arm_fwd_l = 1.2
			arm_in = -0.1
			elbow_r = 1.4
			elbow_l = 0.3
			lean = -0.22
			twist = 0.5
		else:
			arm_fwd_l = 1.7 + sin(f) * 1.1
			arm_fwd_r = 1.7 + sin(f + 2.1) * 1.1
			arm_in = -0.3
			elbow_l = 0.9
			elbow_r = 0.9
			lean = -0.1 + sin(f * 0.5) * 0.12
			twist = sin(f * 0.37) * 0.3
		shake = sin(f * 0.7) * 0.55
	elif cheer_t > 2.1:
		# a hole in one: both arms up and jumping
		arm_fwd_l = 2.9
		arm_fwd_r = 2.9 + sin(t * 14.0) * 0.2
		arm_in = -0.25
		elbow_l = 0.2
		elbow_r = 0.2
		bob = absf(sin(t * 9.0)) * 0.3
		lean = -0.08
	elif cheer_t > 0.0:
		# a birdie: the fist pump, right arm punching, a little hop
		arm_fwd_r = 2.4 + sin(t * 11.0) * 0.45
		arm_fwd_l = 0.2
		arm_in = 0.12
		elbow_r = 1.1
		elbow_l = 0.15
		bob = maxf(sin(t * 5.5), 0.0) * 0.14
		lean = -0.14
		twist = -0.25
	elif sulk_t > 0.0:
		# a double bogey: the head drops, the shoulders sag, a slow shake of the head
		lean = 0.34
		arm_fwd_l = 0.12
		arm_fwd_r = 0.12
		elbow_l = 0.04
		elbow_r = 0.04
		arm_in = 0.02
		shake = sin(t * 4.5) * 0.3
	elif working:
		arm_fwd_l = 0.95 + sin(t * 7.0) * 0.12
		arm_fwd_r = 0.95 - sin(t * 7.0) * 0.12
		elbow_l = 0.5
		elbow_r = 0.5
		lean = 0.2

	# knocked flat
	var down := 0.0
	if hit_t > 0.0:
		down = clampf((3.2 - hit_t) * 6.0, 0.0, 1.0) * clampf(hit_t * 2.0, 0.0, 1.0)
		arm_fwd_l = lerpf(arm_fwd_l, 2.4, down)
		arm_fwd_r = lerpf(arm_fwd_r, 2.0, down)
		arm_in = lerpf(arm_in, -0.9, down)
		leg_fwd_l = lerpf(leg_fwd_l, 0.35, down)
		leg_fwd_r = lerpf(leg_fwd_r, -0.2, down)
		turn = 0.0
		gripping = false
	body.rotation.z = down * PI * 0.5
	body.position.y = bob - crouch * 0.12 + down * 0.12
	stars.visible = hit_t > 0.0
	stars.rotation.y = t * 6.0

	if gripping:
		# both hands on the club, out in front of the chest
		arm_fwd_l = 0.62
		arm_fwd_r = 0.62
		arm_in = 0.42
		elbow_l = 0.08
		elbow_r = 0.08
		leg_fwd_l = crouch
		leg_fwd_r = crouch
		knee_l = -crouch * 1.9
		knee_r = -crouch * 1.9

	spine.rotation.z = lerpf(spine.rotation.z, -lean, ease_k)
	spine.rotation.y = lerpf(spine.rotation.y, twist, ease_k)
	head.rotation.z = lerpf(head.rotation.z, lean * 0.55, ease_k)
	head.rotation.y = lerpf(head.rotation.y, shake, ease_k)
	swing.rotation.x = turn
	arm_l.rotation.z = lerpf(arm_l.rotation.z, arm_fwd_l, ease_k)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, arm_fwd_r, ease_k)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -arm_in, ease_k)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, arm_in, ease_k)
	fore_l.rotation.z = lerpf(fore_l.rotation.z, elbow_l, ease_k)
	fore_r.rotation.z = lerpf(fore_r.rotation.z, elbow_r, ease_k)
	leg_l.rotation.z = lerpf(leg_l.rotation.z, leg_fwd_l, ease_k)
	leg_r.rotation.z = lerpf(leg_r.rotation.z, leg_fwd_r, ease_k)
	shin_l.rotation.z = lerpf(shin_l.rotation.z, knee_l, ease_k)
	shin_r.rotation.z = lerpf(shin_r.rotation.z, knee_r, ease_k)
	if _has_club:
		if gripping:
			# the shaft runs from the hands down to the ball in front
			club.position = Vector3(0.31, -0.5, 0)
			club.rotation = Vector3(hinge, 0, 0.62)
		else:
			# carried at the side in the right hand, head down by the feet
			club.position = Vector3(0.03 + sin(arm_fwd_r) * 0.5, -0.55, 0.215)
			club.rotation = Vector3(0, 0, 0.42 + arm_fwd_r * 0.5)
