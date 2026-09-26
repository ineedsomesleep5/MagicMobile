package io.magicmobile.android.ondevice

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
    private val store = GameResumeStore(File(root, "resume")) { now }
    private val inline = Executor { it.run() }
    private val controller = GameResumeController(store, "2026092601", inline)
    private val engineIdentity = "xmage/protocol-1/abc123/hash9"

    @After fun cleanUp() { root.deleteRecursively() }

    private val newEngine = jsonObject("protocol" to JsonPrimitive(1), "engine" to JsonPrimitive("xmage"), "upstream" to JsonPrimitive("abc123"),
        "catalogueHash" to JsonPrimitive("hash9"), "saveResume" to JsonPrimitive(true))
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
}
