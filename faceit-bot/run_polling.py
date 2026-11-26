"""Запуск без webhook (локально или на VPS): веб-сервер Mini App + опрос Telegram.

Mini App всё равно должен быть доступен по HTTPS через WEBAPP_URL.
"""
import logging
import threading
import time

import config
import tg
from app import app, handle_update

log = logging.getLogger("polling")


def poll() -> None:
    tg.call("deleteWebhook")
    offset = None
    while True:
        try:
            updates = tg.call("getUpdates", offset=offset, timeout=50, allowed_updates=["message"])
            for u in updates:
                offset = u["update_id"] + 1
                try:
                    handle_update(u)
                except Exception:
                    log.exception("update failed")
        except Exception as e:
            log.warning("getUpdates: %s", e)
            time.sleep(3)


if __name__ == "__main__":
    threading.Thread(target=poll, daemon=True).start()
    app.run(host="0.0.0.0", port=config.PORT)
