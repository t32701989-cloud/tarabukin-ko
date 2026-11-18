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

var _tex_cache: Dictionary = {}

func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
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
func portrait(pl: Dictionary, sz: int) -> Control:
	var ph: String = str(pl.get("photo", ""))
	if ph != "" and tex(ph) != null:
		return make_avatar({}, sz, tex(ph))
	return make_avatar(pl.get("look", {}), sz)

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
	h.add_child(label(tr("НОВАЯ КАРЬЕРА"), 28, C_ACC))
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
	var root := _wizard_root(tr("Шаг 1 из 2 · Создание менеджера"))
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
	tb.add_child(label(tr("Внешность"), 18, C_ACC))
	tb.add_child(btn(tr("Случайная внешность"), func():
		cr["avatar"] = Avatar.random_cfg(); show_creator()))
	tb.add_child(btn(tr("Загрузить своё фото..."), func(): open_photo_dialog()))
	if cr_photo != null:
		tb.add_child(btn(tr("Убрать фото"), func():
			cr_photo = null; cr["photo"] = ""; show_creator(), C_BAD))
		tb.add_child(wrap_label(tr("Используется загруженное фото."), 13, C_GOOD, 200))
	else:
		tb.add_child(wrap_label(tr("PNG / JPG / WEBP, фото обрежется до квадрата."), 13, C_DIM, 200))
	if str(cr.get("err", "")) != "":
		tb.add_child(wrap_label(cr["err"], 13, C_BAD, 200))
	lv.add_child(label(tr("Варианты внешности — нажми, чтобы выбрать:"), 14, C_DIM))
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
	lv.add_child(btn(tr("Ещё варианты"), func():
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
	rv.add_child(label(tr("Анкета менеджера"), 18, C_ACC))
	rv.add_child(label(tr("Имя"), 13, C_DIM))
	var name_edit := LineEdit.new()
	name_edit.text = cr["name"]
	name_edit.max_length = 24
	name_edit.placeholder_text = tr("Имя менеджера")
	name_edit.text_changed.connect(func(t): cr["name"] = t)
	rv.add_child(name_edit)
	var r2 := hbox(16)
	var agev := vbox(4)
	agev.add_child(label(tr("Возраст"), 13, C_DIM))
	var age := SpinBox.new()
	age.min_value = 21
	age.max_value = 65
	age.value = cr["age"]
	age.value_changed.connect(func(v): cr["age"] = int(v))
	agev.add_child(age)
	r2.add_child(agev)
	var cv := vbox(4)
	cv.add_child(label(tr("Страна"), 13, C_DIM))
	var co := OptionButton.new()
	for c2 in Teams.COUNTRIES:
		co.add_item(c2)
	co.selected = maxi(0, Teams.COUNTRIES.find(cr["country"]))
	co.item_selected.connect(func(i): cr["country"] = Teams.COUNTRIES[i])
	cv.add_child(co)
	r2.add_child(cv)
	rv.add_child(r2)
	rv.add_child(label(tr("Предыстория (бонус на старте)"), 13, C_DIM))
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
		bb.add_child(label(("> " if sel else "") + tr(b2["name"]), 15, C_ACC if sel else Color.WHITE))
		bb.add_child(label(b2["desc"], 12, C_DIM))
		var hit := Button.new()
		hit.flat = true
		hit.set_anchors_preset(Control.PRESET_FULL_RECT)
		hit.pressed.connect(func(): cr["bg"] = id; show_creator())
		bp.add_child(hit)
		bgrid.add_child(bp)
	rv.add_child(bgrid)

	var bottom := hbox(12)
	bottom.add_child(btn(tr("Назад в меню"), func(): cr = {}; show_menu(), C_DIM))
	bottom.add_child(spacer())
	if gs.list_saves().size() >= gs.MAX_SLOTS:
		bottom.add_child(label(tr("Все слоты заняты: самое старое сохранение будет перезаписано"), 13, C_BAD))
	bottom.add_child(menu_btn(tr("Далее: выбор команды"), func():
		if str(cr["name"]).strip_edges() == "":
			cr["err"] = tr("Введите имя менеджера.")
			show_creator()
			return
		cr["err"] = ""
		show_team_select(), true))
	root.add_child(bottom)

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

func show_team_select() -> void:
	var root := _wizard_root(tr("Шаг 2 из 2 · Выбор команды"))
	var info := hbox(12)
	info.add_child(make_avatar(cr["avatar"], 44, cr_photo))
	info.add_child(label(tr("%s, %d лет · выберите клуб, который возглавите") % [cr["name"], cr["age"]], 16, C_DIM))
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
	cv.add_child(label(tr("СВОЯ КОМАНДА"), 18, C_ACC))
	cv.add_child(label(tr("Сложно"), 13, C_BAD))
	var ne := LineEdit.new()
	ne.placeholder_text = tr("Название")
	ne.max_length = 24
	cv.add_child(ne)
	var te := LineEdit.new()
	te.placeholder_text = tr("Тег (до 4 букв)")
	te.max_length = 4
	cv.add_child(te)
	cv.add_child(wrap_label(tr("Создайте организацию с нуля: скромный бюджет и молодой состав."), 12, C_DIM, 230))
	var err := label("", 12, C_BAD)
	cv.add_child(err)
	cv.add_child(btn(tr("Создать и начать"), func():
		var n: String = ne.text.strip_edges()
		if n == "":
			err.text = tr("Введите название команды.")
			return
		var tag: String = te.text.strip_edges().to_upper()
		if tag == "": tag = n.substr(0, 3).to_upper()
		start_career({"name": n, "tag": tag, "color": "ffffff", "diff": 2, "base": 43.0, "money": 60000, "rep": 10.0}), C_GOOD))
	grid.add_child(cp)
	var bottom := hbox(12)
	bottom.add_child(btn(tr("Назад к менеджеру"), func(): show_creator(), C_DIM))
	root.add_child(bottom)

func team_card(t: Dictionary) -> Control:
	var p := panel(C_PANEL, 14)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := vbox(5)
	p.add_child(v)
	var h := hbox(10)
	if tex(str(t.get("logo", ""))) != null:
		h.add_child(pic(t["logo"], 44))
	else:
		var badge := panel(Color(t["color"]).darkened(0.55), 8)
		badge.add_child(label(t["tag"], 16, Color(t["color"])))
		h.add_child(badge)
	var d: int = int(t["diff"])
	var dl := label(Teams.DIFF_NAMES[d], 13, Color(Teams.DIFF_COLORS[d]))
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dl)
	v.add_child(h)
	v.add_child(label(t["name"], 18))
	v.add_child(label(tr("Лига: %s") % tr(gs.TIERS[int(t.get("tier", 0))]), 13, C_ACC if int(t.get("tier", 0)) > 0 else C_DIM))
	v.add_child(label(tr("Уровень состава: ~%d") % int(t["base"]), 13, C_DIM))
	var roster: Array = t.get("roster", [])
	if not roster.is_empty():
		var faces := hbox(3)
		for rp in roster:
			faces.add_child(portrait(rp, 40))
		v.add_child(faces)
		v.add_child(wrap_label(", ".join(roster.map(func(x): return x["nick"])), 12, Color.WHITE, 230))
	if t.has("coach"):
		v.add_child(label(tr("Тренер: %s") % t["coach"]["name"], 12, C_DIM))
	v.add_child(label(tr("Бюджет: %s") % money_fmt(int(t["money"])), 13, C_DIM))
	v.add_child(label(tr("Репутация: %d") % int(t["rep"]), 13, C_DIM))
	v.add_child(wrap_label(t["desc"], 12, C_DIM, 230))
	var f := Control.new()
	f.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(f)
	var team: Dictionary = t
	v.add_child(btn(tr("Выбрать"), func(): start_career(team), C_GOOD))
	return p

func start_career(team: Dictionary) -> void:
	var photo := ""
	gs.slot = gs.free_slot()
	gs.delete_slot(gs.slot)
	if str(cr.get("photo", "")) != "" and FileAccess.file_exists(TMP_PHOTO):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(TMP_PHOTO), ProjectSettings.globalize_path(gs.photo_path_for(gs.slot)))
		photo = gs.photo_path_for(gs.slot)
	gs.new_game({"name": cr["name"], "age": cr["age"], "country": cr["country"], "bg": cr["bg"], "avatar": cr["avatar"], "photo": photo}, team)
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
	var ph: Texture2D = null
	var pp: String = str(d.get("photo_path", ""))
	if pp != "" and FileAccess.file_exists(pp):
		var im := Image.load_from_file(pp)
		if im: ph = ImageTexture.create_from_image(im)
	return make_avatar(d.get("avatar", {}), sz, ph)

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
	left.add_child(text_btn(tr("НОВАЯ ИГРА"), func(): menu_page("new"), 26))
	left.add_child(text_btn(tr("ЗАГРУЗИТЬ"), func(): menu_page("load")))
	left.add_child(text_btn(tr("ОБУЧЕНИЕ"), func(): tut_page = 0; menu_page("tutorial")))
	left.add_child(text_btn(tr("НАСТРОЙКИ"), func(): menu_page("settings")))
	left.add_child(text_btn(tr("ВЫХОД"), func(): get_tree().quit()))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	left.add_child(label(tr("%s · Godot 4.2 · фан-проект, не связан с разработчиками Standoff 2") % VERSION, 12, Color("5b6270")))
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
			var v := _menu_card(tr("Загрузить игру"))
			var saves: Array = gs.list_saves()
			if saves.is_empty():
				v.add_child(label(tr("Нет сохранений."), 16, C_DIM))
			for e in saves:
				var d: Dictionary = e["data"]
				var sl: int = int(e["slot"])
				var row := panel(Color("1f232b"), 12)
				var h := hbox(14)
				row.add_child(h)
				h.add_child(_save_icon(d, 56))
				var info := vbox(2)
				info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				info.add_child(label("%s  ·  %s" % [d.get("team_name", ""), d.get("coach_name", "")], 18))
				info.add_child(label(tr("Сезон %d · неделя %d/10 · %s") % [int(d.get("season", 1)), int(d.get("week", 1)), tr(gs.TIERS[int(d.get("tier", 0))])], 13, C_DIM))
				info.add_child(label(tr("Слот %d") % sl + "  ·  " + tr("Сохранено: %s") % str(d.get("saved_at", "—")), 12, C_DIM))
				if str(d.get("game_over", "")) != "":
					info.add_child(label(tr("Карьера завершена: ") + str(d["game_over"]), 12, C_BAD))
				h.add_child(info)
				if pending_delete == sl:
					h.add_child(btn(tr("Да, удалить"), func():
						gs.delete_slot(sl); pending_delete = -1; show_menu(); menu_page("load"), C_BAD))
					h.add_child(btn(tr("Отмена"), func(): pending_delete = -1; menu_page("load")))
				else:
					h.add_child(btn(tr("Загрузить"), func():
						if gs.load_game(sl):
							build_game(), C_GOOD))
					h.add_child(btn(tr("Удалить"), func(): pending_delete = sl; menu_page("load"), C_BAD))
				v.add_child(row)
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
				row.add_child(btn(tr("Начать карьеру"), func(): menu_page("new"), C_GOOD))
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
	if tex(gs.team_logo) != null:
		th.add_child(pic(gs.team_logo, 38))
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
	for e in [["dashboard", tr("Главная")], ["squad", tr("Состав")], ["training", tr("Тренировки и тактика")], ["transfers", tr("Трансферы")], ["league", tr("Лига")], ["coach", tr("Тренер")], ["system", tr("Меню / сохранение")]]:
		var key: String = e[0]
		nav_box.add_child(btn(e[1], func(): show_screen(key)))
	show_screen("dashboard")

