/**
 * DeckStudioPreflight.swift (Android DeckStudioPreflight.kt): a fast, offline quick check of the Commander basics while
 * editing — deck size, a commander, colour identity, singleton copies and cards this build can play. It is advisory only:
 * XMage checks the deck when it is played, and a quick check never blocks Play. Anything it cannot judge (missing
 * metadata, an unknown commander identity, partner or background pairings) is left to XMage, so it errs towards quiet.
 */
import type { Catalogue, CatalogueCard } from "./catalogue";
import { DraftPresentation, type DeckDraft } from "./draft";

export type PreflightIssue = "missingCommander" | "offIdentity" | "duplicate" | "unresolved";

/** Fixed chip order. */
export const preflightIssues: readonly PreflightIssue[] = ["missingCommander", "offIdentity", "duplicate", "unresolved"];

export const PreflightIssue = {
  title: (issue: PreflightIssue) => ({ missingCommander: "Missing commander", offIdentity: "Off-color", duplicate: "Duplicates", unresolved: "Unresolved" })[issue],
  badge: (issue: PreflightIssue) => ({ missingCommander: "Missing commander", offIdentity: "Off-color", duplicate: "Duplicate", unresolved: "Unresolved" })[issue],
};

/** The card facts the check reads. */
export type PreflightCard = Pick<CatalogueCard, "name" | "typeLine" | "oracleText" | "colorIdentity">;

/** CardCountText.label: "1 card", "3 cards". */
export const cardCountLabel = (count: number) => `${count} ${count === 1 ? "card" : "cards"}`;
export const issueCountText = (count: number) => `${count} ${count === 1 ? "issue" : "issues"}`;

const numbers: Record<string, number> = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10 };

/** How many copies a Commander deck may hold; undefined means any number. */
export function copyLimit(card: PreflightCard): number | undefined {
  if (card.typeLine?.trim().toLowerCase().startsWith("basic ")) return undefined;
  const text = (card.oracleText ?? "").toLowerCase();
  if (text.includes("a deck can have any number of cards named")) return undefined;
  const match = /a deck can have up to ([a-z0-9]+) cards named/.exec(text);
  if (match) {
    const limit = numbers[match[1]] ?? (/^[0-9]+$/.test(match[1]) ? Number(match[1]) : undefined);
    if (limit !== undefined && limit > 0) return limit;
  }
  return 1;
}

export class Preflight {
  static readonly targetCount = 100;
  static readonly caption = "Quick check · XMage confirms when you play";

  /** Main deck plus commanders; companions and other boards are outside the 100. */
  readonly count: number;
  readonly missingCommander: boolean;
  /** Union of the commanders' identities; undefined with no commander or any commander's identity unknown. */
  readonly commanderIdentity: ReadonlySet<string> | undefined;
  private readonly flagged = new Map<PreflightIssue, Set<string>>();

  /**
   * `card` finds a card's facts by any name the deck uses; `resolves` says whether this build can play a name, and
   * undefined skips the Unresolved check (nothing is loaded yet).
   */
  constructor(draft: DeckDraft, card: (name: string) => PreflightCard | undefined, resolves: ((name: string) => boolean) | undefined) {
    const playing = draft.rows.filter((row) => DraftPresentation.playingBoards.has(DraftPresentation.section(row)));
    const commanders = playing.filter((row) => DraftPresentation.section(row) === "commanders");
    this.count = draft.rows.filter((row) => ["deck", "commanders"].includes(DraftPresentation.section(row))).reduce((sum, row) => sum + row.quantity, 0);
    this.missingCommander = commanders.length === 0;
    let identity: Set<string> | undefined = commanders.length === 0 ? undefined : new Set();
    for (const row of commanders) {
      const colors = card(row.cardName)?.colorIdentity;
      if (!colors) { identity = undefined; break; }
      colors.forEach((color) => identity!.add(color));
    }
    this.commanderIdentity = identity;
    const result = new Map<PreflightIssue, Set<string>>();
    if (resolves) result.set("unresolved", new Set(playing.filter((row) => !resolves(row.cardName)).map((row) => row.id)));
    if (identity) {
      const allowed = identity;
      result.set("offIdentity", new Set(playing.filter((row) => {
        if (DraftPresentation.section(row) === "commanders") return false;
        const colors = card(row.cardName)?.colorIdentity;
        return colors !== undefined && !colors.every((color) => allowed.has(color));
      }).map((row) => row.id)));
    }
    // Copies are counted across main, commanders and companions by canonical name.
    const groups = new Map<string, { info: PreflightCard; total: number; rows: string[] }>();
    for (const row of playing) {
      const info = card(row.cardName);
      if (!info) continue;
      const prior = groups.get(info.name);
      groups.set(info.name, { info, total: (prior?.total ?? 0) + row.quantity, rows: [...(prior?.rows ?? []), row.id] });
    }
    result.set("duplicate", new Set([...groups.values()].filter((group) => {
      const limit = copyLimit(group.info);
      return limit !== undefined && group.total > limit;
    }).flatMap((group) => group.rows)));
    for (const [issue, rows] of result) if (rows.size > 0) this.flagged.set(issue, rows);
  }

  /** The catalogue-backed check: the resolver decides playability when it is loaded, else the catalogue. */
  static of(draft: DeckDraft, catalogue: Catalogue | undefined, canonicalName?: (name: string) => string | undefined): Preflight {
    const resolves = canonicalName ? (name: string) => canonicalName(name) !== undefined
      : catalogue ? (name: string) => catalogue.card(name) !== undefined : undefined;
    return new Preflight(draft, (name) => catalogue?.card(name), resolves);
  }

  rows(issue: PreflightIssue): ReadonlySet<string> { return this.flagged.get(issue) ?? new Set(); }
  issues(rowID: string): PreflightIssue[] { return preflightIssues.filter((issue) => this.flagged.get(issue)?.has(rowID) === true); }
  get issueCount(): number { return (this.missingCommander ? 1 : 0) + [...this.flagged.values()].reduce((sum, rows) => sum + rows.size, 0); }
  /** Chips with something to show, in a fixed order. */
  get activeIssues(): PreflightIssue[] {
    return preflightIssues.filter((issue) => (issue === "missingCommander" ? this.missingCommander : this.rows(issue).size > 0));
  }
  /** Row issues add " · N" with the number of affected rows. */
  chipTitle(issue: PreflightIssue): string {
    return issue === "missingCommander" ? PreflightIssue.title(issue) : `${PreflightIssue.title(issue)} · ${this.rows(issue).size}`;
  }
  /** "3 cards to go · 2 issues", "1 card over · No issues found". */
  get summary(): string {
    const parts: string[] = [];
    if (this.count < Preflight.targetCount) parts.push(`${cardCountLabel(Preflight.targetCount - this.count)} to go`);
    if (this.count > Preflight.targetCount) parts.push(`${cardCountLabel(this.count - Preflight.targetCount)} over`);
    parts.push(this.issueCount === 0 ? "No issues found" : issueCountText(this.issueCount));
    return parts.join(" · ");
  }
}
