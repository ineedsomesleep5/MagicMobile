import type {
  CreateDeckInput,
  DeckEntry,
  DeckSource,
  SavedDeck,
  UpdateDeckInput
} from "@magicmobile/shared";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { SupabaseRequestContext } from "../supabase/request";

export class DeckRepositoryError extends Error {
  constructor(message: string, readonly status: 404 | 409 | 500 = 500) {
    super(message);
    this.name = "DeckRepositoryError";
  }
}

export interface DeckRepository {
  list(): Promise<SavedDeck[]>;
  get(id: string): Promise<SavedDeck>;
  create(input: CreateDeckInput): Promise<SavedDeck>;
  update(id: string, input: UpdateDeckInput): Promise<SavedDeck>;
  delete(id: string): Promise<void>;
}

export const createDeckRepository = (context: SupabaseRequestContext): DeckRepository =>
  context.mode === "development"
    ? new DevelopmentDeckRepository(context.userId)
    : new SupabaseDeckRepository(requireClient(context), context.userId);

interface DeckRow {
  id: string;
  owner_id: string;
  name: string;
  format: "commander";
  commander_name: string | null;
  raw_list: string;
  source_kind: DeckSource["kind"];
  source_url: string | null;
  source_filename: string | null;
  revision: number;
  created_at: string;
  updated_at: string;
  deck_entries?: DeckEntryRow[];
}

interface DeckEntryRow {
  card_name: string;
  quantity: number;
  section: DeckEntry["section"];
  position: number;
}

const DECK_SELECT = "id,owner_id,name,format,commander_name,raw_list,source_kind,source_url,source_filename,revision,created_at,updated_at,deck_entries(card_name,quantity,section,position)";

class SupabaseDeckRepository implements DeckRepository {
  constructor(private readonly client: SupabaseClient, private readonly userId: string) {}

  async list(): Promise<SavedDeck[]> {
    const { data, error } = await this.client
      .from("decks")
      .select(DECK_SELECT)
      .eq("owner_id", this.userId)
      .order("updated_at", { ascending: false });
    if (error) throw databaseError(error);
    return (data as unknown as DeckRow[]).map(mapDeckRow);
  }

  async get(id: string): Promise<SavedDeck> {
    const { data, error } = await this.client
      .from("decks")
      .select(DECK_SELECT)
      .eq("id", id)
      .eq("owner_id", this.userId)
      .maybeSingle();
    if (error) throw databaseError(error);
    if (!data) throw new DeckRepositoryError("Deck not found.", 404);
    return mapDeckRow(data as unknown as DeckRow);
  }

  async create(input: CreateDeckInput): Promise<SavedDeck> {
    const source = input.source ?? { kind: "manual" as const };
    const entries = input.entries;
    const now = new Date().toISOString();
    const { data, error } = await this.client.from("decks").insert({
      owner_id: this.userId,
      name: input.name,
      format: "commander",
      commander_name: commanderFor(input)?.cardName ?? null,
      raw_list: input.rawList ?? serializeEntries(entries),
      source_kind: source.kind,
      source_url: source.url ?? null,
      source_filename: source.filename ?? null,
      revision: 1,
      updated_at: now
    }).select("id").single();
    if (error || !data) throw databaseError(error);
    const deckId = String(data.id);
    const entriesError = await this.replaceEntries(deckId, entries);
    if (entriesError) {
      await this.client.from("decks").delete().eq("id", deckId).eq("owner_id", this.userId);
      throw databaseError(entriesError);
    }
    return this.get(deckId);
  }

  async update(id: string, input: UpdateDeckInput): Promise<SavedDeck> {
    const current = await this.get(id);
    if (current.revision !== input.revision) throw new DeckRepositoryError("Deck was changed on another device. Reload and try again.", 409);
    const entries = input.entries ?? current.entries;
    const source = input.source ?? current.source;
    const commander = input.commander ?? entries.find((entry) => entry.section === "commander");
    const { error } = await this.client.rpc("update_owned_deck", {
      p_deck_id: id,
      p_expected_revision: current.revision,
      p_name: input.name ?? current.name,
      p_commander_name: commander?.cardName ?? null,
      p_raw_list: input.rawList ?? serializeEntries(entries),
      p_source_kind: source.kind,
      p_source_url: source.url ?? null,
      p_source_filename: source.filename ?? null,
      p_entries: entries
    });
    if (error?.message.includes("deck_revision_conflict")) {
      throw new DeckRepositoryError("Deck was changed on another device. Reload and try again.", 409);
    }
    if (error) throw databaseError(error);
    return this.get(id);
  }

