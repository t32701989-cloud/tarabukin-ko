extends Control
## Экран матча: вид сверху на карту, 10 игроков-точек с лицами, лента убийств, карточки команд.

signal round_done

const Layouts := preload("res://scripts/map_layouts.gd")
const T_COL := Color("ff9a3c")
const CT_COL := Color("4aa3ff")
const SIDE_W := 170.0

var layout: Dictionary = {}
var teams: Array = [[], []]          # [{nick, photo}] x5
var tex_cache: Dictionary = {}
var side_atk: int = 0                # какая команда сейчас T
var pos: Array = [[], []]            # Vector2 в координатах карты 1000x700
var alive: Array = [[], []]
var hp: Array = [[], []]
var paths: Array = [[], []]
var feed: Array = []                 # {text_k, text_v, ck, cv, hs, t}
var bomb: Vector2 = Vector2(-1, -1)
var bomb_state: String = ""          # "", "planted", "defused", "exploded"
var anim_t: float = 0.0
var anim_d: float = 0.0
var events: Array = []
var ev_i: int = 0
var plant_t: float = -1.0
var result: Dictionary = {}
var playing: bool = false
var buildings: Array = []
var trees: Array = []
var font: Font

func setup(map_name: String, team_a: Array, team_b: Array, atk: int) -> void:
	layout = Layouts.get_layout(map_name)
	teams = [team_a, team_b]
	side_atk = atk
	font = get_theme_default_font()
	_gen_city(map_name)
	reset_round()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _tex(path: String) -> Texture2D:
	if path == "":
		return null
	if tex_cache.has(path):
		return tex_cache[path]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	tex_cache[path] = t
	return t

func _node(id: String) -> Vector2:
	var p: Array = layout["nodes"].get(id, [500, 350])
	return Vector2(p[0], p[1])

func _team_of_side(t_side: bool) -> int:
	return side_atk if t_side else 1 - side_atk

## Кварталы и деревья генерируются один раз на карту (детерминированно).
func _gen_city(map_name: String) -> void:
	buildings = []
	trees = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name)
	var segs: Array = []
	for e in layout["edges"]:
		segs.append([_node(e[0]), _node(e[1])])
	for gy in range(10, 700, 34):
		for gx in range(10, 1000, 34):
			var c := Vector2(gx + rng.randf_range(-6, 6), gy + rng.randf_range(-6, 6))
			var near: float = 9999.0
			for sg in segs:
				near = minf(near, Geometry2D.get_closest_point_to_segment(c, sg[0], sg[1]).distance_to(c))
			for id in layout["nodes"]:
				near = minf(near, _node(id).distance_to(c) - 18.0)
			if near > 42.0:
				if rng.randf() < 0.82:
					var w: float = rng.randf_range(22, 34)
					var h: float = rng.randf_range(22, 34)
					buildings.append({"r": Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), "c": rng.randi() % 4, "d": rng.randi() % 3})
			elif near > 26.0 and rng.randf() < 0.18:
				trees.append(c)

func reset_round() -> void:
	for t in 2:
		pos[t] = []
		alive[t] = []
		hp[t] = []
		paths[t] = []
		var spawn: Vector2 = _node("T" if t == side_atk else "CT")
		for i in 5:
			var p: Vector2 = spawn + Vector2(cos(i * 1.256) * 16, sin(i * 1.256) * 16)
			pos[t].append(p)
			alive[t].append(true)
			hp[t].append(100)
			paths[t].append([p])
	bomb_state = ""
	bomb = Vector2(-1, -1)
	queue_redraw()

func _route_pts(ids: Array, jitter: float, rng: RandomNumberGenerator) -> Array:
	var pts: Array = []
	for id in ids:
		pts.append(_node(id) + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter)))
	return pts

