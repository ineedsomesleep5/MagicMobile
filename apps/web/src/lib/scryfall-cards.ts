import { readCachedCardVisuals } from "@magicmobile/card-data";

export interface VisualCard {
  name: string;
  typeLine: string;
  manaCost?: string;
  manaValue: number;
  colors: string[];
  oracleText?: string;
  smallImageUrl?: string;
  imageUrl?: string;
  artCropUrl?: string;
  source: "scryfall" | "missing";
}

interface ScryfallCardImageUris {
  small?: string;
  normal?: string;
  art_crop?: string;
  border_crop?: string;
}

interface ScryfallCardFace {
  image_uris?: ScryfallCardImageUris;
}

interface ScryfallCollectionCard {
  name: string;
  type_line?: string;
  mana_cost?: string;
  oracle_text?: string;
  cmc?: number;
  colors?: string[];
  color_identity?: string[];
  image_uris?: ScryfallCardImageUris;
  card_faces?: ScryfallCardFace[];
}

interface ScryfallCollectionResponse {
  data?: ScryfallCollectionCard[];
}

const SCRYFALL_COLLECTION_URL = "https://api.scryfall.com/cards/collection";

const requestHeaders = {
  Accept: "application/json",
  "Content-Type": "application/json",
  "User-Agent": "MagicMobile/0.1 development"
};

const normalize = (name: string) => name.trim().toLowerCase();

export async function fetchCardVisuals(names: string[]): Promise<Map<string, VisualCard>> {
  const uniqueNames = Array.from(new Set(names.map((name) => name.trim()).filter(Boolean)));

  if (uniqueNames.length === 0) {
    return new Map();
  }

  const cached = await readCachedCardVisuals(uniqueNames);
  if (cached.size === uniqueNames.length) {
    return new Map(
      uniqueNames.map((name) => {
        const card = cached.get(name) ?? findCachedSplitCard(name, cached);
        return [name, card ? mapCachedVisual(card) : missingCard(name)];
      })
    );
  }

  try {
    const response = await fetch(SCRYFALL_COLLECTION_URL, {
      method: "POST",
      headers: requestHeaders,
      body: JSON.stringify({
        identifiers: uniqueNames.slice(0, 75).map((name) => ({ name }))
      }),
      next: { revalidate: 60 * 60 * 24 }
    });

    if (!response.ok) {
      throw new Error(`Scryfall collection request failed with ${response.status}`);
    }

    const payload = (await response.json()) as ScryfallCollectionResponse;
    const byName = new Map<string, VisualCard>();

    for (const card of payload.data ?? []) {
      byName.set(normalize(card.name), mapVisualCard(card));
    }

    return new Map(
      uniqueNames.map((name) => {
        const card = byName.get(normalize(name)) ?? findSplitCard(name, byName) ?? missingCard(name);
        return [name, card];
      })
    );
  } catch {
    return new Map(uniqueNames.map((name) => [name, missingCard(name)]));
  }
}

function findCachedSplitCard(name: string, cards: Map<string, { name: string }>): { name: string } | undefined {
  const target = normalize(name);
  for (const [cardName, card] of cards) {
    if (cardName.split("//").some((faceName) => normalize(faceName) === target)) {
      return card;
    }
  }
  return undefined;
}

function mapCachedVisual(card: {
  name: string;
  smallImageUrl?: string;
  imageUrl?: string;
  artCropUrl?: string;
  typeLine?: string;
  manaCost?: string;
  manaValue?: number;
  colors?: string[];
  oracleText?: string;
}): VisualCard {
  const visualCard: VisualCard = {
    name: card.name,
    typeLine: card.typeLine ?? "Magic card",
    manaValue: card.manaValue ?? 0,
    colors: card.colors ?? [],
    source: card.imageUrl ? "scryfall" : "missing"
  };

  if (card.manaCost) visualCard.manaCost = card.manaCost;
  if (card.smallImageUrl) visualCard.smallImageUrl = card.smallImageUrl;
  if (card.imageUrl) visualCard.imageUrl = card.imageUrl;
  if (card.artCropUrl) visualCard.artCropUrl = card.artCropUrl;
  if (card.oracleText) visualCard.oracleText = card.oracleText;

  return visualCard;
}

function findSplitCard(name: string, cards: Map<string, VisualCard>): VisualCard | undefined {
  const target = normalize(name);

  for (const [cardName, card] of cards) {
    if (cardName.split("//").some((faceName) => normalize(faceName) === target)) {
      return card;
    }
  }

  return undefined;
}

function mapVisualCard(card: ScryfallCollectionCard): VisualCard {
  const imageUris = card.image_uris ?? card.card_faces?.find((face) => face.image_uris)?.image_uris;
  const imageUrl = imageUris?.normal ?? imageUris?.border_crop;
  const smallImageUrl = imageUris?.small ?? imageUrl;
  const visualCard: VisualCard = {
    name: card.name,
    typeLine: card.type_line ?? "Magic card",
    manaValue: card.cmc ?? 0,
    colors: card.colors?.length ? card.colors : card.color_identity ?? [],
    source: imageUrl ? "scryfall" : "missing"
  };

  if (card.mana_cost) {
    visualCard.manaCost = card.mana_cost;
  }

  if (card.oracle_text) {
    visualCard.oracleText = card.oracle_text;
  }

  if (imageUrl) {
    visualCard.imageUrl = imageUrl;
  }

  if (smallImageUrl) {
    visualCard.smallImageUrl = smallImageUrl;
  }

  if (imageUris?.art_crop) {
    visualCard.artCropUrl = imageUris.art_crop;
  }

  return visualCard;
}

function missingCard(name: string): VisualCard {
  return {
    name,
    typeLine: "Card image unavailable",
    manaValue: 0,
    colors: [],
    source: "missing"
  };
}
