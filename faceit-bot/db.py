"""SQLite-хранилище: игроки, матчи, участники матчей."""
from __future__ import annotations

import sqlite3
import time

START_ELO = 1000

SCHEMA = """
CREATE TABLE IF NOT EXISTS players (
    tg_id       INTEGER PRIMARY KEY,
    tg_username TEXT,
    tg_name     TEXT,
    nick        TEXT NOT NULL,
    game_id     TEXT,
    elo         INTEGER NOT NULL DEFAULT 1000,
    wins        INTEGER NOT NULL DEFAULT 0,
    losses      INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS matches (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    mode        TEXT NOT NULL,            -- '5x5' | '2x2'
    map         TEXT NOT NULL,
    status      TEXT NOT NULL,            -- open | live | finished | cancelled
    creator_id  INTEGER NOT NULL,
    room        TEXT,                     -- код/пароль комнаты в игре
    winner      INTEGER,                  -- 1 | 2
    score       TEXT,
    created_at  INTEGER NOT NULL,
    started_at  INTEGER,
    finished_at INTEGER
);
CREATE TABLE IF NOT EXISTS match_players (
    match_id   INTEGER NOT NULL,
    tg_id      INTEGER NOT NULL,
    team       INTEGER,
    elo_before INTEGER,
    elo_delta  INTEGER,
    joined_at  INTEGER NOT NULL,
    PRIMARY KEY (match_id, tg_id)
);
"""


