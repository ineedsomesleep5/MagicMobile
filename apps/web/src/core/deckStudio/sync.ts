/**
 * Deck sync (docs/DECK_SYNC.md): this browser's library and the profile's decks on the server, kept the same on every
 * phone and browser signed in to that profile. The rules are shared with iOS and Android through
 * parity/deck-sync-cases.json. A conflict never loses an edit: the server's copy keeps the id and this device's edit
 * becomes a copy named "(this device)".
 */
import type { J } from "../json";
import type { KeyValueStore } from "../playerRecord";
import { type DeckLibrary, type DeckLibraryRecord, DeckDocument } from "./library";

/** A deck as the server answers it (mm_deck_view). */
export interface ServerDeck { id: string; name: string; revision: number; changeSeq: number; deleted: boolean; deck: unknown }

export interface DeckSyncAPI {
  since(cursor: number): Promise<{ decks: ServerDeck[]; cursor: number; more: boolean }>;
  save(id: string, name: string, document: unknown, base: number | null): Promise<{ status: "saved" | "conflict"; deck: ServerDeck }>;
  remove(id: string, base: number): Promise<{ status: "deleted" | "conflict"; deck?: ServerDeck }>;
}

interface Entry { serverRevision: number; syncedLocalRevision: number }
export interface SyncRecord { account?: string; cursor: number; entries: Record<string, Entry>; tombstones: { id: string; serverRevision: number }[] }

const key = (id: string) => id.toLowerCase();
const forkSuffix = " (this device)";
const utf8 = new TextEncoder();

/** `<name> (this device)`, cut to the phones' 512 bytes without splitting a character. */
export function forkName(name: string): string {
  let base = name;
  while (utf8.encode(base + forkSuffix).length > 512) base = [...base].slice(0, -1).join("");
  return base + forkSuffix;
}

/** The sync record beside the library (mm.web.decks.sync). */
export class SyncState {
  static readonly key = "mm.web.decks.sync";
  record: SyncRecord;
  constructor(private readonly store: KeyValueStore) {
    let parsed: SyncRecord | undefined;
    try { parsed = JSON.parse(store.get(SyncState.key) ?? "null") as SyncRecord | undefined; } catch { parsed = undefined; }
    // Ids compare without case: the server answers lower case, the phones make upper case.
    this.record = parsed && typeof parsed.cursor === "number" && parsed.entries && Array.isArray(parsed.tombstones)
      ? { ...parsed, entries: Object.fromEntries(Object.entries(parsed.entries).map(([id, entry]) => [key(id), entry])),
        tombstones: parsed.tombstones.map((t) => ({ ...t, id: key(t.id) })) }
      : { cursor: 0, entries: {}, tombstones: [] };
  }
  save() { this.store.set(SyncState.key, JSON.stringify(this.record)); }
}

export class DeckSync {
  /** Passes over the dirty decks: forks made by a conflict are pushed in the next. */
  static readonly maxPasses = 3;
  private running?: Promise<void>;

  constructor(private readonly library: DeckLibrary, private readonly state: SyncState, private readonly api: DeckSyncAPI) {
    // The player's delete of a synced deck becomes a tombstone the next sync sends.
    library.onDeleted = (record) => this.noteDeleted(record);
  }

  get record() { return this.state.record; }

  isDirty(record: DeckLibraryRecord): boolean {
    const entry = this.record.entries[key(record.id)];
    return entry === undefined || entry.syncedLocalRevision !== record.revision;
  }

  noteDeleted(record: DeckLibraryRecord) {
    const entry = this.record.entries[key(record.id)];
    if (!entry) return;
    delete this.record.entries[key(record.id)];
    this.record.tombstones.push({ id: key(record.id), serverRevision: entry.serverRevision });
    this.state.save();
  }

  /** One sync for `account` (the signed-in profile's id). Concurrent calls share the running one. */
  sync(account: string): Promise<void> {
    if (!this.running) {
      const run = this.run(account);
      this.running = run;
      const clear = () => { if (this.running === run) this.running = undefined; };
      run.then(clear, clear);
    }
    return this.running;
  }

