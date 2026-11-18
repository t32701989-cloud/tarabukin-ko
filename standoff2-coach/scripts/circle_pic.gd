extends Control
## Круглый портрет с обводкой.

var tex: Texture2D
var ring := Color(1, 1, 1, 0.85)
var bg := Color("2a303c")

func setup(t: Texture2D, sz: float, ring_col: Color = Color(1, 1, 1, 0.85)) -> Control:
	tex = t
	ring = ring_col
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 48:
		var a: float = TAU * i / 48.0
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * (r - 3.0))
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	draw_colored_polygon(pts, bg)
	if tex != null:
		draw_colored_polygon(pts, Color.WHITE, uvs, tex)
	draw_arc(c, r - 2.0, 0, TAU, 48, ring, 3.0, true)
