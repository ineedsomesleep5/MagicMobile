// bench.html: boot the Web Image engine worker, play scripted games, show timings (docs/WEB_ENGINE_M1.md).
// URL parameters:
//   games=2p:1,4p:2   players:seed list (seat 0 scripted human, the rest XMage AI); empty: boot only
//   cap=600           per-game wall-time cap in seconds
//   skill=1           XMage AI skill (default: engine default)
//   engine=/engine/   same-origin path of packages/web-engine/build/web
import { EngineClient, WorkerTransport, type JsonObject } from "./engineClient.ts";
import { failedToStart, playGame, stats, type GameResult } from "./autoplay.ts";
import { gameSpec, parseGames, summarize, TARGETS } from "./plan.ts";
import type { BootTimings } from "./protocol.ts";

type Manifest = { upstream: string; catalogueHash: string; engineBuild: string; wasm: { bytes: number; gzip9Bytes: number }; decks: string[] };
type MemorySample = { at: number; bytes: number };

type BenchState = {
  status: "loading" | "running" | "done" | "error";
  error?: string;
  startedAt: number;
  userAgent: string;
  manifest?: Manifest;
  ready?: {
    boot: BootTimings;
    capabilitiesMs: number; // first request: constructs XmageEngine and its registries
    engineReadyMs: number; // script start -> capabilities answered
    engineReadyFromNavigationMs: number;
    capabilities: JsonObject;
    wasmTransfer?: { transferSize: number; encodedBodySize: number; decodedBodySize: number; durationMs: number };
  };
  games: GameResult[];
  summary?: ReturnType<typeof summarize>;
  longTasks: { start: number; duration: number }[];
  memory: MemorySample[]; // performance.measureUserAgentSpecificMemory (page + its workers), when available; resolves late
  engineLogs?: string[];
};

const params = new URLSearchParams(location.search);
const engineBase = params.get("engine") ?? "/engine/";
const games = parseGames(params.get("games") ?? "");
const capMs = Number(params.get("cap") ?? 600) * 1000;
const aiSkill = params.has("skill") ? Number(params.get("skill")) : undefined;

const bench: BenchState = { status: "loading", startedAt: performance.now(), userAgent: navigator.userAgent, games: [], longTasks: [], memory: [] };
(window as unknown as { __bench: BenchState }).__bench = bench;

try {
  new PerformanceObserver((list) => {
    for (const entry of list.getEntries()) bench.longTasks.push({ start: entry.startTime, duration: entry.duration });
  }).observe({ type: "longtask", buffered: true });
} catch {
  /* longtask timing unsupported */
}

type MemoryApi = { measureUserAgentSpecificMemory?: () => Promise<{ bytes: number }> };
let measuring = false;
async function sampleMemory() {
  const api = performance as unknown as MemoryApi;
  if (!api.measureUserAgentSpecificMemory || measuring) return;
  measuring = true;
  try {
    const result = await api.measureUserAgentSpecificMemory();
    bench.memory.push({ at: performance.now(), bytes: result.bytes });
  } catch {
    /* not available here (needs cross-origin isolation; Chromium only) */
  } finally {
    measuring = false;
  }
}

const $ = (id: string) => document.getElementById(id) as HTMLElement;
const seconds = (ms: number | null | undefined) => (ms === null || ms === undefined ? "–" : (ms / 1000).toFixed(ms < 10_000 ? 2 : 1) + " s");
const verdict = (value: number | null | undefined, limit: number) =>
  value === null || value === undefined ? "" : value <= limit ? ' class="ok"' : ' class="bad"';
const status = (text: string) => {
  $("status").textContent = text;
  document.title = "MM bench: " + text.slice(0, 120); // readable without page scripting (Safari via AppleScript)
};

