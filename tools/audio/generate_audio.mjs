#!/usr/bin/env node
// Casino Brawyal: music and sound-effect generation pipeline (patch 0.120).
//
//   node tools/audio/generate_audio.mjs                # everything missing
//   node tools/audio/generate_audio.mjs --only combat  # one id (comma-separate for several)
//   node tools/audio/generate_audio.mjs --force        # regenerate even if the file exists
//   node tools/audio/generate_audio.mjs --dry-run      # print what would be generated
//   node tools/audio/generate_audio.mjs --audition     # music only: 30 s clips to tools/audio/auditions/
//
// Providers (designer's choice, 2026-09-29):
//   music     Google Lyria 3.5 through the Gemini API      GEMINI_API_KEY      (paid tier)
//   sfx       Stable Audio 2.5 on Replicate                 REPLICATE_API_TOKEN (prepaid credit)
// Both keys live in the gitignored .env. The shipped game never calls either API.
//
// Every result is post-processed with the local ffmpeg: trimmed, seam-crossfaded when it
// loops, loudness-normalised and encoded to OGG Vorbis at the path SoundBank.path_for(id)
// gives. After a run, reimport from PowerShell:
//   tools\godot\Godot_v4.5.2-stable_win64_console.exe --headless --path . --import --quit

import { readFileSync, writeFileSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join, resolve, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(here, "..", "..");
const MANIFEST = join(here, "audio_manifest.json");
const ROOT = "assets/audio";
const LOOP_SEAM_SEC = 0.3;
const REPLICATE_MODEL = "stability-ai/stable-audio-2.5";
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/interactions";

function loadEnv() {
  const envPath = join(projectRoot, ".env");
  if (!existsSync(envPath)) return;
  for (const line of readFileSync(envPath, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : null;
};

// ------------------------------------------------------------------ paths

function outPath(asset, variant = 0) {
  const stem = variant > 0 ? `${asset.id}_${variant}` : asset.id;
  return join(projectRoot, ROOT, asset.category, `${stem}.ogg`);
}

function takes(asset) {
  const n = Number(asset.variants ?? 0);
  return n > 0 ? Array.from({ length: n }, (_, i) => i + 1) : [0];
}

function isDone(asset) {
  return takes(asset).every((v) => existsSync(outPath(asset, v)));
}

// ----------------------------------------------------------------- ffmpeg

function run(cmd, cmdArgs) {
  const res = spawnSync(cmd, cmdArgs, { encoding: "utf8" });
  if (res.status !== 0) throw new Error(`${cmd} failed: ${res.stderr.slice(-800)}`);
  return res.stdout;
}

function durationOf(path) {
  return Number(run("ffprobe", ["-v", "error", "-show_entries", "format=duration",
    "-of", "csv=p=0", path]).trim());
}

// Raw provider output -> the shipped OGG. Loops get the seam pass: the last
// LOOP_SEAM_SEC is crossfaded into the head, so `loop = true` in Godot does
// not click at the join.
function finish(rawPath, asset, out) {
  const work = join(tmpdir(), `cb_audio_${process.pid}`);
  mkdirSync(work, { recursive: true });
  const trimmed = join(work, "trimmed.wav");
  const music = asset.category !== "sfx";
  // Leading silence off the front; trailing silence off the back (reverse, trim, reverse).
  run("ffmpeg", ["-y", "-v", "error", "-i", rawPath, "-af",
    "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,"
    + "areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse",
    "-ar", "44100", "-ac", "2", trimmed]);
  let source = trimmed;
  if (asset.loop) {
    const total = durationOf(trimmed);
    const cut = total - LOOP_SEAM_SEC;
    if (cut > 1.0) {
      const seamed = join(work, "seamed.wav");
      run("ffmpeg", ["-y", "-v", "error", "-i", trimmed, "-filter_complex",
        `[0]atrim=0:${cut.toFixed(3)},asetpts=PTS-STARTPTS[body];`
        + `[0]atrim=${cut.toFixed(3)},asetpts=PTS-STARTPTS[tail];`
        + `[tail][body]acrossfade=d=${LOOP_SEAM_SEC}:c1=tri:c2=tri[out]`,
        "-map", "[out]", seamed]);
      source = seamed;
    }
  }
  const norm = music ? "loudnorm=I=-14:TP=-1.5:LRA=11" : "loudnorm=I=-16:TP=-3:LRA=7";
  mkdirSync(dirname(out), { recursive: true });
  // loudnorm resamples to 192 kHz internally; pin the shipped rate after it.
  run("ffmpeg", ["-y", "-v", "error", "-i", source, "-af", norm, "-ar", "44100",
    "-c:a", "libvorbis", "-q:a", music ? "6" : "5", out]);
  rmSync(work, { recursive: true, force: true });
}

// -------------------------------------------------------------- providers

async function fetchJson(url, init, label) {
  let res;
  for (let attempt = 1; ; attempt++) {
    res = await fetch(url, init);
    if ((res.status !== 429 && res.status < 500) || attempt >= 6) break;
    const text = await res.text();
    // A quota of zero is a billing problem, not a busy server: say so at once
    // rather than retrying for five minutes (seen 0.120, Gemini free tier).
    if (/free tier|limit: 0/i.test(text)) {
      throw new Error(`${label}: the key is on a tier with no quota for this model. `
        + `Attach billing to the Google Cloud project behind the key. (${text.slice(0, 300)})`);
    }
    const wait = Number(text.match(/retry after (\d+)/i)?.[1]
      ?? res.headers.get("retry-after") ?? 15) + 2;
    console.log(`  ${label}: ${res.status}, waiting ${wait}s (attempt ${attempt})`);
    await new Promise((r) => setTimeout(r, wait * 1000));
  }
  if (res.status === 402) {
    // Out of prepaid credit: every later call would fail the same way, so stop
    // the whole run here instead of printing forty identical failures (0.120).
    console.error(`${label}: out of credit. Top up at https://replicate.com/account/billing and rerun; finished files are kept.`);
    process.exit(2);
  }
  if (!res.ok) throw new Error(`${label} ${res.status}: ${(await res.text()).slice(0, 600)}`);
  return res.json();
}

let replicateSchema = null;
// The public model page is client-rendered, so the input schema is read live
// once and every field we send is checked against it: prompt and duration
// must exist, the optional ones are dropped with a note when the model does
// not take them.
async function replicateInputs(prompt, seconds, seed) {
  if (!replicateSchema) {
    const model = await fetchJson(`https://api.replicate.com/v1/models/${REPLICATE_MODEL}`, {
      headers: { Authorization: `Bearer ${process.env.REPLICATE_API_TOKEN}` },
    }, "replicate model");
    replicateSchema = model?.latest_version?.openapi_schema?.components?.schemas?.Input?.properties ?? {};
    console.log(`  Stable Audio input fields: ${Object.keys(replicateSchema).join(", ")}`);
    for (const required of ["prompt", "duration"]) {
      if (!(required in replicateSchema)) throw new Error(`Stable Audio schema has no "${required}" field`);
    }
  }
  // The schema types duration as an integer (seen 0.120: a 0.5 s request was a 422),
  // so short effects are asked for at 1 s and the silence trim takes the rest.
  const wanted = { prompt, duration: Math.max(1, Math.round(seconds)), steps: 8, seed, output_format: "wav" };
  const input = {};
  for (const [k, v] of Object.entries(wanted)) {
    if (k in replicateSchema) input[k] = v;
    else if (k !== "prompt" && k !== "duration") console.log(`  (schema has no "${k}", not sent)`);
  }
  return input;
}

async function generateSfx(prompt, seconds, seed, rawPath) {
  const input = await replicateInputs(prompt, seconds, seed);
  let prediction = await fetchJson(
    `https://api.replicate.com/v1/models/${REPLICATE_MODEL}/predictions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.REPLICATE_API_TOKEN}`,
        "Content-Type": "application/json",
        Prefer: "wait=60",
      },
      body: JSON.stringify({ input }),
    }, "replicate predict");
  while (!["succeeded", "failed", "canceled"].includes(prediction.status)) {
    await new Promise((r) => setTimeout(r, 2000));
    prediction = await fetchJson(prediction.urls.get, {
      headers: { Authorization: `Bearer ${process.env.REPLICATE_API_TOKEN}` },
    }, "replicate poll");
  }
  if (prediction.status !== "succeeded") throw new Error(`Stable Audio: ${prediction.error ?? prediction.status}`);
  const url = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
  const audio = await fetch(url);
  if (!audio.ok) throw new Error(`download ${audio.status}`);
  writeFileSync(rawPath, Buffer.from(await audio.arrayBuffer()));
}

async function generateMusic(prompt, model, rawPathBase) {
  let interaction = await fetchJson(GEMINI_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": process.env.GEMINI_API_KEY },
    body: JSON.stringify({ model, input: prompt, response_format: { type: "audio" } }),
  }, "gemini music");
  // The documented call is synchronous; tolerate an async shape too.
  for (let i = 0; i < 90 && interaction.status && !["completed", "failed"].includes(interaction.status); i++) {
    await new Promise((r) => setTimeout(r, 2000));
    interaction = await fetchJson(`${GEMINI_URL}/${interaction.id}`, {
      headers: { "x-goog-api-key": process.env.GEMINI_API_KEY },
    }, "gemini poll");
  }
  const steps = interaction.steps ?? interaction.outputs ?? [];
  let audio = null;
  for (const step of steps) {
    if (step.type && step.type !== "model_output") continue;
    for (const part of step.content ?? []) {
      if (part.type === "audio" && part.data) audio = part;
    }
  }
  if (!audio) throw new Error(`Lyria returned no audio: ${JSON.stringify(interaction).slice(0, 400)}`);
  const ext = /wav/i.test(audio.mime_type ?? "") ? "wav" : "mp3";
  const rawPath = `${rawPathBase}.${ext}`;
  writeFileSync(rawPath, Buffer.from(audio.data, "base64"));
  return rawPath;
}

