package io.magicmobile.android.studio

import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.isNull
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.net.URI
import java.text.Normalizer
import java.util.Locale

/**
 * The documented public Spellbook API takes names and quantities (CommanderSpellbookModels.swift).
 * No deck title, local IDs, notes, sideboard or maybeboard is sent.
 */
class SpellbookDeck(main: List<Card>, commanders: List<Card>) {
    data class Card(val card: String, val quantity: Int)

    val main: List<Card>
    val commanders: List<Card>

    init {
        fun normalize(cards: List<Card>, limit: Int): List<Card> {
            if (cards.size > limit) throw SpellbookError.InvalidDeck
            val quantities = HashMap<String, Int>(); val names = HashMap<String, String>()
            for (row in cards) {
                val name = row.card.trim()
                // Spellbook also accepts numeric strings as its own card IDs; never send one by accident.
                if (name.isEmpty() || name.utf8Size > 256 || name.all { it.isDigit() } || name.any { Character.isISOControl(it) } || row.quantity !in 1..2000) {
                    throw SpellbookError.InvalidDeck
                }
                val key = key(name)
                if ((quantities[key] ?: 0) > 2000 - row.quantity) throw SpellbookError.InvalidDeck
                quantities[key] = (quantities[key] ?: 0) + row.quantity
                names[key] = names[key]?.let { minOf(it, name) } ?: name
            }
            return quantities.keys.sorted().map { Card(names.getValue(it), quantities.getValue(it)) }
        }
        this.main = normalize(main, 600)
        this.commanders = normalize(commanders, 12)
        if (this.commanders.isEmpty() || this.main.sumOf { it.quantity } + this.commanders.sumOf { it.quantity } > 2000) throw SpellbookError.InvalidDeck
    }

    override fun equals(other: Any?) = other is SpellbookDeck && other.main == main && other.commanders == commanders
    override fun hashCode() = main.hashCode() * 31 + commanders.hashCode()

    /** Sorted keys, like the iOS encoder, so the same deck always sends the same bytes. */
    fun encoded(): String = json().toString()
    fun json(): JsonObject = JsonObject(sortedMapOf(
        "commanders" to JsonArray(commanders.map { JsonObject(sortedMapOf("card" to JsonPrimitive(it.card), "quantity" to JsonPrimitive(it.quantity))) }),
        "main" to JsonArray(main.map { JsonObject(sortedMapOf("card" to JsonPrimitive(it.card), "quantity" to JsonPrimitive(it.quantity))) })))

    fun quantities(commandZoneOnly: Boolean = false): Map<String, Int> =
        (if (commandZoneOnly) commanders else main + commanders).groupingBy { key(it.card) }.fold(0) { total, row -> total + row.quantity }

    companion object {
        fun key(name: String): String = Normalizer.normalize(name, Normalizer.Form.NFC).lowercase(Locale.ROOT)
        fun decode(value: J?): SpellbookDeck {
            fun cards(key: String) = (value[key].array ?: throw SpellbookError.InvalidResponse).map {
                Card(it["card"].string ?: throw SpellbookError.InvalidResponse, it["quantity"].integer?.toInt() ?: throw SpellbookError.InvalidResponse)
            }
            return SpellbookDeck(cards("main"), cards("commanders"))
        }
    }
}

/** Resolve against the shipped catalogue before sharing. Never sends other draft sections. */
object DeckStudioSpellbookInput {
    fun make(draft: NativeDeckDraft, resolver: OnDeviceDeckResolver?): SpellbookDeck? {
        resolver ?: return null
        val main = ArrayList<SpellbookDeck.Card>(); val commanders = ArrayList<SpellbookDeck.Card>()
        for (row in draft.rows) {
            val section = DeckStudioDraftPresentation.section(row)
            if (section != "deck" && section != "commanders") continue
            val name = resolver.canonicalCardName(row.cardName) ?: return null
            val card = SpellbookDeck.Card(name, row.quantity)
            if (section == "commanders") commanders += card else main += card
        }
        return runCatching { SpellbookDeck(main, commanders) }.getOrNull()
    }
}