func refresh_top() -> void:
	if top_label == null:
		return
	top_label.text = tr("%s  |  Сезон %d · Неделя %d/10 · %s  |  %s  |  Деньги: %s  |  Репутация: %d") % [gs.team_name, gs.season, gs.week, tr(gs.TIERS[gs.tier]), gs.phase_name(), money_fmt(gs.money), int(gs.rep)]
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
	v.add_child(label(tr("КАРЬЕРА ЗАВЕРШЕНА"), 32, C_BAD))
	v.add_child(label(gs.game_over, 16))
	v.add_child(label(tr("Сезонов: %d · Титулов: %d") % [gs.season, gs.titles], 15, C_DIM))
	v.add_child(btn(tr("В главное меню"), func(): show_menu()))
	content.add_child(p)

func title(t: String) -> Label:
	return label(t, 24, C_ACC)

# ------------------------------------------------------------ главная

func screen_dashboard() -> void:
	content.add_child(title(tr("Главная")))
	var pm: Dictionary = gs.player_match()
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	v.add_child(label(gs.phase_name(), 18, C_ACC))
	var main_btn: Button
	if gs.week > 9:
		v.add_child(label(tr("Межсезонье: подпишите игроков, потратьте очки тренера и подготовьтесь к новому сезону."), 14, C_DIM))
		main_btn = btn(tr("Начать новый сезон"), on_finish_week, C_GOOD)
	elif pm.is_empty():
		v.add_child(label(tr("На этой неделе у вас нет матча."), 15, C_DIM))
		main_btn = btn(tr("Завершить неделю"), on_finish_week, C_GOOD)
	elif gs.match_done:
		v.add_child(label(tr("Матч против %s сыгран.") % pm["opp"], 15, C_GOOD))
		main_btn = btn(tr("Завершить неделю"), on_finish_week, C_GOOD)
	else:
		var kinds := {"league": tr("Матч лиги (BO1)"), "semi": tr("Полуфинал плей-офф (BO3)"), "final": tr("ФИНАЛ плей-офф (BO3)")}
		v.add_child(label(tr("%s: %s против %s") % [kinds[pm["kind"]], gs.team_name, pm["opp"]], 17))
		var s: float = gs.opp_strength(pm["opp"])
		var mine: float = gs.team_power(gs.style, gs.train_map)["base"]
		var d: float = s - mine
		var verdict := tr("примерно равны")
		var col := Color.WHITE
		if d > 6: verdict = tr("соперник заметно сильнее"); col = C_BAD
		elif d > 2: verdict = tr("соперник немного сильнее"); col = C_ACC
		elif d < -6: verdict = tr("вы заметно сильнее"); col = C_GOOD
		elif d < -2: verdict = tr("вы немного сильнее"); col = C_GOOD
		var scout_txt := verdict
		if int(gs.coach_skill["scout"]) >= 3:
			scout_txt += tr(" (рейтинг %d против ваших %d)") % [int(s), int(mine)]
		v.add_child(label(tr("Оценка скаутов: ") + scout_txt, 14, col))
		if not gs.has_enough_players():
			v.add_child(label(tr("Недостаточно здоровых игроков (нужно 5)! Подпишите кого-нибудь."), 14, C_BAD))
			main_btn = btn(tr("Играть матч"), func(): pass, C_DIM)
			main_btn.disabled = true
		else:
			main_btn = btn(tr("К матчу"), on_play_match, C_GOOD)
	v.add_child(main_btn)
	content.add_child(p)

	# турнирная таблица
	var tp := panel()
	var tv := vbox(4)
	tp.add_child(tv)
	tv.add_child(label(tr("Таблица лиги"), 17, C_ACC))
	tv.add_child(table_header())
	var rl: Array = gs.rank_list()
	for i in rl.size():
		tv.add_child(table_row(i + 1, rl[i]))
	content.add_child(tp)

	var np := panel()
	var nv := vbox(3)
	np.add_child(nv)
	nv.add_child(label(tr("Новости"), 17, C_ACC))
	for i in min(8, gs.news.size()):
		nv.add_child(label(gs.news[i], 13, C_DIM))
	content.add_child(np)

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

