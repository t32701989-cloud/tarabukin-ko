"""SQLite-хранилище: привязанный ник и отслеживание ELO."""
from __future__ import annotations

import sqlite3
from pathlib import Path


class Storage:
    def __init__(self, path: str | Path = "bot.db"):
        self.db = sqlite3.connect(path)
        self.db.execute(
            """CREATE TABLE IF NOT EXISTS users (
                chat_id   INTEGER PRIMARY KEY,
                player_id TEXT NOT NULL,
                nickname  TEXT NOT NULL,
                track     INTEGER NOT NULL DEFAULT 0,
                last_elo  INTEGER
            )"""
        )
        self.db.commit()

    def link(self, chat_id: int, player_id: str, nickname: str, elo: int) -> None:
        self.db.execute(
            """INSERT INTO users (chat_id, player_id, nickname, last_elo)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(chat_id) DO UPDATE SET
                 player_id = excluded.player_id,
                 nickname  = excluded.nickname,
                 last_elo  = excluded.last_elo""",
            (chat_id, player_id, nickname, elo),
        )
        self.db.commit()

    def get(self, chat_id: int) -> dict | None:
        row = self.db.execute(
            "SELECT player_id, nickname, track, last_elo FROM users WHERE chat_id = ?",
            (chat_id,),
        ).fetchone()
        if not row:
            return None
        return {"player_id": row[0], "nickname": row[1], "track": bool(row[2]), "last_elo": row[3]}

    def unlink(self, chat_id: int) -> None:
        self.db.execute("DELETE FROM users WHERE chat_id = ?", (chat_id,))
        self.db.commit()

    def set_track(self, chat_id: int, on: bool) -> None:
        self.db.execute("UPDATE users SET track = ? WHERE chat_id = ?", (int(on), chat_id))
        self.db.commit()

    def tracked(self) -> list[tuple[int, str, str, int | None]]:
        return self.db.execute(
            "SELECT chat_id, player_id, nickname, last_elo FROM users WHERE track = 1"
        ).fetchall()

    def update_elo(self, chat_id: int, elo: int, nickname: str) -> None:
        self.db.execute(
            "UPDATE users SET last_elo = ?, nickname = ? WHERE chat_id = ?",
            (elo, nickname, chat_id),
        )
        self.db.commit()
