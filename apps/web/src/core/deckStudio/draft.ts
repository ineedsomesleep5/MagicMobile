/**
 * The editable deck (OnDeviceDeckEditing.swift NativeDeckDraft, DeckStudioEditorOperations.swift, DeckStudioCore.swift's
 * edit history; Android DeckDraft.kt and DeckStudioCore.kt). Lossless local draft editing, not rules validation: unknown
 * names and sections stay intact until edited, and XMage decides legality. Every operation returns a new draft.
 */
import type { DeckEntry as ListEntry, DeckList } from "../deckResolver";
import type { Catalogue } from "./catalogue";

/** CardPrinting.swift: one printing, picked for its artwork. It never reaches the engine. */
export interface CardPrinting { readonly setCode: string; readonly number: string }

export const CardPrinting = {
  /** Undefined unless both parts are ones the app can ask Scryfall for exactly. */
  of(set: string, number: string): CardPrinting | undefined {
    const code = set.trim().toLowerCase();
    const value = number.trim();
    return /^[a-z0-9]{2,6}$/.test(code) && /^[A-Za-z0-9★†-]{1,16}$/u.test(value) ? { setCode: code, number: value } : undefined;
  },
  /** "(CMM) 400" or "(cmm) 400" at the end of a deck-list line; a set code with no number names no one printing. */
  parseSuffix(suffix: string): CardPrinting | undefined {
    const text = suffix.replace(/^[ \t]+|[ \t]+$/g, "");
    if (!text.startsWith("(")) return undefined;
    const close = text.indexOf(")");
    return close < 0 ? undefined : CardPrinting.of(text.slice(1, close), text.slice(close + 1));
  },
  /** "set/number". */
  key: (printing: CardPrinting) => `${printing.setCode}/${printing.number}`,
  /** "(CMM) 400", as exports write it. */
  exportSuffix: (printing: CardPrinting) => `(${printing.setCode.toUpperCase()}) ${printing.number}`,
  /** "CMM 400". */
  label: (printing: CardPrinting) => `${printing.setCode.toUpperCase()} ${printing.number}`,
};

/** Models.swift DeckEntry, the shape decks.json saves (`setCode` and `collectorNumber` both or neither). */
export interface StudioEntry { cardName: string; quantity: number; section: string; setCode?: string; collectorNumber?: string }
/** Models.swift DeckList: the primary commander apart, partners and other boards in `entries`. */
export interface StudioDeck { name: string; commander?: StudioEntry; entries: StudioEntry[] }

export const StudioEntry = {
  printing: (entry: StudioEntry) => (entry.setCode !== undefined && entry.collectorNumber !== undefined
    ? CardPrinting.of(entry.setCode, entry.collectorNumber) : undefined),
  of(cardName: string, quantity: number, section: string, printing?: CardPrinting): StudioEntry {
    return printing ? { cardName, quantity, section, setCode: printing.setCode, collectorNumber: printing.number } : { cardName, quantity, section };
  },
};

export const totalCards = (deck: StudioDeck) => (deck.commander?.quantity ?? 0) + deck.entries.reduce((sum, entry) => sum + entry.quantity, 0);

/** NativeDeckRow. `isPrimaryCommander` clears when the player explicitly moves the row. */
export interface DraftRow {
  readonly id: string;
  readonly cardName: string;
  readonly quantity: number;
  readonly section: string;
  readonly isPrimaryCommander: boolean;
  /** The art the player chose; unset shows the default artwork. Replacing the card clears it. */
  readonly printing?: CardPrinting;
}
export interface DeckDraft { readonly name: string; readonly rows: readonly DraftRow[] }

export type DeckEditingErrorCode = "invalidName" | "invalidEntry" | "multiplePrimaryCommanders" | "oversizedJSON" | "missingEntry";

/** OnDeviceDeckEditing.Error; the messages match the phones. */
export class DeckEditingError extends Error {
  static readonly messages: Record<DeckEditingErrorCode, string> = {
    invalidName: "Give this draft a nonempty name of at most 512 UTF-8 bytes.",
    invalidEntry: "Card names and sections must be nonempty and at most 2,000 UTF-8 bytes. Quantities must be 1–2,000, with at most 2,000 cards total.",
    multiplePrimaryCommanders: "Only one row may be marked as the primary commander. Keep partners in the commander section.",
    oversizedJSON: "Draft JSON must be at most 2 MiB.",
    missingEntry: "That card row changed. Reopen the draft.",
  };
  constructor(readonly code: DeckEditingErrorCode) { super(DeckEditingError.messages[code]); }
}

