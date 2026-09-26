package io.magicmobile.android.studio

import io.magicmobile.android.core.CardInfo
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

    /** Quick Add: merge copies into the same board's row, or append one new row. */
    fun addCopies(draft: NativeDeckDraft, name: String, section: String, quantity: Int): NativeDeckDraft {
        if (quantity !in 1..2000) throw DeckEditingError.InvalidEntry
        val effective = DeckStudioDraftPresentation.normalizedSection(section)
        val index = draft.rows.indexOfFirst { it.cardName == name && DeckStudioDraftPresentation.section(it) == effective }
        if (index < 0) return draft.copy(rows = draft.rows + NativeDeckRow(cardName = name, quantity = quantity, section = section))
        val total = draft.rows[index].quantity.toLong() + quantity
        if (total > 2000) throw DeckEditingError.InvalidEntry
        return draft.copy(rows = draft.rows.toMutableList().also { it[index] = it[index].copy(quantity = total.toInt()) })
    }

    /** A new deck starts from its commander and, while still unnamed, takes the commander's name. */
    fun startWithCommander(draft: NativeDeckDraft, name: String): NativeDeckDraft {
        val next = replacePrimaryCommander(draft, name, keepOld = false)
        val unnamed = draft.name.isBlank() || draft.name == NativeDeckDraft().name
        return if (unnamed && name.isNotBlank() && name.utf8Size <= 512) next.copy(name = name) else next
    }

    private fun selected(draft: NativeDeckDraft, ids: Set<UUID>): Set<UUID> {
        if (ids.isEmpty() || !ids.all { id -> draft.rows.any { it.id == id } }) throw DeckEditingError.MissingEntry
        return ids
    }

    /** Bulk Move to…: one undo step; an explicit move clears the primary-commander mark, as a single move does. */
    fun moveRows(draft: NativeDeckDraft, ids: Set<UUID>, section: String): NativeDeckDraft {
        val chosen = selected(draft, ids)
        return draft.copy(rows = draft.rows.map { if (it.id in chosen) it.copy(section = section, isPrimaryCommander = false) else it })
    }

    /** Bulk Set quantity: every selected row gets exactly `quantity` copies. */
    fun setQuantity(draft: NativeDeckDraft, ids: Set<UUID>, quantity: Int): NativeDeckDraft {
        if (quantity !in 1..2000) throw DeckEditingError.InvalidEntry
        val chosen = selected(draft, ids)
        return draft.copy(rows = draft.rows.map { if (it.id in chosen) it.copy(quantity = quantity) else it })
    }

    fun removeRows(draft: NativeDeckDraft, ids: Set<UUID>): NativeDeckDraft {
        val chosen = selected(draft, ids)
        return draft.copy(rows = draft.rows.filterNot { it.id in chosen })
    }
}

/**
 * The Quick Add grammar, shared with iOS: "Sol Ring", "2 Sol Ring" or "2x Sol Ring". A trailing
 * "(set)" printing (with an optional collector number) and "[tag]" category are ignored and reported,
 * because a row stores neither.
 */
object DeckStudioQuickAdd {
    data class Entry(val quantity: Int, val name: String, val ignored: List<String>) {
        val note: String? get() = if (ignored.isEmpty()) null else "Ignored ${ignored.joinToString(" ")} · printings and tags aren't saved"
    }
    class Invalid(message: String) : Exception(message)

    private val counted = Regex("""^([0-9]{1,5})[xX]?\s+(.+)$""")
    private val tag = Regex("""\s*\[[^\[\]\r\n]*\]$""")
    private val printing = Regex("""\s*\([A-Za-z0-9]+\)(?:\s+[A-Za-z0-9★†-]+)?$""")

    /** Null for blank input. */
    fun parse(text: String): Entry? {
        var line = text.trimSpaces().replace(Regex("\\s+"), " ")
        if (line.isEmpty()) return null
        var quantity = 1
        counted.matchEntire(line)?.let { match ->
            quantity = match.groupValues[1].toIntOrNull()?.takeIf { it in 1..2000 } ?: throw Invalid("Use a quantity from 1 to 2,000.")
            line = match.groupValues[2]
        }
        val ignored = ArrayList<String>()
        while (line.isNotEmpty()) {
            val match = tag.find(line) ?: printing.find(line) ?: break
            ignored.add(0, match.value.trim())
            line = line.removeRange(match.range).trimSpaces()
        }
        if (line.isEmpty() || line.utf8Size > 2000) throw Invalid("Type a card name, like 2 Sol Ring.")
        return Entry(quantity, line, ignored)
    }

