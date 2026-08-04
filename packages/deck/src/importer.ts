import type { DeckEntry, DeckImportRequest, DeckList, DeckSource } from "@magicmobile/shared";
import { PastedDeckParser } from "./parser";

const MAX_REMOTE_BYTES = 2 * 1024 * 1024;
const REMOTE_TIMEOUT_MS = 8_000;

export class DeckImportError extends Error {
  constructor(message: string, readonly status = 400) {
    super(message);
    this.name = "DeckImportError";
  }
}

export interface ImportedDeck {
  deck: DeckList;
  rawList: string;
  source: DeckSource;
}

type FetchLike = typeof fetch;

export const importDeck = async (
  request: DeckImportRequest,
  fetchImpl: FetchLike = fetch
): Promise<ImportedDeck> => {
  const sourceText = request.sourceText?.trim();
  const sourceURL = request.sourceURL?.trim();
  if (Boolean(sourceText) === Boolean(sourceURL)) {
    throw new DeckImportError("Provide exactly one of sourceText or sourceURL.");
  }

  if (sourceText) {
    if (new TextEncoder().encode(sourceText).byteLength > MAX_REMOTE_BYTES) {
      throw new DeckImportError("Deck file is larger than 2 MB.", 413);
    }
    const deck = new PastedDeckParser().parse(sourceText);
    ensureParsed(deck);
    deck.name = request.name?.trim() || filenameDeckName(request.filename) || deck.name;
    return {
      deck,
      rawList: sourceText,
      source: request.filename
        ? { kind: "file", filename: safeFilename(request.filename) }
        : { kind: "paste" }
    };
  }

  return importPublicDeck(sourceURL!, request.name, fetchImpl);
};

const importPublicDeck = async (
  sourceURL: string,
  requestedName: string | undefined,
  fetchImpl: FetchLike
): Promise<ImportedDeck> => {
  let url: URL;
  try {
    url = new URL(sourceURL);
  } catch {
    throw new DeckImportError("Deck URL is invalid.");
  }
  if (url.protocol !== "https:" || url.port) {
    throw new DeckImportError("Deck URL must use HTTPS without a custom port.");
  }

  const host = url.hostname.toLowerCase();
  if (host === "moxfield.com" || host === "www.moxfield.com") {
    const id = url.pathname.match(/^\/decks\/([A-Za-z0-9_-]+)(?:\/|$)/)?.[1];
    if (!id) throw new DeckImportError("Moxfield URL must point to a public deck.");
    const data = await fetchJson(`https://api2.moxfield.com/v2/decks/all/${encodeURIComponent(id)}`, fetchImpl);
    const deck = parseMoxfield(data);
    deck.name = requestedName?.trim() || deck.name;
    const rawList = serializeDeck(deck.entries);
    return { deck, rawList, source: { kind: "moxfield", url: canonicalURL(url) } };
  }

  if (host === "archidekt.com" || host === "www.archidekt.com") {
    const id = url.pathname.match(/^\/decks\/(\d+)(?:\/|$)/)?.[1];
    if (!id) throw new DeckImportError("Archidekt URL must point to a public deck.");
    const data = await fetchJson(`https://archidekt.com/api/decks/${id}/`, fetchImpl);
    const deck = parseArchidekt(data);
    deck.name = requestedName?.trim() || deck.name;
    const rawList = serializeDeck(deck.entries);
    return { deck, rawList, source: { kind: "archidekt", url: canonicalURL(url) } };
  }

  throw new DeckImportError("Only public Archidekt and Moxfield deck URLs are supported.");
};

const fetchJson = async (url: string, fetchImpl: FetchLike): Promise<unknown> => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REMOTE_TIMEOUT_MS);
  try {
    const response = await fetchImpl(url, {
      headers: { Accept: "application/json", "User-Agent": "MagicMobile-DeckImporter/1.0" },
      redirect: "manual",
      signal: controller.signal
    });
    if (!response.ok) {
      throw new DeckImportError(response.status === 404 ? "Public deck was not found." : "Deck provider could not be reached.", 502);
    }
    const contentLength = Number.parseInt(response.headers.get("content-length") ?? "0", 10);
    if (contentLength > MAX_REMOTE_BYTES) throw new DeckImportError("Deck provider response is too large.", 413);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength > MAX_REMOTE_BYTES) throw new DeckImportError("Deck provider response is too large.", 413);
    try {
      return JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      throw new DeckImportError("Deck provider returned invalid data.", 502);
    }
  } catch (error) {
    if (error instanceof DeckImportError) throw error;
    if (error instanceof Error && error.name === "AbortError") {
      throw new DeckImportError("Deck provider timed out.", 504);
    }
    throw new DeckImportError("Deck provider could not be reached.", 502);
  } finally {
    clearTimeout(timeout);
  }
};

