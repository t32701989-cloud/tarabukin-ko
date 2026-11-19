extends Control
## Линейный график значений 0..20 (история атрибута).

var values: Array = []
var labels: Array = []
var col := Color("c86bff")

func setup(v: Array, l: Array, h: float = 170.0) -> Control:
	values = v
	labels = l
	custom_minimum_size = Vector2(0, h)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _draw() -> void:
	var font: Font = get_theme_default_font()
	var left: float = 26.0
	var h: float = size.y - 20.0
	for g in [0, 5, 10, 15, 20]:
		var y: float = h - h * g / 20.0 + 4
		draw_line(Vector2(left, y), Vector2(size.x, y), Color(1, 1, 1, 0.07), 1.0)
		draw_string(font, Vector2(0, y + 4), str(g), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.4))
	var n: int = values.size()
	if n == 0:
		draw_string(font, Vector2(left + 10, h * 0.5), tr("История появится после первой недели."), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.4))
		return
	var w: float = (size.x - left) / maxf(1.0, float(n - 1)) if n > 1 else 0.0
	var pts := PackedVector2Array()
	for i in n:
		var x: float = left + i * w if n > 1 else left + (size.x - left) * 0.5
		var y: float = h - h * clampf(float(values[i]), 0.0, 20.0) / 20.0 + 4
		pts.append(Vector2(x, y))
		draw_rect(Rect2(x - 5, y, 10, h + 4 - y), Color(col.r, col.g, col.b, 0.18))
	if n > 1:
		draw_polyline(pts, col, 3.0, true)
	for p in pts:
		draw_circle(p, 3.5, col)
	for i in n:
		if i < labels.size() and (n <= 10 or i % 3 == 0):
			draw_string(font, Vector2(pts[i].x - 12, size.y - 2), str(labels[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
