/**
 * Deck text and JSON exchange: OnDeviceDeckEditing.importText / exportJSON / importJSON, DeckStudioTextExport and
 * DeckStudioTextDiff (DeckStudioTextExport.swift; Android DeckDraft.kt and DeckStudioCore.kt).
 */
import {
  CardPrinting, DeckEditingError, draftDeck, draftFromDeck, DraftPresentation, StudioEntry, utf8Size, validateDeck,
  type DeckDraft, type StudioDeck,
} from "./draft";

export const maximumJSONBytes = 2 * 1024 * 1024;

export interface TextAnnotation { line: number; text: string }
export interface TextImport { deck: StudioDeck; annotations: TextAnnotation[] }

export class TextImportError extends Error {
  constructor(readonly line: number, readonly reason: string) { super(`Line ${line}: ${reason} No cards were imported.`); }
}

/** Swift `trimmingCharacters(in: .whitespaces)`: spaces and tabs, not line breaks. */
const trimSpaces = (text: string) => text.replace(/^[\t\p{Zs}]+|[\t\p{Zs}]+$/gu, "");

function sectionName(heading: string): string | undefined {
  switch (heading.toLowerCase()) {
    case "deck": case "main": case "mainboard": return "deck";
    case "commander": case "commanders": return "commanders";
    case "companion": case "companions": return "companions";
    case "sideboard": return "sideboard";
    case "maybeboard": case "considering": return "maybeboard";
    default: return undefined;
  }
}

const bulkTags = /\s+#!.+$/u;
const label = /\s+\^[^^\r\n]+,#[0-9A-Fa-f]{6}\^$/u;
const bracket = /\s+\[[^[\]\r\n]+\]$/u;
const foil = /\s+\*(?:F|E)\*$/u;
const printingSuffix = /\s+\([A-Za-z0-9]+\)(?:\s+[A-Za-z0-9★†-]+)?$/u;
const strayDecoration = /\s+\*[^*]*\*$/u;

/**
 * The explicit text-export grammar only ("1 Sol Ring", "1x Sol Ring (CMM) 400", Commander/Deck/… headings, Moxfield
 * and Archidekt decorations), not CSV, JSON or arbitrary provider text. Unknown names and custom groupings survive as
 * draft data; the annotations say what was read around them. Any malformed line rejects the whole import.
 */
