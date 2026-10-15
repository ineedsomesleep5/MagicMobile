package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Test

/** Mirrors testAutoPassesShareOneLinePerRun in apps/ios/MagicMobileTests/OnDeviceMessageLogTests.swift. */
class AutoPassLogTest {
    @Test fun autoPassesShareOneLinePerRun() {
        val log = OnDeviceMessageLog()
        log.noteAutoPass("Upkeep", "p1")
        log.noteAutoPass("Draw", "p2")
        log.noteAutoPass("Draw", "p3")
        assertEquals(listOf("Auto-passed: Upkeep · Draw"), log.entries.map { it.message })
        assertEquals("local:auto-pass:p1", log.entries[0].id)
        // A copy (the session publishes copies) keeps the run going.
        val copy = log.copy()
        copy.noteAutoPass("Main 1", "p4")
        assertEquals(listOf("Auto-passed: Upkeep · Draw · Main 1"), copy.entries.map { it.message })
        for (step in listOf("A", "B", "C", "D", "E", "F", "G")) copy.noteAutoPass(step, step)
        assertEquals("Auto-passed: B · C · D · E · F · G", copy.entries.last().message)
    }
}
