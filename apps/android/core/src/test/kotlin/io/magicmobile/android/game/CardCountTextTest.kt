package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Test

/** Mirrors GameLogPresentationTests.testCardCountLabelIsSingularOnlyForOne (iOS). */
class CardCountTextTest {
    @Test fun cardCountLabelIsSingularOnlyForOne() {
        assertEquals("0 cards", CardCountText.label(0))
        assertEquals("1 card", CardCountText.label(1))
        assertEquals("2 cards", CardCountText.label(2))
        assertEquals("100 cards", CardCountText.label(100))
    }
}
