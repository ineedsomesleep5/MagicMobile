/**
 * The AI deck pool: ranked-cases.json's pools (iOS RankedParityTests), iOS AIDeckPoolTests and
 * RankedStandingTests.testBronzePicksOnlyTheGentlestPrecons, and every AI deck and precon through DeckResolver.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { type AIDeck, AIDeckPool, isPrecon, playerDeckID } from "../src/core/aiDeckPool";
import { BracketRules } from "../src/core/brackets";
import { DeckResolver } from "../src/core/deckResolver";

const root = join(__dirname, "..", "..", "..");
const generated = join(__dirname, "..", "public/generated");
const json = (path: string) => JSON.parse(readFileSync(path, "utf8"));
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = json(join(root, "apps/android/core/src/test/resources/parity/ranked-cases.json"));
const pool = new AIDeckPool(json(join(generated, "ai-decks.json")), json(join(generated, "precons.json")));
const total = (deck: AIDeck) => deck.deckList.entries.reduce((sum, entry) => sum + entry.quantity, 0);

describe("AI deck pool", () => {
  it("pools as ranked-cases.json says", () => {
    for (const item of cases.pools) {
      const found = pool.pool(item.bracket);
      expect(found.length, JSON.stringify(item)).toBe(item.count);
      expect(new Set(found.map((deck) => deck.bracket)), JSON.stringify(item)).toEqual(new Set([item.poolBracket]));
    }
  });

  it("every AI deck is a legal hundred at its bracket, and every deck resolves", () => {
    const resolver = new DeckResolver(readFileSync(join(generated, "printings.tsv"), "utf8"));
    const rules = new BracketRules(json(join(root, "apps/ios/MagicMobile/Resources/commander-brackets.json")));
    const basics = new Set(["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"]);
    expect(pool.bracketDecks.length).toBe(28);
    expect(pool.all.filter(isPrecon).length).toBe(5);
    const unresolved: string[] = [];
    for (const deck of pool.all) {
      expect(total(deck), deck.id).toBe(100);
      const commanders = deck.deckList.entries.filter((entry) => entry.section === "commanders");
      expect(commanders.map((entry) => entry.name), deck.id).toEqual([deck.commander]);
      expect(deck.deckList.entries.every((entry) => entry.section === "commanders" || entry.section === "deck"), deck.id).toBe(true);
      const repeated = deck.deckList.entries.filter((entry) => entry.quantity > 1 && !basics.has(entry.name));
      expect(repeated.map((entry) => entry.name), deck.id).toEqual([]);
      for (const entry of deck.deckList.entries) if (resolver.canonicalName(entry.name) === undefined) unresolved.push(`${deck.id}: ${entry.name}`);
      expect(() => resolver.resolve(deck.deckList), deck.id).not.toThrow();
      expect(rules.evaluateDeck(deck.deckList).minimum, `${deck.id} lists above its bracket`).toBeLessThanOrEqual(Math.max(2, deck.bracket));
    }
    expect(unresolved).toEqual([]);
    expect(new Set(pool.all.map((deck) => deck.id)).size).toBe(pool.all.length);
  });

  it("finds decks by ID", () => {
    const krenko = pool.deck("ai-krenko-mob-boss-core")!;
    expect(krenko.bracket).toBe(2);
    expect(krenko.deckList.entries[0]).toEqual({ name: "Krenko, Mob Boss", quantity: 1, section: "commanders" });
    expect(playerDeckID(krenko)).toBe("included:ai-krenko-mob-boss-core");
    expect(pool.playerDeck("included:ai-krenko-mob-boss-core")).toBe(krenko);
    expect(pool.playerDeck("ai-krenko-mob-boss-core")).toBeUndefined();
    expect(pool.playerDeck("included:token-triumph")).toBeUndefined(); // Swift looks among the bracket decks only
    expect(pool.deck("token-triumph")?.commander).toBe("Emmara, Soul of the Accord");
    expect(pool.decks(1).map((deck) => deck.id).every((id) => id.endsWith("-exhibition"))).toBe(true);
    expect(pool.decks(5)).toEqual([]);
  });

  it("picks avoid your commander and recent decks", () => {
    const three = pool.pool(3);
    const krenko = three.find((deck) => deck.commander === "Krenko, Mob Boss")!;
    for (let roll = 0; roll < three.length; roll++) {
      const pick = pool.pick({ bracket: 3, avoidingCommander: "Krenko, Mob Boss", recent: [], roll: () => roll })!;
      expect(pick.commander).not.toBe(krenko.commander);
    }
    const recent = three.slice(1).map((deck) => deck.id);
    expect(pool.pick({ bracket: 3, recent, roll: () => 0 })?.id, "the one deck not faced lately").toBe(three[0].id);
    // Everything faced lately: still a deck.
    expect(pool.pick({ bracket: 3, recent: three.map((deck) => deck.id), roll: () => 0 })).toBeDefined();
    // Only your commander left: still a deck. An out-of-range roll is clamped.
    const only = pool.pool(3, [krenko]);
    expect(pool.pick({ bracket: 3, avoidingCommander: krenko.commander, recent: [], decks: only, roll: () => 99 })).toBe(krenko);
    expect(pool.pick({ bracket: 3, recent: [], decks: three, roll: () => -5 })).toBe(three[0]);
    expect(pool.pick({ bracket: 3, recent: [], decks: [] })).toBeUndefined();
  });

  it("preconsOnly picks a precon, whatever the bracket asked", () => {
    for (const bracket of [1, 2, 4]) {
      for (let roll = 0; roll < 11; roll++) {
        const pick = pool.pick({ bracket, recent: [], preconsOnly: true, roll: () => roll })!;
        expect(isPrecon(pick), pick.id).toBe(true);
      }
    }
    // Without preconsOnly, bracket 4 never meets a precon.
    expect(pool.pick({ bracket: 4, recent: [], roll: () => 0 })!.bracket).toBe(4);
  });

  it("Bronze meets only the gentlest precons; an empty match falls back to every precon", () => {
    const precons = pool.all.filter(isPrecon);
    for (let roll = 0; roll < 10; roll++) {
      const pick = pool.pick({ bracket: 2, recent: [], preconsOnly: true, onlyPrecons: AIDeckPool.gentlestPrecons, decks: precons, roll: () => roll });
      expect(AIDeckPool.gentlestPrecons.has(pick?.id ?? ""), pick?.id).toBe(true);
    }
    expect(pool.pick({ bracket: 2, recent: [], preconsOnly: true, onlyPrecons: new Set(["no-such-precon"]), decks: precons, roll: () => 4 })).toBeDefined();
  });

  it("decode clamps the bracket and rejects a malformed file", () => {
    const decks = AIDeckPool.decode({ schemaVersion: 1, decks: [{
      id: "ai-x", name: "X", subtitle: "", colors: "R", commander: "C", bracket: 9,
      entries: [{ name: "A", quantity: 2, section: "deck" }, { name: "C", quantity: 1, section: "commander" }],
    }] });
    expect(decks[0].bracket).toBe(5);
    expect(decks[0].deckList.entries).toEqual([{ name: "C", quantity: 1, section: "commanders" }, { name: "A", quantity: 2, section: "deck" }]);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    expect(() => AIDeckPool.decode({ schemaVersion: 1 } as any)).toThrow();
  });
});
