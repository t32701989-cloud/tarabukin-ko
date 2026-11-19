extends Node
## Глобальное состояние карьеры тренера: команда, лига, финансы, трансферы, сохранения.

const MatchSim := preload("res://scripts/match_sim.gd")
const Avatar := preload("res://scripts/avatar.gd")
const SAVE_PATH := "user://coach_save.json"

const ROLES := ["Рифлер", "Снайпер", "Саппорт", "Лурк", "2-й снайпер"]
const ROLE_MIGRATE := {"Капитан": "Рифлер", "Энтри": "Рифлер"}
const MAPS := ["Sandstone", "Province", "Rust", "Zone 9", "Breeze", "Dune"]
const TIERS := ["Открытая лига", "Про-лига", "Мировая серия"]
const STYLES := {"aggro": "Агрессия", "balanced": "Баланс", "defense": "Контроль"}
const STYLE_DESC := {
	"aggro": "Быстрые раши и ранние дуэли. Атака +4, защита -3.",
	"balanced": "Сбалансированный стиль. Атака +1, защита +1.",
	"defense": "Контроль карты и поздние ротации. Атака -3, защита +4.",
}
const TRAIN := {
	"aim": "Аим и стрельба",
	"iq": "Тактика и мышление",
	"tw": "Сыгранность",
	"maps": "Отработка карты",
	"rest": "Отдых и восстановление",
}
const COACH_SKILLS := {
	"tactics": "Тактика (+0.7 к силе команды за уровень)",
	"motivation": "Мотивация (быстрее восстановление формы)",
	"scout": "Скаутинг (точнее оценка потенциала, дешевле трансферы)",
}
const MAX_ROSTER := 8
const LAST_WEEK := 10
const NICK_A := ["Dark", "Ice", "Fire", "Night", "Storm", "Ghost", "Iron", "Silent", "Wild", "Toxic", "Neo", "Rapid", "Cold", "Alpha", "Zero", "Shadow", "Blaze", "Viper", "Raven", "Lucky", "Mad", "Red"]
const NICK_B := ["Wolf", "Fox", "Hawk", "Blade", "Shot", "King", "Rush", "Bear", "Cobra", "Ace", "Hunter", "Spike", "Dash", "Boss", "Star", "Lynx", "Fang", "Bolt"]
const AI_TEAMS := ["Phoenix Rush", "Dust Wolves", "Iron Syndicate", "Nova Squad", "Red Cobras", "Frost Legion", "Black Mamba", "Ghost Protocol", "Titan Core", "Neon Hunters", "Silent Storm", "Alpha Strike", "Crimson Tide", "Night Owls", "Steel Vipers", "Rapid Fire", "Lunar Esports", "Gold Rush", "Shadow Cartel", "Blaze United", "Thunder Bears", "Zero Point", "Arctic Foxes", "Desert Kings"]

signal changed

var active: bool = false
var game_over: String = ""
var legend: bool = false
var coach_name: String = tr("Тренер")
var team_name: String = tr("Моя команда")
var season: int = 1
var week: int = 1
var tier: int = 0
var money: int = 80000
var rep: float = 20.0
var coach_pts: int = 0
var coach_skill: Dictionary = {"tactics": 0, "motivation": 0, "scout": 0}
var players: Array = []
var market: Array = []
var map_skill: Dictionary = {}
var style: String = "balanced"
var train_focus: String = "aim"
var train_map: String = "Sandstone"
var league_teams: Array = []
var strengths: Dictionary = {}
var standings: Dictionary = {}
var schedule: Array = []
var playoff: Dictionary = {}
var match_done: bool = false
var news: Array = []
var history: Array = []
var titles: int = 0
var bad_seasons: int = 0
var next_id: int = 1
var last_report: String = ""
# профиль менеджера
var coach_age: int = 30
var coach_nick: String = ""
var coach_gender: String = "m"
var coach_country_code: String = "ru"
var coach_birth: Array = [1, 1, 1990]
var coach_attrs: Dictionary = {}
var coach_country: String = tr("Россия")
var coach_bg: String = "rookie"
var avatar: Dictionary = {}
var photo_path: String = ""
var team_tag: String = ""
var team_color: String = "ffb23e"
var team_logo: String = ""
var team_desc: String = ""
var staff_count: int = 0
var staff_list: Array = []        # нанятый персонал
var staff_market: Array = []      # кандидаты на найм
var mail: Array = []              # письма
var talks: Array = []             # разговоры (скаут, тренер, игроки)
var money_hist: Array = []        # баланс по неделям
var team_stats: Dictionary = {"w": 0, "l": 0, "mw": 0, "ml": 0, "rw": 0, "rl": 0}
var team_country: String = "ru"
var can_be_fired: bool = true
var country_only: bool = false
var staff_coach: String = ""
var staff_photo: String = ""

# ---------------------------------------------------------------- игроки

## Характеристики игрока (шкала 0..20). Группы: технические, ментальные, физические.
const ATTR_TECH := [["skill", "Навык"], ["awp", "AWP"], ["rifle", "Винтовка"], ["pistol", "Пистолет"], ["nades", "Гранаты"], ["creativity", "Креативность"], ["clutch", "Клатч"], ["tactics", "Тактика"]]
const ATTR_MENTAL := [["leader", "Лидер"], ["teamwork", "Командная работа"], ["morale", "Мораль"], ["conflict", "Конфликтность"], ["productivity", "Продуктивность"], ["stress", "Стрессоустойчивость"], ["loyalty", "Лояльность"]]
const ATTR_PHYS := [["reaction", "Реакция"], ["perception", "Восприятие"], ["immunity", "Иммунитет"], ["strength", "Сила"], ["stamina", "Выносливость"]]
const ROLE_BIAS := {
	"Снайпер": {"awp": 4.0, "rifle": -1.5, "reaction": 1.0, "perception": 1.0},
	"Рифлер": {"rifle": 2.0, "reaction": 1.5, "skill": 1.0, "awp": -3.0},
	"2-й снайпер": {"awp": 2.5, "rifle": 1.0, "perception": 1.0},
	"Саппорт": {"nades": 3.0, "teamwork": 2.0, "awp": -3.0},
	"Лурк": {"clutch": 3.0, "creativity": 2.0, "awp": -2.0},
}
const ATTR_GROUP := {
	"aim": ["skill", "awp", "rifle", "pistol", "reaction"],
	"iq": ["tactics", "creativity", "clutch", "nades", "productivity", "perception"],
	"tw": ["teamwork", "leader", "morale", "stress", "loyalty"],
}

static func all_attr_keys() -> Array:
	var r: Array = []
	for grp in [ATTR_TECH, ATTR_MENTAL, ATTR_PHYS]:
		for a in grp:
			r.append(a[0])
	return r

