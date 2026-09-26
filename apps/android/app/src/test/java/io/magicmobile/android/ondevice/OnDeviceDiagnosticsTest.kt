package io.magicmobile.android.ondevice

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** The local crash, ANR and engine report (OnDeviceDiagnosticsTests on iOS). */
class OnDeviceDiagnosticsTest {
    private val anrTrace = """
        ----- pid 4321 at 2026-09-25 18:00:00.000 -----
        Cmd line: com.calebfeliciano.magicmobile.android.debug
        Build fingerprint: 'google/sdk_gphone64_arm64/emu64a:15/AE3A.240806.019/12345:user/release-keys'

        "Signal Catcher" daemon prio=10 tid=6 Runnable
          at dalvik.system.VMStack.getThreadStackTrace(Native method)

        "main" prio=5 tid=1 Blocked
          | group="main" sCount=1 ucsCount=0 flags=1 obj=0x72a1c3b8 self=0xb400007
          | sysTid=4321 nice=-10 cgrp=top-app sched=0/0 handle=0x7f
          at io.magicmobile.android.session.OnDeviceSession.refresh(OnDeviceSession.kt:120)
          - waiting to lock <0x0f1e2d3c> (a java.lang.Object) held by thread 22
          at io.magicmobile.android.ondevice.OnDeviceRootViewKt.OnDeviceRoot(OnDeviceRootView.kt:200)
          native: #00 pc 000000000004a0e8  /apex/com.android.runtime/lib64/bionic/libc.so (syscall+24)

        "binder:4321_1" prio=5 tid=8 Native
          at android.os.BinderProxy.transactNative(Native method)
    """.trimIndent()

    @Test fun exitSummariesKeepOnlyTriageFields() {
        val version = "0.1.1 (2026092501)"; val platform = "Android 15 (API 35)"
        val anr = OnDeviceSystemReports.entry(OnDeviceSystemReports.Exit(1_758_823_200_000, 4321, OnDeviceSystemReports.REASON_ANR, 0,
            "Input dispatching timed out", 320 * 1024, 400 * 1024, anrTrace), version, platform)!!
        assertEquals("ANR", anr.kind)
        assertTrue(anr.text.startsWith("ANR · 2025-09-25T18:00:00Z\nSeen by app 0.1.1 (2026092501) · Android 15 (API 35)"))
        assertTrue(anr.text.contains("Reason: Input dispatching timed out"))
        assertTrue(anr.text.contains("Memory: PSS 320 MB · RSS 400 MB"))
        assertTrue(anr.text.contains("Main thread (Blocked):\n  0 at io.magicmobile.android.session.OnDeviceSession.refresh(OnDeviceSession.kt:120)\n" +
            "  1 - waiting to lock <0x0f1e2d3c> (a java.lang.Object) held by thread 22"))
        assertTrue(anr.text.contains("  3 native: #00 pc"))
        for (private in listOf("Build fingerprint", "sdk_gphone64", "com.calebfeliciano", "Signal Catcher", "binder:", "sysTid")) {
            assertFalse("Leaked $private", anr.text.contains(private))
        }
        val native = OnDeviceSystemReports.entry(OnDeviceSystemReports.Exit(1_758_823_300_000, 4400, OnDeviceSystemReports.REASON_CRASH_NATIVE, 11,
            null, 0, 0, null), version, platform)!!
        assertEquals("Native crash · 2025-09-25T18:01:40Z\nSeen by app 0.1.1 (2026092501) · Android 15 (API 35)\nSignal 11 (SIGSEGV)", native.text)
        val crash = OnDeviceSystemReports.entry(OnDeviceSystemReports.Exit(1_758_823_400_000, 4500, OnDeviceSystemReports.REASON_CRASH, 0,
            "crash\u0000 " + "x".repeat(400), 0, 0, null), version, platform)!!
        assertEquals("Crash", crash.kind)
        assertTrue(crash.text.lines().last().length <= "Reason: ".length + 300)
        assertFalse(crash.text.contains("\u0000"))
        // User-requested stops, low memory kills and the like are not crashes.
        assertNull(OnDeviceSystemReports.entry(OnDeviceSystemReports.Exit(1, 1, 10, 0, "user request", 0, 0, null), version, platform))
        assertNull(OnDeviceSystemReports.mainThread("no threads here"))
    }

