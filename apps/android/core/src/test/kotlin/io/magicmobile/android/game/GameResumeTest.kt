package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** Save/resume rules on the JVM: a temporary folder and a fixed clock, never the app's real resume folder. */
class GameResumeTest {
    private val root: File = Files.createTempDirectory("mm-resume").toFile()
    private var now = 1_800_000_000_000L
    private val store = GameResumeStore(File(root, "resume")) { now }

    @After fun cleanUp() { root.deleteRecursively() }

    private fun seat(id: String, name: String, controller: String) =
        jsonObject("seatId" to JsonPrimitive(id), "name" to JsonPrimitive(name), "controller" to JsonPrimitive(controller),
            "deck" to jsonObject("name" to JsonPrimitive("$name deck")))

    private val configuration = jsonObject("seats" to JsonArray(listOf(seat("player1", "Caleb", "human"), seat("player2", "AI 1", "ai"),
        seat("player3", "AI 2", "ai"))), "checkpoint" to jsonObject("path" to JsonPrimitive("/data/resume/game.checkpoint")))

    private fun sidecar(lastCheckpointAt: Long = now, leftAt: Long? = null, appBuild: String = "2026092601", engine: String = "engine-a") =
        GameResumeSidecar(appBuild, engine, now - 60_000, lastCheckpointAt, leftAt, 12, "Token Triumph", GameResumeSidecar.opponents(configuration),
            GameResumeSidecar.setup(configuration, "player1", GameResumeSettings("precon:token-triumph", listOf("grave-danger", "first-flight"), 4, "roll")))

    private fun save(value: GameResumeSidecar, checkpoint: Boolean = true) {
        store.write(value)
        if (checkpoint) store.checkpointFile.writeBytes(byteArrayOf(1, 2, 3))
    }

    private fun assertGone() {
        assertFalse("checkpoint deleted", store.checkpointFile.exists())
        assertFalse("sidecar deleted", store.sidecarFile.exists())
        assertFalse("marker deleted", store.markerFile.exists())
    }

    @Test fun expiryIsTenMinutesFromLeavingOrTheLastCheckpoint() {
        val left = now
        assertFalse(GameResumePolicy.expired(left + 599_000, left, 0))
        assertFalse("exactly 600 s is still resumable", GameResumePolicy.expired(left + 600_000, left, 0))
        assertTrue(GameResumePolicy.expired(left + 601_000, left, 0))
        // A process that died in the foreground never set leftAt: its last checkpoint counts.
        assertFalse(GameResumePolicy.expired(left + 599_000, null, left))
        assertTrue(GameResumePolicy.expired(left + 601_000, null, left))
        assertFalse("leftAt wins over an older checkpoint", GameResumePolicy.expired(left + 599_000, left, left - 3_600_000))
    }

    @Test fun launchOffersAGameLeft599SecondsAgoAndExpiresOne601SecondsAgo() {
        save(sidecar(lastCheckpointAt = now - 700_000, leftAt = now))
        now += 599_000
        val offer = store.launch("2026092601", "engine-a")
        assertTrue(offer is GameResumeLaunch.Offer)
        assertEquals("Turn 12 against AI 1 and AI 2 · saved 21 min ago", (offer as GameResumeLaunch.Offer).detail)
        assertTrue("an offer keeps both files for Resume", store.checkpointFile.exists() && store.sidecarFile.exists())

        save(sidecar(leftAt = now))
        now += 601_000
        assertEquals(GameResumeLaunch.Notice(GameResumeText.EXPIRED), store.launch("2026092601", "engine-a"))
        assertGone()
    }

    @Test fun launchWithoutLeftAtUsesTheLastCheckpoint() {
        save(sidecar(lastCheckpointAt = now, leftAt = null))
        now += 599_000
        assertTrue(store.launch("2026092601", "engine-a") is GameResumeLaunch.Offer)
        now += 2_000
        assertEquals(GameResumeLaunch.Notice(GameResumeText.EXPIRED), store.launch("2026092601", "engine-a"))
        assertGone()
    }

