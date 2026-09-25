package io.magicmobile.android.studio

import java.net.URI
import java.text.Normalizer
import java.util.Locale
import java.util.UUID
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/** DeckStudioCore.swift: presentation identity, separate from the mutable deck and native seats. */
data class DeckStudioShelfItem(
    val id: String,
    val name: String,
    val commanders: List<String>,
    val tags: List<String>,
    val origin: Origin,
    /** Milliseconds since the epoch; null for included decks. */
    val updatedAt: Long?,
) {
    enum class Origin { LOCAL, INCLUDED }
}

data class DeckStudioLibraryQuery(val text: String = "", val filter: Filter = Filter.ALL, val sort: Sort = Sort.EDITED) {
    enum class Filter(val title: String) { ALL("All"), FAVORITES("Favorites"), LOCAL("My decks"), INCLUDED("Included") }
    enum class Sort(val title: String) { EDITED("Recently edited"), NAME("Name"), COMMANDER("Commander") }

    fun apply(items: List<DeckStudioShelfItem>, favorites: Set<String>): List<DeckStudioShelfItem> {
        val words = key(text).split(Regex("\\s+")).filter { it.isNotEmpty() }
        val matching = items.filter { item ->
            val haystack = key((listOf(item.name) + item.commanders + item.tags).joinToString(" "))
            words.all { haystack.contains(it) } && when (filter) {
                Filter.ALL -> true
                Filter.FAVORITES -> item.id in favorites
                Filter.LOCAL -> item.origin == DeckStudioShelfItem.Origin.LOCAL
                Filter.INCLUDED -> item.origin == DeckStudioShelfItem.Origin.INCLUDED
            }
        }
        return matching.sortedWith { lhs, rhs ->
            when (sort) {
                Sort.EDITED -> {
                    val a = lhs.updatedAt ?: Long.MIN_VALUE; val b = rhs.updatedAt ?: Long.MIN_VALUE
                    if (a != b) return@sortedWith b.compareTo(a)
                }
                Sort.COMMANDER -> {
                    val a = key(lhs.commanders.joinToString(" / ")); val b = key(rhs.commanders.joinToString(" / "))
                    if (a != b) return@sortedWith a.compareTo(b)
                }
                Sort.NAME -> {}
            }
            val a = key(lhs.name); val b = key(rhs.name)
            if (a == b) lhs.id.compareTo(rhs.id) else a.compareTo(b)
        }
    }

    companion object {
        private val marks = Regex("\\p{M}+")
        /** Case- and diacritic-insensitive, like Swift's folding(options:locale:). */
        fun key(text: String): String = marks.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase(Locale.ROOT)
    }
}

/**
 * Bounded whole-draft transactions. A failed edit never partially updates state. The generation
 * advances on undo and redo too, so an old async reply cannot validate a new revision.
 */
class DeckStudioEditHistory<T> private constructor(
    val value: T,
    val baseline: T,
    val generation: UUID,
    private val past: List<T>,
    private val future: List<T>,
    private val limit: Int,
) {
    constructor(value: T, limit: Int = 64) : this(value, value, UUID.randomUUID(), emptyList(), emptyList(), limit.coerceIn(1, 256))

    val isDirty: Boolean get() = value != baseline
    val canUndo: Boolean get() = past.isNotEmpty()
    val canRedo: Boolean get() = future.isNotEmpty()

    fun edited(operation: (T) -> T): DeckStudioEditHistory<T> {
        val next = operation(value)
        if (next == value) return this
        return DeckStudioEditHistory(next, baseline, UUID.randomUUID(), (past + value).takeLast(limit), emptyList(), limit)
    }
    fun undone(): DeckStudioEditHistory<T> {
        val previous = past.lastOrNull() ?: return this
        return DeckStudioEditHistory(previous, baseline, UUID.randomUUID(), past.dropLast(1), future + value, limit)
    }
    fun redone(): DeckStudioEditHistory<T> {
        val next = future.lastOrNull() ?: return this
        return DeckStudioEditHistory(next, baseline, UUID.randomUUID(), past + value, future.dropLast(1), limit)
    }
    fun saved(): DeckStudioEditHistory<T> = DeckStudioEditHistory(value, value, generation, past, future, limit)
    /** Restoration is one undoable edit and is still dirty relative to disk. */
    fun restored(recovered: T): DeckStudioEditHistory<T> = edited { recovered }
}