  private async run(account: string) {
    // 1. Another profile: start over, so every deck here joins it. Nothing local is deleted.
    if (this.record.account !== account) {
      this.state.record = { account, cursor: 0, entries: {}, tombstones: [] };
      this.state.save();
    }
    // 2. Pull.
    await this.pull();
    // 3. Deletions made here.
    for (const tombstone of [...this.record.tombstones]) {
      const answer = await this.api.remove(tombstone.id, tombstone.serverRevision);
      this.record.tombstones = this.record.tombstones.filter((t) => t !== tombstone);
      if (answer.status === "conflict" && answer.deck) this.apply(answer.deck);
      this.state.save();
    }
    // 4. Changes made here; a conflict's fork goes up in the next pass.
    for (let pass = 0; pass < DeckSync.maxPasses; pass += 1) {
      const dirty = this.library.decks.filter((record) => this.isDirty(record));
      if (dirty.length === 0) break;
      for (const record of dirty) {
        const current = this.library.record(record.id);
        if (!current || !this.isDirty(current)) continue;
        const entry = this.record.entries[key(current.id)];
        let answer;
        // Revision 0 marks a deck the server refused: it was never there.
        const base = entry && entry.serverRevision > 0 ? entry.serverRevision : null;
        try { answer = await this.api.save(current.id, current.name, DeckDocument.of(current), base); }
        catch (error) {
          // A deck the server refuses stays here, skipped until it changes; anything else stops this sync.
          if (code(error) === "invalid_deck") { this.record.entries[key(current.id)] = { serverRevision: entry?.serverRevision ?? 0, syncedLocalRevision: current.revision }; continue; }
          throw error;
        }
        if (answer.status === "saved") this.mark(current, answer.deck);
        else if (!answer.deck.deleted && DeckDocument.same(current, answer.deck.name, answer.deck.deck)) this.mark(current, answer.deck);
        else { this.fork(current); this.apply(answer.deck, true); }
        this.state.save();
      }
    }
    // 5. Pull again, past this device's own changes.
    await this.pull();
  }

  private async pull() {
    for (let page = 0; page < 100; page += 1) {
      const answer = await this.api.since(this.record.cursor);
      for (const deck of answer.decks) this.apply(deck);
      this.record.cursor = answer.cursor;
      this.state.save();
      if (!answer.more) return;
    }
  }

  /** One server deck into the library, by the pull rules; `forked` when this device's edit is already kept as a copy. */
  private apply(server: ServerDeck, forked = false) {
    const id = key(server.id);
    const tombstone = this.record.tombstones.find((t) => t.id === id);
    if (tombstone) {
      if (server.deleted) { this.record.tombstones = this.record.tombstones.filter((t) => t !== tombstone); return; }
      if (server.revision === tombstone.serverRevision) return;
      this.record.tombstones = this.record.tombstones.filter((t) => t !== tombstone);
    }
    const local = this.library.recordMatching(server.id);
    if (local && !server.deleted && DeckDocument.same(local, server.name, server.deck)) { this.mark(local, server); return; }
    if (!local) {
      if (!server.deleted) this.take(server);
      return;
    }
    const entry = this.record.entries[id];
    if (this.isDirty(local) && !forked) {
      if (entry && entry.serverRevision === server.revision) return;
      this.fork(local);
    }
    if (server.deleted) {
      this.library.removeSynced(local.id);
      delete this.record.entries[id];
    } else this.take(server);
  }

  private take(server: ServerDeck) {
    const deck = DeckDocument.read(server.name, server.deck);
    if (!deck) return;
    try { this.mark(this.library.applySynced(server.id, deck), server); } catch { /* a deck this library can't hold stays on the server */ }
  }

  private mark(local: DeckLibraryRecord, server: ServerDeck) {
    this.record.entries[key(local.id)] = { serverRevision: server.revision, syncedLocalRevision: local.revision };
  }

  /** This device's edit as a new deck, so the server's copy can take the id. */
  private fork(local: DeckLibraryRecord) {
    const copy = this.library.add({ name: forkName(local.name), ...(local.commander ? { commander: local.commander } : {}), entries: local.entries }, local.sourceURL);
    this.library.rememberColors(copy.id, this.library.colors(local.id));
  }
}

const code = (error: unknown) => (typeof error === "object" && error !== null && "code" in error ? String((error as { code: unknown }).code) : "error");

/** The server functions over the account's Supabase client. */
export function supabaseDeckSync(rpc: (fn: string, params: Record<string, J>) => Promise<J>): DeckSyncAPI {
  const view = (value: J): ServerDeck => {
    const row = (value ?? {}) as Record<string, J>;
    return { id: String(row.id), name: String(row.name ?? ""), revision: Number(row.revision ?? 0), changeSeq: Number(row.changeSeq ?? 0), deleted: row.deleted === true, deck: row.deck };
  };
  return {
    async since(cursor) {
      const answer = (await rpc("mm_decks_since", { p_cursor: cursor })) as Record<string, J>;
      return { decks: Array.isArray(answer?.decks) ? answer.decks.map(view) : [], cursor: Number(answer?.cursor ?? cursor), more: answer?.more === true };
    },
    async save(id, name, document, base) {
      const answer = (await rpc("mm_deck_save", { p_id: id, p_name: name, p_deck: document as J, p_base: base })) as Record<string, J>;
      return { status: answer?.status === "saved" ? "saved" : "conflict", deck: view(answer?.deck ?? null) };
    },
    async remove(id, base) {
      const answer = (await rpc("mm_deck_delete", { p_id: id, p_base: base })) as Record<string, J>;
      return { status: answer?.status === "conflict" ? "conflict" : "deleted", ...(answer?.deck ? { deck: view(answer.deck) } : {}) };
    },
  };
}
