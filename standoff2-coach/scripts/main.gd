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

func _ready() -> void:
	gs = get_node("/root/GameState")
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
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func btn(t: String, cb: Callable, color: Color = Color.WHITE) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_color_override("font_color", color)
	b.pressed.connect(cb)
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
	h.add_child(label("НОВАЯ КАРЬЕРА", 28, C_ACC))
	h.add_child(label(step, 18, C_DIM))
	h.get_child(1).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(h)
	return root

func show_creator() -> void:
	if cr.is_empty():
		cr = {"name": "Алексей", "age": 32, "country": "Россия", "bg": "pro", "avatar": Avatar.random_cfg(), "photo": "", "variants": [], "err": ""}
		cr_photo = null
	if cr["variants"].is_empty():
		for i in 6:
			cr["variants"].append(Avatar.random_cfg())
	var root := _wizard_root("Шаг 1 из 2 · Создание менеджера")
	var body := hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# --- внешность
	var lp := panel(C_PANEL, 16)
	var lv := vbox(10)
	lp.add_child(lv)
	body.add_child(lp)
	var top := hbox(16)
	lv.add_child(top)
	top.add_child(make_avatar(cr["avatar"], 190, cr_photo))
	var tb := vbox(8)
	top.add_child(tb)
	tb.add_child(label("Внешность", 18, C_ACC))
	tb.add_child(btn("Случайная внешность", func():
		cr["avatar"] = Avatar.random_cfg(); show_creator()))
	tb.add_child(btn("Загрузить своё фото...", func(): open_photo_dialog()))
	if cr_photo != null:
		tb.add_child(btn("Убрать фото", func():
			cr_photo = null; cr["photo"] = ""; show_creator(), C_BAD))
		tb.add_child(wrap_label("Используется загруженное фото.", 13, C_GOOD, 200))
	else:
		tb.add_child(wrap_label("PNG / JPG / WEBP, фото обрежется до квадрата.", 13, C_DIM, 200))
	if str(cr.get("err", "")) != "":
		tb.add_child(wrap_label(cr["err"], 13, C_BAD, 200))
	lv.add_child(label("Варианты внешности — нажми, чтобы выбрать:", 14, C_DIM))
	var grid := hbox(6)
	for vcfg in cr["variants"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(66, 66)
		var av := make_avatar(vcfg, 58)
		av.position = Vector2(4, 4)
		b.add_child(av)
		var c: Dictionary = vcfg
		b.pressed.connect(func():
			cr["avatar"] = c.duplicate(); cr_photo = null; cr["photo"] = ""; show_creator())
		grid.add_child(b)
	lv.add_child(grid)
	lv.add_child(btn("Ещё варианты", func():
		cr["variants"] = []; show_creator()))
	# редактор частей
	var parts := GridContainer.new()
	parts.columns = 2
	parts.add_theme_constant_override("h_separation", 22)
	parts.add_theme_constant_override("v_separation", 4)
	for part in Avatar.PARTS:
		var key: String = part[0]
		var cnt: int = part[2]
		var row := hbox(4)
		row.add_child(cell(part[1], 92, C_DIM, 13))
		row.add_child(btn("<", func():
			cr["avatar"][key] = (int(cr["avatar"].get(key, 0)) - 1 + cnt) % cnt; show_creator()))
		var val := cell(Avatar.part_value_name(key, int(cr["avatar"].get(key, 0))), 96, Color.WHITE, 13)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(val)
		row.add_child(btn(">", func():
			cr["avatar"][key] = (int(cr["avatar"].get(key, 0)) + 1) % cnt; show_creator()))
		parts.add_child(row)
	lv.add_child(parts)

	# --- анкета
	var rp := panel(C_PANEL, 16)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := vbox(8)
	rp.add_child(rv)
	body.add_child(rp)
	rv.add_child(label("Анкета менеджера", 18, C_ACC))
	rv.add_child(label("Имя", 13, C_DIM))
	var name_edit := LineEdit.new()
	name_edit.text = cr["name"]
	name_edit.max_length = 24
	name_edit.placeholder_text = "Имя менеджера"
	name_edit.text_changed.connect(func(t): cr["name"] = t)
	rv.add_child(name_edit)
	var r2 := hbox(16)
	var agev := vbox(4)
	agev.add_child(label("Возраст", 13, C_DIM))
	var age := SpinBox.new()
	age.min_value = 21
	age.max_value = 65
	age.value = cr["age"]
	age.value_changed.connect(func(v): cr["age"] = int(v))
	agev.add_child(age)
	r2.add_child(agev)
	var cv := vbox(4)
	cv.add_child(label("Страна", 13, C_DIM))
	var co := OptionButton.new()
	for c2 in Teams.COUNTRIES:
		co.add_item(c2)
	co.selected = maxi(0, Teams.COUNTRIES.find(cr["country"]))
	co.item_selected.connect(func(i): cr["country"] = Teams.COUNTRIES[i])
	cv.add_child(co)
	r2.add_child(cv)
	rv.add_child(r2)
	rv.add_child(label("Предыстория (бонус на старте)", 13, C_DIM))
	var bgrid := GridContainer.new()
	bgrid.columns = 2
	bgrid.add_theme_constant_override("h_separation", 8)
	bgrid.add_theme_constant_override("v_separation", 8)
	for b2 in Teams.BACKGROUNDS:
		var id: String = b2["id"]
		var sel: bool = cr["bg"] == id
		var bp := panel(Color("3a2f1c") if sel else Color("262a33"), 10)
		bp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bb := vbox(2)
		bp.add_child(bb)
		bb.add_child(label(("> " if sel else "") + b2["name"], 15, C_ACC if sel else Color.WHITE))
		bb.add_child(label(b2["desc"], 12, C_DIM))
		var hit := Button.new()
		hit.flat = true
		hit.set_anchors_preset(Control.PRESET_FULL_RECT)
		hit.pressed.connect(func(): cr["bg"] = id; show_creator())
		bp.add_child(hit)
		bgrid.add_child(bp)
	rv.add_child(bgrid)

	var bottom := hbox(12)
	bottom.add_child(btn("Назад в меню", func(): cr = {}; show_menu(), C_DIM))
	bottom.add_child(spacer())
	if gs.has_save():
		bottom.add_child(label("Текущее сохранение будет перезаписано", 13, C_BAD))
	bottom.add_child(menu_btn("Далее: выбор команды", func():
		if str(cr["name"]).strip_edges() == "":
			cr["err"] = "Введите имя менеджера."
			show_creator()
			return
		cr["err"] = ""
		show_team_select(), true))
	root.add_child(bottom)

func open_photo_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Изображения"])
	fd.title = "Выберите фото менеджера"
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
		cr["err"] = "Не удалось открыть изображение."
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

func show_team_select() -> void:
	var root := _wizard_root("Шаг 2 из 2 · Выбор команды")
	var info := hbox(12)
	info.add_child(make_avatar(cr["avatar"], 44, cr_photo))
	info.add_child(label("%s, %d лет · выберите клуб, который возглавите" % [cr["name"], cr["age"]], 16, C_DIM))
	info.get_child(1).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(info)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	sc.add_child(grid)
	for t in Teams.START_TEAMS:
		grid.add_child(team_card(t))
	# своя команда
	var cp := panel(C_PANEL, 14)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv := vbox(6)
	cp.add_child(cv)
	cv.add_child(label("СВОЯ КОМАНДА", 18, C_ACC))
	cv.add_child(label("Сложно", 13, C_BAD))
	var ne := LineEdit.new()
	ne.placeholder_text = "Название"
	ne.max_length = 24
	cv.add_child(ne)
	var te := LineEdit.new()
	te.placeholder_text = "Тег (до 4 букв)"
	te.max_length = 4
	cv.add_child(te)
	cv.add_child(wrap_label("Создайте организацию с нуля: скромный бюджет и молодой состав.", 12, C_DIM, 230))
	var err := label("", 12, C_BAD)
	cv.add_child(err)
	cv.add_child(btn("Создать и начать", func():
		var n: String = ne.text.strip_edges()
		if n == "":
			err.text = "Введите название команды."
			return
		var tag: String = te.text.strip_edges().to_upper()
		if tag == "": tag = n.substr(0, 3).to_upper()
		start_career({"name": n, "tag": tag, "color": "ffffff", "diff": 2, "base": 43.0, "money": 60000, "rep": 10.0}), C_GOOD))
	grid.add_child(cp)
	var bottom := hbox(12)
	bottom.add_child(btn("Назад к менеджеру", func(): show_creator(), C_DIM))
	root.add_child(bottom)

func team_card(t: Dictionary) -> Control:
	var p := panel(C_PANEL, 14)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := vbox(5)
	p.add_child(v)
	var h := hbox(10)
	var badge := panel(Color(t["color"]).darkened(0.55), 8)
	badge.add_child(label(t["tag"], 16, Color(t["color"])))
	h.add_child(badge)
	var d: int = int(t["diff"])
	var dl := label(Teams.DIFF_NAMES[d], 13, Color(Teams.DIFF_COLORS[d]))
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dl)
	v.add_child(h)
	v.add_child(label(t["name"], 18))
	v.add_child(label("Уровень состава: ~%d" % int(t["base"]), 13, C_DIM))
	v.add_child(label("Бюджет: %s" % money_fmt(int(t["money"])), 13, C_DIM))
	v.add_child(label("Репутация: %d" % int(t["rep"]), 13, C_DIM))
	v.add_child(wrap_label(t["desc"], 12, C_DIM, 230))
	var f := Control.new()
	f.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(f)
	var team: Dictionary = t
	v.add_child(btn("Выбрать", func(): start_career(team), C_GOOD))
	return p

