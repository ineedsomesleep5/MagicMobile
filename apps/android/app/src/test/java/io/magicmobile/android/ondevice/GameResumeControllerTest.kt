package io.magicmobile.android.ondevice

import io.magicmobile.android.game.EngineCheckpoint
import io.magicmobile.android.game.EngineCheckpointResult
import io.magicmobile.android.game.EngineClient
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.EngineTransport
import io.magicmobile.android.game.GameResumeLaunch
import io.magicmobile.android.game.GameResumeSettings
import io.magicmobile.android.game.GameResumeSidecar
import io.magicmobile.android.game.GameResumeStore
import io.magicmobile.android.game.GameResumeText
import io.magicmobile.android.game.J
import io.magicmobile.android.game.MatchPoll
import io.magicmobile.android.game.get
import io.magicmobile.android.game.jsonObject
import io.magicmobile.android.game.string
import io.magicmobile.android.session.OnDeviceSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.concurrent.Executor

/**
 * The app side of save/resume against fake engines: a temporary folder, a fixed clock and file
 * work run inline. The real engine with checkpoint support is exercised by NativeCheckpointTest.
 */
class GameResumeControllerTest {
    private val root: File = Files.createTempDirectory("mm-resume-app").toFile()
    private var now = 1_800_000_000_000L
    /** The monotonic clock for the background save's deadline; the fake engine advances it by each wait. */
    private var uptime = 100_000L
    private val store = GameResumeStore(File(root, "resume")) { now }
    private val inline = Executor { it.run() }
    private val controller = GameResumeController(store, "2026092601", inline) { uptime }
    private val engineIdentity = "xmage/protocol-1/abc123/hash9"

    @After fun cleanUp() { root.deleteRecursively() }

    /** Today's shipped engines: they save at every decision. */
    private val newEngine = jsonObject("protocol" to JsonPrimitive(1), "engine" to JsonPrimitive("xmage"), "upstream" to JsonPrimitive("abc123"),
        "catalogueHash" to JsonPrimitive("hash9"), "saveResume" to JsonPrimitive(true))
    /** Engines that save only when asked. */
    private val onDemandEngine = JsonObject(newEngine + ("checkpointOnDemand" to JsonPrimitive(true)))
    private val oldEngine = JsonObject(newEngine + ("saveResume" to JsonPrimitive(false)))
    private fun seat(id: String, name: String, controller: String): J = jsonObject("seatId" to JsonPrimitive(id), "name" to JsonPrimitive(name),
        "controller" to JsonPrimitive(controller), "deck" to jsonObject("name" to JsonPrimitive("deck")))
    private val seats = listOf(seat("player1", "Caleb", "human"), seat("player2", "AI 1", "ai"))
    private val configuration = jsonObject("seats" to JsonArray(seats))
    private val settings = GameResumeSettings("precon:token-triumph", listOf("grave-danger"), 3, "choose")

    private fun poll(phase: String = "running", checkpoint: J? = null) = MatchPoll(JsonObject(linkedMapOf<String, J>("matchId" to JsonPrimitive("m"),
        "viewerId" to JsonPrimitive("player1"), "revision" to JsonPrimitive(1), "phase" to JsonPrimitive(phase), "resyncRequired" to JsonPrimitive(false),
        "snapshot" to JsonNull, "prompt" to JsonNull).apply { checkpoint?.let { put("checkpoint", it) } }))
    private fun checkpoint(sequence: Long, saved: Long, turn: Long) = jsonObject("sequence" to JsonPrimitive(sequence),
        "savedAtMillis" to JsonPrimitive(saved), "turn" to JsonPrimitive(turn), "bytes" to JsonPrimitive(1234))

    private fun startCheckpointedGame() {
        val path = controller.checkpointFor(newEngine, seats)
        assertNotNull(path)
        controller.gameStarted(configuration, path, newEngine, "player1", "Token Triumph", settings)
        store.checkpointFile.writeBytes(byteArrayOf(1, 2, 3)) // the engine's write
    }

