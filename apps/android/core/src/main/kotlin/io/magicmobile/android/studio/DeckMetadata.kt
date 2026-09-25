package io.magicmobile.android.studio

import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.core.Catalogue
import io.magicmobile.android.core.PrintingIndex
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Resolves only reverse faces attested by the bundled, selected-printing aliases. */
object NativeDeckCanonicalNames {
    fun reverseFaces(aliases: Map<String, String>, exactNames: Set<String>): Map<String, String> {
        val candidates = HashMap<String, MutableSet<String>>()
        for ((combined, front) in aliases) {
            if (!combined.startsWith("$front // ")) continue
            val back = combined.substring(front.length + 4)
            if (back.isEmpty() || back in exactNames) continue
            candidates.getOrPut(back) { HashSet() } += front
        }
        return candidates.filterValues { it.size == 1 }.mapValues { it.value.first() }
    }
}

// NativeDeckMetadataCatalogue.Card field names over the Android catalogue's CardInfo.
val CardInfo.typeLine: String? get() = type
val CardInfo.oracleText: String? get() = rules
val CardInfo.manaCost: String? get() = cost
/** Null means unavailable; an empty list means known colorless identity. */
val CardInfo.colorIdentity: List<String>? get() = identity

/** Selected-printing metadata, not live Oracle updates, Commander legality or mana production. */
class NativeDeckMetadataCatalogue(private val catalogue: Catalogue) {
    data class SearchFilter(
        val query: String = "",
        val type: String = "",
        val setCode: String = "",
        val colors: Set<String>? = null,
        val colorIdentity: Set<String>? = null,
        val minimumManaValue: Double? = null,
        val maximumManaValue: Double? = null,
    )

    class Statistics {
        var cardCount = 0
        var excludedCardCount = 0
        var landCount = 0
        var unknownTypeCount = 0
        var unknownManaValueCount = 0
        var unknownManaCostCount = 0
        var unknownNames: List<String> = emptyList()
        /** Quantity-weighted nonland printed mana values; unknown types and values are excluded. */
        val manaCurve = HashMap<Double, Int>()
        /** Printed symbols, hybrids counted once as their own symbol; no color-source estimates. */
        val manaSymbolCounts = HashMap<String, Int>()
        val averageManaValue: Double? get() {
            val count = manaCurve.values.sum()
            return if (count == 0) null else manaCurve.entries.sumOf { it.key * it.value } / count
        }
    }

    class CatalogueError(message: String) : Exception(message)

    private val aliases: Map<String, String>
    private val reverseFaces: Map<String, String>
    val cards: List<CardInfo> get() = catalogue.cards

    init {
        val names = catalogue.cards.mapTo(HashSet()) { it.name }
        aliases = catalogue.nameAliases.filterKeys { it !in names }
        reverseFaces = NativeDeckCanonicalNames.reverseFaces(aliases, names)
    }

    fun card(name: String): CardInfo? = catalogue.find(name) ?: aliases[name]?.let(catalogue::find) ?: reverseFaces[name]?.let(catalogue::find)

    /** All names this installed engine catalogue supports, without the search limit. */
    val artworkCardNames: List<String> get() = catalogue.cards.map { it.name }

    fun search(filter: SearchFilter = SearchFilter(), limit: Int = 40): List<CardInfo> {
        if (limit <= 0) return emptyList()
        val query = filter.query.trim()
        fun contains(text: String?, query: String) = text?.contains(query, ignoreCase = true) == true
        val matches = catalogue.cards.asSequence().filter { card ->
            (query.isEmpty() || contains(card.name, query) || contains(card.oracleText, query)) &&
                (filter.type.isEmpty() || contains(card.typeLine, filter.type)) &&
                (filter.setCode.isEmpty() || card.setCodes.any { it.equals(filter.setCode, ignoreCase = true) }) &&
                (filter.colors == null || card.colors?.toSet() == filter.colors) &&
                (filter.colorIdentity == null || card.colorIdentity?.toSet() == filter.colorIdentity) &&
                (filter.minimumManaValue == null || card.manaValue?.let { it >= filter.minimumManaValue } == true) &&
                (filter.maximumManaValue == null || card.manaValue?.let { it <= filter.maximumManaValue } == true)
        }
        val cap = minOf(limit, 2000)
        if (query.isEmpty()) return matches.take(cap).toList()
        return ranked(matches.toList(), query).take(cap)
    }

