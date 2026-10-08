package io.magicmobile.android.studio

import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.core.CardPrinting
import io.magicmobile.android.game.CardCountText
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
        return draft.copy(rows = draft.rows.toMutableList().also { it[index] = it[index].copy(cardName = name, printing = null) })
    }

    fun replacePrimaryCommander(draft: NativeDeckDraft, name: String, keepOld: Boolean): NativeDeckDraft {
        val rows = draft.rows.toMutableList()
        val primary = rows.indexOfFirst { it.isPrimaryCommander }.takeIf { it >= 0 }
            ?: rows.indexOfFirst { it.section.trim().lowercase() in setOf("commander", "commanders") }.takeIf { it >= 0 }
        if (primary != null && rows[primary].cardName == name) return draft
        if (primary != null) {
            val old = rows[primary]
            rows[primary] = old.copy(cardName = name, quantity = 1, section = "commanders", isPrimaryCommander = true, printing = null)
            if (keepOld) rows += NativeDeckRow(cardName = old.cardName, quantity = old.quantity, section = "maybeboard", printing = old.printing)
        } else rows.add(0, NativeDeckRow(cardName = name, section = "commanders", isPrimaryCommander = true))
        // Explicit promotion moves one main-deck copy; partners and other boards stay intact.
        val index = rows.indexOfFirst { !it.isPrimaryCommander && it.cardName == name && it.section.trim().lowercase() in setOf("main", "deck") }
        if (index >= 0) {
            // The commander keeps the art the promoted copy had.
            val commander = rows.indexOfFirst { it.isPrimaryCommander && it.cardName == name }
            if (commander >= 0 && rows[commander].printing == null) rows[commander] = rows[commander].copy(printing = rows[index].printing)
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

    /** Adds `quantity` copies to an existing row on the same board, or appends one row. */
    fun addCopies(draft: NativeDeckDraft, name: String, section: String, quantity: Int): NativeDeckDraft {
        if (quantity !in 1..2000 || name.isBlank()) throw DeckEditingError.InvalidEntry
        val board = DeckStudioDraftPresentation.normalizedSection(section)
        val index = draft.rows.indexOfFirst { it.cardName == name && DeckStudioDraftPresentation.section(it) == board }
        if (index < 0) return draft.copy(rows = draft.rows + NativeDeckRow(cardName = name, quantity = quantity, section = section))
        val total = draft.rows[index].quantity.toLong() + quantity
        if (total > Int.MAX_VALUE) throw DeckEditingError.InvalidEntry
        return draft.copy(rows = draft.rows.toMutableList().also { it[index] = it[index].copy(quantity = total.toInt()) })
    }

    /** Commander-first new decks: the chosen card leads the deck, and an untouched default name becomes the commander's name. */
    fun startWithCommander(draft: NativeDeckDraft, name: String): NativeDeckDraft {
        val next = replacePrimaryCommander(draft, name, keepOld = false)
        val current = draft.name.trim()
        return if (current.isEmpty() || current == NativeDeckDraft().name) next.copy(name = name.take(96)) else next
    }

    /** Bulk edits commit as one history step. Every selected row must still exist, so a stale selection changes nothing. */
    private fun requireRows(draft: NativeDeckDraft, ids: Set<UUID>) {
        if (ids.isEmpty() || !draft.rows.map { it.id }.toSet().containsAll(ids)) throw DeckEditingError.MissingEntry
    }

    /** An explicit move clears the primary-commander mark, as a single move does. */
    fun moveRows(draft: NativeDeckDraft, ids: Set<UUID>, section: String): NativeDeckDraft {
        requireRows(draft, ids)
        return draft.copy(rows = draft.rows.map { if (it.id in ids) it.copy(section = section, isPrimaryCommander = false) else it })
    }

    fun setQuantity(draft: NativeDeckDraft, ids: Set<UUID>, quantity: Int): NativeDeckDraft {
        if (quantity !in 1..2000) throw DeckEditingError.InvalidEntry
        requireRows(draft, ids)
        return draft.copy(rows = draft.rows.map { if (it.id in ids) it.copy(quantity = quantity) else it })
    }

    fun removeRows(draft: NativeDeckDraft, ids: Set<UUID>): NativeDeckDraft {
        requireRows(draft, ids)
        return draft.copy(rows = draft.rows.filterNot { it.id in ids })
    }
}

private fun String.trimWhitespace(): String = trim { it.isWhitespace() }

/**
 * Quick Add grammar (DeckStudioQuickAdd in DeckStudioEditorOperations.swift): an optional count
 * ("2 " or "2x "), then the card name. A trailing printing "(set)" / "(set) 123" and "[tag]" are
 * ignored and reported.
 */
data class DeckStudioQuickAdd(val quantity: Int, val name: String, val ignored: List<String>) {
    val note: String? get() = if (ignored.isEmpty()) null else "Ignored ${ignored.joinToString(" ")} · sets and tags aren't saved"

    companion object {
        private val decoration = Regex("""\s*(?:\[[^\[\]]*\]|\([A-Za-z0-9]{2,6}\)(?:\s+[A-Za-z0-9★†-]+)?)$""")
        private val countOnly = Regex("""^[0-9]{1,4}[xX]?$""")
        private val count = Regex("""^[0-9]{1,4}[xX]?\s+""")

        /** Null while there is nothing to add yet or the count is out of range. `isCardName` lets an exact card name that starts with a number win over the count. */
        fun parse(raw: String, isCardName: (String) -> Boolean = { false }): DeckStudioQuickAdd? {
            var text = raw.trimWhitespace()
            if (text.isEmpty() || text.utf8Size > 2000) return null
            val ignored = ArrayList<String>()
            while (true) {
                val match = decoration.find(text) ?: break
                ignored.add(0, match.value.trim { it == ' ' || it == '\t' })
                text = text.substring(0, match.range.first).trim { it == ' ' || it == '\t' }
            }
            if (text.isEmpty()) return null
            if (isCardName(text)) return DeckStudioQuickAdd(1, text, ignored)
            // A count with no name yet ("2x") is still being typed.
            if (countOnly.matches(text)) return null
            var quantity = 1
            count.find(text)?.let { match ->
                val value = match.value.trimWhitespace().trimEnd('x', 'X').toIntOrNull()
                if (value == null || value !in 1..2000) return null
                quantity = value
                text = text.substring(match.range.last + 1).trimWhitespace()
            }
            if (text.isEmpty()) return null
            return DeckStudioQuickAdd(quantity, text, ignored)
        }
    }
}

/**
 * Edit as text (DeckStudioTextDiff in DeckStudioTextExport.swift): the whole deck in the export
 * format, reviewed as cards added and removed per board before it is applied as one undo step.
 */
data class DeckStudioTextDiff(val added: List<Change>, val removed: List<Change>, val art: List<ArtChange> = emptyList()) {
    data class Change(val board: String, val name: String, val before: Int, val after: Int) {
        val delta: Int get() = after - before
        /** e.g. "+2 Sol Ring · Deck", "−1 Island · Maybeboard". */
        val label: String get() = "${if (delta > 0) "+" else "−"}${kotlin.math.abs(delta)} $name · ${title(board)}"
    }
    /** A card whose chosen printing changed, written "(SET) number" in the text. */
    data class ArtChange(val board: String, val name: String, val before: List<String>, val after: List<String>) {
        /** e.g. "Sol Ring · default art → CMM 400". */
        val label: String get() = "$name · ${before.joinToString(", ")} → ${after.joinToString(", ")}"
    }
    val isEmpty: Boolean get() = added.isEmpty() && removed.isEmpty() && art.isEmpty()

    companion object {
        private val order = listOf("commanders", "deck", "companions", "sideboard", "maybeboard")

        fun title(board: String): String = mapOf("commanders" to "Commander", "deck" to "Deck", "companions" to "Companion", "sideboard" to "Sideboard",
            "maybeboard" to "Maybeboard")[board] ?: board.split(" ").joinToString(" ") { word -> word.lowercase().replaceFirstChar { it.uppercase() } }

        fun between(old: NativeDeckDraft, new: NativeDeckDraft): DeckStudioTextDiff {
            fun totals(draft: NativeDeckDraft): Map<Pair<String, String>, Int> {
                val result = LinkedHashMap<Pair<String, String>, Int>()
                for (row in draft.rows) result.merge(DeckStudioDraftPresentation.section(row) to row.cardName, row.quantity, Int::plus)
                return result
            }
            val before = totals(old); val after = totals(new)
            val changes = (before.keys + after.keys).mapNotNull { key ->
                Change(key.first, key.second, before[key] ?: 0, after[key] ?: 0).takeIf { it.delta != 0 }
            }.sortedWith { a, b ->
                val left = order.indexOf(a.board).let { if (it < 0) order.size else it }
                val right = order.indexOf(b.board).let { if (it < 0) order.size else it }
                if (left != right) left.compareTo(right) else if (a.board == b.board) a.name.compareTo(b.name) else a.board.compareTo(b.board)
            }
            // The chosen printings per card and board, one entry per row: default art reads "default art".
            fun artwork(draft: NativeDeckDraft): Map<Pair<String, String>, List<String>> {
                val result = LinkedHashMap<Pair<String, String>, MutableList<String>>()
                for (row in draft.rows) result.getOrPut(DeckStudioDraftPresentation.section(row) to row.cardName) { ArrayList() } += (row.printing?.label ?: "default art")
                return result.mapValues { it.value.sorted() }
            }
            val beforeArt = artwork(old); val afterArt = artwork(new)
            val art = beforeArt.keys.filter { it in afterArt }.mapNotNull { key ->
                val was = beforeArt.getValue(key); val now = afterArt.getValue(key)
                ArtChange(key.first, key.second, was, now).takeIf { was != now }
            }.sortedWith(compareBy({ it.board }, { it.name }))
            return DeckStudioTextDiff(changes.filter { it.delta > 0 }, changes.filter { it.delta < 0 }, art)
        }

        /**
         * Parses edited text with the plain-text importer and returns the new draft and the
         * importer's notes. Rows that stay on the same board keep their identity and section
         * spelling, and the current primary commander stays primary while it remains a commander.
         */
        fun draft(text: String, replacing: NativeDeckDraft): Pair<NativeDeckDraft, List<String>> {
            val draft = replacing
            val name = if (draft.name.trim().isEmpty()) "Draft" else draft.name
            val notes = ArrayList<String>()
            val imported = if (text.isBlank()) DeckList(name, null, emptyList()) else OnDeviceDeckEditing.importText(text, name).also { result ->
                notes += result.annotations.map { "Line ${it.line}: ${it.text}" }
            }.deck
            val unused = draft.rows.toMutableList()
            val rows = NativeDeckDraft.of(imported).rows.map { fresh ->
                val board = DeckStudioDraftPresentation.section(fresh)
                val index = unused.indexOfFirst { DeckStudioDraftPresentation.section(it) == board && it.cardName == fresh.cardName }
                if (index < 0) fresh else {
                    val old = unused.removeAt(index)
                    fresh.copy(id = old.id, section = if (DeckStudioDraftPresentation.normalizedSection(old.section) == board) old.section else fresh.section)
                }
            }.toMutableList()
            val previousPrimary = draft.rows.firstOrNull { it.isPrimaryCommander }?.cardName
            val keep = rows.indexOfFirst { DeckStudioDraftPresentation.section(it) == "commanders" && it.cardName == previousPrimary }
            // Every row on the commander board has a commander section, so moving the flag keeps both commanders.
            if (previousPrimary != null && keep >= 0) for (index in rows.indices) rows[index] = rows[index].copy(isPrimaryCommander = index == keep)
            return draft.copy(rows = rows) to notes
        }
    }
}

/**
 * Group by Role for the Cards list: automatic categories from the role classifier. A card sits under
 * every role it has, and your own role review replaces the automatic hints for that card. Cards with
 * no role are "Other".
 */
object DeckStudioRoleGroups {
    const val other = "Other"
    val order: List<String> = DeckStudioRole.entries.map { it.title } + other

    /** Role group titles for each row, in `order`. */
    fun membership(rows: List<NativeDeckRow>, card: (String) -> CardInfo?, overrides: Map<String, Set<DeckStudioRole>>): Map<UUID, List<String>> {
        val byName = HashMap<String, List<String>>()
        return rows.associate { row ->
            row.id to byName.getOrPut(row.cardName) {
                val info = card(row.cardName)
                val roles = DeckStudioRoleClassifier.classify(info?.oracleText, info?.types, (info?.roles ?: emptyList()).mapNotNull(DeckStudioRole::of),
                    overrides[row.cardName]).map { it.role }
                if (roles.isEmpty()) listOf(other) else DeckStudioRole.entries.filter { it in roles }.map { it.title }
            }
        }
    }

    /** Group headers count unique cards, since one card can appear in several groups. */
    fun uniqueCards(rows: List<NativeDeckRow>): Int = rows.map { it.cardName }.toSet().size
}

/**
 * Goldfish sample hand: draw seven from the main deck, London mulligan (shuffle, draw seven, put one
 * card on the bottom per mulligan taken), then draw a card each turn. Commanders and other boards stay
 * out of the library.
 */
data class DeckStudioSampleHand(
    val library: List<Card>,
    val hand: List<Card> = emptyList(),
    val mulligans: Int = 0,
    /** Cards still to put on the bottom after the latest mulligan. */
    val toBottom: Int = 0,
    val draws: Int = 0,
) {
    data class Card(val id: Int, val name: String)

    val turn: Int get() = draws + 1
    val canMulligan: Boolean get() = draws == 0 && toBottom == 0 && mulligans < handSize && hand.isNotEmpty()
    val canDraw: Boolean get() = toBottom == 0 && library.isNotEmpty()
    /** "Put 1 card on the bottom" after a mulligan, then "Turn 2 · 1 mulligan". */
    val status: String get() = if (toBottom > 0) "Put ${CardCountText.label(toBottom)} on the bottom"
        else "Turn $turn" + if (mulligans == 0) "" else " · $mulligans ${if (mulligans == 1) "mulligan" else "mulligans"}"

    /** A fresh opening hand from the whole deck. */
    fun dealt(random: kotlin.random.Random): DeckStudioSampleHand =
        DeckStudioSampleHand((library + hand).sortedBy { it.id }).drawSeven(random)

    fun mulliganed(random: kotlin.random.Random): DeckStudioSampleHand {
        if (!canMulligan) return this
        val next = copy(library = library + hand, hand = emptyList(), mulligans = mulligans + 1).drawSeven(random)
        return next.copy(toBottom = minOf(next.mulligans, next.hand.size))
    }

    fun puttingOnBottom(id: Int): DeckStudioSampleHand {
        val card = hand.firstOrNull { it.id == id }
        if (toBottom <= 0 || card == null) return this
        return copy(hand = hand - card, library = library + card, toBottom = toBottom - 1)
    }

    fun drawn(): DeckStudioSampleHand = if (!canDraw) this else copy(hand = hand + library.first(), library = library.drop(1), draws = draws + 1)

    private fun drawSeven(random: kotlin.random.Random): DeckStudioSampleHand {
        val shuffled = library.shuffled(random)
        val count = minOf(handSize, shuffled.size)
        return copy(hand = shuffled.take(count), library = shuffled.drop(count))
    }

    companion object {
        const val handSize = 7

        /** Main-deck cards, one entry per copy. */
        fun libraryNames(draft: NativeDeckDraft): List<String> =
            draft.rows.filter { DeckStudioDraftPresentation.section(it) == "deck" }.flatMap { row -> List(maxOf(0, minOf(row.quantity, 2000))) { row.cardName } }

        fun of(names: List<String>): DeckStudioSampleHand = DeckStudioSampleHand(names.mapIndexed { index, name -> Card(index, name) })
    }
}

/**
 * Local search syntax, a small Scryfall-style subset (DeckStudioSearchSyntax in
 * DeckStudioCatalogueSearch.swift): `t:creature`, `o:draw`, `mv<=3`, `mv>=2`, `mv=3`, `id:wu`
 * (identity within W and U; `id:c` is colorless). Values may be quoted: `t:"legendary creature"`.
 * Every term must match. Anything else, including an incomplete term, stays as name or rules text.
 */
data class DeckStudioSearchSyntax(
    val text: String = "",
    val types: List<String> = emptyList(),
    val oracle: List<String> = emptyList(),
    val minimumManaValue: Double? = null,
    val maximumManaValue: Double? = null,
    val identity: Set<String>? = null,
    val setCode: String = "",
) {
    val hasFilters: Boolean get() = types.isNotEmpty() || oracle.isNotEmpty() || minimumManaValue != null || maximumManaValue != null || identity != null

    companion object {
        private val colors = setOf("W", "U", "B", "R", "G")
        private val decimal = Regex("""^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$""")

        fun parse(query: String): DeckStudioSearchSyntax {
            val text = ArrayList<String>()
            var result = DeckStudioSearchSyntax()
            for (token in tokens(query)) {
                val lower = token.lowercase()
                fun value(prefix: String): String? {
                    if (!lower.startsWith(prefix)) return null
                    return token.substring(prefix.length).trim { it == '"' || it == ' ' || it == '\t' }.ifEmpty { null }
                }
                fun bound(prefix: String): Double? = value(prefix)?.takeIf(decimal::matches)?.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }
                // A term still being typed filters nothing yet.
                if (listOf("t:", "o:", "id:", "mv<=", "mv>=", "mv=").any { lower.startsWith(it) && value(it) == null }) continue
                val type = value("t:"); val rules = value("o:"); val identity = value("id:")?.uppercase()?.map { it.toString() }?.toSet()
                val atMost = bound("mv<="); val atLeast = bound("mv>="); val exactly = bound("mv=")
                result = when {
                    type != null -> result.copy(types = result.types + type)
                    rules != null -> result.copy(oracle = result.oracle + rules)
                    identity != null && (colors + "C").containsAll(identity) && !("C" in identity && identity.size > 1) ->
                        result.copy(identity = (result.identity ?: colors).intersect(identity - "C"))
                    atMost != null -> result.copy(maximumManaValue = minOf(result.maximumManaValue ?: atMost, atMost))
                    atLeast != null -> result.copy(minimumManaValue = maxOf(result.minimumManaValue ?: atLeast, atLeast))
                    exactly != null -> result.copy(minimumManaValue = maxOf(result.minimumManaValue ?: exactly, exactly),
                        maximumManaValue = minOf(result.maximumManaValue ?: exactly, exactly))
                    else -> { text += token; result }
                }
            }
            return result.copy(text = text.joinToString(" "))
        }

        /** Whitespace-separated tokens; double quotes keep spaces inside a token. */
        private fun tokens(query: String): List<String> {
            val tokens = ArrayList<String>()
            val current = StringBuilder()
            var quoted = false
            for (character in query) {
                if (character == '"') { quoted = !quoted; current.append(character) }
                else if (character.isWhitespace() && !quoted) { if (current.isNotEmpty()) { tokens += current.toString(); current.clear() } }
                else current.append(character)
            }
            if (current.isNotEmpty()) tokens += current.toString()
            return tokens
        }
    }
}

