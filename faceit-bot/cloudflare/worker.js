// SO2 Arena на Cloudflare Workers: Mini App + API + webhook Telegram-бота.
// Все данные хранятся в одном Durable Object со встроенной SQLite.
//
// Жизненный цикл матча:
//   open  — постоянное лобби («Лобби 1», «Лобби 2»), игроки заходят и выходят;
//   veto  — набралось 10: выбраны 2 капитана и игрок-хост, капитаны по очереди банят карты;
//   live  — осталась одна карта, игра идёт; капитан или админ вносит результат;
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
const CALIBRATION_MULT = 2; // на калибровке ELO меняется в 2 раза сильнее
const START_ELO = 1000;
const VETO_TURN_SEC = 45;   // время на один бан, потом — случайный автобан
const NICK_RE = /^[\p{L}\p{N}_\-.\[\]|★☆ ]{2,20}$/u;

// ---------- ELO ----------
const level = elo => LEVELS.reduce((l, [lv, low]) => (elo >= low ? lv : l), 1);
const nextLevelAt = elo => (LEVELS.find(([, low]) => low > elo) || [])[1] ?? null;
const pick = arr => arr[Math.floor(Math.random() * arr.length)];
const shuffle = arr => { const a = arr.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };

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

// players: [{tg_id, team, elo_before, calibrating}]
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

// ---------- utils ----------
const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json; charset=utf-8" } });
const now = () => Math.floor(Date.now() / 1000);
class ApiError extends Error {}

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
  const expected = hex(await hmac(secret, dcs));
  if (!hash || expected !== hash) throw new Error("bad hash");
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
    if (url.pathname.startsWith("/api/") || url.pathname === "/webhook") {
      return env.ARENA.get(env.ARENA.idFromName("main")).fetch(request);
    }
    return new Response("Not found", { status: 404 });
  },
};

