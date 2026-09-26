package io.magicmobile.android.studio

import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.game.CardCountText

/**
 * DeckStudioPreflight.swift: an instant, offline Commander quick check while editing, read from the
 * bundled catalogue's colour identity and rules text. It never blocks Play; the installed XMage
 * validator stays authoritative when a game starts.
 *
 * Only the playing boards count (Main, Commander(s), Companion); sideboard and maybeboard stay out.
 * It is deliberately conservative: an unknown commander skips the colour check, partner-style pairs
 * use the union of their identities, and commander eligibility is left to XMage.
 */
class DeckStudioPreflight(draft: NativeDeckDraft, card: (String) -> CardInfo?) {
    enum class Kind(val badge: String) {
        MISSING_COMMANDER("No commander"), OFF_COLOR("Off-color"), DUPLICATE("Duplicate"), UNRESOLVED("Unresolved")
    }

    /** One header chip; `names` are the card names a tap filters the list to. */
    data class Chip(val kind: Kind, val names: Set<String>) {
        val title: String get() = when (kind) {
            Kind.MISSING_COMMANDER -> "No commander"
            Kind.OFF_COLOR -> "Off-color · ${CardCountText.label(names.size)}"
            Kind.DUPLICATE -> "Duplicates · ${CardCountText.label(names.size)}"
            Kind.UNRESOLVED -> "Unresolved · ${CardCountText.label(names.size)}"
        }
    }

    /** Main deck plus commanders, the cards counted toward 100. */
    val count: Int = DeckStudioDraftPresentation.gameCount(draft)
    val target: Int = 100
    /** The commanders' combined identity; null while there is no commander or one is unknown. */
    val identity: Set<String>?
    val chips: List<Chip>
    private val byName: Map<String, List<Kind>>

    init {
        val playing = draft.rows.filter { DeckStudioDraftPresentation.section(it) in playingSections }
        val commanders = playing.filter { DeckStudioDraftPresentation.section(it) == "commanders" }
        identity = if (commanders.isEmpty()) null else {
            val union = HashSet<String>()
            var known = true
            for (row in commanders) {
                val colors = card(row.cardName)?.colorIdentity
                if (colors == null) known = false else union += colors
            }
            if (known) union else null
        }
        val unresolved = playing.filter { card(it.cardName) == null }.mapTo(LinkedHashSet()) { it.cardName }
        val offColor = LinkedHashSet<String>()
        identity?.let { allowed ->
            for (row in playing) {
                if (DeckStudioDraftPresentation.section(row) == "commanders") continue
                val colors = card(row.cardName)?.colorIdentity ?: continue
                if (!allowed.containsAll(colors)) offColor += row.cardName
            }
        }
        // The 100-card deck: a card in both the main deck and the command zone is a duplicate too.
        val totals = LinkedHashMap<String, Int>()
        for (row in playing) if (DeckStudioDraftPresentation.section(row) in setOf("deck", "commanders")) totals.merge(row.cardName, row.quantity, Int::plus)
        val duplicates = LinkedHashSet<String>()
        for ((name, total) in totals) {
            val info = card(name) ?: continue
            if (total > copyLimit(name, info)) duplicates += name
        }
        chips = buildList {
            if (commanders.isEmpty()) add(Chip(Kind.MISSING_COMMANDER, emptySet()))
            if (offColor.isNotEmpty()) add(Chip(Kind.OFF_COLOR, offColor))
            if (duplicates.isNotEmpty()) add(Chip(Kind.DUPLICATE, duplicates))
            if (unresolved.isNotEmpty()) add(Chip(Kind.UNRESOLVED, unresolved))
        }
        val badges = LinkedHashMap<String, MutableList<Kind>>()
        for (chip in chips) for (name in chip.names) badges.getOrPut(name) { ArrayList() } += chip.kind
        byName = badges
    }

    /** Inline badges for a row; boards outside play never carry any. */
    fun issues(row: NativeDeckRow): List<Kind> =
        if (DeckStudioDraftPresentation.section(row) in playingSections) byName[row.cardName] ?: emptyList() else emptyList()

    fun rows(kind: Kind, rows: List<NativeDeckRow>): List<NativeDeckRow> = rows.filter { kind in issues(it) }

    val hasIssues: Boolean get() = chips.isNotEmpty()

    companion object {
        const val label = "Quick check · XMage confirms when you play"
        val playingSections = setOf("deck", "commanders", "companions")
        private val anyNumber = Regex("""a deck can have any number of cards named""", RegexOption.IGNORE_CASE)
        private val upTo = Regex("""a deck can have up to ([a-z]+|[0-9]{1,4}) cards named""", RegexOption.IGNORE_CASE)
        private val words = listOf("one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
            "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty")

        /** Copies a Commander deck may hold: basics and "any number" cards are unlimited, "up to seven" is seven. */
        fun copyLimit(name: String, card: CardInfo?): Int {
            if (name in NativeDeckDraft.basicLandNames || card?.typeLine?.startsWith("Basic ") == true) return Int.MAX_VALUE
            val text = card?.oracleText ?: return 1
            if (anyNumber.containsMatchIn(text)) return Int.MAX_VALUE
            upTo.find(text)?.let { match ->
                val value = match.groupValues[1].lowercase()
                return value.toIntOrNull() ?: (words.indexOf(value).takeIf { it >= 0 }?.plus(1) ?: 1)
            }
            return 1
        }
    }
}

/** Commander-first new decks: legendary creatures and cards whose text says they can be your commander. */
object DeckStudioCommanderSearch {
    fun isCandidate(card: CardInfo): Boolean =
        (card.typeLine?.contains("Legendary", ignoreCase = true) == true && card.types?.contains("CREATURE") == true) ||
            card.oracleText?.contains("can be your commander", ignoreCase = true) == true

    /** Filters before the cap so a later eligible card is never hidden by ineligible matches. */
    fun candidates(catalogue: NativeDeckMetadataCatalogue, query: String, limit: Int = 80): List<CardInfo> {
        if (limit <= 0) return emptyList()
        val text = query.trim()
        val matches = catalogue.cards.filter { card ->
            isCandidate(card) && (text.isEmpty() || card.name.contains(text, ignoreCase = true) || card.oracleText?.contains(text, ignoreCase = true) == true)
        }
        return NativeDeckMetadataCatalogue.ranked(matches, text).take(minOf(limit, 2000))
    }
}