sealed class SpellbookError(message: String) : Exception(message) {
    object InvalidDeck : SpellbookError("Combo lookup requires resolved card names, commander(s), and a bounded decklist. Your draft is unchanged.")
    object InvalidResponse : SpellbookError("Commander Spellbook returned an unsupported response. Your draft and previous results are unchanged.")
    object ResponseTooLarge : SpellbookError("The combo response exceeded the safe size limit. Use the Spellbook website for this search.")
    object UnsafePagination : SpellbookError("The next combo page could not be verified. No deck data was sent to that address.")
    object Unavailable : SpellbookError("Commander Spellbook is unavailable or offline. Keep building, use saved results, or retry later.")
    class RateLimited(val seconds: Int) : SpellbookError("Please wait $seconds seconds before another combo request. Your draft is unchanged.")
    class HttpStatus(val status: Int) : SpellbookError("Commander Spellbook returned HTTP $status. No cards were added; retry later.")
    object TooManyResults : SpellbookError("This lookup reached the local result limit. Open Commander Spellbook for more results.")
}

enum class SpellbookGroup(val key: String, val title: String) {
    INCLUDED("included", "Pieces found by Spellbook"),
    INCLUDED_BY_CHANGING_COMMANDERS("includedByChangingCommanders", "Needs a commander change"),
    ALMOST_INCLUDED("almostIncluded", "Nearby combos"),
    ALMOST_INCLUDED_BY_ADDING_COLORS("almostIncludedByAddingColors", "Needs additional colors"),
    ALMOST_INCLUDED_BY_CHANGING_COMMANDERS("almostIncludedByChangingCommanders", "Nearby, with a different commander"),
    ALMOST_INCLUDED_BY_ADDING_COLORS_AND_CHANGING_COMMANDERS("almostIncludedByAddingColorsAndChangingCommanders", "Needs colors and commander changes");

    val isOther: Boolean get() = this != INCLUDED && this != ALMOST_INCLUDED
}

