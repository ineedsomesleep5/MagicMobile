/**
 * Port of PlayerRecord.swift (Android PlayerRecord.kt): the player's profile kept in this browser (ranked standing,
 * match history, chosen title), the profile's stats and achievements. Checked by test/playerRecord.test.ts (the
 * cases of iOS PlayerRecordStoreTests).
 *
 * Stored as one JSON string under `mm.web.playerRecord` (dates are milliseconds since 1970, like iOS's file):
 *
 *   { "rank": { "season": "2026-10", "position": {"tier": "bronze", "division": 4, "pips": 2},
 *               "peak": {…}, "wins": 1, "losses": 0, "draws": 0, "winStreak": 1,
 *               "history": [{"season": "2026-09", "final": {…}, "peak": {…}, "wins": 3, "losses": 1}] },
 *     "matches": [ newest first, at most 300: {"id": "<uuid>", "date": 1791000000000, "mode": "ranked",
 *                  "opponents": [{"name": "Foe", "commander": "Edgar Markov", "isAI": true}],
 *                  "opponentBracket": 2, "aiSkill": 1, "deckID": "token-triumph", "deckName": "Token Triumph",
 *                  "commander": "Emmara, Soul of the Accord", "colors": ["G", "W"], "deckBracket": 2,
 *                  "outcome": "win", "turns": 9, "rankChange": {"outcome", "before", "after", "bonuses"},
 *                  "season": "2026-10", "engineMatchID": "…", "rankedTicket": "…", "settlement": "unverified",
 *                  "settlementCheck": "too_short"} ],
 *     "title": "firstWin", "favoriteCommander": "Krenko, Mob Boss", "recentAIDecks": ["ai-edgar-markov-core"] }
 *
 * Optional fields are left out when absent. Positions use the tier names of parity/ranked-cases.json.
 */
import {
  type RankBonus, type RankChange, RankLadder, type RankOutcome, RankPosition, RankSettlement, RankState, RankTier, type ServerRankChange,
} from "./rankLadder";

/** Where the record lives: `storage` from ui/storage.ts in the app, a Map-backed object in tests. */
export interface KeyValueStore { get(key: string): string | undefined | null; set(key: string, value: string): void }

/** How a game was started, for the profile and for what a result does to your rank. */
export type PlayMode = "quick" | "ranked" | "casual";
/** Who goes first: Ranked always rolls, since picking yourself would be an edge on the ladder; the others keep the player's "choose" or "roll". */
export const startingPlayerMode = (mode: PlayMode, preference: string) => (mode === "ranked" ? "roll" : preference);

export interface MatchOpponent { name: string; commander?: string; isAI: boolean }

/** One finished game in this browser. Only what the player saw: names, commanders, the result. */
export interface MatchRecord {
  id: string;
  date: number;
  mode: PlayMode;
  opponents: MatchOpponent[];
  /** The AI's bracket and skill, when the opponent was an AI. */
  opponentBracket?: number;
  aiSkill?: number;
  deckID: string;
  deckName: string;
  commander?: string;
  /** Your commander's colors, W U B R G order. */
  colors: string[];
  deckBracket: number;
  outcome: RankOutcome;
  turns: number;
  /** The browser's count at once; the server's once it answers (PlayerRecordStore.settleRanked). */
  rankChange?: RankChange;
  season?: string;
  /** The engine's id for the game, when it kept a detailed record. */
  engineMatchID?: string;
  /** A ranked AI game's server ticket, so the server's answer finds this game. */
  rankedTicket?: string;
  /** How the server counted it (counted, too_soon, capped, unverified) and, for an unverified win, why. */
  settlement?: string;
  settlementCheck?: string;
}

export const vsHuman = (match: MatchRecord) => match.opponents.some((opponent) => !opponent.isAI);
/** Why a ranked win left the ladder alone, as the player reads it; undefined when it counted (MatchRecord.rankNote). */
export const rankNote = (match: MatchRecord) => RankSettlement.note(match.settlement, match.settlementCheck, match.deckBracket);

const WUBRG = ["W", "U", "B", "R", "G"];

