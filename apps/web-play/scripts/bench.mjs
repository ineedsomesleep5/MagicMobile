#!/usr/bin/env node
// Headless benchmark of the Web Image engine (docs/WEB_ENGINE_M1.md). Chrome: the installed Google Chrome
// (playwright-core, channel "chrome"; no browser download). --browser firefox|webkit uses Playwright's own builds,
// when installed (npx playwright-core install firefox webkit). Writes a metrics JSON.
//
//   node scripts/bench.mjs --ready-visits 2                     # cold + cached engine boot only
//   node scripts/bench.mjs --ready-visits 1 --games 2p:1,4p:2   # warm the cache, then play
//
// Options: --games <list> --cap <s per game> --skill <n> --ready-visits <n> --out <file>
//          --timeout <s overall> --engine-dir <bundle dir> --browser chromium|firefox|webkit
// It is a heavy workload: run it behind the machine-wide lock, in holds under ~30 minutes.
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, firefox, webkit } from "playwright-core";
import { startServer } from "./serve.mjs";

const here = fileURLToPath(new URL(".", import.meta.url));
const arg = (name, fallback) => {
  const i = process.argv.indexOf("--" + name);
  return i > 0 ? process.argv[i + 1] : fallback;
};
const games = arg("games", "");
const capS = Number(arg("cap", "600"));
const skill = arg("skill", null);
const readyVisits = Number(arg("ready-visits", "1"));
const engineDir = arg("engine-dir", null);
const browserName = arg("browser", "chromium");
const out = resolve(arg("out", resolve(here, "../../../packages/web-engine/build/metrics/bench.json")));
const gameCount = games ? games.split(",").length : 0;
const overallS = Number(arg("timeout", String(600 + gameCount * (capS + 120))));

/** Resident memory of the browser's process tree, sampled with ps (renderer = the tab + its worker). */
function sampleMemory(rootPid) {
  const rows = execFileSync("ps", ["-A", "-o", "pid=,ppid=,rss=,command="], { encoding: "utf8", maxBuffer: 16 << 20 })
    .split("\n")
    .map((line) => /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/.exec(line))
    .filter(Boolean)
    .map((m) => ({ pid: Number(m[1]), ppid: Number(m[2]), rss: Number(m[3]) * 1024, command: m[4] }));
  const tree = new Set([rootPid]);
  for (let grew = true; grew; ) {
    grew = false;
    for (const row of rows) if (!tree.has(row.pid) && tree.has(row.ppid)) (tree.add(row.pid), (grew = true));
  }
  const members = rows.filter((row) => tree.has(row.pid) && row.pid !== rootPid && row.command.includes("Chrome"));
  const renderers = members.filter((row) => row.command.includes("--type=renderer"));
  return {
    totalBytes: members.reduce((sum, row) => sum + row.rss, 0),
    maxRendererBytes: Math.max(0, ...renderers.map((row) => row.rss)),
  };
}

const { server, stats: served, reset, url } = await startServer({ port: 0, ...(engineDir ? { engine: resolve(engineDir) } : {}) });
// A fresh on-disk profile per run: the first visit is cold, later visits use the browser's disk cache and, in
// Chrome, V8's cache of the compiled Wasm (an in-memory incognito cache is too small for the engine).
const profile = mkdtempSync(join(tmpdir(), "web-play-bench-"));
const launcher = { chromium, firefox, webkit }[browserName];
if (!launcher) throw new Error("Unknown --browser " + browserName);
const context = await launcher.launchPersistentContext(profile, browserName === "chromium" ? { channel: "chrome", headless: true } : { headless: true });
const browser = context.browser();
// playwright-core launches Chrome as a child of this Node process; sample that subtree.
const browserPid = process.pid;
const report = {
  runtime: "graalvm-web-image",
  browser: `${browserName === "chromium" ? "Google Chrome" : browserName} ${browser?.version() ?? "?"} (headless, playwright-core, fresh on-disk profile)`,
  machine: "8 GB MacBook, shared with other workloads (numbers are from this machine only)",
  startedAt: new Date().toISOString(),
  params: { games, capS, skill, readyVisits, engineDir, browser: browserName },
  visits: [],
};
const deadline = Date.now() + overallS * 1000;

async function visit(kind, gameList) {
  reset();
  const page = await context.newPage();
  const consoleLines = [];
  const keep = (line) => consoleLines.length < 600 && consoleLines.push(line.slice(0, 800));
  page.on("console", (message) => keep(`[${message.type()}] ${message.text()}`));
  page.on("pageerror", (error) => consoleLines.push("[pageerror] " + String(error).slice(0, 500)));
  const query = new URLSearchParams({ games: gameList, cap: String(capS) });
  if (skill) query.set("skill", skill);
  const memory = { maxRendererBytes: 0, maxTotalBytes: 0, samples: 0 };
  const sampler = setInterval(() => {
    if (!browserPid || browserName !== "chromium") return;
    try {
      const m = sampleMemory(browserPid);
      memory.maxRendererBytes = Math.max(memory.maxRendererBytes, m.maxRendererBytes);
      memory.maxTotalBytes = Math.max(memory.maxTotalBytes, m.totalBytes);
      memory.samples++;
    } catch {
      /* ps unavailable for one tick */
    }
  }, 1000);
  const started = Date.now();
  await page.goto(`${url}/bench.html?${query}`);
  let state;
  let lastStatus = "";
  while (true) {
    state = await page.evaluate(() => {
      const b = window.__bench;
      return { status: b?.status, ready: !!b?.ready, games: b?.games?.length ?? 0, text: document.getElementById("status")?.textContent ?? "" };
    });
    if (state.text !== lastStatus) {
      lastStatus = state.text;
      console.log(`[${kind} +${((Date.now() - started) / 1000).toFixed(0)}s] ${state.text}`);
    }
    const doneWaiting = state.status === "done";
    if (doneWaiting || state.status === "error" || Date.now() > deadline) break;
    await new Promise((r) => setTimeout(r, 1000));
  }
  clearInterval(sampler);
  const bench = await page.evaluate(() => window.__bench);
  await page.close();
  const entry = {
    kind,
    wallMs: Date.now() - started,
    timedOut: Date.now() > deadline,
    served: JSON.parse(JSON.stringify({ requests: served.requests, bytes: served.bytes, engineBytes: served.engineBytes })),
    memory,
    bench,
    console: consoleLines,
  };
  report.visits.push(entry);
  const r = bench?.ready;
  console.log(
    `[${kind}] status=${bench?.status} engineReady=${r ? (r.engineReadyMs / 1000).toFixed(1) + "s" : "n/a"}` +
      ` servedEngineMB=${(served.engineBytes / 1e6).toFixed(1)}` +
      ` maxRendererMB=${(memory.maxRendererBytes / 1e6).toFixed(0)}${bench?.error ? " error=" + bench.error.slice(0, 300) : ""}`,
  );
  return entry;
}

try {
  for (let i = 0; i < readyVisits; i++) await visit(i === 0 ? "cold-ready" : "cached-ready", "");
  if (games) await visit(readyVisits > 0 ? "cached-games" : "cold-games", games);
} finally {
  report.finishedAt = new Date().toISOString();
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, JSON.stringify(report, null, 2) + "\n");
  console.log("wrote " + out);
  await context.close().catch(() => {});
  rmSync(profile, { recursive: true, force: true }); // this run's own temporary Chrome profile
  server.close();
}
