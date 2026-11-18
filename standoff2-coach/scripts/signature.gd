extends Control
## Поле для подписи мышью (или пальцем).

signal changed
var strokes: Array = []      # Array[PackedVector2Array]
var drawing: bool = false
var ink := Color("1d2c6b")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS

func has_signature() -> bool:
	var n: int = 0
	for s in strokes:
		n += s.size()
	return n > 8

func clear_sig() -> void:
	strokes.clear()
	queue_redraw()
	changed.emit()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		drawing = e.pressed
		if e.pressed:
			strokes.append(PackedVector2Array([e.position]))
		else:
			changed.emit()
		accept_event()
	elif e is InputEventMouseMotion and drawing:
		var p: Vector2 = e.position.clamp(Vector2.ZERO, size)
		var s: PackedVector2Array = strokes[strokes.size() - 1]
		s.append(p)
		strokes[strokes.size() - 1] = s
		queue_redraw()
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.2, 0.45, 0.035))
	if strokes.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(10, size.y * 0.55), "✎", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.25))
	draw_line(Vector2(0, size.y - 6), Vector2(size.x, size.y - 6), Color(0, 0, 0, 0.55), 1.5)
	for s in strokes:
		if s.size() > 1:
			draw_polyline(s, ink, 2.4, true)