    fun statistics(deck: DeckList, sections: Set<String> = setOf("main", "deck")): Statistics {
        val stats = Statistics()
        var total = 0
        val unknown = sortedSetOf<String>()
        val selected = sections.map { it.lowercase() }.toSet()
        val rows = listOfNotNull(deck.commander?.let { DeckEntry(it.cardName, it.quantity, "commanders") }) + deck.entries
        for (row in rows) {
            if (row.quantity !in 1..2000 || row.quantity > 2000 - total) throw CatalogueError("Statistics require at most 2,000 cards with positive quantities.")
            total += row.quantity
            if (row.section.trim().lowercase() !in selected) { stats.excludedCardCount += row.quantity; continue }
            stats.cardCount += row.quantity
            val card = card(row.cardName)
            if (card == null) {
                unknown += row.cardName
                stats.unknownTypeCount += row.quantity; stats.unknownManaValueCount += row.quantity; stats.unknownManaCostCount += row.quantity
                continue
            }
            val types = card.types
            if (types != null) {
                if ("LAND" in types) stats.landCount += row.quantity
                else if (card.manaValue != null) stats.manaCurve.merge(card.manaValue, row.quantity, Int::plus)
                else stats.unknownManaValueCount += row.quantity
            } else {
                stats.unknownTypeCount += row.quantity
                if (card.manaValue == null) stats.unknownManaValueCount += row.quantity
            }
            val cost = card.manaCost
            if (cost != null) {
                for (fragment in cost.split("{").drop(1)) {
                    val end = fragment.indexOf('}')
                    if (end < 0) continue
                    val symbol = fragment.substring(0, end)
                    if (symbol != "*" && symbol.isNotEmpty()) stats.manaSymbolCounts.merge(symbol, row.quantity, Int::plus)
                }
            } else stats.unknownManaCostCount += row.quantity
        }
        stats.unknownNames = unknown.toList()
        return stats
    }

    /**
     * Preview only. Distributes additional basics by printed mono-color pips; never infers
     * commander identity, hybrid choices or mana production.
     */
    fun basicLandSuggestion(deck: DeckList, target: Int = 37): List<Pair<String, Int>> {
        val stats = statistics(deck)
        if (stats.unknownTypeCount != 0 || stats.unknownManaCostCount != 0) return emptyList()
        val needed = maxOf(0, minOf(100, target) - stats.landCount)
        val pairs = listOf("W" to "Plains", "U" to "Island", "B" to "Swamp", "R" to "Mountain", "G" to "Forest")
        val weights = pairs.map { stats.manaSymbolCounts[it.first] ?: 0 }
        val total = weights.sum()
        if (needed <= 0 || total <= 0) return emptyList()
        val counts = weights.map { needed * it / total }.toMutableList()
        val priority = weights.indices.sortedWith { a, b ->
            val left = needed * weights[a] % total; val right = needed * weights[b] % total
            if (left == right) a.compareTo(b) else right.compareTo(left)
        }
        priority.take(needed - counts.sum()).forEach { counts[it] += 1 }
        if (!pairs.indices.all { counts[it] == 0 || card(pairs[it].second) != null }) return emptyList()
        return pairs.indices.filter { counts[it] > 0 }.map { pairs[it].second to counts[it] }
    }

