package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors apps/ios/MagicMobileTests/PerformanceAwarenessTests.swift. */
class GamePerformanceTest {
    @Test fun readingsKeepPeaksAndHotTime() {
        val start = 1_000_000_000L
        val entry = GamePerformanceEntry(start, "ranked", 4)
            .absorb(start, 300, 900, 1)
            .absorb(start + 60_000, 520, 640, 2)
            .absorb(start + 120_000, 410, null, 2)
            .absorb(start + 180_000, null, 700, 1)
        assertEquals(520, entry.peakMemoryMB)
        assertEquals(640, entry.lowestAvailableMB)
        assertEquals(2, entry.hottest)
        assertEquals(2.0, entry.hotMinutes, 0.001)
    }

    @Test fun recordKeepsHowTheGameBegan() {
        val start = 1_000_000_000L
        val entry = GamePerformanceEntry(start, "ranked", 6)
            .absorb(start, null, null, 1)
            .absorb(start + 60_000, null, null, 2, onCharger = true)
            .absorb(start + 120_000, null, null, 0, lowPowerMode = true)
        assertEquals(1, entry.startThermal)
        assertTrue(entry.line, entry.line.endsWith("hottest serious, hot 1 min, began fair, charging, low power"))
        val cool = GamePerformanceEntry(start, "ranked", 6).absorb(start, null, null, 0).absorb(start + 60_000, null, null, 1)
        assertTrue(cool.line, cool.line.endsWith("hottest fair"))
        // A record saved by an earlier build has none of these and still loads.
        val old = GamePerformanceLog.decode("""[{"started":1,"mode":"quick"}]""").single()
        assertNull(old.startThermal)
        assertEquals(false, old.charging)
    }

    @Test fun logKeepsTheLastTwentyGames() {
        var text: String? = null
        val start = 2_000_000_000L
        for (game in 0 until 23) {
            val begun = start + game * 3_600_000L
            val entry = GamePerformanceEntry(begun, "quick", 3, turns = game + 1, memoryWarnings = if (game == 22) 1 else 0)
            text = GamePerformanceLog.append(GamePerformanceLog.decode(text), entry, begun + 900_000)
        }
        val entries = GamePerformanceLog.decode(text)
        assertEquals(GamePerformanceLog.LIMIT, entries.size)
        assertEquals(23, entries.last().turns)
        assertEquals(15.0, entries.last().minutes, 0.001)
        val section = GamePerformanceLog.section(entries, "0.1.1 (26)")!!
        assertTrue(section.contains("20 games"))
        assertTrue(section.contains("15 min, 23 turns"))
        assertTrue(section.contains("1 memory warning"))
        assertNull(GamePerformanceLog.section(emptyList(), "x"))
    }

    @Test fun androidThermalStatusMapsToTheIosScale() {
        assertEquals(listOf(0, 1, 1, 2, 3, 3, 3), (0..6).map(GamePerformanceEntry::thermalLevel))
    }
}