export const utf8Size = (text: string) => new TextEncoder().encode(text).length;
const blank = (text: string) => text.trim().length === 0;
let counter = 0;
const newID = () => globalThis.crypto?.randomUUID?.() ?? `row-${Date.now().toString(36)}-${(counter += 1)}`;

export const defaultDraftName = "New Commander Deck";
export const basicLandNames = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"] as const;

export function newRow(fields: Partial<DraftRow> & { cardName: string }): DraftRow {
  return { id: newID(), quantity: 1, section: "deck", isPrimaryCommander: false, ...fields };
}

export function emptyDraft(name = defaultDraftName): DeckDraft { return { name, rows: [] }; }

/** Swift's draft equality, for the edit history. */
export function draftsEqual(a: DeckDraft, b: DeckDraft): boolean {
  if (a === b) return true;
  if (a.name !== b.name || a.rows.length !== b.rows.length) return false;
  return a.rows.every((row, index) => {
    const other = b.rows[index];
    return row.id === other.id && row.cardName === other.cardName && row.quantity === other.quantity && row.section === other.section
      && row.isPrimaryCommander === other.isPrimaryCommander && row.printing?.setCode === other.printing?.setCode
      && row.printing?.number === other.printing?.number;
  });
}

function validateEntry(entry: StudioEntry): void {
  if (!Number.isInteger(entry.quantity) || entry.quantity < 1 || entry.quantity > 2000 || utf8Size(entry.cardName) > 2000
    || utf8Size(entry.section) > 2000 || blank(entry.cardName) || blank(entry.section)) throw new DeckEditingError("invalidEntry");
}

/** OnDeviceDeckEditing.validateDraft. */
export function validateDeck(deck: StudioDeck): void {
  if (utf8Size(deck.name) > 512 || blank(deck.name)) throw new DeckEditingError("invalidName");
  if (deck.commander) validateEntry(deck.commander);
  let count = deck.commander?.quantity ?? 0;
  for (const entry of deck.entries) {
    validateEntry(entry);
    if (entry.quantity > 2000 - count) throw new DeckEditingError("invalidEntry");
    count += entry.quantity;
  }
}

/** NativeDeckDraft.deck(): the marked row, else the first commander-section row, is the primary commander. Validates. */
export function draftDeck(draft: DeckDraft): StudioDeck {
  const marked = draft.rows.flatMap((row, index) => (row.isPrimaryCommander ? [index] : []));
  if (marked.length > 1) throw new DeckEditingError("multiplePrimaryCommanders");
  const primary = marked[0] ?? draft.rows.findIndex((row) => ["commander", "commanders"].includes(row.section.trim().toLowerCase()));
  let commander: StudioEntry | undefined;
  const entries: StudioEntry[] = [];
  draft.rows.forEach((row, index) => {
    const entry = StudioEntry.of(row.cardName, row.quantity, row.section, row.printing);
    if (index === primary) commander = entry; else entries.push(entry);
  });
  const deck: StudioDeck = commander ? { name: draft.name, commander, entries } : { name: draft.name, entries };
  validateDeck(deck);
  return deck;
}

/** NativeDeckDraft(deck:). */
export function draftFromDeck(deck: StudioDeck): DeckDraft {
  const row = (entry: StudioEntry, primary: boolean) => newRow({ cardName: entry.cardName, quantity: entry.quantity, section: entry.section,
    isPrimaryCommander: primary, printing: StudioEntry.printing(entry) });
  return { name: deck.name, rows: [...(deck.commander ? [row(deck.commander, true)] : []), ...deck.entries.map((entry) => row(entry, false))] };
}