## Создать характеристики из уровней aim/iq/tw (0..100) с учётом роли.
func make_attrs(aim: float, iq: float, tw: float, role: String, seed_s: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed_s != "":
		rng.seed = hash(seed_s)
	else:
		rng.randomize()
	var a := {}
	var lv := {"aim": aim / 5.0, "iq": iq / 5.0, "tw": tw / 5.0}
	for k in all_attr_keys():
		var base: float = (lv["aim"] + lv["iq"] + lv["tw"]) / 3.0
		for grp in ATTR_GROUP:
			if ATTR_GROUP[grp].has(k):
				base = lv[grp]
		var v: float = base + rng.randf_range(-2.2, 2.2) + float(ROLE_BIAS.get(role, {}).get(k, 0.0))
		a[k] = snappedf(clampf(v, 1.0, 20.0), 0.01)
	return a

## Пересчитать aim/iq/tw (0..100) из характеристик.
func derive(p: Dictionary) -> void:
	var a: Dictionary = p["attrs"]
	var gun: float = float(a["awp"]) if p.get("role", "") == "Снайпер" else float(a["rifle"])
	var aim: float = (float(a["skill"]) * 2 + gun * 2 + float(a["pistol"]) * 0.5 + float(a["reaction"]) * 1.5 + float(a["perception"])) / 7.0
	var iq: float = (float(a["tactics"]) * 2 + float(a["creativity"]) + float(a["clutch"]) + float(a["nades"]) + float(a["productivity"]) + float(a["stress"])) / 7.0
	var tw: float = (float(a["teamwork"]) * 2 + float(a["leader"]) + float(a["morale"]) + float(a["loyalty"]) * 0.5 + float(a["stamina"]) * 0.5 + float(a["conflict"]) * 0.5) / 5.5
	p["aim"] = clampi(int(round(aim * 5.0)), 5, 99)
	p["iq"] = clampi(int(round(iq * 5.0)), 5, 99)
	p["tw"] = clampi(int(round(tw * 5.0)), 5, 99)

func ensure_attrs(p: Dictionary) -> void:
	if not p.has("attrs") or (p["attrs"] as Dictionary).is_empty():
		p["attrs"] = make_attrs(float(p["aim"]), float(p["iq"]), float(p["tw"]), str(p.get("role", "")), str(p.get("nick", "")))
	derive(p)

## Изменить группу характеристик (aim/iq/tw или "all") на delta (в шкале 0..20).
func bump(p: Dictionary, grp: String, delta: float) -> void:
	ensure_attrs(p)
	var keys: Array = all_attr_keys() if grp == "all" else ATTR_GROUP[grp]
	for k in keys:
		var d: float = delta * randf_range(0.6, 1.4)
		p["attrs"][k] = snappedf(clampf(float(p["attrs"][k]) + d, 1.0, 20.0), 0.01)
	derive(p)

## Общий рейтинг 1..100: среднее всех характеристик (0..20) × 5, с упором на ключевые для роли.
func ovr(p: Dictionary) -> int:
	var a: Dictionary = p.get("attrs", {})
	if a.is_empty():
		return clampi(int(round(float(p["aim"]) * 0.42 + float(p["iq"]) * 0.30 + float(p["tw"]) * 0.28)), 1, 100)
	var s: float = 0.0
	var n: float = 0.0
	for k in a:
		var w: float = 1.0
		if k == "awp" and p.get("role", "") != "Снайпер":
			w = 0.3
		if k == "rifle" and p.get("role", "") == "Снайпер":
			w = 0.5
		if ["immunity", "strength", "loyalty", "conflict"].has(k):
			w = 0.5
		s += float(a[k]) * w
		n += w
	return clampi(int(round(s / maxf(1.0, n) * 5.0)), 1, 100)

func _used_nicks() -> Array:
	var u: Array = []
	for p in players:
		u.append(p["nick"])
	for p in market:
		u.append(p["nick"])
	return u

func gen_player(base: float, role: String = "") -> Dictionary:
	var used: Array = _used_nicks()
	var nick: String = ""
	for i in 30:
		if randf() < 0.6:
			nick = NICK_A[randi() % NICK_A.size()] + NICK_B[randi() % NICK_B.size()]
		else:
			nick = NICK_B[randi() % NICK_B.size()].to_lower() + str(randi_range(1, 99))
		if not used.has(nick):
			break
	var age: int = randi_range(17, 28)
	var aim: int = clampi(int(base + randf_range(-7, 9)), 25, 95)
	var iq: int = clampi(int(base + randf_range(-9, 7)), 25, 95)
	var tw: int = clampi(int(base + randf_range(-8, 8)), 25, 95)
	var pot: int = clampi(int(base + randf_range(4, 26) - maxf(0.0, float(age - 22)) * 3.0), int(base) + 2, 99)
	if role == "":
		role = ROLES[randi() % ROLES.size()]
	var p := {"id": next_id, "nick": nick, "role": role, "aim": aim, "iq": iq, "tw": tw, "form": 75, "morale": 80, "age": age, "pot": pot, "inj": 0, "salary": 0, "matches": 0, "look": Avatar.random_cfg(), "photo": free_photo(), "country": _rand_country()}
	next_id += 1
	p["attrs"] = make_attrs(aim, iq, tw, role)
	derive(p)
	var o: int = ovr(p)
	p["salary"] = int(300 + (o - 30) * 32)
	init_player_meta(p)
	return p

## Контракт, дата рождения, история — для профиля игрока.
func init_player_meta(p: Dictionary) -> void:
	if not p.has("role2"):
		p["role2"] = ""
	if not p.has("health"):
		p["health"] = randi_range(80, 100)
	if not p.has("pr"):
		p["pr"] = randi_range(40, 90)
	if not p.has("birth"):
		p["birth"] = [randi_range(1, 28), randi_range(1, 12), 2026 - int(p["age"])]
	if not p.has("contract"):
		p["contract"] = {"type": "club", "end": season + randi_range(1, 3), "signed": "%02d.%02d.%d" % [1, 1, 2026]}
	if not p.has("thist"):
		p["thist"] = []
	if not p.has("mh"):
		p["mh"] = []
	if not p.has("ahist"):
		p["ahist"] = []

var _photo_pool: Array = []

## Набор фотореалистичных портретов для игроков без своего фото.
func photo_pool() -> Array:
	if _photo_pool.is_empty():
		var d := DirAccess.open("res://assets/players")
		if d:
			for f in d.get_files():
				var n: String = f.trim_suffix(".import")
				var pth: String = "res://assets/players/" + n
				if (n.ends_with(".jpg") or n.ends_with(".png")) and not _photo_pool.has(pth):
					_photo_pool.append(pth)
			_photo_pool.sort()
	return _photo_pool

## Свободный портрет: не занятый игроками команды и рынка.
func free_photo() -> String:
	var pool: Array = photo_pool()
	if pool.is_empty():
		return ""
	var used: Array = []
	for p in players + market:
		used.append(str(p.get("photo", "")))
	var free: Array = pool.filter(func(x): return not used.has(x))
	if free.is_empty():
		free = pool
	return free[randi() % free.size()]

const PLAYER_COUNTRIES := ["ru", "ru", "ru", "ua", "by", "kz", "kz", "uz", "kg", "am", "ge", "az", "md", "pl", "de", "us"]

func _rand_country() -> String:
	if country_only:
		return team_country
	return PLAYER_COUNTRIES[randi() % PLAYER_COUNTRIES.size()]

func fee(p: Dictionary) -> int:
	var o: int = ovr(p)
	var base: float = pow(maxf(5.0, float(o - 30)), 2.0) * 28.0
	var pot_bonus: float = maxf(0.0, float(p["pot"] - o)) * 120.0
	var disc: float = 1.0 - float(coach_skill["scout"]) * 0.03 - float(staff_level("scout")) * 0.03
	return int((base + pot_bonus) * disc)

func lineup() -> Array:
	var res: Array = []
	for p in players:
		if int(p["inj"]) <= 0 and res.size() < 5:
			res.append(p)
	return res

func has_enough_players() -> bool:
	return lineup().size() >= 5

# ---------------------------------------------------------------- мощь

func team_power(st: String, map_name: String) -> Dictionary:
	var l: Array = lineup()
	var s: float = 0.0
	var roles: Array = []
	for p in l:
		s += (float(p["aim"]) * 0.42 + float(p["iq"]) * 0.30 + float(p["tw"]) * 0.28) * (0.85 + 0.30 * float(p["form"]) / 100.0)
		if not roles.has(p["role"]):
			roles.append(p["role"])
	if l.size() > 0:
		s /= float(l.size())
	var bonus: float = 0.0
	if roles.has("Снайпер"): bonus += 2.0
	if roles.has("Рифлер"): bonus += 1.5
	if roles.has("Саппорт"): bonus += 1.0
	if roles.has("Лурк"): bonus += 1.0
	if roles.has("2-й снайпер"): bonus += 0.5
	if roles.size() >= 4: bonus += 1.5
	bonus += float(coach_skill["tactics"]) * 0.7
	if staff_coach != "":
		bonus += 1.5
	bonus += float(staff_level("analyst")) * 0.5
	var cap: Dictionary = captain()
	if not cap.is_empty() and l.has(cap):
		bonus += float(cap.get("attrs", {}).get("leader", 10.0)) / 10.0
	var mor: float = 0.0
	for p in l:
		mor += float(p.get("morale", 80))
	if l.size() > 0:
		bonus += (mor / l.size() - 70.0) / 15.0
	bonus += (float(map_skill.get(map_name, 40)) - 40.0) / 8.0
	var a: float = s + bonus
	var d: float = s + bonus
	match st:
		"aggro":
			a += 4.0; d -= 3.0
		"defense":
			a -= 3.0; d += 4.0
		_:
			a += 1.0; d += 1.0
	return {"atk": a, "dfn": d, "base": s + bonus}

func opp_strength(team: String) -> float:
	return float(strengths.get(team, 50.0))

# ---------------------------------------------------------------- глобальный рейтинг Rankoff

var rankoff: Dictionary = {}     # команда -> очки (Эло)

## Стартовые очки Rankoff: у реальных команд — из базы, у остальных — по силе (ниже топа).
func _base_rank(n: String) -> float:
	for rt in load("res://scripts/teams.gd").START_TEAMS:
		if rt["name"] == n and rt.has("rankoff"):
			return float(rt["rankoff"])
	if strengths.has(n):
		return clampf(float(strengths[n]) * 11.0 - 50.0, 150.0, 880.0)
	return 200.0 + float(abs(hash(n)) % 600)

func _init_rankoff() -> void:
	rankoff = {}
	for rt in load("res://scripts/teams.gd").START_TEAMS:
		rankoff[rt["name"]] = _base_rank(rt["name"])
	for n in strengths:
		rankoff[n] = _base_rank(n)
	if not rankoff.has(team_name):
		rankoff[team_name] = clampf(team_power("balanced", MAPS[0])["base"] * 11.0 - 50.0, 150.0, 880.0)

func rankoff_update(a: String, b: String, a_won: bool, k: float = 28.0) -> void:
	if rankoff.is_empty():
		_init_rankoff()
	var ra: float = float(rankoff.get(a, 1500.0))
	var rb: float = float(rankoff.get(b, 1500.0))
	var ea: float = 1.0 / (1.0 + pow(10.0, (rb - ra) / 400.0))
	var sa: float = 1.0 if a_won else 0.0
	rankoff[a] = ra + k * (sa - ea)
	rankoff[b] = rb + k * ((1.0 - sa) - (1.0 - ea))

func rankoff_list() -> Array:
	if rankoff.is_empty():
		_init_rankoff()
	if not rankoff.has(team_name):
		rankoff[team_name] = _base_rank(team_name) if _base_rank(team_name) > 0.0 else 500.0
	var arr: Array = rankoff.keys()
	arr.sort_custom(func(x, y): return float(rankoff[x]) > float(rankoff[y]))
	return arr

## Команды вне лиги тоже играют: лёгкое случайное движение очков каждую неделю.
func _rankoff_drift() -> void:
	for n in rankoff:
		if not league_teams.has(n):
			rankoff[n] = float(rankoff[n]) + randf_range(-12.0, 12.0)

# ---------------------------------------------------------------- персонал

const STAFF_ROLES := {
	"coach": ["Тренер", "Ускоряет тренировки игроков"],
	"scout": ["Скаут", "Точнее оценка потенциала, дешевле трансферы"],
	"analyst": ["Аналитик", "Разбор соперников: +0.5 к силе команды за звезду"],
	"findir": ["Финансовый директор", "+4% к доходу спонсоров за звезду"],
	"lawyer": ["Юрист", "-3% к зарплатам игроков за звезду"],
	"event": ["Ивент-менеджер", "Растёт репутация клуба"],
	"pr": ["PR-менеджер", "+3% к доходу спонсоров и репутация"],
	"psych": ["Психолог", "Быстрее восстанавливается мораль"],
	"physio": ["Физиотерапевт", "Меньше травм, быстрее восстанавливается форма"],
}
const STAFF_TECH := {
	"coach": [["skill", "Навык"], ["awp", "AWP"], ["rifle", "Винтовка"], ["pistol", "Пистолет"], ["nades", "Гранаты"], ["creativity", "Креативность"], ["clutch", "Клатч"], ["tactics", "Тактика"]],
	"scout": [["talent", "Поиск талантов"], ["potential", "Оценка потенциала"], ["contacts", "Сеть контактов"]],
	"analyst": [["demos", "Разбор демо"], ["statistics", "Статистика"], ["tactics", "Тактика"]],
	"findir": [["budget", "Бюджет"], ["negotiation", "Переговоры"], ["sponsorship", "Спонсорство"]],
	"lawyer": [["contracts", "Контракты"], ["negotiation", "Переговоры"]],
	"event": [["events", "Организация мероприятий"], ["media", "Медиа"]],
	"pr": [["media", "Медиа"], ["social", "Соцсети"], ["sponsorship", "Спонсорство"]],
	"psych": [["psychology", "Психология"], ["motivation", "Мотивация"]],
	"physio": [["medicine", "Медицина"], ["recovery", "Восстановление"]],
}
const STAFF_MENTAL := [["communication", "Коммуникация"], ["finance", "Фин. грамотность"], ["eventorg", "Организатор мероприятий"], ["morale", "Мораль"], ["conflict", "Конфликтность"], ["productivity", "Продуктивность"], ["loyalty", "Лояльность"], ["stress", "Стрессоустойчивость"]]
const STAFF_PHYS := [["immunity", "Иммунитет"]]
const STAFF_FIRST := ["Алексей", "Дмитрий", "Сергей", "Михаил", "Анна", "Елена", "Ольга", "Игорь", "Олег", "Мария", "Кирилл", "Роман", "Виктория", "Артур", "Никита", "Ксения"]
const STAFF_LAST := ["Волков", "Морозов", "Лебедев", "Соколов", "Попов", "Новиков", "Фёдоров", "Козлов", "Павлов", "Голубев", "Егоров", "Зайцев", "Белов", "Орлов", "Тихонов", "Комаров"]
const FEMALE_FIRST := ["Анна", "Елена", "Ольга", "Мария", "Виктория", "Ксения"]

## Портреты для персонала: деловые фото (менеджеры), для женщин — женские.
func _staff_photo(female: bool) -> String:
	var pool: Array = []
	for i in range(1, 7):
		pool.append("res://assets/managers/%s%02d.png" % ["f" if female else "m", i])
	var used: Array = [photo_path]
	for s in staff_list + staff_market:
		used.append(str(s.get("photo", "")))
	var free: Array = pool.filter(func(x): return not used.has(x))
	if free.is_empty():
		free = pool.filter(func(x): return x != photo_path)
	return free[randi() % free.size()]

func staff_stars(s: Dictionary) -> float:
	var a: Dictionary = s.get("attrs", {})
	var keys: Array = STAFF_TECH.get(s["role"], []).map(func(x): return x[0])
	if keys.is_empty() or a.is_empty():
		return float(s.get("lvl", 1))
	var sum: float = 0.0
	for k in keys:
		sum += float(a.get(k, 10))
	return clampf(sum / keys.size() / 4.0, 0.5, 5.0)

func make_staff_attrs(role: String, lvl: float) -> Dictionary:
	var a := {}
	var base: float = 4.0 + lvl * 3.0
	for e in STAFF_TECH.get(role, []):
		a[e[0]] = snappedf(clampf(base + randf_range(-2.0, 2.0), 1.0, 20.0), 0.01)
	for e in STAFF_MENTAL + STAFF_PHYS:
		a[e[0]] = snappedf(clampf(9.0 + lvl + randf_range(-4.0, 5.0), 1.0, 20.0), 0.01)
	return a

func gen_staff(role: String, lvl: int = -1) -> Dictionary:
	if lvl < 0:
		lvl = randi_range(1, 4)
	var first: String = STAFF_FIRST[randi() % STAFF_FIRST.size()]
	var last: String = STAFF_LAST[randi() % STAFF_LAST.size()]
	var female: bool = FEMALE_FIRST.has(first)
	if female:
		last += "а"
	var s := {"role": role, "name": "%s %s" % [first, last], "lvl": lvl, "salary": 250 + lvl * 220, "fee": 1500 * lvl * lvl,
		"photo": _staff_photo(female), "country": _rand_country(), "attrs": make_staff_attrs(role, float(lvl))}
	s["lvl"] = int(round(staff_stars(s)))
	return s

func refresh_staff_market() -> void:
	staff_market = []
	for r in STAFF_ROLES:
		staff_market.append(gen_staff(r))

func staff_level(role: String) -> int:
	var best: int = 0
	for s in staff_list:
		if s["role"] == role:
			best = maxi(best, int(round(staff_stars(s))))
	return best

func hire_staff(idx: int) -> String:
	if idx < 0 or idx >= staff_market.size():
		return tr("Ошибка")
	var s: Dictionary = staff_market[idx]
	if staff_level(s["role"]) > 0:
		return tr("Такая должность уже занята. Сначала уволите сотрудника.")
	if money < int(s["fee"]):
		return tr("Не хватает денег.")
	money -= int(s["fee"])
	staff_list.append(s)
	staff_market.remove_at(idx)
	staff_count = staff_list.size()
	add_mail(tr("Отдел кадров"), tr("Новый сотрудник: %s") % s["name"], tr("%s принят на должность «%s» (уровень %d). Зарплата: $%d в неделю.") % [s["name"], tr(STAFF_ROLES[s["role"]][0]), s["lvl"], s["salary"]])
	changed.emit()
	return ""

func fire_staff(idx: int) -> void:
	if idx < 0 or idx >= staff_list.size():
		return
	var s: Dictionary = staff_list[idx]
	money -= int(s["salary"]) * 2
	staff_list.remove_at(idx)
	staff_count = staff_list.size()
	add_news(tr("%s уволен из штаба.") % s["name"])
	changed.emit()

func staff_salaries() -> int:
	var t2: int = 0
	for s in staff_list:
		t2 += int(s["salary"])
	return t2

func weekly_income() -> int:
	var k: float = 1.0 + 0.04 * staff_level("findir") + 0.03 * staff_level("pr")
	return int((4000 + rep * 70.0 + float(tier) * 3500.0) * k)

func player_salaries() -> int:
	var s: int = 0
	for p in players:
		s += int(p["salary"])
	return int(s * (1.0 - 0.03 * staff_level("lawyer")))

func upkeep() -> int:
	return 800 + tier * 600

# ---------------------------------------------------------------- почта

func add_mail(from: String, subject: String, body: String, kind: String = "info") -> void:
	mail.push_front({"from": from, "subject": subject, "body": body, "season": season, "week": week, "read": false, "kind": kind})
	while mail.size() > 60:
		mail.pop_back()

func unread_mail() -> int:
	var n: int = 0
	for m in mail:
		if not bool(m["read"]):
			n += 1
	return n

# ---------------------------------------------------------------- разговоры

func add_talk(who: String, role: String, photo: String, text: String, options: Array) -> void:
	talks.push_front({"who": who, "role": role, "photo": photo, "text": text, "options": options, "answer": -1, "season": season, "week": week})
	while talks.size() > 30:
		talks.pop_back()

func unread_talks() -> int:
	var n: int = 0
	for t2 in talks:
		if int(t2["answer"]) < 0:
			n += 1
	return n

## Ответ в разговоре: эффекты {morale:+n (игрок), form, sign (индекс на рынке), rep, money}
func answer_talk(i: int, opt: int) -> void:
	var t2: Dictionary = talks[i]
	if int(t2["answer"]) >= 0:
		return
	t2["answer"] = opt
	var o: Dictionary = t2["options"][opt]
	var eff: Dictionary = o.get("eff", {})
	for p in players:
		if p["nick"] == t2["who"]:
			p["morale"] = clampi(int(p.get("morale", 80)) + int(eff.get("morale", 0)), 10, 100)
			p["salary"] = int(p["salary"]) + int(eff.get("salary", 0))
	if eff.has("all_morale"):
		for p in players:
			p["morale"] = clampi(int(p.get("morale", 80)) + int(eff["all_morale"]), 10, 100)
	if eff.has("train"):
		for p in players:
			if p["nick"] == eff["train"][0]:
				var lst: Array = ptrain(p)["coach"]
				if not lst.has(eff["train"][1]):
					if lst.size() >= TRAIN_MAX:
						lst.pop_front()
					lst.append(eff["train"][1])
	rep = clampf(rep + float(eff.get("rep", 0)), 0.0, 100.0)
	money += int(eff.get("money", 0))
	mail.push_front({"from": coach_name, "to": t2["who"], "subject": tr("Ответ: %s") % t2["who"], "body": str(o["t"]), "season": season, "week": week, "read": true, "kind": "out"})
	changed.emit()

## Генерация писем и разговоров каждую неделю.
func _weekly_feed() -> void:
	var others: Array = league_teams.filter(func(x): return x != team_name)
	# новости киберспорта
	if randf() < 0.55 and not others.is_empty():
		var tm: String = others[randi() % others.size()]
		var news_t: Array = [
			[tr("%s объявили буткемп перед следующим туром"), tr("Организация %s проведёт недельный буткемп, чтобы подготовиться к следующим матчам. Ожидается, что команда покажет новые тактики.")],
			[tr("%s показывают лучшую форму сезона"), tr("По данным аналитиков, %s набрали отличную форму и считаются одними из фаворитов недели.")],
			[tr("%s подписали нового спонсора"), tr("Организация %s объявила о новом спонсорском контракте. Сумма сделки не раскрывается.")],
		]
		var n2: Array = news_t[randi() % news_t.size()]
		add_mail(tr("Новости киберспорта"), n2[0] % tm, n2[1] % tm, "news")
	# трансферный слух
	if randf() < 0.35 and not others.is_empty() and not market.is_empty():
		var p2: Dictionary = market[randi() % market.size()]
		var tm2: String = others[randi() % others.size()]
		add_mail(tr("Трансферный рынок"), tr("Слух: %s интересуются %s") % [tm2, p2["nick"]], tr("Источники сообщают, что %s ведут переговоры со свободным агентом %s (%s, ОБЩ %d). Если он нужен вам — поторопитесь в разделе «Трансферы».") % [tm2, p2["nick"], tr(p2["role"]), ovr(p2)], "transfer")
	# разговоры
	var r: float = randf()
	var sc: Array = staff_list.filter(func(x): return x["role"] == "scout")
	var co: Array = staff_list.filter(func(x): return x["role"] == "coach")
	if r < 0.3 and not sc.is_empty() and not market.is_empty():
		var best: Dictionary = market[0]
		for p3 in market:
			if ovr(p3) > ovr(best): best = p3
		var s: Dictionary = sc[0]
		add_talk(s["name"], tr("Скаут"), s["photo"], tr("Нашёл интересного игрока: %s, %s, ОБЩ %d, потенциал около %d. Цена — %s. Стоит присмотреться?") % [best["nick"], tr(best["role"]), ovr(best), int(best.get("pot_est", best["pot"])), "$%d" % fee(best)],
			[{"t": tr("Спасибо, посмотрю в трансферах."), "eff": {}}, {"t": tr("Сейчас не до этого."), "eff": {}}])
	elif r < 0.6 and not co.is_empty() and not players.is_empty():
		var weak: Dictionary = players[0]
		for p4 in players:
			if ovr(p4) < ovr(weak): weak = p4
		var c: Dictionary = co[0]
		var wa: String = weakest_attr(weak)
		var wname: String = ""
		for e in ATTR_TECH:
			if e[0] == wa: wname = tr(e[1])
		add_talk(c["name"], tr("Тренер"), c["photo"], tr("%s проседает в «%s». Предлагаю поставить ему индивидуальную тренировку на это.") % [weak["nick"], wname],
			[{"t": tr("Согласен, ставь."), "eff": {"train": [weak["nick"], wa]}}, {"t": tr("Пусть тренирует то, что выбрал."), "eff": {}}])
	elif r < 0.85 and players.size() > 0:
		var lu: Array = lineup()
		var bench: Array = players.filter(func(x): return not lu.has(x))
		var p5: Dictionary = bench[0] if not bench.is_empty() else players[randi() % players.size()]
		if not bench.is_empty():
			add_talk(p5["nick"], tr("Игрок"), p5.get("photo", ""), tr("Тренер, я давно не играю в основе. Хочу больше игрового времени, иначе буду думать об уходе."),
				[{"t": tr("Работай на тренировках — шанс будет."), "eff": {"morale": 5}}, {"t": tr("Сейчас основа сильнее, жди."), "eff": {"morale": -10}}])
		else:
			add_talk(p5["nick"], tr("Игрок"), p5.get("photo", ""), tr("Я чувствую, что заслуживаю прибавку к зарплате. Что скажете?"),
				[{"t": tr("Хорошо, +$200 в неделю."), "eff": {"morale": 12, "salary": 200}}, {"t": tr("Пока рано, докажи в матчах."), "eff": {"morale": -8}}])

# ---------------------------------------------------------------- новости

func add_news(t: String) -> void:
	news.push_front(tr("[Сез. %d, нед. %d] %s") % [season, week, t])
	while news.size() > 40:
		news.pop_back()

# ---------------------------------------------------------------- новая игра

const PHOTO_PATH := "user://coach_photo.png"

## coach: {name, age, country, bg, avatar, photo}; team: запись из teams.gd (или своя команда)
func new_game(coach: Dictionary, team: Dictionary) -> void:
	var c_name: String = str(coach.get("name", "")).strip_edges()
	var t_name: String = str(team.get("name", "")).strip_edges()
	coach_name = c_name if c_name != "" else "Тренер"
	team_name = t_name if t_name != "" else "Моя команда"
	coach_age = int(coach.get("age", 30))
	coach_nick = str(coach.get("nick", "")).strip_edges()
	coach_gender = str(coach.get("gender", "m"))
	coach_country_code = str(coach.get("country_code", "ru"))
	coach_birth = coach.get("birth", [1, 1, 1990])
	coach_attrs = coach.get("attrs", {}).duplicate()
	coach_country = str(coach.get("country", "Россия"))
	coach_bg = str(coach.get("bg", "rookie"))
	avatar = coach.get("avatar", {}).duplicate()
	photo_path = str(coach.get("photo", ""))
	team_tag = str(team.get("tag", team_name.substr(0, 3).to_upper()))
	team_color = str(team.get("color", "ffb23e"))
	team_logo = str(team.get("logo", ""))
	team_desc = str(team.get("desc", ""))
	staff_count = int(team.get("staff", 0))
	staff_list = []
	mail = []
	money_hist = []
	team_stats = {"w": 0, "l": 0, "mw": 0, "ml": 0, "rw": 0, "rl": 0}
	talks = []
	# штат: реальный тренер команды + сгенерированные сотрудники
	var staff_src: Dictionary = team.get("coach", {})
	if not staff_src.is_empty():
		var cs := {"role": "coach", "name": str(staff_src["name"]), "nick": str(staff_src["name"]), "lvl": 4, "salary": 1200, "fee": 0,
			"photo": str(staff_src.get("photo", "")), "country": str(staff_src.get("country", team.get("country", "ru"))), "attrs": make_staff_attrs("coach", 4.0)}
		staff_list.append(cs)
	var roles_k: Array = STAFF_ROLES.keys()
	roles_k.shuffle()
	var want: int = staff_count
	if not bool(team.get("custom", false)):
		want = randi_range(4, 7)   # у реальных команд — случайный штат
	for r in roles_k:
		if staff_list.size() >= want + (1 if not staff_src.is_empty() else 0):
			break
		if staff_level(r) == 0:
			staff_list.append(gen_staff(r, randi_range(2, 4)))
	staff_count = staff_list.size()
	refresh_staff_market()
	team_country = str(team.get("country", coach.get("country_code", "ru")))
	can_be_fired = bool(team.get("can_be_fired", true))
	country_only = bool(team.get("country_only", false))
	var staff: Dictionary = team.get("coach", {})
	staff_coach = str(staff.get("name", ""))
	staff_photo = str(staff.get("photo", ""))
	active = true
	game_over = ""
	legend = false
	season = 1
	week = 1
	tier = int(team.get("tier", 0))
	money = int(team.get("money", 80000))
	rep = float(team.get("rep", 20.0))
	coach_pts = 1
	coach_skill = {"tactics": 0, "motivation": 0, "scout": 0}
	match coach_bg:
		"pro":
			coach_skill["tactics"] = 1; rep += 10.0
		"analyst":
			coach_skill["tactics"] = 2
		"motivator":
			coach_skill["motivation"] = 2
		"scout":
			coach_skill["scout"] = 2
		"streamer":
			rep += 15.0; money += 15000
		"rookie":
			coach_pts += 3
	if not coach_attrs.is_empty():
		var A := func(k: String) -> int: return int(coach_attrs.get(k, 0))
		coach_skill["tactics"] = clampi((A.call("tactics") + A.call("vision") + A.call("analytics")) / 12, 0, 5)
		coach_skill["motivation"] = clampi((A.call("motivation") + A.call("leadership") + A.call("communication")) / 12, 0, 5)
		coach_skill["scout"] = clampi((A.call("scouting") + A.call("analytics")) / 8, 0, 5)
		money += A.call("finance") * 1500
		rep += float(A.call("image")) * 0.6
	var base: float = float(team.get("base", 46.0))
	players = []
	market = []
	news = []
	history = []
	titles = 0
	bad_seasons = 0
	next_id = 1
	style = "balanced"
	train_focus = "aim"
	map_skill = {}
	for m in MAPS:
		map_skill[m] = randi_range(32, 52)
	train_map = MAPS[0]
	var roster: Array = team.get("roster", [])
	if bool(team.get("empty_roster", false)):
		pass
	elif roster.is_empty():
		for r in ROLES:
			players.append(gen_player(base, r))
		for p in players:
			p["age"] = randi_range(17, 23)
	else:
		for rp in roster:
			var p: Dictionary = gen_player(base, rp["role"])
			for k in ["nick", "aim", "iq", "tw", "age", "photo", "country", "first", "last", "role2", "captain"]:
				if rp.has(k):
					p[k] = rp[k]
			if not rp.has("country"):
				p["country"] = team_country
			p["attrs"] = make_attrs(float(p["aim"]), float(p["iq"]), float(p["tw"]), str(p["role"]), str(p["nick"]))
			if bool(p.get("captain", false)):
				p["attrs"]["leader"] = minf(20.0, float(p["attrs"]["leader"]) + 5.0)
				p["attrs"]["tactics"] = minf(20.0, float(p["attrs"]["tactics"]) + 3.0)
			derive(p)
			p["pot"] = maxi(int(p["pot"]), ovr(p) + randi_range(4, 12))
			p["salary"] = int(300 + (ovr(p) - 30) * 32)
			players.append(p)
	if roster.is_empty() and not bool(team.get("empty_roster", false)) and not bool(team.get("custom", false)):
		players.append(gen_player(base - 4.0))
	_start_league()
	_init_rankoff()
	_refresh_market(12)
	add_mail(tr("Совет директоров"), tr("Добро пожаловать в «%s»!") % team_name,
		tr("Здравствуйте, %s!\n\nСовет директоров рад приветствовать вас на посту главного менеджера.\nЦель на сезон: место не ниже %d в лиге «%s».\nБюджет клуба: $%d.\n\nУдачи, мы верим в вас!") % [coach_name, [4, 6, 8][tier], tr(TIERS[tier]), money], "good")
	add_mail(tr("Оргкомитет лиги"), tr("Приглашение: %s, сезон %d") % [tr(TIERS[tier]), season], tr("Ваша команда приглашена в турнир «%s». Регулярный сезон: 7 туров, затем плей-офф. Удачи!") % tr(TIERS[tier]), "invite")
	add_mail(tr("Аналитический отдел"), tr("Как устроена неделя"), tr("1. Выберите фокус тренировок в разделе «Тренировка».\n2. Проверьте состав и форму игроков.\n3. Нажмите «К матчу» и сыграйте матч недели.\n4. Нажмите «Продолжить», чтобы перейти к следующей неделе."))
	add_news(tr("%s (%d лет, %s) принимает команду «%s». Цель совета директоров: топ-%d в лиге «%s».") % [coach_name, coach_age, tr(coach_country), team_name, [4, 6, 8][tier], tr(TIERS[tier])])
	if staff_coach != "":
		add_news(tr("В тренерском штабе остаётся %s (+1.5 к силе команды).") % staff_coach)
	save()
	changed.emit()

## Лига состоит только из реальных команд базы (плюс своя организация игрока).
func _start_league() -> void:
	week = 1
	match_done = false
	league_teams = [team_name]
	strengths = {}
	for rt in load("res://scripts/teams.gd").START_TEAMS:
		var n: String = rt["name"]
		if n != team_name:
			league_teams.append(n)
			strengths[n] = _real_strength(n)
	standings = {}
	for tm in league_teams:
		standings[tm] = {"w": 0, "l": 0, "rd": 0}
	var order: Array = league_teams.duplicate()
	order.shuffle()
	schedule = _make_schedule(order)
	playoff = {"semis": [], "sf": {}, "final": [], "champion": ""}

func _real_strength(n: String) -> float:
	for rt in load("res://scripts/teams.gd").START_TEAMS:
		if rt["name"] == n:
			return float(rt["base"]) - 4.0
	return 0.0

## Круговая система для любого числа команд; туры повторяются, чтобы заполнить 7 недель.
func _make_schedule(teams: Array) -> Array:
	var tl: Array = teams.duplicate()
	if tl.size() % 2 == 1:
		tl.append("")          # пустое место = выходной
	var n: int = tl.size()
	var rounds: Array = []
	if n >= 2:
		for r in n - 1:
			var pairs: Array = []
			for i in n / 2:
				var a2: String = tl[i]
				var b2: String = tl[n - 1 - i]
				if a2 != "" and b2 != "":
					pairs.append([a2, b2] if r % 2 == 0 else [b2, a2])
			rounds.append(pairs)
			var last = tl.pop_back()
			tl.insert(1, last)
	var res: Array = []
	for w in 7:
		res.append(rounds[w % rounds.size()] if not rounds.is_empty() else [])
	return res

func _refresh_market(n: int) -> void:
	market = []
	var err: int = maxi(0, 12 - int(coach_skill["scout"]) * 2 - staff_level("scout") * 2)
	for i in n:
		var base: float = 38.0 + float(tier) * 12.0 + randf_range(-4, 14)
		var p: Dictionary = gen_player(base)
		p["pot_est"] = clampi(int(p["pot"]) + randi_range(-err, err), 30, 99)
		market.append(p)

# ---------------------------------------------------------------- расписание

func rank_list() -> Array:
	var arr: Array = league_teams.duplicate()
	arr.sort_custom(func(a, b):
		var sa: Dictionary = standings[a]
		var sb: Dictionary = standings[b]
		if sa["w"] != sb["w"]:
			return sa["w"] > sb["w"]
		return sa["rd"] > sb["rd"])
	return arr

func my_rank() -> int:
	return rank_list().find(team_name) + 1

func phase_name() -> String:
	if week <= 7: return tr("Регулярный сезон, тур %d/7") % week
	if week == 8: return tr("Плей-офф: полуфиналы")
	if week == 9: return tr("Плей-офф: финал")
	return tr("Межсезонье")

func player_match() -> Dictionary:
	if schedule.size() < 7:
		return {}
	if week <= 7:
		for pair in schedule[week - 1]:
			if pair.has(team_name):
				var opp: String = pair[1] if pair[0] == team_name else pair[0]
				return {"opp": opp, "bo": 1, "kind": "league"}
	elif week == 8:
		for i in playoff["semis"].size():
			var pair: Array = playoff["semis"][i]
			if pair.has(team_name):
				var opp2: String = pair[1] if pair[0] == team_name else pair[0]
				return {"opp": opp2, "bo": 3, "kind": "semi", "idx": i}
	elif week == 9:
		var f: Array = playoff["final"]
		if f.size() == 2 and f.has(team_name):
			var opp3: String = f[1] if f[0] == team_name else f[0]
			return {"opp": opp3, "bo": 3, "kind": "final"}
	return {}

# ---------------------------------------------------------------- результаты

func _record_league(a: String, b: String, res: Dictionary) -> void:
	var w: int = int(res["winner"])
	var sc: Array = res["score"]
	var win_t: String = a if w == 0 else b
	var lose_t: String = b if w == 0 else a
	standings[win_t]["w"] += 1
	standings[lose_t]["l"] += 1
	var diff: int = abs(int(sc[0]) - int(sc[1]))
	standings[win_t]["rd"] += diff
	standings[lose_t]["rd"] -= diff
	rankoff_update(win_t, lose_t, true)

func _ai_series(a: String, b: String, bo: int) -> Dictionary:
	var need: int = (bo + 1) / 2
	var wins: Array = [0, 0]
	var total: Array = [0, 0]
	while wins[0] < need and wins[1] < need:
		var r: Dictionary = MatchSim.quick(opp_strength(a) if a != team_name else team_power(style, "Sandstone")["base"], opp_strength(b) if b != team_name else team_power(style, "Sandstone")["base"])
		wins[r["winner"]] += 1
		total[0] += r["score"][0]
		total[1] += r["score"][1]
	return {"winner": 0 if wins[0] > wins[1] else 1, "score": total}

func load_photo() -> Texture2D:
	return photo_texture(photo_path)

## Фото по пути: res:// — ресурс игры, user:// — загруженный файл.
static func photo_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if path.begins_with("res://"):
		return load(path) if ResourceLoader.exists(path) else null
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

## Вызывается экраном матча после завершения серии.
func report_match(res: Dictionary) -> void:
	var m: Dictionary = player_match()
	if m.is_empty() or match_done:
		return
	var won: bool = bool(res["won"])
	var tier_k: int = tier + 1
	team_stats["w" if won else "l"] = int(team_stats.get("w" if won else "l", 0)) + 1
	_match_lines(res, str(m["opp"]))
	team_stats["mw"] = int(team_stats.get("mw", 0)) + int(res.get("maps_my", 0))
	team_stats["ml"] = int(team_stats.get("ml", 0)) + int(res.get("maps_opp", 0))
	team_stats["rw"] = int(team_stats.get("rw", 0)) + int(res.get("my", 0))
	team_stats["rl"] = int(team_stats.get("rl", 0)) + int(res.get("opp", 0))
	for s in res.get("stats", []):
		for p in players:
			if p["nick"] == s["nick"]:
				var st: Dictionary = p.get("st", {"k": 0, "d": 0, "maps": 0})
				st["k"] = int(st.get("k", 0)) + int(s["k"])
				st["d"] = int(st.get("d", 0)) + int(s["d"])
				st["maps"] = int(st.get("maps", 0)) + int(res.get("maps_my", 0)) + int(res.get("maps_opp", 0))
				p["st"] = st
	match m["kind"]:
		"league":
			var a: String = team_name
			var b: String = m["opp"]
			_record_league(a, b, {"winner": 0 if won else 1, "score": [res["my"], res["opp"]]})
		"semi":
			playoff["sf"][str(m["idx"])] = team_name if won else m["opp"]
			rankoff_update(team_name, m["opp"], won, 40.0)
		"final":
			playoff["champion"] = team_name if won else m["opp"]
			rankoff_update(team_name, m["opp"], won, 60.0)
	if won:
		money += 1500 * tier_k
		rep = minf(100.0, rep + (1.5 if m["kind"] == "league" else 3.0))
		coach_pts += 1 if m["kind"] == "league" else 2
	else:
		rep = maxf(0.0, rep - 0.6)
	for p in lineup():
		p["form"] = clampi(int(p["form"]) + (6 if won else -5), 20, 100)
		p["matches"] += 1
		if randf() < 0.03 * (1.0 - 0.15 * float(staff_level("physio"))):
			p["inj"] = randi_range(1, 3)
			add_news(tr("%s получил травму и пропустит %d нед.") % [p["nick"], p["inj"]])
			add_mail(tr("Медицинский штаб"), tr("Травма: %s") % p["nick"], tr("%s получил травму и пропустит %d нед. Он не сможет выходить на карту, пока не восстановится.") % [p["nick"], p["inj"]], "bad")
	match_done = true
	add_news("%s: %s %d:%d (%s)" % [tr("Победа") if won else tr("Поражение"), m["opp"], res["my"], res["opp"], tr("серия %d:%d") % [res["maps_my"], res["maps_opp"]] if m["bo"] > 1 else tr("1 карта")])
	changed.emit()

# ---------------------------------------------------------------- неделя

func finish_week() -> String:
	if game_over != "":
		return ""
	var pm: Dictionary = player_match()
	if not pm.is_empty() and not match_done:
		# автосимуляция, если матч не сыгран
		var r: Dictionary = _ai_series(team_name, pm["opp"], pm["bo"])
		report_match({"won": r["winner"] == 0, "my": r["score"][0], "opp": r["score"][1], "maps_my": 1 if r["winner"] == 0 else 0, "maps_opp": 0 if r["winner"] == 0 else 1})
	_sim_others()
	_rankoff_drift()
	_apply_training()
	var rep_txt: String = _finances()
	_weekly_event()
	_weekly_feed()
	for p in players:
		if int(p["inj"]) > 0:
			p["inj"] -= 1
	if randf() < 0.3 and market.size() > 0:
		market.remove_at(randi() % market.size())
		var np: Dictionary = gen_player(38.0 + float(tier) * 12.0 + randf_range(-4, 14))
		np["pot_est"] = int(np["pot"])
		market.append(np)
	var prev_week: int = week
	match_done = false
	week += 1
	if prev_week == 7:
		_make_playoffs()
	elif prev_week == 8:
		_make_final()
	elif prev_week == 9:
		_end_season()
	elif prev_week == LAST_WEEK:
		_start_next_season()
	_check_fired()
	var st = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings")
	if st == null or st.autosave:
		save()
	changed.emit()
	return rep_txt

func _sim_others() -> void:
	if week <= 7:
		for pair in schedule[week - 1]:
			if not pair.has(team_name):
				_record_league(pair[0], pair[1], _ai_series(pair[0], pair[1], 1))
	elif week == 8:
		for i in playoff["semis"].size():
			var pair2: Array = playoff["semis"][i]
			if not pair2.has(team_name):
				var r: Dictionary = _ai_series(pair2[0], pair2[1], 3)
				playoff["sf"][str(i)] = pair2[0] if r["winner"] == 0 else pair2[1]
	elif week == 9:
		var f: Array = playoff["final"]
		if f.size() == 2 and not f.has(team_name) and playoff["champion"] == "":
			var r2: Dictionary = _ai_series(f[0], f[1], 3)
			playoff["champion"] = f[0] if r2["winner"] == 0 else f[1]

func _make_playoffs() -> void:
	var rl: Array = rank_list()
	if rl.slice(0, mini(4, rl.size())).has(team_name):
		add_mail(tr("Оргкомитет лиги"), tr("Приглашение в плей-офф"), tr("Поздравляем! %s проходит в плей-офф лиги «%s».") % [team_name, tr(TIERS[tier])], "invite")
	playoff["sf"] = {}
	if rl.size() < 4:
		# мало команд — сразу финал двух лучших на 9-й неделе
		playoff["semis"] = []
		if rl.size() >= 2:
			playoff["sf"] = {"0": rl[0], "1": rl[1]}
		return
	playoff["semis"] = [[rl[0], rl[3]], [rl[1], rl[2]]]
	if rl.slice(0, 4).has(team_name):
		add_news(tr("Команда вышла в плей-off! Полуфинал против %s.") % player_match()["opp"])
	else:
		add_news(tr("Плей-офф пройдёт без вас: вы заняли %d-е место.") % my_rank())

func _make_final() -> void:
	if not playoff["sf"].has("0") or not playoff["sf"].has("1"):
		playoff["final"] = []
		return
	playoff["final"] = [playoff["sf"]["0"], playoff["sf"]["1"]]
	if playoff["final"].has(team_name):
		add_news(tr("Вы в финале! Соперник — %s.") % player_match()["opp"])

# ---------------------------------------------------------------- тренировки

const TRAIN_GROUPS := {
	"coach": ["skill", "awp", "rifle", "pistol", "nades", "creativity", "clutch", "tactics"],
	"psych": ["teamwork", "morale", "conflict", "productivity", "stress", "loyalty"],
	"physio": ["reaction", "perception", "immunity", "strength", "stamina"],
}
const TRAIN_MAX := 3

func weakest_n(p: Dictionary, keys: Array, n: int) -> Array:
	ensure_attrs(p)
	var ks: Array = keys.filter(func(k): return not (k == "awp" and not ["Снайпер", "2-й снайпер"].has(p.get("role", ""))))
	ks.sort_custom(func(a2, b2): return float(p["attrs"][a2]) < float(p["attrs"][b2]))
	return ks.slice(0, n)

func weakest_attr(p: Dictionary) -> String:
	var w: Array = weakest_n(p, TRAIN_GROUPS["coach"], 1)
	return w[0] if not w.is_empty() else "skill"

func ptrain(p: Dictionary) -> Dictionary:
	var tr2 = p.get("train", {})
	if typeof(tr2) != TYPE_DICTIONARY:
		tr2 = {"coach": [str(tr2)] if str(tr2) != "" else [], "psych": [], "physio": []}
		p["train"] = tr2
	for g2 in TRAIN_GROUPS:
		if not tr2.has(g2):
			tr2[g2] = []
	p["train"] = tr2
	var tp = p.get("tprog", {})
	if typeof(tp) != TYPE_DICTIONARY:
		tp = {"coach": float(tp), "psych": 0.0, "physio": 0.0}
	for g2 in TRAIN_GROUPS:
		if not tp.has(g2):
			tp[g2] = 0.0
	p["tprog"] = tp
	return p["train"]

func toggle_train(p: Dictionary, grp: String, k: String) -> void:
	var lst: Array = ptrain(p)[grp]
	if lst.has(k):
		lst.erase(k)
	elif lst.size() < TRAIN_MAX:
		lst.append(k)
	changed.emit()

func auto_schedule(grp: String = "coach") -> void:
	for p in players:
		ptrain(p)[grp] = weakest_n(p, TRAIN_GROUPS[grp], TRAIN_MAX)
	changed.emit()

func group_active(grp: String) -> bool:
	if grp == "coach":
		return staff_level("coach") > 0 or staff_coach != ""
	return staff_level(grp) > 0

## Скорость тренировки (% прогресса за неделю) для направления.
func train_speed(p: Dictionary, grp: String = "coach") -> float:
	var o: int = ovr(p)
	var g: float = clampf(float(int(p["pot"]) - o) / 15.0, 0.25, 1.3)
	var age_k: float = 1.3 if int(p["age"]) <= 20 else (1.0 if int(p["age"]) < 25 else 0.6)
	var lvl: float = float(staff_level(grp))
	if grp == "coach" and staff_coach != "":
		lvl = maxf(lvl, 4.0)
	var k: float = 0.6 + 0.18 * lvl + 0.03 * float(coach_skill["tactics"] if grp == "coach" else coach_skill["motivation"])
	return 34.0 * g * age_k * k

func _apply_training() -> void:
	var motiv: int = int(coach_skill["motivation"])
	for p in players:
		ensure_attrs(p)
		var trn: Dictionary = ptrain(p)
		for grp in TRAIN_GROUPS:
			if not group_active(grp) or trn[grp].is_empty() or int(p["inj"]) > 0:
				continue
			p["tprog"][grp] = float(p["tprog"].get(grp, 0.0)) + train_speed(p, grp) * randf_range(0.8, 1.2)
			if float(p["tprog"][grp]) >= 100.0:
				p["tprog"][grp] = float(p["tprog"][grp]) - 100.0
				for k in trn[grp]:
					p["attrs"][k] = snappedf(minf(20.0, float(p["attrs"][k]) + randf_range(0.3, 0.6)), 0.01)
				derive(p)
		p["form"] = clampi(int(p["form"]) + 3 + motiv + staff_level("physio"), 20, 100)
		p["morale"] = clampi(int(p.get("morale", 80)) + 2 + staff_level("psych") + motiv / 2, 10, 100)
		p["health"] = clampi(int(p.get("health", 90)) + 2 + staff_level("physio") - (10 if int(p["inj"]) > 0 else 0), 10, 100)
		var ah: Array = p.get("ahist", [])
		ah.append({"w": week, "s": season, "a": p["attrs"].duplicate()})
		while ah.size() > 26:
			ah.pop_front()
		p["ahist"] = ah
	if train_map != "":
		map_skill[train_map] = mini(95, int(map_skill[train_map]) + randi_range(2, 4) + staff_level("analyst") / 2)

## Психолог: сессия для игрока (+мораль), раз в неделю на игрока.
func psych_session(p: Dictionary) -> String:
	if staff_level("psych") <= 0:
		return tr("Нужен психолог в штате.")
	if int(p.get("psy_w", -1)) == season * 100 + week:
		return tr("Сессия с этим игроком уже была на этой неделе.")
	p["psy_w"] = season * 100 + week
	p["morale"] = clampi(int(p.get("morale", 80)) + 6 + staff_level("psych") * 3, 10, 100)
	changed.emit()
	return ""

## Физиотерапевт: восстановление формы, ускоряет выход из травмы.
func physio_session(p: Dictionary) -> String:
	if staff_level("physio") <= 0:
		return tr("Нужен физиотерапевт в штате.")
	if int(p.get("phy_w", -1)) == season * 100 + week:
		return tr("Процедуры с этим игроком уже были на этой неделе.")
	p["phy_w"] = season * 100 + week
	p["form"] = clampi(int(p["form"]) + 6 + staff_level("physio") * 3, 20, 100)
	if int(p["inj"]) > 0 and randf() < 0.25 * staff_level("physio"):
		p["inj"] = int(p["inj"]) - 1
	changed.emit()
	return ""

func offer_contract(p: Dictionary, years: int, salary: int) -> String:
	var want: int = int(300 + (ovr(p) - 30) * 32)
	var mo: int = int(p.get("morale", 80))
	if salary < int(want * (0.95 if mo >= 70 else 1.1)):
		p["morale"] = clampi(mo - 5, 10, 100)
		return tr("%s отклонил предложение: хочет не меньше $%d в неделю.") % [p["nick"], int(want * (0.95 if mo >= 70 else 1.1))]
	p["salary"] = salary
	p["contract"] = {"type": "club", "end": season + years, "signed": game_date_str()}
	p["morale"] = clampi(mo + 8, 10, 100)
	add_mail(tr("Отдел кадров"), tr("Новый контракт: %s") % p["nick"], tr("%s подписал новый контракт до конца сезона %d. Зарплата: $%d в неделю.") % [p["nick"], season + years, salary], "good")
	changed.emit()
	return ""

func game_date_str() -> String:
	var start := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 1, "day": 1, "hour": 12, "minute": 0, "second": 0})
	var d := Time.get_datetime_dict_from_unix_time(start + ((season - 1) * 52 + (week - 1)) * 7 * 86400)
	return "%02d.%02d.%d" % [d["day"], d["month"], d["year"]]

