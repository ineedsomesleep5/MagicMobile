#!/usr/bin/env node
// SPIKE ONLY. Same driver and plan as bench.html, against the same compiled engine on HotSpot
// (EngineCli over stdin/stdout), so CheerpJ numbers have a same-machine reference.
// Usage: node scripts/jvm-baseline.mjs [--games 2p:1,4p:2] [--cap 600] [--heap 1g] [--out file.json]
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
const games = parseGames(arg("games", "2p:1,4p:2"));
const capMs = Number(arg("cap", "600")) * 1000;
const heap = arg("heap", "1g");
const out = resolve(arg("out", join(build, "metrics/jvm-baseline.json")));
const java = (process.env.JAVA_HOME ?? "/opt/homebrew/opt/openjdk@17") + "/bin/java";

class JvmTransport {
  constructor() {
    const cp = readFileSync(join(build, "runtime-classpath.txt"), "utf8").trim();
    this.proc = spawn(java, [`-Xmx${heap}`, "-Djava.awt.headless=true", "-cp", cp, "io.magicmobile.xmage.EngineCli"], {
      stdio: ["pipe", "pipe", "ignore"],
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
    this.proc.on("exit", () => this.waiters.splice(0).forEach((w) => w.reject(new Error("JVM exited"))));
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

const decks = readdirSync(join(build, "web/decks"))
  .filter((f) => f.endsWith(".json"))
  .map((f) => ({ id: f.replace(/\.json$/, ""), deck: JSON.parse(readFileSync(join(build, "web/decks", f), "utf8")) }));

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
  const result = await playGame(client, gameSpec(game, decks, capMs), (text) => process.stdout.write(`\r${text}          `), trace);
  results.push(result);
  console.log(`\n${result.label}: ${result.result} winner=${result.winner} turns=${result.turns} wall=${(result.wallMs / 1000).toFixed(1)}s start=${result.firstPromptMs?.toFixed(0)}ms ${result.failure ?? ""}`);
}
transport.close();
const report = {
  spike: true,
  runtime: "hotspot-jvm",
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
