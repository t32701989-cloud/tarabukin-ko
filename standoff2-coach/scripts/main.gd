extends Control
## Интерфейс игры «Standoff Coach». Все экраны строятся кодом.

const MatchSim := preload("res://scripts/match_sim.gd")

const C_BG := Color("14161b")
const C_PANEL := Color("1f232b")
const C_ACC := Color("ffb23e")
const C_CT := Color("5aa9ff")
const C_GOOD := Color("7dd66b")
const C_BAD := Color("ff6b6b")
const C_DIM := Color("9aa3b2")

var gs: Node
var top_label: Label
var nav_box: VBoxContainer
var content: VBoxContainer
var log_label: RichTextLabel
var current: String = "dashboard"
var m: Dictionary = {}          # состояние матча
var busy: bool = false
var in_match: bool = false

const UITheme := preload("res://scripts/ui_theme.gd")

func _ready() -> void:
	gs = get_node("/root/GameState")
	get_tree().root.theme = UITheme.build()
	var bg := ColorRect.new()
	bg.name = "BG"
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	show_menu()

# ------------------------------------------------------------ помощники UI

func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

func panel(color: Color = C_PANEL, pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p

func label(t: String, size: int = 15, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	if size >= 26:
		l.add_theme_font_override("font", UITheme.heavy())
	elif size >= 16:
		l.add_theme_font_override("font", UITheme.bold())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func btn(t: String, cb: Callable, color: Color = Color.WHITE) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_color_override("font_color", color)
	b.pressed.connect(cb)
	return b

## Компактная кнопка для таблиц.
func small_btn(t: String, cb: Callable, color: Color = Color.WHITE) -> Button:
	var b := btn(t, cb, color)
	b.add_theme_font_size_override("font_size", 12)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var base: StyleBox = get_tree().root.theme.get_stylebox(st, "Button") if get_tree().root.theme else null
		if base is StyleBoxFlat:
			var c: StyleBoxFlat = base.duplicate()
			c.content_margin_left = 8; c.content_margin_right = 8
			c.content_margin_top = 4; c.content_margin_bottom = 4
			b.add_theme_stylebox_override(st, c)
	return b

## Кнопка-иконка (Material Icons) с подсказкой.
func icon_btn(icon: String, tip: String, cb: Callable) -> Button:
	var b := small_btn("", cb)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(30, 28)
	var ic := UITheme.icon(icon, 18)
	b.add_child(ic)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return b

func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func stat_color(v: int) -> Color:
	if v >= 75: return C_GOOD
	if v >= 55: return Color.WHITE
	return C_DIM

func money_fmt(v: int) -> String:
	return ("-" if v < 0 else "") + "$" + str(abs(v))

var _tex_cache: Dictionary = {}

func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if path.begins_with("user://"):
		if FileAccess.file_exists(path):
			var im := Image.load_from_file(path)
			if im != null: t = ImageTexture.create_from_image(im)
	elif ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t

func pic(path: String, sz: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(path)
	r.custom_minimum_size = Vector2(sz, sz)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Портрет игрока: фото, если есть, иначе нарисованное лицо.
var _player_pool: Array = []

## Фото игрока: своё (если есть) или фотореалистичный портрет из набора, закреплённый за ником.
func player_photo(pl: Dictionary) -> String:
	var ph: String = str(pl.get("photo", ""))
	if ph != "":
		return ph
	if _player_pool.is_empty():
		var d := DirAccess.open("res://assets/players")
		if d:
			for f in d.get_files():
				var n: String = f.trim_suffix(".import")
				if (n.ends_with(".png") or n.ends_with(".jpg")) and not _player_pool.has("res://assets/players/" + n):
					_player_pool.append("res://assets/players/" + n)
			_player_pool.sort()
	if _player_pool.is_empty():
		return ""
	return _player_pool[abs(hash(str(pl.get("nick", "")))) % _player_pool.size()]

func portrait(pl: Dictionary, sz: int) -> Control:
	return _circle(player_photo(pl), sz, Color(1, 1, 1, 0.5))

func cell(t: String, w: int, color: Color = Color.WHITE, size: int = 14) -> Label:
	var l := label(t, size, color)
	l.custom_minimum_size = Vector2(w, 0)
	return l

# ------------------------------------------------------------ главное меню

const VERSION := "v0.3"
const Avatar := preload("res://scripts/avatar.gd")
const Teams := preload("res://scripts/teams.gd")
const TMP_PHOTO := "user://coach_photo_new.png"
var photo_tex: Texture2D = null
var cr: Dictionary = {}            # данные мастера создания карьеры
var cr_photo: Texture2D = null
var cr_slot: int = -1

func make_avatar(cfg: Dictionary, sz: int, tex: Texture2D = null) -> Control:
	var a = Avatar.new()
	a.custom_minimum_size = Vector2(sz, sz)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.set_cfg(cfg)
	if tex != null:
		a.set_photo(tex)
	return a

func wrap_label(t: String, size: int, color: Color, w: int) -> Label:
	var l := label(t, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w, 0)
	return l

# ------------------------------------------------------------ мастер: менеджер

func _wizard_root(step: String) -> VBoxContainer:
	_clear_root()
	var root := vbox(14)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 36; root.offset_top = 24; root.offset_right = -36; root.offset_bottom = -20
	add_child(root)
	var h := hbox(14)
	h.add_child(label(tr("НОВАЯ КАРЬЕРА"), 28, C_ACC))
	h.add_child(label(step, 18, C_DIM))
	h.get_child(1).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(h)
	return root

const MONTHS := ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]

func _cr_random_attrs() -> Dictionary:
	var a := {}
	for p in Teams.ATTR_PAIRS:
		a[p[0]] = 0
		a[p[2]] = 0
	var keys: Array = a.keys()
	var left: int = Teams.ATTR_POOL
	while left > 0:
		var k: String = keys[randi() % keys.size()]
		if int(a[k]) < Teams.ATTR_MAX:
			a[k] = int(a[k]) + 1
			left -= 1
	return a

func _cr_points_left() -> int:
	var s: int = 0
	for k in cr["attrs"]:
		s += int(cr["attrs"][k])
	return Teams.ATTR_POOL - s

func _cr_random_identity() -> void:
	var g: String = "m" if randf() < 0.5 else "f"
	cr["gender"] = g
	cr["name"] = (Teams.FIRST_M if g == "m" else Teams.FIRST_F)[randi() % 10]
	var ln: String = Teams.LAST[randi() % Teams.LAST.size()]
	if g == "f" and (ln.ends_with("ов") or ln.ends_with("ев") or ln.ends_with("ёв") or ln.ends_with("ин")):
		ln += "а"
	cr["last"] = ln
	cr["nick"] = Teams.NICKS[randi() % Teams.NICKS.size()]
	cr["country"] = Teams.COUNTRY_LIST[randi() % 6][0]
	cr["day"] = randi_range(1, 28)
	cr["month"] = randi_range(1, 12)
	cr["year"] = randi_range(1975, 2000)
	_cr_random_portrait()

func _cr_random_portrait() -> void:
	var pool: Array = Teams.MANAGER_PORTRAITS.filter(func(x): return x["gender"] == cr["gender"])
	if pool.is_empty():
		pool = Teams.MANAGER_PORTRAITS
	cr["portrait"] = pool[randi() % pool.size()]["file"]
	cr_photo = null
	cr["photo"] = ""

func _cr_age() -> int:
	var now := Time.get_date_dict_from_system()
	var age: int = int(now["year"]) - int(cr["year"])
	if int(now["month"]) < int(cr["month"]) or (int(now["month"]) == int(cr["month"]) and int(now["day"]) < int(cr["day"])):
		age -= 1
	return age

func _cr_country_name() -> String:
	for c in Teams.COUNTRY_LIST:
		if c[0] == cr["country"]:
			return c[1]
	return "Другая"

func _cr_portrait_tex() -> Texture2D:
	if cr_photo != null:
		return cr_photo
	return tex(str(cr.get("portrait", "")))

func _blue_btn(t: String, cb: Callable, size: int = 15) -> Button:
	return _outline_btn(t, cb, Color("2fb8e8"), size)

func show_creator() -> void:
	if cr.is_empty():
		cr = {"attrs": _cr_random_attrs(), "err": ""}
		_cr_random_identity()
	_clear_root()
	_photo_bg("res://assets/ui/arena_bg.jpg", 0.3)

	# ---- галерея справа
	var gal := panel(Color(0.07, 0.08, 0.1, 0.96), 12)
	gal.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	gal.offset_left = -300
	add_child(gal)
	var gsc := ScrollContainer.new()
	gsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gal.add_child(gsc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	gsc.add_child(grid)
	for mp in Teams.MANAGER_PORTRAITS:
		var file: String = mp["file"]
		var sel: bool = cr_photo == null and str(cr.get("portrait", "")) == file
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("232833")
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = Color("2fb8e8") if sel else Color("232833")
		sb.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", sb)
		var cv := vbox(2)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(pic(file, 120))
		var nl := label(tr(mp["name"]), 16, Color.WHITE)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nl)
		card.add_child(cv)
		var hit := Button.new()
		hit.flat = true
		for st in ["normal", "hover", "pressed", "focus"]:
			hit.add_theme_stylebox_override(st, _flat_style())
		hit.mouse_entered.connect(func(): sb.bg_color = Color("2c3442"))
		hit.mouse_exited.connect(func(): sb.bg_color = Color("232833"))
		var g: String = mp["gender"]
		var nm: String = mp["name"]
		hit.pressed.connect(func():
			cr["portrait"] = file; cr["gender"] = g; cr["name"] = tr(nm); cr_photo = null; cr["photo"] = ""; show_creator())
		card.add_child(hit)
		grid.add_child(card)

	# ---- центральная часть
	var main_area := Control.new()
	main_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_area.offset_right = -300
	add_child(main_area)
	var ttl := label(tr("СОЗДАТЬ МЕНЕДЖЕРА"), 34, Color.WHITE)
	ttl.position = Vector2(400, 28)
	main_area.add_child(ttl)

	# качества (слева)
	var ap := panel(Color(0.09, 0.1, 0.13, 0.95), 14)
	ap.position = Vector2(24, 96)
	ap.custom_minimum_size = Vector2(372, 0)
	main_area.add_child(ap)
	var av := vbox(4)
	ap.add_child(av)
	for pair in Teams.ATTR_PAIRS:
		var lk: String = pair[0]
		var rk: String = pair[2]
		var names := hbox(0)
		names.add_child(label(tr(pair[1]).to_upper(), 11, Color("d6dbe3")))
		names.add_child(spacer())
		names.add_child(label(tr(pair[3]).to_upper(), 11, Color("d6dbe3")))
		av.add_child(names)
		var row := hbox(2)
		var ls := HSlider.new()
		ls.min_value = 0
		ls.max_value = Teams.ATTR_MAX
		ls.value = Teams.ATTR_MAX - int(cr["attrs"][lk])
		ls.custom_minimum_size = Vector2(150, 18)
		var rs := HSlider.new()
		rs.min_value = 0
		rs.max_value = Teams.ATTR_MAX
		rs.value = int(cr["attrs"][rk])
		rs.custom_minimum_size = Vector2(150, 18)
		var lv := cell(str(int(cr["attrs"][lk])), 24, C_GOOD, 13)
		var rv2 := cell(str(int(cr["attrs"][rk])), 24, C_GOOD, 13)
		rv2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ls.value_changed.connect(func(v): _cr_set_attr(lk, Teams.ATTR_MAX - int(v), ls, true))
		rs.value_changed.connect(func(v): _cr_set_attr(rk, int(v), rs, false))
		row.add_child(lv)
		row.add_child(ls)
		row.add_child(rs)
		row.add_child(rv2)
		av.add_child(row)
	var abot := hbox(8)
	abot.add_child(_blue_btn(tr("СЛУЧАЙНО"), func(): cr["attrs"] = _cr_random_attrs(); show_creator(), 13))
	abot.add_child(spacer())
	abot.add_child(label(tr("ОСТАЛОСЬ ОЧКОВ:"), 13, Color.WHITE))
	abot.add_child(label(str(_cr_points_left()), 18, C_GOOD if _cr_points_left() == 0 else C_ACC))
	av.add_child(abot)
	av.add_child(wrap_label(tr("Тактика и видение игры усиливают команду, мотивация и лидерство — форму игроков, скаутинг — трансферы, фин. грамотность — бюджет, имидж — репутацию."), 11, C_DIM, 340))

	# анкета (центр)
	var fp := panel(Color(0.09, 0.1, 0.13, 0.95), 16)
	fp.position = Vector2(410, 96)
	fp.custom_minimum_size = Vector2(560, 400)
	main_area.add_child(fp)
	var fh := hbox(10)
	fp.add_child(fh)
	var fv := vbox(4)
	fv.custom_minimum_size = Vector2(250, 0)
	fh.add_child(fv)
	var r1 := hbox(8)
	r1.add_child(_cr_field(tr("НИК") + " *", "nick", 110))
	r1.add_child(_cr_field(tr("ИМЯ") + " *", "name", 130))
	fv.add_child(r1)
	fv.add_child(_cr_field(tr("ФАМИЛИЯ") + " *", "last", 250))
	fv.add_child(label(tr("ПОЛ") + " *", 12, C_DIM))
	var gr := hbox(16)
	for gv in [["m", tr("М")], ["f", tr("Ж")]]:
		var cb := CheckBox.new()
		cb.text = gv[1]
		cb.button_pressed = cr["gender"] == gv[0]
		var gk: String = gv[0]
		cb.pressed.connect(func():
			if cr["gender"] != gk:
				cr["gender"] = gk
				if cr_photo == null: _cr_random_portrait()
				show_creator()
			else:
				cb.button_pressed = true)
		gr.add_child(cb)
	fv.add_child(gr)
	fv.add_child(label(tr("СТРАНА") + " *", 12, C_DIM))
	var co := OptionButton.new()
	for i in Teams.COUNTRY_LIST.size():
		var c: Array = Teams.COUNTRY_LIST[i]
		var ft: Texture2D = tex("res://assets/flags/%s.png" % c[0])
		if ft != null:
			co.add_icon_item(ft, tr(c[1]))
		else:
			co.add_item(tr(c[1]))
		if c[0] == cr["country"]:
			co.selected = i
	co.item_selected.connect(func(i): cr["country"] = Teams.COUNTRY_LIST[i][0])
	fv.add_child(co)
	fv.add_child(label(tr("ДАТА РОЖДЕНИЯ") + " *", 12, C_DIM))
	var dr := hbox(6)
	var dd := OptionButton.new()
	for d in range(1, 32):
		dd.add_item(str(d))
	dd.selected = int(cr["day"]) - 1
	dd.item_selected.connect(func(i): cr["day"] = i + 1)
	dr.add_child(dd)
	var mm := OptionButton.new()
	for mo in MONTHS:
		mm.add_item(tr(mo))
	mm.selected = int(cr["month"]) - 1
	mm.item_selected.connect(func(i): cr["month"] = i + 1)
	dr.add_child(mm)
	var yy := OptionButton.new()
	var years: Array = range(2005, 1959, -1)
	for y in years:
		yy.add_item(str(y))
	yy.selected = maxi(0, years.find(int(cr["year"])))
	yy.item_selected.connect(func(i): cr["year"] = years[i])
	dr.add_child(yy)
	fv.add_child(dr)
	if str(cr.get("err", "")) != "":
		fv.add_child(label(cr["err"], 12, C_BAD))
	# портрет
	var pv := vbox(6)
	fh.add_child(pv)
	var pb := hbox(6)
	pb.add_child(spacer())
	pb.add_child(_blue_btn(tr("ЗАГРУЗИТЬ"), func(): open_photo_dialog(), 12))
	pv.add_child(pb)
	var portrait := TextureRect.new()
	portrait.texture = _cr_portrait_tex()
	portrait.custom_minimum_size = Vector2(270, 270)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv.add_child(portrait)
	var pb2 := hbox(6)
	pb2.add_child(spacer())
	pb2.add_child(_blue_btn(tr("СЛУЧАЙНО"), func(): _cr_random_portrait(); show_creator(), 12))
	pv.add_child(pb2)

	# нижние кнопки
	var bb := hbox(14)
	bb.position = Vector2(470, 520)
	bb.add_child(_blue_btn(tr("РАНДОМИЗИРОВАТЬ ВСЁ"), func():
		cr["attrs"] = _cr_random_attrs(); _cr_random_identity(); show_creator(), 15))
	bb.add_child(_blue_btn(tr("ВЫБРАТЬ МЕНЕДЖЕРА") + "  >", func(): _cr_confirm(), 15))
	main_area.add_child(bb)
	if cr_slot > 0 and gs.read_slot(cr_slot) != null:
		var w := label(tr("Карьера в слоте %d будет заменена") % cr_slot, 13, C_BAD)
		w.position = Vector2(470, 580)
		main_area.add_child(w)
	var back := _outline_btn("<  " + tr("НАЗАД"), func(): cr = {}; show_slots("new"), Color("e0453a"), 16)
	back.position = Vector2(24, 640)
	main_area.add_child(back)

func _cr_field(title: String, key: String, w: int) -> VBoxContainer:
	var v := vbox(2)
	v.add_child(label(title, 12, C_DIM))
	var e := LineEdit.new()
	e.text = str(cr.get(key, ""))
	e.max_length = 20
	e.custom_minimum_size = Vector2(w, 34)
	e.text_changed.connect(func(t): cr[key] = t)
	v.add_child(e)
	return v

func _cr_set_attr(key: String, val: int, slider: HSlider, inverted: bool) -> void:
	var cur: int = int(cr["attrs"][key])
	var left: int = _cr_points_left()
	if val - cur > left:
		val = cur + left
	cr["attrs"][key] = val
	show_creator.call_deferred()

func _cr_confirm() -> void:
	for k in ["nick", "name", "last"]:
		if str(cr.get(k, "")).strip_edges() == "":
			cr["err"] = tr("Заполните ник, имя и фамилию.")
			show_creator()
			return
	cr["err"] = ""
	show_org_choice()

# ------------------------------------------------------------ выбор / создание организации

const TEAM_COLORS := [
	["ffb23e", "Оранжевый"], ["e74c3c", "Красный"], ["ff4fa3", "Розовый"], ["8e44ad", "Фиолетовый"],
	["5aa9ff", "Синий"], ["1abc9c", "Бирюзовый"], ["2ecc71", "Зелёный"], ["f1c40f", "Жёлтый"],
	["ecf0f1", "Белый"], ["95a5a6", "Серый"], ["2c3e50", "Тёмно-синий"], ["111111", "Чёрный"],
]
const INVEST := [
	{"money": 10000, "staff": 0, "name": "СЛОЖНО ($10 000)", "base": 40.0},
	{"money": 100000, "staff": 2, "name": "НОРМАЛЬНО ($100 000)", "base": 43.0},
	{"money": 1000000, "staff": 4, "name": "ЛЕГКО ($1 000 000)", "base": 46.0},
	{"money": 10000000, "staff": 6, "name": "КАЗУАЛЬНО ($10 000 000)", "base": 50.0},
]
const TMP_LOGO := "user://team_logo_new.png"
var org: Dictionary = {}

func _photo_bg(path: String = "res://assets/ui/arena_bg.jpg", shade_a: float = 0.35) -> void:
	var base := ColorRect.new()
	base.color = Color("0e1219")
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(base)
	var bg := TextureRect.new()
	bg.texture = tex(path)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.05, 0.08, shade_a)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

func _dark_bg() -> void:
	_photo_bg()
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.07, 0.09, 0.25)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