## Статистика игроков за матч: если не передана, генерируется по рейтингу.
func _match_lines(res: Dictionary, opp: String) -> void:
	var stats: Array = res.get("stats", [])
	var rounds: int = maxi(1, int(res.get("my", 13)) + int(res.get("opp", 10)))
	if stats.is_empty():
		for p in lineup():
			var kk: int = int(rounds * randf_range(0.45, 0.95) * float(ovr(p)) / 75.0)
			stats.append({"nick": p["nick"], "k": kk, "d": int(rounds * randf_range(0.5, 0.8))})
	for s in stats:
		for p in players:
			if p["nick"] != s["nick"]:
				continue
			var k: int = int(s["k"])
			var d: int = int(s["d"])
			var a: int = int(k * randf_range(0.2, 0.5))
			var line := {"opp": opp, "score": "%d:%d" % [int(res.get("my", 0)), int(res.get("opp", 0))], "won": bool(res["won"]),
				"k": k, "d": d, "a": a, "adr": snappedf((k * 95.0 + a * 30.0) / rounds * randf_range(0.9, 1.1), 0.1),
				"hs": randi_range(32, 62), "kast": randi_range(58, 84), "clutch": randi_range(0, 2),
				"ir": snappedf(clampf(0.55 + (float(k) - d) / rounds * 1.6 + randf_range(-0.08, 0.08), 0.3, 2.2), 0.01), "date": game_date_str(),
				"tour": tr(TIERS[tier]), "season": season}
			var mh: Array = p.get("mh", [])
			mh.push_front(line)
			while mh.size() > 30:
				mh.pop_back()
			p["mh"] = mh

