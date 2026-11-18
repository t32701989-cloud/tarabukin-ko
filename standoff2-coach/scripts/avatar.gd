extends Control
## Аватар менеджера: процедурно нарисованное лицо или загруженное фото.

const SKIN := ["f5dccb", "f2d0b1", "e0b48c", "c68e5e", "a0663c", "6e4426"]
const HAIR_COLORS := ["1d1a17", "4a2f1b", "8a5a2b", "d9b56a", "b0b0b0", "f4f4f4", "c0392b", "2e86de", "8e44ad"]
const EYE_COLORS := ["5b3a1e", "2e86de", "3c8d4f", "6b7280"]
const SHIRTS := ["ffb23e", "5aa9ff", "e74c3c", "2ecc71", "1f232b", "f4f4f4", "8e44ad", "34495e"]
const BGS := ["2b3240", "3a2b40", "2b4036", "40352b", "1d2a3a", "402b2b"]
const HAIR_STYLES := ["Лысый", "Короткая", "Ёжик", "Длинные", "Ирокез", "Кудри", "Кепка", "Капюшон"]
const BEARDS := ["Нет", "Щетина", "Борода", "Усы", "Эспаньолка"]
const GLASSES := ["Нет", "Круглые", "Квадратные", "Тёмные"]
const EXTRAS := ["Нет", "Гарнитура", "Серьга", "Шрам"]

## Части внешности: ключ, название, количество вариантов.
const PARTS := [
	["skin", "Кожа", 6], ["hair", "Причёска", 8], ["hair_color", "Цвет волос", 9],
	["eyes", "Глаза", 4], ["beard", "Борода", 5], ["glasses", "Очки", 4],
	["extra", "Аксессуар", 4], ["shirt", "Одежда", 8], ["bg", "Фон", 6],
]

var cfg: Dictionary = {}
var photo: Texture2D = null

func _init() -> void:
	clip_contents = true

static func random_cfg() -> Dictionary:
	var c := {}
	for p in PARTS:
		c[p[0]] = randi() % int(p[2])
	# немного правдоподобия: яркие цвета волос и лысина реже
	if randf() < 0.7:
		c["hair_color"] = randi() % 5
	if randf() < 0.5:
		c["beard"] = 0
	if randf() < 0.55:
		c["glasses"] = 0
	return c

static func part_value_name(key: String, idx: int) -> String:
	match key:
		"hair": return HAIR_STYLES[idx]
		"beard": return BEARDS[idx]
		"glasses": return GLASSES[idx]
		"extra": return EXTRAS[idx]
	return String(TranslationServer.translate("Вариант %d")) % (idx + 1)

func set_cfg(c: Dictionary) -> void:
	cfg = c.duplicate()
	queue_redraw()

func set_photo(tex: Texture2D) -> void:
	photo = tex
	queue_redraw()

func _g(key: String) -> int:
	return int(cfg.get(key, 0))

func _col(arr: Array, key: String) -> Color:
	return Color(arr[_g(key) % arr.size()])