export const colorName = (symbol: string) => ({ W: "White", U: "Blue", B: "Black", R: "Red", G: "Green" } as Record<string, string>)[symbol] ?? symbol;

/** A commander's colors from its mana cost ("{2}{R}{R}" -> ["R"]), hybrid symbols included. */
export function colorsFromManaCost(manaCost: string | undefined | null): string[] {
  if (manaCost == null) return [];
  const found = new Set([...manaCost.toUpperCase()].filter((c) => WUBRG.includes(c)));
  return WUBRG.filter((c) => found.has(c));
}

export interface StatsLine { id: string; label: string; detail?: string; games: number; wins: number }
export const lineWinRate = (line: StatsLine) => (line.games === 0 ? 0 : line.wins / line.games);

/** Wins and losses as the profile shows them (PlayerStats). */
export interface PlayerStats {
  games: number; wins: number; losses: number; draws: number;
  averageTurns?: number; currentStreak: number; bestStreak: number;
  decks: StatsLine[]; commanders: StatsLine[];
  /** W U B R G: games and wins with a commander of that color. */
  colors: StatsLine[];
}
export const statsWinRate = (stats: PlayerStats) => (stats.games === 0 ? 0 : stats.wins / stats.games);

export function playerStats(matches: MatchRecord[]): PlayerStats {
  const stats: PlayerStats = { games: 0, wins: 0, losses: 0, draws: 0, currentStreak: 0, bestStreak: 0, decks: [], commanders: [], colors: [] };
  const decks = new Map<string, StatsLine>(), commanders = new Map<string, StatsLine>(), colors = new Map<string, StatsLine>();
  const line = (map: Map<string, StatsLine>, id: string, label: string, detail?: string) => {
    let found = map.get(id);
    if (!found) { found = { id, label, ...(detail !== undefined ? { detail } : {}), games: 0, wins: 0 }; map.set(id, found); }
    return found;
  };
  let turnTotal = 0, turnGames = 0, streak = 0;
  // The record keeps the newest game first; streaks read oldest first.
  for (const match of [...matches].reverse()) {
    stats.games += 1;
    const won = match.outcome === "win";
    if (match.outcome === "win") { stats.wins += 1; streak += 1; stats.bestStreak = Math.max(stats.bestStreak, streak); }
    else if (match.outcome === "loss") { stats.losses += 1; streak = 0; }
    else { stats.draws += 1; streak = 0; }
    if (match.turns > 0) { turnTotal += match.turns; turnGames += 1; }
    const deck = line(decks, match.deckID, match.deckName, match.commander);
    deck.games += 1; if (won) deck.wins += 1;
    if (match.commander !== undefined) { const c = line(commanders, match.commander, match.commander); c.games += 1; if (won) c.wins += 1; }
    for (const color of match.colors) { const c = line(colors, color, colorName(color)); c.games += 1; if (won) c.wins += 1; }
  }
  stats.currentStreak = streak;
  if (turnGames > 0) stats.averageTurns = turnTotal / turnGames;
  const byPlay = (a: StatsLine, b: StatsLine) => (a.games !== b.games ? b.games - a.games : a.label < b.label ? -1 : a.label > b.label ? 1 : 0);
  stats.decks = [...decks.values()].sort(byPlay);
  stats.commanders = [...commanders.values()].sort(byPlay);
  stats.colors = WUBRG.flatMap((c) => (colors.has(c) ? [colors.get(c)!] : []));
  return stats;
}

/** Milestones; each unlocks a title the player can show on their profile. */
export type Achievement =
  | "firstWin" | "firstRankedWin" | "silver" | "gold" | "platinum" | "diamond" | "mythic"
  | "streak5" | "veteran" | "prismatic" | "giantSlayer" | "quickDraw" | "humanWin";
