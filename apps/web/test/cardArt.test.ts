/**
 * Card pictures go through one paced loader, ~80 ms apart as Scryfall asks: `<CardArt>` and the board's cards set an
 * `<img>` only once that loader has the picture, so a board's first render never bursts past ten requests a second.
 */
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { afterEach, describe, expect, it, vi } from "vitest";

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.resetModules(); });

describe("card art", () => {
  it("spaces Scryfall requests 80 ms apart and asks for each picture once", async () => {
    vi.useFakeTimers();
    const start = Date.now();
    const requested: { src: string; at: number }[] = [];
    class FakeImage {
      crossOrigin = ""; decoding = "";
      onload?: () => void; onerror?: () => void;
      set src(value: string) { requested.push({ src: value, at: Date.now() - start }); queueMicrotask(() => (value.includes("missing") ? this.onerror : this.onload)?.()); }
    }
    vi.stubGlobal("Image", FakeImage);
    const { loadCardImage } = await import("../src/ui/cardArt");
    const loads = ["a", "b", "missing", "a"].map((name) => loadCardImage(name, "art_crop", `https://cards.test/${name}`));
    await vi.advanceTimersByTimeAsync(1000);
    expect(requested).toEqual([{ src: "https://cards.test/a", at: 0 }, { src: "https://cards.test/b", at: 80 }, { src: "https://cards.test/missing", at: 160 }]);
    const images = await Promise.all(loads);
    expect(images.map((image) => image !== undefined)).toEqual([true, true, false, true]);
    expect(images[3]).toBe(images[0]);
  });

  it("draws no image before the paced loader has it", async () => {
    const { CardArt } = await import("../src/ui/cardArt");
    expect(renderToString(createElement(CardArt, { card: { name: "Grizzly Bears", typeLine: "Creature — Bear" }, version: "art_crop" }))).toBe("");
  });
});
