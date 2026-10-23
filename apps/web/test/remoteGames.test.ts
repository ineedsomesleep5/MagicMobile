import { describe, expect, it } from "vitest";
import type { MatchRecord } from "../src/core/playerRecord";
import { mergeMatches, parseMyGames, remoteDeckID } from "../src/core/remoteGames";

const row = (id: string, playedAt: string, extra: Record<string, unknown> = {}) => ({
  client_id: id, played_at: playedAt, mode: "quick", result: "win", deck_name: "Apex Predators",
  commanders: ["Gishath, Sun's Avatar"], colors: ["R", "G", "W"], opponents: [{ name: "Grave Danger", commander: "Meren of Clan Nel Toth", ai: true }],
  turns: 14, rank_points: null, ...extra,
});

describe("mm_my_games", () => {
  it("reads the server's games as profile matches", () => {
    const [game] = parseMyGames([row("A1", "2026-10-23T20:11:55.777+00:00")]);
    expect(game).toEqual({
      id: "A1", date: Date.parse("2026-10-23T20:11:55.777Z"), mode: "quick", outcome: "win", deckID: remoteDeckID("Apex Predators"),
      deckName: "Apex Predators", commander: "Gishath, Sun's Avatar", colors: ["R", "G", "W"], deckBracket: 0, turns: 14,
      opponents: [{ name: "Grave Danger", commander: "Meren of Clan Nel Toth", isAI: true }],
    });
  });

  it("skips rows it can't read", () => {
    expect(parseMyGames([row("B", "not a date"), row("C", "2026-10-23T00:00:00Z", { mode: "draft" }), "junk", null])).toEqual([]);
    expect(parseMyGames(null)).toEqual([]);
  });

  it("adds the other devices' games once, newest first, keeping this browser's copy", () => {
    const local = { ...parseMyGames([row("abc", "2026-10-22T00:00:00Z")])[0], deckID: "precon:apex", deckBracket: 3 } as MatchRecord;
    const remote = parseMyGames([row("ABC", "2026-10-22T00:00:00Z"), row("phone", "2026-10-23T00:00:00Z"), row("old", "2026-10-01T00:00:00Z")]);
    const merged = mergeMatches([local], remote);
    expect(merged.map((m) => m.id)).toEqual(["phone", "abc", "old"]);
    expect(merged[1].deckID).toBe("precon:apex");
  });
});
