package io.magicmobile.android.laws

import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankOutcome
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.laws.Laws.forAll
import io.magicmobile.android.laws.Laws.pick
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The ladder never moves the wrong way, never loses count, and a rank always reads back as the points it came from. */
class RankedLawsTest {
    private val mythicPoints = RankPosition.MYTHIC_STEP * RankPosition.PIPS_PER_DIVISION

    private fun assertValid(position: RankPosition) {
        if (position.tier == RankTier.MYTHIC) assertEquals(0, position.division)
        else { assertTrue("division ${position.division}", position.division in 1..4); assertTrue("pips ${position.pips}", position.pips in 0..3) }
        assertTrue(position.points >= 0)
    }

    @Test fun pointsAndRanksConvertBothWays() = forAll("ofPoints(p).points == p") { random ->
        val points = random.nextInt(0, mythicPoints + 200)
        val position = RankPosition.ofPoints(points)
        assertValid(position)
        assertEquals(points, position.points)
    }

    @Test fun moreRankPointsNeverMeanALowerRank() = forAll("ofPoints is monotonic") { random ->
        val a = random.nextInt(0, mythicPoints + 50); val b = random.nextInt(0, mythicPoints + 50)
        if (a <= b) assertTrue(RankPosition.ofPoints(a) <= RankPosition.ofPoints(b))
    }

    @Test fun everyGameMovesTheLadderTheRightWay() = forAll("a season of ranked games") { random ->
        var state = RankState.fresh("2026-10")
        repeat(random.nextInt(1, 200)) {
            val outcome = random.pick(RankOutcome.entries)
            val (next, change) = RankLadder.apply(outcome, state, deckBracket = random.nextInt(1, 6))
            when (outcome) {
                RankOutcome.WIN -> assertTrue("a win gains points", next.position.points > state.position.points)
                RankOutcome.LOSS -> {
                    assertTrue("a loss never gains points", next.position.points <= state.position.points)
                    val floorTier = minOf(state.position.tier, RankTier.DIAMOND)
                    assertTrue("a loss never leaves the tier", next.position.tier >= floorTier)
                }
                RankOutcome.DRAW -> assertEquals("a draw changes nothing", state.position, next.position)
            }
            assertEquals("one game counted", state.wins + state.losses + state.draws + 1, next.wins + next.losses + next.draws)
            assertTrue("peak never falls", next.peak >= state.peak)
            assertTrue("peak is at least the rank", next.peak >= next.position)
            assertEquals(change.after.points - change.before.points, change.pipDelta)
            assertValid(next.position)
            state = next
        }
    }

    @Test fun aNewSeasonNeverRaisesYourRank() = forAll("season rollover") { random ->
        val position = RankPosition.ofPoints(random.nextInt(0, mythicPoints + 40))
        val wins = random.nextInt(0, 50); val losses = random.nextInt(0, 50)
        val state = RankState("2026-09", position, maxOf(position, RankPosition.ofPoints(random.nextInt(0, mythicPoints + 40))), wins, losses)
        assertEquals("the same month changes nothing", state, RankLadder.rollover(state, "2026-09"))
        val next = RankLadder.rollover(state, "2026-10")
        assertTrue("never higher", next.position <= state.position)
        assertEquals("a fresh peak", next.position, next.peak)
        assertEquals(0, next.wins + next.losses + next.draws)
        assertEquals("a played season is kept", if (wins + losses > 0) 1 else 0, next.history.size - state.history.size)
        assertValid(next.position)
    }
}
