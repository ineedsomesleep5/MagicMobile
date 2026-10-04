package io.magicmobile.android.game

import io.magicmobile.android.core.CardEntry
import io.magicmobile.android.core.Deck
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneOffset
import java.time.format.TextStyle
import java.util.Locale
import java.util.UUID

// Ports of Ranked/*.swift: Commander brackets, the ranked ladder and seasons, the AI deck pools,
// the profile's stats and achievements, and the ranked queue. parity/ranked-cases.json checks both.

/** Wizards' Commander Brackets (beta), checked from a decklist (CommanderBrackets.swift). */
enum class CommanderBracket(val level: Int, val label: String, val blurb: String) {
    EXHIBITION(1, "Exhibition", "Theme first. Games are slow and win in style."),
    CORE(2, "Core", "Like a modern precon. No Game Changers, no fast combos."),
    UPGRADED(3, "Upgraded", "Tuned decks with up to three Game Changers."),
    OPTIMIZED(4, "Optimized", "Fast, lethal decks. Anything legal goes."),
    CEDH(5, "cEDH", "Competitive Commander. Built to win as fast as possible.");

    /** "Bracket 3 · Upgraded" */
    val title: String get() = "Bracket $level · $label"

    companion object {
        fun of(level: Int): CommanderBracket? = entries.firstOrNull { it.level == level }
        fun clamping(level: Int): CommanderBracket = of(level.coerceIn(1, 5)) ?: CORE
    }
}

data class BracketCombo(val cards: List<String>, val manaValue: Int, val early: Boolean)

/** The card lists the bracket check reads: commander-brackets.json (scripts/ranked/build_bracket_rules.py). */
class BracketRules(
    val gameChangers: Set<String>, val massLandDenial: Set<String>, val extraTurns: Set<String>,
    val combos: List<BracketCombo>, val chainedExtraTurns: Int = 3,
) {
    private fun names(cards: List<String>): Set<String> = buildSet {
        for (card in cards) {
            add(card)
            val front = card.substringBefore(" // ")
            if (front != card) add(front)
        }
    }

    fun evaluate(cardNames: List<String>): BracketReport {
        val cards = names(cardNames)
        val changers = cards.filter { it in gameChangers }.sorted()
        val landDenial = cards.filter { it in massLandDenial }.sorted()
        val turns = cards.filter { it in extraTurns }.sorted()
        val present = combos.filter { cards.containsAll(it.cards) }
        var minimum = CommanderBracket.CORE
        if (changers.isNotEmpty()) minimum = maxOf(minimum, if (changers.size <= 3) CommanderBracket.UPGRADED else CommanderBracket.OPTIMIZED)
        if (landDenial.isNotEmpty()) minimum = CommanderBracket.OPTIMIZED
        if (turns.size >= chainedExtraTurns) minimum = CommanderBracket.OPTIMIZED
        for (combo in present) minimum = maxOf(minimum, if (combo.early) CommanderBracket.OPTIMIZED else CommanderBracket.UPGRADED)
        return BracketReport(minimum, changers, landDenial, turns,
            present.filter { !it.early }.map { it.cards }, present.filter { it.early }.map { it.cards })
    }

    /** The deck as played: commander and main deck (sideboard and maybeboard stay out). */
    fun evaluate(deck: Deck): BracketReport =
        evaluate(deck.entries.filter { it.section == "deck" || it.section == "commanders" }.map { it.name })

    companion object {
        val EMPTY = BracketRules(emptySet(), emptySet(), emptySet(), emptyList())

        fun parse(text: String): BracketRules {
            val root = Json.parseToJsonElement(text).jsonObject
            fun list(key: String) = root[key]!!.jsonArray.map { it.jsonPrimitive.content }.toSet()
            return BracketRules(list("gameChangers"), list("massLandDenial"), list("extraTurns"),
                root["combos"]!!.jsonArray.map { item ->
                    val row = item.jsonObject
                    BracketCombo(row["cards"]!!.jsonArray.map { it.jsonPrimitive.content }, row["manaValue"]!!.jsonPrimitive.int,
                        row["early"]!!.jsonPrimitive.boolean)
                }, root["chainedExtraTurns"]!!.jsonPrimitive.int)
        }
    }
}

