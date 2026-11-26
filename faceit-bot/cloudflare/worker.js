// SO2 Arena на Cloudflare Workers: Mini App + API + webhook Telegram-бота.
// Все данные хранятся в одном Durable Object со встроенной SQLite.
//
// Жизненный цикл матча:
//   open     — постоянное лобби («Лобби 1», «Лобби 2»), игроки заходят и выходят;
//   ready    — набралось 10: у каждого 30 сек, чтобы нажать «Готов»;
//   veto     — выбраны 2 капитана и игрок-хост, капитаны по очереди банят карты;
//   live     — осталась одна карта, игра идёт; капитан отправляет результат;
//   pending  — результат ждёт подтверждения админа;
//   finished / cancelled.
import { DurableObject } from "cloudflare:workers";
import INDEX_HTML from "./index.html";

const TEAM_SIZE = 5;
const LOBBY_SIZE = TEAM_SIZE * 2;
const K_FACTOR = 50;
// [уровень, нижняя граница ELO]
const LEVELS = [[1, 0], [2, 800], [3, 950], [4, 1100], [5, 1250], [6, 1400], [7, 1550], [8, 1700], [9, 1850], [10, 2000]];
const DEFAULT_MAPS = "Sandstone,Rust,Province,Hanami,Prison,Dune,Breeze";
const CALIBRATION_GAMES = 10;
const CALIBRATION_MULT = 2;    // на калибровке ELO меняется в 2 раза сильнее
const PLACEMENT_MIN = 700, PLACEMENT_MAX = 1700; // после калибровки: от 1 до 8 уровня
const PLACEMENT_KD_MAX = 100;  // бонус/штраф за K/D на калибровке
const AVATAR_MAX = 220 * 1024;
const PARTY_MAX = 3, PARTY_MAX_PREMIUM = 5;
const COINS = { win: 50, loss: 20, mvp: 25, daily: 50, daily_premium: 150 }; // TC — Timoha Coin
const PREMIUM_COIN_MULT = 1.5;
const NICK_COLORS = ["#ffc400", "#ff5236", "#2f7cff", "#27c96f", "#b48cff", "#ff6fb5", "#3fe0d0", "#ffffff"];
const it = (id, kind, title, price, extra = {}) => ({ id, kind, title, price, ...extra });
// магазин: премиум, рамки, шевроны, баннеры профиля, комплекты
const SHOP = [
  it("premium_7", "premium", "Премиум на 7 дней", 1500, { days: 7 }),
  it("premium_30", "premium", "Премиум на 30 дней", 5000, { days: 30, tag: "выгодно" }),
  it("premium_90", "premium", "Премиум на 90 дней", 12000, { days: 90, tag: "−20%" }),
  it("frame_steel", "frame", "Сталь", 300), it("frame_mint", "frame", "Мята", 400), it("frame_carbon", "frame", "Карбон", 500),
  it("frame_ice", "frame", "Лёд", 600), it("frame_fire", "frame", "Пламя", 600), it("frame_toxic", "frame", "Токсин", 700),
  it("frame_violet", "frame", "Фиалка", 700), it("frame_ruby", "frame", "Рубин", 900), it("frame_emerald", "frame", "Изумруд", 900),
  it("frame_dual", "frame", "Дуэт", 1100), it("frame_gold", "frame", "Золото", 1500),
  it("frame_prem", "frame", "Премиум (анимированная)", 0, { premium: true }),
  it("chev_star", "chevron", "Звезда", 250), it("chev_heart", "chevron", "Сердце", 250), it("chev_bolt", "chevron", "Молния", 300),
  it("chev_shield", "chevron", "Щит", 350), it("chev_target", "chevron", "Прицел", 400), it("chev_fire", "chevron", "Огонь", 450),
  it("chev_diamond", "chevron", "Алмаз", 600), it("chev_skull", "chevron", "Череп", 600), it("chev_wings", "chevron", "Крылья", 800),
  it("chev_crown", "chevron", "Корона", 1200), it("chev_prem", "chevron", "Премиум", 0, { premium: true }),
  it("bn_night", "banner", "Ночной город", 500), it("bn_camo", "banner", "Камуфляж", 500), it("bn_sand", "banner", "Пустыня", 600),
  it("bn_sakura", "banner", "Сакура", 700), it("bn_ice", "banner", "Ледник", 700), it("bn_lava", "banner", "Лава", 800),
  it("bn_grid", "banner", "Топография", 800), it("bn_carbon", "banner", "Карбон", 900), it("bn_storm", "banner", "Гроза", 1200),
  it("bn_prem", "banner", "Премиум", 0, { premium: true }),
  // флаги — тоже шевроны, отдельный раздел магазина
  ...[["ua", "Украина"], ["kz", "Казахстан"], ["by", "Беларусь"], ["pl", "Польша"], ["de", "Германия"], ["us", "США"], ["gb", "Великобритания"],
    ["ge", "Грузия"], ["am", "Армения"], ["az", "Азербайджан"], ["uz", "Узбекистан"], ["md", "Молдова"], ["lt", "Литва"], ["lv", "Латвия"],
    ["ee", "Эстония"], ["kg", "Кыргызстан"], ["tr", "Турция"], ["ru", "Россия"]].map(([c, t]) => it("flag_" + c, "chevron", t, 200, { flag: true })),
  it("chev_wolf", "chevron", "Волк", 900), it("chev_eagle", "chevron", "Орёл", 900), it("chev_knives", "chevron", "Ножи", 700),
  // эксклюзивы: только из кейсов
  it("frame_galaxy", "frame", "Галактика", 0, { case: true }), it("frame_blood", "frame", "Кровавая луна", 0, { case: true }),
  it("chev_dragon", "chevron", "Дракон", 0, { case: true }), it("chev_phoenix", "chevron", "Феникс", 0, { case: true }),
  it("bn_aurora", "banner", "Северное сияние", 0, { case: true }), it("bn_galaxy", "banner", "Галактика", 0, { case: true }),
  it("set_fire", "bundle", "Комплект «Пламя»", 1500, { items: ["frame_fire", "chev_fire", "bn_lava"] }),
  it("set_ice", "bundle", "Комплект «Лёд»", 1500, { items: ["frame_ice", "chev_diamond", "bn_ice"] }),
  it("set_ops", "bundle", "Комплект «Спецназ»", 1100, { items: ["frame_carbon", "chev_shield", "bn_camo"] }),
  it("set_sakura", "bundle", "Комплект «Сакура»", 1350, { items: ["frame_violet", "chev_heart", "bn_sakura"] }),
  it("set_king", "bundle", "Комплект «Король»", 3000, { items: ["frame_gold", "chev_crown", "bn_storm"] }),
];
// кейсы: шансы по редкости. Редкость предмета: обычный ≤400 TC, редкий ≤900, эпический >900, легендарный — эксклюзив кейса
const CASES = [
  { id: "case_basic", title: "Обычный кейс", price: 400, odds: { common: 70, rare: 24, epic: 5, legendary: 1 } },
  { id: "case_elite", title: "Элитный кейс", price: 1200, odds: { common: 0, rare: 55, epic: 33, legendary: 12 } },
];
const DUP_REFUND = 0.3; // за повторку возвращаем 30% цены кейса
const rarityOf = i => i.case ? "legendary" : i.price <= 400 ? "common" : i.price <= 900 ? "rare" : "epic";
// Telegram Stars: пакеты TC и премиум за звёзды
const STARS = [
  { id: "tc_1000", title: "1 000 TC", stars: 50, tc: 1000 },
  { id: "tc_3000", title: "3 000 TC", stars: 130, tc: 3000 },
  { id: "tc_8000", title: "8 000 TC", stars: 300, tc: 8000 },
  { id: "prem_30", title: "Премиум на 30 дней", stars: 150, days: 30 },
  { id: "prem_90", title: "Премиум на 90 дней", stars: 390, days: 90 },
];
const BAN_BASE_MIN = 10, BAN_MAX_MIN = 24 * 60, BAN_RESET_DAYS = 7;
const PREMIUM_PERKS = [
  "Пати до 5 человек вместо 3",
  "×1.5 TC за каждый матч",
  "Ежедневный бонус 150 TC вместо 50",
  "Анимированная рамка, шеврон и баннер «Премиум»",
  "Свой цвет ника из 8 вариантов",
  "Значок PREMIUM в лобби, рейтинге и профиле",
  "Тикеты в поддержку рассматриваются первыми",
];
const TICKET_TOPICS = ["Игрок не зашёл в игру", "Неверный результат", "Читы или нарушение", "Баг в приложении", "Другое"];
const START_ELO = 1000;
const READY_SEC = 30;          // время на «Готов»
const VETO_TURN_SEC = 45;      // время на один бан, потом — случайный автобан
const STATS_WINDOW = 12 * 3600; // сколько после матча можно вписать K/D
const NICK_RE = /^[\p{L}\p{N}_\-.\[\]|★☆ ]{2,20}$/u;
const MONTHS = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"];

