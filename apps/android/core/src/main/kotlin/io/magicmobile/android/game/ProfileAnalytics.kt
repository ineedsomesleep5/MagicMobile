package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.temporal.TemporalAdjusters

// Port of Ranked/ProfileAnalytics.swift: the numbers behind a profile's pictures (record, streaks,
// weeks, commanders, colors, rank over time) and another player's public profile as the server
// sends it. parity/profile-cases.json checks both.

/** Who may open a player's profile. Public by default; the server enforces it (mm_public_profile). */
enum class ProfileVisibility(val raw: String, val title: String, val detail: String) {
    PUBLIC("public", "Public", "Any player can open your profile, with your rank and recent games."),
    FRIENDS("friends", "Friends only", "Only your friends can open your profile."),
    PRIVATE("private", "Private", "Nobody but you can open your profile. Friends still see when you're online.");

    companion object { fun of(raw: String?) = entries.firstOrNull { it.raw == raw } }
}

data class ProfileOpponent(val name: String, val commander: String?, val isAI: Boolean, val hidden: Boolean = false)

/** One finished game as a profile shows it: this phone's own record, or a row from the profile server. */
data class ProfileGame(
    val id: String, val date: Long, val mode: PlayMode, val outcome: RankOutcome, val deckName: String, val commanders: List<String>,
    val colors: List<String>, val opponents: List<ProfileOpponent>, val turns: Int?, val rankDelta: Int? = null, val engineMatchID: String? = null,
) {
    val commander: String? get() = commanders.firstOrNull()
    val vsHuman: Boolean get() = opponents.any { !it.isAI }

    companion object {
        fun of(match: MatchRecord) = ProfileGame(match.id, match.date, match.mode, match.outcome, match.deckName,
            listOfNotNull(match.commander), match.colors, match.opponents.map { ProfileOpponent(it.name, it.commander, it.isAI) },
            match.turns.takeIf { it > 0 }, match.rankChange?.pipDelta, match.engineMatchID)
    }
}

data class ProfileShare(val id: String, val games: Int, val wins: Int) {
    val winRate: Double get() = if (games == 0) 0.0 else wins.toDouble() / games
}

/** A week starting Monday 00:00 UTC (epoch milliseconds). */
data class ProfileWeek(val start: Long, val games: Int, val wins: Int)

/** A ranked standing: ladder step * 4 + pips. */
data class ProfileRankPoint(val date: Long, val points: Int) {
    val position: RankPosition get() = RankPosition.ofPoints(points)
}

