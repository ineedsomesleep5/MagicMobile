import type { CreateDeckInput, DeckEntry, DeckSource, UpdateDeckInput } from "@magicmobile/shared";

const SECTIONS = new Set<DeckEntry["section"]>(["commander", "deck", "sideboard", "maybeboard"]);
const SOURCES = new Set<DeckSource["kind"]>(["manual", "paste", "file", "archidekt", "moxfield"]);

export class DeckRequestError extends Error {
  constructor(message: string, readonly status = 400) {
    super(message);
    this.name = "DeckRequestError";
  }
}

export const parseCreateDeckInput = (value: unknown): CreateDeckInput => {
  const record = asRecord(value);
  const name = requiredString(record.name, "Deck name", 100);
  const entries = parseEntries(record.entries);
  const commander = record.commander === undefined ? entries.find((entry) => entry.section === "commander") : parseEntry(record.commander);
  const rawList = optionalString(record.rawList, "Raw deck list", 2 * 1024 * 1024);
  const source = record.source === undefined ? { kind: "manual" as const } : parseSource(record.source);
  return { name, entries, ...(commander ? { commander } : {}), ...(rawList !== undefined ? { rawList } : {}), source };
};

export const parseUpdateDeckInput = (value: unknown): UpdateDeckInput => {
  const record = asRecord(value);
  const revision = typeof record.revision === "number" ? Math.floor(record.revision) : Number.NaN;
  if (!Number.isSafeInteger(revision) || revision < 1) throw new DeckRequestError("A valid deck revision is required.");
  const input: UpdateDeckInput = { revision };
  if (record.name !== undefined) input.name = requiredString(record.name, "Deck name", 100);
  if (record.entries !== undefined) input.entries = parseEntries(record.entries);
  if (record.commander !== undefined) input.commander = parseEntry(record.commander);
  if (record.rawList !== undefined) {
    const rawList = optionalString(record.rawList, "Raw deck list", 2 * 1024 * 1024);
    if (rawList !== undefined) input.rawList = rawList;
  }
  if (record.source !== undefined) input.source = parseSource(record.source);
  if (Object.keys(input).length === 1) throw new DeckRequestError("Provide at least one deck field to update.");
  return input;
};

const parseEntries = (value: unknown): DeckEntry[] => {
  if (!Array.isArray(value) || value.length === 0) throw new DeckRequestError("Deck entries are required.");
  if (value.length > 2_000) throw new DeckRequestError("Deck contains too many entries.");
  return value.map(parseEntry);
};

const parseEntry = (value: unknown): DeckEntry => {
  const record = asRecord(value);
  const cardName = requiredString(record.cardName, "Card name", 200);
  const quantity = typeof record.quantity === "number" ? Math.floor(record.quantity) : Number.NaN;
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 1_000) {
    throw new DeckRequestError(`Invalid quantity for ${cardName}.`);
  }
  if (!SECTIONS.has(record.section as DeckEntry["section"])) throw new DeckRequestError(`Invalid section for ${cardName}.`);
  return { cardName, quantity, section: record.section as DeckEntry["section"] };
};

const parseSource = (value: unknown): DeckSource => {
  const record = asRecord(value);
  if (!SOURCES.has(record.kind as DeckSource["kind"])) throw new DeckRequestError("Invalid deck source.");
  const source: DeckSource = { kind: record.kind as DeckSource["kind"] };
  if (record.url !== undefined) source.url = requiredString(record.url, "Source URL", 2_000);
  if (record.filename !== undefined) source.filename = requiredString(record.filename, "Source filename", 255);
  return source;
};

const asRecord = (value: unknown): Record<string, unknown> => {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new DeckRequestError("Request body must be a JSON object.");
  return value as Record<string, unknown>;
};
const requiredString = (value: unknown, label: string, max: number): string => {
  if (typeof value !== "string" || !value.trim()) throw new DeckRequestError(`${label} is required.`);
  if (value.trim().length > max) throw new DeckRequestError(`${label} is too long.`);
  return value.trim();
};
const optionalString = (value: unknown, label: string, max: number): string | undefined => {
  if (value === undefined) return undefined;
  if (typeof value !== "string") throw new DeckRequestError(`${label} must be text.`);
  if (value.length > max) throw new DeckRequestError(`${label} is too long.`, 413);
  return value;
};