// ---------- helpers ----------
const level = elo => LEVELS.reduce((l, [lv, low]) => (elo >= low ? lv : l), 1);
const nextLevelAt = elo => (LEVELS.find(([, low]) => low > elo) || [])[1] ?? null;
const pick = arr => arr[Math.floor(Math.random() * arr.length)];
const shuffle = arr => { const a = arr.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json; charset=utf-8" } });
const now = () => Math.floor(Date.now() / 1000);
const seasonKey = (d = new Date()) => `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
const seasonName = key => { const [y, m] = key.split("-"); return `${MONTHS[+m - 1]} ${y}`; };
class ApiError extends Error {}
const leftText = until => { const s = until - now(); return s < 3600 ? `${Math.max(1, Math.ceil(s / 60))} мин` : s < 86400 ? `${Math.ceil(s / 3600)} ч` : `${Math.ceil(s / 86400)} дн.`; };

function combinations(arr, k, start = 0, cur = [], out = []) {
  if (cur.length === k) { out.push(cur.slice()); return out; }
  for (let i = start; i < arr.length; i++) { cur.push(arr[i]); combinations(arr, k, i + 1, cur, out); cur.pop(); }
  return out;
}

// Капитан 1 всегда в команде 1, капитан 2 — в команде 2, остальные делятся по ELO.
// Пати (party_id) всегда целиком в одной команде, если это возможно.
function balanceWithCaptains(players, cap1, cap2) {
  const c1 = players.find(p => p.tg_id === cap1), c2 = players.find(p => p.tg_id === cap2);
  const rest = shuffle(players.filter(p => p !== c1 && p !== c2));
  const total = players.reduce((s, p) => s + p.elo, 0);
  const groups = {};
  for (const p of players) if (p.party_id) (groups[p.party_id] ||= []).push(p.tg_id);
  const valid = team1 => Object.values(groups).every(g => g.every(id => team1.has(id)) || g.every(id => !team1.has(id)));
  let best = null, bestDiff = Infinity, anyBest = null, anyDiff = Infinity;
  for (const combo of combinations(rest, rest.length / 2)) {
    const diff0 = Math.abs(total - 2 * (c1.elo + combo.reduce((s, p) => s + p.elo, 0)));
    if (diff0 < anyDiff) { anyBest = combo; anyDiff = diff0; }
    if (!valid(new Set([cap1, ...combo.map(p => p.tg_id)]))) continue;
    const diff = Math.abs(total - 2 * (c1.elo + combo.reduce((s, p) => s + p.elo, 0)));
    if (diff < bestDiff) { best = combo; bestDiff = diff; }
  }
  best ||= anyBest;
  const team1 = new Set([cap1, ...best.map(p => p.tg_id)]);
  return Object.fromEntries(players.map(p => [p.tg_id, team1.has(p.tg_id) ? 1 : 2]));
}

function deltas(players, winner) {
  const avg = t => { const e = players.filter(p => p.team === t).map(p => p.elo_before); return e.reduce((a, b) => a + b, 0) / e.length; };
  const [w, l] = winner === 1 ? [avg(1), avg(2)] : [avg(2), avg(1)];
  const expected = 1 / (1 + 10 ** ((l - w) / 400));
  const gain = Math.max(5, Math.min(45, Math.round(K_FACTOR * (1 - expected))));
  return Object.fromEntries(players.map(p => {
    const g = gain * (p.calibrating ? CALIBRATION_MULT : 1);
    return [p.tg_id, p.team === winner ? g : -g];
  }));
}

async function hmac(key, data) {
  const k = await crypto.subtle.importKey("raw", typeof key === "string" ? new TextEncoder().encode(key) : key,
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(data)));
}
const hex = buf => [...buf].map(b => b.toString(16).padStart(2, "0")).join("");

async function checkInitData(initData, botToken) {
  const params = new URLSearchParams(initData);
  const hash = params.get("hash");
  params.delete("hash");
  const dcs = [...params.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([k, v]) => `${k}=${v}`).join("\n");
  const secret = await hmac("WebAppData", botToken);
  if (!hash || hex(await hmac(secret, dcs)) !== hash) throw new Error("bad hash");
  if (now() - Number(params.get("auth_date") || 0) > 7 * 86400) throw new Error("expired");
  return JSON.parse(params.get("user"));
}

// ---------- Worker entry ----------
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return new Response(INDEX_HTML, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-cache" } });
    }
    if (url.pathname.startsWith("/api/") || url.pathname === "/webhook" || url.pathname.startsWith("/avatar/") || url.pathname.startsWith("/ticketimg/") || url.pathname.startsWith("/shot/")) {
      return env.ARENA.get(env.ARENA.idFromName("main")).fetch(request);
    }
    return new Response("Not found", { status: 404 });
  },
};

// ---------- Durable Object ----------
export class Arena extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.env = env;
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS players (
      tg_id INTEGER PRIMARY KEY, tg_username TEXT, tg_name TEXT, nick TEXT NOT NULL, game_id TEXT,
      elo INTEGER NOT NULL DEFAULT 1000, wins INTEGER NOT NULL DEFAULT 0, losses INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS matches (
      id INTEGER PRIMARY KEY AUTOINCREMENT, mode TEXT NOT NULL, map TEXT NOT NULL, status TEXT NOT NULL,
      creator_id INTEGER NOT NULL, room TEXT, winner INTEGER, score TEXT,
      created_at INTEGER NOT NULL, started_at INTEGER, finished_at INTEGER)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS match_players (
      match_id INTEGER NOT NULL, tg_id INTEGER NOT NULL, team INTEGER, elo_before INTEGER, elo_delta INTEGER,
      joined_at REAL NOT NULL, PRIMARY KEY (match_id, tg_id))`);
    this.sql.exec("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS admins (tg_id INTEGER PRIMARY KEY)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS rep (match_id INTEGER NOT NULL, from_id INTEGER NOT NULL, to_id INTEGER NOT NULL, value INTEGER NOT NULL, PRIMARY KEY (match_id, from_id, to_id))");
    this.sql.exec("CREATE TABLE IF NOT EXISTS shots (match_id INTEGER PRIMARY KEY, data BLOB NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS payments (charge_id TEXT PRIMARY KEY, tg_id INTEGER NOT NULL, product TEXT NOT NULL, stars INTEGER NOT NULL, created INTEGER NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS parties (id INTEGER PRIMARY KEY AUTOINCREMENT, leader INTEGER NOT NULL, created INTEGER NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS party_invites (party_id INTEGER NOT NULL, to_id INTEGER NOT NULL, from_id INTEGER NOT NULL, created INTEGER NOT NULL, PRIMARY KEY (party_id, to_id))");
    this.sql.exec("CREATE TABLE IF NOT EXISTS inventory (tg_id INTEGER NOT NULL, item TEXT NOT NULL, created INTEGER NOT NULL, PRIMARY KEY (tg_id, item))");
    this.sql.exec(`CREATE TABLE IF NOT EXISTS tickets (id INTEGER PRIMARY KEY AUTOINCREMENT, tg_id INTEGER NOT NULL, topic TEXT NOT NULL,
      match_id INTEGER, target_id INTEGER, status TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS ticket_msgs (id INTEGER PRIMARY KEY AUTOINCREMENT, ticket_id INTEGER NOT NULL, from_id INTEGER NOT NULL,
      is_admin INTEGER NOT NULL, text TEXT NOT NULL, image BLOB, image_key TEXT, created INTEGER NOT NULL)`);
    // дружба: from_id отправил заявку to_id; status pending | accepted
    this.sql.exec("CREATE TABLE IF NOT EXISTS friends (from_id INTEGER NOT NULL, to_id INTEGER NOT NULL, status TEXT NOT NULL, created INTEGER NOT NULL, PRIMARY KEY (from_id, to_id))");
    this.sql.exec("CREATE TABLE IF NOT EXISTS avatars (tg_id INTEGER PRIMARY KEY, data BLOB NOT NULL, updated INTEGER NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS seasons (season TEXT NOT NULL, place INTEGER NOT NULL, tg_id INTEGER, nick TEXT, elo INTEGER, PRIMARY KEY (season, place))");
    for (const ddl of [
      "ALTER TABLE match_players ADD COLUMN calibrating INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE match_players ADD COLUMN ready INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE match_players ADD COLUMN kills INTEGER",
      "ALTER TABLE match_players ADD COLUMN deaths INTEGER",
      "ALTER TABLE matches ADD COLUMN lobby_no INTEGER",
      "ALTER TABLE matches ADD COLUMN captain1 INTEGER",
      "ALTER TABLE matches ADD COLUMN captain2 INTEGER",
      "ALTER TABLE matches ADD COLUMN bans TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE matches ADD COLUMN veto_deadline INTEGER",
      "ALTER TABLE matches ADD COLUMN ready_deadline INTEGER",
      "ALTER TABLE matches ADD COLUMN pending_winner INTEGER",
      "ALTER TABLE matches ADD COLUMN pending_score TEXT",
      "ALTER TABLE matches ADD COLUMN reported_by INTEGER",
      "ALTER TABLE matches ADD COLUMN mvp INTEGER",
      "ALTER TABLE players ADD COLUMN photo TEXT",
      "ALTER TABLE players ADD COLUMN banned_until INTEGER",
      "ALTER TABLE players ADD COLUMN badges TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE players ADD COLUMN tg_photo TEXT",
      "ALTER TABLE players ADD COLUMN custom_photo INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE players ADD COLUMN last_seen INTEGER",
      "ALTER TABLE match_players ADD COLUMN assists INTEGER",
      "ALTER TABLE match_players ADD COLUMN party_id INTEGER",
      "ALTER TABLE players ADD COLUMN coins INTEGER NOT NULL DEFAULT 200",
      "ALTER TABLE players ADD COLUMN premium_until INTEGER",
      "ALTER TABLE players ADD COLUMN frame TEXT",
      "ALTER TABLE players ADD COLUMN chevron TEXT",
      "ALTER TABLE players ADD COLUMN party_id INTEGER",
      "ALTER TABLE players ADD COLUMN banner TEXT",
      "ALTER TABLE players ADD COLUMN nick_color TEXT",
      "ALTER TABLE players ADD COLUMN daily_at INTEGER",
      "ALTER TABLE players ADD COLUMN offenses INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE players ADD COLUMN last_offense INTEGER",
      "ALTER TABLE matches ADD COLUMN shot_key TEXT",
    ]) { try { this.sql.exec(ddl); } catch {} }
    this.sql.exec("UPDATE matches SET status = 'cancelled' WHERE status = 'open' AND lobby_no IS NULL");

    this.maps = (env.MAPS || DEFAULT_MAPS).split(",").map(s => s.trim()).filter(Boolean);
    this.envAdmins = new Set((env.ADMIN_IDS || "").split(",").map(s => Number(s.trim())).filter(Boolean));
    this.lobbyCount = Math.max(1, Number(env.LOBBY_COUNT || 2));
    if (!this.setting("season")) this.setSetting("season", seasonKey());
    this.ensureLobbies();
  }

  q(query, ...b) { return this.sql.exec(query, ...b).toArray(); }
  one(query, ...b) { return this.q(query, ...b)[0] || null; }
  setting(k) { return this.one("SELECT value FROM settings WHERE key = ?", k)?.value ?? null; }
  setSetting(k, v) { this.sql.exec("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", k, String(v)); }

  isAdmin(id) { return this.envAdmins.has(id) || !!this.one("SELECT 1 AS x FROM admins WHERE tg_id = ?", id); }
  adminIds() { return [...new Set([...this.envAdmins, ...this.q("SELECT tg_id FROM admins").map(r => r.tg_id)])]; }

  ensureLobbies() {
    for (let no = 1; no <= this.lobbyCount; no++) {
      if (!this.one("SELECT id FROM matches WHERE status IN ('open','ready') AND lobby_no = ?", no)) {
        this.sql.exec("INSERT INTO matches (mode, map, status, creator_id, lobby_no, created_at) VALUES ('5x5', '', 'open', 0, ?, ?)", no, now());
      }
    }
  }

  // ----- seasons -----
  async checkSeason() {
    const cur = seasonKey(), stored = this.setting("season");
    if (stored === cur) return;
    const top = this.q(`SELECT tg_id, nick, elo, badges FROM players WHERE tg_id > 0 AND wins + losses >= ${CALIBRATION_GAMES} ORDER BY elo DESC, wins DESC LIMIT 3`);
    top.forEach((p, i) => {
      const badges = JSON.parse(p.badges || "[]");
      badges.push({ season: stored, place: i + 1 });
      this.sql.exec("UPDATE players SET badges = ? WHERE tg_id = ?", JSON.stringify(badges), p.tg_id);
      this.sql.exec("INSERT OR REPLACE INTO seasons (season, place, tg_id, nick, elo) VALUES (?, ?, ?, ?, ?)", stored, i + 1, p.tg_id, p.nick, p.elo);
    });
    // мягкий сброс: ELO сдвигается наполовину к 1000
    this.sql.exec(`UPDATE players SET elo = ${START_ELO} + CAST(ROUND((elo - ${START_ELO}) / 2.0) AS INTEGER)`);
    this.setSetting("season", cur);
    const medals = ["🥇", "🥈", "🥉"];
    if (top.length) {
      await this.notifyGroup(`🏆 <b>Сезон ${seasonName(stored)} завершён!</b>\n\n` +
        top.map((p, i) => `${medals[i]} ${esc(p.nick)} — ${p.elo} ELO`).join("\n") +
        `\n\nСтартует сезон <b>${seasonName(cur)}</b>. ELO у всех сдвинуто к 1000 наполовину.`);
      await Promise.all(top.map((p, i) => this.send(p.tg_id, `${medals[i]} Ты занял ${i + 1} место в сезоне ${seasonName(stored)}! Значок сезона уже в профиле.`)));
    }
  }

  // ----- data -----
  player(id) { return this.one("SELECT * FROM players WHERE tg_id = ?", id); }
  isCalibrated(p) { return p.wins + p.losses >= CALIBRATION_GAMES; }
  rankOf(id) {
    const p = this.player(id);
    if (!p || !this.isCalibrated(p)) return null;
    return this.one(`SELECT COUNT(*) AS n FROM players WHERE elo > ? AND tg_id > 0 AND wins + losses >= ${CALIBRATION_GAMES}`, p.elo).n + 1;
  }
  match(id) {
    const m = this.one("SELECT * FROM matches WHERE id = ?", id);
    if (!m) return null;
    m.bans = JSON.parse(m.bans || "[]");
    m.players = this.q(`SELECT mp.tg_id, mp.team, mp.elo_before, mp.elo_delta, mp.calibrating, mp.ready, mp.kills, mp.deaths, mp.assists,
        mp.party_id, p.nick, p.elo, p.game_id, p.tg_username, p.photo, p.frame, p.chevron, p.banner, p.nick_color, p.premium_until, p.wins + p.losses AS games
      FROM match_players mp JOIN players p ON p.tg_id = mp.tg_id WHERE mp.match_id = ? ORDER BY mp.joined_at`, id);
    return m;
  }
  activeMatchOf(id) {
    const r = this.one(`SELECT m.id FROM matches m JOIN match_players mp ON mp.match_id = m.id
      WHERE mp.tg_id = ? AND m.status IN ('open','ready','veto','live','pending')`, id);
    return r ? r.id : null;
  }
  vetoTurn(m) { return m.bans.length % 2 === 0 ? m.captain1 : m.captain2; }
  nick(m, id) { return m.players.find(p => p.tg_id === id)?.nick ?? "?"; }

  publicPlayer(p) {
    const games = p.wins + p.losses, calibrated = games >= CALIBRATION_GAMES;
    const { badges, ...rest } = p;
    return {
      ...rest, games, calibrated, calib_played: Math.min(games, CALIBRATION_GAMES), calib_total: CALIBRATION_GAMES,
      elo: calibrated ? p.elo : null, level: calibrated ? level(p.elo) : null, next_level_at: calibrated ? nextLevelAt(p.elo) : null,
      badges: JSON.parse(badges || "[]"), banned: (p.banned_until || 0) > now(),
      online: now() - (p.last_seen || 0) < 120,
      premium: (p.premium_until || 0) > now(),
      ...((p.premium_until || 0) > now() ? {} : { nick_color: null,
        frame: /_prem$/.test(p.frame || "") ? null : p.frame, chevron: /_prem$/.test(p.chevron || "") ? null : p.chevron, banner: /_prem$/.test(p.banner || "") ? null : p.banner }),
    };
  }
  publicMatch(m) {
    const out = {
      id: m.id, lobby_no: m.lobby_no, status: m.status, mode: m.mode, map: m.map, room: m.room, score: m.score, winner: m.winner,
      size: LOBBY_SIZE, captain1: m.captain1, captain2: m.captain2, host_id: m.creator_id || null, mvp: m.mvp,
      bans: m.bans, remaining: this.maps.filter(x => !m.bans.some(b => b.map === x)),
      veto_turn: m.status === "veto" ? this.vetoTurn(m) : null,
      veto_left: m.status === "veto" && m.veto_deadline ? Math.max(0, m.veto_deadline - now()) : null,
      ready_left: m.status === "ready" && m.ready_deadline ? Math.max(0, m.ready_deadline - now()) : null,
      pending_winner: m.pending_winner, pending_score: m.pending_score, reported_by: m.reported_by,
      finished_at: m.finished_at, team_avg: {}, shot: m.shot_key ? `/shot/${m.id}/${m.shot_key}` : null,
    };
    for (const t of [1, 2]) {
      const ps = m.players.filter(p => p.team === t);
      if (ps.length) out.team_avg[t] = Math.round(ps.reduce((s, p) => s + (p.elo_before ?? p.elo), 0) / ps.length);
    }
    out.players = m.players.map(p => {
      const calibrated = p.games >= CALIBRATION_GAMES;
      return { tg_id: p.tg_id, team: p.team, nick: p.nick, game_id: p.game_id, photo: p.photo, ready: !!p.ready, party_id: p.party_id,
        ...(((pr) => ({ premium: pr, nick_color: pr ? p.nick_color : null,
          frame: !pr && /_prem$/.test(p.frame || "") ? null : p.frame, chevron: !pr && /_prem$/.test(p.chevron || "") ? null : p.chevron,
          banner: !pr && /_prem$/.test(p.banner || "") ? null : p.banner }))((p.premium_until || 0) > now())),
        kills: p.kills, deaths: p.deaths, assists: p.assists, calibrating: !!p.calibrating,
        elo_delta: m.status === "finished" && !p.calibrating ? p.elo_delta : null,
        calibrated, calib_played: Math.min(p.games, CALIBRATION_GAMES), level: calibrated ? level(p.elo) : null, elo: calibrated ? p.elo : null };
    });
    const host = m.players.find(p => p.tg_id === m.creator_id);
    out.host_nick = host?.nick ?? null;
    out.host_game_id = host?.game_id ?? null;
    return out;
  }

  // профиль: K/D, карты, серии, достижения
  profile(id, viewer) {
    const p = this.player(id);
    const rows = this.q(`SELECT m.id, m.mode, m.map, m.score, m.winner, m.finished_at, m.mvp, mp.team, mp.elo_before, mp.elo_delta, mp.calibrating, mp.kills, mp.deaths, mp.assists
      FROM match_players mp JOIN matches m ON m.id = mp.match_id
      WHERE mp.tg_id = ? AND m.status = 'finished' ORDER BY m.finished_at DESC, m.id DESC`, id);
    const calibrated = this.isCalibrated(p);
    const history = rows.slice(0, 100).map(h => ({
      ...h, elo_delta: calibrated ? h.elo_delta : null, is_mvp: h.mvp === id,
      can_stats: h.kills == null && now() - h.finished_at < STATS_WINDOW,
    }));
    const withStats = rows.filter(r => r.kills != null);
    const kills = withStats.reduce((s, r) => s + r.kills, 0), deaths = withStats.reduce((s, r) => s + r.deaths, 0);
    const assists = withStats.reduce((s, r) => s + (r.assists || 0), 0);
    // история ELO: точки после каждого матча вне калибровки
    const eloHistory = calibrated ? rows.slice().reverse().filter(r => !r.calibrating && r.elo_before != null)
      .map(r => ({ t: r.finished_at, elo: r.elo_before + r.elo_delta, d: r.elo_delta })).slice(-40) : [];
    if (eloHistory.length && eloHistory[eloHistory.length - 1].elo !== p.elo) eloHistory.push({ t: now(), elo: p.elo, d: p.elo - eloHistory[eloHistory.length - 1].elo });
    const best = withStats.reduce((b, r) => (!b || r.kills > b.kills ? r : b), null);
    const mvps = rows.filter(r => r.mvp === id).length;
    // серии
    const chrono = rows.slice().reverse();
    let bestStreak = 0, run = 0;
    for (const r of chrono) { run = r.team === r.winner ? run + 1 : 0; bestStreak = Math.max(bestStreak, run); }
    let cur = 0, curWin = null;
    for (const r of rows) { const w = r.team === r.winner; if (curWin === null) curWin = w; if (w !== curWin) break; cur++; }
    // карты
    const mapsStat = this.maps.map(map => {
      const ms = rows.filter(r => r.map === map), w = ms.filter(r => r.team === r.winner).length;
      return { map, games: ms.length, wins: w, wr: ms.length ? Math.round(w * 100 / ms.length) : null };
    });
    const games = rows.length, wins = rows.filter(r => r.team === r.winner).length;
    const maxMapWins = Math.max(0, ...mapsStat.map(m => m.wins));
    const badges = JSON.parse(p.badges || "[]");
    const ach = [
      ["first_win", "🩸", "Первая кровь", "Выиграть первый матч", wins >= 1],
      ["calibrated", "🎖", "Откалиброван", `Сыграть ${CALIBRATION_GAMES} матчей`, calibrated],
      ["streak3", "🔥", "В ударе", "3 победы подряд", bestStreak >= 3],
      ["streak5", "⚡", "Неудержимый", "5 побед подряд", bestStreak >= 5],
      ["streak10", "👑", "Легенда", "10 побед подряд", bestStreak >= 10],
      ["games50", "🎮", "Ветеран", "Сыграть 50 матчей", games >= 50],
      ["games100", "💯", "Сотка", "Сыграть 100 матчей", games >= 100],
      ["mvp1", "⭐", "MVP", "Стать MVP матча", mvps >= 1],
      ["mvp10", "🌟", "Звезда", "10 раз стать MVP", mvps >= 10],
      ["kills30", "💀", "Мясник", "30+ убийств за матч", (best?.kills || 0) >= 30],
      ["map10", "🗺", "Хозяин карты", "10 побед на одной карте", maxMapWins >= 10],
      ["lvl10", "🔴", "Десятка", "Дойти до 10 уровня", calibrated && level(p.elo) >= 10],
      ["season", "🏆", "Призёр сезона", "Войти в топ-3 сезона", badges.length > 0],
    ].map(([id_, icon, title, desc, got]) => ({ id: id_, icon, title, desc, got }));
    return {
      player: this.publicPlayer(p), rank: this.rankOf(id), history,
      stats: {
        kd: withStats.length ? +(kills / Math.max(1, deaths)).toFixed(2) : null,
        kills, deaths, assists, stat_games: withStats.length, wins, losses: games - wins,
        avg_kills: withStats.length ? +(kills / withStats.length).toFixed(1) : null,
        best_kills: best?.kills ?? null, best_map: best?.map ?? null, mvps,
        streak: cur, streak_win: curWin, best_streak: bestStreak,
      },
      maps: mapsStat, achievements: ach, elo_history: eloHistory,
      reputation: this.one("SELECT COALESCE(SUM(value = 1), 0) AS up, COALESCE(SUM(value = -1), 0) AS down FROM rep WHERE to_id = ?", id),
      offenses: p.last_offense && now() - p.last_offense < BAN_RESET_DAYS * 86400 ? p.offenses : 0,
      friend: viewer && viewer !== id ? this.friendState(viewer, id) : null,
      calibration: {
        wins: rows.filter(r => r.calibrating && r.team === r.winner).length,
        losses: rows.filter(r => r.calibrating && r.team !== r.winner).length,
        with_stats: rows.filter(r => r.calibrating && r.kills != null).length,
      },
    };
  }

  // ----- party -----
  isPremium(p) { return (p?.premium_until || 0) > now(); }
  partyOf(id) {
    const p = this.player(id);
    if (!p?.party_id) return null;
    const party = this.one("SELECT * FROM parties WHERE id = ?", p.party_id);
    if (!party) { this.sql.exec("UPDATE players SET party_id = NULL WHERE tg_id = ?", id); return null; }
    const members = this.q("SELECT tg_id FROM players WHERE party_id = ? ORDER BY tg_id = ? DESC", party.id, party.leader).map(r => r.tg_id);
    return { ...party, members, max: this.isPremium(this.player(party.leader)) ? PARTY_MAX_PREMIUM : PARTY_MAX };
  }
  leaveParty(id) {
    const party = this.partyOf(id);
    if (!party) return;
    this.sql.exec("UPDATE players SET party_id = NULL WHERE tg_id = ?", id);
    const rest = party.members.filter(x => x !== id);
    if (rest.length <= 1) {
      this.sql.exec("UPDATE players SET party_id = NULL WHERE party_id = ?", party.id);
      this.sql.exec("DELETE FROM party_invites WHERE party_id = ?", party.id);
      this.sql.exec("DELETE FROM parties WHERE id = ?", party.id);
    } else if (party.leader === id) this.sql.exec("UPDATE parties SET leader = ? WHERE id = ?", rest[0], party.id);
  }
  addCoins(id, amount) { this.sql.exec("UPDATE players SET coins = coins + ? WHERE tg_id = ?", amount, id); }
  decodeJpeg(data, max = AVATAR_MAX) {
    const m = /^data:image\/jpeg;base64,([A-Za-z0-9+/=]+)$/.exec(String(data || ""));
    if (!m) throw new ApiError("Нужна картинка JPEG");
    const bin = Uint8Array.from(atob(m[1]), c => c.charCodeAt(0));
    if (bin.length > max) throw new ApiError("Картинка слишком большая");
    if (bin[0] !== 0xff || bin[1] !== 0xd8) throw new ApiError("Это не JPEG");
    return bin;
  }
  // зайти в лобби: одному или всей пати (заходит лидер)
  joinLobby(m, uid) {
    const party = this.partyOf(uid);
    if (party && party.leader !== uid) throw new ApiError("В лобби пати заводит лидер");
    const group = party ? party.members : [uid];
    const ids = m.players.map(p => p.tg_id);
    if (ids.length + group.length > LOBBY_SIZE) throw new ApiError(party ? `В лобби нет ${group.length} свободных мест` : "Лобби заполнено");
    for (const id of group) {
      const p = this.player(id);
      if ((p.banned_until || 0) > now()) throw new ApiError(id === uid ? `Ты забанен ещё на ${leftText(p.banned_until)}` : `${p.nick} забанен ещё на ${leftText(p.banned_until)}`);
      if (this.activeMatchOf(id)) throw new ApiError(id === uid ? "Ты уже в другом лобби или матче" : `${p.nick} уже в другом лобби`);
    }
    const t = Date.now() / 1000;
    group.forEach((id, i) => this.sql.exec("INSERT OR IGNORE INTO match_players (match_id, tg_id, joined_at, party_id) VALUES (?, ?, ?, ?)", m.id, id, t + i / 1000, party?.id ?? null));
    return { added: group, full: ids.length + group.length === LOBBY_SIZE };
  }

  // ----- friends -----
  friendRow(a, b) { return this.one("SELECT * FROM friends WHERE (from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?)", a, b, b, a); }
  friendState(me, other) {
    const r = this.friendRow(me, other);
    if (!r) return "none";
    if (r.status === "accepted") return "friends";
    return r.from_id === me ? "outgoing" : "incoming";
  }

  partyView(uid) {
    const party = this.partyOf(uid);
    const invites = this.q("SELECT pi.party_id, pi.from_id, p.nick FROM party_invites pi JOIN players p ON p.tg_id = pi.from_id WHERE pi.to_id = ?", uid);
    if (!party) return { party: null, invites };
    const members = party.members.map(id => { const p = this.publicPlayer(this.player(id)); return { tg_id: id, nick: p.nick, photo: p.photo, level: p.level, frame: p.frame, chevron: p.chevron, nick_color: p.nick_color, premium: p.premium, online: p.online }; });
    const sent = this.q("SELECT to_id FROM party_invites WHERE party_id = ?", party.id).map(r => r.to_id);
    return { party: { id: party.id, leader: party.leader, max: party.max, members, sent }, invites };
  }

  // ----- telegram -----
  async tg(method, params) {
    const r = await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/${method}`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(params),
    });
    return r.json();
  }
  async send(chatId, text, markup) {
    if (chatId < 0 && chatId > -1000) return; // тестовые боты
    try {
      const r = await this.tg("sendMessage", { chat_id: chatId, text, parse_mode: "HTML", disable_web_page_preview: true, ...(markup ? { reply_markup: markup } : {}) });
      if (!r.ok) console.log("send failed", chatId, r.description);
    } catch (e) { console.log("send error", chatId, e.message); }
  }
  notify(ids, text, markup) { return Promise.all(ids.map(id => this.send(id, text, markup))); }
  groupId() { return Number(this.setting("group_chat_id") || this.env.NOTIFY_CHAT_ID || 0); }
  notifyGroup(text) {
    const chat = this.groupId();
    if (!chat) return;
    const u = this.env.BOT_USERNAME;
    return this.send(chat, text, u ? { inline_keyboard: [[{ text: "🎮 Играть", url: `https://t.me/${u}?start=play` }]] } : null);
  }
  appButton(text = "🎮 Открыть приложение") {
    const url = this.origin || this.setting("origin");
    return url ? { inline_keyboard: [[{ text, web_app: { url } }]] } : null;
  }
  teamsText(m) {
    return [1, 2].map(t => {
      const ps = m.players.filter(p => p.team === t);
      const avg = ps.length ? Math.round(ps.reduce((s, p) => s + p.elo, 0) / ps.length) : 0;
      const cap = t === 1 ? m.captain1 : m.captain2;
      return [`<b>Команда ${t}</b> (ср. ${avg} ELO)`, ...ps.map(p => `  • ${esc(p.nick)}${p.tg_id === cap ? " (C)" : ""} — ${
        p.games >= CALIBRATION_GAMES ? `${level(p.elo)} lvl` : `калибровка ${p.games}/${CALIBRATION_GAMES}`}`)].join("\n");
    }).join("\n");
  }
  hostText(m) {
    const h = m.players.find(p => p.tg_id === m.creator_id);
    return h ? `🎮 Лобби в игре создаёт: <b>${esc(h.nick)}</b>${h.game_id ? ` (ID <code>${esc(h.game_id)}</code>)` : ""}` : "";
  }

  // ----- ready check -----
  async startReady(mid) {
    this.sql.exec("UPDATE match_players SET ready = CASE WHEN tg_id < 0 THEN 1 ELSE 0 END WHERE match_id = ?", mid);
    this.sql.exec("UPDATE matches SET status = 'ready', ready_deadline = ? WHERE id = ?", now() + READY_SEC, mid);
    await this.scheduleAlarm();
    const m = this.match(mid);
    await this.notify(m.players.map(p => p.tg_id), `🔔 <b>Лобби ${m.lobby_no} собрано!</b>\nПодтверди готовность за ${READY_SEC} сек, иначе вылетишь из лобби.`,
      this.appButton("✅ Я готов"));
  }

  async readyTimeout(mid) {
    const m = this.match(mid);
    const notReady = m.players.filter(p => !p.ready);
    const banMin = {};
    for (const p of notReady) {
      this.sql.exec("DELETE FROM match_players WHERE match_id = ? AND tg_id = ?", mid, p.tg_id);
      banMin[p.tg_id] = this.punish(p.tg_id);
    }
    this.sql.exec("UPDATE matches SET status = 'open', ready_deadline = NULL WHERE id = ?", mid);
    this.sql.exec("UPDATE match_players SET ready = 0 WHERE match_id = ?", mid);
    await Promise.all(notReady.map(p => this.send(p.tg_id, `⏰ Ты не подтвердил готовность — тебя убрали из лобби ${m.lobby_no}.\n⛔ Бан на ${banMin[p.tg_id]} мин. Каждое следующее нарушение за ${BAN_RESET_DAYS} дней удваивает срок.`)));
    await this.notify(m.players.filter(p => p.ready).map(p => p.tg_id),
      `😕 Не все подтвердили готовность (${notReady.map(p => esc(p.nick)).join(", ")}). Лобби ${m.lobby_no} ждёт ещё ${notReady.length} игроков.`);
  }

  // нарастающий бан: 10, 20, 40, 80… минут (до суток); сбрасывается через 7 дней без нарушений
  punish(id) {
    const p = this.player(id);
    const n = (p.last_offense && now() - p.last_offense < BAN_RESET_DAYS * 86400 ? p.offenses : 0) + 1;
    const min = Math.min(BAN_MAX_MIN, BAN_BASE_MIN * 2 ** (n - 1));
    this.sql.exec("UPDATE players SET offenses = ?, last_offense = ?, banned_until = MAX(COALESCE(banned_until, 0), ?) WHERE tg_id = ?", n, now(), now() + min * 60, id);
    return min;
  }

  // ----- veto -----
  async startVeto(mid) {
    const m = this.match(mid);
    const order = shuffle(m.players);
    const cap1 = order[0].tg_id;
    const cap2 = (order.find(p => p.tg_id !== cap1 && (!p.party_id || p.party_id !== order[0].party_id)) || order[1]).tg_id;
    const host = pick(m.players).tg_id;
    const teams = balanceWithCaptains(m.players, cap1, cap2);
    for (const [id, team] of Object.entries(teams)) {
      this.sql.exec(`UPDATE match_players SET team = ?, elo_before = (SELECT elo FROM players WHERE tg_id = ?),
        calibrating = (SELECT wins + losses < ${CALIBRATION_GAMES} FROM players WHERE tg_id = ?)
        WHERE match_id = ? AND tg_id = ?`, team, +id, +id, mid, +id);
    }
    this.sql.exec(`UPDATE matches SET status = 'veto', captain1 = ?, captain2 = ?, creator_id = ?, bans = '[]', veto_deadline = ?, ready_deadline = NULL
      WHERE id = ?`, cap1, cap2, host, now() + VETO_TURN_SEC, mid);
    this.ensureLobbies();
    await this.scheduleAlarm();
    const m2 = this.match(mid);
    await this.notify(m2.players.map(p => p.tg_id),
      `✅ <b>Все готовы!</b> Матч #${mid}\n\nКапитаны: <b>${esc(this.nick(m2, cap1))}</b> vs <b>${esc(this.nick(m2, cap2))}</b>\n` +
      `Капитаны по очереди банят карты (${this.maps.length - 1} банов), последняя карта играется.\n\n${this.teamsText(m2)}`, this.appButton("🗺 Открыть вето"));
    await this.send(cap1, `🗺 Ты капитан! Твой ход — забань карту (${VETO_TURN_SEC} сек).`, this.appButton("Забанить карту"));
    await this.botVeto(mid);
    await this.notifyGroup(`🔔 Лобби ${m2.lobby_no} собрано (матч #${mid}). Капитаны: ${esc(this.nick(m2, cap1))} vs ${esc(this.nick(m2, cap2))}`);
  }

  async ban(mid, byId, map, auto = false) {
    const m = this.match(mid);
    const remaining = this.maps.filter(x => !m.bans.some(b => b.map === x));
    if (!remaining.includes(map)) throw new ApiError("Эта карта уже забанена");
    m.bans.push({ map, by: byId, auto });
    const left = remaining.filter(x => x !== map);
    if (left.length === 1) {
      this.sql.exec(`UPDATE matches SET bans = ?, map = ?, status = 'live', started_at = ?, veto_deadline = NULL WHERE id = ?`,
        JSON.stringify(m.bans), left[0], now(), mid);
      const m2 = this.match(mid);
      await this.notify(m2.players.map(p => p.tg_id), `🔥 <b>Матч #${mid}: играем на ${esc(left[0])}!</b>\n${this.hostText(m2)}\n\n${this.teamsText(m2)}`);
      await this.send(m2.creator_id, `👑 <b>Ты создаёшь лобби в игре.</b> Создай комнату на ${esc(left[0])} и впиши её код в приложении — все увидят.`,
        this.appButton("🔑 Вписать код комнаты"));
    } else {
      this.sql.exec("UPDATE matches SET bans = ?, veto_deadline = ? WHERE id = ?", JSON.stringify(m.bans), now() + VETO_TURN_SEC, mid);
      await this.send(this.vetoTurn(m), `🗺 Матч #${mid}: ${esc(this.nick(m, byId))} забанил ${esc(map)}${auto ? " (авто)" : ""}. Твой ход — бань (${VETO_TURN_SEC} сек).`,
        this.appButton("Забанить карту"));
    }
    await this.scheduleAlarm();
    if (this.vetoTurn(this.match(mid)) < 0) await this.botVeto(mid);
  }

  // если сейчас банит бот-капитан — банит сам, сразу
  async botVeto(mid) {
    for (let i = 0; i < 10; i++) {
      const m = this.match(mid);
      if (m.status !== "veto" || this.vetoTurn(m) >= 0) return;
      const left = this.maps.filter(x => !m.bans.some(b => b.map === x));
      await this.ban(mid, this.vetoTurn(m), pick(left), true);
    }
  }

  async scheduleAlarm() {
    const r = this.one(`SELECT MIN(t) AS t FROM (
      SELECT veto_deadline AS t FROM matches WHERE status = 'veto' AND veto_deadline IS NOT NULL
      UNION ALL SELECT ready_deadline AS t FROM matches WHERE status = 'ready' AND ready_deadline IS NOT NULL)`);
    if (r?.t) await this.ctx.storage.setAlarm(r.t * 1000);
    else await this.ctx.storage.deleteAlarm();
  }

  async alarm() {
    for (const r of this.q("SELECT id FROM matches WHERE status = 'ready' AND ready_deadline <= ?", now())) {
      try { await this.readyTimeout(r.id); } catch (e) { console.log("ready timeout", e.message); }
    }
    for (const r of this.q("SELECT id FROM matches WHERE status = 'veto' AND veto_deadline <= ?", now())) {
      const m = this.match(r.id);
      const remaining = this.maps.filter(x => !m.bans.some(b => b.map === x));
      try { await this.ban(m.id, this.vetoTurn(m), pick(remaining), true); } catch (e) { console.log("autoban", e.message); }
    }
    await this.scheduleAlarm();
  }

  // ----- calibration -----
  // Итог калибровки: ELO, набранное за 10 матчей (с удвоенным K и учётом силы соперников),
  // плюс бонус/штраф за K/D (если вписан хотя бы в 3 матчах), в пределах 1–8 уровня.
  placement(id) {
    const rows = this.q(`SELECT mp.kills, mp.deaths, mp.team, m.winner FROM match_players mp JOIN matches m ON m.id = mp.match_id
      WHERE mp.tg_id = ? AND mp.calibrating = 1 AND m.status = 'finished'`, id);
    const st = rows.filter(r => r.kills != null);
    const kills = st.reduce((s, r) => s + r.kills, 0), deaths = st.reduce((s, r) => s + r.deaths, 0);
    const kd = st.length >= 3 ? kills / Math.max(1, deaths) : null;
    const bonus = kd == null ? 0 : Math.max(-PLACEMENT_KD_MAX, Math.min(PLACEMENT_KD_MAX, Math.round((kd - 1) * 100)));
    const p = this.player(id);
    const elo = Math.max(PLACEMENT_MIN, Math.min(PLACEMENT_MAX, p.elo + bonus));
    this.sql.exec("UPDATE players SET elo = ? WHERE tg_id = ?", elo, id);
    return { elo, kd: kd == null ? null : +kd.toFixed(2), kd_bonus: elo - p.elo, wins: rows.filter(r => r.team === r.winner).length, losses: rows.filter(r => r.team !== r.winner).length };
  }

  // ----- result -----
  computeMvp(mid) {
    const r = this.one("SELECT tg_id FROM match_players WHERE match_id = ? AND kills IS NOT NULL ORDER BY kills DESC, deaths ASC LIMIT 1", mid);
    this.sql.exec("UPDATE matches SET mvp = ? WHERE id = ?", r?.tg_id ?? null, mid);
    return r?.tg_id ?? null;
  }

  async sendPhoto(chatId, bytes, caption, markup) {
    if (chatId < 0) return;
    try {
      const fd = new FormData();
      fd.append("chat_id", String(chatId)); fd.append("caption", caption); fd.append("parse_mode", "HTML");
      if (markup) fd.append("reply_markup", JSON.stringify(markup));
      fd.append("photo", new Blob([bytes], { type: "image/jpeg" }), "result.jpg");
      const r = await (await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/sendPhoto`, { method: "POST", body: fd })).json();
      if (!r.ok) console.log("photo failed", r.description);
    } catch (e) { console.log("photo error", e.message); }
  }

  async reportResult(m, uid, winner, score, shot) {
    const admins = this.adminIds();
    if (shot) {
      this.sql.exec("INSERT OR REPLACE INTO shots (match_id, data) VALUES (?, ?)", m.id, shot.buffer);
      this.sql.exec("UPDATE matches SET shot_key = ? WHERE id = ?", crypto.randomUUID(), m.id);
    }
    if (!admins.length || this.isAdmin(uid)) return this.applyResult(m.id, winner, score);
    this.sql.exec("UPDATE matches SET status = 'pending', pending_winner = ?, pending_score = ?, reported_by = ? WHERE id = ?", winner, score, uid, m.id);
    const text = `📝 <b>Результат на модерации</b> · матч #${m.id} (${esc(m.map)})\n` +
      `${esc(this.nick(m, uid))}: победила <b>Команда ${winner}</b>${score ? ` ${esc(score)}` : ""}\n\n${this.teamsText(m)}`;
    const kb = { inline_keyboard: [[{ text: "✅ Принять", callback_data: `ok:${m.id}` }, { text: "❌ Отклонить", callback_data: `no:${m.id}` }]] };
    if (shot) await Promise.all(admins.map(a => this.sendPhoto(a, shot, text.slice(0, 1000), kb)));
    else await this.notify(admins, text, kb);
    await this.notify(m.players.map(p => p.tg_id).filter(id => id !== uid),
      `📝 Матч #${m.id}: результат отправлен админу на проверку (победила Команда ${winner}${score ? ` ${esc(score)}` : ""}).\nНе забудь вписать свои убийства и смерти в приложении.`,
      this.appButton("📊 Вписать K/D"));
  }

  async rejectResult(mid, byId) {
    const m = this.match(mid);
    if (m?.status !== "pending") throw new ApiError("Нет результата на проверке");
    this.sql.exec("UPDATE matches SET status = 'live', pending_winner = NULL, pending_score = NULL, reported_by = NULL WHERE id = ?", mid);
    this.sql.exec("DELETE FROM shots WHERE match_id = ?", mid);
    this.sql.exec("UPDATE matches SET shot_key = NULL WHERE id = ?", mid);
    await this.notify(m.players.map(p => p.tg_id), `❌ Админ отклонил результат матча #${mid}. Отправьте правильный результат со скриншотом ещё раз.`, this.appButton());
  }

  async applyResult(mid, winner, score) {
    const m = this.match(mid);
    if (!["live", "pending"].includes(m.status)) throw new ApiError("Матч не ждёт результата");
    const d = deltas(m.players, winner);
    for (const p of m.players) {
      const won = p.team === winner;
      this.sql.exec("UPDATE match_players SET elo_delta = ? WHERE match_id = ? AND tg_id = ?", d[p.tg_id], mid, p.tg_id);
      this.sql.exec(`UPDATE players SET elo = MAX(100, elo + ?), ${won ? "wins = wins + 1" : "losses = losses + 1"} WHERE tg_id = ?`, d[p.tg_id], p.tg_id);
    }
    this.sql.exec(`UPDATE matches SET status = 'finished', winner = ?, score = ?, finished_at = ?, pending_winner = NULL, pending_score = NULL
      WHERE id = ?`, winner, score || "", now(), mid);
    for (const p of m.players.filter(p => p.tg_id < 0 && p.kills == null))
      this.sql.exec("UPDATE match_players SET kills = ?, deaths = ?, assists = ? WHERE match_id = ? AND tg_id = ?",
        6 + Math.floor(Math.random() * 20), 8 + Math.floor(Math.random() * 12), Math.floor(Math.random() * 6), mid, p.tg_id);
    const mvp = this.computeMvp(mid);
    const earned = {};
    for (const p of m.players) {
      const pl = this.player(p.tg_id);
      let c = (p.team === winner ? COINS.win : COINS.loss) + (p.tg_id === mvp ? COINS.mvp : 0);
      if (this.isPremium(pl)) c = Math.round(c * PREMIUM_COIN_MULT);
      this.addCoins(p.tg_id, c); earned[p.tg_id] = c;
    }
    const placed = {};
    for (const p of m.players.filter(p => p.calibrating)) {
      const pl = this.player(p.tg_id);
      if (pl.wins + pl.losses === CALIBRATION_GAMES) placed[p.tg_id] = this.placement(p.tg_id);
    }
    const m2 = this.match(mid);
    await Promise.all(m2.players.map(p => {
      const won = p.team === winner;
      let text = `${won ? "🏆 Победа" : "💀 Поражение"} в матче #${mid} (${esc(m2.map)} ${score || ""})\n`;
      if (p.games < CALIBRATION_GAMES) text += `🎯 Калибровка: ${p.games}/${CALIBRATION_GAMES}`;
      else if (placed[p.tg_id]) {
        const pl = placed[p.tg_id];
        text += `🎖 <b>Калибровка пройдена!</b>\n${pl.wins}W · ${pl.losses}L` +
          (pl.kd != null ? ` · K/D ${pl.kd} (${pl.kd_bonus >= 0 ? "+" : ""}${pl.kd_bonus})` : "") +
          `\nТвой уровень: <b>${level(p.elo)}</b> · ${p.elo} ELO`;
      }
      else {
        const up = level(p.elo) > level(p.elo_before), down = level(p.elo) < level(p.elo_before);
        text += `ELO: ${p.elo_before} → <b>${p.elo}</b> (${p.elo_delta >= 0 ? "+" : ""}${p.elo_delta})` +
          (up ? `\n🎉 Новый уровень: ${level(p.elo)}!` : down ? `\n📉 Уровень понижен до ${level(p.elo)}` : "");
      }
      text += `\n🪙 +${earned[p.tg_id]} TC`;
      if (p.kills == null) text += "\n\n📊 Впиши свои убийства/смерти — так считается MVP и K/D.";
      return this.send(p.tg_id, text, p.kills == null ? this.appButton("📊 Вписать K/D") : null);
    }));
    await this.postMatchCard(m2, mvp);
  }

  async postMatchCard(m, mvp) {
    if (!this.groupId()) return;
    const team = t => {
      const ps = m.players.filter(p => p.team === t);
      const cap = t === 1 ? m.captain1 : m.captain2;
      return `${t === m.winner ? "🏆" : "💀"} <b>Команда ${t}${t === m.winner ? " — ПОБЕДА" : ""}</b>\n` + ps.map(p =>
        `${p.tg_id === mvp ? "⭐" : "▫️"} ${esc(p.nick)}${p.tg_id === cap ? " (C)" : ""}` +
        `${p.kills != null ? ` · ${p.kills}/${p.deaths}` : ""} · ${p.calibrating ? "калибровка" : `${p.elo_delta >= 0 ? "+" : ""}${p.elo_delta}`}`).join("\n");
    };
    const mvpP = m.players.find(p => p.tg_id === mvp);
    await this.notifyGroup(`🏁 <b>Матч #${m.id} · ${esc(m.map)}${m.score ? ` · ${esc(m.score)}` : ""}</b>\n\n${team(1)}\n\n${team(2)}` +
      (mvpP ? `\n\n⭐ <b>MVP: ${esc(mvpP.nick)}</b> — ${mvpP.kills} убийств` : ""));
  }

  // ----- http -----
  async fetch(request) {
    const url = new URL(request.url);
    this.origin = url.origin;
    if (this.setting("origin") !== url.origin) this.setSetting("origin", url.origin);
    await this.checkSeason();
    if (url.pathname === "/webhook") return this.webhook(request);
    if (url.pathname.startsWith("/shot/")) {
      const [, , id, key] = url.pathname.split("/");
      const r = this.one("SELECT s.data FROM shots s JOIN matches m ON m.id = s.match_id WHERE m.id = ? AND m.shot_key = ?", Number(id), String(key));
      if (!r?.data) return new Response("Not found", { status: 404 });
      return new Response(r.data, { headers: { "content-type": "image/jpeg", "cache-control": "private, max-age=86400" } });
    }
    if (url.pathname.startsWith("/ticketimg/")) {
      const [, , id, key] = url.pathname.split("/");
      const r = this.one("SELECT image FROM ticket_msgs WHERE id = ? AND image_key = ?", Number(id), String(key));
      if (!r?.image) return new Response("Not found", { status: 404 });
      return new Response(r.image, { headers: { "content-type": "image/jpeg", "cache-control": "private, max-age=86400" } });
    }
    if (url.pathname.startsWith("/avatar/")) {
      const r = this.one("SELECT data FROM avatars WHERE tg_id = ?", Number(url.pathname.split("/")[2]));
      if (!r) return new Response("Not found", { status: 404 });
      return new Response(r.data, { headers: { "content-type": "image/jpeg", "cache-control": "public, max-age=31536000, immutable" } });
    }

    let user;
    const initData = request.headers.get("X-Init-Data");
    if (initData) {
      try {
        const u = await checkInitData(initData, this.env.BOT_TOKEN);
        user = { id: u.id, username: u.username || null, name: [u.first_name, u.last_name].filter(Boolean).join(" "),
          photo: /^https:\/\//.test(u.photo_url || "") ? u.photo_url : null };
      } catch { return json({ error: "unauthorized" }, 401); }
    } else if (this.env.DEV_MODE === "1" && request.headers.get("X-Dev-User")) {
      const id = Number(request.headers.get("X-Dev-User"));
      user = { id, username: `dev${id}`, name: `Dev ${id}` };
    } else return json({ error: "Открой приложение через Telegram" }, 401);

    const body = request.method === "POST" ? await request.json().catch(() => ({})) : {};
    try {
      return json(await this.route(request.method, url.pathname.slice(4), user, body));
    } catch (e) {
      if (e instanceof ApiError) return json({ error: e.message }, 400);
      console.log("api error", e.stack);
      return json({ error: "Ошибка сервера" }, 500);
    }
  }

  async route(method, path, user, body) {
    const uid = user.id;
    const isAdmin = this.isAdmin(uid);
    const requirePlayer = () => { const p = this.player(uid); if (!p) throw new ApiError("Сначала зарегистрируйся"); return p; };
    const requireAdmin = () => { if (!isAdmin) throw new ApiError("Только для админов"); };
    const getMatch = id => { const m = this.match(id); if (!m) throw new ApiError("Матч не найден"); return m; };
    const isCaptain = m => m.captain1 === uid || m.captain2 === uid;
    const parseScore = (winner, b) => {
      if (winner !== 1 && winner !== 2) throw new ApiError("Выбери победителя");
      const s1 = Number(b.score1) || 0, s2 = Number(b.score2) || 0;
      if (s1 < 0 || s1 > 99 || s2 < 0 || s2 > 99 || ((s1 || s2) && (s1 > s2) !== (winner === 1))) throw new ApiError("Счёт не совпадает с победителем");
      return s1 || s2 ? `${s1}:${s2}` : "";
    };
    let mm;

    // только для локальных тестов: подменить текущий сезон, чтобы проверить его смену
    if (this.env.DEV_MODE === "1" && method === "POST" && path === "/dev/season") { this.setSetting("season", String(body.season)); return { ok: true }; }

    if (method === "GET" && path === "/config") {
      const season = this.setting("season");
      const d = new Date(), end = Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
      return { maps: this.maps, levels: LEVELS, calibration_games: CALIBRATION_GAMES, lobby_size: LOBBY_SIZE, veto_turn_sec: VETO_TURN_SEC,
        ready_sec: READY_SEC, ready_ban_min: BAN_BASE_MIN, shop: SHOP, premium_perks: PREMIUM_PERKS, coins: COINS, ticket_topics: TICKET_TOPICS, nick_colors: NICK_COLORS,
        cases: CASES.map(c => ({ ...c, pool: SHOP.filter(i => ["frame", "chevron", "banner"].includes(i.kind) && !i.premium && !i.flag).map(i => ({ id: i.id, rarity: rarityOf(i) })) })),
        stars: STARS, ban_base_min: BAN_BASE_MIN,
        party_max: PARTY_MAX, party_max_premium: PARTY_MAX_PREMIUM, placement_max_level: level(PLACEMENT_MAX), calibration_mult: CALIBRATION_MULT, season, season_name: seasonName(season), season_days_left: Math.ceil((end - Date.now()) / 86400000) };
    }

    if (method === "GET" && path === "/me") {
      this.sql.exec("UPDATE players SET last_seen = ? WHERE tg_id = ?", now(), uid);
      let p = this.player(uid);
      if (p && user.photo && p.tg_photo !== user.photo) {
        this.sql.exec("UPDATE players SET tg_photo = ?, photo = CASE WHEN custom_photo = 1 THEN photo ELSE ? END WHERE tg_id = ?", user.photo, user.photo, uid);
        p = this.player(uid);
      }
      const pendingCount = isAdmin ? this.one("SELECT COUNT(*) AS n FROM matches WHERE status = 'pending'").n : 0;
      const friendReq = this.one("SELECT COUNT(*) AS n FROM friends WHERE to_id = ? AND status = 'pending'", uid).n
        + this.one("SELECT COUNT(*) AS n FROM party_invites WHERE to_id = ?", uid).n;
      const ticketsNew = isAdmin ? this.one("SELECT COUNT(*) AS n FROM tickets WHERE status = 'open'").n : 0;
      return { user, player: p ? this.publicPlayer(p) : null, rank: this.rankOf(uid), active_match: this.activeMatchOf(uid), is_admin: isAdmin, pending_count: pendingCount + ticketsNew, friend_requests: friendReq,
        party: p ? this.partyView(uid) : null, inventory: p ? this.q("SELECT item FROM inventory WHERE tg_id = ?", uid).map(r => r.item) : [],
        daily_ready: p ? p.daily_at !== Math.floor(now() / 86400) : false,
        my_tickets_answered: p ? this.one("SELECT COUNT(*) AS n FROM tickets WHERE tg_id = ? AND status = 'answered'", uid).n : 0 };
    }

    if (method === "POST" && path === "/register") {
      const nick = String(body.nick || "").trim();
      const gameId = String(body.game_id || "").replace(/\D/g, "").slice(0, 15);
      if (!NICK_RE.test(nick)) throw new ApiError("Ник: 2–20 символов");
      if (this.one("SELECT 1 AS x FROM players WHERE lower(nick) = lower(?) AND tg_id != ?", nick, uid)) throw new ApiError("Этот ник уже занят");
      this.sql.exec(`INSERT INTO players (tg_id, tg_username, tg_name, nick, game_id, elo, created_at, photo, tg_photo) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(tg_id) DO UPDATE SET nick = excluded.nick, game_id = excluded.game_id, tg_username = excluded.tg_username,
          tg_name = excluded.tg_name, photo = CASE WHEN players.custom_photo = 1 THEN players.photo ELSE COALESCE(excluded.photo, players.photo) END,
          tg_photo = COALESCE(excluded.tg_photo, players.tg_photo)`,
        uid, user.username, user.name, nick, gameId, START_ELO, now(), user.photo || null, user.photo || null);
      return { ok: true };
    }

    if (method === "POST" && path === "/avatar") {
      requirePlayer();
      if (body.remove) {
        this.sql.exec("DELETE FROM avatars WHERE tg_id = ?", uid);
        this.sql.exec("UPDATE players SET custom_photo = 0, photo = tg_photo WHERE tg_id = ?", uid);
        return { ok: true };
      }
      const m = /^data:image\/jpeg;base64,([A-Za-z0-9+/=]+)$/.exec(String(body.data || ""));
      if (!m) throw new ApiError("Нужна картинка JPEG");
      const bin = Uint8Array.from(atob(m[1]), c => c.charCodeAt(0));
      if (bin.length > AVATAR_MAX) throw new ApiError("Картинка слишком большая");
      if (bin[0] !== 0xff || bin[1] !== 0xd8) throw new ApiError("Это не JPEG");
      const t = now();
      this.sql.exec("INSERT INTO avatars (tg_id, data, updated) VALUES (?, ?, ?) ON CONFLICT(tg_id) DO UPDATE SET data = excluded.data, updated = excluded.updated", uid, bin.buffer, t);
      this.sql.exec("UPDATE players SET custom_photo = 1, photo = ? WHERE tg_id = ?", `/avatar/${uid}?v=${t}`, uid);
      return { ok: true, photo: `/avatar/${uid}?v=${t}` };
    }

    if (method === "GET" && path === "/lobbies") {
      this.ensureLobbies();
      return this.q(`SELECT id FROM matches WHERE status IN ('open','ready','veto','live','pending')
          ORDER BY CASE WHEN status IN ('open','ready') THEN 1 ELSE 0 END, CASE WHEN status IN ('open','ready') THEN lobby_no ELSE -id END`)
        .map(r => this.publicMatch(this.match(r.id)));
    }

    if (method === "GET" && (mm = path.match(/^\/matches\/(\d+)$/))) {
      const m = this.publicMatch(getMatch(+mm[1]));
      m.my_rates = Object.fromEntries(this.q("SELECT to_id, value FROM rep WHERE match_id = ? AND from_id = ?", m.id, uid).map(r => [r.to_id, r.value]));
      m.can_rate = m.status === "finished" && now() - m.finished_at < 86400 && m.players.some(p => p.tg_id === uid);
      return m;
    }

    if (method === "GET" && path === "/leaderboard") {
      return this.q("SELECT tg_id, nick, game_id, photo, elo, wins, losses, created_at, badges, banned_until, frame, chevron, banner, nick_color, premium_until, last_seen, coins FROM players WHERE tg_id > 0 ORDER BY elo DESC, wins DESC")
        .map(r => this.publicPlayer(r))
        .sort((a, b) => (b.calibrated - a.calibrated) || (a.calibrated ? 0 : b.calib_played - a.calib_played));
    }

    if (method === "GET" && (mm = path.match(/^\/players\/(\d+)$/))) {
      if (!this.player(+mm[1])) throw new ApiError("Игрок не найден");
      return this.profile(+mm[1], uid);
    }

    if (method === "GET" && path === "/seasons") {
      return this.q("SELECT * FROM seasons ORDER BY season DESC, place").map(r => ({ ...r, season_name: seasonName(r.season) }));
    }

    // ----- party -----
    if (method === "POST" && (mm = path.match(/^\/party\/(invite|accept|decline|leave|kick)$/))) {
      const me = requirePlayer();
      if (["invite", "accept"].includes(mm[1]) && this.activeMatchOf(uid)) {
        const st = this.one("SELECT status FROM matches WHERE id = ?", this.activeMatchOf(uid)).status;
        if (st !== "open") throw new ApiError("Сначала доиграй матч");
      }
      switch (mm[1]) {
        case "invite": {
          const to = Number(body.tg_id), tp = this.player(to);
          if (!tp) throw new ApiError("Игрок не найден");
          if (this.friendState(uid, to) !== "friends") throw new ApiError("Звать в пати можно только друзей");
          let party = this.partyOf(uid);
          if (party && party.leader !== uid) throw new ApiError("Звать может только лидер пати");
          if (!party) {
            const id = this.one("INSERT INTO parties (leader, created) VALUES (?, ?) RETURNING id", uid, now()).id;
            this.sql.exec("UPDATE players SET party_id = ? WHERE tg_id = ?", id, uid);
            party = this.partyOf(uid);
          }
          if (party.members.includes(to)) throw new ApiError("Он уже в пати");
          if (party.members.length >= party.max) throw new ApiError(party.max === PARTY_MAX ? `В пати максимум ${PARTY_MAX}. С премиумом — до ${PARTY_MAX_PREMIUM}` : "Пати заполнена");
          this.sql.exec("INSERT OR REPLACE INTO party_invites (party_id, to_id, from_id, created) VALUES (?, ?, ?, ?)", party.id, to, uid, now());
          await this.send(to, `🎮 <b>${esc(me.nick)}</b> зовёт тебя в пати.`, this.appButton("Открыть приглашение"));
          return { ok: true };
        }
        case "accept": {
          const inv = this.one("SELECT * FROM party_invites WHERE to_id = ? AND party_id = ?", uid, Number(body.party_id));
          if (!inv) throw new ApiError("Приглашение устарело");
          const party = this.one("SELECT * FROM parties WHERE id = ?", inv.party_id);
          if (!party) { this.sql.exec("DELETE FROM party_invites WHERE party_id = ?", inv.party_id); throw new ApiError("Пати уже распалась"); }
          const leaderParty = this.partyOf(party.leader);
          if (leaderParty.members.length >= leaderParty.max) throw new ApiError("Пати уже заполнена");
          const lam = this.activeMatchOf(party.leader);
          if (lam && this.one("SELECT status FROM matches WHERE id = ?", lam).status !== "open") throw new ApiError("Пати сейчас в матче, попробуй позже");
          this.leaveParty(uid);
          this.sql.exec("UPDATE players SET party_id = ? WHERE tg_id = ?", party.id, uid);
          this.sql.exec("DELETE FROM party_invites WHERE to_id = ?", uid);
          await this.notify(leaderParty.members, `🤝 <b>${esc(me.nick)}</b> вступил в пати.`);
          return { ok: true };
        }
        case "decline":
          this.sql.exec("DELETE FROM party_invites WHERE to_id = ? AND party_id = ?", uid, Number(body.party_id));
          return { ok: true };
        case "leave": {
          const party = this.partyOf(uid);
          if (!party) throw new ApiError("Ты не в пати");
          this.leaveParty(uid);
          await this.notify(party.members.filter(x => x !== uid), `🚪 <b>${esc(me.nick)}</b> вышел из пати.`);
          return { ok: true };
        }
        case "kick": {
          const party = this.partyOf(uid), target = Number(body.tg_id);
          if (!party || party.leader !== uid) throw new ApiError("Исключать может только лидер");
          if (body.invite) { this.sql.exec("DELETE FROM party_invites WHERE party_id = ? AND to_id = ?", party.id, target); return { ok: true }; }
          if (!party.members.includes(target) || target === uid) throw new ApiError("Его нет в пати");
          this.leaveParty(target);
          await this.send(target, "Тебя исключили из пати.");
          return { ok: true };
        }
      }
    }

    // ----- найти игру: самое заполненное лобби, где хватает мест -----
    if (method === "POST" && path === "/find") {
      requirePlayer();
      const party = this.partyOf(uid), need = party ? party.members.length : 1;
      this.ensureLobbies();
      const open = this.q("SELECT id FROM matches WHERE status = 'open' ORDER BY lobby_no").map(r => this.match(r.id))
        .filter(m => m.players.length + need <= LOBBY_SIZE).sort((a, b) => b.players.length - a.players.length);
      if (!open.length) throw new ApiError("Свободных мест нет, подожди минуту");
      const res = this.joinLobby(open[0], uid);
      if (res.full) await this.startReady(open[0].id);
      return { ok: true, lobby_no: open[0].lobby_no };
    }

    // ----- магазин -----
    if (method === "POST" && path === "/shop/buy") {
      const p = requirePlayer(), item = SHOP.find(i => i.id === body.item);
      if (!item) throw new ApiError("Нет такого товара");
      if (item.premium) throw new ApiError("Этот предмет даёт премиум");
      if (item.case) throw new ApiError("Этот предмет выпадает только из кейсов");
      if (item.kind !== "premium" && this.one("SELECT 1 AS x FROM inventory WHERE tg_id = ? AND item = ?", uid, item.id)) throw new ApiError("Уже куплено");
      const owned = new Set(this.q("SELECT item FROM inventory WHERE tg_id = ?", uid).map(r => r.item));
      if (item.kind === "bundle" && item.items.every(x => owned.has(x))) throw new ApiError("Всё из комплекта уже есть");
      if (p.coins < item.price) throw new ApiError(`Не хватает ${item.price - p.coins} TC`);
      this.sql.exec("UPDATE players SET coins = coins - ? WHERE tg_id = ?", item.price, uid);
      if (item.kind === "premium") {
        this.sql.exec("UPDATE players SET premium_until = MAX(COALESCE(premium_until, 0), ?) + ? WHERE tg_id = ?", now(), item.days * 86400, uid);
        await this.send(uid, `⭐ Премиум активирован на ${item.days} дн. Пати до ${PARTY_MAX_PREMIUM} человек, ×${PREMIUM_COIN_MULT} TC и свой цвет ника уже работают.`);
      } else {
        for (const id of item.kind === "bundle" ? item.items : [item.id]) {
          const sub = SHOP.find(x => x.id === id);
          this.sql.exec("INSERT OR IGNORE INTO inventory (tg_id, item, created) VALUES (?, ?, ?)", uid, id, now());
          this.sql.exec(`UPDATE players SET ${sub.kind} = ? WHERE tg_id = ?`, id, uid);
        }
      }
      return { ok: true };
    }
    if (method === "POST" && path === "/shop/equip") {
      const p = requirePlayer(), kind = ["frame", "chevron", "banner"].includes(body.kind) ? body.kind : "chevron";
      const item = body.item ? SHOP.find(i => i.id === body.item && i.kind === kind) : null;
      if (body.item && !item) throw new ApiError("Нет такого предмета");
      if (item?.premium && !this.isPremium(p)) throw new ApiError("Нужен премиум");
      if (item && !item.premium && !this.one("SELECT 1 AS x FROM inventory WHERE tg_id = ? AND item = ?", uid, item.id)) throw new ApiError("Сначала купи");
      this.sql.exec(`UPDATE players SET ${kind} = ? WHERE tg_id = ?`, item?.id ?? null, uid);
      return { ok: true };
    }

    if (method === "POST" && path === "/case/open") {
      const p = requirePlayer(), c = CASES.find(x => x.id === body.case);
      if (!c) throw new ApiError("Нет такого кейса");
      if (p.coins < c.price) throw new ApiError(`Не хватает ${c.price - p.coins} TC`);
      const pool = SHOP.filter(i => ["frame", "chevron", "banner"].includes(i.kind) && !i.premium && !i.flag);
      let r = Math.random() * 100, rarity = "common";
      for (const [k, w] of Object.entries(c.odds)) { if (r < w) { rarity = k; break; } r -= w; }
      const cands = pool.filter(i => rarityOf(i) === rarity);
      const prize = cands[Math.floor(Math.random() * cands.length)];
      const dup = !!this.one("SELECT 1 AS x FROM inventory WHERE tg_id = ? AND item = ?", uid, prize.id);
      const refund = dup ? Math.round(c.price * DUP_REFUND) : 0;
      this.sql.exec("UPDATE players SET coins = coins - ? + ? WHERE tg_id = ?", c.price, refund, uid);
      if (!dup) this.sql.exec("INSERT INTO inventory (tg_id, item, created) VALUES (?, ?, ?)", uid, prize.id, now());
      return { ok: true, item: prize.id, rarity, dup, refund };
    }
    if (method === "POST" && path === "/stars/invoice") {
      requirePlayer();
      const pr = STARS.find(x => x.id === body.product);
      if (!pr) throw new ApiError("Нет такого товара");
      const r = await this.tg("createInvoiceLink", {
        title: pr.title, description: pr.tc ? `${pr.tc} Timoha Coin на баланс SO2 Arena` : `Премиум SO2 Arena на ${pr.days} дней`,
        payload: JSON.stringify({ u: uid, p: pr.id }), currency: "XTR", prices: [{ label: pr.title, amount: pr.stars }],
      });
      if (!r.ok) throw new ApiError("Telegram не создал счёт: " + (r.description || ""));
      return { link: r.result };
    }

    if (method === "POST" && path === "/shop/color") {
      const p = requirePlayer();
      if (!this.isPremium(p)) throw new ApiError("Цвет ника — функция премиума");
      const c = body.color ? String(body.color) : null;
      if (c && !NICK_COLORS.includes(c)) throw new ApiError("Нет такого цвета");
      this.sql.exec("UPDATE players SET nick_color = ? WHERE tg_id = ?", c, uid);
      return { ok: true };
    }
    if (method === "POST" && path === "/daily") {
      const p = requirePlayer(), day = Math.floor(now() / 86400);
      if (p.daily_at === day) throw new ApiError("Бонус уже получен, приходи завтра");
      const n = this.isPremium(p) ? COINS.daily_premium : COINS.daily;
      this.sql.exec("UPDATE players SET daily_at = ?, coins = coins + ? WHERE tg_id = ?", day, n, uid);
      return { ok: true, amount: n };
    }

    // ----- поддержка -----
    if (method === "GET" && path === "/tickets") {
      return this.q("SELECT t.*, p.nick FROM tickets t LEFT JOIN players p ON p.tg_id = t.tg_id WHERE t.tg_id = ? ORDER BY t.updated DESC", uid);
    }
    if (method === "POST" && path === "/tickets") {
      const p = requirePlayer();
      const topic = TICKET_TOPICS.includes(body.topic) ? body.topic : "Другое";
      const text = String(body.text || "").trim().slice(0, 2000);
      if (text.length < 5) throw new ApiError("Опиши проблему подробнее");
      const img = body.image ? this.decodeJpeg(body.image, 600 * 1024) : null;
      const tq = String(body.target || "").trim();
      const target = tq ? this.one("SELECT tg_id FROM players WHERE lower(nick) = lower(?) OR game_id = ?", tq, tq)?.tg_id ?? null : null;
      const id = this.one("INSERT INTO tickets (tg_id, topic, match_id, target_id, status, created, updated) VALUES (?, ?, ?, ?, 'open', ?, ?) RETURNING id",
        uid, topic, Number(body.match_id) || null, target, now(), now()).id;
      this.sql.exec("INSERT INTO ticket_msgs (ticket_id, from_id, is_admin, text, image, image_key, created) VALUES (?, ?, 0, ?, ?, ?, ?)",
        id, uid, text + (tq && !target ? `\n(игрок: ${tq})` : ""), img ? img.buffer : null, img ? crypto.randomUUID() : null, now());
      await this.notify(this.adminIds(), `🆘 <b>Тикет #${id}</b> · ${esc(topic)}${this.isPremium(p) ? " · ⭐ премиум" : ""}\nОт: ${esc(p.nick)}\n\n${esc(text.slice(0, 300))}`, this.appButton("Открыть тикет"));
      return { ok: true, id };
    }
    if ((mm = path.match(/^\/tickets\/(\d+)(?:\/(msg|close))?$/))) {
      const t = this.one("SELECT t.*, p.nick FROM tickets t LEFT JOIN players p ON p.tg_id = t.tg_id WHERE t.id = ?", +mm[1]);
      if (!t || (t.tg_id !== uid && !isAdmin)) throw new ApiError("Тикет не найден");
      if (method === "GET" && !mm[2]) {
        const msgs = this.q("SELECT m.id, m.from_id, m.is_admin, m.text, m.image_key, m.created, p.nick FROM ticket_msgs m LEFT JOIN players p ON p.tg_id = m.from_id WHERE ticket_id = ? ORDER BY m.id", t.id)
          .map(({ image_key, ...r }) => ({ ...r, image: image_key ? `/ticketimg/${r.id}/${image_key}` : null }));
        const target = t.target_id ? this.player(t.target_id) : null;
        return { ticket: { ...t, target_nick: target?.nick ?? null, premium: this.isPremium(this.player(t.tg_id)) }, msgs };
      }
      if (method === "POST" && mm[2] === "msg") {
        if (t.status === "closed") throw new ApiError("Тикет закрыт");
        const text = String(body.text || "").trim().slice(0, 2000);
        if (!text && !body.image) throw new ApiError("Пустое сообщение");
        const img = body.image ? this.decodeJpeg(body.image, 600 * 1024) : null;
        const fromAdmin = isAdmin && t.tg_id !== uid;
        this.sql.exec("INSERT INTO ticket_msgs (ticket_id, from_id, is_admin, text, image, image_key, created) VALUES (?, ?, ?, ?, ?, ?, ?)",
          t.id, uid, fromAdmin ? 1 : 0, text, img ? img.buffer : null, img ? crypto.randomUUID() : null, now());
        this.sql.exec("UPDATE tickets SET status = ?, updated = ? WHERE id = ?", fromAdmin ? "answered" : "open", now(), t.id);
        if (fromAdmin) await this.send(t.tg_id, `💬 <b>Ответ по тикету #${t.id}</b>\n\n${esc(text.slice(0, 500))}`, this.appButton("Открыть тикет"));
        else await this.notify(this.adminIds(), `💬 Новое сообщение в тикете #${t.id} от ${esc(t.nick)}`, this.appButton("Открыть тикет"));
        return { ok: true };
      }
      if (method === "POST" && mm[2] === "close") {
        this.sql.exec("UPDATE tickets SET status = 'closed', updated = ? WHERE id = ?", now(), t.id);
        if (isAdmin && t.tg_id !== uid) await this.send(t.tg_id, `✅ Тикет #${t.id} закрыт администратором.`);
        return { ok: true };
      }
    }

    // ----- friends -----
    if (method === "GET" && path === "/friends") {
      const rows = this.q("SELECT * FROM friends WHERE from_id = ? OR to_id = ?", uid, uid);
      const card = id => {
        const p = this.player(id);
        if (!p) return null;
        const pp = this.publicPlayer(p);
        const am = this.activeMatchOf(id), st = am ? this.one("SELECT status FROM matches WHERE id = ?", am).status : null;
        return { tg_id: id, nick: pp.nick, photo: pp.photo, game_id: pp.game_id, level: pp.level, elo: pp.elo, calibrated: pp.calibrated,
          calib_played: pp.calib_played, online: pp.online, frame: pp.frame, chevron: pp.chevron, nick_color: pp.nick_color, premium: pp.premium, last_seen: p.last_seen, in_lobby: st === "open" || st === "ready", in_match: ["veto", "live", "pending"].includes(st) };
      };
      const pick = (f) => rows.filter(f).map(r => card(r.from_id === uid ? r.to_id : r.from_id)).filter(Boolean);
      const friends = pick(r => r.status === "accepted").sort((a, b) => (b.online - a.online) || ((b.last_seen || 0) - (a.last_seen || 0)));
      return { friends, incoming: pick(r => r.status === "pending" && r.to_id === uid), outgoing: pick(r => r.status === "pending" && r.from_id === uid) };
    }
    if (method === "POST" && (mm = path.match(/^\/friends\/(request|accept|decline|remove)$/))) {
      const me = requirePlayer(), other = Number(body.tg_id);
      const op = this.player(other);
      if (!op || other === uid) throw new ApiError("Игрок не найден");
      const row = this.friendRow(uid, other);
      switch (mm[1]) {
        case "request":
          if (row?.status === "accepted") throw new ApiError("Вы уже друзья");
          if (row && row.from_id === other) { // встречная заявка — сразу дружим
            this.sql.exec("UPDATE friends SET status = 'accepted' WHERE from_id = ? AND to_id = ?", other, uid);
            await this.send(other, `🤝 <b>${esc(me.nick)}</b> теперь у тебя в друзьях.`);
            return { ok: true, state: "friends" };
          }
          if (row) throw new ApiError("Заявка уже отправлена");
          this.sql.exec("INSERT INTO friends (from_id, to_id, status, created) VALUES (?, ?, 'pending', ?)", uid, other, now());
          await this.send(other, `👋 <b>${esc(me.nick)}</b> хочет добавить тебя в друзья.`, this.appButton("Открыть заявки"));
          return { ok: true, state: "outgoing" };
        case "accept":
          if (!row || row.status !== "pending" || row.from_id !== other) throw new ApiError("Заявки нет");
          this.sql.exec("UPDATE friends SET status = 'accepted' WHERE from_id = ? AND to_id = ?", other, uid);
          await this.send(other, `🤝 <b>${esc(me.nick)}</b> принял твою заявку в друзья.`);
          return { ok: true, state: "friends" };
        case "decline":
        case "remove":
          if (!row) throw new ApiError("Вы не друзья");
          this.sql.exec("DELETE FROM friends WHERE (from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?)", uid, other, other, uid);
          return { ok: true, state: "none" };
      }
    }

    // ----- admin -----
    if (path.startsWith("/admin/")) {
      requireAdmin();
      if (method === "GET" && path === "/admin/overview") {
        return {
          pending: this.q("SELECT id FROM matches WHERE status = 'pending' ORDER BY id").map(r => this.publicMatch(this.match(r.id))),
          admins: this.adminIds().map(id => ({ tg_id: id, nick: this.player(id)?.nick ?? null, env: this.envAdmins.has(id) })),
          group_set: !!this.groupId(),
          tickets: this.q("SELECT t.*, p.nick FROM tickets t LEFT JOIN players p ON p.tg_id = t.tg_id WHERE t.status != 'closed' ORDER BY CASE t.status WHEN 'open' THEN 0 ELSE 1 END, t.updated DESC")
            .map(t => ({ ...t, premium: this.isPremium(this.player(t.tg_id)) })).sort((a, b) => (a.status === b.status ? b.premium - a.premium : 0)),
        };
      }
      if (method === "POST" && (mm = path.match(/^\/admin\/players\/(\d+)\/(\w+)$/))) {
        const id = +mm[1], p = this.player(id);
        if (!p) throw new ApiError("Игрок не найден");
        switch (mm[2]) {
          case "elo": {
            const elo = Math.round(Number(body.elo));
            if (!(elo >= 100 && elo <= 5000)) throw new ApiError("ELO от 100 до 5000");
            this.sql.exec("UPDATE players SET elo = ? WHERE tg_id = ?", elo, id);
            await this.send(id, `🛠 Админ изменил твоё ELO: ${p.elo} → <b>${elo}</b>`);
            return { ok: true };
          }
          case "grant_all": {
            for (const it of SHOP.filter(i => ["frame", "chevron", "banner"].includes(i.kind) && !i.premium))
              this.sql.exec("INSERT OR IGNORE INTO inventory (tg_id, item, created) VALUES (?, ?, ?)", id, it.id, now());
            this.sql.exec("UPDATE players SET coins = coins + 1000000, premium_until = MAX(COALESCE(premium_until, 0), ?) + ? WHERE tg_id = ?", now(), 3650 * 86400, id);
            return { ok: true };
          }
          case "coins": {
            const n = Math.round(Number(body.amount));
            if (!n || Math.abs(n) > 100000) throw new ApiError("Укажи количество");
            this.sql.exec("UPDATE players SET coins = MAX(0, coins + ?) WHERE tg_id = ?", n, id);
            await this.send(id, `🪙 Админ ${n > 0 ? "начислил" : "списал"} ${Math.abs(n)} TC.`);
            return { ok: true };
          }
          case "premium": {
            const days = Math.round(Number(body.days));
            if (days > 0) this.sql.exec("UPDATE players SET premium_until = MAX(COALESCE(premium_until, 0), ?) + ? WHERE tg_id = ?", now(), days * 86400, id);
            else this.sql.exec("UPDATE players SET premium_until = NULL WHERE tg_id = ?", id);
            if (days > 0) await this.send(id, `⭐ Тебе выдан премиум на ${days} дн.`);
            return { ok: true };
          }
          case "ban": {
            const days = Number(body.days) || 0;
            const until = days > 0 ? now() + Math.round(days * 86400) : null;
            this.sql.exec("UPDATE players SET banned_until = ? WHERE tg_id = ?", until, id);
            if (until) {
              this.sql.exec(`DELETE FROM match_players WHERE tg_id = ? AND match_id IN (SELECT id FROM matches WHERE status = 'open')`, id);
              await this.send(id, `⛔ Ты забанен на ${days} дн. Причина: ${esc(body.reason || "решение админа")}`);
            } else await this.send(id, "✅ Бан снят, можешь снова играть.");
            return { ok: true };
          }
          case "admin": {
            if (body.on) this.sql.exec("INSERT OR IGNORE INTO admins (tg_id) VALUES (?)", id);
            else { if (this.envAdmins.has(id)) throw new ApiError("Этого админа можно убрать только в настройках"); this.sql.exec("DELETE FROM admins WHERE tg_id = ?", id); }
            if (body.on) await this.send(id, "🛡 Тебе выданы права админа SO2 Arena.");
            return { ok: true };
          }
          case "delete": {
            if (this.activeMatchOf(id) && this.one(`SELECT 1 AS x FROM matches m JOIN match_players mp ON mp.match_id = m.id
                WHERE mp.tg_id = ? AND m.status IN ('veto','live','pending')`, id)) throw new ApiError("Игрок сейчас в матче");
            this.sql.exec("DELETE FROM match_players WHERE tg_id = ? AND match_id IN (SELECT id FROM matches WHERE status IN ('open','ready'))", id);
            this.sql.exec("DELETE FROM players WHERE tg_id = ?", id);
            this.sql.exec("DELETE FROM avatars WHERE tg_id = ?", id);
            this.sql.exec("DELETE FROM friends WHERE from_id = ? OR to_id = ?", id, id);
            this.leaveParty(id);
            this.sql.exec("DELETE FROM admins WHERE tg_id = ?", id);
            return { ok: true };
          }
        }
      }
      throw new ApiError("Неизвестный запрос");
    }

    if (method === "POST" && (mm = path.match(/^\/lobbies\/(\d+)\/addbot$/))) {
      requireAdmin();
      const m = getMatch(+mm[1]);
      if (m.status !== "open") throw new ApiError("Лобби уже не открыто");
      const want = Math.min(LOBBY_SIZE - m.players.length, Math.max(1, Number(body.count) || 1));
      let added = 0;
      for (let n = 1; n <= 60 && added < want; n++) {
        const id = -n;
        if (!this.player(id)) this.sql.exec(`INSERT INTO players (tg_id, nick, game_id, elo, wins, losses, created_at) VALUES (?, ?, ?, ?, 5, 5, ?)`,
          id, `Bot_${n}`, String(90000000 + n), 800 + Math.floor(Math.random() * 800), now());
        if (this.activeMatchOf(id)) continue;
        this.sql.exec("INSERT INTO match_players (match_id, tg_id, joined_at, ready) VALUES (?, ?, ?, 1)", m.id, id, Date.now() / 1000 + added / 1000);
        added++;
      }
      if (m.players.length + added === LOBBY_SIZE) {
        await this.startReady(m.id);
        if (this.one("SELECT COUNT(*) AS n FROM match_players WHERE match_id = ? AND ready = 0", m.id).n === 0) await this.startVeto(m.id);
      }
      return { ok: true, added };
    }

    if (method !== "POST" || !(mm = path.match(/^\/lobbies\/(\d+)\/(\w+)$/))) throw new ApiError("Неизвестный запрос");
    const mid = +mm[1], action = mm[2];
    const m = getMatch(mid);
    const ids = m.players.map(p => p.tg_id);

    switch (action) {
      case "join": {
        requirePlayer();
        if (m.status !== "open") throw new ApiError("Лобби уже не открыто");
        if (ids.includes(uid)) return { ok: true };
        const res = this.joinLobby(m, uid);
        if (res.full) await this.startReady(mid);
        return { ok: true };
      }
      case "ready": {
        if (m.status !== "ready") throw new ApiError("Сейчас не проверка готовности");
        if (!ids.includes(uid)) throw new ApiError("Ты не в этом лобби");
        this.sql.exec("UPDATE match_players SET ready = 1 WHERE match_id = ? AND tg_id = ?", mid, uid);
        if (this.one("SELECT COUNT(*) AS n FROM match_players WHERE match_id = ? AND ready = 0", mid).n === 0) await this.startVeto(mid);
        return { ok: true };
      }
      case "leave": {
        if (!["open", "ready"].includes(m.status)) throw new ApiError("Из начатого матча выйти нельзя");
        this.sql.exec("DELETE FROM match_players WHERE match_id = ? AND tg_id = ?", mid, uid);
        if (m.status === "ready") {
          this.sql.exec("UPDATE matches SET status = 'open', ready_deadline = NULL WHERE id = ?", mid);
          this.sql.exec("UPDATE match_players SET ready = 0 WHERE match_id = ?", mid);
          await this.scheduleAlarm();
          await this.notify(ids.filter(id => id !== uid), `🚪 ${esc(this.nick(m, uid))} вышел из лобби ${m.lobby_no}. Ждём ещё одного игрока.`);
        }
        return { ok: true };
      }
      case "kick": {
        if (!isAdmin) throw new ApiError("Кикать может только админ");
        if (!["open", "ready"].includes(m.status)) throw new ApiError("Лобби уже не открыто");
        this.sql.exec("DELETE FROM match_players WHERE match_id = ? AND tg_id = ?", mid, Number(body.tg_id));
        if (m.status === "ready") { this.sql.exec("UPDATE matches SET status = 'open', ready_deadline = NULL WHERE id = ?", mid); await this.scheduleAlarm(); }
        return { ok: true };
      }
      case "ban": {
        if (m.status !== "veto") throw new ApiError("Сейчас не идёт выбор карты");
        const turn = this.vetoTurn(m);
        if (turn !== uid && !isAdmin) throw new ApiError(isCaptain(m) ? "Сейчас ход другого капитана" : "Банят только капитаны");
        await this.ban(mid, turn, String(body.map || ""));
        return { ok: true };
      }
      case "room": {
        if (m.creator_id !== uid && !isCaptain(m) && !isAdmin) throw new ApiError("Код комнаты вписывает тот, кто создаёт лобби в игре");
        if (!["veto", "live"].includes(m.status)) throw new ApiError("Матч ещё не собран");
        const room = String(body.room || "").trim().slice(0, 60);
        this.sql.exec("UPDATE matches SET room = ? WHERE id = ?", room, mid);
        if (room) await this.notify(ids, `🔑 Матч #${mid}${m.map ? ` (${esc(m.map)})` : ""}: комната <code>${esc(room)}</code>\nСоздал: ${esc(this.nick(m, m.creator_id))}`);
        return { ok: true };
      }
      case "result": {
        if (!ids.includes(uid) && !isAdmin) throw new ApiError("Ты не играл в этом матче");
        if (m.status !== "live") throw new ApiError(m.status === "pending" ? "Результат уже на модерации" : "Матч не идёт");
        const winner = Number(body.winner), score = parseScore(winner, body);
        const shot = body.image ? this.decodeJpeg(body.image, 900 * 1024) : null;
        if (!shot && !isAdmin) throw new ApiError("Приложи скриншот итоговой таблицы");
        await this.reportResult(m, uid, winner, score, shot);
        return { ok: true, pending: this.match(mid).status === "pending" };
      }
      case "confirm": {
        requireAdmin();
        if (m.status !== "pending" && m.status !== "live") throw new ApiError("Матч не ждёт подтверждения");
        const winner = body.winner ? Number(body.winner) : m.pending_winner;
        const score = body.winner ? parseScore(winner, body) : m.pending_score;
        if (!winner) throw new ApiError("Выбери победителя");
        await this.applyResult(mid, winner, score);
        return { ok: true };
      }
      case "reject": {
        requireAdmin();
        await this.rejectResult(mid, uid);
        return { ok: true };
      }
      case "stats": {
        if (!ids.includes(uid)) throw new ApiError("Ты не играл в этом матче");
        const okStatus = ["live", "pending"].includes(m.status) || (m.status === "finished" && now() - m.finished_at < STATS_WINDOW);
        if (!okStatus) throw new ApiError("Статистику можно вписать во время матча и 12 часов после");
        const kills = Math.round(Number(body.kills)), deaths = Math.round(Number(body.deaths)), assists = Math.round(Number(body.assists) || 0);
        if (!(kills >= 0 && kills <= 99 && deaths >= 0 && deaths <= 99 && assists >= 0 && assists <= 99)) throw new ApiError("Значения от 0 до 99");
        this.sql.exec("UPDATE match_players SET kills = ?, deaths = ?, assists = ? WHERE match_id = ? AND tg_id = ?", kills, deaths, assists, mid, uid);
        if (m.status === "finished") this.computeMvp(mid);
        return { ok: true };
      }
      case "rate": {
        if (m.status !== "finished" || now() - m.finished_at > 86400) throw new ApiError("Оценить можно в течение суток после матча");
        const to = Number(body.tg_id), v = Number(body.value) > 0 ? 1 : -1;
        if (!ids.includes(uid) || !ids.includes(to) || to === uid) throw new ApiError("Оценивать можно только тиммейтов и соперников из своего матча");
        this.sql.exec("INSERT INTO rep (match_id, from_id, to_id, value) VALUES (?, ?, ?, ?) ON CONFLICT(match_id, from_id, to_id) DO UPDATE SET value = excluded.value", mid, uid, to, v);
        return { ok: true };
      }
      case "cancel": {
        if (!isCaptain(m) && !isAdmin) throw new ApiError("Отменить может капитан или админ");
        if (!["veto", "live", "pending"].includes(m.status)) throw new ApiError("Этот матч нельзя отменить");
        this.sql.exec("UPDATE matches SET status = 'cancelled', veto_deadline = NULL WHERE id = ?", mid);
        await this.scheduleAlarm();
        await this.notify(ids, `❌ Матч #${mid} отменён (${esc(this.player(uid)?.nick || "админ")}), ELO не изменилось.`);
        return { ok: true };
      }
    }
    throw new ApiError("Неизвестное действие");
  }

  // ----- bot -----
  async webhook(request) {
    if (request.headers.get("X-Telegram-Bot-Api-Secret-Token") !== this.env.WEBHOOK_SECRET) return new Response("forbidden", { status: 403 });
    try {
      const update = await request.json();
      if (update.pre_checkout_query) {
        const q = update.pre_checkout_query;
        let ok = false;
        try { const pl = JSON.parse(q.invoice_payload); const pr = STARS.find(x => x.id === pl.p); ok = !!pr && pr.stars === q.total_amount && !!this.player(pl.u); } catch {}
        await this.tg("answerPreCheckoutQuery", { pre_checkout_query_id: q.id, ok, ...(ok ? {} : { error_message: "Товар недоступен, попробуй позже" }) });
      } else if (update.message?.successful_payment) await this.handlePayment(update.message);
      else if (update.message?.text) await this.handleMessage(update.message);
      else if (update.callback_query) await this.handleCallback(update.callback_query);
    } catch (e) { console.log("update failed", e.stack); }
    return new Response("ok");
  }

  async handlePayment(msg) {
    const sp = msg.successful_payment;
    const pl = JSON.parse(sp.invoice_payload), pr = STARS.find(x => x.id === pl.p);
    if (!pr || this.one("SELECT 1 AS x FROM payments WHERE charge_id = ?", sp.telegram_payment_charge_id)) return;
    this.sql.exec("INSERT INTO payments (charge_id, tg_id, product, stars, created) VALUES (?, ?, ?, ?, ?)", sp.telegram_payment_charge_id, pl.u, pr.id, sp.total_amount, now());
    if (pr.tc) this.addCoins(pl.u, pr.tc);
    if (pr.days) this.sql.exec("UPDATE players SET premium_until = MAX(COALESCE(premium_until, 0), ?) + ? WHERE tg_id = ?", now(), pr.days * 86400, pl.u);
    await this.send(pl.u, `⭐ Оплата прошла: <b>${esc(pr.title)}</b>. Спасибо!`, this.appButton("Открыть магазин"));
  }

  async handleCallback(cq) {
    const [act, idStr] = String(cq.data || "").split(":");
    const answer = text => this.tg("answerCallbackQuery", { callback_query_id: cq.id, text, show_alert: false });
    if (!this.isAdmin(cq.from.id)) return answer("Только для админов");
    const mid = Number(idStr), m = this.match(mid);
    if (!m || m.status !== "pending") {
      await answer("Уже обработано");
      return this.tg("editMessageReplyMarkup", { chat_id: cq.message.chat.id, message_id: cq.message.message_id, reply_markup: { inline_keyboard: [] } });
    }
    try {
      if (act === "ok") await this.applyResult(mid, m.pending_winner, m.pending_score);
      else await this.rejectResult(mid, cq.from.id);
    } catch (e) { return answer(e.message); }
    await answer(act === "ok" ? "Подтверждено" : "Отклонено");
    const doneText = `${act === "ok" ? "✅ Принято" : "❌ Отклонено"}: матч #${mid} (${esc(m.map)}) — Команда ${m.pending_winner} ${esc(m.pending_score || "")}`;
    if (cq.message.photo) await this.tg("editMessageCaption", { chat_id: cq.message.chat.id, message_id: cq.message.message_id, parse_mode: "HTML", caption: doneText });
    else await this.tg("editMessageText", { chat_id: cq.message.chat.id, message_id: cq.message.message_id, parse_mode: "HTML", text: doneText });
  }

  async handleMessage(msg) {
    const chatId = msg.chat.id, uid = msg.from.id, isPrivate = msg.chat.type === "private";
    const [rawCmd, arg] = msg.text.trim().split(/\s+/);
    const cmd = rawCmd.split("@")[0].toLowerCase();
    if (cmd === "/start") {
      if (!isPrivate) return this.send(chatId, "Напиши мне в личку, чтобы открыть приложение 🙂");
      const p = this.player(uid);
      const hello = p ? `С возвращением, <b>${esc(p.nick)}</b>! ` + (this.isCalibrated(p)
          ? `${level(p.elo)} lvl · ${p.elo} ELO` : `Калибровка ${p.wins + p.losses}/${CALIBRATION_GAMES}`)
        : "Привет! Это наша площадка для матчей <b>Standoff 2</b> с ELO и рейтингом.";
      return this.send(chatId, `${hello}\n\nКак это работает:\n• заходи в свободное лобби 5x5\n• когда соберётся 10 — жми «Готов»\n` +
        "• 2 капитана банят карты, один игрок создаёт комнату\n• после матча капитан отправляет результат, админ подтверждает\n" +
        `\nПервые ${CALIBRATION_GAMES} матчей — калибровка, после неё получишь уровень.`, this.appButton());
    }
    if (cmd === "/top") {
      const rows = this.q(`SELECT nick, elo FROM players WHERE tg_id > 0 AND wins + losses >= ${CALIBRATION_GAMES} ORDER BY elo DESC, wins DESC LIMIT 10`);
      if (!rows.length) return this.send(chatId, "Пока никто не прошёл калибровку.");
      const medals = ["🥇", "🥈", "🥉"];
      return this.send(chatId, `<b>Топ-10 · сезон ${seasonName(this.setting("season"))}</b>\n\n` +
        rows.map((r, i) => `${medals[i] || i + 1 + "."} ${esc(r.nick)} — <b>${r.elo}</b> (${level(r.elo)} lvl)`).join("\n"),
        isPrivate ? this.appButton("📊 Весь рейтинг") : null);
    }
    if (cmd === "/me") {
      const p = this.player(uid);
      if (!p) return this.send(chatId, "Ты ещё не зарегистрирован — открой приложение.", isPrivate ? this.appButton() : null);
      const pr = this.profile(uid), games = p.wins + p.losses, wr = games ? Math.round(p.wins * 100 / games) : 0;
      const head = this.isCalibrated(p) ? `${level(p.elo)} lvl · <b>${p.elo}</b> ELO · #${this.rankOf(uid)} в рейтинге` : `🎯 Калибровка: ${games}/${CALIBRATION_GAMES}`;
      return this.send(chatId, `<b>${esc(p.nick)}</b>\n${head}\nМатчей: ${games} · Побед: ${p.wins} · Винрейт: ${wr}%` +
        (pr.stats.kd != null ? `\nK/D: ${pr.stats.kd} · MVP: ${pr.stats.mvps}` : ""));
    }
    if (cmd === "/id") return this.send(chatId, `Твой ID: <code>${uid}</code>\nID чата: <code>${chatId}</code>`);
    if (cmd === "/admin") {
      if (!isPrivate) return;
      if (this.isAdmin(uid)) return this.send(chatId, "🛡 Ты уже админ.");
      if (!this.env.ADMIN_SECRET || arg !== this.env.ADMIN_SECRET) return this.send(chatId, "Неверный код.");
      this.sql.exec("INSERT OR IGNORE INTO admins (tg_id) VALUES (?)", uid);
      return this.send(chatId, "🛡 Готово, теперь ты админ! В приложении появилась вкладка «Админ».", this.appButton());
    }
    if (cmd === "/setgroup") {
      if (isPrivate) return this.send(chatId, "Эту команду нужно написать в группе, куда бот будет постить итоги матчей.");
      if (!this.isAdmin(uid)) return this.send(chatId, "Только админ может привязать группу.");
      this.setSetting("group_chat_id", chatId);
      return this.send(chatId, "✅ Группа привязана! Сюда будут приходить новые лобби, итоги матчей и итоги сезонов.");
    }
  }
}
