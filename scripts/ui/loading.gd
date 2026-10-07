class_name LoadingScreen
extends CanvasLayer
## The screen shown while a course is laid out or a save is read back: the
## fairway backdrop, the name, what is happening, a bar, and one tip. The
## heavy work is synchronous, so the bar moves in honest steps: before the
## work, after it, and once the world has drawn its first frames.

var _back := Control.new()
var _title := UIKit.label(Defs.TITLE, 54, Color(0.97, 0.96, 0.9))
var _doing := UIKit.label("", 18, Color(0.85, 0.9, 0.8))
var _tip := UIKit.para("", 16, Color(0.9, 0.93, 0.86))
var _bar := ProgressBar.new()
var _alpha := 0.0
var _want := 0.0
var _busy := false


func _ready() -> void:
	layer = 50
	visible = false
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_STOP
	_back.draw.connect(_draw_back)
	add_child(_back)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.add_child(centre)
	var v := UIKit.vbox(10)
	v.custom_minimum_size = Vector2(620, 0)
	centre.add_child(v)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	var sub := UIKit.label("Build the course. Run the club. Play the round.", 15, Color(0.85, 0.9, 0.8, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(UIKit.gap(26))
	_doing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_doing)
	_bar.custom_minimum_size = Vector2(420, 10)
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.add_theme_stylebox_override("fill", UIKit.box(UIKit.GOLD, 5, 0, 0))
	_bar.add_theme_stylebox_override("background", UIKit.box(Color(0, 0, 0, 0.35), 5, 0, 0))
	v.add_child(_bar)
	v.add_child(UIKit.gap(30))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.custom_minimum_size = Vector2(620, 0)
	v.add_child(_tip)


## Show the screen, do the work, let the world draw itself, fade out.
## Returns what the work returned. Screenshot and test runs skip the show.
func run(doing: String, work: Callable) -> Variant:
	if Game.args.has("shot") or Game.args.has("exit"):
		return work.call()
	_busy = true
	var tips: Array = Game.db.tips.get("tips", [])
	_tip.text = str(tips[randi() % tips.size()]) if not tips.is_empty() else ""
	_doing.text = doing
	_bar.value = 0.05
	_want = 1.0
	_alpha = 1.0
	_back.modulate.a = 1.0
	visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	_bar.value = 0.3
	await get_tree().process_frame
	var result: Variant = work.call()
	_bar.value = 0.72
	_doing.text = "Growing the trees"
	for i in 5:
		await get_tree().process_frame
	_doing.text = "Opening the clubhouse"
	_bar.value = 1.0
	await get_tree().create_timer(0.3).timeout
	_want = 0.0
	_busy = false
	return result


## Hold the screen up for a screenshot (--loadingcard).
func preview() -> void:
	var tips: Array = Game.db.tips.get("tips", [])
	_tip.text = str(tips[0]) if not tips.is_empty() else ""
	_doing.text = "Growing the trees"
	_bar.value = 0.72
	_want = 1.0
	_alpha = 1.0
	_busy = true
	_back.modulate.a = 1.0
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_back.queue_redraw()
	_alpha = move_toward(_alpha, _want, delta * 3.0)
	_back.modulate.a = _alpha
	if _alpha <= 0.0 and _want <= 0.0 and not _busy:
		visible = false


## The fairway backdrop: a green that darkens downward, mowing stripes, a
## soft light top left, the same picture as the disk image.
func _draw_back() -> void:
	var size := _back.size
	for y in range(0, int(size.y), 4):
		var t := y / maxf(size.y, 1.0)
		_back.draw_rect(Rect2(0, y, size.x, 4), Color(0.11, 0.30, 0.17).lerp(Color(0.05, 0.16, 0.09), t))
	var w := size.x * 0.09
	var k0 := int(-size.y / w) - 2
	var k1 := int(size.x / w) + 2
	for k in range(k0, k1):
		var x0 := k * w
		_back.draw_colored_polygon(PackedVector2Array([Vector2(x0, size.y), Vector2(x0 + w * 0.5, size.y), Vector2(x0 + w * 0.5 + size.y * 0.65, 0), Vector2(x0 + size.y * 0.65, 0)]), Color(1, 1, 1, 0.035))
	for i in 10:
		_back.draw_circle(Vector2(size.x * 0.2, size.y * 0.15), size.x * (0.18 + i * 0.05), Color(1, 1, 1, 0.012))
