/** The record kept in this browser: iOS PlayerRecordStoreTests, plus ranked-cases.json's colors rows. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  Achievement, colorsFromManaCost, type FinishedGame, type KeyValueStore, PlayerRecordStore, type PlayMode, startingPlayerMode,
} from "../src/core/playerRecord";
import { RankPosition, type RankOutcome } from "../src/core/rankLadder";

const root = join(__dirname, "..", "..", "..");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity/ranked-cases.json"), "utf8"));
const OCTOBER = 1_791_000_000_000;
const DECEMBER = 1_797_292_800_000;

const memory = () => {
  const map = new Map<string, string>();
  const store: KeyValueStore & { map: Map<string, string> } = { map, get: (k) => map.get(k), set: (k, v) => { map.set(k, v); } };
  return store;
};

const play = (store: PlayerRecordStore, mode: PlayMode, outcome: RankOutcome, options: Partial<FinishedGame> & { human?: boolean } = {}) =>
  store.record({
    mode, outcome, opponents: [{ name: "Foe", commander: "Edgar Markov", isAI: !options.human }], opponentBracket: 2, aiSkill: 3,
    deckID: "precon:x", deckName: "Goblins", commander: options.commander ?? "Krenko, Mob Boss", colors: options.colors ?? ["R"],
    deckBracket: options.deckBracket ?? 2, turns: 9, aiDeckID: "ai-edgar-markov-core",
  });

describe("player record", () => {
  it("ranked moves the ladder and quick does not", () => {
    let now = OCTOBER;
    const store = new PlayerRecordStore(memory(), () => now);
    expect(play(store, "quick", "win")).toBeUndefined();
    expect(store.rank.position).toEqual(RankPosition.start);
    const change = play(store, "ranked", "win");
    expect(change?.after).toEqual(RankPosition.make("bronze", 4, 2));
    expect(store.rank.wins).toBe(1);
    expect(store.matches.length).toBe(2);
    expect(store.matches[0].season).toBe("2026-10");
    expect(store.matches[1].season).toBeUndefined();
    expect(store.recentAIDecks).toEqual(["ai-edgar-markov-core"]);
    // A new season (quarterly from November 2026, so December is in "2026-11"): it rolls over before the next result counts.
    now = DECEMBER;
    play(store, "ranked", "loss");
    expect(store.rank.season).toBe("2026-11");
    expect(store.rank.history[0]?.season).toBe("2026-10");
    expect(store.rank.losses).toBe(1);
    expect(store.rank.wins).toBe(0);
  });

  it("refreshSeason rolls over a month that started while open, and a relaunch does too", () => {
    let now = OCTOBER;
    const backing = memory();
    const store = new PlayerRecordStore(backing, () => now);
    play(store, "ranked", "win");
    now = DECEMBER;
    expect(new PlayerRecordStore(backing, () => now).rank.season).toBe("2026-11");
    store.refreshSeason();
    expect(store.rank.season).toBe("2026-11");
    expect(store.rank.history.map((s) => s.season)).toEqual(["2026-10"]);
  });

  it("survives a relaunch", () => {
    const backing = memory();
    const store = new PlayerRecordStore(backing, () => OCTOBER);
    for (let i = 0; i < 5; i++) play(store, "ranked", "win");
    store.title = "firstWin";
    store.favoriteCommander = "Krenko, Mob Boss";
    const again = new PlayerRecordStore(backing, () => OCTOBER);
    expect(again.rank).toEqual(store.rank);
    expect(again.matches.length).toBe(5);
    expect(again.matches).toEqual(store.matches);
    expect(again.title).toBe("firstWin");
    expect(again.favoriteCommander).toBe("Krenko, Mob Boss");
    expect(again.recentAIDecks).toEqual(["ai-edgar-markov-core"]);
  });

  it("a malformed record starts fresh", () => {
    const backing = memory();
    backing.map.set(PlayerRecordStore.key, "{not json");
    expect(new PlayerRecordStore(backing, () => OCTOBER).rank.position).toEqual(RankPosition.start);
    backing.map.set(PlayerRecordStore.key, JSON.stringify({ rank: { season: "2026-10" }, matches: [] }));
    expect(new PlayerRecordStore(backing, () => OCTOBER).rank.wins).toBe(0);
  });

  it("keeps 300 matches and the last four AI decks", () => {
    const store = new PlayerRecordStore(memory(), () => OCTOBER);
    for (let i = 0; i < 305; i++) {
      store.record({ mode: "quick", outcome: "win", opponents: [], deckID: "d", deckName: "D", colors: [], deckBracket: 2, turns: i, aiDeckID: `ai-${i % 6}` });
    }
    expect(store.matches.length).toBe(PlayerRecordStore.maxMatches);
    expect(store.matches[0].turns).toBe(304);
    expect(store.recentAIDecks).toEqual(["ai-4", "ai-3", "ai-2", "ai-1"]);
  });

  it("stats and achievements", () => {
    const store = new PlayerRecordStore(memory(), () => OCTOBER);
    for (const color of ["W", "U", "B", "R", "G"]) play(store, "quick", "win", { colors: [color], commander: `C-${color}` });
    play(store, "ranked", "loss");
    play(store, "ranked", "win", { deckBracket: 2, human: true }); // Bronze opponents play bracket 2: no underdog
    const stats = store.stats;
    expect(stats.games).toBe(7);
    expect(stats.wins).toBe(6);
    expect(stats.bestStreak).toBe(5);
    expect(stats.currentStreak).toBe(1);
    expect(stats.colors.map((line) => line.id)).toEqual(["W", "U", "B", "R", "G"]);
    expect(stats.averageTurns).toBe(9);
    expect(store.shownCommander).toBe("Krenko, Mob Boss");
    const unlocked = store.achievements;
    for (const a of ["firstWin", "firstRankedWin", "streak5", "prismatic", "humanWin"] as Achievement[]) expect(unlocked.has(a), a).toBe(true);
    expect(unlocked.has("giantSlayer")).toBe(false);
    expect(unlocked.has("silver")).toBe(false);
    expect(Achievement.title("firstWin")).toBe("Rising Star");
  });

  it("an underdog ranked win is a Giant Slayer", () => {
    const store = new PlayerRecordStore(memory(), () => OCTOBER);
    play(store, "ranked", "win", { deckBracket: 1 });
    expect(store.rank.position).toEqual(RankPosition.make("bronze", 4, 3));
    expect(store.achievements.has("giantSlayer")).toBe(true);
  });

  it("colors from a mana cost, and who goes first", () => {
    for (const item of cases.colors) expect(colorsFromManaCost(item.manaCost ?? undefined), JSON.stringify(item)).toEqual(item.colors);
    for (const preference of ["choose", "roll"]) {
      expect(startingPlayerMode("ranked", preference)).toBe("roll");
      expect(startingPlayerMode("quick", preference)).toBe(preference);
      expect(startingPlayerMode("casual", preference)).toBe(preference);
    }
  });
});
