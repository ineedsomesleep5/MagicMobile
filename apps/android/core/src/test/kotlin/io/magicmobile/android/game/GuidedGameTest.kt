package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The guided first game's stored notes and first-launch welcome; the coach's rules are checked in ParityGoldenTest. */
class GuidedGameTest {
    private val player = emptyMap<String, String>()

    @Test fun welcomeShowsOnceOnAFirstLaunch() {
        assertTrue(GuidedGameLaunch.shouldShowWelcome(welcomeSeen = false, howToPlaySeenVersion = 0, launch = player))
        assertFalse(GuidedGameLaunch.shouldShowWelcome(welcomeSeen = true, howToPlaySeenVersion = 0, launch = player))
    }

    @Test fun playersWhoSawHowToPlayNeverGetTheWelcome() {
        assertFalse(GuidedGameLaunch.shouldShowWelcome(false, HowToPlayLaunch.CONTENT_VERSION, player))
        assertFalse(GuidedGameLaunch.shouldShowWelcome(false, 0, mapOf("MAGICMOBILE_UI_TEST_PREFERENCES" to "run-1")))
    }

    @Test fun eachNoteIsRememberedOnce() {
        var stored = ""
        stored = GuidedGameLaunch.remember(GuidedGameTip.LAND, stored)
        stored = GuidedGameLaunch.remember(GuidedGameTip.LAND, stored)
        stored = GuidedGameLaunch.remember(GuidedGameTip.CAST, stored)
        assertEquals("land,cast", stored)
        assertEquals(setOf(GuidedGameTip.LAND, GuidedGameTip.CAST), GuidedGameLaunch.shownTips(stored))
        assertTrue(GuidedGameLaunch.shownTips("").isEmpty())
        assertEquals(setOf(GuidedGameTip.PASS), GuidedGameLaunch.shownTips("pass,unknown"))
    }

    @Test fun notesAreShort() {
        for (tip in GuidedGameTip.entries) {
            assertTrue(tip.id, GuidedGameText.title(tip).length <= 26)
            assertTrue(tip.id, GuidedGameText.body(tip).length <= 160)
        }
    }
}
