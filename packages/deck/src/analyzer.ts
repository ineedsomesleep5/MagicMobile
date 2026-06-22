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

const commanderLegalityError = (card: CardWithOptionalData, commander = false): string | undefined => {
  const legality = card.legalities?.commander;
  if (legality === "banned" || legality === "not_legal" || legality === "unknown") {
    return commander ? `${card.name} is not legal as a Commander.` : `${card.name} is not legal in Commander.`;
  }
  return undefined;
};

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
    if (input.deck.errors) {
      errors.push(...input.deck.errors);
    }

    const cardMap = buildCardMap(input.cards);
    const entries = activeEntries(input.deck);
    const commanderEntries = entries.filter((entry) => entry.section === "commander");
    const totalCards = entries.reduce((sum, entry) => sum + entry.quantity, 0);

    if (totalCards !== 100) {
      errors.push("Commander decks must contain exactly 100 cards including the commander.");
    }

    const totalCommanders = commanderEntries.reduce((sum, entry) => sum + entry.quantity, 0);
    const commanderColors = new Set<ColorSymbol>();

    const isTwoCommanders = commanderEntries.length === 2 && commanderEntries.every(e => e.quantity === 1);
    const isOneCommander = commanderEntries.length === 1 && commanderEntries[0]?.quantity === 1;

    if (!isOneCommander && !isTwoCommanders) {
      errors.push("Commander decks must contain exactly one commander.");
    }

    if (totalCommanders === 0) {
      errors.push("Commander is required and must exist in card data.");
    } else if (isTwoCommanders && commanderEntries[0] && commanderEntries[1]) {
      const card1 = cardMap.get(normalizeName(commanderEntries[0].cardName));
      const card2 = cardMap.get(normalizeName(commanderEntries[1].cardName));

      if (!card1 || !card2) {
        errors.push("Commander is required and must exist in card data.");
      } else {
        const type1 = card1.typeLine.toLowerCase();
        const type2 = card2.typeLine.toLowerCase();
        const oracle1 = card1.oracleText?.toLowerCase() ?? "";
        const oracle2 = card2.oracleText?.toLowerCase() ?? "";

        if (!type1.includes("legendary") || !type2.includes("legendary")) {
          errors.push("Both commanders must be legendary.");
        }

        const isPartner1 = oracle1.includes("partner") || oracle1.includes("friends forever") || oracle1.includes("doctor's companion");
        const isPartner2 = oracle2.includes("partner") || oracle2.includes("friends forever") || oracle2.includes("doctor's companion");
        const hasChooseBackground1 = oracle1.includes("choose a background");
        const hasChooseBackground2 = oracle2.includes("choose a background");
        const isBackground1 = type1.includes("background");
        const isBackground2 = type2.includes("background");

        const legalPartners =
          (isPartner1 && isPartner2) ||
          (hasChooseBackground1 && isBackground2) ||
          (hasChooseBackground2 && isBackground1);

        if (!legalPartners) {
          errors.push(`${card1.name} and ${card2.name} are not legal partners.`);
        }

        const legalityError1 = commanderLegalityError(card1, true);
        if (legalityError1) errors.push(legalityError1);
        const legalityError2 = commanderLegalityError(card2, true);
        if (legalityError2) errors.push(legalityError2);
      }

      for (const card of [card1, card2]) {
        if (card) {
          for (const color of card.colorIdentity) {
            commanderColors.add(color);
          }
        }
      }
    } else {
      const commanderEntry = commanderEntries[0];
      const commanderCard = commanderEntry ? cardMap.get(normalizeName(commanderEntry.cardName)) : undefined;
      if (!commanderCard) {
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

        const legalityError = commanderLegalityError(commanderCard, true);
        if (legalityError) {
          errors.push(legalityError);
        }

        for (const color of commanderCard.colorIdentity) {
          commanderColors.add(color);
        }
      }
    }

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

      if (card) {
        if (entry.section !== "commander") {
          const legalityError = commanderLegalityError(card);
          if (legalityError) {
            errors.push(legalityError);
          }
        }

        const illegalColors = card.colorIdentity.filter(
          (color) => color !== "C" && !commanderColors.has(color)
        );
        if (illegalColors.length > 0) {
          errors.push(
            `${card.name} has color identity ${illegalColors.join("")} outside the commander's color identity ${
              Array.from(commanderColors).join("") || "C"
            }.`
          );
        }
      }
    }

    for (const counted of counts.values()) {
      if (counted.quantity > 1 && !isBasicLand(counted.card)) {
        if (counted.card) {
          const nameLower = normalizeName(counted.card.name);
          const oracle = counted.card.oracleText?.toLowerCase() ?? "";
          if (nameLower === "seven dwarves" && counted.quantity <= 7) {
            continue;
          }
          if (oracle.includes("any number of cards named") || oracle.includes("any number of copies")) {
            continue;
          }
        }
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
