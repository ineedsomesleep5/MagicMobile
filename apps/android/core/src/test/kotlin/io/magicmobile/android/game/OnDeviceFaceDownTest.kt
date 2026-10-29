package io.magicmobile.android.game

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * A face-down card its owner may look at (Hideaway's exile, a morph) shows as the real card from CardView's
 * `secondCardFace`, marked face down; without that face it stays a hidden placeholder. Mirrors iOS
 * OnDeviceSnapshotAdapterTests.testOwnFaceDownCardShowsItsRealFace.
 */
class OnDeviceFaceDownTest {
    private val repo = File(System.getProperty("magicmobile.repo") ?: "../../..")
    private val fixtures = File(repo, "apps/ios/MagicMobileTests/Fixtures/OnDevice")

    private fun handCard(edit: (MutableMap<String, kotlinx.serialization.json.JsonElement>, JsonObject) -> Unit): CardIdentity {
        val original = MatchPoll(EngineJson.decode(File(fixtures, "2p-priority.json").readBytes()))
        val raw = original.raw.obj!!.toMutableMap()
        val root = original.snapshot.obj!!.toMutableMap()
        val view = root["gameView"].obj!!.toMutableMap()
        val hand = view["myHand"].obj!!.toMutableMap()
        val (key, first) = hand.entries.first()
        val real = first.obj!!
        val card = real.toMutableMap()
        edit(card, JsonObject(real))
        hand[key] = JsonObject(card)
        view["myHand"] = JsonObject(hand)
        root["gameView"] = JsonObject(view)
        raw["snapshot"] = JsonObject(root)
        val snapshot = OnDeviceSnapshotAdapter.snapshot(MatchPoll(JsonObject(raw)), original.seatID)
        val id = real["id"].string!!
        return snapshot.players.flatMap { it.zones.hand }.first { it.instanceId == id }.card
    }

    @Test fun ownFaceDownCardShowsItsRealFace() {
        var realName = ""
        val card = handCard { card, real ->
            realName = real["name"].string!!
            card["name"] = JsonPrimitive("Face Down: $realName"); card["displayName"] = JsonPrimitive("Face Down: $realName")
            card["faceDown"] = JsonPrimitive(true); card["hideInfo"] = JsonPrimitive(false)
            card["secondCardFace"] = real
        }
        assertEquals(realName, card.name)
        assertEquals(true, card.faceDown)
        assertTrue(card.typeLine.isNotEmpty())
    }

    @Test fun faceDownWithoutItsFaceStaysHidden() {
        val card = handCard { card, _ ->
            card["name"] = JsonPrimitive("Morph"); card["displayName"] = JsonPrimitive("Morph")
            card["faceDown"] = JsonPrimitive(true); card["hideInfo"] = JsonPrimitive(false); card["secondCardFace"] = JsonNull
        }
        assertEquals("Face-down card", card.name)
        assertNull(card.faceDown)
        assertEquals("", card.typeLine)
    }
}
