import { describe, expect, it } from "vitest";
import type { DeckEntry, DeckList } from "@magicmobile/shared";
import { seedCards } from "../../card-data/src";
import { CommanderDeckAnalyzer } from "../src";

const analyzer = new CommanderDeckAnalyzer();

const entry = (
  cardName: string,
  quantity = 1,
  section: DeckEntry["section"] = "deck"
): DeckEntry => ({ cardName, quantity, section });

const validAtraxaDeck = (): DeckList => ({
  name: "Atraxa test deck",
  commander: entry("Atraxa, Praetors' Voice", 1, "commander"),
  entries: [
    entry("Atraxa, Praetors' Voice", 1, "commander"),
    entry("Sol Ring"),
    entry("Arcane Signet"),
    entry("Swords to Plowshares"),
    entry("Counterspell"),
    entry("Cultivate"),
    entry("Wrath of God"),
    entry("Rhystic Study"),
    entry("Demonic Tutor"),
    entry("Beast Within"),
    entry("Plains", 23),
    entry("Island", 23),
    entry("Swamp", 22),
    entry("Forest", 22)
  ]
});

describe("CommanderDeckAnalyzer.validateCommander", () => {
  it("accepts a 100-card singleton Commander deck with on-color cards", async () => {
    await expect(analyzer.validateCommander({ deck: validAtraxaDeck(), cards: seedCards })).resolves.toEqual([]);
  });

  it("reports Commander deck size, singleton, color identity, and commander placeholder legality errors", async () => {
    const deck = validAtraxaDeck();
    deck.commander = entry("Sol Ring", 1, "commander");
    deck.entries[0] = entry("Sol Ring", 1, "commander");
    deck.entries[1] = entry("Sol Ring", 2);
    deck.entries.push(entry("Lightning Bolt"));

    const errors = await analyzer.validateCommander({ deck, cards: seedCards });

    expect(errors).toContain("Commander decks must contain exactly 100 cards including the commander.");
    expect(errors).toContain("Commander must be a legendary creature or explicitly allowed commander.");
    expect(errors).toContain("Sol Ring violates Commander singleton rules.");
    expect(errors).toContain("Lightning Bolt has color identity R outside the commander's color identity C.");
  });

  it("rejects decks without exactly one commander", async () => {
    const noCommander = validAtraxaDeck();
    delete noCommander.commander;
    noCommander.entries = noCommander.entries.filter((entry) => entry.section !== "commander");

    const twoCommanders = validAtraxaDeck();
    twoCommanders.entries[0] = entry("Atraxa, Praetors' Voice", 2, "commander");

    await expect(analyzer.validateCommander({ deck: noCommander, cards: seedCards })).resolves.toContain(
      "Commander decks must contain exactly one commander."
    );
    await expect(analyzer.validateCommander({ deck: twoCommanders, cards: seedCards })).resolves.toContain(
      "Commander decks must contain exactly one commander."
    );
  });

  it("rejects banned commanders", async () => {
    const bannedCards = seedCards.map((card) =>
      card.name === "Atraxa, Praetors' Voice" ? { ...card, legalities: { commander: "banned" as const } } : card
    );

    const errors = await analyzer.validateCommander({ deck: validAtraxaDeck(), cards: bannedCards });

    expect(errors).toContain("Atraxa, Praetors' Voice is not legal as a Commander.");
  });
});

describe("CommanderDeckAnalyzer.getStats", () => {
  it("computes deck composition, mana curve, color distribution, and pip density", () => {
    const stats = analyzer.getStats({
      deck: {
        name: "Stats deck",
        commander: entry("Atraxa, Praetors' Voice", 1, "commander"),
        entries: [
          entry("Atraxa, Praetors' Voice", 1, "commander"),
          entry("Sol Ring"),
          entry("Arcane Signet"),
          entry("Cultivate"),
          entry("Rhystic Study"),
          entry("Swords to Plowshares"),
          entry("Wrath of God"),
          entry("Demonic Tutor"),
          entry("Island"),
          entry("Forest")
        ]
      },
      cards: seedCards
    });

    expect(stats.lands).toBe(2);
    expect(stats.ramp).toBe(3);
    expect(stats.draw).toBe(1);
    expect(stats.removal).toBe(1);
    expect(stats.boardWipes).toBe(1);
    expect(stats.tutors).toBe(1);
    expect(stats.averageManaValue).toBeCloseTo(2.5, 2);
    expect(stats.manaCurve).toMatchObject({ "1": 2, "2": 2, "3": 2, "4": 2 });
    expect(stats.colorDistribution).toMatchObject({ W: 3, U: 2, B: 2, G: 2, R: 0, C: 2 });
    expect(stats.colorPipDensity).toMatchObject({ W: 4, U: 2, B: 2, G: 2, R: 0, C: 0 });
  });
});

describe("CommanderDeckAnalyzer.getBracketScore", () => {
  it("returns explainable scores that rank stronger decks higher", () => {
    const casual = analyzer.getBracketScore({ deck: validAtraxaDeck(), cards: seedCards });
    const tuned = analyzer.getBracketScore({
      deck: {
        name: "Tuned deck",
        commander: entry("Atraxa, Praetors' Voice", 1, "commander"),
        entries: [
          entry("Atraxa, Praetors' Voice", 1, "commander"),
          entry("Mana Crypt"),
          entry("Sol Ring"),
          entry("Arcane Signet"),
          entry("Demonic Tutor"),
          entry("Vampiric Tutor"),
          entry("Cyclonic Rift"),
          entry("Rhystic Study"),
          entry("Smothering Tithe"),
          entry("Plains", 30),
          entry("Island", 30),
          entry("Swamp", 29)
        ]
      },
      cards: seedCards
    });

    expect(tuned.score).toBeGreaterThan(casual.score);
    expect(tuned.bracket).toBeGreaterThanOrEqual(3);
    expect(tuned.explanations).toEqual(
      expect.arrayContaining([
        "Fast mana present: Mana Crypt, Sol Ring.",
        "Tutor density is elevated for casual Commander."
      ])
    );
  });
});

describe("CommanderDeckAnalyzer.getRuleZeroSummary", () => {
  it("summarizes power signals into Rule 0 talking points", () => {
    const summary = analyzer.getRuleZeroSummary({
      deck: {
        name: "Rule 0 deck",
        commander: entry("Atraxa, Praetors' Voice", 1, "commander"),
        entries: [
          entry("Atraxa, Praetors' Voice", 1, "commander"),
          entry("Mana Crypt"),
          entry("Sol Ring"),
          entry("Demonic Tutor"),
          entry("Vampiric Tutor"),
          entry("Cyclonic Rift"),
          entry("Plains", 48),
          entry("Island", 48)
        ]
      },
      cards: seedCards
    });

    expect(summary.headline).toContain("Bracket");
    expect(summary.talkingPoints).toEqual(
      expect.arrayContaining([
        "Mention fast mana before the game: Mana Crypt, Sol Ring.",
        "Mention tutor access and whether repeated tutor lines are welcome.",
        "Commander legality is a placeholder check; confirm table expectations for special commanders."
      ])
    );
  });
});