export const Achievement = {
  all: ["firstWin", "firstRankedWin", "silver", "gold", "platinum", "diamond", "mythic",
    "streak5", "veteran", "prismatic", "giantSlayer", "quickDraw", "humanWin"] as Achievement[],
  title: (a: Achievement) => ({
    firstWin: "Rising Star", firstRankedWin: "Contender", silver: "Silver Blade", gold: "Gold Champion", platinum: "Platinum Warden",
    diamond: "Diamond Duelist", mythic: "Mythic Legend", streak5: "Unstoppable", veteran: "Tavern Veteran", prismatic: "Prismatic",
    giantSlayer: "Giant Slayer", quickDraw: "Quick Draw", humanWin: "Duelist",
  })[a],
  detail: (a: Achievement) => ({
    firstWin: "Win your first game.", firstRankedWin: "Win a ranked match.", silver: "Reach Silver.", gold: "Reach Gold.",
    platinum: "Reach Platinum.", diamond: "Reach Diamond.", mythic: "Reach Mythic.", streak5: "Win five games in a row.",
    veteran: "Play 50 games.", prismatic: "Win with a commander of each color.",
    giantSlayer: "Win a ranked match with a deck below the tier's bracket.", quickDraw: "Win 10 Quick Matches.",
    humanWin: "Beat another player online.",
  })[a],

  /** What the record has earned. Tiers count the best rank ever reached, in any season. */
  unlocked(matches: MatchRecord[], rank: RankState): Set<Achievement> {
    const set = new Set<Achievement>();
    const wins = matches.filter((match) => match.outcome === "win");
    if (wins.length > 0) set.add("firstWin");
    if (wins.some((match) => match.mode === "ranked")) set.add("firstRankedWin");
    if (wins.some((match) => match.mode !== "quick" && vsHuman(match))) set.add("humanWin");
    const best = [rank.peak, ...rank.history.map((season) => season.peak)].reduce(RankPosition.max);
    for (const tier of ["silver", "gold", "platinum", "diamond", "mythic"] as const) {
      if (RankTier.index(best.tier) >= RankTier.index(tier)) set.add(tier);
    }
    if (playerStats(matches).bestStreak >= 5) set.add("streak5");
    if (matches.length >= 50) set.add("veteran");
    const wonColors = new Set(wins.flatMap((match) => match.colors));
    if (WUBRG.every((c) => wonColors.has(c))) set.add("prismatic");
    if (wins.some((match) => match.rankChange?.bonuses.includes("underdog") === true)) set.add("giantSlayer");
    if (wins.filter((match) => match.mode === "quick").length >= 10) set.add("quickDraw");
    return set;
  },
} as const;

/**
 * A ranked game against the AI whose result the server hasn't confirmed yet (iOS PlayerRecordStore.pendingRankedResults):
 * its ticket, the outcome, and with a seeded ticket the engine's game record, kept under `recordFile` until it is sent.
 */
export interface PendingRanked { ticket: string; outcome: RankOutcome; date: number; seeded?: boolean; recordFile?: string }

interface RecordFile {
  rank: RankState;
  matches: MatchRecord[];
  title?: Achievement;
  favoriteCommander?: string;
  recentAIDecks?: string[];
  pendingRankedResults?: PendingRanked[];
}

const isObject = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const isPosition = (value: unknown): value is RankPosition =>
  isObject(value) && RankTier.all.includes(value.tier as RankTier) && Number.isInteger(value.division) && Number.isInteger(value.pips);
const isRank = (value: unknown): value is RankState =>
  isObject(value) && typeof value.season === "string" && isPosition(value.position) && isPosition(value.peak) &&
  ["wins", "losses", "draws", "winStreak"].every((key) => Number.isInteger(value[key])) && Array.isArray(value.history);

/** A finished game as `PlayerRecordStore.record` takes it. */
export interface FinishedGame {
  mode: PlayMode; outcome: RankOutcome; opponents: MatchOpponent[]; opponentBracket?: number; aiSkill?: number;
  deckID: string; deckName: string; commander?: string; colors: string[]; deckBracket: number; turns: number;
  aiDeckID?: string; engineMatchID?: string;
  /** The server's ticket for a ranked game against the AI. */
  rankedTicket?: string;
}

/**
 * The player's profile in this browser (PlayerRecordStore): with an account, ranked results wait here with their game
 * records until the server confirms them, and the server's standing replaces the browser's (adoptRank). A malformed
 * saved record starts fresh, like iOS.
 */
