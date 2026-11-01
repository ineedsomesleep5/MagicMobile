import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Award } from "../src/core/account";
import { Achievement } from "../src/core/playerRecord";
import { TrophyShelf } from "../src/ui/menus/ProfilePage";

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

  it("reads a trophy: mm_trophies' null until earned, and mm_my_awards' shelf flag", () => {
    const shelf = Award.parse([
      { id: "regular", name: "Regular", description: "Play 100 games.", tint: "#C9A15A", rarity: 1, awardedAt: "2026-10-30T17:55:30.075436+00:00" },
      { id: "lifer", name: "Lifer", description: "Play 500 games.", tint: "#FFCC5C", rarity: 2, awardedAt: null },
    ]);
    expect(shelf[0]!.awardedAt).toBe(Date.UTC(2026, 9, 30, 17, 55, 30, 75));
    expect(shelf[1]!.awardedAt).toBeUndefined();
    expect(shelf.map((award) => award.shelf)).toEqual([false, false]);
    expect(Award.parse([{ id: "regular", name: "Regular", shelf: true, seen: false }])[0]).toMatchObject({ shelf: true, seen: false });
  });
});

describe("the Trophies shelf", () => {
  const trophies = Award.parse([
    { id: "regular", name: "Regular", description: "Play 100 games.", awardedAt: "2026-10-30T17:55:30+00:00" },
    { id: "lifer", name: "Lifer", description: "Play 500 games.", awardedAt: null },
    { id: "marathon", name: "Marathon", description: "Win a long game.", awardedAt: null },
  ]);
  const shelf = (server: readonly Award[]) => renderToStaticMarkup(createElement(TrophyShelf, { unlocked: new Set<Achievement>(), server }));
  const coinClass = (html: string, id: string) => new RegExp(`class="([^"]*)" data-id="profile\\.trophy\\.${id}"`).exec(html)?.[1];

  it("shows just the built-in coins for a server without trophies", () => {
    const html = shelf([]);
    expect(html.match(/data-id="profile\.trophy\./g)).toHaveLength(Achievement.all.length);
    expect(html).not.toContain("mprofilemedal");
  });

  it("puts the server's trophies after the built-in coins, five to a row, earned or locked", () => {
    const html = shelf(trophies);
    expect(html.match(/data-id="profile\.trophy\./g)).toHaveLength(Achievement.all.length + 3);
    expect(html.match(/class="mprofilecoins"/g)).toHaveLength(Math.ceil((Achievement.all.length + 3) / 5));
    expect(html.indexOf("profile.trophy.regular")).toBeGreaterThan(html.indexOf(`profile.trophy.${Achievement.all.at(-1)}`));
    expect(html.indexOf("profile.trophy.lifer")).toBeGreaterThan(html.indexOf("profile.trophy.regular"));
    expect(coinClass(html, "regular")).toBe("mprofilecoin earned");
    expect(coinClass(html, "lifer")?.trim()).toBe("mprofilecoin");
    expect(html).toContain('aria-label="Lifer. Play 500 games. Locked"');
  });
});