    private fun assertNoFiles() {
        assertFalse(store.checkpointFile.exists()); assertFalse(store.sidecarFile.exists()); assertFalse(store.markerFile.exists())
    }

    @Test fun capabilityGatesTheCheckpointField() {
        assertEquals(jsonObject("path" to JsonPrimitive(store.checkpointFile.absolutePath)), controller.checkpointFor(newEngine, seats))
        assertNull("engines without saveResume never see the field", controller.checkpointFor(oldEngine, seats))
        assertNull(controller.checkpointFor(JsonObject(newEngine - "saveResume"), seats))
        assertNull("only one human seat", controller.checkpointFor(newEngine, seats + seat("player3", "Alex", "human")))
        assertNull("previews have no resume folder", GameResumeController(null, "1", inline).checkpointFor(newEngine, seats))
    }

    @Test fun startingACheckpointedGameWritesTheSidecar() {
        startCheckpointedGame()
        val sidecar = store.read()!!
        assertEquals("2026092601", sidecar.appBuild)
        assertEquals(engineIdentity, sidecar.engineIdentity)
        assertEquals(now, sidecar.createdAt); assertEquals(now, sidecar.lastCheckpointAt); assertNull(sidecar.leftAt)
        assertEquals("Token Triumph", sidecar.playerDeckName)
        assertEquals(listOf("AI 1"), sidecar.opponents)
        assertEquals(settings, sidecar.settings)
        assertEquals(configuration, sidecar.setup["configuration"])
        assertTrue(controller.isCheckpointing)
        assertFalse(store.markerFile.exists())
    }

    @Test fun anEngineWithoutSaveResumeKeepsOnlyTheMarker() {
        controller.gameStarted(configuration, controller.checkpointFor(oldEngine, seats), oldEngine, "player1", "Token Triumph", settings)
        assertFalse(controller.isCheckpointing)
        assertTrue(store.markerFile.exists())
        assertFalse(store.sidecarFile.exists())
        // Process death: the next launch explains the lost game once.
        val next = GameResumeController(store, "2026092601", inline)
        runBlocking { next.checkAtLaunch(engineIdentity) }
        assertEquals(GameResumeText.LOST, next.notice)
        assertNull(next.offer)
        assertNoFiles()
    }

    @Test fun relayTablesNeverCheckpointAndClearTheMarkerWhenTheyEnd() {
        controller.tableStarted()
        assertTrue(store.markerFile.exists())
        controller.observe(poll(checkpoint = checkpoint(1, now, 2)))
        assertFalse("a table poll never creates a sidecar", store.sidecarFile.exists())
        controller.observe(poll(phase = "ended"))
        assertNoFiles()
    }

    @Test fun pollsUpdateTheSidecarOnlyForNewerCheckpoints() {
        startCheckpointedGame()
        controller.observe(poll(checkpoint = checkpoint(3, now + 5_000, 4)))
        assertEquals(4L, store.read()!!.turn)
        assertEquals(now + 5_000, store.read()!!.lastCheckpointAt)
        controller.observe(poll(checkpoint = checkpoint(2, now + 9_000, 9)))
        assertEquals("an older sequence is ignored", 4L, store.read()!!.turn)
        controller.observe(poll())
        assertEquals(4L, store.read()!!.turn)
    }

    @Test fun aPlayerOutOfAPodCannotGoBackToAnEarlierCheckpoint() {
        startCheckpointedGame()
        controller.observe(MatchPoll(JsonObject(poll().raw.jsonObjectMap() + ("snapshot" to jsonObject("enginePlayerId" to JsonPrimitive("u1"),
            "gameView" to jsonObject("players" to JsonArray(listOf(jsonObject("playerId" to JsonPrimitive("u1"), "hasLeft" to JsonPrimitive(true))))))))))
        assertNoFiles()
        // The spectated game goes on; its polls write nothing more.
        controller.observe(poll(checkpoint = checkpoint(9, now, 20)))
        controller.backgrounded()
        assertNoFiles()
    }

