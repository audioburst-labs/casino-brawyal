// Casino Brawyal telemetry: the ingest API the game POSTs to, and the
// dashboard the designer reads.
//
// The game never touches Postgres. It spools events to disk, and when it sees
// the internet it POSTs a batch here with a write-only API key. This service
// is the only thing holding a database credential, and it is what stamps the
// player's IP onto a play — a desktop client cannot see its own public
// address, and one it claimed would be a claim rather than a fact.
import { createServer } from "node:http";
import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import pg from "pg";

import { dashboardPage } from "./dashboard.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8080);
const API_KEY = process.env.CB_INGEST_KEY || "";
const CONN = process.env.CB_TELEMETRY_PG_URL || process.env.DATABASE_URL || "";
// The dashboard is read-only, but it is not for the public.
const VIEW_KEY = process.env.CB_DASHBOARD_KEY || "";

const MAX_BODY = 1_048_576;   // 1 MB
const MAX_EVENTS = 5_000;
const RATE_PER_MIN = 60;

// A missing connection string is a configuration state, not a crash. Exiting
// would put the container app in a restart loop that hides the real problem;
// this stays up, says exactly what is missing on /healthz and on the
// dashboard, and starts working the moment the secret is set.
// A placeholder or a typo must read as "not configured", not as a URL to
// parse - `new URL("UNSET")` throws at module load and puts the container in
// a restart loop that hides the real problem.
const CONFIGURED = /^postgres(ql)?:\/\//.test(CONN);
if (!CONFIGURED) {
  console.warn("CB_TELEMETRY_PG_URL is not set - serving in unconfigured mode");
}

// Azure Postgres requires TLS; a local container has none. Follow the URL
// rather than hardcoding either, so the same image runs in both places.
const sslmode = CONFIGURED ? (new URL(CONN).searchParams.get("sslmode") ?? "") : "";
const wantsTls = sslmode
  ? !["disable", "allow"].includes(sslmode)
  : !/@(localhost|127\.0\.0\.1)[:/]/.test(CONN);

function makePool(conn, tls) {
  return new pg.Pool({
    connectionString: conn,
    ssl: tls ? { rejectUnauthorized: false } : false,
    max: 4,
    idleTimeoutMillis: 30_000,
  });
}

let pool = CONFIGURED ? makePool(CONN, wantsTls) : null;
let configured = CONFIGURED;

// --------------------------------------------------------------- bootstrap
// Optional, one-shot, and normally absent: when CB_ADMIN_PG_URL is set the
// service creates its own database and least-privilege role before doing
// anything else, then connects as that role.
//
// This exists because the database's firewall does not admit every developer
// machine, but it does admit Azure ("AllowAzureServices") - so provisioning
// from in here beats opening a shared production server to an office IP.
// Remove the CB_ADMIN_PG_URL secret once it has run; the service does not need
// it again, and leaving an admin credential on a container that does not use
// it is exactly the kind of thing nobody notices for a year.
const ADMIN_URL = process.env.CB_ADMIN_PG_URL || "";
const ROLE_PASSWORD = process.env.CB_TELEMETRY_ROLE_PASSWORD || "";
const DB_NAME = "casino_brawyal";
const ROLE_NAME = "casino_telemetry";

