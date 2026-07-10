import { afterEach, describe, expect, it } from "vitest";
import { startupStore, toStartupResponse } from "./commander-startups";

describe("Commander startup records", () => {
  afterEach(() => startupStore().clear());

  it("preserves structured XMage deck validation failures for the iOS client", () => {
    const response = toStartupResponse({
      startupId: "startup-invalid-deck",
      status: "failed",
      error: "Commander deck validation failed.",
      deckErrors: [
        {
          playerId: "human",
          seat: "human",
          deckName: "Imported deck",
          issues: [
            {
              code: "unknown_card",
              message: "Card was not found in XMage.",
              cardName: "Imaginary Lotus"
            }
          ]
        }
      ],
      createdAt: Date.now()
    });

    expect(response.deckErrors?.[0]).toMatchObject({
      seat: "human",
      deckName: "Imported deck",
      issues: [{ cardName: "Imaginary Lotus" }]
    });
  });
});