    private fun J.jsonObjectMap(): Map<String, J> = this as JsonObject

    @Test fun leavingSetsLeftAtAndReturningClearsIt() {
        startCheckpointedGame()
        now += 1_000
        controller.backgrounded()
        assertEquals(now, store.read()!!.leftAt)
        controller.foregrounded()
        assertNull(store.read()!!.leftAt)
        // A game that is not checkpointed writes nothing.
        controller.discard()
        controller.backgrounded()
        assertFalse(store.sidecarFile.exists())
    }

    @Test fun endingConcedingLeavingOrStartingAnotherGameDeletesBothFiles() {
        startCheckpointedGame()
        controller.observe(poll(phase = "ended"))
        assertNoFiles()
        assertFalse(controller.isCheckpointing)
        // Concede, leave and a new game all discard.
        for (step in listOf("concede", "leave", "new game")) {
            startCheckpointedGame()
            assertTrue(step, store.sidecarFile.exists() && store.checkpointFile.exists())
            controller.discard()
            assertNoFiles()
        }
    }

    @Test fun launchOffersAResumableGameOnceAndAbandonDeletesIt() = runBlocking {
        startCheckpointedGame()
        controller.observe(poll(checkpoint = checkpoint(1, now, 12)))
        controller.backgrounded()
        now += 180_000
        val next = GameResumeController(store, "2026092601", inline)
        next.checkAtLaunch(engineIdentity)
        assertEquals("Turn 12 against AI 1 · saved 3 min ago", next.offer?.detail)
        now += 3_600_000
        next.checkAtLaunch(engineIdentity)
        assertNotNull("checked once per launch; the prompt stays", next.offer)
        next.abandon()
        assertNull(next.offer)
        assertNoFiles()
    }

    @Test fun launchNoticesExpiryAndUpdates() = runBlocking {
        startCheckpointedGame(); controller.backgrounded()
        now += 601_000
        val expired = GameResumeController(store, "2026092601", inline)
        expired.checkAtLaunch(engineIdentity)
        assertEquals(GameResumeText.EXPIRED, expired.notice)
        assertNoFiles()
        startCheckpointedGame(); controller.backgrounded()
        val updated = GameResumeController(store, "2026092701", inline)
        updated.checkAtLaunch(engineIdentity)
        assertEquals(GameResumeText.UPDATED, updated.notice)
        assertNoFiles()
        val preview = GameResumeController(null, "2026092601", inline)
        preview.checkAtLaunch(engineIdentity)
        assertNull(preview.notice); assertNull(preview.offer)
    }

    /** A fake engine behind the resume flow; `restoreReply` is the engine's whole reply to `restore`. */
    private inner class FakeResume(var caps: J? = newEngine, var restoreReply: J = ok(jsonObject("matchId" to JsonPrimitive("restored-match"),
        "seats" to JsonArray(listOf(JsonPrimitive("player1"), JsonPrimitive("player2"))),
        "restored" to jsonObject("turn" to JsonPrimitive(12), "savedAtMillis" to JsonPrimitive(1_799_999_990_000L)))),
        var attachFails: Boolean = false) : GameResumeController.ResumeEngine {
        val requests = ArrayList<J>()
        var attached: Pair<String, String>? = null
        var cleanedUp = false
        val client = EngineClient(object : EngineTransport {
            override suspend fun request(data: ByteArray): ByteArray {
                val request = EngineJson.decode(data); requests += request
                return EngineJson.encode(if (request["op"].string == "restore") restoreReply else ok(jsonObject()))
            }
        })
        override suspend fun open(): EngineClient = client
        override val capabilities: J? get() = caps
        override suspend fun restore(client: EngineClient, path: String): J = client.restore(path)
        override suspend fun attach(client: EngineClient, matchID: String, seatID: String) {
            if (attachFails) throw EngineError.InvalidMessage("first poll failed")
            attached = matchID to seatID
        }
        override suspend fun cleanup() { cleanedUp = true }
    }
    private fun ok(result: J): J = jsonObject("protocol" to JsonPrimitive(1), "ok" to JsonPrimitive(true), "result" to result)
    private fun rejected(code: String): J = jsonObject("protocol" to JsonPrimitive(1), "ok" to JsonPrimitive(false),
        "error" to jsonObject("code" to JsonPrimitive(code), "message" to JsonPrimitive("Checkpoint problem")))

