// SPIKE ONLY. bench.html: boot the CheerpJ engine worker, play scripted games, show timings.
// URL parameters:
//   games=2p:1,4p:2   players:seed list (seat 0 scripted human, the rest XMage AI)
//   cap=600           per-game wall-time cap in seconds
//   skill=1           XMage AI skill (default: engine default)
//   loader=<url>      CheerpJ loader (default: 4.3 from the CheerpJ CDN)
//   engine=/engine/   same-origin path of the bundle (build/web, or build/web-java11 via bench.mjs
//                     --engine-dir); its manifest's javaRelease picks the CheerpJ runtime
//   debug=1           Java stack traces of engine failures to the console
import { EngineClient, WorkerTransport, type JsonObject } from "./engineClient.ts";
import { failedToStart, playGame, stats, type GameResult } from "./autoplay.ts";
import { gameSpec, parseGames, summarize, TARGETS } from "./plan.ts";
import type { ReadyTimings, ResourceSummary } from "./protocol.ts";

type Manifest = { upstream: string; catalogueHash: string; javaRelease?: number; totalBytes: number; jars: { name: string; bytes: number }[]; decks: string[] };

type BenchState = {
  status: "loading" | "running" | "done" | "error";
  error?: string;
  startedAt: number; // performance.now() when this script started (ms since navigation)
  manifest?: Manifest;
  ready?: {
    workerReady: ReadyTimings;
    capabilitiesMs: number; // first Java request: constructs XmageEngine + the static set registry
    engineReadyMs: number; // script start -> capabilities answered
    engineReadyFromNavigationMs: number;
    capabilities: JsonObject;
    resourcesAtReady?: ResourceSummary;
  };
  games: GameResult[];
  summary?: ReturnType<typeof summarize>;
  longTasks: { start: number; duration: number }[];
  resourcesAtEnd?: ResourceSummary;
  unsafeBridgeCalls?: number;
};

const params = new URLSearchParams(location.search);
const loaderUrl = params.get("loader") ?? "https://cjrtnc.leaningtech.com/4.3/loader.js";
const engineBase = params.get("engine") ?? "/engine/";
const games = parseGames(params.get("games") ?? "2p:1,4p:2");
const capMs = Number(params.get("cap") ?? 600) * 1000;
const aiSkill = params.has("skill") ? Number(params.get("skill")) : undefined;
const javaProperties = params.get("debug") === "1" ? ["magicmobile.debug=true"] : [];

const bench: BenchState = { status: "loading", startedAt: performance.now(), games: [], longTasks: [] };
(window as unknown as { __bench: BenchState }).__bench = bench;

// Main-thread responsiveness: every long task (>50 ms) the page itself runs.
try {
  new PerformanceObserver((list) => {
    for (const entry of list.getEntries()) bench.longTasks.push({ start: entry.startTime, duration: entry.duration });
  }).observe({ type: "longtask", buffered: true });
} catch {
  /* longtask timing unsupported */
}

const $ = (id: string) => document.getElementById(id) as HTMLElement;
const seconds = (ms: number | null | undefined) => (ms === null || ms === undefined ? "–" : (ms / 1000).toFixed(ms < 10_000 ? 2 : 1) + " s");
const verdict = (value: number | null | undefined, limit: number) =>
  value === null || value === undefined ? "" : value <= limit ? ' class="ok"' : ' class="bad"';
const status = (text: string) => ($("status").textContent = text);

function renderReady() {
  const r = bench.ready;
  if (!r) return;
  const w = r.workerReady;
  $("ready").innerHTML = `
    <tr><th>Engine boot</th><th>ms</th></tr>
    <tr><td>CheerpJ loader script</td><td>${w.loaderMs.toFixed(0)}</td></tr>
    <tr><td>cheerpjInit (Java ${bench.manifest?.javaRelease ?? 17} runtime)</td><td>${w.cheerpjInitMs.toFixed(0)}</td></tr>
    <tr><td>cheerpjRunLibrary (${bench.manifest?.jars.length} jars)</td><td>${w.runLibraryMs.toFixed(0)}</td></tr>
    <tr><td>WebEntryPoints class</td><td>${w.entryClassMs.toFixed(0)}</td></tr>
    <tr><td>First request: XmageEngine + set registry</td><td>${r.capabilitiesMs.toFixed(0)}</td></tr>
    <tr><td><b>Engine ready</b> (target ≤ 45 s first visit, ≤ 10 s cached)</td><td${verdict(r.engineReadyMs, TARGETS.engineReadyFirstMs)}><b>${r.engineReadyMs.toFixed(0)}</b></td></tr>`;
}

