package io.magicmobile.android.studio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Decks page's rules, as DeckStudioRootView.swift lays the boxes out and opens them. */
class ArenaDecksPageTest {
    @Test fun gridKeepsTwoColumnsOnANarrowPhoneAndFillsTheWidth() {
        assertEquals(ArenaDecksPage.Grid(2, 100f), ArenaDecksPage.grid(212f))
        // An upright 412 dp phone, 12 dp margins and 8 dp inside: three boxes of 120.
        assertEquals(ArenaDecksPage.Grid(3, 120f), ArenaDecksPage.grid(384f))
        // Sideways: as many 112 dp boxes as fit.
        val wide = ArenaDecksPage.grid(860f)
        assertEquals(7, wide.columns)
        assertTrue(wide.boxWidth >= ArenaDecksPage.MIN_BOX)
        assertTrue(wide.boxWidth * wide.columns + ArenaDecksPage.GAP * (wide.columns - 1) <= 860f)
    }

    @Test fun theNewDeckTileTakesTheFirstCell() {
        assertEquals(1, ArenaDecksPage.cell(0))
        assertEquals(0, ArenaDecksPage.row(ArenaDecksPage.cell(1), 3))
        assertEquals(1, ArenaDecksPage.row(ArenaDecksPage.cell(2), 3))
        assertEquals(2, ArenaDecksPage.rows(5, 3))
        assertEquals(1, ArenaDecksPage.rows(0, 3))
    }

    @Test fun onlyAnOpenBoxInTheFirstRowNeedsRoomAboveIt() {
        assertTrue(ArenaDecksPage.firstRowOpen(0, 3))
        assertTrue(ArenaDecksPage.firstRowOpen(1, 3))
        assertFalse(ArenaDecksPage.firstRowOpen(2, 3))
        assertFalse(ArenaDecksPage.firstRowOpen(null, 3))
    }

    @Test fun arrivalScrollsOnlyPastTheFirstRow() {
        assertFalse(ArenaDecksPage.scrollsOnArrival(0, 3))
        assertFalse(ArenaDecksPage.scrollsOnArrival(1, 3))
        assertTrue(ArenaDecksPage.scrollsOnArrival(2, 3))
        assertFalse(ArenaDecksPage.scrollsOnArrival(null, 3))
    }

    @Test fun theFirstTapOpensTheBoxAndTheSecondEdits() {
        assertEquals(ArenaDecksPage.Tap.OPEN_BOX, ArenaDecksPage.tap(chosen = false))
        assertEquals(ArenaDecksPage.Tap.EDIT, ArenaDecksPage.tap(chosen = true))
    }

    @Test fun aDeckThatNeedsFixesSaysSoBeforePlaying() {
        assertEquals("FIX", ArenaDecksPage.tag(needsFixes = true, playing = true))
        assertEquals("PLAYING", ArenaDecksPage.tag(needsFixes = false, playing = true))
        assertNull(ArenaDecksPage.tag(needsFixes = false, playing = false))
    }

    @Test fun theCurveCountsNonlandCopiesWithSevenAndMoreTogether() {
        val bins = ArenaDeckCurve.bins(listOf(ArenaDeckCurve.Line(2, 2.0, false), ArenaDeckCurve.Line(1, 9.0, false), ArenaDeckCurve.Line(1, 7.0, false),
            ArenaDeckCurve.Line(30, 0.0, true), ArenaDeckCurve.Line(1, null, false), ArenaDeckCurve.Line(1, 0.0, false)))
        assertEquals(listOf(1, 0, 2, 0, 0, 0, 0, 2), bins)
        assertEquals(30f, ArenaDeckCurve.height(2, bins))
        assertEquals(2f, ArenaDeckCurve.height(0, bins))
        assertEquals(15f, ArenaDeckCurve.height(1, bins))
    }

    @Test fun theStripShowsTheChosenThenThePlayingThenTheFirstDeck() {
        val ids = listOf("precon:a", "local:b")
        assertEquals("local:b", ArenaDecksPage.focusedID("local:b", "precon:a", ids, ids))
        assertEquals("precon:a", ArenaDecksPage.focusedID(null, "precon:a", ids, ids))
        assertEquals("local:b", ArenaDecksPage.focusedID(null, "local:gone", ids, listOf("local:b")))
        assertNull(ArenaDecksPage.focusedID(null, "local:gone", ids, emptyList()))
    }
}