    @Test fun exitSummariesAreDeduplicatedAndBounded() {
        val entries = (0 until 8).map { OnDeviceSystemReports.Entry("Crash", "4-$it-1", it.toLong(), "crash $it") }
        var saved = OnDeviceSystemReports.merged(emptyList(), entries.take(2))
        saved = OnDeviceSystemReports.merged(saved, entries.take(2))
        assertEquals("A repeated exit is kept once", listOf("crash 0", "crash 1"), saved.map { it.text })
        saved = OnDeviceSystemReports.merged(saved, entries.reversed())
        assertEquals((3 until 8).map { "crash $it" }, saved.map { it.text })
        assertNull(OnDeviceSystemReports.section(emptyList()))
        assertTrue(OnDeviceSystemReports.section(saved)!!.startsWith("MagicMobile crash and ANR reports (5, newest last, from Android on this phone)"))
    }

    private fun temporaryDirectory(): File = Files.createTempDirectory("diagnostics").toFile().also { it.deleteOnExit() }

    @Test fun crashAndAnrReportsJoinTheSharedReportAndAreDeleted() {
        val directory = temporaryDirectory()
        val platform = "Android 15 (API 35)"
        val store = OnDeviceDiagnostics(directory, "0.1.1 (2026092501)", platform)
        assertNull(store.report)
        val exit = OnDeviceSystemReports.Exit(1_758_823_200_000, 4321, OnDeviceSystemReports.REASON_ANR, 0, "Input dispatching timed out", 0, 0, anrTrace)
        assertTrue(OnDeviceSystemReports.record(listOf(exit), directory, "0.1.1 (2026092501)", platform))
        assertFalse("Already saved", OnDeviceSystemReports.record(listOf(exit), directory, "0.1.1 (2026092501)", platform))
        store.reloadSystemReports()
        val anrOnly = store.report!!
        assertTrue(anrOnly.startsWith("MagicMobile crash and ANR reports (1"))
        assertTrue("Exit reports describe an earlier session", store.isHistorical)
        store.save("engine failure", "Game stopped")
        val combined = store.report!!
        assertTrue(combined.startsWith("MagicMobile local engine diagnostic\nApp: 0.1.1 (2026092501)\nOS: Android 15 (API 35)"))
        assertTrue(combined.contains("engine failure"))
        assertTrue("The export carries the engine report, then crashes and ANRs", combined.endsWith(anrOnly))
        assertFalse(store.isHistorical)
        val reopened = OnDeviceDiagnostics(directory, "0.1.1 (2026092501)", platform)
        assertEquals(combined, reopened.report)
        assertTrue(reopened.isHistorical)
        reopened.clear()
        assertNull(reopened.report)
        assertTrue(directory.listFiles().isNullOrEmpty())
        assertNull(OnDeviceDiagnostics(directory, "0.1.1 (2026092501)", platform).report)
    }

    @Test fun engineReportIsBoundedAndReopeningKeepsItsTimestamp() = runBlocking {
        val directory = temporaryDirectory()
        val store = OnDeviceDiagnostics(directory, "0.1.1 (1)", "Android 15 (API 35)")
        store.save("🦊".repeat(100_000), "Game stopped")
        val report = store.report!!
        assertTrue(report.toByteArray(Charsets.UTF_8).size <= OnDeviceDiagnostics.MAX_BYTES)
        assertFalse(report.contains("�"))
        val incident = "[local-engine-incident] invalid_deck\nOccurred: 2026-09-15T01:02:03Z"
        store.save(incident, "First failure")
        val original = store.report
        store.beginAttempt()
        assertTrue(store.isHistorical)
        store.capture("Different status") { incident }
        assertEquals(original, store.report)
        store.clear { }
        assertNull(store.report)
        assertTrue(directory.listFiles().isNullOrEmpty())
    }
}
