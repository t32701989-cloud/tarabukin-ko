"""HTTP API для Mini App + раздача статики."""
from __future__ import annotations

import logging
import random
import re
from html import escape
from pathlib import Path

from aiogram import Bot
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup
from aiogram.utils.web_app import safe_parse_webapp_init_data
from aiohttp import web

import config
import elo
from db import DB

log = logging.getLogger("web")
WEBAPP_DIR = Path(__file__).parent / "webapp"
MODES = {"5x5": 10, "2x2": 4}
NICK_RE = re.compile(r"^[\w\-\.\[\]\|★☆ ]{2,20}$", re.UNICODE)


# ---------- auth ----------

@web.middleware
async def auth_middleware(request: web.Request, handler):
    if not request.path.startswith("/api/"):
        return await handler(request)
    init_data = request.headers.get("X-Init-Data", "")
    if init_data:
        try:
            data = safe_parse_webapp_init_data(config.BOT_TOKEN, init_data)
        except ValueError:
            raise web.HTTPUnauthorized(text="bad initData")
        user = data.user
        request["user"] = {
            "id": user.id,
            "username": user.username,
            "name": " ".join(x for x in (user.first_name, user.last_name) if x),
        }
    elif config.DEV_MODE and request.headers.get("X-Dev-User"):
        uid = int(request.headers["X-Dev-User"])
        request["user"] = {"id": uid, "username": f"dev{uid}", "name": f"Dev {uid}"}
    else:
        raise web.HTTPUnauthorized(text="open the app from Telegram")
    try:
        return await handler(request)
    except ApiError as e:
        return web.json_response({"error": str(e)}, status=400)


class ApiError(Exception):
    pass


def db(request: web.Request) -> DB:
    return request.app["db"]


def uid(request: web.Request) -> int:
    return request["user"]["id"]


def is_admin(tg_id: int) -> bool:
    return tg_id in config.ADMIN_IDS


def require_player(request: web.Request) -> dict:
    p = db(request).player(uid(request))
    if not p:
        raise ApiError("Сначала зарегистрируйся")
    return p


def get_match(request: web.Request) -> dict:
    m = db(request).match(int(request.match_info["id"]))
    if not m:
        raise ApiError("Матч не найден")
    return m


def require_host(request: web.Request, m: dict) -> None:
    if m["creator_id"] != uid(request) and not is_admin(uid(request)):
        raise ApiError("Это может сделать только хост лобби или админ")


def public_player(p: dict) -> dict:
    lv = elo.level(p["elo"])
    return {**p, "level": lv, "next_level_at": elo.next_level_at(p["elo"])}


def public_match(m: dict) -> dict:
    for p in m["players"]:
        p["level"] = elo.level(p["elo"])
    m["size"] = MODES[m["mode"]]
    return m


# ---------- notifications ----------

async def notify(request: web.Request, tg_ids, text: str) -> None:
    bot: Bot = request.app["bot"]
    for tg_id in tg_ids:
        try:
            await bot.send_message(tg_id, text)
        except Exception as e:  # пользователь мог не запускать бота
            log.warning("notify %s failed: %s", tg_id, e)


async def notify_group(request: web.Request, text: str) -> None:
    if not config.NOTIFY_CHAT_ID:
        return
    bot: Bot = request.app["bot"]
    me = await bot.me()
    kb = InlineKeyboardMarkup(inline_keyboard=[[
        InlineKeyboardButton(text="🎮 Открыть", url=f"https://t.me/{me.username}?start=play")
    ]])
    try:
        await bot.send_message(config.NOTIFY_CHAT_ID, text, reply_markup=kb)
    except Exception as e:
        log.warning("group notify failed: %s", e)


def teams_text(m: dict) -> str:
    lines = []
    for team in (1, 2):
        ps = [p for p in m["players"] if p["team"] == team]
        avg = round(sum(p["elo"] for p in ps) / len(ps)) if ps else 0
        lines.append(f"<b>Команда {team}</b> (ср. {avg} ELO)")
        lines += [f"  • {escape(p['nick'])} — {p['elo']}" for p in ps]
    return "\n".join(lines)


# ---------- handlers ----------

routes = web.RouteTableDef()


@routes.get("/")
async def index(request: web.Request):
    return web.FileResponse(WEBAPP_DIR / "index.html", headers={"Cache-Control": "no-cache"})