export function importText(text: string, name: string): TextImport {
  if (utf8Size(text) > maximumJSONBytes) throw new TextImportError(1, "Deck text exceeds 2 MiB.");
  validateDeck({ name, entries: [] });
  const rows: StudioEntry[] = [];
  const annotations: TextAnnotation[] = [];
  let section = "deck";
  let total = 0;
  // Normalize CRLF once so line numbers match the user's editor.
  const lines = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
  lines.forEach((raw, offset) => {
    const number = offset + 1;
    const invalid = (reason: string) => new TextImportError(number, reason);
    let line = trimSpaces(raw);
    if (offset === 0 && line.startsWith("﻿")) line = line.slice(1);
    line = trimSpaces(line);
    if (line.length === 0) return;
    let heading = line;
    const explicitHeading = heading.startsWith("//") || heading.startsWith("#") || heading.endsWith(":");
    if (heading.startsWith("//")) heading = heading.slice(2); else if (heading.startsWith("#")) heading = heading.slice(1);
    heading = trimSpaces(heading);
    if (heading.endsWith(":")) heading = heading.slice(0, -1);
    heading = trimSpaces(heading);
    const known = sectionName(heading);
    if (known !== undefined) { section = known; return; }
    if (explicitHeading && !/^\p{N}/u.test(line)) {
      if (heading.length === 0 || utf8Size(heading) > 2000) throw invalid("Invalid section heading.");
      annotations.push({ line: number, text: `Grouping retained in ${section}: ${heading}` });
      return;
    }
    const split = line.search(/\s/u);
    const token = split < 0 ? line : line.slice(0, split);
    const digits = token.toLowerCase().endsWith("x") ? token.slice(0, -1) : token;
    const count = /^[0-9]+$/.test(digits) ? Number(digits) : NaN;
    if (split < 0 || !(count >= 1 && count <= 2000) || count > 2000 - total) {
      throw invalid("Use '1 Card Name' or '1x Card Name', with at most 2,000 cards total. Mark custom headings with // or a trailing colon.");
    }
    let cardName = trimSpaces(line.slice(split + 1));
    let rowSection = section;
    const takeSuffix = (pattern: RegExp): string | undefined => {
      const match = pattern.exec(cardName);
      if (!match) return undefined;
      cardName = cardName.slice(0, match.index) + cardName.slice(match.index + match[0].length);
      return trimSpaces(match[0]);
    };
    // Moxfield bulk tags have their own delimiter; punctuation inside names is untouched.
    const tags = takeSuffix(bulkTags);
    if (tags !== undefined) annotations.push({ line: number, text: tags });
    const owned = takeSuffix(label);
    if (owned !== undefined) annotations.push({ line: number, text: owned });
    const category = takeSuffix(bracket);
    if (category !== undefined) {
      let value = trimSpaces(category.slice(1, -1));
      if (value.endsWith("{top}")) {
        value = trimSpaces(value.slice(0, -5));
        if (sectionName(value) !== "commanders") throw invalid("Only [Commander{top}] is supported as a premier category.");
      }
      if (value.length === 0) throw invalid("Empty bracket category.");
      if (value.includes("{") || value.includes("}")) throw invalid("Unsupported category flags; specify the intended deck section explicitly.");
      const mapped = sectionName(value);
      // A category under an explicit non-main section must not silently move it.
      if (section !== "deck" && mapped !== undefined && mapped !== section) throw invalid("Bracket category conflicts with the current section.");
      if (mapped !== undefined) rowSection = mapped;
      annotations.push({ line: number, text: `Category retained: ${category}` });
    }
    const finish = takeSuffix(foil);
    if (finish !== undefined) annotations.push({ line: number, text: finish });
    // "(CMM) 400" names one printing, which the row keeps as its chosen art. A set code with no number cannot.
    let chosen: CardPrinting | undefined;
    const printing = takeSuffix(printingSuffix);
    if (printing !== undefined) {
      chosen = CardPrinting.parseSuffix(printing);
      annotations.push({ line: number, text: printing });
    }
    // Fail on malformed or unrecognized export decorations rather than import an altered name.
    if (cardName.includes("[") || cardName.includes("]") || cardName.includes("^") || cardName.includes("#!") || strayDecoration.test(cardName)) {
      throw invalid("Unsupported or malformed export suffix; use one bracket category and the documented printing/foil/label syntax.");
    }
    cardName = trimSpaces(cardName);
    const entry = StudioEntry.of(cardName, count, rowSection, chosen);
    try { validateDeck({ name: "Row", entries: [entry] }); } catch { throw invalid("Card name or section is empty or too long."); }
    rows.push(entry);
    total += count;
  });
  if (rows.length === 0) throw new TextImportError(1, "The list has no card rows.");
  // NativeDeckDraft(rows).deck(): the first commander-section row leads.
  const lead = rows.findIndex((row) => row.section === "commanders");
  const deck: StudioDeck = lead < 0 ? { name, entries: rows } : { name, commander: rows[lead], entries: rows.filter((_, index) => index !== lead) };
  validateDeck(deck);
  return { deck, annotations };
}

/** Thrown for decks plain text cannot carry losslessly; JSON is the lossless choice. */
export class RequiresJSONError extends Error {
  constructor() { super("Use JSON export for empty drafts, custom sections or unusual card names."); }
}

/** One line per row: "2 Sol Ring", or with chosen art "2 Sol Ring (CMM) 400" as Moxfield and Archidekt write it. */
export function exportLine(entry: StudioEntry): string {
  const printing = StudioEntry.printing(entry);
  return `${entry.quantity} ${entry.cardName}${printing ? ` ${CardPrinting.exportSuffix(printing)}` : ""}`;
}

const exportBoards = ["Commander", "Deck", "Companion", "Sideboard", "Maybeboard"];