    private suspend fun offered(): Pair<GameResumeController, GameResumeSidecar> {
        startCheckpointedGame(); controller.backgrounded()
        now += 60_000
        val next = GameResumeController(store, "2026092601", inline)
        next.checkAtLaunch(engineIdentity)
        return next to next.accept()!!
    }

    @Test fun resumeRestoresTheCheckpointAndAttachesTheSavedSeat() = runBlocking {
        val (next, sidecar) = offered()
        assertNull("accepting removes the prompt", next.offer)
        val engine = FakeResume()
        assertTrue(next.resume(sidecar, engine))
        assertEquals(jsonObject("protocol" to JsonPrimitive(1), "op" to JsonPrimitive("restore"),
            "checkpoint" to jsonObject("path" to JsonPrimitive(store.checkpointFile.absolutePath))), engine.requests.single())
        assertEquals("restored-match" to "player1", engine.attached)
        assertEquals(GameResumeText.RESUMED, next.notice)
        assertTrue(next.resumedGame && next.isCheckpointing)
        val saved = store.read()!!
        assertNull(saved.leftAt)
        assertEquals(12L, saved.turn)
        assertEquals(1_799_999_990_000L, saved.lastCheckpointAt)
        assertFalse(engine.cleanedUp)
        // The resumed game keeps saving, and ends like any other.
        next.observe(poll(checkpoint = checkpoint(1, now, 13)))
        assertEquals(13L, store.read()!!.turn)
        next.observe(poll(phase = "ended"))
        assertNoFiles()
        assertFalse(next.resumedGame)
    }

    @Test fun anEngineWithoutSaveResumeCannotResume() = runBlocking {
        val (next, sidecar) = offered()
        val engine = FakeResume(caps = oldEngine)
        assertFalse(next.resume(sidecar, engine))
        assertTrue("the restore op never reaches an engine without saveResume", engine.requests.isEmpty())
        assertTrue(engine.cleanedUp)
        assertEquals(GameResumeText.RESUME_FAILED, next.notice)
        assertNoFiles()
    }

    @Test fun restoreFailuresCleanUpDeleteAndSaySo() = runBlocking {
        for (code in listOf("checkpoint_unavailable", "checkpoint_incompatible", "checkpoint_corrupt")) {
            val (next, sidecar) = offered()
            val engine = FakeResume(restoreReply = rejected(code))
            assertFalse(code, next.resume(sidecar, engine))
            assertTrue(code, engine.cleanedUp)
            assertNull(code, engine.attached)
            assertEquals(code, GameResumeText.RESUME_FAILED, next.notice)
            assertFalse(next.resumedGame)
            assertNoFiles()
        }
        // A reply without `restored` is not a resumed game either, nor is a board that cannot attach.
        for (engine in listOf(FakeResume(restoreReply = ok(jsonObject("matchId" to JsonPrimitive("m")))), FakeResume(attachFails = true))) {
            val (next, sidecar) = offered()
            assertFalse(next.resume(sidecar, engine))
            assertTrue(engine.cleanedUp)
            assertEquals(GameResumeText.RESUME_FAILED, next.notice)
            assertFalse(next.isCheckpointing)
            assertNoFiles()
        }
    }