data class BracketReport(
    val minimum: CommanderBracket, val gameChangers: List<String>, val massLandDenial: List<String>,
    val extraTurns: List<String>, val combos: List<List<String>>, val earlyCombos: List<List<String>>,
) {
    /** One line per reason the deck sits above Core. */
    val reasons: List<String> get() = buildList {
        if (gameChangers.isNotEmpty()) add("${gameChangers.size} Game Changers: ${gameChangers.joinToString(", ")}")
        if (massLandDenial.isNotEmpty()) add("Mass land denial: ${massLandDenial.joinToString(", ")}")
        if (minimum == CommanderBracket.OPTIMIZED && extraTurns.size >= 3) add("Chains extra turns: ${extraTurns.joinToString(", ")}")
        earlyCombos.forEach { add("Early two-card combo: ${it.joinToString(" + ")}") }
        combos.forEach { add("Two-card combo: ${it.joinToString(" + ")}") }
    }
}

/** The player's own label for a deck: it may raise the bracket, or lower a Core list to Exhibition. */
object DeckBracketPreference {
    const val KEY = "magicmobile.ranked.deckBrackets"

    fun effective(minimum: CommanderBracket, declared: CommanderBracket?): CommanderBracket = when {
        declared == null -> minimum
        declared == CommanderBracket.EXHIBITION && minimum == CommanderBracket.CORE -> CommanderBracket.EXHIBITION
        else -> maxOf(declared, minimum)
    }

    fun choices(minimum: CommanderBracket): List<CommanderBracket> =
        CommanderBracket.entries.filter { it >= minimum || (it == CommanderBracket.EXHIBITION && minimum == CommanderBracket.CORE) }
}

// MARK: - Ladder (RankLadder.swift)

enum class RankTier(val label: String, val opponentBrackets: IntRange, val aiSkill: Int) {
    BRONZE("Bronze", 1..2, 2), SILVER("Silver", 2..2, 3), GOLD("Gold", 2..3, 4),
    PLATINUM("Platinum", 3..3, 5), DIAMOND("Diamond", 3..4, 6), MYTHIC("Mythic", 4..4, 7);

    val key: String get() = name.lowercase()
    /** The strongest deck you may queue with here. */
    val maxDeckBracket: Int get() = opponentBrackets.last
    /** The badge art: tavern_rank_<tier> (from the iOS asset catalogue). */
    val drawableName: String get() = "tavern_rank_$key"

    companion object { fun of(key: String): RankTier? = entries.firstOrNull { it.key == key } }
}

@Serializable
data class RankPosition(val tier: RankTier, val division: Int, val pips: Int) : Comparable<RankPosition> {
    val step: Int get() = if (tier == RankTier.MYTHIC) MYTHIC_STEP else tier.ordinal * DIVISIONS + (DIVISIONS - division)
    val points: Int get() = step * PIPS_PER_DIVISION + pips
    val divisionNumeral: String get() = listOf("", "I", "II", "III", "IV")[division.coerceIn(0, 4)]
    val title: String get() = if (tier == RankTier.MYTHIC) tier.label else "${tier.label} $divisionNumeral"
    /** The AI's bracket here: the tier's lower bracket in divisions IV–III, the upper in II–I. */
    val opponentBracket: Int get() = if (division >= 3) tier.opponentBrackets.first else tier.opponentBrackets.last

    override fun compareTo(other: RankPosition) = points.compareTo(other.points)

