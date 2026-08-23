# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Casino Brawyal — a slot-machine roguelike battler (Godot 4.5.2, GDScript, Windows desktop). v0.1 scope is Act I only: hero Ace, a 10-encounter run, boss Mr. Moneyman. Game rules live in `docs/Casino Brawyal.docx`; the approved architecture spec is `docs/superpowers/specs/2026-08-18-casino-brawyal-design.md`.

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

The balance instrument is `tests/integration/test_full_run_bot.gd`: 40 seeded full runs, prints `RUN BOT STATS` (win rate / avg death encounter). Run it after any content or damage-math change; ~23% bot win rate is the current baseline (random-play bot — humans do much better).

## Architecture

**Sim/presentation split (the load-bearing decision).** All game rules are plain `RefCounted` classes under `src/core/` — no Node, no scene tree, no awaits, seeded `GameRng` injected (independent named streams: map/combat/shop/rewards). Every state change appends a typed `CombatEvent`; UI screens are *presenters* that send commands to the sim, then `drain_events()` and play one animation per event. Never put rules in UI scripts; never reference autoloads from `src/core/`.

- `CombatSim` (src/core/combat/): phase machine `ROUND_START → ASSIGNMENT → (end_assignment runs the enemy phase) → ROUND_START | ENDED`. Commands: `begin_round`, `assign_chip`, `unassign_chip`, `set_target`, `end_assignment`. Abilities auto-fire when their last socket fills; socketed chips persist across rounds; the tray discards at `end_assignment`.
- Damage order (contract, tested): base + Strength → Weak (−25%) → Vulnerable (+25%) → Block → HP, per hit instance. Rounding is **half-up** (patch 0.1); Weak min 1. The High Stakes relic raises both pcts to 50% via CombatSim.
- Payout ruling (`payout.gd`): 1 chip per landed symbol, +1 bonus chip per suit with 3+ matches. Machine starts at **3 reels** (patch 0.12: designer reverted the 4-reel compensation — bot win rate dropped to 0%, flagged as a balance risk).
- Ace's kit comes from the capabilities Google Sheet (see README links): Mark/Cash In (+10 dmg, `cash_in` op), per-turn limits (`per_turn`), passives (fire each round start after activation), `bonus_mode: replace`, effect `condition`s (KNOWN_CONDITIONS). Enemies: hp_min/hp_max rolled per combat, `graph` brains, `summon`/`heal_allies`/`ally_attack_again`/`blackjack`/`self_heal` intent extras.
- `MapGenerator.next_options()` generates choices lazily from `RunState.history`; placement rules (#1 combat, #10 boss, rest only #4/#9, shop ≤3 non-consecutive, never at #2, ≥2 offers per run, guaranteed at #9, treasure ≤2 after #2, hard combat after #3) are property-tested over hundreds of simulated runs.
- Economy: combat gold comes from each lineup's `gold_min/gold_max` (sheet values); relic prices live on the relic defs; shop reel 60+30/purchase, stickers 10+2×enc, abilities 20–40. Balance is WIP — sheet numbers are the designer's, hero HP/start-reels/dealer-raffle were tuned here.
- `EncounterFactory.combat_config()` is shared by the `Game` autoload and `RunBot` so flow rules can't drift.

**Content is JSON, not .tres.** Everything (abilities, enemies, relics, statuses, lineups, story events) lives in `data/*/*.json` as `{"type": ..., "items": [...]}` and is parsed/validated by `ContentDB.load_all()` — unknown suits/ops/statuses/ids fail loudly, and `tests/unit/test_content_db.gd` doubles as the content linter. Behavior is a declarative effect-op DSL (`{"op": "damage", "amount": 3, "times": 2}` etc.) executed by `EffectInterpreter` (combat) and `RunEffects` (run level: coins/hp/relics). New ops must be registered in `ContentDB.KNOWN_OPS` and implemented in the matching interpreter. Relics declare a `trigger` from `ContentDB.KNOWN_TRIGGERS`; `CombatSim._fire_relics()` fires them at fixed points. Enemy moves support `intent.debuffs` (hit the hero) and `intent.self_status` (buff the enemy); brains are `sequence` / `weighted` (+`no_repeat`) / `phased` (hp thresholds, used by the boss).

**Exactly three autoloads** (`project.godot` order matters: Db before Game): `Db` (loads ContentDB), `Game` (RunState + screen routing + cinematics), `Fx` (shake/hit-stop/floating numbers). `Game.goto_screen()` swaps children under Main's ScreenRoot — it must `remove_child` before `queue_free` (same-name siblings get auto-renamed otherwise). Screens extend `ScreenBase`; combat UI components (`src/ui/combat/`) are built procedurally in code rather than as .tscn files — scene files here are one-node skeletons.

**Cinematics** (`assets/video/*.ogv`) are optional: `Game.play_cinematic()` no-ops when the file is missing **or when running headless** (keeps tests deterministic).

## Environment gotchas (all discovered the hard way)

- **GUT must stay on 9.5.x.** GUT 9.6+/9.7+ use `EditorDock` (Godot 4.6+) and break import on 4.5 with parse errors.
- Hand-written `.tscn`/`.tres`/`.gd` must be UTF-8 **without BOM** (PowerShell `Out-File`/`Set-Content -Encoding utf8` add one; Godot's parser fails with "Expected '['"). Use the Write tool or `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`.
- In PowerShell 5.1, `& godot ... 2>&1` wraps stderr into ErrorRecords and kills scripts under `$ErrorActionPreference = "Stop"`; run Godot via `cmd /c "... 2>&1"` (verify.ps1 does this).
- Art pipeline is **Azure AI Foundry** (`AZURE_OPENAI_IMAGE_*` in gitignored `.env`, deployment `gpt-image-2-1`): route `{endpoint}/openai/v1/images/generations`, `api-key` header, model in body. No native transparency — sprites generate on magenta and `tools/art/chroma_key.gd` keys them out (runs automatically). S0 tier ≈ 1 image/20s; the script retries on 429.
- **The office network blocks api.heygen.com, steamdb, pcgamingwiki** (TLS handshake refused). Workaround: run in the AKS cluster (kubectl context `voice-vikki-media`) via a throwaway `python:3.12-slim` pod — see the HeyGen section in README.md and `tools/art/heygen_pod.py`. `kubectl cp` silently fails on this machine: stream in with `kubectl exec -i ... sh -c 'cat > /path'`, out with `kubectl exec ... base64 | base64 -d`, and set `MSYS_NO_PATHCONV=1` in Git Bash.
- **Local ffmpeg 8.0.1 has a broken libtheora encoder** (output plays garbled in Godot). Encode OGV in the pod with Debian ffmpeg (`apt-get install ffmpeg`) instead.
- Story wounds never kill: `RunEffects` clamps `lose_hp` to leave 1 HP (intentional).

## Workflow expectations

TDD is the norm here: every `src/core/` change starts with a failing GUT test (all existing modules were built red→green). End meaningful chunks with `tools/verify.ps1` green plus a commit; keep the `RUN BOT STATS` line in mind when touching balance-relevant numbers — combat tests pin exact damage values, so balance edits require updating both the JSON descriptions and the pinned test expectations.