export class PlayerRecordStore {
  static readonly maxMatches = 300;
  static readonly key = "mm.web.playerRecord";

  private _rank: RankState;
  private _matches: MatchRecord[];
  private _title?: Achievement;
  private _favoriteCommander?: string;
  /** The last AI decks faced, so the next pick is a different one. */
  private _recentAIDecks: string[];
  private _pending: PendingRanked[];
  /** Records the browser's storage refused (full or blocked), held for this page so the result still goes with one. */
  private readonly heldRecords = new Map<string, string>();

  constructor(private readonly store: KeyValueStore, private readonly now: () => number = Date.now, private readonly key = PlayerRecordStore.key) {
    const season = RankLadder.season(now());
    let loaded: RecordFile = { rank: RankState.fresh(season), matches: [] };
    try {
      const raw = store.get(key);
      const parsed: unknown = raw ? JSON.parse(raw) : undefined;
      if (isObject(parsed) && isRank(parsed.rank) && Array.isArray(parsed.matches)) loaded = parsed as unknown as RecordFile;
    } catch { /* a malformed record starts fresh */ }
    this._rank = RankLadder.rollover(loaded.rank, season);
    this._matches = loaded.matches;
    this._title = Achievement.all.includes(loaded.title as Achievement) ? loaded.title : undefined;
    this._favoriteCommander = typeof loaded.favoriteCommander === "string" ? loaded.favoriteCommander : undefined;
    this._recentAIDecks = Array.isArray(loaded.recentAIDecks) ? loaded.recentAIDecks.filter((id) => typeof id === "string") : [];
    this._pending = Array.isArray(loaded.pendingRankedResults)
      ? loaded.pendingRankedResults.filter((p) => isObject(p) && typeof p.ticket === "string" && ["win", "loss", "draw"].includes(p.outcome as string)) : [];
    if (this._rank !== loaded.rank) this.save();
  }

  get rank(): RankState { return this._rank; }
  get matches(): readonly MatchRecord[] { return this._matches; }
  get recentAIDecks(): readonly string[] { return this._recentAIDecks; }
  get title(): Achievement | undefined { return this._title; }
  set title(value: Achievement | undefined) { if (value !== this._title) { this._title = value; this.save(); } }
  get favoriteCommander(): string | undefined { return this._favoriteCommander; }
  set favoriteCommander(value: string | undefined) { if (value !== this._favoriteCommander) { this._favoriteCommander = value; this.save(); } }

  get stats(): PlayerStats { return playerStats(this._matches); }
  get achievements(): Set<Achievement> { return Achievement.unlocked(this._matches, this._rank); }
  /** The favorite commander chosen, or the one played most. */
  get shownCommander(): string | undefined { return this._favoriteCommander ?? this.stats.commanders[0]?.label; }

  get pendingRankedResults(): readonly PendingRanked[] { return this._pending; }

  /** The server's standing replaces this browser's (PlayerAccount.syncRank through adoptStanding). */
  adoptRank(rank: RankState): void { this._rank = rank; this.save(); }

  /** A finished ranked AI game to send, with its game record kept under its ticket. */
  addPendingRanked(result: Omit<PendingRanked, "recordFile">, gameRecord?: unknown): void {
    let recordFile: string | undefined;
    if (gameRecord !== undefined) {
      recordFile = `${this.key}.game.${result.ticket}`;
      const text = JSON.stringify(gameRecord);
      try { this.store.set(recordFile, text); } catch { this.heldRecords.set(recordFile, text); }
    }
    this._pending = [...this._pending.filter((p) => p.ticket !== result.ticket), { ...result, ...(recordFile ? { recordFile } : {}) }];
    this.save();
  }

  /** The kept game record for a pending result. */
  gameRecord(name: string): unknown {
    try { const raw = this.heldRecords.get(name) ?? this.store.get(name); return raw ? JSON.parse(raw) : undefined; } catch { return undefined; }
  }

