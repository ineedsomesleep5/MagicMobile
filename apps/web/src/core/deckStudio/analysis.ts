/**
 * Deck analysis for the builder: the mana curve and statistics (NativeDeckMetadataCatalogue.statistics, the workspace's
 * deckCurve), functional roles (DeckStudioRoleAnalysis.swift, DeckStudioRoleGroups.swift), the goldfish sample hand
 * (DeckStudioSampleHand.swift) and the deck list's groups (DeckStudioWorkspaceScreen.cardGroups). Structural facts from
 * the catalogue, not an XMage legality result, a deck score or a simulated playtest.
 */
import type { Catalogue, CatalogueCard } from "./catalogue";
import { cardCountLabel } from "./preflight";
import { DraftPresentation, utf8Size, type DeckDraft, type DraftRow, type StudioDeck } from "./draft";

/** The builder's gold curve: main-deck nonland copies by mana value, bins 0 to 6 and 7 for "7+". Unknown types or values are left out. */
export function manaCurve(draft: DeckDraft, catalogue: Catalogue | undefined): number[] {
  const bins = new Array<number>(8).fill(0);
  for (const row of draft.rows) {
    if (DraftPresentation.section(row) !== "deck") continue;
    const card = catalogue?.card(row.cardName);
    if (!card?.types || card.types.includes("LAND") || card.manaValue === undefined) continue;
    bins[Math.min(7, Math.max(0, Math.trunc(card.manaValue)))] += row.quantity;
  }
  return bins;
}

/** A curve bin's label: "0" … "6", "7+". */
export const curveLabel = (bin: number) => (bin >= 7 ? "7+" : String(bin));

export interface DeckStatistics {
  cardCount: number;
  excludedCardCount: number;
  landCount: number;
  unknownTypeCount: number;
  unknownManaValueCount: number;
  unknownManaCostCount: number;
  unknownNames: string[];
  /** Quantity-weighted nonland printed mana values; unknown types and values are excluded. */
  manaCurve: Map<number, number>;
  /** Printed symbols, hybrids counted once as their own symbol; no colour-source estimates. */
  manaSymbolCounts: Map<string, number>;
}

export const averageManaValue = (stats: DeckStatistics): number | undefined => {
  let count = 0; let total = 0;
  for (const [value, copies] of stats.manaCurve) { count += copies; total += value * copies; }
  return count === 0 ? undefined : total / count;
};

const add = <K>(map: Map<K, number>, key: K, amount: number) => map.set(key, (map.get(key) ?? 0) + amount);

/** NativeDeckMetadataCatalogue.statistics: the chosen sections only (main deck by default). */
export function statistics(catalogue: Catalogue, deck: StudioDeck, sections: readonly string[] = ["main", "deck"]): DeckStatistics {
  const stats: DeckStatistics = { cardCount: 0, excludedCardCount: 0, landCount: 0, unknownTypeCount: 0, unknownManaValueCount: 0,
    unknownManaCostCount: 0, unknownNames: [], manaCurve: new Map(), manaSymbolCounts: new Map() };
  let total = 0;
  const unknown = new Set<string>();
  const selected = new Set(sections.map((section) => section.toLowerCase()));
  const rows = [...(deck.commander ? [{ ...deck.commander, section: "commanders" }] : []), ...deck.entries];
  for (const row of rows) {
    if (!Number.isInteger(row.quantity) || row.quantity < 1 || row.quantity > 2000 - total) {
      throw new Error("Statistics require at most 2,000 cards with positive quantities.");
    }
    total += row.quantity;
    if (!selected.has(row.section.trim().toLowerCase())) { stats.excludedCardCount += row.quantity; continue; }
    stats.cardCount += row.quantity;
    const card = catalogue.card(row.cardName);
    if (!card) {
      unknown.add(row.cardName);
      stats.unknownTypeCount += row.quantity; stats.unknownManaValueCount += row.quantity; stats.unknownManaCostCount += row.quantity;
      continue;
    }
    if (card.types) {
      if (card.types.includes("LAND")) stats.landCount += row.quantity;
      else if (card.manaValue !== undefined) add(stats.manaCurve, card.manaValue, row.quantity);
      else stats.unknownManaValueCount += row.quantity;
    } else {
      stats.unknownTypeCount += row.quantity;
      if (card.manaValue === undefined) stats.unknownManaValueCount += row.quantity;
    }
    if (card.manaCost !== undefined) {
      for (const fragment of card.manaCost.split("{").slice(1)) {
        const end = fragment.indexOf("}");
        if (end < 0) continue;
        const symbol = fragment.slice(0, end);
        if (symbol !== "*" && symbol.length > 0) add(stats.manaSymbolCounts, symbol, row.quantity);
      }
    } else stats.unknownManaCostCount += row.quantity;
  }
  stats.unknownNames = [...unknown].sort();
  return stats;
}

