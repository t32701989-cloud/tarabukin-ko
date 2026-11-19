extends RefCounted
## Схемы карт для экрана матча: зоны (узлы), связи между ними и оформление.
## Координаты условные (0..1000 × 0..700), раскладка своя — по общему смыслу карты.

const LAYOUTS := {
	"Sandstone": {
		"theme": {"ground": "d9c49a", "street": "efe0bd", "roof": ["c7a77a", "b8936a", "d4b98c", "a98660"], "accent": "7a9a4a", "tree": true},
		"nodes": {
			"T": [80, 330], "market": [210, 430], "alley": [210, 250], "zigzag": [250, 175], "columns": [340, 135],
			"yard": [440, 110], "apts": [560, 80], "A": [700, 105], "square": [590, 190], "fork": [700, 255],
			"a_down": [820, 175], "CT": [860, 330], "mid": [450, 300], "arch": [400, 410], "mid_down": [590, 340],
			"pass": [560, 460], "b_down": [690, 430], "B": [630, 575], "long": [450, 600], "house": [260, 565], "cross": [330, 480],
		},
		"names": {"T": "Т-спавн", "market": "Рынок", "alley": "Переулок", "zigzag": "Зигзаг", "columns": "Колонны", "yard": "Двор",
			"apts": "Апартаменты", "square": "Площадь", "fork": "Развилка", "a_down": "Спуск A", "CT": "CT-спавн", "mid": "Мид",
			"arch": "Арка", "mid_down": "Спуск мид", "pass": "Переход", "b_down": "Спуск B", "long": "Длина", "house": "Дом", "cross": "Перекрёсток"},
		"edges": [["T", "market"], ["T", "alley"], ["alley", "zigzag"], ["zigzag", "columns"], ["columns", "yard"], ["yard", "apts"], ["apts", "A"],
			["yard", "square"], ["square", "A"], ["square", "fork"], ["fork", "CT"], ["fork", "a_down"], ["a_down", "A"], ["a_down", "CT"],
			["alley", "mid"], ["mid", "arch"], ["arch", "cross"], ["market", "cross"], ["cross", "house"], ["house", "long"], ["long", "B"],
			["mid", "mid_down"], ["mid_down", "fork"], ["mid_down", "pass"], ["pass", "b_down"], ["b_down", "B"], ["b_down", "CT"], ["pass", "B"]],
		"t_routes": {"A": [["T", "alley", "zigzag", "columns", "yard", "apts", "A"], ["T", "alley", "mid", "mid_down", "fork", "A"]],
			"B": [["T", "market", "cross", "house", "long", "B"], ["T", "alley", "mid", "mid_down", "pass", "B"]]},
		"ct_hold": [["CT", "a_down", "A"], ["CT", "fork", "square"], ["CT", "fork", "mid_down"], ["CT", "b_down", "B"], ["CT", "b_down", "pass"]],
	},
}

## Общая схема для карт, у которых ещё нет своей раскладки.
static func generic(theme: Dictionary) -> Dictionary:
	return {
		"theme": theme,
		"nodes": {"T": [90, 350], "t_top": [250, 200], "t_bot": [250, 500], "mid": [480, 350], "A_main": [520, 160], "A": [720, 140],
			"B_main": [520, 540], "B": [720, 560], "con": [650, 350], "CT": [880, 350]},
		"names": {"T": "Т-спавн", "t_top": "Верх", "t_bot": "Низ", "mid": "Мид", "A_main": "Вход A", "B_main": "Вход B", "con": "Коннектор", "CT": "CT-спавн"},
		"edges": [["T", "t_top"], ["T", "t_bot"], ["T", "mid"], ["t_top", "A_main"], ["A_main", "A"], ["t_bot", "B_main"], ["B_main", "B"],
			["mid", "con"], ["con", "A"], ["con", "B"], ["A", "CT"], ["B", "CT"], ["con", "CT"]],
		"t_routes": {"A": [["T", "t_top", "A_main", "A"], ["T", "mid", "con", "A"]], "B": [["T", "t_bot", "B_main", "B"], ["T", "mid", "con", "B"]]},
		"ct_hold": [["CT", "A"], ["CT", "A", "A_main"], ["CT", "con"], ["CT", "B"], ["CT", "B", "B_main"]],
	}

const THEMES := {
	"Breeze": {"ground": "d8dde3", "street": "f2f2ee", "roof": ["4f7fb8", "e9ecef", "3e6aa0", "dfe3e6"], "accent": "5a8a4a", "tree": true},
	"Hanami": {"ground": "a9c48a", "street": "e6e0d2", "roof": ["c2683d", "3f6b5a", "b55a34", "e7e1d6"], "accent": "e48fb1", "tree": true},
	"Sakura": {"ground": "c9c6c0", "street": "ebe7e0", "roof": ["9c5d3a", "e5ddd4", "8a4f30", "d9cfc4"], "accent": "f2a5c4", "tree": true},
	"Prison": {"ground": "e8ecef", "street": "f7f9fa", "roof": ["8d9298", "b9b2a6", "7b8086", "a7a097"], "accent": "c0392b", "tree": false},
	"Dune": {"ground": "e0c08a", "street": "f0dcb2", "roof": ["c99b5e", "b78a52", "d6ad73", "a97d48"], "accent": "6e8c3d", "tree": true},
	"Rust": {"ground": "b9ad98", "street": "d6cdbd", "roof": ["9c4a32", "8e9aa0", "7a3a26", "a9b1b5"], "accent": "5a7a4a", "tree": false},
	"Zone 7": {"ground": "a7a9ab", "street": "c8c9ca", "roof": ["6d7074", "c0392b", "5d6064", "8a8d90"], "accent": "e67e22", "tree": false},
	"Province": {"ground": "cfc6b6", "street": "e7e0d2", "roof": ["b07a52", "d4ccbd", "9c6a46", "bfb5a3"], "accent": "6a8a4a", "tree": true},
}

static func get_layout(map_name: String) -> Dictionary:
	if LAYOUTS.has(map_name):
		return LAYOUTS[map_name]
	return generic(THEMES.get(map_name, THEMES["Dune"]))