data class SpellbookVariant(
    val id: String,
    val uses: List<Ingredient>,
    val requires: List<Template>,
    val produces: List<Result>,
    val identity: String,
    val status: String,
    val spoiler: Boolean,
    val commanderLegal: Boolean?,
    val description: String,
    val easyPrerequisites: String,
    val notablePrerequisites: String,
    val manaNeeded: String,
    val notes: String,
    /** The provider's JSON, kept so a cached lookup round-trips exactly. */
    val raw: J,
) {
    data class Ingredient(val cardID: Int, val cardName: String, val quantity: Int, val mustBeCommander: Boolean, val zoneLocations: List<String>,
                          val battlefieldCardState: String, val exileCardState: String, val libraryCardState: String, val graveyardCardState: String)
    data class Template(val templateID: Int, val templateName: String, val quantity: Int, val mustBeCommander: Boolean, val zoneLocations: List<String>,
                        val battlefieldCardState: String, val exileCardState: String, val libraryCardState: String, val graveyardCardState: String)
    data class Result(val featureName: String, val quantity: Int)

    val websiteURL: String? get() = if (safeID(id)) "https://commanderspellbook.com/combo/$id/" else null

    fun validate() {
        fun text(value: String, max: Int = 32768) = value.utf8Size <= max && '\u0000' !in value
        val ok = safeID(id) && uses.size <= 100 && requires.size <= 100 && produces.size <= 100 && (uses.isNotEmpty() || requires.isNotEmpty()) &&
            identity.all { it in "WUBRGC" } && identity.length <= 6 && text(description) && text(easyPrerequisites) && text(notablePrerequisites) &&
            text(manaNeeded) && text(notes) && text(status, 32) &&
            uses.all { it.cardID > 0 && it.cardName.isNotEmpty() && text(it.cardName, 1024) && it.quantity in 1..2000 && it.zoneLocations.size <= 20 &&
                it.zoneLocations.all { zone -> text(zone, 16) } && text(it.battlefieldCardState) && text(it.exileCardState) && text(it.libraryCardState) && text(it.graveyardCardState) } &&
            requires.all { it.templateID > 0 && text(it.templateName, 1024) && it.quantity in 1..2000 && it.zoneLocations.size <= 20 &&
                it.zoneLocations.all { zone -> text(zone, 16) } && text(it.battlefieldCardState) && text(it.exileCardState) && text(it.libraryCardState) && text(it.graveyardCardState) } &&
            produces.all { text(it.featureName, 4096) && it.quantity in 1..2000 }
        if (!ok) throw SpellbookError.InvalidResponse
    }

    companion object {
        fun safeID(value: String): Boolean = value.isNotEmpty() && value.utf8Size <= 160 && Regex("^[A-Za-z0-9_-]+$").matches(value)

        fun decode(value: J): SpellbookVariant {
            fun string(v: J?, key: String) = v[key].string ?: throw SpellbookError.InvalidResponse
            fun int(v: J?, key: String) = v[key].integer?.toInt() ?: throw SpellbookError.InvalidResponse
            fun bool(v: J?, key: String) = v[key].bool ?: throw SpellbookError.InvalidResponse
            fun zones(v: J?) = (v["zoneLocations"].array ?: throw SpellbookError.InvalidResponse).map { it.string ?: throw SpellbookError.InvalidResponse }
            val legalities = value["legalities"].obj ?: throw SpellbookError.InvalidResponse
            return SpellbookVariant(
                string(value, "id"),
                (value["uses"].array ?: throw SpellbookError.InvalidResponse).map { use ->
                    Ingredient(int(use["card"], "id"), string(use["card"], "name"), int(use, "quantity"), bool(use, "mustBeCommander"), zones(use),
                        string(use, "battlefieldCardState"), string(use, "exileCardState"), string(use, "libraryCardState"), string(use, "graveyardCardState"))
                },
                (value["requires"].array ?: throw SpellbookError.InvalidResponse).map { row ->
                    Template(int(row["template"], "id"), string(row["template"], "name"), int(row, "quantity"), bool(row, "mustBeCommander"), zones(row),
                        string(row, "battlefieldCardState"), string(row, "exileCardState"), string(row, "libraryCardState"), string(row, "graveyardCardState"))
                },
                (value["produces"].array ?: throw SpellbookError.InvalidResponse).map { Result(string(it["feature"], "name"), int(it, "quantity")) },
                string(value, "identity"), string(value, "status"), bool(value, "spoiler"),
                legalities["commander"]?.takeIf { !it.isNull }?.let { it.bool ?: throw SpellbookError.InvalidResponse },
                string(value, "description"), string(value, "easyPrerequisites"), string(value, "notablePrerequisites"), string(value, "manaNeeded"),
                string(value, "notes"), value)
        }
    }
}

/** Never follows a provider-supplied URL with the deck POST body. One page per user action. */
object SpellbookAPI {
    const val endpoint = "https://backend.commanderspellbook.com/find-my-combos"
    const val maximumResponseBytes = 4 * 1024 * 1024
    const val pageSize = 100
    const val maximumResults = 2000

    fun pageURL(offset: Int = 0): String {
        if (offset !in 0..maximumResults) throw SpellbookError.UnsafePagination
        return "$endpoint?limit=$pageSize&offset=$offset"
    }

    fun nextOffset(next: String?, previous: Int): Int? {
        next ?: return null
        val uri = runCatching { URI(next) }.getOrNull() ?: throw SpellbookError.UnsafePagination
        val base = URI(endpoint)
        val items = uri.rawQuery?.split('&')?.map { it.substringBefore('=') to it.substringAfter('=', "") } ?: throw SpellbookError.UnsafePagination
        val raw = items.firstOrNull { it.first == "offset" }?.second
        val offset = raw?.toIntOrNull()
        if (uri.scheme != "https" || uri.host != base.host || uri.port != -1 || uri.rawUserInfo != null || uri.rawFragment != null ||
            uri.rawPath != base.rawPath || items.size != 2 || items.count { it.first == "limit" } != 1 || items.count { it.first == "offset" } != 1 ||
            items.first { it.first == "limit" }.second != pageSize.toString() || offset == null || offset.toString() != raw || offset <= previous ||
            offset > maximumResults) throw SpellbookError.UnsafePagination
        return offset
    }
}

