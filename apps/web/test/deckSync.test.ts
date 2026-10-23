/**
 * Deck sync against a fake server, running every scenario in parity/deck-sync-cases.json (docs/DECK_SYNC.md), the
 * cases iOS and Android run too.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { DeckLibrary, DeckLibraryRecord } from "../src/core/deckStudio/library";
import { DeckSync, type DeckSyncAPI, forkName, type ServerDeck, SyncState } from "../src/core/deckStudio/sync";

const root = join(__dirname, "..", "..", "..");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity/deck-sync-cases.json"), "utf8"));

const document = (cards: string[]) => ({ format: "commander", entries: cards.map((cardName) => ({ cardName, quantity: 1, section: "deck" })), source: { kind: "manual" } });
const cardsOf = (doc: unknown) => ((doc as { entries?: { cardName: string }[] })?.entries ?? []).map((e) => e.cardName);

/** mm_decks_since / mm_deck_save / mm_deck_delete over a map, as the migration does them. */
class FakeServer implements DeckSyncAPI {
  decks = new Map<string, ServerDeck>();
  seq = 0;
  constructor(initial: { id: string; name: string; revision: number; seq: number; deleted: boolean; cards: string[] }[]) {
    for (const d of initial) {
      this.decks.set(d.id.toLowerCase(), { id: d.id.toLowerCase(), name: d.name, revision: d.revision, changeSeq: d.seq, deleted: d.deleted, deck: d.deleted ? null : document(d.cards) });
      this.seq = Math.max(this.seq, d.seq);
    }
  }
  async since(cursor: number) {
    const decks = [...this.decks.values()].filter((d) => d.changeSeq > cursor).sort((a, b) => a.changeSeq - b.changeSeq);
    return { decks: decks.map((d) => ({ ...d })), cursor: decks.at(-1)?.changeSeq ?? cursor, more: false };
  }
  async save(id: string, name: string, deck: unknown, base: number | null) {
    const row = this.decks.get(id.toLowerCase());
    if (!row) {
      if (base !== null) throw Object.assign(new Error("not_found"), { code: "not_found" });
      const created = { id: id.toLowerCase(), name, revision: 1, changeSeq: ++this.seq, deleted: false, deck };
      this.decks.set(created.id, created);
      return { status: "saved" as const, deck: { ...created } };
    }
    if (row.deleted || base === null || row.revision !== base) return { status: "conflict" as const, deck: { ...row } };
    Object.assign(row, { name, deck, revision: row.revision + 1, changeSeq: ++this.seq });
    return { status: "saved" as const, deck: { ...row } };
  }
  async remove(id: string, base: number) {
    const row = this.decks.get(id.toLowerCase());
    if (!row || row.deleted) return { status: "deleted" as const, ...(row ? { deck: { ...row } } : {}) };
    if (row.revision !== base) return { status: "conflict" as const, deck: { ...row } };
    Object.assign(row, { deleted: true, deck: null, revision: row.revision + 1, changeSeq: ++this.seq });
    return { status: "deleted" as const, deck: { ...row } };
  }
}

function memory() {
  const map = new Map<string, string>();
  return { get: (k: string) => map.get(k), set: (k: string, v: string) => { map.set(k, v); } };
}

/** A library holding exactly these decks at these revisions (the phones' decks.json shape). */
function libraryWith(store: ReturnType<typeof memory>, decks: { id: string; name: string; revision: number; cards: string[] }[]) {
  store.set(DeckLibrary.key, JSON.stringify(decks.map((d) => ({
    id: d.id, name: d.name, format: "commander", entries: document(d.cards).entries, source: { kind: "manual" }, revision: d.revision,
    updatedAt: "2026-10-20T12:00:00Z", isCloudBacked: false,
  }))));
  return new DeckLibrary(store);
}

