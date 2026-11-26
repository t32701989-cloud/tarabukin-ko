import os

from dotenv import load_dotenv

load_dotenv()

BOT_TOKEN = os.environ["BOT_TOKEN"]
# Публичный HTTPS-адрес, где открыт этот сервер (нужен Telegram для Mini App)
WEBAPP_URL = os.getenv("WEBAPP_URL", "").rstrip("/")
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8080"))
DB_PATH = os.getenv("DB_PATH", "bot.db")
# Telegram ID админов через запятую (могут отменять/править любые матчи)
ADMIN_IDS = {int(x) for x in os.getenv("ADMIN_IDS", "").replace(" ", "").split(",") if x}
# ID группы с друзьями — туда бот пишет о новых лобби и результатах (необязательно)
NOTIFY_CHAT_ID = int(os.getenv("NOTIFY_CHAT_ID") or 0)
MAPS = [m.strip() for m in os.getenv(
    "MAPS", "Sandstone,Rust,Province,Zone 7,Dune,Breeze,Hanami,Sakura"
).split(",") if m.strip()]
# Только для локальной разработки: пускает в API без Telegram по заголовку X-Dev-User
DEV_MODE = os.getenv("DEV_MODE") == "1"