function renderGames() {
  const rows = bench.games.map((g) => {
    const b = stats(g.boardUpdateMs);
    const a = stats(g.aiTurnMs);
    return `<tr><td>${g.label}</td><td>${g.deckIds.join(", ")}</td><td${g.result === "ended" ? ' class="ok"' : ' class="bad"'}>${g.result}${g.winner ? " (" + g.winner + ")" : ""}</td>
      <td${g.players === 4 ? verdict(g.firstPromptMs, TARGETS.fourPlayerStartMs) : ""}>${seconds(g.firstPromptMs)}</td><td>${g.turns}</td><td>${seconds(g.wallMs)}</td>
      <td${verdict(b.median, TARGETS.boardUpdateMedianMs)}>${seconds(b.median)}</td><td${verdict(b.p95, TARGETS.boardUpdateP95Ms)}>${seconds(b.p95)}</td>
      <td${verdict(a.median, TARGETS.aiTurnMedianMs)}>${seconds(a.median)}</td><td${verdict(a.p95, TARGETS.aiTurnP95Ms)}>${seconds(a.p95)}</td></tr>`;
  });
  $("games").innerHTML = `<tr><th>Game</th><th>Decks</th><th>Result</th><th>Start</th><th>Turns</th><th>Wall</th>
    <th>Board upd. median</th><th>p95</th><th>AI turn median</th><th>p95</th></tr>${rows.join("")}`;
}

function renderSummary() {
  const s = bench.summary;
  if (!s) return;
  const longest = Math.max(0, ...bench.longTasks.map((t) => t.duration));
  $("summary").innerHTML = `
    <tr><th>Across games</th><th>Value</th></tr>
    <tr><td>Finished / total</td><td${s.finished === s.games ? ' class="ok"' : ' class="bad"'}>${s.finished} / ${s.games} (timeouts ${s.timeouts}, stalled ${s.stalled}, failed ${s.failed})</td></tr>
    <tr><td>Board update median / p95 (≤ 1 s / ≤ 3 s)</td><td>${seconds(s.boardUpdateMs.median)} / ${seconds(s.boardUpdateMs.p95)}</td></tr>
    <tr><td>AI turn median / p95 (≤ 5 s / ≤ 15 s)</td><td>${seconds(s.aiTurnMs.median)} / ${seconds(s.aiTurnMs.p95)}</td></tr>
    <tr><td>Poll call median / p95</td><td>${seconds(s.pollMs.median)} / ${seconds(s.pollMs.p95)}</td></tr>
    <tr><td>Longest main-thread task (≤ 100 ms)</td><td${verdict(longest, TARGETS.mainThreadLongTaskMs)}>${longest.toFixed(0)} ms</td></tr>`;
}

async function main() {
  const manifest = (await (await fetch(engineBase + "manifest.json")).json()) as Manifest;
  bench.manifest = manifest;
  status(`Loading CheerpJ + ${manifest.jars.length} jars (${(manifest.totalBytes / 1e6).toFixed(0)} MB, fetched lazily)…`);
  const { transport, timings } = await WorkerTransport.start({ loaderUrl, jarBase: engineBase + "jars/", jars: manifest.jars.map((j) => j.name), javaProperties, javaVersion: manifest.javaRelease ?? 17 });
  const client = new EngineClient(transport);
  status("CheerpJ ready; constructing XmageEngine (set registry)…");
  const capStart = performance.now();
  const capabilities = await client.capabilities();
  const readyAt = performance.now();
  bench.ready = {
    workerReady: timings,
    capabilitiesMs: readyAt - capStart,
    engineReadyMs: readyAt - bench.startedAt,
    engineReadyFromNavigationMs: readyAt,
    capabilities,
    resourcesAtReady: await transport.resources(),
  };
  renderReady();
  const decks = await Promise.all(
    manifest.decks.map(async (id) => ({ id, deck: (await (await fetch(`${engineBase}decks/${id}.json`)).json()) as JsonObject })),
  );
  bench.status = "running";
  for (const game of games) {
    const spec = gameSpec(game, decks, capMs, aiSkill);
    status(`${spec.label}: creating match…`);
    let result: GameResult;
    try {
      result = await playGame(client, spec, (text) => status(text));
    } catch (error) {
      // create() itself failed, e.g. match_limit after a game whose engine thread never came back.
      result = failedToStart(spec, error);
    }
    bench.games.push(result);
    bench.unsafeBridgeCalls = transport.unsafeBridgeCalls;
    bench.summary = summarize(bench.games);
    renderGames();
    renderSummary();
  }
  bench.resourcesAtEnd = await transport.resources();
  bench.status = "done";
  status(`Done: ${bench.summary?.finished ?? 0}/${games.length} games finished.`);
}

main().catch((error: unknown) => {
  bench.status = "error";
  bench.error = String((error as Error)?.stack ?? error);
  status("Error: " + bench.error);
});