func _choice_card(icon: String, title_t: String, desc: String, note: String, col: Color, cb: Callable) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.17, 0.95)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color(col.r, col.g, col.b, 0.25)
	sb.set_content_margin_all(26)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(340, 440)
	var v := vbox(14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var ic := pic(icon, 170)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var t := label(title_t, 22, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(290, 0)
	v.add_child(t)
	var d := wrap_label(desc, 14, Color("c9ced8"), 290)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)
	if note != "":
		var f := Control.new()
		f.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(f)
		var n := label(note, 12, C_DIM)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
	var hit := Button.new()
	hit.flat = true
	for st in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(st, _flat_style())
	hit.mouse_entered.connect(func():
		sb.border_color = col; sb.bg_color = Color(0.15, 0.17, 0.22, 0.97))
	hit.mouse_exited.connect(func():
		sb.border_color = Color(col.r, col.g, col.b, 0.25); sb.bg_color = Color(0.12, 0.13, 0.17, 0.95))
	hit.pressed.connect(cb)
	card.add_child(hit)
	_ignore_mouse(v)
	return card

func show_org_choice() -> void:
	_clear_root()
	_dark_bg()
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var h := hbox(40)
	cc.add_child(h)
	h.add_child(_choice_card("res://assets/ui/ico_cup.png", tr("ВЫБРАТЬ СУЩЕСТВУЮЩУЮ ОРГАНИЗАЦИЮ"),
		tr("Выберите одну из существующих организаций и возглавьте её. Управляйте командой и ведите её к победам."), "",
		Color("8a7dff"), func(): show_team_select()))
	h.add_child(_choice_card("res://assets/ui/ico_pad.png", tr("СОЗДАТЬ ОРГАНИЗАЦИЮ"),
		tr("Создайте свою организацию с уникальным названием и стилем управления. Развивайте её с нуля и ведите к успеху."),
		tr("* ДЛЯ ОПЫТНЫХ ИГРОКОВ"), C_GOOD, func(): org = {}; show_org_creator()))
	var back := _outline_btn("<  " + tr("НАЗАД"), func(): show_creator(), Color("e0453a"), 16)
	back.position = Vector2(24, 650)
	add_child(back)

func _logo_list() -> Array:
	var res: Array = []
	var d := DirAccess.open("res://assets/logos")
	if d:
		for f in d.get_files():
			var n: String = f.trim_suffix(".import")
			if n.ends_with(".png") and not res.has("res://assets/logos/" + n):
				res.append("res://assets/logos/" + n)
	res.sort()
	return res

func show_org_creator() -> void:
	var logos: Array = _logo_list()
	if org.is_empty():
		org = {"country": cr.get("country", "ru"), "color": 0, "tag": "", "name": "", "desc": "", "invest": 1, "fill": true,
			"logo": logos[randi() % logos.size()] if not logos.is_empty() else "", "err": ""}
	_clear_root()
	_dark_bg()
	# галерея логотипов справа
	var gal := panel(Color(0.07, 0.08, 0.1, 0.97), 12)
	gal.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	gal.offset_left = -330
	add_child(gal)
	var gsc := ScrollContainer.new()
	gsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gal.add_child(gsc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	gsc.add_child(grid)
	for lp in logos:
		var file: String = lp
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("1b1f28")
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = Color("2fb8e8") if org["logo"] == file else Color("1b1f28")
		sb.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", sb)
		card.add_child(pic(file, 138))
		var hit := Button.new()
		hit.flat = true
		for st in ["normal", "hover", "pressed", "focus"]:
			hit.add_theme_stylebox_override(st, _flat_style())
		hit.mouse_entered.connect(func(): sb.bg_color = Color("262c38"))
		hit.mouse_exited.connect(func(): sb.bg_color = Color("1b1f28"))
		hit.pressed.connect(func(): org["logo"] = file; show_org_creator())
		card.add_child(hit)
		grid.add_child(card)

	var area := Control.new()
	area.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.offset_right = -330
	add_child(area)
	var ttl := label(tr("СОЗДАТЬ ОРГАНИЗАЦИЮ"), 34, Color.WHITE)
	ttl.position = Vector2(250, 22)
	area.add_child(ttl)
	var fp := panel(Color(0.09, 0.1, 0.13, 0.95), 18)
	fp.position = Vector2(40, 84)
	fp.custom_minimum_size = Vector2(870, 520)
	area.add_child(fp)
	var fh := hbox(24)
	fp.add_child(fh)
	var fv := vbox(6)
	fv.custom_minimum_size = Vector2(500, 0)
	fh.add_child(fv)
	# страна + цвет
	var r1 := hbox(14)
	var cv := vbox(2)
	cv.add_child(label(tr("СТРАНА") + " *", 12, C_DIM))
	var co := OptionButton.new()
	for i in Teams.COUNTRY_LIST.size():
		var c: Array = Teams.COUNTRY_LIST[i]
		var ft: Texture2D = tex("res://assets/flags/%s.png" % c[0])
		if ft != null: co.add_icon_item(ft, tr(c[1]))
		else: co.add_item(tr(c[1]))
		if c[0] == org["country"]: co.selected = i
	co.item_selected.connect(func(i): org["country"] = Teams.COUNTRY_LIST[i][0])
	co.custom_minimum_size = Vector2(230, 0)
	cv.add_child(co)
	r1.add_child(cv)
	var colv := vbox(2)
	colv.add_child(label(tr("ЦВЕТ КОМАНДЫ") + " *", 12, C_DIM))
	var cob := OptionButton.new()
	for i in TEAM_COLORS.size():
		var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		img.fill(Color(TEAM_COLORS[i][0]))
		cob.add_icon_item(ImageTexture.create_from_image(img), tr(TEAM_COLORS[i][1]))
	cob.selected = int(org["color"])
	cob.item_selected.connect(func(i): org["color"] = i; show_org_creator())
	cob.custom_minimum_size = Vector2(220, 0)
	colv.add_child(cob)
	r1.add_child(colv)
	fv.add_child(r1)
	# имена
	var r2 := hbox(14)
	r2.add_child(_org_field(tr("КОРОТКОЕ ИМЯ") + " *", "tag", 140, 5))
	r2.add_child(_org_field(tr("ПОЛНОЕ ИМЯ") + " *", "name", 300, 24))
	fv.add_child(r2)
	fv.add_child(label(tr("ОПИСАНИЕ") + " *", 12, C_DIM))
	var de := TextEdit.new()
	de.text = org["desc"]
	de.placeholder_text = tr("Введите краткое описание здесь")
	de.custom_minimum_size = Vector2(470, 64)
	de.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	de.text_changed.connect(func(): org["desc"] = de.text)
	fv.add_child(de)
	# инвестиции
	fv.add_child(label(tr("НАЧАЛЬНЫЕ ИНВЕСТИЦИИ (СЛОЖНОСТЬ)") + " *", 12, C_DIM))
	for i in INVEST.size():
		var cb := CheckBox.new()
		var inv: Dictionary = INVEST[i]
		cb.text = tr(inv["name"]) + ((("  +  %d " % inv["staff"]) + tr("(ПЕРСОНАЛ)")) if int(inv["staff"]) > 0 else "")
		cb.button_pressed = int(org["invest"]) == i
		var idx: int = i
		cb.pressed.connect(func(): org["invest"] = idx; show_org_creator())
		fv.add_child(cb)
	fv.add_child(label(tr("ЗАПОЛНИТЬ СВОБОДНЫМИ АГЕНТАМИ") + " *", 12, C_DIM))
	var fill := CheckBox.new()
	fill.text = tr("НАЧАТЬ С 5 ИГРОКАМИ")
	fill.button_pressed = bool(org["fill"])
	fill.toggled.connect(func(on): org["fill"] = on)
	fv.add_child(fill)
	if str(org.get("err", "")) != "":
		fv.add_child(label(org["err"], 13, C_BAD))
	# логотип
	var lv := vbox(8)
	fh.add_child(lv)
	lv.add_child(label(tr("ЛОГОТИП КОМАНДЫ") + " *", 12, C_DIM))
	var lbox := PanelContainer.new()
	var lsb := StyleBoxFlat.new()
	var tc := Color(TEAM_COLORS[int(org["color"])][0])
	lsb.bg_color = tc.darkened(0.35)
	lsb.set_corner_radius_all(8)
	lsb.set_content_margin_all(14)
	lbox.add_theme_stylebox_override("panel", lsb)
	var lt := TextureRect.new()
	lt.texture = tex(str(org["logo"]))
	lt.custom_minimum_size = Vector2(270, 270)
	lt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lbox.add_child(lt)
	lv.add_child(lbox)
	var lb := hbox(8)
	lb.add_child(_blue_btn(tr("СЛУЧАЙНО"), func():
		if not logos.is_empty(): org["logo"] = logos[randi() % logos.size()]
		show_org_creator(), 12))
	lb.add_child(_blue_btn(tr("ЗАГРУЗИТЬ"), func(): open_logo_dialog(), 12))
	lv.add_child(lb)
	var f2 := Control.new()
	f2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(f2)
	var cr8 := _outline_btn(tr("СОЗДАТЬ") + "  >", func(): _org_create(), C_GOOD, 18)
	cr8.size_flags_horizontal = Control.SIZE_SHRINK_END
	lv.add_child(cr8)
	var back := _outline_btn("<  " + tr("НАЗАД"), func(): show_org_choice(), Color("e0453a"), 16)
	back.position = Vector2(24, 650)
	area.add_child(back)

func _org_field(title_t: String, key: String, w: int, maxlen: int) -> VBoxContainer:
	var v := vbox(2)
	v.add_child(label(title_t, 12, C_DIM))
	var e := LineEdit.new()
	e.text = str(org.get(key, ""))
	e.max_length = maxlen
	e.custom_minimum_size = Vector2(w, 36)
	e.text_changed.connect(func(t): org[key] = t)
	v.add_child(e)
	return v

func open_logo_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray([tr("*.png, *.jpg, *.jpeg, *.webp ; Изображения")])
	fd.use_native_dialog = true
	fd.size = Vector2i(900, 560)
	add_child(fd)
	fd.file_selected.connect(func(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			var s: int = mini(img.get_width(), img.get_height())
			img = img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
			img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
			img.save_png(TMP_LOGO)
			_tex_cache.erase(TMP_LOGO)
			org["logo"] = TMP_LOGO
		show_org_creator()
		fd.queue_free())
	fd.canceled.connect(func(): fd.queue_free())
	fd.popup_centered()

func _org_create() -> void:
	var tag: String = str(org["tag"]).strip_edges().to_upper()
	var nm: String = str(org["name"]).strip_edges()
	if tag == "" or nm == "":
		org["err"] = tr("Заполните короткое и полное имя.")
		show_org_creator()
		return
	var inv: Dictionary = INVEST[int(org["invest"])]
	var desc: String = str(org["desc"]).strip_edges()
	start_career({"name": nm, "tag": tag, "country": str(org["country"]), "color": TEAM_COLORS[int(org["color"])][0], "diff": 2, "base": inv["base"],
		"money": inv["money"], "rep": 5.0, "logo": str(org["logo"]), "desc": desc if desc != "" else tr("Новая организация."),
		"staff": inv["staff"], "empty_roster": not bool(org["fill"]), "custom": true})

func open_photo_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray([tr("*.png, *.jpg, *.jpeg, *.webp ; Изображения")])
	fd.title = tr("Выберите фото менеджера")
	fd.use_native_dialog = true
	fd.size = Vector2i(900, 560)
	add_child(fd)
	fd.file_selected.connect(func(path):
		apply_photo(path)
		fd.queue_free())
	fd.canceled.connect(func(): fd.queue_free())
	fd.popup_centered()

func apply_photo(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		cr["err"] = tr("Не удалось открыть изображение.")
		show_creator()
		return
	var s: int = mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	img.save_png(TMP_PHOTO)
	cr_photo = ImageTexture.create_from_image(img)
	cr["photo"] = TMP_PHOTO
	cr["err"] = ""
	show_creator()

# ------------------------------------------------------------ мастер: команда

var ts_query: String = ""
var ts_country: String = ""
var ts_page: int = 0
var ts_sel: int = 0
const TS_PER_PAGE := 6
const DIFF_TEXT := ["ЛЕГКО", "НОРМАЛЬНО", "СЛОЖНО"]

func _team_stars(t: Dictionary) -> float:
	return clampf((float(t.get("base", 45)) - 34.0) / 5.0 + float(t.get("tier", 0)) * 0.6, 0.5, 5.0)

func _player_stars(p: Dictionary) -> float:
	var o: float = float(gs.ovr(p)) if p.has("attrs") else float(p.get("aim", 50)) * 0.42 + float(p.get("iq", 50)) * 0.3 + float(p.get("tw", 50)) * 0.28
	return clampf((o - 35.0) / 9.0, 0.5, 5.0)

## Детерминированный состав для команд без реального ростера (одинаковый в превью и в игре).
func _preview_roster(t: Dictionary) -> Array:
	if t.has("roster"):
		return t["roster"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(t["name"]))
	var base: float = float(t.get("base", 45))
	var res: Array = []
	var used: Array = []
	var pool: Array = gs.photo_pool().duplicate()
	for r in gs.ROLES:
		var nick := ""
		while nick == "" or used.has(nick):
			if rng.randf() < 0.6:
				nick = gs.NICK_A[rng.randi() % gs.NICK_A.size()] + gs.NICK_B[rng.randi() % gs.NICK_B.size()]
			else:
				nick = gs.NICK_B[rng.randi() % gs.NICK_B.size()].to_lower() + str(rng.randi_range(1, 99))
		used.append(nick)
		var photo := ""
		if not pool.is_empty():
			photo = pool[rng.randi() % pool.size()]
			pool.erase(photo)
		res.append({"nick": nick, "role": r, "aim": int(base + rng.randf_range(-7, 9)), "iq": int(base + rng.randf_range(-9, 7)),
			"tw": int(base + rng.randf_range(-8, 8)), "age": rng.randi_range(17, 26), "photo": photo, "country": t.get("country", "ru")})
	return res

func _ts_filtered() -> Array:
	var res: Array = []
	for i in Teams.START_TEAMS.size():
		var t: Dictionary = Teams.START_TEAMS[i]
		if ts_query != "" and str(t["name"]).to_lower().find(ts_query.to_lower()) < 0 and str(t["tag"]).to_lower().find(ts_query.to_lower()) < 0:
			continue
		if ts_country != "" and str(t.get("country", "")) != ts_country:
			continue
		res.append(i)
	return res

func _flag(code: String, w: int = 24) -> TextureRect:
	var r := pic("res://assets/flags/%s.png" % code, w)
	r.custom_minimum_size = Vector2(w, w * 2 / 3)
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return r

func _stars(v: float, sz: float = 16.0) -> Control:
	return preload("res://scripts/stars.gd").new().setup(v, sz)

func _circle(path: String, sz: float, ring: Color = Color(1, 1, 1, 0.85)) -> Control:
	var t: Texture2D = tex(path) if path != "" else null
	if t == null:
		t = tex("res://assets/ui/silhouette.png")
	return preload("res://scripts/circle_pic.gd").new().setup(t, sz, ring)

func _team_logo_box(t: Dictionary, sz: int) -> Control:
	var lp: String = str(t.get("logo", ""))
	if tex(lp) != null:
		var r := pic(lp, sz)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return r
	return _save_icon({"team_tag": t["tag"], "team_color": t["color"]}, sz)

func show_team_select() -> void:
	_clear_root()
	_dark_bg()
	var idxs: Array = _ts_filtered()
	if not idxs.has(ts_sel) and not idxs.is_empty():
		ts_sel = idxs[0]
	var root := vbox(14)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 28; root.offset_right = -28; root.offset_top = 20; root.offset_bottom = -20
	add_child(root)
	# --- шапка: заголовок, поиск, фильтр
	var top := hbox(14)
	top.add_child(label(tr("ВЫБРАТЬ КОМАНДУ"), 30, Color.WHITE))
	top.add_child(spacer())
	var search := LineEdit.new()
	search.placeholder_text = tr("Поиск команды...")
	search.text = ts_query
	search.custom_minimum_size = Vector2(260, 40)
	search.right_icon = null
	search.text_changed.connect(func(t):
		ts_query = t
		_ts_refresh_later())
	top.add_child(search)
	var cf := OptionButton.new()
	cf.custom_minimum_size = Vector2(200, 40)
	cf.add_item(tr("Все страны"))
	var codes: Array = [""]
	for c in Teams.COUNTRY_LIST:
		var ft: Texture2D = tex("res://assets/flags/%s.png" % c[0])
		if ft != null: cf.add_icon_item(ft, tr(c[1]))
		else: cf.add_item(tr(c[1]))
		codes.append(c[0])
	cf.selected = maxi(0, codes.find(ts_country))
	cf.item_selected.connect(func(i): ts_country = codes[i]; show_team_select())
	top.add_child(cf)
	root.add_child(top)
	# --- плитки команд (только реальные)
	var strip := hbox(12)
	if idxs.is_empty():
		strip.add_child(label(tr("Ничего не найдено."), 16, C_DIM))
	for i in idxs:
		strip.add_child(_ts_tile(int(i)))
	var ssc := ScrollContainer.new()
	ssc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ssc.custom_minimum_size = Vector2(0, 92)
	ssc.add_child(strip)
	root.add_child(ssc)
	# --- карточка выбранной команды на всю оставшуюся высоту
	if not idxs.is_empty():
		var d := _ts_detail(Teams.START_TEAMS[ts_sel])
		d.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(d)
	else:
		var f := Control.new()
		f.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(f)
	var bot := hbox(12)
	bot.add_child(_outline_btn("<  " + tr("НАЗАД"), func(): show_org_choice(), Color("e0453a"), 16))
	bot.add_child(spacer())
	if cr_slot > 0 and gs.read_slot(cr_slot) != null:
		var w := label(tr("Карьера в слоте %d будет заменена") % cr_slot, 13, C_BAD)
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bot.add_child(w)
	if not idxs.is_empty():
		var team: Dictionary = Teams.START_TEAMS[ts_sel]
		bot.add_child(_outline_btn(tr("ПОДПИСАТЬ КОМАНДУ") + "  >", func(): start_career(team), C_GOOD, 18))
	root.add_child(bot)

var _ts_timer: SceneTreeTimer

func _ts_refresh_later() -> void:
	var t := get_tree().create_timer(0.45)
	_ts_timer = t
	await t.timeout
	if _ts_timer == t and top_label == null:
		show_team_select()
		var le := _find_line_edit(self)
		if le != null:
			le.grab_focus()
			le.caret_column = le.text.length()

func _find_line_edit(n: Node) -> LineEdit:
	if n is LineEdit:
		return n
	for c in n.get_children():
		var r := _find_line_edit(c)
		if r != null:
			return r
	return null

func _ts_tile(i: int) -> Control:
	var t: Dictionary = Teams.START_TEAMS[i]
	var sel: bool = i == ts_sel
	var col := Color(t["color"])
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.28) if sel else Color(0.1, 0.12, 0.16, 0.9)
	sb.border_color = col if sel else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(280, 0)
	var h := hbox(12)
	card.add_child(h)
	h.add_child(_team_logo_box(t, 56))
	var v := vbox(2)
	var nr := hbox(8)
	nr.add_child(_flag(str(t.get("country", "xx"))))
	nr.add_child(label(str(t["name"]).to_upper(), 17, Color.WHITE))
	v.add_child(nr)
	var sr := hbox(8)
	sr.add_child(_stars(_team_stars(t), 14))
	if t.has("rankoff"):
		sr.add_child(label("Rankoff %d" % int(t["rankoff"]), 12, Color("f5c518")))
	v.add_child(sr)
	h.add_child(v)
	var hit := Button.new()
	hit.flat = true
	for st in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(st, _flat_style())
	if not sel:
		hit.mouse_entered.connect(func(): sb.border_color = Color(col.r, col.g, col.b, 0.7))
		hit.mouse_exited.connect(func(): sb.border_color = Color(1, 1, 1, 0.08))
	hit.pressed.connect(func(): ts_sel = i; show_team_select())
	card.add_child(hit)
	_ignore_mouse(h)
	return card

func _rankoff_pos(name: String) -> int:
	var arr: Array = []
	for rt in Teams.START_TEAMS:
		if rt.has("rankoff"):
			arr.append([float(rt["rankoff"]), rt["name"]])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	for k in arr.size():
		if arr[k][1] == name:
			return k + 1
	return 0

func _ts_player_card(pl: Dictionary, team_col: Color) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	sb.border_color = Color(team_col.r, team_col.g, team_col.b, 0.45)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 4
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := vbox(0)
	card.add_child(v)
	# фото во весь верх карточки
	var ph := PanelContainer.new()
	var pbs := StyleBoxFlat.new()
	var g1 := Color(team_col.r, team_col.g, team_col.b, 0.35)
	pbs.bg_color = g1
	pbs.corner_radius_top_left = 10; pbs.corner_radius_top_right = 10
	ph.add_theme_stylebox_override("panel", pbs)
	ph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var img := TextureRect.new()
	img.texture = tex(player_photo(pl))
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.custom_minimum_size = Vector2(0, 150)
	img.clip_contents = true
	ph.add_child(img)
	ph.clip_contents = true
	v.add_child(ph)
	var info := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		info.add_theme_constant_override(m, 10)
	info.add_theme_constant_override("margin_top", 8)
	info.add_theme_constant_override("margin_bottom", 10)
	var iv := vbox(2)
	info.add_child(iv)
	var nr := hbox(6)
	nr.add_child(_flag(str(pl.get("country", "xx")), 20))
	var nl := label(str(pl["nick"]), 17, Color.WHITE)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nr.add_child(nl)
	var tmp := pl.duplicate()
	if not tmp.has("attrs"):
		tmp["attrs"] = gs.make_attrs(float(tmp["aim"]), float(tmp["iq"]), float(tmp["tw"]), str(tmp["role"]), str(tmp["nick"]))
	var o: int = gs.ovr(tmp)
	if pl["role"] != "Тренер":
		nr.add_child(label(str(o), 20, stat_color(o)))
	iv.add_child(nr)
	var full: String = ("%s %s" % [tr(str(pl.get("first", ""))), tr(str(pl.get("last", "")))]).strip_edges()
	iv.add_child(label(full if full != "" else " ", 12, C_DIM))
	var rr := hbox(6)
	rr.add_child(label(tr(pl["role"]), 13, Color(team_col).lightened(0.35)))
	rr.add_child(spacer())
	if pl["role"] != "Тренер":
		rr.add_child(_stars(_player_stars(tmp), 12))
	iv.add_child(rr)
	v.add_child(info)
	return card

func _ts_detail(t: Dictionary) -> Control:
	var col := Color(t["color"])
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.075, 0.1, 0.94)
	sb.border_color = Color(col.r, col.g, col.b, 0.5)
	sb.set_border_width_all(1)
	sb.border_width_top = 4
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	var v := vbox(14)
	p.add_child(v)
	# шапка
	var head := hbox(18)
	var lb := PanelContainer.new()
	var ls := StyleBoxFlat.new()
	ls.bg_color = Color(col.r, col.g, col.b, 0.22)
	ls.set_corner_radius_all(10)
	ls.set_content_margin_all(8)
	lb.add_theme_stylebox_override("panel", ls)
	lb.add_child(_team_logo_box(t, 92))
	head.add_child(lb)
	var hv := vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := hbox(10)
	nr.add_child(_flag(str(t.get("country", "xx")), 32))
	nr.add_child(label(str(t["name"]).to_upper(), 30, Color.WHITE))
	hv.add_child(nr)
	hv.add_child(wrap_label(tr(t["desc"]), 14, Color("c9ced8"), 560))
	var chips := hbox(10)
	var d: int = int(t["diff"])
	for c in [[tr("Лига"), tr(gs.TIERS[int(t.get("tier", 0))]), Color.WHITE], [tr("Бюджет"), money_fmt(int(t["money"])), Color("f5c518")],
			[tr("Сложность"), tr(DIFF_TEXT[d]), Color(Teams.DIFF_COLORS[d])], [tr("Rankoff"), ("#%d · %d" % [_rankoff_pos(t["name"]), int(t["rankoff"])]) if t.has("rankoff") else "—", Color("f5c518")]]:
		var chip := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(1, 1, 1, 0.05)
		cs.border_color = Color(1, 1, 1, 0.08)
		cs.set_border_width_all(1)
		cs.set_corner_radius_all(8)
		cs.content_margin_left = 12; cs.content_margin_right = 12; cs.content_margin_top = 6; cs.content_margin_bottom = 6
		chip.add_theme_stylebox_override("panel", cs)
		var cv := vbox(0)
		cv.add_child(label(str(c[0]).to_upper(), 10, C_DIM))
		cv.add_child(label(str(c[1]), 15, c[2]))
		chip.add_child(cv)
		chips.add_child(chip)
	hv.add_child(chips)
	head.add_child(hv)
	var sv := vbox(4)
	sv.add_child(label(tr("Сила команды"), 11, C_DIM))
	var sl := label("%d" % int(t["base"]), 40, stat_color(int(t["base"])))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(sl)
	sv.add_child(_stars(_team_stars(t), 16))
	head.add_child(sv)
	v.add_child(head)
	# состав — крупные карточки, растягиваются на всю ширину и высоту
	var rh := hbox(12)
	rh.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for pl in _preview_roster(t):
		rh.add_child(_ts_player_card(pl, col))
	if t.has("coach"):
		var c: Dictionary = t["coach"]
		var cpl := {"nick": c["name"], "role": "Тренер", "photo": c.get("photo", ""), "country": c.get("country", t.get("country", "ru")), "aim": 60, "iq": 80, "tw": 80}
		var cc := _ts_player_card(cpl, Color("9aa3b2"))
		cc.size_flags_stretch_ratio = 0.85
		rh.add_child(cc)
	v.add_child(rh)
	return p

# ------------------------------------------------------------ договор

var contract_team: Dictionary = {}
var contract_opts := {"fire": true, "country_only": false}

func start_career(team: Dictionary) -> void:
	contract_team = team
	contract_opts = {"fire": true, "country_only": false}
	show_contract()

func show_contract() -> void:
	var t: Dictionary = contract_team
	var custom: bool = bool(t.get("custom", false))
	_clear_root()
	_dark_bg()
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	# тень под листом
	var shadow_wrap := PanelContainer.new()
	var shs := StyleBoxFlat.new()
	shs.bg_color = Color(0, 0, 0, 0)
	shs.shadow_color = Color(0, 0, 0, 0.65)
	shs.shadow_size = 26
	shs.shadow_offset = Vector2(0, 8)
	shadow_wrap.add_theme_stylebox_override("panel", shs)
	cc.add_child(shadow_wrap)
	var paper := PanelContainer.new()
	var sb := StyleBoxTexture.new()
	sb.texture = tex("res://assets/ui/paper.jpg")
	sb.content_margin_left = 46; sb.content_margin_right = 46
	sb.content_margin_top = 30; sb.content_margin_bottom = 24
	paper.add_theme_stylebox_override("panel", sb)
	paper.custom_minimum_size = Vector2(800, 0)
	shadow_wrap.add_child(paper)
	var v := vbox(4)
	paper.add_child(v)
	var ink := Color("23262d")
	var dim := Color("43474f")
	# шапка: логотип + номер документа
	var hh := hbox(14)
	var lp: String = str(t.get("logo", ""))
	if tex(lp) != null:
		hh.add_child(pic(lp, 54))
	var hv := vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h1 := _serif_label(tr("УЧРЕДИТЕЛЬНЫЙ ДОГОВОР") if custom else tr("КОНТРАКТ МЕНЕДЖЕРА КОМАНДЫ"), 24, ink, true)
	hv.add_child(h1)
	var h2 := _serif_label(tr("киберспортивной организации «%s»") % t["name"], 14, dim)
	hv.add_child(h2)
	hh.add_child(hv)
	var num := _serif_label("№ %s-%04d" % [str(t.get("tag", "SO")), abs(hash(str(t["name"]) + str(cr.get("nick", "")))) % 10000], 13, dim)
	num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hh.add_child(num)
	v.add_child(hh)
	for i in 2:
		var rule := ColorRect.new()
		rule.color = Color(0.1, 0.1, 0.12, 0.6 if i == 0 else 0.25)
		rule.custom_minimum_size = Vector2(0, 2 if i == 0 else 1)
		v.add_child(rule)
	var who: String = "%s \"%s\" %s" % [cr.get("name", ""), cr.get("nick", ""), cr.get("last", "")]
	var paras: Array = []
	if custom:
		paras = [
			[tr("Стороны"), tr("%s (далее — «Основатель») учреждает киберспортивную организацию «%s» [%s] (далее — «Клуб») на условиях, изложенных ниже.") % [who, t["name"], t["tag"]]],
			[tr("Задачи Клуба"), tr("Выступление в лигах Standoff 2, развитие игроков и рост репутации организации.")],
			[tr("Полномочия Основателя"), tr("Основатель самостоятельно формирует состав, нанимает персонал, ведёт переговоры со спонсорами и распоряжается бюджетом Клуба.")],
			[tr("Финансы"), tr("Стартовый капитал Клуба составляет %s. Зарплаты игрокам и персоналу выплачиваются еженедельно из бюджета Клуба.") % money_fmt(int(t["money"]))],
		]
	else:
		paras = [
			[tr("Стороны"), tr("Организация «%s» (далее — «Клуб») назначает %s (далее — «Менеджер») на должность главного менеджера команды по Standoff 2.") % [t["name"], who]],
			[tr("Обязанности Менеджера"), tr("Руководить тренировками и тактикой, формировать состав, проводить трансферы и добиваться целей, поставленных советом директоров.")],
			[tr("Цели сезона"), tr("Совет директоров ожидает место не ниже %d в лиге «%s».") % [[4, 6, 8][int(t.get("tier", 0))], tr(gs.TIERS[int(t.get("tier", 0))])]],
			[tr("Финансы"), tr("Менеджер распоряжается бюджетом Клуба в размере %s и отвечает за выплату зарплат игрокам и персоналу.") % money_fmt(int(t["money"]))],
		]
	var n_par: int = 1
	for p in paras:
		v.add_child(_serif_label("%d. %s" % [n_par, p[0]], 15, ink, true))
		var body := _serif_label(p[1], 14, dim)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(700, 0)
		v.add_child(body)
		n_par += 1
	var sep := ColorRect.new()
	sep.color = Color(0, 0, 0, 0.12)
	sep.custom_minimum_size = Vector2(0, 1)
	v.add_child(sep)
	v.add_child(_serif_label(tr("ДОПОЛНИТЕЛЬНЫЕ УСЛОВИЯ"), 14, ink, true))
	for o in [["fire", tr("Менеджер может быть уволен советом директоров")],
			["country_only", tr("Только игроки из страны организации") + " (" + tr(_country_name(str(t.get("country", "ru")))) + ")"]]:
		var cb := CheckBox.new()
		cb.text = o[1]
		cb.button_pressed = bool(contract_opts[o[0]])
		cb.add_theme_font_override("font", UITheme.serif())
		cb.add_theme_font_size_override("font_size", 15)
		cb.add_theme_color_override("font_color", ink)
		cb.add_theme_color_override("font_hover_color", Color.BLACK)
		cb.add_theme_color_override("font_pressed_color", ink)
		cb.add_theme_color_override("font_hover_pressed_color", Color.BLACK)
		var key: String = o[0]
		cb.toggled.connect(func(on): contract_opts[key] = on)
		v.add_child(cb)
	var bottom := hbox(16)
	var dv := vbox(0)
	dv.add_child(_serif_label(tr("Дата:"), 13, dim))
	var now := Time.get_date_dict_from_system()
	dv.add_child(_serif_label("%02d.%02d.%d" % [now["day"], now["month"], now["year"]], 16, ink, true))
	dv.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(dv)
	bottom.add_child(spacer())
	var sv := vbox(2)
	var sig := preload("res://scripts/signature.gd").new()
	sig.custom_minimum_size = Vector2(300, 80)
	sv.add_child(sig)
	var sh := hbox(8)
	sh.add_child(_serif_label(tr("Поставьте подпись здесь"), 13, dim))
	sh.add_child(spacer())
	var clr := btn(tr("Очистить"), func(): sig.clear_sig())
	sh.add_child(clr)
	sv.add_child(sh)
	bottom.add_child(sv)
	v.add_child(bottom)
	var stamp := preload("res://scripts/stamp.gd").new().setup(str(t["name"]), str(t.get("tag", "")))
	stamp.visible = false
	var anchor := Control.new()
	anchor.custom_minimum_size = Vector2(0, 0)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(anchor)
	anchor.add_child(stamp)
	stamp.position = Vector2(-165, -118)
	# кнопки под листом
	var bar := hbox(10)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 24; bar.offset_right = -24; bar.offset_top = -70; bar.offset_bottom = -18
	add_child(bar)
	bar.add_child(_outline_btn("<  " + tr("НАЗАД"), func():
		if custom: show_org_creator()
		else: show_team_select(), Color("e0453a"), 16))
	bar.add_child(spacer())
	var go := _outline_btn(tr("ПРОДОЛЖИТЬ") + "  >", func(): _finish_contract(), C_GOOD, 18)
	go.disabled = true
	bar.add_child(go)
	sig.changed.connect(func():
		go.disabled = not sig.has_signature()
		if sig.has_signature() and not stamp.visible:
			stamp.appear = 0.0
			stamp.visible = true
		elif not sig.has_signature():
			stamp.visible = false)

func _serif_label(t: String, size: int, color: Color, bold_f: bool = false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UITheme.serif_bold() if bold_f else UITheme.serif())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _country_name(code: String) -> String:
	for c in Teams.COUNTRY_LIST:
		if c[0] == code:
			return c[1]
	return "Другая"

func _finish_contract() -> void:
	var team: Dictionary = contract_team.duplicate()
	team["can_be_fired"] = bool(contract_opts["fire"])
	team["country_only"] = bool(contract_opts["country_only"])
	_start_career_now(team)

func _start_career_now(team: Dictionary) -> void:

	if not team.has("roster") and not bool(team.get("custom", false)):
		team = team.duplicate()
		team["roster"] = _preview_roster(team)
	var photo := ""
	gs.slot = cr_slot if cr_slot > 0 else gs.free_slot()
	gs.delete_slot(gs.slot)
	cr_slot = -1
	if str(cr.get("photo", "")) != "" and FileAccess.file_exists(TMP_PHOTO):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(TMP_PHOTO), ProjectSettings.globalize_path(gs.photo_path_for(gs.slot)))
		photo = gs.photo_path_for(gs.slot)
	if photo == "":
		photo = str(cr.get("portrait", ""))
	if str(team.get("logo", "")) == TMP_LOGO:
		var dst: String = "user://team_logo_%d.png" % gs.slot
		DirAccess.copy_absolute(ProjectSettings.globalize_path(TMP_LOGO), ProjectSettings.globalize_path(dst))
		team = team.duplicate()
		team["logo"] = dst
		_tex_cache.erase(dst)
	gs.new_game({"name": "%s %s" % [cr["name"], cr["last"]], "nick": str(cr.get("nick", "")), "age": _cr_age(), "country": _cr_country_name(),
		"country_code": cr["country"], "gender": cr["gender"], "birth": [cr["day"], cr["month"], cr["year"]], "attrs": cr["attrs"], "avatar": {}, "photo": photo}, team)
	cr = {}
	cr_photo = null
	build_game()
var menu_right: Control
var tut_page: int = 0
var pending_delete: int = -1

func _clear_root() -> void:
	for c in get_children():
		if c is ColorRect and c.name == "BG":
			continue
		remove_child(c)
		c.queue_free()
	top_label = null

func _flat_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

## Кнопка большого меню (как в спортивных менеджерах): текст без рамки, подсветка при наведении.
func text_btn(t: String, cb: Callable, size: int = 22, color: Color = Color.WHITE) -> Button:
	var b := Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", C_ACC)
	b.add_theme_color_override("font_pressed_color", C_ACC.darkened(0.2))
	b.add_theme_color_override("font_focus_color", C_ACC)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _flat_style())
	b.pressed.connect(cb)
	return b

