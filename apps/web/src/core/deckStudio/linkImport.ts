/**
 * Moxfield and Archidekt deck links (OnDeviceDeckLinkImporter.swift; Android DeckMetadata.kt OnDeviceDeckLinkImporter).
 * No login, cookies, scraping or remote card-name resolution: the page fetches the fixed API endpoint, and this decodes
 * and checks the answer.
 *
 * CORS, checked 2026-10-23 with `curl -sI -H 'Origin: https://magicmobile-web.vercel.app'`: neither API can be read
 * from the web app's own origin. Archidekt answered 200 JSON with `vary: Origin` but `access-control-allow-origin:
 * http://localhost:3000`, which a browser rejects for our origin; Moxfield answered 403 from Cloudflare's bot check with
 * no CORS headers at all. The page needs a same-origin proxy (or the player pastes the exported text).
 */
import { StudioEntry, utf8Size, validateDeck, type CardPrinting, type StudioDeck } from "./draft";

export type DeckLinkProvider = "moxfield" | "archidekt";
export interface DeckLinkSource { provider: DeckLinkProvider; id: string; endpoint: string }

/** A link or provider answer this app cannot import; nothing was imported. */
export class DeckLinkError extends Error {
  constructor(readonly reason: string) { super(`${reason} Export the deck as text and paste it instead; no cards were imported.`); }
}

/** OnDeviceDeckResolver.ResolutionError: names, counts or sections the engine cannot play. */
export class ResolutionError extends Error {}

export const maximumResponseBytes = 2 * 1024 * 1024;

/**
 * The provider API for a public deck link. A share link's query and fragment are ignored: the request goes to a fixed
 * endpoint built from the deck ID alone. A link pasted without its scheme is read as HTTPS.
 */
