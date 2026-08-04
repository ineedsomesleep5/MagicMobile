import { describe, expect, it, vi } from "vitest";
import { DeckImportError, importDeck } from "../src";

describe("importDeck", () => {
  it("imports pasted text and preserves a safe filename", async () => {
    const imported = await importDeck({
      sourceText: "Commander\n1 Atraxa, Praetors' Voice\nDeck\n1 Sol Ring",
      filename: "../Atraxa.dec"
    });
    expect(imported.deck.name).toBe("Atraxa");
    expect(imported.source).toEqual({ kind: "file", filename: "Atraxa.dec" });
  });

  it("imports an allowlisted public Moxfield URL through its JSON endpoint", async () => {
    const fetcher = vi.fn(async () => new Response(JSON.stringify({
      name: "Public deck",
      commanders: { cards: { commander: { quantity: 1, card: { name: "Atraxa, Praetors' Voice" } } } },
      mainboard: { cards: { ring: { quantity: 1, card: { name: "Sol Ring" } } } }
    }), { status: 200, headers: { "content-type": "application/json" } }));
    const imported = await importDeck({ sourceURL: "https://www.moxfield.com/decks/abc_DEF-123" }, fetcher as typeof fetch);
    expect(fetcher).toHaveBeenCalledWith("https://api2.moxfield.com/v2/decks/all/abc_DEF-123", expect.objectContaining({ redirect: "manual" }));
    expect(imported.deck.entries).toHaveLength(2);
    expect(imported.source).toEqual({ kind: "moxfield", url: "https://www.moxfield.com/decks/abc_DEF-123" });
  });

  it("rejects untrusted hosts and ambiguous input", async () => {
    await expect(importDeck({ sourceURL: "https://example.com/decks/1" })).rejects.toThrow("Only public Archidekt and Moxfield");
    await expect(importDeck({ sourceText: "1 Sol Ring", sourceURL: "https://moxfield.com/decks/abc" })).rejects.toBeInstanceOf(DeckImportError);
  });

  it("maps Archidekt category ids to Commander sections", async () => {
    const fetcher = vi.fn(async () => new Response(JSON.stringify({
      name: "Archidekt deck",
      categories: [{ id: 10, name: "Commander" }],
      cards: [{ quantity: 1, categories: [10], card: { oracleCard: { name: "Muldrotha, the Gravetide" } } }]
    }), { status: 200 }));
    const imported = await importDeck({ sourceURL: "https://archidekt.com/decks/123/example" }, fetcher as typeof fetch);
    expect(imported.deck.commander?.cardName).toBe("Muldrotha, the Gravetide");
  });
});
