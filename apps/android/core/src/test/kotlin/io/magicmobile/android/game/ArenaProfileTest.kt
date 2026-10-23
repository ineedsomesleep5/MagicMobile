package io.magicmobile.android.game

import java.time.ZoneOffset
import java.time.ZonedDateTime
import org.junit.Test
import org.junit.Assert.assertEquals

class ArenaProfileTest {
    private fun at(year: Int, month: Int, day: Int, hour: Int = 12) =
        ZonedDateTime.of(year, month, day, hour, 0, 0, 0, ZoneOffset.UTC).toInstant().toEpochMilli()

    @Test
    fun seasonEndsCountsWholeDaysUpAndSaysTomorrowAtTheEnd() {
        assertEquals("Season ends in 10 days", ArenaProfileRules.seasonEnds("2026-10", at(2026, 10, 22)))
        assertEquals("Season ends tomorrow", ArenaProfileRules.seasonEnds("2026-10", at(2026, 10, 31)))
        assertEquals("Season ends tomorrow", ArenaProfileRules.seasonEnds("2026-10", at(2026, 11, 2)))
        assertEquals("not-a-season", ArenaProfileRules.seasonEnds("not-a-season", at(2026, 10, 22)))
    }

    @Test
    fun winRateIsADashBeforeAnyGameAndAWholePercentAfter() {
        assertEquals("–", ArenaProfileRules.winRate(0, 0))
        assertEquals("67%", ArenaProfileRules.winRate(2, 3))
        assertEquals("100%", ArenaProfileRules.winRate(4, 4))
    }

    @Test
    fun tierPlaquesStepWiderUpTheStair() {
        assertEquals(250f, ArenaProfileRules.tierPlaqueWidth(0, wide = false), 0.001f)
        assertEquals(360f, ArenaProfileRules.tierPlaqueWidth(5, wide = false), 0.001f)
        assertEquals(430f, ArenaProfileRules.tierPlaqueWidth(5, wide = true), 0.001f)
    }

    @Test
    fun pictureChoicesKeepPlayedFirstAndADeletedChoice() {
        val played = (1..14).map { "C$it" }
        val (most, decks) = ArenaProfileRules.pictureChoices(played, listOf("C2", "", "Atraxa", "Atraxa"), "Gone")
        assertEquals((1..12).map { "C$it" } + "Gone", most)
        assertEquals(listOf("Atraxa"), decks)
        assertEquals(listOf("C1") to emptyList<String>(), ArenaProfileRules.pictureChoices(listOf("C1"), emptyList(), "C1"))
    }

    @Test
    fun podiumPutsTheWinnerInTheMiddle() {
        assertEquals(listOf(2, 1, 3), ArenaProfileRules.podiumOrder(listOf(1, 2, 3)))
        assertEquals(listOf(2, 1), ArenaProfileRules.podiumOrder(listOf(1, 2)))
        assertEquals(listOf(1), ArenaProfileRules.podiumOrder(listOf(1)))
    }

    @Test
    fun achievementIDsMatchTheSwiftCases() {
        assertEquals("firstWin", ArenaProfileRules.achievementID(Achievement.FIRST_WIN))
        assertEquals("firstRankedWin", ArenaProfileRules.achievementID(Achievement.FIRST_RANKED_WIN))
        assertEquals("streak5", ArenaProfileRules.achievementID(Achievement.STREAK5))
        assertEquals("giantSlayer", ArenaProfileRules.achievementID(Achievement.GIANT_SLAYER))
    }
}