/**
 * The builder's local searches over the bundled catalogue (DeckStudioCatalogueSearch.swift): Add
 * cards with the search syntax, Quick Add name suggestions and the commander-first picker.
 */
object DeckStudioBuilderSearch {
    /**
     * Add cards: search syntax filters apply before the cap together with the sheet's own filters.
     * Without filter terms this is DeckStudioCatalogueSearch's plain name or rules-text search (minus
     * any half-typed term).
     */
    fun cards(catalogue: NativeDeckMetadataCatalogue, query: String, type: String = "", allowedIdentity: List<String>? = null, setCode: String = "",
              minimumManaValue: Double? = null, maximumManaValue: Double? = null, limit: Int = 80): List<CardInfo> {
        if (limit <= 0 || minimumManaValue?.let { !it.isFinite() || it < 0 } == true || maximumManaValue?.let { !it.isFinite() || it < 0 } == true ||
            (minimumManaValue != null && maximumManaValue != null && minimumManaValue > maximumManaValue)) return emptyList()
        val syntax = DeckStudioSearchSyntax.parse(query)
        if (!syntax.hasFilters) return DeckStudioCatalogueSearch.cards(catalogue, syntax.text, type, allowedIdentity, setCode, minimumManaValue, maximumManaValue, limit)
        if (allowedIdentity?.let { setOf("W", "U", "B", "R", "G").containsAll(it) } == false) return emptyList()
        val combined = syntax.copy(types = syntax.types + listOf(type).filter { it.isNotEmpty() }, setCode = setCode,
            minimumManaValue = listOfNotNull(syntax.minimumManaValue, minimumManaValue).maxOrNull(),
            maximumManaValue = listOfNotNull(syntax.maximumManaValue, maximumManaValue).minOrNull(),
            identity = allowedIdentity?.let { allowed -> (syntax.identity ?: setOf("W", "U", "B", "R", "G")).intersect(allowed.toSet()) } ?: syntax.identity)
        return scan(catalogue, combined, nameOnly = false, limit = minOf(limit, 2000))
    }

