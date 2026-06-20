import { describe, expect, it } from "vitest";
import { CommanderDeckAnalyzer, generateBracketThreeCommanderDeck, generatedCommanderCardPool } from "../src";

const analyzer = new CommanderDeckAnalyzer();

function deckSize(deck: ReturnType<typeof generateBracketThreeCommanderDeck>["deck"]) {
  return deck.entries.reduce((sum, entry) => sum + entry.quantity, 0);
}

describe("generateBracketThreeCommanderDeck", () => {
  it("creates a valid 100-card singleton Commander deck for bracket 3 play", async () => {
    const generated = generateBracketThreeCommanderDeck({ seed: "human-seed", playerId: "human" });

    await expect(analyzer.validateCommander({ deck: generated.deck, cards: generated.cardPool })).resolves.toEqual([]);
    expect(deckSize(generated.deck)).toBe(100);
    expect(generated.validationErrors).toEqual([]);
    expect(generated.stats.lands).toBeGreaterThanOrEqual(35);
    expect(generated.stats.ramp).toBeGreaterThanOrEqual(8);
    expect(generated.stats.draw).toBeGreaterThanOrEqual(6);
    expect(generated.stats.removal + generated.stats.boardWipes).toBeGreaterThanOrEqual(6);
    expect(generated.bracket.bracket).toBe(3);
    expect(generated.source).toBe("generated");
  });

  it("is stable for the same seed and different across different seeds", () => {
    const first = generateBracketThreeCommanderDeck({ seed: "stable-seed", playerId: "human" });
    const again = generateBracketThreeCommanderDeck({ seed: "stable-seed", playerId: "human" });
    const different = generateBracketThreeCommanderDeck({ seed: "other-seed", playerId: "ai-1" });

    expect(first.deck).toEqual(again.deck);
    expect(first.deck.entries.map((entry) => entry.cardName).join("|")).not.toEqual(
      different.deck.entries.map((entry) => entry.cardName).join("|")
    );
  });

  it("ships enough full card data for generated deck validation and visuals", () => {
    expect(generatedCommanderCardPool.length).toBeGreaterThanOrEqual(75);
    expect(generatedCommanderCardPool.every((card) => card.typeLine && card.legalities?.commander === "legal")).toBe(true);
  });
});
