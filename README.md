# Casino Brawyal

A slot-machine-based roguelike battler. Play as Ace, a charming dagger-and-card slinger, spin the machine to earn suit chips, power your abilities, and take down Mr. Moneyman.

**Engine:** Godot 4.5.2 (GDScript) · **Version:** 0.1 (Act I)

## Setup

1. Godot console binary is expected at `tools/godot/Godot_v4.5.2-stable_win64_console.exe` (gitignored — download from godotengine.org).
2. Secrets go in a project-root `.env` (gitignored):
   ```
   OPENAI_API_KEY=sk-...
   HEYGEN_API_KEY=...
   ```

## Development

- **Run the game:** `tools\godot\Godot_v4.5.2-stable_win64.exe --path .`
- **Verify everything** (import + tests + smoke boot): `powershell -File tools/verify.ps1`
- **Generate art:** `node tools/art/generate_art.mjs` (`--dry-run`, `--only <id>`, `--force`)

## Layout

- `src/core/` — pure game logic (no Node, headless-testable) · `src/autoload/` — Game, Db, Fx · `src/ui/` — screen presenters
- `scenes/` — main + screens + components · `data/` — JSON game content · `assets/` — generated art, theme, fonts
- `tests/` — GUT unit/integration tests · `tools/` — verify script, art pipeline
- Design spec: `docs/superpowers/specs/2026-08-18-casino-brawyal-design.md`
