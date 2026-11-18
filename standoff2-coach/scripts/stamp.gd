extends Control
## Круглая печать организации (появляется после подписи).

var text_top: String = ""
var tag: String = ""
var col := Color(0.16, 0.25, 0.62, 0.78)
var appear: float = 0.0

func setup(name_t: String, tag_t: String) -> Control:
	text_top = name_t.to_upper()
	tag = tag_t
	custom_minimum_size = Vector2(120, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rotation = deg_to_rad(-12)
	pivot_offset = Vector2(60, 60)
	return self

func _process(delta: float) -> void:
	if visible and appear < 1.0:
		appear = minf(1.0, appear + delta * 4.0)
		scale = Vector2.ONE * (1.6 - 0.6 * appear)
		modulate.a = appear
		queue_redraw()

func _draw() -> void:
	var c := Vector2(60, 60)
	var font: Font = get_theme_default_font()
	draw_arc(c, 56, 0, TAU, 64, col, 3.0, true)
	draw_arc(c, 50, 0, TAU, 64, col, 1.5, true)
	draw_arc(c, 30, 0, TAU, 48, col, 1.5, true)
	# текст по кругу
	var t: String = (text_top + " • ").repeat(2)
	var n: int = mini(t.length(), 40)
	for i in n:
		var a: float = -PI / 2 + TAU * float(i) / n
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * 40
		draw_set_transform(p, a + PI / 2, Vector2.ONE)
		draw_string(font, Vector2(-3, 4), t[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	draw_string(font, Vector2(c.x - 28, c.y + 7), tag, HORIZONTAL_ALIGNMENT_CENTER, 56, 18, col)
