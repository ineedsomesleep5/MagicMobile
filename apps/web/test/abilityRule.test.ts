/** parity/ability-rule-cases.json: the full rule a trigger or ability choice shows (OnDevicePromptAdapterTests.swift). */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { EngineDisplayText } from "../src/core/displayText";

const cases = JSON.parse(readFileSync(join(__dirname, "..", "..", "android/core/src/test/resources/parity/ability-rule-cases.json"), "utf8"));

describe("ability rule", () => {
  it("shows the full rule as the cases say", () => {
    for (const item of cases.cases) {
      expect(EngineDisplayText.abilityRule(item.label, item.rules) ?? null, item.name).toBe(item.expect);
    }
  });
});