    companion object {
        /** The same ordering applies within identity buckets and after their merge. */
        fun ranked(cards: List<CardInfo>, query: String): List<CardInfo> {
            val trimmed = query.trim()
            if (trimmed.isEmpty()) return cards.sortedBy { it.name }
            return cards.map { card ->
                val index = card.name.indexOf(trimmed, ignoreCase = true)
                card to when {
                    index < 0 -> 3
                    index == 0 -> if (trimmed.length == card.name.length) 0 else 1
                    else -> 2
                }
            }.sortedWith { a, b -> if (a.second == b.second) a.first.name.compareTo(b.first.name) else a.second.compareTo(b.second) }.map { it.first }
        }
    }
}

/**
 * Apply type, mana, set and identity filters before limiting results. Exact identity buckets
 * are disjoint, so off-color entries cannot hide later matches.
 */
object DeckStudioCatalogueSearch {
    fun cards(catalogue: NativeDeckMetadataCatalogue, query: String = "", type: String = "", allowedIdentity: List<String>? = null,
              setCode: String = "", minimumManaValue: Double? = null, maximumManaValue: Double? = null, limit: Int = 80): List<CardInfo> {
        if (limit <= 0 || minimumManaValue?.let { !it.isFinite() || it < 0 } == true || maximumManaValue?.let { !it.isFinite() || it < 0 } == true ||
            (minimumManaValue != null && maximumManaValue != null && minimumManaValue > maximumManaValue)) return emptyList()
        val cap = minOf(limit, 2000)
        val base = NativeDeckMetadataCatalogue.SearchFilter(query = query, type = type, setCode = setCode,
            minimumManaValue = minimumManaValue, maximumManaValue = maximumManaValue)
        if (allowedIdentity == null) return catalogue.search(base, cap)
        val identity = allowedIdentity.toSet().sorted()
        if (identity.size > 5 || !setOf("W", "U", "B", "R", "G").containsAll(identity)) return emptyList()
        val results = ArrayList<CardInfo>()
        for (mask in 0 until (1 shl identity.size)) {
            val bucket = identity.indices.filter { mask and (1 shl it) != 0 }.map { identity[it] }.toSet()
            results += catalogue.search(base.copy(colorIdentity = bucket), cap)
        }
        return NativeDeckMetadataCatalogue.ranked(results, query).take(cap)
    }
}

class ResolutionError(message: String) : Exception(message)

/** OnDeviceDeckResolver.swift: resolves trusted printings locally; XMage decides legality. */
class OnDeviceDeckResolver(private val index: PrintingIndex) {
    val upstreamCommit: String get() = index.upstreamCommit
    /** The native capability's registry hash. */
    val catalogueHash: String get() = index.catalogueHash
    private val nameAliases: Map<String, String> = index.nameAliases.filterKeys { it !in index.names }
    private val reverseFaces: Map<String, String> = NativeDeckCanonicalNames.reverseFaces(nameAliases, index.names)

    fun canonicalCardName(name: String): String? = if (name in index.names) name else nameAliases[name] ?: reverseFaces[name]
    fun containsCard(name: String): Boolean = canonicalCardName(name) != null

    fun canonicalized(deck: DeckList): DeckList {
        fun entry(value: DeckEntry): DeckEntry {
            val name = canonicalCardName(value.cardName)
                ?: throw ResolutionError("No compiled printing for '${value.cardName}'. Use the exact card name from this app's catalogue or update the app.")
            return value.copy(cardName = name)
        }
        return DeckList(deck.name, deck.commander?.let(::entry), deck.entries.map(::entry))
    }

