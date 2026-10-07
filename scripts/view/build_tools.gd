class_name BuildTools
extends Node
## Mouse tools for shaping the course: paint terrain, sculpt the land, place
## scenery and buildings, bulldoze, and lay out holes.

signal tool_changed()
signal selection_changed(who: Variant)
signal hole_added(index: int)

var sim: Sim
var terrain: TerrainView
var rig: CameraRig
var world: WorldView
var enabled := true
var mode := ""                 # "", terrain, sculpt, object, bulldoze, hole
var terrain_type: int = Defs.T.FAIRWAY
var brush := 1                 # radius in tiles
var sculpt_mode := "raise"
var object_type: int = Defs.O.OAK
var hover: Variant = null      # world position under the mouse, or null
var _down := false
var _last_tile := Vector2i(-999, -999)
var _tick := 0.0
var _level := 0.0
var _tee: Variant = null
var _warned := -10.0
var _marker: MeshInstance3D
var _preview_tile := Vector2i(-999, -999)
var _preview_text := ""
var _ribbon: MeshInstance3D
var _ribbon_mesh: ImmediateMesh


func _ready() -> void:
	_marker = MeshInstance3D.new()
	_marker.mesh = WorldView._cyl(0.12, 0.12, 6.0, 6)
	_marker.material_override = WorldView.glow(Color(0.3, 0.7, 1.0))
	_marker.visible = false
	add_child(_marker)
	_ribbon_mesh = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _ribbon_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.95, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon.material_override = mat
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbon.visible = false
	add_child(_ribbon)


func bind(s: Sim) -> void:
	sim = s
	set_mode("")


func set_mode(m: String) -> void:
	mode = m
	_down = false
	_tee = null
	_preview_tile = Vector2i(-999, -999)
	_preview_text = ""
	if _ribbon != null:
		_ribbon.visible = false
	if rig != null:
		rig.tool_active = m != ""
	if _marker != null:
		_marker.visible = false
	_last_tile = Vector2i(-999, -999)
	if terrain != null:
		terrain.material.set_shader_parameter("grid_alpha", 1.0 if m != "" else 0.0)
	tool_changed.emit()


func hint() -> String:
	var body := ""
	match mode:
		"terrain":
			body = "Drag to paint %s. %s per tile." % [sim.terrain_name(terrain_type).to_lower(), Defs.money(Defs.T_COST[terrain_type])]
		"sculpt":
			body = "Hold the mouse button to %s the land. Hold Shift for fine control." % sculpt_mode
		"object":
			if object_type == Defs.O.BRIDGE:
				body = "Click %s to bridge it. %s a span." % [sim.terrain_name(Defs.T.WATER).to_lower(), Defs.money(Defs.O_COST[object_type])]
			else:
				body = "Click to place: %s. %s each." % [sim.object_name(object_type).to_lower(), Defs.money(Defs.O_COST[object_type])]
		"bulldoze":
			body = "Drag to clear trees, scenery and buildings."
		"hole":
			if _tee == null:
				body = "Click where the tee goes."
			else:
				_update_preview()
				body = "Now click a green to place the pin. %s" % _preview_text
		"land":
			if sim.land_credits > 0:
				body = "Click a greyed-out parcel to claim it. The county owes you %d." % sim.land_credits
			else:
				body = "Click a greyed-out parcel to buy it for %s." % Defs.money(sim.land_price())
	if mode == "":
		return body
	if body != "":
		body += "\n"
	return body + "1 tile ≈ 5.5 yd."


func radius_m() -> float:
	match mode:
		"terrain", "bulldoze":
			return (brush + 0.5) * Defs.TILE
		"sculpt":
			return (brush + 1.0) * Defs.TILE
		"object":
			# a light shows how far it will reach
			if Defs.O_LIGHT[object_type] > 0.0:
				return Defs.O_LIGHT[object_type]
	return Defs.TILE * 0.5