// ---------- Durable Object: вся логика и база ----------
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
    // миграции для старых баз
    for (const ddl of [
      "ALTER TABLE match_players ADD COLUMN calibrating INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE matches ADD COLUMN lobby_no INTEGER",
      "ALTER TABLE matches ADD COLUMN captain1 INTEGER",
      "ALTER TABLE matches ADD COLUMN captain2 INTEGER",
      "ALTER TABLE matches ADD COLUMN bans TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE matches ADD COLUMN veto_deadline INTEGER",
      "ALTER TABLE players ADD COLUMN photo TEXT",
    ]) { try { this.sql.exec(ddl); } catch {} }
    // лобби старого формата (созданные вручную) больше не используются
    this.sql.exec("UPDATE matches SET status = 'cancelled' WHERE status = 'open' AND lobby_no IS NULL");

    this.maps = (env.MAPS || DEFAULT_MAPS).split(",").map(s => s.trim()).filter(Boolean);
    this.admins = new Set((env.ADMIN_IDS || "").split(",").map(s => Number(s.trim())).filter(Boolean));
    this.lobbyCount = Math.max(1, Number(env.LOBBY_COUNT || 2));
    this.ensureLobbies();
  }

  q(query, ...b) { return this.sql.exec(query, ...b).toArray(); }
  one(query, ...b) { return this.q(query, ...b)[0] || null; }

  // ----- lobbies -----
  ensureLobbies() {
    for (let no = 1; no <= this.lobbyCount; no++) {
      if (!this.one("SELECT id FROM matches WHERE status = 'open' AND lobby_no = ?", no)) {
        this.sql.exec("INSERT INTO matches (mode, map, status, creator_id, lobby_no, created_at) VALUES ('5x5', '', 'open', 0, ?, ?)", no, now());
      }
    }
  }

  // ----- db -----
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
    m.players = this.q(`SELECT mp.tg_id, mp.team, mp.elo_before, mp.elo_delta, mp.calibrating, p.nick, p.elo, p.game_id, p.tg_username, p.photo,
        p.wins + p.losses AS games
      FROM match_players mp JOIN players p ON p.tg_id = mp.tg_id WHERE mp.match_id = ? ORDER BY mp.joined_at`, id);
    return m;
  }
  activeMatchOf(id) {
    const r = this.one(`SELECT m.id FROM matches m JOIN match_players mp ON mp.match_id = m.id
      WHERE mp.tg_id = ? AND m.status IN ('open','veto','live')`, id);
    return r ? r.id : null;
  }
  vetoTurn(m) { return m.bans.length % 2 === 0 ? m.captain1 : m.captain2; }
  nick(m, id) { return m.players.find(p => p.tg_id === id)?.nick ?? "?"; }

  // До конца калибровки ELO и уровень скрыты
  publicPlayer(p) {
    const games = p.wins + p.losses, calibrated = games >= CALIBRATION_GAMES;
    return {
      ...p, games, calibrated, calib_played: Math.min(games, CALIBRATION_GAMES), calib_total: CALIBRATION_GAMES,
      elo: calibrated ? p.elo : null, level: calibrated ? level(p.elo) : null,
      next_level_at: calibrated ? nextLevelAt(p.elo) : null,
    };
  }
  publicMatch(m) {
    const out = {
      id: m.id, lobby_no: m.lobby_no, status: m.status, mode: m.mode, map: m.map, room: m.room, score: m.score, winner: m.winner,
      size: LOBBY_SIZE, captain1: m.captain1, captain2: m.captain2, host_id: m.creator_id || null,
      bans: m.bans, remaining: this.maps.filter(x => !m.bans.some(b => b.map === x)),
      veto_turn: m.status === "veto" ? this.vetoTurn(m) : null,
      veto_left: m.status === "veto" && m.veto_deadline ? Math.max(0, m.veto_deadline - now()) : null,
      team_avg: {},
    };
    for (const t of [1, 2]) {
      const ps = m.players.filter(p => p.team === t);
      if (ps.length) out.team_avg[t] = Math.round(ps.reduce((s, p) => s + (p.elo_before ?? p.elo), 0) / ps.length);
    }
    out.players = m.players.map(p => {
      const calibrated = p.games >= CALIBRATION_GAMES;
      return { tg_id: p.tg_id, team: p.team, nick: p.nick, game_id: p.game_id, photo: p.photo, calibrated, calib_played: Math.min(p.games, CALIBRATION_GAMES),
        level: calibrated ? level(p.elo) : null, elo: calibrated ? p.elo : null };
    });
    const host = m.players.find(p => p.tg_id === m.creator_id);
    out.host_nick = host?.nick ?? null;
    out.host_game_id = host?.game_id ?? null;
    return out;
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
  notifyGroup(text) {
    const chat = Number(this.env.NOTIFY_CHAT_ID || 0);
    if (!chat) return;
    const u = this.env.BOT_USERNAME;
    return this.send(chat, text, u ? { inline_keyboard: [[{ text: "🎮 Открыть", url: `https://t.me/${u}?start=play` }]] } : null);
  }
  appButton(text = "🎮 Открыть приложение") {
    return this.origin ? { inline_keyboard: [[{ text, web_app: { url: this.origin } }]] } : null;
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
    this.sql.exec(`UPDATE matches SET status = 'veto', captain1 = ?, captain2 = ?, creator_id = ?, bans = '[]', veto_deadline = ?
      WHERE id = ?`, cap1, cap2, host, now() + VETO_TURN_SEC, mid);
    this.ensureLobbies();
    await this.scheduleAlarm();
    const m2 = this.match(mid);
    await this.notify(m2.players.map(p => p.tg_id),
      `🔔 <b>Лобби ${m2.lobby_no} собрано!</b> Матч #${mid}\n\nКапитаны: <b>${esc(this.nick(m2, cap1))}</b> vs <b>${esc(this.nick(m2, cap2))}</b>\n` +
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
      await this.notify(m2.players.map(p => p.tg_id),
        `🔥 <b>Матч #${mid}: играем на ${esc(left[0])}!</b>\n${this.hostText(m2)}\n\n${this.teamsText(m2)}`);
      await this.send(m2.creator_id, `👑 <b>Ты создаёшь лобби в игре.</b> Создай комнату на ${esc(left[0])} и впиши её код в приложении — все увидят.`,
        this.appButton("🔑 Вписать код комнаты"));
    } else {
      this.sql.exec("UPDATE matches SET bans = ?, veto_deadline = ? WHERE id = ?", JSON.stringify(m.bans), now() + VETO_TURN_SEC, mid);
      const next = this.vetoTurn(m);
      await this.send(next, `🗺 Матч #${mid}: ${esc(this.nick(m, byId))} забанил ${esc(map)}${auto ? " (авто)" : ""}. Твой ход — бань (${VETO_TURN_SEC} сек).`,
        this.appButton("Забанить карту"));
    }
    await this.scheduleAlarm();
  }

  async scheduleAlarm() {
    const r = this.one("SELECT MIN(veto_deadline) AS t FROM matches WHERE status = 'veto' AND veto_deadline IS NOT NULL");
    if (r?.t) await this.ctx.storage.setAlarm(r.t * 1000);
    else await this.ctx.storage.deleteAlarm();
  }

  // капитан не успел — случайный бан за него
  async alarm() {
    for (const r of this.q("SELECT id FROM matches WHERE status = 'veto' AND veto_deadline <= ?", now())) {
      const m = this.match(r.id);
      const remaining = this.maps.filter(x => !m.bans.some(b => b.map === x));
      try { await this.ban(m.id, this.vetoTurn(m), pick(remaining), true); } catch (e) { console.log("autoban", e.message); }
    }
    await this.scheduleAlarm();
  }

  // ----- http -----
  async fetch(request) {
    const url = new URL(request.url);
    this.origin = url.origin;
    if (url.pathname === "/webhook") return this.webhook(request);

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
    const isAdmin = this.admins.has(uid);
    const requirePlayer = () => { const p = this.player(uid); if (!p) throw new ApiError("Сначала зарегистрируйся"); return p; };
    const getMatch = id => { const m = this.match(id); if (!m) throw new ApiError("Матч не найден"); return m; };
    const isCaptain = m => m.captain1 === uid || m.captain2 === uid;
    let mm;

    if (method === "GET" && path === "/config") {
      return { maps: this.maps, levels: LEVELS, calibration_games: CALIBRATION_GAMES, lobby_size: LOBBY_SIZE, veto_turn_sec: VETO_TURN_SEC };
    }

    if (method === "GET" && path === "/me") {
      let p = this.player(uid);
      if (p && user.photo && p.photo !== user.photo) {  // обновляем аватар из Telegram
        this.sql.exec("UPDATE players SET photo = ? WHERE tg_id = ?", user.photo, uid);
        p = this.player(uid);
      }
      return { user, player: p ? this.publicPlayer(p) : null, rank: this.rankOf(uid), active_match: this.activeMatchOf(uid), is_admin: isAdmin };
    }

    if (method === "POST" && path === "/register") {
      const nick = String(body.nick || "").trim();
      const gameId = String(body.game_id || "").replace(/\D/g, "").slice(0, 15);
      if (!NICK_RE.test(nick)) throw new ApiError("Ник: 2–20 символов");
      if (this.one("SELECT 1 AS x FROM players WHERE lower(nick) = lower(?) AND tg_id != ?", nick, uid)) throw new ApiError("Этот ник уже занят");
      this.sql.exec(`INSERT INTO players (tg_id, tg_username, tg_name, nick, game_id, elo, created_at, photo) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(tg_id) DO UPDATE SET nick = excluded.nick, game_id = excluded.game_id, tg_username = excluded.tg_username,
          tg_name = excluded.tg_name, photo = COALESCE(excluded.photo, players.photo)`,
        uid, user.username, user.name, nick, gameId, START_ELO, now(), user.photo || null);
      return { ok: true };
    }

    if (method === "GET" && path === "/lobbies") {
      this.ensureLobbies();
      return this.q(`SELECT id FROM matches WHERE status IN ('open','veto','live')
          ORDER BY CASE status WHEN 'open' THEN 1 ELSE 0 END, CASE status WHEN 'open' THEN lobby_no ELSE -id END`)
        .map(r => this.publicMatch(this.match(r.id)));
    }

    if (method === "GET" && (mm = path.match(/^\/matches\/(\d+)$/))) return this.publicMatch(getMatch(+mm[1]));

    if (method === "GET" && path === "/leaderboard") {
      // вся база игроков: сначала откалиброванные по ELO, потом те, кто на калибровке
      return this.q("SELECT tg_id, nick, game_id, photo, elo, wins, losses, created_at FROM players ORDER BY elo DESC, wins DESC")
        .map(r => this.publicPlayer(r))
        .sort((a, b) => (b.calibrated - a.calibrated) || (a.calibrated ? 0 : b.calib_played - a.calib_played));
    }

    if (method === "GET" && (mm = path.match(/^\/players\/(\d+)$/))) {
      const id = +mm[1];
      const p = this.player(id);
      if (!p) throw new ApiError("Игрок не найден");
      const history = this.q(`SELECT m.id, m.mode, m.map, m.score, m.winner, m.finished_at, mp.team, mp.elo_delta, mp.calibrating
        FROM match_players mp JOIN matches m ON m.id = mp.match_id
        WHERE mp.tg_id = ? AND m.status = 'finished' ORDER BY m.finished_at DESC, m.id DESC LIMIT 20`, id);
      // дельты калибровочных матчей не показываем, пока игрок не откалиброван
      if (!this.isCalibrated(p)) history.forEach(h => (h.elo_delta = null));
      return { player: this.publicPlayer(p), rank: this.rankOf(id), history };
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
        if (this.activeMatchOf(uid)) throw new ApiError("Ты уже в другом лобби или матче");
        if (ids.length >= LOBBY_SIZE) throw new ApiError("Лобби заполнено");
        this.sql.exec("INSERT OR IGNORE INTO match_players (match_id, tg_id, joined_at) VALUES (?, ?, ?)", mid, uid, Date.now() / 1000);
        if (ids.length + 1 === LOBBY_SIZE) await this.startVeto(mid);
        return { ok: true };
      }
      case "leave": {
        if (m.status !== "open") throw new ApiError("Из начатого матча выйти нельзя");
        this.sql.exec("DELETE FROM match_players WHERE match_id = ? AND tg_id = ?", mid, uid);
        return { ok: true };
      }
      case "kick": {
        if (!isAdmin) throw new ApiError("Кикать может только админ");
        if (m.status !== "open") throw new ApiError("Лобби уже не открыто");
        this.sql.exec("DELETE FROM match_players WHERE match_id = ? AND tg_id = ?", mid, Number(body.tg_id));
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
        if (!isCaptain(m) && !isAdmin) throw new ApiError("Результат вносит капитан или админ");
        if (m.status !== "live") throw new ApiError("Матч не идёт");
        const winner = Number(body.winner);
        if (winner !== 1 && winner !== 2) throw new ApiError("Выбери победителя");
        const s1 = Number(body.score1) || 0, s2 = Number(body.score2) || 0;
        if (s1 < 0 || s1 > 99 || s2 < 0 || s2 > 99 || ((s1 || s2) && (s1 > s2) !== (winner === 1))) throw new ApiError("Счёт не совпадает с победителем");
        const score = s1 || s2 ? `${s1}:${s2}` : "";
        const d = deltas(m.players, winner);
        for (const p of m.players) {
          const won = p.team === winner;
          this.sql.exec("UPDATE match_players SET elo_delta = ? WHERE match_id = ? AND tg_id = ?", d[p.tg_id], mid, p.tg_id);
          this.sql.exec(`UPDATE players SET elo = MAX(100, elo + ?), ${won ? "wins = wins + 1" : "losses = losses + 1"} WHERE tg_id = ?`, d[p.tg_id], p.tg_id);
        }
        this.sql.exec("UPDATE matches SET status = 'finished', winner = ?, score = ?, finished_at = ? WHERE id = ?", winner, score, now(), mid);
        const m2 = this.match(mid);
        await Promise.all(m2.players.map(p => {
          const won = p.team === winner;
          let text = `${won ? "🏆 Победа" : "💀 Поражение"} в матче #${mid} (${esc(m2.map)} ${score})\n`;
          if (p.games < CALIBRATION_GAMES) {
            text += `🎯 Калибровка: ${p.games}/${CALIBRATION_GAMES}`;
          } else if (p.calibrating) {
            text += `🎖 <b>Калибровка пройдена!</b>\nТвой уровень: <b>${level(p.elo)}</b> · ${p.elo} ELO`;
          } else {
            const up = level(p.elo) > level(p.elo_before), down = level(p.elo) < level(p.elo_before);
            text += `ELO: ${p.elo_before} → <b>${p.elo}</b> (${p.elo_delta >= 0 ? "+" : ""}${p.elo_delta})` +
              (up ? `\n🎉 Новый уровень: ${level(p.elo)}!` : down ? `\n📉 Уровень понижен до ${level(p.elo)}` : "");
          }
          return this.send(p.tg_id, text);
        }));
        const names = m2.players.filter(p => p.team === winner).map(p => esc(p.nick)).join(", ");
        await this.notifyGroup(`🏁 Матч #${mid} (${esc(m2.map)} ${score}) — победили: ${names}`);
        return { ok: true };
      }
      case "cancel": {
        if (!isCaptain(m) && !isAdmin) throw new ApiError("Отменить может капитан или админ");
        if (!["veto", "live"].includes(m.status)) throw new ApiError("Этот матч нельзя отменить");
        this.sql.exec("UPDATE matches SET status = 'cancelled', veto_deadline = NULL WHERE id = ?", mid);
        await this.scheduleAlarm();
        await this.notify(ids, `❌ Матч #${mid} отменён (${esc(this.nick(m, uid))}), ELO не изменилось.`);
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
      const msg = update.message;
      if (msg?.text) await this.handleMessage(msg);
    } catch (e) { console.log("update failed", e.stack); }
    return new Response("ok");
  }

  async handleMessage(msg) {
    const chatId = msg.chat.id, uid = msg.from.id, isPrivate = msg.chat.type === "private";
    const cmd = msg.text.split(/\s/)[0].split("@")[0].toLowerCase();
    if (cmd === "/start") {
      if (!isPrivate) return this.send(chatId, "Напиши мне в личку, чтобы открыть приложение 🙂");
      const p = this.player(uid);
      const hello = p ? `С возвращением, <b>${esc(p.nick)}</b>! ` + (this.isCalibrated(p)
          ? `${level(p.elo)} lvl · ${p.elo} ELO` : `Калибровка ${p.wins + p.losses}/${CALIBRATION_GAMES}`)
        : "Привет! Это наша площадка для матчей <b>Standoff 2</b> с ELO и рейтингом.";
      return this.send(chatId, `${hello}\n\nКак это работает:\n• заходи в свободное лобби 5x5\n` +
        "• когда соберётся 10 — выбираются 2 капитана, они банят карты\n• один из игроков создаёт комнату в игре\n" +
        `• после матча капитан вносит результат, всем ±ELO\n\nПервые ${CALIBRATION_GAMES} матчей — калибровка, после неё получишь уровень.`, this.appButton());
    }
    if (cmd === "/top") {
      const rows = this.q(`SELECT nick, elo FROM players WHERE wins + losses >= ${CALIBRATION_GAMES} ORDER BY elo DESC, wins DESC LIMIT 10`);
      if (!rows.length) return this.send(chatId, "Пока никто не прошёл калибровку.");
      const medals = ["🥇", "🥈", "🥉"];
      return this.send(chatId, "<b>Топ-10</b>\n\n" + rows.map((r, i) => `${medals[i] || i + 1 + "."} ${esc(r.nick)} — <b>${r.elo}</b> (${level(r.elo)} lvl)`).join("\n"),
        isPrivate ? this.appButton("📊 Весь рейтинг") : null);
    }
    if (cmd === "/me") {
      const p = this.player(uid);
      if (!p) return this.send(chatId, "Ты ещё не зарегистрирован — открой приложение.", isPrivate ? this.appButton() : null);
      const games = p.wins + p.losses, wr = games ? Math.round(p.wins * 100 / games) : 0;
      const head = this.isCalibrated(p) ? `${level(p.elo)} lvl · <b>${p.elo}</b> ELO · #${this.rankOf(uid)} в рейтинге`
        : `🎯 Калибровка: ${games}/${CALIBRATION_GAMES}`;
      return this.send(chatId, `<b>${esc(p.nick)}</b>\n${head}\nМатчей: ${games} · Побед: ${p.wins} · Винрейт: ${wr}%`);
    }
    if (cmd === "/id") return this.send(chatId, `Твой ID: <code>${uid}</code>\nID чата: <code>${chatId}</code>`);
  }
}
