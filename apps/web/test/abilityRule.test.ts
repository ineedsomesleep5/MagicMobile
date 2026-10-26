/** parity/ability-rule-cases.json: the full rule a trigger or ability choice shows (OnDevicePromptAdapterTests.swift). */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { EngineDisplayText } from "../src/core/displayText";

const cases = JSON.parse(readFileSync(join(__dirname, "..", "..", "android/core/src/test/resources/parity/ability-rule-cases.json"), "utf8"));

describe("ability rule", () => {
  it("shows the full rule as the cases say", () => {
    for (const item of cases.cases) {
      expect(EngineDisplayText.abilityRule(item.label, item.rules, item.sourceName) ?? null, item.name).toBe(item.expect);
    }
  });
});

describe("rules text", () => {
  it("cleans XMage markup and names {this}", () => {
    const raw = "<i>Landfall</i> &mdash; Whenever a land you control enters, create a token that's a copy of {this} instead. <br/><hintstart/> Lands you control: 6";
    const shown = EngineDisplayText.rules(raw, "Scute Swarm");
    expect(shown).toContain("Landfall — Whenever");
    expect(shown).toContain("a copy of Scute Swarm instead.");
    expect(shown).not.toMatch(/[<>&]|\{this\}/);
    expect(shown).toContain("Lands you control: 6");
    expect(EngineDisplayText.rules("Sacrifice {this}: Add {G}.")).toBe("Sacrifice this: Add {G}.");
  });
});