    /** The session hands every applied poll to the controller: a checkpoint lands in the sidecar, the end deletes it. */
    @Test fun sessionPollsReachTheSidecar() = runBlocking {
        startCheckpointedGame()
        var phase = "running"
        val engine = object : EngineTransport {
            var revision = 1L
            override suspend fun request(data: ByteArray): ByteArray {
                val request = EngineJson.decode(data)
                val result: J = when (request["op"].string) {
                    "poll" -> JsonObject(mapOf("matchId" to JsonPrimitive("m"), "viewerId" to JsonPrimitive("player1"),
                        "revision" to JsonPrimitive(revision++), "phase" to JsonPrimitive(phase), "resyncRequired" to JsonPrimitive(false),
                        "snapshot" to JsonNull, "prompt" to JsonNull, "checkpoint" to checkpoint(revision, now + revision, 7)))
                    else -> jsonObject()
                }
                return EngineJson.encode(ok(result))
            }
        }
        val job = SupervisorJob()
        val session = OnDeviceSession(CoroutineScope(coroutineContext + job))
        try {
            session.attach(EngineClient(engine), "m", "player1", autoPoll = false, observe = controller::observe) {}
            assertEquals(7L, store.read()!!.turn)
            phase = "ended"
            session.refresh()
            assertNoFiles()
        } finally { job.cancel() }
    }

    @Test fun offerIsAnExplicitChoice() {
        // Nothing resumes on its own: the launch check only offers.
        startCheckpointedGame(); controller.backgrounded()
        val next = GameResumeController(store, "2026092601", inline)
        runBlocking { next.checkAtLaunch(engineIdentity) }
        assertTrue(next.offer is GameResumeLaunch.Offer)
        assertFalse(next.resumedGame)
        assertTrue(store.checkpointFile.exists() && store.sidecarFile.exists())
    }

    // Saving when the player leaves (engines with checkpointOnDemand).

    /**
     * The engine side of saving on leaving. Each request takes the next scripted result (the last
     * one repeats) and advances [uptime] by its wait, as the engine waits. A saved result writes the
     * checkpoint unless [writesFile] is false (a decision saved earlier).
     */
    private inner class FakeSave(vararg results: EngineCheckpointResult) : GameResumeController.SaveEngine {
        val results = results.toMutableList()
        var writesFile = true
        var throws = false
        val waits = ArrayList<Int>()
        var cancels = 0
        var onRequest: () -> Unit = {}
        override suspend fun checkpoint(waitMillis: Int): EngineCheckpointResult {
            waits += waitMillis; uptime += waitMillis; onRequest()
            if (throws) throw EngineError.RuntimeFailure(3)
            val result = if (results.size > 1) results.removeAt(0) else results[0]
            if (result is EngineCheckpointResult.Saved && writesFile) store.checkpointFile.writeBytes(byteArrayOf(waits.size.toByte()))
            return result
        }
        override suspend fun cancel() { cancels++ }
    }

    private fun saved(sequence: Long, turn: Long, at: Long = now) = EngineCheckpointResult.Saved(EngineCheckpoint(sequence, at, turn, 600_000, 40))

    private fun startOnDemandGame(on: GameResumeController = controller) {
        val path = on.checkpointFor(onDemandEngine, seats)
        assertNotNull(path)
        on.gameStarted(configuration, path, onDemandEngine, "player1", "Token Triumph", settings)
        assertTrue(on.savesOnDemand)
        assertFalse("nothing is saved while the player plays", store.checkpointFile.exists())
    }

    private fun relaunch(): GameResumeController =
        GameResumeController(store, "2026092601", inline) { uptime }.also { runBlocking { it.checkAtLaunch(engineIdentity) } }