    @Test fun anotherAppBuildOrEngineCannotResume() {
        save(sidecar(leftAt = now))
        assertEquals(GameResumeLaunch.Notice(GameResumeText.UPDATED), store.launch("2026092701", "engine-a"))
        assertGone()
        save(sidecar(leftAt = now))
        assertEquals(GameResumeLaunch.Notice(GameResumeText.UPDATED), store.launch("2026092601", "engine-b"))
        assertGone()
        // Both wrong: the game had expired anyway, which is what the player is told.
        save(sidecar(leftAt = now))
        now += 601_000
        assertEquals(GameResumeLaunch.Notice(GameResumeText.EXPIRED), store.launch("2026092701", "engine-b"))
        assertGone()
    }

    @Test fun aGameThatDiedBeforeItsFirstCheckpointIsExplainedAndOrphansAreDeletedQuietly() {
        save(sidecar(leftAt = now), checkpoint = false)
        assertEquals(GameResumeLaunch.Notice(GameResumeText.LOST), store.launch("2026092601", "engine-a"))
        assertGone()
        // A checkpoint the engine wrote while the player was already leaving: no sidecar, no notice.
        store.prepare(); store.checkpointFile.writeBytes(byteArrayOf(9)); File(store.directory, "game.checkpoint.tmp").writeBytes(byteArrayOf(9))
        assertEquals(GameResumeLaunch.Nothing, store.launch("2026092601", "engine-a"))
        assertFalse(File(store.directory, "game.checkpoint.tmp").exists())
        assertGone()
        // An unreadable sidecar is treated like a lost game.
        store.prepare(); store.sidecarFile.writeText("{not json"); store.checkpointFile.writeBytes(byteArrayOf(9))
        assertEquals(GameResumeLaunch.Notice(GameResumeText.LOST), store.launch("2026092601", "engine-a"))
        assertGone()
        assertEquals(GameResumeLaunch.Nothing, store.launch("2026092601", "engine-a"))
    }

    @Test fun markerExplainsAGameThatCouldNotCheckpointOnce() {
        store.markInProgress("table")
        assertTrue(store.markerFile.exists())
        assertEquals(GameResumeLaunch.Notice(GameResumeText.LOST), store.launch("2026092601", "engine-a"))
        assertGone()
        assertEquals("the notice is shown once", GameResumeLaunch.Nothing, store.launch("2026092601", "engine-a"))
        // A resumable game wins over a stale marker, and the marker goes.
        store.markInProgress("solo"); save(sidecar(leftAt = now))
        assertTrue(store.launch("2026092601", "engine-a") is GameResumeLaunch.Offer)
        assertFalse(store.markerFile.exists())
    }

    @Test fun sidecarRoundTripsAndKeepsOnlyTheCreateConfiguration() {
        val value = sidecar(leftAt = now - 5)
        store.write(value)
        val read = store.read()!!
        assertEquals(value, read)
        assertEquals("player1", read.seatID)
        assertEquals(GameResumeSettings("precon:token-triumph", listOf("grave-danger", "first-flight"), 4, "roll"), read.settings)
        assertEquals(listOf("AI 1", "AI 2"), read.opponents)
        val json = EngineJson.decode(store.sidecarFile.readBytes())
        assertEquals(1L, json["format"].integer)
        assertEquals(setOf("format", "appBuild", "engineIdentity", "createdAt", "lastCheckpointAt", "leftAt", "turn", "playerDeckName", "opponents", "setup"),
            json.obj!!.keys)
        assertNull("the checkpoint path is not part of the saved setup", json["setup"]["configuration"]["checkpoint"])
        assertEquals(configuration["seats"], json["setup"]["configuration"]["seats"])
        // A game that is being played has no leftAt.
        store.write(value.copy(leftAt = null))
        assertTrue(EngineJson.decode(store.sidecarFile.readBytes())["leftAt"] is JsonNull)
        assertNull(store.read()!!.leftAt)
        // Unknown formats are not guessed at.
        val future = JsonObject(value.json() + ("format" to JsonPrimitive(2)))
        assertNull(GameResumeSidecar.decode(future))
        assertNull(GameResumeSidecar.decode(JsonObject(value.json() - "engineIdentity")))
    }

