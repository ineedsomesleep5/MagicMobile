package io.magicmobile.android.studio

import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.string
import kotlinx.coroutines.CompletableDeferred
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

/*
 * Deck sync (docs/DECK_SYNC.md): this phone's library and the profile's decks on the server, kept the same on every
 * phone and browser signed in to that profile. The rules are shared with iOS and the web through
 * parity/deck-sync-cases.json; apps/web/src/core/deckStudio/sync.ts is the reference. A conflict never loses an edit:
 * the server's copy keeps the id and this device's edit becomes a copy named "(this device)".
 */

/** A deck as the server answers it (mm_deck_view). */
data class ServerDeck(val id: String, val name: String, val revision: Long, val changeSeq: Long, val deleted: Boolean, val deck: JsonElement?)

/** mm_decks_since / mm_deck_save / mm_deck_delete. */
interface DeckSyncAPI {
    data class Page(val decks: List<ServerDeck>, val cursor: Long, val more: Boolean)
    data class Saved(val saved: Boolean, val deck: ServerDeck)
    data class Deleted(val conflict: Boolean, val deck: ServerDeck?)

    suspend fun since(cursor: Long): Page
    suspend fun save(id: String, name: String, document: JsonObject, base: Long?): Saved
    suspend fun remove(id: String, base: Long): Deleted
}

/** A saved deck as sync sees it: the library record without its bookkeeping beyond the revision. */
data class SyncedDeck(val id: String, val name: String, val commander: DeckEntry?, val entries: List<DeckEntry>, val sourceURL: String?, val revision: Long) {
    val deckList: DeckList get() = DeckList(name, commander, entries)
}

/** What the library gives deck sync (DeckLibraryStore's sync hooks). */
interface DeckSyncLibrary {
    val decks: List<SyncedDeck>
    fun record(id: String): SyncedDeck? = decks.firstOrNull { it.id == id }
    /** A deck by id ignoring case: the server answers ids in lower case, iOS makes them upper case. */
    fun recordMatching(id: String): SyncedDeck? = decks.firstOrNull { it.id.equals(id, ignoreCase = true) }
    /** A server deck under its own id: replaces this device's copy (its revision moves on) or is added. Throws when the library can't hold it. */
    fun applySynced(id: String, deck: DeckList, sourceURL: String?): SyncedDeck
    /** A deck deleted on another device leaves this one (no tombstone, unlike the player's delete). */
    fun removeSynced(id: String)
    /** This device's edit of [original] as a new local deck named [name], with a new id (a fork). */
    fun addFork(original: SyncedDeck, name: String): SyncedDeck
    /** The longest deck name this library holds, in characters, beside the phones' 512 bytes. */
    val maxNameChars: Int get() = Int.MAX_VALUE
}

/** What deck sync carries: the phones' decks.json record shape without its id, name and bookkeeping. */
object DeckDocument {
    /** `{format, commander?, entries, source: {kind, url?}}`; Android decks are always the commander format. */
    fun of(deck: SyncedDeck): JsonObject {
        val url = deck.sourceURL
        val kind = if (url == null) "manual" else if (url.contains("archidekt", ignoreCase = true)) "archidekt" else "moxfield"
        val source = if (url == null) JsonObject(mapOf("kind" to JsonPrimitive(kind)))
            else JsonObject(mapOf("kind" to JsonPrimitive(kind), "url" to JsonPrimitive(url)))
        val fields = linkedMapOf<String, JsonElement>("format" to JsonPrimitive("commander"))
        deck.commander?.let { fields["commander"] = it.json() }
        fields["entries"] = JsonArray(deck.entries.map { it.json() })
        fields["source"] = source
        return JsonObject(fields)
    }

    /** A server document as a library deck and its source link; null when it isn't one. Unreadable rows are dropped. */
    fun read(name: String, value: JsonElement?): Pair<DeckList, String?>? {
        if (value !is JsonObject) return null
        fun entry(row: J?): DeckEntry? {
            val cardName = row["cardName"].string ?: return null
            val quantity = row["quantity"].integer?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE } ?: return null
            val section = row["section"].string ?: return null
            return DeckEntry(cardName, quantity.toInt(), section, DeckEntry.printing(row))
        }
        val commander = entry(value["commander"])
        val entries = value["entries"].array.orEmpty().mapNotNull(::entry)
        val sourceURL = value["sourceURL"].string ?: value["source"]["url"].string
        return DeckList(name, commander, entries) to sourceURL
    }

    /** The same name and document: the sync's "already equal" test (JSON objects compare without key order). */
    fun same(deck: SyncedDeck, name: String, document: JsonElement?): Boolean = deck.name == name && of(deck) == document
}

