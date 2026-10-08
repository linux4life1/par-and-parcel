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
var station_for: Crew.Member = null   # the next ground click is their post
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
var preview_par := 0
var preview_length := 0.0
var preview_warn := false
var _preview_searches := 0
var _preview_frame := 0
var _preview_due := 0
var _ribbon: MeshInstance3D
var _ribbon_mesh: ImmediateMesh
var _ribbon_mat: StandardMaterial3D
var _tag_layer: CanvasLayer
var _tag: Label
var _tag_ink := Color(0, 0, 0, 0)


func _ready() -> void:
	_marker = MeshInstance3D.new()
	_marker.mesh = WorldView._cyl(0.12, 0.12, 6.0, 6)
	_marker.material_override = WorldView.glow(Color(0.3, 0.7, 1.0))
	_marker.visible = false
	add_child(_marker)
	_ribbon_mesh = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _ribbon_mesh
	_ribbon_mat = StandardMaterial3D.new()
	_ribbon_mat.albedo_color = Color(0.75, 0.9, 1.0, 0.38)
	_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon.material_override = _ribbon_mat
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbon.visible = false
	add_child(_ribbon)
	_tag_layer = CanvasLayer.new()
	_tag_layer.layer = 30
	add_child(_tag_layer)
	_tag = Label.new()
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_tag.add_theme_constant_override("shadow_offset_x", 1)
	_tag.add_theme_constant_override("shadow_offset_y", 1)
	_tag.visible = false
	_tag_layer.add_child(_tag)


func bind(s: Sim) -> void:
	sim = s
	set_mode("")


func set_mode(m: String) -> void:
	mode = m
	if m != "":
		station_for = null
	_down = false
	_tee = null
	_preview_tile = Vector2i(-999, -999)
	_preview_text = ""
	preview_par = 0
	preview_length = 0.0
	preview_warn = false
	if _ribbon != null:
		_ribbon.visible = false
	if _tag != null:
		_tag.visible = false
	if rig != null:
		rig.tool_active = m != ""
	if _marker != null:
		_marker.visible = false
	_last_tile = Vector2i(-999, -999)
	if terrain != null:
		terrain.material.set_shader_parameter("grid_alpha", 1.0 if m != "" else 0.0)
	tool_changed.emit()


func arm_station(who: Crew.Member) -> void:
	if mode != "":
		set_mode("")
	station_for = who
	tool_changed.emit()


func hint() -> String:
	if station_for != null and sim != null and sim.crew.members.has(station_for):
		return "Click the ground where %s should work." % station_for.name
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
	elif station_for != null and enabled and hover != null:
		terrain.set_brush(hover, sim.crew.home_radius(), Color(0.95, 0.75, 0.35))
	elif mode == "" or not enabled or hover == null:
		terrain.hide_brush()
	else:
		var col := Color(1.0, 1.0, 1.0)
		if mode == "bulldoze":
			col = Color(1.0, 0.5, 0.4)
		elif mode == "hole":
			col = Color(0.4, 0.75, 1.0)
		terrain.set_brush(hover, radius_m(), col)
	_preview_frame += 1
	if mode == "hole" and _tee != null and hover != null:
		_update_preview(true)
	elif mode == "hole" and hover == null:
		if _ribbon != null:
			_ribbon.visible = false
		_hide_tag()
	elif _ribbon != null and mode != "hole":
		_ribbon.visible = false
		_hide_tag()
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
				if station_for != null and sim.crew.members.has(station_for):
					var posted: Crew.Member = station_for
					var person: Variant = world.pick_person(mb.position)
					var spot: Variant = terrain.pick(rig.cam, mb.position)
					if person == null and spot != null:
						var at: Vector3 = spot
						sim.crew.station(posted, at)
						sim.toast.emit("%s will work around that spot." % posted.name, "good")
						station_for = null
						world.selected = posted
						selection_changed.emit(posted)
						return
				station_for = null
				var who: Variant = world.pick_person(mb.position)
				if who == null:
					var spot: Variant = terrain.pick(rig.cam, mb.position)
					if spot != null:
						var at: Vector3 = spot
						var tile := sim.course.tile_of(at.x, at.z)
						var ci := tile.y * sim.course.w + tile.x
						if sim.course.in_bounds(tile.x, tile.y) and sim.course.can_switch(int(sim.course.objects[ci])):
							world.selected = null
							selection_changed.emit(tile)
							return
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


