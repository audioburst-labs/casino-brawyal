# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Casino Brawyal — a slot-machine roguelike battler (Godot 4.5.2, GDScript, Windows desktop). v0.1 scope is Act I only: hero Ace, a 10-encounter run, boss Mr. Moneyman. The **canonical, living design source** is the designer's Google Drive doc + capabilities spreadsheet (not the local `docs/Casino Brawyal.docx`, which lags behind them):
  - Design doc: https://docs.google.com/document/d/1yWbfqCKe5GuJdXhmJmDMVm9Ww9olDnEpaovxXSe57aM/edit
  - Capabilities spreadsheet: https://docs.google.com/spreadsheets/d/1l_dCi7SLp1HjrRdsljdnNWHYpAfFt0cMjtxxClp1hO8/edit (tabs: Abilities - Ace, Abilities - Others/Queen WIP [future heroes, out of v0.1 scope], Relics, Enemies, Summons, Encounters)

  No Google Drive MCP connector is available in this environment; fetch both via `curl -sL "<url>/export?format=txt"` (doc) and `curl -sL "<url>/export?format=xlsx"` (spreadsheet, then unzip and parse `xl/worksheets/sheetN.xml` — see git history around the patch-0.17 content sync for a working converter script). When the doc/sheet and the shipped code disagree on a number, the doc wins (established precedent, patch 0.17 shop pricing and the full ability/relic/enemy rebalance) — ask the user only if genuinely ambiguous. **The boss is Mr. Moneybags** (designer's ruling, 0.117). The design doc says "Mr. Moneyman" and is the outlier here: the sheet, the enemy def and the shipped game all say Moneybags, and the designer confirmed it. Do not "fix" it back to the doc. The victory screen reads the name off the enemy def rather than a literal, because it used to shout "MR. MONEYMAN DEFEATED" at players who had just beaten Mr. Moneybags. (`assets/video/moneyman_boss_intro.ogv` keeps its filename; nobody sees it.) The approved architecture spec is `docs/superpowers/specs/2026-08-18-casino-brawyal-design.md`.

The Godot binaries are NOT in git — they are expected at `tools/godot/Godot_v4.5.2-stable_win64.exe` and `..._win64_console.exe`. Always use the **console** exe for CLI work (the plain exe detaches from stdout on Windows).

## Commands

```powershell
# Full verification: import -> GUT tests -> smoke boot. Non-zero exit on failure.
powershell -File tools/verify.ps1

# All tests (GUT reads .gutconfig.json: tests/unit + tests/integration)
tools\godot\Godot_v4.5.2-stable_win64_console.exe --headless --path . -s res://addons/gut/gut_cmdln.gd -gexit

# One test file / one test
... -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_payout.gd -gexit
... -gtest=res://tests/unit/test_payout.gd -gunit_test_name=test_pair_pays_three_chips_of_that_suit -gexit

# Reimport assets (required after adding files, before any headless run)
... --headless --path . --import --quit

# Run the game / play a seeded headless combat transcript / screenshot a scene
tools\godot\Godot_v4.5.2-stable_win64.exe --path .
... --headless --path . -s res://tools/sim_cli.gd -- <seed> [enemy_ids...]
... --path . --resolution 1920x1080 -s res://tools/screenshot.gd -- res://scenes/screens/combat_screen.tscn 150 out.png   # needs a window, no --headless

# Windows build (templates in %APPDATA%\Godot\export_templates\4.5.2.stable)
... --headless --path . --export-release "Windows Desktop"   # -> build/CasinoBrawyal.exe

# AI art (Azure gpt-image; keys in .env)
node tools/art/generate_art.mjs [--dry-run] [--only <id,id>] [--force]
```

The balance instrument is `tests/integration/test_full_run_bot.gd`: 40 seeded full runs, prints `RUN BOT STATS` (win rate / avg death encounter). Run it after any content or damage-math change; **0/40 wins with avg death at encounter ~4.9 and avg coins ~66 is the current baseline at 0.121** (Drunk Patron lineups, the Rage fix and the sheet's Golem/Dealer/boss number changes; it was 4.7 and 62 post patch-0.116) (coins fell from 70 because the sheet's stories pay per-encounter rather than the old flat 40-60, so an early story is worth much less; depth is unchanged). The designer has seen this and asked to ship it as is: *"it was too easy before, maybe now it will be too hard - I want to see"*. So it is a deliberate setting, not a regression to chase. Note the bot barely moved when Ace's kit tripled in size (4.5 -> 4.7), because a random-play bot gets almost nothing from a kit whose value is in its conditions - treat the bot as a floor, not a measure of the new cards. Previously: **0/40, 4.5, 69 at 0.114, a WARNING not a target**: sheet v0.122 raised every enemy's health and rebuilt the Manager, while Ace's matching 25-ability kit is still unimplemented (pass 2). The bot dies four encounters earlier than it did in 0.113 because it is fighting the new enemies with the old hero. Expect this to swing back hard when the kit lands — do not tune anything against 4.5; 1/40, 8.1, 84 coins at 0.113; 0/40, 7.0, 65 coins at 0.22 (Elites are real mini-bosses and enemy debuffs last a full turn longer); 2/40, 7.3, 50 coins at 0.21 (0/40, 7.0, 40 coins at 0.20 pass 1 — the free Casino spin and the final shop moving back to #9 lifted coins; encounter 6.8 at 0.19 pass 2, 1/40 after 0.19 pass 1) (0/40 at 0.18, 2/40 at 0.17 — a 40-run sample, so treat single-digit win counts as noise and watch avg-death instead; avg coins dropped 67 → 37 when the guaranteed shop moved to #8, because the bot now reaches it and spends) (random-play bot — humans do much better). This number moves whenever ability/enemy numbers change — don't treat a shift as a regression on its own, just note the new baseline here.

## Architecture

**Sim/presentation split (the load-bearing decision).** All game rules are plain `RefCounted` classes under `src/core/` — no Node, no scene tree, no awaits, seeded `GameRng` injected (independent named streams: map/combat/shop/rewards). Every state change appends a typed `CombatEvent`; UI screens are *presenters* that send commands to the sim, then `drain_events()` and play one animation per event. Never put rules in UI scripts; never reference autoloads from `src/core/`.

- `CombatSim` (src/core/combat/): phase machine `ROUND_START → ASSIGNMENT → (end_assignment runs the enemy phase) → ROUND_START | ENDED`. Commands: `begin_round`, `assign_chip`, `unassign_chip`, `set_target`, `end_assignment`. Abilities auto-fire when their last socket fills; socketed chips persist across rounds; the tray discards at `end_assignment`.
- **Status timing (contract, patch 0.22, designer's rule):** *buffs tick down at the START of their owner's turn, debuffs at its END.* `statuses.json` carries the split as a `kind` field and `StatusRules.DURATION_BUFFS`/`DURATION_DEBUFFS` mirror it. The hero's turn starts at `begin_round()` and ends at `end_assignment()` **before** the enemy phase; each enemy's turn brackets its own action in `_run_enemy_phase` (including a skipped one, so a Stun is spent by the action it skipped). `CombatActor.on_turn_start()` also clears that actor's Block — for an enemy that is its own slot in the enemy phase, not the hero's round start, or the Chip Golem's 20 Block would be gone before Ace could swing at it. Before 0.22 everything ticked once, together, after the enemy phase, so an enemy's Weak 2 on Ace lost a stack before he had acted under it once.
- Damage order (contract, tested): base + Strength → Weak (−25%) → **Vulnerable (+50%)** → Block → HP, per hit instance. Vulnerable was 25% in code from 0.1 to 0.113 while every version of the sheet read 50% — corrected in 0.114, doc wins. **`CombatSim._build_intent_entry` runs the announced damage through `StatusRules.damage_taken(..., hero)` too**, so an intent already carries the hero's Vulnerable; showing the pre-Vulnerable figure and then hitting 50% harder was lying about the one number a turn is planned around (0.114). **Multistrike** adds to an attack's instances and **Rage** adds its stacks to every hit of the next attack, then is spent (`RAGE_PER_HIT`, designer's call). The `damage_dealt` event carries all three of `amount` (the full hit), `hp_lost` and `blocked` — presenters must step the HP bar by `hp_lost` and spend the block readout by `blocked`, never by `amount` (patch 0.18: doing the latter dropped the bar and let the next `refresh()` spring it back, so Block read as a heal). Rounding is **half-up** (patch 0.1); Weak min 1. Weak/Vulnerable pcts are overridable per-combat (`CombatSim._weak_pct`/`_vuln_pct`) but nothing currently overrides them — the old High Stakes relic that did was removed in patch 0.17 (replaced by Winner's Aura, a plain `apply_status` effect).
- Payout ruling (`payout.gd`): 1 chip per landed symbol, +1 bonus chip per suit with 3+ matches. Machine starts at **3 reels** (patch 0.12: designer reverted the 4-reel compensation — bot win rate dropped to 0%, flagged as a balance risk). Each `Reel` raffles from its own **pool** (doc "Behavior → Combat → Slot Machine", implemented patch 0.18): `POOL_COPIES` (**2** since v0.19, was 3) instances of every symbol on that reel, drawn without replacement, **refilled with `REFILL_COPIES` = 3 once empty (the doc's "Pool Refresh" line, read literally in 0.122; flag it if that line was just stale)**; `set_symbol()` clears the pool so a sticker takes effect immediately. Marginal odds are unchanged — this only bounds streaks and droughts.
- **Enemy passives are data** (patch 0.22): an enemy def may carry `passive` = `{"type": "bust"|"break"|"loan", ...}`, validated against `ContentDB.KNOWN_PASSIVES`, and every `intent` key is whitelisted by `KNOWN_INTENT_KEYS` (a typo in an intent extra used to fail silently). `CombatSim.on_enemy_damaged()` — called by `EffectInterpreter` right after `damage_dealt` — runs **Bust** (Dealer: tally damage, at 21 stun it and erase its Strength) and **Break** (Chip Golem: a random chip to the player per 20 HP lost). The **Loan** passive interrupts `begin_round`. New intent extras: `self_block`, `gift_chips` (delivered after the next spin, in `_finish_round_start`, so the chips are seen arriving with the payout) and `absorb` (clears every socketed chip). **The Dealer's old blackjack raffle is gone** — no `_raffle_blackjack`, no `blackjack` intent key, no "BUST!" intent text.
- **Loans carry their own offer condition** (sheet v0.122, patch 0.114): a `requires` field on the loan def, linted against `ContentDB.KNOWN_LOAN_REQUIREMENTS`. `"wounded"` hides a loan while the hero is at full health, which is how the sheet's "If the player has full health, don't offer this" note on both healing loans is expressed — as data on the loan, not an id list in the sim (`CombatSim._loan_offerable`).

**Options In Combat / Loans** (doc "Options In Combat" + "Loan", patch 0.22): `Phase.CHOICE` sits between ROUND_START and ASSIGNMENT. `begin_round` shows the intents, then stops and emits `choice_offered` if a living enemy's `loan` passive is due (rounds 1, 4, 7…); `choose(index)` applies the reward, pushes `{id, turns_left}` onto `hero.loans` and calls `_finish_round_start()` (spin → gift chips → ASSIGNMENT). The countdown ticks with the hero's debuffs at the end of his turn and the penalty fires at zero — it can be blocked and it can kill. Loans live in `data/loans/loans.json`; `add_chips` accepts `"suit": "random"`, and `heal`/`lose_hp` work inside combat. **Both bots must resolve `Phase.CHOICE`** or they deadlock (`GreedyBot.play_combat`, `tools/sim_cli.gd`).
- Unit positioning (doc "Behavior → Unit Positioning", patch 0.18; per-actor seating 0.21): each side has 4 fixed slots. `CombatSim.enemies` is ordered **centre-outward** (index 0 nearest the middle of the screen) and that order is also the enemy phase's left-to-right acting order. `combat_screen.initial_slots(n)` seats the opening line (**1 unit → slot 1** — designer's call in 0.21, the doc's table still says the third slot; 2 → 0,1, 3 → 0,1,2, 4 → all) and after that **a slot is assigned once per actor and never recomputed**: `_enemy_slot_of` persists, `seat_summon(order, seats, new_id)` (pure, unit-tested) gives a summon the free slot nearest its summoner on the inward side or, with no room, pushes the summoner and everything outward of it one slot further out (the doc's rule). Dead views move to `_corpse_views` and keep their slot until the sim's `actor_removed` clears the corpse — the 0.19–0.20 code recomputed slots from the head-count on every change *and* left dead views in the row while forgetting them, which is why the line shifted on every summon. Summons insert *inward* of their summoner in the sim (`_summon_slot()` reclaims a dead ally's inner slot first, emitting `actor_removed`).
- **Mark is a toggle, not a stack** (designer, 0.118): `_op_apply_status`
  sets it to 1 whatever the stacks asked for, and Cash In erases it outright.
  Before, three Marks bought three separate Cash Ins. **Reversed in 0.121**
  (designer: Sharp Edge "shouldn't deal damage when a Mark is applied to a
  target that's already marked"): the "when you Mark" triggers fire only when
  the Mark goes ON an unmarked enemy (`was_marked` in `_op_apply_status`).
  `test_patch_121.gd` walks every marking ability against Sharp Edge.
  **The hero's Rage is real since 0.121**: Slow Playing granted stacks for
  nine patches and nothing read them. `EffectInterpreter._deal_damage` adds the
  hero's Rage to every hit and `_spend_rage` clears it after the attack
  (`rage_spent`); `preview_damage` includes it so the card's number is true.
- Ace's kit comes from the capabilities spreadsheet (see the Google Drive links above): Mark/**Cash In — since v0.19 each ability carries its own payoff**, `{"op": "cash_in", "effects": [...], "else_effects": [...]}`: it consumes one Mark **from the selected target only** and runs `effects`, or runs `else_effects` when nothing is marked (the sheet's "Deal X instead" wording; an ability with no `else_effects`, like Bust, does nothing unmarked). The old flat `CombatSim.CASH_IN_BONUS` is gone. Nested effect arrays are linted recursively by `ContentDB._validate_effect`. Also: per-turn limits (`per_turn`), **per-combat limits (`per_combat`, never reset by `begin_round` — House Edge and Face Reader)**, passives (fire each round start after activation), `bonus_mode: replace`, effect `condition`s (KNOWN_CONDITIONS), and a `target: "random_enemy"` damage variant (patch 0.17, High Roller relic). Enemies: hp_min/hp_max rolled per combat, brains (see below), `summon`/`heal_allies`/`ally_attack_again`/`blackjack`/`self_heal` intent extras.
- **The map is authored, not generated** (doc v0.122, patch 0.114). The doc replaced ten patches of procedural placement rules with six predefined **Paths**: a run picks one at its first map screen and walks it to the boss. They are transcribed from the sheet's *Encounter Choices* tab into `data/encounters/act1_paths.json` (regenerate with the converter in `scratchpad/s024/paths.py` rather than retyping). `MapGenerator.next_options(db, run, rng)` just reads the pair for the current encounter; `RunState.path_id` remembers which path and is serialised, and a save without one is adopted into a path on its next ask. **The old guarantees are now properties of the data** — #1 combat, #10 boss, two Elites after #3 two encounters apart, a Shop at #9 beside the Rest — and `test_map_generator.gd` asserts them against the shipped paths, so a designer editing the sheet still gets a failing build rather than a broken run. `MapGenerator` takes the `ContentDB` as its first argument (it is `src/core/`, so it must never touch the `Db` autoload).
- **Elite replaced Hard Combat in patch 0.22.** The type is `&"elite"` everywhere and it has **no buffed/advanced variants**: it draws from the sheet's own Elites pool via `ContentDB.elite_lineups()` (lineups carry `"elite": true` and sit at stage 0, so `lineups_for_stage` never offers one as a normal fight), and the relic is Elite-only (`reward_screen` and `RunBot._play_combat` each implement that rule — keep them in sync). `RunState.from_dict` migrates an in-flight save's `hard_combat` history and pending encounter to `elite`.
- Casino (doc v0.120, patches 0.21–0.22): the visit is **one game of three** (`src/ui/casino_screen.gd` is a hub; the games are `src/ui/casino/{slot_game,dice_game,relic_hunt}_view.gd` over pure logic in `src/core/run/`). **Slot Machine**: the spin is free; the prize table gained **Empty Money Sack** (−10×enc coins) and **Multiple Broken Hearts** (−2×enc health) in v0.122 while the four stickers halved to 5% each, and **the doc's table now sums to 80, not 100** — `CasinoGame._draw()` rolls over `total_weight()` so every listed share stays in proportion (flagged since the 0.21 report). **Dice Game** (`DiceGame`): roll toward exactly 10, bust past it, cash out for enc × count. **Find the Relic** (`RelicHunt`): 1 blank / 3 gold / 1 unowned relic, shuffled, one pick. `RunBot` plays a random one per visit, so all three are in the balance instrument.
- Statuses: **Frail** (sheet v0.120, the Server's Spilled Drink replaced Weak 2 with Frail 2) is a duration status; `StatusRules.block_gained()` taxes every Block an ability op grants by 25% half-up, applied through `EffectInterpreter._grant_block()` for all three block ops, and `CombatSim.preview_block()` is the same function so a card's printed Block is what it actually grants (patch 0.22). Sheet v0.122 numbers (patch 0.114): Bouncer 56–60, Server 25–30, **Dealer 51–55 with the Bust passive** (2×3 on its first two moves), **Manager 61–65, rebuilt to Summon a Server → loop Strength 5, Deal 10** (it applies no Vulnerable or Weak at all any more — `performance_review` is gone, `take_charge` replaces it), Chip Golem 100–109 shedding a chip every **30** health (Bash 22, Crush 3×7), Loan Shark 100–109, boss **150–160**. The boss summons ONE Bouncer and his heal move is `heal_allies` 20 + Strength 3 — `heal_allies` includes the boss himself (pinned by `test_patch_113.gd`).
- Economy: combat gold comes from each lineup's `gold_min/gold_max` (sheet values; patch 0.17 grew the lineup pool to 3 per stage — 15 non-boss lineups across stages 1–5). **Combat gold is the sheet's, per stage: 27–33 / 37–43 / 47–53 / 57–63 / 67–73, boss 0, Elites 77–83** — `test_patch_113.gd` pins every lineup and every gold band against a transcription of the sheet's Encounters tab, because nine of the sixteen lineups had quietly drifted from it by 0.22. (The doc's Rewards section used to say Encounter × 8–12; the designer confirmed the sheet wins in 0.18, 0.19 and again in 0.113.) Relic prices live on the relic defs (the doc now says "In Sheet", resolving the 0.18 conflict); shop reel **75+75/purchase** (doc v0.121, patch 0.113), stickers 10+5×enc, abilities 30–50. Machine caps at **6 reels** (doc v0.19, was 8). Balance is WIP — sheet numbers are the designer's, hero HP/start-reels/dealer-raffle were tuned here.
- `EncounterFactory.combat_config()` is shared by the `Game` autoload and `RunBot` so flow rules can't drift.

**Ace's kit is the sheet's `Abilities - Ace` tab, 25 abilities** (patch 0.115).
The tab was swapped deliberately by the designer — the old roster is now
`Abilities - Ace OLD` and is dead. Regenerate the JSON with the transcription
script rather than hand-editing (`scratchpad/s024/kit_data.py`), and note the
count is **25, not 29**: the extra entries in the trailing columns of rows 16–19
are the designer's scratch space, confirmed with him.

Five mechanics the kit introduced, each shared by several cards:
- **Earn** is the doc's name for adding chips. Implemented as the existing
  `add_chips` op with two new suits: `"random"` and **`"used"`**, which hands
  back a chip the ability was paid with (Hit, All In). `"used"` reads
  `CombatSim.active_ability().filled`, so it only works while an ability is
  resolving — before `ability.clear()`, which runs after the effects.
- **Triggered passives.** `passive: true` with no `passive_trigger` still fires
  at every round start (House Edge, Face Reader). With a trigger it waits for
  that instead — `"earn"` (Chip Tricks) or `"mark"` (Sharp Edge), fired from
  `CombatSim.on_chips_earned()` / `on_enemy_marked()`. A triggered passive's
  `active_effects` is the "Active:" half that runs the turn you play it;
  `effects` is what the trigger runs later. `_fire_triggered_passives` guards
  re-entrancy, or a passive that Earns would fire itself forever.
- **`damage_per_ability`** (The River) multiplies by
  `abilities_fired_this_round`, which is incremented *before* effects run — so
  The River counts itself and can never deal nothing.
- **`damage_bonus_pct`** (All In) sets `CombatActor.damage_bonus_pct`, applied
  in `StatusRules.attack_damage` with Strength and *before* Weak, and cleared in
  `on_turn_start()` beside Block because "this turn" means exactly that.
- **`rage_per_weak`** (Slow Playing) counts Weak **stacks** across living
  enemies, not enemies-with-Weak.

**Suits can be conditions** (`socket_has_suit` / `socket_lacks_suit` +
`condition_suit`): Rainbow reads Club and Heart *independently*, which the
single `bonus_suit` slot cannot express. `target_weak` / `target_not_weak` and
`any_enemy_weak` / `no_enemy_weak` serve Bluff Call and Safe Play — note Safe
Play asks about the whole field, Bluff Call about the target.

**A `bonus_suit` without `bonus_condition` is silently inert** —
`AbilityState.bonus_active()` requires `bonus_condition == "all_slots_bonus_suit"`.
That had quietly disarmed two cards' suit bonuses; the generator now always
pairs them.

**A child node cannot draw outside an `AbilityCard`** (patch 0.116). The card
is a `PanelContainer`, so a container lays out EVERY child into its inner
content rect. The 0.115 glow ring was a child with `PRESET_FULL_RECT` plus
`show_behind_parent`: the container clamped it inside the card and the panel's
own opaque background then covered it. It was built correctly on every
qualifying card and painted where nothing could see it, which is the worst
shape a bug can have. Anything that has to reach past the card's border is
drawn by the card's own `_draw` (a Control's draw is not clipped to its rect)
or given `top_level = true` like `_keyword_panel`.