    /** The top local autocomplete results for the name part: exact, then prefix, then contains. */
    fun suggestions(catalogue: NativeDeckMetadataCatalogue, text: String, limit: Int = 5): List<CardInfo> {
        val name = runCatching { parse(text) }.getOrNull()?.name ?: return emptyList()
        val matches = catalogue.cards.filter { it.name.contains(name, ignoreCase = true) }
        return NativeDeckMetadataCatalogue.ranked(matches, name).take(limit)
    }

    /** Submitting adds the exact card (case-insensitive) or else the top suggestion. */
    fun resolve(catalogue: NativeDeckMetadataCatalogue, entry: Entry): String? =
        catalogue.card(entry.name)?.name ?: suggestions(catalogue, entry.name, 1).firstOrNull()?.name
}

/**
 * Edit as text: the whole deck in the plain-text export format, reviewed as cards added and
 * removed, then applied as one undo step. Unchanged rows keep their IDs, order and exact section.
 */
object DeckStudioTextEdit {
    data class Change(val name: String, val board: String, val quantity: Int)
    data class Review(val added: List<Change>, val removed: List<Change>, val result: NativeDeckDraft, val ignoredLines: Int) {
        val isEmpty: Boolean get() = added.isEmpty() && removed.isEmpty()
    }

    /** The board a row plays in, with "considering" as maybeboard; null for a custom section. */
    fun board(section: String): String? = when (section.trim().lowercase()) {
        "deck", "main", "mainboard" -> "deck"
        "commander", "commanders" -> "commanders"
        "companion", "companions" -> "companions"
        "sideboard" -> "sideboard"
        "maybeboard", "considering" -> "maybeboard"
        else -> null
    }

    fun boardTitle(board: String): String = when (board) {
        "deck" -> "Deck"; "commanders" -> "Commander"; "companions" -> "Companion"; "sideboard" -> "Sideboard"; "maybeboard" -> "Maybeboard"
        else -> board
    }

    private fun board(row: NativeDeckRow): String = if (row.isPrimaryCommander) "commanders" else board(row.section) ?: throw DeckStudioTextExport.RequiresJSON()

    /** The editable text; an empty draft starts blank. Custom sections need JSON instead. */
    fun text(draft: NativeDeckDraft): String = if (draft.rows.isEmpty()) "" else DeckStudioTextExport.text(draft.deck())

    fun review(draft: NativeDeckDraft, text: String): Review {
        draft.rows.forEach { board(it) }
        val imported = if (text.isBlank()) null else OnDeviceDeckEditing.importText(text, draft.name.takeIf { it.isNotBlank() && it.utf8Size <= 512 } ?: "Draft")
        val wanted = LinkedHashMap<Pair<String, String>, Int>()
        imported?.deck?.let { deck ->
            for (entry in listOfNotNull(deck.commander) + deck.entries) {
                wanted.merge((board(entry.section) ?: throw DeckStudioTextExport.RequiresJSON()) to entry.cardName, entry.quantity, Int::plus)
            }
        }
        val existing = LinkedHashMap<Pair<String, String>, Int>()
        for (row in draft.rows) existing.merge(board(row) to row.cardName, row.quantity, Int::plus)
        val removed = existing.mapNotNull { (key, old) -> (old - (wanted[key] ?: 0)).takeIf { it > 0 }?.let { Change(key.second, key.first, it) } }
        val added = wanted.mapNotNull { (key, new) -> (new - (existing[key] ?: 0)).takeIf { it > 0 }?.let { Change(key.second, key.first, it) } }
        val kept = HashSet<Pair<String, String>>()
        val rows = ArrayList<NativeDeckRow>()
        for (row in draft.rows) {
            val key = board(row) to row.cardName
            val quantity = wanted[key] ?: 0
            when {
                quantity == 0 -> {}
                quantity == existing[key] -> rows += row
                key !in kept -> { rows += row.copy(quantity = quantity); kept += key }
            }
        }
        for ((key, quantity) in wanted) if (key !in existing) rows += NativeDeckRow(cardName = key.second, quantity = quantity, section = key.first)
        val result = draft.copy(rows = rows)
        result.copy(name = "Draft").deck()
        return Review(added, removed, result, imported?.annotations?.map { it.line }?.toSet()?.size ?: 0)
    }
}

/**
 * Group by Role: automatic categories from the role classifier. A main-deck card sits under every
 * role it has, as in Archidekt, and under "Other" when it has none; your reviewed roles win.
 */
