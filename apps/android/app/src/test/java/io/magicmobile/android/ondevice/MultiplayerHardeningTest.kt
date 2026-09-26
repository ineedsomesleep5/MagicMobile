package io.magicmobile.android.ondevice

import io.magicmobile.android.game.BuildIdentity
import io.magicmobile.android.game.EngineJson
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.UUID

/** Revision notices and lost host answers (OnDeviceMultiplayerTests on iOS). */
class MultiplayerHardeningTest {
    @Test fun aLostHostAnswerIsARetryableHostUnavailableError() = runBlocking {
        val identity = BuildIdentity("a".repeat(40), "b".repeat(64), RELAY_ADAPTER_VERSION)
        val remote = OnDeviceRemoteEngineTransport("p1-host", "match", "player2", UUID.randomUUID(), this, timeoutMillis = 10) { _, _ -> }
        try { remote.hello(identity); fail("Expected timeout") }
        catch (error: OnDeviceHostUnavailable) { assertTrue(error.message!!.contains("in time")) }
        finally { remote.close() }
    }

    @Test fun revisionNoticeIsTinyStrictAndMatchesIOS() {
        val epoch = UUID.randomUUID()
        val notice = OnDeviceRevisionNotice.packet(epoch, 1234)
        assertTrue(EngineJson.encode(notice).size < 100)
        assertEquals(epoch.toString().uppercase(), (notice as JsonObject)["epoch"]!!.let { (it as JsonPrimitive).content })
        assertEquals(1234L, OnDeviceRevisionNotice.revision(notice))
        // An iOS notice: JSONValue sorts keys and encodes the epoch in uppercase.
        val ios = EngineJson.decode("""{"epoch":"${epoch.toString().uppercase()}","revision":1234,"type":"revision"}""".toByteArray())
        assertEquals(1234L, OnDeviceRevisionNotice.revision(ios))
        for (bad in listOf("""{"epoch":"E","revision":12,"type":"revision","seat":"player1"}""", """{"epoch":"E","revision":-1,"type":"revision"}""",
                "\"{\\\"epoch\\\":\\\"E\\\"}\"", """{"epoch":"E","revision":"12","type":"revision"}""", """{"epoch":"E","revision":12,"type":"presence"}""")) {
            try { OnDeviceRevisionNotice.revision(EngineJson.decode(bad.toByteArray())); fail("Accepted $bad") } catch (expected: Exception) { }
        }
    }
}
