#!/usr/bin/env node
// Same driver and plan as bench.html, against the engine on HotSpot over stdin/stdout, so browser numbers have a
// same-machine reference. Default: the phone engine's threading (EngineCli, packages/ondevice-engine build).
// --web: the web threading mode (WebJvmMain, packages/web-engine build/web-jvm): one engine thread, inline AI
// searches, the same Java sources the Web Image build compiles. It exits with status 3 if the engine starts a thread.
// Usage: node scripts/jvm-baseline.mjs [--web] [--games 2p:1,4p:2] [--cap 600] [--heap 1g] [--skill n] [--out file.json]
//        [--agent <dir>]  (GraalVM's java: record native-image reachability metadata into <dir>)
import { spawn } from "node:child_process";
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { EngineClient } from "../src/engineClient.ts";
import { playGame } from "../src/autoplay.ts";
import { gameSpec, parseGames, summarize } from "../src/plan.ts";

const here = fileURLToPath(new URL(".", import.meta.url));
const build = resolve(here, "../../../packages/web-engine/build");
const arg = (name, fallback) => {
  const i = process.argv.indexOf("--" + name);
  return i > 0 ? process.argv[i + 1] : fallback;
};
const web = process.argv.includes("--web");
const agent = arg("agent", null);
const skill = arg("skill", null);
const games = parseGames(arg("games", "2p:1,4p:2"));
const capMs = Number(arg("cap", "600")) * 1000;
const heap = arg("heap", "1g");
const out = resolve(arg("out", join(build, `metrics/jvm-${web ? "web" : "phone"}.json`)));
const java = (process.env.JAVA_HOME ?? "/opt/homebrew/opt/openjdk@17") + "/bin/java";
const classpathFile = web ? join(build, "web-jvm/runtime-classpath.txt") : resolve(here, "../../../packages/ondevice-engine/build/runtime-classpath.txt");
const mainClass = web ? "io.magicmobile.web.WebJvmMain" : "io.magicmobile.xmage.EngineCli";
const stderrLines = [];

class JvmTransport {
  constructor() {
    const cp = readFileSync(classpathFile, "utf8").trim();
    const agentArgs = agent ? [`-agentlib:native-image-agent=config-merge-dir=${agent}`] : [];
    this.proc = spawn(java, [...agentArgs, `-Xmx${heap}`, "-Djava.awt.headless=true", ...(process.env.MM_WEB_TRACE ? ["-Dmagicmobile.webTrace=true"] : []), "-cp", cp, mainClass], {
      stdio: ["pipe", "pipe", "pipe"],
    });
    createInterface({ input: this.proc.stderr }).on("line", (line) => {
      stderrLines.push(line);
      if (stderrLines.length > 2000) stderrLines.shift();
      if (line.startsWith("FATAL")) console.error(line);
    });
    this.waiters = [];
    createInterface({ input: this.proc.stdout }).on("line", (line) => {
      let reply;
      try {
        reply = JSON.parse(line);
      } catch {
        return; // not a protocol line
      }
      if (reply && reply.protocol === 1 && "ok" in reply) this.waiters.shift()?.resolve(line);
    });
    this.proc.on("exit", (code) => {
      this.exitCode = code;
      this.waiters.splice(0).forEach((w) => w.reject(new Error(`JVM exited (${code})`)));
    });
  }
  request(json) {
    return new Promise((resolve, reject) => {
      this.waiters.push({ resolve, reject });
      this.proc.stdin.write(json + "\n");
    });
  }
  close() {
    this.proc.stdin.end();
    setTimeout(() => this.proc.kill("SIGKILL"), 3000).unref();
  }
}

const deckDir = join(build, "decks");
const decks = readdirSync(deckDir)
  .filter((f) => f.endsWith(".json"))
  .map((f) => ({ id: f.replace(/\.json$/, ""), deck: JSON.parse(readFileSync(join(deckDir, f), "utf8")) }));

const t0 = performance.now();
const transport = new JvmTransport();
const client = new EngineClient(transport);
const capabilities = await client.capabilities();
const engineReadyMs = performance.now() - t0;
console.log(`JVM engine ready in ${(engineReadyMs / 1000).toFixed(1)} s (${capabilities.execution})`);
const results = [];
for (const game of games) {
  let traced = 0;
  const trace = process.argv.includes("--trace")
    ? (prompt, answer, snapshot) => {
        if (traced++ < 200) console.log(JSON.stringify({ turn: snapshot.gameView.turn, step: snapshot.gameView.step, kind: prompt.kind, message: prompt.payload.message, mode: prompt.payload.selectMode, types: prompt.responseTypes, options: prompt.payload.options, canPlay: prompt.kind === "SELECT" ? snapshot.gameView.canPlayObjects : undefined, hand: Object.values(snapshot.gameView.myHand ?? {}).map((c) => c.name + ":" + c.id.slice(0, 8)), bf: snapshot.gameView.players.map((p) => Object.values(p.battlefield).map((c) => c.name)), answer }));
      }
    : undefined;
  const result = await playGame(client, gameSpec(game, decks, capMs, skill === null ? undefined : Number(skill)), (text) => process.stdout.write(`\r${text}          `), trace);
  if (result.result !== "ended") result.engineTrace = stderrLines.slice(-200); // with MM_WEB_TRACE=1: the requests served before it
  results.push(result);
  console.log(`\n${result.label}: ${result.result} winner=${result.winner} turns=${result.turns} wall=${(result.wallMs / 1000).toFixed(1)}s start=${result.firstPromptMs?.toFixed(0)}ms ${result.failure ?? ""}`);
}
transport.close();
await new Promise((r) => setTimeout(r, 500));
const report = {
  runtime: web ? "hotspot-jvm, web threading mode (WebJvmMain)" : "hotspot-jvm, phone threading (EngineCli)",
  exitCode: transport.exitCode ?? null,
  stderrTail: stderrLines.slice(-40),
  java,
  heap,
  machine: "8 GB MacBook (shared with other workloads)",
  engineReadyMs,
  capabilities,
  summary: summarize(results),
  games: results,
};
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report.summary, null, 2));
console.log("wrote " + out);
