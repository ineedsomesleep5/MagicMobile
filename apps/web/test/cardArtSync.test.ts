/**
 * Card picture sync against a fake server, running every scenario in parity/card-art-sync-cases.json
 * (docs/CARD_ART_SYNC.md), the same cases iOS and Android run.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { type CardArtLocal, CardArtSync, CardArtSyncState, type CardArtSyncAPI, type CardArtSyncRecord, type ServerArt } from "../src/core/cardArtSync";

interface Case {
  name: string;
  record: CardArtSyncRecord;
  local: Record<string, string>;
  server: { cardKey: string; picture: string | null }[];
  refuse?: string;
  expect: { local: Record<string, string>; server: Record<string, string | null>; files: string[]; synced: Record<string, string> };
}

const cases = (JSON.parse(readFileSync(join(__dirname, "..", "..", "android/core/src/test/resources/parity/card-art-sync-cases.json"), "utf8")) as { cases: Case[] }).cases;

/** The server's rows and the player's folder; a picture's bytes are its name. */
class FakeServer implements CardArtSyncAPI {
  rows = new Map<string, ServerArt>();
  files = new Set<string>();
  private seq = 0;
  constructor(rows: Case["server"], private readonly refuse?: string) {
    for (const row of rows) this.write(row.cardKey, row.picture);
    for (const row of this.rows.values()) if (row.picture) this.files.add(row.picture);
  }
  private write(cardKey: string, picture: string | null): ServerArt {
    const row = { cardKey, picture, changeSeq: ++this.seq };
    this.rows.delete(cardKey);
    this.rows.set(cardKey, row);
    return row;
  }
  async since(cursor: number) {
    const arts = [...this.rows.values()].filter((row) => row.changeSeq > cursor).sort((a, b) => a.changeSeq - b.changeSeq);
    return { arts, cursor: arts.length ? arts[arts.length - 1].changeSeq : cursor, more: false };
  }
  async set(cardKey: string, picture: string | null) {
    if (cardKey === this.refuse) throw Object.assign(new Error("too_many_pictures"), { code: "too_many_pictures" });
    if (picture && !this.files.has(picture)) throw Object.assign(new Error("picture_missing"), { code: "picture_missing" });
    return this.write(cardKey, picture);
  }
  async upload(picture: string, bytes: Blob) { expect(await bytes.text()).toBe(picture); this.files.add(picture); }
  async download(picture: string) {
    if (!this.files.has(picture)) throw Object.assign(new Error("not_found"), { code: "not_found" });
    return new Blob([picture], { type: "image/jpeg" });
  }
  async removeFile(picture: string) { this.files.delete(picture); }
}

class FakeLocal implements CardArtLocal {
  constructor(readonly pictures: Map<string, string>) {}
  keys() { return [...this.pictures.keys()]; }
  async hash(key: string) { return this.pictures.get(key); }
  async bytes(key: string) { const picture = this.pictures.get(key); return picture === undefined ? undefined : new Blob([picture]); }
  async store(key: string, bytes: Blob) { this.pictures.set(key, await bytes.text()); }
  async remove(key: string) { this.pictures.delete(key); }
}

const memory = () => { const values = new Map<string, string>(); return { get: (k: string) => values.get(k), set: (k: string, v: string) => { values.set(k, v); }, remove: (k: string) => { values.delete(k); } }; };

describe("card picture sync (parity/card-art-sync-cases.json)", () => {
  for (const scenario of cases) {
    it(scenario.name, async () => {
      const state = new CardArtSyncState(memory());
      state.record = structuredClone({ account: "me", ...scenario.record });
      const local = new FakeLocal(new Map(Object.entries(scenario.local)));
      const server = new FakeServer(scenario.server, scenario.refuse);
      await new CardArtSync(local, state, server).sync("me");
      expect(Object.fromEntries(local.pictures)).toEqual(scenario.expect.local);
      expect(Object.fromEntries([...server.rows.values()].map((row) => [row.cardKey, row.picture]))).toEqual(scenario.expect.server);
      expect([...server.files].sort()).toEqual(scenario.expect.files);
      expect(state.record.synced).toEqual(scenario.expect.synced);
      expect(state.record.removed).toEqual([]);
      expect(state.record.account).toBe("me");
    });
  }

  it("a removal here waits for the next sync and the record survives a reload", async () => {
    const store = memory();
    const state = new CardArtSyncState(store);
    state.record = { account: "me", cursor: 0, synced: { gojo: "p1" }, removed: [] };
    const sync = new CardArtSync(new FakeLocal(new Map()), state, new FakeServer([]));
    sync.noteRemoved("gojo");
    expect(await sync.pending()).toBe(true);
    expect(new CardArtSyncState(store).record.removed).toEqual([{ cardKey: "gojo", picture: "p1" }]);
  });
});
