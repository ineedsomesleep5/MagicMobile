/** The Arena game log: the iOS log reader's goldens (text-cases.json), each line's kind and icon, and combat reasons (combat-cases.json). */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { CombatKeyword } from "../src/core/boardEvents";
import { arenaLogLine, CombatLogReasons, damageStep, type Fighter, GameLogPresentation } from "../src/core/gameLog";

const parity = join(__dirname, "..", "..", "android", "core", "src", "test", "resources", "parity");
const read = (name: string) => JSON.parse(readFileSync(join(parity, name), "utf8"));

describe("game log", () => {
  it("reads every shared log message as iOS does", () => {
    const messages: string[] = read("text-cases.json").log;
    const golden = read("golden/text-cases.json").log;
    expect(messages.map((message) => {
      const presentation = new GameLogPresentation(message);
      return { plain: presentation.plainText, spans: presentation.spans.map((span) => ({
        bold: span.bold, card: span.card?.name ?? null, italic: span.italic, role: span.role, text: span.text,
      })) };
    })).toEqual(golden);
  });

  it("gives each line its kind and icon", () => {
    const line = (message: string, id = "e") => arenaLogLine({ id, message });
    expect(line("TURN 3 for <font color='#20B2AA'>AI 1</font> (40 - 38)").kind).toBe("turn");
    expect(line("Passed priority", "local:auto-pass:4").kind).toBe("autoPass");
    expect(line("<font color='#20B2AA'>Caleb</font> casts <font color='#FF6347' object_id='5c1e0000-0000-4000-8000-0000000000c3'>Lightning Bolt</font> [5c1]").icon).toBe("cast");
    expect(line("<font color='#696969'>Typhoid Rats</font> died").icon).toBe("died");
    expect(line("AI 1 gains 3 life").icon).toBe("heal");
    expect(line("Caleb draws a card").icon).toBe("draw");
    expect(line("Something else").icon).toBe("dot");
  });

  it("gives combat damage and deaths their one-line reasons", () => {
    const log = read("combat-cases.json").log;
    const fighters = new Map<string, Fighter>(Object.entries(log.fighters as Record<string, { name: string; keywords: CombatKeyword[] }>)
      .map(([id, fighter]) => [id.toLowerCase(), { name: fighter.name, keywords: new Set(fighter.keywords) }]));
    for (const item of log.cases) {
      expect(CombatLogReasons.reason(item.message, damageStep(item.previous ?? undefined, item.step), fighters), item.name).toBe(item.reason ?? undefined);
    }
  });
});
