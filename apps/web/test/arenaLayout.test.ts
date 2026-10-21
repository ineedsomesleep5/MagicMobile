/** The Arena board's geometry: any window shape fills, the nearest plate lies under it, rows and the hand keep their places. */
import { describe, expect, it } from "vitest";
import type { ZoneCard } from "../src/core/models";
import { battlefieldPlaces, geometry, handPlaces, PLATES, STAGE } from "../src/ui/arena/layout";

const card = (id: string, name: string, typeLine: string, extra: Partial<ZoneCard> = {}): ZoneCard =>
  ({ instanceId: id, card: { name, typeLine } as ZoneCard["card"], ...extra });

describe("arena geometry", () => {
  it("fills a window of any shape between 2.17:1 and 4:3, on the nearest plate", () => {
    for (const [w, h] of [[1440, 900], [1920, 1080], [1024, 768], [2560, 1080], [1280, 800]]) {
      const geo = geometry(w, h);
      // The board covers the window edge to edge in at least one direction, and never overflows it.
      expect(Math.min(Math.abs(STAGE.width * geo.scale - w), Math.abs(geo.height * geo.scale - h))).toBeLessThan(1);
      expect(STAGE.width * geo.scale).toBeLessThanOrEqual(w + 0.5);
      expect(geo.height * geo.scale).toBeLessThanOrEqual(h + 0.5);
      const plate = PLATES.find((p) => p.src === geo.plate)!;
      expect(Math.abs(plate.height - geo.height) / geo.height).toBeLessThan(0.07);
    }
    expect(geometry(1440, 900).plate).toBe("/arena/table-1610.jpg");
    expect(geometry(1920, 1080).plate).toBe("/arena/table-169.jpg");
    expect(geometry(1024, 768).plate).toBe("/arena/table-43.jpg");
    expect(geometry(3440, 1440).plate).toBe("/arena/table.jpg");
  });

  it("puts creatures and planeswalkers up front, lands and artifacts behind, theirs above yours", () => {
    const geo = geometry(1440, 900);
    const mine = battlefieldPlaces([
      card("a", "Forest", "Basic Land — Forest"), card("b", "Forest", "Basic Land — Forest", { tapped: true }),
      card("c", "Mentor of the Meek", "Creature — Human Soldier"), card("d", "Ajani, Caller of the Pride", "Legendary Planeswalker — Ajani"),
      card("e", "Talisman of Unity", "Artifact"),
    ], "me", undefined, geo);
    const theirs = battlefieldPlaces([card("x", "Island", "Basic Land — Island"), card("y", "Drake", "Creature — Drake")], "opp", undefined, geo);
    expect(mine.get("c")!.y).toBe(mine.get("d")!.y);
    expect(mine.get("a")!.y).toBeGreaterThan(mine.get("c")!.y);
    expect(mine.get("e")!.y).toBeCloseTo(mine.get("a")!.y, 0);
    expect(mine.get("b")!.r).toBe(12);
    expect(theirs.get("y")!.y).toBeLessThan(mine.get("c")!.y);
    expect(theirs.get("x")!.y).toBeLessThan(theirs.get("y")!.y);
    for (const place of [...mine.values(), ...theirs.values()]) {
      expect(place.y).toBeGreaterThan(0);
      expect(place.y).toBeLessThan(geo.height);
    }
  });

  it("keeps a land where it was when it taps, so the next click finds the next land", () => {
    const geo = geometry(1440, 900);
    const lands = (tapped: string[]) => battlefieldPlaces([
      card("p", "Plains", "Basic Land — Plains", { tapped: tapped.includes("p") }),
      card("f", "Forest", "Basic Land — Forest", { tapped: tapped.includes("f") }),
    ], "me", undefined, geo);
    const before = lands([]);
    const after = lands(["p"]);
    expect(after.get("p")!.x).toBeLessThan(after.get("f")!.x);
    expect(after.get("f")!.x).toBeCloseTo(before.get("f")!.x, 0);
  });

  it("keeps the hand on the bottom edge however tall the board is", () => {
    for (const [w, h] of [[2560, 1080], [1440, 900], [1024, 768]]) {
      const geo = geometry(w, h);
      const tucked = handPlaces(["a", "b", "c"], false, undefined, geo).get("b")!;
      const raised = handPlaces(["a", "b", "c"], true, undefined, geo).get("b")!;
      expect(geo.height - tucked.y).toBeLessThan(tucked.h / 2);
      expect(raised.y).toBeLessThan(tucked.y);
    }
  });
});
