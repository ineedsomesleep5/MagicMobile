import { describe, expect, it } from "vitest";
import { PastedDeckParser } from "../src";

describe("PastedDeckParser", () => {
  it("parses Moxfield, Archidekt, and MTGO-style lines into sections", () => {
    const deck = new PastedDeckParser().parse(`
Commander
1 Atraxa, Praetors' Voice

Deck
1 Sol Ring (CMM) 410
1x Arcane Signet
2 Island

Sideboard
1 Swords to Plowshares

Maybeboard:
1 Cyclonic Rift
`);

    expect(deck.name).toBe("Imported deck");
    expect(deck.commander).toEqual({
      cardName: "Atraxa, Praetors' Voice",
      quantity: 1,
      section: "commander"
    });
    expect(deck.entries).toEqual([
      { cardName: "Atraxa, Praetors' Voice", quantity: 1, section: "commander" },
      { cardName: "Sol Ring", quantity: 1, section: "deck" },
      { cardName: "Arcane Signet", quantity: 1, section: "deck" },
      { cardName: "Island", quantity: 2, section: "deck" },
      { cardName: "Swords to Plowshares", quantity: 1, section: "sideboard" },
      { cardName: "Cyclonic Rift", quantity: 1, section: "maybeboard" }
    ]);
  });
});
