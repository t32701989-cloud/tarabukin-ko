# FACEIT Telegram-бот (CS2)

Бот показывает статистику игроков FACEIT по CS2 и присылает уведомления об изменении ELO.

## Команды
| Команда | Что делает |
|---|---|
| `/stats ник` | ELO, уровень, сколько до следующего lvl, матчи, винрейт, K/D, HS%, последние результаты |
| `/last ник` | Последние 10 матчей: карта, счёт, K/D/A, ADR + итог |
| `/compare ник1 ник2` | Сравнение двух игроков |
| `/link ник` | Привязать свой ник — дальше `/stats` и `/last` можно без ника |
| `/unlink` | Отвязать ник |
| `/track on\|off` | Уведомления, когда у привязанного ника меняется ELO (и уровень) |

Можно просто прислать ник сообщением — бот ответит статистикой.

## Запуск
1. Создай бота у [@BotFather](https://t.me/BotFather) и возьми токен.
2. Получи **Server-side API key** на <https://developers.faceit.com> (App Studio → своё приложение → API Keys).
3. Установи и запусти:
   ```bash
   cd faceit-bot
   python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   cp .env.example .env   # впиши BOT_TOKEN и FACEIT_API_KEY
   python bot.py
   ```

Данные (привязанные ники) хранятся в `bot.db` (SQLite) рядом с ботом.
Для работы 24/7 запусти на VPS (через `systemd`, `screen` или Docker).
