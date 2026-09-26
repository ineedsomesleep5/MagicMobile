#!/usr/bin/env node
// SPIKE ONLY. Local static server for the bench: byte-range requests, no compression.
// CheerpJ reads jars lazily with HTTP Range requests, so gzip/brotli must stay off.
//   /            -> apps/web-play/dist (vite build output)
//   /engine/...  -> packages/web-engine/build/web (jars, manifest.json, decks/)
import { createServer } from "node:http";
import { createReadStream, statSync } from "node:fs";
import { extname, join, normalize, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
export const DIST = resolve(here, "../dist");
export const ENGINE = resolve(here, "../../../packages/web-engine/build/web");

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".jar": "application/java-archive",
  ".svg": "image/svg+xml",
};

export function startServer({ port = 5178, host = "127.0.0.1", dist = DIST, engine = ENGINE, log = false } = {}) {
  const stats = { requests: 0, rangeRequests: 0, bytes: 0, jarBytes: 0, byPath: {} };
  const server = createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://local");
    let path = decodeURIComponent(url.pathname);
    const [root, rel] = path.startsWith("/engine/") ? [engine, path.slice("/engine/".length)] : [dist, path.slice(1) || "bench.html"];
    const file = normalize(join(root, rel));
    if (file !== root && !file.startsWith(root + sep)) {
      res.writeHead(403).end();
      return;
    }
    let info;
    try {
      info = statSync(file);
      if (!info.isFile()) throw new Error("not a file");
    } catch {
      res.writeHead(404).end();
      return;
    }
    const headers = {
      "Content-Type": TYPES[extname(file)] ?? "application/octet-stream",
      "Accept-Ranges": "bytes",
      // Jars behave like immutable CDN assets (a real host would content-hash their names);
      // everything else revalidates with its ETag.
      "Cache-Control": file.endsWith(".jar") ? "public, max-age=86400" : "no-cache",
      ETag: `"${info.size}-${info.mtimeMs}"`,
      "Last-Modified": info.mtime.toUTCString(),
      "Access-Control-Allow-Origin": "*",
    };
    stats.requests++;
    if (req.headers["if-none-match"] === headers.ETag) {
      res.writeHead(304, headers).end();
      return;
    }
    let start = 0;
    let end = info.size - 1;
    let status = 200;
    const range = req.headers.range;
    if (range) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(range);
      if (!match || (match[1] === "" && match[2] === "")) {
        res.writeHead(416, { "Content-Range": `bytes */${info.size}` }).end();
        return;
      }
      if (match[1] === "") {
        start = Math.max(0, info.size - Number(match[2]));
      } else {
        start = Number(match[1]);
        if (match[2] !== "") end = Math.min(end, Number(match[2]));
      }
      if (start > end || start >= info.size) {
        res.writeHead(416, { "Content-Range": `bytes */${info.size}` }).end();
        return;
      }
      status = 206;
      headers["Content-Range"] = `bytes ${start}-${end}/${info.size}`;
      stats.rangeRequests++;
    }
    const length = end - start + 1;
    headers["Content-Length"] = String(length);
    stats.bytes += req.method === "HEAD" ? 0 : length;
    if (file.endsWith(".jar") && req.method !== "HEAD") stats.jarBytes += length;
    const entry = (stats.byPath[path] ??= { requests: 0, bytes: 0 });
    entry.requests++;
    entry.bytes += req.method === "HEAD" ? 0 : length;
    if (log) console.log(`${req.method} ${path} ${status} ${range ?? ""} ${length}`);
    res.writeHead(status, headers);
    if (req.method === "HEAD") res.end();
    else createReadStream(file, { start, end }).pipe(res);
  });
  return new Promise((resolveStart) => {
    server.listen(port, host, () => {
      const reset = () => Object.assign(stats, { requests: 0, rangeRequests: 0, bytes: 0, jarBytes: 0, byPath: {} });
      resolveStart({ server, stats, reset, url: `http://${host}:${server.address().port}` });
    });
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT ?? 5178);
  const { url } = await startServer({ port, log: process.env.LOG === "1" });
  console.log(`web-play spike: ${url}/bench.html  (engine from ${ENGINE})`);
}