## Par and yardage of the hole the pointer would make, and a faint line along
## the same route the hole will be scored on. `paced` is the per-frame path:
## the search waits for the throttle in the preview data. A direct call, from
## a test or the first look, searches as soon as the tile changes.
func _update_preview(paced: bool = false) -> void:
	if sim == null or _tee == null or hover == null:
		_preview_text = ""
		_hide_tag()
		if _ribbon != null:
			_ribbon.visible = false
		return
	var p: Vector3 = hover
	var tile := sim.course.tile_of(p.x, p.z)
	if tile == _preview_tile and _preview_text != "":
		_place_tag()
		return
	var book := _preview_book()
	var every := maxi(int(book.get("throttle_frames", 1)), 1)
	if paced and _preview_frame < _preview_due:
		_place_tag()
		return
	_preview_due = _preview_frame + every
	_preview_tile = tile
	_preview_searches += 1
	var tee: Vector3 = _tee
	var pin := sim.course.on_ground(p.x, p.z)
	var measured: Dictionary = Hole.measure(sim.course, tee, pin)
	preview_par = int(measured.par)
	preview_length = float(measured.length)
	var short_m := float(book.get("short_metres", 90.0))
	preview_warn = preview_length < short_m or not bool(measured.playable)
	_preview_text = "Par %d · %d yd." % [preview_par, Defs.yards(preview_length)]
	if Vector2(pin.x - tee.x, pin.z - tee.z).length() < 40.0:
		_preview_text = "Too short (a hole needs 45 yards). " + _preview_text
	var pts: PackedVector2Array = measured.line
	_show_route(pts)
	_place_tag()


func _preview_book() -> Dictionary:
	if sim != null and sim.db != null:
		return sim.db.preview
	return {}


func _ink(book: Dictionary, key: String, fallback: Color) -> Color:
	var raw: Variant = book.get(key, [])
	if raw is Array:
		var row: Array = raw
		if row.size() >= 3:
			var a := 1.0
			if row.size() > 3:
				a = float(row[3])
			return Color(float(row[0]), float(row[1]), float(row[2]), a)
	return fallback


func _place_tag() -> void:
	if _tag == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var book := _preview_book()
	var ink := _ink(book, "warn_colour" if preview_warn else "colour", Color(0.97, 0.45, 0.4) if preview_warn else Color(0.93, 0.96, 0.93))
	if _tag.text != _preview_text:
		_tag.text = _preview_text
	if not _tag_ink.is_equal_approx(ink):
		_tag.add_theme_color_override("font_color", ink)
		_tag_ink = ink
	_tag.visible = _preview_text != ""
	var origin := vp.get_mouse_position() + Vector2(float(book.get("offset_x", 18.0)), float(book.get("offset_y", -32.0)))
	var bounds := vp.get_visible_rect().size
	_tag.position = Vector2(clampf(origin.x, 8.0, maxf(bounds.x - 8.0, 8.0)), clampf(origin.y, 8.0, maxf(bounds.y - 8.0, 8.0)))


func _hide_tag() -> void:
	if _tag != null:
		_tag.visible = false


func _show_route(pts: PackedVector2Array) -> void:
	if _ribbon_mesh == null:
		return
	_ribbon_mesh.clear_surfaces()
	if pts.size() < 2:
		_ribbon.visible = false
		return
	var book := _preview_book()
	if _ribbon_mat != null:
		_ribbon_mat.albedo_color = _ink(book, "warn_line_colour" if preview_warn else "line_colour", Color(0.75, 0.9, 1.0, 0.38))
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
		var side := Vector2(-dir.y, dir.x) * 0.35
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
		_update_preview()
		tool_changed.emit()
		return
	if not Defs.is_green(course.terrain_at(p.x, p.z)):
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
	hole.open = false
	sim.toast.emit("Hole %d is a draft: par %d, %d yards. Test it, then open it to the public." % [course.holes.size(), hole.par, Defs.yards(hole.length)], "good")
	set_mode("")
	hole_added.emit(course.holes.size() - 1)


func _warn_broke() -> void:
	_warn("You can't afford that.")


func _warn(text: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _warned > 3.0:
		_warned = now
		sim.toast.emit(text, "bad")
