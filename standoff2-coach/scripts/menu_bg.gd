extends Control
## Фон главного меню: размытая мозаика команд (фото) и кубок, лёгкая анимация.

var bg_tex: Texture2D
var cup_tex: Texture2D
var t: float = 0.0
var show_cup: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_tex = load("res://assets/ui/menu_bg.jpg")
	cup_tex = load("res://assets/ui/trophy.png")

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color("101217"))
	if bg_tex != null:
		# «cover» с медленным наездом камеры
		var ts := bg_tex.get_size()
		var k: float = maxf(sz.x / ts.x, sz.y / ts.y) * (1.06 + 0.02 * sin(t * 0.12))
		var ds := ts * k
		var off := (sz - ds) * 0.5 + Vector2(sin(t * 0.07) * 18.0, cos(t * 0.05) * 10.0)
		draw_texture_rect(bg_tex, Rect2(off, ds), false)
	if show_cup and cup_tex != null:
		var h: float = sz.y * 0.6
		var cs := cup_tex.get_size() * (h / cup_tex.get_size().y)
		var c := Vector2(sz.x * 0.70, sz.y * 0.5 + sin(t * 1.1) * 5.0)
		# мягкое свечение за кубком
		for i in 8:
			draw_circle(c, (cs.x * 0.62) * (1.0 - i * 0.1), Color(1.0, 0.78, 0.35, 0.025))
		draw_texture_rect(cup_tex, Rect2(c - cs * 0.5, cs), false)