async function bootstrap() {
  if (!/^postgres(ql)?:\/\//.test(ADMIN_URL) || !ROLE_PASSWORD) return null;
  const admin = new URL(ADMIN_URL);
  const base = { ssl: { rejectUnauthorized: false } };
  const sys = new pg.Client({
    connectionString: new URL("/postgres" + admin.search, admin).toString(), ...base });
  await sys.connect();
  try {
    const db = await sys.query("SELECT 1 FROM pg_database WHERE datname = $1", [DB_NAME]);
    if (db.rowCount === 0) {
      await sys.query(`CREATE DATABASE "${DB_NAME}"`);
      console.log("bootstrap: created database", DB_NAME);
    }
    const role = await sys.query("SELECT 1 FROM pg_roles WHERE rolname = $1", [ROLE_NAME]);
    if (role.rowCount === 0) {
      await sys.query(`CREATE ROLE "${ROLE_NAME}" WITH LOGIN PASSWORD $1`
        .replace("$1", "'" + ROLE_PASSWORD.replace(/'/g, "''") + "'"));
      console.log("bootstrap: created role", ROLE_NAME);
    } else {
      await sys.query(`ALTER ROLE "${ROLE_NAME}" WITH LOGIN PASSWORD $1`
        .replace("$1", "'" + ROLE_PASSWORD.replace(/'/g, "''") + "'"));
      console.log("bootstrap: role already existed, password re-asserted");
    }
    // It owns its own database and has no rights anywhere else on the server.
    await sys.query(`GRANT CONNECT ON DATABASE "${DB_NAME}" TO "${ROLE_NAME}"`);
    await sys.query(`ALTER DATABASE "${DB_NAME}" OWNER TO "${ROLE_NAME}"`);
    console.log("bootstrap: %s owns %s, and nothing else", ROLE_NAME, DB_NAME);
  } finally {
    await sys.end().catch(() => {});
  }
  const url = new URL(admin.toString());
  url.username = ROLE_NAME;
  url.password = ROLE_PASSWORD;
  url.pathname = "/" + DB_NAME;
  return url.toString();
}

// ---------------------------------------------------------------- migrations
// Applied on boot inside an advisory lock, so a scaled-out revision cannot
// race itself and nobody ever needs a psql client to deploy a schema change.
async function migrate() {
  const client = await pool.connect();
  try {
    await client.query("SELECT pg_advisory_lock(873_113_114)");
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      filename text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`);
    const dir = join(HERE, "migrations");
    const files = (await readdir(dir)).filter((f) => f.endsWith(".sql")).sort();
    for (const file of files) {
      const { rowCount } = await client.query(
        "SELECT 1 FROM schema_migrations WHERE filename = $1", [file]);
      if (rowCount) continue;
      await client.query("BEGIN");
      await client.query(await readFile(join(dir, file), "utf8"));
      await client.query("INSERT INTO schema_migrations (filename) VALUES ($1)", [file]);
      await client.query("COMMIT");
      console.log("migrated", file);
    }
  } finally {
    await client.query("SELECT pg_advisory_unlock(873_113_114)").catch(() => {});
    client.release();
  }
}

// ------------------------------------------------------------------ helpers
const hits = new Map();
function rateLimited(ip) {
  const now = Date.now();
  const bucket = hits.get(ip)?.filter((t) => now - t < 60_000) ?? [];
  bucket.push(now);
  hits.set(ip, bucket);
  if (hits.size > 5000) hits.clear();          // crude, and that is fine
  return bucket.length > RATE_PER_MIN;
}

// Container Apps terminates TLS and forwards the caller in X-Forwarded-For.
// Never trust a client-supplied address field; this is the only source.
function callerIp(req) {
  const fwd = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim();
  return fwd || req.socket.remoteAddress || "0.0.0.0";
}

function json(res, code, body) {
  const text = JSON.stringify(body);
  res.writeHead(code, { "content-type": "application/json; charset=utf-8" });
  res.end(text);
}

async function readBody(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw new Error("payload too large");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

const isUuid = (v) =>
  typeof v === "string" &&
  /^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$/i.test(v);
const dash = (v) =>
  isUuid(v) && !v.includes("-")
    ? `${v.slice(0, 8)}-${v.slice(8, 12)}-${v.slice(12, 16)}-${v.slice(16, 20)}-${v.slice(20)}`
    : v;

// ------------------------------------------------------------------- ingest
async function ingest(req, res) {
  const ip = callerIp(req);
  if (API_KEY && req.headers["x-api-key"] !== API_KEY) {
    return json(res, 401, { error: "bad key" });
  }
  if (rateLimited(ip)) return json(res, 429, { error: "slow down" });
  if (!configured) {
    // Authenticated, but there is nowhere to put it yet. 503 is a RETRY for
    // the client, so the batch stays spooled and arrives once we are wired up.
    return json(res, 503, { error: "CB_TELEMETRY_PG_URL not set" });
  }

  let payload;
  try {
    payload = JSON.parse(await readBody(req));
  } catch (err) {
    return json(res, 400, { error: String(err.message || err) });
  }

  const batchId = dash(payload.batch);
  const installId = dash(payload.inst);
  if (!isUuid(batchId) || !isUuid(installId)) {
    return json(res, 400, { error: "batch and inst must be uuids" });
  }
  const events = Array.isArray(payload.events) ? payload.events : [];
  if (events.length > MAX_EVENTS) return json(res, 413, { error: "too many events" });

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    // The whole dedup story: a batch we have already taken writes nothing.
    const seen = await client.query(
      "INSERT INTO ingest_batches (batch_id, install_id, event_count, ip) " +
      "VALUES ($1,$2,$3,$4) ON CONFLICT (batch_id) DO NOTHING",
      [batchId, installId, events.length, ip]);
    if (seen.rowCount === 0) {
      await client.query("ROLLBACK");
      return json(res, 202, { accepted: 0, duplicate: true });
    }

    await client.query(
      `INSERT INTO installs (install_id, first_ip, last_ip, os_name, os_version,
         cpu_name, cpu_count, gpu_name, screen_size, locale)
       VALUES ($1,$2,$2,$3,$4,$5,$6,$7,$8,$9)
       ON CONFLICT (install_id) DO UPDATE SET
         last_seen_at = now(), last_ip = EXCLUDED.last_ip,
         os_name = COALESCE(EXCLUDED.os_name, installs.os_name),
         gpu_name = COALESCE(EXCLUDED.gpu_name, installs.gpu_name)`,
      [installId, ip, payload.os_name ?? null, payload.os_version ?? null,
       payload.cpu_name ?? null, payload.cpu_count ?? null, payload.gpu_name ?? null,
       payload.screen ?? null, payload.locale ?? null]);

    let accepted = 0;
    for (const ev of events) {
      accepted += await applyEvent(client, ev, { installId, ip, payload });
    }
    await client.query("COMMIT");
    return json(res, 202, { accepted, duplicate: false });
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    console.error("ingest failed:", err.message);
    return json(res, 500, { error: "ingest failed" });
  } finally {
    client.release();
  }
}

// One spooled line. Unknown kinds are dropped rather than rejected, so an
// older service never blocks a newer build's batch.
async function applyEvent(client, ev, ctx) {
  const t = String(ev.t || "");
  const runId = dash(ev.run);
  const combatId = dash(ev.combat);
  const d = ev.d ?? {};

  if (t === "session_started" || t === "session_ended" || t === "session_heartbeat") {
    const playId = dash(ev.sess);
    if (!isUuid(playId)) return 0;
    await client.query(
      `INSERT INTO plays (play_id, install_id, game_version, started_at, ip,
                          duration_sec, active_sec, ended_cleanly)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (play_id) DO UPDATE SET
         duration_sec = GREATEST(plays.duration_sec, EXCLUDED.duration_sec),
         active_sec   = GREATEST(plays.active_sec, EXCLUDED.active_sec),
         ended_at     = COALESCE(EXCLUDED.ended_at, plays.ended_at),
         ended_cleanly = plays.ended_cleanly OR EXCLUDED.ended_cleanly`,
      [playId, ctx.installId, ctx.payload.app ?? null, ev.ts ?? null, ctx.ip,
       Math.round(Number(d.duration_sec ?? ev.mono ?? 0)),
       Math.round(Number(d.active_sec ?? 0)), t === "session_ended"]);
    return 1;
  }

  if (t === "run_started" || t === "run_ended") {
    if (!isUuid(runId)) return 0;
    await client.query(
      `INSERT INTO runs (run_id, play_id, install_id, seed, path_id, started_at,
                         outcome, final_encounter, final_hp, max_hp, coins_earned,
                         relic_ids, ability_ids, ability_tiers, reels, duration_sec)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
       ON CONFLICT (run_id) DO UPDATE SET
         outcome = COALESCE(EXCLUDED.outcome, runs.outcome),
         ended_at = now(),
         final_encounter = COALESCE(EXCLUDED.final_encounter, runs.final_encounter),
         final_hp = COALESCE(EXCLUDED.final_hp, runs.final_hp),
         coins_earned = COALESCE(EXCLUDED.coins_earned, runs.coins_earned),
         relic_ids = COALESCE(EXCLUDED.relic_ids, runs.relic_ids),
         ability_ids = COALESCE(EXCLUDED.ability_ids, runs.ability_ids),
         ability_tiers = COALESCE(EXCLUDED.ability_tiers, runs.ability_tiers),
         reels = COALESCE(EXCLUDED.reels, runs.reels),
         duration_sec = GREATEST(runs.duration_sec, EXCLUDED.duration_sec)`,
      [runId, isUuid(dash(ev.sess)) ? dash(ev.sess) : null, ctx.installId,
       d.seed ?? null, d.path_id ?? null, ev.ts ?? null,
       t === "run_ended" ? (d.outcome ?? "defeat") : "in_progress",
       d.final_encounter ?? null, d.final_hp ?? null, d.max_hp ?? null,
       d.coins ?? null, d.relics ?? null, d.abilities ?? null,
       d.ability_tiers ? JSON.stringify(d.ability_tiers) : null,
       d.reels ?? null, Math.round(Number(d.duration_sec ?? 0))]);
    return 1;
  }

  if (t === "combat_started" || t === "combat_ended") {
    if (!isUuid(combatId) || !isUuid(runId)) return 0;
    await client.query(
      `INSERT INTO combats (combat_id, run_id, encounter_number, encounter_type,
                            lineup_id, enemy_ids, combat_seed, started_at, rounds,
                            won, hp_before, hp_after, damage_dealt, damage_taken,
                            block_gained, chips_spun, chips_spent, duration_sec)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)
       ON CONFLICT (combat_id) DO UPDATE SET
         ended_at = now(), rounds = COALESCE(EXCLUDED.rounds, combats.rounds),
         won = COALESCE(EXCLUDED.won, combats.won),
         hp_after = COALESCE(EXCLUDED.hp_after, combats.hp_after),
         damage_dealt = COALESCE(EXCLUDED.damage_dealt, combats.damage_dealt),
         damage_taken = COALESCE(EXCLUDED.damage_taken, combats.damage_taken),
         block_gained = COALESCE(EXCLUDED.block_gained, combats.block_gained),
         chips_spun = COALESCE(EXCLUDED.chips_spun, combats.chips_spun),
         chips_spent = COALESCE(EXCLUDED.chips_spent, combats.chips_spent),
         duration_sec = GREATEST(combats.duration_sec, EXCLUDED.duration_sec)`,
      [combatId, runId, ev.enc ?? null, d.encounter_type ?? null, d.lineup ?? null,
       d.enemies ?? null, d.seed ?? null, ev.ts ?? null, d.rounds ?? null,
       t === "combat_ended" ? (d.won ?? null) : null, d.hp_before ?? null,
       d.hp_after ?? null, d.damage_dealt ?? null, d.damage_taken ?? null,
       d.block_gained ?? null, d.chips_spun ?? null, d.chips_spent ?? null,
       Math.round(Number(d.duration_sec ?? 0))]);
    return 1;
  }

  // Everything else is a move. `(run_id, seq)` makes a resend a no-op.
  if (!isUuid(runId) || ev.seq === undefined) return 0;
  const r = await client.query(
    `INSERT INTO moves (run_id, combat_id, seq, at, round_number, kind, detail)
     VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (run_id, seq) DO NOTHING`,
    [runId, isUuid(combatId) ? combatId : null, Number(ev.seq), ev.ts ?? null,
     ev.rnd ?? null, t, JSON.stringify(d)]);
  return r.rowCount;
}

// ---------------------------------------------------------------- dashboard
const QUERIES = {
  totals: `SELECT
      (SELECT count(*) FROM installs)                                  AS players,
      (SELECT count(*) FROM plays)                                     AS plays,
      (SELECT count(*) FROM runs)                                      AS runs,
      (SELECT count(*) FROM runs WHERE outcome = 'victory')            AS wins,
      (SELECT coalesce(round(sum(duration_sec)/3600.0, 1), 0) FROM plays) AS hours,
      (SELECT count(*) FROM combats)                                   AS fights`,
  funnel: `SELECT * FROM v_run_funnel`,
  lethality: `SELECT * FROM v_enemy_lethality LIMIT 20`,
  abilities: `SELECT * FROM v_ability_usage LIMIT 30`,
  sessions: `SELECT * FROM v_session_length LIMIT 30`,
  paths: `SELECT * FROM v_path_popularity`,
  recent: `SELECT p.play_id, p.game_version, p.started_at, p.duration_sec,
                  p.ended_cleanly, host(p.ip) AS ip, i.os_name, i.gpu_name,
                  (SELECT count(*) FROM runs r WHERE r.play_id = p.play_id) AS runs
           FROM plays p JOIN installs i USING (install_id)
           ORDER BY p.started_at DESC NULLS LAST LIMIT 40`,
};

async function dashboardData() {
  const out = {};
  for (const [name, sql] of Object.entries(QUERIES)) {
    try {
      const { rows } = await pool.query(sql);
      out[name] = name === "totals" ? rows[0] : rows;
    } catch (err) {
      out[name] = [];
      out[`${name}_error`] = err.message;
    }
  }
  return out;
}

// -------------------------------------------------------------------- routes
const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    if (req.method === "GET" && url.pathname === "/healthz") {
      if (!configured) {
        return json(res, 503, { ok: false, reason: "CB_TELEMETRY_PG_URL not set" });
      }
      await pool.query("SELECT 1");
      return json(res, 200, { ok: true });
    }
    if (req.method === "POST" && url.pathname === "/v1/ingest") {
      return await ingest(req, res);
    }
    if (!configured) {
      // Everything past this point needs the database. Deliberately AFTER the
      // ingest route, so the API key is still checked first and a client sees
      // the same auth behaviour before and after the secret is set.
      if (url.pathname === "/" || url.pathname === "/index.html") {
        res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
        return res.end("<!doctype html><meta charset=utf-8>" +
          "<title>Casino Brawyal - Play Data</title>" +
          "<body style='background:#0c1f16;color:#ecdfc4;font:16px system-ui;" +
          "padding:48px'><h1 style='color:#d4af37'>Not configured yet</h1>" +
          "<p>Set <code>CB_TELEMETRY_PG_URL</code> on this container app and " +
          "restart the revision. See <code>services/telemetry/README.md</code>.");
      }
      return json(res, 503, { error: "CB_TELEMETRY_PG_URL not set" });
    }
    const authed = !VIEW_KEY || url.searchParams.get("key") === VIEW_KEY;
    if (req.method === "GET" && url.pathname === "/api/stats") {
      if (!authed) return json(res, 401, { error: "add ?key=" });
      return json(res, 200, await dashboardData());
    }
    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
      if (!authed) {
        res.writeHead(401, { "content-type": "text/plain" });
        return res.end("Add ?key=<CB_DASHBOARD_KEY> to the URL.");
      }
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      return res.end(dashboardPage(url.searchParams.get("key") ?? ""));
    }
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found");
  } catch (err) {
    console.error(err);
    json(res, 500, { error: "server error" });
  }
});

try {
  const provisioned = await bootstrap();
  if (provisioned && !configured) {
    pool = makePool(provisioned, true);
    configured = true;
    console.log("bootstrap: connected as", ROLE_NAME);
  }
} catch (err) {
  // A bootstrap failure must not take the service down - it stays up and
  // says it is unconfigured, which is the same as any other missing secret.
  console.error("bootstrap failed:", err.message);
}
if (configured) {
  await migrate();
}
server.listen(PORT, () =>
  console.log(`telemetry listening on :${PORT}` +
    (configured ? "" : " (unconfigured - no database)")));
