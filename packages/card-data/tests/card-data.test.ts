import { describe, expect, it } from "vitest";
import { SeedCardDataProvider, mapScryfallCard, seedCards } from "../src";

describe("SeedCardDataProvider", () => {
  it("finds seed cards by exact name without case sensitivity", async () => {
    const provider = new SeedCardDataProvider(seedCards);

    await expect(provider.getCardByName("sol ring")).resolves.toMatchObject({
      name: "Sol Ring",
      manaValue: 1,
      colorIdentity: ["C"]
    });
  });

  it("searches card names from deterministic seed data", async () => {
    const provider = new SeedCardDataProvider(seedCards);

    const results = await provider.searchCards("sol");

    expect(results.map((card) => card.name)).toEqual(["Sol Ring"]);
  });
});

describe("mapScryfallCard", () => {
  it("maps the small Scryfall shape used by the sync stub into shared card identity", () => {
    expect(
      mapScryfallCard({
        id: "scryfall-sol-ring",
        name: "Sol Ring",
        cmc: 1,
        color_identity: [],
        type_line: "Artifact",
        oracle_text: "{T}: Add {C}{C}.",
        mana_cost: "{1}"
      })
    ).toMatchObject({
      id: "scryfall-sol-ring",
      name: "Sol Ring",
      manaValue: 1,
      colorIdentity: ["C"],
      typeLine: "Artifact",
      manaCost: "{1}"
    });
  });
});