## Запуск анимации раунда по результату симуляции.
func play_round(r: Dictionary, atk: int, duration: float) -> void:
	side_atk = atk
	reset_round()
	result = r
	events = r.get("events", [])
	ev_i = 0
	anim_t = 0.0
	anim_d = maxf(0.5, duration)
	playing = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var site: String = str(r.get("site", "A"))
	var t_team: int = side_atk
	var ct_team: int = 1 - side_atk
	var routes: Array = layout["t_routes"][site]
	for i in 5:
		var rt: Array = routes[0] if i < 3 else routes[1]
		paths[t_team][i] = _route_pts(rt, 14.0, rng)
		var hold: Array = layout["ct_hold"][i]
		var hp2: Array = hold.duplicate()
		paths[ct_team][i] = _route_pts(hp2, 12.0, rng)
	plant_t = 0.62 if bool(r.get("planted", false)) else -1.0
	# время событий
	var n: int = events.size()
	for k in n:
		events[k]["at"] = lerpf(0.3, 0.93, float(k + 1) / float(n + 1)) + rng.randf_range(-0.03, 0.03)
	set_process(true)

func _pos_on_path(pts: Array, f: float) -> Vector2:
	if pts.size() == 1:
		return pts[0]
	var total: float = 0.0
	for i in pts.size() - 1:
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	var d: float = total * clampf(f, 0.0, 1.0)
	for i in pts.size() - 1:
		var seg: float = (pts[i] as Vector2).distance_to(pts[i + 1])
		if d <= seg:
			return (pts[i] as Vector2).lerp(pts[i + 1], d / maxf(seg, 0.001))
		d -= seg
	return pts[pts.size() - 1]

func _process(delta: float) -> void:
	if not playing:
		set_process(false)
		return
	anim_t += delta
	var f: float = anim_t / anim_d
	for t in 2:
		for i in 5:
			if alive[t][i]:
				var spd: float = (0.6 if t == side_atk else 0.35) * (1.0 + 0.12 * (i % 3))
				var prog: float = f / spd
				pos[t][i] = _pos_on_path(paths[t][i], prog) + Vector2(cos(i * 2.1) * 14.0, sin(i * 2.1) * 14.0) * clampf(prog, 0.0, 1.0)
	if plant_t > 0.0 and bomb_state == "" and f >= plant_t:
		bomb_state = "planted"
		bomb = _node(str(result.get("site", "A"))) + Vector2(8, 6)
	while ev_i < events.size() and f >= float(events[ev_i]["at"]):
		var e: Dictionary = events[ev_i]
		alive[e["vt"]][e["v"]] = false
		hp[e["vt"]][e["v"]] = 0
		hp[e["kt"]][e["k"]] = maxi(1, hp[e["kt"]][e["k"]] - randi_range(0, 60))
		feed.push_front({"k": teams[e["kt"]][e["k"]]["nick"], "v": teams[e["vt"]][e["v"]]["nick"], "ck": e["kt"], "cv": e["vt"], "hs": e["hs"], "t": 0.0})
		while feed.size() > 5:
			feed.pop_back()
		ev_i += 1
	if f >= 1.0:
		if bomb_state == "planted":
			bomb_state = "defused" if bool(result.get("defuse", false)) else ("exploded" if int(result.get("winner", 0)) == side_atk else "defused")
		playing = false
		round_done.emit()
	queue_redraw()

# ------------------------------------------------------------ отрисовка

func _map_rect() -> Rect2:
	var avail := Rect2(SIDE_W + 6, 0, size.x - SIDE_W * 2 - 12, size.y)
	var k: float = minf(avail.size.x / 1000.0, avail.size.y / 700.0)
	var sz := Vector2(1000, 700) * k
	return Rect2(avail.position + (avail.size - sz) * 0.5, sz)

func _to_screen(p: Vector2, mr: Rect2) -> Vector2:
	return mr.position + p * (mr.size.x / 1000.0)

