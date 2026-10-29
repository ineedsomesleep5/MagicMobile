package io.magicmobile.android.studio

import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.string
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.UUID

/**
 * Deck sync against a fake server, running every scenario in parity/deck-sync-cases.json (docs/DECK_SYNC.md), the cases
 * iOS and the web run too, plus the web test's extra cases (apps/web/test/deckSync.test.ts).
 */
class DeckSyncTest {
    private val repo = File(System.getProperty("magicmobile.repo") ?: "../../..")
    private val cases = Json.parseToJsonElement(File(repo, "apps/android/core/src/test/resources/parity/deck-sync-cases.json").readText())["cases"].array!!

    private fun document(cards: List<String>): JsonObject = JsonObject(mapOf(
        "format" to JsonPrimitive("commander"),
        "entries" to JsonArray(cards.map { JsonObject(mapOf("cardName" to JsonPrimitive(it), "quantity" to JsonPrimitive(1), "section" to JsonPrimitive("deck"))) }),
        "source" to JsonObject(mapOf("kind" to JsonPrimitive("manual")))))

    private fun cardsOf(doc: JsonElement?): List<String> = doc["entries"].array.orEmpty().mapNotNull { it["cardName"].string }

    /** mm_decks_since / mm_deck_save / mm_deck_delete over a map, as the migration does them. */
    private class FakeServer(initial: List<ServerDeck>) : DeckSyncAPI {
        val decks = LinkedHashMap<String, ServerDeck>()
        var seq = 0L
        init { for (d in initial) { decks[d.id] = d; seq = maxOf(seq, d.changeSeq) } }

        override suspend fun since(cursor: Long): DeckSyncAPI.Page {
            val changed = decks.values.filter { it.changeSeq > cursor }.sortedBy { it.changeSeq }
            return DeckSyncAPI.Page(changed, changed.lastOrNull()?.changeSeq ?: cursor, false)
        }

        override suspend fun save(id: String, name: String, document: JsonObject, base: Long?): DeckSyncAPI.Saved {
            val row = decks[id.lowercase()]
            if (row == null) {
                if (base != null) throw IllegalStateException("not_found")
                val created = ServerDeck(id.lowercase(), name, 1, ++seq, false, document)
                decks[created.id] = created
                return DeckSyncAPI.Saved(true, created)
            }
            if (row.deleted || base == null || row.revision != base) return DeckSyncAPI.Saved(false, row)
            val updated = row.copy(name = name, deck = document, revision = row.revision + 1, changeSeq = ++seq)
            decks[row.id] = updated
            return DeckSyncAPI.Saved(true, updated)
        }

        override suspend fun remove(id: String, base: Long): DeckSyncAPI.Deleted {
            val row = decks[id.lowercase()]
            if (row == null || row.deleted) return DeckSyncAPI.Deleted(false, row)
            if (row.revision != base) return DeckSyncAPI.Deleted(true, row)
            val gone = row.copy(deleted = true, deck = null, revision = row.revision + 1, changeSeq = ++seq)
            decks[row.id] = gone
            return DeckSyncAPI.Deleted(false, gone)
        }
    }

    /** The library's sync hooks over a list, as DeckLibraryStore does them over its files. */
    private class MemoryLibrary(initial: List<SyncedDeck>) : DeckSyncLibrary {
        override var decks: List<SyncedDeck> = initial
        var onDeleted: ((String) -> Unit)? = null

        override fun applySynced(id: String, deck: DeckList, sourceURL: String?): SyncedDeck {
            OnDeviceDeckEditing.validateDraft(deck)
            val old = recordMatching(id)
            val record = SyncedDeck(old?.id ?: id, deck.name, deck.commander, deck.entries, sourceURL, (old?.revision ?: 0) + 1)
            decks = if (old != null) decks.map { if (it === old) record else it } else listOf(record) + decks
            return record
        }

        override fun removeSynced(id: String) { recordMatching(id)?.let { gone -> decks = decks.filter { it !== gone } } }

        override fun addFork(original: SyncedDeck, name: String): SyncedDeck {
            val deck = DeckList(name, original.commander, original.entries)
            OnDeviceDeckEditing.validateDraft(deck)
            return SyncedDeck(UUID.randomUUID().toString(), name, deck.commander, deck.entries, original.sourceURL, 1).also { decks = listOf(it) + decks }
        }

        fun delete(id: String) {
            val gone = record(id) ?: return
            decks = decks.filter { it !== gone }
            onDeleted?.invoke(gone.id)
        }
    }

    private class Store { var text: String? = null; fun state() = SyncState({ text }, { text = it }) }

    private fun library(decks: List<Triple<String, String, Pair<Long, List<String>>>>) = MemoryLibrary(decks.map { (id, name, rest) ->
        SyncedDeck(id, name, null, rest.second.map { DeckEntry(it, 1, "deck") }, null, rest.first)
    })

    private fun sync(library: MemoryLibrary, state: SyncState, server: FakeServer) =
        DeckSync(library, state, server) { it.message }.also { s -> library.onDeleted = { s.noteDeleted(it) } }

    private data class Row(val id: String, val name: String, val cards: List<String>? = null, val revision: Long? = null, val deleted: Boolean? = null)