    @Test fun leavingSavesAndTheNextLaunchOffersIt() = runBlocking {
        startOnDemandGame()
        now += 42_000
        val engine = FakeSave(EngineCheckpointResult.WaitingForEngine, EngineCheckpointResult.WaitingForEngine, saved(3, 5))
        assertTrue(controller.backgrounded())
        assertEquals("leftAt is written before the engine is asked", now, store.read()!!.leftAt)
        controller.saveForBackground(engine)
        assertEquals("asks again while the AI is thinking", listOf(1000, 1000, 1000), engine.waits)
        val sidecar = store.read()!!
        assertEquals(5L, sidecar.turn); assertEquals(now, sidecar.lastCheckpointAt); assertEquals(now, sidecar.leftAt)
        assertTrue(store.checkpointFile.exists())
        // Android ends the process while the app is away.
        now += 60_000
        assertEquals("Turn 5 against AI 1 · saved 1 min ago", relaunch().offer?.detail)
    }

    @Test fun theBackgroundSaveStopsAtItsDeadline() = runBlocking {
        for ((budget, waits) in listOf(GameResumeController.BACKGROUND_SAVE_MILLIS to List(12) { 1000 }, 500L to listOf(500), 0L to listOf(0))) {
            startOnDemandGame()
            val engine = FakeSave(EngineCheckpointResult.WaitingForEngine)
            controller.backgrounded()
            controller.saveForBackground(engine, budget)
            assertEquals("budget $budget", waits, engine.waits)
            assertFalse(store.checkpointFile.exists())
            // Never saved: the next launch says the game ended.
            assertEquals(GameResumeText.LOST, relaunch().notice)
            assertNoFiles()
        }
    }

    @Test fun theBackgroundSaveStopsWhenTheGameCannotBeSaved() = runBlocking {
        for (result in listOf(EngineCheckpointResult.WaitingForPlayer, EngineCheckpointResult.Failed(jsonObject("message" to JsonPrimitive("disk full"))),
            EngineCheckpointResult.Unavailable("checkpoint_unavailable"), null)) {
            startOnDemandGame()
            val engine = FakeSave(result ?: EngineCheckpointResult.WaitingForEngine).apply { throws = result == null }
            controller.backgrounded()
            controller.saveForBackground(engine)
            assertEquals("$result", 1, engine.waits.size)
            assertNotNull(store.read()!!.leftAt)
            assertEquals("$result", GameResumeText.LOST, relaunch().notice)
        }
        // The match is over: nothing is left to resume.
        startOnDemandGame()
        controller.backgrounded()
        controller.saveForBackground(FakeSave(EngineCheckpointResult.Over))
        assertNoFiles()
        assertFalse(controller.isCheckpointing)
        assertNull(relaunch().notice)
    }

    @Test fun comingBackUsesUpTheSaveSoACrashEndsTheGame() = runBlocking {
        startOnDemandGame()
        controller.backgrounded()
        controller.saveForBackground(FakeSave(saved(1, 3)))
        assertTrue(store.checkpointFile.exists())
        assertTrue("the engine's armed request must be cancelled", controller.foregrounded())
        assertNull("a surviving process keeps its live game", store.read()!!.leftAt)
        assertFalse("the save made on leaving is used up", store.checkpointFile.exists())
        assertTrue(store.sidecarFile.exists())
        assertFalse("only a return from leaving cancels", controller.foregrounded())
        // The app dies while the player is in it: never an older save.
        val next = relaunch()
        assertNull(next.offer)
        assertEquals(GameResumeText.LOST, next.notice)
        assertNoFiles(); assertFalse(store.consumedFile.exists())
    }

