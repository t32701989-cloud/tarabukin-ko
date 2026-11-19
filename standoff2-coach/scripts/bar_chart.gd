extends Control
## Простая столбчатая диаграмма (баланс по неделям).

var values: Array = []
var labels: Array = []
var pos_col := Color("6fd35a")
var neg_col := Color("ff5a3c")

func setup(v: Array, l: Array, h: float = 160.0) -> Control:
	values = v
	labels = l
	custom_minimum_size = Vector2(0, h)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _draw() -> void:
	var n: int = values.size()
	var font: Font = get_theme_default_font()
	draw_line(Vector2(0, size.y - 18), Vector2(size.x, size.y - 18), Color(1, 1, 1, 0.15), 1.0)
	if n == 0:
		draw_string(font, Vector2(10, size.y * 0.5), tr("Нет данных — сыграйте первую неделю."), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.4))
		return
	var mx: float = 1.0
	for v in values:
		mx = maxf(mx, absf(float(v)))
	var h: float = size.y - 30
	var zero: float = h * 0.5 + 6
	var has_neg := false
	for v in values:
		if float(v) < 0: has_neg = true
	if not has_neg:
		zero = h + 6
	draw_line(Vector2(0, zero), Vector2(size.x, zero), Color(1, 1, 1, 0.12), 1.0)
	var bw: float = size.x / float(n)
	for i in n:
		var v: float = float(values[i])
		var bh: float = (absf(v) / mx) * (h * (0.5 if has_neg else 1.0) - 4)
		var x: float = i * bw + bw * 0.18
		var r := Rect2(x, zero - bh, bw * 0.64, bh) if v >= 0 else Rect2(x, zero, bw * 0.64, bh)
		draw_rect(r, pos_col if v >= 0 else neg_col)
		if i < labels.size() and (n <= 12 or i % 2 == 0):
			draw_string(font, Vector2(i * bw, size.y - 3), str(labels[i]), HORIZONTAL_ALIGNMENT_CENTER, bw, 10, Color(1, 1, 1, 0.45))
