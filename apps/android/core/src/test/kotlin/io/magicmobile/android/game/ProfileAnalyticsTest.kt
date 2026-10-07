package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** profile-cases.json: the numbers behind a profile's pictures and a public profile as the server sends it (iOS ProfileAnalyticsTests.swift). */
class ProfileAnalyticsTest {
    private val repo = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory }
    private val root = Json.parseToJsonElement(File(repo, "apps/android/core/src/test/resources/parity/profile-cases.json").readText()).jsonObject

    private fun millis(text: String) = Instant.parse(text).toEpochMilli()
    private fun day(start: Long) = LocalDate.ofInstant(Instant.ofEpochMilli(start), ZoneOffset.UTC).toString()
    private fun JsonObject.str(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
    private fun JsonObject.int(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.intOrNull
    private fun JsonObject.bool(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.booleanOrNull
    private fun JsonObject.rows(key: String) = (this[key] as? JsonArray).orEmpty().map { it.jsonObject }

    @Test fun summaries() {
        for (item in root.rows("summaries")) {
            val name = item.str("name")
            val points = ArrayList<ProfileRankPoint>()
            val games = item.rows("games").map { row ->
                val at = millis(row.str("at")!!)
                row.int("rankAfter")?.let { points.add(0, ProfileRankPoint(at, it)) }
                ProfileGame(row.str("id")!!, at, PlayMode.entries.first { it.raw == row.str("mode") }, RankOutcome.entries.first { it.raw == row.str("result") }, "",
                    (row["commanders"] as? JsonArray).orEmpty().map { it.jsonPrimitive.content }, (row["colors"] as? JsonArray).orEmpty().map { it.jsonPrimitive.content },
                    emptyList(), row.int("turns")?.takeIf { it > 0 })
            }
            val expect = item["expect"]!!.jsonObject
            val summary = ProfileSummary.of(games, millis(item.str("now")!!), points)
            assertEquals(name, expect.int("games"), summary.games)
            assertEquals(name, expect.int("wins"), summary.wins)
            assertEquals(name, expect.int("losses"), summary.losses)
            assertEquals(name, expect.int("draws"), summary.draws)
            assertEquals(name, expect.int("currentStreak"), summary.currentStreak)
            assertEquals(name, expect.int("bestStreak"), summary.bestStreak)
            val average = (expect["averageTurns"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.doubleOrNull
            if (average != null) assertEquals(name, average, summary.averageTurns!!, 1e-9) else assertNull(name, summary.averageTurns)
            val weeks = expect.rows("weeks")
            assertEquals(name, ProfileSummary.WEEK_COUNT, summary.weeks.size)
            assertEquals(name, weeks.map { it.str("start") }, summary.weeks.map { day(it.start) })
            assertEquals(name, weeks.map { it.int("games") }, summary.weeks.map { it.games })
            assertEquals(name, weeks.map { it.int("wins") }, summary.weeks.map { it.wins })
            for (kind in listOf("commanders", "colors")) {
                val wanted = expect.rows(kind)
                val actual = if (kind == "commanders") summary.commanders else summary.colors
                assertEquals("$name $kind", wanted.map { it.str("id") }, actual.map { it.id })
                assertEquals("$name $kind", wanted.map { it.int("games") }, actual.map { it.games })
                assertEquals("$name $kind", wanted.map { it.int("wins") }, actual.map { it.wins })
            }
            assertEquals(name, (expect["rankPoints"] as JsonArray).map { it.jsonPrimitive.int() }, summary.rankPoints.map { it.points })
        }
    }

    private fun JsonPrimitive.int() = content.toInt()

    @Test fun summaryFromMatchRecordsFollowsTheRecordsRankChanges() {
        fun record(at: String, outcome: RankOutcome, after: Int?) = MatchRecord(date = millis(at), mode = if (after == null) PlayMode.QUICK else PlayMode.RANKED, opponents = emptyList(),
            deckID = "d", deckName = "Deck", commander = "Krenko, Mob Boss", colors = listOf("R"), deckBracket = 2, outcome = outcome, turns = 7,
            rankChange = after?.let { RankChange(outcome, RankPosition.ofPoints(maxOf(0, it - 1)), RankPosition.ofPoints(it), emptyList()) })
        val summary = ProfileSummary.of(listOf(record("2026-10-06T10:00:00Z", RankOutcome.WIN, 30), record("2026-10-05T10:00:00Z", RankOutcome.LOSS, 29),
            record("2026-10-04T10:00:00Z", RankOutcome.WIN, null)), millis("2026-10-07T12:00:00Z"))
        assertEquals(listOf(29, 30), summary.rankPoints.map { it.points })
        assertEquals(listOf("Krenko, Mob Boss"), summary.commanders.map { it.id })
        assertEquals(1, summary.currentStreak)
        assertEquals(1, ProfileGame.of(record("2026-10-06T10:00:00Z", RankOutcome.WIN, 30)).rankDelta)
    }

    @Test fun publicProfiles() {
        for (item in root.rows("publicProfiles")) {
            val name = item.str("name")
            val profile = PublicProfile.parse(item["json"]!!.toString(), millis("2026-10-07T12:00:00Z"))
            val expect = item["expect"]!!.jsonObject
            assertEquals(name, expect.str("username"), profile.username)
            assertEquals(name, expect.bool("restricted"), profile.restricted)
            assertEquals(name, expect.str("visibility"), profile.visibility.raw)
            assertEquals(name, expect.str("relation"), profile.relation)
            assertEquals(name, expect.bool("online"), profile.online)
            assertEquals(name, expect.bool("isFriend"), profile.isFriend)
            assertEquals(name, expect.int("rankStep"), profile.rank?.step)
            assertEquals(name, expect.int("games"), profile.summary.games)
            assertEquals(name, expect.int("weeks"), profile.summary.weeks.size)
            assertEquals(name, expect.int("gameCount"), profile.games.size)
            if (profile.restricted) continue
            assertEquals(name, expect.str("title"), profile.title)
            assertEquals(name, expect.str("favoriteCommander"), profile.favoriteCommander)
            assertEquals(name, expect.int("rankPips"), profile.rank?.pips)
            assertEquals(name, expect.int("rankPeak"), profile.rank?.peakStep)
            assertEquals(name, expect.int("wins"), profile.summary.wins)
            assertEquals(name, expect.int("losses"), profile.summary.losses)
            assertEquals(name, expect.int("currentStreak"), profile.summary.currentStreak)
            assertEquals(name, expect.int("bestStreak"), profile.summary.bestStreak)
            assertEquals(name, expect["averageTurns"]!!.jsonPrimitive.doubleOrNull!!, profile.summary.averageTurns!!, 1e-9)
            assertEquals(name, (expect["weekGames"] as JsonArray).map { it.jsonPrimitive.int() }, profile.summary.weeks.map { it.games })
            assertEquals(name, (expect["rankPoints"] as JsonArray).map { it.jsonPrimitive.int() }, profile.summary.rankPoints.map { it.points })
            assertEquals(name, (expect["colors"] as JsonArray).map { it.jsonPrimitive.content }, profile.summary.colors.map { it.id })
            assertEquals(name, (expect["commanders"] as JsonArray).map { it.jsonPrimitive.content }, profile.summary.commanders.map { it.id })
            val first = profile.games.first()
            assertEquals(name, (expect["firstGameOpponents"] as JsonArray).map { it.jsonPrimitive.content }, first.opponents.map { it.name })
            assertEquals(name, (expect["firstGameHidden"] as JsonArray).map { it.jsonPrimitive.booleanOrNull }, first.opponents.map { it.hidden })
            assertEquals(name, (expect["firstGameHuman"] as JsonArray).map { it.jsonPrimitive.booleanOrNull }, first.opponents.map { !it.isAI })
            assertEquals(name, expect.str("secondGameDeck"), profile.games[1].deckName)
            assertNull(name, profile.games[1].turns)
            assertEquals(name, millis("2026-10-06T10:00:00Z"), first.date)
        }
    }

    @Test fun searchResults() {
        val block = root["searchResults"]!!.jsonObject
        val results = PlayerSearchResult.parse(block["json"]!!.toString())
        val expect = block.rows("expect")
        assertEquals(expect.size, results.size)
        for ((result, wanted) in results.zip(expect)) {
            assertEquals(wanted.str("username"), result.username)
            assertEquals(wanted.str("visibility"), result.visibility.raw)
            assertEquals(wanted.str("relation"), result.relation)
            assertEquals(wanted.bool("online"), result.online)
            assertEquals(wanted.int("rankStep"), result.rankStep)
        }
    }

    @Test fun searchPrefixes() {
        for (item in root.rows("searchPrefixes")) assertEquals("'${item.str("text")}'", item.str("normalized"), PlayerSearchRules.normalized(item.str("text")!!))
    }

    @Test fun visibilityHasThreeChoices() {
        assertEquals(listOf("public", "friends", "private"), ProfileVisibility.entries.map { it.raw })
        assertTrue(ProfileVisibility.of("public") == ProfileVisibility.PUBLIC)
        assertFalse(ProfileVisibility.of("secret") != null)
    }
}
