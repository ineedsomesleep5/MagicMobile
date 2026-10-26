/** The browsers' sideways row (HScroller): edges, arrows and the wheel. */
import { describe, expect, it } from "vitest";
import { pageTarget, rowEdges, wheelSideways } from "../src/ui/arena/hscroll";
import { abilityCardHeight } from "../src/ui/arena/Browsers";

describe("sideways row", () => {
  it("shows no edge when the cards fit, and each edge with cards beyond it", () => {
    expect(rowEdges({ scrollLeft: 0, clientWidth: 900, scrollWidth: 901 })).toEqual({ before: false, after: false });
    expect(rowEdges({ scrollLeft: 0, clientWidth: 900, scrollWidth: 1600 })).toEqual({ before: false, after: true });
    expect(rowEdges({ scrollLeft: 300, clientWidth: 900, scrollWidth: 1600 })).toEqual({ before: true, after: true });
    expect(rowEdges({ scrollLeft: 699.5, clientWidth: 900, scrollWidth: 1600 })).toEqual({ before: true, after: false });
  });

  it("pages most of a view along and stops at the ends", () => {
    expect(pageTarget({ scrollLeft: 0, clientWidth: 900, scrollWidth: 2000 }, 1)).toBe(720);
    expect(pageTarget({ scrollLeft: 800, clientWidth: 900, scrollWidth: 2000 }, 1)).toBe(1100);
    expect(pageTarget({ scrollLeft: 300, clientWidth: 900, scrollWidth: 2000 }, -1)).toBe(0);
  });

  it("turns a vertical wheel sideways and leaves a sideways swipe to the browser", () => {
    expect(wheelSideways(0, 100, 0, 900)).toBe(100);
    expect(wheelSideways(0, -3, 1, 900)).toBe(-120);
    expect(wheelSideways(0, 1, 2, 900)).toBe(900);
    expect(wheelSideways(40, 10, 0, 900)).toBeUndefined();
  });

  it("sizes trigger cards to the row, half the board until it is measured", () => {
    expect(abilityCardHeight(undefined, 502)).toBe(251);
    expect(abilityCardHeight(undefined, 717)).toBe(280);
    expect(abilityCardHeight(328, 502)).toBeCloseTo(280.8, 1);
    expect(abilityCardHeight(900, 717)).toBe(340);
    expect(abilityCardHeight(100, 440)).toBe(150);
  });
});
