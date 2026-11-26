"""Минимальный асинхронный клиент FACEIT Data API v4."""
from __future__ import annotations

import aiohttp

BASE_URL = "https://open.faceit.com/data/v4"
GAME = "cs2"

# Пороги ELO для уровней CS2 (нижняя граница уровня)
LEVELS = [
    (1, 100), (2, 501), (3, 751), (4, 901), (5, 1051),
    (6, 1201), (7, 1351), (8, 1531), (9, 1751), (10, 2001),
]


class FaceitError(Exception):
    pass


class PlayerNotFound(FaceitError):
    pass


def level_for_elo(elo: int) -> int:
    lvl = 1
    for level, low in LEVELS:
        if elo >= low:
            lvl = level
    return lvl


def elo_to_next_level(elo: int) -> int | None:
    """Сколько ELO не хватает до следующего уровня (None для 10 lvl)."""
    for _, low in LEVELS:
        if low > elo:
            return low - elo
    return None


class FaceitClient:
    def __init__(self, api_key: str):
        self._headers = {"Authorization": f"Bearer {api_key}"}
        self._session: aiohttp.ClientSession | None = None

    async def _get(self, path: str, **params) -> dict:
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                headers=self._headers, timeout=aiohttp.ClientTimeout(total=15)
            )
        async with self._session.get(BASE_URL + path, params=params) as resp:
            if resp.status == 404:
                raise PlayerNotFound(path)
            if resp.status == 401:
                raise FaceitError("Неверный FACEIT_API_KEY")
            if resp.status == 429:
                raise FaceitError("FACEIT ограничил запросы, попробуй через минуту")
            if resp.status >= 400:
                raise FaceitError(f"FACEIT API ответил {resp.status}")
            return await resp.json()

    async def close(self) -> None:
        if self._session and not self._session.closed:
            await self._session.close()

    async def player_by_nickname(self, nickname: str) -> dict:
        data = await self._get("/players", nickname=nickname)
        if GAME not in data.get("games", {}):
            raise PlayerNotFound(nickname)
        return data

    async def player_by_id(self, player_id: str) -> dict:
        return await self._get(f"/players/{player_id}")

    async def lifetime_stats(self, player_id: str) -> dict:
        data = await self._get(f"/players/{player_id}/stats/{GAME}")
        return data.get("lifetime", {})

    async def recent_matches(self, player_id: str, limit: int = 10) -> list[dict]:
        """Статистика игрока по последним матчам (K/D, карта, результат...)."""
        data = await self._get(
            f"/players/{player_id}/games/{GAME}/stats", limit=limit, offset=0
        )
        return [item.get("stats", {}) for item in data.get("items", [])]


def cs2_info(player: dict) -> tuple[int, int]:
    """(elo, level) игрока из ответа /players."""
    game = player.get("games", {}).get(GAME, {})
    elo = int(game.get("faceit_elo") or 0)
    level = int(game.get("skill_level") or level_for_elo(elo))
    return elo, level
