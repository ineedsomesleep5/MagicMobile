package io.magicmobile.android.core

import java.text.Normalizer
import java.util.Locale
import java.util.UUID

/** Optional local authoring data. It is never part of the deck sent to XMage. */
@ConsistentCopyVisibility
data class DeckOrganization private constructor(
    val tags: List<String>,
    val notes: String,
) {
    init {
        require(tags.size <= 24 && notes.toByteArray().size <= 16_384 && '\u0000' !in notes)
        require(tags.all { tag ->
            tag.isNotEmpty() && tag == tag.trim() && tag.toByteArray().size <= 80 && tag.none(Char::isISOControl)
        })
        require(tags.map(::tagKey).toSet().size == tags.size)
    }

    companion object {
        private fun tagKey(tag: String): String = Normalizer.normalize(tag, Normalizer.Form.NFD)
            .replace(Regex("\\p{M}+"), "")
            .lowercase(Locale.ROOT)

        fun create(tags: List<String> = emptyList(), notes: String = ""): DeckOrganization {
            require(tags.size <= 24)
            val seen = mutableSetOf<String>()
            val normalized = tags.mapNotNull { raw ->
                val tag = raw.trim()
                require(tag.isNotEmpty() && tag.toByteArray().size <= 80 && tag.none(Char::isISOControl))
                tag.takeIf { seen.add(tagKey(tag)) }
            }
            return DeckOrganization(normalized, notes)
        }
    }
}

enum class DeckRole(val key: String) {
    RAMP("ramp"),
    CARD_FLOW("cardFlow"),
    INTERACTION("interaction"),
    BOARD_WIPE("boardWipe"),
    PROTECTION("protection"),
    GRAVEYARD_HATE("graveyardHate"),
    RECURSION("recursion"),
    TUTOR("tutor");

    companion object {
        private val byKey = entries.associateBy(DeckRole::key)
        fun fromKey(value: String): DeckRole? = byKey[value]
    }
}

data class RoleSummary(val count: Int, val cardNames: List<String>)

/**
 * Structural, catalogue-backed facts about a deck. This is not an XMage legality result,
 * a deck score, a mana-source estimate, or a simulated playtest.
 */
data class DeckAnalysis(
    val mainCardCount: Int,
    val excludedCardCount: Int,
    val landCount: Int,
    val averageNonlandManaValue: Double?,
    /** Exact printed mana values for known nonlands. */
    val manaCurve: Map<Double, Int>,
    /** UI-friendly 0 through 7+ curve buckets. */
    val manaCurveBins: Map<Int, Int>,
    /** Quantity-weighted printed colors. Multicolor cards appear in each color. */
    val printedColorCounts: Map<String, Int>,
    val knownColorlessCount: Int,
    /** nil means at least one commander's identity is unavailable. */
    val commanderColorIdentity: Set<String>?,
    /** Only curated roles bundled in the catalogue are counted. */
    val roles: Map<DeckRole, RoleSummary>,
    val withoutCuratedRolesCount: Int,
    val unknownNameCount: Int,
    val unknownTypeCount: Int,
    val unknownManaValueCount: Int,
    val unknownColorCount: Int,
    val unknownNames: List<String>,
)

object DeckAnalyzer {
    private val colors = listOf("W", "U", "B", "R", "G")

