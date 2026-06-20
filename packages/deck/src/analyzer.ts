import type {
  BracketScore,
  CardIdentity,
  ColorSymbol,
  DeckAnalyzer,
  DeckEntry,
  DeckList,
  DeckStats,
  RuleZeroSummary
} from "@magicmobile/shared";

type CardWithOptionalData = CardIdentity & {
  manaCost?: string;
  legalities?: {
    commander?: "legal" | "not_legal" | "banned" | "unknown";
  };
};

const colorSymbols: ColorSymbol[] = ["W", "U", "B", "R", "G", "C"];
const fastManaNames = new Set(["mana crypt", "sol ring"]);
const tutorNames = new Set(["demonic tutor", "vampiric tutor"]);

const emptyColorRecord = (): Record<ColorSymbol, number> => ({
  W: 0,
  U: 0,
  B: 0,
  R: 0,
  G: 0,
  C: 0
});

const normalizeName = (name: string) => name.trim().toLowerCase();

const activeEntries = (deck: DeckList): DeckEntry[] =>
  deck.entries.filter((entry) => entry.section === "commander" || entry.section === "deck");

const buildCardMap = (cards: CardIdentity[]): Map<string, CardWithOptionalData> =>
  new Map(cards.map((card) => [normalizeName(card.name), card as CardWithOptionalData]));

const isLand = (card: CardIdentity): boolean => card.typeLine.toLowerCase().includes("land");

const isBasicLand = (card: CardIdentity | undefined): boolean =>
  Boolean(card?.isBasicLand || card?.typeLine.toLowerCase().includes("basic land"));

const includesAny = (text: string, phrases: string[]): boolean =>
  phrases.some((phrase) => text.includes(phrase));

const countColoredPips = (manaCost: string | undefined): Record<ColorSymbol, number> => {
  const pips = emptyColorRecord();
  for (const match of manaCost?.matchAll(/\{([WUBRGC])\}/g) ?? []) {
    const symbol = match[1] as ColorSymbol | undefined;
    if (symbol) {
      pips[symbol] += 1;
    }
  }
  return pips;
};

const curveBucket = (manaValue: number): string => (manaValue >= 7 ? "7+" : String(manaValue));

const categoryFlags = (card: CardIdentity) => {
  const name = normalizeName(card.name);
  const oracle = card.oracleText?.toLowerCase() ?? "";
  const land = isLand(card);

  return {
    ramp:
      !land &&
      (fastManaNames.has(name) ||
        name === "arcane signet" ||
        name === "cultivate" ||
        oracle.includes("treasure token") ||
        oracle.includes("add one mana") ||
        /\badd \{[wubrgc]\}/i.test(oracle) ||
        oracle.includes("add {c}{c}") ||
        oracle.includes("basic land cards")),
    draw: !land && oracle.includes("draw a card"),
    removal:
      !land &&
      !includesAny(oracle, ["destroy all", "return all"]) &&
      includesAny(oracle, ["destroy target", "exile target", "return target", "deals 3 damage"]),
    boardWipe: !land && includesAny(oracle, ["destroy all", "return all"]),
    tutor: !land && (tutorNames.has(name) || oracle.includes("search your library for a card"))
  };
};

export class CommanderDeckAnalyzer implements DeckAnalyzer {
  async validateCommander(input: { deck: DeckList; cards: CardIdentity[] }): Promise<string[]> {
    const errors: string[] = [];
    const cardMap = buildCardMap(input.cards);
    const entries = activeEntries(input.deck);
    const commanderEntries = entries.filter((entry) => entry.section === "commander");
    const commanderEntry = input.deck.commander ?? entries.find((entry) => entry.section === "commander");
    const commanderCard = commanderEntry ? cardMap.get(normalizeName(commanderEntry.cardName)) : undefined;
    const totalCards = entries.reduce((sum, entry) => sum + entry.quantity, 0);

    if (totalCards !== 100) {
      errors.push("Commander decks must contain exactly 100 cards including the commander.");
    }

    if (commanderEntries.reduce((sum, entry) => sum + entry.quantity, 0) !== 1) {
      errors.push("Commander decks must contain exactly one commander.");
    }

    if (!commanderEntry || !commanderCard) {
      errors.push("Commander is required and must exist in card data.");
    } else {
      const typeLine = commanderCard.typeLine.toLowerCase();
      const oracle = commanderCard.oracleText?.toLowerCase() ?? "";
      const canBeCommander =
        (typeLine.includes("legendary") && typeLine.includes("creature")) ||
        oracle.includes("can be your commander");

      if (!canBeCommander) {
        errors.push("Commander must be a legendary creature or explicitly allowed commander.");
      }

      if (commanderCard.legalities?.commander === "banned") {
        errors.push(`${commanderCard.name} is not legal as a Commander.`);
      }
    }

    const commanderColors = new Set(commanderCard?.colorIdentity ?? []);
    const counts = new Map<string, { displayName: string; quantity: number; card?: CardIdentity }>();

    for (const entry of entries) {
      const normalizedName = normalizeName(entry.cardName);
      const card = cardMap.get(normalizedName);
      const existing = counts.get(normalizedName);
      const counted: { displayName: string; quantity: number; card?: CardIdentity } = {
        displayName: card?.name ?? entry.cardName,
        quantity: (existing?.quantity ?? 0) + entry.quantity
      };

      if (card) {
        counted.card = card;
      }

      counts.set(normalizedName, counted);

      if (commanderCard && card) {
        const illegalColors = card.colorIdentity.filter(
          (color) => color !== "C" && !commanderColors.has(color)
        );
        if (illegalColors.length > 0) {
          errors.push(
            `${card.name} has color identity ${illegalColors.join("")} outside the commander's color identity ${
              commanderCard.colorIdentity.join("") || "C"
            }.`
          );
        }
      }
    }

    for (const counted of counts.values()) {
      if (counted.quantity > 1 && !isBasicLand(counted.card)) {
        errors.push(`${counted.displayName} violates Commander singleton rules.`);
      }
    }

    return errors;
  }