data class ProfileSummary(
    val games: Int = 0, val wins: Int = 0, val losses: Int = 0, val draws: Int = 0, val currentStreak: Int = 0, val bestStreak: Int = 0,
    val averageTurns: Double? = null, val weeks: List<ProfileWeek> = emptyList(), val commanders: List<ProfileShare> = emptyList(),
    val colors: List<ProfileShare> = emptyList(), val rankPoints: List<ProfileRankPoint> = emptyList(),
) {
    val winRate: Double get() = if (games == 0) 0.0 else wins.toDouble() / games

    companion object {
        const val WEEK_COUNT = 8
        const val MAX_COMMANDERS = 6
        val COLOR_ORDER = listOf("W", "U", "B", "R", "G")

        /** Monday 00:00 UTC of the week holding `millis`. */
        fun weekStart(millis: Long): Long = LocalDate.ofInstant(Instant.ofEpochMilli(millis), ZoneOffset.UTC)
            .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli()

        /** The last eight weeks, oldest first, all empty. */
        fun emptyWeeks(now: Long): List<ProfileWeek> {
            val current = LocalDate.ofInstant(Instant.ofEpochMilli(weekStart(now)), ZoneOffset.UTC)
            return (WEEK_COUNT - 1 downTo 0).map { back ->
                ProfileWeek(current.minusWeeks(back.toLong()).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli(), 0, 0)
            }
        }

        /** This phone's games, newest first (the record's order). */
        fun of(matches: List<MatchRecord>, now: Long = System.currentTimeMillis()) = of(matches.map(ProfileGame::of), now,
            matches.asReversed().mapNotNull { m -> m.rankChange?.let { ProfileRankPoint(m.date, it.after.points) } })

        /** Games newest first; `rankPoints` is given separately: the rank history is the ranked games' standings,
         *  whatever deck the totals are narrowed to. */
        fun of(list: List<ProfileGame>, now: Long = System.currentTimeMillis(), rankPoints: List<ProfileRankPoint> = emptyList()): ProfileSummary {
            var games = 0; var wins = 0; var losses = 0; var draws = 0; var streak = 0; var best = 0; var turnTotal = 0; var turnGames = 0
            val commanders = LinkedHashMap<String, IntArray>(); val colors = LinkedHashMap<String, IntArray>()
            for (game in list.asReversed()) {
                games++
                val won = game.outcome == RankOutcome.WIN
                when (game.outcome) {
                    RankOutcome.WIN -> { wins++; streak++; best = maxOf(best, streak) }
                    RankOutcome.LOSS -> { losses++; streak = 0 }
                    RankOutcome.DRAW -> { draws++; streak = 0 }
                }
                game.turns?.takeIf { it > 0 }?.let { turnTotal += it; turnGames++ }
                for (commander in game.commanders) commanders.getOrPut(commander) { IntArray(2) }.also { it[0]++; if (won) it[1]++ }
                for (color in game.colors.toSet()) if (color in COLOR_ORDER) colors.getOrPut(color) { IntArray(2) }.also { it[0]++; if (won) it[1]++ }
            }
            val weeks = emptyWeeks(now).toMutableList()
            for (game in list) {
                val start = weekStart(game.date)
                val index = weeks.indexOfFirst { it.start == start }
                if (index >= 0) weeks[index] = weeks[index].let { it.copy(games = it.games + 1, wins = it.wins + if (game.outcome == RankOutcome.WIN) 1 else 0) }
            }
            return ProfileSummary(games, wins, losses, draws, streak, best, if (turnGames == 0) null else turnTotal.toDouble() / turnGames, weeks,
                commanders.map { (id, t) -> ProfileShare(id, t[0], t[1]) }.sortedWith(compareByDescending<ProfileShare> { it.games }.thenBy { it.id }).take(MAX_COMMANDERS),
                COLOR_ORDER.mapNotNull { key -> colors[key]?.let { ProfileShare(key, it[0], it[1]) } }, rankPoints)
        }
    }
}

