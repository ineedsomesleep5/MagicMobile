/**
 * Port of CommanderBrackets.swift (Android CommanderBrackets.kt): Wizards' Commander Brackets (beta). A decklist
 * shows the lowest bracket a deck can be in; the player's intent (1 vs 2, 4 vs 5) is their call. The card lists
 * are commander-brackets.json (scripts/ranked/build_bracket_rules.py), passed in parsed. Checked by
 * test/brackets.test.ts against parity/ranked-cases.json.
 */
import type { DeckList } from "./deckResolver";
import type { KeyValueStore } from "./playerRecord";

/** 1 Exhibition … 5 cEDH (Swift's raw values). */
export type CommanderBracket = 1 | 2 | 3 | 4 | 5;
export const CommanderBracket = {
  exhibition: 1, core: 2, upgraded: 3, optimized: 4, cedh: 5,
  all: [1, 2, 3, 4, 5] as CommanderBracket[],
  name(bracket: CommanderBracket): string {
    return ["Exhibition", "Core", "Upgraded", "Optimized", "cEDH"][bracket - 1];
  },
  /** "Bracket 3 · Upgraded" */
  title: (bracket: CommanderBracket) => `Bracket ${bracket} · ${CommanderBracket.name(bracket)}`,
  blurb(bracket: CommanderBracket): string {
    return [
      "Theme first. Games are slow and win in style.",
      "Like a modern precon. No Game Changers, no fast combos.",
      "Tuned decks with up to three Game Changers.",
      "Fast, lethal decks. Anything legal goes.",
      "Competitive Commander. Built to win as fast as possible.",
    ][bracket - 1];
  },
  /** `init(clamping:)`: 1–5, Core for anything that isn't a whole number. */
  clamping: (value: number): CommanderBracket =>
    Number.isInteger(value) ? (Math.min(5, Math.max(1, value)) as CommanderBracket) : 2,
  from: (value: unknown): CommanderBracket | undefined =>
    typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= 5 ? (value as CommanderBracket) : undefined,
} as const;

export interface BracketCombo { cards: string[]; manaValue: number; /** Cheap enough to win in the first few turns: only Bracket 4 and up. */ early: boolean }

/** What a decklist shows about its bracket, with the cards behind it. */
export interface BracketReport {
  minimum: CommanderBracket;
  gameChangers: string[];
  massLandDenial: string[];
  extraTurns: string[];
  /** Two-card combos late enough for Bracket 3. */
  combos: string[][];
  earlyCombos: string[][];
}

/** One line per reason the deck sits above Core, for the bracket sheet (BracketReport.reasons). */
export function bracketReasons(report: BracketReport): string[] {
  const lines: string[] = [];
  if (report.gameChangers.length > 0) lines.push(`${report.gameChangers.length} Game Changers: ${report.gameChangers.join(", ")}`);
  if (report.massLandDenial.length > 0) lines.push(`Mass land denial: ${report.massLandDenial.join(", ")}`);
  if (report.minimum === CommanderBracket.optimized && report.extraTurns.length >= 3) lines.push(`Chains extra turns: ${report.extraTurns.join(", ")}`);
  for (const combo of report.earlyCombos) lines.push(`Early two-card combo: ${combo.join(" + ")}`);
  for (const combo of report.combos) lines.push(`Two-card combo: ${combo.join(" + ")}`);
  return lines;
}

/** commander-brackets.json as BracketRules reads it. */
export interface BracketRulesFile { gameChangers: string[]; massLandDenial: string[]; extraTurns: string[]; combos: BracketCombo[]; chainedExtraTurns: number }

/** The card lists the bracket check reads (BracketRules). */
export class BracketRules {
  readonly gameChangers: Set<string>;
  readonly massLandDenial: Set<string>;
  readonly extraTurns: Set<string>;
  readonly combos: BracketCombo[];
  /** This many extra-turn cards read as a deck built to chain them. */
  readonly chainedExtraTurns: number;

