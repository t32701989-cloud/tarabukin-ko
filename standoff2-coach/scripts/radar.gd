extends Control
## Радарная диаграмма (5 осей, значения 0..1).

var axes: Array = []
var values: Array = []
var col := Color("3fe0c5")

func setup(ax: Array, vals: Array, sz: float = 220.0) -> Control:
	axes = ax
	values = vals
	custom_minimum_size = Vector2(sz + 120, sz + 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _pt(i: int, r: float, c: Vector2) -> Vector2:
	var a: float = -PI / 2 + TAU * i / axes.size()
	return c + Vector2(cos(a), sin(a)) * r

func _draw() -> void:
	var n: int = axes.size()
	if n < 3:
		return
	var c := size * 0.5
	var R: float = minf(size.x - 120, size.y - 40) * 0.5
	for ring in [0.25, 0.5, 0.75, 1.0]:
		var pts := PackedVector2Array()
		for i in n + 1:
			pts.append(_pt(i % n, R * ring, c))
		draw_polyline(pts, Color(1, 1, 1, 0.12), 1.0, true)
	for i in n:
		draw_line(c, _pt(i, R, c), Color(1, 1, 1, 0.1), 1.0)
	var poly := PackedVector2Array()
	for i in n:
		poly.append(_pt(i, R * clampf(float(values[i]), 0.05, 1.0), c))
	draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.22))
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, col, 2.5, true)
	for p in poly:
		draw_circle(p, 4.5, col)
	var font: Font = get_theme_default_font()
	for i in n:
		var p2: Vector2 = _pt(i, R + 18, c)
		var t: String = str(axes[i])
		var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, p2 + Vector2(-w * 0.5, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