# ------------------------------------------------------------ состав

func screen_squad() -> void:
	content.add_child(title(tr("Состав (первые 5 здоровых игроков выходят на карту)")))
	if gs.staff_coach != "":
		var sp := panel()
		var sh := hbox(12)
		sp.add_child(sh)
		sh.add_child(portrait({"photo": gs.staff_photo}, 56))
		var sv := vbox(2)
		sv.add_child(label(tr("Тренер состава: ") + gs.staff_coach, 17))
		sv.add_child(label(tr("Работает в вашем штабе: +1.5 к силе команды"), 13, C_DIM))
		sh.add_child(sv)
		content.add_child(sp)
	var p := panel()
	var v := vbox(5)
	p.add_child(v)
	var h := hbox(4)
	for e in [["", 34], [tr("Ник"), 108], [tr("Роль"), 78], [tr("Воз"), 36], [tr("Аим"), 40], [tr("ИИ"), 40], [tr("Сыг"), 40], [tr("ОБЩ"), 44], [tr("Форма"), 56], [tr("Зарплата"), 70], [tr("Статус"), 96]]:
		h.add_child(cell(e[0], e[1], C_DIM, 13))
	v.add_child(h)
	var lineup_ids: Array = []
	for q in gs.lineup():
		lineup_ids.append(q["id"])
	for i in gs.players.size():
		var pl: Dictionary = gs.players[i]
		var r := hbox(4)
		var starter: bool = lineup_ids.has(pl["id"])
		r.add_child(portrait(pl, 34))
		r.add_child(cell(pl["nick"], 108, C_ACC if starter else C_DIM))
		r.add_child(cell(pl["role"], 78))
		r.add_child(cell(str(pl["age"]), 36, C_DIM))
		r.add_child(cell(str(pl["aim"]), 40, stat_color(pl["aim"])))
		r.add_child(cell(str(pl["iq"]), 40, stat_color(pl["iq"])))
		r.add_child(cell(str(pl["tw"]), 40, stat_color(pl["tw"])))
		r.add_child(cell(str(gs.ovr(pl)), 44, stat_color(gs.ovr(pl))))
		var fc: Color = C_GOOD if pl["form"] >= 70 else (C_ACC if pl["form"] >= 45 else C_BAD)
		r.add_child(cell(str(pl["form"]) + "%", 56, fc))
		r.add_child(cell("$" + str(pl["salary"]), 70, C_DIM))
		var st := tr("Основа") if starter else tr("Скамейка")
		var stc: Color = C_GOOD if starter else C_DIM
		if pl["inj"] > 0:
			st = tr("Травма %dн") % pl["inj"]
			stc = C_BAD
		r.add_child(cell(st, 96, stc))
		var idx: int = i
		r.add_child(btn(tr("Вверх"), func(): gs.move_player(idx, -1); show_screen("squad")))
		r.add_child(btn(tr("Вниз"), func(): gs.move_player(idx, 1); show_screen("squad")))
		r.add_child(btn(tr("Продать"), func(): gs.sell_player(idx); show_screen("squad")))
		r.add_child(btn(tr("Отчислить"), func(): gs.release_player(idx); show_screen("squad"), C_BAD))
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
	var info := label(tr("Роли в основе: %d/5.%s") % [roles.size(), (tr(" Не хватает: ") + ", ".join(miss.map(func(x): return tr(x))) + tr(" (бонус к силе команды)")) if miss.size() > 0 else tr(" Полный набор ролей: бонус +2!")], 14, C_DIM)
	content.add_child(info)
	var pw: Dictionary = gs.team_power(gs.style, gs.train_map)
	content.add_child(label(tr("Сила команды: атака %.1f · защита %.1f") % [pw["atk"], pw["dfn"]], 15, C_ACC))