func set_captain(p: Dictionary) -> void:
	for q in players:
		q["captain"] = false
	p["captain"] = true
	changed.emit()

func captain() -> Dictionary:
	for q in players:
		if bool(q.get("captain", false)):
			return q
	return {}

func _finances() -> String:
	var income: int = weekly_income()
	var salaries: int = player_salaries()
	var staff: int = upkeep() + staff_salaries()
	var net: int = income - salaries - staff
	money += net
	rep = minf(100.0, rep + 0.08 * staff_level("event") + 0.04 * staff_level("pr"))
	money_hist.append({"s": season, "w": week, "money": money, "net": net})
	while money_hist.size() > 30:
		money_hist.pop_front()
	return tr("Спонсоры +$%d, зарплаты -$%d, штаб -$%d (итого %s$%d)") % [income, salaries, staff, "+" if net >= 0 else "-", abs(net)]

func _weekly_event() -> void:
	if randf() > 0.12 or players.is_empty():
		return
	var p: Dictionary = players[randi() % players.size()]
	match randi() % 5:
		0:
			bump(p, "tw", -0.4)
			p["form"] = maxi(20, int(p["form"]) - 8)
			add_news(tr("Конфликт в команде: %s поссорился с партнёрами (-сыгранность).") % p["nick"])
		1:
			var b: int = 3000 * (tier + 1)
			money += b
			add_news(tr("Новый спонсорский контракт: +$%d.") % b)
		2:
			bump(p, "aim", 0.4)
			add_news(tr("%s провёл отличную серию на стриме и поверил в себя (+аим).") % p["nick"])
		3:
			p["form"] = maxi(20, int(p["form"]) - 15)
			add_news(tr("%s выгорел после напряжённых тренировок (-форма).") % p["nick"])
		4:
			rep = minf(100.0, rep + 2.0)
			add_news(tr("Видео с хайлайтами команды стало вирусным: +2 репутации."))

