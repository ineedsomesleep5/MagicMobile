package io.magicmobile.android.game

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Test

/** EngineClient.poll returns the previous poll, undecoded, for a byte-identical reply to the same request (iOS OnDevicePollReader). */
class EnginePollMemoTest {
    private var revision = 3L
    private var requests = 0
    private val client = EngineClient(object : EngineTransport {
        override suspend fun request(data: ByteArray): ByteArray {
            requests += 1
            return EngineJson.encode(jsonObject("protocol" to JsonPrimitive(1), "ok" to JsonPrimitive(true), "result" to jsonObject(
                "matchId" to JsonPrimitive("m"), "viewerId" to JsonPrimitive("player1"), "revision" to JsonPrimitive(revision),
                "phase" to JsonPrimitive("running"), "resyncRequired" to JsonPrimitive(false), "snapshot" to JsonNull, "prompt" to JsonNull)))
        }
    })

    @Test fun repeatedRepliesReturnThePreviousPoll() = runBlocking {
        val first = client.poll("m", "player1", 3)
        assertSame("an identical reply is not decoded again", first, client.poll("m", "player1", 3))
        val otherCursor = client.poll("m", "player1", 2)
        assertNotSame("a different request is decoded even when the reply is the same", first, otherCursor)
        assertEquals(first, otherCursor)
        revision = 4
        val changed = client.poll("m", "player1", 2)
        assertEquals(4L, changed.revision)
        assertEquals("every poll still asks the engine", 4, requests)
    }
}