    @Test fun everyParityCase() {
        assertEquals(12, cases.size)
        for (c in cases) {
            val name = c["name"].string!!
            val server = FakeServer(c["server"].array!!.map { d ->
                val deleted = d["deleted"].bool!!
                ServerDeck(d["id"].string!!.lowercase(), d["name"].string!!, d["revision"].integer!!, d["seq"].integer!!, deleted,
                    if (deleted) null else document(d["cards"].array!!.map { it.string!! }))
            })
            val lib = library(c["local"].array!!.map { d -> Triple(d["id"].string!!, d["name"].string!!, d["revision"].integer!! to d["cards"].array!!.map { it.string!! }) })
            val store = Store()
            c["sync"]?.takeIf { it !is JsonNull }?.let { store.text = it.toString() }
            val sync = sync(lib, store.state(), server)
            runBlocking { sync.sync(c["account"].string!!) }

            val original = (c["local"].array!! + c["server"].array!!).map { it["id"].string!!.lowercase() }.toSet()
            fun idOf(id: String) = if (id.lowercase() in original) id.lowercase() else "fork"
            fun expectedID(d: J) = if (d["fork"].bool == true) "fork" else d["id"].string!!.lowercase()

            val local = lib.decks.map { Row(idOf(it.id), it.name, cards = it.deckList.let { l -> listOfNotNull(l.commander) + l.entries }.map { e -> e.cardName }) }
            val expectedLocal = c["expect"]["local"].array!!.map { d -> Row(expectedID(d), d["name"].string!!, cards = d["cards"].array!!.map { it.string!! }) }
            assertEquals(name, expectedLocal.sortedBy { it.name }, local.sortedBy { it.name })

            val remote = server.decks.values.map { Row(idOf(it.id), it.name, revision = it.revision, deleted = it.deleted) }
            val expectedRemote = c["expect"]["server"].array!!.map { d -> Row(expectedID(d), d["name"].string!!, revision = d["revision"].integer!!, deleted = d["deleted"].bool!!) }
            assertEquals(name, expectedRemote.sortedBy { it.name }, remote.sortedBy { it.name })

            for (d in lib.decks) assertFalse("$name: ${d.name} dirty", sync.isDirty(d))
            assertTrue(name, sync.record.tombstones.isEmpty())
            for (d in server.decks.values.filter { !it.deleted }) {
                val mine = lib.recordMatching(d.id) ?: continue
                assertEquals(name, cardsOf(d.deck), mine.entries.map { it.cardName })
            }
        }
    }

    @Test fun aDeleteHereLeavesATombstoneOnlyWhenTheServerHasTheDeck() {
        val lib = library(listOf(Triple("AAAAAAAA-1111-4222-8333-444444444444", "Synced", 1L to listOf("Forest")), Triple("B1", "Local only", 1L to listOf("Island"))))
        val store = Store()
        store.text = """{"account":"A","cursor":1,"entries":{"aaaaaaaa-1111-4222-8333-444444444444":{"serverRevision":4,"syncedLocalRevision":1}},"tombstones":[]}"""
        val sync = sync(lib, store.state(), FakeServer(emptyList()))
        lib.delete("AAAAAAAA-1111-4222-8333-444444444444")
        lib.delete("B1")
        assertEquals(listOf(SyncState.Tombstone("aaaaaaaa-1111-4222-8333-444444444444", 4)), sync.record.tombstones)
        // The record on disk has it too, ids folded to lower case.
        assertEquals(sync.record.tombstones, store.state().record.tombstones)
    }

    @Test fun aSecondSyncChangesNothingAndAForkNameKeepsTo512Bytes() {
        val lib = library(listOf(Triple("L1", "Atraxa", 1L to listOf("Sol Ring"))))
        val server = FakeServer(emptyList())
        val store = Store()
        val sync = sync(lib, store.state(), server)
        runBlocking { sync.sync("A") }
        val before = server.decks.values.toList()
        val revisions = lib.decks.map { it.revision }
        runBlocking { sync.sync("A") }
        assertEquals(before, server.decks.values.toList())
        assertEquals(revisions, lib.decks.map { it.revision })
        assertTrue(forkName("é".repeat(300)).utf8Size <= 512)
        assertTrue(forkName("😀".repeat(200)).let { it.utf8Size <= 512 && !Character.isHighSurrogate(it[it.length - 15]) })
        assertEquals("Mine (this device)", forkName("Mine"))
        assertTrue(forkName("x".repeat(400), maxChars = 300).length <= 300)
    }

    @Test fun aRefusedDeckStaysLocalUntilItChanges() {
        val lib = library(listOf(Triple("L1", "Atraxa", 1L to listOf("Sol Ring"))))
        var saves = 0
        val refusing = object : DeckSyncAPI {
            override suspend fun since(cursor: Long) = DeckSyncAPI.Page(emptyList(), cursor, false)
            override suspend fun save(id: String, name: String, document: JsonObject, base: Long?): DeckSyncAPI.Saved { saves += 1; throw IllegalStateException("invalid_deck") }
            override suspend fun remove(id: String, base: Long) = DeckSyncAPI.Deleted(false, null)
        }
        val sync = DeckSync(lib, Store().state(), refusing) { it.message }
        runBlocking { sync.sync("A"); sync.sync("A") }
        assertEquals(1, saves)
        assertEquals(SyncState.Entry(0, 1), sync.record.entries["l1"])
        assertFalse(sync.hasPending())
    }
}
