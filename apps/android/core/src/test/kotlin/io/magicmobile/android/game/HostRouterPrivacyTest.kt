package io.magicmobile.android.game

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.UUID

/** Mirrors SafetyTests.diagnosticsNeverReachEngineFromPeer: a peer can never read the host's diagnostics or game record. */
class HostRouterPrivacyTest {
    @Test fun diagnosticsAndTheGameRecordNeverReachTheEngineFromAPeer() = runBlocking {
        val identity = BuildIdentity("dac400b", "catalogue")
        // The game record shows every hand and library order (docs/PROTOCOL.md "Game record").
        for (operation in listOf("diagnostics", "clearDiagnostics", "record", "destroy")) {
            val calls = mutableListOf<ByteArray>()
            val router = HostRouter(EngineClient { calls.add(it); error("engine reached") }, "match", identity)
            router.bind("peer", "seat-2")
            router.handle(PeerFrame(router.epoch, 1, "hello", identity.json), "peer")
            try {
                router.handle(PeerFrame(router.epoch, 2, operation, JsonObject(emptyMap())), "peer")
                fail("$operation reached the engine")
            } catch (expected: EngineError) {
            }
            assertTrue(operation, calls.isEmpty())
        }
    }
}