    companion object {
        const val PIPS_PER_DIVISION = 4
        const val DIVISIONS = 4
        const val MYTHIC_STEP = 20
        val START = make(RankTier.BRONZE, 4, 0)

        fun make(tier: RankTier, division: Int, pips: Int) = RankPosition(tier,
            if (tier == RankTier.MYTHIC) 0 else division.coerceIn(1, 4),
            maxOf(0, if (tier == RankTier.MYTHIC) pips else pips.coerceAtMost(PIPS_PER_DIVISION - 1)))

        fun ofPoints(points: Int): RankPosition {
            val p = maxOf(0, points); val step = p / PIPS_PER_DIVISION
            return if (step >= MYTHIC_STEP) make(RankTier.MYTHIC, 0, p - MYTHIC_STEP * PIPS_PER_DIVISION)
            else make(RankTier.entries[step / DIVISIONS], DIVISIONS - step % DIVISIONS, p % PIPS_PER_DIVISION)
        }

        fun atStep(step: Int) = ofPoints(step.coerceIn(0, MYTHIC_STEP) * PIPS_PER_DIVISION)

        /** A standing as the profile server keeps it. */
        fun published(step: Int, pips: Int): RankPosition { val base = atStep(step); return make(base.tier, base.division, pips) }
    }
}

enum class RankOutcome(val raw: String) { WIN("win"), LOSS("loss"), DRAW("draw") }

enum class RankBonus(val raw: String) { STREAK("streak"), UNDERDOG("underdog") }

enum class RankChangeKind(val raw: String) { NONE("none"), PIP_UP("pipUp"), PIP_DOWN("pipDown"), DIVISION_UP("divisionUp"),
    DIVISION_DOWN("divisionDown"), TIER_UP("tierUp"), TIER_DOWN("tierDown") }

@Serializable
data class RankChange(val outcome: RankOutcome, val before: RankPosition, val after: RankPosition, val bonuses: List<RankBonus>) {
    val pipDelta: Int get() = after.points - before.points
    val kind: RankChangeKind get() = when {
        after.tier != before.tier -> if (after.tier > before.tier) RankChangeKind.TIER_UP else RankChangeKind.TIER_DOWN
        after.division != before.division -> if (after.division < before.division) RankChangeKind.DIVISION_UP else RankChangeKind.DIVISION_DOWN
        after.pips != before.pips -> if (after.pips > before.pips) RankChangeKind.PIP_UP else RankChangeKind.PIP_DOWN
        else -> RankChangeKind.NONE
    }
    val isMilestone: Boolean get() = kind in setOf(RankChangeKind.DIVISION_UP, RankChangeKind.DIVISION_DOWN, RankChangeKind.TIER_UP, RankChangeKind.TIER_DOWN)
}

@Serializable
data class SeasonRecord(val season: String, val final: RankPosition, val peak: RankPosition, val wins: Int, val losses: Int)

@Serializable
data class RankState(
    val season: String, val position: RankPosition, val peak: RankPosition,
    val wins: Int = 0, val losses: Int = 0, val draws: Int = 0, val winStreak: Int = 0,
    val history: List<SeasonRecord> = emptyList(),
) {
    companion object { fun fresh(season: String) = RankState(season, RankPosition.START, RankPosition.START) }
}

object RankLadder {
    /** Seasons are calendar months in UTC: "2026-10". */
    fun season(millis: Long): String = YearMonth.from(Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC)).toString()

    fun seasonEnd(season: String): Long? = runCatching {
        YearMonth.parse(season).plusMonths(1).atDay(1).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    }.getOrNull()

    /** "October 2026" */
    fun seasonName(season: String): String = runCatching {
        val month = YearMonth.parse(season)
        "${month.month.getDisplayName(TextStyle.FULL, Locale.getDefault())} ${month.year}"
    }.getOrDefault(season)

    /** A new month: last season goes into history and you drop one tier (Mythic to Diamond IV). */
    fun rollover(state: RankState, season: String): RankState {
        if (state.season == season) return state
        val played = state.wins + state.losses + state.draws > 0
        val history = (if (played) listOf(SeasonRecord(state.season, state.position, state.peak, state.wins, state.losses)) else emptyList()) + state.history
        val position = RankPosition.atStep(state.position.step - RankPosition.DIVISIONS)
        return RankState(season, position, position, history = history.take(24))
    }

    fun apply(outcome: RankOutcome, state: RankState, deckBracket: Int): Pair<RankState, RankChange> {
        val bonuses = mutableListOf<RankBonus>()
        var delta = 0
        var wins = state.wins; var losses = state.losses; var draws = state.draws; var streak = state.winStreak
        when (outcome) {
            RankOutcome.WIN -> {
                wins++; streak++; delta = 1
                if (state.position.tier < RankTier.GOLD && streak >= 3) { delta++; bonuses += RankBonus.STREAK }
                if (deckBracket < state.position.tier.opponentBrackets.first) { delta++; bonuses += RankBonus.UNDERDOG }
            }
            RankOutcome.LOSS -> { losses++; streak = 0; delta = -1 }
            RankOutcome.DRAW -> { draws++; streak = 0 }
        }
        val position = RankPosition.ofPoints(state.position.points + delta)
        val next = state.copy(position = position, peak = maxOf(state.peak, position), wins = wins, losses = losses, draws = draws, winStreak = streak)
        return next to RankChange(outcome, state.position, position, bonuses)
    }
}

