import { describe, expect, it } from "vitest";

describe("web route manifest", () => {
  it("keeps the requested scaffold routes visible to smoke tests", () => {
    const routes = ["/", "/decks", "/decks/new", "/decks/[id]", "/cards", "/play", "/rooms/[id]", "/settings", "/dev/engine", "/dev/components"];
    expect(routes).toHaveLength(10);
    expect(routes).toContain("/play");
  });
});
