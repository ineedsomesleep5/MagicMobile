import { createReadStream, statSync } from "node:fs";
import { extname, join, normalize, resolve, sep } from "node:path";
import type { Connect, Plugin } from "vite";
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

/**
 * Cross-origin isolation, which the engine's SharedArrayBuffer channel needs. Every subresource must then be
 * same-origin or CORS: Scryfall images load with crossorigin="anonymous" (Scryfall answers with ACAO *).
 */
const isolation = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Resource-Policy": "same-origin",
};

/** The Web Image engine build (git-ignored; see README). ENGINE_DIR overrides it. */
const engineDir = resolve(process.env.ENGINE_DIR ?? resolve(__dirname, "../../packages/web-engine/build/web"));
const types: Record<string, string> = { ".js": "text/javascript; charset=utf-8", ".json": "application/json; charset=utf-8", ".wasm": "application/wasm" };

/**
 * Serves /engine/* from the engine build. The page keeps the module in the Cache API under its content hash, so
 * the module is never stored in the HTTP cache too (no-store); the manifest and wrapper revalidate.
 */
const serveEngine: Connect.NextHandleFunction = (req, res, next) => {
  const path = decodeURIComponent(new URL(req.url ?? "/", "http://local").pathname).replace(/^\/+/, "");
  const file = normalize(join(engineDir, path));
  if (!file.startsWith(engineDir + sep)) { res.statusCode = 403; res.end(); return; }
  let size: number;
  try {
    const info = statSync(file);
    if (!info.isFile()) throw new Error("not a file");
    size = info.size;
  } catch {
    next();
    return;
  }
  res.writeHead(200, {
    ...isolation,
    "Content-Type": types[extname(file)] ?? "application/octet-stream",
    "Content-Length": String(size),
    "Cache-Control": file.endsWith(".wasm") ? "no-store" : "no-cache",
  });
  if (req.method === "HEAD") res.end();
  else createReadStream(file).pipe(res);
};

const engine = (): Plugin => ({
  name: "magicmobile-engine",
  configureServer(server) { server.middlewares.use("/engine", serveEngine); },
  configurePreviewServer(server) { server.middlewares.use("/engine", serveEngine); },
});

/**
 * Deck-link APIs through this origin, as the hosted site's rewrites do (scripts/stage_vercel.mjs): neither site lets a
 * browser on another origin read them.
 */
const providers = {
  "/provider/archidekt": { target: "https://archidekt.com", changeOrigin: true, rewrite: (path: string) => path.replace(/^\/provider\/archidekt\/decks\/(\d+)\/?$/, "/api/decks/$1/") },
  "/sb": { target: "https://pbspondpyvrjcnvwhtim.supabase.co", changeOrigin: true, rewrite: (path: string) => path.replace(/^\/sb/, "") },
  "/provider/moxfield": { target: "https://api2.moxfield.com", changeOrigin: true, rewrite: (path: string) => path.replace(/^\/provider\/moxfield/, "") },
};

export default defineConfig({
  plugins: [react(), engine()],
  server: { headers: isolation, proxy: providers },
  preview: { headers: isolation, proxy: providers },
  // The engine worker must be classic: the Web Image wrapper is loaded with importScripts().
  worker: { format: "iife" },
  test: { include: ["test/**/*.test.ts"], environment: "node" },
});
