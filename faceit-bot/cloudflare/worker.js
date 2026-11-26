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

function combinations(arr, k, start = 0, cur = [], out = []) {
  if (cur.length === k) { out.push(cur.slice()); return out; }
  for (let i = start; i < arr.length; i++) { cur.push(arr[i]); combinations(arr, k, i + 1, cur, out); cur.pop(); }
  return out;
}

// Капитан 1 всегда в команде 1, капитан 2 — в команде 2, остальные делятся по ELO.
function balanceWithCaptains(players, cap1, cap2) {
  const c1 = players.find(p => p.tg_id === cap1), c2 = players.find(p => p.tg_id === cap2);
  const rest = shuffle(players.filter(p => p !== c1 && p !== c2));
  const total = players.reduce((s, p) => s + p.elo, 0);
  let best = null, bestDiff = Infinity;
  for (const combo of combinations(rest, rest.length / 2)) {
    const diff = Math.abs(total - 2 * (c1.elo + combo.reduce((s, p) => s + p.elo, 0)));
    if (diff < bestDiff) { best = combo; bestDiff = diff; }
  }
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
    if (url.pathname.startsWith("/api/") || url.pathname === "/webhook" || url.pathname.startsWith("/avatar/")) {
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
    const top = this.q(`SELECT tg_id, nick, elo, badges FROM players WHERE wins + losses >= ${CALIBRATION_GAMES} ORDER BY elo DESC, wins DESC LIMIT 3`);
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
    return this.one(`SELECT COUNT(*) AS n FROM players WHERE elo > ? AND wins + losses >= ${CALIBRATION_GAMES}`, p.elo).n + 1;
  }
  match(id) {
    const m = this.one("SELECT * FROM matches WHERE id = ?", id);
    if (!m) return null;
    m.bans = JSON.parse(m.bans || "[]");
    m.players = this.q(`SELECT mp.tg_id, mp.team, mp.elo_before, mp.elo_delta, mp.calibrating, mp.ready, mp.kills, mp.deaths, mp.assists,
        p.nick, p.elo, p.game_id, p.tg_username, p.photo, p.wins + p.losses AS games
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
      finished_at: m.finished_at, team_avg: {},
    };
    for (const t of [1, 2]) {
      const ps = m.players.filter(p => p.team === t);
      if (ps.length) out.team_avg[t] = Math.round(ps.reduce((s, p) => s + (p.elo_before ?? p.elo), 0) / ps.length);
    }
    out.players = m.players.map(p => {
      const calibrated = p.games >= CALIBRATION_GAMES;
      return { tg_id: p.tg_id, team: p.team, nick: p.nick, game_id: p.game_id, photo: p.photo, ready: !!p.ready,
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
      friend: viewer && viewer !== id ? this.friendState(viewer, id) : null,
      calibration: {
        wins: rows.filter(r => r.calibrating && r.team === r.winner).length,
        losses: rows.filter(r => r.calibrating && r.team !== r.winner).length,
        with_stats: rows.filter(r => r.calibrating && r.kills != null).length,
      },
    };
  }

  // ----- friends -----
  friendRow(a, b) { return this.one("SELECT * FROM friends WHERE (from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?)", a, b, b, a); }
  friendState(me, other) {
    const r = this.friendRow(me, other);
    if (!r) return "none";
    if (r.status === "accepted") return "friends";
    return r.from_id === me ? "outgoing" : "incoming";
  }

  // ----- telegram -----
  async tg(method, params) {
    const r = await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/${method}`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(params),
    });
    return r.json();
  }
  async send(chatId, text, markup) {
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
    this.sql.exec("UPDATE match_players SET ready = 0 WHERE match_id = ?", mid);
    this.sql.exec("UPDATE matches SET status = 'ready', ready_deadline = ? WHERE id = ?", now() + READY_SEC, mid);
    await this.scheduleAlarm();
    const m = this.match(mid);
    await this.notify(m.players.map(p => p.tg_id), `🔔 <b>Лобби ${m.lobby_no} собрано!</b>\nПодтверди готовность за ${READY_SEC} сек, иначе вылетишь из лобби.`,
      this.appButton("✅ Я готов"));
  }

  async readyTimeout(mid) {
    const m = this.match(mid);
    const notReady = m.players.filter(p => !p.ready);
    for (const p of notReady) this.sql.exec("DELETE FROM match_players WHERE match_id = ? AND tg_id = ?", mid, p.tg_id);
    this.sql.exec("UPDATE matches SET status = 'open', ready_deadline = NULL WHERE id = ?", mid);
    this.sql.exec("UPDATE match_players SET ready = 0 WHERE match_id = ?", mid);
    await this.notify(notReady.map(p => p.tg_id), `⏰ Ты не подтвердил готовность — тебя убрали из лобби ${m.lobby_no}.`);
    await this.notify(m.players.filter(p => p.ready).map(p => p.tg_id),
      `😕 Не все подтвердили готовность (${notReady.map(p => esc(p.nick)).join(", ")}). Лобби ${m.lobby_no} ждёт ещё ${notReady.length} игроков.`);
  }

  // ----- veto -----
  async startVeto(mid) {
    const m = this.match(mid);
    const [cap1, cap2] = shuffle(m.players.map(p => p.tg_id)).slice(0, 2);
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

  async reportResult(m, uid, winner, score) {
    const admins = this.adminIds();
    if (!admins.length || this.isAdmin(uid)) return this.applyResult(m.id, winner, score);
    this.sql.exec("UPDATE matches SET status = 'pending', pending_winner = ?, pending_score = ?, reported_by = ? WHERE id = ?", winner, score, uid, m.id);
    const text = `📝 <b>Результат на проверку</b> · матч #${m.id} (${esc(m.map)})\n` +
      `${esc(this.nick(m, uid))} пишет: победила <b>Команда ${winner}</b>${score ? ` ${esc(score)}` : ""}\n\n${this.teamsText(m)}`;
    await this.notify(admins, text, { inline_keyboard: [[
      { text: "✅ Подтвердить", callback_data: `ok:${m.id}` }, { text: "❌ Отклонить", callback_data: `no:${m.id}` },
    ]] });
    await this.notify(m.players.map(p => p.tg_id).filter(id => id !== uid),
      `📝 Матч #${m.id}: результат отправлен админу на проверку (победила Команда ${winner}${score ? ` ${esc(score)}` : ""}).\nНе забудь вписать свои убийства и смерти в приложении.`,
      this.appButton("📊 Вписать K/D"));
  }

  async rejectResult(mid, byId) {
    const m = this.match(mid);
    if (m?.status !== "pending") throw new ApiError("Нет результата на проверке");
    this.sql.exec("UPDATE matches SET status = 'live', pending_winner = NULL, pending_score = NULL, reported_by = NULL WHERE id = ?", mid);
    await this.notify([m.captain1, m.captain2], `❌ Админ отклонил результат матча #${mid}. Отправь правильный результат ещё раз.`, this.appButton());
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
    const mvp = this.computeMvp(mid);
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
        ready_sec: READY_SEC, placement_max_level: level(PLACEMENT_MAX), calibration_mult: CALIBRATION_MULT, season, season_name: seasonName(season), season_days_left: Math.ceil((end - Date.now()) / 86400000) };
    }

    if (method === "GET" && path === "/me") {
      this.sql.exec("UPDATE players SET last_seen = ? WHERE tg_id = ?", now(), uid);
      let p = this.player(uid);
      if (p && user.photo && p.tg_photo !== user.photo) {
        this.sql.exec("UPDATE players SET tg_photo = ?, photo = CASE WHEN custom_photo = 1 THEN photo ELSE ? END WHERE tg_id = ?", user.photo, user.photo, uid);
        p = this.player(uid);
      }
      const pendingCount = isAdmin ? this.one("SELECT COUNT(*) AS n FROM matches WHERE status = 'pending'").n : 0;
      const friendReq = this.one("SELECT COUNT(*) AS n FROM friends WHERE to_id = ? AND status = 'pending'", uid).n;
      return { user, player: p ? this.publicPlayer(p) : null, rank: this.rankOf(uid), active_match: this.activeMatchOf(uid), is_admin: isAdmin, pending_count: pendingCount, friend_requests: friendReq };
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

    if (method === "GET" && (mm = path.match(/^\/matches\/(\d+)$/))) return this.publicMatch(getMatch(+mm[1]));

    if (method === "GET" && path === "/leaderboard") {
      return this.q("SELECT tg_id, nick, game_id, photo, elo, wins, losses, created_at, badges, banned_until FROM players ORDER BY elo DESC, wins DESC")
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

    // ----- friends -----
    if (method === "GET" && path === "/friends") {
      const rows = this.q("SELECT * FROM friends WHERE from_id = ? OR to_id = ?", uid, uid);
      const card = id => {
        const p = this.player(id);
        if (!p) return null;
        const pp = this.publicPlayer(p);
        const am = this.activeMatchOf(id), st = am ? this.one("SELECT status FROM matches WHERE id = ?", am).status : null;
        return { tg_id: id, nick: pp.nick, photo: pp.photo, game_id: pp.game_id, level: pp.level, elo: pp.elo, calibrated: pp.calibrated,
          calib_played: pp.calib_played, online: pp.online, last_seen: p.last_seen, in_lobby: st === "open" || st === "ready", in_match: ["veto", "live", "pending"].includes(st) };
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
            this.sql.exec("DELETE FROM admins WHERE tg_id = ?", id);
            return { ok: true };
          }
        }
      }
      throw new ApiError("Неизвестный запрос");
    }

    if (method !== "POST" || !(mm = path.match(/^\/lobbies\/(\d+)\/(\w+)$/))) throw new ApiError("Неизвестный запрос");
    const mid = +mm[1], action = mm[2];
    const m = getMatch(mid);
    const ids = m.players.map(p => p.tg_id);

    switch (action) {
      case "join": {
        const p = requirePlayer();
        if ((p.banned_until || 0) > now()) throw new ApiError(`Ты забанен до ${new Date(p.banned_until * 1000).toLocaleDateString("ru")}`);
        if (m.status !== "open") throw new ApiError("Лобби уже не открыто");
        if (ids.includes(uid)) return { ok: true };
        if (this.activeMatchOf(uid)) throw new ApiError("Ты уже в другом лобби или матче");
        if (ids.length >= LOBBY_SIZE) throw new ApiError("Лобби заполнено");
        this.sql.exec("INSERT OR IGNORE INTO match_players (match_id, tg_id, joined_at) VALUES (?, ?, ?)", mid, uid, Date.now() / 1000);
        if (ids.length + 1 === LOBBY_SIZE) await this.startReady(mid);
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
        if (!isCaptain(m) && !isAdmin) throw new ApiError("Результат отправляет капитан");
        if (m.status !== "live") throw new ApiError(m.status === "pending" ? "Результат уже на проверке у админа" : "Матч не идёт");
        const winner = Number(body.winner);
        await this.reportResult(m, uid, winner, parseScore(winner, body));
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
      if (update.message?.text) await this.handleMessage(update.message);
      else if (update.callback_query) await this.handleCallback(update.callback_query);
    } catch (e) { console.log("update failed", e.stack); }
    return new Response("ok");
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
    await this.tg("editMessageText", { chat_id: cq.message.chat.id, message_id: cq.message.message_id, parse_mode: "HTML",
      text: `${act === "ok" ? "✅ Подтверждено" : "❌ Отклонено"}: матч #${mid} (${esc(m.map)}) — Команда ${m.pending_winner} ${esc(m.pending_score || "")}` });
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
      const rows = this.q(`SELECT nick, elo FROM players WHERE wins + losses >= ${CALIBRATION_GAMES} ORDER BY elo DESC, wins DESC LIMIT 10`);
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
