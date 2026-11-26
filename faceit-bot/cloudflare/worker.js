// SO2 Arena на Cloudflare Workers: Mini App + API + webhook Telegram-бота.
// Все данные хранятся в одном Durable Object со встроенной SQLite.
import { DurableObject } from "cloudflare:workers";
import INDEX_HTML from "./index.html";

const MODES = { "5x5": 10, "2x2": 4 };
const K_FACTOR = 50;
// [уровень, нижняя граница ELO]
const LEVELS = [[1, 0], [2, 800], [3, 950], [4, 1100], [5, 1250], [6, 1400], [7, 1550], [8, 1700], [9, 1850], [10, 2000]];
const DEFAULT_MAPS = "Sandstone,Rust,Province,Hanami,Prison,Dune,Breeze";
const CALIBRATION_GAMES = 10;
const CALIBRATION_MULT = 2; // на калибровке ELO меняется в 2 раза сильнее
const START_ELO = 1000;
const NICK_RE = /^[\p{L}\p{N}_\-.\[\]|★☆ ]{2,20}$/u;

// ---------- ELO ----------
const level = elo => LEVELS.reduce((l, [lv, low]) => (elo >= low ? lv : l), 1);
const nextLevelAt = elo => (LEVELS.find(([, low]) => low > elo) || [])[1] ?? null;

function combinations(arr, k, start = 0, cur = [], out = []) {
  if (cur.length === k) { out.push(cur.slice()); return out; }
  for (let i = start; i < arr.length; i++) { cur.push(arr[i]); combinations(arr, k, i + 1, cur, out); cur.pop(); }
  return out;
}

