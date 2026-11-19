extends Control
## Круговой индикатор прогресса с процентом в центре.

var value: float = 0.0
var col := Color("2fb8e8")
var caption: String = ""
var number: String = ""

func setup(v: float, sz: float, c: Color, cap: String = "", num: String = "") -> Control:
	value = clampf(v, 0.0, 1.0)
	col = c
	caption = cap
	number = num
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
	var t: String = number if number != "" else "%d%%" % int(value * 100)
	var fs: int = int(r * 0.55)
	var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var dy: float = -fs * 0.1 if caption != "" else fs * 0.35
	draw_string(font, c + Vector2(-w * 0.5, dy), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.2) if caption != "" else Color.WHITE)
	if caption != "":
		var cf: int = maxi(9, int(r * 0.24))
		var cw: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cf).x
		draw_string(font, c + Vector2(-cw * 0.5, cf * 1.6), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cf, Color(1, 1, 1, 0.75))
