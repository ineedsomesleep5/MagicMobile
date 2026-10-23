package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The inbox (NativeUpdateNewsView.swift `UpdateNews`) and the Downloads readout (NativeDownloadsView.swift), as iOS shows them. */
class ArenaInboxTest {
    @Test fun inboxIsNewestFirstWithOneNewMessage() {
        val messages = UpdateNews.messages
        assertEquals("arena-menus", messages.first().id)
        assertEquals(messages.map { it.id }.distinct(), messages.map { it.id })
        assertEquals(messages.sortedByDescending { it.day }.map { it.day }, messages.map { it.day })
        assertTrue(UpdateNews.isNew(0))
        assertFalse(messages.indices.drop(1).any(UpdateNews::isNew))
        assertFalse(messages.any { it.id == UpdateNews.ABOUT_ID })
        assertEquals("October 22, 2026", messages.first().date)
        assertEquals(listOf("U"), messages.first().colors)
    }

    @Test fun aRowOpensAndClosesInPlace() {
        assertEquals("ranked", UpdateNews.toggle(null, "ranked"))
        assertNull(UpdateNews.toggle("ranked", "ranked"))
        assertEquals("tavern", UpdateNews.toggle("ranked", "tavern"))
    }

    @Test fun readoutCountsWhatIsStoredOrDownloaded() {
        assertEquals(DownloadReadout.Readout("0 of 31,959 stored", 0.0),
            DownloadReadout.readout(false, false, 0, 0, false, 0, 31_959, 0, 0, scanPending = false))
        assertEquals("Artwork on this phone", DownloadReadout.readout(false, false, 0, 0, false, 0, 31_959, 0, 0, scanPending = true).count)
        assertNull(DownloadReadout.readout(false, false, 0, 0, false, 0, 0, 0, 0, false).fraction)
        assertEquals("120 of 1,200 stored", DownloadReadout.readout(false, false, 0, 0, true, 5, 9, 120, 1_200, false).count)
        val running = DownloadReadout.readout(true, false, 250, 1_000, false, 0, 31_959, 0, 0, false)
        assertEquals("250 of 1,000 downloaded", running.count)
        assertEquals(0.25, running.fraction!!, 1e-9)
        // Preparing the list shows the stored count, not "0 of 0 downloaded".
        assertEquals("Artwork on this phone", DownloadReadout.readout(true, true, 0, 0, false, 0, 0, 0, 0, false).count)
    }

    @Test fun stateLineSaysWhereThingsStandOnce() {
        fun line(running: Boolean = false, preparing: Boolean = false, status: String = "", scanning: Boolean = false, reading: Boolean = false,
                 pending: Boolean = false, missing: Int = 0, incomplete: Boolean = false) =
            DownloadReadout.stateLine(running, preparing, status, scanning, reading, pending, missing, incomplete, "3.1 MB", "Standard")
        assertEquals("Preparing image list…", line(running = true, preparing = true))
        assertEquals("Downloading 4 of 9", line(running = true, status = "Downloading 4 of 9"))
        assertEquals("Checking local files…", line(scanning = true))
        assertEquals("Reading the installed catalogue…", line(reading = true))
        assertEquals("Checking needed", line(pending = true))
        assertEquals("All artwork stored", line())
        assertEquals("", line(missing = 3, incomplete = true))
        assertEquals("1,204 missing · about 3.1 MB at standard quality", line(missing = 1_204))
    }

    @Test fun coverageLeavesOutWhatSaysNothing() {
        assertEquals("", DownloadReadout.coverage(false, false, true, 0, 0, 0, "Zero KB"))
        assertEquals("Tokens 3 of 900 · 12 MB on this phone", DownloadReadout.coverage(false, false, true, 3, 900, 12_000_000, "12 MB"))
        assertEquals("12 MB on this phone", DownloadReadout.coverage(true, false, true, 3, 900, 12_000_000, "12 MB"))
        assertEquals("", DownloadReadout.coverage(false, true, true, 3, 900, 0, "0 B"))
        assertEquals(listOf("catalogue", "tokens", "decks", "deck"), DownloadReadout.scopes.map { it.second })
    }
}