func _check_fired() -> void:
	if not can_be_fired:
		return
	if money < -40000:
		game_over = tr("Команда обанкротилась. Совет директоров вас уволил.")
		add_news(game_over)

# ---------------------------------------------------------------- конец сезона

func _end_season() -> void:
	var pos: int = my_rank()
	var prizes: Array = [12000, 8000, 5000, 3000, 1500, 500, 0, 0]
	var prize: int = int(prizes[clampi(pos - 1, 0, prizes.size() - 1)]) * (tier + 1)
	money += prize
	var champ: bool = playoff["champion"] == team_name
	var txt: String = tr("Сезон %d (%s): %d-е место") % [season, tr(TIERS[tier]), pos]
	if champ:
		var cp: int = 15000 * (tier + 1)
		money += cp
		rep = minf(100.0, rep + 12.0)
		titles += 1
		txt += tr(", ЧЕМПИОН (+$%d)") % cp
		coach_pts += 3
		if tier == 2 and not legend:
			legend = true
			add_news(tr("Вы выиграли Мировую серию! Вы вошли в историю Standoff 2 как легендарный тренер!"))
	elif playoff["final"].has(team_name):
		txt += tr(", финалист")
		rep = minf(100.0, rep + 4.0)
	history.push_front(txt + tr(" (приз за лигу +$%d)") % prize)
	add_mail(tr("Оргкомитет лиги"), tr("Итоги турнира: %s") % tr(TIERS[tier]), tr("Чемпион: %s.\nВаше место: %d.") % [str(playoff["champion"]) if str(playoff["champion"]) != "" else rank_list()[0], pos], "result")
	add_mail(tr("Совет директоров"), tr("Итоги сезона %d") % season, txt + tr(" (приз за лигу +$%d)") % prize, "good" if pos <= [4, 6, 8][tier] else "bad")
	refresh_staff_market()
	add_news(txt)
	# цели совета
	var goal: int = [4, 6, 8][tier]
	if pos > goal:
		bad_seasons += 1
		add_news(tr("Совет директоров недоволен результатом (цель: топ-%d).") % goal)
		rep = maxf(0.0, rep - 4.0)
		if bad_seasons >= 2 and can_be_fired:
			game_over = tr("Два неудачных сезона подряд. Совет директоров вас уволил.")
	else:
		bad_seasons = 0
	# возрастное развитие
	for p in players:
		p["age"] += 1
		var o: int = ovr(p)
		if int(p["age"]) <= 24 and o < int(p["pot"]):
			bump(p, "all", randf_range(0.2, 0.8))
		elif int(p["age"]) >= 29:
			bump(p, "all", -randf_range(0.0, 0.6))
		p["salary"] = int(300 + (ovr(p) - 30) * 32)
		p["form"] = 80
	# переход между дивизионами
	if pos <= 2 and tier < 2 and league_teams.size() >= 6:
		tier += 1
		add_news(tr("Повышение! Следующий сезон: %s.") % tr(TIERS[tier]))
	elif pos >= 7 and tier > 0 and league_teams.size() >= 8:
		tier -= 1
		rep = maxf(0.0, rep - 5.0)
		add_news(tr("Вылет в дивизион ниже: %s.") % tr(TIERS[tier]))
	last_report = txt