/** The DeckList the resolver and the menus read: commanders first in "commanders", main-deck rows in "deck", other boards normalized. */
export function draftToDeckList(draft: DeckDraft, id: string): DeckList {
  const entries: ListEntry[] = draft.rows.map((row) => ({ name: row.cardName, quantity: row.quantity, section: DraftPresentation.section(row) }));
  return { id, name: draft.name, entries: [...entries.filter((e) => e.section === "commanders"), ...entries.filter((e) => e.section !== "commanders")] };
}

/** A DeckList back to a draft: its first "commanders" entry is the primary commander. */
export function draftFromDeckList(list: DeckList): DeckDraft {
  const lead = list.entries.findIndex((entry) => DraftPresentation.normalizedSection(entry.section) === "commanders");
  return { name: list.name, rows: list.entries.map((entry, index) => newRow({ cardName: entry.name, quantity: entry.quantity,
    section: entry.section, isPrimaryCommander: index === lead })) };
}

/** DeckStudioPlayProjection: the boards XMage plays. Sideboard and maybeboard stay out; any other section needs mapping first. */
export function playProjection(deck: StudioDeck): { playing: StudioDeck; excluded: StudioEntry[] } {
  validateDeck(deck);
  const included: StudioEntry[] = [];
  const excluded: StudioEntry[] = [];
  for (const row of deck.entries) {
    const section = row.section.trim().toLowerCase();
    if (["main", "deck", "commander", "commanders", "companion", "companions"].includes(section)) included.push(row);
    else if (["sideboard", "maybeboard", "considering"].includes(section)) excluded.push(row);
    else throw new Error(`Map section '${row.section}' to Main, Commander, Companion, Sideboard or Maybeboard before validating. No cards have been discarded.`);
  }
  return { playing: { ...deck, entries: included }, excluded };
}

/** DeckStudioDraftPresentation / DeckStudioBoard: board names shared by the quick check, text diff, sample hand and bulk edits. */
export const DraftPresentation = {
  playingBoards: new Set(["deck", "commanders", "companions"]),
  /** "considering" is the maybeboard, as in the text export and the play projection. */
  normalizedSection(raw: string): string {
    const value = raw.trim().toLowerCase();
    switch (value) {
      case "deck": case "main": return "deck";
      case "commander": case "commanders": return "commanders";
      case "companion": case "companions": return "companions";
      case "maybeboard": case "considering": return "maybeboard";
      default: return value;
    }
  },
  section: (row: DraftRow) => (row.isPrimaryCommander ? "commanders" : DraftPresentation.normalizedSection(row.section)),
  commanders: (draft: DeckDraft) => draft.rows.filter((row) => DraftPresentation.section(row) === "commanders").map((row) => row.cardName),
  /** The art chosen for the first commander, which the deck's cover draws. */
  commanderPrinting: (draft: DeckDraft) => draft.rows.find((row) => DraftPresentation.section(row) === "commanders")?.printing,
  /** Main deck plus commanders. */
  gameCount: (draft: DeckDraft) => draft.rows.filter((row) => ["deck", "commanders"].includes(DraftPresentation.section(row)))
    .reduce((sum, row) => sum + row.quantity, 0),
  /** The commanders' colour identity in WUBRG order; undefined without a commander or with any unknown identity. */
  colors(draft: DeckDraft, catalogue: Catalogue | undefined): string[] | undefined {
    const commanders = DraftPresentation.commanders(draft);
    if (commanders.length === 0) return undefined;
    const union = new Set<string>();
    for (const name of commanders) {
      const identity = catalogue?.card(name)?.colorIdentity;
      if (!identity) return undefined;
      identity.forEach((color) => union.add(color));
    }
    return ["W", "U", "B", "R", "G"].filter((color) => union.has(color));
  },
};

const isMainBasicLand = (row: DraftRow, name: string) =>
  row.cardName === name && !row.isPrimaryCommander && ["deck", "main"].includes(row.section.trim().toLowerCase());

export const basicLandCount = (draft: DeckDraft, name: string) =>
  draft.rows.filter((row) => isMainBasicLand(row, name)).reduce((sum, row) => sum + row.quantity, 0);

