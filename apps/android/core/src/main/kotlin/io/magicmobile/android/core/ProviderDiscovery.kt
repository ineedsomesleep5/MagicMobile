package io.magicmobile.android.core

import io.magicmobile.core.Json
import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.text.Normalizer
import java.util.Locale

/** Pure provider contracts. Network transport and user consent stay in the Android app. */
object ProviderDiscovery {
    const val MAX_RESPONSE_BYTES = 4 * 1024 * 1024
    const val SPELLBOOK_PAGE_SIZE = 100
    const val SPELLBOOK_MAX_RESULTS = 2_000
    private const val SCRYFALL_HOST = "api.scryfall.com"
    private const val SPELLBOOK_HOST = "backend.commanderspellbook.com"

    fun scryfallSearchUri(query: String, page: Int = 1): URI {
        val value = query.trim()
        require(value.isNotEmpty() && value.toByteArray().size <= 1_024 && page in 1..10)
        return URI("https://$SCRYFALL_HOST/cards/search?q=${encode(value)}&unique=cards&page=$page")
    }

    fun scryfallNamedUri(name: String): URI {
        val value = name.trim()
        require(validName(value))
        return URI("https://$SCRYFALL_HOST/cards/named?exact=${encode(value)}")
    }

    fun spellbookUri(offset: Int = 0): URI {
        require(offset in 0..SPELLBOOK_MAX_RESULTS)
        return URI("https", SPELLBOOK_HOST, "/find-my-combos",
            "limit=$SPELLBOOK_PAGE_SIZE&offset=$offset", null)
    }

    fun nextSpellbookOffset(next: String?, previous: Int): Int? {
        if (next == null) return null
        val uri = runCatching { URI(next) }.getOrElse { error("Unsafe Spellbook pagination") }
        requireSafeHttps(uri, SPELLBOOK_HOST, "/find-my-combos")
        require(uri.fragment == null)
        val values = parseQuery(uri.rawQuery)
        require(values.keys == setOf("limit", "offset") && values["limit"] == listOf("$SPELLBOOK_PAGE_SIZE"))
        val offsets = values["offset"] ?: error("Unsafe Spellbook pagination")
        require(offsets.size == 1)
        val raw = offsets.single()
        val offset = raw.toIntOrNull() ?: error("Unsafe Spellbook pagination")
        require(offset.toString() == raw && offset > previous && offset <= SPELLBOOK_MAX_RESULTS)
        return offset
    }

    fun requireProviderUri(uri: URI, kind: ProviderKind) {
        when (kind) {
            ProviderKind.SCRYFALL -> requireSafeHttps(uri, SCRYFALL_HOST, null)
            ProviderKind.SPELLBOOK -> requireSafeHttps(uri, SPELLBOOK_HOST, "/find-my-combos")
            ProviderKind.EDHREC -> requireSafeHttps(uri, "edhrec.com", null, setOf("edhrec.com", "www.edhrec.com"))
        }
    }

    fun requireExternalHttps(uri: URI) {
        require(uri.scheme.equals("https", true) && !uri.host.isNullOrBlank())
        require(uri.userInfo == null && (uri.port == -1 || uri.port == 443))
    }

    fun parseScryfallPage(bytes: ByteArray, query: String, page: Int): ScryfallPage {
        require(bytes.size <= MAX_RESPONSE_BYTES)
        val root = Wire.objectValue(Json.parseObject(bytes.toString(Charsets.UTF_8)))
        require(root.text("object") == "list")
        val rows = root.array("data")
        require(rows.size <= 200)
        val cards = rows.map { parseScryfallObject(Wire.objectValue(it)) }
        require(cards.map { it.id }.toSet().size == cards.size)
        return ScryfallPage(query.trim(), page, cards, root.flag("has_more"))
    }

    fun parseScryfallCard(bytes: ByteArray): ProviderCard {
        require(bytes.size <= MAX_RESPONSE_BYTES)
        return parseScryfallObject(Wire.objectValue(Json.parseObject(bytes.toString(Charsets.UTF_8))))
    }

    fun parseSpellbookPage(bytes: ByteArray, offset: Int): SpellbookPage {
        require(bytes.size <= MAX_RESPONSE_BYTES && offset in 0..SPELLBOOK_MAX_RESULTS)
        val root = Wire.objectValue(Json.parseObject(bytes.toString(Charsets.UTF_8)))
        val result = root.obj("results") ?: error("Spellbook response has no results")
        val identity = result.text("identity") ?: error("Spellbook response has no identity")
        require(identity.length <= 6 && identity.all { it in "WUBRGC" })
        val groups = SpellbookGroup.entries.associateWith { group ->
            require(result.containsKey(group.wireName))
            result.array(group.wireName).map { parseSpellbookCombo(Wire.objectValue(it), group) }
        }
        val all = groups.values.flatten()
        require(all.size <= 1_000 && all.map { it.id }.toSet().size == all.size)
        val count = root["count"]?.let(Wire::integer)
        require(count == null || count >= 0)
        return SpellbookPage(groups, nextSpellbookOffset(root.text("next"), offset), identity)
    }