  /** The server answered for this ticket (or never will): its record is dropped. */
  resolvePendingRanked(ticket: string): void {
    const done = this._pending.find((p) => p.ticket === ticket);
    if (!done) return;
    if (done.recordFile) {
      this.heldRecords.delete(done.recordFile);
      try { this.store.set(done.recordFile, ""); } catch { /* storage blocked */ }
    }
    this._pending = this._pending.filter((p) => p.ticket !== ticket);
    this.save();
  }

  /** The server's answer for a ranked AI game: how it counted, and its own move on the ladder in place of the browser's. */
  settleRanked(ticket: string, settlement: string | undefined, check: string | undefined, change: ServerRankChange | undefined): void {
    const index = this._matches.findIndex((m) => m.rankedTicket === ticket);
    if (index < 0) return;
    const match: MatchRecord = { ...this._matches[index] };
    delete match.settlement; delete match.settlementCheck;
    if (settlement !== undefined) match.settlement = settlement;
    if (check !== undefined) match.settlementCheck = check;
    if (change) {
      match.rankChange = {
        outcome: match.outcome, before: RankPosition.fromPoints(change.pointsBefore), after: RankPosition.fromPoints(change.pointsAfter),
        bonuses: (change.bonuses ?? []).filter((b): b is RankBonus => b === "streak" || b === "underdog"),
      };
    } else if (RankSettlement.held(settlement) && match.rankChange) {
      match.rankChange = { ...match.rankChange, after: match.rankChange.before, bonuses: [] };
    }
    if (JSON.stringify(match) === JSON.stringify(this._matches[index])) return;
    this._matches = this._matches.map((m, i) => (i === index ? match : m));
    this.save();
  }

  /** A new month started while the page was open. */
  refreshSeason(): void {
    const season = RankLadder.season(this.now());
    if (season === this._rank.season) return;
    this._rank = RankLadder.rollover(this._rank, season);
    this.save();
  }

  /** Records a finished game. A ranked game moves the ladder and returns how. */
  record(game: FinishedGame): RankChange | undefined {
    this.refreshSeason();
    let change: RankChange | undefined;
    if (game.mode === "ranked") {
      const result = RankLadder.apply(game.outcome, this._rank, game.deckBracket);
      this._rank = result.state;
      change = result.change;
    }
    const match: MatchRecord = {
      id: globalThis.crypto.randomUUID(), date: this.now(), mode: game.mode, opponents: game.opponents,
      ...(game.opponentBracket !== undefined ? { opponentBracket: game.opponentBracket } : {}),
      ...(game.aiSkill !== undefined ? { aiSkill: game.aiSkill } : {}),
      deckID: game.deckID, deckName: game.deckName,
      ...(game.commander !== undefined ? { commander: game.commander } : {}),
      colors: game.colors, deckBracket: game.deckBracket, outcome: game.outcome, turns: game.turns,
      ...(change ? { rankChange: change } : {}),
      ...(game.mode === "ranked" ? { season: this._rank.season } : {}),
      ...(game.engineMatchID !== undefined ? { engineMatchID: game.engineMatchID } : {}),
      ...(game.mode === "ranked" && game.rankedTicket !== undefined && game.opponents.every((o) => o.isAI) ? { rankedTicket: game.rankedTicket } : {}),
    };
    this._matches = [match, ...this._matches].slice(0, PlayerRecordStore.maxMatches);
    const aiDeckID = game.aiDeckID;
    if (aiDeckID !== undefined) this._recentAIDecks = [aiDeckID, ...this._recentAIDecks.filter((id) => id !== aiDeckID)].slice(0, 4);
    this.save();
    return change;
  }

  private save(): void {
    const file: RecordFile = {
      rank: this._rank, matches: this._matches,
      ...(this._title !== undefined ? { title: this._title } : {}),
      ...(this._favoriteCommander !== undefined ? { favoriteCommander: this._favoriteCommander } : {}),
      recentAIDecks: this._recentAIDecks,
      ...(this._pending.length > 0 ? { pendingRankedResults: this._pending } : {}),
    };
    // The profile is a convenience; a failed save never interrupts play.
    try { this.store.set(this.key, JSON.stringify(file)); } catch { /* storage full or blocked */ }
  }
}