    /** Quick Add autocomplete: names only, exact and prefix matches first. */
    fun nameSuggestions(catalogue: NativeDeckMetadataCatalogue, query: String, limit: Int = 5): List<CardInfo> {
        val text = query.trimWhitespace()
        if (text.isEmpty() || limit <= 0) return emptyList()
        return scan(catalogue, DeckStudioSearchSyntax(text = text), nameOnly = true, limit = minOf(limit, 2000))
    }

    /** Legendary creatures and cards whose text says they can be your commander. Partner and background pairings are left to XMage. */
    fun isCommanderCandidate(card: CardInfo): Boolean =
        (card.types?.contains("CREATURE") == true && card.typeLine?.contains("Legendary", ignoreCase = true) == true) ||
            card.oracleText?.contains("can be your commander", ignoreCase = true) == true

    /** Commander-first picker. Plain words match the name; the search syntax also applies. */
    fun commanders(catalogue: NativeDeckMetadataCatalogue, query: String, limit: Int = 80): List<CardInfo> {
        if (limit <= 0) return emptyList()
        return scan(catalogue, DeckStudioSearchSyntax.parse(query), nameOnly = true, limit = minOf(limit, 2000), extra = ::isCommanderCandidate)
    }

    private fun fold(text: String): String = if (text.all { it.code < 128 }) text.lowercase(java.util.Locale.ROOT) else DeckStudioLibraryQuery.key(text)

