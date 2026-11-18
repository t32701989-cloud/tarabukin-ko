extends RefCounted
## Общая тема интерфейса: шрифты Montserrat / PT Serif, иконки Material Icons, объёмные кнопки и поля.

const F := "res://assets/fonts/"
static var _regular: Font
static var _bold: Font
static var _heavy: Font
static var _serif: Font
static var _serif_bold: Font
static var _icons: Font

static func _pair(latin: String, cyr: String) -> Font:
	var a: FontFile = load(F + latin)
	var b: FontFile = load(F + cyr)
	if a == null:
		return ThemeDB.fallback_font
	if b != null:
		a.fallbacks = [b]
	return a

static func regular() -> Font:
	if _regular == null: _regular = _pair("montserrat-latin-500-normal.woff2", "montserrat-cyrillic-500-normal.woff2")
	return _regular

static func bold() -> Font:
	if _bold == null: _bold = _pair("montserrat-latin-700-normal.woff2", "montserrat-cyrillic-700-normal.woff2")
	return _bold

static func heavy() -> Font:
	if _heavy == null: _heavy = _pair("montserrat-latin-800-normal.woff2", "montserrat-cyrillic-800-normal.woff2")
	return _heavy

static func serif() -> Font:
	if _serif == null: _serif = _pair("pt-serif-latin-400-normal.woff2", "pt-serif-cyrillic-400-normal.woff2")
	return _serif

static func serif_bold() -> Font:
	if _serif_bold == null: _serif_bold = _pair("pt-serif-latin-700-normal.woff2", "pt-serif-cyrillic-700-normal.woff2")
	return _serif_bold

static func icons() -> Font:
	if _icons == null:
		_icons = load(F + "material-icons.woff2")
	return _icons

static func _box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 6, shadow: int = 0, pad: Vector4 = Vector4(12, 7, 12, 7)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	s.content_margin_left = pad.x; s.content_margin_top = pad.y
	s.content_margin_right = pad.z; s.content_margin_bottom = pad.w
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, 2)
	return s