func _process(delta: float) -> void:
	if sim == null or terrain == null:
		return
	terrain.set_land_rect(Rect2i())
	if mode == "land" and enabled and hover != null:
		terrain.hide_brush()
		var hp: Vector3 = hover
		var parcel := sim.course.parcel_of(int(hp.x / Defs.TILE), int(hp.z / Defs.TILE))
		var ok := sim.course.parcel_for_sale(parcel)
		terrain.set_land_rect(sim.course.parcel_rect(parcel), Color(0.5, 1.0, 0.6) if ok else Color(1.0, 0.45, 0.4))
	elif mode == "" or not enabled or hover == null:
		terrain.hide_brush()
	else:
		var col := Color(1.0, 1.0, 1.0)
		if mode == "bulldoze":
			col = Color(1.0, 0.5, 0.4)
		elif mode == "hole":
			col = Color(0.4, 0.75, 1.0)
		terrain.set_brush(hover, radius_m(), col)
	if mode == "hole" and _tee != null and hover != null:
		_update_preview()
	elif _ribbon != null and mode != "hole":
		_ribbon.visible = false
	if _down and mode == "sculpt" and hover != null:
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.07
			var fine := Input.is_key_pressed(KEY_SHIFT)
			var amount := 0.04 if fine else 0.2
			if sculpt_mode == "flatten":
				amount = _level
			var p: Vector3 = hover
			if not sim.sculpt(sculpt_mode, p.x, p.z, radius_m(), amount):
				_warn_broke()
			else:
				SoundDesk.ui("dig")


## A brush stroke ends when the button comes up, wherever the pointer is.
func _input(event: InputEvent) -> void:
	if _down and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_down = false


func _unhandled_input(event: InputEvent) -> void:
	if sim == null or not enabled:
		return
	if event is InputEventMouseMotion:
		hover = terrain.pick(rig.cam, (event as InputEventMouseMotion).position)
		if _down and (mode == "terrain" or mode == "object" or mode == "bulldoze"):
			_apply()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if not mb.pressed:
			_down = false
			# With no tool out, a click picks a person. A drag moved the map
			# instead, so it picks nobody.
			if mode == "" and not rig.dragged:
				var who: Variant = world.pick_person(mb.position)
				world.selected = who
				selection_changed.emit(who)
			return
		if mode == "":
			return
		# Command-drag moves the map and Option-drag turns it, even with a tool out
		if mb.alt_pressed or mb.meta_pressed:
			return
		hover = terrain.pick(rig.cam, mb.position)
		if hover == null:
			return
		_down = true
		_last_tile = Vector2i(-999, -999)
		_tick = 0.0
		var p: Vector3 = hover
		_level = p.y
		if mode == "hole":
			_down = false
			if sim.course.holes.size() >= sim.hole_cap():
				_warn("The %s allows %d holes. Upgrade the clubhouse (Build, Clubhouse) to lay out more." % [sim.clubhouse_name().to_lower(), sim.hole_cap()])
				return
			_click_hole(p)
		elif mode == "land":
			_down = false
			var tile := sim.course.tile_of(p.x, p.z)
			match sim.buy_land(tile.x, tile.y):
				1:
					if sim.land_credits > 0:
						sim.toast.emit("Land claimed. %d more free parcel%s to come." % [sim.land_credits, "" if sim.land_credits == 1 else "s"], "good")
					else:
						sim.toast.emit("Land bought. The next parcel will cost %s." % Defs.money(sim.land_price()), "good")
				0:
					sim.toast.emit("That land is not for sale.", "info")
				_:
					_warn_broke()
		else:
			_apply()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE and mode != "":
			set_mode("")
			get_viewport().set_input_as_handled()


func _apply() -> void:
	if hover == null:
		return
	var p: Vector3 = hover
	var tile := sim.course.tile_of(p.x, p.z)
	if tile == _last_tile:
		return
	_last_tile = tile
	if (mode == "terrain" or mode == "object") and not sim.course.can_build(tile.x, tile.y):
		_warn("You can't build there. %s" % ("Buy the land first." if sim.course.in_bounds(tile.x, tile.y) and sim.course.locked[tile.y * sim.course.w + tile.x] != 0 else "It's on the volcano."))
		return
	match mode:
		"terrain":
			var painted := sim.paint(tile.x, tile.y, brush, terrain_type)
			if painted < 0:
				_warn_broke()
			elif painted > 0:
				SoundDesk.ui("paint")
		"object":
			var placed := sim.place_object(tile.x, tile.y, object_type)
			if placed < 0:
				_warn_broke()
			elif placed > 0:
				SoundDesk.ui("place")
		"bulldoze":
			var cleared := false
			for ty in range(tile.y - brush, tile.y + brush + 1):
				for tx in range(tile.x - brush, tile.x + brush + 1):
					if sim.remove_object(tx, ty):
						cleared = true
			if cleared:
				SoundDesk.ui("remove")


