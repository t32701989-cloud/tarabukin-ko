extends Control
## Рейтинг звёздами (0..5, с половинками).

var value: float = 3.0
var star_size: float = 16.0
var color_on := Color("f5c518")
var color_off := Color(1, 1, 1, 0.18)

func setup(v: float, sz: float = 16.0) -> Control:
	value = clampf(v, 0.0, 5.0)
	star_size = sz
	custom_minimum_size = Vector2(sz * 5.4, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _star(c: Vector2, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 10:
		var rr: float = r if i % 2 == 0 else r * 0.45
		var a: float = -PI / 2 + i * PI / 5
		p.append(c + Vector2(cos(a), sin(a)) * rr)
	return p

func _draw() -> void:
	var r: float = star_size * 0.52
	for i in 5:
		var c := Vector2(i * star_size * 1.08 + r, star_size * 0.55)
		var pts := _star(c, r)
		draw_colored_polygon(pts, color_off)
		var fill: float = clampf(value - i, 0.0, 1.0)
		if fill >= 0.99:
			draw_colored_polygon(pts, color_on)
		elif fill > 0.0:
			# половинка: обрезаем левую часть
			var clip := PackedVector2Array()
			var xmax: float = c.x - r + 2.0 * r * fill
			for p in pts:
				clip.append(Vector2(minf(p.x, xmax), p.y))
			draw_colored_polygon(clip, color_on)
