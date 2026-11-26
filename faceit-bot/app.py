"""Flask-приложение: API для Mini App, раздача Mini App и webhook бота.

Работает на любом WSGI-хостинге (PythonAnywhere и т.п.).
Локально/на VPS можно запустить `python run_polling.py`.
"""
from __future__ import annotations

import logging
import random
import re
from functools import wraps
from html import escape
from pathlib import Path

from flask import Flask, abort, g, jsonify, request, send_from_directory

import config
import elo
import tg
from db import DB

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("app")

WEBAPP_DIR = Path(__file__).parent / "webapp"
MODES = {"5x5": 10, "2x2": 4}
NICK_RE = re.compile(r"^[\w\-\.\[\]\|★☆ ]{2,20}$", re.UNICODE)

app = Flask(__name__)
db = DB(config.DB_PATH)


class ApiError(Exception):
    pass


@app.errorhandler(ApiError)
def api_error(e):
    return jsonify(error=str(e)), 400


# ---------- auth ----------

def auth(fn):
    @wraps(fn)
    def wrapper(*a, **kw):
        init_data = request.headers.get("X-Init-Data", "")
        if init_data:
            try:
                u = tg.check_init_data(init_data)
            except Exception:
                abort(401)
            g.user = {
                "id": u["id"],
                "username": u.get("username"),
                "name": " ".join(x for x in (u.get("first_name"), u.get("last_name")) if x),
            }
        elif config.DEV_MODE and request.headers.get("X-Dev-User"):
            uid = int(request.headers["X-Dev-User"])
            g.user = {"id": uid, "username": f"dev{uid}", "name": f"Dev {uid}"}
        else:
            abort(401)
        return fn(*a, **kw)
    return wrapper


def uid() -> int:
    return g.user["id"]


def body() -> dict:
    return request.get_json(silent=True) or {}


def is_admin(tg_id: int) -> bool:
    return tg_id in config.ADMIN_IDS


def require_player() -> dict:
    p = db.player(uid())
    if not p:
        raise ApiError("Сначала зарегистрируйся")
    return p


def get_match(match_id: int) -> dict:
    m = db.match(match_id)
    if not m:
        raise ApiError("Матч не найден")
    return m


def require_host(m: dict) -> None:
    if m["creator_id"] != uid() and not is_admin(uid()):
        raise ApiError("Это может сделать только хост лобби или админ")


def public_player(p: dict) -> dict:
    return {**p, "level": elo.level(p["elo"]), "next_level_at": elo.next_level_at(p["elo"])}


def public_match(m: dict) -> dict:
    for p in m["players"]:
        p["level"] = elo.level(p["elo"])
    m["size"] = MODES[m["mode"]]
    return m


# ---------- notifications ----------

def notify(tg_ids, text: str) -> None:
    for tg_id in tg_ids:
        tg.send(tg_id, text)


def notify_group(text: str) -> None:
    if config.NOTIFY_CHAT_ID:
        tg.send(config.NOTIFY_CHAT_ID, text, {"inline_keyboard": [[
            {"text": "🎮 Открыть", "url": f"https://t.me/{config.BOT_USERNAME}?start=play"}
        ]]} if config.BOT_USERNAME else None)


def teams_text(m: dict) -> str:
    lines = []
    for team in (1, 2):
        ps = [p for p in m["players"] if p["team"] == team]
        avg = round(sum(p["elo"] for p in ps) / len(ps)) if ps else 0
        lines.append(f"<b>Команда {team}</b> (ср. {avg} ELO)")
        lines += [f"  • {escape(p['nick'])} — {p['elo']}" for p in ps]
    return "\n".join(lines)


# ---------- Mini App ----------

@app.get("/")
def index():
    resp = send_from_directory(WEBAPP_DIR, "index.html")
    resp.headers["Cache-Control"] = "no-cache"
    return resp


@app.get("/api/config")
@auth
def api_config():
    return jsonify(maps=config.MAPS, modes=MODES, levels=elo.LEVELS)


@app.get("/api/me")
@auth
def api_me():
    p = db.player(uid())
    return jsonify(
        user=g.user,
        player=public_player(p) if p else None,
        rank=db.rank_of(uid()),
        active_match=db.active_match_of(uid()),
        is_admin=is_admin(uid()),
    )


@app.post("/api/register")
@auth
def api_register():
    b = body()
    nick = str(b.get("nick", "")).strip()
    game_id = re.sub(r"\D", "", str(b.get("game_id", "")))[:15]
    if not NICK_RE.match(nick):
        raise ApiError("Ник: 2–20 символов")
    if db.nick_taken(nick, uid()):
        raise ApiError("Этот ник уже занят")
    db.upsert_player(uid(), nick, game_id, g.user["username"], g.user["name"])
    return jsonify(ok=True)