object DeckStudioRoleGroups {
    const val other = "Other"
    val order: List<String> = DeckStudioRole.entries.map { it.title } + other

    fun roles(card: CardInfo?, reviewed: Set<DeckStudioRole>?): List<String> {
        val evidence = DeckStudioRoleClassifier.classify(card?.oracleText, card?.types, (card?.roles ?: emptyList()).mapNotNull(DeckStudioRole::of), reviewed)
        return evidence.map { it.role.title }.ifEmpty { listOf(other) }
    }

    /** Role title to its main-deck rows, in role order with "Other" last; empty groups are left out. */
    fun groups(rows: List<NativeDeckRow>, card: (String) -> CardInfo?,
               overrides: Map<String, Set<DeckStudioRole>>): LinkedHashMap<String, List<NativeDeckRow>> {
        val grouped = HashMap<String, MutableList<NativeDeckRow>>()
        for (row in rows) {
            if (DeckStudioDraftPresentation.section(row) != "deck") continue
            for (role in roles(card(row.cardName), overrides[row.cardName])) grouped.getOrPut(role) { ArrayList() } += row
        }
        return order.filter { it in grouped }.associateWithTo(LinkedHashMap()) { grouped.getValue(it) }
    }

    /** Headers count unique cards, since one card can appear in several groups. */
    fun uniqueCards(rows: List<NativeDeckRow>): Int = rows.map { it.cardName }.toSet().size
}

/**
 * The Playtest tab's sample hand: draw 7, London mulligan (shuffle back, draw 7, then put one card
 * on the bottom per mulligan), draw the next card and count turns. Only main-deck cards are in the
 * library; commanders, companions, sideboard and maybeboard stay out.
 */
data class DeckStudioSampleHand(
    val library: List<Card>,
    val hand: List<Card>,
    val mulligans: Int = 0,
    val bottomed: Int = 0,
    val drawn: Int = 0,
    val turn: Int = 1,
) {
    data class Card(val id: Int, val name: String)

    /** Cards still to put on the bottom before the hand is kept. */
    val toBottom: Int get() = maxOf(0, minOf(mulligans, hand.size + bottomed) - bottomed)
    val canMulligan: Boolean get() = drawn == 0 && bottomed == 0 && mulligans < 7 && size > 0
    val canDraw: Boolean get() = toBottom == 0 && library.isNotEmpty()
    val size: Int get() = library.size + hand.size

    fun mulligan(random: kotlin.random.Random): DeckStudioSampleHand {
        if (!canMulligan) return this
        return deal(library + hand, random).copy(mulligans = mulligans + 1)
    }

    fun putOnBottom(id: Int): DeckStudioSampleHand {
        if (toBottom == 0) return this
        val card = hand.firstOrNull { it.id == id } ?: return this
        return copy(hand = hand - card, library = library + card, bottomed = bottomed + 1)
    }

    fun draw(): DeckStudioSampleHand {
        if (!canDraw) return this
        return copy(hand = hand + library.first(), library = library.drop(1), drawn = drawn + 1)
    }

    /** The next turn's draw step. */
    fun nextTurn(): DeckStudioSampleHand = if (!canDraw) this else draw().copy(turn = turn + 1)

    companion object {
        const val handSize = 7

        /** Main-deck cards, one entry per copy, in row order. */
        fun library(draft: NativeDeckDraft): List<String> =
            draft.rows.filter { DeckStudioDraftPresentation.section(it) == "deck" }.flatMap { row -> List(row.quantity.coerceIn(0, 2000)) { row.cardName } }.take(2000)

        fun start(names: List<String>, random: kotlin.random.Random): DeckStudioSampleHand =
            deal(names.mapIndexed { index, name -> Card(index, name) }, random)

        private fun deal(cards: List<Card>, random: kotlin.random.Random): DeckStudioSampleHand {
            val shuffled = cards.shuffled(random)
            return DeckStudioSampleHand(shuffled.drop(handSize), shuffled.take(handSize))
        }
    }
}

/**
 * Local search syntax, shared with iOS: `t:` type line, `o:` rules text, `mv<=`/`mv>=` mana value
 * and `id:` colour identity (the card fits within the colours, `id:c` for colourless). Values may be
 * quoted, as in o:"draw a card". Everything else searches names and rules text as before.
 */