func _ellipse(c: Vector2, rx: float, ry: float, from: float = 0.0, to: float = TAU, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a: float = from + (to - from) * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _draw() -> void:
	var k: float = minf(size.x, size.y) / 100.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	if photo != null:
		draw_texture_rect(photo, Rect2(0, 0, 100, 100), false)
		draw_rect(Rect2(0, 0, 100, 100), Color(1, 1, 1, 0.15), false, 1.0)
		return
	var skin: Color = _col(SKIN, "skin")
	var hair: Color = _col(HAIR_COLORS, "hair_color")
	var shirt: Color = _col(SHIRTS, "shirt")
	var dark_skin: Color = skin.darkened(0.25)
	draw_rect(Rect2(0, 0, 100, 100), _col(BGS, "bg"))
	var style: int = _g("hair")
	# за головой
	if style == 7:
		draw_colored_polygon(_ellipse(Vector2(50, 46), 33, 37), shirt.darkened(0.15))
	if style == 3:
		draw_colored_polygon(_ellipse(Vector2(50, 50), 29, 34), hair)
		draw_rect(Rect2(21, 50, 58, 30), hair)
	# тело
	draw_colored_polygon(_ellipse(Vector2(50, 116), 42, 38), shirt)
	draw_rect(Rect2(43, 64, 14, 16), dark_skin)
	if style == 7:
		draw_colored_polygon(_ellipse(Vector2(50, 80), 18, 6, 0.0, PI), shirt.darkened(0.3))
	# голова
	draw_circle(Vector2(26, 49), 5, skin)
	draw_circle(Vector2(74, 49), 5, skin)
	draw_colored_polygon(_ellipse(Vector2(50, 46), 24, 28), skin)
	# глаза
	for x in [41.0, 59.0]:
		draw_circle(Vector2(x, 47), 4.2, Color.WHITE)
		draw_circle(Vector2(x, 47.3), 2.4, _col(EYE_COLORS, "eyes"))
		draw_circle(Vector2(x, 47.3), 1.1, Color.BLACK)
	# брови
	draw_line(Vector2(36, 40), Vector2(45, 39), hair.darkened(0.1), 2.0)
	draw_line(Vector2(55, 39), Vector2(64, 40), hair.darkened(0.1), 2.0)
	# нос и рот
	draw_polyline(PackedVector2Array([Vector2(50, 49), Vector2(48, 57), Vector2(51.5, 58)]), dark_skin, 1.6)
	draw_arc(Vector2(50, 59), 6.5, 0.35, PI - 0.35, 12, Color("8b3a3a"), 2.0)
	# борода
	match _g("beard"):
		1:
			draw_colored_polygon(_ellipse(Vector2(50, 54), 23, 19, 0.15, PI - 0.15), Color(hair.r, hair.g, hair.b, 0.35))
		2:
			var b := _ellipse(Vector2(50, 54), 24, 21, 0.05, PI - 0.05)
			draw_colored_polygon(b, hair)
			draw_arc(Vector2(50, 60), 5.5, 0.3, PI - 0.3, 10, Color("8b3a3a"), 2.0)
		3:
			draw_colored_polygon(PackedVector2Array([Vector2(41, 58), Vector2(59, 58), Vector2(57, 55), Vector2(43, 55)]), hair)
		4:
			draw_colored_polygon(PackedVector2Array([Vector2(44, 56), Vector2(56, 56), Vector2(54, 54.5), Vector2(46, 54.5)]), hair)
			draw_colored_polygon(_ellipse(Vector2(50, 69), 5, 5), hair)
	# причёска сверху
	match style:
		1:
			draw_colored_polygon(_ellipse(Vector2(50, 32), 25, 14, PI, TAU), hair)
			draw_colored_polygon(PackedVector2Array([Vector2(25, 33), Vector2(75, 33), Vector2(70, 38), Vector2(30, 38)]), hair)
		2:
			draw_colored_polygon(_ellipse(Vector2(50, 33), 24, 12, PI, TAU), Color(hair.r, hair.g, hair.b, 0.75))
		3:
			draw_colored_polygon(_ellipse(Vector2(50, 33), 26, 16, PI, TAU), hair)
			draw_rect(Rect2(24, 31, 52, 6), hair)
		4:
			draw_colored_polygon(_ellipse(Vector2(50, 30), 6, 22, PI, TAU), hair)
			draw_rect(Rect2(44, 22, 12, 12), hair)
		5:
			for p in [Vector2(30, 32), Vector2(38, 25), Vector2(47, 22), Vector2(56, 22), Vector2(65, 25), Vector2(71, 32), Vector2(27, 40), Vector2(73, 40)]:
				draw_circle(p, 8, hair)
		6:
			draw_colored_polygon(_ellipse(Vector2(50, 32), 26, 17, PI, TAU), shirt.darkened(0.2))
			draw_colored_polygon(PackedVector2Array([Vector2(28, 32), Vector2(80, 32), Vector2(84, 36), Vector2(28, 36)]), shirt.darkened(0.4))
		7:
			draw_arc(Vector2(50, 46), 30, PI + 0.2, TAU - 0.2, 20, shirt.darkened(0.15), 8.0)
	# очки
	match _g("glasses"):
		1:
			for x in [41.0, 59.0]:
				draw_arc(Vector2(x, 47), 6.5, 0, TAU, 20, Color("222222"), 1.6)
			draw_line(Vector2(47.5, 47), Vector2(52.5, 47), Color("222222"), 1.6)
		2:
			for x in [41.0, 59.0]:
				draw_rect(Rect2(x - 7, 42, 14, 10), Color("222222"), false, 1.8)
			draw_line(Vector2(48, 46), Vector2(52, 46), Color("222222"), 1.6)
		3:
			for x in [41.0, 59.0]:
				draw_rect(Rect2(x - 7, 42, 14, 9), Color(0.05, 0.05, 0.08, 0.92))
			draw_line(Vector2(48, 45), Vector2(52, 45), Color("111111"), 1.8)
	# аксессуары
	match _g("extra"):
		1:
			draw_arc(Vector2(50, 46), 28, PI + 0.15, TAU - 0.15, 22, Color("2b2b2b"), 3.5)
			draw_rect(Rect2(19, 41, 8, 15), Color("2b2b2b"))
			draw_rect(Rect2(73, 41, 8, 15), Color("2b2b2b"))
			draw_polyline(PackedVector2Array([Vector2(23, 55), Vector2(28, 64), Vector2(38, 63)]), Color("2b2b2b"), 1.8)
			draw_circle(Vector2(39, 63), 1.8, Color("ffb23e"))
		2:
			draw_circle(Vector2(26, 55), 1.8, Color("f1c40f"))
		3:
			draw_line(Vector2(60, 38), Vector2(56, 55), Color("b05050"), 1.6)
