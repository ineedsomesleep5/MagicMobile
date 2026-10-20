/**
 * Resolves deck lists to the exact compiled printings the engine accepts (OnDeviceDeckResolver.swift,
 * Catalogue.resolve in Decks.kt), from the same catalogue the phones ship. XMage decides legality.
 */
import { EngineError, type J } from "./json";

export interface DeckEntry { name: string; quantity: number; section: string }
export interface DeckList { id: string; name: string; subtitle?: string; colors?: string; entries: DeckEntry[] }
export interface Printing { name: string; setCode: string; collectorNumber: string }

export class DeckResolver {
  readonly catalogueHash: string;
  readonly upstreamCommit: string;
  private readonly cards = new Map<string, Printing>();
  private readonly aliases = new Map<string, string>();

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

  canonicalName(name: string): string | undefined {
    if (this.cards.has(name)) return name;
    return this.aliases.get(name);
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