    private fun scan(catalogue: NativeDeckMetadataCatalogue, syntax: DeckStudioSearchSyntax, nameOnly: Boolean, limit: Int,
                     extra: (CardInfo) -> Boolean = { true }): List<CardInfo> {
        // Case- and diacritic-insensitive, as on iOS; the folded card text is only built when a plain match fails.
        fun matcher(query: String): (String?) -> Boolean {
            val folded = fold(query)
            return { text -> text != null && (text.contains(query, ignoreCase = true) || fold(text).contains(folded)) }
        }
        val name = matcher(syntax.text)
        val types = syntax.types.map(::matcher)
        val oracle = syntax.oracle.map(::matcher)
        val matches = catalogue.cards.filter { card ->
            (syntax.text.isEmpty() || name(card.name) || (!nameOnly && name(card.oracleText))) &&
                types.all { it(card.typeLine) } && oracle.all { it(card.oracleText) } &&
                (syntax.setCode.isEmpty() || card.setCodes.any { it.equals(syntax.setCode, ignoreCase = true) }) &&
                (syntax.identity == null || card.colorIdentity?.let { syntax.identity.containsAll(it) } == true) &&
                (syntax.minimumManaValue == null || card.manaValue?.let { it >= syntax.minimumManaValue } == true) &&
                (syntax.maximumManaValue == null || card.manaValue?.let { it <= syntax.maximumManaValue } == true) &&
                extra(card)
        }
        return NativeDeckMetadataCatalogue.ranked(matches, syntax.text).take(limit)
    }
}