    /** The engine deck: main, commanders and companions with each exact printing. */
    fun resolve(deck: DeckList): J {
        val canonical = canonicalized(deck)
        var total = 0
        fun row(entry: DeckEntry): J {
            if (entry.quantity !in 1..2000 || entry.quantity > 2000 - total) {
                throw ResolutionError("Invalid count for '${entry.cardName}'. Each count must be 1–2,000 and the entire deck must contain at most 2,000 cards.")
            }
            total += entry.quantity
            val printing = index.find(entry.cardName)?.takeIf { it.name == entry.cardName }
                ?: throw ResolutionError("No compiled printing for '${entry.cardName}'. Use the exact card name from this app's catalogue or update the app.")
            return JsonObject(mapOf("name" to JsonPrimitive(printing.name), "setCode" to JsonPrimitive(printing.setCode),
                "collectorNumber" to JsonPrimitive(printing.collectorNumber), "count" to JsonPrimitive(entry.quantity)))
        }
        val sections = linkedMapOf("main" to ArrayList<J>(), "commanders" to ArrayList(), "companions" to ArrayList())
        val assigned = HashMap<String, String>()
        fun append(entry: DeckEntry, section: String) {
            val previous = assigned[entry.cardName]
            if (previous != null && previous != section) {
                throw ResolutionError("'${entry.cardName}' appears in both $previous and $section. Keep it in one section and confirm its count; no copies were removed automatically.")
            }
            assigned[entry.cardName] = section
            sections.getValue(section) += row(entry)
        }
        canonical.commander?.let { append(it, "commanders") }
        for (entry in canonical.entries) append(entry, section(entry.section))
        return JsonObject(sections.mapValues { JsonArray(it.value) } + ("name" to JsonPrimitive(canonical.name)))
    }

    private fun section(name: String): String = when (name.trim().lowercase()) {
        "deck", "main" -> "main"
        "commander", "commanders" -> "commanders"
        "companion", "companions" -> "companions"
        else -> throw ResolutionError("Unsupported deck section '$name'. Native play supports Deck, Commander, or Companion, not a general sideboard. No cards were dropped.")
    }
}

/**
 * Draft boards stay intact. Only explicit sideboard and maybeboard sections are left out of a
 * separate playing projection; unknown sections need review.
 */
class DeckStudioPlayProjection(val original: DeckList) {
    val playing: DeckList
    val excluded: List<DeckEntry>

    init {
        OnDeviceDeckEditing.validateDraft(original)
        val included = ArrayList<DeckEntry>(); val left = ArrayList<DeckEntry>()
        for (row in original.entries) {
            when (row.section.trim().lowercase()) {
                "main", "deck", "commander", "commanders", "companion", "companions" -> included += row
                "sideboard", "maybeboard", "considering" -> left += row
                else -> throw ResolutionError("Map section '${row.section}' to Main, Commander, Companion, Sideboard or Maybeboard before validating. No cards have been discarded.")
            }
        }
        playing = DeckList(original.name, original.commander, included)
        excluded = left
    }

    fun resolve(resolver: OnDeviceDeckResolver): J = resolver.resolve(playing)
    /** The exact request bytes a validation receipt is bound to. */
    fun request(resolver: OnDeviceDeckResolver): String = String(EngineJson.encode(resolve(resolver)), Charsets.UTF_8)
}

/**
 * OnDeviceDeckLinkImporter.swift. No gateway, login, cookies, retries, redirects, scraping or
 * remote card-name resolution. The phone fetches; this decodes and checks.
 */
class OnDeviceDeckLinkImporter(val resolver: OnDeviceDeckResolver) {
    data class Preview(val deck: DeckList, val unresolvedNames: List<String>, val annotations: List<OnDeviceDeckEditing.TextAnnotation> = emptyList())
    enum class Provider { MOXFIELD, ARCHIDEKT }
    data class Source(val provider: Provider, val id: String, val endpoint: String)
    class ImportError(message: String) : Exception("$message Export the deck as text and paste it instead; no cards were imported.")

    fun preview(deck: DeckList): Preview {
        OnDeviceDeckEditing.validateDraft(deck)
        val unresolved = sortedSetOf<String>()
        fun entry(row: DeckEntry): DeckEntry {
            val canonical = resolver.canonicalCardName(row.cardName)
            if (canonical == null) unresolved += row.cardName
            return row.copy(cardName = canonical ?: row.cardName)
        }
        return Preview(DeckList(deck.name, deck.commander?.let(::entry), deck.entries.map(::entry)), unresolved.toList())
    }