/** A deliberate main-deck edit, never an automatic mana-base recommendation. */
export function settingBasicLandCount(draft: DeckDraft, name: string, quantity: number): DeckDraft {
  if (!(basicLandNames as readonly string[]).includes(name) || !Number.isInteger(quantity) || quantity < 0 || quantity > 2000) {
    throw new DeckEditingError("invalidEntry");
  }
  const existing = draft.rows.find((row) => isMainBasicLand(row, name));
  const kept = draft.rows.filter((row) => !isMainBasicLand(row, name));
  const updated = { ...draft, rows: quantity > 0 ? [...kept, { ...(existing ?? newRow({ cardName: name })), quantity }] : kept };
  // Check entries and count without making an unfinished name prevent editing.
  draftDeck({ ...updated, name: "Draft" });
  return updated;
}

const requireRows = (draft: DeckDraft, ids: ReadonlySet<string>) => {
  const present = new Set(draft.rows.map((row) => row.id));
  if (ids.size === 0 || [...ids].some((id) => !present.has(id))) throw new DeckEditingError("missingEntry");
};
const indexOf = (draft: DeckDraft, rowID: string) => {
  const index = draft.rows.findIndex((row) => row.id === rowID);
  if (index < 0) throw new DeckEditingError("missingEntry");
  return index;
};
const replacing = (draft: DeckDraft, index: number, row: DraftRow): DeckDraft =>
  ({ ...draft, rows: draft.rows.map((value, at) => (at === index ? row : value)) });

