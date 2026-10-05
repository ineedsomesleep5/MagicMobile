package io.magicmobile.android.game

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Friend challenges (iOS FriendChallengeTests in RankedParityTests.swift). */
class FriendChallengesTest {
    private val id = "c6000000-0000-0000-0000-00000000000a"
    private fun challenge(status: String, mode: String = "ranked", code: String? = null, match: String? = null) =
        FriendChallenge(id, mode, status, "challenger", "DuelOne", "DuelTwo", 9, "p", code, match)

    private inner class Fake(var sent: FriendChallenge) : FriendChallengeService {
        val statuses = ArrayDeque<FriendChallenge>()
        var cancelResult = FriendChallenge.closed(id)
        var incomingList = listOf<FriendChallenge>()
        val declined = mutableListOf<String>()
        var fail: String? = null
        override suspend fun send(username: String, mode: PlayMode, protocol: String, rankStep: Int, tableCode: String): FriendChallenge {
            fail?.let { throw IllegalStateException(it) }
            return sent
        }
        override suspend fun incoming() = incomingList
        override suspend fun status(id: String) = statuses.removeFirstOrNull() ?: sent
        override suspend fun accept(id: String, protocol: String, rankStep: Int) = challenge("accepted", code = "ABCDEF")
        override suspend fun decline(id: String) { declined += id }
        override suspend fun cancel(id: String) = cancelResult
    }

    @Test fun rankedNeedsTheSameTier() {
        assertTrue(FriendChallengeRules.mayRank(8, 11))     // Gold IV with Gold I
        assertFalse(FriendChallengeRules.mayRank(11, 12))   // Gold I with Platinum IV
        assertTrue(FriendChallengeRules.mayRank(2, null))   // no standing reads as Bronze
        assertFalse(FriendChallengeRules.mayRank(4, null))
        assertTrue(FriendChallengeRules.mayRank(20, 20))    // Mythic with Mythic
        assertFalse(FriendChallengeRules.mayRank(19, 20))
    }

    @Test fun parsesTheServerShape() {
        val row = Json.parseToJsonElement("""{"id":"$id","mode":"ranked","status":"accepted","role":"challenged","challenger":"DuelOne",
            "challenged":"DuelTwo","challengerStep":11,"protocol":"p","tableCode":"ABCDEF","matchId":"m1","createdAt":"2026-10-04T12:00:00Z"}""") as JsonObject
        val parsed = FriendChallenge.parse(row)
        assertEquals(PlayMode.RANKED, parsed.playMode)
        assertEquals(11, parsed.challengerStep)
        assertEquals("ABCDEF", parsed.tableCode)
        assertEquals("m1", parsed.matchId)
        // A challenge the server no longer shows reads as cancelled.
        assertEquals("cancelled", FriendChallenge.parse(Json.parseToJsonElement("""{"status":"cancelled"}""") as JsonObject, id).status)
    }

    @Test fun acceptedChallengeHandsBackTheMatch() = runTest {
        val fake = Fake(challenge("pending"))
        fake.statuses += challenge("pending"); fake.statuses += challenge("accepted", code = "ABCDEF", match = "m1")
        val coordinator = FriendChallengeCoordinator(fake, sleep = {})
        val answer = coordinator.challenge("DuelTwo", PlayMode.RANKED, "p", 9, "ABCDEF")
        assertEquals(ChallengeAnswer.Accepted(challenge("accepted", code = "ABCDEF", match = "m1")), answer)
        assertFalse(coordinator.isWaiting)
    }

    @Test fun declinedAndFailedChallenges() = runTest {
        val fake = Fake(challenge("pending"))
        fake.statuses += challenge("declined")
        val coordinator = FriendChallengeCoordinator(fake, sleep = {}, codeOf = { it.message ?: "error" })
        assertEquals(ChallengeAnswer.Declined, coordinator.challenge("DuelTwo", PlayMode.QUICK, "p", 9, "ABCDEF"))
        fake.fail = "rank_mismatch"
        assertEquals(ChallengeAnswer.Failed("rank_mismatch"), coordinator.challenge("DuelTwo", PlayMode.RANKED, "p", 4, "ABCDEF"))
        assertEquals("Ranked challenges need the same tier.", FriendChallengeRules.message("rank_mismatch"))
    }

    @Test fun withdrawingKeepsAnAcceptThatArrivedFirst() = runTest {
        val fake = Fake(challenge("pending"))
        lateinit var coordinator: FriendChallengeCoordinator
        coordinator = FriendChallengeCoordinator(fake, sleep = { coordinator.cancelOutgoing() })
        assertEquals(ChallengeAnswer.Cancelled, coordinator.challenge("DuelTwo", PlayMode.QUICK, "p", 9, "ABCDEF"))
        fake.cancelResult = challenge("accepted", code = "ABCDEF")
        assertEquals(ChallengeAnswer.Accepted(challenge("accepted", code = "ABCDEF")), coordinator.challenge("DuelTwo", PlayMode.QUICK, "p", 9, "ABCDEF"))
    }

    @Test fun incomingSkipsAnsweredChallenges() = runTest {
        val fake = Fake(challenge("pending"))
        fake.incomingList = listOf(challenge("pending", mode = "quick"))
        val coordinator = FriendChallengeCoordinator(fake, sleep = {})
        coordinator.refreshIncoming()
        assertEquals(1, coordinator.incoming.size)
        coordinator.decline(coordinator.incoming[0])
        assertEquals(listOf(id), fake.declined)
        coordinator.refreshIncoming()
        assertTrue("A declined challenge never comes back while the server catches up", coordinator.incoming.isEmpty())
    }
}
