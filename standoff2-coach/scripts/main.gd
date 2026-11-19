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
	for st in [["normal", 0.18], ["hover", 0.38], ["pressed", 0.5], ["focus", 0.18], ["disabled", 0.05]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r, col.g, col.b, st[1])
		sb.border_color = col if st[0] != "disabled" else Color("3a3f4a")
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 26; sb.content_margin_right = 26
		sb.content_margin_top = 10; sb.content_margin_bottom = 10
		if st[0] == "hover":
			sb.shadow_color = Color(col.r, col.g, col.b, 0.45)
			sb.shadow_size = 10
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
	["Состав", "На карту выходят первые 5 здоровых игроков. Полный набор ролей (Капитан, Снайпер, Энтри, Саппорт, Лурк) даёт бонус к силе."],
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
	["dashboard", "Главная", "home"], ["mail", "Почта", "mail"], [],
	["squad", "Состав", "groups"], ["staff", "Штат", "badge"], ["training", "Тренировка", "fitness_center"],
	[], ["transfers", "Трансферы", "swap_horiz"], ["league", "Турниры", "emoji_events"], ["stats", "Статистика", "bar_chart"],
	[], ["finance", "Финансы", "payments"], ["coach", "Профиль", "account_circle"], [], ["system", "Настройки", "settings"],
]
const SCREEN_TITLES := {"dashboard": "Главная", "mail": "Почта", "squad": "Состав", "staff": "Штат", "training": "Тренировка",
	"transfers": "Трансферы", "league": "Турниры", "stats": "Статистика", "finance": "Финансы", "coach": "Профиль", "system": "Настройки", "match": "Матч", "player": "Игрок"}
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
	sb.bg_color = Color(0.09, 0.12, 0.17, 0.85)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
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

func screen_player() -> void:
	var pl: Dictionary = viewed_player
	if pl.is_empty():
		screen_squad()
		return
	gs.ensure_attrs(pl)
	# шапка
	var hc := _card()
	content.add_child(hc)
	var hh := hbox(18)
	hc.add_child(hh)
	hh.add_child(_circle(player_photo(pl), 110, Color(gs.team_color)))
	var hv := vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := hbox(10)
	nr.add_child(_flag(str(pl.get("country", "xx")), 30))
	nr.add_child(label(str(pl["nick"]), 30, Color.WHITE))
	hv.add_child(nr)
	var full: String = ("%s %s" % [tr(str(pl.get("first", ""))), tr(str(pl.get("last", "")))]).strip_edges()
	if full != "":
		hv.add_child(label(full, 15, Color("c9ced8")))
	var r2 := hbox(14)
	r2.add_child(_stars(_player_stars(pl), 18))
	r2.add_child(label(tr(pl["role"]), 15, C_ACC))
	r2.add_child(label(tr("%d лет") % int(pl["age"]), 15, C_DIM))
	hv.add_child(r2)
	var r3 := hbox(18)
	r3.add_child(label(tr("Форма") + " %d%%" % int(pl["form"]), 15, C_GOOD if int(pl["form"]) >= 70 else C_ACC))
	r3.add_child(label(tr("Зарплата") + " $%d" % int(pl["salary"]), 15, C_DIM))
	r3.add_child(label(tr("Потенциал") + " ~%d" % int(pl.get("pot_est", pl["pot"])), 15, C_DIM))
	hv.add_child(r3)
	hh.add_child(hv)
	var ob := vbox(0)
	var on := label(str(gs.ovr(pl)), 44, stat_color(gs.ovr(pl)))
	on.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ob.add_child(on)
	var ol := label(tr("ОБЩИЙ"), 12, C_DIM)
	ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ob.add_child(ol)
	hh.add_child(ob)
	var back := small_btn("<  " + tr("Назад"), func(): _hist_move(-1))
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hh.add_child(back)
	# характеристики
	var ab := _block(tr("Характеристики"))
	content.add_child(ab)
	var ac := _card()
	ab.add_child(ac)
	var cols := hbox(14)
	ac.add_child(cols)
	for grp in [[tr("ТЕХНИЧЕСКИЕ"), gs.ATTR_TECH], [tr("МЕНТАЛЬНЫЕ"), gs.ATTR_MENTAL], [tr("ФИЗИЧЕСКИЕ"), gs.ATTR_PHYS]]:
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
			var v: float = float(pl["attrs"].get(a[0], 0))
			var row := PanelContainer.new()
			var rs := StyleBoxFlat.new()
			rs.bg_color = Color(1, 1, 1, 0.025)
			rs.content_margin_left = 10; rs.content_margin_right = 10
			rs.content_margin_top = 6; rs.content_margin_bottom = 6
			row.add_theme_stylebox_override("panel", rs)
			var rh := hbox(6)
			row.add_child(rh)
			var nl := label(tr(a[1]), 15, Color("e9edf3"))
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rh.add_child(nl)
			rh.add_child(label("%.2f" % v, 16, _attr_color(v)))
			cv.add_child(row)
		cols.add_child(cv)

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

