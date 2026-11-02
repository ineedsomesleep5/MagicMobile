package io.magicmobile.android.game

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** Mirrors apps/ios/MagicMobileTests/BadgeArtStoreTests.swift. */
class BadgeArtTest {
    private val big = "https://raw.githubusercontent.com/o/r/main/design/awards/lifer.png"
    private val small = "https://raw.githubusercontent.com/o/r/main/design/awards/small/lifer.png"
    private fun folder(): File = Files.createTempDirectory("badges").toFile()

    @Test fun ourArtHasASmallCopyAndOtherArtDoesnt() {
        assertEquals(small, BadgeArtStore.smallURL(big))
        assertEquals(small, BadgeArtStore.smallURL(small))
        assertEquals("https://example.com/a.png", BadgeArtStore.smallURL("https://example.com/a.png"))
    }

    @Test fun aBadgeDownloadsOnceAndWaitsOnThePhone() = runBlocking {
        val asked = mutableListOf<Pair<String, String?>>()
        val store = BadgeArtStore(folder()) { url, etag -> asked += url to etag; BadgeFetch.New(byteArrayOf(1, 2), "tag") }
        assertNull(store.stored(big))
        assertTrue(store.refresh(big, now = 1_000))
        assertArrayEquals(byteArrayOf(1, 2), store.stored(big))
        assertFalse("checked lately", store.refresh(big, now = 2_000))
        assertEquals(listOf(small to null), asked)
    }

    /** A replaced file comes down again, and an unchanged one costs a single short answer. */
    @Test fun afterSixHoursOnlyAChangedFileComesDown() = runBlocking {
        var answer: BadgeFetch = BadgeFetch.New(byteArrayOf(1), "one")
        val tags = mutableListOf<String?>()
        val store = BadgeArtStore(folder()) { _, etag -> tags += etag; answer }
        store.refresh(big, now = 0)
        answer = BadgeFetch.Unchanged
        assertFalse(store.refresh(big, now = BadgeArtStore.RECHECK_MS))
        assertFalse("the check counts", store.refresh(big, now = BadgeArtStore.RECHECK_MS + 1))
        answer = BadgeFetch.New(byteArrayOf(2), "two")
        assertTrue(store.refresh(big, now = BadgeArtStore.RECHECK_MS * 2))
        assertArrayEquals(byteArrayOf(2), store.stored(big))
        assertEquals(listOf(null, "one", "one"), tags)
    }

    @Test fun aMissingSmallCopyFallsBackToTheBigFile() = runBlocking {
        val asked = mutableListOf<String>()
        val store = BadgeArtStore(folder()) { url, _ -> asked += url; if (url == small) BadgeFetch.Missing else BadgeFetch.New(byteArrayOf(9), null) }
        assertTrue(store.refresh(big))
        assertArrayEquals(byteArrayOf(9), store.stored(big))
        assertEquals(listOf(small, big), asked)
    }

    @Test fun beingOfflineKeepsTheCoinAndTriesAgain() = runBlocking {
        var answer: BadgeFetch = BadgeFetch.New(byteArrayOf(5), "t")
        var calls = 0
        val store = BadgeArtStore(folder()) { _, _ -> calls++; answer }
        store.refresh(big, now = 0)
        answer = BadgeFetch.Failed
        assertFalse(store.refresh(big, now = BadgeArtStore.RECHECK_MS))
        assertFalse(store.refresh(big, now = BadgeArtStore.RECHECK_MS + 1))
        assertEquals("a failure doesn't count as a check", 3, calls)
        assertArrayEquals(byteArrayOf(5), store.stored(big))
    }

    @Test fun theBigAndSmallCopiesAreKeptApart() = runBlocking {
        val store = BadgeArtStore(folder()) { url, _ -> BadgeFetch.New(if (url == small) byteArrayOf(1) else byteArrayOf(2), null) }
        store.refresh(big)
        store.refresh(big, small = false)
        assertArrayEquals(byteArrayOf(1), store.stored(big))
        assertArrayEquals(byteArrayOf(2), store.stored(big, small = false))
    }

    @Test fun everyCoinHasASmallCopy() {
        var root = File("").absoluteFile
        while (!File(root, "design/awards").exists()) root = root.parentFile
        val small = File(root, "design/awards/small")
        File(root, "design/awards").listFiles().orEmpty().filter { it.extension == "png" }.forEach { art ->
            val copy = File(small, art.name)
            assertTrue("run scripts/brand/award_small.sh: ${art.name}", copy.exists())
            assertTrue("${art.name} is ${copy.length()} bytes", copy.length() < 60_000)
        }
    }
}