data class SpellbookPage(val count: Int?, val next: String?, val identity: String, val groups: Map<SpellbookGroup, List<SpellbookVariant>>) {
    companion object {
        fun decode(text: String): SpellbookPage {
            if (text.utf8Size > SpellbookAPI.maximumResponseBytes) throw SpellbookError.ResponseTooLarge
            try {
                val value = Json.parseToJsonElement(text)
                val results = value["results"].obj ?: throw SpellbookError.InvalidResponse
                val identity = results["identity"].string ?: throw SpellbookError.InvalidResponse
                val groups = SpellbookGroup.entries.associateWith { group ->
                    (results[group.key].array ?: throw SpellbookError.InvalidResponse).map(SpellbookVariant::decode)
                }
                val count = value["count"]?.takeIf { !it.isNull }?.let { it.integer?.toInt() ?: throw SpellbookError.InvalidResponse }
                val next = value["next"]?.takeIf { !it.isNull }?.let { it.string ?: throw SpellbookError.InvalidResponse }
                if ((count != null && count < 0) || groups.values.sumOf { it.size } > 1000 || (next?.utf8Size ?: 0) > 2048 ||
                    !identity.all { it in "WUBRGC" }) throw SpellbookError.InvalidResponse
                val seen = HashSet<String>()
                for (group in SpellbookGroup.entries) for (variant in groups.getValue(group)) {
                    variant.validate()
                    if (!seen.add(variant.id)) throw SpellbookError.InvalidResponse
                }
                return SpellbookPage(count, next, identity, groups)
            } catch (error: SpellbookError) { throw error } catch (error: Exception) { throw SpellbookError.InvalidResponse }
        }
    }
}

data class SpellbookSnapshot(
    val deck: SpellbookDeck,
    val fetchedAt: Long,
    val total: Int?,
    val groups: Map<SpellbookGroup, List<SpellbookVariant>>,
    val offsets: List<Int>,
    val nextOffset: Int?,
) {
    val loadedCount: Int get() = groups.values.sumOf { it.size }

    fun validate(expected: SpellbookDeck) {
        val ok = deck == expected && groups.keys == SpellbookGroup.entries.toSet() && offsets.firstOrNull() == 0 && offsets == offsets.toSortedSet().toList() &&
            offsets.size <= 21 && offsets.all { it in 0..SpellbookAPI.maximumResults } && (total?.let { it >= 0 } ?: true) &&
            (nextOffset?.let { it > (offsets.lastOrNull() ?: -1) && it <= SpellbookAPI.maximumResults } ?: true) && loadedCount <= SpellbookAPI.maximumResults
        if (!ok) throw SpellbookError.InvalidResponse
        val seen = HashSet<String>()
        for (group in SpellbookGroup.entries) for (variant in groups.getValue(group)) {
            variant.validate()
            if (!seen.add(variant.id)) throw SpellbookError.InvalidResponse
        }
    }

    fun json(): JsonObject = JsonObject(buildMap {
        put("schema", JsonPrimitive(1)); put("deck", deck.json()); put("fetchedAt", JsonPrimitive(fetchedAt))
        total?.let { put("total", JsonPrimitive(it)) }
        put("groups", JsonObject(groups.entries.associate { (group, variants) -> group.key to JsonArray(variants.map { it.raw }) }))
        put("offsets", JsonArray(offsets.map(::JsonPrimitive))); nextOffset?.let { put("nextOffset", JsonPrimitive(it)) }
    })

    companion object {
        fun decode(value: J?): SpellbookSnapshot {
            if (value["schema"].integer != 1L) throw SpellbookError.InvalidResponse
            val groups = value["groups"].obj ?: throw SpellbookError.InvalidResponse
            return SpellbookSnapshot(SpellbookDeck.decode(value["deck"]), value["fetchedAt"].integer ?: throw SpellbookError.InvalidResponse,
                value["total"]?.takeIf { !it.isNull }?.let { it.integer?.toInt() ?: throw SpellbookError.InvalidResponse },
                SpellbookGroup.entries.associateWith { group -> (groups[group.key].array ?: throw SpellbookError.InvalidResponse).map(SpellbookVariant::decode) },
                (value["offsets"].array ?: throw SpellbookError.InvalidResponse).map { it.integer?.toInt() ?: throw SpellbookError.InvalidResponse },
                value["nextOffset"]?.takeIf { !it.isNull }?.let { it.integer?.toInt() ?: throw SpellbookError.InvalidResponse })
        }

        /** Merges one more page into the previous snapshot, rejecting a changed duplicate. */
        fun merged(deck: SpellbookDeck, previous: SpellbookSnapshot?, page: SpellbookPage, offset: Int, next: Int?, now: Long): SpellbookSnapshot {
            val groups = SpellbookGroup.entries.associateWith { (previous?.groups?.get(it) ?: emptyList()).toMutableList() }
            val seen = HashMap<String, Pair<SpellbookGroup, SpellbookVariant>>()
            for ((group, variants) in groups) for (variant in variants) seen[variant.id] = group to variant
            for (group in SpellbookGroup.entries) for (variant in page.groups.getValue(group)) {
                val old = seen[variant.id]
                if (old != null) {
                    if (old.first != group || old.second.raw != variant.raw) throw SpellbookError.InvalidResponse
                    continue
                }
                groups.getValue(group) += variant
                seen[variant.id] = group to variant
            }
            if (seen.size > SpellbookAPI.maximumResults) throw SpellbookError.TooManyResults
            val snapshot = SpellbookSnapshot(deck, previous?.fetchedAt ?: now, page.count, groups, (previous?.offsets ?: emptyList()) + offset, next)
            snapshot.validate(deck)
            return snapshot
        }
    }
}