/** `<name> (this device)`, cut to the phones' 512 bytes (and at most [maxChars] characters) without splitting a character. */
fun forkName(name: String, maxChars: Int = Int.MAX_VALUE): String {
    val suffix = " (this device)"
    var base = name
    while (base.isNotEmpty() && ((base + suffix).utf8Size > 512 || (base + suffix).length > maxChars)) {
        base = base.substring(0, base.offsetByCodePoints(base.length, -1))
    }
    return base + suffix
}

/** The sync record beside the library: the profile it synced with, the pull cursor, entries and tombstones. */
class SyncState(private val read: () -> String?, private val write: (String) -> Unit) {
    data class Entry(val serverRevision: Long, val syncedLocalRevision: Long)
    data class Tombstone(val id: String, val serverRevision: Long)
    data class Record(val account: String? = null, var cursor: Long = 0, val entries: MutableMap<String, Entry> = linkedMapOf(),
                      val tombstones: MutableList<Tombstone> = mutableListOf())

    var record: Record = load()

    private fun load(): Record = runCatching {
        val value = Json.parseToJsonElement(read() ?: return@runCatching null) as? JsonObject ?: return@runCatching null
        val cursor = (value["cursor"] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull ?: return@runCatching null
        val entries = value["entries"] as? JsonObject ?: return@runCatching null
        val tombstones = value["tombstones"] as? JsonArray ?: return@runCatching null
        // Ids compare without case: the server answers lower case, iOS makes upper case.
        Record(value["account"].string, cursor,
            entries.mapNotNullTo(mutableListOf()) { (id, entry) ->
                val server = entry["serverRevision"].integer ?: return@mapNotNullTo null
                val local = entry["syncedLocalRevision"].integer ?: return@mapNotNullTo null
                key(id) to Entry(server, local)
            }.toMap(linkedMapOf()),
            tombstones.mapNotNullTo(mutableListOf()) { t ->
                Tombstone(key(t["id"].string ?: return@mapNotNullTo null), t["serverRevision"].integer ?: return@mapNotNullTo null)
            })
    }.getOrNull() ?: Record()

    fun save() {
        val fields = linkedMapOf<String, JsonElement>()
        record.account?.let { fields["account"] = JsonPrimitive(it) }
        fields["cursor"] = JsonPrimitive(record.cursor)
        fields["entries"] = JsonObject(record.entries.mapValues { (_, e) ->
            JsonObject(mapOf("serverRevision" to JsonPrimitive(e.serverRevision), "syncedLocalRevision" to JsonPrimitive(e.syncedLocalRevision)))
        })
        fields["tombstones"] = JsonArray(record.tombstones.map { JsonObject(mapOf("id" to JsonPrimitive(it.id), "serverRevision" to JsonPrimitive(it.serverRevision))) })
        write(JsonObject(fields).toString())
    }

    /** The player deleted a deck here: a synced one becomes a tombstone the next sync sends; one never synced needs none. */
    fun noteDeleted(id: String) {
        val entry = record.entries.remove(key(id)) ?: return
        record.tombstones += Tombstone(key(id), entry.serverRevision)
        save()
    }

    companion object { fun key(id: String) = id.lowercase() }
}

/**
 * One sync at a time over [library], [state] and the server [api]. [codeOf] names a server error ("invalid_deck").
 * Errors other than a refused deck stop the sync; the caller keeps them quiet and syncs again later.
 */
class DeckSync(private val library: DeckSyncLibrary, private val state: SyncState, private val api: DeckSyncAPI,
               private val codeOf: (Throwable) -> String?) {
    private var running: CompletableDeferred<Unit>? = null

    val record: SyncState.Record get() = state.record

    fun isDirty(deck: SyncedDeck): Boolean = record.entries[SyncState.key(deck.id)]?.syncedLocalRevision != deck.revision

    /** Something waits to go up: a dirty deck or a tombstone. */
    fun hasPending(): Boolean = record.tombstones.isNotEmpty() || library.decks.any(::isDirty)

    fun noteDeleted(id: String) = state.noteDeleted(id)

    /** One sync for [account] (the signed-in profile's id). Concurrent calls share the running one. */
    suspend fun sync(account: String) {
        val shared: CompletableDeferred<Unit>
        val mine: Boolean
        synchronized(this) {
            val current = running
            mine = current == null
            shared = current ?: CompletableDeferred<Unit>().also { running = it }
        }
        if (!mine) return shared.await()
        try {
            run(account)
            shared.complete(Unit)
        } catch (error: Throwable) {
            shared.completeExceptionally(error)
            throw error
        } finally {
            synchronized(this) { if (running === shared) running = null }
        }
    }

    private suspend fun run(account: String) {
        // 1. Another profile: start over, so every deck here joins it. Nothing local is deleted.
        if (record.account != account) {
            state.record = SyncState.Record(account)
            state.save()
        }
        // 2. Pull.
        pull()
        // 3. Deletions made here.
        for (tombstone in record.tombstones.toList()) {
            val answer = api.remove(tombstone.id, tombstone.serverRevision)
            record.tombstones.remove(tombstone)
            if (answer.conflict && answer.deck != null) apply(answer.deck)
            state.save()
        }
        // 4. Changes made here; a conflict's fork goes up in the next pass.
        for (pass in 0 until MAX_PASSES) {
            val dirty = library.decks.filter(::isDirty)
            if (dirty.isEmpty()) break
            for (deck in dirty) {
                val current = library.record(deck.id) ?: continue
                if (!isDirty(current)) continue
                val entry = record.entries[SyncState.key(current.id)]
                // Revision 0 marks a deck the server refused: it was never there.
                val base = entry?.serverRevision?.takeIf { it > 0 }
                val answer = try { api.save(current.id, current.name, DeckDocument.of(current), base) } catch (error: Throwable) {
                    // A deck the server refuses stays here, skipped until it changes; anything else stops this sync.
                    if (codeOf(error) == "invalid_deck") {
                        record.entries[SyncState.key(current.id)] = SyncState.Entry(entry?.serverRevision ?: 0, current.revision)
                        continue
                    }
                    throw error
                }
                if (answer.saved) mark(current, answer.deck)
                else if (!answer.deck.deleted && DeckDocument.same(current, answer.deck.name, answer.deck.deck)) mark(current, answer.deck)
                else { fork(current); apply(answer.deck, forked = true) }
                state.save()
            }
        }
        // 5. Pull again, past this device's own changes.
        pull()
    }

    private suspend fun pull() {
        repeat(100) {
            val answer = api.since(record.cursor)
            for (deck in answer.decks) apply(deck)
            record.cursor = answer.cursor
            state.save()
            if (!answer.more) return
        }
    }

    /** One server deck into the library, by the pull rules; [forked] when this device's edit is already kept as a copy. */
    private fun apply(server: ServerDeck, forked: Boolean = false) {
        val id = SyncState.key(server.id)
        val tombstone = record.tombstones.firstOrNull { it.id == id }
        if (tombstone != null) {
            if (server.deleted) { record.tombstones.remove(tombstone); return }
            if (server.revision == tombstone.serverRevision) return
            record.tombstones.remove(tombstone)
        }
        val local = library.recordMatching(server.id)
        if (local != null && !server.deleted && DeckDocument.same(local, server.name, server.deck)) { mark(local, server); return }
        if (local == null) {
            if (!server.deleted) take(server)
            return
        }
        val entry = record.entries[id]
        if (isDirty(local) && !forked) {
            if (entry != null && entry.serverRevision == server.revision) return
            fork(local)
        }
        if (server.deleted) {
            library.removeSynced(local.id)
            record.entries.remove(id)
        } else take(server)
    }

    private fun take(server: ServerDeck) {
        val (deck, sourceURL) = DeckDocument.read(server.name, server.deck) ?: return
        // A deck this library can't hold stays on the server.
        runCatching { library.applySynced(server.id, deck, sourceURL) }.onSuccess { mark(it, server) }
    }

    private fun mark(local: SyncedDeck, server: ServerDeck) {
        record.entries[SyncState.key(local.id)] = SyncState.Entry(server.revision, local.revision)
    }

    /** This device's edit as a new deck, so the server's copy can take the id. */
    private fun fork(local: SyncedDeck) {
        library.addFork(local, forkName(local.name, library.maxNameChars))
    }

    companion object {
        /** Passes over the dirty decks: forks made by a conflict are pushed in the next. */
        const val MAX_PASSES = 3
    }
}