// MARK: - AI decks (AIDeckPool.swift)

data class AIDeck(val id: String, val name: String, val subtitle: String, val colors: String, val commander: String,
                  val bracket: CommanderBracket, val deck: Deck) {
    /** The setup screen's deck ID when a player picks one of these decks for themselves. */
    val playerDeckID: String get() = "included:$id"
}

object AIDeckPool {
    /** ai-decks.json (scripts/ranked/build_ai_decks.py). */
    fun parse(text: String): List<AIDeck> = Json.parseToJsonElement(text).jsonObject["decks"]!!.jsonArray.map { item ->
        val row = item.jsonObject
        fun s(key: String) = row[key]!!.jsonPrimitive.content
        AIDeck(s("id"), s("name"), s("subtitle"), s("colors"), s("commander"), CommanderBracket.clamping(row["bracket"]!!.jsonPrimitive.int),
            Deck(s("name"), row["entries"]!!.jsonArray.map {
                val e = it.jsonObject
                CardEntry(e["name"]!!.jsonPrimitive.content, e["quantity"]!!.jsonPrimitive.int,
                    if (e["section"]!!.jsonPrimitive.content == "commander") "commanders" else "deck")
            }))
    }

    /** The pool for a bracket. cEDH borrows Optimized; an empty bracket borrows its nearest neighbour. */
    fun pool(bracket: Int, decks: List<AIDeck>): List<AIDeck> {
        val wanted = bracket.coerceIn(1, 4)
        for (distance in 0..3) for (candidate in listOf(wanted - distance, wanted + distance)) {
            if (candidate !in 1..4) continue
            val found = decks.filter { it.bracket.level == candidate }
            if (found.isNotEmpty()) return found
        }
        return decks
    }

    fun pick(bracket: Int, avoidingCommander: String?, recent: List<String>, decks: List<AIDeck>,
             roll: (Int) -> Int = { (0 until it).random() }): AIDeck? {
        var candidates = pool(bracket, decks)
        if (avoidingCommander != null && candidates.any { it.commander != avoidingCommander }) candidates = candidates.filter { it.commander != avoidingCommander }
        val fresh = candidates.filter { it.id !in recent }
        if (fresh.isNotEmpty()) candidates = fresh
        if (candidates.isEmpty()) return null
        return candidates[roll(candidates.size).coerceIn(0, candidates.size - 1)]
    }
}

// MARK: - Profile (PlayerRecord.swift)

enum class PlayMode(val raw: String) { QUICK("quick"), RANKED("ranked"), CASUAL("casual") }

@Serializable
data class MatchOpponent(val name: String, val commander: String? = null, val isAI: Boolean)

@Serializable
data class MatchRecord(
    val id: String = UUID.randomUUID().toString(), val date: Long, val mode: PlayMode, val opponents: List<MatchOpponent>,
    val opponentBracket: Int? = null, val aiSkill: Int? = null, val deckID: String, val deckName: String, val commander: String? = null,
    val colors: List<String> = emptyList(), val deckBracket: Int, val outcome: RankOutcome, val turns: Int,
    val rankChange: RankChange? = null, val season: String? = null,
) {
    val vsHuman: Boolean get() = opponents.any { !it.isAI }
}

