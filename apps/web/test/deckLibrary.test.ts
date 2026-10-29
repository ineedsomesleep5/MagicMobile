/**
 * The saved deck library (iOS DeckLibraryStore): the phone's JSON shape both ways, revision and other-tab checks, an
 * unreadable library left alone, and the deck list the engine's resolver reads.
 */
import { describe, expect, it } from "vitest";
import { DeckLibrary, DeckLibraryRecord, type LibraryDeck, LibraryError } from "../src/core/deckStudio/library";

function memory(initial: Record<string, string> = {}) {
  const map = new Map(Object.entries(initial));
  return { map, store: { get: (k: string) => map.get(k), set: (k: string, v: string) => { map.set(k, v); } } };
}

const deck: LibraryDeck = {
  name: "Atraxa Counters",
  commander: { cardName: "Atraxa, Praetors' Voice", quantity: 1, section: "commander" },
  entries: [{ cardName: "Sol Ring", quantity: 1, section: "deck" }, { cardName: "Forest", quantity: 10, section: "deck" }],
};

const code = (run: () => void) => { try { run(); } catch (error) { return (error as LibraryError).code; } return undefined; };

describe("DeckLibrary", () => {
  it("reads the phone's decks.json shape and writes it back the same way", () => {
    const phone = JSON.stringify([{
      id: "6F1C", name: "Phone deck", format: "commander", commander: { cardName: "Krenko, Mob Boss", quantity: 1, section: "commander" },
      entries: [{ cardName: "Mountain", quantity: 30, section: "deck", setCode: "LEA", collectorNumber: "292" }, { cardName: "Bad", section: "deck" }],
      source: { kind: "moxfield", url: "https://moxfield.com/decks/abc" }, revision: 3, updatedAt: "2026-10-20T12:00:00Z", isCloudBacked: false,
    }]);
    const { store, map } = memory({ [DeckLibrary.key]: phone });
    const library = new DeckLibrary(store, () => 1_800_000_000_000);
    const [record] = library.decks;
    expect(record).toMatchObject({ id: "6F1C", name: "Phone deck", sourceURL: "https://moxfield.com/decks/abc", revision: 3, isCloudBacked: false });
    expect(record.updatedAt).toBe(Date.parse("2026-10-20T12:00:00Z"));
    expect(record.entries).toEqual([{ cardName: "Mountain", quantity: 30, section: "deck", setCode: "LEA", collectorNumber: "292" }]);
    library.update("6F1C", { ...record, name: "Renamed" }, 3);
    const saved = JSON.parse(map.get(DeckLibrary.key)!)[0];
    expect(saved).toMatchObject({ name: "Renamed", revision: 4, source: { kind: "moxfield", url: "https://moxfield.com/decks/abc" } });
    expect(saved.updatedAt).toBe(new Date(1_800_000_000_000).toISOString());
  });

  it("adds, updates with revision checks, duplicates as a local copy and deletes", () => {
    const { store } = memory();
    const library = new DeckLibrary(store);
    const added = library.add(deck);
    expect(added.revision).toBe(1);
    expect(library.decks.map((d) => d.name)).toEqual(["Atraxa Counters"]);
    expect(code(() => library.update(added.id, deck, 2))).toBe("staleRevision");
    const updated = library.update(added.id, { ...deck, commander: undefined }, 1);
    expect(updated.commander).toBeUndefined();
    expect(updated.revision).toBe(2);
    const copy = library.duplicate(updated, "Atraxa Copy");
    expect(copy.id).not.toBe(updated.id);
    expect(library.decks.map((d) => d.name)).toEqual(["Atraxa Copy", "Atraxa Counters"]);
    library.setFavorite(DeckLibraryRecord.selectionID(copy), true);
    library.delete(copy.id);
    expect(library.decks).toHaveLength(1);
    expect(library.isFavorite(DeckLibraryRecord.selectionID(copy))).toBe(false);
    expect(code(() => library.delete("missing"))).toBe("missingRecord");
  });

  it("validates as the phone does", () => {
    const library = new DeckLibrary(memory().store);
    expect(code(() => library.add({ ...deck, name: "  " }))).toBe("invalidName");
    expect(code(() => library.add({ ...deck, entries: [{ cardName: "Forest", quantity: 0, section: "deck" }] }))).toBe("invalidEntry");
    expect(code(() => library.add({ ...deck, entries: [{ cardName: "Forest", quantity: 2000, section: "deck" }] }))).toBe("invalidEntry");
  });

  it("never replaces another tab's newer save or an unreadable library", () => {
    const { store } = memory();
    const first = new DeckLibrary(store);
    const second = new DeckLibrary(store);
    first.add(deck);
    expect(code(() => second.add(deck))).toBe("staleRevision");
    second.reload();
    expect(second.add(deck).name).toBe("Atraxa Counters");

    const broken = memory({ [DeckLibrary.key]: "{not json" });
    const library = new DeckLibrary(broken.store);
    expect(library.notice).toMatch(/could not be read/);
    expect(code(() => library.add(deck))).toBe("unreadableCache");
    expect(broken.map.get(DeckLibrary.key)).toBe("{not json");
  });

  it("says so when the browser drops the save", () => {
    const library = new DeckLibrary({ get: () => undefined, set: () => {} });
    expect(code(() => library.add(deck))).toBe("notKept");
  });

  it("hands the resolver the commander first, then each row in its section", () => {
    const library = new DeckLibrary(memory().store);
    const record = library.add(deck);
    expect(DeckLibraryRecord.deckList(record)).toEqual({
      id: `local:${record.id}`, name: "Atraxa Counters",
      entries: [
        { name: "Atraxa, Praetors' Voice", quantity: 1, section: "commanders" },
        { name: "Sol Ring", quantity: 1, section: "deck" },
        { name: "Forest", quantity: 10, section: "deck" },
      ],
    });
    expect(library.bySelection(`local:${record.id}`)).toBe(record);
    expect(DeckLibraryRecord.cardCount(record)).toBe(12);
  });
});
