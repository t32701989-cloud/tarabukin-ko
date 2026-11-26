"""Заливает бота на Cloudflare Workers через API и настраивает Telegram.

    CLOUDFLARE_API_TOKEN=... BOT_TOKEN=... python cloudflare/deploy.py

Токен Cloudflare: шаблон «Edit Cloudflare Workers». BOT_TOKEN можно взять из ../.env.
Необязательно: ADMIN_IDS, NOTIFY_CHAT_ID, MAPS, WORKER_NAME (по умолчанию so2-arena).
"""
from __future__ import annotations

import json
import os
import secrets
import sys
from pathlib import Path

import requests
from dotenv import load_dotenv

HERE = Path(__file__).resolve().parent
load_dotenv(HERE.parent / ".env")

CF = "https://api.cloudflare.com/client/v4"
CF_TOKEN = os.environ.get("CLOUDFLARE_API_TOKEN", "")
BOT_TOKEN = os.environ["BOT_TOKEN"]
NAME = os.getenv("WORKER_NAME", "so2-arena")
H = {"Authorization": f"Bearer {CF_TOKEN}"}


def cf(method: str, path: str, **kw) -> dict:
    r = requests.request(method, CF + path, headers=H, timeout=60, **kw)
    try:
        data = r.json()
    except ValueError:
        sys.exit(f"Cloudflare {method} {path}: HTTP {r.status_code} {r.text[:300]}")
    if not data.get("success"):
        raise RuntimeError(f"{method} {path}: {data.get('errors')}")
    return data["result"]


def tg(method: str, **params) -> dict:
    r = requests.post(f"https://api.telegram.org/bot{BOT_TOKEN}/{method}", json=params, timeout=30).json()
    if not r.get("ok"):
        raise RuntimeError(f"Telegram {method}: {r.get('description')}")
    return r["result"]


def main() -> None:
    bot = tg("getMe")
    print(f"Бот: @{bot['username']}")

    accounts = cf("GET", "/accounts")
    if not accounts:
        sys.exit("Токен не видит ни одного аккаунта Cloudflare")
    acc = accounts[0]["id"]
    print(f"Аккаунт Cloudflare: {accounts[0]['name']}")

    # поддомен *.workers.dev
    try:
        sub = cf("GET", f"/accounts/{acc}/workers/subdomain")["subdomain"]
    except RuntimeError:
        sub = None
    if not sub:
        sub = f"so2arena-{secrets.token_hex(3)}"
        cf("PUT", f"/accounts/{acc}/workers/subdomain", json={"subdomain": sub})
        print(f"Создан поддомен {sub}.workers.dev")

    webhook_secret = secrets.token_hex(16)
    bindings = [
        {"type": "durable_object_namespace", "name": "ARENA", "class_name": "Arena"},
        {"type": "secret_text", "name": "BOT_TOKEN", "text": BOT_TOKEN},
        {"type": "secret_text", "name": "WEBHOOK_SECRET", "text": webhook_secret},
        {"type": "plain_text", "name": "BOT_USERNAME", "text": bot["username"]},
        {"type": "plain_text", "name": "ADMIN_IDS", "text": os.getenv("ADMIN_IDS", "")},
        {"type": "plain_text", "name": "NOTIFY_CHAT_ID", "text": os.getenv("NOTIFY_CHAT_ID", "")},
    ]
    if os.getenv("MAPS"):
        bindings.append({"type": "plain_text", "name": "MAPS", "text": os.environ["MAPS"]})

    def upload(with_migration: bool) -> None:
        meta = {"main_module": "worker.js", "compatibility_date": "2025-01-01", "bindings": bindings}
        if with_migration:
            meta["migrations"] = {"new_tag": "v1", "new_sqlite_classes": ["Arena"]}
        files = {
            "metadata": (None, json.dumps(meta), "application/json"),
            "worker.js": ("worker.js", (HERE / "worker.js").read_bytes(), "application/javascript+module"),
            "index.html": ("index.html", (HERE.parent / "webapp" / "index.html").read_bytes(), "text/plain"),
        }
        cf("PUT", f"/accounts/{acc}/workers/scripts/{NAME}", files=files)

    try:
        upload(with_migration=True)
    except RuntimeError as e:
        if "migration" not in str(e).lower():
            raise
        upload(with_migration=False)  # повторный деплой: миграция уже применена
    print("Код залит")

    cf("POST", f"/accounts/{acc}/workers/scripts/{NAME}/subdomain", json={"enabled": True})
    url = f"https://{NAME}.{sub}.workers.dev"
    print(f"Адрес: {url}")

    tg("setMyCommands", commands=[
        {"command": "start", "description": "Открыть приложение"},
        {"command": "top", "description": "Топ-10 игроков"},
        {"command": "me", "description": "Моя статистика"},
        {"command": "id", "description": "Узнать ID"},
    ])
    tg("setChatMenuButton", menu_button={"type": "web_app", "text": "Играть", "web_app": {"url": url}})
    tg("setMyShortDescription", short_description="Матчи Standoff 2 с друзьями: лобби 5x5, бан карт, ELO и уровни 1–10.")
    tg("setMyDescription", description=(
        "SO2 Arena — своя ELO-площадка для Standoff 2.\n\n"
        "🎮 Заходи в лобби 5x5\n🗺 Капитаны банят карты\n📈 ELO, калибровка и уровни 1–10\n🏆 Рейтинг друзей\n\n"
        "Жми «Старт» и открывай приложение."))
    tg("setWebhook", url=f"{url}/webhook", secret_token=webhook_secret, allowed_updates=["message"])
    print("Telegram настроен ✅")


if __name__ == "__main__":
    main()
