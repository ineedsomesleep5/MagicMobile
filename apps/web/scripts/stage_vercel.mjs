#!/usr/bin/env node
/**
 * Stages the built web app with its engine for a static Vercel deployment (apps/web/README.md, "Hosted on Vercel").
 *
 *   npm --prefix apps/web run build
 *   node apps/web/scripts/stage_vercel.mjs            # writes apps/web/.vercel-deploy
 *   npx vercel deploy apps/web/.vercel-deploy          # a preview, behind Vercel's login
 *
 * Vercel's free plan takes no file over 100 MB and the engine module is ~137 MB, so the module goes up gzipped
 * (~43 MB) and the page's engine worker unpacks it (manifest `files.wasmGzip`). The raw module is left out. The
 * vercel.json carries the cross-origin isolation headers the engine's SharedArrayBuffer channel needs.
 */
import { createReadStream, createWriteStream, existsSync } from "node:fs";
import { cp, mkdir, readdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";
import { constants, createGzip } from "node:zlib";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(web, "dist");
const engineDir = resolve(process.env.ENGINE_DIR ?? join(web, "../../packages/web-engine/build/web"));
const out = resolve(process.argv[2] ?? join(web, ".vercel-deploy"));
const LIMIT = 100 * 1024 * 1024;

const fail = (message) => { console.error(`stage_vercel: ${message}`); process.exit(1); };
if (!existsSync(join(dist, "index.html"))) fail(`no build in ${dist}; run npm --prefix apps/web run build first`);
if (!existsSync(join(engineDir, "manifest.json"))) fail(`no engine in ${engineDir} (set ENGINE_DIR)`);

const manifest = JSON.parse(await readFile(join(engineDir, "manifest.json"), "utf8"));
if (!manifest.files?.js || !manifest.files?.wasm) fail("the engine manifest names no files (a bundle from before the CE engine)");

// Keep the project link (.vercel) across runs; replace everything else.
await mkdir(out, { recursive: true });
for (const entry of await readdir(out)) if (entry !== ".vercel") await rm(join(out, entry), { recursive: true, force: true });
await cp(dist, out, { recursive: true });

const engineOut = join(out, "engine");
await mkdir(engineOut, { recursive: true });
for (const entry of await readdir(engineDir)) {
  if (entry === manifest.files.wasm || entry === "manifest.json") continue;
  await cp(join(engineDir, entry), join(engineOut, entry), { recursive: true });
}
const gzipName = `${manifest.files.wasm}.gz`;
await pipeline(createReadStream(join(engineDir, manifest.files.wasm)), createGzip({ level: constants.Z_BEST_COMPRESSION }), createWriteStream(join(engineOut, gzipName)));
const gzipBytes = (await stat(join(engineOut, gzipName))).size;
manifest.files.wasmGzip = gzipName;
manifest.wasm.gzipBytes = gzipBytes;
await writeFile(join(engineOut, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");

const immutable = [{ key: "Cache-Control", value: "public, max-age=31536000, immutable" }];
const revalidate = [{ key: "Cache-Control", value: "no-cache" }];
await writeFile(join(out, "vercel.json"), JSON.stringify({
  headers: [
    { source: "/(.*)", headers: [
      { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
      { key: "Cross-Origin-Embedder-Policy", value: "require-corp" },
      { key: "Cross-Origin-Resource-Policy", value: "same-origin" },
      // Unlisted until Caleb decides between public and private: no search engine indexes it.
      { key: "X-Robots-Tag", value: "noindex, nofollow" },
    ] },
    { source: "/engine/manifest.json", headers: revalidate },
    { source: "/engine/decks/(.*)", headers: revalidate },
    { source: "/engine/engine-(.*)", headers: immutable },
    { source: "/assets/(.*)", headers: immutable },
  ],
  // Deck links: Archidekt and Moxfield don't let another site's page read their APIs (CORS), so the page asks its own
  // origin and Vercel fetches the fixed endpoint (studioAdapter.fetchLinkedDeck). Opening a table on the table relay is
  // proxied the same way (it sends no CORS headers; RelayTransport.createTable); the table's WebSocket goes to the relay
  // directly. The relay allows 5 table creations a minute per caller IP, and through this rewrite every web host shares
  // Vercel's egress IPs: a relay CORS change for this origin is the proper follow-up. Then the app's own paths (/join,
  // /join/CODE) are the single page; files win over that rewrite.
  rewrites: [
    { source: "/provider/archidekt/decks/:id", destination: "https://archidekt.com/api/decks/:id/" },
    { source: "/provider/moxfield/:path*", destination: "https://api2.moxfield.com/:path*" },
    { source: "/relay/v1/:path*", destination: "https://magicmobile-relay.calebjfeliciano.workers.dev/v1/:path*" },
    { source: "/(.*)", destination: "/index.html" },
  ],
}, null, 2) + "\n");

// `vercel link` leaves a token in .env.local here: never upload it.
await writeFile(join(out, ".vercelignore"), ".env*\n.gitignore\n");

// Vercel refuses a file over the limit only after uploading everything else; fail here instead.
const walk = async (dir) => (await Promise.all((await readdir(dir, { withFileTypes: true })).map(async (entry) => {
  const path = join(dir, entry.name);
  return entry.isDirectory() ? walk(path) : [{ path, size: (await stat(path)).size }];
}))).flat();
const files = (await walk(out)).filter((f) => !f.path.includes(`${out}/.vercel/`) && !/\/\.(env|gitignore|vercelignore)/.test(f.path));
const big = files.filter((f) => f.size > LIMIT);
if (big.length > 0) fail(`over 100 MB: ${big.map((f) => f.path).join(", ")}`);
const total = files.reduce((sum, f) => sum + f.size, 0);
console.log(`staged ${files.length} files, ${(total / 1e6).toFixed(1)} MB, in ${out}`);
console.log(`engine ${manifest.files.wasm}: ${(manifest.wasm.bytes / 1e6).toFixed(1)} MB as ${gzipName}, ${(gzipBytes / 1e6).toFixed(1)} MB`);
