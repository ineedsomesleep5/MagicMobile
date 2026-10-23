/**
 * Port of ProfileAnalytics.swift's ProfileGame and ProfileSummary (Android ProfileAnalytics.kt): the numbers behind a
 * profile's pictures (record, streaks, the last eight weeks, commanders, colors and rank over time), built from this
 * browser's games. Checked by test/profileSummary.test.ts against parity/profile-cases.json, as iOS and Android are.
 * Dates are milliseconds since 1970. The public-profile and player-search parts wait for accounts on the web.
 */
import type { MatchOpponent, MatchRecord, PlayMode } from "./playerRecord";
import { RankChange, type RankOutcome, RankPosition } from "./rankLadder";

/** One finished game as a profile shows it. */
export interface ProfileGame {
  id: string;
  date: number;
  mode: PlayMode;
  outcome: RankOutcome;
  deckName: string;
  commanders: string[];
  colors: string[];
  opponents: (MatchOpponent & { hidden?: boolean })[];
  /** Undefined when the game's length wasn't recorded. */
  turns?: number;
  /** Pips a ranked game moved. */
  rankDelta?: number;
}

export const ProfileGame = {
  from(match: MatchRecord): ProfileGame {
    return {
      id: match.id, date: match.date, mode: match.mode, outcome: match.outcome, deckName: match.deckName,
      commanders: match.commander !== undefined ? [match.commander] : [], colors: match.colors,
      opponents: match.opponents.map((o) => ({ name: o.name, ...(o.commander !== undefined ? { commander: o.commander } : {}), isAI: o.isAI })),
      ...(match.turns > 0 ? { turns: match.turns } : {}),
      ...(match.rankChange ? { rankDelta: RankChange.pipDelta(match.rankChange) } : {}),
    };
  },
  commander: (game: ProfileGame) => game.commanders[0],
  vsHuman: (game: ProfileGame) => game.opponents.some((o) => !o.isAI),
  /** "Foe", "a player" for a hidden name, "3 opponents", or "Opponent" when none were recorded. */
  opponentText(game: ProfileGame): string {
    const names = game.opponents.map((o) => (o.hidden ? "a player" : o.name));
    return names.length <= 1 ? (names[0] ?? "Opponent") : `${names.length} opponents`;
  },
  modeText(game: ProfileGame): string {
    switch (game.mode) {
      case "quick": return "Quick";
      case "ranked": return ProfileGame.vsHuman(game) ? "Ranked · Player" : "Ranked · AI";
      case "casual": return "Custom";
    }
  },
  resultLetter: (game: ProfileGame) => ({ win: "W", loss: "L", draw: "D" })[game.outcome],
  resultName: (game: ProfileGame) => ({ win: "Won", loss: "Lost", draw: "Drawn" })[game.outcome],
} as const;

export interface ProfileShare { id: string; games: number; wins: number }
export interface ProfileWeek {
  /** Monday 00:00 UTC. */
  start: number;
  games: number;
  wins: number;
}
export interface ProfileRankPoint {
  date: number;
  /** The standing as one number: ladder step * 4 + pips. */
  points: number;
}

export interface ProfileSummary {
  games: number;
  wins: number;
  losses: number;
  draws: number;
  currentStreak: number;
  bestStreak: number;
  averageTurns?: number;
  /** The last eight weeks, oldest first, empty weeks included. */
  weeks: ProfileWeek[];
  /** Most played first, at most six. */
  commanders: ProfileShare[];
  /** W U B R G, each with the games played with a commander of that color. */
  colors: ProfileShare[];
  /** Ranked standings over time, oldest first. */
  rankPoints: ProfileRankPoint[];
}

const DAY = 86_400_000;
const WEEK = 7 * DAY;

/** A whole percentage, rounded as iOS rounds it; 0 with no games. */
export const percent = (part: number, whole: number) => (whole === 0 ? 0 : Math.round((part / whole) * 100));

