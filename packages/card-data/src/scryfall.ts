import type { ColorSymbol } from "@magicmobile/shared";
import type { MagicMobileCard, ScryfallCardLike } from "./models";

const toColorSymbols = (colors: string[] | undefined): ColorSymbol[] => {
  const symbols = (colors ?? []).filter((color): color is ColorSymbol =>
    ["W", "U", "B", "R", "G"].includes(color)
  );

  return symbols.length > 0 ? symbols : ["C"];
};

export const mapScryfallCard = (card: ScryfallCardLike): MagicMobileCard => {
  const mapped: MagicMobileCard = {
    id: card.id,
    scryfallId: card.id,
    name: card.name,
    manaValue: card.cmc,
    colorIdentity: toColorSymbols(card.color_identity),
    typeLine: card.type_line
  };

  if (card.oracle_text) {
    mapped.oracleText = card.oracle_text;
  }

  if (card.mana_cost) {
    mapped.manaCost = card.mana_cost;
  }

  if (card.colors) {
    mapped.colors = toColorSymbols(card.colors).filter((color) => color !== "C");
  }

  if (card.type_line.toLowerCase().includes("basic land")) {
    mapped.isBasicLand = true;
  }

  if (card.legalities) {
    mapped.legalities = card.legalities;
  }

  if (card.artist) {
    mapped.artist = card.artist;
  }

  mapped.copyright = card.copyright ?? "™ & © Wizards of the Coast";

  return mapped;
};
