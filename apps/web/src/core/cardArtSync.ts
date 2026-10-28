/**
 * Your own card pictures (ui/customArt.ts) on every phone and browser signed in to this profile (docs/CARD_ART_SYNC.md).
 * The rules are shared with iOS (CardArtSync.swift) and Android (CardArtSync.kt) through parity/card-art-sync-cases.json.
 * A picture changed here since the last sync wins over one changed elsewhere meanwhile; nothing is ever merged.
 */
import type { J } from "./json";
import type { KeyValueStore } from "./playerRecord";

/** One card's picture as the server answers it: `picture` is the JPEG's SHA-256, null when the card has none. */
export interface ServerArt { cardKey: string; picture: string | null; changeSeq: number }

export interface CardArtSyncAPI {
  since(cursor: number): Promise<{ arts: ServerArt[]; cursor: number; more: boolean }>;
  set(cardKey: string, picture: string | null): Promise<ServerArt>;
  upload(picture: string, bytes: Blob): Promise<void>;
  download(picture: string): Promise<Blob>;
  /** Best effort: a file nothing points at any more. */
  removeFile(picture: string): Promise<void>;
}

/** The pictures on this device, by card key. */
export interface CardArtLocal {
  keys(): string[];
  /** The stored JPEG's SHA-256 (lower-case hex). */
  hash(cardKey: string): Promise<string | undefined>;
  bytes(cardKey: string): Promise<Blob | undefined>;
  /** A picture from another device: stored without counting as a change made here. */
  store(cardKey: string, bytes: Blob): Promise<void>;
  remove(cardKey: string): Promise<void>;
}

export interface CardArtSyncRecord {
  account?: string;
  cursor: number;
  /** The picture the server had for each card when this device last matched it. */
  synced: Record<string, string>;
  /** Cards whose picture was removed here while the server still has it. */
  removed: { cardKey: string; picture: string }[];
}

/** Codes the server answers for one card that will not change by asking again: that card stays on this device. */
const refusals = new Set(["invalid_card_art", "too_many_pictures", "Payload too large", "invalid_mime_type"]);

export class CardArtSyncState {
  static readonly key = "mm.web.cardArt.sync";
  record: CardArtSyncRecord;
  constructor(private readonly store: KeyValueStore) {
    let parsed: CardArtSyncRecord | undefined;
    try { parsed = JSON.parse(store.get(CardArtSyncState.key) ?? "null") as CardArtSyncRecord | undefined; } catch { parsed = undefined; }
    this.record = parsed && typeof parsed.cursor === "number" && parsed.synced && Array.isArray(parsed.removed)
      ? parsed : { cursor: 0, synced: {}, removed: [] };
  }
  save() { try { this.store.set(CardArtSyncState.key, JSON.stringify(this.record)); } catch { /* storage blocked */ } }
}

export class CardArtSync {
  private running?: Promise<void>;
  /** Cards the server refused this session (too many, too large): not offered again until their picture changes. */
  private readonly refused = new Map<string, string>();

  constructor(private readonly local: CardArtLocal, private readonly state: CardArtSyncState, private readonly api: CardArtSyncAPI) {}

  get record() { return this.state.record; }

  /** The player removed a card's picture here: the server's copy goes next sync. */
  noteRemoved(cardKey: string) {
    const picture = this.record.synced[cardKey];
    if (picture === undefined) return;
    delete this.record.synced[cardKey];
    this.record.removed = [...this.record.removed.filter((r) => r.cardKey !== cardKey), { cardKey, picture }];
    this.state.save();
  }