**Card Glow** (doc "Glow", patch 0.115; made visible 0.116): `AbilityCard.wants_glow(def, sim)`
walks the whole effect tree and returns true for a Cash In while anything is
Marked, or a Weak-synergy card while a Weak enemy exists. The doc lists Knights
too; no Knight exists in the game. The glow is re-evaluated on every card
refresh *and* whenever a status lands on an enemy.

**Ability upgrade tiers** (doc "Ability Upgrades", patch 0.19 pass 2): every ability ships a `tiers` array of exactly `ContentDB.MAX_TIER` (2) **sparse overrides** — silver then gold — merged over the base item, so a tier can change any field (Color Up's tiers change `per_turn`, House Edge's swap the op entirely), not just a number. `ContentDB` resolves one immutable `AbilityDef` per tier and `get_ability(id, tier)` clamps; the tiers must be separate objects because `AbilityState` holds its def **by reference**, so a shared mutated def would leak an upgrade into later runs. Ownership is `RunState.ability_tiers` (id -> 0/1/2) beside `ability_ids`, never encoded into the id — the id is the ability's identity at ~13 call sites. `acquire_ability()` upgrades a duplicate instead of stacking; `_forget()` clears the tier so a trashed gold ability returns to the pool at base. **There is no storage/"Unequipped" tier as of v0.20** (designer call; matches the doc's Ability Choosing Screen, which lists only Equipped and Trash — the doc's *Layout Tab* line still says otherwise and is stale): an owned ability is either equipped or in the single trash slot, a 7th goes straight to the bin, and `STORAGE_CAP`/`stored_ids()`/`unequip()` are gone. `EncounterFactory` passes `ability_tiers` into the combat config. `Rewards.upgradeable_pool()` is the single pool both the reward screen (1 of 3) and `ShopStock` (4 offers) draw from: everything with `can_upgrade()` true, owned or not, uniform, gold excluded. **"starter" only means Ace begins the run holding the base version** — starters are offered like anything else (designer call, 0.19); do not re-add a `pool != "starter"` filter. Upgrades cost the same 30-50 as a new ability. `TierStyle` (`src/ui/combat/tier_style.gd`) owns the shared silver/gold look so every surface agrees.

