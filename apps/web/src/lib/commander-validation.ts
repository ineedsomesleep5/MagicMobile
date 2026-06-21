import { readCachedCardVisuals } from "@magicmobile/card-data";
import { CommanderDeckAnalyzer } from "@magicmobile/deck";
import type { CardIdentity, CommanderGameConfig, DeckEntry, DeckList } from "@magicmobile/shared";

const analyzer = new CommanderDeckAnalyzer();

export async function validateCommanderGameConfig(config: CommanderGameConfig): Promise<string[]> {
  const errors: string[] = [];
  const decks = [
    { owner: "Human deck", deck: config.humanDeck },
    ...config.aiPlayers.map((player) => ({ owner: `${player.displayName || player.playerId} deck`, deck: player.deck }))
  ].filter((entry): entry is { owner: string; deck: DeckList } => Boolean(entry.deck));

  const names = Array.from(
    new Set(
      decks.flatMap(({ deck }) => [
        ...(deck.commander ? [deck.commander.cardName] : []),
        ...deck.entries.map((entry) => entry.cardName)
      ])
    )
  );
  const cachedCards = await readCachedCardVisuals(names);
  const cards = Array.from(cachedCards.values()).map(toCardIdentity);

  for (const { owner, deck } of decks) {
    const deckErrors = await analyzer.validateCommander({
      deck: analyzerDeck(deck),
      cards
    });
    errors.push(...deckErrors.map((error) => `${owner}: ${error}`));
  }

  return errors;
}

function analyzerDeck(deck: DeckList): DeckList {
  const entries = [...deck.entries];
  if (deck.commander && !entries.some((entry) => entry.section === "commander")) {
    entries.unshift(deck.commander);
  }
  return { ...deck, entries };
}

function toCardIdentity(card: {
  name: string;
  manaValue?: number;
  colorIdentity?: string[];
  typeLine?: string;
  oracleText?: string;
  isBasicLand?: boolean;
  legalities?: { commander?: "legal" | "not_legal" | "banned" | "unknown" };
}): CardIdentity & { legalities?: { commander?: "legal" | "not_legal" | "banned" | "unknown" } } {
  const identity: CardIdentity & {
    legalities?: { commander?: "legal" | "not_legal" | "banned" | "unknown" };
  } = {
    id: card.name,
    name: card.name,
    manaValue: card.manaValue ?? 0,
    colorIdentity: (card.colorIdentity ?? []).filter(isColorSymbol),
    typeLine: card.typeLine ?? "Magic card"
  };
  if (card.oracleText) identity.oracleText = card.oracleText;
  if (card.isBasicLand) identity.isBasicLand = true;
  if (card.legalities) identity.legalities = card.legalities;
  return identity;
}

function isColorSymbol(value: string): value is CardIdentity["colorIdentity"][number] {
  return ["W", "U", "B", "R", "G", "C"].includes(value);
}
