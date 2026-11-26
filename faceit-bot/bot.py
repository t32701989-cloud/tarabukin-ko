"""Telegram-бот для FACEIT (CS2): статистика, последние матчи, сравнение, отслеживание ELO."""
from __future__ import annotations

import asyncio
import logging
import os
from html import escape

from aiogram import Bot, Dispatcher, F
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.filters import Command, CommandObject, CommandStart
from aiogram.types import BotCommand, Message
from dotenv import load_dotenv

from faceit import (
    FaceitClient,
    FaceitError,
    PlayerNotFound,
    cs2_info,
    elo_to_next_level,
    level_for_elo,
)
from storage import Storage

load_dotenv()
BOT_TOKEN = os.environ["BOT_TOKEN"]
FACEIT_API_KEY = os.environ["FACEIT_API_KEY"]
TRACK_INTERVAL = int(os.getenv("TRACK_INTERVAL_MIN", "5")) * 60

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("faceit-bot")

faceit = FaceitClient(FACEIT_API_KEY)
storage = Storage(os.getenv("DB_PATH", "bot.db"))
dp = Dispatcher()

LEVEL_EMOJI = {1: "⚪", 2: "🟢", 3: "🟢", 4: "🟡", 5: "🟡", 6: "🟡", 7: "🟡", 8: "🟠", 9: "🟠", 10: "🔴"}

HELP = (
    "<b>FACEIT бот (CS2)</b>\n\n"
    "/stats <i>ник</i> — общая статистика и ELO\n"
    "/last <i>ник</i> — последние 10 матчей\n"
    "/compare <i>ник1 ник2</i> — сравнить двух игроков\n"
    "/link <i>ник</i> — привязать свой ник (потом можно без ника)\n"
    "/unlink — отвязать ник\n"
    "/track on|off — уведомлять об изменении ELO\n\n"
    "Можно просто отправить ник сообщением."
)


# ---------- helpers ----------

def fmt_level(elo: int, level: int) -> str:
    to_next = elo_to_next_level(elo)
    nxt = f" (до {level + 1} lvl: {to_next})" if to_next else ""
    return f"{LEVEL_EMOJI.get(level, '')} {level} lvl · <b>{elo}</b> ELO{nxt}"


def fnum(value, default: float = 0.0) -> float:
    try:
        return float(str(value).replace(",", "."))
    except (TypeError, ValueError):
        return default


async def resolve_player(message: Message, nickname: str | None) -> dict | None:
    """Находит игрока по нику, либо берёт привязанного. Пишет ошибку в чат."""
    nickname = (nickname or "").strip()
    try:
        if nickname:
            return await faceit.player_by_nickname(nickname)
        linked = storage.get(message.chat.id)
        if not linked:
            await message.answer("Укажи ник: <code>/stats s1mple</code> или привяжи свой через /link")
            return None
        return await faceit.player_by_id(linked["player_id"])
    except PlayerNotFound:
        await message.answer(f"Игрок <b>{escape(nickname)}</b> не найден на FACEIT (CS2) 🤷")
    except FaceitError as e:
        await message.answer(f"Ошибка FACEIT: {escape(str(e))}")
    return None


def profile_url(player: dict) -> str:
    return (player.get("faceit_url") or "").replace("{lang}", "ru")


async def build_stats(player: dict) -> str:
    elo, level = cs2_info(player)
    life = await faceit.lifetime_stats(player["player_id"])
    recent = "".join("🟢" if r == "1" else "🔴" for r in life.get("Recent Results", []))
    nick = escape(player["nickname"])
    country = (player.get("country") or "").upper()
    lines = [
        f'<a href="{profile_url(player)}"><b>{nick}</b></a> {country}',
        fmt_level(elo, level),
        "",
        f"🎮 Матчей: <b>{life.get('Matches', '—')}</b>",
        f"🏆 Винрейт: <b>{life.get('Win Rate %', '—')}%</b>",
        f"🔫 K/D: <b>{life.get('Average K/D Ratio', '—')}</b>",
        f"🎯 HS: <b>{life.get('Average Headshots %', '—')}%</b>",
        f"🔥 Лучший винстрик: <b>{life.get('Longest Win Streak', '—')}</b>",
    ]
    if recent:
        lines.append(f"\nПоследние: {recent}")
    return "\n".join(lines)