export function deckLinkSource(text: string): DeckLinkSource {
  let value = text.trim();
  if (!value.includes("://")) value = `https://${value}`;
  let url: URL;
  try { url = new URL(value); } catch { throw new DeckLinkError("Use an HTTPS public Moxfield or Archidekt deck URL without credentials."); }
  // URL normalizes the path, so read the raw path from the text: no percent escapes, no dot segments.
  const rawPath = /^[a-z][a-z0-9+.-]*:\/\/[^/?#]*([^?#]*)/i.exec(value)?.[1] ?? "";
  if (utf8Size(value) > 2048 || url.protocol !== "https:" || url.username !== "" || url.password !== "" || url.port !== "" || rawPath.includes("%")) {
    throw new DeckLinkError("Use an HTTPS public Moxfield or Archidekt deck URL without credentials.");
  }
  const path = rawPath.split("/");
  if (path.length < 3 || path[0] !== "" || path[1] !== "decks") throw new DeckLinkError("This is not a supported deck link.");
  const id = path[2];
  switch (url.hostname.toLowerCase()) {
    case "moxfield.com": case "www.moxfield.com":
      if (!/^[A-Za-z0-9_-]{22}$/.test(id) || !(path.length === 3 || (path.length === 4 && path[3] === ""))) throw new DeckLinkError("Invalid Moxfield deck ID.");
      return { provider: "moxfield", id, endpoint: `https://api2.moxfield.com/v3/decks/all/${id}` };
    case "archidekt.com": case "www.archidekt.com":
      if (!/^[1-9][0-9]{0,14}$/.test(id) || !(path.length === 3 || (path.length === 4 && /^[A-Za-z0-9_-]*$/.test(path[3])))) {
        throw new DeckLinkError("Invalid Archidekt deck ID or slug.");
      }
      return { provider: "archidekt", id, endpoint: `https://archidekt.com/api/decks/${id}/` };
    default: throw new DeckLinkError("Only moxfield.com and archidekt.com deck links are supported.");
  }
}

/** The engine's name for a card (DeckResolver.canonicalName or Catalogue.canonicalName); undefined when it has none. */
export type CanonicalName = (name: string) => string | undefined;

export interface DeckPreview { deck: StudioDeck; unresolvedNames: string[] }

/** Canonical names where the engine knows them, and the names it does not, sorted. */
export function previewDeck(deck: StudioDeck, canonical: CanonicalName): DeckPreview {
  validateDeck(deck);
  const unresolved = new Set<string>();
  const entry = (row: StudioEntry): StudioEntry => {
    const name = canonical(row.cardName);
    if (name === undefined) unresolved.add(row.cardName);
    return { ...row, cardName: name ?? row.cardName };
  };
  const result: StudioDeck = { name: deck.name, entries: deck.entries.map(entry) };
  if (deck.commander) result.commander = entry(deck.commander);
  return { deck: result, unresolvedNames: [...unresolved].sort() };
}

/**
 * OnDeviceDeckResolver.canonicalized + resolve's checks, without printings: every name known, counts 1–2,000 with at
 * most 2,000 in all, sections Deck/Commander/Companion only, and no card split between them.
 */
function resolvable(deck: StudioDeck, canonical: CanonicalName): StudioDeck {
  const name = (row: StudioEntry) => {
    const value = canonical(row.cardName);
    if (value === undefined) throw new ResolutionError(`No compiled printing for '${row.cardName}'. Use the exact card name from this app's catalogue or update the app.`);
    return { ...row, cardName: value };
  };
  const result: StudioDeck = { name: deck.name, entries: deck.entries.map(name) };
  if (deck.commander) result.commander = name(deck.commander);
  const assigned = new Map<string, string>();
  let total = 0;
  const check = (row: StudioEntry, section: string) => {
    if (!Number.isInteger(row.quantity) || row.quantity < 1 || row.quantity > 2000 - total) {
      throw new ResolutionError(`Invalid count for '${row.cardName}'. Each count must be 1–2,000 and the entire deck must contain at most 2,000 cards.`);
    }
    total += row.quantity;
    const previous = assigned.get(row.cardName);
    if (previous !== undefined && previous !== section) {
      throw new ResolutionError(`'${row.cardName}' appears in both ${previous} and ${section}. Keep it in one section and confirm its count; no copies were removed automatically.`);
    }
    assigned.set(row.cardName, section);
  };
  if (result.commander) check(result.commander, "commanders");
  for (const row of result.entries) {
    const section = { deck: "main", main: "main", commander: "commanders", commanders: "commanders", companion: "companions",
      companions: "companions" }[row.section.trim().toLowerCase()];
    if (section === undefined) throw new ResolutionError(`Unsupported deck section '${row.section}'. Native play supports Deck, Commander, or Companion, not a general sideboard. No cards were dropped.`);
    check(row, section);
  }
  return result;
}

export interface DecodeOptions {
  canonicalName: CanonicalName;
  /** "Exclude sideboard / maybeboard": those boards are checked, then left out. Otherwise a nonempty one fails the import. */
  excludeSideboards?: boolean;
  /** Keep unknown names for review (the import screen's path) instead of failing on them. */
  reviewOnly?: boolean;
}

type Wire = Record<string, unknown>;
const schema = (): never => { throw new DeckLinkError("Malformed or changed provider deck schema."); };
const object = (value: unknown): Wire => (typeof value === "object" && value !== null && !Array.isArray(value) ? value as Wire : schema());
const string = (value: unknown): string => (typeof value === "string" ? value : schema());
const integer = (value: unknown): number => (Number.isInteger(value) ? value as number : schema());
const boolean = (value: unknown): boolean => (typeof value === "boolean" ? value : schema());

/** Decodes a provider's JSON answer for `source` into a deck: the first commander leads, partners stay in "commanders". */
export function decodeDeckLink(source: DeckLinkSource, text: string, options: DecodeOptions): StudioDeck {
  const { canonicalName, excludeSideboards = false, reviewOnly = false } = options;
  if (utf8Size(text) > maximumResponseBytes) throw new DeckLinkError("Provider response exceeds 2 MiB.");
  // Opting out of a section does not permit malformed quantities or unknown card names.
  const validateExcluded = (entries: StudioEntry[]) => { if (entries.length > 0) resolvable({ name: "Excluded cards", entries }, canonicalName); };
  const checked = (name: string, entries: StudioEntry[]): StudioDeck => {
    if (entries.length === 0 || entries.length > 2000 || utf8Size(name) > 512) throw new DeckLinkError("Deck is empty or too large.");
    const lead = entries.findIndex((entry) => entry.section === "commanders");
    const raw: StudioDeck = lead < 0 ? { name, entries } : { name, commander: entries[lead], entries: entries.filter((_, index) => index !== lead) };
    return reviewOnly ? previewDeck(raw, canonicalName).deck : resolvable(raw, canonicalName);
  };
  let value: Wire;
  try { value = object(JSON.parse(text)); } catch (error) { if (error instanceof DeckLinkError) throw error; return schema(); }
  try {
    if (source.provider === "moxfield") {
      const publicId = string(value.publicId); const name = string(value.name); const visibility = string(value.visibility);
      const boards = object(value.boards);
      if (publicId !== source.id || visibility.toLowerCase() !== "public") throw new DeckLinkError("Moxfield deck is private, not public, or has a mismatched ID.");
      const sections: Record<string, string> = { mainboard: "main", commanders: "commanders", companions: "companions" };
      const entries: StudioEntry[] = [];
      const boardRows = Object.fromEntries(Object.entries(boards).map(([key, board]) => [key, Object.entries(object(object(board).cards)).map(([id, raw]) => {
        const row = object(raw);
        return [id, string(object(row.card).name), integer(row.quantity)] as const;
      })]));
      for (const key of Object.keys(boardRows).sort()) {
        const rows = boardRows[key];
        const section = sections[key];
        if (section === undefined) {
          if (excludeSideboards && (key === "sideboard" || key === "maybeboard")) {
            validateExcluded(rows.map(([, card, quantity]) => ({ cardName: card, quantity, section: "main" })));
            continue;
          }
          if (rows.length > 0) throw new DeckLinkError(`Unsupported Moxfield section '${key}'; it cannot be discarded or treated as a companion.`);
          continue;
        }
        for (const [, card, quantity] of [...rows].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))) entries.push({ cardName: card, quantity, section });
      }
      return checked(name, entries);
    }
    const id = integer(value.id); const name = string(value.name);
    const isPrivate = boolean(value.private); const unlisted = boolean(value.unlisted);
    const categoryRows = Array.isArray(value.categories) ? value.categories : schema();
    const cardRows = Array.isArray(value.cards) ? value.cards : schema();
    if (String(id) !== source.id || isPrivate || unlisted) throw new DeckLinkError("Archidekt deck is private, not public, or has a mismatched ID.");
    const categories = new Map<string, boolean>();
    const parsedCategories = categoryRows.map((raw) => { const row = object(raw); return [string(row.name), boolean(row.includedInDeck)] as const; });
    const parsedCards = cardRows.map((raw) => {
      const row = object(raw);
      const labels = row.categories === undefined || row.categories === null ? [] : (Array.isArray(row.categories) ? row.categories.map(string) : schema());
      const companion = row.companion === undefined || row.companion === null ? undefined : boolean(row.companion);
      return { quantity: integer(row.quantity), labels, companion, name: string(object(object(row.card).oracleCard).name) };
    });
    for (const [label, included] of parsedCategories) {
      if (categories.has(label)) throw new DeckLinkError("Ambiguous Archidekt categories.");
      categories.set(label, included);
    }
    const entries: StudioEntry[] = [];
    for (const row of parsedCards) {
      if (!row.labels.every((label) => categories.has(label))) throw new DeckLinkError("Unknown Archidekt card category.");
      const roles = new Set(row.labels.map((label) => label.toLowerCase()).filter((label) => ["commander", "companion", "sideboard", "maybeboard"].includes(label)));
      if (roles.size > 1) throw new DeckLinkError("Conflicting Archidekt card roles.");
      if (row.companion === true && roles.has("commander")) throw new DeckLinkError("Card marked both commander and companion.");
      const companion = row.companion === true || roles.has("companion");
      const sideboard = roles.has("sideboard") || roles.has("maybeboard");
      const excludedCategory = row.labels.length > 0 && row.labels.every((label) => categories.get(label) === false);
      if (sideboard || (excludedCategory && !companion)) {
        if (roles.has("commander") || companion || (sideboard && row.labels.some((label) => categories.get(label) === true))) {
          throw new DeckLinkError("Conflicting included and excluded Archidekt card roles.");
        }
        if (!excludeSideboards) throw new DeckLinkError("Archidekt contains sideboard or excluded cards; these cannot be silently discarded.");
        validateExcluded([{ cardName: row.name, quantity: row.quantity, section: "main" }]);
        continue;
      }
      entries.push({ cardName: row.name, quantity: row.quantity, section: roles.has("commander") ? "commanders" : companion ? "companions" : "main" });
    }
    return checked(name, entries);
  } catch (error) {
    if (error instanceof DeckLinkError || error instanceof ResolutionError) throw error;
    return schema();
  }
}

