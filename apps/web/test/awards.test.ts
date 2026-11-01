import { describe, expect, it } from "vitest";
import { Award } from "../src/core/account";

describe("Award", () => {
  it("reads what the server sends and skips what it can't show", () => {
    const awards = Award.parse([
      { id: "first-mythic", name: "First to Mythic", description: "The first.", imageUrl: "https://example.com/a.png", tint: "#FF7338",
        rarity: 3, note: "Season 1", awardedAt: "2026-10-30T17:55:30.075436+00:00", seen: false },
      { id: "plain", name: "Plain", imageUrl: "http://example.com/a.png", tint: "orange", rarity: 9 },
      { id: "", name: "No id" }, { id: "no-name" }, "not a row",
    ]);
    expect(awards.map((award) => award.id)).toEqual(["first-mythic", "plain"]);
    expect(awards[0]).toMatchObject({ imageUrl: "https://example.com/a.png", tint: "#FF7338", rarity: 3, seen: false, note: "Season 1" });
    expect(awards[0]!.awardedAt).toBe(Date.UTC(2026, 9, 30, 17, 55, 30, 75));
    expect(awards[1]!.imageUrl).toBeUndefined();
    expect(awards[1]).toMatchObject({ tint: Award.gold, rarity: 3, seen: true });
  });

  it("shows nothing for a server without awards", () => {
    expect(Award.parse(undefined)).toEqual([]);
  });
});