func start_career(team: Dictionary) -> void:
	var photo := ""
	if str(cr.get("photo", "")) != "" and FileAccess.file_exists(TMP_PHOTO):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(TMP_PHOTO), ProjectSettings.globalize_path(gs.PHOTO_PATH))
		photo = gs.PHOTO_PATH
	gs.new_game({"name": cr["name"], "age": cr["age"], "country": cr["country"], "bg": cr["bg"], "avatar": cr["avatar"], "photo": photo}, team)
	cr = {}
	cr_photo = null
	build_game()
var menu_right: VBoxContainer

func _clear_root() -> void:
	for c in get_children():
		if c is ColorRect and c.name == "BG":
			continue
		remove_child(c)
		c.queue_free()
	top_label = null

func menu_btn(t: String, cb: Callable, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = "   " + t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(340, 48)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", C_ACC if accent else Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.BLACK)
	b.add_theme_color_override("font_pressed_color", Color.BLACK)
	b.add_theme_color_override("font_disabled_color", Color("4b5260"))
	for st in [["normal", Color("1f232b"), 0], ["hover", C_ACC, 6], ["pressed", Color("e09a2c"), 6], ["disabled", Color("181b21"), 0], ["focus", Color(0, 0, 0, 0), 0]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.set_corner_radius_all(6)
		sb.border_width_left = 6
		sb.border_color = C_ACC if st[0] == "normal" and accent else Color(st[1]).darkened(0.25)
		if st[0] == "focus":
			sb.border_width_left = 0
			sb.border_width_bottom = 2
			sb.border_color = C_ACC
		b.add_theme_stylebox_override(st[0], sb)
	b.pressed.connect(cb)
	return b

func _stripe(x: float, w: float, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.size = Vector2(w, 2400)
	r.position = Vector2(x, -600)
	r.rotation = deg_to_rad(18)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func show_menu() -> void:
	in_match = false
	busy = false
	_clear_root()
	# фон: диагональные полосы
	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.clip_contents = true
	add_child(deco)
	deco.add_child(_stripe(760, 260, Color(1, 0.7, 0.24, 0.05)))
	deco.add_child(_stripe(1060, 60, Color(1, 0.7, 0.24, 0.10)))
	deco.add_child(_stripe(1160, 18, Color(0.35, 0.66, 1.0, 0.18)))
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 80; root.offset_top = 44; root.offset_right = -60; root.offset_bottom = -24
	root.add_theme_constant_override("separation", 60)
	add_child(root)
	var left := vbox(10)
	left.custom_minimum_size = Vector2(360, 0)
	root.add_child(left)
	left.add_child(label("STANDOFF", 64, Color.WHITE))
	var c2 := label("COACH", 64, C_ACC)
	c2.add_theme_constant_override("line_spacing", -10)
	left.add_child(c2)
	left.add_child(label("Карьера тренера по Standoff 2", 16, C_DIM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	left.add_child(gap)
	if gs.has_save():
		left.add_child(menu_btn("Продолжить", func():
			if gs.load_game():
				build_game(), true))
	left.add_child(menu_btn("Новая карьера", func(): menu_page("new"), not gs.has_save()))
	left.add_child(menu_btn("Настройки", func(): menu_page("settings")))
	left.add_child(menu_btn("Как играть", func(): menu_page("howto")))
	left.add_child(menu_btn("Об игре", func(): menu_page("about")))
	left.add_child(menu_btn("Выход", func(): get_tree().quit()))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	left.add_child(label("%s · Godot 4.2 · фан-проект, не связан с разработчиками Standoff 2" % VERSION, 12, Color("5b6270")))
	menu_right = vbox(12)
	menu_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(menu_right)
	menu_page("home")

func _menu_card(t: String) -> VBoxContainer:
	clear(menu_right)
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 40)
	menu_right.add_child(top)
	var p := panel(Color(0.12, 0.137, 0.168, 0.94), 26)
	menu_right.add_child(p)
	var v := vbox(12)
	p.add_child(v)
	v.add_child(label(t, 28, C_ACC))
	return v

func menu_page(page: String) -> void:
	match page:
		"home":
			var v := _menu_card("Последнее сохранение" if gs.has_save() else "Добро пожаловать, тренер")
			if gs.has_save():
				var d = _peek_save()
				if d is Dictionary:
					var hr := hbox(14)
					var tex: Texture2D = null
					var pp: String = str(d.get("photo_path", ""))
					if pp != "" and FileAccess.file_exists(pp):
						var im := Image.load_from_file(pp)
						if im: tex = ImageTexture.create_from_image(im)
					hr.add_child(make_avatar(d.get("avatar", {}), 72, tex))
					var hv := vbox(2)
					hv.add_child(label(str(d.get("team_name", "")), 22))
					hv.add_child(label("Менеджер: %s" % d.get("coach_name", ""), 15, C_DIM))
					hr.add_child(hv)
					v.add_child(hr)
					v.add_child(label("Сезон %d · неделя %d/10 · %s" % [int(d.get("season", 1)), int(d.get("week", 1)), gs.TIERS[int(d.get("tier", 0))]], 15, C_DIM))
					v.add_child(label("Деньги: %s · Репутация: %d · Титулов: %d" % [money_fmt(int(d.get("money", 0))), int(d.get("rep", 0)), int(d.get("titles", 0))], 15, C_DIM))
					if str(d.get("game_over", "")) != "":
						v.add_child(label("Карьера завершена: " + str(d["game_over"]), 14, C_BAD))
			else:
				v.add_child(label("Возьми под крыло команду новичков из Открытой лиги,\nпрокачай игроков, выстрой тактику и доведи их\nдо титула Мировой серии.", 16, C_DIM))
				v.add_child(menu_btn("Начать карьеру", func(): menu_page("new"), true))
		"new":
			show_creator()
		"settings":
			var v := _menu_card("Настройки")
			build_settings(v, func(): menu_page("settings"))
			v.add_child(btn("Назад", func(): menu_page("home"), C_DIM))
		"howto":
			var v := _menu_card("Как играть")
			for t in [
				"Каждую неделю выбирай фокус тренировок и стиль игры, затем жми «К матчу».",
				"Перед матчем выбери карту — команда сильнее на картах с высоким мастерством.",
				"Во время матча можно взять 2 тайм-аута за карту: смена стиля и бонус на 3 раунда.",
				"Следи за формой игроков: после тяжёлых тренировок давай отдых.",
				"Полный набор ролей в основе (Капитан, Снайпер, Энтри, Саппорт, Лурк) даёт бонус.",
				"Топ-4 лиги выходят в плей-офф, топ-2 повышаются в дивизионе, двое последних вылетают.",
				"Победы дают очки тренера — вкладывай их в тактику, мотивацию и скаутинг.",
				"Два провала целей совета подряд или долг больше $40 000 — увольнение."]:
				v.add_child(label("•  " + t, 15))
			v.add_child(btn("Назад", func(): menu_page("home"), C_DIM))
		"about":
			var v := _menu_card("Об игре")
			v.add_child(label("Standoff Coach %s" % VERSION, 18))
			v.add_child(label("Менеджер киберспортивной команды по мотивам Standoff 2.\nСделано на Godot 4.2. Все команды и игроки вымышлены.\nФан-проект, не связан с разработчиками Standoff 2.", 15, C_DIM))
			v.add_child(btn("Назад", func(): menu_page("home"), C_DIM))
		"confirm_delete":
			var v := _menu_card("Удалить сохранение?")
			v.add_child(label("Карьера будет удалена без возможности восстановления.", 15, C_BAD))
			var row := hbox(10)
			row.add_child(btn("Да, удалить", func():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.SAVE_PATH))
				show_menu(), C_BAD))
			row.add_child(btn("Отмена", func(): menu_page("settings")))
			v.add_child(row)

func _peek_save():
	var f := FileAccess.open(gs.SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

## Общий блок настроек — используется и в главном меню, и в игре.
func build_settings(v: VBoxContainer, refresh: Callable) -> void:
	var st: Node = get_node("/root/Settings")
	v.add_child(label("Экран", 17, C_ACC))
	var fs := CheckButton.new()
	fs.text = "Полноэкранный режим"
	fs.button_pressed = st.fullscreen
	fs.toggled.connect(func(on): st.fullscreen = on; st.apply(); st.save_settings())
	v.add_child(fs)
	var vs := CheckButton.new()
	vs.text = "Вертикальная синхронизация (VSync)"
	vs.button_pressed = st.vsync
	vs.toggled.connect(func(on): st.vsync = on; st.apply(); st.save_settings())
	v.add_child(vs)
	var r1 := hbox(10)
	r1.add_child(cell("Масштаб интерфейса", 260))
	var sc := OptionButton.new()
	for s in st.UI_SCALES:
		sc.add_item("%d%%" % int(round(s * 100)))
	sc.selected = maxi(0, st.UI_SCALES.find(st.ui_scale))
	sc.item_selected.connect(func(i): st.ui_scale = st.UI_SCALES[i]; st.apply(); st.save_settings())
	r1.add_child(sc)
	v.add_child(r1)
	v.add_child(label("Игра", 17, C_ACC))
	var r2 := hbox(10)
	r2.add_child(cell("Скорость симуляции матча", 260))
	var sp := OptionButton.new()
	var keys: Array = st.SPEED_NAMES.keys()
	for k in keys:
		sp.add_item(st.SPEED_NAMES[k])
	sp.selected = maxi(0, keys.find(st.match_speed))
	sp.item_selected.connect(func(i): st.match_speed = keys[i]; st.save_settings())
	r2.add_child(sp)
	v.add_child(r2)
	var au := CheckButton.new()
	au.text = "Автосохранение после каждой недели"
	au.button_pressed = st.autosave
	au.toggled.connect(func(on): st.autosave = on; st.save_settings())
	v.add_child(au)
	var sb := CheckButton.new()
	sb.text = "Показывать закупку команд в логе матча"
	sb.button_pressed = st.show_buys
	sb.toggled.connect(func(on): st.show_buys = on; st.save_settings())
	v.add_child(sb)
	var row := hbox(10)
	row.add_child(btn("Сбросить настройки", func(): st.reset(); refresh.call()))
	if gs.has_save() and top_label == null:
		row.add_child(btn("Удалить сохранение", func(): menu_page("confirm_delete"), C_BAD))
	v.add_child(row)

# ------------------------------------------------------------ каркас игры

func build_game() -> void:
	_clear_root()
	var root := vbox(8)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12; root.offset_top = 12; root.offset_right = -12; root.offset_bottom = -12
	add_child(root)
	var top := panel(C_PANEL, 8)
	var th := hbox(12)
	top.add_child(th)
	photo_tex = gs.load_photo()
	th.add_child(make_avatar(gs.avatar, 38, photo_tex))
	var badge := label(gs.team_tag, 16, Color(gs.team_color))
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	th.add_child(badge)
	top_label = label("", 17, Color.WHITE)
	top_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	th.add_child(top_label)
	root.add_child(top)
	var body := hbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var navp := panel(C_PANEL, 10)
	nav_box = vbox(6)
	nav_box.custom_minimum_size = Vector2(190, 0)
	navp.add_child(nav_box)
	body.add_child(navp)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	content = vbox(10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	var lp := panel(C_PANEL, 8)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.custom_minimum_size = Vector2(0, 74)
	log_label.scroll_following = true
	lp.add_child(log_label)
	root.add_child(lp)
	for e in [["dashboard", "Главная"], ["squad", "Состав"], ["training", "Тренировки и тактика"], ["transfers", "Трансферы"], ["league", "Лига"], ["coach", "Тренер"], ["system", "Меню / сохранение"]]:
		var key: String = e[0]
		nav_box.add_child(btn(e[1], func(): show_screen(key)))
	show_screen("dashboard")

func refresh_top() -> void:
	if top_label == null:
		return
	top_label.text = "%s  |  Сезон %d · Неделя %d/10 · %s  |  %s  |  Деньги: %s  |  Репутация: %d" % [gs.team_name, gs.season, gs.week, gs.TIERS[gs.tier], gs.phase_name(), money_fmt(gs.money), int(gs.rep)]
	var t := ""
	for i in min(4, gs.news.size()):
		t += "[color=#9aa3b2]%s[/color]\n" % gs.news[i]
	log_label.text = t.strip_edges()

func show_screen(name: String) -> void:
	if busy:
		return
	current = name
	in_match = false
	clear(content)
	refresh_top()
	if gs.game_over != "":
		show_game_over()
		return
	match name:
		"dashboard": screen_dashboard()
		"squad": screen_squad()
		"training": screen_training()
		"transfers": screen_transfers()
		"league": screen_league()
		"coach": screen_coach()
		"system": screen_system()
		_: screen_dashboard()

func show_game_over() -> void:
	var p := panel(C_PANEL, 24)
	var v := vbox(12)
	p.add_child(v)
	v.add_child(label("КАРЬЕРА ЗАВЕРШЕНА", 32, C_BAD))
	v.add_child(label(gs.game_over, 16))
	v.add_child(label("Сезонов: %d · Титулов: %d" % [gs.season, gs.titles], 15, C_DIM))
	v.add_child(btn("В главное меню", func(): show_menu()))
	content.add_child(p)

func title(t: String) -> Label:
	return label(t, 24, C_ACC)

# ------------------------------------------------------------ главная

func screen_dashboard() -> void:
	content.add_child(title("Главная"))
	var pm: Dictionary = gs.player_match()
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	v.add_child(label(gs.phase_name(), 18, C_ACC))
	var main_btn: Button
	if gs.week > 9:
		v.add_child(label("Межсезонье: подпишите игроков, потратьте очки тренера и подготовьтесь к новому сезону.", 14, C_DIM))
		main_btn = btn("Начать новый сезон", on_finish_week, C_GOOD)
	elif pm.is_empty():
		v.add_child(label("На этой неделе у вас нет матча.", 15, C_DIM))
		main_btn = btn("Завершить неделю", on_finish_week, C_GOOD)
	elif gs.match_done:
		v.add_child(label("Матч против %s сыгран." % pm["opp"], 15, C_GOOD))
		main_btn = btn("Завершить неделю", on_finish_week, C_GOOD)
	else:
		var kinds := {"league": "Матч лиги (BO1)", "semi": "Полуфинал плей-офф (BO3)", "final": "ФИНАЛ плей-офф (BO3)"}
		v.add_child(label("%s: %s против %s" % [kinds[pm["kind"]], gs.team_name, pm["opp"]], 17))
		var s: float = gs.opp_strength(pm["opp"])
		var mine: float = gs.team_power(gs.style, gs.train_map)["base"]
		var d: float = s - mine
		var verdict := "примерно равны"
		var col := Color.WHITE
		if d > 6: verdict = "соперник заметно сильнее"; col = C_BAD
		elif d > 2: verdict = "соперник немного сильнее"; col = C_ACC
		elif d < -6: verdict = "вы заметно сильнее"; col = C_GOOD
		elif d < -2: verdict = "вы немного сильнее"; col = C_GOOD
		var scout_txt := verdict
		if int(gs.coach_skill["scout"]) >= 3:
			scout_txt += " (рейтинг %d против ваших %d)" % [int(s), int(mine)]
		v.add_child(label("Оценка скаутов: " + scout_txt, 14, col))
		if not gs.has_enough_players():
			v.add_child(label("Недостаточно здоровых игроков (нужно 5)! Подпишите кого-нибудь.", 14, C_BAD))
			main_btn = btn("Играть матч", func(): pass, C_DIM)
			main_btn.disabled = true
		else:
			main_btn = btn("К матчу", on_play_match, C_GOOD)
	v.add_child(main_btn)
	content.add_child(p)

	# турнирная таблица
	var tp := panel()
	var tv := vbox(4)
	tp.add_child(tv)
	tv.add_child(label("Таблица лиги", 17, C_ACC))
	tv.add_child(table_header())
	var rl: Array = gs.rank_list()
	for i in rl.size():
		tv.add_child(table_row(i + 1, rl[i]))
	content.add_child(tp)

	var np := panel()
	var nv := vbox(3)
	np.add_child(nv)
	nv.add_child(label("Новости", 17, C_ACC))
	for i in min(8, gs.news.size()):
		nv.add_child(label(gs.news[i], 13, C_DIM))
	content.add_child(np)

func table_header() -> HBoxContainer:
	var h := hbox(4)
	h.add_child(cell("#", 30, C_DIM)); h.add_child(cell("Команда", 220, C_DIM)); h.add_child(cell("В", 40, C_DIM)); h.add_child(cell("П", 40, C_DIM)); h.add_child(cell("Раунды ±", 80, C_DIM))
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

# ------------------------------------------------------------ состав

func screen_squad() -> void:
	content.add_child(title("Состав (первые 5 здоровых игроков выходят на карту)"))
	var p := panel()
	var v := vbox(5)
	p.add_child(v)
	var h := hbox(4)
	for e in [["Ник", 130], ["Роль", 80], ["Воз", 40], ["Аим", 44], ["ИИ", 44], ["Сыг", 44], ["ОБЩ", 48], ["Форма", 60], ["Зарплата", 80], ["Статус", 110]]:
		h.add_child(cell(e[0], e[1], C_DIM, 13))
	v.add_child(h)
	var lineup_ids: Array = []
	for q in gs.lineup():
		lineup_ids.append(q["id"])
	for i in gs.players.size():
		var pl: Dictionary = gs.players[i]
		var r := hbox(4)
		var starter: bool = lineup_ids.has(pl["id"])
		r.add_child(cell(pl["nick"], 130, C_ACC if starter else C_DIM))
		r.add_child(cell(pl["role"], 80))
		r.add_child(cell(str(pl["age"]), 40, C_DIM))
		r.add_child(cell(str(pl["aim"]), 44, stat_color(pl["aim"])))
		r.add_child(cell(str(pl["iq"]), 44, stat_color(pl["iq"])))
		r.add_child(cell(str(pl["tw"]), 44, stat_color(pl["tw"])))
		r.add_child(cell(str(gs.ovr(pl)), 48, stat_color(gs.ovr(pl))))
		var fc: Color = C_GOOD if pl["form"] >= 70 else (C_ACC if pl["form"] >= 45 else C_BAD)
		r.add_child(cell(str(pl["form"]) + "%", 60, fc))
		r.add_child(cell("$" + str(pl["salary"]), 80, C_DIM))
		var st := "Основа" if starter else "Скамейка"
		var stc: Color = C_GOOD if starter else C_DIM
		if pl["inj"] > 0:
			st = "Травма %dн" % pl["inj"]
			stc = C_BAD
		r.add_child(cell(st, 110, stc))
		var idx: int = i
		r.add_child(btn("Вверх", func(): gs.move_player(idx, -1); show_screen("squad")))
		r.add_child(btn("Вниз", func(): gs.move_player(idx, 1); show_screen("squad")))
		r.add_child(btn("Продать", func(): gs.sell_player(idx); show_screen("squad")))
		r.add_child(btn("Отчислить", func(): gs.release_player(idx); show_screen("squad"), C_BAD))
		v.add_child(r)
	content.add_child(p)
	var roles: Array = []
	for q in gs.lineup():
		if not roles.has(q["role"]):
			roles.append(q["role"])
	var miss: Array = []
	for rr in gs.ROLES:
		if not roles.has(rr):
			miss.append(rr)
	var info := label("Роли в основе: %d/5.%s" % [roles.size(), (" Не хватает: " + ", ".join(miss) + " (бонус к силе команды)") if miss.size() > 0 else " Полный набор ролей: бонус +2!"], 14, C_DIM)
	content.add_child(info)
	var pw: Dictionary = gs.team_power(gs.style, gs.train_map)
	content.add_child(label("Сила команды: атака %.1f · защита %.1f" % [pw["atk"], pw["dfn"]], 15, C_ACC))

# ------------------------------------------------------------ тренировки

func screen_training() -> void:
	content.add_child(title("Тренировки и тактика"))
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	v.add_child(label("Недельный фокус тренировок", 17, C_ACC))
	var ob := OptionButton.new()
	var keys: Array = gs.TRAIN.keys()
	for k in keys:
		ob.add_item(gs.TRAIN[k])
	ob.selected = keys.find(gs.train_focus)
	ob.item_selected.connect(func(i): gs.train_focus = keys[i]; show_screen("training"))
	v.add_child(ob)
	if gs.train_focus == "maps":
		var mo := OptionButton.new()
		for mm in gs.MAPS:
			mo.add_item("%s (мастерство %d)" % [mm, int(gs.map_skill[mm])])
		mo.selected = gs.MAPS.find(gs.train_map)
		mo.item_selected.connect(func(i): gs.train_map = gs.MAPS[i]; show_screen("training"))
		v.add_child(mo)
	var desc := {"aim": "Растёт аим. Утомляет игроков.", "iq": "Растёт игровое мышление. Утомляет игроков.", "tw": "Растёт сыгранность. Слегка утомляет.", "maps": "Команда лучше знает выбранную карту (+бонус к силе на ней).", "rest": "Игроки восстанавливают форму (+16%)."}
	v.add_child(label(desc[gs.train_focus], 14, C_DIM))
	content.add_child(p)

	var tp := panel()
	var tv := vbox(8)
	tp.add_child(tv)
	tv.add_child(label("Стиль игры", 17, C_ACC))
	var so := OptionButton.new()
	var skeys: Array = gs.STYLES.keys()
	for k in skeys:
		so.add_item(gs.STYLES[k])
	so.selected = skeys.find(gs.style)
	so.item_selected.connect(func(i): gs.style = skeys[i]; show_screen("training"))
	tv.add_child(so)
	tv.add_child(label(gs.STYLE_DESC[gs.style], 14, C_DIM))
	content.add_child(tp)

	var mp := panel()
	var mv := vbox(4)
	mp.add_child(mv)
	mv.add_child(label("Пул карт", 17, C_ACC))
	for mm in gs.MAPS:
		var r := hbox(8)
		r.add_child(cell(mm, 120))
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = int(gs.map_skill[mm])
		bar.custom_minimum_size = Vector2(240, 18)
		bar.show_percentage = false
		r.add_child(bar)
		r.add_child(cell(str(int(gs.map_skill[mm])), 40, C_DIM))
		mv.add_child(r)
	content.add_child(mp)

# ------------------------------------------------------------ трансферы

func screen_transfers() -> void:
	content.add_child(title("Рынок свободных агентов"))
	content.add_child(label("Состав: %d/%d · Деньги: %s · Скаутинг ур.%d (чем выше — тем точнее оценка потенциала)" % [gs.players.size(), gs.MAX_ROSTER, money_fmt(gs.money), int(gs.coach_skill["scout"])], 14, C_DIM))
	var p := panel()
	var v := vbox(5)
	p.add_child(v)
	var h := hbox(4)
	for e in [["Ник", 130], ["Роль", 80], ["Воз", 40], ["Аим", 44], ["ИИ", 44], ["Сыг", 44], ["ОБЩ", 48], ["Потенциал", 80], ["Цена", 90], ["Зарплата", 80]]:
		h.add_child(cell(e[0], e[1], C_DIM, 13))
	v.add_child(h)
	for i in gs.market.size():
		var pl: Dictionary = gs.market[i]
		var r := hbox(4)
		r.add_child(cell(pl["nick"], 130, C_ACC))
		r.add_child(cell(pl["role"], 80))
		r.add_child(cell(str(pl["age"]), 40, C_DIM))
		r.add_child(cell(str(pl["aim"]), 44, stat_color(pl["aim"])))
		r.add_child(cell(str(pl["iq"]), 44, stat_color(pl["iq"])))
		r.add_child(cell(str(pl["tw"]), 44, stat_color(pl["tw"])))
		r.add_child(cell(str(gs.ovr(pl)), 48, stat_color(gs.ovr(pl))))
		var pe: int = int(pl.get("pot_est", pl["pot"]))
		r.add_child(cell("~%d" % pe if int(gs.coach_skill["scout"]) < 6 else str(pe), 80, stat_color(pe)))
		var fee: int = gs.fee(pl)
		r.add_child(cell("$" + str(fee), 90, C_GOOD if gs.money >= fee else C_BAD))
		r.add_child(cell("$" + str(pl["salary"]), 80, C_DIM))
		var idx: int = i
		var b := btn("Подписать", func():
			var err: String = gs.sign_player(idx)
			if err != "":
				gs.add_news(err)
			show_screen("transfers"))
		r.add_child(b)
		v.add_child(r)
	content.add_child(p)

# ------------------------------------------------------------ лига

func screen_league() -> void:
	content.add_child(title("Лига: %s" % gs.TIERS[gs.tier]))
	var p := panel()
	var v := vbox(4)
	p.add_child(v)
	v.add_child(table_header())
	var rl: Array = gs.rank_list()
	for i in rl.size():
		v.add_child(table_row(i + 1, rl[i]))
	v.add_child(label("Топ-4 выходят в плей-офф. Топ-2 повышаются в дивизионе, два последних — вылетают.", 13, C_DIM))
	content.add_child(p)
	var pp := panel()
	var pv := vbox(4)
	pp.add_child(pv)
	pv.add_child(label("Плей-офф", 17, C_ACC))
	if gs.playoff["semis"].is_empty():
		pv.add_child(label("Начнётся после 7-го тура.", 14, C_DIM))
	else:
		for i in gs.playoff["semis"].size():
			var s: Array = gs.playoff["semis"][i]
			var w: String = str(gs.playoff["sf"].get(str(i), ""))
			pv.add_child(label("Полуфинал %d: %s — %s%s" % [i + 1, s[0], s[1], ("  → " + w) if w != "" else ""], 14))
		if not gs.playoff["final"].is_empty():
			pv.add_child(label("Финал: %s — %s%s" % [gs.playoff["final"][0], gs.playoff["final"][1], ("  → ЧЕМПИОН: " + gs.playoff["champion"]) if gs.playoff["champion"] != "" else ""], 15, C_ACC))
	content.add_child(pp)
	var hp := panel()
	var hv := vbox(3)
	hp.add_child(hv)
	hv.add_child(label("История карьеры · Титулов: %d" % gs.titles, 17, C_ACC))
	if gs.history.is_empty():
		hv.add_child(label("Пока пусто.", 14, C_DIM))
	for t in gs.history:
		hv.add_child(label(t, 13, C_DIM))
	content.add_child(hp)

# ------------------------------------------------------------ тренер

func screen_coach() -> void:
	content.add_child(title("Профиль менеджера"))
	var pr := panel()
	var ph := hbox(18)
	pr.add_child(ph)
	ph.add_child(make_avatar(gs.avatar, 140, photo_tex))
	var pv := vbox(4)
	ph.add_child(pv)
	pv.add_child(label(gs.coach_name, 26))
	pv.add_child(label("%d лет · %s" % [gs.coach_age, gs.coach_country], 15, C_DIM))
	var bgname := ""
	for b in Teams.BACKGROUNDS:
		if b["id"] == gs.coach_bg: bgname = b["name"]
	pv.add_child(label("Предыстория: " + bgname, 15, C_DIM))
	pv.add_child(label("Команда: %s [%s]" % [gs.team_name, gs.team_tag], 15, Color(gs.team_color)))
	content.add_child(pr)
	content.add_child(label("Очки навыков: %d (дают победы, плей-офф и титулы)" % gs.coach_pts, 16, C_GOOD))
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	for k in gs.COACH_SKILLS:
		var r := hbox(10)
		r.add_child(cell(gs.COACH_SKILLS[k], 460))
		r.add_child(cell("Ур. %d/10" % int(gs.coach_skill[k]), 70, C_ACC))
		var key: String = k
		var b := btn("Улучшить", func(): gs.upgrade_coach(key); show_screen("coach"))
		b.disabled = gs.coach_pts <= 0 or int(gs.coach_skill[k]) >= 10
		r.add_child(b)
		v.add_child(r)
	content.add_child(p)
	content.add_child(label("Репутация: %d · Титулов: %d · Дивизион: %s" % [int(gs.rep), gs.titles, gs.TIERS[gs.tier]], 15, C_DIM))
	if gs.legend:
		content.add_child(label("Вы выиграли Мировую серию — вы легенда Standoff 2!", 16, C_ACC))

# ------------------------------------------------------------ система

func screen_system() -> void:
	content.add_child(title("Меню"))
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	v.add_child(btn("Сохранить игру", func(): gs.save(); gs.add_news("Игра сохранена."); show_screen("system")))
	v.add_child(btn("Выйти в главное меню", func(): gs.save(); show_menu()))
	content.add_child(p)
	var sp := panel()
	var sv := vbox(8)
	sp.add_child(sv)
	build_settings(sv, func(): show_screen("system"))
	content.add_child(sp)

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
	clear(content)
	refresh_top()
	var gi: int = int(m["game"]) + 1
	content.add_child(title("%s — карта %d (счёт серии %d:%d)" % [m["opp"], gi, m["wins"][0], m["wins"][1]]))
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	v.add_child(label("Выбор карты", 17, C_ACC))
	var avail: Array = []
	for mm in gs.MAPS:
		if not m["played"].has(mm):
			avail.append(mm)
	var map_ob := OptionButton.new()
	if gi == 1:
		for mm in avail:
			map_ob.add_item("%s (наше мастерство %d)" % [mm, int(gs.map_skill[mm])])
		m["pick"] = avail[0]
		map_ob.item_selected.connect(func(i): m["pick"] = avail[i])
		v.add_child(map_ob)
	else:
		var forced: String = avail[randi() % avail.size()]
		m["pick"] = forced
		v.add_child(label("Карта выбрана жребием: %s (мастерство %d)" % [forced, int(gs.map_skill[forced])], 15))
	v.add_child(label("Стиль на карту", 17, C_ACC))
	var so := OptionButton.new()
	var skeys: Array = gs.STYLES.keys()
	for k in skeys:
		so.add_item(gs.STYLES[k])
	so.selected = skeys.find(gs.style)
	var sdesc := label(gs.STYLE_DESC[gs.style], 13, C_DIM)
	so.item_selected.connect(func(i): gs.style = skeys[i]; sdesc.text = gs.STYLE_DESC[skeys[i]])
	v.add_child(so)
	v.add_child(sdesc)
	v.add_child(label("Состав: " + ", ".join(gs.lineup().map(func(x): return "%s (%s)" % [x["nick"], x["role"]])), 13, C_DIM))
	v.add_child(btn("Начать карту", func(): start_map(), C_GOOD))
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
	var mine_side := "АТАКА (T)" if sim.side_atk == 0 else "ЗАЩИТА (CT)"
	var ot := " · ОВЕРТАЙМ" if sim.is_overtime() else ""
	var c := label("Карта: %s · Раунд %d · Вы: %s%s · Серия: %d:%d (BO%d)" % [m["map"], sim.rounds + 1, mine_side, ot, m["wins"][0], m["wins"][1], m["bo"]], 14, C_DIM)
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
	bar.add_child(btn("Следующий раунд", func(): play(1), C_GOOD))
	bar.add_child(btn("5 раундов", func(): play(5)))
	bar.add_child(btn("До конца карты", func(): play(100)))
	var to := btn("Тайм-аут (%d)" % sim.timeouts[0], func(): m["tactic_open"] = !m["tactic_open"]; show_map_ui())
	to.disabled = sim.timeouts[0] <= 0
	bar.add_child(to)
	content.add_child(bar)
	if m["tactic_open"]:
		var tp := panel(C_PANEL, 10)
		var tv := hbox(8)
		tp.add_child(tv)
		tv.add_child(label("Тайм-аут: смените стиль (+%d к силе на 3 раунда)" % (3 + int(gs.coach_skill["tactics"] / 3)), 14))
		for k in gs.STYLES:
			var key: String = k
			tv.add_child(btn(gs.STYLES[k], func(): use_timeout(key)))
		content.add_child(tp)

func use_timeout(st: String) -> void:
	var sim = m["sim"]
	if sim.call_timeout(0, 3.0 + float(int(gs.coach_skill["tactics"]) / 3)):
		gs.style = st
		var pw: Dictionary = gs.team_power(st, m["map"])
		sim.atk[0] = pw["atk"]
		sim.dfn[0] = pw["dfn"]
		m["log_text"] = str(m.get("log_text", "")) + "[color=#ffb23e]Тайм-аут! Стиль: %s[/color]\n" % gs.STYLES[st]
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
		var line := "[color=%s]Р%d  %d:%d[/color]  %s\n" % [col, r["round"], sim.score[0], sim.score[1], r["text"]]
		if r["swap"]:
			line = "[color=#ffb23e]— Смена сторон —[/color]\n" + line
		var modes := {"pistol": "пистолеты", "full": "фулл-бай", "force": "форс-бай", "eco": "эко"}
		if get_node("/root/Settings").show_buys:
			line += "[color=#6b7280]   Закупка: вы — %s, соперник — %s[/color]\n" % [modes[r["buy"][0]], modes[r["buy"][1]]]
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
	v.add_child(label("Карта %s: %s %d:%d" % [m["map"], "победа" if won else "поражение", sim.score[0], sim.score[1]], 24, C_GOOD if won else C_BAD))
	v.add_child(label("Счёт в серии: %d:%d" % [m["wins"][0], m["wins"][1]], 18))
	v.add_child(btn("Следующая карта", func(): show_prematch(), C_GOOD))
	content.add_child(p)

func show_match_result() -> void:
	var won: bool = m["wins"][0] > m["wins"][1]
	clear(content)
	var p := panel(C_PANEL, 20)
	var v := vbox(8)
	p.add_child(v)
	v.add_child(label("ПОБЕДА!" if won else "ПОРАЖЕНИЕ", 36, C_GOOD if won else C_BAD))
	v.add_child(label("%s %d:%d %s (по картам). Раундов: %d:%d" % [gs.team_name, m["wins"][0], m["wins"][1], m["opp"], m["total"][0], m["total"][1]], 17))
	v.add_child(label("Статистика игроков", 16, C_ACC))
	var best: Dictionary = {}
	for s in m["stats"]:
		var kd: float = float(s["k"]) / maxf(1.0, float(s["d"]))
		var r := hbox(6)
		r.add_child(cell(s["nick"], 140))
		r.add_child(cell("%d / %d" % [s["k"], s["d"]], 90))
		r.add_child(cell("K/D %.2f" % kd, 100, C_GOOD if kd >= 1.0 else C_BAD))
		v.add_child(r)
	v.add_child(btn("Завершить матч", func(): end_match(won), C_GOOD))
	content.add_child(p)

func end_match(won: bool) -> void:
	gs.report_match({"won": won, "my": m["total"][0], "opp": m["total"][1], "maps_my": m["wins"][0], "maps_opp": m["wins"][1]})
	in_match = false
	m = {}
	show_screen("dashboard")
