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

  it("handles Moxfield and Archidekt annotations (foils, tags, collector numbers)", () => {
    const deck = new PastedDeckParser().parse(`
Commander
1 Atraxa, Praetors' Voice (2XM) 220 *F*

Deck
1 Sol Ring (CMM) 410
1 Arcane Signet *F* [Category]
1 Swords to Plowshares #Removal #Instant
`);

    expect(deck.commander?.cardName).toBe("Atraxa, Praetors' Voice");
    expect(deck.entries).toEqual([
      { cardName: "Atraxa, Praetors' Voice", quantity: 1, section: "commander" },
      { cardName: "Sol Ring", quantity: 1, section: "deck" },
      { cardName: "Arcane Signet", quantity: 1, section: "deck" },
      { cardName: "Swords to Plowshares", quantity: 1, section: "deck" }
    ]);
  });

  it("handles quantity-less lines as quantity 1", () => {
    const deck = new PastedDeckParser().parse(`
Commander
Atraxa, Praetors' Voice

Deck
Sol Ring
Arcane Signet
`);

    expect(deck.commander?.cardName).toBe("Atraxa, Praetors' Voice");
    expect(deck.entries).toEqual([
      { cardName: "Atraxa, Praetors' Voice", quantity: 1, section: "commander" },
      { cardName: "Sol Ring", quantity: 1, section: "deck" },
      { cardName: "Arcane Signet", quantity: 1, section: "deck" }
    ]);
  });

  it("returns errors when pasting URLs instead of exported text", () => {
    const deck = new PastedDeckParser().parse(`https://www.moxfield.com/decks/yG0V2bN7Z0G`);
    expect(deck.errors).toContain("Direct website scraping is not supported. Please paste the exported plain text of your deck list.");
  });

  it("returns errors when pasting empty or invalid input", () => {
    const deck = new PastedDeckParser().parse(`
    
    // Just some comments
    # Another comment
    `);
    expect(deck.errors).toContain("No valid card entries found in the pasted text.");
  });
});
