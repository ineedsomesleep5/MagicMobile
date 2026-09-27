package io.magicmobile.android.game

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The save/resume wire contract: the exact restore request, the engine's restore rejections, the
 * checkpoint field only for a saveResume engine, and poll metadata that never breaks a game.
 */
class GameResumeWireTest {
    private var sent: J? = null
    private var reply: J = ok(jsonObject("matchId" to JsonPrimitive("m"),
        "restored" to jsonObject("turn" to JsonPrimitive(4), "savedAtMillis" to JsonPrimitive(7))))
    private val client = EngineClient(object : EngineTransport {
        override suspend fun request(data: ByteArray): ByteArray { sent = EngineJson.decode(data); return EngineJson.encode(reply) }
    })

    private fun ok(result: J): J = jsonObject("protocol" to JsonPrimitive(1), "ok" to JsonPrimitive(true), "result" to result)

    @Test fun restoreSendsExactlyTheCheckpointPath() = runBlocking {
        val result = client.restore("/data/user/0/app/no_backup/resume/game.checkpoint")
        assertEquals(jsonObject("protocol" to JsonPrimitive(1), "op" to JsonPrimitive("restore"),
            "checkpoint" to jsonObject("path" to JsonPrimitive("/data/user/0/app/no_backup/resume/game.checkpoint"))), sent)
        assertEquals(EngineRestored("m", 4, 7), EngineRestored.parse(result))
    }

    @Test fun restoreRejectionsReachTheApp() = runBlocking {
        for (code in listOf("checkpoint_unavailable", "checkpoint_incompatible", "checkpoint_corrupt")) {
            reply = jsonObject("protocol" to JsonPrimitive(1), "ok" to JsonPrimitive(false),
                "error" to jsonObject("code" to JsonPrimitive(code), "message" to JsonPrimitive("no")))
            val failure = runCatching { client.restore("/x") }.exceptionOrNull()
            assertEquals(code, (failure as? EngineError.Rejected)?.code)
        }
    }

    @Test fun createCarriesACheckpointOnlyForASaveResumeEngine() = runBlocking {
        val seats = listOf<J>(jsonObject("seatId" to JsonPrimitive("player1"), "controller" to JsonPrimitive("human")),
            jsonObject("seatId" to JsonPrimitive("player2"), "controller" to JsonPrimitive("ai")))
        val older = jsonObject("saveResume" to JsonPrimitive(false), "concede" to JsonPrimitive(true))
        assertFalse(GameResumePolicy.checkpoints(older, seats))
        assertTrue(GameResumePolicy.checkpoints(jsonObject("saveResume" to JsonPrimitive(true)), seats))
        reply = ok(jsonObject("matchId" to JsonPrimitive("m")))
        client.create(jsonObject("seats" to kotlinx.serialization.json.JsonArray(seats)))
        assertNull("an ordinary create has no checkpoint field", sent["configuration"]["checkpoint"])
    }

    @Test fun pollsWithoutOrWithMalformedCheckpointsStillParse() {
        val poll = jsonObject("matchId" to JsonPrimitive("m"), "viewerId" to JsonPrimitive("player1"), "revision" to JsonPrimitive(2),
            "phase" to JsonPrimitive("running"), "resyncRequired" to JsonPrimitive(false), "snapshot" to JsonNull, "prompt" to JsonNull)
        assertNull(MatchPoll(poll).checkpoint)
        assertNull(MatchPoll(jsonObject(poll + ("checkpoint" to JsonPrimitive("bad")))).checkpoint)
        assertNull(MatchPoll(jsonObject(poll + ("checkpoint" to jsonObject("sequence" to JsonPrimitive(-1), "savedAtMillis" to JsonPrimitive(1),
            "turn" to JsonPrimitive(1), "bytes" to JsonPrimitive(1))))).checkpoint)
    }

    @Test fun checkpointRequestShapeAndResults() = runBlocking {
        reply = ok(jsonObject("state" to JsonPrimitive("saved"), "checkpoint" to jsonObject("sequence" to JsonPrimitive(5),
            "savedAtMillis" to JsonPrimitive(1_790_000_000_000), "turn" to JsonPrimitive(7), "bytes" to JsonPrimitive(600_000),
            "writeMillis" to JsonPrimitive(41))))
        assertEquals(EngineCheckpointResult.Saved(EngineCheckpoint(5, 1_790_000_000_000, 7, 600_000, 41)), client.checkpoint("m", 1000))
        assertEquals(jsonObject("protocol" to JsonPrimitive(1), "op" to JsonPrimitive("checkpoint"), "matchId" to JsonPrimitive("m"),
            "waitMillis" to JsonPrimitive(1000)), sent)
        reply = ok(jsonObject("cancelled" to JsonPrimitive(true)))
        client.cancelCheckpoint("m")
        assertEquals(jsonObject("protocol" to JsonPrimitive(1), "op" to JsonPrimitive("cancelCheckpoint"), "matchId" to JsonPrimitive("m")), sent)

        fun state(vararg fields: Pair<String, J>) = EngineCheckpointResult.parse(jsonObject(*fields))
        assertEquals(EngineCheckpointResult.WaitingForEngine, state("state" to JsonPrimitive("pending"), "waitingFor" to JsonPrimitive("engine")))
        assertEquals(EngineCheckpointResult.WaitingForPlayer, state("state" to JsonPrimitive("pending"), "waitingFor" to JsonPrimitive("player")))
        assertEquals(EngineCheckpointResult.Over, state("state" to JsonPrimitive("over")))
        val failure = jsonObject("code" to JsonPrimitive("io"), "message" to JsonPrimitive("disk full"))
        assertEquals(EngineCheckpointResult.Failed(failure), state("state" to JsonPrimitive("failed"), "checkpointFailure" to failure))
        for (malformed in listOf(jsonObject(), jsonObject("state" to JsonPrimitive("saving")),
            jsonObject("state" to JsonPrimitive("pending"), "waitingFor" to JsonPrimitive("host")),
            jsonObject("state" to JsonPrimitive("saved"), "checkpoint" to jsonObject("sequence" to JsonPrimitive(1))))) {
            assertTrue("$malformed", runCatching { EngineCheckpointResult.parse(malformed) }.exceptionOrNull() is EngineError)
        }
    }

    @Test fun checkpointBoundsAreCheckedBeforeSending() = runBlocking {
        for ((match, wait) in listOf("m" to -1, "m" to 1001, "" to 0)) {
            assertTrue(runCatching { client.checkpoint(match, wait) }.exceptionOrNull() is EngineError.InvalidMessage)
        }
        assertTrue(runCatching { client.cancelCheckpoint("") }.exceptionOrNull() is EngineError.InvalidMessage)
        assertNull("nothing reached the engine", sent)
    }

    @Test fun unavailableCheckpointCodesAreResultsOtherErrorsThrow() = runBlocking {
        fun rejected(code: String) = jsonObject("protocol" to JsonPrimitive(1), "ok" to JsonPrimitive(false),
            "error" to jsonObject("code" to JsonPrimitive(code), "message" to JsonPrimitive("no")))
        for (code in listOf("checkpoint_unavailable", "match_unavailable")) {
            reply = rejected(code)
            assertEquals(EngineCheckpointResult.Unavailable(code), client.checkpoint("m", 0))
        }
        reply = rejected("invalid_request")
        assertEquals("invalid_request", (runCatching { client.checkpoint("m", 0) }.exceptionOrNull() as? EngineError.Rejected)?.code)
    }
}