func _start_next_season() -> void:
	season += 1
	_start_league()
	add_mail(tr("Оргкомитет лиги"), tr("Приглашение: %s, сезон %d") % [tr(TIERS[tier]), season], tr("Ваша команда приглашена в турнир «%s». Регулярный сезон: 7 туров, затем плей-офф. Удачи!") % tr(TIERS[tier]), "invite")
	for n in strengths:
		if not rankoff.has(n):
			rankoff[n] = _base_rank(n)
	_refresh_market(12)
	add_news(tr("Начался сезон %d — %s.") % [season, tr(TIERS[tier])])

# ---------------------------------------------------------------- действия тренера

func sign_player(idx: int) -> String:
	if idx < 0 or idx >= market.size():
		return tr("Ошибка")
	if players.size() >= MAX_ROSTER:
		return tr("Состав заполнен (максимум %d).") % MAX_ROSTER
	var p: Dictionary = market[idx]
	var f: int = fee(p)
	if money < f:
		return tr("Не хватает денег.")
	money -= f
	p.erase("pot_est")
	players.append(p)
	market.remove_at(idx)
	add_news(tr("Подписан %s (%s, общий %d) за $%d.") % [p["nick"], tr(p["role"]), ovr(p), f])
	changed.emit()
	return ""

func release_player(idx: int) -> void:
	if idx < 0 or idx >= players.size():
		return
	var p: Dictionary = players[idx]
	var sev: int = int(p["salary"]) * 4
	money -= sev
	add_news(tr("%s отчислен (выплата $%d).") % [p["nick"], sev])
	players.remove_at(idx)
	changed.emit()