/**
 * The commander the player picked before importing leads the reviewed deck, whether or not the list marked one. One
 * main-deck copy is promoted (keeping its printing); a card the list marked as commander instead joins the main deck,
 * except a partner already in the command zone, which stays beside it.
 */
export function choosingCommander(name: string, deck: StudioDeck): StudioDeck {
  const board = (entry: StudioEntry) => entry.section.trim().toLowerCase();
  if (deck.commander?.cardName === name) return deck;
  const entries = [...deck.entries];
  let printing: CardPrinting | undefined;
  let demotedSection = "deck";
  const zone = entries.findIndex((entry) => entry.cardName === name && ["commander", "commanders"].includes(board(entry)));
  const main = entries.findIndex((entry) => entry.cardName === name && ["main", "mainboard", "deck"].includes(board(entry)));
  if (zone >= 0) {
    // A partner already in the command zone takes the lead; the old lead stays there too.
    printing = StudioEntry.printing(entries.splice(zone, 1)[0]);
    demotedSection = "commanders";
  } else if (main >= 0) {
    const row = entries[main];
    printing = StudioEntry.printing(row);
    if (row.quantity > 1) entries[main] = { ...row, quantity: row.quantity - 1 }; else entries.splice(main, 1);
  }
  if (deck.commander) entries.unshift({ ...deck.commander, section: demotedSection });
  return { name: deck.name, commander: StudioEntry.of(name, 1, "commanders", printing), entries };
}

