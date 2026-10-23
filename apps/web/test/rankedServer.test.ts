/** The browser's half of ranked games that count on the server: pending results with their records, the adopted rank, the exact seed. */
import { describe, expect, it } from "vitest";
import { EngineJson } from "../src/core/json";
import { PlayerRecordStore } from "../src/core/playerRecord";
import { RankPosition } from "../src/core/rankLadder";
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

  it("sends a ticket's 64-bit seed exactly, only to engines that keep game records", () => {
    const setup = { name: "Caleb", deck: {}, aiDecks: [{}], aiSkill: 3, startingPlayerMode: "roll" as const, seed: -9223372036854775807n };
    expect(EngineJson.encode(soloConfiguration(setup, true))).toContain('"seed":-9223372036854775807');
    expect(soloConfiguration(setup, false)).not.toHaveProperty("seed");
    expect(EngineJson.encode({ a: EngineJson.integer(18446744073709551615n) })).toBe('{"a":18446744073709551615}');
  });
});