static func _grad_box(top: Color, bottom: Color, border: Color, radius: int = 6) -> StyleBoxTexture:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var s := StyleBoxTexture.new()
	s.texture = gt
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 7; s.content_margin_bottom = 7
	return s

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = regular()
	t.default_font_size = 15
	var acc := Color("ffb23e")
	# --- Button
	var bn := _box(Color("232a36"), Color(1, 1, 1, 0.10), 1, 6, 4)
	var bh := _box(Color("2e3747"), Color(1, 0.7, 0.24, 0.55), 1, 6, 6)
	var bp := _box(Color("1b212b"), Color(1, 0.7, 0.24, 0.8), 1, 6, 0)
	var bd := _box(Color("1a1f28"), Color(1, 1, 1, 0.04), 1, 6, 0)
	var bf := _box(Color("232a36"), Color(1, 0.7, 0.24, 0.6), 1, 6, 0)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, bn)
		t.set_stylebox("hover", type, bh)
		t.set_stylebox("pressed", type, bp)
		t.set_stylebox("disabled", type, bd)
		t.set_stylebox("focus", type, bf)
		t.set_font("font", type, bold())
		t.set_color("font_color", type, Color("e9edf3"))
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, acc)
		t.set_color("font_disabled_color", type, Color("5d6573"))
	t.set_font_size("font_size", "Button", 15)
	# --- LineEdit / TextEdit / SpinBox
	var le := _box(Color("10141b"), Color(1, 1, 1, 0.12), 1, 6, 0, Vector4(10, 7, 10, 7))
	var lef := _box(Color("10141b"), acc, 1, 6, 0, Vector4(10, 7, 10, 7))
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, le)
		t.set_stylebox("focus", type, lef)
		t.set_stylebox("read_only", type, le)
		t.set_color("font_color", type, Color.WHITE)
		t.set_color("font_placeholder_color", type, Color(1, 1, 1, 0.35))
		t.set_color("caret_color", type, acc)
		t.set_color("selection_color", type, Color(1, 0.7, 0.24, 0.35))
	# --- PopupMenu
	t.set_stylebox("panel", "PopupMenu", _box(Color("161b24"), Color(1, 1, 1, 0.12), 1, 6, 10, Vector4(6, 6, 6, 6)))
	t.set_stylebox("hover", "PopupMenu", _box(Color(1, 0.7, 0.24, 0.22), Color(0, 0, 0, 0), 0, 4))
	t.set_color("font_color", "PopupMenu", Color("dfe4ec"))
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", regular())
	# --- CheckBox / CheckButton
	t.set_icon("checked", "CheckBox", _check_icon(true, acc))
	t.set_icon("unchecked", "CheckBox", _check_icon(false, acc))
	t.set_icon("radio_checked", "CheckBox", _check_icon(true, acc))
	t.set_icon("radio_unchecked", "CheckBox", _check_icon(false, acc))
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", Color("dfe4ec"))
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", Color.WHITE)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	t.set_constant("h_separation", "CheckBox", 8)
	# --- ScrollBar
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 0, 4, 0, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber", type, _box(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 0, 4))
		t.set_stylebox("grabber_highlight", type, _box(Color(1, 0.7, 0.24, 0.55), Color(0, 0, 0, 0), 0, 4))
		t.set_stylebox("grabber_pressed", type, _box(acc, Color(0, 0, 0, 0), 0, 4))
	# --- ProgressBar / Slider
	t.set_stylebox("background", "ProgressBar", _box(Color("10141b"), Color(1, 1, 1, 0.08), 1, 4, 0, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", _box(acc, Color(0, 0, 0, 0), 0, 4, 0, Vector4(0, 0, 0, 0)))
	t.set_stylebox("slider", "HSlider", _box(Color("10141b"), Color(1, 1, 1, 0.1), 1, 4, 0, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area", "HSlider", _box(Color("6fd35a"), Color(0, 0, 0, 0), 0, 4, 0, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(Color("8ae373"), Color(0, 0, 0, 0), 0, 4, 0, Vector4(0, 3, 0, 3)))
	t.set_icon("grabber", "HSlider", _knob(Color("f2f4f8")))
	t.set_icon("grabber_highlight", "HSlider", _knob(acc))
	# --- Label / Panel
	t.set_color("font_color", "Label", Color("e9edf3"))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.09, 0.12, 0.17, 0.88), Color(1, 1, 1, 0.08), 1, 8, 6))
	t.set_stylebox("panel", "TooltipPanel", _box(Color("161b24"), Color(1, 1, 1, 0.15), 1, 6, 6))
	return t

static func _check_icon(on: bool, acc: Color) -> ImageTexture:
	var s := 22
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in s:
		for x in s:
			var inside: bool = x >= 2 and y >= 2 and x < s - 2 and y < s - 2
			var border: bool = inside and (x < 4 or y < 4 or x >= s - 4 or y >= s - 4)
			if border:
				img.set_pixel(x, y, acc if on else Color(1, 1, 1, 0.45))
			elif inside:
				img.set_pixel(x, y, Color(acc.r, acc.g, acc.b, 0.9) if on else Color(0.06, 0.08, 0.11, 0.9))
	if on:
		# галочка
		var pts := [Vector2(6, 11), Vector2(9, 14), Vector2(16, 7)]
		for i in 2:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			for k in 30:
				var p: Vector2 = a.lerp(b, k / 29.0)
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						var q := Vector2i(int(p.x) + dx, int(p.y) + dy)
						if q.x >= 0 and q.y >= 0 and q.x < s and q.y < s:
							img.set_pixelv(q, Color("14161b"))
	return ImageTexture.create_from_image(img)

static func _knob(c: Color) -> ImageTexture:
	var s := 18
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ctr := Vector2(s / 2.0 - 0.5, s / 2.0 - 0.5)
	for y in s:
		for x in s:
			var d: float = Vector2(x, y).distance_to(ctr)
			if d <= s / 2.0 - 1:
				var a: float = clampf(s / 2.0 - 1 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)

## Иконка Material Icons по имени лигатуры (home, mail, groups...).
static func icon(name: String, size: int = 20, color: Color = Color(0.85, 0.88, 0.95)) -> Label:
	var l := Label.new()
	l.text = name
	l.add_theme_font_override("font", icons())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
