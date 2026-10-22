/**
 * Card pictures from Scryfall (CORS-open, so canvas and WebGL can use them). Catalogue cards use
 * their exact compiled printing; anything else (tokens, unknown printings) falls back to the name.
 * Requests are spaced ~80 ms apart, as Scryfall asks, and every image is cached for the session.
 */
import type { DeckResolver } from "../core/deckResolver";

export type ArtVersion = "normal" | "large" | "art_crop";

let resolver: DeckResolver | undefined;
export const setArtResolver = (value: DeckResolver) => { resolver = value; };

export const cardImageURL = (name: string, version: ArtVersion): string => {
  const front = name.split(" // ")[0];
  const printing = resolver?.printing(name) ?? resolver?.printing(front);
  if (printing) {
    return `https://api.scryfall.com/cards/${encodeURIComponent(printing.setCode.toLowerCase())}/${encodeURIComponent(printing.collectorNumber)}?format=image&version=${version}`;
  }
  return `https://api.scryfall.com/cards/named?exact=${encodeURIComponent(front)}&format=image&version=${version}`;
};

/** The Magic card back as Scryfall serves it (iOS CardImageURL's "Hidden card"; the Arena board's ArenaCardBack). */
export const CARD_BACK_URL = "https://backs.scryfall.io/normal/0/a/0aeebaf5-8c7d-4636-9e82-8c27447861f7.jpg";

/** A mana symbol, flat, as Scryfall draws it (iOS ManaSymbolView; the Arena board has no 3D tavern pips): {W/U} is WU.svg. */
export const manaSymbolURL = (symbol: string): string =>
  `https://svgs.scryfall.io/card-symbols/${encodeURIComponent(symbol.toUpperCase().replace(/\//g, ""))}.svg`;

const images = new Map<string, Promise<HTMLImageElement | undefined>>();
let nextSlot = 0;

/** A decoded, CORS-clean image, or undefined when Scryfall has none. */
export const loadCardImage = (name: string, version: ArtVersion): Promise<HTMLImageElement | undefined> => {
  const key = `${version}|${name}`;
  let pending = images.get(key);
  if (!pending) {
    const wait = Math.max(0, nextSlot - Date.now());
    nextSlot = Date.now() + wait + 80;
    pending = new Promise((resolve) => {
      setTimeout(() => {
        const image = new Image();
        image.crossOrigin = "anonymous";
        image.decoding = "async";
        image.onload = () => resolve(image);
        image.onerror = () => resolve(undefined);
        image.src = cardImageURL(name, version);
      }, wait);
    });
    images.set(key, pending);
  }
  return pending;
};

const symbolPattern = /\{([^}]+)\}/g;
/** "{2}{R}{R}" → ["2", "R", "R"]; split halves keep their " // " marker. */
export const manaSymbols = (cost: string | undefined): string[] => {
  if (!cost) return [];
  const symbols: string[] = [];
  for (const half of cost.split(" // ")) {
    if (symbols.length > 0) symbols.push("//");
    for (const match of half.matchAll(symbolPattern)) symbols.push(match[1].toUpperCase());
  }
  return symbols;
};
