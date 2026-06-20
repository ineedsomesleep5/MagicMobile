import { describe, expect, it } from "vitest";
import { POST } from "./route";

describe("POST /api/decks/generate", () => {
  it("returns a valid generated bracket-3 Commander deck", async () => {
    const response = await POST(
      new Request("http://magicmobile.test/api/decks/generate", {
        method: "POST",
        body: JSON.stringify({ bracket: 3, seed: "api-seed", playerId: "human" })
      })
    );
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload).toMatchObject({
      source: "generated",
      validationErrors: [],
      deck: {
        name: expect.stringContaining("Bracket 3"),
        commander: expect.objectContaining({ quantity: 1, section: "commander" })
      },
      stats: expect.objectContaining({ lands: expect.any(Number) })
    });
    expect(payload.deck.entries.reduce((sum: number, entry: { quantity: number }) => sum + entry.quantity, 0)).toBe(100);
  });
});