data class StatsLine(val id: String, val label: String, val detail: String?, val games: Int, val wins: Int) {
    val winRate: Double get() = if (games == 0) 0.0 else wins.toDouble() / games
}

class PlayerStats(matches: List<MatchRecord>) {
    var games = 0; private set
    var wins = 0; private set
    var losses = 0; private set
    var draws = 0; private set
    var averageTurns: Double? = null; private set
    var currentStreak = 0; private set
    var bestStreak = 0; private set
    val decks: List<StatsLine>
    val commanders: List<StatsLine>
    val colors: List<StatsLine>
    val winRate: Double get() = if (games == 0) 0.0 else wins.toDouble() / games

    init {
        data class Tally(val label: String, val detail: String?, var games: Int = 0, var wins: Int = 0)
        val deckTally = LinkedHashMap<String, Tally>(); val commanderTally = LinkedHashMap<String, Tally>(); val colorTally = LinkedHashMap<String, Tally>()
        var turnTotal = 0; var turnGames = 0; var streak = 0
        // The record keeps the newest game first; streaks read oldest first.
        for (match in matches.asReversed()) {
            games++
            val won = match.outcome == RankOutcome.WIN
            when (match.outcome) {
                RankOutcome.WIN -> { wins++; streak++; bestStreak = maxOf(bestStreak, streak) }
                RankOutcome.LOSS -> { losses++; streak = 0 }
                RankOutcome.DRAW -> { draws++; streak = 0 }
            }
            if (match.turns > 0) { turnTotal += match.turns; turnGames++ }
            deckTally.getOrPut(match.deckID) { Tally(match.deckName, match.commander) }.also { it.games++; if (won) it.wins++ }
            match.commander?.let { c -> commanderTally.getOrPut(c) { Tally(c, null) }.also { it.games++; if (won) it.wins++ } }
            match.colors.forEach { c -> colorTally.getOrPut(c) { Tally(colorName(c), null) }.also { it.games++; if (won) it.wins++ } }
        }
        currentStreak = streak
        averageTurns = if (turnGames == 0) null else turnTotal.toDouble() / turnGames
        val order = compareByDescending<StatsLine> { it.games }.thenBy { it.label }
        decks = deckTally.map { (k, t) -> StatsLine(k, t.label, t.detail, t.games, t.wins) }.sortedWith(order)
        commanders = commanderTally.map { (k, t) -> StatsLine(k, t.label, null, t.games, t.wins) }.sortedWith(order)
        colors = listOf("W", "U", "B", "R", "G").mapNotNull { c -> colorTally[c]?.let { StatsLine(c, it.label, null, it.games, it.wins) } }
    }

    companion object {
        fun colorName(symbol: String) = when (symbol) { "W" -> "White"; "U" -> "Blue"; "B" -> "Black"; "R" -> "Red"; "G" -> "Green"; else -> symbol }

        /** A commander's colors from its mana cost ("{2}{R}{R}" -> [R]), hybrid symbols included. */
        fun colors(manaCost: String?): List<String> {
            if (manaCost == null) return emptyList()
            val found = manaCost.uppercase().filter { it in "WUBRG" }.map { it.toString() }.toSet()
            return listOf("W", "U", "B", "R", "G").filter { it in found }
        }
    }
}

enum class Achievement(val title: String, val detail: String) {
    FIRST_WIN("Rising Star", "Win your first game."),
    FIRST_RANKED_WIN("Contender", "Win a ranked match."),
    SILVER("Silver Blade", "Reach Silver."),
    GOLD("Gold Champion", "Reach Gold."),
    PLATINUM("Platinum Warden", "Reach Platinum."),
    DIAMOND("Diamond Duelist", "Reach Diamond."),
    MYTHIC("Mythic Legend", "Reach Mythic."),
    STREAK5("Unstoppable", "Win five games in a row."),
    VETERAN("Tavern Veteran", "Play 50 games."),
    PRISMATIC("Prismatic", "Win with a commander of each color."),
    GIANT_SLAYER("Giant Slayer", "Win a ranked match with a deck below the tier's bracket."),
    QUICK_DRAW("Quick Draw", "Win 10 Quick Matches."),
    HUMAN_WIN("Duelist", "Beat another player online.");