func screen_mail() -> void:
	if not gs.mail.is_empty():
		mail_sel = clampi(mail_sel, 0, gs.mail.size() - 1)
		gs.mail[mail_sel]["read"] = true
	content.add_child(_hdr_card("mail", tr("Почта"), tr("Писем: %d · непрочитанных: %d") % [gs.mail.size(), gs.unread_mail()]))
	if gs.mail.is_empty():
		var c0 := _card()
		c0.add_child(label(tr("Писем нет."), 14, C_DIM))
		content.add_child(c0)
		return
	mail_sel = clampi(mail_sel, 0, gs.mail.size() - 1)
	gs.mail[mail_sel]["read"] = true
	var cols := hbox(12)
	content.add_child(cols)
	var lc := _card()
	lc.custom_minimum_size = Vector2(380, 0)
	cols.add_child(lc)
	var lv := vbox(4)
	lc.add_child(lv)
	var kind_col := {"good": C_GOOD, "bad": C_BAD, "info": Color("5aa9ff")}
	for i in mini(gs.mail.size(), 14):
		var ml: Dictionary = gs.mail[i]
		var row := PanelContainer.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(0.2, 0.45, 0.85, 0.3) if i == mail_sel else Color(1, 1, 1, 0.03)
		rs.border_width_left = 4
		rs.border_color = kind_col.get(ml.get("kind", "info"), Color("5aa9ff"))
		rs.set_corner_radius_all(6)
		rs.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", rs)
		var rv := vbox(1)
		var top := hbox(6)
		top.add_child(label(str(ml["from"]), 12, C_DIM))
		top.add_child(spacer())
		top.add_child(label(tr("С%d Н%d") % [int(ml["season"]), int(ml["week"])], 11, C_DIM))
		rv.add_child(top)
		var sl := label(str(ml["subject"]), 14, Color.WHITE if not bool(ml["read"]) else Color("c9ced8"))
		if not bool(ml["read"]):
			sl.add_theme_font_override("font", UITheme.bold())
		sl.clip_text = true
		sl.custom_minimum_size = Vector2(330, 0)
		rv.add_child(sl)
		row.add_child(rv)
		var hit := Button.new()
		hit.flat = true
		for st in ["normal", "hover", "pressed", "focus"]:
			hit.add_theme_stylebox_override(st, _flat_style())
		var idx: int = i
		hit.pressed.connect(func(): mail_sel = idx; show_screen("mail", false))
		row.add_child(hit)
		_ignore_mouse(rv)
		lv.add_child(row)
	var ml2: Dictionary = gs.mail[mail_sel]
	var rc := _card()
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(rc)
	var rv2 := vbox(10)
	rc.add_child(rv2)
	rv2.add_child(label(str(ml2["subject"]), 20, Color.WHITE))
	rv2.add_child(label(tr("От: %s · сезон %d, неделя %d") % [ml2["from"], int(ml2["season"]), int(ml2["week"])], 12, C_DIM))
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.08)
	sep.custom_minimum_size = Vector2(0, 1)
	rv2.add_child(sep)
	rv2.add_child(wrap_label(str(ml2["body"]), 15, Color("d6dbe3"), 560))
	refresh_top()

# ------------------------------------------------------------ состав