  getStats(input: { deck: DeckList; cards: CardIdentity[] }): DeckStats {
    const cardMap = buildCardMap(input.cards);
    const stats: DeckStats = {
      lands: 0,
      ramp: 0,
      draw: 0,
      removal: 0,
      boardWipes: 0,
      tutors: 0,
      averageManaValue: 0,
      manaCurve: {},
      colorDistribution: emptyColorRecord(),
      colorPipDensity: emptyColorRecord()
    };
    let nonLandManaValue = 0;
    let nonLandCards = 0;

    for (const entry of activeEntries(input.deck)) {
      const card = cardMap.get(normalizeName(entry.cardName));
      if (!card) {
        continue;
      }

      if (isLand(card)) {
        stats.lands += entry.quantity;
        continue;
      }

      nonLandCards += entry.quantity;
      nonLandManaValue += card.manaValue * entry.quantity;
      stats.manaCurve[curveBucket(card.manaValue)] =
        (stats.manaCurve[curveBucket(card.manaValue)] ?? 0) + entry.quantity;

      for (const color of card.colorIdentity) {
        stats.colorDistribution[color] += entry.quantity;
      }

      const pips = countColoredPips(card.manaCost);
      for (const color of colorSymbols) {
        stats.colorPipDensity[color] += pips[color] * entry.quantity;
      }

      const flags = categoryFlags(card);
      if (flags.ramp) stats.ramp += entry.quantity;
      if (flags.draw) stats.draw += entry.quantity;
      if (flags.removal) stats.removal += entry.quantity;
      if (flags.boardWipe) stats.boardWipes += entry.quantity;
      if (flags.tutor) stats.tutors += entry.quantity;
    }

    stats.averageManaValue = nonLandCards > 0 ? Number((nonLandManaValue / nonLandCards).toFixed(2)) : 0;

    return stats;
  }

  getBracketScore(input: { deck: DeckList; cards: CardIdentity[] }): BracketScore {
    const stats = this.getStats(input);
    const cardMap = buildCardMap(input.cards);
    const entries = activeEntries(input.deck);
    const presentFastMana = entries
      .map((entry) => cardMap.get(normalizeName(entry.cardName)))
      .filter((card): card is CardIdentity => Boolean(card && fastManaNames.has(normalizeName(card.name))))
      .map((card) => card.name);
    const explanations: string[] = [];
    let score = 20;

    if (presentFastMana.length > 0) {
      score += 15;
      explanations.push(`Fast mana present: ${presentFastMana.join(", ")}.`);
    }

    if (stats.tutors >= 2) {
      score += 15;
      explanations.push("Tutor density is elevated for casual Commander.");
    } else if (stats.tutors === 1) {
      score += 6;
      explanations.push("Single flexible tutor raises consistency.");
    }

    if (stats.draw >= 1) {
      score += 5;
      explanations.push("Repeatable card draw improves staying power.");
    }

    if (stats.removal + stats.boardWipes >= 3) {
      score += 8;
      explanations.push("Interaction suite can answer multiple board states.");
    }

    if (stats.averageManaValue <= 2.5) {
      score += 6;
      explanations.push("Low average mana value suggests faster deployment.");
    }

    const bracket: BracketScore["bracket"] =
      score >= 75 ? 5 : score >= 55 ? 4 : score >= 40 ? 3 : score >= 25 ? 2 : 1;

    return { bracket, score, explanations };
  }

  getRuleZeroSummary(input: { deck: DeckList; cards: CardIdentity[] }): RuleZeroSummary {
    const score = this.getBracketScore(input);
    const stats = this.getStats(input);
    const cardMap = buildCardMap(input.cards);
    const fastMana = activeEntries(input.deck)
      .map((entry) => cardMap.get(normalizeName(entry.cardName)))
      .filter((card): card is CardIdentity => Boolean(card && fastManaNames.has(normalizeName(card.name))))
      .map((card) => card.name);
    const talkingPoints: string[] = [
      `This list scored ${score.score} using local heuristics: ${score.explanations.join(" ")}`
    ];

    if (fastMana.length > 0) {
      talkingPoints.push(`Mention fast mana before the game: ${fastMana.join(", ")}.`);
    }

    if (stats.tutors > 0) {
      talkingPoints.push("Mention tutor access and whether repeated tutor lines are welcome.");
    }

    if (stats.boardWipes > 0) {
      talkingPoints.push(`Board wipes included: ${stats.boardWipes}.`);
    }

    talkingPoints.push(
      "Commander legality is a placeholder check; confirm table expectations for special commanders."
    );

    return {
      headline: `Bracket ${score.bracket} Commander deck with ${stats.lands} lands and ${stats.averageManaValue} average mana value.`,
      talkingPoints
    };
  }
}
