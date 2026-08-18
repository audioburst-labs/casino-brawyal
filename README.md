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
- **Generate art:** `node tools/art/generate_art.mjs` (`--dry-run`, `--only <id>`, `--force`) — Azure gpt-image; transparent sprites are generated on magenta and keyed by `tools/art/chroma_key.gd`
- **Seeded combat transcript:** `tools\godot\..._console.exe --headless --path . -s res://tools/sim_cli.gd -- <seed> [enemies...]`
- **Screenshot a scene:** `... -s res://tools/screenshot.gd -- <scene.tscn> <frames> <out.png>` (no `--headless`)
- **HeyGen cinematics:** `api.heygen.com` is blocked on the office network. Run `tools/art/heygen_pod.py` in the AKS cluster (context `voice-vikki-media`): `kubectl run heygen-worker --image=python:3.12-slim --restart=Never --command -- sleep 7200`, `kubectl cp` the script + portraits into `/work/`, exec it with `HYGEN_API_KEY`, `kubectl cp` the MP4s back, convert with `ffmpeg -i in.mp4 -c:v libtheora -q:v 7 -c:a libvorbis -q:a 4 assets/video/<id>.ogv`. From an unblocked network, `node tools/art/generate_videos.mjs` works directly.

## Layout

- `src/core/` — pure game logic (no Node, headless-testable) · `src/autoload/` — Game, Db, Fx · `src/ui/` — screen presenters
- `scenes/` — main + screens + components · `data/` — JSON game content · `assets/` — generated art, theme, fonts
- `tests/` — GUT unit/integration tests · `tools/` — verify script, art pipeline
- Design spec: `docs/superpowers/specs/2026-08-18-casino-brawyal-design.md`
