/** The Arena board's geometry: any window shape fills, the nearest plate lies under it, rows and the hand keep their places. */
import { describe, expect, it } from "vitest";
import type { ZoneCard } from "../src/core/models";
import { ARENA, battlefieldPlaces, geometry, handPlaces, pileLean, pileThickness, PLATES, STAGE } from "../src/ui/arena/layout";

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

describe("piles", () => {
  // testPilesLeanAwayFromTheMiddleOfTheTable, on the only board the web has: landscape.
  it("lean away from the point under the camera, whichever side they stand on, and far ones stand shorter", () => {
    expect(pileLean(ARENA.opponentPiles.library).drift).toBeGreaterThan(0);
    expect(pileLean(ARENA.viewerPiles.library).drift).toBeLessThan(0);
    expect(pileLean(ARENA.opponentPiles.library).rise).toBeLessThan(1);
    expect(pileLean(ARENA.viewerPiles.library).rise).toBe(1);
  });

  it("drift by how far they stand from the camera, up to the old sideways shift", () => {
    expect(pileLean({ x: 900, y: 30 }).drift).toBe(0.22);
    expect(pileLean({ x: 80, y: 404 }).drift).toBe(-0.22);
    expect(pileLean({ x: 478, y: 30 }).drift).toBe(0);
    // A further opponent's piles stand 170 points left of the first's, so they cross the camera and turn round.
    expect(pileLean({ x: ARENA.opponentPiles.library.x - 170, y: 30 }).drift).toBeCloseTo(56 / 566);
    expect(pileLean({ x: ARENA.opponentPiles.library.x - 340, y: 30 }).drift).toBeCloseTo(-114 / 566);
  });

  it("stand as tall as their rise", () => {
    const near = pileThickness(40, 50), far = pileThickness(40, 50, 0.6);
    expect(far.thickness).toBeCloseTo(near.thickness * 0.6);
    expect(far.layers).toBeLessThan(near.layers);
    expect(pileThickness(0, 50, 0.6)).toEqual({ thickness: 0, layers: 0 });
  });
});

describe("the resting hand's pop", () => {
  it("pops the card whole and upright, clear of the bottom edge, and slides card by card", async () => {
    const { handPlaces, scrubHand, BASE_GEOMETRY } = await import("../src/ui/arena/layout");
    const ids = ["a", "b", "c", "d", "e"];
    const rest = handPlaces(ids, false, undefined, BASE_GEOMETRY);
    const popped = handPlaces(ids, false, "c", BASE_GEOMETRY).get("c")!;
    expect(popped.s).toBe(1.18);
    expect(popped.r).toBe(0);
    expect(popped.y + (popped.h * 1.18) / 2).toBeLessThanOrEqual(BASE_GEOMETRY.height - 8 + 1e-9);
    const y = rest.get("c")!.y;
    // Each card owns the strip of it that shows: from its left edge to the next card's.
    const lefts = ids.map((id) => rest.get(id)!.x - rest.get(id)!.w / 2);
    expect(ids.map((_, i) => scrubHand(ids, rest, { x: lefts[i] + 2, y }))).toEqual(ids);
    // A few points into the next strip the pop stays put; further in it moves on.
    expect(scrubHand(ids, rest, { x: lefts[3] + 4, y }, "c")).toBe("c");
    expect(scrubHand(ids, rest, { x: lefts[3] + 8, y }, "c")).toBe("d");
  });
});