func menu_btn(t: String, cb: Callable, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = "   " + t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(300, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", C_ACC if accent else Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.BLACK)
	b.add_theme_color_override("font_pressed_color", Color.BLACK)
	for st in [["normal", Color("1f232b")], ["hover", C_ACC], ["pressed", Color("e09a2c")], ["disabled", Color("181b21")], ["focus", Color("1f232b")]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.set_corner_radius_all(6)
		sb.border_width_left = 6
		sb.border_color = C_ACC if accent else Color(st[1]).darkened(0.25)
		b.add_theme_stylebox_override(st[0], sb)
	b.pressed.connect(cb)
	return b

func _save_icon(d: Dictionary, sz: int) -> Control:
	var lp: String = str(d.get("team_logo", ""))
	if lp != "" and tex(lp) != null:
		var bgp := panel(Color(1, 1, 1, 0.08), 4)
		bgp.add_child(pic(lp, sz - 8))
		return bgp
	# логотипа нет — плашка с тегом команды
	var col := Color(str(d.get("team_color", "ffb23e")))
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.6)
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	badge.add_theme_stylebox_override("panel", sb)
	badge.custom_minimum_size = Vector2(sz, sz)
	var tag := label(str(d.get("team_tag", "?")), int(sz * 0.3), col)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(tag)
	return badge

func show_menu() -> void:
	in_match = false
	busy = false
	_clear_root()
	var bg := preload("res://scripts/menu_bg.gd").new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var left := vbox(4)
	left.position = Vector2(90, 0)
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 90
	left.offset_top = 110
	left.offset_right = 520
	left.offset_bottom = -30
	add_child(left)
	# логотип
	var logo := hbox(10)
	var lt := VBoxContainer.new()
	lt.add_theme_constant_override("separation", -14)
	lt.add_child(label("STANDOFF", 38, Color.WHITE))
	lt.add_child(label("COACH", 38, Color.WHITE))
	logo.add_child(lt)
	var box := panel(C_ACC, 8)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(label("SO2", 44, Color("14161b")))
	logo.add_child(box)
	left.add_child(logo)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	left.add_child(gap)
	# продолжить
	var saves: Array = gs.list_saves()
	if not saves.is_empty():
		var d: Dictionary = saves[0]["data"]
		var cont := Button.new()
		cont.custom_minimum_size = Vector2(380, 64)
		for st in ["normal", "hover", "pressed", "focus"]:
			cont.add_theme_stylebox_override(st, _flat_style())
		var ch := hbox(14)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.set_anchors_preset(Control.PRESET_FULL_RECT)
		var icon := _save_icon(d, 56)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.add_child(icon)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", -6)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ct := label(tr("ПРОДОЛЖИТЬ"), 28, Color.WHITE)
		cv.add_child(ct)
		cv.add_child(label(tr("как %s") % str(d.get("coach_name", "")) + "  ·  " + str(d.get("team_name", "")), 15, C_DIM))
		ch.add_child(cv)
		cont.add_child(ch)
		cont.mouse_entered.connect(func(): ct.add_theme_color_override("font_color", C_ACC))
		cont.mouse_exited.connect(func(): ct.add_theme_color_override("font_color", Color.WHITE))
		var sl: int = int(saves[0]["slot"])
		cont.pressed.connect(func():
			if gs.load_game(sl):
				build_game())
		left.add_child(cont)
		var g2 := Control.new()
		g2.custom_minimum_size = Vector2(0, 8)
		left.add_child(g2)
	left.add_child(text_btn(tr("НОВАЯ ИГРА"), func(): show_slots("new"), 26))
	left.add_child(text_btn(tr("ЗАГРУЗИТЬ"), func(): show_slots("load")))
	left.add_child(text_btn(tr("ОБУЧЕНИЕ"), func(): tut_page = 0; menu_page("tutorial")))
	left.add_child(text_btn(tr("НАСТРОЙКИ"), func(): menu_page("settings")))
	left.add_child(text_btn(tr("ВЫХОД"), func(): get_tree().quit()))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	# правая панель для подстраниц
	menu_right = Control.new()
	menu_right.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_right.offset_left = 560
	menu_right.offset_top = 60
	menu_right.offset_right = -50
	menu_right.offset_bottom = -50
	menu_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_right)

func _menu_card(t: String) -> VBoxContainer:
	if menu_right == null or not is_instance_valid(menu_right):
		show_menu()
	clear(menu_right)
	var p := panel(Color(0.09, 0.105, 0.13, 0.96), 26)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_right.add_child(p)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var v := vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var h := hbox(10)
	h.add_child(label(t, 28, C_ACC))
	h.add_child(spacer())
	h.add_child(btn("X", func(): menu_page("home"), C_DIM))
	v.add_child(h)
	return v

# ------------------------------------------------------------ экран слотов

var slots_mode: String = "load"
var slot_confirm: int = -1      # слот, ожидающий подтверждения (удаление / перезапись)
var slot_action: String = ""

func _fmt_date(s: String) -> String:
	# "2026-11-18 20:13:36" -> "18.11.2026 20:13"
	if s.length() < 16:
		return s
	return "%s.%s.%s %s" % [s.substr(8, 2), s.substr(5, 2), s.substr(0, 4), s.substr(11, 5)]

func _outline_btn(t: String, cb: Callable, col: Color, size: int = 20) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color("5b6270"))
	for st in [["normal", 0.85], ["hover", 1.0], ["pressed", 0.7], ["focus", 0.85], ["disabled", 0.15]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r * 0.75, col.g * 0.75, col.b * 0.75, st[1])
		sb.set_border_width_all(0)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 26; sb.content_margin_right = 26
		sb.content_margin_top = 10; sb.content_margin_bottom = 10
		b.add_theme_stylebox_override(st[0], sb)
	b.pressed.connect(cb)
	return b

## Экран выбора слота. mode = "new" (создать/заменить карьеру) или "load" (загрузить).
func show_slots(mode: String) -> void:
	slots_mode = mode
	_clear_root()
	var bg := preload("res://scripts/menu_bg.gd").new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var p := panel(Color(0.085, 0.095, 0.12, 0.97), 28)
	p.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	p.offset_left = 60
	p.offset_right = 680
	add_child(p)
	var v := vbox(16)
	p.add_child(v)
	var t := label(tr("ВЫБРАТЬ СЛОТ СОХРАНЕНИЯ") if mode == "new" else tr("ЗАГРУЗИТЬ ИГРУ"), 32, Color.WHITE)
	v.add_child(t)
	var saves: Array = gs.list_saves()
	if mode == "new":
		var cc := CenterContainer.new()
		var nb := _outline_btn("+  " + tr("СОЗДАТЬ НОВЫЙ СЛОТ"), func():
			cr = {}
			cr_slot = gs.free_slot()
			show_creator(), C_GOOD)
		nb.disabled = saves.size() >= gs.MAX_SLOTS
		cc.add_child(nb)
		v.add_child(cc)
		if nb.disabled:
			v.add_child(label(tr("Все %d слотов заняты — выберите слот, чтобы заменить карьеру.") % gs.MAX_SLOTS, 13, C_ACC))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if saves.is_empty():
		list.add_child(label(tr("Нет сохранений."), 16, C_DIM))
	for e in saves:
		list.add_child(slot_card(e["data"], int(e["slot"])))
	var bot := hbox(10)
	bot.add_child(_outline_btn("<  " + tr("НАЗАД"), func(): slot_confirm = -1; show_menu(), Color("e0453a")))
	v.add_child(bot)

func slot_card(d: Dictionary, sl: int) -> Control:
	var base_col := Color("1f232b")
	var hover_col := Color("3f8f3a")
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = base_col
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(0, 118)
	var h := hbox(16)
	card.add_child(h)
	var ic := _save_icon(d, 84)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var info := vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nick: String = str(d.get("coach_nick", ""))
	info.add_child(label(str(d.get("coach_name", "")) + ((" \"%s\"" % nick) if nick != "" else ""), 14, Color("d6dbe3")))
	info.add_child(label(str(d.get("team_name", "")).to_upper(), 26, Color.WHITE))
	var weeks: int = (int(d.get("season", 1)) - 1) * 10 + int(d.get("week", 1))
	var r1 := hbox(6)
	r1.add_child(label(tr("Время игры"), 14, Color("d6dbe3")))
	r1.add_child(label(tr("%d нед.") % weeks, 14, Color.WHITE))
	info.add_child(r1)
	var r2 := hbox(6)
	r2.add_child(label(tr("Сохранено"), 14, Color("d6dbe3")))
	r2.add_child(label(_fmt_date(str(d.get("saved_at", ""))), 14, Color("7dff6b")))
	info.add_child(r2)
	h.add_child(info)
	var ph: Texture2D = null
	ph = gs.photo_texture(str(d.get("photo_path", "")))
	var av := make_avatar(d.get("avatar", {}), 88, ph)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	# подтверждение
	if slot_confirm == sl:
		sb.bg_color = Color("3a2020")
		var cv := info
		var q := tr("Удалить этот слот?") if slot_action == "delete" else tr("Заменить эту карьеру новой?")
		cv.add_child(label(q, 13, C_ACC))
		var row := hbox(6)
		row.add_child(btn(tr("Да"), func():
			slot_confirm = -1
			if slot_action == "delete":
				gs.delete_slot(sl)
				show_slots(slots_mode)
			else:
				cr = {}
				cr_slot = sl
				show_creator(), C_BAD))
		row.add_child(btn(tr("Отмена"), func(): slot_confirm = -1; show_slots(slots_mode)))
		cv.add_child(row)
		return card
	# крестик удаления
	var x := Button.new()
	x.text = "X"
	x.add_theme_font_size_override("font_size", 20)
	x.add_theme_color_override("font_color", Color("ff5a3c"))
	x.add_theme_color_override("font_hover_color", Color("ff8a6c"))
	for st in ["normal", "hover", "pressed", "focus"]:
		x.add_theme_stylebox_override(st, _flat_style())
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.pressed.connect(func(): slot_confirm = sl; slot_action = "delete"; show_slots(slots_mode))
	# вся карточка — кнопка
	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	for st in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(st, _flat_style())
	hit.mouse_entered.connect(func(): sb.bg_color = hover_col)
	hit.mouse_exited.connect(func(): sb.bg_color = base_col)
	hit.pressed.connect(func():
		if slots_mode == "load":
			if gs.load_game(sl):
				build_game()
		else:
			slot_confirm = sl
			slot_action = "replace"
			show_slots(slots_mode))
	card.add_child(hit)
	_ignore_mouse(h)
	h.add_child(x)
	# крестик поверх кнопки-карточки
	h.move_to_front()
	return card

func _ignore_mouse(n: Node) -> void:
	if n is Control:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

const TUTORIAL := [
	["Добро пожаловать", "Вы — менеджер киберспортивной команды по Standoff 2. Цель — пройти путь от Открытой лиги до титула Мировой серии."],
	["Неделя", "Каждую неделю выберите фокус тренировок и стиль игры, сыграйте матч недели и нажмите «Завершить неделю»."],
	["Матч", "Перед матчем выберите карту — команда сильнее там, где выше мастерство. За карту доступно 2 тайм-аута: смена стиля и бонус на 3 раунда."],
	["Состав", "На карту выходят первые 5 здоровых игроков. Роли: Рифлер, Снайпер, Саппорт, Люркер, 2-й снайпер. Капитан (IGL) назначается в составе."],
	["Форма", "Тяжёлые тренировки растят навыки, но утомляют. Следите за формой и давайте отдых перед важными матчами."],
	["Деньги и трансферы", "Спонсоры платят каждую неделю, игроки получают зарплату. Подписывайте свободных агентов и продавайте лишних."],
	["Сезон", "7 туров лиги, затем плей-офф для топ-4. Топ-2 повышаются в дивизионе, двое последних вылетают."],
	["Навыки тренера", "Победы приносят очки навыков: вкладывайте их в тактику, мотивацию и скаутинг. Провал целей совета два сезона подряд — увольнение."],
]

func menu_page(page: String) -> void:
	match page:
		"home":
			if menu_right != null and is_instance_valid(menu_right):
				clear(menu_right)
		"new":
			show_creator()
		"load":
			show_slots("load")
		"tutorial":
			var v := _menu_card(tr("Обучение"))
			var step: Array = TUTORIAL[tut_page]
			v.add_child(label(tr("Шаг %d из %d") % [tut_page + 1, TUTORIAL.size()], 13, C_DIM))
			v.add_child(label(tr(step[0]), 24))
			v.add_child(wrap_label(tr(step[1]), 17, Color("d6dbe3"), 560))
			var bar := ProgressBar.new()
			bar.max_value = TUTORIAL.size()
			bar.value = tut_page + 1
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 6)
			v.add_child(bar)
			var row := hbox(10)
			var back := btn(tr("Назад"), func(): tut_page -= 1; menu_page("tutorial"))
			back.disabled = tut_page == 0
			row.add_child(back)
			row.add_child(spacer())
			if tut_page < TUTORIAL.size() - 1:
				row.add_child(btn(tr("Далее"), func(): tut_page += 1; menu_page("tutorial"), C_GOOD))
			else:
				row.add_child(btn(tr("Начать карьеру"), func(): show_slots("new"), C_GOOD))
			v.add_child(row)
		"settings":
			var v := _menu_card(tr("Настройки"))
			build_settings(v, func(): menu_page("settings"))

## Общий блок настроек — используется и в главном меню, и в игре.
func build_settings(v: VBoxContainer, refresh: Callable) -> void:
	var st: Node = get_node("/root/Settings")
	var lr := hbox(10)
	lr.add_child(cell("Язык / Language", 260))
	var lo := OptionButton.new()
	var lkeys: Array = ["ru", "en"]
	lo.add_item("Русский")
	lo.add_item("English")
	lo.selected = maxi(0, lkeys.find(st.language))
	lo.item_selected.connect(func(i):
		st.language = lkeys[i]; st.apply(); st.save_settings()
		if top_label != null:
			build_game()
			show_screen("system")
		else:
			show_menu()
			menu_page("settings"))
	lr.add_child(lo)
	v.add_child(lr)
	v.add_child(label(tr("Экран"), 17, C_ACC))
	var fs := CheckButton.new()
	fs.text = tr("Полноэкранный режим")
	fs.button_pressed = st.fullscreen
	fs.toggled.connect(func(on): st.fullscreen = on; st.apply(); st.save_settings())
	v.add_child(fs)
	var vs := CheckButton.new()
	vs.text = tr("Вертикальная синхронизация (VSync)")
	vs.button_pressed = st.vsync
	vs.toggled.connect(func(on): st.vsync = on; st.apply(); st.save_settings())
	v.add_child(vs)
	var r1 := hbox(10)
	r1.add_child(cell(tr("Масштаб интерфейса"), 260))
	var sc := OptionButton.new()
	for s in st.UI_SCALES:
		sc.add_item("%d%%" % int(round(s * 100)))
	sc.selected = maxi(0, st.UI_SCALES.find(st.ui_scale))
	sc.item_selected.connect(func(i): st.ui_scale = st.UI_SCALES[i]; st.apply(); st.save_settings())
	r1.add_child(sc)
	v.add_child(r1)
	v.add_child(label(tr("Игра"), 17, C_ACC))
	var r2 := hbox(10)
	r2.add_child(cell(tr("Скорость симуляции матча"), 260))
	var sp := OptionButton.new()
	var keys: Array = st.SPEED_NAMES.keys()
	for k in keys:
		sp.add_item(st.SPEED_NAMES[k])
	sp.selected = maxi(0, keys.find(st.match_speed))
	sp.item_selected.connect(func(i): st.match_speed = keys[i]; st.save_settings())
	r2.add_child(sp)
	v.add_child(r2)
	var au := CheckButton.new()
	au.text = tr("Автосохранение после каждой недели")
	au.button_pressed = st.autosave
	au.toggled.connect(func(on): st.autosave = on; st.save_settings())
	v.add_child(au)
	var sb := CheckButton.new()
	sb.text = tr("Показывать закупку команд в логе матча")
	sb.button_pressed = st.show_buys
	sb.toggled.connect(func(on): st.show_buys = on; st.save_settings())
	v.add_child(sb)
	var row := hbox(10)
	row.add_child(btn(tr("Сбросить настройки"), func(): st.reset(); refresh.call()))
	v.add_child(row)

# ------------------------------------------------------------ каркас игры

var hist: Array = []
var hist_pos: int = -1
var title_label: Label
var date_label: Label
var cont_btn: Button
var nav_btns: Dictionary = {}

const NAV := [
	["dashboard", "Главная", "home"], ["mail", "Почта", "mail"], ["talk", "Разговор", "forum"], [],
	["squad", "Состав", "groups"], ["staff", "Штат", "badge"], ["training", "Тренировка", "fitness_center"],
	[], ["scouting", "Скаутинг", "travel_explore"], ["transfers", "Трансферы", "swap_horiz"], ["league", "Турниры", "emoji_events"], ["stats", "Статистика", "bar_chart"],
	[], ["finance", "Финансы", "payments"], ["coach", "Профиль", "account_circle"], [], ["system", "Настройки", "settings"],
]
const SCREEN_TITLES := {"dashboard": "Главная", "mail": "Почта", "squad": "Состав", "staff": "Штат", "training": "Тренировка",
	"transfers": "Трансферы", "league": "Турниры", "stats": "Статистика", "finance": "Финансы", "coach": "Профиль", "system": "Настройки", "match": "Матч", "player": "Профиль игрока", "talk": "Разговор", "scouting": "Скаутинг", "staff_member": "Персонал команды", "staff_hire": "Найм персонала"}
const WEEKDAYS := ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
const MONTHS_SHORT := ["янв.", "февр.", "марта", "апр.", "мая", "июня", "июля", "авг.", "сент.", "окт.", "нояб.", "дек."]

## Игровая дата: сезон 1 начинается 1 января 2026, ход = неделя.
func game_date() -> Dictionary:
	var start := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 1, "day": 1, "hour": 12, "minute": 0, "second": 0})
	var days: int = ((gs.season - 1) * 52 + (gs.week - 1)) * 7
	return Time.get_datetime_dict_from_unix_time(start + days * 86400)

## Внешний вид любой команды лиги: логотип, цвет, тег.
func team_visual(name: String) -> Dictionary:
	if name == gs.team_name:
		return {"logo": gs.team_logo, "color": gs.team_color, "tag": gs.team_tag}
	for t in Teams.START_TEAMS:
		if t["name"] == name:
			return {"logo": str(t.get("logo", "")), "color": t["color"], "tag": t["tag"]}
	var logos: Array = _logo_list()
	var h: int = abs(hash(name))
	var words: PackedStringArray = name.split(" ")
	var tag := ""
	for w in words:
		if w != "": tag += w.substr(0, 1).to_upper()
	return {"logo": logos[h % logos.size()] if not logos.is_empty() else "", "color": TEAM_COLORS[h % TEAM_COLORS.size()][0], "tag": tag}

func team_icon(name: String, sz: int) -> Control:
	var v: Dictionary = team_visual(name)
	if tex(v["logo"]) != null:
		var r := pic(v["logo"], sz)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return r
	return _save_icon({"team_tag": v["tag"], "team_color": v["color"]}, sz)

func _nav_btn(key: String, text: String, icon: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(184, 36)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "          " + text
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color("d6dbe3"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	for st in [["normal", Color(0, 0, 0, 0)], ["hover", Color(1, 1, 1, 0.06)], ["pressed", Color(0.2, 0.5, 0.9, 0.35)], ["focus", Color(0, 0, 0, 0)]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override(st[0], sb)
	var ic := UITheme.icon(icon, 20)
	ic.position = Vector2(10, 7)
	b.add_child(ic)
	b.pressed.connect(func(): show_screen(key))
	return b

func build_game() -> void:
	_clear_root()
	hist = []
	hist_pos = -1
	_photo_bg("res://assets/ui/arena_bg.jpg", 0.45)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	# --- боковое меню
	var side := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.06, 0.08, 0.11, 0.92)
	ssb.set_content_margin_all(10)
	side.add_theme_stylebox_override("panel", ssb)
	root.add_child(side)
	var sv := vbox(2)
	side.add_child(sv)
	var who := hbox(10)
	photo_tex = gs.load_photo()
	var av := _circle(gs.photo_path, 44, Color(gs.team_color))
	who.add_child(av)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", -4)
	wv.add_child(label(gs.coach_nick if gs.coach_nick != "" else gs.coach_name, 12, C_DIM))
	wv.add_child(label(gs.team_tag, 18, Color.WHITE))
	who.add_child(wv)
	if tex(gs.team_logo) != null:
		who.add_child(pic(gs.team_logo, 34))
	sv.add_child(who)
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, 10)
	sv.add_child(g)
	nav_btns = {}
	for e in NAV:
		if e.is_empty():
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(0, 10)
			sv.add_child(sp)
			continue
		var b := _nav_btn(e[0], tr(e[1]), e[2])
		nav_btns[e[0]] = b
		sv.add_child(b)
	var f := Control.new()
	f.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(f)
	sv.add_child(_nav_btn_exit())
	# --- правая часть
	var right := vbox(0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var top := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.07, 0.1, 0.75)
	tsb.content_margin_left = 16; tsb.content_margin_right = 12; tsb.content_margin_top = 8; tsb.content_margin_bottom = 8
	top.add_theme_stylebox_override("panel", tsb)
	right.add_child(top)
	var th := hbox(10)
	top.add_child(th)
	th.add_child(text_btn("<", func(): _hist_move(-1), 24))
	th.add_child(text_btn(">", func(): _hist_move(1), 24))
	title_label = label("", 22, Color.WHITE)
	th.add_child(title_label)
	th.add_child(spacer())
	top_label = label("", 12, C_DIM)
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(top_label)
	date_label = label("", 12, Color.WHITE)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(date_label)
	cont_btn = _outline_btn(tr("ПРОДОЛЖИТЬ") + "  >", func(): on_continue(), C_GOOD, 14)
	th.add_child(cont_btn)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side_m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side_m, 16)
	sc.add_child(pad)
	content = vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(content)
	log_label = null
	show_screen("dashboard")

func _nav_btn_exit() -> Button:
	var b := _nav_btn("system", tr("Выйти в меню"), "logout")
	for c in b.pressed.get_connections():
		b.pressed.disconnect(c["callable"])
	b.pressed.connect(func(): gs.save(); show_menu())
	return b

func _hist_move(d: int) -> void:
	var np: int = hist_pos + d
	if np < 0 or np >= hist.size():
		return
	hist_pos = np
	show_screen(hist[hist_pos], false)

func on_continue() -> void:
	if busy or in_match:
		return
	var pm: Dictionary = gs.player_match()
	if gs.game_over != "":
		return
	if not pm.is_empty() and not gs.match_done and gs.has_enough_players():
		on_play_match()
	else:
		on_finish_week()