    @Test fun leavingAgainAtTheSameDecisionKeepsThatSave() = runBlocking {
        startOnDemandGame()
        val engine = FakeSave(saved(1, 3))
        controller.backgrounded(); controller.saveForBackground(engine)
        controller.foregrounded()
        assertFalse(store.checkpointFile.exists())
        // Back out without a decision: the engine reports the save it already made.
        engine.writesFile = false
        controller.backgrounded(); controller.saveForBackground(engine)
        assertTrue("the used-up save is the current one again", store.checkpointFile.exists())
        assertFalse(store.consumedFile.exists())
        // After a decision the engine writes a new save, and the old one goes.
        controller.foregrounded()
        engine.writesFile = true
        engine.results[0] = saved(2, 4, now + 30_000)
        controller.backgrounded(); controller.saveForBackground(engine)
        assertTrue(store.checkpointFile.exists()); assertFalse(store.consumedFile.exists())
        assertEquals(4L, store.read()!!.turn)
        assertNotNull(relaunch().offer)
        assertFalse(store.consumedFile.exists())
    }

    @Test fun pausingArmsASaveWithoutWaiting() = runBlocking {
        startOnDemandGame()
        val engine = FakeSave(EngineCheckpointResult.WaitingForEngine)
        now += 10_000
        assertTrue(controller.backgrounded())
        controller.armSave(engine)
        assertEquals(listOf(0), engine.waits)
        assertEquals(now, store.read()!!.leftAt)
        // Back without leaving (ON_PAUSE, then ON_RESUME): the request is cancelled.
        assertTrue(controller.foregrounded())
        assertNull(store.read()!!.leftAt)
        // Closed from Recents after the engine saved: the next launch offers it.
        engine.results[0] = saved(1, 2)
        controller.backgrounded(); controller.armSave(engine)
        assertTrue(store.checkpointFile.exists())
        assertEquals(2L, store.read()!!.turn)
        assertNotNull(relaunch().offer)
    }

    @Test fun aSaveAnsweredAfterTheReturnIsNotTheSaveOnLeaving() = runBlocking {
        startOnDemandGame()
        val engine = FakeSave(saved(1, 3))
        // The player returns while the request is waiting; its answer comes after.
        engine.onRequest = { controller.foregrounded() }
        controller.backgrounded(); controller.saveForBackground(engine)
        assertEquals(1, engine.waits.size)
        val sidecar = store.read()!!
        assertNull(sidecar.leftAt); assertEquals(0L, sidecar.turn)
        assertNull(relaunch().offer)
    }

    @Test fun olderEnginesSaveAtEveryDecisionAndAreNeverAsked() = runBlocking {
        startCheckpointedGame()
        assertFalse(controller.savesOnDemand)
        val engine = FakeSave(EngineCheckpointResult.WaitingForEngine)
        assertTrue(controller.backgrounded())
        controller.armSave(engine); controller.saveForBackground(engine)
        assertTrue("checkpoint is never sent to an engine without checkpointOnDemand", engine.waits.isEmpty())
        assertNotNull("its last per-decision save is offered after leaving", relaunch().offer)
        assertFalse("nothing to cancel", controller.foregrounded())
        assertNull(store.read()!!.leftAt)
        assertTrue("the engine keeps writing its file", store.checkpointFile.exists())
        assertEquals(GameResumeText.LOST, relaunch().notice)
    }

    @Test fun restoringWithAnOnDemandEngineUsesUpTheSaveAndSavesAgainOnLeaving() = runBlocking {
        val (next, sidecar) = offered()
        val engine = FakeResume(caps = onDemandEngine)
        assertTrue(next.resume(sidecar, engine))
        assertTrue(next.savesOnDemand)
        assertFalse("playing again uses up the save: a crash now ends the game", store.checkpointFile.exists())
        assertTrue(store.consumedFile.exists())
        // Leaving again before any decision: the engine reports the save it restored from.
        val save = FakeSave(saved(4, 12, 1_799_999_990_000L)).apply { writesFile = false }
        next.backgrounded(); next.saveForBackground(save)
        assertTrue(store.checkpointFile.exists()); assertFalse(store.consumedFile.exists())
        assertNotNull(relaunch().offer)
    }
}