    fun analyze(deck: Deck, catalogue: Catalogue): DeckAnalysis {
        var accepted = 0
        var excluded = 0
        var lands = 0
        var unknownNames = 0
        var unknownTypes = 0
        var unknownMana = 0
        var unknownColors = 0
        var colorless = 0
        var noCuratedRole = 0
        val unresolved = sortedSetOf<String>()
        val curve = sortedMapOf<Double, Int>()
        val printedColors = colors.associateWith { 0 }.toMutableMap()
        val roleCounts = DeckRole.entries.associateWith { 0 }.toMutableMap()
        val roleCards = DeckRole.entries.associateWith { sortedSetOf<String>() }.toMutableMap()
        var totalManaValue = 0.0
        var totalManaCards = 0

        deck.entries.forEach { row ->
            require(row.quantity > 0)
            if (row.section != "deck") {
                excluded += row.quantity
                return@forEach
            }
            accepted += row.quantity
            val card = catalogue.find(row.name)
            if (card == null) {
                unknownNames += row.quantity
                unknownTypes += row.quantity
                unknownMana += row.quantity
                unknownColors += row.quantity
                noCuratedRole += row.quantity
                unresolved += row.name
                return@forEach
            }

            val types = card.types
            if (types == null) {
                unknownTypes += row.quantity
                if (card.manaValue == null) unknownMana += row.quantity
            } else if ("LAND" in types) {
                lands += row.quantity
            } else {
                val manaValue = card.manaValue
                if (manaValue == null) unknownMana += row.quantity
                else {
                    curve[manaValue] = curve.getOrDefault(manaValue, 0) + row.quantity
                    totalManaValue += manaValue * row.quantity
                    totalManaCards += row.quantity
                }
            }

            val cardColors = card.colors
            if (cardColors == null) unknownColors += row.quantity
            else if (cardColors.isEmpty()) colorless += row.quantity
            else cardColors.forEach { color ->
                if (color in printedColors) printedColors[color] = printedColors.getValue(color) + row.quantity
            }

            val curated = card.roles.orEmpty().mapNotNull(DeckRole::fromKey).distinct()
            if (curated.isEmpty()) noCuratedRole += row.quantity
            curated.forEach { role ->
                roleCounts[role] = roleCounts.getValue(role) + row.quantity
                roleCards.getValue(role) += card.name
            }
        }

        val commanderRows = deck.entries.filter { it.section == "commanders" }
        val commanderIdentity = if (commanderRows.isEmpty()) emptySet() else {
            val identities = commanderRows.map { catalogue.find(it.name)?.identity }
            if (identities.any { it == null }) null else identities.filterNotNull().flatten().toSortedSet()
        }
        val bins = (0..7).associateWith { 0 }.toMutableMap()
        curve.forEach { (manaValue, count) ->
            val bin = manaValue.toInt().coerceAtMost(7)
            bins[bin] = bins.getValue(bin) + count
        }
        val roleSummaries = DeckRole.entries.associateWith { role ->
            RoleSummary(roleCounts.getValue(role), roleCards.getValue(role).toList())
        }
        require(accepted + excluded == deck.entries.sumOf(CardEntry::quantity))
        return DeckAnalysis(
            mainCardCount = accepted,
            excludedCardCount = excluded,
            landCount = lands,
            averageNonlandManaValue = totalManaCards.takeIf { it > 0 }
                ?.let { totalManaValue / it },
            manaCurve = curve,
            manaCurveBins = bins,
            printedColorCounts = printedColors,
            knownColorlessCount = colorless,
            commanderColorIdentity = commanderIdentity,
            roles = roleSummaries,
            withoutCuratedRolesCount = noCuratedRole,
            unknownNameCount = unknownNames,
            unknownTypeCount = unknownTypes,
            unknownManaValueCount = unknownMana,
            unknownColorCount = unknownColors,
            unknownNames = unresolved.toList(),
        )
    }
}

enum class PlayingSection { MAIN, COMMANDERS, COMPANIONS }

data class PlayingCard(val name: String, val quantity: Int, val section: PlayingSection)

/** Card-list identity independent of title, row order, and selected printings. */
@ConsistentCopyVisibility
data class DeckSignature private constructor(val cards: List<PlayingCard>) {
    init {
        require(cards.size <= 2000 && cards.sumOf(PlayingCard::quantity) <= 2000)
        require(cards.all { card ->
            card.name.isNotEmpty() && card.name.toByteArray().size <= 2000 &&
                card.name.none(Char::isISOControl) && card.quantity in 1..2000
        })
        require(cards == cards.sortedWith(compareBy<PlayingCard>({ it.section.ordinal }, { it.name })))
        require(cards.map { it.section to it.name }.toSet().size == cards.size)
    }

    companion object {
        fun canonical(cards: List<PlayingCard>): DeckSignature = DeckSignature(cards.toList())
        fun from(deck: Deck, catalogue: Catalogue): DeckSignature {
            val grouped = mutableMapOf<Pair<PlayingSection, String>, Int>()
            deck.entries.forEach { row ->
                val section = when (row.section) {
                    "deck" -> PlayingSection.MAIN
                    "commanders" -> PlayingSection.COMMANDERS
                    "companions" -> PlayingSection.COMPANIONS
                    else -> null
                } ?: return@forEach
                val canonicalName = catalogue.find(row.name)?.name
                    ?: throw IllegalArgumentException("Unknown compiled card: ${row.name}")
                val key = section to canonicalName
                grouped[key] = Math.addExact(grouped[key] ?: 0, row.quantity)
            }
            val cards = grouped.map { (key, quantity) -> PlayingCard(key.second, quantity, key.first) }
                .sortedWith(compareBy<PlayingCard>({ it.section.ordinal }, { it.name }))
            return DeckSignature(cards)
        }
    }
}

