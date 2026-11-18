extends Control
## Простые векторные иконки для бокового меню.

var kind: String = "home"
var col := Color(0.85, 0.88, 0.95)

func setup(k: String, sz: float = 22.0, c: Color = Color(0.85, 0.88, 0.95)) -> Control:
	kind = k
	col = c
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _draw() -> void:
	var s: float = minf(size.x, size.y)
	draw_set_transform(Vector2((size.x - s) * 0.5, (size.y - s) * 0.5), 0.0, Vector2(s / 24.0, s / 24.0))
	var w := 2.0
	match kind:
		"home":
			draw_colored_polygon(PackedVector2Array([Vector2(12, 3), Vector2(22, 12), Vector2(19, 12), Vector2(19, 21), Vector2(5, 21), Vector2(5, 12), Vector2(2, 12)]), col)
			draw_rect(Rect2(10, 14, 4, 7), Color(0, 0, 0, 0.45))
		"mail":
			draw_rect(Rect2(2, 5, 20, 14), col, false, w)
			draw_polyline(PackedVector2Array([Vector2(2, 6), Vector2(12, 13), Vector2(22, 6)]), col, w)
		"squad":
			draw_circle(Vector2(8, 8), 3.5, col); draw_circle(Vector2(16, 8), 3.5, col)
			draw_colored_polygon(PackedVector2Array([Vector2(1, 20), Vector2(3, 13), Vector2(13, 13), Vector2(15, 20)]), col)
			draw_colored_polygon(PackedVector2Array([Vector2(9, 20), Vector2(11, 13), Vector2(21, 13), Vector2(23, 20)]), col)
		"staff":
			draw_circle(Vector2(12, 7), 4.5, col)
			draw_colored_polygon(PackedVector2Array([Vector2(4, 22), Vector2(6, 14), Vector2(18, 14), Vector2(20, 22)]), col)
		"training":
			draw_polyline(PackedVector2Array([Vector2(2, 19), Vector2(8, 12), Vector2(13, 15), Vector2(21, 5)]), col, 2.5)
			draw_colored_polygon(PackedVector2Array([Vector2(16, 4), Vector2(22, 4), Vector2(22, 10)]), col)
		"tactics":
			draw_rect(Rect2(3, 3, 18, 18), col, false, w)
			draw_line(Vector2(7, 8), Vector2(11, 12), col, w); draw_line(Vector2(11, 8), Vector2(7, 12), col, w)
			draw_arc(Vector2(16, 16), 2.5, 0, TAU, 12, col, w)
			draw_line(Vector2(10, 15), Vector2(13, 15), col, 1.5)
		"transfers":
			draw_line(Vector2(3, 8), Vector2(19, 8), col, w); draw_colored_polygon(PackedVector2Array([Vector2(16, 4), Vector2(22, 8), Vector2(16, 12)]), col)
			draw_line(Vector2(5, 16), Vector2(21, 16), col, w); draw_colored_polygon(PackedVector2Array([Vector2(8, 12), Vector2(2, 16), Vector2(8, 20)]), col)
		"tournaments":
			draw_colored_polygon(PackedVector2Array([Vector2(6, 3), Vector2(18, 3), Vector2(17, 11), Vector2(12, 15), Vector2(7, 11)]), col)
			draw_rect(Rect2(11, 14, 2, 4), col); draw_rect(Rect2(7, 18, 10, 3), col)
			draw_arc(Vector2(6, 7), 3, PI / 2, 3 * PI / 2, 8, col, 1.5); draw_arc(Vector2(18, 7), 3, -PI / 2, PI / 2, 8, col, 1.5)
		"stats":
			draw_rect(Rect2(3, 13, 4, 8), col); draw_rect(Rect2(10, 8, 4, 13), col); draw_rect(Rect2(17, 4, 4, 17), col)
		"finance":
			draw_circle(Vector2(12, 12), 9, col)
			draw_string(ThemeDB.fallback_font, Vector2(7.5, 17), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.12, 0.16))
		"profile":
			draw_arc(Vector2(12, 12), 9.5, 0, TAU, 24, col, w)
			draw_circle(Vector2(12, 10), 3.5, col)
			draw_arc(Vector2(12, 21), 6, PI + 0.4, TAU - 0.4, 10, col, w)
		"settings":
			for i in 8:
				var a: float = TAU * i / 8.0
				draw_line(Vector2(12, 12) + Vector2(cos(a), sin(a)) * 6, Vector2(12, 12) + Vector2(cos(a), sin(a)) * 10, col, 3.0)
			draw_arc(Vector2(12, 12), 5.5, 0, TAU, 16, col, 2.5)
		"exit":
			draw_rect(Rect2(3, 3, 11, 18), col, false, w)
			draw_line(Vector2(10, 12), Vector2(21, 12), col, w)
			draw_colored_polygon(PackedVector2Array([Vector2(18, 8), Vector2(23, 12), Vector2(18, 16)]), col)
		"thumb":
			draw_rect(Rect2(3, 10, 4, 11), col)
			draw_colored_polygon(PackedVector2Array([Vector2(8, 10), Vector2(12, 3), Vector2(14, 4), Vector2(13, 10), Vector2(20, 10), Vector2(21, 12), Vector2(19, 21), Vector2(8, 21)]), col)
		"warn":
			draw_colored_polygon(PackedVector2Array([Vector2(12, 2), Vector2(23, 21), Vector2(1, 21)]), col)
			draw_rect(Rect2(11, 8, 2, 7), Color(0.1, 0.1, 0.1)); draw_rect(Rect2(11, 17, 2, 2), Color(0.1, 0.1, 0.1))