    @Test fun sidecarWritesAreAtomic() {
        val first = sidecar()
        store.write(first)
        assertFalse("no temporary file is left behind", File(store.directory, "resume.json.tmp").exists())
        // A stale temporary file from a killed write does not block the next one.
        File(store.directory, "resume.json.tmp").writeText("partial")
        val second = first.copy(turn = 13)
        store.write(second)
        assertEquals(second, store.read())
        assertFalse(File(store.directory, "resume.json.tmp").exists())
        // A write that fails before its rename leaves the previous sidecar whole.
        File(store.directory, "resume.json.tmp").mkdirs()
        File(store.directory, "resume.json.tmp/blocker").writeText("x")
        try { store.write(first.copy(turn = 99)); fail("expected the write to fail") } catch (_: Exception) {}
        assertEquals(second, store.read())
    }

    @Test fun deletingRemovesBothFilesTheirTemporariesAndTheMarker() {
        save(sidecar()); store.markInProgress("solo")
        File(store.directory, "game.checkpoint.tmp").writeBytes(byteArrayOf(1))
        store.deleteAll()
        assertGone()
        assertFalse(File(store.directory, "game.checkpoint.tmp").exists())
        store.deleteAll()
    }

    @Test fun onlyASaveResumeEngineWithOneHumanCheckpoints() {
        val oneHuman = listOf<J>(seat("player1", "Caleb", "human"), seat("player2", "AI 1", "ai"))
        val twoHumans = listOf<J>(seat("player1", "Caleb", "human"), seat("player2", "Alex", "human"))
        val supported = jsonObject("saveResume" to JsonPrimitive(true))
        assertTrue(GameResumePolicy.checkpoints(supported, oneHuman))
        assertFalse(GameResumePolicy.checkpoints(supported, twoHumans))
        assertFalse(GameResumePolicy.checkpoints(jsonObject("saveResume" to JsonPrimitive(false)), oneHuman))
        assertFalse("engines before saveResume say nothing", GameResumePolicy.checkpoints(jsonObject("concede" to JsonPrimitive(true)), oneHuman))
        assertFalse(GameResumePolicy.checkpoints(jsonObject("saveResume" to JsonPrimitive("true")), oneHuman))
        assertFalse(GameResumePolicy.checkpoints(null, oneHuman))
    }

    @Test fun engineIdentityIsTheSameFromCapabilitiesAndTheAppBuild() {
        val capabilities = jsonObject("protocol" to JsonPrimitive(1), "engine" to JsonPrimitive("xmage"), "upstream" to JsonPrimitive("abc123"),
            "catalogueHash" to JsonPrimitive("hash9"), "saveResume" to JsonPrimitive(true))
        assertEquals("xmage/protocol-1/abc123/hash9", GameResumeIdentity.engine(capabilities))
        assertEquals(GameResumeIdentity.engine(capabilities), GameResumeIdentity.engine(BuildIdentity("abc123", "hash9", "ondevice-0.1/app-0.1.1/build-9")))
        assertNull(GameResumeIdentity.engine(JsonObject(capabilities - "upstream")))
    }