/** DeckStudioTextExport.text: standard boards only, checked by re-importing before it is shared. */
export function exportText(deck: StudioDeck): string {
  const entries = [...(deck.commander ? [{ ...deck.commander, section: "commanders" }] : []), ...deck.entries];
  if (entries.length === 0) throw new RequiresJSONError();
  const groups = new Map<string, StudioEntry[]>();
  for (const entry of entries) {
    let section: string;
    switch (entry.section.toLowerCase()) {
      case "deck": case "main": case "mainboard": section = "Deck"; break;
      case "commander": case "commanders": section = "Commander"; break;
      case "companion": case "companions": section = "Companion"; break;
      case "sideboard": section = "Sideboard"; break;
      case "maybeboard": case "considering": section = "Maybeboard"; break;
      default: throw new RequiresJSONError();
    }
    if (!groups.has(section)) groups.set(section, []);
    groups.get(section)!.push(entry);
  }
  const text = exportBoards.flatMap((section) => {
    const rows = groups.get(section);
    return rows && rows.length > 0 ? [`${section}\n${rows.map(exportLine).join("\n")}`] : [];
  }).join("\n\n") + "\n";
  // The real importer must preserve every name, quantity, board and chosen printing.
  let decoded: StudioDeck;
  try { decoded = importText(text, deck.name).deck; } catch { throw new RequiresJSONError(); }
  const counts = (values: StudioEntry[]) => {
    const result = new Map<string, number>();
    for (const value of values) {
      const printing = StudioEntry.printing(value);
      const key = `${value.section}\u0000${value.cardName}\u0000${printing ? CardPrinting.key(printing) : ""}`;
      result.set(key, (result.get(key) ?? 0) + value.quantity);
    }
    return result;
  };
  const board = (key: string) => (key === "Commander" ? "commanders" : key === "Companion" ? "companions" : key.toLowerCase());
  const expected = counts([...groups].flatMap(([key, values]) => values.map((value) => ({ ...value, section: board(key) }))));
  const actual = counts([...(decoded.commander ? [{ ...decoded.commander, section: "commanders" }] : []), ...decoded.entries]);
  if (expected.size !== actual.size || [...expected].some(([key, value]) => actual.get(key) !== value)) throw new RequiresJSONError();
  return text;
}

/** JSONEncoder with `.prettyPrinted, .sortedKeys`: two-space indent, `"key" : value`, slashes escaped. */
function swiftJSON(value: unknown, indent = ""): string {
  const inner = `${indent}  `;
  if (Array.isArray(value)) {
    return value.length === 0 ? "[\n\n]" : `[\n${value.map((item) => inner + swiftJSON(item, inner)).join(",\n")}\n${indent}]`;
  }
  if (value !== null && typeof value === "object") {
    const keys = Object.keys(value).filter((key) => (value as Record<string, unknown>)[key] !== undefined).sort();
    if (keys.length === 0) return "{\n\n}";
    return `{\n${keys.map((key) => `${inner}${swiftJSON(key)} : ${swiftJSON((value as Record<string, unknown>)[key], inner)}`).join(",\n")}\n${indent}}`;
  }
  return JSON.stringify(value).replace(/\//g, "\\/");
}

/** JSON draft exchange preserves every section and name verbatim, unlike lossy text. */
export function exportJSON(deck: StudioDeck): string {
  validateDeck(deck);
  const text = swiftJSON(deck);
  if (utf8Size(text) > maximumJSONBytes) throw new DeckEditingError("oversizedJSON");
  return text;
}

export function importJSON(text: string): StudioDeck {
  if (utf8Size(text) > maximumJSONBytes) throw new DeckEditingError("oversizedJSON");
  let value: unknown;
  try { value = JSON.parse(text); } catch { throw new DeckEditingError("invalidEntry"); }
  const entry = (raw: unknown): StudioEntry => {
    const row = raw as Record<string, unknown>;
    if (typeof row !== "object" || row === null || typeof row.cardName !== "string" || typeof row.section !== "string"
      || !Number.isInteger(row.quantity)) throw new DeckEditingError("invalidEntry");
    const printing = typeof row.setCode === "string" && typeof row.collectorNumber === "string"
      ? CardPrinting.of(row.setCode, row.collectorNumber) : undefined;
    return StudioEntry.of(row.cardName, row.quantity as number, row.section, printing);
  };
  const object = value as Record<string, unknown>;
  if (typeof object !== "object" || object === null || Array.isArray(object)) throw new DeckEditingError("invalidEntry");
  if (typeof object.name !== "string") throw new DeckEditingError("invalidName");
  if (!Array.isArray(object.entries)) throw new DeckEditingError("invalidEntry");
  const deck: StudioDeck = { name: object.name, entries: object.entries.map(entry) };
  if (object.commander !== undefined && object.commander !== null) deck.commander = entry(object.commander);
  validateDeck(deck);
  return deck;
}

/** One card's count change on one board in "Edit as text". */
export interface TextChange { board: string; name: string; before: number; after: number }
/** A card whose chosen printing changed, written "(SET) number" in the text. */
export interface ArtChange { board: string; name: string; before: string[]; after: string[] }

const diffOrder = ["commanders", "deck", "companions", "sideboard", "maybeboard"];
const capitalized = (text: string) => text.split(" ").map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()).join(" ");