/**
 * Preview only: additional basics distributed by printed mono-colour pips (largest remainder). Never infers commander
 * identity, hybrid choices or mana production.
 */
export function basicLandSuggestion(catalogue: Catalogue, deck: StudioDeck, target = 37): [string, number][] {
  const stats = statistics(catalogue, deck);
  if (stats.unknownTypeCount !== 0 || stats.unknownManaCostCount !== 0) return [];
  const needed = Math.max(0, Math.min(100, target) - stats.landCount);
  const pairs: [string, string][] = [["W", "Plains"], ["U", "Island"], ["B", "Swamp"], ["R", "Mountain"], ["G", "Forest"]];
  const weights = pairs.map(([symbol]) => stats.manaSymbolCounts.get(symbol) ?? 0);
  const total = weights.reduce((sum, value) => sum + value, 0);
  if (needed <= 0 || total <= 0) return [];
  const counts = weights.map((weight) => Math.floor((needed * weight) / total));
  const priority = weights.map((_, index) => index).sort((a, b) => {
    const left = (needed * weights[a]) % total; const right = (needed * weights[b]) % total;
    return left === right ? a - b : right - left;
  });
  priority.slice(0, needed - counts.reduce((sum, value) => sum + value, 0)).forEach((index) => { counts[index] += 1; });
  if (!pairs.every(([, land], index) => counts[index] === 0 || catalogue.card(land) !== undefined)) return [];
  return pairs.flatMap(([, land], index) => (counts[index] > 0 ? [[land, counts[index]] as [string, number]] : []));
}

export type DeckRole = "ramp" | "cardFlow" | "interaction" | "boardWipe" | "protection" | "graveyardHate" | "recursion" | "tutor";

/** DeckStudioRole in its fixed order. */
export const deckRoles: readonly DeckRole[] = ["ramp", "cardFlow", "interaction", "boardWipe", "protection", "graveyardHate", "recursion", "tutor"];

export const DeckRole = {
  title: (role: DeckRole) => ({ ramp: "Ramp", cardFlow: "Draw / card flow", interaction: "Targeted interaction", boardWipe: "Board wipes",
    protection: "Protection", graveyardHate: "Graveyard interaction", recursion: "Recursion", tutor: "Tutors" })[role],
  of: (key: string): DeckRole | undefined => (deckRoles as readonly string[]).includes(key) ? key as DeckRole : undefined,
};

export interface RoleEvidence { role: DeckRole; source: "reviewed" | "curated" | "textPattern"; explanation: string }

