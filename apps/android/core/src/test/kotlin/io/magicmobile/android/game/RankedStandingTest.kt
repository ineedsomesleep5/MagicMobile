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

    @Test fun theServersAnswerReplacesThePhonesGuessOnThatGame() {
        val played = fresh().copy(rankedTicket = "t1").play(RankOutcome.WIN)
        assertEquals("t1", played.matches.first().rankedTicket)
        val answer = { body: String -> RankedStanding.parse(Json.parseToJsonElement(body) as JsonObject) }
        // Counted: the server's own move on the ladder.
        val counted = answer("""{"season": "2026-10", "points": 6, "settlement": "counted",
            "change": {"pointsBefore": 4, "pointsAfter": 6, "bonuses": ["underdog"]}, "check": null}""")
        val settled = played.settlingRanked("t1", counted.settlement, counted.check, counted.change).matches.first()
        assertEquals(RankPosition.ofPoints(6), settled.rankChange?.after)
        assertEquals(listOf(RankBonus.UNDERDOG), settled.rankChange?.bonuses)
        assertNull(settled.rankNote)
        // Held back: no move, and why.
        val short = answer("""{"season": "2026-10", "points": 4, "settlement": "unverified", "change": null, "check": "too_short"}""")
        val held = played.settlingRanked("t1", short.settlement, short.check, short.change).matches.first()
        assertEquals(0, held.rankChange?.pipDelta)
        assertEquals("Not ranked: wins before turn 5 don't count", held.rankNote)
        assertEquals("Not ranked: wins before turn 3 don't count", RankSettlement.note("unverified", "too_short", 5))
        assertEquals("Not ranked: 12 ranked wins a day", RankSettlement.note("capped", null, 2))
        assertSame(played, played.settlingRanked("other", "counted", null, null))
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

    /** Mirrors testBronzePicksOnlyTheGentlestPrecons: Bronze faces only the three softest precons. */
    @Test fun bronzePicksOnlyTheGentlestPrecons() {
        val deck = io.magicmobile.android.core.Deck("x", emptyList())
        val precons = listOf("token-triumph", "first-flight", "grave-danger", "chaos-incarnate", "draconic-destruction")
            .map { AIDeck(it, it, "", "", "Commander $it", CommanderBracket.CORE, deck) }
        for (roll in 0 until 10) {
            val pick = AIDeckPool.pick(2, null, emptyList(), precons, preconsOnly = true, onlyPrecons = AIDeckPool.gentlestPrecons) { roll }
            assertTrue("${pick?.id}", pick?.id in AIDeckPool.gentlestPrecons)
        }
        assertTrue(AIDeckPool.pick(2, null, emptyList(), precons, preconsOnly = true, onlyPrecons = setOf("no-such-precon")) { 4 } != null)
    }

    /** Phase 5: a seeded ticket's result goes with the game record kept on the phone, and survives a relaunch. */
    @Test fun seededTicketKeepsTheGameRecordWithTheResult() {
        val file = fresh().copy(rankedTicket = "t1", rankedTicketSeeded = true)
            .recording(october, PlayMode.RANKED, RankOutcome.WIN, listOf(MatchOpponent("Foe", null, true)), 2, 1, "precon:x", "Goblins",
                null, listOf("R"), 2, 9, gameRecordFile = "game-1.json").first
        val pending = file.pendingRankedResults.single()
        assertEquals(PendingRankedResult("t1", RankOutcome.WIN, october, seeded = true, recordFile = "game-1.json"), pending)
        assertNull(file.rankedTicket)
        assertEquals(false, file.rankedTicketSeeded)
        val again = PlayerRecordFile.json.decodeFromString(PlayerRecordFile.serializer(),
            PlayerRecordFile.json.encodeToString(PlayerRecordFile.serializer(), file))
        assertEquals(file, again)
        // An older file without the new fields reads as unseeded.
        assertEquals(PendingRankedResult("t2", RankOutcome.LOSS, 5), PlayerRecordFile.json.decodeFromString(PendingRankedResult.serializer(),
            """{"ticket":"t2","outcome":"LOSS","date":5}"""))
        // The next ticket starts unseeded.
        assertEquals(false, file.copy(rankedTicket = "t3").play(RankOutcome.LOSS).pendingRankedResults.last().seeded)
    }

    @Test fun parsesTheSeededTicket() {
        val id = "3f1c2a9e-7b1d-4c55-9a0e-1d2c3b4a5f60"
        assertEquals(RankedAITicket(id, -4_123_456_789_012_345_678L),
            RankedAITicket.parse("""{"id":"$id","seed":"-4123456789012345678","aiSkill":1}"""))
        assertNull(RankedAITicket.parse("""{"id":"$id","seed":4.5}"""))
        assertNull(RankedAITicket.parse("\"$id\""))
    }

    /** mm_ranked_leaderboard's reply (RankedStandingTests.swift testLeaderboardParsesAndPinsYourRowOffTheList). */
    @Test fun leaderboardParsesAndPinsYourRowOffTheList() {
        val board = RankedLeaderboard.parse(Json.parseToJsonElement("""
            {"season":"2026-10","scope":"everyone","total":3,"online":1,"entries":[
             {"position":1,"username":"Dahlia_Rose","title":"Mythic Legend","commander":"Ayula, Queen Among Bears","points":87,"step":20,"pips":7,"peakStep":20,"wins":28,"losses":11,"online":true,"you":false},
             {"position":2,"username":"ManaFiend","title":null,"commander":null,"points":71,"step":17,"pips":3,"peakStep":17,"wins":25,"losses":10,"online":false,"you":false}],
             "me":{"position":3,"username":"CalebM","title":"Contender","commander":"Edgar Markov","points":42,"step":10,"pips":2,"peakStep":11,"wins":14,"losses":9,"online":true,"you":true}}
        """) as JsonObject)
        assertEquals(listOf("Dahlia_Rose", "ManaFiend"), board.entries.map { it.username })
        assertEquals(RankTier.MYTHIC, board.entries[0].rank.tier)
        assertNull(board.entries[1].title)
        assertTrue(board.entries[0].online)
        assertEquals("CalebM", board.pinnedMe?.username)
        val empty = RankedLeaderboard.parse(Json.parseToJsonElement(
            """{"season":"2026-10","scope":"friends","total":0,"online":0,"entries":[],"me":null}""") as JsonObject)
        assertTrue(empty.entries.isEmpty())
        assertNull(empty.pinnedMe)
    }
}