  async delete(id: string): Promise<void> {
    await this.get(id);
    const { error } = await this.client.from("decks").delete().eq("id", id).eq("owner_id", this.userId);
    if (error) throw databaseError(error);
  }

  private async replaceEntries(deckId: string, entries: DeckEntry[]) {
    const { error: deleteError } = await this.client
      .from("deck_entries")
      .delete()
      .eq("deck_id", deckId)
      .eq("owner_id", this.userId);
    if (deleteError) return deleteError;
    const { error } = await this.client.from("deck_entries").insert(entries.map((entry, position) => ({
      deck_id: deckId,
      owner_id: this.userId,
      card_name: entry.cardName,
      quantity: entry.quantity,
      section: entry.section,
      position
    })));
    return error;
  }
}

declare global {
  // Development-only state. Production never reaches this store.
  var __magicMobileDevelopmentDecks: Map<string, SavedDeck> | undefined;
}

class DevelopmentDeckRepository implements DeckRepository {
  private readonly store = globalThis.__magicMobileDevelopmentDecks ??= new Map<string, SavedDeck>();

  constructor(private readonly userId: string) {}

  async list(): Promise<SavedDeck[]> {
    return [...this.store.values()]
      .filter((deck) => deck.ownerId === this.userId)
      .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))
      .map(cloneDeck);
  }

  async get(id: string): Promise<SavedDeck> {
    const deck = this.store.get(id);
    if (!deck || deck.ownerId !== this.userId) throw new DeckRepositoryError("Deck not found.", 404);
    return cloneDeck(deck);
  }

  async create(input: CreateDeckInput): Promise<SavedDeck> {
    const timestamp = new Date().toISOString();
    const commander = commanderFor(input);
    const deck: SavedDeck = {
      id: crypto.randomUUID(),
      ownerId: this.userId,
      name: input.name,
      format: "commander",
      entries: input.entries.map((entry) => ({ ...entry })),
      ...(commander ? { commander: { ...commander } } : {}),
      revision: 1,
      source: { ...(input.source ?? { kind: "manual" }) },
      createdAt: timestamp,
      updatedAt: timestamp
    };
    this.store.set(deck.id, deck);
    return cloneDeck(deck);
  }

  async update(id: string, input: UpdateDeckInput): Promise<SavedDeck> {
    const current = await this.get(id);
    if (current.revision !== input.revision) throw new DeckRepositoryError("Deck was changed on another device. Reload and try again.", 409);
    const entries = input.entries?.map((entry) => ({ ...entry })) ?? current.entries;
    const commander = input.commander ?? entries.find((entry) => entry.section === "commander");
    const updated: SavedDeck = {
      ...current,
      name: input.name ?? current.name,
      entries,
      source: { ...(input.source ?? current.source) },
      revision: current.revision + 1,
      updatedAt: new Date().toISOString()
    };
    if (commander) updated.commander = { ...commander };
    else delete updated.commander;
    this.store.set(id, updated);
    return cloneDeck(updated);
  }

  async delete(id: string): Promise<void> {
    await this.get(id);
    this.store.delete(id);
  }
}

const mapDeckRow = (row: DeckRow): SavedDeck => {
  const entries = [...(row.deck_entries ?? [])]
    .sort((left, right) => left.position - right.position)
    .map((entry) => ({ cardName: entry.card_name, quantity: entry.quantity, section: entry.section }));
  const commander = entries.find((entry) => entry.section === "commander");
  const source: DeckSource = {
    kind: row.source_kind,
    ...(row.source_url ? { url: row.source_url } : {}),
    ...(row.source_filename ? { filename: row.source_filename } : {})
  };
  return {
    id: row.id,
    ownerId: row.owner_id,
    name: row.name,
    format: "commander",
    entries,
    ...(commander ? { commander } : {}),
    revision: Number(row.revision),
    source,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
};

const commanderFor = (input: CreateDeckInput): DeckEntry | undefined =>
  input.commander ?? input.entries.find((entry) => entry.section === "commander");
const serializeEntries = (entries: DeckEntry[]): string => entries.map((entry) => `${entry.quantity} ${entry.cardName}`).join("\n");
const cloneDeck = (deck: SavedDeck): SavedDeck => structuredClone(deck);
const requireClient = (context: SupabaseRequestContext): SupabaseClient => {
  if (!context.client) throw new DeckRepositoryError("Cloud decks are unavailable.");
  return context.client;
};
const databaseError = (error: { message?: string } | null): DeckRepositoryError => {
  console.error("Cloud deck database operation failed", error?.message ?? "unknown error");
  return new DeckRepositoryError("Cloud deck operation failed.");
};