/** One public deck in an Archidekt user's list. */
export interface ArchidektDeckSummary { id: number; name: string; size?: number; updatedAt?: string }

export const ArchidektDeckSummary = {
  link: (deck: ArchidektDeckSummary) => `https://archidekt.com/decks/${deck.id}`,
  /** The day it was last changed, from Archidekt's ISO timestamp. */
  updatedDay: (deck: ArchidektDeckSummary) => deck.updatedAt?.slice(0, 10),
};

/**
 * Archidekt's public deck list for a username. Archidekt staff allow use of this API
 * (https://archidekt.com/forum/thread/2832338); it runs only when the player asks, one page at a time.
 */
export function archidektDeckListEndpoint(username: string, page: number): string {
  const name = username.trim();
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(name)) throw new ResolutionError("Enter an Archidekt username: letters, numbers, dots, dashes or underscores.");
  if (!Number.isInteger(page) || page < 1 || page > 40) throw new ResolutionError("That's as many decks as one list can show.");
  return `https://archidekt.com/api/decks/v3/?ownerUsername=${name}&pageSize=50&page=${page}`;
}

/** Private and unlisted decks never appear. */
export function decodeArchidektDeckPage(text: string): { decks: ArchidektDeckSummary[]; hasMore: boolean } {
  const unreadable = () => new ResolutionError("Archidekt returned a deck list this app can't read.");
  let value: Wire;
  try { value = object(JSON.parse(text)); } catch { throw unreadable(); }
  if (!Array.isArray(value.results) || value.results.length > 200 || (value.next !== undefined && value.next !== null && typeof value.next !== "string")) throw unreadable();
  const decks = value.results.flatMap((raw): ArchidektDeckSummary[] => {
    const row = raw as Wire;
    if (typeof row !== "object" || row === null || !Number.isInteger(row.id) || typeof row.name !== "string") throw unreadable();
    if (row.private === true || row.unlisted === true || row.name.length === 0 || utf8Size(row.name) > 512) return [];
    const deck: ArchidektDeckSummary = { id: row.id as number, name: row.name };
    if (Number.isInteger(row.size)) deck.size = row.size as number;
    if (typeof row.updatedAt === "string") deck.updatedAt = row.updatedAt;
    return [deck];
  });
  return { decks, hasMore: typeof value.next === "string" };
}