/**
 * Interchange for the standard boards plain-text importers support. JSON stays the lossless
 * choice for custom sections or decorated names.
 */
object DeckStudioTextExport {
    class RequiresJSON : Exception("Use JSON export for empty drafts, custom sections or unusual card names.")

    /** One line per row, "2 Sol Ring" or, with chosen art, "2 Sol Ring (CMM) 400" as Moxfield and Archidekt write it. */
    fun line(entry: DeckEntry): String = "${entry.quantity} ${entry.cardName}" + (entry.printing?.let { " " + it.exportSuffix } ?: "")

    fun text(deck: DeckList): String {
        val entries = listOfNotNull(deck.commander?.let { DeckEntry(it.cardName, it.quantity, "commanders", it.printing) }) + deck.entries
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
            section + "\n" + rows.joinToString("\n") { line(it) }
        }.joinToString("\n\n") + "\n"
        // The real importer must preserve every name, quantity, board and chosen printing before sharing.
        val decoded = try { OnDeviceDeckEditing.importText(text, deck.name).deck } catch (error: Exception) { throw RequiresJSON() }
        fun counts(values: List<DeckEntry>): Map<String, Int> =
            values.groupingBy { "${it.section}\u0000${it.cardName}\u0000${it.printing?.key ?: ""}" }.fold(0) { total, row -> total + row.quantity }
        val expected = groups.flatMap { (key, values) ->
            values.map { DeckEntry(it.cardName, it.quantity, when (key) { "Commander" -> "commanders"; "Companion" -> "companions"; else -> key.lowercase() }, it.printing) }
        }
        val actual = listOfNotNull(decoded.commander?.let { DeckEntry(it.cardName, it.quantity, "commanders", it.printing) }) + decoded.entries
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
        // "Considering" is a maybeboard on both phones.
        "maybeboard", "considering" -> "maybeboard"
        else -> value
    }
    fun section(row: NativeDeckRow): String = if (row.isPrimaryCommander) "commanders" else normalizedSection(row.section)
    fun commanders(draft: NativeDeckDraft): List<String> = draft.rows.filter { section(it) == "commanders" }.map { it.cardName }
    /** The art chosen for the first commander, which the deck's cover draws. */
    fun commanderPrinting(draft: NativeDeckDraft): CardPrinting? = draft.rows.firstOrNull { section(it) == "commanders" }?.printing
    fun gameCount(draft: NativeDeckDraft): Int = draft.rows.filter { section(it) in setOf("deck", "commanders") }.sumOf { it.quantity }
    fun colors(draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?): List<String>? {
        val commanders = commanders(draft)
        if (commanders.isEmpty()) return null
        val union = HashSet<String>()
        for (name in commanders) union += metadata?.card(name)?.colorIdentity ?: return null
        return listOf("W", "U", "B", "R", "G").filter { it in union }
    }
}
