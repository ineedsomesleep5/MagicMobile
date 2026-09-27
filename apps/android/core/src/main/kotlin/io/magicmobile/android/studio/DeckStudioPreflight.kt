package io.magicmobile.android.studio

import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.game.CardCountText
import java.util.UUID

/**
 * DeckStudioPreflight.swift: a fast, offline quick check of the Commander basics while editing:
 * deck size, a commander, colour identity, singleton copies and cards this build can play. It is
 * advisory only. XMage checks the deck when it is played, and a quick check never blocks Play.
 * Anything it cannot judge (missing metadata, an unknown commander identity, partner or background
 * pairings) is left to XMage rather than reported, so the check errs towards staying quiet.
 */
class DeckStudioPreflight(draft: NativeDeckDraft, card: (String) -> CardInfo?, resolves: ((String) -> Boolean)?) {
    enum class Issue(val title: String, val badge: String) {
        MISSING_COMMANDER("Missing commander", "Missing commander"),
        OFF_IDENTITY("Off-color", "Off-color"),
        DUPLICATE("Duplicates", "Duplicate"),
        UNRESOLVED("Unresolved", "Unresolved"),
    }

    /** Main deck plus commanders; companions and other boards are outside the 100. */
    val count: Int
    val missingCommander: Boolean
    /** Union of the commanders' identities; null when there is no commander or any commander's identity is unknown. */
    val commanderIdentity: Set<String>?
    private val flagged: Map<Issue, Set<UUID>>

    /** The catalogue-backed check: the resolver decides playability when it is loaded, else the catalogue. */
    constructor(draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?, resolver: OnDeviceDeckResolver?) : this(draft, { name -> metadata?.card(name) },
        resolver?.let { value -> { name: String -> value.canonicalCardName(name) != null } } ?: metadata?.let { value -> { name: String -> value.card(name) != null } })

    init {
        val playing = draft.rows.filter { DeckStudioDraftPresentation.section(it) in playingBoards }
        val commanders = playing.filter { DeckStudioDraftPresentation.section(it) == "commanders" }
        count = draft.rows.filter { DeckStudioDraftPresentation.section(it) in setOf("deck", "commanders") }.sumOf { it.quantity }
        missingCommander = commanders.isEmpty()
        commanderIdentity = if (commanders.isEmpty()) null else {
            val union = HashSet<String>()
            var known = true
            for (row in commanders) { val colors = card(row.cardName)?.colorIdentity; if (colors == null) { known = false; break }; union += colors }
            if (known) union else null
        }
        val result = LinkedHashMap<Issue, Set<UUID>>()
        if (resolves != null) result[Issue.UNRESOLVED] = playing.filter { !resolves(it.cardName) }.mapTo(LinkedHashSet()) { it.id }
        commanderIdentity?.let { identity ->
            result[Issue.OFF_IDENTITY] = playing.filter { row ->
                if (DeckStudioDraftPresentation.section(row) == "commanders") return@filter false
                val colors = card(row.cardName)?.colorIdentity ?: return@filter false
                !identity.containsAll(colors)
            }.mapTo(LinkedHashSet()) { it.id }
        }
        // Copies are counted across main, commanders and companions by canonical name.
        val groups = LinkedHashMap<String, Triple<CardInfo, Int, List<UUID>>>()
        for (row in playing) {
            val info = card(row.cardName) ?: continue
            val prior = groups[info.name]
            groups[info.name] = Triple(info, (prior?.second ?: 0) + row.quantity, (prior?.third ?: emptyList()) + row.id)
        }
        result[Issue.DUPLICATE] = groups.values.filter { (info, total) -> copyLimit(info)?.let { total > it } ?: false }.flatMapTo(LinkedHashSet()) { it.third }
        flagged = result.filterValues { it.isNotEmpty() }
    }

    fun rows(issue: Issue): Set<UUID> = flagged[issue] ?: emptySet()
    fun issues(row: UUID): List<Issue> = Issue.entries.filter { flagged[it]?.contains(row) == true }
    val issueCount: Int get() = (if (missingCommander) 1 else 0) + flagged.values.sumOf { it.size }
    /** Chips with something to show, in a fixed order. */
    val activeIssues: List<Issue> get() = Issue.entries.filter { if (it == Issue.MISSING_COMMANDER) missingCommander else rows(it).isNotEmpty() }
    /** Row issues add " · N" with the number of affected rows. */
    fun chipTitle(issue: Issue): String = if (issue == Issue.MISSING_COMMANDER) issue.title else "${issue.title} · ${rows(issue).size}"
    /** e.g. "3 cards to go · 2 issues", "1 card over · No issues found". */
    val summary: String get() = buildList {
        if (count < targetCount) add("${CardCountText.label(targetCount - count)} to go")
        if (count > targetCount) add("${CardCountText.label(count - targetCount)} over")
        add(if (issueCount == 0) "No issues found" else issueCountText(issueCount))
    }.joinToString(" · ")

    companion object {
        const val targetCount = 100
        const val caption = "Quick check · XMage confirms when you play"
        val playingBoards = setOf("deck", "commanders", "companions")
        private val upTo = Regex("""a deck can have up to ([a-z0-9]+) cards named""")
        private val numbers = mapOf("one" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5, "six" to 6, "seven" to 7, "eight" to 8, "nine" to 9, "ten" to 10)

        fun issueCountText(count: Int): String = "$count ${if (count == 1) "issue" else "issues"}"

        /** How many copies a Commander deck may hold; null means any number. */
        fun copyLimit(card: CardInfo): Int? {
            if (card.typeLine?.trim()?.lowercase()?.startsWith("basic ") == true) return null
            val text = (card.oracleText ?: "").lowercase()
            if ("a deck can have any number of cards named" in text) return null
            upTo.find(text)?.let { match ->
                val value = match.groupValues[1]
                val limit = numbers[value] ?: value.toIntOrNull()
                if (limit != null && limit > 0) return limit
            }
            return 1
        }
    }
}

/**
 * What the Cards list is narrowed to (DeckStudioListFilter in DeckStudioPreflight.swift): one
 * quick-check issue, or the cards XMage named (Fix deck). Both read "Showing only: …" with Show all,
 * and clear once nothing matches.
 */
sealed class DeckStudioListFilter {
    abstract val label: String
    val title: String get() = DeckStudioPlayText.showingOnly(label)
    abstract fun rows(preflight: DeckStudioPreflight, draft: NativeDeckDraft, canonical: (String) -> String?): Set<UUID>

    data class QuickCheck(val issue: DeckStudioPreflight.Issue) : DeckStudioListFilter() {
        override val label: String get() = issue.badge
        override fun rows(preflight: DeckStudioPreflight, draft: NativeDeckDraft, canonical: (String) -> String?) = preflight.rows(issue)
    }

    data class NeedsFixes(val cards: List<String>) : DeckStudioListFilter() {
        override val label: String get() = DeckStudioPlayText.needsFixes
        override fun rows(preflight: DeckStudioPreflight, draft: NativeDeckDraft, canonical: (String) -> String?) =
            DeckStudioPlayRules.fixRows(draft.rows, cards, canonical)
    }
}