func refresh_top() -> void:
	if top_label == null:
		return
	top_label.text = "%s  ·  %s   " % [money_fmt(gs.money), tr(gs.TIERS[gs.tier])]
	var d := game_date()
	date_label.text = "%s,\n%02d %s %d" % [tr(WEEKDAYS[int(d["weekday"])]), int(d["day"]), tr(MONTHS_SHORT[int(d["month"]) - 1]), int(d["year"])]
	if title_label != null:
		title_label.text = tr(SCREEN_TITLES.get(current, "Главная"))
	if cont_btn != null:
		var pm: Dictionary = gs.player_match()
		var label_t := tr("ПРОДОЛЖИТЬ")
		if not pm.is_empty() and not gs.match_done and gs.has_enough_players():
			label_t = tr("К МАТЧУ")
		cont_btn.text = label_t + "  >"
		cont_btn.disabled = in_match or gs.game_over != ""
	if nav_btns.has("mail"):
		var ub: int = gs.unread_mail()
		nav_btns["mail"].text = "          " + tr("Почта") + (("  (%d)" % ub) if ub > 0 else "")
	if nav_btns.has("talk"):
		var ut: int = gs.unread_talks()
		nav_btns["talk"].text = "          " + tr("Разговор") + (("  (%d)" % ut) if ut > 0 else "")
	for k in nav_btns:
		var b: Button = nav_btns[k]
		b.add_theme_color_override("font_color", Color.WHITE if k == current else Color("aab2c0"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.45, 0.85, 0.35) if k == current else Color(0, 0, 0, 0)
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", sb)

func show_screen(name: String, push: bool = true) -> void:
	if busy:
		return
	if content == null or not is_instance_valid(content):
		build_game()
		if name == "dashboard":
			return
	current = name
	in_match = false
	if push:
		hist = hist.slice(0, hist_pos + 1)
		if hist.is_empty() or hist[hist.size() - 1] != name:
			hist.append(name)
		hist_pos = hist.size() - 1
	clear(content)
	refresh_top()
	if gs.game_over != "":
		show_game_over()
		return
	match name:
		"dashboard": screen_dashboard()
		"mail": screen_mail()
		"scouting": screen_scouting()
		"talk": screen_talk()
		"staff_member": screen_staff_member()
		"staff_hire": screen_staff_hire()
		"squad": screen_squad()
		"staff": screen_staff()
		"training": screen_training()
		"transfers": screen_transfers()
		"league": screen_league()
		"stats": screen_stats()
		"finance": screen_finance()
		"player": screen_player()
		"coach": screen_coach()
		"system": screen_system()
		_: screen_dashboard()

func show_game_over() -> void:
	var p := panel(C_PANEL, 24)
	var v := vbox(12)
	p.add_child(v)
	v.add_child(label(tr("КАРЬЕРА ЗАВЕРШЕНА"), 32, C_BAD))
	v.add_child(label(gs.game_over, 16))
	v.add_child(label(tr("Сезонов: %d · Титулов: %d") % [gs.season, gs.titles], 15, C_DIM))
	v.add_child(btn(tr("В главное меню"), func(): show_menu()))
	content.add_child(p)

func title(t: String) -> Label:
	return label(t, 22, Color.WHITE)

# ------------------------------------------------------------ главная

func _block(t: String) -> VBoxContainer:
	var v := vbox(6)
	var h := hbox(6)
	h.add_child(label("»", 15, Color("ffb23e")))
	h.add_child(label(t, 15, Color.WHITE))
	v.add_child(h)
	return v

func _card() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.17, 0.9)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _alert(t: String, good: bool) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.35, 0.15, 0.55) if good else Color(0.45, 0.12, 0.12, 0.55)
	sb.border_width_left = 4
	sb.border_color = C_GOOD if good else C_BAD
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(t, 14, Color.WHITE))
	return p

func screen_dashboard() -> void:
	var pm: Dictionary = gs.player_match()
	# --- верхняя полоса: статус + лиги
	var topc := _card()
	content.add_child(topc)
	var th := hbox(16)
	topc.add_child(th)
	var status_t := ""
	var status_d := ""
	if gs.week > 9:
		status_t = tr("Межсезонье")
		status_d = tr("Подпишите игроков и подготовьтесь к новому сезону. Нажмите «Продолжить».")
	elif not pm.is_empty() and not gs.match_done:
		status_t = tr("Матч на этой неделе")
		status_d = tr("%s против %s. Нажмите «К матчу».") % [gs.team_name, pm["opp"]]
	else:
		status_t = tr("Готовы к следующей неделе")
		status_d = tr("Работа здесь завершена. Нажмите «Продолжить», чтобы перейти дальше.")
	th.add_child(UITheme.icon("thumb_up", 34, Color("d6dbe3")))
	var sv := vbox(0)
	sv.add_child(label(status_t, 15, Color.WHITE))
	sv.add_child(label(status_d, 12, C_DIM))
	th.add_child(sv)
	th.add_child(spacer())
	for i in 3:
		var tv := vbox(0)
		var cup := pic("res://assets/ui/trophy.png", 46)
		cup.modulate = Color.WHITE if i == gs.tier else Color(1, 1, 1, 0.3)
		tv.add_child(cup)
		var tl := label(tr(gs.TIERS[i]), 10, Color.WHITE if i == gs.tier else C_DIM)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(tl)
		th.add_child(tv)
	var po := vbox(0)
	po.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	po.add_child(label(tr("ПЛЕЙ-ОФФ"), 15, Color.WHITE))
	var left: int = 8 - gs.week
	po.add_child(label(tr("Через %d нед.") % left if left > 0 else gs.phase_name(), 12, C_DIM))
	th.add_child(po)

	var cols := hbox(14)
	content.add_child(cols)
	# --- колонка 1: организация
	var c1 := vbox(12)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c1)
	var ob := _block(tr("Организация"))
	c1.add_child(ob)
	var oc := _card()
	ob.add_child(oc)
	var ov := vbox(8)
	oc.add_child(ov)
	if gs.train_focus == "rest":
		ov.add_child(_alert(tr("Неделя отдыха: игроки восстанавливают форму."), true))
	else:
		ov.add_child(_alert(tr("Тренировка недели: %s") % tr(gs.TRAIN[gs.train_focus]), true))
	ov.add_child(label(tr("СОСТАВ"), 13, C_DIM))
	var rr := hbox(8)
	for p in gs.lineup():
		var pv := vbox(2)
		pv.add_child(_circle(player_photo(p), 54))
		var nl := label(p["nick"], 11, Color.WHITE)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.custom_minimum_size = Vector2(54, 0)
		nl.clip_text = true
		pv.add_child(nl)
		rr.add_child(pv)
	for i in range(gs.lineup().size(), 5):
		rr.add_child(_circle("", 54, Color(1, 1, 1, 0.2)))
	ov.add_child(rr)
	var tired: int = 0
	for p in gs.players:
		if int(p["form"]) < 50: tired += 1
	if not gs.has_enough_players():
		ov.add_child(_alert(tr("Недостаточно здоровых игроков (нужно 5)! Подпишите кого-нибудь."), false))
	elif tired > 0:
		ov.add_child(_alert(tr("Уставших игроков: %d. Подумайте об отдыхе.") % tired, false))
	else:
		ov.add_child(_alert(tr("Все игроки в хорошей форме!"), true))
	var eb := _block(tr("Ключевые события"))
	c1.add_child(eb)
	var ec := _card()
	eb.add_child(ec)
	var ev := vbox(6)
	ec.add_child(ev)
	for i in min(4, gs.news.size()):
		ev.add_child(wrap_label(str(gs.news[i]), 12, Color("c9ced8"), 330))
	# --- колонка 2: матчи
	var c2 := vbox(12)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c2)
	var ub := _block(tr("Предстоящие матчи"))
	c2.add_child(ub)
	var uc := _card()
	ub.add_child(uc)
	var uv := vbox(8)
	uc.add_child(uv)
	var shown: int = 0
	for w in range(gs.week, 8):
		if shown >= 3:
			break
		var opp := ""
		for pair in gs.schedule[w - 1]:
			if pair.has(gs.team_name):
				opp = pair[1] if pair[0] == gs.team_name else pair[0]
		if opp == "" or (w == gs.week and gs.match_done):
			continue
		var r := hbox(10)
		r.add_child(team_icon(opp, 44))
		var rv := vbox(0)
		rv.add_child(label(opp.to_upper(), 15, Color.WHITE))
		rv.add_child(label(tr("Тур %d · %s") % [w, tr("на этой неделе") if w == gs.week else tr("через %d нед.") % (w - gs.week)], 12, C_DIM))
		r.add_child(rv)
		uv.add_child(r)
		shown += 1
	if shown == 0:
		if not pm.is_empty() and not gs.match_done:
			var r2 := hbox(10)
			r2.add_child(team_icon(pm["opp"], 44))
			r2.add_child(label(str(pm["opp"]).to_upper() + "  (BO%d)" % pm["bo"], 15, Color.WHITE))
			uv.add_child(r2)
		else:
			uv.add_child(label(tr("НЕТ ЗАПЛАНИРОВАННЫХ МАТЧЕЙ"), 14, C_DIM))
	var lb := _block(tr("Последние результаты"))
	c2.add_child(lb)
	var lc := _card()
	lb.add_child(lc)
	var lv := vbox(4)
	lc.add_child(lv)
	var res: Array = []
	for n in gs.news:
		var s: String = str(n)
		if s.find(tr("Победа")) >= 0 or s.find(tr("Поражение")) >= 0:
			res.append(s)
		if res.size() >= 4:
			break
	if res.is_empty():
		var nl2 := label(tr("НЕТ НЕДАВНИХ ИГР"), 14, Color.WHITE)
		nl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.add_child(nl2)
	for s in res:
		lv.add_child(label(s, 12, C_GOOD if s.find(tr("Победа")) >= 0 else C_BAD))
	# --- колонка 3: рейтинг
	var c3 := vbox(12)
	c3.custom_minimum_size = Vector2(300, 0)
	cols.add_child(c3)
	var rb := _block(tr("Глобальный рейтинг Rankoff"))
	c3.add_child(rb)
	var rc := _card()
	rb.add_child(rc)
	var rv2 := vbox(3)
	rc.add_child(rv2)
	var rl: Array = gs.rankoff_list()
	var my_pos: int = rl.find(gs.team_name)
	for stage in [[tr("STAGE 3"), 0, 8], [tr("STAGE 2"), 8, 16]]:
		if rl.size() <= stage[1]:
			continue
		rv2.add_child(label(stage[0], 13, C_DIM))
		for i in range(stage[1], mini(stage[2], rl.size())):
			rv2.add_child(_rank_row(i, rl[i]))
	if my_pos >= 16:
		var sep := ColorRect.new()
		sep.color = Color(1, 1, 1, 0.1)
		sep.custom_minimum_size = Vector2(0, 1)
		rv2.add_child(sep)
		rv2.add_child(_rank_row(my_pos, gs.team_name))

func _rank_row(i: int, tname: String) -> Control:
	var row := hbox(8)
	var mine: bool = tname == gs.team_name
	row.add_child(cell("#%d" % (i + 1), 34, C_ACC if mine else Color("d6dbe3"), 13))
	row.add_child(team_icon(tname, 22))
	row.add_child(cell(tname, 150, C_ACC if mine else Color.WHITE, 13))
	row.add_child(cell(str(int(gs.rankoff[tname])), 44, C_DIM, 12))
	return row

# ------------------------------------------------------------ профиль игрока

var viewed_player: Dictionary = {}

func _nick_link(pl: Dictionary, w: int, col: Color) -> Button:
	var b := Button.new()
	b.text = str(pl["nick"])
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(w, 0)
	b.clip_text = true
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 14)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, _flat_style())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ref: Dictionary = pl
	b.pressed.connect(func(): viewed_player = ref; show_screen("player"))
	return b

func _attr_color(v: float) -> Color:
	if v < 8.0: return Color("ff5a3c")
	if v < 13.0: return Color("ffb23e")
	return Color("7ddf5a")

var player_tab: String = "attrs"
var cmp_attr: String = "skill"
var contract_form: bool = false
var cf_years: int = 2
var cf_salary: int = 0

const REP_NAMES := ["Новичок", "Перспективный", "Достойный", "Звезда", "Легенда"]

func _role_tags(pl: Dictionary) -> Array:
	var tags: Array = []
	if bool(pl.get("captain", false)):
		tags.append("IGL")
	var m := {"Рифлер": "RIFLER", "Снайпер": "AWPER", "Саппорт": "SUPPORT", "Лурк": "LURKER", "2-й снайпер": "2ND SNIPER"}
	tags.append(m.get(str(pl.get("role", "")), "RIFLER"))
	var r2: String = str(pl.get("role2", ""))
	if r2 != "" and m.has(r2) and not tags.has(m[r2]):
		tags.append(m[r2])
	return tags

func _radar_vals(pl: Dictionary) -> Array:
	var a: Dictionary = pl["attrs"]
	var f := func(keys: Array) -> float:
		var s: float = 0.0
		for k in keys: s += float(a.get(k, 10))
		return s / keys.size() / 20.0
	return [f.call(["perception", "stress", "teamwork", "nades"]), f.call(["skill", "rifle", "awp" if pl["role"] == "Снайпер" else "pistol", "reaction"]),
		f.call(["leader", "teamwork", "morale"]), f.call(["tactics", "creativity", "nades"]), f.call(["clutch", "stress", "creativity"])]

func screen_player() -> void:
	var pl: Dictionary = viewed_player
	if pl.is_empty():
		screen_squad()
		return
	gs.ensure_attrs(pl)
	gs.init_player_meta(pl)
	var mine: bool = gs.players.has(pl)
	var tabs := hbox(18)
	for tb in [["attrs", tr("Характеристики")], ["contract", tr("Контракт")], ["transfer", tr("Трансфер")], ["stats", tr("Статистика")]]:
		var key: String = tb[0]
		tabs.add_child(text_btn(tb[1], func(): player_tab = key; contract_form = false; show_screen("player", false), 16, C_ACC if player_tab == key else Color.WHITE))
	tabs.add_child(spacer())
	tabs.add_child(small_btn("<  " + tr("Назад"), func(): _hist_move(-1)))
	content.add_child(tabs)
	var cols := hbox(12)
	content.add_child(cols)
	cols.add_child(_player_left(pl, mine))
	var right := vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	match player_tab:
		"attrs": _player_attrs(pl, right)
		"contract": _player_contract(pl, right, mine)
		"transfer": _player_transfer(pl, right, mine)
		"stats": _player_stats(pl, right)
	if title_label != null:
		title_label.text = tr("Профиль игрока") + " | " + str(pl["nick"])

func _player_left(pl: Dictionary, mine: bool) -> Control:
	var tc := Color(gs.team_color)
	var c := _card()
	c.custom_minimum_size = Vector2(370, 0)
	var v := vbox(10)
	c.add_child(v)
	var top := hbox(12)
	var ph := Control.new()
	ph.custom_minimum_size = Vector2(120, 170)
	ph.clip_contents = true
	var bgc := ColorRect.new()
	bgc.color = Color(tc.r, tc.g, tc.b, 0.18)
	bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
	ph.add_child(bgc)
	var img := TextureRect.new()
	img.texture = tex(player_photo(pl))
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	ph.add_child(img)
	top.add_child(ph)
	var iv := vbox(5)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var full: String = "%s \"%s\" %s" % [tr(str(pl.get("first", ""))), pl["nick"], tr(str(pl.get("last", "")))] if str(pl.get("first", "")) != "" else str(pl["nick"])
	var nl := label(full, 16, Color.WHITE)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(200, 0)
	iv.add_child(nl)
	var sr := hbox(8)
	sr.add_child(_stars(_player_stars(pl), 14))
	sr.add_child(label(" · ".join(_role_tags(pl)), 12, Color("2fb8e8")))
	iv.add_child(sr)
	var tr2 := hbox(6)
	if mine and tex(gs.team_logo) != null:
		tr2.add_child(pic(gs.team_logo, 22))
	if not mine and str(pl.get("team", "")) != "":
		tr2.add_child(team_icon(str(pl["team"]), 22))
	tr2.add_child(label(gs.team_name if mine else (str(pl.get("team", "")) if str(pl.get("team", "")) != "" else tr("Свободный агент")), 13, Color.WHITE))
	iv.add_child(tr2)
	var cr2 := hbox(6)
	cr2.add_child(_flag(str(pl.get("country", "xx")), 22))
	cr2.add_child(label(tr(_country_name(str(pl.get("country", "xx")))), 13, Color.WHITE))
	iv.add_child(cr2)
	var bd := hbox(6)
	var inj: bool = int(pl["inj"]) > 0
	bd.add_child(_badge(tr("Травма") if inj else tr("Активен"), C_BAD if inj else C_GOOD))
	var mo: int = int(pl.get("morale", 80))
	bd.add_child(_badge(tr("Счастлив") if mo >= 70 else (tr("Спокоен") if mo >= 45 else tr("Недоволен")), C_GOOD if mo >= 70 else (C_ACC if mo >= 45 else C_BAD)))
	iv.add_child(bd)
	var rings := hbox(8)
	var PR := preload("res://scripts/progress_ring.gd")
	for e in [[int(pl["form"]), tr("ФОРМА")], [int(pl.get("health", 90)), tr("ЗДОРОВЬЕ")], [int(pl.get("pr", 60)), "PR"]]:
		rings.add_child(PR.new().setup(float(e[0]) / 100.0, 64, _form_col(int(e[0])), e[1], str(e[0])))
	iv.add_child(rings)
	top.add_child(iv)
	v.add_child(top)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.08)
	sep.custom_minimum_size = Vector2(0, 1)
	v.add_child(sep)
	var mid := hbox(10)
	var lv := vbox(6)
	lv.add_child(_mini_hdr(tr("Роли игрока")))
	var rr := hbox(6)
	var r1 := OptionButton.new()
	for r in gs.ROLES:
		r1.add_item(tr(r))
	r1.selected = maxi(0, gs.ROLES.find(pl["role"]))
	r1.disabled = not mine
	var ref: Dictionary = pl
	r1.item_selected.connect(func(i): ref["role"] = gs.ROLES[i]; gs.derive(ref); show_screen("player", false))
	rr.add_child(r1)
	var r2 := OptionButton.new()
	r2.add_item("—")
	for r in gs.ROLES:
		r2.add_item(tr(r))
	r2.selected = maxi(0, gs.ROLES.find(str(pl.get("role2", ""))) + 1)
	r2.disabled = not mine
	r2.item_selected.connect(func(i): ref["role2"] = "" if i == 0 else gs.ROLES[i - 1]; show_screen("player", false))
	rr.add_child(r2)
	lv.add_child(rr)
	lv.add_child(_mini_hdr(tr("Потенциал")))
	lv.add_child(_stars(clampf((float(pl.get("pot_est", pl["pot"])) - 35.0) / 9.0, 0.5, 5.0), 18))
	lv.add_child(_mini_hdr(tr("Репутация")))
	var rp: int = clampi(int((gs.ovr(pl) - 45) / 10 + int(pl.get("pr", 60)) / 40), 0, 4)
	var rb := PanelContainer.new()
	var rbs := StyleBoxFlat.new()
	rbs.bg_color = Color(0.2, 0.45, 0.9, 0.55)
	rbs.set_corner_radius_all(6)
	rbs.set_content_margin_all(8)
	rb.add_theme_stylebox_override("panel", rbs)
	var rh := hbox(8)
	rh.add_child(UITheme.icon("military_tech", 26, Color("f5c518")))
	rh.add_child(label(tr(REP_NAMES[rp]), 16, Color.WHITE))
	rb.add_child(rh)
	lv.add_child(rb)
	mid.add_child(lv)
	mid.add_child(preload("res://scripts/radar.gd").new().setup([tr("ЗАЩИТА"), tr("АТАКА"), tr("ЛИДЕР"), tr("ТАКТИКА"), tr("КЛАТЧ")], _radar_vals(pl), 110))
	v.add_child(mid)
	v.add_child(_mini_hdr(tr("Биография")))
	var b: Array = pl.get("birth", [1, 1, 2000])
	var months := ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
	v.add_child(label(tr("%d лет (%02d.%02d.%d)") % [int(pl["age"]), int(b[0]), int(b[1]), int(b[2])], 13, Color.WHITE))
	var bio: String = tr("%s (родился %d %s %d года) — профессиональный игрок в Standoff 2 из страны %s. Основная роль — %s.") % [full, int(b[0]), tr(months[int(b[1]) - 1]), int(b[2]), tr(_country_name(str(pl.get("country", "xx")))), tr(pl["role"])]
	if mine:
		bio += " " + tr("Выступает за %s.") % gs.team_name
	v.add_child(wrap_label(bio, 12, C_DIM, 340))
	return c

func _attr_name(k: String) -> String:
	for e in gs.ATTR_TECH + gs.ATTR_MENTAL + gs.ATTR_PHYS:
		if e[0] == k:
			return tr(e[1])
	return k

func _mini_hdr(t: String) -> Control:
	var h := hbox(5)
	h.add_child(label("»", 13, C_ACC))
	h.add_child(label(t, 13, Color.WHITE))
	return h

func _player_attrs(pl: Dictionary, right: VBoxContainer) -> void:
	var ab := _block(tr("Характеристики"))
	right.add_child(ab)
	var ac := _card()
	ab.add_child(ac)
	var cols := hbox(10)
	ac.add_child(cols)
	for grp in [[tr("ТЕХНИЧЕСКИЕ"), gs.ATTR_TECH], [tr("МЕНТАЛЬНЫЕ"), gs.ATTR_MENTAL], [tr("ФИЗИЧЕСКИЕ"), gs.ATTR_PHYS]]:
		var cv := vbox(2)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := PanelContainer.new()
		var hs := StyleBoxFlat.new()
		hs.bg_color = Color(1, 1, 1, 0.06)
		hs.set_content_margin_all(6)
		head.add_theme_stylebox_override("panel", hs)
		head.add_child(label(grp[0], 13, Color.WHITE))
		cv.add_child(head)
		for a in grp[1]:
			var k: String = a[0]
			var val: float = float(pl["attrs"].get(k, 0))
			var row := PanelContainer.new()
			var rs := StyleBoxFlat.new()
			rs.bg_color = Color(0.2, 0.45, 0.85, 0.5) if k == cmp_attr else Color(1, 1, 1, 0.025)
			rs.content_margin_left = 8; rs.content_margin_right = 8; rs.content_margin_top = 4; rs.content_margin_bottom = 4
			row.add_theme_stylebox_override("panel", rs)
			var rh := hbox(4)
			row.add_child(rh)
			var nl := label(tr(a[1]), 12, Color("e9edf3"))
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nl.clip_text = true
			nl.custom_minimum_size = Vector2(60, 0)
			rh.add_child(nl)
			rh.add_child(label("%.2f" % val, 13, _attr_color(val)))
			var hit := Button.new()
			hit.flat = true
			for st in ["normal", "hover", "pressed", "focus"]:
				hit.add_theme_stylebox_override(st, _flat_style())
			hit.pressed.connect(func(): cmp_attr = k; show_screen("player", false))
			row.add_child(hit)
			_ignore_mouse(rh)
			cv.add_child(row)
		cols.add_child(cv)
	var hb := _block(tr("История и сравнение") + " — " + _attr_name(cmp_attr))
	right.add_child(hb)
	var hr := hbox(10)
	hb.add_child(hr)
	var lc := _card()
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vals: Array = []
	var labs: Array = []
	for h in pl.get("ahist", []):
		vals.append(float(h["a"].get(cmp_attr, 0)))
		labs.append(tr("Н%d") % int(h["w"]))
	vals.append(float(pl["attrs"].get(cmp_attr, 0)))
	labs.append(tr("сейчас"))
	var lcv := vbox(4)
	lcv.add_child(label(tr("ИСТОРИЯ ИЗМЕНЕНИЯ АТРИБУТА"), 11, C_DIM))
	lcv.add_child(preload("res://scripts/line_chart.gd").new().setup(vals, labs, 170))
	lc.add_child(lcv)
	hr.add_child(lc)
	var cc := _card()
	cc.custom_minimum_size = Vector2(220, 0)
	var cv2 := vbox(4)
	cc.add_child(cv2)
	cv2.add_child(label(tr("СРАВНЕНИЕ В КОМАНДЕ"), 11, C_DIM))
	var arr: Array = gs.players.duplicate() if gs.players.has(pl) else gs.players + [pl]
	for q in arr:
		gs.ensure_attrs(q)
	arr.sort_custom(func(x, y): return float(x["attrs"].get(cmp_attr, 0)) > float(y["attrs"].get(cmp_attr, 0)))
	for i in arr.size():
		var q: Dictionary = arr[i]
		var r := hbox(6)
		r.add_child(cell(str(i + 1), 18, Color.WHITE, 13))
		var bar := _bar(float(q["attrs"].get(cmp_attr, 0)), 20.0, C_GOOD if q == pl else Color("2fb8e8"), 60, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(bar)
		r.add_child(cell(str(q["nick"]), 70, Color.WHITE, 12))
		r.add_child(cell("%d" % int(float(q["attrs"].get(cmp_attr, 0))), 22, Color.WHITE, 13))
		cv2.add_child(r)
	hr.add_child(cc)

func _kv_row(k: String, v: String, col: Color = Color.WHITE) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.035)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 7; sb.content_margin_bottom = 7
	p.add_theme_stylebox_override("panel", sb)
	var h := hbox(6)
	var kl := label(k, 14, Color("d6dbe3"))
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(kl)
	h.add_child(label(v, 14, col))
	p.add_child(h)
	return p

func _season_end_date(s: int) -> String:
	var start := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 1, "day": 1, "hour": 12, "minute": 0, "second": 0})
	var d := Time.get_datetime_dict_from_unix_time(start + ((s - 1) * 52 + 9) * 7 * 86400)
	return "%02d.%02d.%d" % [d["day"], d["month"], d["year"]]