    private fun parseScryfallObject(value: Obj): ProviderCard {
        require(value.text("object") == "card")
        val id = value.text("id") ?: error("Scryfall card has no id")
        val name = value.text("name") ?: error("Scryfall card has no name")
        require(Wire.uuid(id) && validName(name))
        fun text(key: String, maximum: Int): String? = value.text(key)?.also {
            require(it.toByteArray().size <= maximum && '\u0000' !in it)
        }
        val faces = value.array("card_faces").map(Wire::objectValue)
        require(faces.size <= 8)
        val faceRules = faces.mapNotNull { it.text("oracle_text") }.joinToString("\n\n").ifBlank { null }
        val oracle = text("oracle_text", 32_768) ?: faceRules?.also { require(it.toByteArray().size <= 32_768 && '\u0000' !in it) }
        val edhrec = value.obj("related_uris")?.text("edhrec")?.let { raw ->
            URI(raw).also { requireProviderUri(it, ProviderKind.EDHREC) }.toString()
        }
        return ProviderCard(id, name, text("mana_cost", 1_024), text("type_line", 2_048), oracle, edhrec)
    }

    private fun parseSpellbookCombo(value: Obj, group: SpellbookGroup): SpellbookCombo {
        val id = value.text("id") ?: error("Spellbook combo has no id")
        require(id.length <= 160 && id.matches(Regex("[A-Za-z0-9_-]+")))
        val uses = value.array("uses").map { raw ->
            val ingredient = Wire.objectValue(raw)
            val card = ingredient.obj("card") ?: error("Spellbook ingredient has no card")
            val name = card.text("name") ?: error("Spellbook ingredient has no name")
            val cardID = Wire.integer(card["id"])
            val quantity = Wire.integer(ingredient["quantity"])
            require(cardID > 0 && validName(name) && quantity in 1..2_000 && ingredient["mustBeCommander"] is Boolean)
            SpellbookIngredient(name, quantity.toInt(), ingredient.flag("mustBeCommander"))
        }
        require(uses.isNotEmpty() && uses.size <= 100)
        val requires = value.array("requires")
        require(requires.size <= 100)
        val produces = value.array("produces").map { raw ->
            val row = Wire.objectValue(raw)
            val feature = row.obj("feature")?.text("name") ?: error("Spellbook result has no feature")
            val quantity = Wire.integer(row["quantity"])
            require(feature.toByteArray().size <= 4_096 && '\u0000' !in feature && quantity in 1..2_000)
            feature
        }
        require(produces.size <= 100)
        val identity = value.text("identity") ?: ""
        require(identity.length <= 6 && identity.all { it in "WUBRGC" })
        val status = value.text("status") ?: ""
        require(status.toByteArray().size <= 32 && value["spoiler"] is Boolean)
        val commanderLegal = value.obj("legalities")?.get("commander") as? Boolean
        return SpellbookCombo(id, group, uses, produces, requires.isNotEmpty(), identity,
            status, value.flag("spoiler"), commanderLegal)
    }

    private fun requireSafeHttps(uri: URI, host: String, path: String?, allowedHosts: Set<String> = setOf(host)) {
        require(uri.scheme.equals("https", true) && uri.host?.lowercase(Locale.ROOT) in allowedHosts)
        require(uri.userInfo == null && (uri.port == -1 || uri.port == 443))
        require(path == null || uri.path == path)
    }

    private fun parseQuery(raw: String?): Map<String, List<String>> {
        require(!raw.isNullOrEmpty())
        return raw.split('&').groupBy({ it.substringBefore('=') }, { it.substringAfter('=', "") })
    }

    private fun encode(value: String): String = URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20")
    private fun validName(value: String): Boolean = value.isNotEmpty() && value.toByteArray().size <= 1_024 &&
        value == value.trim() && value.none { it.isISOControl() }
}

enum class ProviderKind { SCRYFALL, SPELLBOOK, EDHREC }

data class ProviderCard(
    val id: String,
    val name: String,
    val manaCost: String?,
    val typeLine: String?,
    val oracleText: String?,
    val edhrecUrl: String?,
)

data class ScryfallPage(val query: String, val page: Int, val cards: List<ProviderCard>, val hasMore: Boolean)