# ---------- commands ----------

@dp.message(CommandStart())
@dp.message(Command("help"))
async def cmd_start(message: Message) -> None:
    await message.answer(HELP)


@dp.message(Command("stats"))
async def cmd_stats(message: Message, command: CommandObject) -> None:
    player = await resolve_player(message, command.args)
    if not player:
        return
    try:
        await message.answer(await build_stats(player), disable_web_page_preview=True)
    except FaceitError as e:
        await message.answer(f"Ошибка FACEIT: {escape(str(e))}")


@dp.message(Command("last"))
async def cmd_last(message: Message, command: CommandObject) -> None:
    player = await resolve_player(message, command.args)
    if not player:
        return
    try:
        matches = await faceit.recent_matches(player["player_id"], limit=10)
    except FaceitError as e:
        await message.answer(f"Ошибка FACEIT: {escape(str(e))}")
        return
    if not matches:
        await message.answer("Матчей пока нет.")
        return

    rows, kills, deaths, wins, adr_sum, adr_n = [], 0, 0, 0, 0.0, 0
    for m in matches:
        win = str(m.get("Result")) == "1"
        k, d, a = int(fnum(m.get("Kills"))), int(fnum(m.get("Deaths"))), int(fnum(m.get("Assists")))
        kills, deaths, wins = kills + k, deaths + d, wins + win
        adr = m.get("ADR")
        if adr is not None:
            adr_sum, adr_n = adr_sum + fnum(adr), adr_n + 1
        map_name = escape(str(m.get("Map", "?")).replace("de_", "").capitalize())
        score = escape(str(m.get("Score", "")))
        rows.append(
            f"{'🟢' if win else '🔴'} <code>{map_name:<9}</code> {score}  "
            f"{k}/{d}/{a}  K/D <b>{m.get('K/D Ratio', '—')}</b>"
            + (f"  ADR {adr}" if adr is not None else "")
        )

    kd = kills / deaths if deaths else float(kills)
    summary = f"\n\nИтого: {wins}/{len(matches)} побед · K/D <b>{kd:.2f}</b>"
    if adr_n:
        summary += f" · ADR <b>{adr_sum / adr_n:.1f}</b>"
    header = f"<b>{escape(player['nickname'])}</b> — последние матчи ({len(matches)})\n\n"
    await message.answer(header + "\n".join(rows) + summary)


@dp.message(Command("compare"))
async def cmd_compare(message: Message, command: CommandObject) -> None:
    nicks = (command.args or "").split()
    if len(nicks) != 2:
        await message.answer("Использование: <code>/compare ник1 ник2</code>")
        return
    players = []
    for nick in nicks:
        p = await resolve_player(message, nick)
        if not p:
            return
        players.append(p)
    try:
        stats = await asyncio.gather(*(faceit.lifetime_stats(p["player_id"]) for p in players))
    except FaceitError as e:
        await message.answer(f"Ошибка FACEIT: {escape(str(e))}")
        return

    (p1, p2), (s1, s2) = players, stats
    e1, l1 = cs2_info(p1)
    e2, l2 = cs2_info(p2)

    def row(title: str, v1, v2, higher_better: bool = True) -> str:
        a, b = fnum(v1), fnum(v2)
        m1 = m2 = ""
        if a != b:
            first_wins = (a > b) == higher_better
            m1, m2 = ("✅", "") if first_wins else ("", "✅")
        return f"{title}: <b>{v1}</b>{m1}  vs  <b>{v2}</b>{m2}"

    text = "\n".join([
        f"<b>{escape(p1['nickname'])}</b> vs <b>{escape(p2['nickname'])}</b>\n",
        row("ELO", e1, e2),
        row("Уровень", l1, l2),
        row("Матчи", s1.get("Matches", 0), s2.get("Matches", 0)),
        row("Винрейт %", s1.get("Win Rate %", 0), s2.get("Win Rate %", 0)),
        row("K/D", s1.get("Average K/D Ratio", 0), s2.get("Average K/D Ratio", 0)),
        row("HS %", s1.get("Average Headshots %", 0), s2.get("Average Headshots %", 0)),
    ])
    await message.answer(text)


