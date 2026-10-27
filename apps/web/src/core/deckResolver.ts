/**
 * Resolves deck lists to the exact compiled printings the engine accepts (OnDeviceDeckResolver.swift,
 * Catalogue.resolve in Decks.kt), from the same catalogue the phones ship. XMage decides legality.
 */
import { appConfig } from "./appConfig";
import { EngineError, type J } from "./json";

/**
 * The names a deck's card is looked up by, in order (NativeDeckCanonicalNames.candidates, parity/card-name-cases.json;
 * Caleb, 2026-10-26: Archidekt links dropped cards that search then found). The exact name first, then plain letters for
 * accents ("Troll of Khazad-dûm": XMage spells names without them), then the front of a two-part name ("Brazen Borrower //
 * Petty Theft": adventure, omen and prepare cards, whose full name only Archidekt sends). An exact split-card name wins.
 */
export function cardNameCandidates(raw: string): string[] {
  const name = raw.trim();
  const found: string[] = [];
  const add = (value: string) => { if (value && !found.includes(value)) found.push(value); };
  add(name);
  add(plainLetters(name));
  const split = name.indexOf(" // ");
  if (split > 0) {
    const front = name.slice(0, split).trim();
    add(front);
    add(plainLetters(front));
  }
  return found;
}

/**
 * Whether `candidate` is the front of the two-part `name` (as written or in plain letters). A double-faced card's front
 * never stands in for a different back: its aliases name the real one ("Front // Wrong" stays unknown).
 */
export function isFrontOf(candidate: string, name: string): boolean {
  const trimmed = name.trim();
  const split = trimmed.indexOf(" // ");
  if (split <= 0) return false;
  const front = trimmed.slice(0, split).trim();
  return candidate === front || candidate === plainLetters(front);
}

/** Accents off, Æ as Ae, a curly apostrophe straight. */
export const plainLetters = (name: string) =>
  name.replace(/\u2019/g, "'").replace(/Æ/g, "Ae").replace(/æ/g, "ae").normalize("NFKD").replace(/\p{Mn}+/gu, "");

export interface DeckEntry { name: string; quantity: number; section: string }
export interface DeckList { id: string; name: string; subtitle?: string; colors?: string; entries: DeckEntry[] }
export interface Printing { name: string; setCode: string; collectorNumber: string }

export class DeckResolver {
  readonly catalogueHash: string;
  readonly upstreamCommit: string;
  private readonly cards = new Map<string, Printing>();
  private readonly aliases = new Map<string, string>();
  /** Front faces with an attested back (double-faced cards). */
  private fronts?: Set<string>;
  private get aliasedFronts(): Set<string> { return (this.fronts ??= new Set(this.aliases.values())); }

  /** `printings.tsv` from scripts/prepare_data.py: a `#` header, printings, then `=` alias rows. */
  constructor(tsv: string) {
    const lines = tsv.split("\n").filter((line) => line.length > 0);
    const header = lines[0]?.split("\t");
    if (!header || header[0] !== "#" || !/^[0-9a-f]{64}$/.test(header[1] ?? "") || !/^[0-9a-f]{40}$/.test(header[2] ?? "")) {
      throw EngineError.invalid("The card catalogue is incomplete or incompatible. Reload the page.");
    }
    this.catalogueHash = header[1]; this.upstreamCommit = header[2];
    for (const line of lines.slice(1)) {
      const parts = line.split("\t");
      if (parts[0] === "=" && parts.length === 3) this.aliases.set(parts[1], parts[2]);
      else if (parts.length === 3) this.cards.set(parts[0], { name: parts[0], setCode: parts[1], collectorNumber: parts[2] });
      else throw EngineError.invalid("The card catalogue has a malformed row.");
    }
    if (this.cards.size === 0) throw EngineError.invalid("The card catalogue is empty.");
  }

  /** The catalogue's name for a card, tried by cardNameCandidates (exact, plain letters, front face). */
  canonicalName(name: string): string | undefined {
    for (const candidate of cardNameCandidates(name)) {
      const found = this.cards.has(candidate) ? candidate : this.aliases.get(candidate);
      if (found === undefined) continue;
      // A double-faced card's front never stands in for a different back (isFrontOf).
      if (isFrontOf(candidate, name) && this.aliasedFronts.has(found)) continue;
      return found;
    }
    // A fix the server sent for a name a deck site spells its own way (appConfig), when that card is here.
    const fixes = appConfig.current.nameFixes;
    return cardNameCandidates(name).map((candidate) => fixes[candidate]).find((fixed) => fixed !== undefined && this.cards.has(fixed));
  }

  printing(name: string): Printing | undefined {
    const canonical = this.canonicalName(name);
    return canonical === undefined ? undefined : this.cards.get(canonical);
  }

  /** The engine deck: `{name, main, commanders, companions}` of `{name, setCode, collectorNumber, count}` rows. */
  resolve(deck: DeckList): J {
    const sections: Record<string, J[]> = { main: [], commanders: [], companions: [] };
    const assigned = new Map<string, string>();
    let total = 0;
    for (const entry of deck.entries) {
      const section = DeckResolver.section(entry.section);
      const name = this.canonicalName(entry.name);
      if (name === undefined) throw EngineError.invalid(`No compiled printing for '${entry.name}'. Use the exact card name from this app's catalogue or update the app.`);
      if (!Number.isInteger(entry.quantity) || entry.quantity < 1 || entry.quantity > 2000 - total) {
        throw EngineError.invalid(`Invalid count for '${entry.name}'. Each count must be 1–2,000 and the entire deck must contain at most 2,000 cards.`);
      }
      const previous = assigned.get(name);
      if (previous !== undefined && previous !== section) {
        throw EngineError.invalid(`'${name}' appears in both ${previous} and ${section}. Keep it in one section and confirm its count; no copies were removed automatically.`);
      }
      assigned.set(name, section);
      total += entry.quantity;
      const printing = this.cards.get(name)!;
      sections[section].push({ name: printing.name, setCode: printing.setCode, collectorNumber: printing.collectorNumber, count: entry.quantity });
    }
    if (sections.commanders.length === 0) throw EngineError.invalid("Add a commander section first.");
    return { name: deck.name, main: sections.main, commanders: sections.commanders, companions: sections.companions };
  }

  private static section(name: string): string {
    switch (name.trim().toLowerCase()) {
      case "deck": case "main": return "main";
      case "commander": case "commanders": return "commanders";
      case "companion": case "companions": return "companions";
      default: throw EngineError.invalid(`Unsupported deck section '${name}'. Native play supports Deck, Commander, or Companion, not a general sideboard. No cards were dropped.`);
    }
  }
}
