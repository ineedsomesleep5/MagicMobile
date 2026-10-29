package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The custom table's seats and strip, as iOS OnDeviceRootView.swift `addAISeat`, `removeAISeat` and `setupStartBar` apply them. */
class ArenaCustomTableTest {
    private val precons = listOf("p1", "p2", "p3")
    private val available = setOf("p1", "p2", "p3", "ai-a", "ai-b")

    @Test fun theTableShowsOneToThreeSeats() {
        assertEquals(1, ArenaCustomTable.seatCount(0))
        assertEquals(3, ArenaCustomTable.seatCount(5))
        assertTrue(ArenaCustomTable.canAddSeat(2))
        assertFalse(ArenaCustomTable.canAddSeat(3))
        assertFalse(ArenaCustomTable.canRemoveSeat(1))
        assertTrue(ArenaCustomTable.canRemoveSeat(2))
    }

    @Test fun anAddedSeatComesBackWithItsLastDeck() {
        assertEquals(listOf("ai-a", "ai-b", "p3") to 2, ArenaCustomTable.addSeat(listOf("ai-a", "ai-b", "p3"), 1, available, precons, "p1"))
    }

    @Test fun anAddedSeatWithoutADeckGetsAPreconNotAtTheTable() {
        assertEquals(listOf("p1", "p2", "") to 2, ArenaCustomTable.addSeat(listOf("p1", "gone", ""), 1, available, precons, "p1"))
        assertEquals(listOf("p1", "p2", "p3") to 3, ArenaCustomTable.addSeat(listOf("p1", "p2"), 2, available, precons, "p1"))
        assertNull(ArenaCustomTable.addSeat(listOf("p1", "p2", "p3"), 3, available, precons, "p1"))
    }

    @Test fun anEmptiedSeatsDeckWaitsPastTheRemainingSeats() {
        assertEquals(listOf("b", "c", "a") to 2, ArenaCustomTable.removeSeat(listOf("a", "b", "c"), 3, 0))
        assertEquals(listOf("a", "b", "c") to 1, ArenaCustomTable.removeSeat(listOf("a", "b", "c"), 2, 1))
        assertEquals(listOf("b", "a", "c") to 1, ArenaCustomTable.removeSeat(listOf("a", "b", "c"), 2, 0))
        assertNull(ArenaCustomTable.removeSeat(listOf("a", "b", "c"), 1, 0))
        assertNull(ArenaCustomTable.removeSeat(listOf("a", "b", "c"), 2, 2))
    }

    @Test fun theStripSaysNothingWhileTheTableIsIdle() {
        assertEquals("", ArenaCustomTable.stripStatus(ArenaCustomTable.IDLE_STATUS))
        assertEquals("Starting game…", ArenaCustomTable.stripStatus("Starting game…"))
    }
}
