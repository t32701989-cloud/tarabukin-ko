"""Telegram-бот + Mini App: своя ELO-площадка для матчей Standoff 2 с друзьями."""
from __future__ import annotations

import asyncio
import logging
from html import escape

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.filters import Command, CommandStart
from aiogram.types import (
    BotCommand,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    MenuButtonWebApp,
    Message,
    WebAppInfo,
)
from aiohttp import web

import config
import elo
from db import DB
from web import create_app

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("bot")

database = DB(config.DB_PATH)
dp = Dispatcher()


def app_keyboard(text: str = "🎮 Открыть приложение") -> InlineKeyboardMarkup | None:
    if not config.WEBAPP_URL:
        return None
    return InlineKeyboardMarkup(inline_keyboard=[[
        InlineKeyboardButton(text=text, web_app=WebAppInfo(url=config.WEBAPP_URL))
    ]])


@dp.message(CommandStart())
async def cmd_start(message: Message) -> None:
    if message.chat.type != "private":
        await message.answer("Напиши мне в личку, чтобы открыть приложение 🙂")
        return
    p = database.player(message.from_user.id)
    hello = (
        f"С возвращением, <b>{escape(p['nick'])}</b>! {elo.level(p['elo'])} lvl · {p['elo']} ELO"
        if p else "Привет! Это наша площадка для матчей <b>Standoff 2</b> с ELO и рейтингом."
    )
    await message.answer(
        f"{hello}\n\n"
        "В приложении можно:\n"
        "• создать лобби 5x5 или 2x2 и собрать друзей\n"
        "• автоматически поделить команды по ELO\n"
        "• записать результат и получить ±ELO\n"
        "• смотреть рейтинг и свою историю",
        reply_markup=app_keyboard(),
    )


@dp.message(Command("top"))
async def cmd_top(message: Message) -> None:
    rows = database.leaderboard(10)
    if not rows:
        await message.answer("Пока никто не зарегистрирован.")
        return
    medals = {1: "🥇", 2: "🥈", 3: "🥉"}
    lines = [
        f"{medals.get(i, f'{i}.')} {escape(r['nick'])} — <b>{r['elo']}</b> ({elo.level(r['elo'])} lvl)"
        for i, r in enumerate(rows, 1)
    ]
    await message.answer("<b>Топ-10</b>\n\n" + "\n".join(lines), reply_markup=app_keyboard("📊 Весь рейтинг"))


@dp.message(Command("me"))
async def cmd_me(message: Message) -> None:
    p = database.player(message.from_user.id)
    if not p:
        await message.answer("Ты ещё не зарегистрирован — открой приложение.", reply_markup=app_keyboard())
        return
    games = p["wins"] + p["losses"]
    wr = round(p["wins"] * 100 / games) if games else 0
    await message.answer(
        f"<b>{escape(p['nick'])}</b>\n"
        f"{elo.level(p['elo'])} lvl · <b>{p['elo']}</b> ELO · #{database.rank_of(p['tg_id'])} в рейтинге\n"
        f"Матчей: {games} · Побед: {p['wins']} · Винрейт: {wr}%"
    )


@dp.message(Command("id"))
async def cmd_id(message: Message) -> None:
    """Помогает узнать свой ID (для ADMIN_IDS) и ID группы (для NOTIFY_CHAT_ID)."""
    await message.answer(f"Твой ID: <code>{message.from_user.id}</code>\nID чата: <code>{message.chat.id}</code>")


async def main() -> None:
    bot = Bot(config.BOT_TOKEN, default=DefaultBotProperties(parse_mode=ParseMode.HTML))
    await bot.set_my_commands([
        BotCommand(command="start", description="Открыть приложение"),
        BotCommand(command="top", description="Топ-10 игроков"),
        BotCommand(command="me", description="Моя статистика"),
        BotCommand(command="id", description="Узнать ID"),
    ])
    if config.WEBAPP_URL:
        await bot.set_chat_menu_button(
            menu_button=MenuButtonWebApp(text="Играть", web_app=WebAppInfo(url=config.WEBAPP_URL))
        )
    else:
        log.warning("WEBAPP_URL не задан — кнопка Mini App не появится в Telegram")

    runner = web.AppRunner(create_app(bot, database))
    await runner.setup()
    await web.TCPSite(runner, config.HOST, config.PORT).start()
    log.info("Mini App сервер на http://%s:%s", config.HOST, config.PORT)
    try:
        await dp.start_polling(bot)
    finally:
        await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
