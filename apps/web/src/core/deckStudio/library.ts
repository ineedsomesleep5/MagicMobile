/**
 * Your saved decks (iOS DeckLibrary.swift, DeckLibraryStore): records kept in this browser as the phone keeps
 * `decks.json`, in the same JSON shape (`cardName`, `source: {kind, url}`, ISO dates), so a library can move between
 * them unchanged. Every save checks the record's revision and that nothing else (another tab) rewrote the library since
 * it was read; an unreadable library is never replaced. Saving is draft persistence only: XMage decides legality.
 */
import type { DeckEntry as ListEntry, DeckList } from "../deckResolver";
import type { KeyValueStore } from "../playerRecord";

/** A row as the phones save it; `setCode` and `collectorNumber` (both or neither) are the art the player chose. */
export interface LibraryEntry { cardName: string; quantity: number; section: string; setCode?: string; collectorNumber?: string }

export interface DeckLibraryRecord {
  id: string;
  name: string;
  format: string;
  commander?: LibraryEntry;
  entries: LibraryEntry[];
  sourceURL?: string;
  revision: number;
  /** Milliseconds since 1970. */
  updatedAt: number;
  isCloudBacked: boolean;
}

/** What the editor hands back to be saved: the deck without its record's bookkeeping. */
export interface LibraryDeck { name: string; commander?: LibraryEntry; entries: LibraryEntry[] }

export type LibraryErrorCode = "invalidName" | "invalidEntry" | "missingRecord" | "staleRevision" | "copyRequired" | "unreadableCache" | "notKept";

/** OnDeviceDeckEditing.Error's words. */
export class LibraryError extends Error {
  static readonly messages: Record<LibraryErrorCode, string> = {
    invalidName: "Give this draft a nonempty name of at most 512 UTF-8 bytes.",
    invalidEntry: "Card names and sections must be nonempty and at most 2,000 UTF-8 bytes. Quantities must be 1–2,000, with at most 2,000 cards total.",
    missingRecord: "That saved deck no longer exists.",
    staleRevision: "The saved library changed. Reopen it before saving again.",
    copyRequired: "Make a local editing copy of this cloud deck first.",
    unreadableCache: "The saved library is unreadable. Preserve it before recovery.",
    notKept: "This browser didn't keep the deck. Allow site data for this page, or free some space, and save again.",
  };
  constructor(readonly code: LibraryErrorCode) { super(LibraryError.messages[code]); }
}

const bytes = (text: string) => new TextEncoder().encode(text).length;
const blank = (text: string) => text.trim().length === 0;

/** OnDeviceDeckEditing.validateDraft. */
export function validateDeck(deck: LibraryDeck): void {
  if (bytes(deck.name) > 512 || blank(deck.name)) throw new LibraryError("invalidName");
  const check = (entry: LibraryEntry) => {
    if (!Number.isInteger(entry.quantity) || entry.quantity < 1 || entry.quantity > 2000 || bytes(entry.cardName) > 2000
      || bytes(entry.section) > 2000 || blank(entry.cardName) || blank(entry.section)) throw new LibraryError("invalidEntry");
  };
  if (deck.commander) check(deck.commander);
  let count = deck.commander?.quantity ?? 0;
  for (const entry of deck.entries) {
    check(entry);
    if (entry.quantity > 2000 - count) throw new LibraryError("invalidEntry");
    count += entry.quantity;
  }
}

export const DeckLibraryRecord = {
  /** The selection id the menus and the record use for a saved deck (AIDeckPool's `local:`). */
  selectionID: (record: Pick<DeckLibraryRecord, "id">) => `local:${record.id}`,
  /**
   * An included deck as a record that is never saved (DeckLibraryRecord(deck:id:)): its first commander row leads, other
   * commander rows (partners) stay in the commander section. Duplicating it makes your own copy.
   */
  fromDeckList(list: DeckList, id: string, sourceURL?: string): DeckLibraryRecord {
    const isCommander = (section: string) => /^commanders?$/i.test(section.trim());
    const first = list.entries.find((entry) => isCommander(entry.section));
    return {
      id, name: list.name, format: "commander",
      ...(first ? { commander: { cardName: first.name, quantity: first.quantity, section: "commander" } } : {}),
      entries: list.entries.filter((entry) => entry !== first).map((entry) => ({
        cardName: entry.name, quantity: entry.quantity, section: isCommander(entry.section) ? "commander" : entry.section,
      })),
      ...(sourceURL !== undefined ? { sourceURL } : {}), revision: 1, updatedAt: 0, isCloudBacked: true,
    };
  },
  cardCount: (record: LibraryDeck) => (record.commander?.quantity ?? 0) + record.entries.reduce((sum, entry) => sum + entry.quantity, 0),
  /** The deck as the engine's resolver reads it: the commander first in "commanders", then each row in its section. */
  deckList(record: DeckLibraryRecord): DeckList {
    const entries: ListEntry[] = [
      ...(record.commander ? [{ name: record.commander.cardName, quantity: record.commander.quantity, section: "commanders" }] : []),
      ...record.entries.map((entry) => ({ name: entry.cardName, quantity: entry.quantity, section: entry.section })),
    ];
    return { id: DeckLibraryRecord.selectionID(record), name: record.name, entries };
  },
};