function balance(players) {
  const ps = players.slice().sort(() => Math.random() - 0.5);
  const n = ps.length / 2, total = ps.reduce((s, p) => s + p.elo, 0);
  const [first, ...rest] = ps;
  let best = null, bestDiff = Infinity;
  for (const combo of combinations(rest, n - 1)) {
    const team = [first, ...combo];
    const diff = Math.abs(total - 2 * team.reduce((s, p) => s + p.elo, 0));
    if (diff < bestDiff) { best = team; bestDiff = diff; }
  }
  const ids = new Set(best.map(p => p.tg_id));
  return Object.fromEntries(ps.map(p => [p.tg_id, ids.has(p.tg_id) ? 1 : 2]));
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
    try { this.sql.exec("ALTER TABLE match_players ADD COLUMN calibrating INTEGER NOT NULL DEFAULT 0"); } catch {}
    this.maps = (env.MAPS || DEFAULT_MAPS).split(",").map(s => s.trim()).filter(Boolean);
    this.admins = new Set((env.ADMIN_IDS || "").split(",").map(s => Number(s.trim())).filter(Boolean));
  }

  q(query, ...b) { return this.sql.exec(query, ...b).toArray(); }
  one(query, ...b) { return this.q(query, ...b)[0] || null; }

  // ----- db -----
  player(id) { return this.one("SELECT * FROM players WHERE tg_id = ?", id); }
  rankOf(id) {
    const p = this.player(id);
    if (!p || !this.isCalibrated(p)) return null;
    return this.one(`SELECT COUNT(*) AS n FROM players WHERE elo > ? AND wins + losses >= ${CALIBRATION_GAMES}`, p.elo).n + 1;
  }
  match(id) {
    const m = this.one("SELECT * FROM matches WHERE id = ?", id);
    if (!m) return null;
    m.players = this.q(`SELECT mp.tg_id, mp.team, mp.elo_before, mp.elo_delta, mp.calibrating, p.nick, p.elo, p.game_id, p.tg_username,
        p.wins + p.losses AS games
      FROM match_players mp JOIN players p ON p.tg_id = mp.tg_id WHERE mp.match_id = ? ORDER BY mp.joined_at`, id);
    return m;
  }
  activeMatchOf(id) {
    const r = this.one(`SELECT m.id FROM matches m JOIN match_players mp ON mp.match_id = m.id
      WHERE mp.tg_id = ? AND m.status IN ('open','live')`, id);
    return r ? r.id : null;
  }
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
    m.team_avg = {};
    for (const t of [1, 2]) {
      const ps = m.players.filter(p => p.team === t);
      if (ps.length) m.team_avg[t] = Math.round(ps.reduce((s, p) => s + (p.elo_before ?? p.elo), 0) / ps.length);
    }
    m.players = m.players.map(p => {
      const calibrated = p.games >= CALIBRATION_GAMES;
      return { tg_id: p.tg_id, team: p.team, nick: p.nick, calibrated, calib_played: Math.min(p.games, CALIBRATION_GAMES),
        level: calibrated ? level(p.elo) : null, elo: calibrated ? p.elo : null };
    });
    m.size = MODES[m.mode];
    return m;
  }
  isCalibrated(p) { return p.wins + p.losses >= CALIBRATION_GAMES; }

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
  notify(ids, text) { return Promise.all(ids.map(id => this.send(id, text))); }
  notifyGroup(text) {
    const chat = Number(this.env.NOTIFY_CHAT_ID || 0);
    if (!chat) return;
    const u = this.env.BOT_USERNAME;
    return this.send(chat, text, u ? { inline_keyboard: [[{ text: "🎮 Открыть", url: `https://t.me/${u}?start=play` }]] } : null);
  }
  appButton(text = "🎮 Открыть приложение") {
    return { inline_keyboard: [[{ text, web_app: { url: this.origin } }]] };
  }
  teamsText(m) {
    return [1, 2].map(t => {
      const ps = m.players.filter(p => p.team === t);
      const avg = ps.length ? Math.round(ps.reduce((s, p) => s + p.elo, 0) / ps.length) : 0;
      return [`<b>Команда ${t}</b> (ср. ${avg} ELO)`, ...ps.map(p => `  • ${esc(p.nick)} — ${
        p.games >= CALIBRATION_GAMES ? `${level(p.elo)} lvl` : `калибровка ${p.games}/${CALIBRATION_GAMES}`}`)].join("\n");
    }).join("\n");
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
        user = { id: u.id, username: u.username || null, name: [u.first_name, u.last_name].filter(Boolean).join(" ") };
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
    const requireHost = m => { if (m.creator_id !== uid && !isAdmin) throw new ApiError("Это может сделать только хост лобби или админ"); };
    let mm;

    if (method === "GET" && path === "/config") return { maps: this.maps, modes: MODES, levels: LEVELS, calibration_games: CALIBRATION_GAMES };

    if (method === "GET" && path === "/me") {
      const p = this.player(uid);
      return { user, player: p ? this.publicPlayer(p) : null, rank: this.rankOf(uid), active_match: this.activeMatchOf(uid), is_admin: isAdmin };
    }

    if (method === "POST" && path === "/register") {
      const nick = String(body.nick || "").trim();
      const gameId = String(body.game_id || "").replace(/\D/g, "").slice(0, 15);
      if (!NICK_RE.test(nick)) throw new ApiError("Ник: 2–20 символов");
      if (this.one("SELECT 1 AS x FROM players WHERE lower(nick) = lower(?) AND tg_id != ?", nick, uid)) throw new ApiError("Этот ник уже занят");
      this.sql.exec(`INSERT INTO players (tg_id, tg_username, tg_name, nick, game_id, elo, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(tg_id) DO UPDATE SET nick = excluded.nick, game_id = excluded.game_id, tg_username = excluded.tg_username, tg_name = excluded.tg_name`,
        uid, user.username, user.name, nick, gameId, START_ELO, now());
      return { ok: true };
    }

    if (method === "GET" && path === "/lobbies") {
      return this.q("SELECT id FROM matches WHERE status IN ('open','live') ORDER BY id DESC").map(r => this.publicMatch(this.match(r.id)));
    }

    if (method === "GET" && (mm = path.match(/^\/matches\/(\d+)$/))) return this.publicMatch(getMatch(+mm[1]));

    if (method === "POST" && path === "/lobbies") {
      const p = requirePlayer();
      if (this.activeMatchOf(uid)) throw new ApiError("Ты уже в другом лобби");
      if (!MODES[body.mode]) throw new ApiError("Неверный режим");
      let map = body.map || "random";
      if (map === "random") map = this.maps[Math.floor(Math.random() * this.maps.length)];
      else if (!this.maps.includes(map)) throw new ApiError("Неверная карта");
      const id = this.one("INSERT INTO matches (mode, map, status, creator_id, created_at) VALUES (?, ?, 'open', ?, ?) RETURNING id",
        body.mode, map, uid, now()).id;
      this.sql.exec("INSERT INTO match_players (match_id, tg_id, joined_at) VALUES (?, ?, ?)", id, uid, Date.now() / 1000);
      await this.notifyGroup(`🆕 <b>${esc(p.nick)}</b> создал лобби #${id}: ${body.mode}, ${esc(map)}. Залетайте!`);
      return { id };
    }

    if (method === "GET" && path === "/leaderboard") {
      // вся база игроков: сначала откалиброванные по ELO, потом те, кто на калибровке
      return this.q("SELECT tg_id, nick, game_id, elo, wins, losses, created_at FROM players ORDER BY elo DESC, wins DESC")
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

    switch (action) {
      case "join": {
        requirePlayer();
        if (m.status !== "open") throw new ApiError("Лобби уже не открыто");
        if (m.players.some(p => p.tg_id === uid)) return { ok: true };
        if (this.activeMatchOf(uid)) throw new ApiError("Ты уже в другом лобби");
        if (m.players.length >= MODES[m.mode]) throw new ApiError("Лобби заполнено");
        this.sql.exec("INSERT OR IGNORE INTO match_players (match_id, tg_id, joined_at) VALUES (?, ?, ?)", mid, uid, Date.now() / 1000);
        if (m.players.length + 1 === MODES[m.mode]) await this.send(m.creator_id, `✅ Лобби #${mid} собрано — можно стартовать!`);
        return { ok: true };
      }
      case "leave": {
        if (m.status !== "open") throw new ApiError("Из начатого матча выйти нельзя");
        this.sql.exec("DELETE FROM match_players WHERE match_id = ? AND tg_id = ?", mid, uid);
        const rest = m.players.filter(p => p.tg_id !== uid);
        if (!rest.length) this.sql.exec("UPDATE matches SET status = 'cancelled' WHERE id = ?", mid);
        else if (m.creator_id === uid) this.sql.exec("UPDATE matches SET creator_id = ? WHERE id = ?", rest[0].tg_id, mid);
        return { ok: true };
      }
      case "kick": {
        requireHost(m);
        if (m.status !== "open") throw new ApiError("Лобби уже не открыто");
        const target = Number(body.tg_id);
        if (target === m.creator_id) throw new ApiError("Нельзя кикнуть хоста");
        this.sql.exec("DELETE FROM match_players WHERE match_id = ? AND tg_id = ?", mid, target);
        return { ok: true };
      }
      case "room": {
        requireHost(m);
        const room = String(body.room || "").trim().slice(0, 60);
        this.sql.exec("UPDATE matches SET room = ? WHERE id = ?", room, mid);
        if (m.status === "live" && room) await this.notify(m.players.map(p => p.tg_id), `🔑 Матч #${mid}: комната <code>${esc(room)}</code>`);
        return { ok: true };
      }
      case "start": {
        requireHost(m);
        if (m.status !== "open") throw new ApiError("Матч уже начат");
        if (m.players.length !== MODES[m.mode]) throw new ApiError(`Нужно ${MODES[m.mode]} игроков`);
        const teams = balance(m.players);
        for (const [id, team] of Object.entries(teams)) {
          this.sql.exec(`UPDATE match_players SET team = ?, elo_before = (SELECT elo FROM players WHERE tg_id = ?),
            calibrating = (SELECT wins + losses < ${CALIBRATION_GAMES} FROM players WHERE tg_id = ?)
            WHERE match_id = ? AND tg_id = ?`, team, +id, +id, mid, +id);
        }
        this.sql.exec("UPDATE matches SET status = 'live', started_at = ? WHERE id = ?", now(), mid);
        const m2 = this.match(mid);
        const room = m2.room ? `\n🔑 Комната: <code>${esc(m2.room)}</code>` : "";
        const host = m2.players.find(p => p.tg_id === m2.creator_id);
        await this.notify(m2.players.map(p => p.tg_id),
          `🔥 <b>Матч #${mid} начался!</b> ${m2.mode} · ${esc(m2.map)}\nХост: ${esc(host?.nick)}${room}\n\n${this.teamsText(m2)}`);
        return { ok: true };
      }
      case "result": {
        requireHost(m);
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
        requireHost(m);
        if (!["open", "live"].includes(m.status)) throw new ApiError("Матч уже завершён");
        this.sql.exec("UPDATE matches SET status = 'cancelled' WHERE id = ?", mid);
        if (m.status === "live") await this.notify(m.players.map(p => p.tg_id), `❌ Матч #${mid} отменён, ELO не изменилось.`);
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
      return this.send(chatId, `${hello}\n\nВ приложении можно:\n• создать лобби 5x5 или 2x2 и собрать друзей\n` +
        "• автоматически поделить команды по ELO\n• записать результат и получить ±ELO\n• смотреть рейтинг и свою историю\n\n" +
        `Первые ${CALIBRATION_GAMES} матчей — калибровка, после неё получишь уровень.`, this.appButton());
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
