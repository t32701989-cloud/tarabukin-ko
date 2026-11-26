"""Настраивает бота в Telegram: webhook, команды, кнопку «Играть». Запускать после изменения .env."""
import config
import tg

me = tg.call("getMe")
print(f"Бот: @{me['username']}")
tg.call("setMyCommands", commands=[
    {"command": "start", "description": "Открыть приложение"},
    {"command": "top", "description": "Топ-10 игроков"},
    {"command": "me", "description": "Моя статистика"},
    {"command": "id", "description": "Узнать ID"},
])
if config.WEBAPP_URL:
    tg.call("setChatMenuButton", menu_button={
        "type": "web_app", "text": "Играть", "web_app": {"url": config.WEBAPP_URL},
    })
    tg.call("setWebhook", url=config.WEBAPP_URL + "/webhook", secret_token=config.WEBHOOK_SECRET,
            allowed_updates=["message"], drop_pending_updates=True)
    print(f"Webhook и кнопка «Играть» → {config.WEBAPP_URL}")
else:
    print("WEBAPP_URL не задан — webhook не установлен")
