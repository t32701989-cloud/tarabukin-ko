"""Простые синхронные вызовы Telegram Bot API и проверка initData Mini App."""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
import time
from urllib.parse import parse_qsl

import requests

import config

log = logging.getLogger("tg")
API = f"https://api.telegram.org/bot{config.BOT_TOKEN}/"


class TgError(Exception):
    pass


def call(method: str, **params):
    params = {k: v for k, v in params.items() if v is not None}
    r = requests.post(API + method, json=params, timeout=15)
    data = r.json()
    if not data.get("ok"):
        raise TgError(f"{method}: {data.get('description')}")
    return data["result"]


def send(chat_id: int, text: str, markup: dict | None = None) -> bool:
    try:
        call("sendMessage", chat_id=chat_id, text=text, parse_mode="HTML",
             reply_markup=markup, disable_web_page_preview=True)
        return True
    except Exception as e:  # пользователь мог не запускать бота / заблокировать его
        log.warning("send to %s failed: %s", chat_id, e)
        return False


def app_button(text: str = "🎮 Открыть приложение") -> dict | None:
    if not config.WEBAPP_URL:
        return None
    return {"inline_keyboard": [[{"text": text, "web_app": {"url": config.WEBAPP_URL}}]]}


def check_init_data(init_data: str, max_age: int = 7 * 86400) -> dict:
    """Проверяет подпись initData из Telegram.WebApp и возвращает user."""
    pairs = dict(parse_qsl(init_data, keep_blank_values=True))
    received = pairs.pop("hash", "")
    check_string = "\n".join(f"{k}={v}" for k, v in sorted(pairs.items()))
    secret = hmac.new(b"WebAppData", config.BOT_TOKEN.encode(), hashlib.sha256).digest()
    expected = hmac.new(secret, check_string.encode(), hashlib.sha256).hexdigest()
    if not received or not hmac.compare_digest(expected, received):
        raise ValueError("bad hash")
    if time.time() - int(pairs.get("auth_date", 0)) > max_age:
        raise ValueError("expired")
    return json.loads(pairs["user"])
