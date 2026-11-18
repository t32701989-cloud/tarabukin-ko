extends Node
## Настройки игры. Хранятся в user://settings.cfg и применяются при запуске.

const PATH := "user://settings.cfg"
const UI_SCALES := [0.9, 1.0, 1.15, 1.3]
const SPEEDS := {"slow": 0.18, "normal": 0.06, "fast": 0.015}
const SPEED_NAMES := {"slow": "Медленно", "normal": "Обычно", "fast": "Быстро"}

var fullscreen: bool = false
var vsync: bool = true
var ui_scale: float = 1.0
var match_speed: String = "normal"
var autosave: bool = true
var show_buys: bool = true

func _ready() -> void:
	load_settings()
	apply()

func apply() -> void:
	var w := get_window()
	if w:
		if fullscreen:
			w.mode = Window.MODE_FULLSCREEN
		elif w.mode == Window.MODE_FULLSCREEN:
			w.mode = Window.MODE_WINDOWED
		w.content_scale_factor = ui_scale
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

func round_delay() -> float:
	return float(SPEEDS.get(match_speed, 0.06))

func save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("video", "vsync", vsync)
	c.set_value("video", "ui_scale", ui_scale)
	c.set_value("game", "match_speed", match_speed)
	c.set_value("game", "autosave", autosave)
	c.set_value("game", "show_buys", show_buys)
	c.save(PATH)

func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	fullscreen = bool(c.get_value("video", "fullscreen", fullscreen))
	vsync = bool(c.get_value("video", "vsync", vsync))
	ui_scale = float(c.get_value("video", "ui_scale", ui_scale))
	match_speed = str(c.get_value("game", "match_speed", match_speed))
	autosave = bool(c.get_value("game", "autosave", autosave))
	show_buys = bool(c.get_value("game", "show_buys", show_buys))

func reset() -> void:
	fullscreen = false
	vsync = true
	ui_scale = 1.0
	match_speed = "normal"
	autosave = true
	show_buys = true
	apply()
	save_settings()