func screen_squad() -> void:
	var pw: Dictionary = gs.team_power(gs.style, gs.train_map)
	content.add_child(_hdr_card("groups", tr("Состав"), tr("На карту выходят первые 5 здоровых игроков. Игроков: %d/%d") % [gs.players.size(), gs.MAX_ROSTER]))
	var tiles := hbox(10)
	var avg: float = 0.0
	var fsum: float = 0.0
	for p in gs.players:
		avg += gs.ovr(p)
		fsum += float(p["form"])
	var n: float = maxf(1.0, gs.players.size())
	tiles.add_child(_stat_tile(tr("Средний ОБЩ"), "%d" % int(avg / n), stat_color(int(avg / n)), "star"))
	tiles.add_child(_stat_tile(tr("Средняя форма"), "%d%%" % int(fsum / n), _form_col(int(fsum / n)), "favorite"))
	tiles.add_child(_stat_tile(tr("Атака"), "%.1f" % pw["atk"], C_ACC, "flash_on"))
	tiles.add_child(_stat_tile(tr("Защита"), "%.1f" % pw["dfn"], Color("5aa9ff"), "shield"))
	tiles.add_child(_stat_tile(tr("Зарплаты / нед."), money_fmt(gs.player_salaries()), C_DIM, "payments"))
	content.add_child(tiles)
	var c := _card()
	content.add_child(c)
	var v := vbox(4)
	c.add_child(v)
	var h := hbox(6)
	for e in [["", 44], ["", 22], [tr("Игрок"), 160], [tr("Роль"), 90], [tr("Воз"), 36], [tr("ОБЩ"), 44], [tr("Форма"), 130], [tr("Зарплата"), 70], [tr("Статус"), 96]]:
		h.add_child(cell(e[0], e[1], C_DIM, 12))
	v.add_child(h)
	var lineup_ids: Array = []
	for q in gs.lineup():
		lineup_ids.append(q["id"])
	for i in gs.players.size():
		var pl: Dictionary = gs.players[i]
		var starter: bool = lineup_ids.has(pl["id"])
		var row := PanelContainer.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(1, 1, 1, 0.045) if starter else Color(1, 1, 1, 0.015)
		rs.border_width_left = 3
		rs.border_color = Color(gs.team_color) if starter else Color(1, 1, 1, 0.1)
		rs.set_corner_radius_all(6)
		rs.content_margin_left = 6; rs.content_margin_top = 4; rs.content_margin_bottom = 4
		row.add_theme_stylebox_override("panel", rs)
		var r := hbox(6)
		row.add_child(r)
		r.add_child(portrait(pl, 40))
		r.add_child(_flag(str(pl.get("country", "xx")), 20))
		var nv := vbox(0)
		nv.custom_minimum_size = Vector2(160, 0)
		nv.add_child(_nick_link(pl, 160, Color.WHITE if starter else Color("c9ced8")))
		var full: String = ("%s %s" % [tr(str(pl.get("first", ""))), tr(str(pl.get("last", "")))]).strip_edges()
		if full != "":
			nv.add_child(label(full, 11, C_DIM))
		r.add_child(nv)
		r.add_child(cell(tr(pl["role"]), 90, C_ACC))
		r.add_child(cell(str(pl["age"]), 36, C_DIM))
		r.add_child(cell(str(gs.ovr(pl)), 44, stat_color(gs.ovr(pl)), 16))
		var fh := hbox(6)
		fh.custom_minimum_size = Vector2(130, 0)
		fh.add_child(_bar(float(pl["form"]), 100.0, _form_col(int(pl["form"])), 80))
		fh.add_child(label("%d%%" % int(pl["form"]), 12, _form_col(int(pl["form"]))))
		r.add_child(fh)
		r.add_child(cell("$" + str(pl["salary"]), 70, C_DIM))
		var st := tr("Основа") if starter else tr("Скамейка")
		var stc: Color = C_GOOD if starter else C_DIM
		if int(pl["inj"]) > 0:
			st = tr("Травма %dн") % int(pl["inj"])
			stc = C_BAD
		r.add_child(cell(st, 96, stc))
		r.add_child(spacer())
		var idx: int = i
		r.add_child(icon_btn("arrow_upward", tr("Вверх"), func(): gs.move_player(idx, -1); show_screen("squad", false)))
		r.add_child(icon_btn("arrow_downward", tr("Вниз"), func(): gs.move_player(idx, 1); show_screen("squad", false)))
		r.add_child(small_btn(tr("Продать"), func(): gs.sell_player(idx); show_screen("squad", false)))
		r.add_child(small_btn(tr("Отчислить"), func(): gs.release_player(idx); show_screen("squad", false), C_BAD))
		v.add_child(row)
	var roles: Array = []
	for q in gs.lineup():
		if not roles.has(q["role"]):
			roles.append(q["role"])
	var miss: Array = []
	for rr in gs.ROLES:
		if not roles.has(rr):
			miss.append(rr)
	content.add_child(_alert(tr("Полный набор ролей в основе: бонус +2 к силе!") if miss.is_empty() else tr("Не хватает ролей: %s") % ", ".join(miss.map(func(x): return tr(x))), miss.is_empty()))

