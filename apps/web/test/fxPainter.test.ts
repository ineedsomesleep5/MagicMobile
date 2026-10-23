/**
 * The board's effects painter (BoardFXPainter's Arena moments): every kind of board event, scheduled at the Arena pace,
 * painted at a run of moments against a recording canvas. Each must draw something and never throw (one that threw
 * once blanked the whole table, game C). Kinds rarely met in test games (stats, transform, steal, phasing) are covered here.
 */
import { describe, expect, it } from "vitest";
import { type BoardFXEvent, BoardFXScheduler } from "../src/core/boardEvents";
import { noise, paint, type PaintContext } from "../src/ui/arena/fxPainter";

/** A 2D context that records the drawing calls it gets and accepts any property. */
function recordingContext() {
  const calls: string[] = [];
  const gradient = { addColorStop: () => undefined };
  const ctx = new Proxy({} as Record<string, unknown>, {
    get(target, key: string) {
      if (key in target) return target[key];
      if (key === "createRadialGradient" || key === "createLinearGradient") return () => gradient;
      if (key === "measureText") return () => ({ width: 20 });
      return (...args: unknown[]) => {
        calls.push(key);
        if (key === "arc" && typeof args[2] === "number" && args[2] < 0) throw new Error("negative radius");
      };
    },
    set(target, key: string, value) { target[key] = value; return true; },
  });
  return { ctx: ctx as unknown as CanvasRenderingContext2D, calls };
}

const rect = { x: 400, y: 200, w: 60, h: 84 };
const k: PaintContext = {
  rect: (id) => (id === "gone" ? undefined : rect), player: (id) => (id === "me" ? { x: 84, y: 402 } : { x: 478, y: 25 }), stack: { x: 760, y: 200 },
  viewerID: "me", subjects: new Map(), grabbed: () => ({ x: 300, y: 60, w: 60, h: 84 }),
};
const EVENTS: BoardFXEvent[] = [
  { type: "attackDeclared", cardID: "a", tint: "red" },
  { type: "blockDeclared", cardID: "b", attackerID: "a" },
  { type: "firstStrikeBeat" },
  { type: "combatStrike", attackerID: "a", target: { player: "me" }, tint: "red", firstStrike: false },
  { type: "combatStrike", attackerID: "a", target: { card: "b" }, tint: "green", firstStrike: true },
  { type: "damageMarked", cardID: "b", amount: 3 },
  { type: "leftBattlefield", cardID: "b", playerID: "ai", to: "graveyard", tint: "black" },
  { type: "leftBattlefield", cardID: "c", playerID: "ai", to: "exile", tint: "white" },
  { type: "enteredBattlefield", cardID: "d", playerID: "me", tint: "green", entrance: "plain" },
  { type: "enteredBattlefield", cardID: "e", playerID: "me", tint: "multicolor", entrance: "commander" },
  { type: "countersChanged", cardID: "d", kind: "plusOne", delta: 2 },
  { type: "countersChanged", cardID: "d", kind: "minusOne", delta: 1 },
  { type: "countersChanged", cardID: "d", kind: "loyalty", delta: -3 },
  { type: "statsChanged", cardID: "d", power: 2, toughness: 2 },
  { type: "phased", cardID: "d", out: true },
  { type: "phased", cardID: "d", out: false },
  { type: "transformed", cardID: "d", name: "Back face" },
  { type: "controlChanged", cardID: "d", from: "me", to: "ai" },
  { type: "lifeChanged", playerID: "me", delta: -5 },
  { type: "lifeChanged", playerID: "ai", delta: 4 },
];

describe("effects painter", () => {
  for (const level of ["full", "reduced"] as const) {
    it(`paints every kind at the Arena pace (${level})`, () => {
      for (const event of EVENTS) {
        const [fx] = BoardFXScheduler.schedule([event], level, 1, 0, "arena", "me");
        const { ctx, calls } = recordingContext();
        for (const p of [0, 0.05, 0.2, 0.42, 0.5, 0.7, 0.9, 0.99]) expect(() => paint(ctx, fx, p, k), event.type).not.toThrow();
        if (event.type !== "firstStrikeBeat" || level === "full") expect(calls.length, `${event.type} drew nothing`).toBeGreaterThan(0);
      }
    });
  }
  it("skips a mark whose card has gone", () => {
    const [fx] = BoardFXScheduler.schedule([{ type: "statsChanged", cardID: "gone", power: 1, toughness: 1 }], "full", 1, 0, "arena", "me");
    const { ctx, calls } = recordingContext();
    paint(ctx, fx, 0.5, k);
    expect(calls).toEqual([]);
  });
});

describe("particle noise", () => {
  it("is BoardFXPainter.noise's 64-bit mix, always in 0..1", () => {
    // Reference values from an independent implementation of the Swift function.
    expect([noise(3, 5, 7), noise(9, 69, 4), noise(0, 0, 0), noise(-12, 3, 1)]).toEqual([0.7886, 0.9485, 0, 0.9775]);
    for (let seed = 0; seed < 40; seed++) for (let i = 0; i < 80; i++) for (let salt = 1; salt < 5; salt++) {
      const value = noise(seed, i, salt);
      expect(value >= 0 && value < 1).toBe(true);
    }
  });
});
