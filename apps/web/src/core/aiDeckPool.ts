/**
 * Port of AIDeckPool.swift (Android AIDeckPool.kt): an AI opponent's deck is one of the included precons (Core) or
 * one of ai-decks.json, built from EDHREC's average decks per bracket (scripts/ranked/build_ai_decks.py). Players
 * may play them too. Built from the parsed `generated/ai-decks.json` and `generated/precons.json`
 * (scripts/prepare_data.py); every deck is a `DeckList` that DeckResolver.resolve accepts. Checked by
 * test/aiDeckPool.test.ts against parity/ranked-cases.json.
 */
import { CommanderBracket } from "./brackets";
import type { DeckEntry, DeckList } from "./deckResolver";

export interface AIDeck {
  id: string;
  name: string;
  subtitle: string;
  colors: string;
  commander: string;
  bracket: CommanderBracket;
  /** Hidden deck Power, 1-10 (ai-decks.json `power`, scripts/ranked/deck_power.py); undefined when unrated. */
  power?: number;
  /** Commander first (section "commanders", as precons.json has it), then the main deck (section "deck"). */
  deckList: DeckList;
}

/** The setup screen's deck ID when a player picks one of these decks for themselves. */
export const playerDeckID = (deck: AIDeck) => `included:${deck.id}`;
/** An official precon; ai-decks.json IDs all start with "ai-". */
export const isPrecon = (deck: AIDeck) => !deck.id.startsWith("ai-");

/** ai-decks.json's `power` block: each deck's Power, Ranked's tier bands and Quick Match's levels (docs/DECK_POWER.md). */
export interface DeckPowerData {
  closest: number;
  /** How many decks each tier picks among, Bronze to Mythic; `closest` for a tier it leaves out. */
  rankedClosest?: number[];
  /** Bronze to Mythic: each tier's [low, high] Power band. */
  rankedTiers: [number, number][];
  quickMatch: Record<string, { power: number; skill: number }>;
  decks: Record<string, number>;
}

/** ai-decks.json (iOS Resources). */
export interface AIDecksFile {
  schemaVersion: number;
  source?: string;
  catalogueHash?: string;
  power?: DeckPowerData;
  decks: {
    id: string; name: string; subtitle: string; colors: string; commander: string; bracket: number; computedBracket?: number;
    entries: DeckEntry[];
  }[];
}
/** precons.json (scripts/prepare_data.py): the commander is the "commanders" entry. */
export interface PreconsFile { decks: DeckList[] }

const fail = (what: string): never => { throw new Error(`AI decks: ${what}`); };
const text = (value: unknown, what: string): string => (typeof value === "string" ? value : fail(what));
const entries = (value: unknown, what: string): DeckEntry[] => {
  if (!Array.isArray(value)) fail(what);
  return (value as unknown[]).map((entry) => {
    const row = entry as Partial<DeckEntry> | null;
    if (!row || typeof row.name !== "string" || typeof row.section !== "string" || !Number.isInteger(row.quantity)) fail(what);
    return row as DeckEntry;
  });
};

export class AIDeckPool {
  /** The softest precons in the AI's hands, for Bronze ranked (C3's equal-skill round-robin, docs/cloud/reports/c3.md). */
  static readonly gentlestPrecons: ReadonlySet<string> = new Set(["chaos-incarnate", "grave-danger", "token-triumph"]);

  /** The bracket decks (ai-decks.json), without the precons. */
  readonly bracketDecks: AIDeck[];
  /** Every AI deck: the precons first (Core; their IDs are the precon IDs saved games already use). */
  readonly all: AIDeck[];
  /** Power picking's settings, when the file has them. */
  readonly power?: DeckPowerData;

  constructor(aiDecks: AIDecksFile, precons: PreconsFile) {
    this.bracketDecks = AIDeckPool.decode(aiDecks);
    if (!precons || !Array.isArray(precons.decks)) fail("precons.json has no decks");
    const preconDecks = precons.decks.map((deck): AIDeck => {
      const list = entries(deck.entries, `precon ${deck.id}`);
      const commander = list.find((entry) => /^commanders?$/i.test(entry.section.trim()))?.name ?? fail(`precon ${deck.id} has no commander`);
      return {
        id: text(deck.id, "precon id"), name: text(deck.name, `precon ${deck.id}`), subtitle: deck.subtitle ?? "", colors: deck.colors ?? "",
        commander, bracket: CommanderBracket.core, deckList: { ...deck, entries: list },
      };
    });
    this.power = aiDecks.power;
    this.all = [...preconDecks, ...this.bracketDecks].map((deck) => ({ ...deck, power: aiDecks.power?.decks[deck.id] }));
    this.bracketDecks = this.all.filter((deck) => !isPrecon(deck));
  }

  /**
   * Ranked's target Power (docs/DECK_POWER.md): the tier's band split in four divisions, IV low to I high; Mythic
   * (division 0) aims at the middle of its band. `tier` counts from Bronze (0).
   */
  static rankedTarget(tier: number, division: number, tiers: [number, number][]): number {
    const [low, high] = tiers[Math.min(tiers.length - 1, Math.max(0, tier))];
    if (division <= 0) return (low + high) / 2;
    return low + (high - low) * (4 - Math.min(4, division) + 0.5) / 4;
  }

  /** How many of the nearest decks a tier picks among. */
  static closest(power: DeckPowerData, tier: number): number { return power.rankedClosest?.[tier] ?? power.closest; }