@app.get("/api/lobbies")
@auth
def api_lobbies():
    return jsonify([public_match(m) for m in db.active_matches()])


@app.get("/api/matches/<int:mid>")
@auth
def api_match(mid: int):
    return jsonify(public_match(get_match(mid)))


@app.post("/api/lobbies")
@auth
def api_create():
    p = require_player()
    if db.active_match_of(p["tg_id"]):
        raise ApiError("Ты уже в другом лобби")
    b = body()
    mode = b.get("mode")
    if mode not in MODES:
        raise ApiError("Неверный режим")
    map_name = b.get("map") or "random"
    if map_name == "random":
        map_name = random.choice(config.MAPS)
    elif map_name not in config.MAPS:
        raise ApiError("Неверная карта")
    mid = db.create_match(mode, map_name, p["tg_id"])
    notify_group(f"🆕 <b>{escape(p['nick'])}</b> создал лобби #{mid}: {mode}, {escape(map_name)}. Залетайте!")
    return jsonify(id=mid)


@app.post("/api/lobbies/<int:mid>/join")
@auth
def api_join(mid: int):
    p = require_player()
    m = get_match(mid)
    if m["status"] != "open":
        raise ApiError("Лобби уже не открыто")
    if any(x["tg_id"] == p["tg_id"] for x in m["players"]):
        return jsonify(ok=True)
    if db.active_match_of(p["tg_id"]):
        raise ApiError("Ты уже в другом лобби")
    if len(m["players"]) >= MODES[m["mode"]]:
        raise ApiError("Лобби заполнено")
    db.join(mid, p["tg_id"])
    if len(m["players"]) + 1 == MODES[m["mode"]]:
        notify([m["creator_id"]], f"✅ Лобби #{mid} собрано — можно стартовать!")
    return jsonify(ok=True)


@app.post("/api/lobbies/<int:mid>/leave")
@auth
def api_leave(mid: int):
    m = get_match(mid)
    me = uid()
    if m["status"] != "open":
        raise ApiError("Из начатого матча выйти нельзя")
    db.leave(mid, me)
    rest = [p for p in m["players"] if p["tg_id"] != me]
    if not rest:
        db.set_status(mid, "cancelled")
    elif m["creator_id"] == me:
        db.set_creator(mid, rest[0]["tg_id"])
    return jsonify(ok=True)


@app.post("/api/lobbies/<int:mid>/kick")
@auth
def api_kick(mid: int):
    m = get_match(mid)
    require_host(m)
    if m["status"] != "open":
        raise ApiError("Лобби уже не открыто")
    target = int(body().get("tg_id", 0))
    if target == m["creator_id"]:
        raise ApiError("Нельзя кикнуть хоста")
    db.leave(mid, target)
    return jsonify(ok=True)


@app.post("/api/lobbies/<int:mid>/room")
@auth
def api_room(mid: int):
    m = get_match(mid)
    require_host(m)
    room = str(body().get("room", "")).strip()[:60]
    db.set_room(mid, room)
    if m["status"] == "live" and room:
        notify([p["tg_id"] for p in m["players"]], f"🔑 Матч #{mid}: комната <code>{escape(room)}</code>")
    return jsonify(ok=True)


@app.post("/api/lobbies/<int:mid>/start")
@auth
def api_start(mid: int):
    m = get_match(mid)
    require_host(m)
    if m["status"] != "open":
        raise ApiError("Матч уже начат")
    if len(m["players"]) != MODES[m["mode"]]:
        raise ApiError(f"Нужно {MODES[m['mode']]} игроков")
    db.start_match(mid, elo.balance(m["players"]))
    m = db.match(mid)
    room = f"\n🔑 Комната: <code>{escape(m['room'])}</code>" if m["room"] else ""
    host = next(p for p in m["players"] if p["tg_id"] == m["creator_id"])
    notify(
        [p["tg_id"] for p in m["players"]],
        f"🔥 <b>Матч #{mid} начался!</b> {m['mode']} · {escape(m['map'])}\n"
        f"Хост: {escape(host['nick'])}{room}\n\n{teams_text(m)}",
    )
    return jsonify(ok=True)