/** DeckStudioEditorOperations and DeckStudioEditorModel's row edits. One Undo reverses each whole operation. */
export const EditorOperations = {
  replaceCard(draft: DeckDraft, rowID: string, name: string): DeckDraft {
    const index = indexOf(draft, rowID);
    return replacing(draft, index, { ...draft.rows[index], cardName: name, printing: undefined });
  },

  replacePrimaryCommander(draft: DeckDraft, name: string, keepOld: boolean): DeckDraft {
    const rows = [...draft.rows];
    let primary = rows.findIndex((row) => row.isPrimaryCommander);
    if (primary < 0) primary = rows.findIndex((row) => ["commander", "commanders"].includes(row.section.trim().toLowerCase()));
    if (primary >= 0 && rows[primary].cardName === name) return draft;
    if (primary >= 0) {
      const old = rows[primary];
      rows[primary] = { ...old, cardName: name, quantity: 1, section: "commanders", isPrimaryCommander: true, printing: undefined };
      if (keepOld) rows.push(newRow({ cardName: old.cardName, quantity: old.quantity, section: "maybeboard", printing: old.printing }));
    } else rows.unshift(newRow({ cardName: name, section: "commanders", isPrimaryCommander: true }));
    // Explicit promotion moves one main-deck copy; partners and other boards stay intact.
    const index = rows.findIndex((row) => !row.isPrimaryCommander && row.cardName === name && ["main", "deck"].includes(row.section.trim().toLowerCase()));
    if (index >= 0) {
      // The commander keeps the art the promoted copy had.
      const commander = rows.findIndex((row) => row.isPrimaryCommander && row.cardName === name);
      if (commander >= 0 && rows[commander].printing === undefined) rows[commander] = { ...rows[commander], printing: rows[index].printing };
      if (rows[index].quantity === 1) rows.splice(index, 1); else rows[index] = { ...rows[index], quantity: rows[index].quantity - 1 };
    }
    return { ...draft, rows };
  },

  /** Every basic land's main-deck count at once; reductions apply first so the 2,000-card cap never blocks a swap. */
  setBasicLands(draft: DeckDraft, quantities: Readonly<Record<string, number>>): DeckDraft {
    const keys = Object.keys(quantities);
    if (keys.length !== basicLandNames.length || !basicLandNames.every((name) => keys.includes(name))) throw new DeckEditingError("invalidEntry");
    let candidate = draft;
    for (const name of basicLandNames) {
      if (quantities[name] < basicLandCount(candidate, name)) candidate = settingBasicLandCount(candidate, name, quantities[name]);
    }
    for (const name of basicLandNames) candidate = settingBasicLandCount(candidate, name, quantities[name]);
    return candidate;
  },

  /** Adds `quantity` copies to an existing row on the same board, or appends one row. */
  addCopies(draft: DeckDraft, name: string, section: string, quantity: number): DeckDraft {
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 2000 || blank(name)) throw new DeckEditingError("invalidEntry");
    const board = DraftPresentation.normalizedSection(section);
    const index = draft.rows.findIndex((row) => row.cardName === name && DraftPresentation.section(row) === board);
    if (index < 0) return { ...draft, rows: [...draft.rows, newRow({ cardName: name, quantity, section })] };
    return replacing(draft, index, { ...draft.rows[index], quantity: draft.rows[index].quantity + quantity });
  },

  /** One more copy, from a card search or a row's plus (DeckStudioEditorModel.add). */
  addOne: (draft: DeckDraft, name: string, section = "deck") => EditorOperations.addCopies(draft, name, section, 1),

  /** One fewer copy of the last matching row on that board; a row that reaches zero is removed. */
  removeOne(draft: DeckDraft, name: string, section: string): DeckDraft {
    const board = DraftPresentation.normalizedSection(section);
    const row = [...draft.rows].reverse().find((value) => value.cardName === name && DraftPresentation.section(value) === board);
    return row ? EditorOperations.changeQuantity(draft, row.id, -1) : draft;
  },

  /** A row's plus or minus (DeckStudioEditorModel.quantity(id:delta:)). */
  changeQuantity(draft: DeckDraft, rowID: string, delta: number): DeckDraft {
    const index = indexOf(draft, rowID);
    const next = draft.rows[index].quantity + delta;
    if (next <= 0) return { ...draft, rows: draft.rows.filter((_, at) => at !== index) };
    return replacing(draft, index, { ...draft.rows[index], quantity: next });
  },

  /** The art a row shows; undefined returns it to the card's default art. */
  setPrinting(draft: DeckDraft, rowID: string, printing: CardPrinting | undefined): DeckDraft {
    const index = indexOf(draft, rowID);
    return replacing(draft, index, { ...draft.rows[index], printing });
  },

  /** Commander-first new decks: the chosen card leads, and an untouched default name becomes the commander's name. */
  startWithCommander(draft: DeckDraft, name: string): DeckDraft {
    const next = EditorOperations.replacePrimaryCommander(draft, name, false);
    const current = draft.name.trim();
    return current.length === 0 || current === defaultDraftName ? { ...next, name: [...name].slice(0, 96).join("") } : next;
  },

  /** An explicit move clears the primary-commander mark. Bulk edits need every selected row to still exist. */
  moveRows(draft: DeckDraft, ids: ReadonlySet<string>, section: string): DeckDraft {
    requireRows(draft, ids);
    return { ...draft, rows: draft.rows.map((row) => (ids.has(row.id) ? { ...row, section, isPrimaryCommander: false } : row)) };
  },

  setQuantity(draft: DeckDraft, ids: ReadonlySet<string>, quantity: number): DeckDraft {
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 2000) throw new DeckEditingError("invalidEntry");
    requireRows(draft, ids);
    return { ...draft, rows: draft.rows.map((row) => (ids.has(row.id) ? { ...row, quantity } : row)) };
  },

  removeRows(draft: DeckDraft, ids: ReadonlySet<string>): DeckDraft {
    requireRows(draft, ids);
    return { ...draft, rows: draft.rows.filter((row) => !ids.has(row.id)) };
  },

  /** Copies of a name, on one board or all (DeckStudioEditorModel.cardCount). */
  cardCount(draft: DeckDraft, name: string, section?: string): number {
    const board = section === undefined ? undefined : DraftPresentation.normalizedSection(section);
    return draft.rows.filter((row) => row.cardName === name && (board === undefined || DraftPresentation.section(row) === board))
      .reduce((sum, row) => sum + row.quantity, 0);
  },
};

/**
 * DeckStudioEditHistory: bounded whole-draft transactions. A failed edit never partially updates state, and the
 * generation advances on undo and redo too, so an old async reply cannot validate a new revision.
 */
export class EditHistory<T> {
  private static generations = 0;
  private constructor(
    readonly value: T, readonly baseline: T, readonly generation: number,
    private readonly past: readonly T[], private readonly future: readonly T[], private readonly limit: number,
    private readonly equals: (a: T, b: T) => boolean,
  ) {}

