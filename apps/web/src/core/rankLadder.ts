/**
 * Port of RankLadder.swift (Android RankLadder.kt): the ranked ladder (1v1). Bronze to Diamond in four divisions
 * each (IV lowest, I highest), then Mythic. Four pips fill a division. Wins and losses both move you, so you can
 * rank down too. Checked by test/rankLadder.test.ts against parity/ranked-cases.json.
 */

export type RankTier = "bronze" | "silver" | "gold" | "platinum" | "diamond" | "mythic";
export const RankTier = {
  all: ["bronze", "silver", "gold", "platinum", "diamond", "mythic"] as RankTier[],
  /** Swift's raw value, 0 (Bronze) to 5 (Mythic); tiers compare by it. */
  index: (tier: RankTier) => RankTier.all.indexOf(tier),
  at: (index: number): RankTier => RankTier.all[index] ?? "bronze",
  min: (a: RankTier, b: RankTier): RankTier => (RankTier.index(a) <= RankTier.index(b) ? a : b),
  name: (tier: RankTier) => tier.charAt(0).toUpperCase() + tier.slice(1),
  /** The badge art (iOS Assets.xcassets tavern-rank-*). */
  assetName: (tier: RankTier) => `tavern-rank-${tier}`,
  /**
   * Brackets your opponents' decks come from at this tier, as [lower, upper]. Bracket 1 is never asked for: the
   * Exhibition AI decks are tribal lists no weaker than Core, so Bronze plays precons instead.
   */
  opponentBrackets(tier: RankTier): [number, number] {
    switch (tier) {
      case "bronze": case "silver": return [2, 2];
      case "gold": return [2, 3];
      case "platinum": return [3, 3];
      case "diamond": return [3, 4];
      case "mythic": return [4, 4];
    }
  },
  /** The strongest deck you may queue with here. A weaker deck is allowed and earns an extra pip per win. */
  maxDeckBracket: (tier: RankTier) => RankTier.opponentBrackets(tier)[1],
  /** Pips a ranked win earns here (Arena's Bo1 steps; ladder option B, Caleb 2026-10-15): two up to Gold, one from Platinum. */
  winPips: (tier: RankTier) => (RankTier.index(tier) <= RankTier.index("gold") ? 2 : 1),
  /** Pips a ranked loss costs here: none in Bronze. */
  lossPips: (tier: RankTier) => (tier === "bronze" ? 0 : 1),
  /** Bronze AI opponents play only the official precons, the gentlest decks in the pool. */
  preconOpponentsOnly: (tier: RankTier) => tier === "bronze",
  /**
   * XMage AI skill for AI opponents at this tier (AIDifficulty.java): Bronze to Gold look fewer moves ahead and make
   * deliberate mistakes, Platinum plays upstream's full strength, Diamond and Mythic play as experts. Mythic stops at 6.
   */
  aiSkill: (tier: RankTier) => RankTier.index(tier) + 1,
} as const;

/**
 * A place on the ladder. `division` is 4 (lowest) to 1, 0 for Mythic; `pips` is 0–3 below Mythic and counts up
 * without limit in Mythic. Plain data (it is stored as JSON); build one with `RankPosition.make` to normalise it.
 */
export interface RankPosition { tier: RankTier; division: number; pips: number }
export const RankPosition = {
  pipsPerDivision: 4,
  divisions: 4,
  /** Steps below Mythic: five tiers of four divisions. */
  mythicStep: 20,

  /** Swift's memberwise init: clamps division and pips. */
  make(tier: RankTier, division: number, pips: number): RankPosition {
    return {
      tier,
      division: tier === "mythic" ? 0 : Math.min(4, Math.max(1, division)),
      pips: Math.max(0, tier === "mythic" ? pips : Math.min(RankPosition.pipsPerDivision - 1, pips)),
    };
  },

  /** Every pip ever earned, as one number, back to a place. */
  fromPoints(value: number): RankPosition {
    const points = Math.max(0, value);
    const step = Math.floor(points / RankPosition.pipsPerDivision);
    if (step >= RankPosition.mythicStep) return RankPosition.make("mythic", 0, points - RankPosition.mythicStep * RankPosition.pipsPerDivision);
    return RankPosition.make(RankTier.at(Math.floor(step / RankPosition.divisions)), RankPosition.divisions - (step % RankPosition.divisions),
      points % RankPosition.pipsPerDivision);
  },

  atStep: (step: number) => RankPosition.fromPoints(Math.max(0, Math.min(RankPosition.mythicStep, step)) * RankPosition.pipsPerDivision),

  /** A standing as the profile server keeps it: the ladder step and pips. */
  published(step: number, pips: number): RankPosition {
    const base = RankPosition.atStep(step);
    return RankPosition.make(base.tier, base.division, pips);
  },

  start: { tier: "bronze", division: 4, pips: 0 } as RankPosition,

  /** 0 (Bronze IV) to 20 (Mythic). */
  step: (p: RankPosition) => (p.tier === "mythic" ? RankPosition.mythicStep : RankTier.index(p.tier) * RankPosition.divisions + (RankPosition.divisions - p.division)),
  /** Every pip ever earned, as one number: losing below 0 pips steps down a division. */
  points: (p: RankPosition) => RankPosition.step(p) * RankPosition.pipsPerDivision + p.pips,

  compare: (a: RankPosition, b: RankPosition) => RankPosition.points(a) - RankPosition.points(b),
  equal: (a: RankPosition, b: RankPosition) => a.tier === b.tier && a.division === b.division && a.pips === b.pips,
  max: (a: RankPosition, b: RankPosition) => (RankPosition.compare(a, b) < 0 ? b : a),

  divisionNumeral: (p: RankPosition) => ["", "I", "II", "III", "IV"][Math.min(4, Math.max(0, p.division))],
  /** "Gold II", "Mythic". */
  title: (p: RankPosition) => (p.tier === "mythic" ? RankTier.name(p.tier) : `${RankTier.name(p.tier)} ${RankPosition.divisionNumeral(p)}`),

  /** The AI's bracket here: the lower bracket of a tier's range in divisions IV–III, the upper in II–I. */
  opponentBracket(p: RankPosition): number {
    const [lower, upper] = RankTier.opponentBrackets(p.tier);
    return p.division >= 3 ? lower : upper;
  },
} as const;