@routes.get("/api/config")
async def api_config(request: web.Request):
    return web.json_response({"maps": config.MAPS, "modes": MODES, "levels": elo.LEVELS})


@routes.get("/api/me")
async def api_me(request: web.Request):
    p = db(request).player(uid(request))
    return web.json_response({
        "user": request["user"],
        "player": public_player(p) if p else None,
        "rank": db(request).rank_of(uid(request)),
        "active_match": db(request).active_match_of(uid(request)),
        "is_admin": is_admin(uid(request)),
    })


@routes.post("/api/register")
async def api_register(request: web.Request):
    body = await request.json()
    nick = str(body.get("nick", "")).strip()
    game_id = re.sub(r"\D", "", str(body.get("game_id", "")))[:15]
    if not NICK_RE.match(nick):
        raise ApiError("Ник: 2–20 символов")
    if db(request).nick_taken(nick, uid(request)):
        raise ApiError("Этот ник уже занят")
    u = request["user"]
    db(request).upsert_player(u["id"], nick, game_id, u["username"], u["name"])
    return web.json_response({"ok": True})


@routes.get("/api/lobbies")
async def api_lobbies(request: web.Request):
    return web.json_response([public_match(m) for m in db(request).active_matches()])


@routes.get("/api/matches/{id}")
async def api_match(request: web.Request):
    return web.json_response(public_match(get_match(request)))


@routes.post("/api/lobbies")
async def api_create(request: web.Request):
    p = require_player(request)
    if db(request).active_match_of(p["tg_id"]):
        raise ApiError("Ты уже в другом лобби")
    body = await request.json()
    mode = body.get("mode")
    if mode not in MODES:
        raise ApiError("Неверный режим")
    map_name = body.get("map") or "random"
    if map_name == "random":
        map_name = random.choice(config.MAPS)
    elif map_name not in config.MAPS:
        raise ApiError("Неверная карта")
    mid = db(request).create_match(mode, map_name, p["tg_id"])
    await notify_group(
        request,
        f"🆕 <b>{escape(p['nick'])}</b> создал лобби #{mid}: {mode}, {escape(map_name)}. Залетайте!",
    )
    return web.json_response({"id": mid})


@routes.post("/api/lobbies/{id}/join")
async def api_join(request: web.Request):
    p = require_player(request)
    m = get_match(request)
    if m["status"] != "open":
        raise ApiError("Лобби уже не открыто")
    if any(x["tg_id"] == p["tg_id"] for x in m["players"]):
        return web.json_response({"ok": True})
    if db(request).active_match_of(p["tg_id"]):
        raise ApiError("Ты уже в другом лобби")
    if len(m["players"]) >= MODES[m["mode"]]:
        raise ApiError("Лобби заполнено")
    db(request).join(m["id"], p["tg_id"])
    if len(m["players"]) + 1 == MODES[m["mode"]]:
        await notify(request, [m["creator_id"]], f"✅ Лобби #{m['id']} собрано — можно стартовать!")
    return web.json_response({"ok": True})


@routes.post("/api/lobbies/{id}/leave")
async def api_leave(request: web.Request):
    m = get_match(request)
    me = uid(request)
    if m["status"] != "open":
        raise ApiError("Из начатого матча выйти нельзя")
    db(request).leave(m["id"], me)
    rest = [p for p in m["players"] if p["tg_id"] != me]
    if not rest:
        db(request).set_status(m["id"], "cancelled")
    elif m["creator_id"] == me:
        db(request).set_creator(m["id"], rest[0]["tg_id"])
    return web.json_response({"ok": True})


@routes.post("/api/lobbies/{id}/kick")
async def api_kick(request: web.Request):
    m = get_match(request)
    require_host(request, m)
    if m["status"] != "open":
        raise ApiError("Лобби уже не открыто")
    target = int((await request.json())["tg_id"])
    if target == m["creator_id"]:
        raise ApiError("Нельзя кикнуть хоста")
    db(request).leave(m["id"], target)
    return web.json_response({"ok": True})