func _draw() -> void:
	if layout.is_empty():
		return
	var th: Dictionary = layout["theme"]
	draw_rect(Rect2(Vector2.ZERO, size), Color(th["ground"]).darkened(0.35))
	var mr := _map_rect()
	var k: float = mr.size.x / 1000.0
	draw_rect(mr, Color(th["ground"]))
	# улицы
	for e in layout["edges"]:
		draw_line(_to_screen(_node(e[0]), mr), _to_screen(_node(e[1]), mr), Color(th["street"]), 40.0 * k, true)
	for id in layout["nodes"]:
		draw_circle(_to_screen(_node(id), mr), 30.0 * k, Color(th["street"]))
	# здания с тенью и деталями крыши
	for b in buildings:
		var r: Rect2 = b["r"]
		var sr := Rect2(_to_screen(r.position, mr), r.size * k)
		draw_rect(Rect2(sr.position + Vector2(3, 4) * k, sr.size), Color(0, 0, 0, 0.18))
		var rc: Color = Color(th["roof"][int(b["c"])])
		draw_rect(sr, rc)
		draw_rect(sr.grow(-3 * k), rc.lightened(0.08))
		if int(b["d"]) == 1:
			draw_line(sr.position + Vector2(sr.size.x * 0.5, 2), sr.position + Vector2(sr.size.x * 0.5, sr.size.y - 2), rc.darkened(0.2), 1.5)
		elif int(b["d"]) == 2:
			draw_rect(Rect2(sr.position + sr.size * 0.3, sr.size * 0.4), rc.darkened(0.15))
	if bool(th.get("tree", false)):
		for tp in trees:
			var sp: Vector2 = _to_screen(tp, mr)
			draw_circle(sp + Vector2(2, 3) * k, 9 * k, Color(0, 0, 0, 0.15))
			draw_circle(sp, 9 * k, Color(th["accent"]))
			draw_circle(sp - Vector2(2, 2) * k, 5 * k, Color(th["accent"]).lightened(0.2))
	# спавны и точки
	for sp_id in [["T", T_COL], ["CT", CT_COL]]:
		var c: Vector2 = _to_screen(_node(sp_id[0]), mr)
		draw_rect(Rect2(c - Vector2(34, 34) * k, Vector2(68, 68) * k), Color(sp_id[1].r, sp_id[1].g, sp_id[1].b, 0.25))
	for site in ["A", "B"]:
		var c2: Vector2 = _to_screen(_node(site), mr)
		draw_rect(Rect2(c2 - Vector2(30, 30) * k, Vector2(60, 60) * k), Color(0.85, 0.15, 0.12, 0.85))
		draw_string(font, c2 + Vector2(-9, 10) * k, site, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k), Color.WHITE)
	# подписи зон
	for id in layout["names"]:
		var c3: Vector2 = _to_screen(_node(id), mr) + Vector2(0, -36 * k)
		var t: String = tr(str(layout["names"][id])).to_upper()
		var fs: int = maxi(9, int(12 * k))
		var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c3 + Vector2(-w * 0.5 + 1, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.55))
		draw_string(font, c3 + Vector2(-w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# бомба
	if bomb_state != "":
		var bp: Vector2 = _to_screen(bomb, mr)
		var bc: Color = Color("ff3b30") if bomb_state == "planted" else (Color("ffcc00") if bomb_state == "exploded" else Color("4aa3ff"))
		if bomb_state == "exploded":
			draw_circle(bp, 46 * k, Color(1, 0.6, 0.1, 0.35))
		draw_rect(Rect2(bp - Vector2(8, 6) * k, Vector2(16, 12) * k), bc)
	# игроки
	for t in 2:
		var col: Color = T_COL if t == side_atk else CT_COL
		for i in 5:
			var p: Vector2 = _to_screen(pos[t][i], mr)
			if not alive[t][i]:
				draw_line(p - Vector2(7, 7), p + Vector2(7, 7), Color(0.2, 0.2, 0.2, 0.8), 3)
				draw_line(p - Vector2(7, -7), p + Vector2(7, -7), Color(0.2, 0.2, 0.2, 0.8), 3)
				continue
			_face(p, 15.0, teams[t][i].get("photo", ""), col)
			var nick: String = str(teams[t][i]["nick"])
			var w2: float = font.get_string_size(nick, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, p + Vector2(-w2 * 0.5 + 1, 29), nick, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.7))
			draw_string(font, p + Vector2(-w2 * 0.5, 28), nick, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	_draw_side(0, Rect2(0, 0, SIDE_W, size.y))
	_draw_side(1, Rect2(size.x - SIDE_W, 0, SIDE_W, size.y))
	_draw_feed()

func _face(c: Vector2, r: float, photo: String, ring: Color) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 32:
		var a: float = TAU * i / 32.0
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.45) + d * 0.45)
	draw_colored_polygon(pts, Color("2a303c"))
	var tx: Texture2D = _tex(photo)
	if tx != null:
		draw_colored_polygon(pts, Color.WHITE, uvs, tx)
	draw_arc(c, r, 0, TAU, 32, ring, 3.0, true)

