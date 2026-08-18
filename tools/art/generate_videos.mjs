#!/usr/bin/env node
// Casino Brawyal — HeyGen talking-face cinematics (optional M7 polish).
//
// NOTE: api.heygen.com is blocked on the office network (TLS handshake refused).
// Run this from a network that allows it. The game runs fine without the videos —
// the intro/boss overlays only appear when the .ogv files exist.
//
// Usage:
//   node tools/art/generate_videos.mjs            # generate all missing clips
//   node tools/art/generate_videos.mjs --status   # poll pending video ids
//
// Requires HYGEN_API_KEY in .env and ffmpeg on PATH (MP4 -> OGV for Godot).

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(here, "..", "..");
const stateFile = join(here, "video_state.json");

const CLIPS = [
  {
    id: "ace_intro",
    out: "assets/video/ace_intro.ogv",
    text:
      "They say the house always wins. Well... the house never played against me. " +
      "Mister Moneyman took everything I had. Tonight, I'm taking it back — one spin at a time.",
    style: "confident, roguish, charming male voice",
  },
  {
    id: "moneyman_boss_intro",
    out: "assets/video/moneyman_boss_intro.ogv",
    text:
      "Well, well. The little card trick made it all the way to my office. " +
      "You should have taken your losses and crawled home, boy. " +
      "Now... the house collects EVERYTHING.",
    style: "deep, smug, villainous tycoon voice",
  },
];

function loadEnv() {
  const envPath = join(projectRoot, ".env");
  if (!existsSync(envPath)) return;
  for (const line of readFileSync(envPath, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

async function api(path, options = {}) {
  const res = await fetch(`https://api.heygen.com${path}`, {
    ...options,
    headers: {
      "X-Api-Key": process.env.HYGEN_API_KEY,
      "Content-Type": "application/json",
      ...(options.headers ?? {}),
    },
  });
  if (!res.ok) throw new Error(`HeyGen ${path}: ${res.status} ${(await res.text()).slice(0, 300)}`);
  return res.json();
}

async function main() {
  loadEnv();
  if (!process.env.HYGEN_API_KEY) {
    console.error("HYGEN_API_KEY not set in .env");
    process.exit(1);
  }
  const state = existsSync(stateFile) ? JSON.parse(readFileSync(stateFile, "utf8")) : {};

  // Pick a default avatar + voice from the account's available sets.
  const avatars = (await api("/v2/avatars")).data.avatars;
  const voices = (await api("/v2/voices")).data.voices.filter((v) => v.language === "English");
  const avatar = avatars[0];
  console.log(`using avatar: ${avatar.avatar_name} (${avatar.avatar_id})`);

  for (const clip of CLIPS) {
    const outPath = join(projectRoot, clip.out);
    if (existsSync(outPath)) {
      console.log(`skip   ${clip.id} (exists)`);
      continue;
    }
    let videoId = state[clip.id];
    if (!videoId) {
      const voice = voices[0];
      const body = {
        video_inputs: [{
          character: { type: "avatar", avatar_id: avatar.avatar_id, avatar_style: "normal" },
          voice: { type: "text", input_text: clip.text, voice_id: voice.voice_id },
        }],
        dimension: { width: 1280, height: 720 },
      };
      const created = await api("/v2/video/generate", { method: "POST", body: JSON.stringify(body) });
      videoId = created.data.video_id;
      state[clip.id] = videoId;
      writeFileSync(stateFile, JSON.stringify(state, null, 2));
      console.log(`queued ${clip.id} -> ${videoId}`);
    }
    // Poll until completed (HeyGen renders take a few minutes).
    for (;;) {
      const status = (await api(`/v1/video_status.get?video_id=${videoId}`)).data;
      if (status.status === "completed") {
        console.log(`render done ${clip.id}, downloading...`);
        const mp4 = Buffer.from(await (await fetch(status.video_url)).arrayBuffer());
        const mp4Path = outPath.replace(/\.ogv$/, ".mp4");
        mkdirSync(dirname(outPath), { recursive: true });
        writeFileSync(mp4Path, mp4);
        execSync(`ffmpeg -y -i "${mp4Path}" -c:v libtheora -q:v 7 -c:a libvorbis -q:a 4 "${outPath}"`);
        console.log(`done   ${clip.id} -> ${clip.out}`);
        break;
      }
      if (status.status === "failed") throw new Error(`render failed for ${clip.id}`);
      console.log(`  ${clip.id}: ${status.status}, waiting 20s...`);
      await new Promise((r) => setTimeout(r, 20_000));
    }
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
