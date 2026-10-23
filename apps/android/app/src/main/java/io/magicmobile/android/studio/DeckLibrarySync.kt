package io.magicmobile.android.studio

import android.util.AtomicFile
import java.io.File

/** Deck sync's view of Deck Studio's library (core DeckSync keeps the rules, docs/DECK_SYNC.md). */
class DeckLibrarySyncAdapter(private val library: DeckLibraryStore) : DeckSyncLibrary {
    override val decks: List<SyncedDeck> get() = library.decks.map(::synced)
    override fun record(id: String): SyncedDeck? = library.decks.firstOrNull { it.id == id }?.let(::synced)
    override fun recordMatching(id: String): SyncedDeck? = library.recordMatching(id)?.let(::synced)
    override fun applySynced(id: String, deck: DeckList, sourceURL: String?): SyncedDeck = synced(library.applySynced(id, deck, sourceURL))
    override fun removeSynced(id: String) = library.removeSynced(id)

    /** A fork keeps the original's tags and notes; it is a new deck, so favourites stay with the original. */
    override fun addFork(original: SyncedDeck, name: String): SyncedDeck {
        val copy = library.addLocalDurably(DeckList(name, original.commander, original.entries), original.sourceURL)
        runCatching { DeckStudioServices.organization.duplicate(original.id, copy.id) }
        return synced(copy)
    }

    /** The library's saved Deck keeps names to 300 characters. */
    override val maxNameChars: Int get() = 300

    private fun synced(record: DeckLibraryRecord) = SyncedDeck(record.id, record.name, record.commander, record.entries, record.sourceURL, record.revision)

    companion object {
        /** The sync record beside the library's `decks-v1` folder (not inside it: every file there is read as a deck). */
        fun state(filesDir: File): SyncState {
            val file = AtomicFile(File(filesDir, "decks-v1-sync.json"))
            return SyncState(
                read = { runCatching { file.readFully().toString(Charsets.UTF_8) }.getOrNull() },
                write = { text ->
                    runCatching {
                        val output = file.startWrite()
                        try { output.write(text.toByteArray(Charsets.UTF_8)); file.finishWrite(output) } catch (error: Exception) { file.failWrite(output); throw error }
                    }
                })
        }
    }
}
