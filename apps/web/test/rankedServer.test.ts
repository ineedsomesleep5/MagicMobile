/** The browser's half of ranked games that count on the server: pending results with their records, the adopted rank, the exact seed. */
import { describe, expect, it } from "vitest";
import { EngineJson } from "../src/core/json";
import { type FinishedGame, PlayerRecordStore, rankNote } from "../src/core/playerRecord";
import { ProfileGame } from "../src/core/profileSummary";
import { RankChange, RankPosition, RankSettlement } from "../src/core/rankLadder";
import { soloConfiguration } from "../src/table/soloTable";

const memory = () => { const map = new Map<string, string>(); return { get: (k: string) => map.get(k), set: (k: string, v: string) => { map.set(k, v); }, map }; };
const now = () => Date.UTC(2026, 9, 23);

describe("ranked results for the server", () => {
  it("keeps a pending result with its game record until the server settles it, across reloads", () => {
    const store = memory();
    const record = new PlayerRecordStore(store, now);
    record.addPendingRanked({ ticket: "t-1", outcome: "win", date: now(), seeded: true }, { format: "magicmobile-game-record", entries: ["a"] });
    const reloaded = new PlayerRecordStore(store, now);
    expect(reloaded.pendingRankedResults).toEqual([{ ticket: "t-1", outcome: "win", date: now(), seeded: true, recordFile: "mm.web.playerRecord.game.t-1" }]);
    expect(reloaded.gameRecord("mm.web.playerRecord.game.t-1")).toEqual({ format: "magicmobile-game-record", entries: ["a"] });
    reloaded.resolvePendingRanked("t-1");
    expect(new PlayerRecordStore(store, now).pendingRankedResults).toEqual([]);
    expect(store.map.get("mm.web.playerRecord.game.t-1")).toBe("");
  });

  it("takes the server's rank", () => {
    const store = memory();
    const record = new PlayerRecordStore(store, now);
    record.adoptRank({ ...record.rank, position: RankPosition.make("gold", 2, 1), wins: 9 });
    expect(new PlayerRecordStore(store, now).rank.position).toEqual(RankPosition.make("gold", 2, 1));
  });

  it("keeps a ranked AI game's ticket, and the server's answer replaces the browser's guess on that game (RankedStandingTests)", () => {
    const store = memory();
    const record = new PlayerRecordStore(store, now);
    const game = (ticket?: string, isAI = true): FinishedGame => ({
      mode: "ranked", outcome: "win", opponents: [{ name: "Foe", isAI }], deckID: "precon:x", deckName: "Goblins", colors: ["R"], deckBracket: 2, turns: 9,
      ...(ticket ? { rankedTicket: ticket } : {}),
    });
    record.record(game("t-1"));
    expect(record.matches[0].rankedTicket).toBe("t-1");
    // Only a ranked game against the AI keeps one.
    record.record(game("t-2", false));
    expect(record.matches[0].rankedTicket).toBeUndefined();
    const settled = () => new PlayerRecordStore(store, now).matches[1];
    // Counted: the server's own move on the ladder.
    record.settleRanked("t-1", "counted", undefined, { pointsBefore: 4, pointsAfter: 6, bonuses: ["underdog", "mystery"] });
    expect(settled().rankChange).toEqual({ outcome: "win", before: RankPosition.fromPoints(4), after: RankPosition.fromPoints(6), bonuses: ["underdog"] });
    expect(rankNote(settled())).toBeUndefined();
    // Held back: no move, and why.
    record.settleRanked("t-1", "unverified", "too_short", undefined);
    expect(RankChange.pipDelta(settled().rankChange!)).toBe(0);
    expect(settled().rankChange?.bonuses).toEqual([]);
    expect([settled().settlement, settled().settlementCheck]).toEqual(["unverified", "too_short"]);
    expect(rankNote(settled())).toBe("Not ranked: wins before turn 5 don't count");
    // Already settled (no change) and counted: the game stays as it is.
    record.settleRanked("t-1", "counted", undefined, undefined);
    expect(RankChange.pipDelta(settled().rankChange!)).toBe(0);
    // A ticket no game has is ignored.
    record.settleRanked("t-9", "capped", undefined, undefined);
    expect(record.matches.every((m) => m.settlement !== "capped")).toBe(true);
  });

  it("says why a ranked win didn't count, and words the game's move on the ladder", () => {
    expect(RankSettlement.note("unverified", "too_short", 5)).toBe("Not ranked: wins before turn 3 don't count");
    expect(RankSettlement.note("unverified", "too_short", 4)).toBe("Not ranked: wins before turn 5 don't count");
    expect(RankSettlement.note("unverified", "too_fast", 2)).toBe("Not ranked: the game ended too quickly");
    expect(RankSettlement.note("unverified", "no_record", 2)).toBe("Not ranked: this win couldn't be checked");
    expect(RankSettlement.note("too_soon", undefined, 2)).toBe("Not ranked: the game ended too quickly");
    expect(RankSettlement.note("capped", undefined, 2)).toBe("Not ranked: 12 ranked wins a day");
    expect(RankSettlement.note("counted", undefined, 2)).toBeUndefined();
    expect(RankSettlement.note("abandoned", undefined, 2)).toBeUndefined();
    expect(["too_soon", "capped", "unverified", "counted", "abandoned", undefined].map(RankSettlement.held)).toEqual([true, true, true, false, false, false]);
    const change = (before: RankPosition, after: RankPosition): RankChange => ({ outcome: "win", before, after, bonuses: [] });
    expect(RankChange.line(change(RankPosition.make("gold", 2, 1), RankPosition.make("gold", 2, 3)))).toBe("Gold II: 1 → 3 pips");
    expect(RankChange.line(change(RankPosition.make("gold", 2, 3), RankPosition.make("gold", 1, 0)))).toBe("Gold II → Gold I");
    expect(RankChange.line(change(RankPosition.make("mythic", 0, 2), RankPosition.make("mythic", 0, 3)))).toBe("Mythic → Mythic");
  });

  it("shows the rank line and the note on the profile's game card", () => {
    const record = new PlayerRecordStore(memory(), now);
    record.record({ mode: "ranked", outcome: "win", opponents: [{ name: "Foe", isAI: true }], deckID: "d", deckName: "D", colors: [], deckBracket: 2, turns: 3, rankedTicket: "t" });
    record.settleRanked("t", "unverified", "too_short", undefined);
    const game = ProfileGame.from(record.matches[0]);
    expect(game.rankDelta).toBe(0);
    expect(game.rankLine).toBe(RankChange.line(record.matches[0].rankChange!));
    expect(game.rankNote).toBe("Not ranked: wins before turn 5 don't count");
    record.record({ mode: "quick", outcome: "win", opponents: [], deckID: "d", deckName: "D", colors: [], deckBracket: 2, turns: 9 });
    expect(ProfileGame.from(record.matches[0])).not.toHaveProperty("rankLine");
    expect(ProfileGame.from(record.matches[0])).not.toHaveProperty("rankNote");
  });

  it("sends a ticket's 64-bit seed exactly, only to engines that keep game records", () => {
    const setup = { name: "Caleb", deck: {}, aiDecks: [{}], aiSkill: 3, startingPlayerMode: "roll" as const, seed: -9223372036854775807n };
    expect(EngineJson.encode(soloConfiguration(setup, true))).toContain('"seed":-9223372036854775807');
    expect(soloConfiguration(setup, false)).not.toHaveProperty("seed");
    expect(EngineJson.encode({ a: EngineJson.integer(18446744073709551615n) })).toBe('{"a":18446744073709551615}');
  });
});
