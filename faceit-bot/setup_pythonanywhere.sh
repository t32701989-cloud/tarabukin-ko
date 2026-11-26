#!/bin/bash
# Установка бота на PythonAnywhere. Запуск из Bash-консоли PythonAnywhere:
#   bash ~/tarabukin-ko/faceit-bot/setup_pythonanywhere.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# Адрес сайта: ЛОГИН.pythonanywhere.com (или ЛОГИН.eu.pythonanywhere.com для EU-аккаунтов)
DOMAIN="${USER}.pythonanywhere.com"
WSGI="/var/www/${USER}_pythonanywhere_com_wsgi.py"
if [ ! -f "$WSGI" ] && [ -f "/var/www/${USER}_eu_pythonanywhere_com_wsgi.py" ]; then
  DOMAIN="${USER}.eu.pythonanywhere.com"
  WSGI="/var/www/${USER}_eu_pythonanywhere_com_wsgi.py"
fi
if [ ! -f "$WSGI" ]; then
  echo "❌ Не найден веб-сайт. Сначала: вкладка Web → Add a new web app → Next → Flask → Python 3.10 → Next."
  exit 1
fi

echo "📦 Ставлю зависимости…"
for v in 3.10 3.11 3.12 3.13; do
  command -v "python$v" >/dev/null && "python$v" -m pip install --user -q -r requirements.txt 2>/dev/null || true
done

OLD_TOKEN=""
[ -f .env ] && OLD_TOKEN=$(grep -oP '^BOT_TOKEN=\K.*' .env || true)
read -r -p "🔑 Токен бота от @BotFather${OLD_TOKEN:+ (Enter — оставить старый)}: " TOKEN
TOKEN="${TOKEN:-$OLD_TOKEN}"
[ -z "$TOKEN" ] && { echo "Токен обязателен"; exit 1; }
read -r -p "👑 Твой Telegram ID для админки (можно пропустить, Enter): " ADMIN

BOT_USERNAME=$(python3 -c "import json,sys,urllib.request;print(json.load(urllib.request.urlopen('https://api.telegram.org/bot'+sys.argv[1]+'/getMe'))['result']['username'])" "$TOKEN") \
  || { echo "❌ Telegram не принял токен"; exit 1; }
SECRET=$(python3 -c "import secrets;print(secrets.token_hex(16))")

cat > .env <<ENV
BOT_TOKEN=$TOKEN
BOT_USERNAME=$BOT_USERNAME
WEBAPP_URL=https://$DOMAIN
WEBHOOK_SECRET=$SECRET
ADMIN_IDS=$ADMIN
NOTIFY_CHAT_ID=
MAPS=Sandstone,Rust,Province,Zone 7,Dune,Breeze,Hanami,Sakura
ENV
chmod 600 .env

cat > "$WSGI" <<PY
import sys
sys.path.insert(0, "$DIR")
from app import app as application
PY

python3 setup_bot.py
touch "$WSGI"   # перезагрузка сайта
echo
echo "✅ Готово! Открой @$BOT_USERNAME и нажми /start (или кнопку «Играть»)."
echo "   Сайт: https://$DOMAIN"