type Wire = Record<string, unknown>;

function entryFromWire(value: unknown): LibraryEntry | undefined {
  if (typeof value !== "object" || value === null) return undefined;
  const row = value as Wire;
  if (typeof row.cardName !== "string" || typeof row.quantity !== "number" || typeof row.section !== "string") return undefined;
  const entry: LibraryEntry = { cardName: row.cardName, quantity: row.quantity, section: row.section };
  // A damaged art choice shows default art rather than failing the deck.
  if (typeof row.setCode === "string" && typeof row.collectorNumber === "string") { entry.setCode = row.setCode; entry.collectorNumber = row.collectorNumber; }
  return entry;
}

/** DeckLibraryRecord.init(from:): missing fields take the phone's defaults; a record without a name is unreadable. */
function recordFromWire(value: unknown): DeckLibraryRecord {
  if (typeof value !== "object" || value === null) throw new LibraryError("unreadableCache");
  const row = value as Wire;
  if (typeof row.name !== "string") throw new LibraryError("unreadableCache");
  const source = typeof row.source === "object" && row.source !== null ? (row.source as Wire) : undefined;
  const sourceURL = typeof row.sourceURL === "string" ? row.sourceURL : typeof source?.url === "string" ? source.url : undefined;
  const date = typeof row.updatedAt === "string" ? Date.parse(row.updatedAt) : NaN;
  const commander = entryFromWire(row.commander);
  return {
    id: typeof row.id === "string" ? row.id : crypto.randomUUID().toUpperCase(),
    name: row.name,
    format: typeof row.format === "string" ? row.format : "commander",
    ...(commander ? { commander } : {}),
    entries: Array.isArray(row.entries) ? row.entries.flatMap((entry) => entryFromWire(entry) ?? []) : [],
    ...(sourceURL !== undefined ? { sourceURL } : {}),
    revision: typeof row.revision === "number" ? row.revision : 1,
    updatedAt: Number.isNaN(date) ? 0 : date,
    isCloudBacked: typeof row.isCloudBacked === "boolean" ? row.isCloudBacked : true,
  };
}

/** What deck sync carries (docs/DECK_SYNC.md): the record's wire shape without its id, name and bookkeeping. */
export interface DeckDocument { format: string; commander?: LibraryEntry; entries: LibraryEntry[]; source: { kind: string; url?: string } }

export const DeckDocument = {
  of(record: DeckLibraryRecord): DeckDocument {
    const wire = recordToWire(record);
    return { format: record.format, ...(record.commander ? { commander: record.commander } : {}), entries: record.entries, source: wire.source as DeckDocument["source"] };
  },
  /** A server document as a library deck; undefined when it isn't one. */
  read(name: string, value: unknown): (LibraryDeck & { format: string; sourceURL?: string }) | undefined {
    try {
      const record = recordFromWire({ ...(typeof value === "object" && value !== null ? value : {}), name, id: "x" });
      return { name: record.name, format: record.format, ...(record.commander ? { commander: record.commander } : {}), entries: record.entries,
        ...(record.sourceURL !== undefined ? { sourceURL: record.sourceURL } : {}) };
    } catch { return undefined; }
  },
  /** The same name and document: the sync's "already equal" test. */
  same(record: DeckLibraryRecord, name: string, document: unknown): boolean {
    return record.name === name && canonical(DeckDocument.of(record)) === canonical(document);
  },
};