    /** Review-only parsing keeps names, sections and provider export annotations. */
    fun preview(text: String, name: String): Preview {
        val imported = OnDeviceDeckEditing.importText(text, name)
        return preview(imported.deck).copy(annotations = imported.annotations)
    }

    fun decode(text: String, source: Source, excludeSideboards: Boolean = false, reviewOnly: Boolean = false): DeckList {
        if (text.utf8Size > maximumBytes) throw ImportError("Provider response exceeds 2 MiB.")
        try {
            val value = kotlinx.serialization.json.Json.parseToJsonElement(text)
            return when (source.provider) {
                Provider.MOXFIELD -> {
                    val publicId = value["publicId"].string; val visibility = value["visibility"].string
                    val name = value["name"].string ?: throw IllegalStateException()
                    if (publicId != source.id || visibility?.lowercase() != "public") throw ImportError("Moxfield deck is private, not public, or has a mismatched ID.")
                    val boards = value["boards"].obj ?: throw IllegalStateException()
                    val sections = mapOf("mainboard" to "main", "commanders" to "commanders", "companions" to "companions")
                    val entries = ArrayList<DeckEntry>()
                    for (key in boards.keys.sorted()) {
                        val rows = boards[key]["cards"].obj ?: throw IllegalStateException()
                        fun decoded(id: String) = rows[id].let { row ->
                            val quantity = row["quantity"].integer?.toInt() ?: throw IllegalStateException()
                            (row["card"]["name"].string ?: throw IllegalStateException()) to quantity
                        }
                        val section = sections[key]
                        if (section == null) {
                            if (excludeSideboards && key in setOf("sideboard", "maybeboard")) {
                                validateExcluded(rows.keys.map { decoded(it).let { (card, count) -> DeckEntry(card, count, "main") } })
                                continue
                            }
                            if (rows.isNotEmpty()) throw ImportError("Unsupported Moxfield section '$key'; it cannot be discarded or treated as a companion.")
                            continue
                        }
                        for (id in rows.keys.sorted()) decoded(id).let { (card, count) -> entries += DeckEntry(card, count, section) }
                    }
                    checkedDeck(name, entries, reviewOnly)
                }
                Provider.ARCHIDEKT -> {
                    val id = value["id"].integer ?: throw IllegalStateException()
                    val private = value["private"].bool ?: throw IllegalStateException()
                    val unlisted = value["unlisted"].bool ?: throw IllegalStateException()
                    val name = value["name"].string ?: throw IllegalStateException()
                    if (id.toString() != source.id || private || unlisted) throw ImportError("Archidekt deck is private, not public, or has a mismatched ID.")
                    val categories = HashMap<String, Boolean>()
                    for (category in value["categories"].array ?: throw IllegalStateException()) {
                        val label = category["name"].string ?: throw IllegalStateException()
                        val included = category["includedInDeck"].bool ?: throw IllegalStateException()
                        if (label in categories) throw ImportError("Ambiguous Archidekt categories.")
                        categories[label] = included
                    }
                    val entries = ArrayList<DeckEntry>()
                    for (row in value["cards"].array ?: throw IllegalStateException()) {
                        val quantity = row["quantity"].integer?.toInt() ?: throw IllegalStateException()
                        val cardName = row["card"]["oracleCard"]["name"].string ?: throw IllegalStateException()
                        val labels = row["categories"]?.takeIf { it !is kotlinx.serialization.json.JsonNull }?.let { labels ->
                            (labels.array ?: throw IllegalStateException()).map { it.string ?: throw IllegalStateException() }
                        } ?: emptyList()
                        val companionFlag = row["companion"]?.takeIf { it !is kotlinx.serialization.json.JsonNull }?.let { it.bool ?: throw IllegalStateException() }
                        if (!labels.all { it in categories }) throw ImportError("Unknown Archidekt card category.")
                        val roles = labels.map { it.lowercase() }.filter { it in setOf("commander", "companion", "sideboard", "maybeboard") }.toSet()
                        if (roles.size > 1) throw ImportError("Conflicting Archidekt card roles.")
                        if (companionFlag == true && "commander" in roles) throw ImportError("Card marked both commander and companion.")
                        val companion = companionFlag == true || "companion" in roles
                        val sideboard = "sideboard" in roles || "maybeboard" in roles
                        val excludedCategory = labels.isNotEmpty() && labels.all { categories[it] == false }
                        if (sideboard || (excludedCategory && !companion)) {
                            if ("commander" in roles || companion || (sideboard && labels.any { categories[it] == true })) {
                                throw ImportError("Conflicting included and excluded Archidekt card roles.")
                            }
                            if (!excludeSideboards) throw ImportError("Archidekt contains sideboard or excluded cards; these cannot be silently discarded.")
                            validateExcluded(listOf(DeckEntry(cardName, quantity, "main")))
                            continue
                        }
                        val section = if ("commander" in roles) "commanders" else if (companion) "companions" else "main"
                        entries += DeckEntry(cardName, quantity, section)
                    }
                    checkedDeck(name, entries, reviewOnly)
                }
            }
        } catch (error: ImportError) { throw error }
        catch (error: ResolutionError) { throw error }
        catch (error: Exception) { throw ImportError("Malformed or changed provider deck schema.") }
    }