/**
 * A local, conservative named-card check. A provider's "included" bucket may contain flexible
 * templates; it is not proof that a combo can be executed.
 */
data class SpellbookAssessment(val readiness: Readiness, val explanation: String) {
    sealed class Readiness {
        object NamedPiecesPresent : Readiness()
        data class OneCardAway(val name: String) : Readiness()
        object ReviewRequirements : Readiness()
    }

    companion object {
        fun make(variant: SpellbookVariant, group: SpellbookGroup, deck: SpellbookDeck, commanderColors: List<String>?, canonicalName: (String) -> String?): SpellbookAssessment {
            if (group.isOther) return SpellbookAssessment(Readiness.ReviewRequirements, group.title)
            if (variant.status != "OK" || variant.spoiler || variant.commanderLegal != true) {
                return SpellbookAssessment(Readiness.ReviewRequirements, "Check spoiler, format legality and provider status before considering this combo.")
            }
            if (commanderColors == null || !setOf("W", "U", "B", "R", "G").containsAll(commanderColors) ||
                !variant.identity.filter { it != 'C' }.all { it.toString() in commanderColors }) {
                return SpellbookAssessment(Readiness.ReviewRequirements, "Commander color identity is unknown or this combo uses additional colors.")
            }
            if (variant.requires.isNotEmpty()) {
                return SpellbookAssessment(Readiness.ReviewRequirements, "Contains flexible requirements. Review the named cards, templates and prerequisites; availability is not proven.")
            }
            val available = deck.quantities(); val commanders = deck.quantities(commandZoneOnly = true)
            val needed = HashMap<String, Int>(); val commanderNeeded = HashMap<String, Int>(); val names = HashMap<String, String>()
            for (use in variant.uses) {
                val name = canonicalName(use.cardName)
                    ?: return SpellbookAssessment(Readiness.ReviewRequirements, "A required card is not resolved in the installed XMage catalogue.")
                val key = SpellbookDeck.key(name)
                if ((needed[key] ?: 0) > 2000 - use.quantity) return SpellbookAssessment(Readiness.ReviewRequirements, "The required quantities need review.")
                needed[key] = (needed[key] ?: 0) + use.quantity; names[key] = name
                if (use.mustBeCommander) commanderNeeded[key] = (commanderNeeded[key] ?: 0) + use.quantity
            }
            if (!commanderNeeded.all { (commanders[it.key] ?: 0) >= it.value }) {
                return SpellbookAssessment(Readiness.ReviewRequirements, "A specific card must be a commander, not merely in the deck.")
            }
            val missing = needed.mapNotNull { (key, count) -> maxOf(0, count - (available[key] ?: 0)).takeIf { it > 0 }?.let { key to it } }
            if (missing.isEmpty()) {
                return SpellbookAssessment(Readiness.NamedPiecesPresent, "All named pieces are present. Mana, zones, timing and other prerequisites still apply; this is not an XMage simulation.")
            }
            val only = missing.singleOrNull()
            if (only != null && only.second == 1 && (available[only.first] ?: 0) == 0) {
                names[only.first]?.let {
                    return SpellbookAssessment(Readiness.OneCardAway(it), "One named piece is absent. Adding it does not certify deck legality or prove the required game state.")
                }
            }
            return SpellbookAssessment(Readiness.ReviewRequirements, "Missing multiple cards or additional copies. No automatic Commander-legal addition is implied.")
        }
    }
}

