package io.magicmobile.android.game

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    private fun played(minutes: Int = 3, thermal: Int = 1, id: String? = "11111111-2222-3333-4444-555555555555", build: Int? = 55, start: Long = 1_000_000_000L): GamePerformanceEntry {
        var entry = GamePerformanceEntry(start, "ranked", 6, id = id, build = build)
        for (tick in 0..minutes * 6) {
            val spent = tick * 10_000L
            entry = entry.absorb(start + spent, 600, null, if (tick >= 6) thermal else 0,
                cpu = CPUReading(spent * 4 / 10, spent * 2 / 10, spent / 20), battery = 80 - tick / 6, temperature = 30.0 + tick / 6)
        }
        return entry
    }

    private fun Map<String, JsonElement>.stats() = (getValue("p_stats") as JsonObject)
    private fun JsonObject.number(key: String) = getValue(key).jsonPrimitive.double

    /** The server's numbers: heat over time, CPU by part as percent of one core, and how the game looked. */
    @Test fun reportCarriesTheGamesNumbers() {
        val entry = played(thermal = 2).copy(turns = 9, setup = GameBoardNote("arena", effects = "reduced")).noteFrames(170, 17)
        val report = entry.report("samsung SM-S918U", "16")!!
        assertEquals("android", report.getValue("p_platform").jsonPrimitive.content)
        assertEquals(55, report.getValue("p_build").jsonPrimitive.int)
        assertEquals("samsung SM-S918U", report.getValue("p_device").jsonPrimitive.content)
        assertEquals(6, report.getValue("p_ai_skill").jsonPrimitive.int)
        assertEquals("reduced", report.getValue("p_effects").jsonPrimitive.content)
        assertNull("Android has no moving worlds", report["p_table"])
        assertNull(report["p_motion"])
        val stats = report.stats()
        assertEquals(3.0, stats.number("minutes"), 0.0)
        assertEquals(2.0, stats.number("hottest"), 0.0)
        assertEquals(60.0, stats.number("secondsToWarm"), 0.0)
        assertEquals(60.0, stats.number("secondsToHot"), 0.0)
        assertEquals(2.2, stats.number("warmMinutes"), 0.0)
        assertEquals(2.2, stats.number("hotMinutes"), 0.0)
        assertEquals(40.0, stats.number("cpu"), 0.0)
        assertEquals(20.0, stats.number("cpuBoard"), 0.0)
        assertEquals(15.0, stats.number("cpuUpdates"), 0.0)
        assertEquals(5.0, stats.number("cpuAI"), 0.0)
        assertEquals(10.0, stats.number("slowFrames"), 0.0)
        assertEquals(3.0, stats.number("batteryUsed"), 0.0)
        assertEquals(30.0, stats.number("tempStart"), 0.0)
        assertEquals(33.0, stats.number("tempPeak"), 0.0)
        assertTrue(entry.line, entry.line.endsWith("CPU 40% (board 20, updates 15, AI 5), 10.0% slow frames, battery 3%, battery peak 33°C"))
    }

    @Test fun aPhoneOnAChargerSpentNoBattery() {
        val entry = played().let { it.absorb(it.lastSample!!, null, null, 0, onCharger = true) }
        val stats = entry.report("d", "s")!!.stats()
        assertNull(stats["batteryUsed"])
        assertTrue(stats.getValue("charging").jsonPrimitive.boolean)
    }

    @Test fun reportsNeedAWholeMinuteAndAnID() {
        assertTrue(played(minutes = 1).report("d", "s") != null)
        assertNull("under a minute says nothing", GamePerformanceEntry(1, "quick", id = "x", build = 55).report("d", "s"))
        assertNull("a record from an earlier build", played(id = null).report("d", "s"))
        assertNull(played(build = null).report("d", "s"))
    }

    /** A long gap is the app in the background: that time and its CPU don't count against the game. */
    @Test fun timeInTheBackgroundDoesntCount() {
        val start = 1_000_000_000L
        val entry = GamePerformanceEntry(start, "quick")
            .absorb(start, null, null, 0, cpu = CPUReading(10_000, 5_000, 0))
            .absorb(start + 10_000, null, null, 0, cpu = CPUReading(14_000, 7_000, 0))
            .absorb(start + 1_000_000, null, null, 1, cpu = CPUReading(60_000, 8_000, 0))
            .absorb(start + 1_010_000, null, null, 1, cpu = CPUReading(62_000, 9_000, 0))
        assertEquals(20_000L, entry.activeMillis)
        assertEquals(6_000L, entry.cpu?.total)
        assertEquals(3_000L, entry.cpu?.board)
        assertEquals(10.0 / 60, entry.warmMinutes, 0.001)
        assertEquals(10.0, entry.secondsToWarm!!, 0.0)
    }

    /** A game cut off (heat, memory, a force quit) still reports, up to its last saved minute. */
    @Test fun aGameTheAppNeverEndedStillCounts() {
        val saved = GamePerformanceLog.encode(played(thermal = 3))
        val cut = GamePerformanceLog.interrupted(GamePerformanceLog.decodeRunning(saved)!!)
        assertEquals(3.0, cut.minutes, 0.001)
        assertTrue(cut.report("d", "s")!!.stats().getValue("interrupted").jsonPrimitive.boolean)
        assertTrue(cut.line, cut.line.endsWith("cut short"))
        assertNull(GamePerformanceLog.decodeRunning("not json"))
    }

    @Test fun markingOneSentLeavesTheRest() {
        val entries = listOf(played(id = "a"), played(id = "b"))
        val text = GamePerformanceLog.markSent(entries, "b")
        assertEquals(listOf(false, true), GamePerformanceLog.decode(text).map { it.sent })
    }

    /** The name can hold spaces and brackets, and utime and stime are the 14th and 15th fields of the file. */
    @Test fun threadStatLinesAreRead() {
        val line = "4312 (AI-SIM-MAD - 5) S 1 4300 4300 0 -1 4194624 22 0 0 0 150 25 0 0 20 0 9 0 12345 0 0"
        assertEquals("AI-SIM-MAD - 5" to 175L, ThreadCPU.parse(line))
        assertEquals("a) b" to 3L, ThreadCPU.parse("7 (a) b) R 1 1 1 0 -1 0 0 0 0 0 1 2 0 0"))
        assertNull(ThreadCPU.parse("nonsense"))
        assertNull(ThreadCPU.parse("7 (short) R 1"))
        assertTrue(ThreadCPU.isSearchThread("AI-SIM-MAD - 5"))
        assertFalse(ThreadCPU.isSearchThread("ee-522377db2ea8"))
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