/** Another player's profile, as mm_public_profile returns it. */
data class PublicProfile(
    val username: String, val restricted: Boolean, val visibility: ProfileVisibility, val relation: String, val online: Boolean?,
    val title: String?, val favoriteCommander: String?, val rank: Rank?, val summary: ProfileSummary, val games: List<ProfileGame>,
) {
    data class Rank(val season: String, val step: Int, val pips: Int, val peakStep: Int, val wins: Int, val losses: Int) {
        /** This season's place, or null when it is from an earlier season. */
        val position: RankPosition? get() = if (season == RankLadder.season(System.currentTimeMillis())) RankPosition.published(step, pips) else null
    }

    val isSelf: Boolean get() = relation == "self"
    val isFriend: Boolean get() = relation == "friend"

    companion object {
        private fun JsonElement?.text(): String? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.contentOrNull
        private fun JsonElement?.number(): Int? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.let { it.intOrNull ?: it.doubleOrNull?.toInt() }
        private fun JsonElement?.flag(): Boolean? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.booleanOrNull
        private fun JsonElement?.rows(): List<JsonObject> = (this as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }

        /** Reads the server's JSON. Missing parts come out empty rather than failing the screen. */
        fun parse(text: String, now: Long = System.currentTimeMillis()): PublicProfile {
            val root = Json.parseToJsonElement(text) as? JsonObject ?: throw IllegalArgumentException("malformed profile")
            val username = root["username"].text() ?: throw IllegalArgumentException("malformed profile")
            val visibility = ProfileVisibility.of(root["visibility"].text()) ?: ProfileVisibility.PUBLIC
            val relation = root["relation"].text() ?: "none"
            if (root["restricted"].flag() == true) return PublicProfile(username, true, visibility, relation, null, null, null, null,
                ProfileSummary(weeks = ProfileSummary.emptyWeeks(now)), emptyList())
            val rank = (root["rank"] as? JsonObject)?.let { r ->
                val step = r["step"].number(); val season = r["season"].text()
                if (step == null || season == null) null else Rank(season, step, r["pips"].number() ?: 0, r["peakStep"].number() ?: step,
                    r["wins"].number() ?: 0, r["losses"].number() ?: 0)
            }
            val stats = root["stats"] as? JsonObject ?: JsonObject(emptyMap())
            fun shares(key: String, id: String) = root[key].rows().mapNotNull { row -> row[id].text()?.let { ProfileShare(it, row["games"].number() ?: 0, row["wins"].number() ?: 0) } }
            val weeks = root["weekly"].rows().mapNotNull { row ->
                row["week"].text()?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                    ?.let { ProfileWeek(it.atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli(), row["games"].number() ?: 0, row["wins"].number() ?: 0) }
            }
            val points = root["rankHistory"].rows().mapNotNull { row ->
                val at = row["at"].text()?.let(::timestamp); val value = row["points"].number()
                if (at == null || value == null) null else ProfileRankPoint(at, value)
            }
            val summary = ProfileSummary(stats["games"].number() ?: 0, stats["wins"].number() ?: 0, stats["losses"].number() ?: 0, stats["draws"].number() ?: 0,
                stats["currentStreak"].number() ?: 0, stats["bestStreak"].number() ?: 0, (stats["avgTurns"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.doubleOrNull,
                weeks.ifEmpty { ProfileSummary.emptyWeeks(now) }, shares("commanders", "name"), shares("colors", "color"), points)
            val games = root["games"].rows().mapNotNull { row ->
                val id = row["id"].text() ?: return@mapNotNull null
                val at = row["playedAt"].text()?.let(::timestamp) ?: return@mapNotNull null
                val mode = PlayMode.entries.firstOrNull { it.raw == row["mode"].text() } ?: return@mapNotNull null
                val outcome = RankOutcome.entries.firstOrNull { it.raw == row["result"].text() } ?: return@mapNotNull null
                ProfileGame(id, at, mode, outcome, row["deckName"].text() ?: "",
                    (row["commanders"] as? JsonArray).orEmpty().mapNotNull { it.text() }, (row["colors"] as? JsonArray).orEmpty().mapNotNull { it.text() },
                    row["opponents"].rows().mapNotNull { o -> o["name"].text()?.let { ProfileOpponent(it, o["commander"].text(), o["ai"].flag() ?: true, o["hidden"].flag() ?: false) } },
                    row["turns"].number())
            }
            return PublicProfile(username, false, visibility, relation, root["online"].flag(), root["title"].text(), root["favoriteCommander"].text(),
                rank, summary, games)
        }

        /** PostgREST timestamps: "2026-10-05T12:30:00+00:00", with or without fractions. */
        fun timestamp(text: String): Long? = runCatching { OffsetDateTime.parse(text).toInstant().toEpochMilli() }.getOrNull()
    }
}

/** A player found by typing the start of a name (mm_search_players). */
data class PlayerSearchResult(
    val username: String, val favoriteCommander: String?, val season: String?, val rankStep: Int?, val pips: Int?,
    val visibility: ProfileVisibility, val relation: String, val online: Boolean?,
) {
    val position: RankPosition? get() =
        if (rankStep == null || season != RankLadder.season(System.currentTimeMillis())) null else RankPosition.published(rankStep, pips ?: 0)

    companion object {
        fun parse(text: String): List<PlayerSearchResult> = (Json.parseToJsonElement(text) as? JsonArray).orEmpty().mapNotNull { element ->
            val row = element as? JsonObject ?: return@mapNotNull null
            fun s(key: String) = (row[key] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.contentOrNull
            fun n(key: String) = (row[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.intOrNull
            val name = s("username") ?: return@mapNotNull null
            PlayerSearchResult(name, s("favorite_commander"), s("season"), n("rank_step"), n("pips"), ProfileVisibility.of(s("visibility")) ?: ProfileVisibility.PUBLIC,
                s("relation") ?: "none", (row["online"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.booleanOrNull)
        }
    }
}

/** What the search field sends: at least two letters, digits or underscores (the server returns nothing otherwise). */
object PlayerSearchRules {
    const val MINIMUM_LENGTH = 2
    const val MAXIMUM_LENGTH = 20

    fun normalized(text: String): String? {
        val trimmed = text.trim()
        return trimmed.takeIf { it.length in MINIMUM_LENGTH..MAXIMUM_LENGTH && it.all { c -> c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '_' } }
    }
}
