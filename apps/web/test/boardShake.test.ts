/** The board's shake (NativeGameView.ingestBoardFX): what shakes it, how hard, and when it flares red. */
import { describe, expect, it } from "vitest";
import type { ScheduledBoardFX } from "../src/core/boardEvents";
import { boardShakes } from "../src/ui/arena/useBoardFX";

const fx = (event: object, delay = 0.2, landing = 0.5) => ({ event, delay, landing }) as unknown as ScheduledBoardFX;

describe("board shake", () => {
  it("shakes for your losses, big hits on opponents and commanders, at most three", () => {
    expect(boardShakes([fx({ type: "lifeChanged", playerID: "me", delta: -3 })], "me")).toEqual([{ at: 0.2, amplitude: 6, flare: false }]);
    expect(boardShakes([fx({ type: "lifeChanged", playerID: "me", delta: -5 })], "me")).toEqual([{ at: 0.2, amplitude: 12, flare: true }]);
    expect(boardShakes([fx({ type: "lifeChanged", playerID: "ai", delta: -4 })], "me")).toEqual([]);
    expect(boardShakes([fx({ type: "lifeChanged", playerID: "ai", delta: -6 })], "me")).toEqual([{ at: 0.2, amplitude: 5, flare: false }]);
    expect(boardShakes([fx({ type: "lifeChanged", playerID: "me", delta: 4 })], "me")).toEqual([]);
    expect(boardShakes([fx({ type: "enteredBattlefield", cardID: "c", entrance: "commander" })], "me")).toEqual([{ at: 0.5, amplitude: 6, flare: false }]);
    expect(boardShakes(Array(5).fill(fx({ type: "lifeChanged", playerID: "me", delta: -1 })), "me")).toHaveLength(3);
  });
});