# ------------------------------------------------------------ штат

func screen_staff() -> void:
	content.add_child(_hdr_card("badge", tr("Штат"), tr("Сотрудники усиливают команду. Зарплаты штаба: %s в неделю") % money_fmt(gs.staff_salaries())))
	var top := hbox(12)
	content.add_child(top)
	var mc := _card()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(mc)
	var mh := hbox(14)
	mc.add_child(mh)
	mh.add_child(_circle(gs.photo_path, 80, Color(gs.team_color)))
	var mv := vbox(2)
	mv.add_child(label("%s%s" % [gs.coach_name, (" \"%s\"" % gs.coach_nick) if gs.coach_nick != "" else ""], 18, Color.WHITE))
	mv.add_child(label(tr("Главный менеджер"), 13, C_ACC))
	mv.add_child(label(tr("Тактика %d · Мотивация %d · Скаутинг %d") % [int(gs.coach_skill["tactics"]), int(gs.coach_skill["motivation"]), int(gs.coach_skill["scout"])], 12, C_DIM))
	mh.add_child(mv)
	if gs.staff_coach != "":
		var cc := _card()
		cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(cc)
		var ch := hbox(14)
		cc.add_child(ch)
		ch.add_child(_circle(gs.staff_photo, 80))
		var cv := vbox(2)
		cv.add_child(label(gs.staff_coach, 18, Color.WHITE))
		cv.add_child(label(tr("Тренер состава"), 13, C_ACC))
		cv.add_child(label(tr("+1.5 к силе команды"), 12, C_DIM))
		ch.add_child(cv)
	var sb := _block(tr("Персонал"))
	content.add_child(sb)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sb.add_child(grid)
	for role in gs.STAFF_ROLES:
		var idx: int = -1
		for i in gs.staff_list.size():
			if gs.staff_list[i]["role"] == role:
				idx = i
		var c := _card()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size = Vector2(170, 210)
		var v := vbox(5)
		c.add_child(v)
		var rl := label(tr(gs.STAFF_ROLES[role][0]).to_upper(), 12, C_ACC)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rl)
		if idx >= 0:
			var s: Dictionary = gs.staff_list[idx]
			var pc := _circle(str(s["photo"]), 70)
			pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(pc)
			var nl := label(tr(str(s["name"]).split(" ")[0]) + " " + tr(str(s["name"]).split(" ")[1]) if str(s["name"]).split(" ").size() > 1 else str(s["name"]), 13, Color.WHITE)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(nl)
			var stl := _stars(float(s["lvl"]), 13)
			stl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(stl)
			var sl := label("$%d / %s" % [int(s["salary"]), tr("нед.")], 11, C_DIM)
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(sl)
			var ii: int = idx
			v.add_child(small_btn(tr("Уволить"), func(): gs.fire_staff(ii); show_screen("staff", false), C_BAD))
		else:
			var e := _circle("", 70, Color(1, 1, 1, 0.15))
			e.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(e)
			var vl := label(tr("Вакансия"), 13, C_DIM)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(vl)
			var dl := label(tr(gs.STAFF_ROLES[role][1]), 11, C_DIM)
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dl.custom_minimum_size = Vector2(150, 0)
			v.add_child(dl)
		grid.add_child(c)
	var hb := _block(tr("Кандидаты на найм"))
	content.add_child(hb)
	var hc := _card()
	hb.add_child(hc)
	var hv := vbox(4)
	hc.add_child(hv)
	for i in gs.staff_market.size():
		var s2: Dictionary = gs.staff_market[i]
		var r := hbox(10)
		r.add_child(_circle(str(s2["photo"]), 36))
		r.add_child(cell(str(s2["name"]), 170, Color.WHITE))
		r.add_child(cell(tr(gs.STAFF_ROLES[s2["role"]][0]), 160, C_ACC))
		r.add_child(_stars(float(s2["lvl"]), 13))
		r.add_child(cell(tr("Подъёмные %s") % money_fmt(int(s2["fee"])), 170, C_GOOD if gs.money >= int(s2["fee"]) else C_BAD, 12))
		r.add_child(cell("$%d / %s" % [int(s2["salary"]), tr("нед.")], 100, C_DIM, 12))
		r.add_child(spacer())
		var ii2: int = i
		var hire := small_btn(tr("Нанять"), func():
			var err: String = gs.hire_staff(ii2)
			if err != "":
				gs.add_news(err)
			show_screen("staff", false), C_GOOD)
		hire.disabled = gs.staff_level(s2["role"]) > 0
		r.add_child(hire)
		hv.add_child(r)