    companion object {
        fun unlocked(matches: List<MatchRecord>, rank: RankState): Set<Achievement> = buildSet {
            val wins = matches.filter { it.outcome == RankOutcome.WIN }
            if (wins.isNotEmpty()) add(FIRST_WIN)
            if (wins.any { it.mode == PlayMode.RANKED }) add(FIRST_RANKED_WIN)
            if (wins.any { it.mode != PlayMode.QUICK && it.vsHuman }) add(HUMAN_WIN)
            val best = (listOf(rank.peak) + rank.history.map { it.peak }).max()
            listOf(RankTier.SILVER to SILVER, RankTier.GOLD to GOLD, RankTier.PLATINUM to PLATINUM, RankTier.DIAMOND to DIAMOND, RankTier.MYTHIC to MYTHIC)
                .forEach { (tier, a) -> if (best.tier >= tier) add(a) }
            if (PlayerStats(matches).bestStreak >= 5) add(STREAK5)
            if (matches.size >= 50) add(VETERAN)
            if (wins.flatMap { it.colors }.toSet().containsAll(listOf("W", "U", "B", "R", "G"))) add(PRISMATIC)
            if (wins.any { it.rankChange?.bonuses?.contains(RankBonus.UNDERDOG) == true }) add(GIANT_SLAYER)
            if (wins.count { it.mode == PlayMode.QUICK } >= 10) add(QUICK_DRAW)
        }
    }
}

/** The profile file: ranked standing, match history, title and favorite commander (PlayerRecordStore). */
@Serializable
data class PlayerRecordFile(
    val rank: RankState, val matches: List<MatchRecord> = emptyList(), val title: Achievement? = null,
    val favoriteCommander: String? = null, val recentAIDecks: List<String> = emptyList(),
) {
    /** Records one finished game; a ranked game moves the ladder. */
    fun recording(now: Long, mode: PlayMode, outcome: RankOutcome, opponents: List<MatchOpponent>, opponentBracket: Int?, aiSkill: Int?,
                  deckID: String, deckName: String, commander: String?, colors: List<String>, deckBracket: Int, turns: Int,
                  aiDeckID: String? = null): Pair<PlayerRecordFile, RankChange?> {
        var rank = RankLadder.rollover(rank, RankLadder.season(now))
        var change: RankChange? = null
        if (mode == PlayMode.RANKED) { val (next, c) = RankLadder.apply(outcome, rank, deckBracket); rank = next; change = c }
        val match = MatchRecord(date = now, mode = mode, opponents = opponents, opponentBracket = opponentBracket, aiSkill = aiSkill,
            deckID = deckID, deckName = deckName, commander = commander, colors = colors, deckBracket = deckBracket, outcome = outcome,
            turns = turns, rankChange = change, season = if (mode == PlayMode.RANKED) rank.season else null)
        val recent = if (aiDeckID == null) recentAIDecks else (listOf(aiDeckID) + recentAIDecks.filter { it != aiDeckID }).take(4)
        return copy(rank = rank, matches = (listOf(match) + matches).take(MAX_MATCHES), recentAIDecks = recent) to change
    }

    companion object {
        const val MAX_MATCHES = 300
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }
}

// MARK: - Ranked queue (RankedQueue.swift)

data class RankedTicket(val ticket: String?, val status: String, val matchId: String?, val role: String?,
                        val tableCode: String?, val opponent: String?, val opponentStep: Int?) {
    val isMatched: Boolean get() = status == "matched" && matchId != null
    val isHost: Boolean get() = role == "host"

    companion object {
        fun parse(value: JsonObject): RankedTicket {
            fun s(key: String) = value[key]?.jsonPrimitive?.takeIf { it.isString }?.content
            return RankedTicket(s("ticket"), s("status") ?: "cancelled", s("matchId"), s("role"), s("tableCode"), s("opponent"),
                value["opponentStep"]?.jsonPrimitive?.content?.toIntOrNull())
        }
    }
}