@dp.message(Command("link"))
async def cmd_link(message: Message, command: CommandObject) -> None:
    if not command.args:
        await message.answer("Использование: <code>/link твой_ник</code>")
        return
    player = await resolve_player(message, command.args)
    if not player:
        return
    elo, level = cs2_info(player)
    storage.link(message.chat.id, player["player_id"], player["nickname"], elo)
    await message.answer(
        f"Привязал <b>{escape(player['nickname'])}</b> — {fmt_level(elo, level)}\n"
        "Теперь /stats и /last работают без ника. Включить уведомления об ELO: /track on"
    )


@dp.message(Command("unlink"))
async def cmd_unlink(message: Message) -> None:
    storage.unlink(message.chat.id)
    await message.answer("Ник отвязан, уведомления выключены.")


@dp.message(Command("track"))
async def cmd_track(message: Message, command: CommandObject) -> None:
    linked = storage.get(message.chat.id)
    if not linked:
        await message.answer("Сначала привяжи ник: <code>/link твой_ник</code>")
        return
    arg = (command.args or "").strip().lower()
    if arg not in ("on", "off"):
        state = "включены" if linked["track"] else "выключены"
        await message.answer(f"Уведомления сейчас {state}. Используй <code>/track on</code> или <code>/track off</code>")
        return
    storage.set_track(message.chat.id, arg == "on")
    await message.answer(
        f"🔔 Буду писать, когда у <b>{escape(linked['nickname'])}</b> изменится ELO."
        if arg == "on" else "🔕 Уведомления выключены."
    )


@dp.message(F.text & ~F.text.startswith("/"))
async def plain_nickname(message: Message) -> None:
    nick = message.text.strip()
    if " " in nick or len(nick) > 32:
        await message.answer(HELP)
        return
    player = await resolve_player(message, nick)
    if player:
        try:
            await message.answer(await build_stats(player), disable_web_page_preview=True)
        except FaceitError as e:
            await message.answer(f"Ошибка FACEIT: {escape(str(e))}")


# ---------- ELO tracker ----------

async def elo_tracker(bot: Bot) -> None:
    while True:
        await asyncio.sleep(TRACK_INTERVAL)
        for chat_id, player_id, nickname, last_elo in storage.tracked():
            try:
                player = await faceit.player_by_id(player_id)
                elo, _ = cs2_info(player)
                if last_elo is not None and elo != last_elo:
                    diff = elo - last_elo
                    old_lvl, new_lvl = level_for_elo(last_elo), level_for_elo(elo)
                    text = (
                        f"{'📈' if diff > 0 else '📉'} <b>{escape(player['nickname'])}</b>: "
                        f"{last_elo} → <b>{elo}</b> ({diff:+d})"
                    )
                    if new_lvl != old_lvl:
                        text += f"\n{'🎉 Новый' if new_lvl > old_lvl else '😢 Понижение до'} {new_lvl} lvl!"
                    await bot.send_message(chat_id, text)
                if elo != last_elo or player["nickname"] != nickname:
                    storage.update_elo(chat_id, elo, player["nickname"])
            except Exception:
                log.exception("tracker failed for %s", chat_id)
            await asyncio.sleep(1)  # не долбим API


async def main() -> None:
    bot = Bot(BOT_TOKEN, default=DefaultBotProperties(parse_mode=ParseMode.HTML))
    await bot.set_my_commands([
        BotCommand(command="stats", description="Статистика игрока"),
        BotCommand(command="last", description="Последние матчи"),
        BotCommand(command="compare", description="Сравнить двух игроков"),
        BotCommand(command="link", description="Привязать свой ник"),
        BotCommand(command="track", description="Уведомления об ELO"),
        BotCommand(command="help", description="Помощь"),
    ])
    tracker = asyncio.create_task(elo_tracker(bot))
    try:
        await dp.start_polling(bot)
    finally:
        tracker.cancel()
        await faceit.close()


if __name__ == "__main__":
    asyncio.run(main())
