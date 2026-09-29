# Audio pipeline

Music comes from Google Lyria 3.5 (Gemini API) and sound effects from Stable Audio 2.5 on
Replicate. Both keys live in the gitignored `.env` at the project root:

```
GEMINI_API_KEY=...          # https://aistudio.google.com/apikey  (Lyria is paid tier only)
REPLICATE_API_TOKEN=r8_...  # https://replicate.com/account/api-tokens  (prepaid credit)
```

The shipped game never calls either API. It plays OGG files from `assets/audio/<category>/`.

## Adding a sound

1. Add the id to the right list in `src/core/audio/sound_bank.gd` (`MUSIC_IDS`, `SFX_IDS` or
   `AMBIENCE_IDS`). Lock its pitch in `PITCH_LOCKED` if it is a jingle.
2. Add an entry to `audio_manifest.json` with the same id and category, a prompt, `seconds`,
   `loop` for music and ambience, and `variants: N` for a one-shot that repeats a lot.
   Mark it `"pending": true` until the file exists, or `"source": "library"` for a recorded
   sound you will drop in by hand.
3. Ask for it from a presenter: `Audio.play_sfx(&"my_sound")`. Unknown ids are silent no-ops,
   so the game runs before the file exists.
4. Generate: `node tools/audio/generate_audio.mjs --only my_sound`, then reimport from
   PowerShell so Godot writes the `.import` file:
   `tools\godot\Godot_v4.5.2-stable_win64_console.exe --headless --path . --import --quit`
5. Remove `pending`. `tests/unit/test_audio_manifest.gd` holds the bank, the manifest and every
   `Audio.play_*` call in `src/ui` together.

## Flags

`--dry-run` prints the prompts. `--only a,b` limits the run. `--force` regenerates.
`--audition` renders every theme as a 30 second Lyria clip into `tools/audio/auditions/`
($0.04 each) so prompts can be judged before the full tracks are bought ($0.08 each).

## What the post step does

Every provider result goes through the local ffmpeg: silence trimmed at both ends; for loops,
the last 300 ms crossfaded into the head so Godot's `loop = true` does not click; loudness
normalised (music -14 LUFS, effects -16 LUFS); encoded to OGG Vorbis. Music asks for WAV from
Lyria and effects ask for WAV from Stable Audio because MP3 encoder padding breaks the seam.
