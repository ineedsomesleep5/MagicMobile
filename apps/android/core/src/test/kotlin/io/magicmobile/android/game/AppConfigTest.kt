package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** AppConfig (mm_app_config): the reply read safely, switches on unless named off (iOS AppConfigTests). */
class AppConfigTest {
    @Test fun theReplyIsReadAndSwitchesDefaultOn() {
        val config = AppConfig.parse("""{"notice": {"id": "update-64", "text": "Update to build 64."}, "nameFixes": {"A": "B", "": "C", "D": 3}, "switches": {"leaveVote": false, "odd": "yes"}}""")!!
        assertEquals(AppConfig.Notice("update-64", "Update to build 64."), config.notice)
        assertEquals(mapOf("A" to "B"), config.nameFixes)
        assertFalse(config.isOn("leaveVote"))
        assertTrue(config.isOn("stackAutoTuck"))
        assertTrue(config.isOn("odd"))
        assertNull(AppConfig.parse("""{"notice": null, "nameFixes": {}, "switches": {}}""")!!.notice)
        assertNull(AppConfig.parse("[1, 2]"))
    }

    @Test fun aDeckFileIsReadOnlyWhenComplete() {
        val sha = "a".repeat(64)
        val config = AppConfig.parse("""{"aiDecks": {"good": {"revision": 2, "url": "https://example.com/a.json", "sha256": "$sha"}, "http": {"revision": 2, "url": "http://example.com/a.json", "sha256": "$sha"}, "short": {"revision": 2, "url": "https://example.com/a.json", "sha256": "abc"}}}""")!!
        assertEquals(setOf("good"), config.deckFiles.keys)
        assertEquals(2, config.deckFiles["good"]?.revision)
    }
}