  /**
   * An AI deck by Power: decks with a Power and a bracket at most `maxBracket` (none: any), never your commander and
   * not a recent deck while others remain, then the `closest` nearest the target (ties by id), `roll` picking among
   * them. Undefined when no deck qualifies. Checked against parity/power-cases.json.
   */
  pickByPower(options: {
    target: number; maxBracket?: number; avoidingCommander?: string; recent: string[]; decks?: AIDeck[]; closest?: number;
    roll?: (count: number) => number;
  }): AIDeck | undefined {
    const roll = options.roll ?? ((count: number) => Math.floor(Math.random() * count));
    const { maxBracket, avoidingCommander: commander, target } = options;
    let candidates = (options.decks ?? this.all)
      .filter((deck) => deck.power !== undefined && deck.power !== null && (maxBracket === undefined || deck.bracket <= maxBracket));
    if (commander !== undefined && candidates.some((deck) => deck.commander !== commander)) {
      candidates = candidates.filter((deck) => deck.commander !== commander);
    }
    const fresh = candidates.filter((deck) => !options.recent.includes(deck.id));
    if (fresh.length > 0) candidates = fresh;
    const near = [...candidates]
      .sort((a, b) => Math.abs(a.power! - target) - Math.abs(b.power! - target) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
      .slice(0, options.closest ?? this.power?.closest ?? 3);
    if (near.length === 0) return undefined;
    return near[Math.min(near.length - 1, Math.max(0, Math.trunc(roll(near.length))))];
  }

  /** ai-decks.json to decks (AIDeckPool.decode): the commander entry becomes the commander, everything else the main deck. */
  static decode(file: AIDecksFile): AIDeck[] {
    if (!file || !Array.isArray(file.decks)) fail("ai-decks.json has no decks");
    return file.decks.map((deck) => {
      const id = text(deck.id, "deck id"), name = text(deck.name, id);
      if (!Number.isInteger(deck.bracket)) fail(`${id} has no bracket`);
      const list = entries(deck.entries, id);
      const commander = list.find((entry) => entry.section === "commander");
      const deckEntries: DeckEntry[] = [
        ...(commander ? [{ name: commander.name, quantity: 1, section: "commanders" }] : []),
        ...list.filter((entry) => entry.section !== "commander").map((entry) => ({ name: entry.name, quantity: entry.quantity, section: "deck" })),
      ];
      return {
        id, name, subtitle: text(deck.subtitle, id), colors: text(deck.colors, id), commander: text(deck.commander, id),
        bracket: CommanderBracket.clamping(deck.bracket),
        deckList: { id, name, subtitle: deck.subtitle, colors: deck.colors, entries: deckEntries },
      };
    });
  }

  deck(id: string): AIDeck | undefined { return this.all.find((deck) => deck.id === id); }

  /** A bracket deck by the ID a player's deck picker saves ("included:<id>"). Like Swift, precons are not matched here. */
  playerDeck(id: string): AIDeck | undefined {
    if (!id.startsWith("included:")) return undefined;
    return this.bracketDecks.find((deck) => playerDeckID(deck) === id);
  }

  decks(bracket: CommanderBracket): AIDeck[] { return this.all.filter((deck) => deck.bracket === bracket); }

  /** The pool for a bracket. cEDH borrows Optimized; an empty bracket borrows its nearest neighbour. */
  pool(bracket: number, decks: AIDeck[] = this.all): AIDeck[] {
    const wanted = Math.min(4, Math.max(1, bracket));
    for (let distance = 0; distance <= 3; distance++) {
      for (const candidate of [wanted - distance, wanted + distance]) {
        if (candidate < 1 || candidate > 4) continue;
        const found = decks.filter((deck) => deck.bracket === candidate);
        if (found.length > 0) return found;
      }
    }
    return decks;
  }

  /**
   * An AI deck for this bracket: never your own commander, and not one of the last few you faced while others
   * remain. `preconsOnly` keeps to the official precons, and `onlyPrecons` narrows them further when any of those
   * are present. `roll(count)` picks an index among what is left (default: uniform random; inject it for tests).
   */
  pick(options: {
    bracket: number; avoidingCommander?: string; recent: string[]; preconsOnly?: boolean; onlyPrecons?: ReadonlySet<string>;
    decks?: AIDeck[]; roll?: (count: number) => number;
  }): AIDeck | undefined {
    const decks = options.decks ?? this.all;
    const roll = options.roll ?? ((count: number) => Math.floor(Math.random() * count));
    const { onlyPrecons, avoidingCommander: commander } = options;
    let precons = decks.filter(isPrecon);
    if (onlyPrecons && precons.some((deck) => onlyPrecons.has(deck.id))) precons = precons.filter((deck) => onlyPrecons.has(deck.id));
    let candidates = this.pool(options.bracket, options.preconsOnly && precons.length > 0 ? precons : decks);
    if (commander !== undefined && candidates.some((deck) => deck.commander !== commander)) {
      candidates = candidates.filter((deck) => deck.commander !== commander);
    }
    const fresh = candidates.filter((deck) => !options.recent.includes(deck.id));
    if (fresh.length > 0) candidates = fresh;
    if (candidates.length === 0) return undefined;
    return candidates[Math.min(candidates.length - 1, Math.max(0, Math.trunc(roll(candidates.length))))];
  }
}