function renderReady() {
  const r = bench.ready;
  if (!r) return;
  const m = bench.manifest;
  $("ready").innerHTML = `
    <tr><th>Engine boot</th><th>ms</th></tr>
    <tr><td>Engine script (engine.js)</td><td>${r.boot.scriptMs.toFixed(0)}</td></tr>
    <tr><td>Fetch + compile + instantiate (${m ? (m.wasm.bytes / 1e6).toFixed(0) + " MB Wasm" : "Wasm"})</td><td>${r.boot.fetchAndCompileMs.toFixed(0)}</td></tr>
    <tr><td>Java main until ready for requests</td><td>${r.boot.mainToFirstTakeMs.toFixed(0)}</td></tr>
    <tr><td>First request: XmageEngine and its registries</td><td>${r.capabilitiesMs.toFixed(0)}</td></tr>
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
  const peak = Math.max(0, ...bench.memory.map((m) => m.bytes));
  $("summary").innerHTML = `
    <tr><th>Across games</th><th>Value</th></tr>
    <tr><td>Finished / total</td><td${s.finished === s.games ? ' class="ok"' : ' class="bad"'}>${s.finished} / ${s.games} (timeouts ${s.timeouts}, stalled ${s.stalled}, failed ${s.failed})</td></tr>
    <tr><td>Board update median / p95 (≤ 1 s / ≤ 3 s)</td><td>${seconds(s.boardUpdateMs.median)} / ${seconds(s.boardUpdateMs.p95)}</td></tr>
    <tr><td>AI turn median / p95 (≤ 5 s / ≤ 15 s)</td><td>${seconds(s.aiTurnMs.median)} / ${seconds(s.aiTurnMs.p95)}</td></tr>
    <tr><td>Poll call median / p95</td><td>${seconds(s.pollMs.median)} / ${seconds(s.pollMs.p95)}</td></tr>
    <tr><td>Peak page + worker memory (≤ 2 GB)</td><td${verdict(peak || null, TARGETS.tabMemoryBytes)}>${peak ? (peak / 1e9).toFixed(2) + " GB" : "n/a"}</td></tr>
    <tr><td>Longest main-thread task (≤ 100 ms)</td><td${verdict(longest, TARGETS.mainThreadLongTaskMs)}>${longest.toFixed(0)} ms</td></tr>`;
}

async function main() {
  const manifest = (await (await fetch(engineBase + "manifest.json", { cache: "no-cache" })).json()) as Manifest;
  bench.manifest = manifest;
  status(`Loading the engine (${(manifest.wasm.bytes / 1e6).toFixed(0)} MB Wasm)…`);
  const memoryTimer = setInterval(sampleMemory, 5000);
  const { transport, timings } = await WorkerTransport.start({
    engineUrl: new URL(engineBase + "engine.js", location.href).href,
    wasmUrl: new URL(engineBase + "engine.js.wasm", location.href).href,
  });
  const client = new EngineClient(transport);
  status("Engine started; constructing XmageEngine…");
  const capStart = performance.now();
  const capabilities = await client.capabilities();
  const readyAt = performance.now();
  const wasmEntry = performance.getEntriesByType("resource").find((e) => e.name.endsWith("engine.js.wasm")) as PerformanceResourceTiming | undefined;
  bench.ready = {
    boot: timings,
    capabilitiesMs: readyAt - capStart,
    engineReadyMs: readyAt - bench.startedAt,
    engineReadyFromNavigationMs: readyAt,
    capabilities,
    wasmTransfer: wasmEntry && { transferSize: wasmEntry.transferSize, encodedBodySize: wasmEntry.encodedBodySize, decodedBodySize: wasmEntry.decodedBodySize, durationMs: wasmEntry.duration },
  };
  renderReady();
  void sampleMemory(); // Chrome may answer only at its next GC (a minute when idle): never wait for it
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
      result = failedToStart(spec, error);
    }
    bench.games.push(result);
    bench.summary = summarize(bench.games);
    renderGames();
    renderSummary();
  }
  clearInterval(memoryTimer);
  bench.engineLogs = transport.logs;
  renderSummary();
  bench.status = "done";
  status(games.length ? `Done: ${bench.summary?.finished ?? 0}/${games.length} games finished.` : "Engine ready.");
}

main().catch((error: unknown) => {
  bench.status = "error";
  bench.error = String((error as Error)?.stack ?? error);
  status("Error: " + bench.error);
});