func _player_contract(pl: Dictionary, right: VBoxContainer, mine: bool) -> void:
	var cb := _block(tr("Контракт"))
	right.add_child(cb)
	var c := _card()
	cb.add_child(c)
	var v := vbox(4)
	c.add_child(v)
	if not mine:
		var tm: String = str(pl.get("team", ""))
		v.add_child(_kv_row(tr("Тип контракта"), (tr("В клубе") + " · " + tm) if tm != "" else tr("Свободный агент"), C_ACC))
		if tm != "":
			v.add_child(_kv_row(tr("Конец контракта"), _season_end_date(int(pl.get("contract", {}).get("end", gs.season)))))
		v.add_child(_kv_row(tr("Ожидаемая зарплата"), "$%d / %s" % [int(pl["salary"]), tr("нед.")]))
		return
	var ct: Dictionary = pl.get("contract", {})
	v.add_child(_kv_row(tr("Тип контракта"), tr("Аренда") if str(ct.get("type", "club")) == "loan" else tr("В клубе")))
	v.add_child(_kv_row(tr("Зарплата"), "$%d / %s" % [int(pl["salary"]), tr("нед.")], C_GOOD))
	v.add_child(_kv_row(tr("Последние переговоры"), str(ct.get("signed", "01.01.2026"))))
	var end_s: int = int(ct.get("end", gs.season + 1))
	v.add_child(_kv_row(tr("Конец контракта"), _season_end_date(end_s) + "  (" + tr("сезон %d") % end_s + ")", C_BAD if end_s <= gs.season else Color.WHITE))
	v.add_child(_kv_row(tr("Мораль"), "%d%%" % int(pl.get("morale", 80)), _form_col(int(pl.get("morale", 80)))))
	var br := hbox(10)
	var ref: Dictionary = pl
	br.add_child(btn(tr("Предложить новый контракт"), func():
		contract_form = true
		cf_salary = int(ref["salary"])
		show_screen("player", false), C_GOOD))
	br.add_child(btn(tr("Удалить из команды"), func():
		gs.release_player(gs.players.find(ref))
		viewed_player = {}
		show_screen("squad"), C_BAD))
	v.add_child(br)
	if contract_form:
		var fc := _card()
		right.add_child(fc)
		var fv := vbox(8)
		fc.add_child(fv)
		fv.add_child(label(tr("Новый контракт"), 16, Color.WHITE))
		var r1 := hbox(10)
		r1.add_child(cell(tr("Срок (сезонов)"), 180, Color("d6dbe3")))
		var yo := OptionButton.new()
		for y in [1, 2, 3]:
			yo.add_item(str(y))
		yo.selected = cf_years - 1
		yo.item_selected.connect(func(i): cf_years = i + 1)
		r1.add_child(yo)
		fv.add_child(r1)
		var r2 := hbox(10)
		r2.add_child(cell(tr("Зарплата в неделю, $"), 180, Color("d6dbe3")))
		var sp := SpinBox.new()
		sp.min_value = 100
		sp.max_value = 20000
		sp.step = 50
		sp.value = cf_salary
		sp.value_changed.connect(func(x): cf_salary = int(x))
		r2.add_child(sp)
		fv.add_child(r2)
		fv.add_child(btn(tr("Отправить предложение"), func():
			var err: String = gs.offer_contract(ref, cf_years, cf_salary)
			if err != "":
				gs.add_news(err)
				contract_answer = err
			else:
				contract_answer = tr("Контракт подписан!")
				contract_form = false
			show_screen("player", false), C_GOOD))
	if contract_answer != "":
		right.add_child(_alert(contract_answer, contract_answer == tr("Контракт подписан!")))
		contract_answer = ""

var contract_answer: String = ""

func _player_transfer(pl: Dictionary, right: VBoxContainer, mine: bool) -> void:
	var tb := _block(tr("Трансфер"))
	right.add_child(tb)
	var c := _card()
	tb.add_child(c)
	var v := vbox(6)
	c.add_child(v)
	var val: int = gs.fee(pl)
	v.add_child(_kv_row(tr("Рыночная стоимость"), money_fmt(val), C_GOOD))
	var ref: Dictionary = pl
	if mine:
		v.add_child(_kv_row(tr("Сумма продажи (60%)"), money_fmt(int(val * 0.6)), C_ACC))
		var sb2 := btn(tr("Продать игрока"), func():
			gs.sell_player(gs.players.find(ref))
			viewed_player = {}
			show_screen("squad"), C_BAD)
		sb2.disabled = str(pl.get("contract", {}).get("type", "")) == "loan"
		v.add_child(sb2)
	else:
		var team: String = str(pl.get("team", ""))
		v.add_child(_kv_row(tr("Команда"), team if team != "" else tr("Свободный агент")))
		v.add_child(_kv_row(tr("Цена выкупа"), money_fmt(gs.buyout(pl)), C_GOOD))
		var row := vbox(6)
		var b := btn(tr("Купить за %s") % money_fmt(gs.buyout(pl)), func():
			var err: String = gs.buy_player(ref)
			if err != "":
				gs.add_news(err)
				contract_answer = err
				show_screen("player", false)
			else:
				show_screen("squad"), C_GOOD)
		b.disabled = gs.money < gs.buyout(pl)
		row.add_child(b)
		if team != "":
			v.add_child(_kv_row(tr("Аренда до конца сезона"), money_fmt(gs.loan_fee(pl)) if bool(pl.get("loan_ok", false)) else tr("недоступна"), C_ACC if bool(pl.get("loan_ok", false)) else C_DIM))
			var lb := btn(tr("Арендовать за %s") % money_fmt(gs.loan_fee(pl)), func():
				var err2: String = gs.loan_player(ref)
				if err2 != "":
					gs.add_news(err2)
					contract_answer = err2
					show_screen("player", false)
				else:
					show_screen("squad"), C_ACC)
			lb.disabled = not bool(pl.get("loan_ok", false)) or gs.money < gs.loan_fee(pl)
			row.add_child(lb)
		var bm := btn(tr("Убрать из закладок") if gs.is_shortlisted(pl) else tr("В закладки"), func(): gs.toggle_shortlist(ref); show_screen("player", false))
		row.add_child(bm)
		v.add_child(row)
		if contract_answer != "":
			v.add_child(_alert(contract_answer, false))
			contract_answer = ""
	var hb := _block(tr("Трансферная история"))
	right.add_child(hb)
	var hc := _card()
	hb.add_child(hc)
	var hv := vbox(4)
	hc.add_child(hv)
	var th: Array = pl.get("thist", [])
	if th.is_empty():
		hv.add_child(label(tr("Трансферов не было."), 13, C_DIM))
	for e in th:
		hv.add_child(_kv_row("%s  ·  %s → %s" % [e.get("date", ""), e.get("from", "—"), e.get("to", "—")], money_fmt(int(e.get("fee", 0))) if int(e.get("fee", 0)) > 0 else tr("свободный агент")))

func _player_stats(pl: Dictionary, right: VBoxContainer) -> void:
	var mh: Array = pl.get("mh", [])
	var k := 0; var d := 0; var a := 0; var hs := 0.0; var adr := 0.0; var kast := 0.0; var ir := 0.0
	for e in mh:
		k += int(e["k"]); d += int(e["d"]); a += int(e["a"])
		hs += float(e["hs"]) * int(e["k"]); adr += float(e["adr"]); kast += float(e["kast"]); ir += float(e["ir"])
	var n: int = mh.size()
	var top := hbox(10)
	right.add_child(top)
	var ob := _block(tr("Обзор"))
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(ob)
	var oc := _card()
	ob.add_child(oc)
	var oh := hbox(10)
	oc.add_child(oh)
	var na := tr("Н/Д")
	var lft := vbox(10)
	lft.add_child(_stat_tile("ADR", ("%.1f" % (adr / n)) if n > 0 else na, Color.WHITE))
	lft.add_child(_stat_tile("KAST", ("%d%%" % int(kast / n)) if n > 0 else na, Color.WHITE))
	oh.add_child(lft)
	var irv: float = (ir / n) if n > 0 else 0.0
	var ring := preload("res://scripts/progress_ring.gd").new().setup(clampf(irv / 2.0, 0.0, 1.0), 120, Color("2fd3c8"), "IMPACT RATING", ("%.2f" % irv) if n > 0 else na)
	oh.add_child(ring)
	var rgt := vbox(10)
	rgt.add_child(_stat_tile("KPR", ("%.2f" % (float(k) / maxf(1.0, n * 22.0))) if n > 0 else na, Color.WHITE))
	rgt.add_child(_stat_tile("K/D", ("%.2f" % (float(k) / maxf(1.0, d))) if n > 0 else na, Color.WHITE))
	oh.add_child(rgt)
	var db := _block(tr("Детали"))
	db.custom_minimum_size = Vector2(220, 0)
	top.add_child(db)
	var dc := _card()
	db.add_child(dc)
	var dv := vbox(3)
	dc.add_child(dv)
	dv.add_child(_kv_row(tr("Сыграно матчей"), str(n)))
	dv.add_child(_kv_row(tr("Всего убийств"), str(k)))
	dv.add_child(_kv_row(tr("Хедшоты %"), ("%.1f%%" % (hs / maxf(1.0, k))) if k > 0 else "0%"))
	dv.add_child(_kv_row(tr("Всего смертей"), str(d)))
	dv.add_child(_kv_row("K/D", "%.2f" % (float(k) / maxf(1.0, d))))
	dv.add_child(_kv_row(tr("Всего ассистов"), str(a)))
	# турниры
	var tb := _block(tr("История турниров"))
	right.add_child(tb)
	var tc := _card()
	tb.add_child(tc)
	var tv := vbox(3)
	tc.add_child(tv)
	var hh := hbox(6)
	for e in [[tr("Турнир"), 130], [tr("Сезон"), 50], [tr("Матчи"), 50], ["K", 40], ["D", 40], ["A", 40], ["ADR", 50], ["HS%", 46], ["IR", 44]]:
		hh.add_child(cell(e[0], e[1], C_ACC, 12))
	tv.add_child(hh)
	var agg := {}
	for e in mh:
		var key: String = "%s|%d" % [e.get("tour", ""), int(e.get("season", 1))]
		if not agg.has(key):
			agg[key] = {"t": e.get("tour", ""), "s": int(e.get("season", 1)), "n": 0, "k": 0, "d": 0, "a": 0, "adr": 0.0, "hs": 0.0, "ir": 0.0}
		var g: Dictionary = agg[key]
		g["n"] += 1; g["k"] += int(e["k"]); g["d"] += int(e["d"]); g["a"] += int(e["a"]); g["adr"] += float(e["adr"]); g["hs"] += float(e["hs"]); g["ir"] += float(e["ir"])
	if agg.is_empty():
		tv.add_child(label(tr("Нет данных о турнирах"), 14, C_DIM))
	for key in agg:
		var g: Dictionary = agg[key]
		var r := hbox(6)
		for x in [[str(g["t"]), 130], [str(g["s"]), 50], [str(g["n"]), 50], [str(g["k"]), 40], [str(g["d"]), 40], [str(g["a"]), 40], ["%.1f" % (g["adr"] / g["n"]), 50], ["%d%%" % int(g["hs"] / g["n"]), 46], ["%.2f" % (g["ir"] / g["n"]), 44]]:
			r.add_child(cell(x[0], x[1], Color.WHITE, 13))
		tv.add_child(r)
	# матчи
	var mb := _block(tr("История матчей"))
	right.add_child(mb)
	var mc := _card()
	mb.add_child(mc)
	var mv := vbox(3)
	mc.add_child(mv)
	var mh2 := hbox(6)
	for e in [[tr("Счёт"), 46], [tr("Соперник"), 120], ["KAST", 46], ["K", 32], ["D", 32], ["A", 32], ["ADR", 46], ["HS%", 42], ["1vX", 34], ["IR", 40]]:
		mh2.add_child(cell(e[0], e[1], C_ACC, 12))
	mv.add_child(mh2)
	if mh.is_empty():
		mv.add_child(label(tr("Нет данных о матчах"), 14, C_DIM))
	for e in mh.slice(0, 10):
		var r2 := hbox(6)
		r2.add_child(cell(str(e["score"]), 46, C_GOOD if bool(e["won"]) else C_BAD, 13))
		var oc2 := cell(str(e["opp"]), 120, Color.WHITE, 13)
		oc2.clip_text = true
		r2.add_child(oc2)
		for x in [["%d%%" % int(e["kast"]), 46], [str(e["k"]), 32], [str(e["d"]), 32], [str(e["a"]), 32], ["%.1f" % float(e["adr"]), 46], ["%d%%" % int(e["hs"]), 42], [str(e["clutch"]), 34], ["%.2f" % float(e["ir"]), 40]]:
			r2.add_child(cell(x[0], x[1], Color.WHITE, 13))
		mv.add_child(r2)

func table_header() -> HBoxContainer:
	var h := hbox(4)
	h.add_child(cell("#", 30, C_DIM)); h.add_child(cell(tr("Команда"), 220, C_DIM)); h.add_child(cell(tr("В"), 40, C_DIM)); h.add_child(cell(tr("П"), 40, C_DIM)); h.add_child(cell(tr("Раунды ±"), 80, C_DIM))
	return h

func table_row(pos: int, team: String) -> HBoxContainer:
	var s: Dictionary = gs.standings[team]
	var mine: bool = team == gs.team_name
	var col: Color = C_ACC if mine else (Color.WHITE if pos <= 4 else C_DIM)
	var h := hbox(4)
	h.add_child(cell(str(pos), 30, col)); h.add_child(cell(team, 220, col)); h.add_child(cell(str(int(s["w"])), 40, col)); h.add_child(cell(str(int(s["l"])), 40, col)); h.add_child(cell(("+" if int(s["rd"]) > 0 else "") + str(int(s["rd"])), 80, col))
	return h

func on_finish_week() -> void:
	var was_off: bool = gs.week > 9
	var rep_txt: String = gs.finish_week()
	show_screen("dashboard")
	if gs.game_over == "" and rep_txt != "":
		gs.add_news(rep_txt)
		refresh_top()

# ------------------------------------------------------------ общие элементы разделов

func _hdr_card(icon: String, t: String, sub: String, right: Control = null) -> PanelContainer:
	var c := _card()
	var h := hbox(14)
	c.add_child(h)
	var ib := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	var tc := Color(gs.team_color)
	isb.bg_color = Color(tc.r, tc.g, tc.b, 0.22)
	isb.set_corner_radius_all(10)
	isb.set_content_margin_all(10)
	ib.add_theme_stylebox_override("panel", isb)
	ib.add_child(UITheme.icon(icon, 30, tc.lightened(0.3)))
	h.add_child(ib)
	var v := vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(label(t, 22, Color.WHITE))
	v.add_child(label(sub, 13, C_DIM))
	h.add_child(v)
	if right != null:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(right)
	return c

func _stat_tile(t: String, val: String, col: Color = Color.WHITE, icon: String = "") -> PanelContainer:
	var c := _card()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := hbox(10)
	c.add_child(h)
	if icon != "":
		h.add_child(UITheme.icon(icon, 26, C_DIM))
	var v := vbox(0)
	v.add_child(label(t.to_upper(), 11, C_DIM))
	v.add_child(label(val, 22, col))
	h.add_child(v)
	return c

func _sel_card(icon: String, t: String, desc: String, selected: bool, cb: Callable, accent: Color = C_ACC) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.18) if selected else Color(0.09, 0.12, 0.17, 0.88)
	sb.border_color = accent if selected else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := vbox(6)
	card.add_child(v)
	var h := hbox(8)
	h.add_child(UITheme.icon(icon, 26, accent if selected else Color("c9ced8")))
	var tl := label(t, 14, Color.WHITE)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(110, 0)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tl)
	if selected:
		h.add_child(UITheme.icon("check_circle", 20, accent))
	v.add_child(h)
	var d := label(desc, 12, C_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(140, 0)
	v.add_child(d)
	var hit := Button.new()
	hit.flat = true
	for st in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(st, _flat_style())
	if not selected:
		hit.mouse_entered.connect(func(): sb.border_color = Color(accent.r, accent.g, accent.b, 0.6))
		hit.mouse_exited.connect(func(): sb.border_color = Color(1, 1, 1, 0.08))
	hit.pressed.connect(cb)
	card.add_child(hit)
	_ignore_mouse(v)
	return card

func _bar(v: float, mx: float, col: Color, w: int = 120, h: int = 8) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = mx
	b.value = v
	b.show_percentage = false
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fs := StyleBoxFlat.new()
	fs.bg_color = col
	fs.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fs)
	return b

func _form_col(f: int) -> Color:
	return C_GOOD if f >= 70 else (C_ACC if f >= 45 else C_BAD)

# ------------------------------------------------------------ почта

var mail_sel: int = 0
var mail_tab: String = "all"

func _mail_view() -> Array:
	var res: Array = []
	for i in gs.mail.size():
		var k: String = str(gs.mail[i].get("kind", "info"))
		if mail_tab == "in" and k == "out": continue
		if mail_tab == "out" and k != "out": continue
		res.append(i)
	return res

func screen_mail() -> void:
	var view: Array = _mail_view()
	if not view.has(mail_sel) and not view.is_empty():
		mail_sel = view[0]
	if not gs.mail.is_empty() and mail_sel < gs.mail.size():
		gs.mail[mail_sel]["read"] = true
	var bar := hbox(14)
	for tb in [["all", tr("Все"), ""], ["in", tr("Входящие"), "south"], ["out", tr("Исходящие"), "north"]]:
		var key: String = tb[0]
		var b := text_btn(tb[1], func(): mail_tab = key; show_screen("mail", false), 16, C_ACC if mail_tab == key else Color.WHITE)
		bar.add_child(b)
	bar.add_child(label("|", 16, C_DIM))
	bar.add_child(UITheme.icon("drafts", 18, C_DIM))
	bar.add_child(text_btn(tr("Прочитать все"), func():
		for ml in gs.mail: ml["read"] = true
		show_screen("mail", false), 15))
	bar.add_child(UITheme.icon("delete", 18, C_DIM))
	bar.add_child(text_btn(tr("Удалить все"), func(): gs.mail.clear(); mail_sel = 0; show_screen("mail", false), 15))
	bar.add_child(spacer())
	bar.add_child(label(tr("Писем: %d") % view.size(), 13, C_DIM))
	content.add_child(bar)
	if view.is_empty():
		var c0 := _card()
		c0.add_child(label(tr("Писем нет."), 14, C_DIM))
		content.add_child(c0)
		return
	var cols := hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var lc := _card()
	lc.custom_minimum_size = Vector2(380, 520)
	cols.add_child(lc)
	var lsc := ScrollContainer.new()
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lc.add_child(lsc)
	var lv := vbox(6)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(lv)
	var kind_col := {"good": C_GOOD, "bad": C_BAD, "info": Color("5aa9ff"), "news": Color("b18cff"), "transfer": C_ACC, "invite": Color("2fd3c8"), "result": Color("f5c518"), "out": C_DIM}
	var kind_icon := {"good": "verified", "bad": "warning", "info": "info", "news": "newspaper", "transfer": "swap_horiz", "invite": "confirmation_number", "result": "emoji_events", "out": "north_east"}
	for i in view:
		var ml: Dictionary = gs.mail[i]
		var k: String = str(ml.get("kind", "info"))
		var row := PanelContainer.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(0.2, 0.45, 0.85, 0.28) if i == mail_sel else Color(1, 1, 1, 0.035)
		rs.border_width_left = 4
		rs.border_color = kind_col.get(k, Color("5aa9ff"))
		rs.set_corner_radius_all(8)
		rs.set_content_margin_all(10)
		row.add_theme_stylebox_override("panel", rs)
		var rh := hbox(10)
		row.add_child(rh)
		rh.add_child(UITheme.icon(kind_icon.get(k, "mail"), 24, kind_col.get(k, Color("5aa9ff"))))
		var rv := vbox(1)
		rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := hbox(6)
		top.add_child(label(str(ml.get("to", ml["from"])) if k == "out" else str(ml["from"]), 13, Color.WHITE))
		top.add_child(spacer())
		var age: int = (gs.season * 100 + gs.week) - (int(ml["season"]) * 100 + int(ml["week"]))
		top.add_child(label(tr("Сегодня") if age == 0 else tr("Нед. %d") % int(ml["week"]), 11, C_DIM))
		rv.add_child(top)
		var sl := label(str(ml["subject"]), 13, kind_col.get(k, Color("5aa9ff")).lightened(0.2))
		sl.clip_text = true
		sl.custom_minimum_size = Vector2(280, 0)
		if not bool(ml["read"]):
			sl.add_theme_font_override("font", UITheme.bold())
		rv.add_child(sl)
		var pv := label(str(ml["body"]).replace("\n", " "), 11, C_DIM)
		pv.clip_text = true
		pv.custom_minimum_size = Vector2(280, 0)
		rv.add_child(pv)
		rh.add_child(rv)
		var hit := Button.new()
		hit.flat = true
		for st in ["normal", "hover", "pressed", "focus"]:
			hit.add_theme_stylebox_override(st, _flat_style())
		var idx: int = i
		hit.pressed.connect(func(): mail_sel = idx; show_screen("mail", false))
		row.add_child(hit)
		_ignore_mouse(rh)
		lv.add_child(row)
	var ml2: Dictionary = gs.mail[mail_sel]
	var rc := _card()
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(rc)
	var rv2 := vbox(12)
	rc.add_child(rv2)
	var hh := hbox(14)
	var from: String = str(ml2["from"])
	var is_board: bool = ["Совет директоров", "Board of directors"].has(from) or from == tr("Совет директоров")
	if is_board and tex(gs.team_logo) != null:
		hh.add_child(_circle(gs.team_logo, 70, Color(gs.team_color)))
	else:
		var ib := PanelContainer.new()
		var isb := StyleBoxFlat.new()
		isb.bg_color = Color(1, 1, 1, 0.06)
		isb.set_corner_radius_all(35)
		isb.set_content_margin_all(14)
		ib.add_theme_stylebox_override("panel", isb)
		ib.add_child(UITheme.icon(kind_icon.get(str(ml2.get("kind", "info")), "mail"), 40, kind_col.get(str(ml2.get("kind", "info")), Color.WHITE)))
		hh.add_child(ib)
	var hv := vbox(2)
	hv.add_child(label(from, 22, Color.WHITE))
	var addr := hbox(6)
	addr.add_child(_flag(gs.team_country, 20))
	addr.add_child(label("%s@%s.gg" % [_slug(from), gs.team_tag.to_lower()], 13, C_DIM))
	hv.add_child(addr)
	hv.add_child(label(str(ml2["subject"]), 14, Color("5aa9ff")))
	hh.add_child(hv)
	hh.add_child(spacer())
	hh.add_child(label(tr("Сезон %d · нед. %d") % [int(ml2["season"]), int(ml2["week"])], 12, C_DIM))
	rv2.add_child(hh)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.1)
	sep.custom_minimum_size = Vector2(0, 1)
	rv2.add_child(sep)
	var greet: String = tr("Уважаемая %s,") if gs.coach_gender == "f" else tr("Уважаемый %s,")
	if str(ml2.get("kind", "")) != "out":
		rv2.add_child(label(greet % gs.coach_name, 15, Color("5aa9ff")))
	rv2.add_child(wrap_label(str(ml2["body"]), 15, Color("e3e7ee"), 560))
	if str(ml2.get("kind", "")) != "out":
		var sig := vbox(0)
		sig.add_child(label(tr("С уважением,"), 14, Color("c9ced8")))
		sig.add_child(label(from, 14, Color.WHITE))
		sig.add_child(label(gs.team_name, 13, Color("5aa9ff")))
		rv2.add_child(sig)
	refresh_top()

func _slug(s: String) -> String:
	var map := {"Совет директоров": "board", "Аналитический отдел": "analytics", "Медицинский штаб": "medical", "Отдел кадров": "hr", "Новости киберспорта": "news", "Трансферный рынок": "transfers", "Оргкомитет лиги": "league"}
	for k in map:
		if tr(k) == s or k == s:
			return map[k]
	return "info"

# ------------------------------------------------------------ разговор

var talk_sel: int = 0

func screen_talk() -> void:
	if gs.talks.is_empty():
		content.add_child(_hdr_card("forum", tr("Разговор"), tr("Здесь вам пишут скаут, тренер и игроки.")))
		var c0 := _card()
		c0.add_child(label(tr("Пока никто не писал. Сообщения появляются по ходу недель."), 14, C_DIM))
		content.add_child(c0)
		return
	talk_sel = clampi(talk_sel, 0, gs.talks.size() - 1)
	var cols := hbox(12)
	content.add_child(cols)
	var lc := _card()
	lc.custom_minimum_size = Vector2(330, 520)
	cols.add_child(lc)
	var lv := vbox(6)
	lc.add_child(lv)
	for i in mini(gs.talks.size(), 10):
		var t2: Dictionary = gs.talks[i]
		var row := PanelContainer.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(0.2, 0.45, 0.85, 0.28) if i == talk_sel else Color(1, 1, 1, 0.035)
		rs.set_corner_radius_all(8)
		rs.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", rs)
		var rh := hbox(10)
		row.add_child(rh)
		rh.add_child(_circle(str(t2.get("photo", "")), 44))
		var rv := vbox(0)
		rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rv.add_child(label(str(t2["who"]), 14, Color.WHITE))
		rv.add_child(label(str(t2["role"]), 11, C_ACC))
		var pv := label(str(t2["text"]), 11, C_DIM)
		pv.clip_text = true
		pv.custom_minimum_size = Vector2(200, 0)
		rv.add_child(pv)
		rh.add_child(rv)
		if int(t2["answer"]) < 0:
			rh.add_child(UITheme.icon("fiber_manual_record", 12, C_ACC))
		var hit := Button.new()
		hit.flat = true
		for st in ["normal", "hover", "pressed", "focus"]:
			hit.add_theme_stylebox_override(st, _flat_style())
		var idx: int = i
		hit.pressed.connect(func(): talk_sel = idx; show_screen("talk", false))
		row.add_child(hit)
		_ignore_mouse(rh)
		lv.add_child(row)
	var t3: Dictionary = gs.talks[talk_sel]
	var rc := _card()
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(rc)
	var cv := vbox(14)
	rc.add_child(cv)
	var hh := hbox(12)
	hh.add_child(_circle(str(t3.get("photo", "")), 60, Color(gs.team_color)))
	var hv := vbox(0)
	hv.add_child(label(str(t3["who"]), 20, Color.WHITE))
	hv.add_child(label(str(t3["role"]) + " · " + gs.team_name, 12, C_ACC))
	hh.add_child(hv)
	cv.add_child(hh)
	cv.add_child(_bubble(str(t3["text"]), false))
	if int(t3["answer"]) >= 0:
		cv.add_child(_bubble(str(t3["options"][int(t3["answer"])]["t"]), true))
	else:
		cv.add_child(label(tr("Ваш ответ:"), 12, C_DIM))
		for oi in t3["options"].size():
			var o: Dictionary = t3["options"][oi]
			var ti: int = talk_sel
			var oo: int = oi
			var b := btn(str(o["t"]), func(): gs.answer_talk(ti, oo); show_screen("talk", false))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			cv.add_child(b)

