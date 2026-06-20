import { describe, expect, it } from "vitest";
import {
  EdhrecProvider,
  LocalSynergyRecommendationProvider,
  MockRecommendationProvider,
  createEdhrecCommanderUrl
} from "../src";
import type { DeckList } from "@magicmobile/shared";

const deck: DeckList = {
  name: "Atraxa Counters",
  commander: { cardName: "Atraxa, Praetors' Voice", quantity: 1, section: "commander" },
  entries: [
    { cardName: "Sol Ring", quantity: 1, section: "deck" },
    { cardName: "Arcane Signet", quantity: 1, section: "deck" }
  ]
};

describe("recommendation providers", () => {
  it("returns deterministic mock recommendations using the shared contract", async () => {
    const provider = new MockRecommendationProvider();

    const recommendations = await provider.recommend({ deck });

    expect(recommendations).toEqual([
      {
        cardName: "Command Tower",
        confidence: 0.5,
        reason: "Mock recommendation for Atraxa, Praetors' Voice decks.",
        source: "mock"
      },
      {
        cardName: "Swords to Plowshares",
        confidence: 0.4,
        reason: "Mock staple suggestion for early recommendation UI wiring.",
        source: "mock"
      }
    ]);
  });

  it("keeps local synergy disabled until approved local data exists", async () => {
    const provider = new LocalSynergyRecommendationProvider();

    await expect(provider.recommend({ deck })).resolves.toEqual([]);
  });

  it("refuses EDHREC recommendations unless explicitly enabled and approved", async () => {
    const provider = new EdhrecProvider({ enabled: false, approvedIntegration: false });

    await expect(provider.recommend({ deck })).rejects.toThrow("EDHREC recommendations are disabled");
  });
});

describe("EDHREC link helper", () => {
  it("builds a public commander link without scraping data", () => {
    expect(createEdhrecCommanderUrl("Atraxa, Praetors' Voice")).toBe(
      "https://edhrec.com/commanders/atraxa-praetors-voice"
    );
  });
});
