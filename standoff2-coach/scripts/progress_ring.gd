extends Control
## Круговой индикатор прогресса с процентом в центре.

var value: float = 0.0
var col := Color("2fb8e8")

func setup(v: float, sz: float, c: Color) -> Control:
	value = clampf(v, 0.0, 1.0)
	col = c
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5 - 5.0
	var c := size * 0.5
	draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.1), 8.0, true)
	if value > 0.0:
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU * value, 64, col, 8.0, true)
	var font: Font = get_theme_default_font()
	var t := "%d%%" % int(value * 100)
	var fs: int = int(r * 0.55)
	var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
