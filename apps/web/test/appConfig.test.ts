/** appConfig (mm_app_config): the reply read safely, switches on unless named off (iOS AppConfigTests, Android AppConfigTest). */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { AppConfig, appConfig } from "../src/core/appConfig";
import { DeckResolver } from "../src/core/deckResolver";

describe("app config", () => {
  it("reads the reply and treats an unnamed switch as on", () => {
    const config = AppConfig.parse({ notice: { id: "update-64", text: "Update to build 64." }, nameFixes: { A: "B", "": "C", D: 3 }, switches: { leaveVote: false, odd: "yes" } })!;
    expect(config.notice).toEqual({ id: "update-64", text: "Update to build 64." });
    expect(config.nameFixes).toEqual({ A: "B" });
    expect(AppConfig.isOn(config, "leaveVote")).toBe(false);
    expect(AppConfig.isOn(config, "stackAutoTuck")).toBe(true);
    expect(AppConfig.isOn(config, "odd")).toBe(true);
    expect(AppConfig.parse({ notice: null, nameFixes: {}, switches: {} })!.notice).toBeUndefined();
    expect(AppConfig.parse([1, 2])).toBeUndefined();
  });

  it("uses a server name fix only for a card the catalogue has", () => {
    const resolver = new DeckResolver(readFileSync(join(__dirname, "..", "public/generated/printings.tsv"), "utf8"));
    expect(resolver.canonicalName("Bolt of Lightning (Archidekt)")).toBeUndefined();
    appConfig.store({ nameFixes: { "Bolt of Lightning (Archidekt)": "Lightning Bolt", "Nothing Here": "Not A Card" } });
    expect(resolver.canonicalName("Bolt of Lightning (Archidekt)")).toBe("Lightning Bolt");
    expect(resolver.canonicalName("Nothing Here")).toBeUndefined();
    appConfig.store({ notice: null, nameFixes: {}, switches: {} });
  });
});