func _bubble(t: String, mine: bool) -> Control:
	var row := hbox(0)
	if mine:
		row.add_child(spacer())
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.45, 0.85, 0.55) if mine else Color(1, 1, 1, 0.07)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(wrap_label(t, 14, Color.WHITE, 440))
	row.add_child(p)
	if not mine:
		row.add_child(spacer())
	return row

# ------------------------------------------------------------ состав

const ROLE_TAGS := {"Капитан": ["IGL", "RIFLER"], "Снайпер": ["AWPER"], "Энтри": ["RIFLER", "ENTRY"], "Саппорт": ["RIFLER", "SUPPORT"], "Лурк": ["RIFLER", "LURKER"]}

func _team_cohesion() -> Dictionary:
	var f: float = 0.0
	var mo: float = 0.0
	var cnt := {}
	for p in gs.players:
		f += float(p["form"])
		mo += float(p.get("morale", 80))
		var c: String = str(p.get("country", "xx"))
		cnt[c] = int(cnt.get(c, 0)) + 1
	var n: float = maxf(1.0, gs.players.size())
	var mx: int = 0
	for c in cnt:
		mx = maxi(mx, int(cnt[c]))
	return {"form": f / n, "morale": mo / n, "lang": 100.0 * float(mx) / n}

func _player_card(pl: Dictionary, starter: bool, idx: int) -> Control:
	var tc := Color(gs.team_color)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	sb.border_color = Color(tc.r, tc.g, tc.b, 0.55) if starter else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 4 if starter else 1
	sb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := vbox(4)
	card.add_child(v)
	var tags := hbox(5)
	var mt := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top"]:
		mt.add_theme_constant_override(m, 8)
	mt.add_child(tags)
	for tg in _role_tags(pl):
		tags.add_child(label(tg, 11, Color("f5c518") if tg == "IGL" else Color.WHITE))
	tags.add_child(spacer())
	if bool(pl.get("captain", false)):
		tags.add_child(UITheme.icon("military_tech", 18, Color("f5c518")))
	v.add_child(mt)
	var ph := Control.new()
	ph.custom_minimum_size = Vector2(0, 150)
	ph.clip_contents = true
	var bgc := ColorRect.new()
	bgc.color = Color(tc.r, tc.g, tc.b, 0.18)
	bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
	ph.add_child(bgc)
	var img := TextureRect.new()
	img.texture = tex(player_photo(pl))
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	ph.add_child(img)
	var fl := _flag(str(pl.get("country", "xx")), 26)
	fl.position = Vector2(8, 6)
	ph.add_child(fl)
	v.add_child(ph)
	var iv := vbox(3)
	var mi := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_bottom"]:
		mi.add_theme_constant_override(m, 8)
	mi.add_child(iv)
	var nm: String = str(pl["nick"])
	var full: String = "%s \"%s\" %s" % [tr(str(pl.get("first", ""))), nm, tr(str(pl.get("last", "")))]
	var nb := _nick_link(pl, 0, Color.WHITE)
	nb.text = full.strip_edges() if str(pl.get("first", "")) != "" else nm
	nb.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nb.add_theme_font_size_override("font_size", 12)
	nb.clip_text = true
	nb.custom_minimum_size = Vector2(60, 0)
	iv.add_child(nb)
	var badges := hbox(6)
	badges.alignment = BoxContainer.ALIGNMENT_CENTER
	var inj: bool = int(pl["inj"]) > 0
	badges.add_child(_badge(tr("Травма") if inj else tr("Активен"), C_BAD if inj else C_GOOD))
	var mo: int = int(pl.get("morale", 80))
	badges.add_child(_badge(tr("Счастлив") if mo >= 70 else (tr("Спокоен") if mo >= 45 else tr("Недоволен")), C_GOOD if mo >= 70 else (C_ACC if mo >= 45 else C_BAD)))
	iv.add_child(badges)
	var sr := hbox(6)
	sr.add_child(_stars(_player_stars(pl), 12))
	sr.add_child(label(str(gs.ovr(pl)), 14, stat_color(gs.ovr(pl))))
	sr.add_child(spacer())
	sr.add_child(label(tr("Форма") + " %d%%" % int(pl["form"]), 11, _form_col(int(pl["form"]))))
	iv.add_child(sr)
	var cap := CheckBox.new()
	cap.text = tr("Назначить капитаном")
	cap.add_theme_font_size_override("font_size", 11)
	cap.button_pressed = bool(pl.get("captain", false))
	var ref: Dictionary = pl
	cap.pressed.connect(func(): gs.set_captain(ref); show_screen("squad", false))
	iv.add_child(cap)
	var ar := hbox(4)
	ar.alignment = BoxContainer.ALIGNMENT_CENTER
	ar.add_child(icon_btn("arrow_back", tr("Левее"), func(): gs.move_player(idx, -1); show_screen("squad", false)))
	ar.add_child(icon_btn("arrow_forward", tr("Правее"), func(): gs.move_player(idx, 1); show_screen("squad", false)))
	var mv := icon_btn("south" if starter else "north", tr("В запас") if starter else tr("В основу"), func():
		gs.move_player(idx, (5 - idx) if starter else (4 - idx) if idx > 4 else 0)
		show_screen("squad", false))
	ar.add_child(mv)
	iv.add_child(ar)
	v.add_child(mi)
	return card

func _badge(t: String, c: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c.r, c.g, c.b, 0.12)
	sb.border_color = c
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6; sb.content_margin_right = 6; sb.content_margin_top = 1; sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(t, 11, c))
	return p

func screen_squad() -> void:
	var ch: Dictionary = _team_cohesion()
	var info := _block(tr("Инфо о команде"))
	content.add_child(info)
	var ic := _card()
	info.add_child(ic)
	var ih := hbox(16)
	ic.add_child(ih)
	if tex(gs.team_logo) != null:
		ih.add_child(pic(gs.team_logo, 70))
	var iv := vbox(4)
	var nr := hbox(10)
	nr.add_child(_flag(gs.team_country, 28))
	nr.add_child(label(gs.team_name, 26, Color.WHITE))
	var rl: Array = gs.rankoff_list()
	nr.add_child(label(tr("#%d мировой рейтинг | %d очков Rankoff") % [rl.find(gs.team_name) + 1, int(gs.rankoff.get(gs.team_name, 0))], 13, C_DIM))
	iv.add_child(nr)
	var avg: float = 0.0
	for p in gs.lineup():
		avg += gs.ovr(p)
	avg /= maxf(1.0, gs.lineup().size())
	iv.add_child(_stars(clampf((avg - 35.0) / 9.0, 0.5, 5.0), 18))
	ih.add_child(iv)
	ih.add_child(spacer())
	for e in [[tr("Физическое состояние"), ch["form"]], [tr("Моральный дух"), ch["morale"]], [tr("Языковая сплочённость"), ch["lang"]]]:
		var bv := vbox(2)
		bv.add_child(label(e[0], 11, C_DIM))
		var bh := hbox(6)
		bh.add_child(label("%d%%" % int(e[1]), 13, Color.WHITE))
		bh.add_child(_bar(float(e[1]), 100.0, _form_col(int(e[1])), 70))
		bv.add_child(bh)
		bv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ih.add_child(bv)
	var lu: Array = gs.lineup()
	var mb := _block(tr("Основной состав"))
	content.add_child(mb)
	var mr := hbox(10)
	mb.add_child(mr)
	var bench: Array = []
	for i in gs.players.size():
		var p: Dictionary = gs.players[i]
		if lu.has(p):
			mr.add_child(_player_card(p, true, i))
		else:
			bench.append(i)
	for k in range(lu.size(), 5):
		mr.add_child(_empty_slot())
	var bb := _block(tr("Запасной состав"))
	content.add_child(bb)
	var br := hbox(10)
	bb.add_child(br)
	for i in bench:
		br.add_child(_player_card(gs.players[i], false, i))
	for k in range(bench.size(), 5):
		br.add_child(_empty_slot())

func _empty_slot() -> Control:
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.025)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	c.add_theme_stylebox_override("panel", sb)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(0, 290)
	return c

# ------------------------------------------------------------ штат

var viewed_staff: Dictionary = {}

func _staff_card(role_t: String, name_t: String, photo: String, country: String, stars: float, active: bool, cb: Callable) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := vbox(4)
	card.add_child(v)
	var mt := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top"]:
		mt.add_theme_constant_override(m, 8)
	var th := vbox(2)
	th.add_child(label(role_t.to_upper(), 12, Color.WHITE))
	if country != "":
		th.add_child(_flag(country, 24))
	mt.add_child(th)
	v.add_child(mt)
	var ph := Control.new()
	ph.custom_minimum_size = Vector2(0, 140)
	ph.clip_contents = true
	var img := TextureRect.new()
	img.texture = tex(photo) if photo != "" else tex("res://assets/ui/silhouette.png")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	if photo == "":
		img.modulate = Color(1, 1, 1, 0.35)
	ph.add_child(img)
	v.add_child(ph)
	var mi := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_bottom"]:
		mi.add_theme_constant_override(m, 8)
	var iv := vbox(4)
	mi.add_child(iv)
	var nl := label(name_t, 14, Color.WHITE)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.clip_text = true
	iv.add_child(nl)
	if stars > 0:
		var st := _stars(stars, 13)
		st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		iv.add_child(st)
	var bd := hbox(6)
	bd.alignment = BoxContainer.ALIGNMENT_CENTER
	if active:
		bd.add_child(_badge(tr("Активен"), C_GOOD))
		bd.add_child(_badge(tr("Счастлив"), C_GOOD))
	else:
		bd.add_child(_badge(tr("Вакансия"), C_DIM))
	iv.add_child(bd)
	v.add_child(mi)
	var hit := Button.new()
	hit.flat = true
	for st2 in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(st2, _flat_style())
	hit.mouse_entered.connect(func(): sb.border_color = Color(1, 0.7, 0.24, 0.6))
	hit.mouse_exited.connect(func(): sb.border_color = Color(1, 1, 1, 0.08))
	hit.pressed.connect(cb)
	card.add_child(hit)
	_ignore_mouse(v)
	return card

func screen_staff() -> void:
	var sb := _block(tr("Штат"))
	content.add_child(sb)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sb.add_child(grid)
	grid.add_child(_staff_card(tr("Генеральный директор"), "%s \"%s\"" % [gs.coach_name, gs.coach_nick] if gs.coach_nick != "" else gs.coach_name, gs.photo_path, gs.coach_country_code, 0.0, true, func(): show_screen("coach")))
	for role in gs.STAFF_ROLES:
		var found: Dictionary = {}
		for s in gs.staff_list:
			if s["role"] == role:
				found = s
		var role_t: String = tr(gs.STAFF_ROLES[role][0])
		if not found.is_empty():
			var ref: Dictionary = found
			grid.add_child(_staff_card(role_t, str(found["name"]), str(found.get("photo", "")), str(found.get("country", "")), gs.staff_stars(found), true, func(): viewed_staff = ref; show_screen("staff_member")))
		else:
			var rk: String = role
			grid.add_child(_staff_card(role_t, tr("Нанять"), "", "", 0.0, false, func(): staff_hire_role = rk; show_screen("staff_hire")))

var staff_hire_role: String = ""

func screen_staff_hire() -> void:
	var role: String = staff_hire_role
	content.add_child(_hdr_card("person_add", tr("Найм: %s") % tr(gs.STAFF_ROLES.get(role, ["?"])[0]), tr(gs.STAFF_ROLES.get(role, ["", ""])[1]), small_btn("<  " + tr("Назад"), func(): _hist_move(-1))))
	var cands: Array = []
	for i in gs.staff_market.size():
		if gs.staff_market[i]["role"] == role:
			cands.append(i)
	if cands.is_empty():
		gs.staff_market.append(gs.gen_staff(role))
		gs.staff_market.append(gs.gen_staff(role))
		cands = [gs.staff_market.size() - 2, gs.staff_market.size() - 1]
	var row := hbox(12)
	content.add_child(row)
	for i in cands:
		var s: Dictionary = gs.staff_market[i]
		var c := _card()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := vbox(8)
		c.add_child(v)
		var h := hbox(12)
		h.add_child(_circle(str(s["photo"]), 80))
		var hv := vbox(2)
		hv.add_child(label(str(s["name"]), 18, Color.WHITE))
		hv.add_child(_stars(gs.staff_stars(s), 16))
		hv.add_child(label(tr("Подъёмные %s · $%d / нед.") % [money_fmt(int(s["fee"])), int(s["salary"])], 12, C_DIM))
		h.add_child(hv)
		v.add_child(h)
		for e in gs.STAFF_TECH.get(role, []):
			var val: float = float(s["attrs"].get(e[0], 0))
			var r := hbox(8)
			r.add_child(cell(tr(e[1]), 170, Color("d6dbe3"), 13))
			var b := _bar(val, 20.0, _attr_color(val), 120, 8)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(b)
			r.add_child(cell("%.1f" % val, 40, _attr_color(val), 13))
			v.add_child(r)
		var ii: int = i
		var hb := btn(tr("Нанять"), func():
			var err: String = gs.hire_staff(ii)
			if err != "":
				gs.add_news(err)
			show_screen("staff"), C_GOOD)
		hb.disabled = gs.money < int(s["fee"])
		v.add_child(hb)
		row.add_child(c)

func screen_staff_member() -> void:
	var s: Dictionary = viewed_staff
	if s.is_empty():
		screen_staff()
		return
	var hc := _card()
	content.add_child(hc)
	var hh := hbox(18)
	hc.add_child(hh)
	hh.add_child(_circle(str(s.get("photo", "")), 110, Color(gs.team_color)))
	var hv := vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := hbox(10)
	nr.add_child(_flag(str(s.get("country", "xx")), 28))
	nr.add_child(label(str(s["name"]), 28, Color.WHITE))
	hv.add_child(nr)
	hv.add_child(label(tr(gs.STAFF_ROLES[s["role"]][0]) + " · " + gs.team_name, 15, C_ACC))
	hv.add_child(_stars(gs.staff_stars(s), 18))
	hv.add_child(label(tr(gs.STAFF_ROLES[s["role"]][1]), 13, C_DIM))
	hv.add_child(label(tr("Зарплата") + " $%d / %s" % [int(s["salary"]), tr("нед.")], 13, C_DIM))
	hh.add_child(hv)
	var bv := vbox(6)
	bv.add_child(small_btn("<  " + tr("Назад"), func(): _hist_move(-1)))
	var idx: int = gs.staff_list.find(s)
	if idx >= 0:
		bv.add_child(small_btn(tr("Уволить"), func(): gs.fire_staff(idx); viewed_staff = {}; show_screen("staff"), C_BAD))
	hh.add_child(bv)
	var ab := _block(tr("Характеристики"))
	content.add_child(ab)
	var ac := _card()
	ab.add_child(ac)
	var cols := hbox(14)
	ac.add_child(cols)
	for grp in [[tr("ТЕХНИЧЕСКИЕ"), gs.STAFF_TECH.get(s["role"], [])], [tr("МЕНТАЛЬНЫЕ"), gs.STAFF_MENTAL], [tr("ФИЗИЧЕСКИЕ"), gs.STAFF_PHYS]]:
		var cv := vbox(3)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := PanelContainer.new()
		var hs := StyleBoxFlat.new()
		hs.bg_color = Color(1, 1, 1, 0.06)
		hs.set_content_margin_all(8)
		head.add_theme_stylebox_override("panel", hs)
		head.add_child(label(grp[0], 15, Color.WHITE))
		cv.add_child(head)
		for a in grp[1]:
			var v: float = float(s["attrs"].get(a[0], 0))
			var row := PanelContainer.new()
			var rs := StyleBoxFlat.new()
			rs.bg_color = Color(1, 1, 1, 0.025)
			rs.content_margin_left = 10; rs.content_margin_right = 10; rs.content_margin_top = 6; rs.content_margin_bottom = 6
			row.add_theme_stylebox_override("panel", rs)
			var rh := hbox(6)
			row.add_child(rh)
			var nl := label(tr(a[1]), 15, Color("e9edf3"))
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rh.add_child(nl)
			rh.add_child(label("%.2f" % v, 16, _attr_color(v)))
			cv.add_child(row)
		cols.add_child(cv)

# ------------------------------------------------------------ тренировка

var train_tab: String = "coach"
var train_pick: Dictionary = {}

func screen_training() -> void:
	var tabs := hbox(18)
	for tb in [["coach", tr("Тренер")], ["maps", tr("Тренировка карт")], ["psych", tr("Психолог")], ["physio", tr("Физиотерапевт")]]:
		var key: String = tb[0]
		var need: bool = key != "maps" and not gs.group_active(key)
		var h := hbox(4)
		h.add_child(text_btn(tb[1], func(): train_tab = key; train_pick = {}; show_screen("training", false), 16, C_ACC if train_tab == key else Color.WHITE))
		if need:
			h.add_child(UITheme.icon("error", 16, C_BAD))
		tabs.add_child(h)
	content.add_child(tabs)
	if train_tab == "maps":
		_train_maps()
	else:
		_train_group(train_tab)

func _group_staff(grp: String) -> Dictionary:
	for s in gs.staff_list:
		if s["role"] == grp:
			return s
	return {}

func _train_group(grp: String) -> void:
	var row := hbox(12)
	content.add_child(row)
	var st: Dictionary = _group_staff(grp)
	var active: bool = gs.group_active(grp)
	var cc := _card()
	cc.custom_minimum_size = Vector2(260, 0)
	row.add_child(cc)
	var cv := vbox(6)
	cc.add_child(cv)
	var ph := TextureRect.new()
	ph.texture = tex(str(st.get("photo", ""))) if not st.is_empty() else tex("res://assets/ui/silhouette.png")
	ph.custom_minimum_size = Vector2(0, 150)
	ph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if st.is_empty():
		ph.modulate = Color(1, 1, 1, 0.35)
	cv.add_child(ph)
	var nl := label(str(st.get("name", tr("Вакансия"))), 16, Color.WHITE)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(nl)
	var rl := label(tr(gs.STAFF_ROLES[grp][0]), 12, C_ACC)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(rl)
	var head := PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.2, 0.45, 0.85, 0.45)
	hs.set_content_margin_all(5)
	head.add_theme_stylebox_override("panel", hs)
	var hl := label(tr("ТЕХНИЧЕСКИЕ"), 13, Color.WHITE)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(hl)
	cv.add_child(head)
	for e in gs.STAFF_TECH[grp]:
		var v: float = float(st.get("attrs", {}).get(e[0], 0))
		var r := hbox(4)
		var al := label(tr(e[1]), 13, Color("d6dbe3"))
		al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(al)
		r.add_child(label(("%.2f" % v) if not st.is_empty() else "—", 13, _attr_color(v)))
		cv.add_child(r)
	if not active:
		cv.add_child(_alert(tr("Нет сотрудника — наймите в «Штате»."), false))
		cv.add_child(small_btn(tr("Нанять"), func(): staff_hire_role = grp; show_screen("staff_hire"), C_GOOD))
	var ab := btn(tr("АВТОРАСПИСАНИЕ"), func(): gs.auto_schedule(grp); show_screen("training", false), Color("2fb8e8"))
	ab.disabled = not active
	cv.add_child(ab)
	cv.add_child(label(tr("До %d характеристик на игрока. Авто — 3 худших.") % gs.TRAIN_MAX, 11, C_DIM))
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 540)
	row.add_child(sc)
	var pr := hbox(10)
	sc.add_child(pr)
	for p in gs.players:
		pr.add_child(_train_player_col(p, grp, active))

func _train_player_col(p: Dictionary, grp: String, active: bool) -> Control:
	gs.ensure_attrs(p)
	var trn: Dictionary = gs.ptrain(p)
	var lst: Array = trn[grp]
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	c.add_theme_stylebox_override("panel", sb)
	c.custom_minimum_size = Vector2(150, 520)
	var v := vbox(7)
	c.add_child(v)
	var ph := Control.new()
	ph.custom_minimum_size = Vector2(130, 100)
	ph.clip_contents = true
	var img := TextureRect.new()
	img.texture = tex(player_photo(p))
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	ph.add_child(img)
	var fl := _flag(str(p.get("country", "xx")), 22)
	fl.position = Vector2(2, 2)
	ph.add_child(fl)
	v.add_child(ph)
	var nl := label(str(p["nick"]), 15, Color.WHITE)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	var rl := label(" · ".join(_role_tags(p)), 11, C_ACC)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rl)
	var ref: Dictionary = p
	var tb := small_btn(tr("ТРЕНИРОВАТЬ"), func(): train_pick = {} if train_pick == ref else ref; show_screen("training", false), Color("2fb8e8"))
	tb.disabled = not active
	v.add_child(tb)
	v.add_child(small_btn(tr("ОТЧЁТ"), func(): viewed_player = ref; player_tab = "attrs"; show_screen("player")))
	var prog: float = float(p.get("tprog", {}).get(grp, 0.0)) if typeof(p.get("tprog")) == TYPE_DICTIONARY else 0.0
	var circ := preload("res://scripts/progress_ring.gd").new().setup(prog / 100.0, 84, Color("2fb8e8"))
	circ.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(circ)
	if lst.is_empty():
		var nl2 := label(tr("Не выбрано"), 12, C_DIM)
		nl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nl2)
	for k in lst:
		var r := hbox(4)
		var al := label(_attr_name(k), 12, Color("d6dbe3"))
		al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(al)
		r.add_child(label("%.1f" % float(p["attrs"].get(k, 0)), 12, _attr_color(float(p["attrs"].get(k, 0)))))
		v.add_child(r)
	if active:
		var spd := label(tr("~%d%% в неделю") % int(gs.train_speed(p, grp)), 11, C_DIM)
		spd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(spd)
	if not train_pick.is_empty() and train_pick == p:
		var pick := vbox(2)
		pick.add_child(label(tr("Выбрано %d/%d") % [lst.size(), gs.TRAIN_MAX], 11, C_ACC))
		for k2 in gs.TRAIN_GROUPS[grp]:
			var ak: String = k2
			var cb := CheckBox.new()
			cb.text = "%s %.1f" % [_attr_name(ak), float(p["attrs"].get(ak, 0))]
			cb.add_theme_font_size_override("font_size", 11)
			cb.button_pressed = lst.has(ak)
			cb.disabled = not lst.has(ak) and lst.size() >= gs.TRAIN_MAX
			cb.pressed.connect(func(): gs.toggle_train(ref, grp, ak); show_screen("training", false))
			pick.add_child(cb)
		v.add_child(pick)
	return c

func _map_card(mp: String) -> Control:
	var in_pool: bool = gs.map_pool.has(mp)
	var picked: bool = gs.map_picks.has(mp)
	var banned: bool = gs.map_bans.has(mp)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 1)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(3 if picked else 1)
	sb.border_color = Color("2fb8e8") if picked else (C_BAD if banned else Color(1, 1, 1, 0.1))
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(100, 360)
	card.clip_contents = true
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(100, 360)
	card.add_child(holder)
	var img := TextureRect.new()
	img.texture = tex("res://assets/maps/%s.jpg" % gs.MAP_FILES[mp])
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not in_pool:
		img.modulate = Color(0.85, 0.3, 0.25, 0.75)
	elif banned:
		img.modulate = Color(0.6, 0.45, 0.45)
	elif not picked:
		img.modulate = Color(0.75, 0.75, 0.78)
	holder.add_child(img)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(shade)
	var v := vbox(6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6; v.offset_right = -6; v.offset_top = 6; v.offset_bottom = -8
	holder.add_child(v)
	if in_pool:
		var pb := hbox(4)
		pb.alignment = BoxContainer.ALIGNMENT_CENTER
		var pk := small_btn("PICK", func(): gs.toggle_pick(mp); show_screen("training", false), Color.BLACK if picked else Color.WHITE)
		if picked:
			var s2 := StyleBoxFlat.new(); s2.bg_color = C_GOOD; s2.set_corner_radius_all(4)
			s2.content_margin_left = 6; s2.content_margin_right = 6; s2.content_margin_top = 2; s2.content_margin_bottom = 2
			pk.add_theme_stylebox_override("normal", s2)
		pk.add_theme_font_size_override("font_size", 10)
		pb.add_child(pk)
		var bn := small_btn("BAN", func(): gs.toggle_ban(mp); show_screen("training", false), Color.BLACK if banned else Color.WHITE)
		if banned:
			var s3 := StyleBoxFlat.new(); s3.bg_color = C_BAD; s3.set_corner_radius_all(4)
			s3.content_margin_left = 6; s3.content_margin_right = 6; s3.content_margin_top = 2; s3.content_margin_bottom = 2
			bn.add_theme_stylebox_override("normal", s3)
		bn.add_theme_font_size_override("font_size", 10)
		pb.add_child(bn)
		v.add_child(pb)
	var nl := label(mp.to_upper(), 15, Color.WHITE)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	nl.add_theme_constant_override("shadow_offset_y", 2)
	nl.clip_text = true
	v.add_child(nl)
	if not in_pool:
		var ol := label(tr("ВНЕ МАППУЛА"), 11, Color.WHITE)
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ol)
	var f := Control.new()
	f.size_flags_vertical = Control.SIZE_EXPAND_FILL
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(f)
	var sk: int = int(gs.map_skill.get(mp, 50))
	var ring := preload("res://scripts/progress_ring.gd").new().setup(sk / 100.0, 78, Color("f5c518") if sk < 75 else C_GOOD)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ring)
	var gain: int = gs.map_gain() if picked else 0
	var g1 := label(tr("За неделю: +%d") % gain, 10, C_GOOD if gain > 0 else Color(1, 1, 1, 0.6))
	g1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(g1)
	var g2 := label(tr("За месяц: +%d") % (gain * 4), 10, C_GOOD if gain > 0 else Color(1, 1, 1, 0.6))
	g2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(g2)
	if picked:
		var ck := UITheme.icon("check", 22, C_GOOD)
		ck.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ck)
	elif banned:
		var bk := UITheme.icon("block", 22, C_BAD)
		bk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(bk)
	return card