/** JSON with sorted keys, so equal documents compare equal whatever their key order. */
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (typeof value === "object" && value !== null) {
    return `{${Object.keys(value).filter((k) => (value as Wire)[k] !== undefined).sort().map((k) => `${JSON.stringify(k)}:${canonical((value as Wire)[k])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function recordToWire(record: DeckLibraryRecord): Wire {
  const kind = record.sourceURL === undefined ? "manual" : /archidekt/i.test(record.sourceURL) ? "archidekt" : "moxfield";
  return {
    id: record.id, name: record.name, format: record.format,
    ...(record.commander ? { commander: record.commander } : {}),
    entries: record.entries,
    source: record.sourceURL === undefined ? { kind } : { kind, url: record.sourceURL },
    revision: record.revision, updatedAt: new Date(record.updatedAt).toISOString(), isCloudBacked: record.isCloudBacked,
  };
}

/** DeckLibraryStore over a key-value store; `changed` runs after every save so the menus redraw. */
export class DeckLibrary {
  static readonly key = "mm.web.decks";
  static readonly favoritesKey = "mm.web.decks.favorites";
  /** Each deck's colours, worked out from the catalogue when it was saved, so the menus need no catalogue to draw it. */
  static readonly colorsKey = "mm.web.decks.colors";

  private records: DeckLibraryRecord[] = [];
  private baseline: string | undefined;
  private readFailed = false;
  private favoriteIDs = new Set<string>();
  private colorMemo: Record<string, string[]> = {};
  /** Set when the saved library couldn't be read; it is left as it was. */
  notice: string | undefined;
  /** Runs after the player deletes a deck (deck sync keeps a tombstone for it). */
  onDeleted?: (record: DeckLibraryRecord) => void;

  constructor(private readonly store: KeyValueStore, private readonly now: () => number = Date.now) {
    this.reload();
  }

  get decks(): readonly DeckLibraryRecord[] { return this.records; }
  record(id: string): DeckLibraryRecord | undefined { return this.records.find((record) => record.id === id); }
  /** A deck by id ignoring case: the server answers ids in lower case, the phones make them upper case. */
  recordMatching(id: string): DeckLibraryRecord | undefined {
    const key = id.toLowerCase();
    return this.records.find((record) => record.id.toLowerCase() === key);
  }
  /** A saved deck by its menu selection id (`local:<id>`). */
  bySelection(selection: string): DeckLibraryRecord | undefined {
    return selection.startsWith("local:") ? this.record(selection.slice(6)) : undefined;
  }

  /** Reads the library again (another tab may have saved). */
  reload(): void {
    const raw = this.store.get(DeckLibrary.key) ?? undefined;
    this.readFailed = false; this.notice = undefined;
    if (raw === undefined) { this.records = []; this.baseline = undefined; }
    else {
      try {
        const parsed: unknown = JSON.parse(raw);
        if (!Array.isArray(parsed)) throw new LibraryError("unreadableCache");
        this.records = parsed.map(recordFromWire);
        this.baseline = raw;
      } catch {
        this.records = []; this.readFailed = true;
        this.notice = "The saved deck library could not be read. It has not been replaced.";
      }
    }
    try {
      const favorites: unknown = JSON.parse(this.store.get(DeckLibrary.favoritesKey) ?? "[]");
      this.favoriteIDs = new Set(Array.isArray(favorites) ? favorites.filter((id): id is string => typeof id === "string") : []);
    } catch { this.favoriteIDs = new Set(); }
    try {
      const colors: unknown = JSON.parse(this.store.get(DeckLibrary.colorsKey) ?? "{}");
      this.colorMemo = typeof colors === "object" && colors !== null && !Array.isArray(colors) ? (colors as Record<string, string[]>) : {};
    } catch { this.colorMemo = {}; }
  }

  /** The colours remembered for a deck (WUBRG letters), empty until the builder or an import has seen it. */
  colors(id: string): string[] {
    const value = this.colorMemo[id];
    return Array.isArray(value) ? value.filter((c) => typeof c === "string") : [];
  }
  rememberColors(id: string, colors: readonly string[]): void {
    if (this.colors(id).join("") === colors.join("")) return;
    this.colorMemo = { ...this.colorMemo, [id]: [...colors] };
    this.store.set(DeckLibrary.colorsKey, JSON.stringify(this.colorMemo));
  }

  add(deck: LibraryDeck, sourceURL?: string): DeckLibraryRecord {
    validateDeck(deck);
    const record: DeckLibraryRecord = {
      id: crypto.randomUUID().toUpperCase(), name: deck.name, format: "commander", ...(deck.commander ? { commander: deck.commander } : {}),
      entries: deck.entries, ...(sourceURL !== undefined ? { sourceURL } : {}), revision: 1, updatedAt: this.now(), isCloudBacked: false,
    };
    this.persist([record, ...this.records]);
    return record;
  }

  update(id: string, deck: LibraryDeck, expectedRevision: number): DeckLibraryRecord {
    validateDeck(deck);
    const index = this.index(id, expectedRevision);
    const old = this.records[index];
    const record: DeckLibraryRecord = {
      ...old, name: deck.name, commander: deck.commander, entries: deck.entries, revision: old.revision + 1, updatedAt: this.now(),
    };
    if (!record.commander) delete record.commander;
    const next = [...this.records]; next[index] = record;
    this.persist(next);
    return record;
  }

  delete(id: string, expectedRevision?: number): void {
    const record = this.record(id);
    if (!record) throw new LibraryError("missingRecord");
    const index = this.index(id, expectedRevision ?? record.revision);
    this.persist(this.records.filter((_, i) => i !== index));
    this.onDeleted?.(record);
    if (this.favoriteIDs.delete(DeckLibraryRecord.selectionID(record))) this.saveFavorites();
    if (id in this.colorMemo) {
      const { [id]: _gone, ...rest } = this.colorMemo;
      this.colorMemo = rest;
      this.store.set(DeckLibrary.colorsKey, JSON.stringify(rest));
    }
  }

  /** A copy keeps the source link but is always a local deck with a new identity. */
  duplicate(record: DeckLibraryRecord, name: string): DeckLibraryRecord {
    const deck: LibraryDeck = { name, ...(record.commander ? { commander: record.commander } : {}), entries: record.entries };
    validateDeck(deck);
    const copy: DeckLibraryRecord = {
      id: crypto.randomUUID().toUpperCase(), name, format: record.format, ...(deck.commander ? { commander: deck.commander } : {}),
      entries: deck.entries, ...(record.sourceURL !== undefined ? { sourceURL: record.sourceURL } : {}), revision: 1,
      updatedAt: this.now(), isCloudBacked: false,
    };
    this.persist([copy, ...this.records]);
    this.rememberColors(copy.id, this.colors(record.id));
    return copy;
  }

  /**
   * Deck sync: a server deck under its own id, replacing this device's copy (its revision moves on) or added first.
   * Answers the record as saved.
   */
  applySynced(id: string, deck: LibraryDeck & { format?: string; sourceURL?: string }): DeckLibraryRecord {
    validateDeck(deck);
    const index = this.records.findIndex((record) => record.id.toLowerCase() === id.toLowerCase());
    const old = index >= 0 ? this.records[index] : undefined;
    const record: DeckLibraryRecord = {
      id: old?.id ?? id, name: deck.name, format: deck.format ?? old?.format ?? "commander", ...(deck.commander ? { commander: deck.commander } : {}),
      entries: deck.entries, ...(deck.sourceURL !== undefined ? { sourceURL: deck.sourceURL } : {}),
      revision: (old?.revision ?? 0) + 1, updatedAt: this.now(), isCloudBacked: false,
    };
    this.persist(old ? this.records.map((r, i) => (i === index ? record : r)) : [record, ...this.records]);
    return record;
  }

  /** Deck sync: a deck deleted on another device leaves this one (no tombstone, unlike the player's delete). */
  removeSynced(id: string): void {
    const record = this.recordMatching(id);
    if (!record) return;
    this.persist(this.records.filter((r) => r !== record));
    if (this.favoriteIDs.delete(DeckLibraryRecord.selectionID(record))) this.saveFavorites();
  }

  isFavorite(selection: string): boolean { return this.favoriteIDs.has(selection); }
  setFavorite(selection: string, favorite: boolean): void {
    if (favorite) this.favoriteIDs.add(selection); else this.favoriteIDs.delete(selection);
    this.saveFavorites();
  }

  private saveFavorites() { this.store.set(DeckLibrary.favoritesKey, JSON.stringify([...this.favoriteIDs])); }

  private index(id: string, expectedRevision: number): number {
    const index = this.records.findIndex((record) => record.id === id);
    if (index < 0) throw new LibraryError("missingRecord");
    if (this.records[index].isCloudBacked) throw new LibraryError("copyRequired");
    if (this.records[index].revision !== expectedRevision) throw new LibraryError("staleRevision");
    return index;
  }

  /** Never replaces an unreadable library or one another tab saved since this one read it. */
  private persist(candidate: DeckLibraryRecord[]): void {
    if (this.readFailed) throw new LibraryError("unreadableCache");
    if ((this.store.get(DeckLibrary.key) ?? undefined) !== this.baseline) throw new LibraryError("staleRevision");
    const raw = JSON.stringify(candidate.map(recordToWire));
    this.store.set(DeckLibrary.key, raw);
    // A private window or a full store drops the write: say so instead of showing a deck that isn't kept.
    if ((this.store.get(DeckLibrary.key) ?? undefined) !== raw) throw new LibraryError("notKept");
    this.baseline = raw;
    this.records = candidate;
  }
}