// ------------------------------------------------------------------- main

async function main() {
  loadEnv();
  const manifest = JSON.parse(readFileSync(MANIFEST, "utf8"));
  const only = option("--only")?.split(",").map((s) => s.trim()).filter(Boolean);
  const dry = flag("--dry-run");
  const force = flag("--force");
  const audition = flag("--audition");
  const work = join(tmpdir(), `cb_audio_raw_${process.pid}`);
  mkdirSync(work, { recursive: true });

  let made = 0, skipped = 0, pending = 0, failed = 0;
  for (const asset of manifest.assets) {
    if (only && !only.includes(asset.id)) continue;
    if (asset.source === "library") { pending++; continue; }
    if (!force && !audition && isDone(asset)) { skipped++; continue; }
    // Music goes to Lyria; effects AND ambience (room tone is foley) to Stable Audio.
    const music = asset.category === "music";
    const prefix = music ? manifest.music_prefix : manifest.sfx_prefix;
    const prompt = `${prefix} ${asset.prompt}`.trim();
    if (dry) {
      console.log(`[dry] ${asset.id} (${asset.category}, ${asset.seconds}s${asset.variants ? `, x${asset.variants}` : ""})`);
      console.log(`      ${prompt.slice(0, 160)}${prompt.length > 160 ? "..." : ""}`);
      made++;
      continue;
    }
    try {
      if (music) {
        if (!process.env.GEMINI_API_KEY) throw new Error("GEMINI_API_KEY missing from .env");
        const lengthNote = ` About ${asset.seconds} seconds long. Instrumental only, no vocals, no lyrics.`
          + (asset.loop ? " Written to loop seamlessly: steady tempo, end on the same figure it opens with." : "");
        if (audition) {
          const dir = join(here, "auditions");
          mkdirSync(dir, { recursive: true });
          const raw = await generateMusic(prompt + " Instrumental only, no vocals.", "lyria-3-clip-preview",
            join(dir, asset.id));
          console.log(`audition ${asset.id} -> ${raw}`);
        } else {
          const raw = await generateMusic(prompt + lengthNote, manifest.music_model ?? "lyria-3.5",
            join(work, asset.id));
          finish(raw, asset, outPath(asset));
          console.log(`made ${asset.id} -> ${outPath(asset)}`);
        }
      } else {
        if (!process.env.REPLICATE_API_TOKEN) throw new Error("REPLICATE_API_TOKEN missing from .env");
        for (const take of takes(asset)) {
          const out = outPath(asset, take);
          if (!force && existsSync(out)) continue;
          const raw = join(work, `${asset.id}_${take}.wav`);
          await generateSfx(prompt, Number(asset.seconds ?? 1.0), (asset.seed ?? 7) * 100 + take, raw);
          finish(raw, asset, out);
          console.log(`made ${asset.id}${take ? ` take ${take}` : ""} -> ${out}`);
        }
      }
      made++;
    } catch (err) {
      failed++;
      console.error(`FAILED ${asset.id}: ${err.message}`);
    }
  }
  rmSync(work, { recursive: true, force: true });
  console.log(`\n${made} generated, ${skipped} already present, ${pending} library (by hand), ${failed} failed`);
  if (failed) process.exitCode = 1;
}

main().catch((err) => { console.error(err); process.exit(1); });
