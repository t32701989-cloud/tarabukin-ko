extends Control
## Фон главного меню: медленно плывущая мозаика из плиток команд и кубок.

const Teams := preload("res://scripts/teams.gd")
const TILE := 150.0

var tiles: Array = []      # [{color, tag, logo}]
var t: float = 0.0
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	var src: Array = []
	for tm in Teams.START_TEAMS:
		var logo: Texture2D = null
		var lp: String = str(tm.get("logo", ""))
		if lp != "" and ResourceLoader.exists(lp):
			logo = load(lp)
		src.append({"color": Color(tm["color"]), "tag": tm["tag"], "logo": logo})
	var extra := ["5aa9ff", "e74c3c", "2ecc71", "8e44ad", "f1c40f", "1abc9c", "e67e22", "95a5a6"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 80:
		if rng.randf() < 0.55:
			tiles.append(src[rng.randi() % src.size()])
		else:
			tiles.append({"color": Color(extra[rng.randi() % extra.size()]), "tag": "", "logo": null})

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color("101217"))
	var cols: int = int(sz.x / TILE) + 3
	var rows: int = int(sz.y / TILE) + 3
	var off := Vector2(fmod(t * 12.0, TILE), fmod(t * 5.0, TILE))
	for r in rows:
		for c in cols:
			var tile: Dictionary = tiles[(r * 7 + c * 3) % tiles.size()]
			var pos := Vector2((c - 1) * TILE + off.x, (r - 1) * TILE - off.y)
			var rect := Rect2(pos + Vector2(3, 3), Vector2(TILE - 6, TILE - 6))
			var col: Color = tile["color"]
			draw_rect(rect, Color(col.r, col.g, col.b, 0.22))
			if tile["logo"] != null:
				draw_texture_rect(tile["logo"], rect.grow(-28), false, Color(1, 1, 1, 0.20))
			elif tile["tag"] != "":
				draw_string(font, rect.position + Vector2(0, TILE * 0.58), tile["tag"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 34, Color(1, 1, 1, 0.16))
	# затемнение слева для читаемости меню
	var steps := 24
	for i in steps:
		var a: float = 0.92 * (1.0 - float(i) / steps)
		draw_rect(Rect2(i * sz.x * 0.6 / steps, 0, sz.x * 0.6 / steps + 1, sz.y), Color(0.06, 0.07, 0.09, a))
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.07, 0.09, 0.35))
	_draw_cup(Vector2(sz.x * 0.68, sz.y * 0.52), minf(sz.y / 720.0, sz.x / 1280.0))

func _ell(c: Vector2, rx: float, ry: float, a0: float, a1: float, n: int = 24) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n + 1:
		var a: float = a0 + (a1 - a0) * float(i) / n
		p.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return p

## Оригинальный кубок: чаша, ручки, ножка, постамент со звездой.
func _draw_cup(c: Vector2, k: float) -> void:
	var gold := Color("e8b44a")
	var gold_d := Color("a8761f")
	var gold_l := Color("ffe39a")
	var bob: float = sin(t * 1.2) * 4.0 * k
	c.y += bob
	# свечение
	for i in 6:
		draw_circle(c + Vector2(0, -40 * k), (230 - i * 30) * k, Color(1, 0.75, 0.3, 0.035))
	# постамент
	draw_rect(Rect2(c + Vector2(-110, 150) * k, Vector2(220, 46) * k), Color("1d2533"))
	draw_rect(Rect2(c + Vector2(-90, 120) * k, Vector2(180, 34) * k), Color("27324a"))
	draw_rect(Rect2(c + Vector2(-90, 120) * k, Vector2(180, 6) * k), Color("3b4a6b"))
	# ножка
	draw_colored_polygon(PackedVector2Array([c + Vector2(-60, 120) * k, c + Vector2(60, 120) * k, c + Vector2(30, 90) * k, c + Vector2(-30, 90) * k]), gold_d)
	draw_rect(Rect2(c + Vector2(-14, 20) * k, Vector2(28, 72) * k), gold)
	draw_rect(Rect2(c + Vector2(-14, 20) * k, Vector2(8, 72) * k), gold_l)
	draw_colored_polygon(_ell(c + Vector2(0, 46) * k, 30 * k, 10 * k, 0, TAU), gold_d)
	# ручки
	for s in [-1.0, 1.0]:
		draw_arc(c + Vector2(s * 112, -95) * k, 46 * k, -PI / 2 if s > 0 else PI / 2, PI / 2 if s > 0 else 3 * PI / 2, 24, gold_d, 16 * k)
		draw_arc(c + Vector2(s * 112, -95) * k, 46 * k, -PI / 2 if s > 0 else PI / 2, PI / 2 if s > 0 else 3 * PI / 2, 24, gold, 9 * k)
	# чаша
	var bowl := PackedVector2Array([c + Vector2(-120, -170) * k, c + Vector2(120, -170) * k])
	for p in _ell(c + Vector2(0, -170) * k, 120 * k, 190 * k, 0.0, PI, 28):
		bowl.append(p)
	var bowl_clip := PackedVector2Array()
	for p in bowl:
		bowl_clip.append(Vector2(p.x, minf(p.y, c.y + 22 * k)))
	draw_colored_polygon(bowl_clip, gold)
	var shine := PackedVector2Array([c + Vector2(-95, -165) * k, c + Vector2(-62, -165) * k, c + Vector2(-48, -20) * k, c + Vector2(-70, -40) * k])
	draw_colored_polygon(shine, gold_l)
	draw_colored_polygon(_ell(c + Vector2(0, -170) * k, 120 * k, 16 * k, 0, TAU), gold_d)
	draw_colored_polygon(_ell(c + Vector2(0, -172) * k, 106 * k, 11 * k, 0, TAU), Color("5a3d0e"))
	# звезда
	var star := PackedVector2Array()
	for i in 10:
		var r: float = (34.0 if i % 2 == 0 else 14.0) * k
		var a: float = -PI / 2 + i * PI / 5
		star.append(c + Vector2(0, -95) * k + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(star, Color("fff3c4"))
	# табличка
	draw_rect(Rect2(c + Vector2(-46, 162) * k, Vector2(92, 22) * k), gold_d)
	draw_string(font, c + Vector2(-46, 179) * k, "SO2", HORIZONTAL_ALIGNMENT_CENTER, 92 * k, int(16 * k), Color("2a1c05"))
