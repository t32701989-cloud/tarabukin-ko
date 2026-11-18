extends RefCounted
## Посчётный симулятор карты Standoff 2 (режим закладки бомбы, MR12 + овертайм).
## Команда 0 — команда игрока, команда 1 — соперник.

var names: Array = ["Вы", "Соперник"]
var nicks: Array = [[], []]            # ники игроков для статистики
var weights: Array = [[], []]          # веса киллов (аим)
var atk: Array = [50.0, 50.0]          # сила на атаке
var dfn: Array = [50.0, 50.0]          # сила в защите
var score: Array = [0, 0]
var side_atk: int = 0                  # какая команда сейчас атакует (T)
var rounds: int = 0
var bank: Array = [4000, 4000]
var loss_streak: Array = [0, 0]
var buff: Array = [0.0, 0.0]
var buff_rounds: Array = [0, 0]
var timeouts: Array = [2, 2]
var target: int = 13
var finished: bool = false
var winner: int = -1
var kills: Array = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
var deaths: Array = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

func _buy_mode(t: int) -> String:
	if rounds == 0 or rounds == 12:
		return "pistol"
	if bank[t] >= 14000:
		return "full"
	if bank[t] >= 7500:
		return "force"
	return "eco"

func call_timeout(t: int, bonus: float) -> bool:
	if timeouts[t] <= 0:
		return false
	timeouts[t] -= 1
	buff[t] = bonus
	buff_rounds[t] = 3
	return true

func _pick(t: int) -> int:
	var w: Array = weights[t]
	if w.is_empty():
		return rng.randi_range(0, 4)
	var total: float = 0.0
	for x in w:
		total += float(x)
	var r: float = rng.randf() * total
	for i in w.size():
		r -= float(w[i])
		if r <= 0.0:
			return i
	return w.size() - 1

func play_round() -> Dictionary:
	var out := {"winner": -1, "text": "", "buy": ["", ""], "round": rounds + 1, "side_atk": side_atk, "swap": false}
	if rounds == 12 or (rounds >= 24 and (rounds - 24) % 3 == 0):
		side_atk = 1 - side_atk
		out["side_atk"] = side_atk
		out["swap"] = true
		if rounds == 12:
			bank = [4000, 4000]
			loss_streak = [0, 0]
	if rounds >= 24 and (rounds - 24) % 6 == 0:
		bank = [16000, 16000]
	var pw := [0.0, 0.0]
	var buy := ["", ""]
	for t in 2:
		var p: float = atk[t] if side_atk == t else dfn[t]
		var mode: String = _buy_mode(t)
		buy[t] = mode
		if mode == "eco":
			p -= 14.0
		elif mode == "force":
			p -= 6.0
		if buff_rounds[t] > 0:
			p += buff[t]
		pw[t] = p
	out["buy"] = buy
	var prob: float = 1.0 / (1.0 + exp(-(pw[0] - pw[1]) / 11.0))
	var w: int = 0 if rng.randf() < prob else 1
	var l: int = 1 - w
	# бухгалтерия
	for t in 2:
		if buff_rounds[t] > 0:
			buff_rounds[t] -= 1
		match buy[t]:
			"full":
				bank[t] -= 14000
			"force":
				bank[t] = 0
	bank[w] = min(40000, bank[w] + 16250)
	loss_streak[w] = 0
	loss_streak[l] += 1
	bank[l] = min(40000, bank[l] + 9500 + 2500 * min(loss_streak[l] - 1, 4))
	score[w] += 1
	rounds += 1
	# текст раунда
	var site: String = "A" if rng.randf() < 0.5 else "B"
	var attacker_won: bool = (w == side_atk)
	var elimination: bool = false
	if attacker_won:
		if rng.randf() < 0.55:
			out["text"] = "%s закладывает бомбу на %s и удерживает позицию — бомба взорвана." % [names[w], site]
		else:
			out["text"] = "%s зачищает защиту и берёт раунд." % names[w]
			elimination = true
	else:
		var r: float = rng.randf()
		if r < 0.35:
			out["text"] = "%s обезвреживает бомбу на %s." % [names[w], site]
		elif r < 0.7:
			out["text"] = "%s останавливает атаку на %s." % [names[w], site]
			elimination = true
		else:
			out["text"] = "%s не даёт атаке закрепиться — время вышло." % names[w]
	# статистика
	var kw: int = 5 if elimination else rng.randi_range(2, 4)
	var kl: int = rng.randi_range(0, 3)
	for i in kw:
		kills[w][_pick(w)] += 1
		deaths[l][rng.randi_range(0, 4)] += 1
	for i in kl:
		kills[l][_pick(l)] += 1
		deaths[w][rng.randi_range(0, 4)] += 1
	# яркий момент
	if not nicks[w].is_empty() and rng.randf() < 0.07:
		var star: String = str(nicks[w][_pick(w)])
		var n: int = rng.randi_range(2, 4)
		out["text"] += " %s вытаскивает клатч 1v%d!" % [star, n]
	# овертайм / конец
	if score[w] >= target:
		finished = true
		winner = w
	elif score[0] == target - 1 and score[1] == target - 1:
		target += 3
	out["winner"] = w
	return out

func is_overtime() -> bool:
	return rounds >= 24

static func quick(strength_a: float, strength_b: float, rng_in: RandomNumberGenerator = null) -> Dictionary:
	var s = load("res://scripts/match_sim.gd").new()
	var r: RandomNumberGenerator = rng_in if rng_in != null else s.rng
	s.atk = [strength_a + r.randf_range(-2.5, 2.5), strength_b + r.randf_range(-2.5, 2.5)]
	s.dfn = [strength_a + r.randf_range(-2.5, 2.5), strength_b + r.randf_range(-2.5, 2.5)]
	s.side_atk = r.randi_range(0, 1)
	var guard: int = 0
	while not s.finished and guard < 200:
		s.play_round()
		guard += 1
	return {"winner": s.winner, "score": s.score.duplicate()}