func _draw_side(t: int, area: Rect2) -> void:
	var col: Color = T_COL if t == side_atk else CT_COL
	var row_h: float = minf(64.0, (area.size.y - 20) / 5.0)
	for i in 5:
		var r := Rect2(area.position + Vector2(4, 10 + i * row_h), Vector2(area.size.x - 8, row_h - 6))
		var a: bool = alive[t][i]
		draw_rect(r, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.92 if a else 0.5))
		draw_rect(Rect2(r.position, Vector2(4, r.size.y)), col)
		_face(r.position + Vector2(26, r.size.y * 0.5), minf(20.0, r.size.y * 0.38), teams[t][i].get("photo", ""), col if a else Color(0.4, 0.4, 0.4))
		draw_string(font, r.position + Vector2(52, 20), str(teams[t][i]["nick"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56, 13, Color.WHITE if a else Color(1, 1, 1, 0.4))
		var h: int = hp[t][i]
		var bar := Rect2(r.position + Vector2(52, r.size.y - 16), Vector2(r.size.x - 60, 6))
		draw_rect(bar, Color(0, 0, 0, 0.4))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * h / 100.0, bar.size.y)), Color("7dd66b") if h > 50 else (Color("ffb23e") if h > 0 else Color("ff5a3c")))
		draw_string(font, r.position + Vector2(r.size.x - 30, 20), str(h), HORIZONTAL_ALIGNMENT_RIGHT, 26, 12, Color.WHITE if a else Color(1, 1, 1, 0.4))

func _draw_feed() -> void:
	var x2: float = size.x - SIDE_W - 14
	var y: float = 10.0
	for e in feed:
		var kc: Color = T_COL if e["ck"] == side_atk else CT_COL
		var vc: Color = T_COL if e["cv"] == side_atk else CT_COL
		var ks: String = str(e["k"])
		var vs: String = str(e["v"])
		var kw: float = font.get_string_size(ks, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var vw: float = font.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var iw: float = 46.0 if e["hs"] else 26.0
		var w: float = kw + vw + iw + 24
		var r := Rect2(x2 - w, y, w, 24)
		draw_rect(r, Color(0, 0, 0, 0.6))
		draw_string(font, r.position + Vector2(8, 17), ks, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, kc)
		var ix: float = r.position.x + 12 + kw
		# значок оружия (силуэт)
		draw_rect(Rect2(ix, y + 10, 18, 4), Color.WHITE)
		draw_rect(Rect2(ix + 3, y + 14, 4, 5), Color.WHITE)
		if e["hs"]:
			# хедшот: кружок с прицелом
			var hc := Vector2(ix + 30, y + 12)
			draw_arc(hc, 7, 0, TAU, 16, Color("ff5a3c"), 2.0, true)
			draw_circle(hc, 2.5, Color("ff5a3c"))
		draw_string(font, Vector2(ix + iw, y + 17), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, vc)
		y += 28
