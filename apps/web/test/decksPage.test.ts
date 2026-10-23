/** The Decks page's search, filter and order (iOS DeckStudioLibraryQuery.apply). */
import { describe, expect, it } from "vitest";
import { shelfQuery, type ShelfDeck } from "../src/ui/menus/DecksPage";

const deck = (id: string, name: string, commander: string, local: boolean, updatedAt?: number): ShelfDeck => ({
  box: { id, name, commander, colors: [], subtitle: "Core" }, local, updatedAt, cardCount: 100, bracket: "Core",
});

const decks = [
  deck("precon:a", "Token Triumph", "Emmara, Soul of the Accord", false),
  deck("local:1", "Élan Vital", "Atraxa, Praetors' Voice", true, 200),
  deck("local:2", "Goblins", "Krenko, Mob Boss", true, 300),
  deck("precon:b", "Chaos Incarnate", "Saheeli, the Gifted", false),
];

describe("shelfQuery", () => {
  it("matches every word against the name and commander, ignoring case and accents", () => {
    expect(shelfQuery(decks, "elan atraxa", "all", "name", new Set()).map((d) => d.box.id)).toEqual(["local:1"]);
    expect(shelfQuery(decks, "KRENKO", "all", "name", new Set()).map((d) => d.box.id)).toEqual(["local:2"]);
  });

  it("filters by favourites, your decks and included decks", () => {
    expect(shelfQuery(decks, "", "favorites", "name", new Set(["precon:b"])).map((d) => d.box.id)).toEqual(["precon:b"]);
    expect(shelfQuery(decks, "", "local", "name", new Set()).map((d) => d.box.id)).toEqual(["local:1", "local:2"]);
    expect(shelfQuery(decks, "", "included", "name", new Set()).map((d) => d.box.id)).toEqual(["precon:b", "precon:a"]);
  });

  it("sorts by last edit (included decks last, by name), by name, or by commander", () => {
    expect(shelfQuery(decks, "", "all", "edited", new Set()).map((d) => d.box.id)).toEqual(["local:2", "local:1", "precon:b", "precon:a"]);
    expect(shelfQuery(decks, "", "all", "name", new Set()).map((d) => d.box.name)).toEqual(["Chaos Incarnate", "Élan Vital", "Goblins", "Token Triumph"]);
    expect(shelfQuery(decks, "", "all", "commander", new Set()).map((d) => d.box.commander?.split(",")[0])).toEqual(["Atraxa", "Emmara", "Krenko", "Saheeli"]);
  });
});