func _train_maps() -> void:
	var hb := _block(tr("Выбор карт для тренировки"))
	content.add_child(hb)
	var top := hbox(10)
	var tv := vbox(2)
	tv.add_child(label(tr("Выберите три карты (PICK), на которых сосредоточится команда, и до трёх BAN. Можно менять в любой момент."), 13, Color("d6dbe3")))
	tv.add_child(label(tr("Пики: %s   ·   Баны: %s") % [", ".join(gs.map_picks) if not gs.map_picks.is_empty() else "—", ", ".join(gs.map_bans) if not gs.map_bans.is_empty() else "—"], 13, C_ACC))
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	top.add_child(btn("AUTO", func(): gs.auto_maps(); show_screen("training", false), Color("2fb8e8")))
	hb.add_child(top)
	var row := hbox(8)
	content.add_child(row)
	var order: Array = gs.MAPS.duplicate()
	order.sort_custom(func(a, b): return int(gs.map_pool.has(a)) > int(gs.map_pool.has(b)))
	for mp in order:
		row.add_child(_map_card(mp))
	content.add_child(label(tr("Маппул: %d карт. Каждый год (1 января) две наименее игранные карты уходят, две из запаса возвращаются.") % gs.map_pool.size(), 12, C_DIM))
	var pb := _block(tr("Прогресс"))
	content.add_child(pb)
	var pr := hbox(30)
	pb.add_child(pr)
	var items: Array = [[gs.team_logo, gs.team_name + " " + tr("Состав"), 2]]
	var cs: Dictionary = _group_staff("coach")
	if not cs.is_empty():
		items.append([str(cs.get("photo", "")), str(cs["name"]), 1])
	var an: Dictionary = _group_staff("analyst")
	if not an.is_empty():
		items.append([str(an.get("photo", "")), str(an["name"]), gs.staff_level("analyst") / 2])
	for it in items:
		var h := hbox(8)
		h.add_child(_circle(str(it[0]), 40))
		var iv := vbox(0)
		iv.add_child(label(str(it[1]), 13, Color.WHITE))
		iv.add_child(label(tr("+%d/неделю") % int(it[2]), 12, C_GOOD))
		h.add_child(iv)
		pr.add_child(h)

# ------------------------------------------------------------ трансферы

var tr_role: String = ""
var tr_sort: String = "ovr"


var trf_tab: String = "mine"
var trf_ask: Dictionary = {}

const TRF_KIND := {"buy": ["Покупка", "5aa9ff"], "loan": ["Аренда", "ffb23e"], "sell": ["Продажа", "7dd66b"], "release": ["Отчисление", "ff6b6b"], "return": ["Возврат из аренды", "9aa3b2"]}

func screen_transfers() -> void:
	var tabs := hbox(18)
	for tb in [["mine", tr("Мои трансферы")], ["world", tr("Мировые трансферы")], ["list", tr("Трансферный список")]]:
		var key: String = tb[0]
		tabs.add_child(text_btn(tb[1], func(): trf_tab = key; show_screen("transfers", false), 17, C_ACC if trf_tab == key else Color.WHITE))
	tabs.add_child(spacer())
	tabs.add_child(label(tr("Бюджет: %s · Состав: %d/%d") % [money_fmt(gs.money), gs.players.size(), gs.MAX_ROSTER], 13, C_DIM))
	content.add_child(tabs)
	match trf_tab:
		"mine": _trf_log(true)
		"world": _trf_log(false)
		"list": _trf_list()

func _trf_log(mine_only: bool) -> void:
	var rows: Array = []
	for e in gs.transfers_log:
		if not mine_only or e["from"] == gs.team_name or e["to"] == gs.team_name:
			rows.append(e)
	if mine_only:
		var tin: int = 0
		var tout: int = 0
		for e in rows:
			if e["to"] == gs.team_name: tin += int(e["fee"])
			elif e["from"] == gs.team_name: tout += int(e["fee"])
		var tiles := hbox(10)
		tiles.add_child(_stat_tile(tr("Сделок"), str(rows.size()), Color.WHITE, "swap_horiz"))
		tiles.add_child(_stat_tile(tr("Потрачено"), money_fmt(tin), C_BAD, "trending_down"))
		tiles.add_child(_stat_tile(tr("Заработано"), money_fmt(tout), C_GOOD, "trending_up"))
		tiles.add_child(_stat_tile(tr("Баланс трансферов"), money_fmt(tout - tin), C_GOOD if tout >= tin else C_BAD, "account_balance"))
		content.add_child(tiles)
	var c := _card()
	content.add_child(c)
	var v := vbox(3)
	c.add_child(v)
	var hh := hbox(8)
	for e in [[tr("Дата"), 80], ["", 30], [tr("Игрок"), 120], [tr("Роль"), 80], [tr("ОБЩ"), 34], [tr("Откуда"), 140], ["", 18], [tr("Куда"), 140], [tr("Тип"), 120], [tr("Сумма"), 80]]:
		hh.add_child(cell(e[0], e[1], C_DIM, 11))
	v.add_child(hh)
	if rows.is_empty():
		v.add_child(label(tr("Трансферов пока не было.") if mine_only else tr("В мире пока не было трансферов."), 14, C_DIM))
	for i in mini(rows.size(), 40):
		var e: Dictionary = rows[i]
		var row := PanelContainer.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(1, 1, 1, 0.04) if i % 2 == 0 else Color(1, 1, 1, 0.015)
		rs.content_margin_top = 4; rs.content_margin_bottom = 4; rs.content_margin_left = 4
		row.add_theme_stylebox_override("panel", rs)
		var r := hbox(8)
		row.add_child(r)
		r.add_child(cell(str(e["date"]), 80, C_DIM, 12))
		r.add_child(_circle(str(e.get("photo", "")), 30))
		var nr := hbox(5)
		nr.custom_minimum_size = Vector2(120, 0)
		nr.add_child(_flag(str(e.get("country", "xx")), 18))
		nr.add_child(label(str(e["nick"]), 13, Color.WHITE))
		r.add_child(nr)
		r.add_child(cell(tr(str(e.get("role", ""))), 80, C_ACC, 12))
		r.add_child(cell(str(int(e.get("ovr", 0))), 34, stat_color(int(e.get("ovr", 0))), 13))
		r.add_child(_trf_team(str(e["from"]), 140))
		var ar := UITheme.icon("arrow_forward", 16, C_DIM)
		ar.custom_minimum_size = Vector2(18, 0)
		r.add_child(ar)
		r.add_child(_trf_team(str(e["to"]), 140))
		var kd: Array = TRF_KIND.get(str(e["kind"]), ["?", "ffffff"])
		r.add_child(cell(tr(kd[0]), 120, Color(kd[1]), 12))
		r.add_child(cell(money_fmt(int(e["fee"])) if int(e["fee"]) > 0 else "—", 80, Color.WHITE, 13))
		v.add_child(row)

func _trf_team(t: String, w: int) -> Control:
	var h := hbox(5)
	h.custom_minimum_size = Vector2(w, 0)
	if t == "":
		h.add_child(label(tr("Свободный агент"), 12, C_DIM))
		return h
	h.add_child(team_icon(t, 20))
	var l := label(t, 12, C_ACC if t == gs.team_name else Color("5aa9ff"))
	l.clip_text = true
	l.custom_minimum_size = Vector2(w - 30, 0)
	h.add_child(l)
	return h

func _trf_list() -> void:
	var mb := _block(tr("Мои игроки"))
	content.add_child(mb)
	var mc := _card()
	mb.add_child(mc)
	var mv := vbox(4)
	mc.add_child(mv)
	mv.add_child(label(tr("Выставьте игрока на трансфер со своей ценой — клубы будут присылать предложения в «Разговор»."), 12, C_DIM))
	for p in gs.players:
		var r := hbox(8)
		r.add_child(portrait(p, 34))
		r.add_child(_flag(str(p.get("country", "xx")), 20))
		r.add_child(_nick_link(p, 130, Color.WHITE))
		r.add_child(cell(tr(p["role"]), 90, C_ACC, 12))
		r.add_child(cell(str(gs.ovr(p)), 40, stat_color(gs.ovr(p)), 13))
		r.add_child(cell(tr("Стоимость %s") % money_fmt(gs.fee(p)), 160, C_DIM, 12))
		var ref: Dictionary = p
		var loan: bool = str(p.get("contract", {}).get("type", "")) == "loan"
		if bool(p.get("listed", false)):
			r.add_child(_badge(tr("В списке · %s") % money_fmt(int(p.get("ask", 0))), C_ACC))
			r.add_child(spacer())
			r.add_child(small_btn(tr("Снять"), func(): gs.unlist_player(ref); show_screen("transfers", false), C_BAD))
		else:
			r.add_child(spacer())
			var key: String = str(p["nick"])
			if not trf_ask.has(key):
				trf_ask[key] = gs.fee(p)
			var sp := SpinBox.new()
			sp.min_value = 1000
			sp.max_value = 10000000
			sp.step = 1000
			sp.value = int(trf_ask[key])
			sp.prefix = "$"
			sp.custom_minimum_size = Vector2(140, 0)
			sp.editable = not loan
			sp.value_changed.connect(func(x): trf_ask[key] = int(x))
			r.add_child(sp)
			var lb := small_btn(tr("Выставить"), func(): gs.list_player(ref, int(trf_ask[key])); show_screen("transfers", false), C_GOOD)
			lb.disabled = loan
			if loan:
				lb.tooltip_text = tr("Арендованного игрока нельзя выставить.")
			r.add_child(lb)
		mv.add_child(r)
	var ob := _block(tr("Выставлены другими клубами"))
	content.add_child(ob)
	var oc := _card()
	ob.add_child(oc)
	var ov := vbox(4)
	oc.add_child(ov)
	var any := false
	for p in gs.world:
		if not bool(p.get("listed", false)):
			continue
		any = true
		var r2 := hbox(8)
		r2.add_child(portrait(p, 34))
		r2.add_child(_flag(str(p.get("country", "xx")), 20))
		r2.add_child(_nick_link(p, 130, Color("5aa9ff")))
		r2.add_child(cell(tr(p["role"]), 90, C_ACC, 12))
		r2.add_child(cell(str(gs.ovr(p)), 40, stat_color(gs.ovr(p)), 13))
		r2.add_child(_trf_team(str(p.get("team", "")), 150))
		r2.add_child(cell(money_fmt(gs.buyout(p)), 100, C_GOOD, 13))
		r2.add_child(spacer())
		var ref2: Dictionary = p
		var bb := small_btn(tr("Купить"), func():
			var err: String = gs.buy_player(ref2)
			if err != "":
				gs.add_news(err)
			show_screen("transfers", false), C_GOOD)
		bb.disabled = gs.money < gs.buyout(p) or gs.players.size() >= gs.MAX_ROSTER
		r2.add_child(bb)
		ov.add_child(r2)
	if not any:
		ov.add_child(label(tr("Сейчас никто не выставлен."), 13, C_DIM))

# ------------------------------------------------------------ турниры

func screen_league() -> void:
	content.add_child(_hdr_card("emoji_events", tr("Турниры"), "%s · %s" % [tr(gs.TIERS[gs.tier]), gs.phase_name()]))
	var cols := hbox(12)
	content.add_child(cols)
	var lb := _block(tr("Таблица лиги"))
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(lb)
	var lc := _card()
	lb.add_child(lc)
	var lv := vbox(4)
	lc.add_child(lv)
	var hh := hbox(6)
	for e in [["#", 30], ["", 30], [tr("Команда"), 200], [tr("В"), 36], [tr("П"), 36], [tr("Раунды ±"), 70]]:
		hh.add_child(cell(e[0], e[1], C_DIM, 12))
	lv.add_child(hh)
	var rl: Array = gs.rank_list()
	for i in rl.size():
		var tn: String = rl[i]
		var s: Dictionary = gs.standings[tn]
		var mine: bool = tn == gs.team_name
		var row := PanelContainer.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(1, 0.7, 0.24, 0.12) if mine else Color(1, 1, 1, 0.025)
		rs.border_width_left = 3
		rs.border_color = C_GOOD if i < 4 else Color(1, 1, 1, 0.1)
		rs.set_corner_radius_all(5)
		rs.set_content_margin_all(6)
		row.add_theme_stylebox_override("panel", rs)
		var r := hbox(6)
		row.add_child(r)
		r.add_child(cell(str(i + 1), 30, C_ACC if mine else Color.WHITE, 15))
		r.add_child(team_icon(tn, 26))
		r.add_child(cell(tn, 200, C_ACC if mine else Color.WHITE, 15))
		r.add_child(cell(str(int(s["w"])), 36, C_GOOD))
		r.add_child(cell(str(int(s["l"])), 36, C_BAD))
		r.add_child(cell(("+" if int(s["rd"]) > 0 else "") + str(int(s["rd"])), 70, C_DIM))
		lv.add_child(row)
	lv.add_child(label(tr("Зелёная полоса — зона плей-офф."), 11, C_DIM))
	var pb := _block(tr("Плей-офф"))
	pb.custom_minimum_size = Vector2(360, 0)
	cols.add_child(pb)
	var pc := _card()
	pb.add_child(pc)
	var pv := vbox(8)
	pc.add_child(pv)
	if gs.week <= 7:
		pv.add_child(label(tr("Начнётся после 7-го тура (через %d нед.).") % (8 - gs.week), 13, C_DIM))
	for i in gs.playoff["semis"].size():
		var sm: Array = gs.playoff["semis"][i]
		pv.add_child(_match_box(tr("Полуфинал %d") % (i + 1), sm[0], sm[1], str(gs.playoff["sf"].get(str(i), ""))))
	if not gs.playoff["final"].is_empty():
		pv.add_child(_match_box(tr("ФИНАЛ"), gs.playoff["final"][0], gs.playoff["final"][1], str(gs.playoff["champion"])))
	if str(gs.playoff["champion"]) != "":
		var ch := hbox(8)
		ch.add_child(pic("res://assets/ui/trophy.png", 40))
		ch.add_child(label(tr("Чемпион: %s") % gs.playoff["champion"], 16, Color("f5c518")))
		pv.add_child(ch)
	pv.add_child(label(tr("Призы: 1 место $%d, 2 место $%d · Чемпион плей-офф +$%d") % [12000 * (gs.tier + 1), 8000 * (gs.tier + 1), 15000 * (gs.tier + 1)], 11, C_DIM))
	var hb := _block(tr("История"))
	content.add_child(hb)
	var hc := _card()
	hb.add_child(hc)
	var hv := vbox(4)
	hc.add_child(hv)
	hv.add_child(label(tr("Титулов: %d") % gs.titles, 15, Color("f5c518")))
	if gs.history.is_empty():
		hv.add_child(label(tr("Пока пусто."), 13, C_DIM))
	for t in gs.history:
		hv.add_child(label(t, 13, Color("c9ced8")))

func _match_box(t: String, a: String, b: String, winner: String) -> Control:
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	c.add_theme_stylebox_override("panel", sb)
	var v := vbox(3)
	c.add_child(v)
	v.add_child(label(t, 11, C_DIM))
	for tn in [a, b]:
		var r := hbox(8)
		r.add_child(team_icon(tn, 22))
		var col: Color = Color.WHITE
		if winner != "":
			col = C_GOOD if tn == winner else C_DIM
		if tn == gs.team_name:
			col = C_ACC if winner == "" or winner == tn else C_BAD
		r.add_child(label(tn, 14, col))
		v.add_child(r)
	return c

# ------------------------------------------------------------ статистика

func screen_stats() -> void:
	content.add_child(_hdr_card("bar_chart", tr("Статистика"), tr("Сезон %d") % gs.season))
	var ts: Dictionary = gs.team_stats
	var tiles := hbox(10)
	tiles.add_child(_stat_tile(tr("Матчи (В-П)"), "%d-%d" % [int(ts.get("w", 0)), int(ts.get("l", 0))], Color.WHITE, "sports_esports"))
	tiles.add_child(_stat_tile(tr("Карты (В-П)"), "%d-%d" % [int(ts.get("mw", 0)), int(ts.get("ml", 0))], Color.WHITE, "map"))
	tiles.add_child(_stat_tile(tr("Раунды"), "%d:%d" % [int(ts.get("rw", 0)), int(ts.get("rl", 0))], Color.WHITE, "flag"))
	var games: int = int(ts.get("w", 0)) + int(ts.get("l", 0))
	tiles.add_child(_stat_tile(tr("Винрейт"), ("%d%%" % int(100.0 * int(ts.get("w", 0)) / games)) if games > 0 else "—", C_GOOD, "trending_up"))
	tiles.add_child(_stat_tile(tr("Титулы"), str(gs.titles), Color("f5c518"), "emoji_events"))
	content.add_child(tiles)
	var pb := _block(tr("Статистика игроков"))
	content.add_child(pb)
	var c := _card()
	pb.add_child(c)
	var v := vbox(4)
	c.add_child(v)
	var hh := hbox(8)
	for e in [["", 36], [tr("Игрок"), 150], [tr("Роль"), 100], [tr("Матчи"), 70], [tr("Киллы"), 70], [tr("Смерти"), 70], ["K/D", 70], [tr("ОБЩ"), 50]]:
		hh.add_child(cell(e[0], e[1], C_DIM, 12))
	v.add_child(hh)
	var arr: Array = gs.players.duplicate()
	arr.sort_custom(func(a, b): return int(a.get("st", {}).get("k", 0)) > int(b.get("st", {}).get("k", 0)))
	for p in arr:
		var st: Dictionary = p.get("st", {})
		var k: int = int(st.get("k", 0))
		var d: int = int(st.get("d", 0))
		var kd: float = float(k) / maxf(1.0, float(d))
		var r := hbox(8)
		r.add_child(portrait(p, 32))
		r.add_child(_nick_link(p, 150, Color.WHITE))
		r.add_child(cell(tr(p["role"]), 100, C_ACC))
		r.add_child(cell(str(int(p["matches"])), 70))
		r.add_child(cell(str(k), 70, C_GOOD))
		r.add_child(cell(str(d), 70, C_BAD))
		r.add_child(cell(("%.2f" % kd) if d > 0 else "—", 70, C_GOOD if kd >= 1.0 else C_ACC))
		r.add_child(cell(str(gs.ovr(p)), 50, stat_color(gs.ovr(p))))
		v.add_child(r)

# ------------------------------------------------------------ финансы

