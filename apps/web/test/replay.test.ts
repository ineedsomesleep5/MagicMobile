/**
 * Recorded games replayed through the web's logic and checked against iOS (docs/WEB_PARITY.md "replay"). Each fixture in
 * parity/replay holds the raw engine polls a web seat applied in a real game against the AI (apps/web/scripts/play.mjs
 * --polls), as raw-DEFLATE JSON to keep the repository small. For every poll: the prompt, smart pass's decision with the default settings, Auto Pay's next step, and the
 * board events since the previous poll. ParityGoldenTests.testWebReplaysMatchGoldens writes the same trace from the iOS
 * code into parity/golden/replay-<name>; the two must be equal. A difference is written to test/replay-differences/
 * for review.
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { inflateRawSync } from "node:zlib";
import { describe, expect, it } from "vitest";
import { replayTrace } from "./replayTrace";

const parity = join(__dirname, "..", "..", "android", "core", "src", "test", "resources", "parity");
const replays = join(parity, "replay");

describe("recorded games replay as on iOS", () => {
  const names = existsSync(replays) ? readdirSync(replays).filter((n) => n.endsWith(".deflate")).sort() : [];
  it("has recorded games", () => expect(names.length).toBeGreaterThan(0));
  for (const name of names) {
    it(name, () => {
      const fixture = JSON.parse(inflateRawSync(readFileSync(join(replays, name))).toString("utf8")) as { polls: unknown[] };
      const web = replayTrace(fixture.polls);
      const golden = JSON.parse(readFileSync(join(parity, "golden", `replay-${name.replace(/\.deflate$/, ".json")}`), "utf8")) as { trace: Record<string, unknown>[] };
      // Key order differs (the golden's keys are sorted); the values must not.
      const canonical = (value: unknown): string => JSON.stringify(value, (_, v) => (v && typeof v === "object" && !Array.isArray(v)
        ? Object.fromEntries(Object.entries(v as Record<string, unknown>).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) : v));
      const differences = web.flatMap((entry, i) => (canonical(entry) === canonical(golden.trace[i]) ? [] : [{ index: i, web: entry, ios: golden.trace[i] }]));
      if (web.length !== golden.trace.length) differences.push({ index: -1, web: { length: web.length }, ios: { length: golden.trace.length } });
      const out = join(__dirname, "replay-differences");
      if (differences.length > 0) { mkdirSync(out, { recursive: true }); writeFileSync(join(out, name), JSON.stringify(differences, null, 1)); }
      expect(differences, `see test/replay-differences/${name}`).toEqual([]);
    });
  }
});