## Par and yardage of the hole the pointer would make, and a ribbon along it.
func _update_preview() -> void:
	if sim == null or _tee == null or hover == null:
		_preview_text = ""
		return
	var p: Vector3 = hover
	var tile := sim.course.tile_of(p.x, p.z)
	if tile == _preview_tile and _preview_text != "":
		return
	_preview_tile = tile
	var tee: Vector3 = _tee
	var pin := sim.course.on_ground(p.x, p.z)
	if Vector2(pin.x - tee.x, pin.z - tee.z).length() < 40.0:
		_preview_text = "Too short (a hole needs 45 yards)."
		_show_route(PackedVector2Array())
		return
	var measured: Dictionary = Hole.measure(sim.course, tee, pin)
	_preview_text = "Par %d · %d yd." % [int(measured.par), Defs.yards(float(measured.length))]
	var pts: PackedVector2Array = measured.line
	_show_route(pts)


func _show_route(pts: PackedVector2Array) -> void:
	if _ribbon_mesh == null:
		return
	_ribbon_mesh.clear_surfaces()
	if pts.size() < 2:
		_ribbon.visible = false
		return
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p: Vector2 = pts[i]
		var prev: Vector2 = pts[i - 1] if i > 0 else p
		var nxt: Vector2 = pts[i + 1] if i + 1 < pts.size() else p
		var dir := nxt - prev
		if dir.length_squared() < 0.01:
			dir = Vector2(1.0, 0.0)
		else:
			dir = dir.normalized()
		var side := Vector2(-dir.y, dir.x) * 0.45
		var y := sim.course.height_at(p.x, p.y) + 0.35
		_ribbon_mesh.surface_add_vertex(Vector3(p.x + side.x, y, p.y + side.y))
		_ribbon_mesh.surface_add_vertex(Vector3(p.x - side.x, y, p.y - side.y))
	_ribbon_mesh.surface_end()
	_ribbon.visible = true


func _click_hole(p: Vector3) -> void:
	var course := sim.course
	var tile := course.tile_of(p.x, p.z)
	if _tee == null:
		if course.terrain_at(p.x, p.z) == Defs.T.WATER:
			sim.toast.emit("A tee can't go in the %s." % sim.terrain_name(Defs.T.WATER).to_lower(), "bad")
			return
		if not course.can_build(tile.x, tile.y):
			_warn("You can't put a tee there.")
			return
		if course.terrain_at(p.x, p.z) != Defs.T.TEE:
			if sim.paint(tile.x, tile.y, 0, Defs.T.TEE) < 0:
				_warn_broke()
				return
		_tee = course.tile_center(tile.x, tile.y)
		_marker.position = (_tee as Vector3) + Vector3(0, 3.0, 0)
		_marker.visible = true
		tool_changed.emit()
		return
	if course.terrain_at(p.x, p.z) != Defs.T.GREEN:
		sim.toast.emit("The pin has to go on a green. Paint one first.", "bad")
		return
	var tee: Vector3 = _tee
	if Vector2(p.x - tee.x, p.z - tee.z).length() < 40.0:
		sim.toast.emit("That hole is too short. Put the pin at least 45 yards from the tee.", "bad")
		return
	var hole := sim.add_hole(tee, p)
	if hole == null:
		_warn_broke()
		return
	sim.toast.emit("Hole %d is open: par %d, %d yards." % [course.holes.size(), hole.par, Defs.yards(hole.length)], "good")
	set_mode("")
	hole_added.emit(course.holes.size() - 1)


func _warn_broke() -> void:
	_warn("You can't afford that.")


func _warn(text: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _warned > 3.0:
		_warned = now
		sim.toast.emit(text, "bad")