class DB:
    def __init__(self, path: str = "bot.db"):
        self.c = sqlite3.connect(path, check_same_thread=False)
        self.c.row_factory = sqlite3.Row
        self.c.executescript(SCHEMA)
        self.c.commit()

    # ---------- players ----------

    def player(self, tg_id: int) -> dict | None:
        r = self.c.execute("SELECT * FROM players WHERE tg_id = ?", (tg_id,)).fetchone()
        return dict(r) if r else None

    def upsert_player(self, tg_id: int, nick: str, game_id: str, tg_username: str | None, tg_name: str) -> None:
        self.c.execute(
            """INSERT INTO players (tg_id, tg_username, tg_name, nick, game_id, elo, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(tg_id) DO UPDATE SET
                 nick = excluded.nick, game_id = excluded.game_id,
                 tg_username = excluded.tg_username, tg_name = excluded.tg_name""",
            (tg_id, tg_username, tg_name, nick, game_id, START_ELO, int(time.time())),
        )
        self.c.commit()

    def nick_taken(self, nick: str, except_tg_id: int) -> bool:
        r = self.c.execute(
            "SELECT 1 FROM players WHERE lower(nick) = lower(?) AND tg_id != ?", (nick, except_tg_id)
        ).fetchone()
        return r is not None

    def leaderboard(self, limit: int = 100) -> list[dict]:
        rows = self.c.execute(
            "SELECT tg_id, nick, elo, wins, losses FROM players ORDER BY elo DESC, wins DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]

    # ---------- matches ----------

    def match(self, match_id: int) -> dict | None:
        r = self.c.execute("SELECT * FROM matches WHERE id = ?", (match_id,)).fetchone()
        if not r:
            return None
        m = dict(r)
        m["players"] = [
            dict(p) for p in self.c.execute(
                """SELECT mp.tg_id, mp.team, mp.elo_before, mp.elo_delta, p.nick, p.elo, p.game_id, p.tg_username
                   FROM match_players mp JOIN players p ON p.tg_id = mp.tg_id
                   WHERE mp.match_id = ? ORDER BY mp.joined_at""",
                (match_id,),
            ).fetchall()
        ]
        return m

    def active_matches(self) -> list[dict]:
        ids = self.c.execute(
            "SELECT id FROM matches WHERE status IN ('open', 'live') ORDER BY id DESC"
        ).fetchall()
        return [self.match(r["id"]) for r in ids]

    def active_match_of(self, tg_id: int) -> int | None:
        r = self.c.execute(
            """SELECT m.id FROM matches m JOIN match_players mp ON mp.match_id = m.id
               WHERE mp.tg_id = ? AND m.status IN ('open', 'live')""",
            (tg_id,),
        ).fetchone()
        return r["id"] if r else None

    def create_match(self, mode: str, map_name: str, creator_id: int) -> int:
        now = int(time.time())
        cur = self.c.execute(
            "INSERT INTO matches (mode, map, status, creator_id, created_at) VALUES (?, ?, 'open', ?, ?)",
            (mode, map_name, creator_id, now),
        )
        self.c.execute(
            "INSERT INTO match_players (match_id, tg_id, joined_at) VALUES (?, ?, ?)",
            (cur.lastrowid, creator_id, now),
        )
        self.c.commit()
        return cur.lastrowid

    def join(self, match_id: int, tg_id: int) -> None:
        self.c.execute(
            "INSERT OR IGNORE INTO match_players (match_id, tg_id, joined_at) VALUES (?, ?, ?)",
            (match_id, tg_id, time.time()),
        )
        self.c.commit()

    def leave(self, match_id: int, tg_id: int) -> None:
        self.c.execute("DELETE FROM match_players WHERE match_id = ? AND tg_id = ?", (match_id, tg_id))
        self.c.commit()

    def set_creator(self, match_id: int, tg_id: int) -> None:
        self.c.execute("UPDATE matches SET creator_id = ? WHERE id = ?", (tg_id, match_id))
        self.c.commit()

    def set_room(self, match_id: int, room: str) -> None:
        self.c.execute("UPDATE matches SET room = ? WHERE id = ?", (room, match_id))
        self.c.commit()

    def set_status(self, match_id: int, status: str) -> None:
        self.c.execute("UPDATE matches SET status = ? WHERE id = ?", (status, match_id))
        self.c.commit()

    def start_match(self, match_id: int, teams: dict[int, int]) -> None:
        for tg_id, team in teams.items():
            self.c.execute(
                """UPDATE match_players SET team = ?,
                     elo_before = (SELECT elo FROM players WHERE tg_id = ?)
                   WHERE match_id = ? AND tg_id = ?""",
                (team, tg_id, match_id, tg_id),
            )
        self.c.execute(
            "UPDATE matches SET status = 'live', started_at = ? WHERE id = ?", (int(time.time()), match_id)
        )
        self.c.commit()

    def finish_match(self, match_id: int, winner: int, score: str, deltas: dict[int, int]) -> None:
        for tg_id, delta in deltas.items():
            won = self._team(match_id, tg_id) == winner
            self.c.execute(
                "UPDATE match_players SET elo_delta = ? WHERE match_id = ? AND tg_id = ?",
                (delta, match_id, tg_id),
            )
            self.c.execute(
                f"""UPDATE players SET elo = MAX(100, elo + ?),
                      {'wins = wins + 1' if won else 'losses = losses + 1'}
                    WHERE tg_id = ?""",
                (delta, tg_id),
            )
        self.c.execute(
            "UPDATE matches SET status = 'finished', winner = ?, score = ?, finished_at = ? WHERE id = ?",
            (winner, score, int(time.time()), match_id),
        )
        self.c.commit()

    def _team(self, match_id: int, tg_id: int) -> int | None:
        r = self.c.execute(
            "SELECT team FROM match_players WHERE match_id = ? AND tg_id = ?", (match_id, tg_id)
        ).fetchone()
        return r["team"] if r else None

    def history(self, tg_id: int, limit: int = 20) -> list[dict]:
        rows = self.c.execute(
            """SELECT m.id, m.mode, m.map, m.score, m.winner, m.finished_at, mp.team, mp.elo_delta
               FROM match_players mp JOIN matches m ON m.id = mp.match_id
               WHERE mp.tg_id = ? AND m.status = 'finished'
               ORDER BY m.finished_at DESC LIMIT ?""",
            (tg_id, limit),
        ).fetchall()
        return [dict(r) for r in rows]

    def rank_of(self, tg_id: int) -> int | None:
        p = self.player(tg_id)
        if not p:
            return None
        r = self.c.execute("SELECT COUNT(*) AS n FROM players WHERE elo > ?", (p["elo"],)).fetchone()
        return r["n"] + 1