const parseMoxfield = (value: unknown): DeckList => {
  const record = asRecord(value);
  const entries: DeckEntry[] = [];
  for (const [key, section] of [
    ["commanders", "commander"],
    ["mainboard", "deck"],
    ["sideboard", "sideboard"],
    ["maybeboard", "maybeboard"]
  ] as const) {
    const board = asRecord(record[key]);
    const cards = Object.keys(asRecord(board.cards)).length > 0 ? asRecord(board.cards) : board;
    for (const cardValue of Object.values(cards)) {
      const cardRecord = asRecord(cardValue);
      const card = asRecord(cardRecord.card);
      const cardName = stringValue(card.name) || stringValue(cardRecord.name);
      const quantity = numberValue(cardRecord.quantity, 1);
      if (cardName && quantity > 0) entries.push({ cardName, quantity, section });
    }
  }
  return finishProviderDeck(stringValue(record.name) || "Imported Moxfield deck", entries);
};

const parseArchidekt = (value: unknown): DeckList => {
  const record = asRecord(value);
  const cards = Array.isArray(record.cards) ? record.cards : [];
  const categoryNames = new Map<string, string>();
  for (const categoryValue of Array.isArray(record.categories) ? record.categories : []) {
    const category = asRecord(categoryValue);
    const id = String(category.id ?? "");
    const name = stringValue(category.name);
    if (id && name) categoryNames.set(id, name);
  }
  const entries: DeckEntry[] = cards.flatMap((value): DeckEntry[] => {
    const item = asRecord(value);
    const card = asRecord(item.card);
    const oracle = asRecord(card.oracleCard);
    const cardName = stringValue(oracle.name) || stringValue(card.name) || stringValue(item.name);
    const quantity = numberValue(item.quantity, 1);
    if (!cardName || quantity < 1) return [];
    const categories = (Array.isArray(item.categories) ? item.categories : [])
      .map((category) => {
        if (typeof category === "number") return categoryNames.get(String(category)) ?? "";
        if (typeof category === "string") return categoryNames.get(category) ?? category;
        return stringValue(asRecord(category).name);
      })
      .join(" ")
      .toLowerCase();
    const section: DeckEntry["section"] = categories.includes("commander")
      ? "commander"
      : categories.includes("side")
        ? "sideboard"
        : categories.includes("maybe") || categories.includes("consider")
          ? "maybeboard"
          : "deck";
    return [{ cardName, quantity, section }];
  });
  return finishProviderDeck(stringValue(record.name) || "Imported Archidekt deck", entries);
};

const finishProviderDeck = (name: string, entries: DeckEntry[]): DeckList => {
  const deck: DeckList = { name, entries };
  const commander = entries.find((entry) => entry.section === "commander");
  if (commander) deck.commander = commander;
  ensureParsed(deck);
  return deck;
};

const ensureParsed = (deck: DeckList): void => {
  if (deck.errors?.length || deck.entries.length === 0) {
    throw new DeckImportError(deck.errors?.[0] ?? "Deck contains no cards.");
  }
};

const asRecord = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
const stringValue = (value: unknown): string => typeof value === "string" ? value.trim() : "";
const numberValue = (value: unknown, fallback: number): number =>
  typeof value === "number" && Number.isFinite(value) ? Math.floor(value) : fallback;
const serializeDeck = (entries: DeckEntry[]): string => entries
  .map((entry) => `${entry.quantity} ${entry.cardName}`)
  .join("\n");
const canonicalURL = (url: URL): string => `${url.protocol}//${url.hostname}${url.pathname}`;
const safeFilename = (filename: string): string => filename.split(/[\\/]/).pop()?.slice(0, 255) || "deck.txt";
const filenameDeckName = (filename: string | undefined): string | undefined => {
  if (!filename) return undefined;
  return safeFilename(filename).replace(/\.(?:txt|dec|csv)$/i, "").trim() || undefined;
};