    @Test fun pollCheckpointAndRestoreResultsParse() {
        assertEquals(EngineCheckpoint(4, 1_700_000_000_123, 12, 9_876_543),
            EngineCheckpoint.parse(jsonObject("sequence" to JsonPrimitive(4), "savedAtMillis" to JsonPrimitive(1_700_000_000_123),
                "turn" to JsonPrimitive(12), "bytes" to JsonPrimitive(9_876_543))))
        assertNull(EngineCheckpoint.parse(null))
        assertNull(EngineCheckpoint.parse(JsonNull))
        assertNull("malformed metadata is ignored", EngineCheckpoint.parse(jsonObject("sequence" to JsonPrimitive("4"))))
        val poll = MatchPoll(jsonObject("matchId" to JsonPrimitive("m"), "viewerId" to JsonPrimitive("player1"), "revision" to JsonPrimitive(3),
            "phase" to JsonPrimitive("running"), "resyncRequired" to JsonPrimitive(false), "snapshot" to JsonNull, "prompt" to JsonNull,
            "checkpoint" to jsonObject("sequence" to JsonPrimitive(1), "savedAtMillis" to JsonPrimitive(5), "turn" to JsonPrimitive(1),
                "bytes" to JsonPrimitive(10))))
        assertEquals(1L, poll.checkpoint?.sequence)
        val older = MatchPoll(JsonObject(poll.raw.obj!! - "checkpoint"))
        assertNull("polls from engines without saveResume have no checkpoint", older.checkpoint)

        val restored = EngineRestored.parse(jsonObject("matchId" to JsonPrimitive("m2"), "seats" to JsonArray(listOf(JsonPrimitive("player1"))),
            "restored" to jsonObject("turn" to JsonPrimitive(12), "savedAtMillis" to JsonPrimitive(99))))
        assertEquals(EngineRestored("m2", 12, 99), restored)
        try { EngineRestored.parse(jsonObject("matchId" to JsonPrimitive("m2"))); fail("a create result is not a restore") } catch (_: EngineError) {}
    }

    @Test fun theGameIsOverWhenItEndsOrThisSeatLeftIt() {
        fun poll(phase: String, viewerLeft: Boolean, snapshot: Boolean = true) = MatchPoll(jsonObject("matchId" to JsonPrimitive("m"),
            "viewerId" to JsonPrimitive("player1"), "revision" to JsonPrimitive(3), "phase" to JsonPrimitive(phase), "resyncRequired" to JsonPrimitive(false),
            "prompt" to JsonNull, "snapshot" to if (!snapshot) JsonNull else jsonObject("enginePlayerId" to JsonPrimitive("u1"),
                "gameView" to jsonObject("players" to JsonArray(listOf(jsonObject("playerId" to JsonPrimitive("u1"), "hasLeft" to JsonPrimitive(viewerLeft)),
                    jsonObject("playerId" to JsonPrimitive("u2"), "hasLeft" to JsonPrimitive(true))))))))
        assertTrue(GameResumePolicy.over(poll("ended", false)))
        assertTrue("conceded or lost in a pod, now spectating", GameResumePolicy.over(poll("running", true)))
        assertFalse("another seat leaving is not this seat's end", GameResumePolicy.over(poll("running", false)))
        assertFalse(GameResumePolicy.over(poll("running", false, snapshot = false)))
    }

    @Test fun detailNamesTheTurnOpponentsAndAge() {
        assertEquals("Turn 12 against Alice and Bob · saved 3 min ago", GameResumeText.detail(12, listOf("Alice", "Bob"), 180_000))
        assertEquals("Turn 3 against AI 1 · saved just now", GameResumeText.detail(3, listOf("AI 1"), 59_999))
        assertEquals("Turn 7 against AI 1, AI 2 and AI 3 · saved 1 min ago", GameResumeText.detail(7, listOf("AI 1", "AI 2", "AI 3"), 60_000))
        assertEquals("Against AI 1 · saved 9 min ago", GameResumeText.detail(0, listOf("AI 1"), 599_000))
        assertEquals("Turn 5 against AI 1 · saved 1 hr ago", GameResumeText.detail(5, listOf("AI 1"), 3_700_000))
        assertEquals("a clock that moved back reads as now", "Turn 5 · saved just now", GameResumeText.detail(5, emptyList(), -5_000))
    }
}