  constructor(file: BracketRulesFile) {
    const list = (value: unknown, key: string): string[] => {
      if (!Array.isArray(value) || !value.every((x) => typeof x === "string")) throw new Error(`commander-brackets.json: bad ${key}`);
      return value;
    };
    this.gameChangers = new Set(list(file.gameChangers, "gameChangers"));
    this.massLandDenial = new Set(list(file.massLandDenial, "massLandDenial"));
    this.extraTurns = new Set(list(file.extraTurns, "extraTurns"));
    if (!Array.isArray(file.combos)) throw new Error("commander-brackets.json: bad combos");
    this.combos = file.combos.map((combo) => ({ cards: list(combo.cards, "combo"), manaValue: combo.manaValue, early: combo.early === true }));
    this.chainedExtraTurns = Number.isInteger(file.chainedExtraTurns) ? file.chainedExtraTurns : 3;
  }

  /** No lists: checks nothing (Swift's fallback when the bundled file is missing). */
  static readonly empty = new BracketRules({ gameChangers: [], massLandDenial: [], extraTurns: [], combos: [], chainedExtraTurns: 3 });

  /** A card as the lists name it: double-faced and split cards are matched by their front face too. */
  private static names(cards: string[]): Set<string> {
    const set = new Set<string>();
    for (const card of cards) {
      set.add(card);
      const front = card.split(" // ")[0];
      if (front !== card) set.add(front);
    }
    return set;
  }

  evaluate(cardNames: string[]): BracketReport {
    const cards = BracketRules.names(cardNames);
    const among = (list: Set<string>) => [...cards].filter((card) => list.has(card)).sort();
    const changers = among(this.gameChangers);
    const landDenial = among(this.massLandDenial);
    const turns = among(this.extraTurns);
    const present = this.combos.filter((combo) => combo.cards.every((card) => cards.has(card)));
    let minimum: CommanderBracket = CommanderBracket.core;
    const raise = (to: CommanderBracket) => { minimum = Math.max(minimum, to) as CommanderBracket; };
    if (changers.length > 0) raise(changers.length <= 3 ? CommanderBracket.upgraded : CommanderBracket.optimized);
    if (landDenial.length > 0) minimum = CommanderBracket.optimized;
    if (turns.length >= this.chainedExtraTurns) minimum = CommanderBracket.optimized;
    for (const combo of present) raise(combo.early ? CommanderBracket.optimized : CommanderBracket.upgraded);
    return {
      minimum, gameChangers: changers, massLandDenial: landDenial, extraTurns: turns,
      combos: present.filter((combo) => !combo.early).map((combo) => combo.cards),
      earlyCombos: present.filter((combo) => combo.early).map((combo) => combo.cards),
    };
  }

  /** The deck as played: commander plus main deck (sideboard and maybeboard stay out). */
  evaluateDeck(deck: DeckList): BracketReport {
    const played = deck.entries.filter((entry) => ["deck", "main", "commander", "commanders"].includes(entry.section.trim().toLowerCase()));
    return this.evaluate(played.map((entry) => entry.name));
  }
}

/**
 * The player's own label for a deck, kept per deck ID (DeckBracketPreference). It may raise the bracket (intent),
 * or lower a Core list to Exhibition; never below what the list shows. Stored as one JSON object `{deckID: bracket}`.
 */
export const DeckBracketPreference = {
  key: "mm.web.deckBrackets",

  all(store: KeyValueStore): Record<string, number> {
    try {
      const parsed: unknown = JSON.parse(store.get(DeckBracketPreference.key) ?? "{}");
      return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed) ? (parsed as Record<string, number>) : {};
    } catch { return {}; }
  },

  declared: (deckID: string, store: KeyValueStore): CommanderBracket | undefined =>
    CommanderBracket.from(DeckBracketPreference.all(store)[deckID]),

  setDeclared(bracket: CommanderBracket | undefined, deckID: string, store: KeyValueStore): void {
    const all = DeckBracketPreference.all(store);
    if (bracket === undefined) delete all[deckID]; else all[deckID] = bracket;
    store.set(DeckBracketPreference.key, JSON.stringify(all));
  },

  effective(minimum: CommanderBracket, declared: CommanderBracket | undefined): CommanderBracket {
    if (declared === undefined) return minimum;
    if (declared === CommanderBracket.exhibition && minimum === CommanderBracket.core) return CommanderBracket.exhibition;
    return Math.max(declared, minimum) as CommanderBracket;
  },

  /** The labels a player may choose for a deck whose list shows `minimum`. */
  choices: (minimum: CommanderBracket): CommanderBracket[] =>
    CommanderBracket.all.filter((bracket) => bracket >= minimum || (bracket === CommanderBracket.exhibition && minimum === CommanderBracket.core)),
} as const;
