class_name IconButton
extends Button
## A small button that draws its own symbol, so the camera controls do not
## depend on what glyphs the font happens to have.

var kind := ""


static func make(icon_kind: String, tip: String) -> IconButton:
	var b := IconButton.new()
	b.kind = icon_kind
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(32, 28)
	return b


func _draw() -> void:
	var c := size * 0.5
	var col := UIKit.TEXT if not disabled else UIKit.MUTED
	var w := 2.0
	match kind:
		"turn_left", "turn_right":
			# most of a circle, with an arrowhead on the leading end
			var flip := -1.0 if kind == "turn_left" else 1.0
			var r := 7.0
			var a0 := -PI * 0.5 - flip * 2.2
			var a1 := -PI * 0.5 + flip * 1.7
			draw_arc(c, r, a0, a1, 20, col, w, true)
			var tip := c + Vector2(cos(a1), sin(a1)) * r
			var along := Vector2(-sin(a1), cos(a1)) * flip
			var out := Vector2(cos(a1), sin(a1))
			draw_colored_polygon(PackedVector2Array([tip + along * 5.0, tip - out * 4.0 - along * 1.0, tip + out * 4.0 - along * 1.0]), col)
		"tilt_up", "tilt_down":
			var s := -1.0 if kind == "tilt_up" else 1.0
			draw_polyline(PackedVector2Array([c + Vector2(-6, -3 * s), c + Vector2(0, 3 * s), c + Vector2(6, -3 * s)]), col, w + 0.5, true)
		"zoom_in", "zoom_out":
			draw_line(c + Vector2(-6, 0), c + Vector2(6, 0), col, w + 0.5, true)
			if kind == "zoom_in":
				draw_line(c + Vector2(0, -6), c + Vector2(0, 6), col, w + 0.5, true)
		"reset":
			draw_arc(c, 6.5, 0.0, TAU, 24, col, w, true)
			draw_circle(c, 2.0, col)