describe("deck sync (deck-sync-cases.json)", () => {
  for (const c of cases.cases) {
    it(c.name, async () => {
      const store = memory();
      const library = libraryWith(store, c.local);
      if (c.sync) store.set(SyncState.key, JSON.stringify(c.sync));
      const state = new SyncState(store);
      const server = new FakeServer(c.server);
      const sync = new DeckSync(library, state, server);
      await sync.sync(c.account);

      const original = new Set<string>([...c.local.map((d: { id: string }) => d.id.toLowerCase()), ...c.server.map((d: { id: string }) => d.id.toLowerCase())]);
      const local = library.decks.map((d) => ({ id: original.has(d.id.toLowerCase()) ? d.id.toLowerCase() : "fork", name: d.name, cards: DeckLibraryRecord.deckList(d).entries.map((e) => e.name) }));
      const expectedLocal = c.expect.local.map((d: { id?: string; fork?: boolean; name: string; cards: string[] }) => ({ id: d.fork ? "fork" : d.id!.toLowerCase(), name: d.name, cards: d.cards }));
      const byName = (a: { name: string }, b: { name: string }) => (a.name < b.name ? -1 : 1);
      expect(local.sort(byName)).toEqual(expectedLocal.sort(byName));

      const remote = [...server.decks.values()].map((d) => ({ id: original.has(d.id) ? d.id : "fork", name: d.name, revision: d.revision, deleted: d.deleted }));
      const expectedRemote = c.expect.server.map((d: { id?: string; fork?: boolean; name: string; revision: number; deleted: boolean }) =>
        ({ id: d.fork ? "fork" : d.id!.toLowerCase(), name: d.name, revision: d.revision, deleted: d.deleted }));
      expect(remote.sort(byName)).toEqual(expectedRemote.sort(byName));

      for (const d of library.decks) expect(sync.isDirty(d)).toBe(false);
      expect(sync.record.tombstones).toEqual([]);
      for (const d of [...server.decks.values()].filter((d) => !d.deleted)) {
        expect(cardsOf(d.deck)).toEqual(library.recordMatching(d.id) ? DeckLibraryRecord.deckList(library.recordMatching(d.id)!).entries.map((e) => e.name) : cardsOf(d.deck));
      }
    });
  }

  it("a deck deleted here leaves a tombstone only when the server has it", async () => {
    const store = memory();
    const library = libraryWith(store, [{ id: "AAAAAAAA-1111-4222-8333-444444444444", name: "Synced", revision: 1, cards: ["Forest"] }, { id: "B1", name: "Local only", revision: 1, cards: ["Island"] }]);
    store.set(SyncState.key, JSON.stringify({ account: "A", cursor: 1, entries: { "aaaaaaaa-1111-4222-8333-444444444444": { serverRevision: 4, syncedLocalRevision: 1 } }, tombstones: [] }));
    const sync = new DeckSync(library, new SyncState(store), new FakeServer([]));
    library.delete("AAAAAAAA-1111-4222-8333-444444444444");
    library.delete("B1");
    expect(sync.record.tombstones).toEqual([{ id: "aaaaaaaa-1111-4222-8333-444444444444", serverRevision: 4 }]);
  });

  it("a second sync changes nothing, and a fork's name keeps to 512 bytes", async () => {
    const store = memory();
    const library = libraryWith(store, [{ id: "L1", name: "Atraxa", revision: 1, cards: ["Sol Ring"] }]);
    const server = new FakeServer([]);
    const sync = new DeckSync(library, new SyncState(store), server);
    await sync.sync("A");
    const before = JSON.stringify([...server.decks.values()]);
    const revisions = library.decks.map((d) => d.revision);
    await sync.sync("A");
    expect(JSON.stringify([...server.decks.values()])).toBe(before);
    expect(library.decks.map((d) => d.revision)).toEqual(revisions);
    expect(new TextEncoder().encode(forkName("é".repeat(300))).length).toBeLessThanOrEqual(512);
    expect(forkName("Mine")).toBe("Mine (this device)");
  });
});
