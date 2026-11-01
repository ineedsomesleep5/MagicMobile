package io.magicmobile.android.game

import kotlinx.serialization.json.Json
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

    @Test fun awardsParseWhatTheServerSends() {
        val awards = Award.parse(Json.parseToJsonElement("""[
            {"id": "first-mythic", "name": "First to Mythic", "description": "The first.", "imageUrl": "https://example.com/a.png",
             "tint": "#FF7338", "rarity": 3, "note": "Season 1", "awardedAt": "2026-10-30T17:55:30.075436+00:00", "seen": false},
            {"id": "plain", "name": "Plain", "imageUrl": "http://example.com/a.png", "tint": "orange", "rarity": 9},
            {"id": "", "name": "No id"}, {"id": "no-name"}]"""))
        assertEquals(listOf("first-mythic", "plain"), awards.map { it.id })
        assertEquals("https://example.com/a.png", awards[0].imageUrl)
        assertEquals(0xFF7338, awards[0].tint)
        assertEquals(false, awards[0].seen)
        assertEquals(1793382930075L, awards[0].awardedAt)
        assertEquals(null, awards[1].imageUrl)
        assertEquals(Award.GOLD, awards[1].tint)
        assertEquals(3, awards[1].rarity)
        assertEquals(true, awards[1].seen)
    }
}