  /** Whether anything made here is waiting to go up. */
  async pending(): Promise<boolean> {
    if (this.record.removed.length > 0) return true;
    for (const key of this.local.keys()) {
      const hash = await this.local.hash(key);
      if (hash !== undefined && hash !== this.record.synced[key] && this.refused.get(key) !== hash) return true;
    }
    return false;
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
    // 1. Another profile: start over, so every picture here joins it. Nothing local is deleted.
    if (this.record.account !== account) {
      this.state.record = { account, cursor: 0, synced: {}, removed: [] };
      this.state.save();
    }
    // 2. Pull.
    await this.pull();
    // 3. Removals made here.
    for (const removal of [...this.record.removed]) {
      await this.api.set(removal.cardKey, null);
      this.record.removed = this.record.removed.filter((r) => r !== removal);
      this.state.save();
      await this.forget(removal.picture);
    }
    // 4. Pictures set or changed here.
    for (const key of this.local.keys()) {
      const hash = await this.local.hash(key);
      if (hash === undefined || hash === this.record.synced[key] || this.refused.get(key) === hash) continue;
      const bytes = await this.local.bytes(key);
      if (!bytes) continue;
      try {
        await this.api.upload(hash, bytes);
        await this.api.set(key, hash);
      } catch (error) {
        if (refusals.has(code(error))) { this.refused.set(key, hash); await this.forget(hash); continue; }
        throw error;
      }
      const old = this.record.synced[key];
      this.record.synced[key] = hash;
      this.state.save();
      if (old !== undefined) await this.forget(old);
    }
    // 5. Pull once more, past this device's own changes.
    await this.pull();
  }

  private async pull() {
    for (;;) {
      const answer = await this.api.since(this.record.cursor);
      for (const art of answer.arts) await this.apply(art);
      this.record.cursor = answer.cursor;
      this.state.save();
      if (!answer.more) break;
    }
  }

  private async apply(art: ServerArt) {
    const key = art.cardKey;
    const removal = this.record.removed.find((r) => r.cardKey === key);
    if (removal) {
      // This device's removal follows, unless someone set another picture meanwhile (it comes back).
      if (art.picture === removal.picture) return;
      this.record.removed = this.record.removed.filter((r) => r !== removal);
      if (art.picture === null) return;
    }
    const hash = await this.local.hash(key);
    const synced = this.record.synced[key];
    const changedHere = hash !== undefined && hash !== synced;
    if (art.picture === null) {
      if (hash !== undefined && !changedHere) await this.local.remove(key);
      delete this.record.synced[key];
    } else if (hash === art.picture) {
      this.record.synced[key] = art.picture;
    } else if (changedHere) {
      // Changed here since the last sync: this device's picture goes up and wins.
      this.record.synced[key] = art.picture;
    } else {
      await this.local.store(key, await this.api.download(art.picture));
      this.record.synced[key] = art.picture;
    }
  }

  /** A file no card points at any more. */
  private async forget(picture: string) {
    if (Object.values(this.record.synced).includes(picture)) return;
    await this.api.removeFile(picture).catch(() => undefined);
  }
}

const code = (error: unknown) => (typeof error === "object" && error !== null && "code" in error ? String((error as { code: unknown }).code) : "error");

/** SHA-256 of a picture's bytes, lower-case hex. */
export async function pictureHash(bytes: Blob): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", await bytes.arrayBuffer());
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** The server functions and the player's picture folder (custom-card-art/<user id>/) over the account's client. */
export function supabaseCardArtSync(client: {
  rpc(fn: string, params: Record<string, J>): Promise<J>;
  storage(method: "PUT" | "GET" | "DELETE", objectPath: string, body?: Blob): Promise<Blob>;
}, userID: () => Promise<string | undefined>): CardArtSyncAPI {
  const art = (value: J): ServerArt => {
    const row = (value ?? {}) as Record<string, J>;
    return { cardKey: String(row.cardKey ?? ""), picture: typeof row.picture === "string" ? row.picture : null, changeSeq: Number(row.changeSeq ?? 0) };
  };
  const file = async (picture: string) => {
    const id = await userID();
    if (!id) throw Object.assign(new Error("not_signed_in"), { code: "not_signed_in" });
    return `custom-card-art/${id}/${picture}.jpg`;
  };
  return {
    async since(cursor) {
      const answer = (await client.rpc("mm_card_art_since", { p_cursor: cursor })) as Record<string, J>;
      return { arts: Array.isArray(answer?.arts) ? answer.arts.map(art) : [], cursor: Number(answer?.cursor ?? cursor), more: answer?.more === true };
    },
    async set(cardKey, picture) { return art(await client.rpc("mm_card_art_set", { p_card_key: cardKey, p_picture: picture })); },
    async upload(picture, bytes) { await client.storage("PUT", await file(picture), bytes.type === "image/jpeg" ? bytes : new Blob([bytes], { type: "image/jpeg" })); },
    async download(picture) { return client.storage("GET", await file(picture)); },
    async removeFile(picture) { await client.storage("DELETE", await file(picture)); },
  };
}
