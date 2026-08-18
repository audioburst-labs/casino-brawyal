#!/usr/bin/env node
// Casino Brawyal — AI art generation pipeline (OpenAI Images API).
//
// Usage:
//   node tools/art/generate_art.mjs                 # generate all missing assets
//   node tools/art/generate_art.mjs --only ace_idle # one asset (comma-separate for several)
//   node tools/art/generate_art.mjs --force         # regenerate even if the file exists
//   node tools/art/generate_art.mjs --dry-run       # print what would be generated
//
// Reads OPENAI_API_KEY from the environment or the project-root .env file.
// Manifest: tools/art/art_manifest.json — { style_prefix, model, assets: [...] }.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(here, "..", "..");

function loadEnv() {
  const envPath = join(projectRoot, ".env");
  if (!existsSync(envPath)) return;
  for (const line of readFileSync(envPath, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

// Supports Azure OpenAI (preferred when AZURE_OPENAI_IMAGE_ENDPOINT is set)
// and the standard OpenAI API as fallback.
function apiTarget() {
  const azureEndpoint = process.env.AZURE_OPENAI_IMAGE_ENDPOINT;
  if (azureEndpoint) {
    // Azure AI Foundry OpenAI-compatible v1 surface: deployment name goes in body.model.
    return {
      url: `${azureEndpoint.replace(/\/$/, "")}/openai/v1/images/generations`,
      headers: { "Content-Type": "application/json", "api-key": process.env.AZURE_OPENAI_IMAGE_API_KEY },
      key: process.env.AZURE_OPENAI_IMAGE_API_KEY,
      model: process.env.AZURE_OPENAI_IMAGE_DEPLOYMENT,
      isAzure: true,
    };
  }
  return {
    url: "https://api.openai.com/v1/images/generations",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${process.env.OPENAI_API_KEY}` },
    key: process.env.OPENAI_API_KEY,
    model: null,
    isAzure: false,
  };
}

// gpt-image-2 on Azure rejects background:"transparent"; transparent assets are
// generated on a flat magenta screen instead and keyed out afterwards by
// tools/art/chroma_key.gd (run automatically by this script).
const MAGENTA_INSTRUCTION =
  "The entire background must be one flat, uniform, pure magenta color (#FF00FF) " +
  "filling every pixel that is not the subject. No gradients, no vignette, no shadows " +
  "cast on the background, no magenta anywhere on the subject itself.";

async function generateOne(manifest, asset, target) {
  let prompt = `${manifest.style_prefix}\n\n${asset.prompt}`;
  const body = {
    n: 1,
    size: asset.size ?? "1024x1024",
    quality: asset.quality ?? manifest.quality ?? "high",
    output_format: "png",
  };
  body.model = target.model ?? manifest.model ?? "gpt-image-1";
  if (asset.transparent) {
    if (target.isAzure) prompt += `\n\n${MAGENTA_INSTRUCTION}`;
    else body.background = "transparent";
  }
  body.prompt = prompt;

  let res;
  for (let attempt = 1; ; attempt++) {
    res = await fetch(target.url, {
      method: "POST",
      headers: target.headers,
      body: JSON.stringify(body),
    });
    if (res.status !== 429 || attempt >= 6) break;
    const text = await res.text();
    const wait = Number(text.match(/retry after (\d+) second/i)?.[1] ?? 20) + 2;
    console.log(`  rate-limited, waiting ${wait}s (attempt ${attempt})`);
    await new Promise((r) => setTimeout(r, wait * 1000));
  }
  if (!res.ok) {
    throw new Error(`API ${res.status} for "${asset.id}": ${(await res.text()).slice(0, 500)}`);
  }
  const json = await res.json();
  const b64 = json.data?.[0]?.b64_json;
  if (!b64) throw new Error(`No image data returned for "${asset.id}"`);

  const outPath = join(projectRoot, asset.out);
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, Buffer.from(b64, "base64"));
  return outPath;
}

async function main() {
  loadEnv();
  const args = process.argv.slice(2);
  const force = args.includes("--force");
  const dryRun = args.includes("--dry-run");
  const onlyIdx = args.indexOf("--only");
  const only = onlyIdx >= 0 ? new Set(args[onlyIdx + 1].split(",")) : null;

  const manifest = JSON.parse(readFileSync(join(here, "art_manifest.json"), "utf8"));
  const target = apiTarget();
  if (!target.key && !dryRun) {
    console.error("No image API key found (AZURE_OPENAI_IMAGE_API_KEY or OPENAI_API_KEY, env or project .env). Aborting.");
    process.exit(1);
  }

  let generated = 0, skipped = 0, failed = 0;
  const toKey = [];
  for (const asset of manifest.assets) {
    if (only && !only.has(asset.id)) continue;
    const outPath = join(projectRoot, asset.out);
    if (existsSync(outPath) && !force) {
      console.log(`skip   ${asset.id} (exists: ${asset.out})`);
      skipped++;
      continue;
    }
    if (dryRun) {
      console.log(`would  ${asset.id} -> ${asset.out} [${asset.size ?? "1024x1024"}${asset.transparent ? ", transparent" : ""}]`);
      continue;
    }
    try {
      console.log(`gen    ${asset.id} ...`);
      await generateOne(manifest, asset, target);
      console.log(`done   ${asset.id} -> ${asset.out}`);
      if (asset.transparent && target.isAzure) toKey.push(join(projectRoot, asset.out));
      generated++;
    } catch (err) {
      console.error(`FAIL   ${asset.id}: ${err.message}`);
      failed++;
    }
  }

  if (toKey.length > 0) {
    console.log(`\nchroma-keying ${toKey.length} image(s)...`);
    const godot = join(projectRoot, "tools", "godot", "Godot_v4.5.2-stable_win64_console.exe");
    const result = spawnSync(godot,
      ["--headless", "--path", projectRoot, "-s", "res://tools/art/chroma_key.gd", "--", ...toKey],
      { stdio: "inherit" });
    if (result.status !== 0) {
      console.error("chroma keying failed");
      failed++;
    }
  }

  console.log(`\n${generated} generated, ${skipped} skipped, ${failed} failed.`);
  process.exit(failed > 0 ? 1 : 0);
}

main();
