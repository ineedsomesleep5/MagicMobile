package io.magicmobile.android.session

import io.magicmobile.android.game.EngineClient
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.EngineTransport
import io.magicmobile.android.game.J
import io.magicmobile.android.game.get
import io.magicmobile.android.game.string
import io.magicmobile.android.ondevice.OnDeviceHostUnavailable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import io.magicmobile.android.session.OnDeviceGuestPollSchedule.Step

/** Port of the iOS OnDeviceSessionTests for phone-hosted tables: revision notices and host retries. */
class OnDeviceTablePollingTest {
    @Test fun guestPollScheduleFollowsNoticesAnswersAndHeartbeat() {
        val heartbeat = OnDeviceGuestPollSchedule.HEARTBEAT_MILLIS
        val window = OnDeviceGuestPollSchedule.ANSWER_WINDOW_MILLIS
        fun next(announces: Boolean = true, noticed: Long = 7, applied: Long? = 7, awaiting: Boolean = false, sinceAction: Long? = null,
                 sincePoll: Long, spacing: Long = 300) = OnDeviceGuestPollSchedule.next(announces, noticed, applied, awaiting, sinceAction, sincePoll, spacing)
        // A host that never announced (an older build) keeps the short timer.
        assertEquals(Step.Poll(200), next(announces = false, noticed = -1, sincePoll = 100))
        // Caught up: wait for a notice, at most until the heartbeat is due.
        assertEquals(Step.AwaitNotice(heartbeat - 5_000), next(sincePoll = 5_000))
        assertEquals(Step.Poll(0), next(sincePoll = heartbeat))
        // A newer notice polls, still spaced like the short timer.
        assertEquals(Step.Poll(200), next(noticed = 9, sincePoll = 100))
        assertEquals(Step.Poll(0), next(noticed = 9, sincePoll = 2_000))
        assertEquals(Step.Poll(300), next(noticed = 3, applied = null, sincePoll = 0))
        // An answer on its way polls promptly, but only for the answer window.
        assertEquals(Step.Poll(0), next(awaiting = true, sinceAction = 1_000, sincePoll = 600, spacing = 600))
        assertEquals(Step.AwaitNotice(heartbeat - 1_000), next(awaiting = true, sinceAction = window + 1, sincePoll = 1_000))
        assertEquals(Step.AwaitNotice(heartbeat - 1_000), next(sinceAction = 1_000, sincePoll = 1_000))
    }

    @Test fun hostRetryPolicyRetriesOnlyLostHostAnswersAFewTimes() {
        val policy = OnDeviceHostRetryPolicy()
        assertNull(policy.delayAfter(EngineError.InvalidMessage("The host is busy. Retry the same action.")))
        assertNull(policy.delayAfter(java.io.IOException("offline")))
        assertEquals(1_000L, policy.delayAfter(OnDeviceHostUnavailable()))
        assertEquals(2_000L, policy.delayAfter(OnDeviceHostUnavailable()))
        assertEquals(4_000L, policy.delayAfter(OnDeviceHostUnavailable()))
        assertNull("Give up after a few retries", policy.delayAfter(OnDeviceHostUnavailable()))
        policy.reset()
        assertEquals(1_000L, policy.delayAfter(OnDeviceHostUnavailable()))
        assertEquals("The host did not answer in time. Keep every player’s app in the foreground.", OnDeviceHostUnavailable().message)
    }

    @Test fun tableLinkWakesOnNoticesAndOtherwiseTimesOut() = runBlocking {
        val link = OnDeviceTableLink(OnDeviceTableLink.Role.GUEST, "  ")
        assertEquals("Waiting for the host…", link.waitingStatus)
        assertFalse(link.hostAnnounces)
        val start = System.nanoTime()
        link.waitForNotice(100)
        assertTrue(System.nanoTime() - start >= 90_000_000L)
        var woke = false
        val waiter = launch { link.waitForNotice(30_000); woke = true }
        repeat(5) { kotlinx.coroutines.yield() }
        assertFalse(woke)
        link.noticed(5)
        waiter.join()
        assertTrue(woke)
        assertTrue(link.hostAnnounces)
        link.noticed(3)
        assertEquals("A late notice never moves the revision back", 5L, link.noticedRevision)
        val host = OnDeviceTableLink(OnDeviceTableLink.Role.HOST, "Caleb")
        val announced = ArrayList<Long>()
        host.announce = { announced += it }
        host.applied(4); host.applied(4); host.applied(2); host.applied(6)
        host.noticed(10)
        assertEquals(listOf(4L, 6L), announced)
        assertFalse("Only guests hear notices", host.hostAnnounces)
    }

