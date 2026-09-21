// The designer's guide to the dashboard. Served at /guide, linked from the
// dashboard header, so the explanation lives next to the thing it explains
// rather than in a document nobody can find six weeks from now.
//
// Written for the game designer, not for an engineer: it says what each number
// means, what it does NOT mean, and what to do about it.

export function guidePage(key) {
  const k = JSON.stringify(key ?? "");
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Casino Brawyal: reading the play data</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Ctext y='14'%3E%F0%9F%93%8A%3C/text%3E%3C/svg%3E">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Alfa+Slab+One&family=JetBrains+Mono:wght@400;600&family=Inter:wght@400;500;700&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#0c1f16; --surface:#12301f; --surface-2:#173a27; --line:#245138;
  --ink:#ecdfc4; --ink-dim:#9db39f; --gold:#d4af37; --good:#6cc48b;
  --bad:#c8564c; --warn:#d8a13c;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
  font:16px/1.65 Inter,system-ui,sans-serif}
.wrap{max-width:900px;margin:0 auto;padding:0 22px}
header{background:linear-gradient(180deg,#143224,#0c1f16);
  border-bottom:1px solid var(--line);padding:34px 0 26px;margin-bottom:34px}
h1{font-family:"Alfa Slab One",serif;color:var(--gold);margin:0 0 6px;
  font-size:34px;letter-spacing:.01em;font-weight:400}
header .sub{color:var(--ink-dim);margin:0 0 16px}
a{color:var(--gold)}
.back{display:inline-block;border:1px solid var(--line);background:var(--surface-2);
  color:var(--ink);padding:7px 15px;border-radius:5px;text-decoration:none;
  font-size:14px}
.back:hover{border-color:var(--gold)}
h2{font-family:"Alfa Slab One",serif;color:var(--gold);font-weight:400;
  font-size:22px;margin:0 0 4px}
h3{font-size:17px;margin:26px 0 6px;color:var(--ink)}
section{background:var(--surface);border:1px solid var(--line);border-radius:9px;
  padding:24px 26px;margin-bottom:22px}
p{margin:10px 0}
.lead{color:var(--ink-dim)}
code{font-family:"JetBrains Mono",monospace;font-size:.88em;
  background:var(--surface-2);padding:2px 6px;border-radius:4px;color:var(--gold)}
table{width:100%;border-collapse:collapse;margin:14px 0 6px;font-size:15px}
th,td{text-align:left;padding:9px 12px;border-bottom:1px solid var(--line);
  vertical-align:top}
th{color:var(--ink-dim);font-size:12px;text-transform:uppercase;
  letter-spacing:.06em;font-family:"JetBrains Mono",monospace;font-weight:600}
td:first-child{white-space:nowrap;color:var(--gold);font-family:"JetBrains Mono",monospace;
  font-size:13.5px}
.note{border-left:3px solid var(--gold);background:var(--surface-2);
  padding:12px 16px;border-radius:0 5px 5px 0;margin:16px 0;color:var(--ink)}
.note.warn{border-left-color:var(--warn)}
.note b{color:var(--gold)}
.ask{font-style:italic;color:var(--good);margin-top:2px}
ul{margin:10px 0;padding-left:22px}
li{margin:6px 0}
footer{color:var(--ink-dim);font-size:14px;padding:10px 0 50px;text-align:center}
</style>
</head><body>

<header><div class="wrap">
  <h1>Reading the play data</h1>
  <p class="sub">What every number on the dashboard means, and what it does not.</p>
  <a class="back" id="back" href="/">&#8592; Back to the dashboard</a>
</div></header>

<div class="wrap">

<section>
  <h2>The one-paragraph version</h2>
  <p class="lead">Every copy of the game keeps a small log of what the player does.
  It writes that log to the player's own disk first, so a session on a train with no
  signal is never lost, and it uploads whenever it next sees the internet. A small
  service in Azure receives those uploads, stamps each one with the player's IP
  address, and stores them. The dashboard is a read-only view of that store.</p>
  <p><b>Yes, it is every player, everywhere.</b> Not just your machine. Anyone who
  runs a build with telemetry left on appears here, identified by a random id their
  copy generated on first launch plus the IP the upload arrived from.</p>
</section>

<section>
  <h2>The four things being counted</h2>
  <p class="lead">Most confusion on this dashboard comes from mixing these up.
  They nest inside each other.</p>
  <table>
    <tr><th>Word</th><th>Means</th></tr>
    <tr><td>player</td><td>One installation. A random id made the first time that
      copy of the game starts. If somebody reinstalls, or deletes their save folder,
      they become a new player. Two people behind one office router look like two
      players but share an IP.</td></tr>
    <tr><td>play</td><td>One launch of the game: from double-click to close. A player
      who opens the game three times in an evening is three plays.</td></tr>
    <tr><td>run</td><td>One attempt at Act I, from "New Run" to victory, death, or
      abandonment. One play can hold several runs.</td></tr>
    <tr><td>fight</td><td>One combat encounter inside a run.</td></tr>
  </table>
  <p>So <code>plays &gt; runs</code> is normal: people open the game and close it again
  without starting anything. <code>runs &gt; plays</code> is also normal: somebody died
  four times in one sitting.</p>
</section>

<section>
  <h2>The strip along the top</h2>
  <table>
    <tr><th>Number</th><th>What to read into it</th></tr>
    <tr><td>players</td><td>How many distinct installs have ever reported. Your
      audience size, near enough.</td></tr>
    <tr><td>plays</td><td>Total launches. Against players, this is your
      <i>return rate</i>: 12 plays from 3 players means people are coming back.</td></tr>
    <tr><td>runs</td><td>Total attempts at Act I.</td></tr>
    <tr><td>wins</td><td>Runs that beat the boss, and the percentage of runs that
      did. This is the number the whole difficulty conversation hangs on.</td></tr>
    <tr><td>fights</td><td>Total combats. Divided by runs, it tells you how deep the
      average run gets before it stops.</td></tr>
    <tr><td>hours played</td><td>Total time with the game open, summed across everyone.</td></tr>
  </table>
  <div class="note"><b>The win rate is the one to watch.</b> The 40-run bot in the test
  suite plays randomly and wins almost nothing, which makes it a floor, not a forecast.
  Real people are far better than it. This percentage is the only honest read on whether
  Act I is too hard.</div>
</section>

<section>
  <h2>Where runs end</h2>
  <p class="lead">Every finished run, bucketed by the encounter number it ended on.
  Red bars are runs that ended in death, green means at least one run in that bucket
  was a win.</p>
  <p>Encounter 10 is the boss, so a bar at 10 or 11 is somebody who went the distance.
  A tall red bar anywhere earlier is a <b>wall</b>: the point where the difficulty curve
  outruns the player's kit.</p>
  <p class="ask">Ask it: is there one encounter that kills far more people than its
  neighbours? That is a spike to flatten, not a general difficulty problem.</p>
</section>

<section>
  <h2>Which fight ends runs</h2>
  <p class="lead">Each enemy lineup, sorted by how often players lose to it.
  Lineup ids like <code>full_service</code> and <code>vault_golem</code> come straight
  from the Encounters tab of your spreadsheet.</p>
  <table>
    <tr><th>Column</th><th>Means</th></tr>
    <tr><td>Fights</td><td>How many times anyone has fought this lineup.</td></tr>
    <tr><td>Losses</td><td>How many of those fights ended the run.</td></tr>
    <tr><td>Loss %</td><td>Losses over fights. Green under 15%, amber to 40%, red above.</td></tr>
    <tr><td>Avg rounds</td><td>How long the fight takes. A high number with a low loss
      rate is a <i>boring</i> fight, not a hard one: the player was never in danger,
      it just took a while.</td></tr>
    <tr><td>Dmg taken</td><td>Average health the player loses in it. This is the fight's
      real cost, and it is often paid two encounters later.</td></tr>
  </table>
  <div class="note warn"><b>Read loss % with the fight count next to it.</b> One loss out
  of one fight is 100% and means nothing at all. Ignore any row until it has roughly ten
  fights behind it.</div>
  <p class="ask">Ask it: which lineup has a high <i>damage taken</i> but a low loss rate?
  That is the fight that is quietly killing people later, and it will not show up as a
  wall in the funnel.</p>
</section>

<section>
  <h2>Paths</h2>
  <p class="lead">Which of the six authored paths through Act I a run walked, how many
  runs took it, and how far they got.</p>
  <p>Since the paths are hand-authored rather than generated, this is the panel that tells
  you whether one of them is noticeably kinder or crueller than the others. Two paths with
  the same number of runs but very different average depth means the encounter order
  matters more than intended.</p>
  <div class="note"><b>This panel was empty until build 0.0.116.</b> The path is chosen at
  the first map screen, which happens after the game has already reported that the run
  started, and the service was throwing that later value away. Runs recorded before 0.0.116
  have no path and cannot be recovered. It fills in from 0.0.116 onward.</div>
</section>

<section>
  <h2>What players actually use</h2>
  <p class="lead">Every ability, by how many times it has been fired and how many separate
  runs it was fired in.</p>
  <p>The two columns say different things. <b>Fired</b> is raw volume and is dominated by
  cheap cards played every turn. <b>Runs used in</b> is reach: how many players ever found
  a use for it at all.</p>
  <ul>
    <li>High fired, high reach: a staple. Probably correctly costed.</li>
    <li>Low fired, high reach: a situational card doing its job.</li>
    <li><b>Low on both:</b> the interesting one. Either it is too weak, too expensive, or
      the shop almost never offers it. The data cannot tell you which, but it tells you
      where to look.</li>
  </ul>
  <div class="note warn">A card at the bottom is <b>not</b> automatically bad. Ace starts
  with a fixed hand, so starter abilities get a large head start on everything bought later.
  Compare starters with starters.</div>
</section>

<section>
  <h2>Sessions</h2>
  <p class="lead">One row per day: how many plays, how many distinct players, the average
  session length, and how many of those sessions ended badly.</p>
  <p><b>Average minutes</b> is your engagement number. A day where it collapses is worth
  looking into, and the recent-plays table below will usually say why.</p>
  <p><b>Unclean exits</b> counts sessions that never reported an ending. That means the
  game was closed abruptly, killed from Task Manager, or crashed. A steady low number is
  normal: people alt-F4 games. A sudden jump after a new build is a crash signal and is
  the single most valuable alarm on this page.</p>
</section>

<section>
  <h2>Recent plays</h2>
  <p class="lead">The newest sessions, one row each. This is the panel to open when a
  number above looks wrong.</p>
  <table>
    <tr><th>Column</th><th>Means</th></tr>
    <tr><td>Started</td><td>When the game was opened, in UTC.</td></tr>
    <tr><td>Build</td><td>The version that reported. This is why the build number gets
      bumped every patch: without it you cannot tell whether a change helped.</td></tr>
    <tr><td>Minutes</td><td>How long the game was open.</td></tr>
    <tr><td>Runs</td><td>How many runs were started in that session. Zero means they
      opened the game and closed it again.</td></tr>
    <tr><td>Exit</td><td>Clean if the game wrote its own ending, unclean otherwise.
      The duration is still accurate either way: the game leaves a heartbeat roughly
      once a minute.</td></tr>
    <tr><td>IP</td><td>Stamped by the server, never sent by the game. A desktop game
      cannot see its own public address, which is one of the reasons the uploads go
      through a service instead of straight to the database.</td></tr>
    <tr><td>OS</td><td>Windows version, and the machine's graphics card is stored
      alongside it. Useful when somebody reports that it runs badly.</td></tr>
  </table>
</section>

<section>
  <h2>Five things that will look like bugs and are not</h2>
  <h3>1. Numbers arrive late</h3>
  <p>A player with no internet keeps everything on disk and uploads on a later launch.
  A session from Tuesday can appear on Thursday. The timestamps are the real ones.</p>

  <h3>2. A session shows zero minutes and an unclean exit</h3>
  <p>The ending never arrived. It usually turns up on that player's next launch and the
  row corrects itself in place.</p>

  <h3>3. One person shows as several players</h3>
  <p>The id lives in the game's save folder. Reinstalling, moving machine, or clearing
  that folder mints a new one.</p>

  <h3>4. Several people share one IP</h3>
  <p>Anyone behind the same office or home router uploads from the same address. The IP
  is a hint about location, not an identity: the random install id is the identity.</p>

  <h3>5. Someone played but nothing appeared</h3>
  <p>Telemetry can be turned off from the Settings panel, and the notice on first launch
  offers it up front. Turning it off also deletes what that machine had stored. A player
  who declines is invisible here by design.</p>
</section>

<section>
  <h2>Privacy, briefly</h2>
  <p>No account, no name, nothing anyone types. What is stored is: a random id, an IP
  address, the operating system and graphics card, and what happened in the game.</p>
  <p>The IP is what makes this personal data in the legal sense, so there is a working
  deletion path: one request removes a player and everything under them, and it cannot
  come back afterwards even if their game re-uploads. Ask and it takes a minute.</p>
</section>

<footer>Casino Brawyal telemetry. This page is served from the same service as the
dashboard and updates with it.</footer>

</div>
<script>
// Carry the key across so "Back to the dashboard" does not bounce off the door.
const KEY = ${k};
if (KEY) {
  document.getElementById("back").href = "/?key=" + encodeURIComponent(KEY);
}
</script>
</body></html>`;
}