  static of<T>(value: T, equals: (a: T, b: T) => boolean = Object.is, limit = 64): EditHistory<T> {
    return new EditHistory(value, value, EditHistory.next(), [], [], Math.max(1, Math.min(limit, 256)), equals);
  }

  private static next() { EditHistory.generations += 1; return EditHistory.generations; }

  get isDirty() { return !this.equals(this.value, this.baseline); }
  get canUndo() { return this.past.length > 0; }
  get canRedo() { return this.future.length > 0; }

  /** Throws when the operation does; an unchanged value is no step. */
  edited(operation: (value: T) => T): EditHistory<T> {
    const next = operation(this.value);
    if (this.equals(next, this.value)) return this;
    return new EditHistory(next, this.baseline, EditHistory.next(), [...this.past, this.value].slice(-this.limit), [], this.limit, this.equals);
  }
  undone(): EditHistory<T> {
    if (this.past.length === 0) return this;
    return new EditHistory(this.past[this.past.length - 1], this.baseline, EditHistory.next(), this.past.slice(0, -1),
      [...this.future, this.value], this.limit, this.equals);
  }
  redone(): EditHistory<T> {
    if (this.future.length === 0) return this;
    return new EditHistory(this.future[this.future.length - 1], this.baseline, EditHistory.next(), [...this.past, this.value],
      this.future.slice(0, -1), this.limit, this.equals);
  }
  saved(): EditHistory<T> { return new EditHistory(this.value, this.value, this.generation, this.past, this.future, this.limit, this.equals); }
  /** Restoration is one undoable edit and is still dirty relative to the saved deck. */
  restored(recovered: T): EditHistory<T> { return this.edited(() => recovered); }
}

/** The editor's history of drafts. */
export const draftHistory = (draft: DeckDraft) => EditHistory.of(draft, draftsEqual);

/** DeckStudioEditorModel.change: one undo step, committed only when the draft still validates (under a placeholder name). */
export function changeDraft(history: EditHistory<DeckDraft>, operation: (draft: DeckDraft) => DeckDraft): EditHistory<DeckDraft> {
  return history.edited((value) => {
    const next = operation(value);
    draftDeck({ ...next, name: "Draft" });
    return next;
  });
}

/**
 * Quick Add grammar (DeckStudioQuickAdd): an optional count ("2 " or "2x "), then the card name. A trailing printing
 * "(set)" / "(set) 123" and "[tag]" are ignored and reported.
 */
export interface QuickAdd { quantity: number; name: string; ignored: string[] }

export const QuickAdd = {
  note: (value: QuickAdd) => (value.ignored.length === 0 ? null : `Ignored ${value.ignored.join(" ")} · sets and tags aren't saved`),

  /** Null while there is nothing to add yet or the count is out of range. An exact card name that starts with a number wins over the count. */
  parse(raw: string, isCardName: (name: string) => boolean = () => false): QuickAdd | null {
    let text = raw.trim();
    if (text.length === 0 || utf8Size(text) > 2000) return null;
    const ignored: string[] = [];
    const decoration = /\s*(?:\[[^[\]]*\]|\([A-Za-z0-9]{2,6}\)(?:\s+[A-Za-z0-9★†-]+)?)$/u;
    for (let match = decoration.exec(text); match; match = decoration.exec(text)) {
      ignored.unshift(match[0].replace(/^[ \t]+|[ \t]+$/g, ""));
      text = text.slice(0, match.index).replace(/^[ \t]+|[ \t]+$/g, "");
    }
    if (text.length === 0) return null;
    if (isCardName(text)) return { quantity: 1, name: text, ignored };
    // A count with no name yet ("2x") is still being typed.
    if (/^[0-9]{1,4}[xX]?$/.test(text)) return null;
    let quantity = 1;
    const count = /^[0-9]{1,4}[xX]?\s+/.exec(text);
    if (count) {
      const value = Number.parseInt(count[0].trim().replace(/[xX]$/, ""), 10);
      if (!(value >= 1 && value <= 2000)) return null;
      quantity = value;
      text = text.slice(count[0].length).replace(/^[ \t]+|[ \t]+$/g, "");
    }
    return text.length === 0 ? null : { quantity, name: text, ignored };
  },
};