enum class SpellbookGroup(val wireName: String, val title: String) {
    INCLUDED("included", "Pieces found by Spellbook"),
    INCLUDED_CHANGING_COMMANDERS("includedByChangingCommanders", "Needs a commander change"),
    ALMOST_INCLUDED("almostIncluded", "Nearby combos"),
    ALMOST_ADDING_COLORS("almostIncludedByAddingColors", "Needs additional colors"),
    ALMOST_CHANGING_COMMANDERS("almostIncludedByChangingCommanders", "Nearby, with a different commander"),
    ALMOST_COLORS_AND_COMMANDERS("almostIncludedByAddingColorsAndChangingCommanders", "Needs colors and commander changes"),
}

data class SpellbookIngredient(val name: String, val quantity: Int, val mustBeCommander: Boolean)
data class SpellbookCombo(
    val id: String,
    val group: SpellbookGroup,
    val ingredients: List<SpellbookIngredient>,
    val produces: List<String>,
    val hasFlexibleRequirements: Boolean,
    val identity: String,
    val status: String,
    val spoiler: Boolean,
    val commanderLegal: Boolean?,
) {
    val websiteUri: URI get() = URI("https://commanderspellbook.com/combo/$id/")
}
data class SpellbookPage(
    val groups: Map<SpellbookGroup, List<SpellbookCombo>>,
    val nextOffset: Int?,
    val identity: String,
) { val loadedCount: Int get() = groups.values.sumOf { it.size } }

data class SpellbookRow(val card: String, val quantity: Int)
data class SpellbookInput(val main: List<SpellbookRow>, val commanders: List<SpellbookRow>) {
    init {
        require(main.size <= 600 && commanders.isNotEmpty() && commanders.size <= 12)
        require((main + commanders).sumOf { it.quantity } <= 2_000)
        require((main + commanders).all { it.quantity in 1..2_000 && validProviderName(it.card) })
    }

    val body: ByteArray get() = Json.write(mapOf(
        "main" to main.map { mapOf("card" to it.card, "quantity" to it.quantity) },
        "commanders" to commanders.map { mapOf("card" to it.card, "quantity" to it.quantity) },
    )).toByteArray(Charsets.UTF_8)

    fun quantities(): Map<String, Int> = (main + commanders).groupingBy { normalized(it.card) }
        .fold(0) { total, row -> total + row.quantity }

    companion object {
        fun from(deck: Deck, catalogue: Catalogue): SpellbookInput {
            fun rows(section: String, maximum: Int): List<SpellbookRow> {
                val values = deck.entries.filter { it.section == section }
                require(values.size <= maximum)
                val totals = linkedMapOf<String, Pair<String, Int>>()
                for (row in values) {
                    val canonical = catalogue.find(row.name)?.name ?: error("Resolve every shared card name before lookup")
                    require(validProviderName(canonical))
                    val key = normalized(canonical)
                    val previous = totals[key]
                    val count = (previous?.second ?: 0) + row.quantity
                    require(count in 1..2_000)
                    totals[key] = minOf(previous?.first ?: canonical, canonical) to count
                }
                return totals.toSortedMap().values.map { SpellbookRow(it.first, it.second) }
            }
            return SpellbookInput(rows("deck", 600), rows("commanders", 12))
        }
    }
}

fun SpellbookCombo.singleMissingResolvedCard(input: SpellbookInput, catalogue: Catalogue): String? {
    if (group !in setOf(SpellbookGroup.INCLUDED, SpellbookGroup.ALMOST_INCLUDED) ||
        status != "OK" || spoiler || commanderLegal != true || hasFlexibleRequirements) return null
    val commanderColors = input.commanders.flatMap { row -> catalogue.find(row.card)?.identity ?: return null }.toSet()
    if (identity.filter { it != 'C' }.any { it.toString() !in commanderColors }) return null
    val available = input.quantities()
    val commanderQuantities = input.commanders.associate { normalized(it.card) to it.quantity }
    val needed = linkedMapOf<String, Pair<String, Int>>()
    val commanderNeeded = linkedMapOf<String, Int>()
    for (ingredient in ingredients) {
        val canonical = catalogue.find(ingredient.name)?.name ?: return null
        val key = normalized(canonical)
        val total = (needed[key]?.second ?: 0) + ingredient.quantity
        if (total > 2_000) return null
        needed[key] = canonical to total
        if (ingredient.mustBeCommander) commanderNeeded[key] = commanderNeeded.getOrDefault(key, 0) + ingredient.quantity
    }
    if (commanderNeeded.any { commanderQuantities.getOrDefault(it.key, 0) < it.value }) return null
    val missing = needed.mapNotNull { (key, row) ->
        val count = row.second - available.getOrDefault(key, 0)
        if (count > 0) row.first to count else null
    }
    return missing.singleOrNull()?.takeIf { it.second == 1 }?.first
}

private fun validProviderName(value: String): Boolean = value.isNotEmpty() && value.toByteArray().size <= 256 &&
    value == value.trim() && value.any { !it.isDigit() } && value.none { it.isISOControl() }
private fun normalized(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFC).lowercase(Locale.ROOT)