sealed class DeckStudioScryfallError(message: String) : Exception(message) {
    object InvalidInput : DeckStudioScryfallError("Enter a card name or search of at most 512 bytes.")
    object InvalidResponse : DeckStudioScryfallError("Scryfall returned an unsupported response. The local catalogue and deck are unchanged.")
    object TooLarge : DeckStudioScryfallError("Scryfall's response exceeded the safe size limit. Refine the search.")
    object Unavailable : DeckStudioScryfallError("Scryfall is unavailable or offline. Local search, editing and gameplay still work.")
    object RateLimited : DeckStudioScryfallError("Scryfall requests are paused after a rate limit. Retry later; no automatic retry was sent.")
    class Http(val status: Int) : DeckStudioScryfallError(if (status == 404) "No matching cards were found on Scryfall." else "Scryfall returned HTTP $status. Local data is unchanged.")
}

/** Reference metadata only; it never overwrites the shipped XMage catalogue. */
data class DeckStudioScryfallCard(
    val id: String,
    val name: String,
    val manaCost: String?,
    val manaValue: Double?,
    val typeLine: String?,
    val oracleText: String?,
    val colorIdentity: List<String>?,
    val legalities: Map<String, String>?,
    val faces: List<Face>?,
    val relatedURIs: Map<String, String>?,
    val scryfallURI: String?,
) {
    data class Face(val name: String, val manaCost: String?, val typeLine: String?, val oracleText: String?)

    val edhrecURL: String? get() = safeWebURL(relatedURIs?.get("edhrec"), setOf("edhrec.com", "www.edhrec.com"))
    val websiteURL: String? get() = safeWebURL(scryfallURI, setOf("scryfall.com", "www.scryfall.com"))

    fun validated(): DeckStudioScryfallCard {
        val ok = name.isNotEmpty() && name.utf8Size <= 1024 && (oracleText?.utf8Size ?: 0) <= 32768 && (typeLine?.utf8Size ?: 0) <= 2048 &&
            (manaCost?.utf8Size ?: 0) <= 2048 && (manaValue?.let { it.isFinite() && it >= 0 && it < 1_000_000 } ?: true) &&
            (colorIdentity?.let { it.size <= 5 && setOf("W", "U", "B", "R", "G").containsAll(it) } ?: true) && (faces?.size ?: 0) <= 8 &&
            (faces?.all { it.name.isNotEmpty() && it.name.utf8Size <= 1024 && (it.oracleText?.utf8Size ?: 0) <= 32768 } ?: true)
        if (!ok) throw DeckStudioScryfallError.InvalidResponse
        return this
    }

    companion object {
        fun safeWebURL(value: String?, hosts: Set<String>): String? {
            if (value == null || value.utf8Size > 2048) return null
            val uri = runCatching { URI(value) }.getOrNull() ?: return null
            if (uri.scheme != "https" || uri.host?.lowercase() !in hosts || uri.rawUserInfo != null || uri.port != -1) return null
            return value
        }

        fun decode(value: J?): DeckStudioScryfallCard {
            fun optional(key: String, v: J? = value) = v[key]?.takeIf { !it.isNull }?.let { it.string ?: throw DeckStudioScryfallError.InvalidResponse }
            fun stringMap(key: String) = value[key]?.takeIf { !it.isNull }?.let { map ->
                (map.obj ?: throw DeckStudioScryfallError.InvalidResponse).mapValues { it.value.string ?: throw DeckStudioScryfallError.InvalidResponse }
            }
            val id = value["id"].string?.takeIf { io.magicmobile.android.game.isUuid(it) } ?: throw DeckStudioScryfallError.InvalidResponse
            return DeckStudioScryfallCard(id, value["name"].string ?: throw DeckStudioScryfallError.InvalidResponse, optional("mana_cost"),
                value["cmc"]?.takeIf { !it.isNull }?.let { (it as? JsonPrimitive)?.content?.toDoubleOrNull() ?: throw DeckStudioScryfallError.InvalidResponse },
                optional("type_line"), optional("oracle_text"),
                value["color_identity"]?.takeIf { !it.isNull }?.let { list -> (list.array ?: throw DeckStudioScryfallError.InvalidResponse).map { it.string ?: throw DeckStudioScryfallError.InvalidResponse } },
                stringMap("legalities"),
                value["card_faces"]?.takeIf { !it.isNull }?.let { list -> (list.array ?: throw DeckStudioScryfallError.InvalidResponse).map { face ->
                    Face(face["name"].string ?: throw DeckStudioScryfallError.InvalidResponse, optional("mana_cost", face), optional("type_line", face), optional("oracle_text", face)) } },
                stringMap("related_uris"), optional("scryfall_uri"))
        }
    }
}

