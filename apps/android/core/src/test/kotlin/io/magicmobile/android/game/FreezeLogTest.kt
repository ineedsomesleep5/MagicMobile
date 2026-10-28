package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** freeze-cases.json and the freeze log's pure parts (docs/FREEZE_LOG.md; iOS FreezeLogTests). */
class FreezeLogTest {
    private val root = Json.parseToJsonElement(
        File(generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory },
            "apps/android/core/src/test/resources/parity/freeze-cases.json").readText()).jsonObject
    private val cases = root["cases"]!!.jsonArray

    @Test fun sharedCases() {
        assertTrue(cases.size >= 10)
        for (case in cases) {
            val name = case.jsonObject["name"]!!.jsonPrimitive.content
            val input = case.jsonObject["input"]!!.jsonObject
            val pending = input["answerPendingSeconds"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.double }
            val result = FreezeRules.stall(input["inGame"]!!.jsonPrimitive.boolean, input["over"]!!.jsonPrimitive.boolean,
                input["waitingOnYou"]!!.jsonPrimitive.boolean, pending, input["quietSeconds"]!!.jsonPrimitive.double,
                input["withPeople"]!!.jsonPrimitive.boolean, input["waitingOnPerson"]?.jsonPrimitive?.boolean ?: false)
            val expected = case.jsonObject["expect"].let { if (it == null || it is JsonNull) null else (it as JsonPrimitive).content }
            assertEquals(name, expected, result)
        }
        val asks = root["askCases"]!!.jsonArray
        assertTrue(asks.isNotEmpty())
        for (case in asks) {
            val fields = case.jsonObject
            val duration = fields["duration"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.double }
            assertEquals(fields["name"]!!.jsonPrimitive.content, fields["expect"]!!.jsonPrimitive.boolean,
                FreezeRules.worthAsking(fields["kind"]!!.jsonPrimitive.content, duration))
        }
        val mayAsks = root["mayAskCases"]!!.jsonArray
        assertTrue(mayAsks.isNotEmpty())
        for (case in mayAsks) {
            val fields = case.jsonObject
            val since = fields["secondsSinceAsked"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.double }
            assertEquals(fields["name"]!!.jsonPrimitive.content, fields["expect"]!!.jsonPrimitive.boolean, FreezeRules.mayAsk(since))
        }
    }

    @Test fun aStallIsRecordedOncePerEpisode() {
        val tracker = FreezeStallTracker(0.0)
        assertNull(tracker.check(119.0, true, false, false, false))
        assertEquals(FreezeRules.ENGINE_QUIET, tracker.check(120.0, true, false, false, false))
        assertNull(tracker.check(400.0, true, false, false, false))
        // A new snapshot is progress: the next stall counts again.
        tracker.changed(400.0)
        assertNull(tracker.check(500.0, true, false, false, false))
        assertEquals(FreezeRules.ENGINE_QUIET, tracker.check(520.0, true, false, false, false))

        tracker.restart(1000.0)
        tracker.answerSent(1001.0)
        tracker.answerSent(1010.0)  // a retry keeps the first send's time
        assertEquals(FreezeRules.ANSWER_NOT_ACCEPTED, tracker.check(1021.0, true, false, true, false))
        assertNull(tracker.check(1030.0, true, false, true, false))
        tracker.answerLanded()
        assertNull(tracker.answerPendingSeconds(1030.0))
        assertNull(tracker.check(1030.0, true, false, true, false))
    }

    @Test fun breadcrumbsKeepTheLastEighty() {
        val crumbs = FreezeBreadcrumbs()
        repeat(100) { crumbs.add(it.toDouble(), "step $it") }
        val lines = crumbs.snapshot()
        assertEquals(80, lines.size)
        assertEquals("+20.0s step 20", lines.first())
        assertEquals("+99.0s step 99", lines.last())
        crumbs.add(12.34, "line\nbreak " + "x".repeat(400))
        val last = crumbs.snapshot().last()
        assertTrue(last.startsWith("+12.3s line break "))
        assertFalse(last.contains('\n'))
        assertEquals("+12.3s ".length + FreezeBreadcrumbs.MAX_LINE, last.length)
    }

    @Test fun storeRoundTripsAndKeepsTheLastFive() {
        val directory = Files.createTempDirectory("freeze-log").toFile()
        try {
            val store = FreezeStore(File(directory, "Diagnostics"))
            assertEquals(emptyList<FreezeIncident>(), store.load())
            val first = FreezeIncident("a", FreezeRules.HANG, 1_761_300_000_000, 3.25, listOf("App" to "0.1.1 (30)", "Mode" to "ranked"),
                listOf("+1.0s Game started (ranked)", "+2.5s Sent Pass"))
            store.save(listOf(first))
            assertEquals(listOf(first), store.load())
            val saved = store.update { it.map { incident -> incident.copy(sent = true) } + (1..6).map { n ->
                FreezeIncident("n$n", FreezeRules.ENGINE_QUIET, 1_761_300_000_000 + n, null) } }
            assertEquals(5, saved.size)
            assertEquals(listOf("n2", "n3", "n4", "n5", "n6"), store.load().map { it.id })
            // A damaged file reads as empty, never as an error.
            File(directory, "Diagnostics/${FreezeStore.FILE_NAME}").writeText("{")
            assertEquals(emptyList<FreezeIncident>(), store.load())
            store.clear()
            assertFalse(File(directory, "Diagnostics/${FreezeStore.FILE_NAME}").exists())
        } finally { directory.deleteRecursively() }
    }

    @Test fun reportText() {
        val hang = FreezeIncident("h", FreezeRules.HANG, 1_761_300_000_000, 4.0, listOf("App" to "0.1.1 (30)", "Waiting on you" to "no"),
            listOf("+1.0s Game started (quick)"))
        val text = FreezeReport.incident(hang)
        assertTrue(text.startsWith("Freeze · hang · 2025-10-24T10:00:00Z\nMain thread stuck for 4.0 s\nApp: 0.1.1 (30)\nWaiting on you: no\n"))
        assertTrue(text.endsWith("Breadcrumbs (oldest first):\n  +1.0s Game started (quick)"))
        assertTrue(FreezeReport.incident(hang.copy(durationSeconds = null)).contains("had not recovered"))
        assertTrue(FreezeReport.incident(hang.copy(kind = FreezeRules.REPORTED, sent = true)).startsWith("Freeze · reported · 2025-10-24T10:00:00Z · sent\nApp:"))

        val sent = FreezeReport.sent(hang, "MagicMobile crash and ANR reports (1)")
        assertTrue(sent.startsWith("MagicMobile freeze report\n\nFreeze · hang"))
        assertTrue(sent.endsWith("\n\nMagicMobile crash and ANR reports (1)"))
        assertEquals(FreezeReport.MAX_CHARACTERS, FreezeReport.sent(hang, "x".repeat(100_000)).length)

        assertNull(FreezeReport.section(emptyList()))
        assertTrue(FreezeReport.section(listOf(hang, hang))!!.startsWith("Freeze log (2, newest last)\n\nFreeze · hang"))
    }
}