/** Exact sampling-without-replacement math, not AI playtesting or a mulligan model. */
object DeckStudioProbability {
    class InvalidPopulation : Exception("Invalid population")

    fun atLeast(threshold: Int, successes: Int, population: Int, draws: Int): Double {
        if (population !in 0..2000 || successes !in 0..population || draws !in 0..population) throw InvalidPopulation()
        val low = max(0, draws - (population - successes)); val high = min(successes, draws)
        if (threshold <= low) return 1.0
        if (threshold > high) return 0.0
        fun logChoose(n: Int, k: Int): Double {
            val count = min(k, n - k)
            if (count <= 0) return 0.0
            var result = 0.0
            for (index in 1..count) result += ln((n - count + index).toDouble()) - ln(index.toDouble())
            return result
        }
        val denominator = logChoose(population, draws)
        val probability = (threshold..high).fold(0.0) { total, hits ->
            total + exp(logChoose(successes, hits) + logChoose(population - successes, draws - hits) - denominator)
        }
        return probability.coerceIn(0.0, 1.0)
    }
}

/**
 * Ordinary user browsing only. This never loads a page, extracts content, invents a commander
 * slug or embeds a private deck in a URL.
 */
object DeckStudioEDHRECPolicy {
    const val browseURL = "https://edhrec.com/commanders"
    const val recsURL = "https://edhrec.com/recs"

    fun allowsEmbeddedNavigation(url: String): Boolean {
        val uri = runCatching { URI(url) }.getOrNull() ?: return false
        if (uri.scheme?.lowercase() != "https" || uri.rawUserInfo != null || (uri.port != -1 && uri.port != 443)) return false
        val host = uri.host?.lowercase() ?: return false
        return host == "edhrec.com" || host == "www.edhrec.com"
    }

    fun allowsExternalBrowser(url: String): Boolean {
        val uri = runCatching { URI(url) }.getOrNull() ?: return false
        return uri.scheme?.lowercase() == "https" && uri.rawUserInfo == null && !uri.host.isNullOrEmpty()
    }
}

/** One Undo reverses a whole replacement, commander promotion or basic-land operation. */
object DeckStudioEditorOperations {
    fun replaceCard(draft: NativeDeckDraft, rowID: UUID, name: String): NativeDeckDraft {
        val index = draft.rows.indexOfFirst { it.id == rowID }
        if (index < 0) throw DeckEditingError.MissingEntry
        return draft.copy(rows = draft.rows.toMutableList().also { it[index] = it[index].copy(cardName = name) })
    }

    fun replacePrimaryCommander(draft: NativeDeckDraft, name: String, keepOld: Boolean): NativeDeckDraft {
        val rows = draft.rows.toMutableList()
        val primary = rows.indexOfFirst { it.isPrimaryCommander }.takeIf { it >= 0 }
            ?: rows.indexOfFirst { it.section.trim().lowercase() in setOf("commander", "commanders") }.takeIf { it >= 0 }
        if (primary != null && rows[primary].cardName == name) return draft
        if (primary != null) {
            val old = rows[primary]
            rows[primary] = old.copy(cardName = name, quantity = 1, section = "commanders", isPrimaryCommander = true)
            if (keepOld) rows += NativeDeckRow(cardName = old.cardName, quantity = old.quantity, section = "maybeboard")
        } else rows.add(0, NativeDeckRow(cardName = name, section = "commanders", isPrimaryCommander = true))
        // Explicit promotion moves one main-deck copy; partners and other boards stay intact.
        val index = rows.indexOfFirst { !it.isPrimaryCommander && it.cardName == name && it.section.trim().lowercase() in setOf("main", "deck") }
        if (index >= 0) {
            if (rows[index].quantity == 1) rows.removeAt(index) else rows[index] = rows[index].copy(quantity = rows[index].quantity - 1)
        }
        return draft.copy(rows = rows)
    }