@routes.post("/api/lobbies/{id}/room")
async def api_room(request: web.Request):
    m = get_match(request)
    require_host(request, m)
    room = str((await request.json()).get("room", "")).strip()[:60]
    db(request).set_room(m["id"], room)
    if m["status"] == "live" and room:
        await notify(
            request, [p["tg_id"] for p in m["players"]],
            f"🔑 Матч #{m['id']}: комната <code>{escape(room)}</code>",
        )
    return web.json_response({"ok": True})


@routes.post("/api/lobbies/{id}/start")
async def api_start(request: web.Request):
    m = get_match(request)
    require_host(request, m)
    if m["status"] != "open":
        raise ApiError("Матч уже начат")
    if len(m["players"]) != MODES[m["mode"]]:
        raise ApiError(f"Нужно {MODES[m['mode']]} игроков")
    teams = elo.balance(m["players"])
    db(request).start_match(m["id"], teams)
    m = db(request).match(m["id"])
    room = f"\n🔑 Комната: <code>{escape(m['room'])}</code>" if m["room"] else ""
    host = next(p for p in m["players"] if p["tg_id"] == m["creator_id"])
    await notify(
        request, [p["tg_id"] for p in m["players"]],
        f"🔥 <b>Матч #{m['id']} начался!</b> {m['mode']} · {escape(m['map'])}\n"
        f"Хост: {escape(host['nick'])}{room}\n\n{teams_text(m)}",
    )
    return web.json_response({"ok": True})


@routes.post("/api/lobbies/{id}/result")
async def api_result(request: web.Request):
    m = get_match(request)
    require_host(request, m)
    if m["status"] != "live":
        raise ApiError("Матч не идёт")
    body = await request.json()
    winner = int(body.get("winner", 0))
    if winner not in (1, 2):
        raise ApiError("Выбери победителя")
    s1, s2 = int(body.get("score1", 0)), int(body.get("score2", 0))
    if not (0 <= s1 <= 99 and 0 <= s2 <= 99) or (s1 or s2) and (s1 > s2) != (winner == 1):
        raise ApiError("Счёт не совпадает с победителем")
    score = f"{s1}:{s2}" if (s1 or s2) else ""
    d = elo.deltas(m["players"], winner)
    db(request).finish_match(m["id"], winner, score, d)
    m = db(request).match(m["id"])
    for p in m["players"]:
        won = p["team"] == winner
        await notify(
            request, [p["tg_id"]],
            f"{'🏆 Победа' if won else '💀 Поражение'} в матче #{m['id']} ({escape(m['map'])} {score})\n"
            f"ELO: {p['elo_before']} → <b>{p['elo']}</b> ({p['elo_delta']:+d})"
            + (f"\n🎉 Новый уровень: {elo.level(p['elo'])}!"
               if elo.level(p["elo"]) > elo.level(p["elo_before"]) else ""),
        )
    win_names = ", ".join(escape(p["nick"]) for p in m["players"] if p["team"] == winner)
    await notify_group(request, f"🏁 Матч #{m['id']} ({escape(m['map'])} {score}) — победили: {win_names}")
    return web.json_response({"ok": True})


@routes.post("/api/lobbies/{id}/cancel")
async def api_cancel(request: web.Request):
    m = get_match(request)
    require_host(request, m)
    if m["status"] not in ("open", "live"):
        raise ApiError("Матч уже завершён")
    db(request).set_status(m["id"], "cancelled")
    if m["status"] == "live":
        await notify(request, [p["tg_id"] for p in m["players"]], f"❌ Матч #{m['id']} отменён, ELO не изменилось.")
    return web.json_response({"ok": True})


@routes.get("/api/leaderboard")
async def api_leaderboard(request: web.Request):
    rows = db(request).leaderboard()
    for r in rows:
        r["level"] = elo.level(r["elo"])
    return web.json_response(rows)


@routes.get("/api/players/{tg_id}")
async def api_player(request: web.Request):
    tg_id = int(request.match_info["tg_id"])
    p = db(request).player(tg_id)
    if not p:
        raise ApiError("Игрок не найден")
    return web.json_response({
        "player": public_player(p),
        "rank": db(request).rank_of(tg_id),
        "history": db(request).history(tg_id),
    })


def create_app(bot: Bot, database: DB) -> web.Application:
    app = web.Application(middlewares=[auth_middleware])
    app["bot"] = bot
    app["db"] = database
    app.add_routes(routes)
    app.router.add_static("/static/", WEBAPP_DIR)
    return app
