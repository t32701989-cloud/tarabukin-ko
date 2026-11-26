"""Уровни, расчёт ELO и балансировка команд."""
from __future__ import annotations

import random
from itertools import combinations

K_FACTOR = 50  # при равных командах победа даёт ~+25

# (уровень, нижняя граница ELO). Старт — 1000 ELO (3 уровень).
LEVELS = [
    (1, 0), (2, 800), (3, 950), (4, 1100), (5, 1250),
    (6, 1400), (7, 1550), (8, 1700), (9, 1850), (10, 2000),
]


def level(elo: int) -> int:
    lvl = 1
    for lv, low in LEVELS:
        if elo >= low:
            lvl = lv
    return lvl


def next_level_at(elo: int) -> int | None:
    for _, low in LEVELS:
        if low > elo:
            return low
    return None


def balance(players: list[dict]) -> dict[int, int]:
    """Делит игроков на две команды с минимальной разницей суммарного ELO.

    players: [{'tg_id':..., 'elo':...}, ...] (чётное количество).
    Возвращает {tg_id: 1|2}.
    """
    players = players[:]
    random.shuffle(players)  # при равенстве — разные составы
    n = len(players) // 2
    total = sum(p["elo"] for p in players)
    first, rest = players[0], players[1:]
    best, best_diff = None, None
    # фиксируем первого игрока в команде 1, чтобы не считать зеркальные варианты
    for combo in combinations(rest, n - 1):
        team1 = (first, *combo)
        diff = abs(total - 2 * sum(p["elo"] for p in team1))
        if best_diff is None or diff < best_diff:
            best, best_diff = team1, diff
    ids1 = {p["tg_id"] for p in best}
    return {p["tg_id"]: 1 if p["tg_id"] in ids1 else 2 for p in players}


def deltas(players: list[dict], winner: int) -> dict[int, int]:
    """Изменение ELO для каждого игрока по среднему ELO команд.

    players: [{'tg_id', 'team', 'elo_before'}].
    """
    def avg(team: int) -> float:
        elos = [p["elo_before"] for p in players if p["team"] == team]
        return sum(elos) / len(elos)

    a1, a2 = avg(1), avg(2)
    w_avg, l_avg = (a1, a2) if winner == 1 else (a2, a1)
    expected = 1 / (1 + 10 ** ((l_avg - w_avg) / 400))
    gain = max(5, min(45, round(K_FACTOR * (1 - expected))))
    return {p["tg_id"]: gain if p["team"] == winner else -gain for p in players}
