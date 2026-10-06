class_name SkyIcon
extends Control
## The little sun or moon beside the clock.

var dark := 0.0:
	set(v):
		if absf(v - dark) > 0.01:
			dark = v
			queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(22, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	if dark < 0.5:
		# a sun, turning from gold to orange as it sets
		var col := Color(1.0, 0.86, 0.3).lerp(Color(1.0, 0.55, 0.25), dark * 2.0)
		draw_circle(c, 5.0, col)
		for k in 8:
			var a := k * TAU / 8.0
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * 7.0, c + d * 9.5, col, 1.6, true)
	else:
		# a crescent moon: a pale disc with a bite taken out of it
		var col := Color(0.82, 0.88, 1.0)
		draw_circle(c, 6.5, col)
		draw_circle(c + Vector2(3.2, -2.2), 5.6, Color(0.075, 0.11, 0.1))
