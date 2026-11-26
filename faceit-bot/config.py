import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

BOT_TOKEN = os.environ["BOT_TOKEN"]
BOT_USERNAME = os.getenv("BOT_USERNAME", "")
# Публичный HTTPS-адрес сайта (на PythonAnywhere: https://ЛОГИН.pythonanywhere.com)
WEBAPP_URL = os.getenv("WEBAPP_URL", "").rstrip("/")
# Секрет, которым Telegram подписывает запросы на /webhook
WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "")
DB_PATH = os.getenv("DB_PATH") or str(BASE_DIR / "bot.db")
# Telegram ID админов через запятую (могут отменять/править любые матчи)
ADMIN_IDS = {int(x) for x in os.getenv("ADMIN_IDS", "").replace(" ", "").split(",") if x}
# ID группы с друзьями — туда бот пишет о новых лобби и результатах (необязательно)
NOTIFY_CHAT_ID = int(os.getenv("NOTIFY_CHAT_ID") or 0)
MAPS = [m.strip() for m in os.getenv(
    "MAPS", "Sandstone,Rust,Province,Zone 7,Dune,Breeze,Hanami,Sakura"
).split(",") if m.strip()]
# Только для локальной разработки: пускает в API без Telegram по заголовку X-Dev-User
DEV_MODE = os.getenv("DEV_MODE") == "1"
PORT = int(os.getenv("PORT", "8080"))