/** "Edit as text": the whole deck in the export format, reviewed as cards added and removed per board, applied as one undo step. */
export const TextDiff = {
  title: (board: string) => ({ commanders: "Commander", deck: "Deck", companions: "Companion", sideboard: "Sideboard", maybeboard: "Maybeboard" } as
    Record<string, string>)[board] ?? capitalized(board),
  /** "+2 Sol Ring · Deck", "−1 Island · Maybeboard". */
  label: (change: TextChange) => {
    const delta = change.after - change.before;
    return `${delta > 0 ? "+" : "−"}${Math.abs(delta)} ${change.name} · ${TextDiff.title(change.board)}`;
  },
  /** "Sol Ring · default art → CMM 400". */
  artLabel: (change: ArtChange) => `${change.name} · ${change.before.join(", ")} → ${change.after.join(", ")}`,

  between(old: DeckDraft, next: DeckDraft): { added: TextChange[]; removed: TextChange[]; art: ArtChange[] } {
    const key = (board: string, name: string) => `${board}\u0000${name}`;
    const totals = (draft: DeckDraft) => {
      const result = new Map<string, { board: string; name: string; count: number }>();
      for (const row of draft.rows) {
        const board = DraftPresentation.section(row);
        const value = result.get(key(board, row.cardName)) ?? { board, name: row.cardName, count: 0 };
        value.count += row.quantity;
        result.set(key(board, row.cardName), value);
      }
      return result;
    };
    const before = totals(old);
    const after = totals(next);
    const rank = (board: string) => { const index = diffOrder.indexOf(board); return index < 0 ? diffOrder.length : index; };
    const compare = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
    const changes = [...new Set([...before.keys(), ...after.keys()])].map((id): TextChange => {
      const value = before.get(id) ?? after.get(id)!;
      return { board: value.board, name: value.name, before: before.get(id)?.count ?? 0, after: after.get(id)?.count ?? 0 };
    }).filter((change) => change.after !== change.before).sort((a, b) =>
      rank(a.board) !== rank(b.board) ? rank(a.board) - rank(b.board) : a.board === b.board ? compare(a.name, b.name) : compare(a.board, b.board));
    // The chosen printings per card and board, one per row; default art reads "default art".
    const artwork = (draft: DeckDraft) => {
      const result = new Map<string, string[]>();
      for (const row of draft.rows) {
        const id = key(DraftPresentation.section(row), row.cardName);
        result.set(id, [...(result.get(id) ?? []), row.printing ? CardPrinting.label(row.printing) : "default art"]);
      }
      for (const [id, values] of result) result.set(id, values.sort());
      return result;
    };
    const beforeArt = artwork(old);
    const afterArt = artwork(next);
    const art = [...beforeArt.keys()].filter((id) => afterArt.has(id)).flatMap((id): ArtChange[] => {
      const was = beforeArt.get(id)!;
      const now = afterArt.get(id)!;
      const [board, name] = id.split("\u0000");
      return was.join("\u0000") === now.join("\u0000") ? [] : [{ board, name, before: was, after: now }];
    }).sort((a, b) => compare(a.board, b.board) || compare(a.name, b.name));
    return { added: changes.filter((c) => c.after > c.before), removed: changes.filter((c) => c.after < c.before), art };
  },

  /**
   * Parses edited text with the plain-text importer and returns the new draft and the importer's notes. Rows that stay
   * on the same board keep their identity and section spelling; the primary commander stays primary while it remains one.
   */
  draft(text: string, replacing: DeckDraft): { draft: DeckDraft; notes: string[] } {
    const name = replacing.name.trim().length === 0 ? "Draft" : replacing.name;
    const notes: string[] = [];
    let imported: StudioDeck = { name, entries: [] };
    if (text.trim().length > 0) {
      const result = importText(text, name);
      notes.push(...result.annotations.map((note) => `Line ${note.line}: ${note.text}`));
      imported = result.deck;
    }
    const unused = [...replacing.rows];
    const rows = draftFromDeck(imported).rows.map((fresh) => {
      const board = DraftPresentation.section(fresh);
      const index = unused.findIndex((row) => DraftPresentation.section(row) === board && row.cardName === fresh.cardName);
      if (index < 0) return fresh;
      const [old] = unused.splice(index, 1);
      return { ...fresh, id: old.id, section: DraftPresentation.normalizedSection(old.section) === board ? old.section : fresh.section };
    });
    const previous = replacing.rows.find((row) => row.isPrimaryCommander)?.cardName;
    const keep = rows.findIndex((row) => DraftPresentation.section(row) === "commanders" && row.cardName === previous);
    // Every row on the commander board has a commander section, so moving the flag keeps both commanders.
    const final = previous !== undefined && keep >= 0 ? rows.map((row, index) => ({ ...row, isPrimaryCommander: index === keep })) : rows;
    return { draft: { ...replacing, rows: final }, notes };
  },
};

/** The draft as export text (Copy list, Edit as text). */
export const draftText = (draft: DeckDraft) => exportText(draftDeck(draft));