    /** Opting out of a section does not permit malformed quantities or unknown card names. */
    private fun validateExcluded(entries: List<DeckEntry>) {
        if (entries.isEmpty()) return
        resolver.resolve(DeckList("Excluded cards", null, entries))
    }

    private fun checkedDeck(name: String, entries: List<DeckEntry>, reviewOnly: Boolean): DeckList {
        if (entries.isEmpty() || entries.size > 2000 || name.utf8Size > 512) throw ImportError("Deck is empty or too large.")
        val remaining = entries.toMutableList()
        val first = remaining.indexOfFirst { it.section == "commanders" }.takeIf { it >= 0 }?.let { remaining.removeAt(it) }
        val raw = DeckList(name, first, remaining)
        if (reviewOnly) return preview(raw).deck
        val deck = resolver.canonicalized(raw)
        resolver.resolve(deck)
        return deck
    }

    companion object {
        const val maximumBytes = 2 * 1024 * 1024

        fun source(text: String): Source {
            val value = text.trim()
            val uri = runCatching { java.net.URI(value) }.getOrNull()
            if (value.utf8Size > 2048 || uri == null || uri.scheme != "https" || uri.rawUserInfo != null || uri.port != -1 ||
                uri.rawQuery != null || uri.rawPath?.contains('%') != false) {
                throw ImportError("Use an HTTPS public Moxfield or Archidekt deck URL without credentials or query parameters.")
            }
            val path = uri.path.split('/')
            if (path.size < 3 || path[0].isNotEmpty() || path[1] != "decks") throw ImportError("This is not a supported deck link.")
            val id = path[2]
            return when (uri.host?.lowercase()) {
                "moxfield.com", "www.moxfield.com" -> {
                    if (!Regex("^[A-Za-z0-9_-]{22}$").matches(id) || !(path.size == 3 || (path.size == 4 && path[3].isEmpty()))) throw ImportError("Invalid Moxfield deck ID.")
                    Source(Provider.MOXFIELD, id, "https://api2.moxfield.com/v3/decks/all/$id")
                }
                "archidekt.com", "www.archidekt.com" -> {
                    if (!Regex("^[1-9][0-9]{0,14}$").matches(id) || !(path.size == 3 || (path.size == 4 && Regex("^[A-Za-z0-9_-]*$").matches(path[3])))) {
                        throw ImportError("Invalid Archidekt deck ID or slug.")
                    }
                    Source(Provider.ARCHIDEKT, id, "https://archidekt.com/api/decks/$id/")
                }
                else -> throw ImportError("Only moxfield.com and archidekt.com deck links are supported.")
            }
        }
    }
}