func screen_finance() -> void:
	var income: int = gs.weekly_income()
	var salaries: int = gs.player_salaries()
	var staff: int = gs.staff_salaries()
	var upk: int = gs.upkeep()
	var net: int = income - salaries - staff - upk
	content.add_child(_hdr_card("payments", tr("Финансы"), tr("Баланс клуба и движение денег")))
	var tiles := hbox(10)
	tiles.add_child(_stat_tile(tr("Баланс"), money_fmt(gs.money), C_GOOD if gs.money >= 0 else C_BAD, "account_balance"))
	tiles.add_child(_stat_tile(tr("Доход / нед."), "+" + money_fmt(income), C_GOOD, "trending_up"))
	tiles.add_child(_stat_tile(tr("Расходы / нед."), "-" + money_fmt(salaries + staff + upk), C_BAD, "trending_down"))
	tiles.add_child(_stat_tile(tr("Итог / нед."), ("+" if net >= 0 else "") + money_fmt(net), C_GOOD if net >= 0 else C_BAD, "savings"))
	content.add_child(tiles)
	var cols := hbox(12)
	content.add_child(cols)
	var bb := _block(tr("Статьи бюджета"))
	bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(bb)
	var bc := _card()
	bb.add_child(bc)
	var bv := vbox(8)
	bc.add_child(bv)
	var mx: float = float(maxi(1, maxi(income, salaries + staff + upk)))
	for e in [[tr("Спонсоры"), income, C_GOOD, "handshake"], [tr("Зарплаты игроков"), salaries, C_BAD, "groups"], [tr("Зарплаты штаба"), staff, C_BAD, "badge"], [tr("Инфраструктура"), upk, C_BAD, "home_work"]]:
		var r := hbox(10)
		r.add_child(UITheme.icon(e[3], 20, C_DIM))
		r.add_child(cell(e[0], 170, Color("d6dbe3")))
		var b := _bar(float(e[1]), mx, e[2], 180, 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(b)
		r.add_child(cell(money_fmt(int(e[1])), 80, e[2]))
		bv.add_child(r)
	bv.add_child(label(tr("Призовые: победа в матче +$%d. Места в лиге и титулы — в конце сезона.") % (1500 * (gs.tier + 1)), 11, C_DIM))
	var hb := _block(tr("Итог по неделям"))
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(hb)
	var hc := _card()
	hb.add_child(hc)
	var vals: Array = []
	var labs: Array = []
	for h in gs.money_hist:
		vals.append(int(h["net"]))
		labs.append("%d" % int(h["w"]))
	hc.add_child(preload("res://scripts/bar_chart.gd").new().setup(vals, labs, 190))

# ------------------------------------------------------------ профиль

func screen_coach() -> void:
	var pr := _card()
	content.add_child(pr)
	var ph := hbox(20)
	pr.add_child(ph)
	ph.add_child(_circle(gs.photo_path, 140, Color(gs.team_color)))
	var pv := vbox(4)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := hbox(10)
	nr.add_child(_flag(gs.coach_country_code, 30))
	nr.add_child(label(gs.coach_name, 28, Color.WHITE))
	pv.add_child(nr)
	if gs.coach_nick != "":
		pv.add_child(label("\"%s\"" % gs.coach_nick, 16, C_ACC))
	pv.add_child(label(tr("%d лет · %s") % [gs.coach_age, tr(gs.coach_country)], 14, C_DIM))
	var tr2 := hbox(8)
	if tex(gs.team_logo) != null:
		tr2.add_child(pic(gs.team_logo, 28))
	tr2.add_child(label(tr("Главный менеджер · %s") % gs.team_name, 14, Color(gs.team_color).lightened(0.3)))
	pv.add_child(tr2)
	ph.add_child(pv)
	var tiles := vbox(6)
	tiles.add_child(_stat_tile(tr("Репутация"), str(int(gs.rep)), C_ACC, "star"))
	tiles.add_child(_stat_tile(tr("Титулы"), str(gs.titles), Color("f5c518"), "emoji_events"))
	ph.add_child(tiles)
	var cols := hbox(12)
	content.add_child(cols)
	var ab := _block(tr("Качества менеджера"))
	ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(ab)
	var ac := _card()
	ab.add_child(ac)
	var av := vbox(6)
	ac.add_child(av)
	if gs.coach_attrs.is_empty():
		av.add_child(label(tr("Нет данных."), 13, C_DIM))
	for pair in Teams.ATTR_PAIRS:
		for kk in [[pair[0], pair[1]], [pair[2], pair[3]]]:
			if not gs.coach_attrs.has(kk[0]):
				continue
			var val: float = float(gs.coach_attrs[kk[0]])
			var r := hbox(10)
			r.add_child(cell(tr(kk[1]), 170, Color("d6dbe3")))
			var b := _bar(val, 20.0, _attr_color(val), 160, 8)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(b)
			r.add_child(cell(str(int(val)), 30, _attr_color(val)))
			av.add_child(r)
	var sb := _block(tr("Навыки · очков: %d") % gs.coach_pts)
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(sb)
	var sc := _card()
	sb.add_child(sc)
	var sv := vbox(10)
	sc.add_child(sv)
	var sicons := {"tactics": "psychology", "motivation": "local_fire_department", "scout": "travel_explore"}
	for k in gs.COACH_SKILLS:
		var r2 := hbox(10)
		r2.add_child(UITheme.icon(sicons.get(k, "star"), 24, C_ACC))
		var v2 := vbox(2)
		v2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v2.add_child(label(tr(gs.COACH_SKILLS[k]), 13, Color.WHITE))
		var lvl := hbox(3)
		for i in 10:
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(16, 6)
			dot.color = C_ACC if i < int(gs.coach_skill[k]) else Color(1, 1, 1, 0.1)
			lvl.add_child(dot)
		v2.add_child(lvl)
		r2.add_child(v2)
		var key: String = k
		var b2 := small_btn("+", func(): gs.upgrade_coach(key); show_screen("coach", false), C_GOOD)
		b2.disabled = gs.coach_pts <= 0 or int(gs.coach_skill[k]) >= 10
		r2.add_child(b2)
		sv.add_child(r2)
	sv.add_child(label(tr("Очки дают победы, плей-офф и титулы."), 11, C_DIM))
	if gs.legend:
		content.add_child(_alert(tr("Вы выиграли Мировую серию — вы легенда Standoff 2!"), true))

# ------------------------------------------------------------ настройки

func screen_system() -> void:
	content.add_child(_hdr_card("settings", tr("Настройки"), tr("Сохранение, язык, экран и игра")))
	var cols := hbox(12)
	content.add_child(cols)
	var gb := _block(tr("Игра"))
	gb.custom_minimum_size = Vector2(320, 0)
	cols.add_child(gb)
	var gc := _card()
	gb.add_child(gc)
	var gv := vbox(10)
	gc.add_child(gv)
	gv.add_child(label(tr("Слот %d") % gs.slot + " · " + gs.team_name, 14, Color.WHITE))
	gv.add_child(btn(tr("Сохранить игру"), func(): gs.save(); gs.add_news(tr("Игра сохранена.")); show_screen("system", false), C_GOOD))
	gv.add_child(btn(tr("Выйти в главное меню"), func(): gs.save(); show_menu()))
	var sb := _block(tr("Параметры"))
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(sb)
	var sc := _card()
	sb.add_child(sc)
	var sv := vbox(8)
	sc.add_child(sv)
	build_settings(sv, func(): show_screen("system", false))

# ------------------------------------------------------------ скаутинг

var sc_tab: String = "players"
var sc_quick: String = "all"
var sc_page: int = 0
var sc_q: String = ""
var sc_nat: String = ""
var sc_role: String = ""
var sc_age: Array = [16, 40]
var sc_sal: int = 0
var sc_price: int = 0
var sc_stars: float = 0.0
var sc_filters_open: bool = false
const SC_PER_PAGE := 12

func _k(v: int) -> String:
	if v >= 1000000: return "%.1fM" % (v / 1000000.0)
	if v >= 1000: return "%.1fK" % (v / 1000.0)
	return str(v)

func _scout_pool() -> Array:
	var all: Array = gs.market + gs.world
	var res: Array = []
	for p in all:
		gs.ensure_attrs(p)
		var team: String = str(p.get("team", ""))
		var age: int = int(p["age"])
		match sc_quick:
			"free": if team != "": continue
			"u23": if age >= 23: continue
			"loan": if team == "" or not bool(p.get("loan_ok", false)): continue
			"expiring": if team == "" or int(p.get("contract", {}).get("end", 99)) > gs.season: continue
			"afford": if gs.buyout(p) > gs.money: continue
			"short": if not gs.is_shortlisted(p): continue
		if sc_q != "" and str(p["nick"]).to_lower().find(sc_q.to_lower()) < 0 and ("%s %s" % [p.get("first", ""), p.get("last", "")]).to_lower().find(sc_q.to_lower()) < 0:
			continue
		if sc_nat != "" and str(p.get("country", "")) != sc_nat: continue
		if sc_role != "" and p["role"] != sc_role and str(p.get("role2", "")) != sc_role: continue
		if age < int(sc_age[0]) or age > int(sc_age[1]): continue
		if sc_sal > 0 and int(p["salary"]) > sc_sal: continue
		if sc_price > 0 and gs.buyout(p) > sc_price: continue
		if sc_stars > 0.0 and _player_stars(p) < sc_stars: continue
		res.append(p)
	res.sort_custom(func(a, b): return gs.ovr(a) > gs.ovr(b))
	return res

func screen_scouting() -> void:
	var top := hbox(10)
	for tb in [["players", tr("Игроки")], ["staff", tr("Штат")]]:
		var key: String = tb[0]
		top.add_child(text_btn(tb[1], func(): sc_tab = key; show_screen("scouting", false), 17, C_ACC if sc_tab == key else Color.WHITE))
	content.add_child(top)
	top = hbox(6)
	if sc_tab == "players":
		for q in [["all", tr("Все")], ["free", tr("Свободные агенты")], ["u23", tr("До 23 лет")], ["loan", tr("Готов в аренду")], ["expiring", tr("Контракт кончается")], ["afford", tr("По карману")], ["short", tr("Мои закладки")]]:
			var key2: String = q[0]
			top.add_child(small_btn(q[1], func(): sc_quick = key2; sc_page = 0; show_screen("scouting", false), C_ACC if sc_quick == key2 else Color.WHITE))
		top.add_child(spacer())
		var se := LineEdit.new()
		se.placeholder_text = tr("Поиск...")
		se.text = sc_q
		se.custom_minimum_size = Vector2(130, 30)
		se.text_submitted.connect(func(t): sc_q = t; sc_page = 0; show_screen("scouting", false))
		top.add_child(se)
		top.add_child(small_btn(tr("ФИЛЬТРЫ"), func(): sc_filters_open = not sc_filters_open; show_screen("scouting", false), C_GOOD))
		content.add_child(top)
	if sc_tab == "staff":
		_scout_staff()
		return
	if sc_filters_open:
		content.add_child(_scout_filters())
	var pool: Array = _scout_pool()
	var pages: int = maxi(1, int(ceil(float(pool.size()) / SC_PER_PAGE)))
	sc_page = clampi(sc_page, 0, pages - 1)
	var c := _card()
	content.add_child(c)
	var v := vbox(2)
	c.add_child(v)
	var hh := hbox(6)
	for e in [["", 24], [tr("Ник"), 130], [tr("Роль"), 84], [tr("Возраст"), 50], [tr("Рейтинг"), 80], [tr("Нация"), 40], [tr("Потенциал"), 80], [tr("Истекает"), 80], [tr("Зарплата"), 76], [tr("Трансф. стоимость"), 76], [tr("Аренда"), 54], [tr("Команда"), 120]]:
		hh.add_child(cell(e[0], e[1], C_DIM, 11))
	v.add_child(hh)
	if pool.is_empty():
		v.add_child(label(tr("Никого не найдено."), 14, C_DIM))
	for i in range(sc_page * SC_PER_PAGE, mini(pool.size(), (sc_page + 1) * SC_PER_PAGE)):
		v.add_child(_scout_row(pool[i], i))
	var pr := hbox(8)
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	var pb := small_btn("<", func(): sc_page -= 1; show_screen("scouting", false))
	pb.disabled = sc_page == 0
	pr.add_child(pb)
	for pg in range(maxi(0, sc_page - 2), mini(pages, sc_page + 3)):
		var pp: int = pg
		pr.add_child(small_btn(str(pg + 1), func(): sc_page = pp; show_screen("scouting", false), C_ACC if pg == sc_page else Color.WHITE))
	var nb := small_btn(">", func(): sc_page += 1; show_screen("scouting", false))
	nb.disabled = sc_page >= pages - 1
	pr.add_child(nb)
	pr.add_child(spacer())
	pr.add_child(label(tr("Найдено %d из %d") % [pool.size(), gs.market.size() + gs.world.size()], 12, C_DIM))
	v.add_child(pr)

func _scout_row(p: Dictionary, i: int) -> Control:
	var row := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(1, 1, 1, 0.04) if i % 2 == 0 else Color(1, 1, 1, 0.015)
	rs.content_margin_top = 3; rs.content_margin_bottom = 3; rs.content_margin_left = 4
	row.add_theme_stylebox_override("panel", rs)
	var r := hbox(6)
	row.add_child(r)
	var star := icon_btn("star" if gs.is_shortlisted(p) else "star_border", tr("В закладки"), func(): gs.toggle_shortlist(p); show_screen("scouting", false))
	star.custom_minimum_size = Vector2(24, 24)
	r.add_child(star)
	var nv := vbox(0)
	nv.custom_minimum_size = Vector2(130, 0)
	var nl := _nick_link(p, 130, Color("5aa9ff"))
	nl.add_theme_font_size_override("font_size", 13)
	nv.add_child(nl)
	var full: String = ("%s %s" % [tr(str(p.get("first", ""))), tr(str(p.get("last", "")))]).strip_edges()
	nv.add_child(label(full if full != "" else " ", 10, C_DIM))
	r.add_child(nv)
	var roles: String = tr(p["role"]) + (("\n" + tr(p["role2"])) if str(p.get("role2", "")) != "" else "")
	r.add_child(cell(roles, 84, Color.WHITE, 12))
	r.add_child(cell(str(p["age"]), 50, Color.WHITE, 13))
	var s1 := _stars(_player_stars(p), 12)
	s1.custom_minimum_size = Vector2(80, 14)
	r.add_child(s1)
	var fl := _flag(str(p.get("country", "xx")), 24)
	var fw := CenterContainer.new()
	fw.custom_minimum_size = Vector2(40, 0)
	fw.add_child(fl)
	r.add_child(fw)
	var s2 := _stars(clampf((float(p.get("pot_est", p["pot"])) - 35.0) / 9.0, 0.5, 5.0), 12)
	s2.custom_minimum_size = Vector2(80, 14)
	r.add_child(s2)
	var team: String = str(p.get("team", ""))
	r.add_child(cell(_season_end_date(int(p.get("contract", {}).get("end", gs.season))) if team != "" else "—", 80, Color.WHITE, 12))
	r.add_child(cell("$" + _k(int(p["salary"]) * 4) + tr("/мес"), 76, C_GOOD, 12))
	r.add_child(cell("$" + _k(gs.buyout(p)), 76, Color("5aa9ff"), 13))
	if team == "":
		r.add_child(cell("—", 54, C_DIM, 13))
	else:
		var ok: bool = bool(p.get("loan_ok", false))
		r.add_child(cell(tr("Да") if ok else tr("Нет"), 54, C_GOOD if ok else C_BAD, 13))
	var tv := hbox(6)
	tv.custom_minimum_size = Vector2(120, 0)
	if team != "":
		tv.add_child(team_icon(team, 20))
		var tl := label(team, 11, Color("5aa9ff"))
		tl.clip_text = true
		tl.custom_minimum_size = Vector2(90, 0)
		tv.add_child(tl)
	else:
		tv.add_child(label(tr("Свободный агент"), 12, C_DIM))
	r.add_child(tv)
	return row

func _scout_filters() -> Control:
	var c := _card()
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 8)
	c.add_child(g)
	var nat := OptionButton.new()
	nat.add_item(tr("Все нации"))
	var codes: Array = [""]
	for cc in Teams.COUNTRY_LIST:
		var ft: Texture2D = tex("res://assets/flags/%s.png" % cc[0])
		if ft != null: nat.add_icon_item(ft, tr(cc[1]))
		else: nat.add_item(tr(cc[1]))
		codes.append(cc[0])
	nat.selected = maxi(0, codes.find(sc_nat))
	nat.item_selected.connect(func(i): sc_nat = codes[i]; sc_page = 0; show_screen("scouting", false))
	g.add_child(_flt(tr("Нация"), nat))
	var ro := OptionButton.new()
	ro.add_item(tr("Все роли"))
	for rr in gs.ROLES:
		ro.add_item(tr(rr))
	ro.selected = maxi(0, gs.ROLES.find(sc_role) + 1)
	ro.item_selected.connect(func(i): sc_role = "" if i == 0 else gs.ROLES[i - 1]; sc_page = 0; show_screen("scouting", false))
	g.add_child(_flt(tr("Роль"), ro))
	var ah := hbox(4)
	var a0 := SpinBox.new(); a0.min_value = 16; a0.max_value = 40; a0.value = sc_age[0]
	var a1 := SpinBox.new(); a1.min_value = 16; a1.max_value = 40; a1.value = sc_age[1]
	a0.value_changed.connect(func(x): sc_age[0] = int(x))
	a1.value_changed.connect(func(x): sc_age[1] = int(x))
	ah.add_child(a0); ah.add_child(label("—", 13, C_DIM)); ah.add_child(a1)
	g.add_child(_flt(tr("Возраст"), ah))
	var st := OptionButton.new()
	for s in [0.0, 2.0, 3.0, 3.5, 4.0, 4.5]:
		st.add_item(tr("Любой") if s == 0.0 else "≥ %.1f★" % s)
	st.selected = [0.0, 2.0, 3.0, 3.5, 4.0, 4.5].find(sc_stars)
	st.item_selected.connect(func(i): sc_stars = [0.0, 2.0, 3.0, 3.5, 4.0, 4.5][i]; sc_page = 0; show_screen("scouting", false))
	g.add_child(_flt(tr("Рейтинг"), st))
	var sal := SpinBox.new(); sal.min_value = 0; sal.max_value = 20000; sal.step = 100; sal.value = sc_sal
	sal.value_changed.connect(func(x): sc_sal = int(x))
	g.add_child(_flt(tr("Зарплата до ($/нед, 0 — любая)"), sal))
	var pr := SpinBox.new(); pr.min_value = 0; pr.max_value = 5000000; pr.step = 5000; pr.value = sc_price
	pr.value_changed.connect(func(x): sc_price = int(x))
	g.add_child(_flt(tr("Цена до ($, 0 — любая)"), pr))
	var ap := btn(tr("Применить"), func(): sc_page = 0; show_screen("scouting", false), C_GOOD)
	g.add_child(_flt(" ", ap))
	var rs := btn(tr("Сбросить"), func():
		sc_nat = ""; sc_role = ""; sc_age = [16, 40]; sc_sal = 0; sc_price = 0; sc_stars = 0.0; sc_q = ""
		show_screen("scouting", false))
	g.add_child(_flt(" ", rs))
	return c

func _flt(t: String, ctl: Control) -> Control:
	var v := vbox(2)
	v.add_child(label(t, 11, C_DIM))
	v.add_child(ctl)
	return v

func _scout_staff() -> void:
	var c := _card()
	content.add_child(c)
	var v := vbox(4)
	c.add_child(v)
	var hh := hbox(8)
	for e in [["", 36], [tr("Имя"), 180], [tr("Должность"), 170], [tr("Нация"), 50], [tr("Рейтинг"), 90], [tr("Подъёмные"), 100], [tr("Зарплата"), 90]]:
		hh.add_child(cell(e[0], e[1], C_DIM, 11))
	v.add_child(hh)
	for i in gs.staff_market.size():
		var s: Dictionary = gs.staff_market[i]
		var r := hbox(8)
		r.add_child(_circle(str(s.get("photo", "")), 32))
		r.add_child(cell(str(s["name"]), 180, Color("5aa9ff"), 13))
		r.add_child(cell(tr(gs.STAFF_ROLES[s["role"]][0]), 170, Color.WHITE, 13))
		var fw := CenterContainer.new()
		fw.custom_minimum_size = Vector2(50, 0)
		fw.add_child(_flag(str(s.get("country", "xx")), 22))
		r.add_child(fw)
		var st := _stars(gs.staff_stars(s), 13)
		st.custom_minimum_size = Vector2(90, 14)
		r.add_child(st)
		r.add_child(cell("$" + _k(int(s["fee"])), 100, C_GOOD, 13))
		r.add_child(cell("$" + _k(int(s["salary"]) * 4) + tr("/мес"), 90, C_GOOD, 13))
		r.add_child(spacer())
		var ii: int = i
		var hb := small_btn(tr("Нанять"), func():
			var err: String = gs.hire_staff(ii)
			if err != "":
				gs.add_news(err)
			show_screen("scouting", false), C_GOOD)
		hb.disabled = gs.staff_level(s["role"]) > 0 or gs.money < int(s["fee"])
		r.add_child(hb)
		v.add_child(r)

func _unhandled_input(e: InputEvent) -> void:
	if not e.is_action_pressed("ui_cancel") or busy:
		return
	if top_label == null:
		if menu_right != null and is_instance_valid(menu_right):
			menu_page("home")
	elif not in_match:
		show_screen("system" if current != "system" else "dashboard")

# ------------------------------------------------------------ матч: подготовка

func on_play_match() -> void:
	var pm: Dictionary = gs.player_match()
	m = {"opp": pm["opp"], "bo": pm["bo"], "kind": pm["kind"], "wins": [0, 0], "game": 0, "stats": [], "played": [], "total": [0, 0], "sim": null, "log": null}
	for p in gs.lineup():
		m["stats"].append({"nick": p["nick"], "k": 0, "d": 0})
	show_prematch()

func show_prematch() -> void:
	in_match = true
	current = "match"
	clear(content)
	refresh_top()
	var gi: int = int(m["game"]) + 1
	content.add_child(title(tr("%s — карта %d (счёт серии %d:%d)") % [m["opp"], gi, m["wins"][0], m["wins"][1]]))
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	v.add_child(label(tr("Выбор карты"), 17, C_ACC))
	var avail: Array = []
	var pool_src: Array = gs.playable_maps() if gi == 1 else gs.map_pool
	for mm in gs.map_picks + pool_src:
		if not m["played"].has(mm) and not avail.has(mm) and pool_src.has(mm):
			avail.append(mm)
	if avail.is_empty():
		for mm in gs.map_pool:
			if not m["played"].has(mm):
				avail.append(mm)
	var map_ob := OptionButton.new()
	if gi == 1:
		for mm in avail:
			map_ob.add_item(tr("%s (наше мастерство %d)") % [mm, int(gs.map_skill[mm])])
		m["pick"] = avail[0]
		map_ob.item_selected.connect(func(i): m["pick"] = avail[i])
		v.add_child(map_ob)
	else:
		var forced: String = avail[randi() % avail.size()]
		m["pick"] = forced
		v.add_child(label(tr("Карта выбрана жребием: %s (мастерство %d)") % [forced, int(gs.map_skill[forced])], 15))
	v.add_child(label(tr("Стиль на карту"), 17, C_ACC))
	var so := OptionButton.new()
	var skeys: Array = gs.STYLES.keys()
	for k in skeys:
		so.add_item(tr(gs.STYLES[k]))
	so.selected = skeys.find(gs.style)
	var sdesc := label(tr(gs.STYLE_DESC[gs.style]), 13, C_DIM)
	so.item_selected.connect(func(i): gs.style = skeys[i]; sdesc.text = tr(gs.STYLE_DESC[skeys[i]]))
	v.add_child(so)
	v.add_child(sdesc)
	v.add_child(label(tr("Состав: ") + ", ".join(gs.lineup().map(func(x): return "%s (%s)" % [x["nick"], tr(x["role"])])), 13, C_DIM))
	v.add_child(btn(tr("Начать карту"), func(): start_map(), C_GOOD))
	content.add_child(p)

func start_map() -> void:
	var map_name: String = m["pick"]
	var sim = MatchSim.new()
	var l: Array = gs.lineup()
	sim.names = [gs.team_name, m["opp"]]
	var opp_l: Array = gs.world.filter(func(x): return str(x.get("team", "")) == str(m["opp"])).slice(0, 5)
	while opp_l.size() < 5:
		opp_l.append({"nick": "%s %d" % [str(m["opp"]).substr(0, 3).to_upper(), opp_l.size() + 1], "photo": "", "aim": 60})
	sim.nicks = [l.map(func(x): return x["nick"]), opp_l.map(func(x): return x["nick"])]
	sim.weights = [l.map(func(x): return float(x["aim"])), opp_l.map(func(x): return float(x.get("aim", 60)))]
	m["teamA"] = l.map(func(x): return {"nick": x["nick"], "photo": player_photo(x)})
	m["teamB"] = opp_l.map(func(x): return {"nick": x["nick"], "photo": player_photo(x) if x.has("role") else ""})
	var pw: Dictionary = gs.team_power(gs.style, map_name)
	var os: float = gs.opp_strength(m["opp"])
	sim.atk = [pw["atk"], os + randf_range(-2.5, 2.5)]
	sim.dfn = [pw["dfn"], os + randf_range(-2.5, 2.5)]
	sim.side_atk = randi_range(0, 1)
	m["sim"] = sim
	m["map"] = map_name
	m["tactic_open"] = false
	show_map_ui()

# ------------------------------------------------------------ матч: игра

func show_map_ui() -> void:
	clear(content)
	refresh_top()
	var sim = m["sim"]
	var hp := panel(C_PANEL, 14)
	var hv := vbox(6)
	hp.add_child(hv)
	var head := hbox(20)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(label(gs.team_name, 22, C_ACC))
	head.add_child(label("%d : %d" % [sim.score[0], sim.score[1]], 34))
	head.add_child(label(m["opp"], 22, C_CT))
	hv.add_child(head)
	var mine_side := tr("АТАКА (T)") if sim.side_atk == 0 else tr("ЗАЩИТА (CT)")
	var ot := tr(" · ОВЕРТАЙМ") if sim.is_overtime() else ""
	var c := label(tr("Карта: %s · Раунд %d · Вы: %s%s · Серия: %d:%d (BO%d)") % [m["map"], sim.rounds + 1, mine_side, ot, m["wins"][0], m["wins"][1], m["bo"]], 14, C_DIM)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(c)
	content.add_child(hp)
	var mv = preload("res://scripts/match_view.gd").new()
	mv.custom_minimum_size = Vector2(0, 420)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(mv)
	mv.setup(str(m["map"]), m.get("teamA", []), m.get("teamB", []), sim.side_atk)
	m["view"] = mv
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.custom_minimum_size = Vector2(0, 110)
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m["log"] = rt
	content.add_child(rt)
	if m.has("log_text"):
		rt.text = m["log_text"]
	var bar := hbox(8)
	bar.add_child(btn(tr("Следующий раунд"), func(): play(1), C_GOOD))
	bar.add_child(btn(tr("5 раундов"), func(): play(5)))
	bar.add_child(btn(tr("До конца карты"), func(): play(100)))
	var to := btn(tr("Тайм-аут (%d)") % sim.timeouts[0], func(): m["tactic_open"] = !m["tactic_open"]; show_map_ui())
	to.disabled = sim.timeouts[0] <= 0
	bar.add_child(to)
	content.add_child(bar)
	if m["tactic_open"]:
		var tp := panel(C_PANEL, 10)
		var tv := hbox(8)
		tp.add_child(tv)
		tv.add_child(label(tr("Тайм-аут: смените стиль (+%d к силе на 3 раунда)") % (3 + int(gs.coach_skill["tactics"] / 3)), 14))
		for k in gs.STYLES:
			var key: String = k
			tv.add_child(btn(tr(gs.STYLES[k]), func(): use_timeout(key)))
		content.add_child(tp)

func use_timeout(st: String) -> void:
	var sim = m["sim"]
	if sim.call_timeout(0, 3.0 + float(int(gs.coach_skill["tactics"]) / 3)):
		gs.style = st
		var pw: Dictionary = gs.team_power(st, m["map"])
		sim.atk[0] = pw["atk"]
		sim.dfn[0] = pw["dfn"]
		m["log_text"] = str(m.get("log_text", "")) + tr("[color=#ffb23e]Тайм-аут! Стиль: %s[/color]\n") % tr(gs.STYLES[st])
	m["tactic_open"] = false
	show_map_ui()

func play(n: int) -> void:
	if busy:
		return
	busy = true
	var sim = m["sim"]
	var i: int = 0
	while i < n and not sim.finished:
		var r: Dictionary = sim.play_round()
		var col := "#5dd16f" if r["winner"] == 0 else "#ff7b7b"
		var line := tr("[color=%s]Р%d  %d:%d[/color]  %s\n") % [col, r["round"], sim.score[0], sim.score[1], r["text"]]
		if r["swap"]:
			line = tr("[color=#ffb23e]— Смена сторон —[/color]\n") + line
		var modes := {"pistol": tr("пистолеты"), "full": tr("фулл-бай"), "force": tr("форс-бай"), "eco": tr("эко")}
		if get_node("/root/Settings").show_buys:
			line += tr("[color=#6b7280]   Закупка: вы — %s, соперник — %s[/color]\n") % [modes[r["buy"][0]], modes[r["buy"][1]]]
		m["log_text"] = str(m.get("log_text", "")) + line
		i += 1
		var mv = m.get("view", null)
		if n <= 5 and mv != null and is_instance_valid(mv) and mv.is_inside_tree():
			var dur: float = {"slow": 9.0, "normal": 6.0, "fast": 3.0}.get(get_node("/root/Settings").match_speed, 6.0) * (1.0 if n == 1 else 0.45)
			mv.play_round(r, int(r["side_atk"]), dur)
			if m.has("log") and is_instance_valid(m["log"]):
				m["log"].text = m["log_text"]
			await mv.round_done
			await get_tree().create_timer(0.6 if n == 1 else 0.25).timeout
		elif n > 1:
			await get_tree().create_timer(get_node("/root/Settings").round_delay()).timeout
		if not is_inside_tree():
			return
	busy = false
	if sim.finished:
		finish_map()
	else:
		show_map_ui()

func finish_map() -> void:
	var sim = m["sim"]
	var won: bool = sim.winner == 0
	m["wins"][sim.winner] += 1
	m["played"].append(m["map"])
	gs.note_map_played(m["map"])
	m["total"][0] += sim.score[0]
	m["total"][1] += sim.score[1]
	for i in m["stats"].size():
		m["stats"][i]["k"] += sim.kills[0][i]
		m["stats"][i]["d"] += sim.deaths[0][i]
	m["game"] += 1
	m["log_text"] = ""
	var need: int = (int(m["bo"]) + 1) / 2
	if m["wins"][0] >= need or m["wins"][1] >= need:
		show_match_result()
		return
	clear(content)
	refresh_top()
	var p := panel(C_PANEL, 20)
	var v := vbox(10)
	p.add_child(v)
	v.add_child(label(tr("Карта %s: %s %d:%d") % [m["map"], tr("победа") if won else tr("поражение"), sim.score[0], sim.score[1]], 24, C_GOOD if won else C_BAD))
	v.add_child(label(tr("Счёт в серии: %d:%d") % [m["wins"][0], m["wins"][1]], 18))
	v.add_child(btn(tr("Следующая карта"), func(): show_prematch(), C_GOOD))
	content.add_child(p)

func show_match_result() -> void:
	var won: bool = m["wins"][0] > m["wins"][1]
	clear(content)
	var p := panel(C_PANEL, 20)
	var v := vbox(8)
	p.add_child(v)
	v.add_child(label(tr("ПОБЕДА!") if won else tr("ПОРАЖЕНИЕ"), 36, C_GOOD if won else C_BAD))
	v.add_child(label(tr("%s %d:%d %s (по картам). Раундов: %d:%d") % [gs.team_name, m["wins"][0], m["wins"][1], m["opp"], m["total"][0], m["total"][1]], 17))
	v.add_child(label(tr("Статистика игроков"), 16, C_ACC))
	var best: Dictionary = {}
	for s in m["stats"]:
		var kd: float = float(s["k"]) / maxf(1.0, float(s["d"]))
		var r := hbox(6)
		r.add_child(cell(s["nick"], 140))
		r.add_child(cell("%d / %d" % [s["k"], s["d"]], 90))
		r.add_child(cell("K/D %.2f" % kd, 100, C_GOOD if kd >= 1.0 else C_BAD))
		v.add_child(r)
	v.add_child(btn(tr("Завершить матч"), func(): end_match(won), C_GOOD))
	content.add_child(p)

func end_match(won: bool) -> void:
	gs.report_match({"won": won, "my": m["total"][0], "opp": m["total"][1], "maps_my": m["wins"][0], "maps_opp": m["wins"][1], "stats": m["stats"]})
	in_match = false
	m = {}
	show_screen("dashboard")