# ------------------------------------------------------------ тренировки

func screen_training() -> void:
	content.add_child(title(tr("Тренировки и тактика")))
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	v.add_child(label(tr("Недельный фокус тренировок"), 17, C_ACC))
	var ob := OptionButton.new()
	var keys: Array = gs.TRAIN.keys()
	for k in keys:
		ob.add_item(tr(gs.TRAIN[k]))
	ob.selected = keys.find(gs.train_focus)
	ob.item_selected.connect(func(i): gs.train_focus = keys[i]; show_screen("training"))
	v.add_child(ob)
	if gs.train_focus == "maps":
		var mo := OptionButton.new()
		for mm in gs.MAPS:
			mo.add_item(tr("%s (мастерство %d)") % [mm, int(gs.map_skill[mm])])
		mo.selected = gs.MAPS.find(gs.train_map)
		mo.item_selected.connect(func(i): gs.train_map = gs.MAPS[i]; show_screen("training"))
		v.add_child(mo)
	var desc := {"aim": tr("Растёт аим. Утомляет игроков."), "iq": tr("Растёт игровое мышление. Утомляет игроков."), "tw": tr("Растёт сыгранность. Слегка утомляет."), "maps": tr("Команда лучше знает выбранную карту (+бонус к силе на ней)."), "rest": tr("Игроки восстанавливают форму (+16%).")}
	v.add_child(label(desc[gs.train_focus], 14, C_DIM))
	content.add_child(p)

	var tp := panel()
	var tv := vbox(8)
	tp.add_child(tv)
	tv.add_child(label(tr("Стиль игры"), 17, C_ACC))
	var so := OptionButton.new()
	var skeys: Array = gs.STYLES.keys()
	for k in skeys:
		so.add_item(tr(gs.STYLES[k]))
	so.selected = skeys.find(gs.style)
	so.item_selected.connect(func(i): gs.style = skeys[i]; show_screen("training"))
	tv.add_child(so)
	tv.add_child(label(tr(gs.STYLE_DESC[gs.style]), 14, C_DIM))
	content.add_child(tp)

	var mp := panel()
	var mv := vbox(4)
	mp.add_child(mv)
	mv.add_child(label(tr("Пул карт"), 17, C_ACC))
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
	content.add_child(title(tr("Рынок свободных агентов")))
	content.add_child(label(tr("Состав: %d/%d · Деньги: %s · Скаутинг ур.%d (чем выше — тем точнее оценка потенциала)") % [gs.players.size(), gs.MAX_ROSTER, money_fmt(gs.money), int(gs.coach_skill["scout"])], 14, C_DIM))
	var p := panel()
	var v := vbox(5)
	p.add_child(v)
	var h := hbox(4)
	for e in [["", 34], [tr("Ник"), 130], [tr("Роль"), 80], [tr("Воз"), 40], [tr("Аим"), 44], [tr("ИИ"), 44], [tr("Сыг"), 44], [tr("ОБЩ"), 48], [tr("Потенциал"), 80], [tr("Цена"), 90], [tr("Зарплата"), 80]]:
		h.add_child(cell(e[0], e[1], C_DIM, 13))
	v.add_child(h)
	for i in gs.market.size():
		var pl: Dictionary = gs.market[i]
		var r := hbox(4)
		r.add_child(portrait(pl, 34))
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
		var b := btn(tr("Подписать"), func():
			var err: String = gs.sign_player(idx)
			if err != "":
				gs.add_news(err)
			show_screen("transfers"))
		r.add_child(b)
		v.add_child(r)
	content.add_child(p)

