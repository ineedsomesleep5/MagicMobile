package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * An attacked planeswalker that dies to trample damage leaves its attackers attacking nothing: XMage drops the
 * group's defenderId. That is a legal state, not a corrupt update (it froze the board). Mirrors iOS
 * OnDeviceSnapshotAdapterTests.testCombatGroupWithoutDefenderStillAdapts.
 */
class OnDeviceCombatDefenderTest {
    private val repo = File(System.getProperty("magicmobile.repo") ?: "../../..")
    private val fixtures = File(repo, "apps/ios/MagicMobileTests/Fixtures/OnDevice")

    @Test fun combatGroupWithoutDefenderStillAdapts() {
        val original = MatchPoll(EngineJson.decode(File(fixtures, "2p-combat.json").readBytes()))
        val raw = original.raw.obj!!.toMutableMap()
        val root = original.snapshot.obj!!.toMutableMap()
        val view = root["gameView"].obj!!.toMutableMap()
        val group = view["combat"].array!!.first().obj!!.toMutableMap()
        group.remove("defenderId"); group["defenderName"] = JsonPrimitive("")
        view["combat"] = JsonArray(listOf(JsonObject(group)))
        root["gameView"] = JsonObject(view)
        raw["snapshot"] = JsonObject(root)

        val snapshot = OnDeviceSnapshotAdapter.snapshot(MatchPoll(JsonObject(raw)), original.seatID)
        val adapted = snapshot.xmage!!.combat.first()
        assertEquals("none", adapted.defenderKind)
        assertEquals("No defender", adapted.defenderName)
        assertTrue(snapshot.players.none { it.playerId == adapted.defenderId })
        assertEquals("Isamaru, Hound of Konda", adapted.attackers.first().card.name)
        assertEquals(true, adapted.attackers.first().isAttacking)
    }
}
