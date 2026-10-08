package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.UUID

/**
 * A revealed top card (Conspicuous Snoop, Future Sight, Courser of Kruphix) arrives as the player's `topCard`: it is
 * the library's one visible card, and a cast offered for it resolves (it used to be dropped as unknown). The helper
 * emblems' day or night and storm count, and a designation, reach the snapshot too. Mirrors iOS
 * OnDeviceSnapshotAdapterTests.testRevealedTopCardIsVisibleAndCastableWithTableHints.
 */
class OnDeviceTopCardTest {
    private val repo = File(System.getProperty("magicmobile.repo") ?: "../../..")
    private val fixtures = File(repo, "apps/ios/MagicMobileTests/Fixtures/OnDevice")

    @Test fun revealedTopCardIsVisibleAndCastableWithTableHints() {
        val original = MatchPoll(EngineJson.decode(File(fixtures, "2p-priority.json").readBytes()))
        val raw = original.raw.obj!!.toMutableMap()
        val root = original.snapshot.obj!!.toMutableMap()
        val view = root["gameView"].obj!!.toMutableMap()
        val viewer = view["myPlayerId"].string!!
        val topID = UUID.randomUUID().toString()
        val abilityID = UUID.randomUUID().toString()
        val template = view["myHand"].obj!!.values.first().obj!!.toMutableMap().apply { this["id"] = JsonPrimitive(topID) }
        view["players"] = JsonArray(view["players"].array!!.map { player ->
            if (player["playerId"].string != viewer) player
            else JsonObject(player.obj!!.toMutableMap().apply {
                this["topCard"] = JsonObject(template)
                this["designationNames"] = JsonArray(listOf(JsonPrimitive("City's Blessing")))
            })
        })
        val objects = (view["canPlayObjects"]["objects"].obj ?: emptyMap()).toMutableMap()
        objects[topID] = jsonObject("basicCastAbilities" to JsonArray(listOf(jsonObject("id" to JsonPrimitive(abilityID),
            "value" to JsonPrimitive("Cast from the top"), "manaAbility" to JsonPrimitive(false), "spellAbility" to JsonPrimitive(true)))))
        view["canPlayObjects"] = jsonObject("objects" to JsonObject(objects))
        fun rules(vararg lines: String) = jsonObject("rules" to JsonArray(lines.map { JsonPrimitive(it) }))
        view["myHelperEmblems"] = jsonObject(
            UUID.randomUUID().toString() to rules("Day or night.", "<br/><hintstart/>",
                "It's currently night, active player has cast 0 spells this turn. It will  become day next turn."),
            UUID.randomUUID().toString() to rules("Storm counter.", "<br/><hintstart/>", "Spells cast this turn: 3"))
        root["gameView"] = JsonObject(view)
        raw["snapshot"] = JsonObject(root)

        val snapshot = OnDeviceSnapshotAdapter.snapshot(MatchPoll(JsonObject(raw)), original.seatID)
        val me = snapshot.players.first { it.playerId == viewer }
        assertEquals("the revealed top card is the library's visible card", listOf(topID), me.zones.library.map { it.instanceId })
        val casts = snapshot.legalActions.orEmpty().filter { it.sourceInstanceId == topID && it.type == "cast_spell" }
        assertEquals("casting from the top of the library is offered", listOf(abilityID), casts.mapNotNull { it.abilityId })
        assertEquals("library", casts.first().sourceZone)
        assertEquals("night", snapshot.dayNight)
        assertEquals(3, snapshot.stormCount)
        assertEquals(listOf("City's Blessing"), me.designations)
        assertTrue(BoardZoneReference.PlayerZone.LIBRARY in GameplayAffordances.castableZones(me, snapshot, null))
        assertTrue("no other library shows a card", snapshot.players.filter { it.playerId != viewer }.all { it.zones.library.isEmpty() })
    }
}
