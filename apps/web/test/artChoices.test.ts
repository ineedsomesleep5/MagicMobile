import { describe, expect, it } from "vitest";
import { chosenPrintings } from "../src/core/artChoices";
import type { DeckLibraryRecord, LibraryEntry } from "../src/core/deckStudio/library";

const deck = (id: string, updatedAt: number, entries: LibraryEntry[]): DeckLibraryRecord =>
  ({ id, name: id, format: "commander", entries, revision: 1, updatedAt, isCloudBacked: false });
const row = (cardName: string, setCode?: string, collectorNumber?: string): LibraryEntry =>
  ({ cardName, quantity: 1, section: "main", setCode, collectorNumber });

describe("chosen art (CardArtChoices)", () => {
  it("takes the playing deck first, its default art included, then the newest other deck", () => {
    const zur = deck("zur", 1, [row("Island", "unf", "236"), row("Sol Ring")]);
    const other = deck("other", 5, [row("Sol Ring", "cmm", "400"), row("Plains", "neo", "293"), row("Island", "dmu", "262")]);
    const older = deck("older", 2, [row("Plains", "one", "267")]);
    const chosen = chosenPrintings([other, zur, older], "zur");
    expect(chosen.get("island")).toEqual({ setCode: "unf", collectorNumber: "236" });
    expect(chosen.has("sol ring")).toBe(false); // the playing deck holds it with its default art
    expect(chosen.get("plains")).toEqual({ setCode: "neo", collectorNumber: "293" });
  });

  it("reads a double-faced card by its front", () => {
    const chosen = chosenPrintings([deck("a", 1, [row("Delver of Secrets // Insectile Aberration", "isd", "51")])]);
    expect(chosen.get("delver of secrets")).toEqual({ setCode: "isd", collectorNumber: "51" });
  });
});