export const ProfileSummary = {
  weekCount: 8,
  maxCommanders: 6,
  colorOrder: ["W", "U", "B", "R", "G"] as string[],

  winRate: (summary: ProfileSummary) => (summary.games === 0 ? 0 : summary.wins / summary.games),
  shareWinRate: (share: ProfileShare) => (share.games === 0 ? 0 : share.wins / share.games),
  /** A standing for the rank-history line: the ladder's own position for a points value. */
  position: (point: ProfileRankPoint) => RankPosition.fromPoints(point.points),

  /** The Monday 00:00 UTC that starts `date`'s week, like the server's date_trunc('week'). */
  weekStart(date: number): number {
    const day = Math.floor(date / DAY) * DAY;
    const weekday = (new Date(day).getUTCDay() + 6) % 7; // Monday 0 … Sunday 6
    return day - weekday * DAY;
  },

  /** A week's Monday as the server writes it: "2026-10-05". */
  dayText: (date: number) => new Date(date).toISOString().slice(0, 10),

  emptyWeeks(now: number): ProfileWeek[] {
    const current = ProfileSummary.weekStart(now);
    return Array.from({ length: ProfileSummary.weekCount }, (_, i) => ({
      start: current - (ProfileSummary.weekCount - 1 - i) * WEEK, games: 0, wins: 0,
    }));
  },

  /**
   * Games newest first. `rankPoints` is given separately: the rank history is the ranked games' standings, whatever
   * deck the totals are narrowed to.
   */
  fromGames(list: readonly ProfileGame[], now: number = Date.now(), rankPoints: ProfileRankPoint[] = []): ProfileSummary {
    const summary: ProfileSummary = {
      games: 0, wins: 0, losses: 0, draws: 0, currentStreak: 0, bestStreak: 0, weeks: [], commanders: [], colors: [], rankPoints,
    };
    let turnTotal = 0, turnGames = 0, streak = 0;
    const commanders = new Map<string, ProfileShare>(), colors = new Map<string, ProfileShare>();
    const count = (map: Map<string, ProfileShare>, id: string, won: boolean) => {
      const share = map.get(id) ?? { id, games: 0, wins: 0 };
      share.games += 1;
      if (won) share.wins += 1;
      map.set(id, share);
    };
    for (const game of [...list].reverse()) {
      summary.games += 1;
      const won = game.outcome === "win";
      if (game.outcome === "win") { summary.wins += 1; streak += 1; summary.bestStreak = Math.max(summary.bestStreak, streak); }
      else if (game.outcome === "loss") { summary.losses += 1; streak = 0; }
      else { summary.draws += 1; streak = 0; }
      if (game.turns !== undefined && game.turns > 0) { turnTotal += game.turns; turnGames += 1; }
      for (const commander of game.commanders) count(commanders, commander, won);
      for (const color of new Set(game.colors)) if (ProfileSummary.colorOrder.includes(color)) count(colors, color, won);
    }
    summary.currentStreak = streak;
    if (turnGames > 0) summary.averageTurns = turnTotal / turnGames;
    summary.commanders = [...commanders.values()]
      .sort((a, b) => (a.games !== b.games ? b.games - a.games : a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
      .slice(0, ProfileSummary.maxCommanders);
    summary.colors = ProfileSummary.colorOrder.flatMap((c) => (colors.has(c) ? [colors.get(c)!] : []));
    const weeks = ProfileSummary.emptyWeeks(now);
    for (const game of list) {
      const week = weeks.find((w) => w.start === ProfileSummary.weekStart(game.date));
      if (!week) continue;
      week.games += 1;
      if (game.outcome === "win") week.wins += 1;
    }
    summary.weeks = weeks;
    return summary;
  },

  /** The ranked games' standings after each game, oldest first, from the record (newest first). */
  rankPoints: (matches: readonly MatchRecord[]): ProfileRankPoint[] =>
    [...matches].reverse().flatMap((m) => (m.rankChange ? [{ date: m.date, points: RankPosition.points(m.rankChange.after) }] : [])),

  /** This browser's games, newest first (the record's order). `now` fixes the weeks for tests. */
  fromMatches: (matches: readonly MatchRecord[], now: number = Date.now()): ProfileSummary =>
    ProfileSummary.fromGames(matches.map(ProfileGame.from), now, ProfileSummary.rankPoints(matches)),

  /**
   * The profile's totals for one deck (or all with `deckID` undefined). The rank history stays the ranked standings of
   * every deck.
   */
  forDeck(matches: readonly MatchRecord[], deckID: string | undefined, now: number = Date.now()): ProfileSummary {
    const scoped = deckID === undefined ? matches : matches.filter((m) => m.deckID === deckID);
    return ProfileSummary.fromGames(scoped.map(ProfileGame.from), now, ProfileSummary.rankPoints(matches));
  },
} as const;

/** The rank-history chart's vertical range: three points of room each side, at least ten points tall. */
export function rankChartRange(values: readonly number[]): { low: number; high: number } {
  if (values.length === 0) return { low: 0, high: 10 };
  const low = Math.max(0, Math.min(...values) - 3);
  return { low, high: Math.max(low + 10, Math.max(...values) + 3) };
}

/**
 * The portrait choices besides "Most played": the commanders played most (up to 12), then the player's decks'
 * commanders not already offered, and a choice from a deck since deleted, which stays selectable.
 */
export function portraitChoices(playedCommanders: readonly string[], deckCommanders: readonly string[], favorite?: string): { played: string[]; decks: string[] } {
  const played = playedCommanders.slice(0, 12);
  const seen = new Set(played);
  const decks = deckCommanders.filter((name) => {
    if (name === "" || seen.has(name)) return false;
    seen.add(name);
    return true;
  });
  if (favorite !== undefined && !seen.has(favorite)) played.push(favorite);
  return { played, decks };
}
