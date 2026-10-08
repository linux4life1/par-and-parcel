class_name SlopeArrows
extends Node3D
## Short marks on the greens, pointing downhill. Built for the greens in
## view, and rebuilt when the land changes or the view moves on, not every
## frame. Shown with the slope map, and in play when the ball is on or near
## a green.

var sim: Sim
var rig: CameraRig
var play: PlayMode
var overlay_on := false

var _dirty := true
var _wait := 0.0
var _built_key := 0
var _built_mode := 0
var _mm := MultiMesh.new()
var _mi := MultiMeshInstance3D.new()


func _ready() -> void:
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _arrow_mesh()
	_mi.multimesh = _mm
	_mi.material_override = _arrow_mat()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mi.extra_cull_margin = 8.0
	# The marks are flat on the ground. A zero-height box can be thrown out
	# before it is drawn, so give the batch a box that covers the course.
	_mi.custom_aabb = AABB(Vector3(-50.0, -30.0, -50.0), Vector3(4000.0, 100.0, 4000.0))
	add_child(_mi)
	visible = false


func set_sim(s: Sim) -> void:
	if sim != null:
		var old := sim.course
		if old.heights_changed.is_connected(_mark):
			old.heights_changed.disconnect(_mark)
		if old.tiles_changed.is_connected(_mark):
			old.tiles_changed.disconnect(_mark)
	sim = s
	_dirty = true
	if s != null:
		s.course.heights_changed.connect(_mark)
		s.course.tiles_changed.connect(_mark)


func _mark(_rect: Rect2i) -> void:
	_dirty = true


func _process(delta: float) -> void:
	if sim == null:
		return
	var mode := _mode()
	visible = mode != 0
	if mode == 0:
		return
	var key := _key(mode)
	var same := key == _built_key and mode == _built_mode
	if not _dirty and same:
		return
	# A drag of the sculpt brush changes heights many times a second. The
	# marks catch up a few times a second; a new view rebuilds at once.
	if _dirty and same:
		_wait -= delta
		if _wait > 0.0:
			return
	_wait = 0.2
	_rebuild(mode)
	_dirty = false
	_built_key = key
	_built_mode = mode


func _mode() -> int:
	if overlay_on:
		return 1
	if play != null and play.active() and play.g != null:
		var p := play.g.ball.pos
		if Slope.near_green(sim.course, p.x, p.z):
			return 2
	return 0


func _key(mode: int) -> int:
	if mode == 2 and play != null and play.g != null:
		var p := play.g.ball.pos
		return sim.course.index_at(p.x, p.z)
	if rig == null:
		return 0
	var at := rig.cam.global_position
	return int(at.x / 24.0) + int(at.z / 24.0) * 131 + int(at.y / 8.0) * 1723 + int(rig.yaw * 4.0) * 9176 + int(rig.dist / 40.0) * 524287


func _rebuild(mode: int) -> void:
	var course := sim.course
	var marks: Array[Transform3D] = []
	var reach := float(Slope.book().get("view_range", 180.0))
	var near := float(Slope.book().get("near", 10.0))
	var ball := Vector3.ZERO
	var cam: Camera3D = null
	if mode == 2 and play != null and play.g != null:
		ball = play.g.ball.pos
	elif rig != null:
		cam = rig.cam
	for ty in course.h:
		for tx in course.w:
			if not Defs.is_green(course.terrain[ty * course.w + tx]):
				continue
			var center := course.tile_center(tx, ty)
			if mode == 2:
				if Vector2(center.x - ball.x, center.z - ball.z).length() > near + Defs.TILE:
					continue
			elif cam != null:
				if cam.global_position.distance_to(center) > reach:
					continue
				if not _in_front(center, cam):
					continue
			_lay(course, tx, ty, marks)
			if marks.size() > 6000:
				break
		if marks.size() > 6000:
			break
	_mm.instance_count = marks.size()
	for i in marks.size():
		_mm.set_instance_transform(i, marks[i])


func _in_front(p: Vector3, cam: Camera3D) -> bool:
	if cam.is_position_behind(p):
		return false
	var sp := cam.unproject_position(p)
	var vp := cam.get_viewport().get_visible_rect().size
	return sp.x >= -80.0 and sp.y >= -80.0 and sp.x <= vp.x + 80.0 and sp.y <= vp.y + 80.0


func _lay(course: Course, tx: int, ty: int, marks: Array[Transform3D]) -> void:
	var center := course.tile_center(tx, ty)
	var read := Slope.read(course, center.x, center.z)
	var fit := Slope.mark(float(read.get("percent", 0.0)))
	if not bool(fit.get("show", false)):
		return
	var space := maxf(float(fit.get("space", Defs.TILE)), 0.5)
	var length := float(fit.get("length", 0.8))
	var n: int = maxi(int(Defs.TILE / space), 1)
	var step := Defs.TILE / float(n)
	var x0 := float(tx) * Defs.TILE + step * 0.5
	var z0 := float(ty) * Defs.TILE + step * 0.5
	for iz in n:
		for ix in n:
			var x := x0 + float(ix) * step
			var z := z0 + float(iz) * step
			var here := Slope.read(course, x, z)
			var fall: Vector2 = here.get("fall", Vector2.ZERO)
			if fall.length_squared() < 1e-8:
				continue
			var axis := Vector3(fall.x, 0.0, fall.y).normalized()
			var side := Vector3(-axis.z, 0.0, axis.x)
			var basis := Basis(axis * length, Vector3.UP, side * 0.55)
			var at := Vector3(x, course.height_at(x, z) + 0.12, z)
			marks.append(Transform3D(basis, at))


func _arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, Vector3(0.0, 0.0, -0.07), Vector3(0.62, 0.0, -0.07), Vector3(0.62, 0.0, 0.07), Vector3(0.0, 0.0, 0.07))
	_tri(st, Vector3(0.48, 0.0, -0.22), Vector3(1.0, 0.0, 0.0), Vector3(0.48, 0.0, 0.22))
	st.generate_normals()
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var lift := Vector3(0.0, 0.02, 0.0)
	st.add_vertex(a + lift)
	st.add_vertex(b + lift)
	st.add_vertex(c + lift)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)


func _arrow_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var ink: Array = Slope.book().get("arrow", [0.12, 0.11, 0.09])
	mat.albedo_color = Color(float(ink[0]), float(ink[1]), float(ink[2]))
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