@app.post("/api/lobbies/<int:mid>/result")
@auth
def api_result(mid: int):
    m = get_match(mid)
    require_host(m)
    if m["status"] != "live":
        raise ApiError("Матч не идёт")
    b = body()
    winner = int(b.get("winner", 0))
    if winner not in (1, 2):
        raise ApiError("Выбери победителя")
    s1, s2 = int(b.get("score1", 0) or 0), int(b.get("score2", 0) or 0)
    if not (0 <= s1 <= 99 and 0 <= s2 <= 99) or ((s1 or s2) and (s1 > s2) != (winner == 1)):
        raise ApiError("Счёт не совпадает с победителем")
    score = f"{s1}:{s2}" if (s1 or s2) else ""
    db.finish_match(mid, winner, score, elo.deltas(m["players"], winner))
    m = db.match(mid)
    for p in m["players"]:
        won = p["team"] == winner
        up = elo.level(p["elo"]) > elo.level(p["elo_before"])
        tg.send(
            p["tg_id"],
            f"{'🏆 Победа' if won else '💀 Поражение'} в матче #{mid} ({escape(m['map'])} {score})\n"
            f"ELO: {p['elo_before']} → <b>{p['elo']}</b> ({p['elo_delta']:+d})"
            + (f"\n🎉 Новый уровень: {elo.level(p['elo'])}!" if up else ""),
        )
    win_names = ", ".join(escape(p["nick"]) for p in m["players"] if p["team"] == winner)
    notify_group(f"🏁 Матч #{mid} ({escape(m['map'])} {score}) — победили: {win_names}")
    return jsonify(ok=True)


@app.post("/api/lobbies/<int:mid>/cancel")
@auth
def api_cancel(mid: int):
    m = get_match(mid)
    require_host(m)
    if m["status"] not in ("open", "live"):
        raise ApiError("Матч уже завершён")
    db.set_status(mid, "cancelled")
    if m["status"] == "live":
        notify([p["tg_id"] for p in m["players"]], f"❌ Матч #{mid} отменён, ELO не изменилось.")
    return jsonify(ok=True)


@app.get("/api/leaderboard")
@auth
def api_leaderboard():
    rows = db.leaderboard()
    for r in rows:
        r["level"] = elo.level(r["elo"])
    return jsonify(rows)


@app.get("/api/players/<int:tg_id>")
@auth
def api_player(tg_id: int):
    p = db.player(tg_id)
    if not p:
        raise ApiError("Игрок не найден")
    return jsonify(player=public_player(p), rank=db.rank_of(tg_id), history=db.history(tg_id))


# ---------- Telegram bot ----------

def handle_update(update: dict) -> None:
    msg = update.get("message")
    if not msg or "text" not in msg:
        return
    chat_id, user_id = msg["chat"]["id"], msg["from"]["id"]
    cmd = msg["text"].split()[0].split("@")[0].lower()
    private = msg["chat"]["type"] == "private"

    if cmd == "/start":
        if not private:
            tg.send(chat_id, "Напиши мне в личку, чтобы открыть приложение 🙂")
            return
        p = db.player(user_id)
        hello = (
            f"С возвращением, <b>{escape(p['nick'])}</b>! {elo.level(p['elo'])} lvl · {p['elo']} ELO"
            if p else "Привет! Это наша площадка для матчей <b>Standoff 2</b> с ELO и рейтингом."
        )
        tg.send(chat_id, f"{hello}\n\n"
                "В приложении можно:\n"
                "• создать лобби 5x5 или 2x2 и собрать друзей\n"
                "• автоматически поделить команды по ELO\n"
                "• записать результат и получить ±ELO\n"
                "• смотреть рейтинг и свою историю", tg.app_button())
    elif cmd == "/top":
        rows = db.leaderboard(10)
        if not rows:
            tg.send(chat_id, "Пока никто не зарегистрирован.")
            return
        medals = {1: "🥇", 2: "🥈", 3: "🥉"}
        lines = [f"{medals.get(i, f'{i}.')} {escape(r['nick'])} — <b>{r['elo']}</b> ({elo.level(r['elo'])} lvl)"
                 for i, r in enumerate(rows, 1)]
        tg.send(chat_id, "<b>Топ-10</b>\n\n" + "\n".join(lines), tg.app_button("📊 Весь рейтинг") if private else None)
    elif cmd == "/me":
        p = db.player(user_id)
        if not p:
            tg.send(chat_id, "Ты ещё не зарегистрирован — открой приложение.", tg.app_button() if private else None)
            return
        games = p["wins"] + p["losses"]
        wr = round(p["wins"] * 100 / games) if games else 0
        tg.send(chat_id, f"<b>{escape(p['nick'])}</b>\n"
                f"{elo.level(p['elo'])} lvl · <b>{p['elo']}</b> ELO · #{db.rank_of(user_id)} в рейтинге\n"
                f"Матчей: {games} · Побед: {p['wins']} · Винрейт: {wr}%")
    elif cmd == "/id":
        tg.send(chat_id, f"Твой ID: <code>{user_id}</code>\nID чата: <code>{chat_id}</code>")


@app.post("/webhook")
def webhook():
    if request.headers.get("X-Telegram-Bot-Api-Secret-Token") != config.WEBHOOK_SECRET:
        abort(403)
    try:
        handle_update(request.get_json(force=True))
    except Exception:
        log.exception("update failed")
    return "ok"
