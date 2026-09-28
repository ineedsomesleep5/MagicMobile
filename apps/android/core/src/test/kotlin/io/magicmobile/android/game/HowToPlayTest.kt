package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The walkthrough's first-launch flag and page rules; the shared words are checked in ParityGoldenTest. */
class HowToPlayTest {
    private val player = emptyMap<String, String>()

    @Test fun opensOnFirstLaunchAndNotAfterItWasClosed() {
        var stored = 0
        assertTrue(HowToPlayLaunch.shouldShowAutomatically(stored, player))
        stored = HowToPlayLaunch.seenVersionAfterClosing(stored)
        assertEquals(HowToPlayLaunch.CONTENT_VERSION, stored)
        assertFalse(HowToPlayLaunch.shouldShowAutomatically(stored, player))
    }

    @Test fun closingNeverLowersANewerStoredVersion() {
        val newer = HowToPlayLaunch.CONTENT_VERSION + 1
        assertEquals(newer, HowToPlayLaunch.seenVersionAfterClosing(newer))
        assertFalse(HowToPlayLaunch.shouldShowAutomatically(newer, player))
    }

    @Test fun anOlderStoredVersionShowsTheWalkthroughAgain() {
        assertTrue(HowToPlayLaunch.shouldShowAutomatically(HowToPlayLaunch.CONTENT_VERSION - 1, automated = false, forced = false))
    }

    @Test fun automationNeverSeesItUnlessARunAsks() {
        val uiTest = mapOf("MAGICMOBILE_UI_TEST_PREFERENCES" to "run-1")
        assertTrue(HowToPlayLaunch.isAutomated(uiTest))
        assertTrue(HowToPlayLaunch.isAutomated(mapOf("MAGICMOBILE_DESIGN_PREVIEW" to "menu")))
        assertFalse(HowToPlayLaunch.isAutomated(player))
        assertFalse(HowToPlayLaunch.shouldShowAutomatically(0, uiTest))

        val forced = uiTest + (HowToPlayLaunch.FIRST_LAUNCH_EXTRA to "1")
        assertTrue(HowToPlayLaunch.isForced(forced))
        assertFalse(HowToPlayLaunch.isForced(uiTest + (HowToPlayLaunch.FIRST_LAUNCH_EXTRA to "0")))
        assertTrue(HowToPlayLaunch.shouldShowAutomatically(0, forced))
        assertFalse("A forced first launch still shows only once",
            HowToPlayLaunch.shouldShowAutomatically(HowToPlayLaunch.seenVersionAfterClosing(0), forced))
    }

    @Test fun pagesAreShortAndDistinct() {
        val pages = HowToPlayText.pages
        assertEquals(10, pages.size)
        assertEquals(pages.size, pages.map { it.id }.toSet().size)
        for (page in pages) {
            assertTrue(page.id, page.title.isNotEmpty())
            val sentences = Regex("[.!?](\\s|$)").findAll(page.body).count()
            assertTrue("${page.id} has $sentences sentences", sentences in 1..3)
        }
        assertEquals("Page 1 of 10", HowToPlayText.progress(1, pages.size))
    }
}
