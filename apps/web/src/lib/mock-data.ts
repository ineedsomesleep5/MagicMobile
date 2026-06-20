import { SeedCardDataProvider } from "@magicmobile/card-data";
import { CommanderDeckAnalyzer } from "@magicmobile/deck";
import { MockRecommendationProvider, createEdhrecCommanderUrl } from "@magicmobile/recommendations";
import type { DeckList, DeckStats, GameLogEntry, Recommendation, RuleZeroSummary } from "@magicmobile/shared";

export const decks = [
  {
    id: "atraxa-counters",
    name: "Atraxa Counter Table",
    commander: "Atraxa, Praetors' Voice",
    colors: ["W", "U", "B", "G"],
    bracket: 4,
    games: 4,
    stats: {
      lands: 36,
      ramp: 8,
      draw: 5,
      removal: 6,
      boardWipes: 1,
      tutors: 2,
      averageManaValue: 2.35,
      manaCurve: { "0": 1, "1": 4, "2": 5, "3": 5, "4": 3 },
      colorDistribution: { W: 7, U: 4, B: 3, R: 0, G: 5, C: 3 },
      colorPipDensity: { W: 7, U: 5, B: 3, R: 0, G: 4, C: 2 }
    } satisfies DeckStats
  }
];

export const cards = [
  { name: "Sol Ring", typeLine: "Artifact", manaValue: 1, colorIdentity: ["C"], note: "Fast mana staple" },
  { name: "Swords to Plowshares", typeLine: "Instant", manaValue: 1, colorIdentity: ["W"], note: "Efficient answer" },
  { name: "Cultivate", typeLine: "Sorcery", manaValue: 3, colorIdentity: ["G"], note: "New-player friendly ramp" },
  { name: "Command Tower", typeLine: "Land", manaValue: 0, colorIdentity: ["C"], note: "Commander fixing" }
];

export const roomSeats = [
  { name: "Ari", type: "digital" as const, status: "active" as const },
  { name: "Bo", type: "webcam" as const, status: "ready" as const },
  { name: "Cam", type: "hybrid" as const, status: "waiting" as const }
];

export const logEntries: GameLogEntry[] = [
  { id: "1", message: "Ari kept an opening seven.", createdAt: "Turn 0" },
  { id: "2", message: "Bo played Command Tower.", createdAt: "Turn 1" },
  { id: "3", message: "Cam passed priority.", createdAt: "Turn 1" }
];

export const ruleZero: RuleZeroSummary = {
  headline: "Bracket 3 creature-first game with slow combo expectations.",
  talkingPoints: ["No mass land destruction", "Tell the table before deterministic combo lines", "Webcam players confirm card names aloud"]
};

const sampleDeckLists: Record<string, DeckList> = {
  "atraxa-counters": {
    name: "Atraxa Counter Table",
    commander: { cardName: "Atraxa, Praetors' Voice", quantity: 1, section: "commander" },
    entries: [
      { cardName: "Atraxa, Praetors' Voice", quantity: 1, section: "commander" },
      { cardName: "Sol Ring", quantity: 1, section: "deck" },
      { cardName: "Arcane Signet", quantity: 1, section: "deck" },
      { cardName: "Mana Crypt", quantity: 1, section: "deck" },
      { cardName: "Swords to Plowshares", quantity: 1, section: "deck" },
      { cardName: "Counterspell", quantity: 1, section: "deck" },
      { cardName: "Cultivate", quantity: 1, section: "deck" },
      { cardName: "Wrath of God", quantity: 1, section: "deck" },
      { cardName: "Rhystic Study", quantity: 1, section: "deck" },
      { cardName: "Demonic Tutor", quantity: 1, section: "deck" },
      { cardName: "Vampiric Tutor", quantity: 1, section: "deck" },
      { cardName: "Beast Within", quantity: 1, section: "deck" },
      { cardName: "Cyclonic Rift", quantity: 1, section: "deck" },
      { cardName: "Smothering Tithe", quantity: 1, section: "deck" },
      { cardName: "Plains", quantity: 22, section: "deck" },
      { cardName: "Island", quantity: 21, section: "deck" },
      { cardName: "Swamp", quantity: 21, section: "deck" },
      { cardName: "Forest", quantity: 22, section: "deck" }
    ]
  }
};

export interface DeckDetailData {
  deck: {
    commander: string;
    id: string;
    name: string;
    stats: DeckStats;
  };
  cardTiles: Array<{
    colorIdentity: string[];
    count: number;
    manaValue: number;
    name: string;
    note: string;
    typeLine: string;
  }>;
  edhrecCommanderUrl?: string;
  recommendations: Recommendation[];
  ruleZero: RuleZeroSummary;
}

export async function getDeckDetail(id: string): Promise<DeckDetailData | undefined> {
  const deckList = sampleDeckLists[id];
  if (!deckList) {
    return undefined;
  }

  const cardProvider = new SeedCardDataProvider();
  const analyzer = new CommanderDeckAnalyzer();
  const recommendationProvider = new MockRecommendationProvider();
  const seedCards = await cardProvider.getSeedCards();
  const stats = analyzer.getStats({ cards: seedCards, deck: deckList });
  const bracketScore = analyzer.getBracketScore({ cards: seedCards, deck: deckList });
  const ruleZeroSummary = analyzer.getRuleZeroSummary({ cards: seedCards, deck: deckList });
  const recommendations = await recommendationProvider.recommend({ deck: deckList });
  const commanderName = deckList.commander?.cardName ?? "Unknown commander";
  const cardTiles = deckList.entries
    .filter((entry) => entry.section === "commander" || entry.section === "deck")
    .map((entry) => {
      const card = seedCards.find((candidate) => candidate.name === entry.cardName);
      return card
        ? {
            colorIdentity: card.colorIdentity,
            count: entry.quantity,
            manaValue: card.manaValue,
            name: card.name,
            note: card.oracleText ?? card.typeLine,
            typeLine: card.typeLine
          }
        : undefined;
    })
    .filter((card): card is NonNullable<typeof card> => Boolean(card));

  return {
    cardTiles,
    deck: {
      commander: commanderName,
      id,
      name: deckList.name,
      stats
    },
    edhrecCommanderUrl: createEdhrecCommanderUrl(commanderName),
    recommendations,
    ruleZero: {
      headline: `Bracket ${bracketScore.bracket}: ${ruleZeroSummary.headline}`,
      talkingPoints: ruleZeroSummary.talkingPoints
    }
  };
}