data class DeckStudioScryfallPage(val cards: List<DeckStudioScryfallCard>, val hasMore: Boolean, val page: Int, val query: String, val fetchedAt: Long, val cached: Boolean)

object DeckStudioScryfallRequests {
    /** The exact Scryfall URL for a named lookup (page null) or a search page. */
    fun url(value: String, page: Int? = null): String {
        val query = value.trim()
        if (query.isEmpty() || query.utf8Size > 512 || query.any { Character.isISOControl(it) } || (page != null && page !in 1..10)) {
            throw DeckStudioScryfallError.InvalidInput
        }
        fun encode(text: String) = java.net.URLEncoder.encode(text, "UTF-8").replace("+", "%20")
        return if (page == null) "https://api.scryfall.com/cards/named?exact=${encode(query)}"
        else "https://api.scryfall.com/cards/search?q=${encode(query)}&unique=cards&page=$page"
    }

    fun decodeList(text: String): Pair<List<DeckStudioScryfallCard>, Boolean> {
        val value = try { Json.parseToJsonElement(text) } catch (error: Exception) { throw DeckStudioScryfallError.InvalidResponse }
        val rows = value["data"].array ?: throw DeckStudioScryfallError.InvalidResponse
        val more = value["has_more"].bool ?: throw DeckStudioScryfallError.InvalidResponse
        if (value["object"].string != "list" || rows.size > 200) throw DeckStudioScryfallError.InvalidResponse
        val cards = rows.map { DeckStudioScryfallCard.decode(it).validated() }
        if (cards.map { it.id }.toSet().size != cards.size) throw DeckStudioScryfallError.InvalidResponse
        return cards to more
    }

    fun decodeCard(text: String): DeckStudioScryfallCard {
        val value = try { Json.parseToJsonElement(text) } catch (error: Exception) { throw DeckStudioScryfallError.InvalidResponse }
        if (value["object"].string != "card") throw DeckStudioScryfallError.InvalidResponse
        return DeckStudioScryfallCard.decode(value).validated()
    }
}