# ------------------------------------------------------------ тренировка

func screen_training() -> void:
	content.add_child(_hdr_card("fitness_center", tr("Тренировка"), tr("Фокус недели применяется при нажатии «Продолжить»")))
	var fb := _block(tr("Фокус тренировок"))
	content.add_child(fb)
	var fr := hbox(10)
	fb.add_child(fr)
	var icons := {"aim": "gps_fixed", "iq": "psychology", "tw": "diversity_3", "maps": "map", "rest": "hotel"}
	var desc := {"aim": tr("Навык, оружие, реакция. Утомляет игроков."), "iq": tr("Тактика, креативность, клатч. Утомляет игроков."), "tw": tr("Командная работа, лидерство, мораль. Слегка утомляет."), "maps": tr("Мастерство на выбранной карте."), "rest": tr("Игроки восстанавливают форму (+16%).")}
	for k in gs.TRAIN:
		var key: String = k
		fr.add_child(_sel_card(icons[k], tr(gs.TRAIN[k]), desc[k], gs.train_focus == k, func(): gs.train_focus = key; show_screen("training", false)))
	var sb := _block(tr("Стиль игры"))
	content.add_child(sb)
	var sr := hbox(10)
	sb.add_child(sr)
	var sicons := {"aggro": "local_fire_department", "balanced": "balance", "defense": "shield"}
	for k in gs.STYLES:
		var key2: String = k
		sr.add_child(_sel_card(sicons[k], tr(gs.STYLES[k]), tr(gs.STYLE_DESC[k]), gs.style == k, func(): gs.style = key2; show_screen("training", false), Color("5aa9ff")))
	var cols := hbox(12)
	content.add_child(cols)
	var mb := _block(tr("Пул карт"))
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(mb)
	var mc := _card()
	mb.add_child(mc)
	var mv := vbox(6)
	mc.add_child(mv)
	for mm in gs.MAPS:
		var r := hbox(10)
		var sel: bool = gs.train_focus == "maps" and gs.train_map == mm
		var mbn := small_btn(mm, func(): gs.train_map = mm; gs.train_focus = "maps"; show_screen("training", false), C_ACC if sel else Color.WHITE)
		mbn.custom_minimum_size = Vector2(110, 0)
		r.add_child(mbn)
		var bar := _bar(float(gs.map_skill[mm]), 100.0, Color("5aa9ff") if not sel else C_ACC, 220, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(bar)
		r.add_child(cell(str(int(gs.map_skill[mm])), 34, Color.WHITE))
		mv.add_child(r)
	mv.add_child(label(tr("Нажмите на карту, чтобы отработать её на этой неделе."), 11, C_DIM))
	var pb := _block(tr("Форма игроков"))
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(pb)
	var pc := _card()
	pb.add_child(pc)
	var pv := vbox(6)
	pc.add_child(pv)
	for p in gs.players:
		var r2 := hbox(10)
		r2.add_child(portrait(p, 30))
		r2.add_child(cell(p["nick"], 110, Color.WHITE))
		var b := _bar(float(p["form"]), 100.0, _form_col(int(p["form"])), 160, 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(b)
		r2.add_child(cell("%d%%" % int(p["form"]), 44, _form_col(int(p["form"]))))
		pv.add_child(r2)

# ------------------------------------------------------------ трансферы

var tr_role: String = ""
var tr_sort: String = "ovr"

func screen_transfers() -> void:
	content.add_child(_hdr_card("swap_horiz", tr("Трансферы"), tr("Свободные агенты. Состав: %d/%d · Бюджет: %s") % [gs.players.size(), gs.MAX_ROSTER, money_fmt(gs.money)]))
	var fr := hbox(8)
	fr.add_child(label(tr("Роль:"), 13, C_DIM))
	for rr in [""] + gs.ROLES:
		var key: String = rr
		var b := small_btn(tr("Все") if rr == "" else tr(rr), func(): tr_role = key; show_screen("transfers", false), C_ACC if tr_role == rr else Color.WHITE)
		fr.add_child(b)
	content.add_child(fr)
	fr = hbox(8)
	fr.add_child(label(tr("Сортировка:"), 13, C_DIM))
	for so in [["ovr", tr("ОБЩ")], ["pot", tr("Потенциал")], ["fee", tr("Цена")], ["age", tr("Возраст")]]:
		var sk: String = so[0]
		fr.add_child(small_btn(so[1], func(): tr_sort = sk; show_screen("transfers", false), C_ACC if tr_sort == sk else Color.WHITE))
	content.add_child(fr)
	var idxs: Array = []
	for i in gs.market.size():
		if tr_role == "" or gs.market[i]["role"] == tr_role:
			idxs.append(i)
	idxs.sort_custom(func(a, b):
		var pa: Dictionary = gs.market[a]
		var pb: Dictionary = gs.market[b]
		match tr_sort:
			"pot": return int(pa.get("pot_est", pa["pot"])) > int(pb.get("pot_est", pb["pot"]))
			"fee": return gs.fee(pa) < gs.fee(pb)
			"age": return int(pa["age"]) < int(pb["age"])
		return gs.ovr(pa) > gs.ovr(pb))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	if idxs.is_empty():
		content.add_child(label(tr("Нет игроков под фильтр."), 14, C_DIM))
	for i in idxs:
		var pl: Dictionary = gs.market[i]
		var c := _card()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := vbox(5)
		c.add_child(v)
		var h := hbox(10)
		h.add_child(portrait(pl, 54))
		var hv := vbox(0)
		var nr := hbox(5)
		nr.add_child(_flag(str(pl.get("country", "xx")), 18))
		nr.add_child(_nick_link(pl, 110, Color.WHITE))
		hv.add_child(nr)
		hv.add_child(label("%s · %d %s" % [tr(pl["role"]), int(pl["age"]), tr("лет")], 12, C_ACC))
		h.add_child(hv)
		h.add_child(spacer())
		var ov := vbox(0)
		ov.add_child(label(str(gs.ovr(pl)), 22, stat_color(gs.ovr(pl))))
		ov.add_child(label(tr("ОБЩ"), 10, C_DIM))
		h.add_child(ov)
		v.add_child(h)
		var pe: int = int(pl.get("pot_est", pl["pot"]))
		var pr := hbox(6)
		pr.add_child(label(tr("Потенциал"), 11, C_DIM))
		var pbar := _bar(float(pe), 100.0, Color("b18cff"), 80, 6)
		pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(pbar)
		pr.add_child(label("~%d" % pe, 11, Color("b18cff")))
		v.add_child(pr)
		var fee: int = gs.fee(pl)
		var br := hbox(6)
		var fv := vbox(0)
		fv.add_child(label(money_fmt(fee), 15, C_GOOD if gs.money >= fee else C_BAD))
		fv.add_child(label("$%d / %s" % [int(pl["salary"]), tr("нед.")], 10, C_DIM))
		br.add_child(fv)
		br.add_child(spacer())
		var idx: int = i
		var sb := small_btn(tr("Подписать"), func():
			var err: String = gs.sign_player(idx)
			if err != "":
				gs.add_news(err)
			show_screen("transfers", false), C_GOOD)
		sb.disabled = gs.money < fee or gs.players.size() >= gs.MAX_ROSTER
		br.add_child(sb)
		v.add_child(br)
		grid.add_child(c)

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
	for mm in gs.MAPS:
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
	sim.nicks = [l.map(func(x): return x["nick"]), []]
	sim.weights = [l.map(func(x): return float(x["aim"])), []]
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
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.custom_minimum_size = Vector2(0, 300)
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
		if n > 1:
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
