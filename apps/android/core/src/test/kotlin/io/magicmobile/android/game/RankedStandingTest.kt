package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors apps/ios/MagicMobileTests/RankedStandingTests.swift: the server keeps the ranked standing. */
class RankedStandingTest {
    private val october = 1_791_000_000_000L // October 2026

    private fun standing(season: String = "2026-10", points: Int, peak: Int = points, wins: Int = 0, losses: Int = 0,
                         unsettled: Int = 0, history: String = "[]"): RankedStanding = RankedStanding.parse(Json.parseToJsonElement("""
        {"seeded": true, "unsettled": $unsettled, "season": "$season", "points": $points, "peakPoints": $peak,
         "wins": $wins, "losses": $losses, "draws": 0, "winStreak": 2, "history": $history, "settlement": "counted",
         "change": {"outcome": "win"}}
    """) as JsonObject)

    private fun PlayerRecordFile.play(outcome: RankOutcome, human: Boolean = false): PlayerRecordFile =
        recording(october, PlayMode.RANKED, outcome, listOf(MatchOpponent("Foe", null, !human)), 2, 1, "precon:x", "Goblins",
            "Krenko, Mob Boss", listOf("R"), 2, 9).first

    private fun fresh() = PlayerRecordFile(RankState.fresh("2026-10"))

    @Test fun parsesTheServerStanding() {
        val value = standing(points = 9, peak = 12, wins = 5, losses = 2,
            history = """[{"season": "2026-09", "finalPoints": 30, "peakPoints": 33, "wins": 9, "losses": 4}]""")
        assertEquals(9, value.points)
        assertEquals(30, value.history.first().finalPoints)
        assertEquals("counted", value.settlement)
    }

    @Test fun adoptsTheServerStanding() {
        val file = fresh().play(RankOutcome.WIN).adopting(standing(points = 9, peak = 12, wins = 5, losses = 2))
        assertEquals(RankPosition.make(RankTier.BRONZE, 2, 1), file.rank.position)
        assertEquals(RankPosition.make(RankTier.BRONZE, 1, 0), file.rank.peak)
        assertEquals(5, file.rank.wins)
        assertEquals(2, file.rank.losses)
        assertEquals(2, file.rank.winStreak)
        assertEquals(1, file.matches.size)
    }

    @Test fun keepsItsOwnCountWhileAResultIsOnItsWay() {
        val played = fresh().play(RankOutcome.WIN)
        assertSame(played, played.adopting(standing(points = 0, unsettled = 1)))
        val pending = played.copy(rankedTicket = "t1").play(RankOutcome.WIN)
        assertEquals(1, pending.pendingRankedResults.size)
        assertSame(pending, pending.adopting(standing(points = 1)))
    }

    @Test fun aNewSeasonOnTheServerRollsOverAndKeepsItsHistory() {
        var file = fresh()
        repeat(3) { file = file.play(RankOutcome.WIN) }
        file = file.adopting(standing(season = "2026-11", points = 4,
            history = """[{"season": "2026-10", "finalPoints": 20, "peakPoints": 22, "wins": 9, "losses": 4}]"""))
        assertEquals("2026-11", file.rank.season)
        assertEquals(RankPosition.ofPoints(4), file.rank.position)
        assertEquals("2026-10", file.rank.history.first().season)
        assertEquals(RankPosition.ofPoints(20), file.rank.history.first().final)
        assertEquals(9, file.rank.history.first().wins)
        assertSame(file, file.adopting(standing(season = "2026-09", points = 60)))
    }

    @Test fun rankedAIResultsWaitWithTheirTicket() {
        val file = fresh().copy(rankedTicket = "t1").play(RankOutcome.WIN)
        assertNull(file.rankedTicket)
        assertEquals(listOf("t1"), file.pendingRankedResults.map { it.ticket })
        assertEquals(RankOutcome.WIN, file.pendingRankedResults.first().outcome)
        // A game against a person never uses an AI ticket.
        val human = file.copy(rankedTicket = "t2").play(RankOutcome.LOSS, human = true)
        assertEquals(1, human.pendingRankedResults.size)
        assertEquals("t2", human.rankedTicket)
        // The file keeps both across a relaunch.
        val again = PlayerRecordFile.json.decodeFromString(PlayerRecordFile.serializer(),
            PlayerRecordFile.json.encodeToString(PlayerRecordFile.serializer(), human))
        assertEquals(human, again)
        assertTrue(again.pendingRankedResults.isNotEmpty())
    }
}