enum class PlaytestEnd { IN_PROGRESS, COMPLETED, LEFT, INTERRUPTED, ENGINE_FAILED }

/**
 * Bounded facts observed from one local XMage session. No hands, opponent decks, draw
 * history, mulligans, mana payments, inferred losses, or fabricated metrics belong here.
 */
data class PlaytestSummary(
    val id: String,
    val matchId: String,
    val seatId: String,
    val deck: DeckSignature,
    val title: String,
    val engineUpstream: String,
    val catalogueHash: String,
    val appBuild: String,
    val aiOpponents: Int,
    val startedAtMillis: Long,
    val observedAtMillis: Long,
    val finishedAtMillis: Long?,
    val end: PlaytestEnd,
    val highestObservedTurn: Int,
    val commanderCasts: Map<String, Int>,
    val won: Boolean?,
    val lastRevision: Long,
    val viewerPlayerId: String?,
) {
    init {
        require(uuid(id) && uuid(matchId) && seatId.isNotBlank() && seatId.toByteArray().size <= 128)
        require(title.toByteArray().size <= 512 && engineUpstream.isNotBlank() && engineUpstream.toByteArray().size <= 128)
        require(catalogueHash.isNotBlank() && catalogueHash.toByteArray().size <= 256)
        require(appBuild.isNotBlank() && appBuild.toByteArray().size <= 128 && aiOpponents in 1..3)
        require(startedAtMillis >= 0 && observedAtMillis >= startedAtMillis &&
            observedAtMillis - startedAtMillis <= MAX_DURATION_MILLIS)
        require(finishedAtMillis == null || finishedAtMillis in startedAtMillis..observedAtMillis)
        require((end == PlaytestEnd.IN_PROGRESS) == (finishedAtMillis == null))
        require(highestObservedTurn in 0..1_000_000 && lastRevision >= -1)
        require(viewerPlayerId == null || uuid(viewerPlayerId))
        require(commanderCasts.size <= 12 && commanderCasts.all { (name, count) ->
            count in 0..1_000_000 && deck.cards.any {
                it.section == PlayingSection.COMMANDERS && it.name == name
            }
        })
        require(end == PlaytestEnd.COMPLETED || won == null)
    }

    val elapsedMillis: Long get() = (finishedAtMillis ?: observedAtMillis) - startedAtMillis

    private companion object {
        const val MAX_DURATION_MILLIS = 365L * 24 * 60 * 60 * 1000
        fun uuid(value: String): Boolean = runCatching {
            UUID.fromString(value).toString().equals(value, ignoreCase = true)
        }.getOrDefault(false)
    }
}

/** Immutable, newest-first local history with the same 100-session bound as iOS. */
@ConsistentCopyVisibility
data class PlaytestHistory private constructor(val summaries: List<PlaytestSummary>) {
    init {
        require(summaries.size <= MAX_GAMES && summaries.map { it.id }.toSet().size == summaries.size)
        require(summaries == summaries.sortedWith(
            compareByDescending<PlaytestSummary> { it.startedAtMillis }.thenBy { it.id }
        ))
    }

    fun record(summary: PlaytestSummary): PlaytestHistory =
        create((summaries.filterNot { it.id == summary.id } + summary)
            .sortedWith(compareByDescending<PlaytestSummary> { it.startedAtMillis }.thenBy { it.id })
            .take(MAX_GAMES))

    fun forDeck(signature: DeckSignature): List<PlaytestSummary> = summaries.filter { it.deck == signature }

    companion object {
        const val MAX_GAMES = 100
        fun create(summaries: List<PlaytestSummary> = emptyList()): PlaytestHistory {
            require(summaries.size <= MAX_GAMES && summaries.map { it.id }.toSet().size == summaries.size)
            return PlaytestHistory(summaries.sortedWith(
                compareByDescending<PlaytestSummary> { it.startedAtMillis }.thenBy { it.id }
            ))
        }
    }
}
