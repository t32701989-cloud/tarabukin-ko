extends RefCounted
## Команды, которые можно выбрать в начале карьеры.
## Реальные команды. Новые добавляются сюда.
## base — средний уровень стартового состава, money — стартовый бюджет, rep — репутация.

const START_TEAMS := [
	{"name": "Virtus.pro", "country": "ru", "tag": "VP", "color": "ff5500", "diff": 1, "base": 76.0, "money": 220000, "rep": 60.0, "tier": 1,
		"logo": "res://assets/teams/vp/logo.png",
		"coach": {"name": "inverness", "photo": "res://assets/teams/vp/inverness.png"},
		"desc": "Топ-организация. Стартует в Про-лиге, большой бюджет и высокие ожидания.",
		"roster": [
			{"nick": "Lunax", "first": "Никита", "last": "Макаров", "role": "Саппорт", "aim": 74, "iq": 78, "tw": 82, "age": 21, "photo": "res://assets/teams/vp/lunax.png"},
			{"nick": "reason", "first": "Самир", "last": "Курбанов", "role": "Снайпер", "aim": 84, "iq": 74, "tw": 75, "age": 20, "photo": "res://assets/teams/vp/reason.png"},
			{"nick": "chipaa", "first": "", "last": "", "role": "Лурк", "aim": 80, "iq": 76, "tw": 72, "age": 18, "photo": "res://assets/teams/vp/chipaa.png"},
			{"nick": "Arventy", "first": "Иван", "last": "Шумкин", "role": "Капитан", "aim": 73, "iq": 84, "tw": 82, "age": 19, "photo": "res://assets/teams/vp/arventy.png"},
			{"nick": "Hi-Lo", "first": "Иван", "last": "Сидоренков", "role": "Энтри", "aim": 82, "iq": 71, "tw": 74, "age": 20, "photo": "res://assets/teams/vp/hi-lo.png"},
		]},
]

const DIFF_NAMES := ["Легко", "Средне", "Сложно"]
const DIFF_COLORS := ["7dd66b", "ffb23e", "ff6b6b"]

## Предыстории менеджера: бонусы на старте.
const BACKGROUNDS := [
	{"id": "pro", "name": "Бывший про-игрок", "desc": "+1 Тактика, +10 репутации"},
	{"id": "analyst", "name": "Аналитик", "desc": "+2 Тактика"},
	{"id": "motivator", "name": "Мотиватор", "desc": "+2 Мотивация"},
	{"id": "scout", "name": "Скаут", "desc": "+2 Скаутинг"},
	{"id": "streamer", "name": "Стример", "desc": "+15 репутации, +$15 000 бюджета"},
	{"id": "rookie", "name": "Новичок", "desc": "+3 свободных очка навыков"},
]

const COUNTRIES := ["Россия", "Украина", "Беларусь", "Казахстан", "Узбекистан", "Кыргызстан", "Армения", "Грузия", "Азербайджан", "Молдова", "Другая"]

## Страны: код флага (assets/flags/<код>.png) и название.
const COUNTRY_LIST := [
	["ru", "Россия"], ["ua", "Украина"], ["by", "Беларусь"], ["kz", "Казахстан"], ["uz", "Узбекистан"],
	["kg", "Кыргызстан"], ["tj", "Таджикистан"], ["am", "Армения"], ["ge", "Грузия"], ["az", "Азербайджан"],
	["md", "Молдова"], ["pl", "Польша"], ["de", "Германия"], ["us", "США"], ["xx", "Другая"],
]

## Качества менеджера парами (левое / правое), 0..20 каждое, общий пул очков.
const ATTR_PAIRS := [
	["communication", "Коммуникация", "finance", "Фин. грамотность"],
	["tactics", "Тактика", "stress", "Стрессоустойчивость"],
	["motivation", "Мотивация", "image", "Публичный имидж"],
	["scouting", "Скаутинг", "vision", "Видение игры"],
	["leadership", "Лидерство", "loyalty", "Лояльность"],
	["discipline", "Дисциплина", "analytics", "Аналитика"],
]
const ATTR_MAX := 20
const ATTR_POOL := 100

## Галерея готовых менеджеров (фотореалистичные портреты вымышленных людей).
const MANAGER_PORTRAITS := [
	{"file": "res://assets/managers/m01.png", "name": "Артём", "gender": "m"},
	{"file": "res://assets/managers/f01.png", "name": "Алина", "gender": "f"},
	{"file": "res://assets/managers/m02.png", "name": "Тимур", "gender": "m"},
	{"file": "res://assets/managers/f02.png", "name": "Дана", "gender": "f"},
	{"file": "res://assets/managers/m03.png", "name": "Марк", "gender": "m"},
	{"file": "res://assets/managers/f03.png", "name": "Вероника", "gender": "f"},
	{"file": "res://assets/managers/m04.png", "name": "Руслан", "gender": "m"},
	{"file": "res://assets/managers/f04.png", "name": "Камила", "gender": "f"},
	{"file": "res://assets/managers/m05.png", "name": "Давид", "gender": "m"},
	{"file": "res://assets/managers/f05.png", "name": "София", "gender": "f"},
	{"file": "res://assets/managers/m06.png", "name": "Олег", "gender": "m"},
	{"file": "res://assets/managers/f06.png", "name": "Ева", "gender": "f"},
]

const FIRST_M := ["Артём", "Максим", "Тимур", "Даниил", "Руслан", "Марк", "Илья", "Арсен", "Никита", "Егор"]
const FIRST_F := ["Алина", "Дана", "София", "Камила", "Ева", "Вероника", "Мария", "Аружан", "Полина", "Диана"]
const LAST := ["Иванов", "Ким", "Алиев", "Смирнов", "Петров", "Нуриев", "Ковалёв", "Сергеев", "Ахмедов", "Орлов"]
const NICKS := ["sirzephyr", "noahlord", "kingpin", "tactix", "mindgame", "coldcall", "ironmind", "blueprint", "overwatch", "maestro"]
