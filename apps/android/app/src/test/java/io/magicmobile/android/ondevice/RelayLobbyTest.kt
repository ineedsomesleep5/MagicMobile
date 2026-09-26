package io.magicmobile.android.ondevice

import io.magicmobile.android.game.BuildIdentity
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.get
import io.magicmobile.android.game.string
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.UUID

/** The relay lobby must accept exactly what the iOS app sends (OnDeviceMultiplayer.swift). */
class RelayLobbyTest {
    private val identity = BuildIdentity("a".repeat(40), "b".repeat(64), RELAY_ADAPTER_VERSION)
    private val host = "p1-hostAAAA"
    private val guest = "p2-guestBBB"

    private fun deck(commander: String = "Emmara, Soul of the Accord"): J = JsonObject(mapOf(
        "name" to JsonPrimitive("Token Triumph"),
        "main" to JsonArray(listOf(JsonObject(mapOf("name" to JsonPrimitive("Forest"), "setCode" to JsonPrimitive("M21"),
            "collectorNumber" to JsonPrimitive("274"), "count" to JsonPrimitive(99))))),
        "commanders" to JsonArray(listOf(JsonObject(mapOf("name" to JsonPrimitive(commander), "setCode" to JsonPrimitive("GRN"),
            "collectorNumber" to JsonPrimitive("168"), "count" to JsonPrimitive(1))))),
        "companions" to JsonArray(emptyList())))

    /** An iOS packet: `epoch.uuidString` is uppercase and JSONValue sorts keys; decoding keeps it as sent. */
    private fun iosPacket(type: String, epoch: UUID, lobby: OnDeviceMultiplayerLobby, extra: Map<String, J> = emptyMap()): J {
        val fields = linkedMapOf<String, J>("aiSettings" to lobby.aiSettings, "build" to identity.json,
            "epoch" to JsonPrimitive(epoch.toString().uppercase()), "roster" to JsonArray(lobby.peerIDs.map(::JsonPrimitive)),
            "type" to JsonPrimitive(type))
        fields.putAll(extra)
        return EngineJson.decode(EngineJson.encode(JsonObject(fields)))
    }

    @Test fun relayPeerIDsSortTheHostFirst() {
        val lobby = OnDeviceMultiplayerLobby(listOf(guest, host), guest)
        assertEquals(host, lobby.hostID)
        assertEquals("player1", lobby.seatID(host))
        assertEquals("player2", lobby.seatID(guest))
    }

    @Test fun aGuestAcceptsAnIOSHostOfferAndSubmitsItsDeck() {
        val hostLobby = OnDeviceMultiplayerLobby(listOf(host, guest), host)
        val guestLobby = OnDeviceMultiplayerLobby(listOf(host, guest), guest)
        val epoch = UUID.randomUUID()
        val offer = iosPacket("offer", epoch, hostLobby)
        assertEquals(epoch, guestLobby.verifyHandshake(offer, host, identity, null))
        guestLobby.acceptHostOffer(offer)
        assertTrue(guestLobby.acceptedHostSettings)

        val player = JsonObject(mapOf("name" to JsonPrimitive("Robin"), "deck" to deck()))
        val submission = iosPacket("submission", epoch, guestLobby, mapOf("player" to player))
        assertEquals(epoch, hostLobby.verifyHandshake(submission, guest, identity, epoch))
        hostLobby.submit(player, guest)
        hostLobby.submit(JsonObject(mapOf("name" to JsonPrimitive("Caleb"), "deck" to deck())), host)
        assertTrue(hostLobby.isReady)
        val seats = hostLobby.configuration()["seats"].array!!
        assertEquals(listOf("player1", "player2"), seats.map { it["seatId"].string })
        assertEquals(listOf("Caleb", "Robin"), seats.map { it["name"].string })
    }

    @Test fun aDifferentBuildIsReportedAsSuch() {
        val hostLobby = OnDeviceMultiplayerLobby(listOf(host, guest), host)
        val guestLobby = OnDeviceMultiplayerLobby(listOf(host, guest), guest)
        val other = BuildIdentity("a".repeat(40), "c".repeat(64), RELAY_ADAPTER_VERSION)
        val offer = EngineJson.decode(EngineJson.encode(JsonObject(mapOf("aiSettings" to hostLobby.aiSettings, "build" to other.json,
            "epoch" to JsonPrimitive(UUID.randomUUID().toString().uppercase()), "roster" to JsonArray(hostLobby.peerIDs.map(::JsonPrimitive)),
            "type" to JsonPrimitive("offer")))))
        try { guestLobby.verifyHandshake(offer, host, identity, null); fail("A different catalogue must not join") }
        catch (expected: OnDeviceMultiplayerLobby.HandshakeFailure.DifferentBuild) { }
    }

    @Test fun onlyTheHostMayOfferAndStart() {
        val guestLobby = OnDeviceMultiplayerLobby(listOf(host, guest, "p3-thirdCCC"), guest)
        val forged = iosPacket("offer", UUID.randomUUID(), guestLobby)
        try { guestLobby.verifyHandshake(forged, "p3-thirdCCC", identity, null); fail("A guest must not offer") }
        catch (expected: EngineError) { }
    }

    @Test fun matchingNamesGetSeatSuffixes() {
        val lobby = OnDeviceMultiplayerLobby(listOf(host, guest), host)
        lobby.submit(JsonObject(mapOf("name" to JsonPrimitive("Robin"), "deck" to deck())), host)
        lobby.submit(JsonObject(mapOf("name" to JsonPrimitive("robin"), "deck" to deck())), guest)
        assertEquals(mapOf("player1" to "Robin (player1)", "player2" to "robin (player2)"), lobby.seatNames)
    }

    @Test fun theSharedRollRoundTripsInIOSFormat() {
        val seats = listOf("player1", "player2", "player3")
        var values = listOf(12, 12, 7, 20, 14).iterator()
        val roll = OnDeviceStartingRoll.generate(seats) { values.next() }
        val decoded = OnDeviceStartingRoll.decode(EngineJson.decode(EngineJson.encode(roll.encoded(seats))), seats)
        assertEquals(roll, decoded)
        assertEquals("player1", decoded.winnerSeatID)
        values = listOf(3).iterator()
        assertEquals(5, roll.steps.size)
    }
}
