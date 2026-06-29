import { describe, expect, it } from "vitest";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SeedCardDataProvider, mapScryfallCard, readCachedCardImageManifest, seedCards } from "../src";

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

describe("readCachedCardImageManifest", () => {
  it("keeps small URLs for board tiles and exposes high resolution inspection URLs", async () => {
    const cacheDir = await mkdtemp(join(tmpdir(), "magicmobile-card-cache-"));
    await writeFile(join(cacheDir, "card-visuals.json"), JSON.stringify([
      {
        name: "Sol Ring",
        smallImageUrl: "https://cards.scryfall.io/small/front/a/b/sol-ring.jpg",
        imageUrl: "https://cards.scryfall.io/normal/front/a/b/sol-ring.jpg",
        largeImageUrl: "https://cards.scryfall.io/large/front/a/b/sol-ring.jpg"
      }
    ]));

    await expect(readCachedCardImageManifest(cacheDir)).resolves.toEqual([
      {
        name: "Sol Ring",
        url: "https://cards.scryfall.io/small/front/a/b/sol-ring.jpg",
        normalUrl: "https://cards.scryfall.io/normal/front/a/b/sol-ring.jpg",
        inspectionUrl: "https://cards.scryfall.io/large/front/a/b/sol-ring.jpg"
      }
    ]);
  });
});
