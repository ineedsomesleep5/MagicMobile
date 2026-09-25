package io.magicmobile.android.studio

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.core.CardInfo
import java.util.UUID

/**
 * DeckStudioEditorModel.swift: one source of truth for the draft, its disk revision and undo.
 * Durable local storage and recovery stay authoritative; nothing is written to a cloud.
 */
class DeckStudioEditorModel(private val library: DeckLibraryStore, record: DeckLibraryRecord?, included: Boolean = false,
                            private val defaults: StudioDefaults = DeckStudioServices.defaults) {
    var history by mutableStateOf(DeckStudioEditHistory(record?.let { NativeDeckDraft.of(it.deckList) } ?: NativeDeckDraft())); private set
    var record by mutableStateOf(record); private set
    var readOnly by mutableStateOf(included || record?.isCloudBacked == true); private set
    var recovered by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null)
    var recoveryBlocked = false; private set
    private var recoveryKey = record?.let { "${it.id}.${it.revision}" } ?: "new"
    private var sourceURL = record?.sourceURL

    init {
        if (!readOnly) {
            try {
                NativeDeckDraftRecovery.load(recoveryKey, defaults)?.let { saved -> history = history.restored(saved); recovered = history.isDirty }
            } catch (failure: Exception) {
                recoveryBlocked = true
                error = "A recovery draft could not be read. It has been preserved; automatic recovery writes are paused. ${failure.message ?: ""}".trim()
            }
        }
    }

    val draft: NativeDeckDraft get() = history.value
    val isDirty: Boolean get() = history.isDirty
    val canSave: Boolean get() = !readOnly && runCatching { draft.deck() }.isSuccess
    val saveLabel: String get() = when {
        readOnly -> "Included / read-only"
        recoveryBlocked -> "Recovery paused · original data preserved"
        error != null && isDirty -> "Unsaved changes · check recovery error"
        recovered && isDirty -> "Recovered draft · unsaved"
        isDirty -> "Unsaved changes · recovery kept locally"
        record == null -> "New local draft"
        else -> "Saved on this device"
    }

    fun change(operation: (NativeDeckDraft) -> NativeDeckDraft): Boolean {
        if (readOnly) return false
        return try {
            history = history.edited { value ->
                val next = operation(value)
                next.copy(name = "Draft").deck()
                next
            }
            persistRecovery()
            true
        } catch (failure: Exception) { error = failure.message; false }
    }

    fun undo() { if (readOnly) return; history = history.undone(); persistRecovery() }
    fun redo() { if (readOnly) return; history = history.redone(); persistRecovery() }

    /** An explicit discard never overwrites the saved record or unreadable recovery. */
    fun discardUnsavedChanges() {
        if (readOnly) return
        history = DeckStudioEditHistory(history.baseline)
        recovered = false
        if (!recoveryBlocked) NativeDeckDraftRecovery.clear(recoveryKey, defaults)
        error = null
    }

    fun makeEditableCopy() {
        val source = record ?: return
        if (!readOnly) return
        try {
            val copy = library.duplicateLocalDurably(source, draft.name + " — My copy")
            record = copy; readOnly = false; recoveryKey = "${copy.id}.${copy.revision}"
            history = DeckStudioEditHistory(NativeDeckDraft.of(copy.deckList))
            recovered = false; error = null
            runCatching { DeckStudioServices.organization.duplicate(source.id, copy.id) }.onFailure {
                if (record?.id == copy.id) error = "The deck cards were copied, but their optional notes/tags could not be copied. The original details remain intact."
            }
        } catch (failure: Exception) { error = failure.message }
    }

    fun add(name: String, section: String = "deck"): Boolean = change { value ->
        val effective = DeckStudioDraftPresentation.normalizedSection(section)
        val index = value.rows.indexOfFirst { it.cardName == name && DeckStudioDraftPresentation.section(it) == effective }
        if (index >= 0) {
            val quantity = value.rows[index].quantity.toLong() + 1
            if (quantity > Int.MAX_VALUE) throw DeckEditingError.InvalidEntry
            value.copy(rows = value.rows.toMutableList().also { it[index] = it[index].copy(quantity = quantity.toInt()) })
        } else value.copy(rows = value.rows + NativeDeckRow(cardName = name, section = section))
    }

    fun cardCount(name: String, section: String? = null): Int {
        val destination = section?.let(DeckStudioDraftPresentation::normalizedSection)
        return draft.rows.filter { it.cardName == name && (destination == null || DeckStudioDraftPresentation.section(it) == destination) }.sumOf { it.quantity }
    }

    fun removeOne(name: String, section: String) {
        val row = draft.rows.lastOrNull { it.cardName == name && DeckStudioDraftPresentation.section(it) == DeckStudioDraftPresentation.normalizedSection(section) } ?: return
        quantity(row.id, -1)
    }

    /** Advisory only: XMage remains responsible for exceptions and exact legality. */
    fun needsSingletonReview(name: String, metadata: CardInfo?, destination: String): Boolean {
        if (DeckStudioDraftPresentation.normalizedSection(destination) !in setOf("deck", "commanders") ||
            cardCount(name, "deck") + cardCount(name, "commanders") <= 0) return false
        if (metadata?.typeLine?.startsWith("Basic ") == true) return false
        if (metadata?.oracleText?.contains("A deck can have", ignoreCase = true) == true) return false
        return true
    }

    fun quantity(id: UUID, delta: Int) {
        change { value ->
            val index = value.rows.indexOfFirst { it.id == id }
            if (index < 0) throw DeckEditingError.MissingEntry
            val next = value.rows[index].quantity.toLong() + delta
            if (next > Int.MAX_VALUE || next < Int.MIN_VALUE) throw DeckEditingError.InvalidEntry
            value.copy(rows = value.rows.toMutableList().also { if (next <= 0) it.removeAt(index) else it[index] = it[index].copy(quantity = next.toInt()) })
        }
    }

    fun move(id: UUID, section: String) {
        change { value ->
            val index = value.rows.indexOfFirst { it.id == id }
            if (index < 0) throw DeckEditingError.MissingEntry
            value.copy(rows = value.rows.toMutableList().also { it[index] = it[index].copy(section = section, isPrimaryCommander = false) })
        }
    }

    fun remove(id: UUID) { change { value -> value.copy(rows = value.rows.filterNot { it.id == id }) } }
    fun replace(rowID: UUID, name: String): Boolean = change { DeckStudioEditorOperations.replaceCard(it, rowID, name) }
    fun commander(name: String, keepOld: Boolean): Boolean = change { DeckStudioEditorOperations.replacePrimaryCommander(it, name, keepOld) }
    fun basics(values: Map<String, Int>, expected: NativeDeckDraft): Boolean {
        if (expected != draft) { error = "The draft changed. Reopen the land tool."; return false }
        return change { DeckStudioEditorOperations.setBasicLands(it, values) }
    }
    fun rename(name: String) { change { it.copy(name = name) } }

    /**
     * A draft with non-playing boards produces a separate playable copy. It is never rewritten to
     * satisfy the resolver; unsaved source changes are saved first.
     */
    fun preparePlayable(playing: DeckList, resolver: OnDeviceDeckResolver): String? = try {
        val projection = DeckStudioPlayProjection(draft.deck())
        if (projection.resolve(resolver) != resolver.resolve(playing)) throw DeckEditingError.StaleRevision
        if (projection.excluded.isEmpty()) {
            val current = record
            if (readOnly && current != null) (if (current.id.startsWith("precon:")) current.id else "local:${current.id}")
            else save()?.let { "local:${it.id}" }
        } else {
            if (!readOnly && (isDirty || record == null) && save() == null) null
            else {
                val copy = DeckList(playing.name.take(96) + " — Playtest", playing.commander, playing.entries)
                "local:${library.addLocalDurably(copy, sourceURL).id}"
            }
        }
    } catch (failure: Exception) { error = failure.message; null }

    fun save(): DeckLibraryRecord? {
        if (!canSave) return null
        return try {
            val deck = draft.deck()
            val current = record
            val saved = if (current != null) library.updateLocalDurably(deck, current.id, current.revision) else library.addLocalDurably(deck, sourceURL)
            if (!recoveryBlocked) NativeDeckDraftRecovery.clear(recoveryKey, defaults)
            record = saved; recoveryKey = "${saved.id}.${saved.revision}"
            history = history.saved(); recovered = false; error = null
            saved
        } catch (failure: Exception) { error = failure.message; null }
    }

    fun persistRecovery(): Boolean {
        if (readOnly) return true
        if (recoveryBlocked) return false
        return try {
            if (history.isDirty) NativeDeckDraftRecovery.save(draft, recoveryKey, defaults) else NativeDeckDraftRecovery.clear(recoveryKey, defaults)
            true
        } catch (failure: Exception) { error = "Draft recovery could not be saved: ${failure.message}"; false }
    }
}