export type RankOutcome = "win" | "loss" | "draw";

/** A third straight win below Gold (declared, never awarded: parity case "no streak bonus"), or a win with a deck below the tier's opponent brackets. */
export type RankBonus = "streak" | "underdog";
export type RankChangeKind = "none" | "pipUp" | "pipDown" | "divisionUp" | "divisionDown" | "tierUp" | "tierDown";

/** How one ranked result moved you. */
export interface RankChange { outcome: RankOutcome; before: RankPosition; after: RankPosition; bonuses: RankBonus[] }
export const RankChange = {
  pipDelta: (change: RankChange) => RankPosition.points(change.after) - RankPosition.points(change.before),
  kind(change: RankChange): RankChangeKind {
    const { before, after } = change;
    if (after.tier !== before.tier) return RankTier.index(after.tier) > RankTier.index(before.tier) ? "tierUp" : "tierDown";
    if (after.division !== before.division) return after.division < before.division ? "divisionUp" : "divisionDown";
    if (after.pips !== before.pips) return after.pips > before.pips ? "pipUp" : "pipDown";
    return "none";
  },
} as const;

export interface SeasonRecord { season: string; final: RankPosition; peak: RankPosition; wins: number; losses: number }

/** The player's ranked standing for the current season, plus past seasons (newest first). */
export interface RankState {
  season: string;
  position: RankPosition;
  peak: RankPosition;
  wins: number;
  losses: number;
  draws: number;
  winStreak: number;
  history: SeasonRecord[];
}
export const RankState = {
  fresh: (season: string): RankState =>
    ({ season, position: RankPosition.start, peak: RankPosition.start, wins: 0, losses: 0, draws: 0, winStreak: 0, history: [] }),
} as const;

const DAY = 86_400_000;

export const RankLadder = {
  /** Seasons are calendar months in UTC: "2026-10". */
  season(date: Date | number): string {
    const value = new Date(date);
    return `${String(value.getUTCFullYear()).padStart(4, "0")}-${String(value.getUTCMonth() + 1).padStart(2, "0")}`;
  },

  /** When a season ends (the next month starts, UTC); undefined for a malformed season. */
  seasonEnd(season: string): Date | undefined {
    // Swift: split on "-" (empty pieces dropped), keep the pieces that read as integers, expect exactly two.
    const parts = season.split("-").filter((piece) => piece.length > 0 && /^[+-]?\d+$/.test(piece)).map(Number);
    if (parts.length !== 2) return undefined;
    return new Date(Date.UTC(parts[0], parts[1], 1));
  },

  /** "October 2026" (in `locale`, the browser's by default). */
  seasonName(season: string, locale?: string): string {
    const end = RankLadder.seasonEnd(season);
    if (end === undefined) return season;
    return new Intl.DateTimeFormat(locale, { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(end.getTime() - DAY));
  },

  /**
   * A new month: last season goes into history and everyone drops one tier (Mythic to Diamond IV), keeping their
   * division, with empty pips. The same season returns `state` itself.
   */
  rollover(state: RankState, season: string): RankState {
    if (state.season === season) return state;
    const next = RankState.fresh(season);
    const played = state.wins + state.losses + state.draws > 0;
    next.history = played
      ? [{ season: state.season, final: state.position, peak: state.peak, wins: state.wins, losses: state.losses }, ...state.history]
      : [...state.history];
    next.history = next.history.slice(0, 24);
    next.position = RankPosition.atStep(RankPosition.step(state.position) - RankPosition.divisions);
    next.peak = next.position;
    return next;
  },

  /** One ranked result. `deckBracket` is your deck's bracket, for the underdog pip. */
  apply(outcome: RankOutcome, state: RankState, deckBracket: number): { state: RankState; change: RankChange } {
    const next: RankState = { ...state };
    const bonuses: RankBonus[] = [];
    const tier = state.position.tier;
    let delta = 0;
    switch (outcome) {
      case "win":
        next.wins += 1;
        next.winStreak += 1;
        delta = RankTier.winPips(tier);
        if (deckBracket < RankTier.opponentBrackets(tier)[0]) { delta += 1; bonuses.push("underdog"); }
        break;
      case "loss":
        next.losses += 1;
        next.winStreak = 0;
        delta = -RankTier.lossPips(tier);
        break;
      case "draw":
        next.draws += 1;
        next.winStreak = 0;
        break;
    }
    // A loss never takes you out of your tier (Mythic can fall back to Diamond, never below Diamond IV).
    const floor = RankPosition.points(RankPosition.atStep(RankTier.index(RankTier.min(tier, "diamond")) * RankPosition.divisions));
    next.position = RankPosition.fromPoints(Math.max(RankPosition.points(state.position) + delta, floor));
    next.peak = RankPosition.max(next.peak, next.position);
    return { state: next, change: { outcome, before: state.position, after: next.position, bonuses } };
  },
} as const;
