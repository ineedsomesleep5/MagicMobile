package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of BattlefieldRowOverflowTests in apps/ios/MagicMobileTests/BattlefieldAdaptiveSizingTests.swift, case for case. */
class BattlefieldRowOverflowTest {
    /** Ten 50-dp slots in a 300-dp lane: content is 16 + 500 + 36 = 552 wide, so it scrolls up to 252. */
    private fun tenSlots(offset: Float, cardsPerSlot: List<Int> = emptyList()) =
        BattlefieldRowOverflow.measure(offset, 300f, List(10) { 50f }, 4f, 8f, cardsPerSlot)

    private fun twoSlots(offset: Float) = BattlefieldRowOverflow.measure(offset, 100f, listOf(50f, 50f), 4f)

    @Test fun rowThatFitsHidesNothing() {
        assertEquals(BattlefieldRowOverflow.NONE, BattlefieldRowOverflow.measure(0f, 300f, listOf(50f, 50f, 50f), 4f, 8f))
    }

    @Test fun restingOverflowCountsOnlyFullyHiddenTrailingCards() {
        // Slot 5 spans 278..328: clipped but partly visible. Slots 6-9 start past 300.
        assertEquals(BattlefieldRowOverflow(0, 4, clipsLeading = false, clipsTrailing = true), tenSlots(0f))
    }

    @Test fun midScrollHidesCardsOnBothSides() {
        // Offset 120: slots 0-1 end left of 0, slots 8-9 start past 300.
        assertEquals(BattlefieldRowOverflow(2, 2, clipsLeading = true, clipsTrailing = true), tenSlots(120f))
        // Offset 200: slots 0-2 end left of 0, slot 3 spans -30..20, slot 9 spans 294..344.
        assertEquals(BattlefieldRowOverflow(3, 0, clipsLeading = true, clipsTrailing = true), tenSlots(200f))
    }

    @Test fun fullyScrolledRowClearsTheTrailingEdge() {
        assertEquals(BattlefieldRowOverflow(4, 0, clipsLeading = true, clipsTrailing = false), tenSlots(252f))
    }

    @Test fun subPointSliversUseTheTolerance() {
        assertEquals(BattlefieldRowOverflow(1, 0, clipsLeading = true, clipsTrailing = false), twoSlots(49.6f))
        assertEquals(BattlefieldRowOverflow(0, 0, clipsLeading = true, clipsTrailing = false), twoSlots(49f))
        assertEquals(BattlefieldRowOverflow(0, 0, clipsLeading = false, clipsTrailing = true), twoSlots(0.4f))
    }

    @Test fun groupedSlotsCountEveryCardTheyShow() {
        // An attachment stack of 3 in slot 8 and a collapsed ×4 group in slot 9; missing entries count one.
        assertEquals(1 + 1 + 3 + 4, tenSlots(0f, listOf(1, 1, 1, 1, 1, 1, 1, 1, 3, 4)).hiddenTrailing)
        assertEquals(4, tenSlots(0f, listOf(2)).hiddenTrailing)
        assertEquals(2 + 0 + 0 + 1, tenSlots(252f, listOf(2, 0, -1)).hiddenLeading)
    }

    @Test fun laneAddsRowsThatShareOneOffset() {
        val rows = listOf(List(10) { 1 }, listOf(1, 1, 1))
        assertEquals(BattlefieldRowOverflow(0, 4, clipsLeading = false, clipsTrailing = true), BattlefieldRowOverflow.lane(0f, 300f, 50f, rows))
        // The short row starts at the same padding, so scrolling to the end hides all three of its cards.
        assertEquals(BattlefieldRowOverflow(7, 0, clipsLeading = true, clipsTrailing = false), BattlefieldRowOverflow.lane(252f, 300f, 50f, rows))
        assertEquals(BattlefieldRowOverflow.NONE, BattlefieldRowOverflow.lane(0f, 300f, 50f, emptyList()))
        assertEquals(8f, BattlefieldRowOverflow.ROW_PADDING)
        assertEquals(4f, BattlefieldRowOverflow.SLOT_SPACING)
    }

    @Test fun scrollingRightNeverUncoversLeadingCardsOrHidesTrailingOnes() {
        var previous = tenSlots(0f)
        for (step in 0..84) {
            val offset = step * 3f
            val current = tenSlots(offset)
            assertTrue(current.hiddenLeading >= previous.hiddenLeading)
            assertTrue(current.hiddenTrailing <= previous.hiddenTrailing)
            assertTrue("A 300-dp lane always shows five 50-dp slots", current.hiddenLeading + current.hiddenTrailing <= 5)
            assertEquals(offset > 8.5f, current.clipsLeading)
            previous = current
        }
    }

    @Test fun invalidGeometryHidesNothing() {
        for (offset in listOf(Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY)) assertEquals(BattlefieldRowOverflow.NONE, tenSlots(offset))
        for (viewport in listOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            assertEquals(BattlefieldRowOverflow.NONE, BattlefieldRowOverflow.measure(0f, viewport, listOf(50f), 4f))
        }
        assertEquals(BattlefieldRowOverflow.NONE, BattlefieldRowOverflow.measure(0f, 300f, emptyList(), 4f))
        // Negative or non-finite widths, spacing and inset collapse to zero; an empty slot at an edge is not hidden.
        assertEquals(BattlefieldRowOverflow(0, 0, clipsLeading = false, clipsTrailing = true),
            BattlefieldRowOverflow.measure(0f, 100f, listOf(-20f, Float.NaN, 150f), Float.NaN, Float.NaN))
    }
}