func sell_player(idx: int) -> void:
	if idx < 0 or idx >= players.size():
		return
	var p: Dictionary = players[idx]
	var v: int = int(fee(p) * 0.6)
	money += v
	add_news(tr("%s продан за $%d.") % [p["nick"], v])
	players.remove_at(idx)
	changed.emit()

func move_player(idx: int, dir: int) -> void:
	var j: int = idx + dir
	if idx < 0 or j < 0 or idx >= players.size() or j >= players.size():
		return
	var t: Dictionary = players[idx]
	players[idx] = players[j]
	players[j] = t
	changed.emit()

func upgrade_coach(skill: String) -> void:
	if coach_pts <= 0 or int(coach_skill[skill]) >= 10:
		return
	coach_pts -= 1
	coach_skill[skill] += 1
	changed.emit()

# ---------------------------------------------------------------- сохранения

func to_dict() -> Dictionary:
	return {
		"active": active, "game_over": game_over, "legend": legend, "coach_name": coach_name, "team_name": team_name,
		"season": season, "week": week, "tier": tier, "money": money, "rep": rep, "coach_pts": coach_pts,
		"coach_skill": coach_skill, "players": players, "market": market, "map_skill": map_skill, "style": style,
		"train_focus": train_focus, "train_map": train_map, "league_teams": league_teams, "strengths": strengths,
		"standings": standings, "schedule": schedule, "playoff": playoff, "match_done": match_done, "news": news,
		"history": history, "titles": titles, "bad_seasons": bad_seasons, "next_id": next_id,
		"coach_age": coach_age, "coach_nick": coach_nick, "coach_gender": coach_gender, "coach_country_code": coach_country_code,
		"coach_birth": coach_birth, "coach_attrs": coach_attrs, "coach_country": coach_country, "coach_bg": coach_bg, "avatar": avatar,
		"photo_path": photo_path, "team_tag": team_tag, "team_color": team_color,
		"team_logo": team_logo, "team_desc": team_desc, "staff_count": staff_count, "staff_list": staff_list, "staff_market": staff_market, "mail": mail, "talks": talks, "money_hist": money_hist, "team_stats": team_stats, "team_country": team_country, "rankoff": rankoff, "can_be_fired": can_be_fired, "country_only": country_only, "staff_coach": staff_coach, "staff_photo": staff_photo,
	}