    fun setBasicLands(draft: NativeDeckDraft, quantities: Map<String, Int>): NativeDeckDraft {
        if (quantities.keys != NativeDeckDraft.basicLandNames.toSet()) throw DeckEditingError.InvalidEntry
        var candidate = draft
        for (name in NativeDeckDraft.basicLandNames) {
            val value = quantities.getValue(name)
            if (value < candidate.basicLandCount(name)) candidate = candidate.settingBasicLandCount(name, value)
        }
        for (name in NativeDeckDraft.basicLandNames) candidate = candidate.settingBasicLandCount(name, quantities.getValue(name))
        return candidate
    }
}

/**
 * Interchange for the standard boards plain-text importers support. JSON stays the lossless
 * choice for custom sections or decorated names.
 */
object DeckStudioTextExport {
    class RequiresJSON : Exception("Use JSON export for empty drafts, custom sections or unusual card names.")

    fun text(deck: DeckList): String {
        val entries = listOfNotNull(deck.commander?.let { DeckEntry(it.cardName, it.quantity, "commanders") }) + deck.entries
        if (entries.isEmpty()) throw RequiresJSON()
        val groups = LinkedHashMap<String, MutableList<DeckEntry>>()
        for (entry in entries) {
            val section = when (entry.section.lowercase()) {
                "deck", "main", "mainboard" -> "Deck"
                "commander", "commanders" -> "Commander"
                "companion", "companions" -> "Companion"
                "sideboard" -> "Sideboard"
                "maybeboard", "considering" -> "Maybeboard"
                else -> throw RequiresJSON()
            }
            groups.getOrPut(section) { ArrayList() } += entry
        }
        val text = listOf("Commander", "Deck", "Companion", "Sideboard", "Maybeboard").mapNotNull { section ->
            val rows = groups[section]?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            section + "\n" + rows.joinToString("\n") { "${it.quantity} ${it.cardName}" }
        }.joinToString("\n\n") + "\n"
        // The real importer must preserve every name, quantity and board before sharing.
        val decoded = try { OnDeviceDeckEditing.importText(text, deck.name).deck } catch (error: Exception) { throw RequiresJSON() }
        fun counts(values: List<DeckEntry>): Map<String, Int> =
            values.groupingBy { "${it.section}\u0000${it.cardName}" }.fold(0) { total, row -> total + row.quantity }
        val expected = groups.flatMap { (key, values) ->
            values.map { DeckEntry(it.cardName, it.quantity, when (key) { "Commander" -> "commanders"; "Companion" -> "companions"; else -> key.lowercase() }) }
        }
        val actual = listOfNotNull(decoded.commander?.let { DeckEntry(it.cardName, it.quantity, "commanders") }) + decoded.entries
        if (counts(expected) != counts(actual)) throw RequiresJSON()
        return text
    }
}

/** DeckStudioEditorModel.swift DeckStudioDraftPresentation. */
object DeckStudioDraftPresentation {
    fun normalizedSection(raw: String): String = when (val value = raw.trim().lowercase()) {
        "deck", "main" -> "deck"
        "commander", "commanders" -> "commanders"
        "companion", "companions" -> "companions"
        else -> value
    }
    fun section(row: NativeDeckRow): String = if (row.isPrimaryCommander) "commanders" else normalizedSection(row.section)
    fun commanders(draft: NativeDeckDraft): List<String> = draft.rows.filter { section(it) == "commanders" }.map { it.cardName }
    fun gameCount(draft: NativeDeckDraft): Int = draft.rows.filter { section(it) in setOf("deck", "commanders") }.sumOf { it.quantity }
    fun colors(draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?): List<String>? {
        val commanders = commanders(draft)
        if (commanders.isEmpty()) return null
        val union = HashSet<String>()
        for (name in commanders) union += metadata?.card(name)?.colorIdentity ?: return null
        return listOf("W", "U", "B", "R", "G").filter { it in union }
    }
}
