// The designer's dashboard. Served by server.mjs at "/", reads /api/stats.
//
// Written for one reader answering one kind of question: where do runs end,
// which fight ends them, what do people actually play, and is anyone playing.
// Deliberately dependency-free — no CDN, no build step, one file to deploy.
export function dashboardPage(key) {
  const k = JSON.stringify(key);
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Casino Brawyal — Play Data</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Ctext y='14' font-size='14'%3E%F0%9F%83%8F%3C/text%3E%3C/svg%3E">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rye&family=Zilla+Slab:wght@500;600;700&family=Karla:wght@400;500;700&family=JetBrains+Mono:wght@400;600&display=swap">
<style>
:root{
  --felt:#0c1f16; --felt-2:#123524; --panel:#14301f; --panel-2:#1b3d28;
  --ink:#ecdfc4; --ink-dim:#93a694; --rule:#24452f;
  --gold:#d4af37; --gold-soft:#8d7426;
  --good:#6cc48b; --warn:#e0b95a; --bad:#e08a80; --cool:#8fb6d4;
}
*{box-sizing:border-box}
body{margin:0;background:#0c1f16;color:var(--ink);
  font-family:"Karla",system-ui,sans-serif;font-size:15px;line-height:1.55}
.wrap{max-width:1180px;margin:0 auto;padding:0 20px 80px}
h1{font-family:"Rye",Georgia,serif;color:var(--gold);font-size:clamp(26px,4vw,40px);
  margin:0 0 4px;letter-spacing:.01em}
h2{font-family:"Zilla Slab",Georgia,serif;font-size:21px;margin:0 0 4px;font-weight:600}
.sub{color:var(--ink-dim);margin:0}
header{background:#0a1a12;border-bottom:3px solid var(--gold);padding:30px 0 24px;margin-bottom:26px}
/* the page wrap carries a tall bottom padding for the footer; the header
   reuses the same class for its gutter and must not inherit that gap. */
header .wrap{padding-bottom:0}
.bar{display:flex;flex-wrap:wrap;gap:10px 22px;align-items:center;margin-top:16px;
  font-family:"JetBrains Mono",monospace;font-size:12px;letter-spacing:.05em;color:var(--ink-dim)}
button{font:inherit;font-size:13px;background:var(--panel-2);color:var(--ink);
  border:1px solid var(--rule);border-radius:4px;padding:5px 12px;cursor:pointer}
button:hover{border-color:var(--gold-soft)}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:1px;
  background:var(--rule);border:1px solid var(--rule);border-radius:6px;overflow:hidden;margin-bottom:30px}
.stat{background:var(--panel);padding:14px 16px}
.stat b{display:block;font-family:"Zilla Slab",serif;font-size:29px;line-height:1.1;
  font-variant-numeric:tabular-nums;color:var(--ink)}
.stat b.gold{color:var(--gold)}
.stat span{display:block;margin-top:5px;font-family:"JetBrains Mono",monospace;
  font-size:10.5px;letter-spacing:.09em;text-transform:uppercase;color:var(--ink-dim)}
section{margin:0 0 34px}
.card{background:var(--panel);border:1px solid var(--rule);border-radius:8px;padding:18px 20px}
.note{color:var(--ink-dim);font-size:13.5px;margin:2px 0 16px;max-width:70ch}
table{width:100%;border-collapse:collapse;font-size:14px}
th{text-align:left;font-family:"JetBrains Mono",monospace;font-size:10.5px;
  letter-spacing:.08em;text-transform:uppercase;color:var(--ink-dim);font-weight:600;
  padding:0 12px 8px 0;border-bottom:1px solid var(--rule)}
td{padding:8px 12px 8px 0;border-bottom:1px solid #1b3323;vertical-align:middle}
td.num{text-align:right;font-variant-numeric:tabular-nums;font-family:"JetBrains Mono",monospace}
tr:last-child td{border-bottom:0}
.tw{overflow-x:auto}
.mini{height:9px;border-radius:2px;background:var(--cool);min-width:2px;display:block}
.pill{font-family:"JetBrains Mono",monospace;font-size:10.5px;padding:2px 7px;border-radius:3px;
  letter-spacing:.05em;white-space:nowrap}
.pill.good{background:#1b3d29;color:var(--good)}
.pill.bad{background:#3c2120;color:var(--bad)}
.pill.warn{background:#3a3018;color:var(--warn)}
.empty{color:var(--ink-dim);font-style:italic;padding:22px 0}
.grid2{display:grid;gap:22px;grid-template-columns:1fr}
@media(min-width:900px){.grid2{grid-template-columns:1fr 1fr}}
svg text{font-family:"JetBrains Mono",monospace;font-size:11px;fill:var(--ink-dim)}
</style>
</head><body>

<header><div class="wrap">
  <h1>Casino Brawyal</h1>
  <p class="sub">Play data — who is playing, how far they get, and what stops them.</p>
  <div class="bar">
    <span id="updated">loading…</span>
    <button id="refresh">Refresh</button>
    <label><input type="checkbox" id="auto" checked> auto every 30s</label>
  </div>
</div></header>

<div class="wrap">
  <div class="stats" id="totals"></div>

  <section><div class="card">
    <h2>Where runs end</h2>
    <p class="note">Every finished run, bucketed by the encounter it ended on. The
      tall bars are your difficulty wall. Encounter 10 is the boss.</p>
    <div id="funnel"></div>
  </div></section>

  <div class="grid2">
    <section><div class="card">
      <h2>Which fight ends runs</h2>
      <p class="note">Lineups sorted by how often the player loses them.</p>
      <div class="tw" id="lethality"></div>
    </div></section>

    <section><div class="card">
      <h2>Paths</h2>
      <p class="note">Which of the six authored paths a run walked, and how deep it got.</p>
      <div class="tw" id="paths"></div>
    </div></section>
  </div>

  <section><div class="card">
    <h2>What players actually use</h2>
    <p class="note">Abilities by how often they are fired. A card near the bottom is
      either weak, expensive, or never offered.</p>
    <div class="tw" id="abilities"></div>
  </div></section>

  <section><div class="card">
    <h2>Sessions</h2>
    <div class="tw" id="sessions"></div>
  </div></section>

  <section><div class="card">
    <h2>Recent plays</h2>
    <p class="note">Newest first. An unclean exit means the game was closed or crashed
      before it could write its own ending — the duration is still accurate to the
      last heartbeat.</p>
    <div class="tw" id="recent"></div>
  </div></section>
</div>

<script>
const KEY = ${k};
const $ = (id) => document.getElementById(id);
const esc = (v) => String(v ?? "").replace(/[<>&"]/g, (c) =>
  ({"<":"&lt;",">":"&gt;","&":"&amp;",'"':"&quot;"}[c]));
const n = (v) => v === null || v === undefined ? "—" : Number(v).toLocaleString();

function table(rows, cols, empty) {
  if (!rows || !rows.length) return '<p class="empty">' + empty + '</p>';
  const head = cols.map((c) => '<th' + (c.num ? ' style="text-align:right"' : '') +
    '>' + esc(c.label) + '</th>').join("");
  const body = rows.map((r) => "<tr>" + cols.map((c) =>
    '<td class="' + (c.num ? "num" : "") + '">' + c.cell(r) + "</td>").join("") + "</tr>").join("");
  return "<table><thead><tr>" + head + "</tr></thead><tbody>" + body + "</tbody></table>";
}

// A plain horizontal bar chart. One scale, labels that name real values.
function bars(rows, labelOf, valueOf, tint) {
  if (!rows.length) return '<p class="empty">No runs recorded yet.</p>';
  const max = Math.max(...rows.map(valueOf), 1);
  const rowH = 26, padL = 108, padR = 56, w = 900, h = rows.length * rowH + 12;
  const parts = rows.map((r, i) => {
    const v = valueOf(r), y = i * rowH + 6;
    const len = Math.max(2, (w - padL - padR) * v / max);
    return '<rect x="' + padL + '" y="' + y + '" width="' + len + '" height="16" rx="3" fill="' +
      tint(r) + '"></rect>' +
      '<text x="' + (padL - 10) + '" y="' + (y + 12) + '" text-anchor="end">' +
        esc(labelOf(r)) + '</text>' +
      '<text x="' + (padL + len + 8) + '" y="' + (y + 12) + '" fill="#ecdfc4">' + n(v) + '</text>';
  }).join("");
  return '<svg viewBox="0 0 ' + w + ' ' + h + '" width="100%" height="' + h +
    '" role="img">' + parts + "</svg>";
}

function render(d) {
  const t = d.totals || {};
  const winPct = t.runs ? Math.round(100 * t.wins / t.runs) : 0;
  $("totals").innerHTML = [
    ["players", n(t.players), "gold"], ["plays", n(t.plays), ""],
    ["runs", n(t.runs), ""], ["wins", n(t.wins) + " (" + winPct + "%)", ""],
    ["fights", n(t.fights), ""], ["hours played", n(t.hours), "gold"],
  ].map(([label, value, cls]) =>
    '<div class="stat"><b class="' + cls + '">' + value + "</b><span>" +
    label + "</span></div>").join("");

  // Where runs end — deaths are the signal, wins are the reward.
  const funnel = (d.funnel || []).slice().sort((a, b) => a.final_encounter - b.final_encounter);
  $("funnel").innerHTML = bars(funnel,
    (r) => "Encounter " + r.final_encounter,
    (r) => Number(r.runs),
    (r) => Number(r.wins) > 0 ? "#6cc48b" : "#a8443c");

  $("lethality").innerHTML = table(d.lethality, [
    { label: "Lineup", cell: (r) => esc(r.lineup_id ?? "—") },
    { label: "Fights", num: true, cell: (r) => n(r.fights) },
    { label: "Losses", num: true, cell: (r) => n(r.losses) },
    { label: "Loss %", num: true, cell: (r) => {
        const v = Number(r.loss_pct ?? 0);
        const cls = v >= 40 ? "bad" : v >= 15 ? "warn" : "good";
        return '<span class="pill ' + cls + '">' + v + "%</span>"; } },
    { label: "Avg rounds", num: true, cell: (r) => n(r.avg_rounds) },
    { label: "Dmg taken", num: true, cell: (r) => n(r.avg_damage_taken) },
  ], "No combats recorded yet.");

  $("paths").innerHTML = table(d.paths, [
    { label: "Path", cell: (r) => esc(r.path_id) },
    { label: "Runs", num: true, cell: (r) => n(r.runs) },
    { label: "Wins", num: true, cell: (r) => n(r.wins) },
    { label: "Avg depth", num: true, cell: (r) => n(r.avg_depth) },
  ], "No runs recorded yet.");

  const maxFired = Math.max(1, ...(d.abilities || []).map((r) => Number(r.times_fired)));
  $("abilities").innerHTML = table(d.abilities, [
    { label: "Ability", cell: (r) => esc(r.ability_id) },
    { label: "", cell: (r) => '<span class="mini" style="width:' +
        Math.round(160 * Number(r.times_fired) / maxFired) + 'px"></span>' },
    { label: "Fired", num: true, cell: (r) => n(r.times_fired) },
    { label: "Runs used in", num: true, cell: (r) => n(r.runs_used_in) },
  ], "No abilities fired yet.");

  $("sessions").innerHTML = table(d.sessions, [
    { label: "Day", cell: (r) => esc(r.day) },
    { label: "Plays", num: true, cell: (r) => n(r.plays) },
    { label: "Players", num: true, cell: (r) => n(r.players) },
    { label: "Avg minutes", num: true, cell: (r) => n(r.avg_minutes) },
    { label: "Unclean exits", num: true, cell: (r) => n(r.unclean_exits) },
  ], "No sessions recorded yet.");

  $("recent").innerHTML = table(d.recent, [
    { label: "Started", cell: (r) => esc((r.started_at || "").toString().slice(0, 16).replace("T", " ")) },
    { label: "Build", cell: (r) => esc(r.game_version ?? "—") },
    { label: "Minutes", num: true, cell: (r) => n(Math.round((r.duration_sec ?? 0) / 60)) },
    { label: "Runs", num: true, cell: (r) => n(r.runs) },
    { label: "Exit", cell: (r) => r.ended_cleanly
        ? '<span class="pill good">clean</span>'
        : '<span class="pill warn">unclean</span>' },
    { label: "IP", cell: (r) => esc(r.ip) },
    { label: "OS", cell: (r) => esc(r.os_name ?? "—") },
  ], "Nobody has played this build yet.");

  $("updated").textContent = "updated " + new Date().toLocaleTimeString();
}

async function load() {
  try {
    const res = await fetch("/api/stats" + (KEY ? "?key=" + encodeURIComponent(KEY) : ""));
    if (!res.ok) throw new Error("HTTP " + res.status);
    render(await res.json());
  } catch (err) {
    $("updated").textContent = "could not load: " + err.message;
  }
}
$("refresh").addEventListener("click", load);
let timer = setInterval(load, 30000);
$("auto").addEventListener("change", (e) => {
  clearInterval(timer);
  if (e.target.checked) timer = setInterval(load, 30000);
});
load();
</script>
</body></html>`;
}