    /** A host engine at one revision that counts polls and can lose answers or advance. */
    private class FakeHost : EngineTransport {
        var revision = 10L
        var polls = 0
        var lostAnswers = 0
        val responses = ArrayList<J>()
        override suspend fun request(data: ByteArray): ByteArray {
            val request = EngineJson.decode(data)
            val result: J = when (request["op"].string) {
                "poll" -> {
                    polls += 1
                    if (lostAnswers > 0) { lostAnswers -= 1; throw OnDeviceHostUnavailable() }
                    JsonObject(mapOf("matchId" to JsonPrimitive("match"), "viewerId" to JsonPrimitive("player2"),
                        "revision" to JsonPrimitive(revision), "phase" to JsonPrimitive("running"), "resyncRequired" to JsonPrimitive(false),
                        "snapshot" to JsonNull, "prompt" to JsonNull))
                }
                "respond" -> { responses += request; JsonObject(mapOf("status" to JsonPrimitive("queued"))) }
                else -> throw EngineError.InvalidMessage("Unexpected fixture operation")
            }
            return EngineJson.encode(JsonObject(mapOf("protocol" to JsonPrimitive(1), "ok" to JsonPrimitive(true), "result" to result)))
        }
    }

    private fun table(test: suspend (CoroutineScope) -> Unit) = runBlocking {
        val job = SupervisorJob()
        val scope = CoroutineScope(coroutineContext + job)
        try { test(scope) } finally { job.cancel() }
    }

    @Test fun hostAnnouncesEachNewRevisionOnce() = table { scope ->
        val host = FakeHost()
        val link = OnDeviceTableLink(OnDeviceTableLink.Role.HOST, "Caleb")
        val announced = ArrayList<Long>()
        link.announce = { announced += it }
        val session = OnDeviceSession(scope)
        session.attach(EngineClient(host), "match", "player2", autoPoll = false, table = link) {}
        session.refresh()
        assertEquals("An unchanged revision is announced once", listOf(10L), announced)
        host.revision = 11
        session.refresh()
        assertEquals(listOf(10L, 11L), announced)
        session.close()
    }

    @Test fun guestPollsOnHostNoticesInsteadOfTheShortTimer() = table { scope ->
        val host = FakeHost()
        val link = OnDeviceTableLink(OnDeviceTableLink.Role.GUEST, "Caleb")
        link.noticed(10)
        val session = OnDeviceSession(scope)
        session.attach(EngineClient(host), "match", "player2", table = link) {}
        delay(1_500)
        val quiet = host.polls
        // Attach, then one catch-up poll; the 300 ms timer would have polled about six times.
        assertTrue("polls: $quiet", quiet <= 2)
        host.revision = 11
        link.noticed(11)
        delay(500)
        assertEquals("A notice brings exactly one poll", quiet + 1, host.polls)
        link.noticed(10)
        delay(700)
        assertEquals("A repeated or stale notice does not poll again", quiet + 1, host.polls)
        session.close()
    }

    @Test fun guestOfAHostWithoutNoticesKeepsTheShortTimer() = table { scope ->
        val host = FakeHost()
        val session = OnDeviceSession(scope)
        session.attach(EngineClient(host), "match", "player2", table = OnDeviceTableLink(OnDeviceTableLink.Role.GUEST, "Caleb")) {}
        delay(1_500)
        assertTrue("An older host never announces, so its guests keep polling (${host.polls})", host.polls >= 3)
        session.close()
    }

    @Test fun guestWaitsForAnUnansweringHostAndRecoversWithoutResending() = table { scope ->
        val host = FakeHost()
        val session = OnDeviceSession(scope)
        session.hostRetryDelaysMillis = listOf(300, 300, 300)
        session.attach(EngineClient(host), "match", "player2", table = OnDeviceTableLink(OnDeviceTableLink.Role.GUEST, "Caleb")) {}
        host.lostAnswers = 2
        var sawWaiting = false
        repeat(300) { if (!sawWaiting) { if (session.status == "Waiting for Caleb…") sawWaiting = true else delay(5) } }
        assertTrue(sawWaiting)
        assertNull("Waiting is not an error yet", session.errorMessage)
        delay(1_500)
        assertEquals("Live", session.status)
        assertNull(session.errorMessage)
        assertTrue("Retries only poll", host.responses.isEmpty())
        session.close()
    }

    @Test fun guestGivesUpAfterAFewRetriesWithTheUsualMessage() = table { scope ->
        val host = FakeHost()
        val session = OnDeviceSession(scope)
        session.hostRetryDelaysMillis = listOf(50, 50, 50)
        session.attach(EngineClient(host), "match", "player2", table = OnDeviceTableLink(OnDeviceTableLink.Role.GUEST, "Caleb")) {}
        val before = host.polls
        host.lostAnswers = 100
        repeat(300) { if (session.errorMessage == null) delay(10) }
        assertEquals("Updates interrupted. Refresh to retry.", session.status)
        assertEquals(OnDeviceHostUnavailable().message, session.errorMessage)
        delay(300)
        assertEquals("One poll and three retries", 4, host.polls - before)
        session.close()
    }

    @Test fun localSessionDoesNotRetryHostErrors() = table { scope ->
        val host = FakeHost()
        val session = OnDeviceSession(scope)
        session.hostRetryDelaysMillis = listOf(50, 50, 50)
        session.attach(EngineClient(host), "match", "player2") {}
        host.lostAnswers = 1
        repeat(200) { if (session.errorMessage == null) delay(10) }
        assertEquals("Updates interrupted. Refresh to retry.", session.status)
        session.close()
    }
}
