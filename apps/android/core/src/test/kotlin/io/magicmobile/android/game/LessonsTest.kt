package io.magicmobile.android.game

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/** The lessons' recordings (scripts/lessons/record.py) played through LessonTransport; iOS LessonsTests checks the same. */
class LessonsTest {
    private val repo = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "apps/android").isDirectory }
    private val lessons = File(repo, "apps/ios/MagicMobile/Resources/Lessons")
    private fun script(id: String) = LessonScript(EngineJson.decode(File(lessons, "lesson-$id.json").readBytes()))

    private class Recorder : LessonListener {
        var nudges = 0
        var last: LessonFrame? = null
        override fun show(frame: LessonFrame) { last = frame }
        override fun nudge() { nudges += 1 }
    }

    @Test fun everyLessonPlaysThroughWithItsRecordedMoves() = runBlocking {
        val ids = LessonCatalog.parse(File(lessons, "lessons.json").readBytes()).map { it.id }
        assertEquals(listOf("first-spells", "combat", "stack", "commander", "table"), ids)
        for (id in ids) {
            val script = script(id)
            var now = 0L
            val transport = LessonTransport(script, Recorder()) { now }
            val client = EngineClient(transport)
            val match = client.create(JsonObject(emptyMap()))["matchId"].string!!
            var moves = 0
            var steps = 0
            while (true) {
                assertTrue("$id never finished", ++steps < 500)
                val poll = client.poll(match, script.viewer)
                val (index, waits, expect) = transport.position
                if (poll.phase == "ended" || index == script.frames.size - 1 && expect == null && !waits) break
                if (waits) { transport.release(); continue }
                if (expect != null) {
                    val prompt = assertNotNullAndGet(poll.prompt, "$id frame $index waits for a move with no question open")
                    client.respond(match, script.viewer, prompt, expect)
                    moves += 1
                } else {
                    assertNull("$id frame $index moves on by itself but asks something", poll.prompt)
                    now += 2000
                }
            }
            assertEquals(id, script.frames.count { it.expect != null }, moves)
            assertTrue(id, script.frames.last().complete || script.frames.last().ended)
        }
    }

    @Test fun noLibraryShowsAFullDeck() {
        for (id in LessonCatalog.parse(File(lessons, "lessons.json").readBytes()).map { it.id }) {
            for (frame in script(id).frames) for (player in frame.poll["snapshot"]["gameView"]["players"].array!!) {
                assertTrue("$id: ${player["name"].string}", (player["libraryCount"].integer ?: 0) < 100)
            }
        }
    }

    @Test fun aWrongMoveIsTurnedDownAndNudges() = runBlocking {
        val script = script("first-spells")
        var now = 0L
        val listener = Recorder()
        val transport = LessonTransport(script, listener) { now }
        val client = EngineClient(transport)
        val match = client.create(JsonObject(emptyMap()))["matchId"].string!!
        var poll = client.poll(match, script.viewer)
        while (transport.position.third == null) { transport.release(); now += 2000; poll = client.poll(match, script.viewer) }
        try {
            client.respond(match, script.viewer, poll.prompt!!, EnginePrompt.answer("boolean", JsonPrimitive(true)))
            fail("A pass instead of the land was accepted")
        } catch (error: EngineError.Rejected) {
            assertEquals("lesson_wrong_move", error.code)
        }
        assertEquals(1, listener.nudges)
        assertNotNull(transport.position.third)
    }

    @Test fun eitherOfTwoForestsPaysAndTheRecordingFollows() = runBlocking {
        val script = script("first-spells")
        var now = 0L
        val transport = LessonTransport(script, Recorder()) { now }
        val client = EngineClient(transport)
        val match = client.create(JsonObject(emptyMap()))["matchId"].string!!
        while (true) {
            val poll = client.poll(match, script.viewer)
            val (_, waits, expect) = transport.position
            if (waits) { transport.release(); continue }
            val prompt = poll.prompt
            if (expect == null || prompt == null) { now += 2000; continue }
            if (prompt.kind == "PLAY_MANA") {
                val recorded = expect["value"].string!!
                val mine = poll.snapshot["gameView"]["players"].array!!.first { it["name"].string == "You" }
                val other = mine["battlefield"].obj!!.entries.first { it.key != recorded && it.value["name"].string == "Forest" }.key
                client.respond(match, script.viewer, prompt, EnginePrompt.answer("uuid", JsonPrimitive(other)))
                val next = client.poll(match, script.viewer)
                val tapped = next.snapshot["gameView"]["players"].array!!.first { it["name"].string == "You" }["battlefield"][other]["tapped"].bool
                assertEquals("The Forest the player tapped shows tapped", true, tapped)
                return@runBlocking
            }
            client.respond(match, script.viewer, prompt, expect)
        }
    }

    @Test fun theTableLessonAsksForBothSwaps() {
        assertEquals(listOf("Bryn", "Rook"), script("table").frames.mapNotNull { it.focus })
    }

    @Test fun theCoachPointsAtTheExpectedCardByName() {
        val frame = script("first-spells").frames.first { it.coach?.spot == "Forest" && it.expect != null }
        assertEquals(setOf(frame.expect["value"].string!!), LessonSpot.resolve("Forest", frame.poll, frame.expect).ids)
        assertEquals("primary", LessonSpot.resolve("primary", frame.poll, null).control)
    }

    private fun <T> assertNotNullAndGet(value: T?, message: String): T { assertNotNull(message, value); return value!! }
}