interface RankedQueueService {
    suspend fun enqueue(protocol: String, rankStep: Int, deckBracket: Int): RankedTicket
    suspend fun poll(ticket: String): RankedTicket
    suspend fun cancel(ticket: String): RankedTicket
    suspend fun setTable(match: String, code: String)
    suspend fun report(match: String, outcome: RankOutcome)
}

sealed interface RankedSearch {
    data class Human(val ticket: RankedTicket) : RankedSearch
    data object AI : RankedSearch
    data object Cancelled : RankedSearch
}

/** Searches for a person for a while; an AI at your tier takes the seat when nobody is searching. */
class RankedMatchmaker(var service: RankedQueueService?, private val sleep: suspend (Long) -> Unit = { delay(it) },
                       private val clock: () -> Long = System::currentTimeMillis) {
    sealed interface Phase {
        data object Idle : Phase
        data class Searching(val since: Long) : Phase
        data class Matched(val ticket: RankedTicket) : Phase
    }

    var phase: Phase = Phase.Idle; private set
    var onPhase: ((Phase) -> Unit)? = null
    @Volatile private var cancelled = false
    @Volatile private var playAINow = false
    private var ticket: String? = null

    val isSearching: Boolean get() = phase != Phase.Idle

    private fun set(next: Phase) { phase = next; onPhase?.invoke(next) }

    suspend fun search(protocol: String, rankStep: Int, deckBracket: Int): RankedSearch {
        val service = service ?: return RankedSearch.AI
        if (phase != Phase.Idle) return RankedSearch.AI
        cancelled = false; playAINow = false
        val started = clock()
        set(Phase.Searching(started))
        try {
            var current = service.enqueue(protocol, rankStep, deckBracket)
            ticket = current.ticket
            while (!current.isMatched) {
                if (cancelled || playAINow || clock() - started >= SEARCH_MILLIS) {
                    val id = ticket ?: return done(if (cancelled) RankedSearch.Cancelled else RankedSearch.AI)
                    val final = service.cancel(id)
                    if (final.isMatched && !cancelled) { current = final; break }
                    if (final.isMatched) final.matchId?.let { runCatching { service.report(it, RankOutcome.LOSS) } }
                    ticket = null
                    return done(if (cancelled) RankedSearch.Cancelled else RankedSearch.AI)
                }
                sleep(2000)
                current = service.poll(ticket ?: return done(RankedSearch.AI))
            }
            set(Phase.Matched(current))
            if (current.isHost) return RankedSearch.Human(current)
            val waitStarted = clock()
            while (current.tableCode == null) {
                if (cancelled) return done(RankedSearch.Cancelled)
                if (clock() - waitStarted >= TABLE_CODE_MILLIS) return done(RankedSearch.AI)
                sleep(1500)
                current = service.poll(ticket ?: return done(RankedSearch.AI))
                set(Phase.Matched(current))
            }
            return RankedSearch.Human(current)
        } catch (e: CancellationException) {
            set(Phase.Idle); throw e
        } catch (e: Exception) {
            return done(if (cancelled) RankedSearch.Cancelled else RankedSearch.AI)
        }
    }

    private fun done(result: RankedSearch): RankedSearch { set(Phase.Idle); return result }

    fun cancel() { cancelled = true }
    fun skipToAI() { playAINow = true }
    fun finish() { set(Phase.Idle); ticket = null }

    suspend fun shareTable(match: String, code: String) { runCatching { service?.setTable(match, code) } }
    suspend fun report(match: String, outcome: RankOutcome) { runCatching { service?.report(match, outcome) } }

    companion object {
        const val SEARCH_MILLIS = 40_000L
        const val TABLE_CODE_MILLIS = 30_000L
    }
}
