/** ranked-cases.json's brackets, effective and choices rows (iOS RankedParityTests.testBrackets, Android RankedParityTest.kt). */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { bracketReasons, BracketRules, CommanderBracket, DeckBracketPreference } from "../src/core/brackets";

const root = join(__dirname, "..", "..", "..");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity/ranked-cases.json"), "utf8"));
const rules = new BracketRules(JSON.parse(readFileSync(join(root, "apps/ios/MagicMobile/Resources/commander-brackets.json"), "utf8")));

describe("Commander brackets", () => {
  it("names, titles and clamping", () => {
    expect(CommanderBracket.all.map(CommanderBracket.name)).toEqual(["Exhibition", "Core", "Upgraded", "Optimized", "cEDH"]);
    expect(CommanderBracket.title(3)).toBe("Bracket 3 · Upgraded");
    expect(CommanderBracket.blurb(2)).toBe("Like a modern precon. No Game Changers, no fast combos.");
    expect([-3, 0, 1, 4, 5, 9].map(CommanderBracket.clamping)).toEqual([1, 1, 1, 4, 5, 5]);
    expect(CommanderBracket.from(6)).toBeUndefined();
  });

  it("evaluates lists as ranked-cases.json says", () => {
    expect(rules.gameChangers.size).toBe(53); // the February 2026 list
    for (const item of cases.brackets) {
      const report = rules.evaluate(item.cards);
      expect(report.minimum, item.name).toBe(item.minimum);
      expect(report.gameChangers, item.name).toEqual(item.gameChangers);
      expect(report.massLandDenial, item.name).toEqual(item.massLandDenial);
      expect(report.extraTurns, item.name).toEqual(item.extraTurns);
      expect(report.combos.length, item.name).toBe(item.combos);
      expect(report.earlyCombos.length, item.name).toBe(item.earlyCombos);
    }
  });

  it("matches a double-faced card by its front face and explains the bracket", () => {
    const local = new BracketRules({ gameChangers: ["Front"], massLandDenial: [], extraTurns: [], combos: [], chainedExtraTurns: 3 });
    const report = local.evaluate(["Front // Back", "Forest"]);
    expect(report.minimum).toBe(3);
    expect(report.gameChangers).toEqual(["Front"]);
    expect(bracketReasons(report)).toEqual(["1 Game Changers: Front"]);
    expect(BracketRules.empty.evaluate(["Sol Ring"]).minimum).toBe(2);
    expect(local.evaluateDeck({ id: "d", name: "d", entries: [
      { name: "Front", quantity: 1, section: "commanders" }, { name: "Front", quantity: 1, section: "sideboard" }] }).minimum).toBe(3);
    expect(local.evaluateDeck({ id: "d", name: "d", entries: [{ name: "Front", quantity: 1, section: "sideboard" }] }).minimum).toBe(2);
  });

  it("the player's declared bracket", () => {
    for (const item of cases.effective) {
      expect(DeckBracketPreference.effective(item.minimum, item.declared ?? undefined), JSON.stringify(item)).toBe(item.effective);
    }
    for (const item of cases.choices) expect(DeckBracketPreference.choices(item.minimum)).toEqual(item.choices);
    const map = new Map<string, string>();
    const store = { get: (k: string) => map.get(k), set: (k: string, v: string) => { map.set(k, v); } };
    expect(DeckBracketPreference.declared("deck", store)).toBeUndefined();
    DeckBracketPreference.setDeclared(1, "deck", store);
    expect(DeckBracketPreference.declared("deck", store)).toBe(1);
    DeckBracketPreference.setDeclared(undefined, "deck", store);
    expect(DeckBracketPreference.declared("deck", store)).toBeUndefined();
    map.set(DeckBracketPreference.key, "not json");
    expect(DeckBracketPreference.declared("deck", store)).toBeUndefined();
  });
});
