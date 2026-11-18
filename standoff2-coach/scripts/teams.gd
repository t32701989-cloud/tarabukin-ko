extends RefCounted
## Команды, которые можно выбрать в начале карьеры.
## ВРЕМЕННЫЙ список (вымышленные названия) — будет заменён на настоящий.
## base — средний уровень стартового состава, money — стартовый бюджет, rep — репутация.

const START_TEAMS := [
	{"name": "Virtus.pro", "tag": "VP", "color": "ff5500", "diff": 1, "base": 60.0, "money": 220000, "rep": 60.0, "tier": 1,
		"logo": "res://assets/teams/vp/logo.png",
		"coach": {"name": "inverness", "photo": "res://assets/teams/vp/inverness.png"},
		"desc": "Топ-организация. Стартует в Про-лиге, большой бюджет и высокие ожидания.",
		"roster": [
			{"nick": "Lunax", "role": "Саппорт", "aim": 59, "iq": 63, "tw": 66, "age": 21, "photo": "res://assets/teams/vp/lunax.png"},
			{"nick": "reason", "role": "Снайпер", "aim": 66, "iq": 59, "tw": 60, "age": 20, "photo": "res://assets/teams/vp/reason.png"},
			{"nick": "chipaa", "role": "Лурк", "aim": 63, "iq": 61, "tw": 58, "age": 18, "photo": "res://assets/teams/vp/chipaa.png"},
			{"nick": "Arventy", "role": "Капитан", "aim": 58, "iq": 66, "tw": 63, "age": 19, "photo": "res://assets/teams/vp/arventy.png"},
			{"nick": "Hi-Lo", "role": "Энтри", "aim": 64, "iq": 57, "tw": 60, "age": 20, "photo": "res://assets/teams/vp/hi-lo.png"},
		]},
	{"name": "Tarabukin Esports", "tag": "TBK", "color": "ffb23e", "diff": 1, "base": 46.0, "money": 80000, "rep": 20.0,
		"desc": "Молодой проект с амбициями и нормальным бюджетом."},
	{"name": "Nova Squad", "tag": "NOVA", "color": "5aa9ff", "diff": 0, "base": 52.0, "money": 120000, "rep": 30.0,
		"desc": "Фавориты Открытой лиги. Сильный состав и деньги, но от вас ждут побед."},
	{"name": "Steel Vipers", "tag": "STV", "color": "2ecc71", "diff": 0, "base": 50.0, "money": 105000, "rep": 26.0,
		"desc": "Стабильная организация с опытными игроками."},
	{"name": "Red Cobras", "tag": "RCB", "color": "e74c3c", "diff": 1, "base": 47.0, "money": 70000, "rep": 18.0,
		"desc": "Агрессивная команда, которой не хватает дисциплины."},
	{"name": "Frost Legion", "tag": "FRL", "color": "7fd3ff", "diff": 1, "base": 45.0, "money": 90000, "rep": 22.0,
		"desc": "Слабее соперников, зато богатый спонсор."},
	{"name": "Desert Kings", "tag": "DK", "color": "d9b56a", "diff": 1, "base": 48.0, "money": 60000, "rep": 20.0,
		"desc": "Сильные игроки, но пустая касса."},
	{"name": "Night Owls", "tag": "OWL", "color": "8e44ad", "diff": 2, "base": 41.0, "money": 50000, "rep": 12.0,
		"desc": "Аутсайдеры. Мало денег, слабый состав — испытание для настоящего тренера."},
	{"name": "Dust Wolves", "tag": "DSW", "color": "95a5a6", "diff": 2, "base": 40.0, "money": 40000, "rep": 8.0,
		"desc": "Команда с самого дна. Только для опытных менеджеров."},
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