const roleRules: [DeckRole, RegExp, string][] = [
  ["ramp", /^\{t\}: add (?:\{[wubrgc]\})+\./, "A nonland permanent has a direct tap-for-mana ability."],
  ["ramp", /^\{t\}: add one mana of any color(?: in your commander's color identity)?\./, "A nonland permanent has a direct tap-for-mana ability."],
  ["ramp", /^search your library for (?:a|up to two) basic land cards?, (?:reveal (?:it|them), )?put (?:it|one of them) onto the battlefield/,
    "A library-search instruction puts a basic land onto the battlefield. Conditions still need review."],
  ["cardFlow", /^draw (?:a|two|three|four|five|six|seven|[1-9][0-9]?) cards?\./,
    "A direct draw instruction is present. Cantrips and draw-then-discard effects are card flow, not necessarily net advantage."],
  ["interaction", /^(?:destroy|exile) target (?:creature|artifact|enchantment|permanent)(?: or (?:creature|artifact|enchantment))?\./,
    "A direct targeted removal instruction is present; restrictions and other modes still matter."],
  ["interaction", /^counter target (?:noncreature )?spell\./, "A direct counterspell instruction is present."],
  ["boardWipe", /^(?:destroy|exile) all creatures\./, "A direct instruction affects all creatures. Symmetry and deck context still matter."],
  ["protection", /^permanents you control gain hexproof and indestructible until end of turn\./, "A direct protective instruction grants hexproof and indestructible."],
  ["graveyardHate", /^exile (?:all cards from all graveyards|target card from a graveyard|target player's graveyard)\./, "A direct instruction exiles cards from a graveyard."],
  ["recursion", /^return target (?:(?:creature|artifact|enchantment|permanent) )?card from your graveyard to (?:your hand|the battlefield)\./,
    "A direct instruction returns a card from your graveyard."],
  ["tutor", /^search your library for a card, put that card into your hand, then shuffle\./, "A direct unrestricted library-search instruction is present."],
];

/** DeckStudioRoleClassifier: curated Scryfall tags first, then conservative text patterns; your own review overrides both. */
export const RoleClassifier = {
  /**
   * Reminder text removed, then each sentence and each activated ability's effect offered as its own candidate.
   * Triggered and conditional effects are left to curated tags and review.
   */
  clauses(text: string): string[] {
    const normalized = text.normalize("NFC").toLowerCase().replace(/’/g, "'");
    let depth = 0;
    let stripped = "";
    for (const character of normalized) {
      if (character === "(") { depth += 1; stripped += " "; }
      else if (character === ")") { if (depth <= 0) return []; depth -= 1; }
      else if (depth === 0) stripped += character;
    }
    if (depth !== 0) return [];
    if (/["“”•]/.test(stripped) || /\bchoose (?:one|two|three|four|any)\b/.test(stripped)) return [];
    const tidy = (value: string) => {
      const cleaned = value.split(/\s+/u).filter((part) => part.length > 0).join(" ");
      return cleaned.length === 0 ? undefined : cleaned.endsWith(".") ? cleaned : `${cleaned}.`;
    };
    const pieces: string[] = [];
    for (const line of stripped.split(/[\n\r\u000B\u000C\u0085\u2028\u2029]/)) {
      if (/\b(?:when|whenever|at the beginning|at the end|if|unless|activate only|activate (?:as|during)|only any time)\b/.test(line)) continue;
      for (const candidate of [line, ...line.split(/[.;]/).filter((part) => part.length > 0)]) {
        const whole = tidy(candidate);
        if (whole === undefined) continue;
        pieces.push(whole);
        const colon = candidate.indexOf(":");
        const effect = colon >= 0 ? tidy(candidate.slice(colon + 1)) : undefined;
        if (effect !== undefined) pieces.push(effect);
      }
    }
    return [...new Set(pieces)];
  },

  classify(text: string | undefined, types: readonly string[] | undefined, curated: readonly DeckRole[] = [],
    reviewed?: ReadonlySet<DeckRole>): RoleEvidence[] {
    if (reviewed) {
      return deckRoles.filter((role) => reviewed.has(role)).map((role) => ({ role, source: "reviewed",
        explanation: "You assigned this role. It overrides automatic hints for this card." }));
    }
    const matches = new Map<DeckRole, RoleEvidence>();
    for (const role of curated) {
      if (!matches.has(role)) matches.set(role, { role, source: "curated",
        explanation: "Tagged by Scryfall's community-curated oracle tags, bundled with this build. Correct it if you disagree." });
    }
    const resolved = () => deckRoles.flatMap((role) => (matches.has(role) ? [matches.get(role)!] : []));
    if (text === undefined || utf8Size(text) > 32768) return resolved();
    const pieces = RoleClassifier.clauses(text);
    if (pieces.length > 512) return resolved();
    for (const [role, expression, explanation] of roleRules) {
      if (matches.has(role)) continue;
      if (role === "ramp" && (types === undefined || types.includes("LAND"))) continue;
      if (pieces.some((piece) => expression.test(piece))) matches.set(role, { role, source: "textPattern", explanation });
    }
    return resolved();
  },

  /** A catalogue card's roles (curated keys it does not know are ignored). */
  forCard: (card: CatalogueCard | undefined, reviewed?: ReadonlySet<DeckRole>) => RoleClassifier.classify(card?.oracleText, card?.types,
    (card?.roles ?? []).flatMap((key) => { const role = DeckRole.of(key); return role ? [role] : []; }), reviewed),
};

/** The facts role grouping reads. */
export type RoleCard = Pick<CatalogueCard, "oracleText" | "types" | "roles">;

/**
 * "Group by Role" (DeckStudioRoleGroups): a card sits under every role it has, your own role review replaces the
 * automatic hints for that card, and cards with no role are "Other".
 */
export const RoleGroups = {
  other: "Other",
  order: [...deckRoles.map(DeckRole.title), "Other"] as readonly string[],
  /** Role group titles for each row ID, in `order`. */
  membership(rows: readonly DraftRow[], card: (name: string) => RoleCard | undefined,
    overrides: ReadonlyMap<string, ReadonlySet<DeckRole>> = new Map()): Map<string, string[]> {
    const byName = new Map<string, string[]>();
    const result = new Map<string, string[]>();
    for (const row of rows) {
      if (!byName.has(row.cardName)) {
        const info = card(row.cardName);
        const roles = RoleClassifier.classify(info?.oracleText, info?.types,
          (info?.roles ?? []).flatMap((key) => { const role = DeckRole.of(key); return role ? [role] : []; }), overrides.get(row.cardName)).map((e) => e.role);
        byName.set(row.cardName, roles.length === 0 ? [RoleGroups.other] : deckRoles.filter((role) => roles.includes(role)).map(DeckRole.title));
      }
      result.set(row.id, byName.get(row.cardName)!);
    }
    return result;
  },
  /** Group headers count unique cards, since one card can appear in several groups. */
  uniqueCards: (rows: readonly DraftRow[]) => new Set(rows.map((row) => row.cardName)).size,
};

/** A seeded random source in [0, 1) (mulberry32), so a sample hand can be replayed in tests. */
export function seededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export interface HandCard { id: number; name: string }

/**
 * DeckStudioSampleHand, a goldfish: draw seven from the main deck, London mulligan (shuffle, draw seven, put one card on
 * the bottom per mulligan taken), then draw a card each turn. Commanders and other boards stay out of the library.
 */
export class SampleHand {
  static readonly handSize = 7;

  private constructor(
    readonly library: readonly HandCard[], readonly hand: readonly HandCard[] = [], readonly mulligans = 0,
    /** Cards still to put on the bottom after the latest mulligan. */
    readonly toBottom = 0, readonly draws = 0,
  ) {}

  /** Main-deck cards, one entry per copy. */
  static libraryNames(draft: DeckDraft): string[] {
    return draft.rows.filter((row) => DraftPresentation.section(row) === "deck")
      .flatMap((row) => new Array<string>(Math.max(0, Math.min(row.quantity, 2000))).fill(row.cardName));
  }

  static of(names: readonly string[]): SampleHand { return new SampleHand(names.map((name, id) => ({ id, name }))); }

  get turn() { return this.draws + 1; }
  get canMulligan() { return this.draws === 0 && this.toBottom === 0 && this.mulligans < SampleHand.handSize && this.hand.length > 0; }
  get canDraw() { return this.toBottom === 0 && this.library.length > 0; }
  /** "Put 1 card on the bottom" after a mulligan, then "Turn 2 · 1 mulligan". */
  get status(): string {
    if (this.toBottom > 0) return `Put ${cardCountLabel(this.toBottom)} on the bottom`;
    return `Turn ${this.turn}${this.mulligans === 0 ? "" : ` · ${this.mulligans} ${this.mulligans === 1 ? "mulligan" : "mulligans"}`}`;
  }

  /** A fresh opening hand from the whole deck. */
  dealt(random: () => number = Math.random): SampleHand {
    return new SampleHand([...this.library, ...this.hand].sort((a, b) => a.id - b.id)).drawSeven(random);
  }

  mulliganed(random: () => number = Math.random): SampleHand {
    if (!this.canMulligan) return this;
    const next = new SampleHand([...this.library, ...this.hand], [], this.mulligans + 1).drawSeven(random);
    return new SampleHand(next.library, next.hand, next.mulligans, Math.min(next.mulligans, next.hand.length), next.draws);
  }

  puttingOnBottom(id: number): SampleHand {
    const card = this.hand.find((value) => value.id === id);
    if (this.toBottom <= 0 || !card) return this;
    return new SampleHand([...this.library, card], this.hand.filter((value) => value !== card), this.mulligans, this.toBottom - 1, this.draws);
  }

  drawn(): SampleHand {
    if (!this.canDraw) return this;
    return new SampleHand(this.library.slice(1), [...this.hand, this.library[0]], this.mulligans, this.toBottom, this.draws + 1);
  }

  private drawSeven(random: () => number): SampleHand {
    const shuffled = [...this.library];
    for (let index = shuffled.length - 1; index > 0; index -= 1) {
      const other = Math.floor(random() * (index + 1));
      [shuffled[index], shuffled[other]] = [shuffled[other], shuffled[index]];
    }
    const count = Math.min(SampleHand.handSize, shuffled.length);
    return new SampleHand(shuffled.slice(count), shuffled.slice(0, count), this.mulligans, this.toBottom, this.draws);
  }
}

export type CardGrouping = "Type" | "Role" | "Section" | "Mana value" | "Color" | "Name";
export const cardGroupings: readonly CardGrouping[] = ["Type", "Role", "Section", "Mana value", "Color", "Name"];

export interface CardGroup { title: string; rows: DraftRow[]; count: number }

const typePriority = ["LAND", "CREATURE", "PLANESWALKER", "INSTANT", "SORCERY", "ARTIFACT", "ENCHANTMENT", "BATTLE"];
/** Swift `capitalized`: each word's first letter upper case, the rest lower. */
const capitalized = (text: string) => text.toLowerCase().replace(/(^|\s)(\S)/g, (_, space: string, letter: string) => space + letter.toUpperCase());
/**
 * The deck list's groups (DeckStudioWorkspaceScreen.cardGroups): "Commanders" first, then the main deck's groups, then
 * each other board ("Sideboard", "Maybeboard", "Companions" …). By Type a main-deck card goes under the first of Land,
 * Creature, Planeswalker, Instant, Sorcery, Artifact, Enchantment, Battle it has, and those groups sort by title, as on
 * the iPhone. Counts are copies, or unique cards for role groups.
 */
export function cardGroups(rows: readonly DraftRow[], grouping: CardGrouping, catalogue: Catalogue | undefined,
  overrides: ReadonlyMap<string, ReadonlySet<DeckRole>> = new Map()): CardGroup[] {
  const roles = grouping === "Role"
    ? RoleGroups.membership(rows.filter((row) => DraftPresentation.section(row) === "deck"), (name) => catalogue?.card(name), overrides)
    : new Map<string, string[]>();
  const keys = (row: DraftRow): [string, number][] => {
    const section = DraftPresentation.section(row);
    if (section === "commanders") return [["Commanders", -1]];
    if (section !== "deck") return [[capitalized(section), 2_000_000]];
    const card = catalogue?.card(row.cardName);
    switch (grouping) {
      case "Role":
        return (roles.get(row.id) ?? [RoleGroups.other]).map((title) => {
          const index = RoleGroups.order.indexOf(title);
          return [title, index < 0 ? RoleGroups.order.length : index];
        });
      case "Name": case "Section": return [["Main deck", 1_000_001]];
      case "Mana value":
        return card?.manaValue === undefined ? [["Unknown mana value", 1_000_001]] : [[`Mana value ${card.manaValue}`, Math.min(card.manaValue, 1_000_000)]];
      case "Color": {
        const colors = card?.colors;
        if (!colors) return [["Unknown color", 1_000_001]];
        return [[colors.length === 0 ? "Colorless" : ["W", "U", "B", "R", "G"].filter((c) => colors.includes(c)).join(" / "), 1_000_001]];
      }
      default: {
        if (!card?.types) return [["Unclassified", 1_000_001]];
        const type = typePriority.find((value) => card.types!.includes(value));
        return [[type ? capitalized(type) : "Other types", 1_000_001]];
      }
    }
  };
  const groups = new Map<string, { title: string; order: number; rows: DraftRow[] }>();
  for (const row of rows) {
    for (const [title, order] of keys(row)) {
      if (!groups.has(title)) groups.set(title, { title, order, rows: [] });
      groups.get(title)!.rows.push(row);
    }
  }
  return [...groups.values()].map((group) => {
    const byRole = grouping === "Role" && RoleGroups.order.includes(group.title);
    return { ...group, count: byRole ? RoleGroups.uniqueCards(group.rows) : group.rows.reduce((sum, row) => sum + row.quantity, 0) };
  }).sort((a, b) => (a.order === b.order ? (a.title < b.title ? -1 : a.title > b.title ? 1 : 0) : a.order - b.order))
    .map(({ title, rows: members, count }) => ({ title, rows: members, count }));
}

export type RowSorting = "Name" | "Quantity" | "Mana value";

/** The deck list's row order (DeckStudioWorkspaceScreen.filteredRows): by quantity or mana value first when chosen, then name. */
export function sortRows(rows: readonly DraftRow[], sorting: RowSorting, catalogue: Catalogue | undefined): DraftRow[] {
  return [...rows].sort((a, b) => {
    if (sorting === "Quantity" && a.quantity !== b.quantity) return b.quantity - a.quantity;
    if (sorting === "Mana value") {
      const left = catalogue?.card(a.cardName)?.manaValue ?? Infinity;
      const right = catalogue?.card(b.cardName)?.manaValue ?? Infinity;
      if (left !== right) return left < right ? -1 : 1;
    }
    if (a.cardName === b.cardName) return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    return a.cardName < b.cardName ? -1 : 1;
  });
}