object DeckStudioSearchSyntax {
    data class Query(
        val text: String = "",
        val types: List<String> = emptyList(),
        val oracle: List<String> = emptyList(),
        val minimumManaValue: Double? = null,
        val maximumManaValue: Double? = null,
        val identity: Set<String>? = null,
    ) {
        val hasSyntax: Boolean get() = types.isNotEmpty() || oracle.isNotEmpty() || minimumManaValue != null || maximumManaValue != null || identity != null
    }
    class Invalid : Exception("Use t:type, o:text, mv<=3, mv>=2 or id:wubrg (id:c for colorless).")

    private fun tokens(input: String): List<String> {
        val result = ArrayList<String>()
        var index = 0
        while (index < input.length) {
            if (input[index].isWhitespace()) { index++; continue }
            val token = StringBuilder()
            var quoted = false
            while (index < input.length && (quoted || !input[index].isWhitespace())) {
                if (input[index] == '"') quoted = !quoted else token.append(input[index])
                index++
            }
            result += token.toString()
        }
        return result
    }

    fun parse(input: String): Query {
        val words = ArrayList<String>()
        var query = Query()
        for (token in tokens(input)) {
            val lower = token.lowercase()
            fun value(prefix: String) = token.substring(prefix.length).trim().ifEmpty { throw Invalid() }
            fun number(prefix: String) = value(prefix).toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 } ?: throw Invalid()
            query = when {
                lower.startsWith("t:") -> query.copy(types = query.types + value("t:"))
                lower.startsWith("o:") -> query.copy(oracle = query.oracle + value("o:"))
                lower.startsWith("mv<=") -> number("mv<=").let { query.copy(maximumManaValue = minOf(query.maximumManaValue ?: it, it)) }
                lower.startsWith("mv>=") -> number("mv>=").let { query.copy(minimumManaValue = maxOf(query.minimumManaValue ?: it, it)) }
                lower.startsWith("id:") -> {
                    val letters = value("id:").lowercase()
                    val colors = if (letters == "c") emptySet() else letters.map { letter ->
                        "wubrg".indexOf(letter).takeIf { it >= 0 }?.let { "WUBRG"[it].toString() } ?: throw Invalid()
                    }.toSet()
                    query.copy(identity = query.identity?.intersect(colors) ?: colors)
                }
                else -> { words += token; query }
            }
        }
        return query.copy(text = words.joinToString(" "))
    }

    fun matches(card: CardInfo, query: Query): Boolean {
        fun contains(text: String?, value: String) = text?.contains(value, ignoreCase = true) == true
        return (query.text.isEmpty() || contains(card.name, query.text) || contains(card.oracleText, query.text)) &&
            query.types.all { contains(card.typeLine, it) } && query.oracle.all { contains(card.oracleText, it) } &&
            (query.minimumManaValue == null || card.manaValue?.let { it >= query.minimumManaValue } == true) &&
            (query.maximumManaValue == null || card.manaValue?.let { it <= query.maximumManaValue } == true) &&
            (query.identity == null || card.colorIdentity?.let { query.identity.containsAll(it) } == true)
    }

    /**
     * The Add cards search. Plain queries keep DeckStudioCatalogueSearch's behaviour exactly; syntax
     * filters apply before the cap, together with the sheet's own filters.
     */
    fun cards(catalogue: NativeDeckMetadataCatalogue, input: String, type: String = "", allowedIdentity: List<String>? = null, setCode: String = "",
              minimumManaValue: Double? = null, maximumManaValue: Double? = null, limit: Int = 80): List<CardInfo> {
        val parsed = parse(input)
        if (!parsed.hasSyntax) return DeckStudioCatalogueSearch.cards(catalogue, input, type, allowedIdentity, setCode, minimumManaValue, maximumManaValue, limit)
        if (limit <= 0) return emptyList()
        val query = parsed.copy(
            types = parsed.types + listOf(type).filter { it.isNotEmpty() },
            minimumManaValue = listOfNotNull(parsed.minimumManaValue, minimumManaValue).maxOrNull(),
            maximumManaValue = listOfNotNull(parsed.maximumManaValue, maximumManaValue).minOrNull(),
            identity = allowedIdentity?.toSet()?.let { allowed -> parsed.identity?.intersect(allowed) ?: allowed } ?: parsed.identity)
        val matches = catalogue.cards.filter { card ->
            matches(card, query) && (setCode.isEmpty() || card.setCodes.any { it.equals(setCode, ignoreCase = true) })
        }
        return NativeDeckMetadataCatalogue.ranked(matches, query.text).take(minOf(limit, 2000))
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
        // "Considering" is a maybeboard on both phones.
        "maybeboard", "considering" -> "maybeboard"
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