# ------------------------------------------------------------ лига

func screen_league() -> void:
	content.add_child(title(tr("Лига: %s") % tr(gs.TIERS[gs.tier])))
	var p := panel()
	var v := vbox(4)
	p.add_child(v)
	v.add_child(table_header())
	var rl: Array = gs.rank_list()
	for i in rl.size():
		v.add_child(table_row(i + 1, rl[i]))
	v.add_child(label(tr("Топ-4 выходят в плей-офф. Топ-2 повышаются в дивизионе, два последних — вылетают."), 13, C_DIM))
	content.add_child(p)
	var pp := panel()
	var pv := vbox(4)
	pp.add_child(pv)
	pv.add_child(label(tr("Плей-офф"), 17, C_ACC))
	if gs.playoff["semis"].is_empty():
		pv.add_child(label(tr("Начнётся после 7-го тура."), 14, C_DIM))
	else:
		for i in gs.playoff["semis"].size():
			var s: Array = gs.playoff["semis"][i]
			var w: String = str(gs.playoff["sf"].get(str(i), ""))
			pv.add_child(label(tr("Полуфинал %d: %s — %s%s") % [i + 1, s[0], s[1], ("  → " + w) if w != "" else ""], 14))
		if not gs.playoff["final"].is_empty():
			pv.add_child(label(tr("Финал: %s — %s%s") % [gs.playoff["final"][0], gs.playoff["final"][1], (tr("  → ЧЕМПИОН: ") + gs.playoff["champion"]) if gs.playoff["champion"] != "" else ""], 15, C_ACC))
	content.add_child(pp)
	var hp := panel()
	var hv := vbox(3)
	hp.add_child(hv)
	hv.add_child(label(tr("История карьеры · Титулов: %d") % gs.titles, 17, C_ACC))
	if gs.history.is_empty():
		hv.add_child(label(tr("Пока пусто."), 14, C_DIM))
	for t in gs.history:
		hv.add_child(label(t, 13, C_DIM))
	content.add_child(hp)