func from_dict(d: Dictionary) -> void:
	active = bool(d.get("active", true))
	game_over = str(d.get("game_over", ""))
	legend = bool(d.get("legend", false))
	coach_name = str(d["coach_name"])
	team_name = str(d["team_name"])
	season = int(d["season"])
	week = int(d["week"])
	tier = int(d["tier"])
	money = int(d["money"])
	rep = float(d["rep"])
	coach_pts = int(d["coach_pts"])
	coach_skill = {}
	for k in d["coach_skill"]:
		coach_skill[k] = int(d["coach_skill"][k])
	players = _fix_players(d["players"])
	market = _fix_players(d["market"])
	map_skill = {}
	for k in d["map_skill"]:
		map_skill[k] = int(d["map_skill"][k])
	style = str(d["style"])
	train_focus = str(d["train_focus"])
	train_map = str(d["train_map"])
	league_teams = d["league_teams"]
	strengths = d["strengths"]
	standings = {}
	for k in d["standings"]:
		var s: Dictionary = d["standings"][k]
		standings[k] = {"w": int(s["w"]), "l": int(s["l"]), "rd": int(s["rd"])}
	schedule = d["schedule"]
	playoff = d["playoff"]
	match_done = bool(d["match_done"])
	news = d["news"]
	history = d["history"]
	titles = int(d["titles"])
	bad_seasons = int(d["bad_seasons"])
	next_id = int(d["next_id"])
	coach_age = int(d.get("coach_age", 30))
	coach_nick = str(d.get("coach_nick", ""))
	coach_gender = str(d.get("coach_gender", "m"))
	coach_country_code = str(d.get("coach_country_code", "ru"))
	coach_birth = d.get("coach_birth", [1, 1, 1990])
	coach_attrs = {}
	var ca: Dictionary = d.get("coach_attrs", {})
	for k in ca:
		coach_attrs[k] = int(ca[k])
	coach_country = str(d.get("coach_country", tr("Россия")))
	coach_bg = str(d.get("coach_bg", "rookie"))
	avatar = {}
	var av: Dictionary = d.get("avatar", {})
	for k in av:
		avatar[k] = int(av[k])
	photo_path = str(d.get("photo_path", ""))
	team_tag = str(d.get("team_tag", team_name.substr(0, 3).to_upper()))
	team_color = str(d.get("team_color", "ffb23e"))
	team_logo = str(d.get("team_logo", ""))
	team_desc = str(d.get("team_desc", ""))
	staff_count = int(d.get("staff_count", 0))
	staff_list = _fix_staff(d.get("staff_list", []))
	staff_market = _fix_staff(d.get("staff_market", []))
	if staff_market.is_empty():
		refresh_staff_market()
	mail = d.get("mail", [])
	talks = d.get("talks", [])
	money_hist = d.get("money_hist", [])
	team_stats = d.get("team_stats", {"w": 0, "l": 0, "mw": 0, "ml": 0, "rw": 0, "rl": 0})
	team_country = str(d.get("team_country", "ru"))
	rankoff = {}
	var rk: Dictionary = d.get("rankoff", {})
	for k in rk:
		rankoff[k] = float(rk[k])
	can_be_fired = bool(d.get("can_be_fired", true))
	country_only = bool(d.get("country_only", false))
	staff_coach = str(d.get("staff_coach", ""))
	staff_photo = str(d.get("staff_photo", ""))
	changed.emit()

func _fix_staff(arr: Array) -> Array:
	var res: Array = []
	for s in arr:
		var q: Dictionary = s.duplicate()
		for k in ["lvl", "salary", "fee"]:
			q[k] = int(q.get(k, 0))
		var at := {}
		var src: Dictionary = q.get("attrs", {})
		for k in src:
			at[k] = float(src[k])
		if at.is_empty():
			at = make_staff_attrs(str(q.get("role", "coach")), float(q.get("lvl", 2)))
		q["attrs"] = at
		if not STAFF_ROLES.has(str(q.get("role", ""))):
			q["role"] = "coach"
		res.append(q)
	return res

func _fix_players(arr: Array) -> Array:
	var res: Array = []
	for p in arr:
		var q: Dictionary = p.duplicate()
		for k in ["id", "aim", "iq", "tw", "form", "age", "pot", "inj", "salary", "matches", "pot_est"]:
			if q.has(k):
				q[k] = int(q[k])
		var lk: Dictionary = {}
		var src: Dictionary = q.get("look", {})
		for k in src:
			lk[k] = int(src[k])
		q["look"] = lk
		q["photo"] = str(q.get("photo", ""))
		var at := {}
		var srcat: Dictionary = q.get("attrs", {})
		for k in srcat:
			at[k] = float(srcat[k])
		q["attrs"] = at
		if ROLE_MIGRATE.has(str(q.get("role", ""))):
			if q["role"] == "Капитан":
				q["captain"] = true
			q["role"] = ROLE_MIGRATE[q["role"]]
		ensure_attrs(q)
		init_player_meta(q)
		res.append(q)
	return res

# ---------------------------------------------------------------- слоты сохранений

const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 5
var slot: int = 1

func slot_path(i: int) -> String:
	return SAVE_DIR + "slot_%d.json" % i

func photo_path_for(i: int) -> String:
	return "user://coach_photo_%d.png" % i

func _migrate_old_save() -> void:
	if FileAccess.file_exists(SAVE_PATH) and not FileAccess.file_exists(slot_path(1)):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(slot_path(1)))

func save() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var d: Dictionary = to_dict()
	d["saved_at"] = Time.get_datetime_string_from_system(false, true)
	d["saved_unix"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func read_slot(i: int):
	if not FileAccess.file_exists(slot_path(i)):
		return null
	var f := FileAccess.open(slot_path(i), FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else null

## Список сохранений: [{slot, data}], новые сверху.
func list_saves() -> Array:
	_migrate_old_save()
	var res: Array = []
	for i in range(1, MAX_SLOTS + 1):
		var d = read_slot(i)
		if d != null:
			res.append({"slot": i, "data": d})
	res.sort_custom(func(a, b): return float(a["data"].get("saved_unix", 0)) > float(b["data"].get("saved_unix", 0)))
	return res

func has_save() -> bool:
	return not list_saves().is_empty()

func latest_slot() -> int:
	var l: Array = list_saves()
	return int(l[0]["slot"]) if not l.is_empty() else -1

## Свободный слот для новой карьеры (или самый старый, если все заняты).
func free_slot() -> int:
	for i in range(1, MAX_SLOTS + 1):
		if not FileAccess.file_exists(slot_path(i)):
			return i
	var l: Array = list_saves()
	return int(l[l.size() - 1]["slot"])

func delete_slot(i: int) -> void:
	for pth in [slot_path(i), photo_path_for(i)]:
		if FileAccess.file_exists(pth):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(pth))

func load_game(i: int = -1) -> bool:
	if i < 0:
		i = latest_slot()
	if i < 0:
		return false
	var data = read_slot(i)
	if data == null:
		return false
	slot = i
	from_dict(data)
	return true