**No long dashes in anything a player reads** (designer's rule, patch 0.116).
Em and en dashes are out: use a comma, a colon or a full stop.
`tests/unit/test_copy_style.gd` scans `data/` and `src/ui/` and fails the build,
because a rule nobody can see being broken gets broken again in a month. Source
comments are ours, not the player's, and are out of scope.

**Content is JSON, not .tres.** Everything (abilities, enemies, relics, statuses, lineups, story events) lives in `data/*/*.json` as `{"type": ..., "items": [...]}` and is parsed/validated by `ContentDB.load_all()` — unknown suits/ops/statuses/ids fail loudly, and `tests/unit/test_content_db.gd` doubles as the content linter. Behavior is a declarative effect-op DSL (`{"op": "damage", "amount": 3, "times": 2}` etc.) executed by `EffectInterpreter` (combat) and `RunEffects` (run level: coins/hp/relics). New ops must be registered in `ContentDB.KNOWN_OPS` and implemented in the matching interpreter. Relics declare a `trigger` from `ContentDB.KNOWN_TRIGGERS`; `CombatSim._fire_relics()` fires them at fixed points (skipped when `effects` is empty — a few relics like the Emblems/Lucky Foot are still special-cased directly in `CombatSim` instead of going through the op DSL). Enemy moves support `intent.debuffs` (hit the hero) and `intent.self_status` (buff the enemy); `EnemyBrain` types are `sequence` (loops a step list) / `weighted` (+`no_repeat_last`) / `pair_then` (a designer-notation reading of the sheet's "X → Y / Y → X, Z": a shuffled opening pair then a fixed tail, looping) / `intro_loop` (plays `intro` once in order, then loops `loop` — used by the boss and, since patch 0.17, the Manager) / `phased` (hp thresholds). The sheet's brain-order shorthand is genuinely ambiguous in places; treat any interpretation of it as a judgment call worth a quick sanity check against the resulting gameplay feel, not a literal spec.

**Story encounters are the sheet's `Story - WIP` tab, five of them** (patch
0.116): Lost Soul, Risky Dealings, Guarded Treasure, Quick Catch, Cheap Tricks.
They replaced five placeholders that had shipped since v0.1 and had nothing to
do with the sheet. Regenerate with `scratchpad/s024/stories.py`. The tab is
1000 rows tall because that is Google Sheets' default empty grid, not because
there are 1000 stories; there are five.

Three run-level ops arrived with them (`RunEffects`, and registered in
`ContentDB.KNOWN_OPS`):
- **`per_encounter`** on `gain_coins` / `lose_coins` / `lose_hp`, because the
  sheet prices almost everything as "[Encounter Value X n]". It multiplies by
  `run.encounter_number()`, so encounter 1 still pays. An explicit `amount`
  still wins.
- **`grant_sticker`** with a named suit or `"random"` (Cheap Tricks).
- **`casino_spin`**, one pull on `CasinoGame`'s prize table, resolved in place.
  The sheet's note on Lost Soul is "grants a use of the Slot Machine in the
  Casino Encounter": the reward is the spin, not a visit, so it does not route
  to the casino screen.

**A story choice can pick a fight** (Guarded Treasure): `"then": "combat"` plus
`bonus_rewards`. `Game.story_started_a_fight()` re-points the pending encounter
at a combat (`record_visit` already ran when the story was chosen, so it must
not add a second entry to the history) and stages the prize on
`RunState.bonus_rewards`. **`combat_finished` pays it on the win and clears it
on the loss** — the relic is the prize for beating the guards, so the story
screen must never hand it over itself.

**Exactly five autoloads** (`project.godot` order matters: Db before Game): `Db` (loads ContentDB), `Game` (RunState + screen routing + cinematics + `current_screen_path`, used by HeaderHud to hide itself outside a run), `Fx` (shake/hit-stop/floating numbers, plus the custom cursor — `Fx.init_cursor()`/`Fx.set_cursor_grabbing()`), `Telemetry` and `Audio` (both inert headless, both reference no other autoload; see their sections). `Game.goto_screen()` swaps children under Main's ScreenRoot — it must `remove_child` before `queue_free` (same-name siblings get auto-renamed otherwise). The **shop** (`src/ui/shop_screen.gd`) is laid out to the mock in the doc, which the text export drops — pull the doc as `?export=zip` to get its images (`image4.png` is the shop, `image2.png` the Ultimate reference). It hides `ScreenBase`'s title/content stack and draws its own board, and reuses `LayoutTab.AbilityChit` / `LayoutTab.DropZone` rather than adding a third copy of the drag-and-drop classes. Screens extend `ScreenBase`; combat UI components (`src/ui/combat/`) are built procedurally in code rather than as .tscn files — scene files here are one-node skeletons. `AbilityCard` and `UnitView` keep **constant frames** and shrink their own text to fit (`_fit_description_font`, `_name_font_size`) — measure with `get_theme_font(...)` only after the Control is in the tree, or the theme variation's real font is not what you measured. Relic art goes through `SuitAssets.relic_texture(id)`, which falls back to the house chip — the two relic UIs used to interpolate the path by hand and silently render *nothing* on a miss, which is how Gambler's Confidence went invisible after its rename. A `Button.icon` is drawn at the texture's native size: suit/relic art is 1024px square, so put it in an inset child `TextureRect` (the socket pattern) rather than assigning `icon`.

**Header numbers never move** (patch 0.22): every numeric label in the header reserves a fixed `custom_minimum_size.x` measured from its widest reading in the real theme font (`_reserve_number_widths`, deferred because a Label only resolves its theme font inside the tree) and is right-aligned in it. Alfa Slab One has proportional digits and both header rows are positioned each frame from their own measured width, so without this `00:01` → `00:11` dragged every sibling sideways once a second. **The HP reading is the exception to the right-alignment** (patch 0.113): it is LEFT-aligned in its column and shares a 5 px `health_box` with the heart, because right-aligning a two-digit reading inside a `999/999` column parked it a thumb's width from the icon. `_reserve()` takes the alignment as an argument for exactly this.

**Persistent header UI** (patch 0.17, `src/ui/header_hud.gd`): `HeaderHud.attach()` is called once by `main.gd` and lives in `Main`'s `HudLayer` (a `CanvasLayer`, layer 10) so it survives every `goto_screen()` swap underneath it. It shows **Ace's portrait medallion and HP** (0.21, the Slay the Spire reference bar — `Portrait` draws `ace_portrait.png` through a UV-cropped circle polygon; the heart is `icon_health.png`, not `fx_heal.png` which has a cross) then Relics (top-left), and a Gold/Encounter/Timer/Layout/Settings group (top-right, patch 0.18 — screens must not draw their own gold tally, and must keep content below `HeaderHud.BAR_HEIGHT`). **The HP it shows is `Game.live_hp` when ≥ 0, else `run.hp`**: `run.hp` is only written back when a fight ends, so the combat screen publishes its own panel's *shown* value (`_publish_hero_hp()` after every hero hit/heal/refresh) and `Game.goto_screen()` resets `live_hp` on any non-combat screen. The header hides on `HIDDEN_SCREENS` (main menu, game over, victory), and opens `LayoutTab`/`SettingsTab` (the Layout Tab's machine view is read-only again since 0.21 — sticker placing moved to the **Sticker Applying screen**, `src/ui/sticker_screen.gd`, which `Game._after_encounter()` opens ahead of the loadout check whenever `run.sticker_inventory` is non-empty; the cursor becomes the held sticker via `Fx.set_cursor_sticker()`) — full-screen overlays also added to `HudLayer`, not to `get_tree().root` (a plain Control added directly under the root Window does not reliably resolve anchor percentages against the true viewport size the same frame it's created — position overlays from `get_viewport_rect().size` explicitly instead of trusting anchors on a freshly-instantiated Control).

**The backgrounds are living paintings** (patch 0.119, designer: "make it more
alive"). `LivingBackdrop` (`src/ui/fx/living_backdrop.gd`) replaces the plain
background `TextureRect` in combat and on the main menu with three layers over
the same still art: the painting through `assets/shaders/living_backdrop.gdshader`
(a slow Ken Burns drift plus a few pixels of mouse parallax, curtain sway at the
edges, lights that pulse and flicker inside ellipses, background reel windows
that scroll, warm haze low in the frame; and for the night exterior rain, wet
ground shimmer, two searchlights sweeping the clouds and lightning now and
then), gold dust motes (`CPUParticles2D`, so headless and GPU-less machines are
fine), and a foreground curtain cutout (`assets/backgrounds/curtains_overlay.png`
through `curtain_cloth.gdshader`) that moves with more parallax than the room.
Rules worth keeping:
- **Regions are ellipses and rectangles in the painting's own UV** (the
  `TextureRect` covers, so UV is the painting regardless of window size),
  measured off the 1536x1024 art by eye in the two presets `casino_floor()` and
  `night_exterior()`. No hand-painted masks anywhere. Uniform arrays are set as
  `PackedVector4Array`.
- **"Subtle, always alive" is the designer's call**: amplitudes are tuned so
  you notice the motion when it stops. `CB_DEBUG_BACKDROP_LOUD=1` multiplies
  them for review, and a two-frame pixel diff is how to check a region lands
  (a chandelier pulse of 0.13 read as still in a diff; 0.18 is the floor).
- **The curtain overlay draws above the painting and below everything else.**
  The Flush card already overlaps the painted right curtain, so a curtain in
  front of the UI would cover it. The generated art came out at 22% of the
  frame per side; `tools/art/spread_curtains.py` slides both to 14% and is
  named as the entry's `post` step in the manifest, so regeneration is
  reproducible without re-rolling the art.
- `react(strength)` kicks the fabric; `combat_screen` calls it beside
  `Fx.shake` for hits of 12 or more, so the room and the camera answer the
  same blow. `UnitView` also breathes now: `_sprite` hangs off a `_breath`
  wrapper that bobs 2 px on its own clock, so the pose tweens on the sprite
  never fight it.

**The slot machine** (doc "Assets → Gameplay Elements", patch 0.22): `SlotCabinet` (`src/ui/combat/slot_cabinet.gd`) is the golden machine — a generated marquee, reel window and coin drawer, plus a lever. The window and drawer art each carry a **flat magenta rectangle that `chroma_key.gd` turns into a real hole**, so the cabinet is drawn OVER live content that shows through it; that is why every existing animation still works untouched. Its bands are nine-sliced **by hand in `_draw`** (a `NinePatchRect` would draw the 1500-px source margins) with the slice margins measured off the keyed PNGs into `WINDOW_HOLE`/`DRAWER_HOLE` — **regenerating that art means re-measuring those constants**. Textures are `preload`ed: a `load()` inside `_draw` hands back a placeholder that paints a flat white rectangle. Modes: COMBAT (reels + chip tray), CASINO (prize reels + the result line in the drawer), GRID (a symbol grid, used by the shop, Layout tab and Sticker screen). `refresh_layout()` after the reel count changes — a plain Control gets no sort-children notification.

Patch 0.114: the drawer gets **no dark recess and no coloured well** — the chips lie straight on the chassis's own maroon wood, which is the plank the drawer frame is painted in. `ChipTrayView._well_style()` returns a `StyleBoxEmpty` on purpose; anything drawn there hides the plank.

Patch 0.113 added a drawn **chassis** so the three bands read as one machine instead of three loose pictures: `draw_chassis()` runs on a `_backdrop` layer added BEFORE the content (so the reels and chips still draw over it) and fills the bands' transparent padding with a body slab and a dark well behind each hole; `draw_cabinet()` then adds two side rails, a bolted coupler across the window/drawer seam, the lever on a bracket, and a **chase of bulbs** seated `BULB_INSET` in from the outer edge and driven by `_process`. `pull_lever()` swings the lever on every spin and `celebrate()` runs the chase hot on a payout; both machines call them. Anything drawn from the geometry must use `custom_minimum_size.y` and `size.x - _lever_width()`, never a stretched `size.y`.

**Use limits are printed on the card** (doc "Per Turn & Per Combat", patch 0.113): `AbilityCard` puts a lavender `N Per Turn` and/or a peach `N Per Fight` pill flush in the top-right corner, stacked when both apply. It replaced the 0.13 icon badge, which said "limited" without saying to what and showed nothing at all for `per_combat`. No shipped ability carries both limits yet — the stacked case in the doc's mock is implemented but unused.

**`ReelStrip` is one widget for both machines** (patch 0.22; the Casino used to keep a duplicate). Geometry and feel are properties (`window_size`, `face_height`, `strip_faces`, `base_duration`, `stagger`, `stop_flash`, `framed`, `shrink_to_fit`, `face_provider`, `filler_pool`), and **the strips scroll DOWNWARD**: the landing cell is `LANDING_INDEX = 1` near the top and the strip starts far above it, so `position:y` increases as the faces fall. `reel_centre(i)` is where that reel's paid chip comes from.

**Combat layout and VFX** (patch 0.21): the bottom band spans the full width with a **fixed `MACHINE_WIDTH` area** for the machine on the left and the ability row filling the rest — `ReelStrip.scale_for(count)` shrinks reels to fit `MAX_ROW_WIDTH` (530 since the cabinet and its lever take the rest) at 5–6 reels, so buying reels never moves the cards, and six 190-wide cards fit. **Pass sits in its own strip between the enemies' band and the ability row**, right-aligned. The Dagger Slash is `SlashArc` (nested class in `combat_screen.gd`): three **non-overlapping rings** (purple, teal, white core) along a tapered circular arc plus seeded drybrush filaments, `material = _vfx._additive`, drawn in by `progress` over 0.10 s then dissolved — the rings must not overlap, because additive strokes piled on each other sum to white and the teal vanished. `_dagger_slash(at, angle, palette, scale)` takes a direction so Flush cuts from eight angles; `_impact()` is the same arc in red. **Patch 0.22: the default sweep is a quarter turn clockwise (`SLASH_ANGLE`, `ULTIMATE_ANGLES`, `IMPACT_ANGLE`) and the arc is offset by its own `belly()`** — the crescent is drawn on a circle centred on the node, so pinning that centre to the target put the target in the crescent's empty middle ("it goes around it"). It lands on **`UnitView.strike_landed`**, emitted on the strike/release frame of every pose animation (and after the plain-lunge fallback) — `play_slash()` only returns after the lunge, 0.09 s late. Flush's cut-in is the generated `ace_flush_splash.png` whipped in over a procedural purple `PaintStreak` (`_splash_cut_in()`, falling back to `_paint_streak_closeup()` when the art is missing). `Fx` handles `NOTIFICATION_DRAG_END` itself to reopen the hand cursor — the chip button that started the drag is rebuilt before the notification reaches it.

**The Choice screen** (doc "Choice", rebuilt patch 0.116, `src/ui/map_screen.gd`):
header, the offered encounters as framed cards carrying an icon, a name and a
description, then `PathRibbon` (`src/ui/map/path_ribbon.gd`) underneath.
- The ribbon is **drawn, not built from child nodes**: the road, the fork, the
  dashes and the tokens all have to agree about one set of coordinates, and a
  Container would own those coordinates instead. It degrades to a coloured
  token with a letter when `assets/icons/encounter_<type>.png` is missing, so
  it worked before the art existed.
- Road solid up to the stop the player is on, then the fork, then dashed to
  the boss. **The solid run stops one short (`i < here - 1`)** or a stub of
  road draws straight through the split.
- The screen no longer prints HP and coins. `HeaderHud` has owned both since
  0.18 and this screen was drawing a second, quietly different copy.

**Run flow** (patch 0.21): `RunState.pending_encounter` holds the encounter being played (type, plus lineup+seed for combat, event for story, the serialised `ShopStock` and SOLD keys for the shop). `Game.choose_encounter()` sets it, `resume_run()` reopens it from the beginning, `_after_encounter()`/`combat_finished()` clear it, and screens call `Game.commit_encounter()` the moment their outcome is banked (casino spin rolled, story choice made, rest taken, treasure opened) so a save from there resumes at the map instead of replaying a reward. Without this, exiting to the main menu skipped the encounter because `record_visit()` runs at choice time. `EncounterFactory.combat_config()` honours `option.lineup` and reports `lineup` in the config for that purpose. `RunState.swap_abilities(a, b)` backs the drop-to-swap in both loadout UIs (equipped↔equipped reorder, equipped↔trash rescue).

**Block gain animates from every source** (patch 0.114): `UnitView.play_block_gain(amount)` draws a shield sweeping up the unit and pulses the HP panel, and the `block_gained` handler holds the beat for 0.34 s. The event was never missing — relic and start-of-turn passive grants fire at a round start, a beat *before* the reels spin, so the old 0.4 s icon was gone while the player was still watching the machine. Anything new that grants Block must go through `EffectInterpreter._grant_block` or emit `block_gained` itself, or it will be silent.

**Loan coins land immediately** (0.118, "Cash Advance should always give
coins"): while a loan's reward or penalty executes, `CombatSim.settling_loan`
is true and the interpreter routes `gain_coins`/`lose_coins` to
`sim.run_ops` + a `run_effect` event instead of `pending_rewards` (which a lost
fight never paid). The presenter applies each `run_effect` to `Game.run` as it
plays; `RunBot` applies `sim.run_ops` after the fight whichever way it went.
`RunEffects` already clamps `lose_coins` at zero: "taking as many as it can".
`TelemetryFilter` DROPs `run_effect` (the coins are on the run row).

**Every chip arrival is animated from where it came** (0.118): `chips_generated`
carries `source` (`earn` from an ability's `add_chips`, `gift` with the
promising enemy's `actor`, `break` from the Golem) and the presenter flies a
chip from Ace, the giver or the Golem into the drawer, then
`ChipTrayView.reveal(suit)` steps the shown count up by one. `spin_resolved`
reveals only its own `payout`. **Do not call `_tray_view.refresh()` on an
arrival**: the sim has already put every later chip in the live tray, so a
refresh exposed the Loan Shark's gift before its flight (designer's note). The
old `ABILITY_ANIMS` "chip" arm is gone; it only ever covered Color Up, which is
why Hit and Card Trick had no Earn animation.

**Combat carries the run's max HP** (0.118): `EncounterFactory` passes
`hero_max_hp` and `CombatSim` builds the hero from it, not the hero def's 80.
Before, a max HP raised by a story or relic showed in the header and not on
the panel ("Max HP numbers in the UI and below the character are
inconsistent").

**An Elite is fought once per run** (designer, 0.118): `RunState.fought_lineups`
(serialised) is recorded by `Game._start_combat` and `RunBot` the moment a
lineup is drawn, and `EncounterFactory` draws an Elite from the ones not yet
fought, falling back to the whole pool only when every Elite has been. A
pinned (resumed) lineup still wins, so a save never re-rolls its fight.

**`UnitView.refresh()` vs `refresh_statuses()` vs `refresh_block()`** (patch 0.113 — "health drops more than it should, then rises back up to the correct number"): HP and Block are the two ANIMATED readouts, stepped hit by hit by `apply_damage_display(hp_lost, blocked)`. The sim resolves a whole multi-hit attack synchronously before its first hit is drawn, so any *absolute* re-sync landing between two `damage_dealt` animations snapped the bar to the final HP and the remaining hits then subtracted again — undershoot, then a bounce back up on the next refresh. `refresh()` now re-syncs everything, `refresh_block()` only the shield, and `refresh_statuses()` only the pips/passive/loans/Mark. **Every mid-attack call site must use the narrow ones**: `status_applied`, `turn_started`/`turn_ended`, `rage_spent`, `enemy_busted` and `passive_counter` take `refresh_statuses()`, `block_gained` takes `refresh_block()`; only `healed`, `round_ended` and `_refresh_all` keep the full one. **The three `loan_*` handlers moved to `refresh_statuses()` in 0.118**: a loan coming due emits `loan_due` and THEN its `damage_dealt`, so the full refresh in `loan_due` snapped the bar to the already-resolved HP and the hit subtracted again ("you take damage and then heal back up for your block"). `turn_started` also calls `refresh_block()` now, because the sim spends Block at the start of its owner's turn and the shield should read zero on that beat. 0.22 added four of those call sites at once, which is when the bounce became visible.

**Passive plaques are badges** (0.118): `PassiveChip` draws `icon` with the
number in a strip under it (`passive_bust.png`, `passive_break.png`), and the
Loan Shark shows the badge alone (`show_value = false`; its countdown "serves
no purpose for the player"). The tooltip's number comes from the def
(`every` / `threshold`), because the keyword prose said "every 20" for two
patches after the sheet moved the Golem to 30.

**Ability lists show the real cost and the limits** (0.118): the reward screen
and both shop views use `AbilityCard.cost_row(def)` (suit art, the socket's own
ghost textures) and `AbilityCard.limits_row(def)` (the Per Turn / Per Fight
pills) instead of "Cost: H S" letters. Keep new ability surfaces on the same
two helpers.

**Chip placement on abilities** (doc, 0.118): `AbilityState.placement_slot(suit)`
is the rule, pure and tested: the first empty slot asking for that suit, else
the leftmost empty `any`, else -1. `AbilityCard._can_drop_data/_drop_data`
accept a drop on the card body with it; the socket buttons keep their exact
slot drop for aimed placement.

The Rest node icon is a chair (`encounter_rest.png`, regenerated 0.118), not
a campfire; Pocket Rockets is "Deal 6 damage twice" (sheet 0.117); the Absorb
keyword reads "Consume all chips left on abilities."

**Enemy passives are worn as permanent buffs** (patch 0.113): the running number lives on `CombatActor.passive_counter` (not in a sim-side dictionary), is seeded by `CombatSim.passive_start(def.passive)` at spawn, **counts DOWN** and fires at 0 — the Dealer's Bust from 21, the Chip Golem's Break from 20 — and every change emits `passive_counter {actor, value}` so `UnitView` can tick its plaque. `_build_intent_entry` publishes the same field, so the panel and the plaque cannot disagree. Before 0.113 it counted UP in `_passive_counters` and nothing showed it.

**The presenter's busy flag is a single point of failure, and it is watched**
(patch 0.118). Every interaction is gated on `_busy`; `_play_events` is awaited
and sets it back. A script error inside ANY awaited handler aborts that
coroutine, the `await` never resumes, and `_busy` stays true forever: every
drop, click and Pass is ignored while the animations keep going. That is the
designer's "the game gets completely stuck the first time you Mark an enemy",
which did not reproduce here in six configurations (sim, standalone, three
real-run drives, the exported exe). GDScript cannot catch it, so `_process`
watches: past `BUSY_WATCHDOG_MS` it logs the event being played, records a
`presenter_stuck` telemetry row, clears the flag and re-syncs. **The player's
`godot.log` is the diagnostic**: a stuck fight now names its event there.
Never remove the watchdog to "clean up"; make the handlers not throw instead.
**What the designer's stuck run actually shows** (from the telemetry move log,
run `fdb3827d…`, V117): the first Mark (round 2, Card Sling with a Spade) went
through and that fight was WON; the run went Casino, then chose the encounter
3 combat (`muscle_and_service`, Bouncer + Server, Ace 79/80), and the last
recorded event is that fight's round 1 `spin_resolved`. Not one chip placed
after it. His `godot.log` has no script error and ends in the normal exit
lines. So the freeze is at the START of a fight that follows a Casino visit,
and it is a silent stall, not a crash: an `await` that never resumes, or
input that never reaches the sim. That exact lineup, driven in a real run,
reaches round 2 here. The unexplored variable is whatever the Casino left on
the run (a sticker, a relic, coins, health). `/api/runs` and
`/api/run/<id>/moves` + `/combats` on the service exist for exactly this kind
of question: read them before guessing. The designer's own account is
"the first duel", which the recorded run contradicts (its first duel was won);
the likeliest reconciliation is a second, unrecorded session whose spool had
not shipped yet, because a killed game ships on its next launch. Also driven
and clean in 0.118: a REAL drag through Godot's drag-and-drop
(`CB_DEBUG_DRAG=N` dispatches synthetic mouse events via
`Input.parse_input_event`, so `_get_drag_data`, the preview, `_drop_data` and
`NOTIFICATION_DRAG_END` all run). `setup()` also cancels a stale
`gui_is_dragging()` left over from a previous screen, which would swallow
every drop in the fight and look exactly like a freeze.
Also from that hunt: `CB_DEBUG_AUTOFIRE` and `CB_DEBUG_ENDTURN` now work
inside a real run and `AUTOFIRE` takes a comma list (`"1,3"` = Card Sling then
Double Down), which is what made a run-mode drive possible at all.

**The card's number walker must know every damage op** (0.118): with Ace
Weak, every printed figure dropped except The River's, because
`AbilityCard._collect_damage` only knew `damage`. It now covers
`damage_per_ability` and the passives' `active_effects`, and
`test_patch_117.gd` checks every "Deal N" in every description against
`damage_amounts()`, so a new op that prints a number cannot be missed again.
`damage_missing_pct` is deliberately excluded: it bypasses the attacker's
modifiers, so its printed number is right as it is.

**Combat presenter contracts** (patch 0.19–0.20): the chip tray draws from `ChipTrayView._shown`, not from the live `ChipTray` — the sim resolves an ability the instant its last socket fills, so a Go Again's winnings are already in the tray before the reels are seen to spin for them. `chip_assigned` calls `spend(suit)`; only `spin_resolved` (after `_payout_flourish`) and the discard/unassign paths `refresh()`. `Targeting.effective_target()` **records every branch it resolves**, including the lone-enemy shortcut — leaving that one unrecorded is what let a summon steal the target (patch 0.20). Live ability numbers walk the effect tree recursively via `AbilityCard.damage_amounts()`: since the Cash In rework a damage op can be nested in `cash_in.effects`/`else_effects` or duplicated in `bonus_effects`, and a top-level-only walk silently skipped Double Down, Bust and On a Roll.

**Combat presenter contracts** (patch 0.19): the hero gets an `actor_died` event like anyone else, emitted between `damage_dealt` and `combat_lost`, so his death animation lands on the killing blow — the handler branches on `event.data.actor == sim.hero.id` because the enemy path is a "cash out" (confetti, `_enemy_views.erase`). `enemy_move` picks its animation from the intent via `_intent_strikes()`: only a move with `instances > 0` plays `play_attack()`, or a heal/summon animates as an attack on the hero. The victory/defeat banner is a full-rect Label with centred alignment — `PRESET_CENTER` on an empty Label bakes zero-size offsets and renders from screen centre rightward. End Turn ("Pass") has now lived in four places; since 0.21 it has its own strip between the enemy band and the ability row and must stay out of both.

**Debug hooks for screenshot review** (`tools/screenshot.gd` needs a window, no `--headless`): `CB_DEBUG_AUTORUN=1` (main.tscn straight into a run), `CB_DEBUG_ENEMIES="dealer,dealer,..."` (force any lineup, works from the run flow too), `CB_DEBUG_ABILITIES="face_reader,color_up,..."` (force a hand, 0.113), `CB_DEBUG_AUTOFIRE=N` (fire the Nth equipped ability), `CB_DEBUG_ENDTURN=N` (auto-end N turns so enemy phases animate), `CB_DEBUG_STICKERS="spade,heart"`, `CB_DEBUG_RELICS="gamblers_confidence,..."`, `CB_DEBUG_HERO_HP=N`, `CB_DEBUG_BANNER=victory|defeat`, `CB_DEBUG_TIERS=1|2` (every equipped ability at that upgrade tier), `CB_DEBUG_OPEN_LAYOUT` / `CB_DEBUG_OPEN_SETTINGS`, `CB_DEBUG_REELS=N` (standalone combat with an N-reel machine), `CB_DEBUG_AUTOSPIN=1` (the casino game plays itself), `CB_DEBUG_CASINO=slots|dice|hunt` (open one casino game directly), `CB_DEBUG_CHOICE=N` (auto-take option N of an Options In Combat choice), `CB_DEBUG_HERO_STATUS="weak,frail"` (put statuses on Ace, 0.118), `CB_DEBUG_BACKDROP_LOUD=1` (exaggerate every living-backdrop motion for review, 0.119), `CB_DEBUG_TUTORIAL=1` (force the tutorial), `CB_DEBUG_TUTORIAL_DRIVE=1` (perform its steps) and `CB_DEBUG_OPEN_CODEX=1` (open the codex, 0.121), `CB_DEBUG_DRAG=N` (drag the first tray chip onto ability N through the real GUI, 0.118), `CB_DEBUG_ENEMY_STATUS="mark,weak"` (put statuses on every enemy at the start, for reviewing status-conditional UI like the card glow without playing into the state first, 0.116), `CB_DEBUG_STORY="cheap_tricks"` (open a story event standalone), `CB_DEBUG_MAP="combat,story,rest"` (open the Choice screen standalone with that history behind the player, so the path ribbon can be reviewed at any depth). `CB_DEBUG_AUTOFIRE` fills every socket, so multi-chip abilities (Flush) fire too. The sticker screen runs standalone with `CB_DEBUG_STICKERS`.

**Combat speed** (patch 0.121, phase 0 of the roadmap in
`docs/Casino_Brawyal_Status_Review_2026-09-30.pdf`).
- **`Engine.time_scale` has one writer: `Fx._apply_time_scale()`**, fed by
  `SpeedRules.effective(base, animating, hitstop, slowmo)` (`src/core/speed_rules.gd`,
  pure, tested). The player's speed (`AppSettings.combat_speed`, one of
  `SpeedRules.ALLOWED`: 1x, 1.5x, 2x, chosen only in the Settings tab, there is no button in combat) applies only while the presenter's `_busy` is true,
  so hovers, tooltips and thinking time never run fast; a hitstop beats
  everything; the ultimate's slow-mo is `Fx.set_slowmo(0.65)` and back to 1.0,
  never a literal write. Before 0.121 `hitstop()` and the flourish each wrote
  `1.0` back, which any toggle would have fought. `combat_screen._exit_tree`
  resets both, so leaving mid-animation cannot leak a speed. The run timer in
  `HeaderHud` divides `delta` by the time scale: it counts real seconds.
  Shader `TIME` in the living backdrop does follow the scale (the room drifts
  faster during 2x animations); accepted.
- **There is no undo.** Undo turn shipped in 0.121 and was removed on the
  designer's ruling ("it makes no sense"): the sim has no snapshot/restore,
  no `turn_undone` event and no Undo button. Do not re-add it.

**GIF capture** (patch 0.121): `tools/screenshot.gd` saves a frame sequence
when `CB_CAPTURE_EVERY=K` (and `CB_CAPTURE_FROM=M`) are set, and
`tools/capture_gif.ps1 -Out build/gifs/x.gif -Frames N -From M -Every K -Env
"CB_DEBUG_AUTORUN=1;CB_DEBUG_DRAG=1"` wraps it with ffmpeg's palette pipeline
(`-Env` is a semicolon string because `powershell -File` cannot pass a
hashtable). The living backdrop makes every frame differ, so GIFs run 6 to
9 MB at 960 px and 20 fps; drop `-Width` or raise `-Every` for the 8 MB
store limit. `build/gifs/` is gitignored with the rest of `build/`.

**Tutorial** (doc "Tutorial", patch 0.121): the first fight is a scripted
Ace vs Bouncer walk-through. It replaced the four-card `FirstFightGuide`
(deleted). Three layers, the same split as everywhere else:
- **Rules** (`src/core/combat/tutorial_script.gd`, pure, tested): the lineup
  (`door_duty`), the three scripted spins (2 Clubs + Diamond, 2 Spades + Club,
  3 Hearts which pay 4) and the Bouncer's forced opening move (Attack #2,
  `EnemyBrain.start_with`). `CombatSim` plays them through the `scripted_spins`
  and `first_moves` config keys; anything past the script is real dice.
- **Flow** (`Game`): `tutorial_wanted()` is the title-screen "Play Tutorial"
  toggle (`AppSettings.play_tutorial`) OR not yet completed
  (`tutorial_completed`). The tutorial replaces Encounter 1 only, and note
  that in `_start_combat` the encounter number is `run.history.size()`, NOT
  `run.encounter_number()` (the visit is recorded at choice time, so the latter
  is already the NEXT one). It is pinned in `pending_encounter["tutorial"]`
  so a save resumes it. Winning sets `run.tutorial_won`; **completion is
  recorded when the player picks Encounter 2** (doc: "until the player beats
  the Bouncer, moving forward to the reward screen... and choosing Encounter
  #2 afterwards"). `CB_DEBUG_TUTORIAL=1` forces it in a debug drive,
  `CB_DEBUG_TUTORIAL_DRIVE=1` then performs the asked-for drops itself.
- **Presenter** (`src/ui/combat/tutorial_flow.gd` + `tutorial_director.gd`):
  `TutorialFlow` is the script (banter, machine, sling, quick, final, pass,
  free, plus the round-3 jackpot hint) and `TutorialDirector` draws the dimmed
  screen with lit windows, talking and thinking bubbles, the arrow and the
  translucent ghost hand. The overlay never swallows input; the REAL drag
  completes a step, and `allows_drop()` refuses any other placement while a
  step is waiting (only the instructed chip, in the instructed card). No
  voice-over: there are no recorded lines yet, so every line is text.

**Onboarding** (patch 0.121, phase 0): `CodexTab`
(`src/ui/codex_tab.gd`, from Settings and the main menu,
`CB_DEBUG_OPEN_CODEX=1`) reads every keyword and status straight from
`Db.content` (`all_keyword_ids()`, `all_status_ids()`), which is how the
Vulnerable status text was found still saying 25% a year after the rule
became 50%.

**Audio** (patch 0.120). Music per screen, a casino-floor ambience on the hub
screens, and a one-shot per presenter beat. Providers are Google Lyria 3.5
(Gemini API) for music and Stable Audio 2.5 on Replicate for effects and
ambience, chosen after a network survey: `api.elevenlabs.io`, `api.stability.ai`
and `api.suno.ai` are TLS-blocked from the office like HeyGen, and Azure AI
Foundry has no music or SFX model. Keys `GEMINI_API_KEY` (paid tier) and
`REPLICATE_API_TOKEN` (prepaid) live in `.env`; `tools/audio/README.md` has the
signup steps. Rules worth keeping:
- **`SoundBank` (`src/core/audio/`) is the one list of ids.** The manifest
  must name exactly these ids, every `Audio.play_*(&"...")` in `src/ui` must
  name one, and `test_audio_manifest.gd` holds the three together. An entry
  without a file is `"pending": true`; a recorded sound dropped in by hand is
  `"source": "library"`. Regenerate with `node tools/audio/generate_audio.mjs`
  and then `--import` from PowerShell.
- **The `Audio` autoload is inert headless** (`is_live()` false, no players,
  every public method returns on its first line) and never `push_error`s: an
  unknown id or a missing file is a silent no-op, so a sound can never be the
  awaited handler that throws and freezes `_busy`. `CB_AUDIO=0` silences a
  windowed run.
- **Duck the player, never the bus.** The Settings sliders read bus levels
  live; `duck()` moves the active music deck's `volume_db` and comes back.
  Music tweens `set_ignore_time_scale(true)` because `Fx.hitstop` drops
  `Engine.time_scale` to 0.05.
- **Music routes through `ScreenMusic.track_for(scene, args)`** in
  `Game.goto_screen`; `args.music` overrides it, which is how the boss fight
  gets its theme (`_start_combat` sets `config["music"] = "boss"`; the sim
  ignores the key). `test_screen_music.gd` walks `res://scenes/screens` so a
  new screen cannot ship silent. Reward, loadout and sticker screens share the
  map theme so it does not restart between fights; the casino shares the shop's.
- **One hook for every button**: `node_added` connects `ui_hover`/`ui_press`
  to any `BaseButton` unless it carries the `silent` meta. Chip buttons and
  card sockets set it in `_init()` because they are heard through
  `chip_pickup`/`chip_assigned`; anything with its own sound should do the same.
- `SfxThrottle` denies a repeat of the same id inside 40 ms, because the sim
  resolves a three-hit attack in one call and three `hit_enemy` on one frame
  sum to a phased 3x thud. `variants: N` in the manifest produces `id_1..N.ogg`
  and `play_sfx` picks one; repetition is what makes generated foley sound
  cheap. Stingers and jingles are in `PITCH_LOCKED` and never jittered.
- `AppSettings` carries `music_pct`/`sfx_pct` beside `volume_pct`;
  `Telemetry.settings` is still the single writer (the Settings tab saves on
  slider release through it) and `Audio` only reads at boot.
- Loops get a seam pass in the pipeline (last 300 ms crossfaded into the head)
  and the autoload sets `loop = true` on the stream at load, so no `.import`
  file is ever hand-edited. Ask providers for WAV, never MP3: encoder padding
  breaks the seam.

**Telemetry** (patch 0.115). The game spools play data to
`user://telemetry/spool.ndjson` and POSTs batches to the ingest service in
`services/telemetry/`; it never touches Postgres, and the service is what
stamps the player's IP on a play (a desktop client cannot see its own public
address). Rules worth keeping:
- **Every decision lives in `src/core/telemetry/`** and is unit-tested; the
  `Telemetry` autoload holds an `HTTPRequest`, a `Timer` and a file handle and
  nothing else that needs thinking about. **It references no other autoload**,
  so load and teardown order are irrelevant — callers push into it.
- **One capture seam**: `combat_screen._drain()` is the only place
  `sim.drain_events()` may be called (`grep -c` it — the answer must be 1).
  `RunBot` never builds a presenter, so the 40-run balance instrument is silent
  by construction rather than by a flag.
- **Inertness** is one predicate: headless, editor, `CB_TELEMETRY=0`, no
  endpoint, or opted out ⇒ no HTTPRequest, no Timer, no directory, no file, and
  every public method returns on its first line.
  `tests/integration/test_telemetry_inert.gd` pins that, and also scans
  `src/core/` for autoload references with a word-boundary regex (a substring
  match flags `CasinoGame.` and `DiceGame.`).
- **Transport is at-least-once; storage is exactly-once.** The client keeps
  spooled lines until a 2xx, so a lost response means a resend — the server's
  `batch_id` PK and `moves (run_id, seq)` unique index are load-bearing. Do not
  "fix" that into a handshake.
- `JSON.parse_string` **pushes an engine error** on bad input; use
  `JSON.new().parse()` anywhere a corrupt file is expected, or a player's log
  fills with errors for something handled fine.
- The ingest key ships inside the build and **is not a secret** (unencrypted
  PCK). It is write-only, rate-limited, and rotating it is a one-line container
  update plus a one-line repo change.

**The service is live** (patch 0.115): Azure Container App `casino-telemetry`
in RG `abra-data-ai`, scaled to zero, writing to the `casino_brawyal` database
on `voicevikkidb`. The designer's dashboard is the app root plus
`?key=<CB_DASHBOARD_KEY>`; `/api/stats` is the JSON behind it.
- **Port 5432 on `voicevikkidb` is blocked from the office network**, so there
  is no `psql` path from a developer machine — every schema change ships as a
  numbered file in `migrations/`, which the service applies on boot. Do not
  add a step that assumes a local database client.
- That is also why `server.mjs` carries `bootstrap()`, a one-shot that creates
  the database and role from inside Azure when `CB_ADMIN_PG_URL` is set. **The
  admin secret was removed the minute it ran** and must be again if it is ever
  re-added — `voicevikkidb` hosts ten other applications. On Azure Postgres the
  server admin is *not* a superuser, so `GRANT "<role>" TO CURRENT_USER` has to
  precede `ALTER DATABASE ... OWNER TO` or it fails with `aclcheck_error`.
- **`/guide` is the designer's guide to every panel**, behind the same key,
  linked from the dashboard header. Keep it true when a panel changes: it is
  the only place that says what a number does NOT mean.
- **The Dockerfile copies `*.mjs`, not a hand-listed few.** Adding `guide.mjs`
  and forgetting to list it crash-looped the revision on import while traffic
  quietly stayed on the old one, which looks exactly like a deploy that did
  nothing.
- **`runs.path_id` only ever arrives on `run_ended`** (the path is chosen at
  the first map screen, after `run_started` has been sent), so it has to be in
  the `ON CONFLICT DO UPDATE` list, and the parameter needs `|| null` rather
  than `?? null` because the client sends `""` before a path exists. Omitting
  both is what left the Paths panel empty for every run before 0.116.
- **`/api/runs`, `/api/run/<uuid>/moves` and `/api/run/<uuid>/combats`** (0.118)
  are the investigation tools: the last fifty runs with how they ended, every
  recorded move of one run in order, and its fights with lineup and seed. A
  stuck fight is a move log that simply stops; read it before reproducing.
- `DELETE /api/install/<uuid>` is the erasure path (and how test data gets
  cleared, since nothing else can reach the database). It cascades but leaves
  the accepted `batch_id`s, so a resend cannot resurrect an erased player.

**Cinematics** (`assets/video/*.ogv`) are optional: `Game.play_cinematic()` no-ops when the file is missing **or when running headless** (keeps tests deterministic).

## Environment gotchas (all discovered the hard way)

- **GUT must stay on 9.5.x.** GUT 9.6+/9.7+ use `EditorDock` (Godot 4.6+) and break import on 4.5 with parse errors.
- Hand-written `.tscn`/`.tres`/`.gd` must be UTF-8 **without BOM** (PowerShell `Out-File`/`Set-Content -Encoding utf8` add one; Godot's parser fails with "Expected '['"). Use the Write tool or `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`.
- In PowerShell 5.1, `& godot ... 2>&1` wraps stderr into ErrorRecords and kills scripts under `$ErrorActionPreference = "Stop"`; run Godot via `cmd /c "... 2>&1"` (verify.ps1 does this).
- Art pipeline is **Azure AI Foundry** (`AZURE_OPENAI_IMAGE_*` in gitignored `.env`, deployment `gpt-image-2-1`): route `{endpoint}/openai/v1/images/generations`, `api-key` header, model in body. No native transparency — sprites generate on magenta and `tools/art/chroma_key.gd` keys them out (runs automatically). S0 tier ≈ 1 image/20s; the script retries on 429.
- **Character pose frames use image EDITS**, not fresh generations: a manifest entry with `"base": "assets/characters/ace_idle.png"` POSTs multipart to `{endpoint}/openai/v1/images/edits` (same key/model). Editing from the idle sprite is what keeps Ace's face/outfit identical across animation frames — always edit from the idle art, never chain edits. Frames are picked up automatically by `UnitView` via the naming convention `<def_id>_<pose>.png` (poses: throw_windup/throw_release/throw_follow, slash_windup/slash_strike/slash_follow, punch_windup/punch_strike/punch_follow); actors without pose files fall back to the tween-only lunge. `_return_to_idle()` fades the sprite fully to alpha 0 before swapping the texture back — swapping at partial alpha still reads as a visible flicker between the two poses' silhouettes (patch 0.17 fix).
- **Run the headless `--import` from PowerShell** (or `tools/verify.ps1`), not from Git Bash via `cmd /c "..."` — bash's quoting hands cmd an empty command line, it prints its banner and imports nothing, and new PNGs silently never get `.import` files (patch 0.21).
- **Character sprites were colour-graded once** (`tools/art/color_grade.gd`, patch 0.21: R×0.89, B×1.13, 10% desaturation — the generated art had the casino's warm light baked in and read as a red hue). The tool is NOT idempotent; every character PNG except `ace_flush_splash.png` has had exactly one pass. **Pose frames generated from an already-graded base inherit the look and must not be graded again** — patch 0.22 graded the Chip Golem's and Loan Shark's new frames by mistake and had to regenerate them.
- **A manifest entry with `"cutout": true`** tells `generate_art.mjs` to ask for a flat magenta rectangle *inside* the artwork as well as behind it; `chroma_key.gd` keys both, so the piece comes out as a frame with a real hole (the cabinet window and drawer).
- **The office network blocks api.heygen.com, steamdb, pcgamingwiki** (TLS handshake refused). Workaround: run in the AKS cluster (kubectl context `voice-vikki-media`) via a throwaway `python:3.12-slim` pod — see the HeyGen section in README.md and `tools/art/heygen_pod.py`. `kubectl cp` silently fails on this machine: stream in with `kubectl exec -i ... sh -c 'cat > /path'`, out with `kubectl exec ... base64 | base64 -d`, and set `MSYS_NO_PATHCONV=1` in Git Bash.
- **Local ffmpeg 8.0.1 has a broken libtheora encoder** (output plays garbled in Godot). Encode OGV in the pod with Debian ffmpeg (`apt-get install ffmpeg`) instead.
- Story wounds never kill: `RunEffects` clamps `lose_hp` to leave 1 HP (intentional).

## Workflow expectations

TDD is the norm here: every `src/core/` change starts with a failing GUT test (all existing modules were built red→green). End meaningful chunks with `tools/verify.ps1` green plus a commit; keep the `RUN BOT STATS` line in mind when touching balance-relevant numbers — combat tests pin exact damage values, so balance edits require updating both the JSON descriptions and the pinned test expectations.

## Patch 0.121 notes (designer's list), in brief

- **Drunk Patron** (sheet v0.121): 12 to 15 HP, Wild Swing (Deal 4) then Liquid Courage (Gain Strength 4, Heal 4), looping. Art is `enemy_drunk_patron.png` (the old Tipsy Patron, renamed in the manifest). The sheet's Standard Combat tab now reads: stage 1 Bouncer / 2 Servers / 4 Patrons; stage 2 Bouncer+Server / Dealer+Server / 2 Patrons+2 Servers; stage 3 unchanged; stage 4 Patron+Manager / Bouncer+Server+2 Patrons / Dealer+Server+2 Patrons; stage 5 unchanged. `test_patch_113.gd` pins every lineup against a transcription of that tab. The same sheet pass changed the Chip Golem (Bash 20, Crush 3x6), the Dealer's third move (2x3) and the boss (his second summon is 2 Servers); the six authored paths were re-read against the Encounter Choices tab and were already right.
- **Enemy status row** lives in a fixed 35 px slot (`UnitView.status_slot`) and may overflow it: the Dealer's 64 px Bust plaque used to push that unit up out of line with the others and with Ace. A stunned unit shows no intent (`show_intent` returns early on `stun`, and `enemy_busted` clears it).
- **All In** wears an ember aura, a warm pulse and a "+30%" chip while `damage_bonus_pct > 0` (`UnitView._update_bonus_fx`); the `damage_bonus` event drives the burst.
- **Hero death** (`UnitView.play_hero_death`): waits out the killing blow, then he reels, kneels and falls backwards and stays down; the banner waits for it.
- **Stories**: summaries use `{coins}`/`{hp}` tokens resolved by `RunEffects.summary_text` (the final figure for the encounter the player is on). `StoryPicker` prefers stories not seen this run AND not seen on this machine (`AppSettings.seen_stories`), resetting once all five have been met.
- **Ability tooltips** in the Layout Tab use `AbilityCard.detail_panel` (name, sockets, limits, text), the same panel the Shop's loadout preview shows.

## Build 1.22 notes (patch 0.122), in brief

- **Layout Tab is the mock's "Player Loadout"** (doc image: the slot machine on top, six ability slots in 3x2 below). Relics were dropped from it (the header owns them); a small Trash drop zone stays beneath the grid because nothing else in a run lets you discard between fights. Chits use `AbilityCard.detail_panel` tooltips.
- **Tutorial v0.122**: a new step 7 (`Step.NICE`, "Excellent, a few more hits..." with an arrow at the Bouncer's health) and step 8 lights only the Bouncer's head and intent (`UnitView.head_rect`). **Any chip completes a step**: `allows_drop` checks the ABILITY being taught, never the suit; the ghost hand carries the doc's suit only if the tray still has it (`_demo_suit`). Bubble fades are 30% slower (`FADE_IN`/`FADE_OUT`).
- **Chip reveal**: the payout flourish used to call `_tray_view.refresh()` on every landing, which showed the whole tray (bonus chip, Golem and Loan Shark gift chips) at the first landing, ahead of their own animations. It now reveals one chip per landed symbol and the `spin_resolved` handler reveals only the three-of-a-kind remainder.
- **Telemetry spool cost**: `line_count()` JSON-parsed the whole spool after every accepted batch, and `_raw_lines`/`_rewrite` looped per line in GDScript; a 3 MB backlog cost about 0.9 s of main thread PER BATCH (now about 0.08 s), and batches drain 0.3 s apart. This is the best explanation found for the "freezes a few seconds after load" reports (a cold-started service answers 10 to 20 s in, then the backlog drains); it could not be reproduced on the dev machine, whose spool is small. `[CB telemetry]` lines in godot.log report any batch that still costs more than 60 ms.
- **Art pipeline without node**: `tools/art/generate_art.mjs` needs node, which this machine lacks. The Drunk Patron's three punch frames were made with a PowerShell port of its edit branch (keys read from the untracked `env` file, then `chroma_key.gd`). The manifest entries are the source of truth for regenerating them.
- **Ace's kit re-read against the sheet**: only On a Roll differed ("Deal 10 to all enemies. Cash In: Repeat 1.", 12, 14); The River's text now reads as the sheet does (same behaviour). The four scratch abilities in the sheet's trailing columns (Double or Nothing, Smart Retreat, Poker Face, Playstyle Shift) are still NOT implemented.
- **Enemy intent shows its own heal** (`self_heal`, fx_heal icon), so the Drunk Patron's second move reads Strength 4 + Heal 4.
