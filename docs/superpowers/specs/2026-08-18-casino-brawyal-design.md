# Casino Brawyal v0.1 — Design Spec

Approved 2026-08-18. Source of truth for architecture decisions; gameplay rules live in `docs/Casino Brawyal.docx`.

## Scope

Act I only: hero Ace, 10-encounter run (9 + Mr. Moneyman boss), combat driven by a slot machine producing suit chips that power abilities, plus Story / Rest / Treasure / Shop encounters, rewards, relics, and machine upgrades (extra reels, symbol stickers). Desktop (Windows), Godot 4.5.2, GDScript.

## Platform decision

Godot 4.5 + GDScript, chosen after researching the references (Slay the Spire II = Godot 4 C#; Darkest Dungeon 2, Monster Train, Die in the Dungeon = Unity; DD1 = custom C++). Rationale: genre-proven (StS2), excellent 2D/Control UI, and a fully headless CLI loop (text scenes, script checks, tests, screenshots) suited to AI-agent development. Unity 6 is installed locally as a fallback; the pure-logic core would port.

## Architecture

1. **Sim/presentation split**: all rules in plain `RefCounted` classes under `src/core/` (`CombatSim`, `SlotMachine`, `Payout`, `MapGenerator`, `RunState`) — no Node, no scene tree, injected seeded RNG. State changes append typed events (`SpinResolved`, `DamageDealt`, …); UI screens are presenters that drain the queue and animate. Deterministic and headless-testable (the Mega Crit lesson: engine-agnostic rules).
2. **JSON content** in `data/` (heroes, abilities, enemies, lineups, relics, story events, statuses), parsed and validated at boot by `ContentDB`. Shared effect-op DSL (`{"op":"damage","amount":3,"times":2}`, `apply_status`, `convert_chips`, `respin_reel`, …) run by `EffectInterpreter`; script-class escape hatch for exotic relic/boss logic.
3. **Three autoloads only**: `Game` (scene flow + RunState), `Db` (content), `Fx` (shake, damage numbers, hit-stop).
4. **Payout ruling** (generalizes the doc to 4–8 reels, per suit): count n of a suit → n=1: 1 chip, n=2: 3 chips, n≥3: n+2 chips. Isolated in `payout.gd`.
5. **Map generation**: lazy per-step `next_options()` honoring all doc constraints (#1 Combat, #10 Boss, Rest only #4/#9, Shop ≤3 non-consecutive + guaranteed option at #9, Treasure ≤2 after #2 non-consecutive, Hard Combat after #3). Property-tested over thousands of seeded runs.
6. **Combat state machine**: ROUND_START → INTENT_AND_SPIN → ASSIGNMENT → ENEMY_PHASE → ROUND_END. Command API (`assign_chip`, `unassign_chip`, `set_target`, `end_assignment`). Chips persist in ability sockets across rounds; tray discards at end of assignment. Targeting per doc (taunt override, persistence, auto-retarget lowest HP). Statuses: Weak, Vulnerable, Taunt, Block, Strength, Stun. Enemy brains: sequence / weighted / phased.
7. **Tap-first chip assignment**; drag added later without touching the sim.

## Art

Real AI-generated art via OpenAI Images API (gpt-image), stylized-cartoon direction, driven by `tools/art/generate_art.mjs` + `art_manifest.json` (style-prefix for consistency, idempotent, `--only`/`--force`). ~55 assets. Style locked with the user on 4 test images before batch generation. Static sprites + programmatic motion (tweens/particles/shake/hit-stop). Optional HeyGen talking-face clips (boss intro, Ace monologue) as M7 polish, converted MP4→OGV for Godot.

## Initial content set (authored, doc leaves open)

12 Ace abilities (spade-synergy bonuses as schema fields), 9 enemies + phased boss Mr. Moneyman, 10 relics, 5 story events, stage-tagged lineups (Hard Combat: "advanced" draws stage+1, "buffed" ×1.25 HP/damage).

## Milestones

M0 bootstrap (engine, GUT, verify.ps1, art pipeline, style lock) → M1 slot core → M2 combat sim → M3 combat screen vertical slice (+combat art batch) → M4 run loop (+screen art) → M5 economy & events (+shop/story art) → M6 full content & boss (+remaining art, balance via headless run-bot) → M7 polish & ship (transitions, SFX stubs, save/Continue, Windows export). Every milestone ends with `tools/verify.ps1` green and a git commit.

## Verification

`tools/verify.ps1`: headless import → GUT tests (`.gutconfig.json`) → smoke boot with SCRIPT ERROR grep. Plus: payout table tests, map-constraint property tests, 200-run headless bot (also the balance instrument), `tools/screenshot.gd` for visual review, seeded replay via `tools/sim_cli.gd`.

## Known environment constraints

- GUT must stay on the 9.5.x line — 9.6+/9.7+ use `EditorDock` (Godot 4.6+) and break 4.5.
- Godot binaries live gitignored at `tools/godot/` (console exe for CLI stdout).
- Secrets in project-root `.env` (gitignored): `OPENAI_API_KEY`, `HEYGEN_API_KEY`.
