package io.magicmobile.android

import androidx.test.platform.app.InstrumentationRegistry
import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Save/resume through the packaged JNI/AOT engine: a solo game writes nothing while it is played,
 * saves the human's priority decision when the app asks (the `checkpoint` op the app sends on
 * leaving), a fresh runtime restores it, and the same decision is asked again.
 * Skips until the packaged engine advertises `checkpointOnDemand` (after the native rebuild). It
 * uses its own folder, never the app's noBackupFilesDir/resume.
 */
class NativeCheckpointTest {
    @Test fun packagedEngineSavesOnRequestAndRestoresThePriorityDecision() {
        assertTrue("This test requires -PwithNative=true", BuildConfig.NATIVE_ENGINE)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val catalogue = Catalogue(context.assets.open("catalogue.jsonl"))
        val decks = Wire.decode(context.assets.open("precons.json").use { it.readBytes() }).array("decks").map { Deck.decode(Wire.objectValue(it)) }
        val human = decks.first { it.name.contains("Token Triumph", true) }
        val opponent = decks.first { it.name.contains("Grave Danger", true) }
        val folder = File(context.noBackupFilesDir, "resume-instrumentation-test").apply { deleteRecursively(); mkdirs() }
        val path = File(folder, "game.checkpoint")
        val temporary = File(folder, "game.checkpoint.tmp")
        var token = NativeBridge.open()
        assertTrue("Native isolate opens", token != 0L)
        fun request(op: String, vararg fields: Pair<String, Any?>) = Wire.result(NativeBridge.request(token, Wire.request(op, *fields)))
        fun close() {
            if (token == 0L) return
            var status = NativeBridge.close(token)
            repeat(30) { if (status != 0) { Thread.sleep(100); status = NativeBridge.close(token) } }
            assertEquals("Native runtime releases", 0, status)
            token = 0L
        }
        fun isPriority(decision: Decision?) = decision != null && !decision.submitted && decision.kind == "SELECT" && decision.payload["selectMode"] == "priority"
        /** The app's save loop: one-second requests until the engine answers anything but pending(engine). */
        fun save(match: String): Obj {
            val until = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
            while (true) {
                val reply = request("checkpoint", "matchId" to match, "waitMillis" to 1000L)
                if (reply["state"] != "pending" || reply["waitingFor"] != "engine" || System.nanoTime() > until) return reply
            }
        }
        try {
            val capabilities = request("capabilities")
            assumeTrue("The packaged engine does not advertise checkpointOnDemand yet; run this after the native rebuild",
                capabilities["saveResume"] == true && capabilities["checkpointOnDemand"] == true)
            val created = request("create", "configuration" to mapOf("seats" to listOf(
                mapOf("seatId" to "player-1", "name" to "You", "controller" to "human", "deck" to catalogue.resolve(human, false)),
                mapOf("seatId" to "player-2", "name" to "AI 1", "controller" to "ai", "aiSkill" to 1, "deck" to catalogue.resolve(opponent, false))),
                "checkpoint" to mapOf("path" to path.absolutePath)))
            val match = Wire.string(created["matchId"])
            val state = PollState(match, "player-1")
            val deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(10)
            var turn = 0L
            var priorityPoll: Obj? = null
            // Keep the opening hand and answer setup prompts until the first priority decision.
            while (System.nanoTime() < deadline) {
                val raw = request("poll", "matchId" to match, "viewerId" to "player-1", "after" to (state.current?.revision ?: 0L))
                val poll = GamePoll.parse(raw, match, "player-1")
                state.publish(poll)
                if (poll.phase == "failed") fail("Native game failed: ${poll.failure}")
                if (poll.phase == "ended") fail("The game ended before its first priority decision")
                val prompt = state.current?.decision
                if (isPriority(prompt)) {
                    priorityPoll = raw
                    turn = poll.snapshot?.obj("gameView")?.number("turn") ?: 0L
                    break
                }
                if (prompt != null && !prompt.submitted) {
                    val choices = Decisions.choices(prompt, poll.snapshot)
                    val choice = when (prompt.kind) {
                        "ASK" -> choices.firstOrNull { it.type == "boolean" && it.value == false }
                        "SELECT" -> choices.firstOrNull { it.type == "boolean" && it.value == true }
                        else -> choices.firstOrNull { it.type == "uuid" } ?: choices.firstOrNull()
                    }
                    val command = when {
                        choice != null -> state.prepare(choice.type, choice.value)
                        "integer" in prompt.responseTypes -> state.prepare("integer", maxOf(0L, prompt.minimum ?: 0L).coerceAtMost(prompt.maximum ?: Int.MAX_VALUE.toLong()))
                        else -> error("Unhandled real prompt ${prompt.kind}")
                    }
                    request("respond", "matchId" to match, "viewerId" to "player-1", "command" to command)
                    state.acknowledged()
                }
                Thread.sleep(30)
            }
            val parked = priorityPoll ?: error("No priority decision within 10 minutes")
            // Nothing is written while the game is played.
            assertNull("No checkpoint before a request", parked.obj("checkpoint"))
            assertFalse("No checkpoint file before a request", path.exists() || temporary.exists())
            // The app's request at the parked priority decision: the engine's GAME thread writes it.
            val started = System.nanoTime()
            val reply = save(match)
            val requestMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)
            assertEquals("The priority decision is saved: $reply", "saved", reply["state"])
            val saved = reply.obj("checkpoint")!!
            assertEquals(1L, Wire.integer(saved["sequence"]))
            assertTrue(path.isFile && Wire.integer(saved["bytes"]) == path.length() && !temporary.exists())
            assertEquals("The checkpoint names the decision's turn", turn, Wire.integer(saved["turn"]))
            assertEquals("A saved decision answers saved again without writing", saved, request("checkpoint", "matchId" to match, "waitMillis" to 0L).obj("checkpoint"))
            assertEquals(mapOf("cancelled" to true), request("cancelCheckpoint", "matchId" to match))
            android.util.Log.i("MagicMobileAcceptance", "Checkpoint on request: turn=$turn bytes=${path.length()} " +
                "writeMillis=${saved["writeMillis"]} requestMillis=$requestMillis")

            // A fresh runtime, as after process death: close it, reopen, restore.
            close()
            assertTrue("The engine never deletes its checkpoint", path.isFile)
            val bytes = path.readBytes()
            token = NativeBridge.open(); assertTrue(token != 0L)
            assertEquals(true, request("capabilities")["checkpointOnDemand"])
            val restoreStarted = System.nanoTime()
            val restored = request("restore", "checkpoint" to mapOf("path" to path.absolutePath))
            android.util.Log.i("MagicMobileAcceptance", "Restore took ${TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - restoreStarted)} ms")
            val resumed = Wire.string(restored["matchId"])
            assertEquals(turn, Wire.integer(restored.obj("restored")!!["turn"]))
            assertEquals(Wire.integer(saved["savedAtMillis"]), Wire.integer(restored.obj("restored")!!["savedAtMillis"]))
            val again = PollState(resumed, "player-1")
            val until = System.nanoTime() + TimeUnit.MINUTES.toNanos(2)
            while (System.nanoTime() < until) {
                val raw = request("poll", "matchId" to resumed, "viewerId" to "player-1", "after" to 0L)
                val poll = GamePoll.parse(raw, resumed, "player-1")
                again.publish(poll)
                if (poll.phase == "failed") fail("Restored game failed: ${poll.failure}")
                if (isPriority(again.current?.decision)) {
                    assertEquals(turn, poll.snapshot?.obj("gameView")?.number("turn"))
                    // A restore writes nothing by itself: polls describe the file it read.
                    assertEquals(1L, raw.obj("checkpoint")?.number("sequence"))
                    assertArrayEquals("The restored file is unchanged until a request", bytes, path.readBytes())
                    return
                }
                Thread.sleep(30)
            }
            fail("The restored game did not ask the checkpointed priority decision again")
        } finally {
            close()
            folder.deleteRecursively()
        }
    }
}
