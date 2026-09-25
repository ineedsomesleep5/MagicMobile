package io.magicmobile.android.studio

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.DeckStore
import io.magicmobile.android.SavedDeck
import io.magicmobile.android.game.array
import io.magicmobile.android.game.string
import io.magicmobile.android.ondevice.PreconDeck
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive

/**
 * DeckLibraryRecord.swift on the Android library. Local decks keep the file store build 7 wrote
 * (one JSON file per deck, revision-checked), so existing decks open unchanged.
 */
data class DeckLibraryRecord(
    val id: String,
    val name: String,
    val commander: DeckEntry?,
    val entries: List<DeckEntry>,
    val sourceURL: String?,
    val revision: Long,
    /** Milliseconds since the epoch; 0 for included decks. */
    val updatedAt: Long,
    val isCloudBacked: Boolean = false,
    internal val saved: SavedDeck? = null,
) {
    val deckList: DeckList get() = DeckList(name, commander, entries)
    val cardCount: Int get() = deckList.totalCards

    companion object {
        fun of(saved: SavedDeck): DeckLibraryRecord {
            val list = DeckList.fromStored(saved.deck)
            return DeckLibraryRecord(saved.id, list.name, list.commander, list.entries, saved.sourceURL, saved.revision, saved.modifiedAtMillis, saved = saved)
        }
        fun included(precon: PreconDeck): DeckLibraryRecord {
            val list = DeckList.fromStored(precon.deck)
            return DeckLibraryRecord("precon:${precon.id}", list.name, list.commander, list.entries, null, 1, 0)
        }
    }
}

/**
 * DeckLibraryStore.swift: durable local decks. Every write checks the revision on disk, so two
 * screens can never silently overwrite each other. `changed` keeps the setup model in step.
 */
class DeckLibraryStore(private val store: DeckStore, private val changed: (List<SavedDeck>) -> Unit) {
    var decks by mutableStateOf<List<DeckLibraryRecord>>(emptyList()); private set
    var notice by mutableStateOf<String?>(null)
    private var readFailed = false

    init { reload() }

    fun reload() {
        try {
            val saved = store.all()
            readFailed = false
            publish(saved)
        } catch (error: Exception) {
            readFailed = true
            notice = "The saved deck library could not be read. It has not been replaced."
        }
    }

    private fun publish(saved: List<SavedDeck>) {
        decks = saved.map(DeckLibraryRecord::of).sortedByDescending { it.updatedAt }
        changed(saved)
    }

    private fun guardReadable() { if (readFailed) throw DeckEditingError.UnreadableCache }

    fun addLocalDurably(deck: DeckList, sourceURL: String? = null): DeckLibraryRecord {
        guardReadable()
        OnDeviceDeckEditing.validateDraft(deck)
        val saved = try { store.save(deck.storedDeck(), null, sourceURL) } catch (error: IllegalArgumentException) { throw DeckEditingError.InvalidEntry }
        reloadAfterWrite()
        return DeckLibraryRecord.of(saved)
    }

    /** Draft persistence only: this does not certify card support or engine legality. */
    fun updateLocalDurably(deck: DeckList, id: String, expectedRevision: Long): DeckLibraryRecord {
        guardReadable()
        OnDeviceDeckEditing.validateDraft(deck)
        val record = decks.firstOrNull { it.id == id } ?: throw DeckEditingError.MissingRecord
        val original = record.saved ?: throw DeckEditingError.CopyRequired
        if (original.revision != expectedRevision) throw DeckEditingError.StaleRevision
        val saved = try { store.save(deck.storedDeck(), original) } catch (error: IllegalArgumentException) {
            if (error.message?.contains("changed on disk") == true) throw DeckEditingError.StaleRevision
            throw DeckEditingError.InvalidEntry
        }
        reloadAfterWrite()
        return DeckLibraryRecord.of(saved)
    }

    fun deleteLocalDurably(id: String, expectedRevision: Long) {
        guardReadable()
        val record = decks.firstOrNull { it.id == id } ?: throw DeckEditingError.MissingRecord
        val original = record.saved ?: throw DeckEditingError.CopyRequired
        if (original.revision != expectedRevision) throw DeckEditingError.StaleRevision
        try { store.delete(original) } catch (error: IllegalArgumentException) { throw DeckEditingError.StaleRevision }
        reloadAfterWrite()
    }

    /** Copies local or included decks without touching the original's identity or source. */
    fun duplicateLocalDurably(record: DeckLibraryRecord, name: String): DeckLibraryRecord {
        guardReadable()
        val deck = DeckList(name, record.commander, record.entries)
        OnDeviceDeckEditing.validateDraft(deck)
        val saved = try { store.save(deck.storedDeck(), null, record.sourceURL) } catch (error: IllegalArgumentException) { throw DeckEditingError.InvalidEntry }
        reloadAfterWrite()
        return DeckLibraryRecord.of(saved)
    }

    private fun reloadAfterWrite() {
        // One unreadable file must not hide a successful write; keep the list in step either way.
        runCatching { publish(store.all()) }.onFailure { notice = "The saved deck library could not be read. It has not been replaced." }
    }

    companion object {
        private const val favoritesKey = "deckStudio.library.favorites.v1"
        private const val migratedKey = "deckStudio.library.android.migrated.v1"

        /**
         * Build 7 kept favourites, tags and notes inside each deck file. Deck Studio keeps them
         * apart as iOS does; copy them over once and leave the originals untouched.
         */
        fun migrateBuild7Details(saved: List<SavedDeck>) {
            val defaults = DeckStudioServices.defaults
            if (defaults.string(migratedKey) == "true") return
            val favorites = loadFavorites().getOrNull()?.toMutableSet() ?: return
            favorites += saved.filter { it.favorite }.map { "local:${it.id}" }
            saveFavorites(favorites)
            for (deck in saved) {
                if (deck.tags.isEmpty() && deck.notes.isEmpty()) continue
                runCatching {
                    val existing = DeckStudioServices.organization.load(deck.id)
                    if (existing.revision == 0) DeckStudioServices.organization.save(DeckStudioOrganization(tags = deck.tags, notes = deck.notes), deck.id, 0)
                }
            }
            defaults.set(migratedKey, "true")
        }

        fun loadFavorites(): Result<Set<String>> = runCatching {
            val text = DeckStudioServices.defaults.string(favoritesKey) ?: return@runCatching emptySet()
            if (text.utf8Size > 256 * 1024) throw IllegalStateException("corrupt")
            val values = (Json.parseToJsonElement(text).array ?: throw IllegalStateException("corrupt")).map { it.string ?: throw IllegalStateException("corrupt") }
            if (values.size > 4000 || !values.all { it.utf8Size <= 256 }) throw IllegalStateException("corrupt")
            values.toSet()
        }

        fun saveFavorites(values: Set<String>) {
            DeckStudioServices.defaults.set(favoritesKey, JsonArray(values.sorted().map(::JsonPrimitive)).toString())
        }
    }
}
