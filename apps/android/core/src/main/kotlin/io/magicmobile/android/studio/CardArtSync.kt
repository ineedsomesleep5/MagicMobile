package io.magicmobile.android.studio

import io.magicmobile.android.game.array
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.string
import kotlinx.coroutines.CompletableDeferred
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.security.MessageDigest

/*
 * Your own card pictures (CustomCardArt) on every phone and browser signed in to this profile (docs/CARD_ART_SYNC.md).
 * The rules are shared with iOS (CardArtSync.swift) and the web (cardArtSync.ts, the reference) through
 * parity/card-art-sync-cases.json. A picture changed here since the last sync wins over one changed elsewhere meanwhile;
 * nothing is ever merged.
 */

/** One card's picture as the server answers it: [picture] is the JPEG's SHA-256, null when the card has none. */
data class ServerCardArt(val cardKey: String, val picture: String?, val changeSeq: Long)

/** mm_card_art_since / mm_card_art_set and the player's picture folder. */
interface CardArtSyncAPI {
    data class Page(val arts: List<ServerCardArt>, val cursor: Long, val more: Boolean)

    suspend fun since(cursor: Long): Page
    suspend fun set(cardKey: String, picture: String?): ServerCardArt
    suspend fun upload(picture: String, bytes: ByteArray)
    suspend fun download(picture: String): ByteArray
    /** Best effort: a file nothing points at any more. */
    suspend fun removeFile(picture: String)
}

/** The pictures on this device, by card key. */
interface CardArtLocal {
    fun keys(): List<String>
    /** The stored JPEG's SHA-256 (lower-case hex). */
    fun hash(cardKey: String): String?
    fun bytes(cardKey: String): ByteArray?
    /** A picture from another device: stored without counting as a change made here. */
    fun store(cardKey: String, bytes: ByteArray)
    fun remove(cardKey: String)
}

/** The sync record beside the pictures, kept through [read] and [write]. */
class CardArtSyncState(private val read: () -> String?, private val write: (String) -> Unit) {
    data class Removal(val cardKey: String, val picture: String)
    data class Record(val account: String? = null, var cursor: Long = 0, val synced: MutableMap<String, String> = linkedMapOf(),
                      val removed: MutableList<Removal> = mutableListOf())

    var record: Record = load()

    private fun load(): Record = runCatching {
        val value = Json.parseToJsonElement(read() ?: return@runCatching null) as? JsonObject ?: return@runCatching null
        val cursor = value["cursor"].integer ?: return@runCatching null
        val synced = value["synced"] as? JsonObject ?: return@runCatching null
        Record(value["account"].string, cursor,
            synced.mapNotNull { (key, picture) -> picture.string?.let { key to it } }.toMap(linkedMapOf()),
            value["removed"].array.orEmpty().mapNotNullTo(mutableListOf()) { r ->
                Removal(r["cardKey"].string ?: return@mapNotNullTo null, r["picture"].string ?: return@mapNotNullTo null)
            })
    }.getOrNull() ?: Record()

    fun save() {
        val fields = linkedMapOf<String, JsonElement>()
        record.account?.let { fields["account"] = JsonPrimitive(it) }
        fields["cursor"] = JsonPrimitive(record.cursor)
        fields["synced"] = JsonObject(record.synced.mapValues { JsonPrimitive(it.value) })
        fields["removed"] = JsonArray(record.removed.map { JsonObject(mapOf("cardKey" to JsonPrimitive(it.cardKey), "picture" to JsonPrimitive(it.picture))) })
        write(JsonObject(fields).toString())
    }
}

class CardArtSync(private val local: CardArtLocal, private val state: CardArtSyncState, private val api: CardArtSyncAPI,
                  private val codeOf: (Throwable) -> String?) {
    companion object {
        /** Codes the server answers for one card that will not change by asking again: that card stays on this device. */
        val refusals = setOf("invalid_card_art", "too_many_pictures", "Payload too large", "invalid_mime_type")

        /** SHA-256 of a picture's bytes, lower-case hex. */
        fun pictureHash(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }

    private var running: CompletableDeferred<Unit>? = null
    /** Cards the server refused this session (too many, too large): not offered again until their picture changes. */
    private val refused = mutableMapOf<String, String>()

    val record: CardArtSyncState.Record get() = state.record

    /** The player removed a card's picture here: the server's copy goes next sync. */
    @Synchronized fun noteRemoved(cardKey: String) {
        val picture = record.synced.remove(cardKey) ?: return
        record.removed.removeAll { it.cardKey == cardKey }
        record.removed += CardArtSyncState.Removal(cardKey, picture)
        state.save()
    }

    /** Something made here waits to go up. */
    fun hasPending(): Boolean = record.removed.isNotEmpty() || local.keys().any { key ->
        val hash = local.hash(key)
        hash != null && hash != record.synced[key] && refused[key] != hash
    }

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
        // 1. Another profile: start over, so every picture here joins it. Nothing local is deleted.
        if (record.account != account) {
            state.record = CardArtSyncState.Record(account)
            state.save()
        }
        // 2. Pull.
        pull()
        // 3. Removals made here.
        for (removal in record.removed.toList()) {
            api.set(removal.cardKey, null)
            record.removed.remove(removal)
            state.save()
            forget(removal.picture)
        }
        // 4. Pictures set or changed here.
        for (key in local.keys()) {
            val hash = local.hash(key) ?: continue
            if (hash == record.synced[key] || refused[key] == hash) continue
            val bytes = local.bytes(key) ?: continue
            try {
                api.upload(hash, bytes)
                api.set(key, hash)
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException) throw error
                if (codeOf(error) in refusals) { refused[key] = hash; forget(hash); continue }
                throw error
            }
            val old = record.synced.put(key, hash)
            state.save()
            if (old != null) forget(old)
        }
        // 5. Pull once more, past this device's own changes.
        pull()
    }

    private suspend fun pull() {
        while (true) {
            val page = api.since(record.cursor)
            for (art in page.arts) apply(art)
            record.cursor = page.cursor
            state.save()
            if (!page.more) break
        }
    }

    private suspend fun apply(art: ServerCardArt) {
        val key = art.cardKey
        record.removed.firstOrNull { it.cardKey == key }?.let { removal ->
            // This device's removal follows, unless someone set another picture meanwhile (it comes back).
            if (art.picture == removal.picture) return
            record.removed.remove(removal)
            if (art.picture == null) return
        }
        val hash = local.hash(key)
        val changedHere = hash != null && hash != record.synced[key]
        val picture = art.picture
        if (picture == null) {
            if (hash != null && !changedHere) local.remove(key)
            record.synced.remove(key)
            return
        }
        if (hash != picture && !changedHere) local.store(key, api.download(picture))
        // Changed here since the last sync: this device's picture goes up and wins.
        record.synced[key] = picture
    }

    /** A file no card points at any more. */
    private suspend fun forget(picture: String) {
        if (picture in record.synced.values) return
        try { api.removeFile(picture) } catch (error: Exception) { if (error is kotlinx.coroutines.CancellationException) throw error }
    }
}