# ------------------------------------------------------------ тренер

func screen_coach() -> void:
	content.add_child(title(tr("Профиль менеджера")))
	var pr := panel()
	var ph := hbox(18)
	pr.add_child(ph)
	ph.add_child(make_avatar(gs.avatar, 140, photo_tex))
	var pv := vbox(4)
	ph.add_child(pv)
	pv.add_child(label(gs.coach_name, 26))
	pv.add_child(label(tr("%d лет · %s") % [gs.coach_age, tr(gs.coach_country)], 15, C_DIM))
	var bgname := ""
	for b in Teams.BACKGROUNDS:
		if b["id"] == gs.coach_bg: bgname = b["name"]
	pv.add_child(label(tr("Предыстория: ") + tr(bgname), 15, C_DIM))
	pv.add_child(label(tr("Команда: %s [%s]") % [gs.team_name, gs.team_tag], 15, Color(gs.team_color)))
	content.add_child(pr)
	content.add_child(label(tr("Очки навыков: %d (дают победы, плей-офф и титулы)") % gs.coach_pts, 16, C_GOOD))
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	for k in gs.COACH_SKILLS:
		var r := hbox(10)
		r.add_child(cell(tr(gs.COACH_SKILLS[k]), 460))
		r.add_child(cell(tr("Ур. %d/10") % int(gs.coach_skill[k]), 70, C_ACC))
		var key: String = k
		var b := btn(tr("Улучшить"), func(): gs.upgrade_coach(key); show_screen("coach"))
		b.disabled = gs.coach_pts <= 0 or int(gs.coach_skill[k]) >= 10
		r.add_child(b)
		v.add_child(r)
	content.add_child(p)
	content.add_child(label(tr("Репутация: %d · Титулов: %d · Дивизион: %s") % [int(gs.rep), gs.titles, tr(gs.TIERS[gs.tier])], 15, C_DIM))
	if gs.legend:
		content.add_child(label(tr("Вы выиграли Мировую серию — вы легенда Standoff 2!"), 16, C_ACC))

# ------------------------------------------------------------ система

func screen_system() -> void:
	content.add_child(title(tr("Меню")))
	var p := panel()
	var v := vbox(8)
	p.add_child(v)
	v.add_child(btn(tr("Сохранить игру"), func(): gs.save(); gs.add_news(tr("Игра сохранена.")); show_screen("system")))
	v.add_child(btn(tr("Выйти в главное меню"), func(): gs.save(); show_menu()))
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
	gs.report_match({"won": won, "my": m["total"][0], "opp": m["total"][1], "maps_my": m["wins"][0], "maps_opp": m["wins"][1]})
	in_match = false
	m = {}
	show_screen("dashboard")
