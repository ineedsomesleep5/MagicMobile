/**
 * Card pictures from Scryfall (CORS-open, so canvas and WebGL can use them). Catalogue cards use
 * their exact compiled printing; anything else (tokens, unknown printings) falls back to the name.
 * Requests are spaced ~80 ms apart, as Scryfall asks, and every image is cached for the session.
 */
import { createElement, useEffect, useState } from "react";
import type { DeckResolver } from "../core/deckResolver";
import { tokenArtworkName } from "../core/gameStats";
import type { CardIdentity, TokenArtworkIdentity, ZoneCard } from "../core/models";
import { permitsSourceName } from "../core/snapshotAdapter";
import { matchTokenArtwork, safeTokenSearchName, type TokenArtwork, tokenImage, tokenSearchQuery, tokensFromSearch } from "../core/tokenArt";

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

/**
 * The Magic card back (iOS CardImageURL's "Hidden card"; the Arena board's ArenaCardBack), from the site's own copy of
 * Scryfall's backs.scryfall.io image: a work filter that blocks that host would otherwise leave every back blank.
 */
export const CARD_BACK_URL = "/arena/card-back.jpg";

/** A mana symbol, flat, as Scryfall draws it (iOS ManaSymbolView; the Arena board has no 3D tavern pips): {W/U} is WU.svg. */
const symbolFile = (symbol: string) => encodeURIComponent(symbol.toUpperCase().replace(/\//g, ""));
/**
 * A card symbol ({T}, {W}, {2/B}…) from the site's own copy of Scryfall's set (public/symbols, scripts/fetch_symbols.mjs):
 * a network that blocks svgs.scryfall.io (a work filter) would otherwise turn every symbol into a letter.
 */
export const manaSymbolURL = (symbol: string): string => `/symbols/${symbolFile(symbol)}.svg`;
/** Scryfall's own copy, for a symbol newer than the site's set. */
export const remoteManaSymbolURL = (symbol: string): string => `https://svgs.scryfall.io/card-symbols/${symbolFile(symbol)}.svg`;

const images = new Map<string, Promise<HTMLImageElement | undefined>>();
let nextSlot = 0;
/** Milliseconds to wait before the next Scryfall request, keeping them ~80 ms apart. */
const slot = () => {
  const wait = Math.max(0, nextSlot - Date.now());
  nextSlot = Date.now() + wait + 80;
  return wait;
};

const tokenSearches = new Map<string, Promise<TokenArtwork[]>>();
/** Every token printing with this exact name (three pages at most), searched once a session. */
function searchTokens(name: string): Promise<TokenArtwork[]> {
  const query = tokenSearchQuery(name);
  let found = tokenSearches.get(query);
  if (!found) {
    found = (async () => {
      const tokens: TokenArtwork[] = [];
      for (let page = 1; page <= 3; page++) {
        await new Promise((resolve) => setTimeout(resolve, slot()));
        const url = `https://api.scryfall.com/cards/search?q=${encodeURIComponent(query)}&unique=cards&page=${page}`;
        const response = await fetch(url).catch(() => undefined);
        if (!response || response.status === 404 || !response.ok) break;
        const body = await response.json().catch(() => undefined) as { data?: Record<string, unknown>[]; has_more?: boolean } | undefined;
        if (!body || !Array.isArray(body.data)) break;
        tokens.push(...tokensFromSearch(body.data));
        if (!body.has_more) break;
      }
      return tokens;
    })();
    tokenSearches.set(query, found);
  }
  return found;
}

/** A token's picture, the printing that matches what the engine shows (NativeDeckArtwork's token path), or undefined. */
export async function tokenArtURL(identity: TokenArtworkIdentity, version: ArtVersion): Promise<string | undefined> {
  if (!safeTokenSearchName(tokenArtworkName(identity.name))) return undefined;
  const candidates = await searchTokens(identity.name);
  const match = matchTokenArtwork(candidates, identity);
  return match && tokenImage(candidates, match, version);
}

/**
 * NativeCardArtworkPolicy.permitsLookup: never a placeholder's name ("Face-down card", CardView's "Face Down: …"), nor a
 * card the engine marks face down, except your own face-down card, which shows its real face.
 */
export const permitsArtName = (name: string) => permitsSourceName(name) && !/^face[ -]down:/i.test(name.trim());
export const permitsArtLookup = (card: ZoneCard) =>
  permitsArtName(card.card.name) && (card.card.faceDown === true || !(card.cardIcons ?? []).some((i) => i.iconType.toUpperCase() === "OTHER_FACEDOWN"));

/**
 * The picture for a card on the table: a copy's source card, a token's matched printing, else the card by name. A token
 * resolves after a search, so this is undefined until then and null when there is none.
 */
export function useCardArtURL(card: CardIdentity, version: ArtVersion): string | null | undefined {
  const token = card.isToken === true && !card.copySourceArtworkName ? card.tokenArtwork : undefined;
  const named = card.copySourceArtworkName ?? card.name;
  const plain = token || !permitsArtName(named) ? undefined : cardImageURL(named, version);
  const key = token ? JSON.stringify(token) + version : "";
  const [resolved, setResolved] = useState<{ key: string; url: string | null }>();
  useEffect(() => {
    if (!token) return;
    let live = true;
    void tokenArtURL(token, version).then((url) => { if (live) setResolved({ key, url: url ?? null }); });
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  if (plain) return plain;
  if (!token) return null;
  return resolved?.key === key ? resolved.url : undefined;
}

/** A decoded, CORS-clean image, or undefined when Scryfall has none. */
export const loadCardImage = (name: string, version: ArtVersion, url = cardImageURL(name, version)): Promise<HTMLImageElement | undefined> => {
  const key = `${version}|${url}`;
  let pending = images.get(key);
  if (!pending) {
    const wait = slot();
    pending = new Promise((resolve) => {
      setTimeout(() => {
        const image = new Image();
        image.crossOrigin = "anonymous";
        image.decoding = "async";
        image.onload = () => resolve(image);
        image.onerror = () => resolve(undefined);
        image.src = url;
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

/**
 * Whether a picture has come through the paced loader (loadCardImage): undefined while it waits its turn, then true, or
 * false when Scryfall has none. An `<img>` given the address only after this is true takes it from the browser's cache,
 * so a board's first render never bursts past Scryfall's ten requests a second.
 */
export function usePacedImage(url: string | null | undefined, version: ArtVersion): boolean | undefined {
  const [done, setDone] = useState<{ url: string; ok: boolean }>();
  useEffect(() => {
    if (!url) return;
    let live = true;
    void loadCardImage("", version, url).then((image) => { if (live) setDone({ url, ok: image !== undefined }); });
    return () => { live = false; };
  }, [url, version]);
  return url && done?.url === url ? done.ok : undefined;
}

/** A card's picture as an image, nothing while it waits its turn (usePacedImage), while a token's printing is found or when there is none. */
export function CardArt({ card, version, onMissing }: { card: CardIdentity; version: ArtVersion; onMissing?: () => void }) {
  const url = useCardArtURL(card, version);
  const loaded = usePacedImage(url, version);
  useEffect(() => { if (url === null || loaded === false) onMissing?.(); }, [url, loaded, onMissing]);
  return url && loaded ? createElement("img", { key: url, src: url, alt: "", crossOrigin: "anonymous", draggable: false, onError: onMissing }) : null;
}
