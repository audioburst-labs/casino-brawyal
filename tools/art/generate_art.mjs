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

async function generateOne(manifest, asset, apiKey) {
  const body = {
    model: manifest.model ?? "gpt-image-1",
    prompt: `${manifest.style_prefix}\n\n${asset.prompt}`,
    n: 1,
    size: asset.size ?? "1024x1024",
    quality: asset.quality ?? manifest.quality ?? "high",
    output_format: "png",
  };
  if (asset.transparent) body.background = "transparent";

  const res = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify(body),
  });
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
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey && !dryRun) {
    console.error("OPENAI_API_KEY is not set (environment or project .env). Aborting.");
    process.exit(1);
  }

  let generated = 0, skipped = 0, failed = 0;
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
      await generateOne(manifest, asset, apiKey);
      console.log(`done   ${asset.id} -> ${asset.out}`);
      generated++;
    } catch (err) {
      console.error(`FAIL   ${asset.id}: ${err.message}`);
      failed++;
    }
  }
  console.log(`\n${generated} generated, ${skipped} skipped, ${failed} failed.`);
  process.exit(failed > 0 ? 1 : 0);
}

main();
