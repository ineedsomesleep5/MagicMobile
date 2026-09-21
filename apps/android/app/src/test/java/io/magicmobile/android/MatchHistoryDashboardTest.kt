package io.magicmobile.android

import io.magicmobile.android.core.Obj
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class MatchHistoryDashboardTest {
    private val viewer=UUID.randomUUID().toString()
    private val rival=UUID.randomUUID().toString()
    private fun snapshot(name:String="AI rival"):Obj=mapOf(
        "gameView" to mapOf("myPlayerId" to viewer,"players" to listOf(
            mapOf("playerId" to viewer,"name" to "You","myHand" to listOf("secret")),
            mapOf("playerId" to rival,"name" to name,"hand" to listOf("hidden")))),
        "commanders" to mapOf(UUID.randomUUID().toString() to mapOf(
            "ownerPlayerId" to rival,"name" to "Aurelia, the Warleader",
            "damageToPlayers" to mapOf(viewer to 7))),
        "authorizedOpponentHands" to mapOf("secret" to listOf("Never save")))

    @Test fun recordsOnlyPublicOpponentNamesAndCommanderNames() {
        val opponents=publicOpponents(snapshot(),viewer,1)
        assertEquals(listOf(RecordedOpponent(rival,"AI rival",listOf("Aurelia, the Warleader"))),opponents)
        val serialized=opponents.toString()
        assertFalse(serialized.contains("secret"))
        assertFalse(serialized.contains("hidden"))
        assertFalse(serialized.contains("Never save"))
        assertFalse(serialized.contains("damageToPlayers"))
    }

    @Test fun malformedOrMismatchedPublicIdentityIsNotRecorded() {
        assertNull(publicOpponents(snapshot("Bad\nname"),viewer,1))
        assertNull(publicOpponents(snapshot(),UUID.randomUUID().toString(),1))
        assertNull(publicOpponents(snapshot(),viewer,2))
        val duplicate=snapshot()+("gameView" to mapOf("myPlayerId" to viewer,"players" to listOf(
            mapOf("playerId" to viewer,"name" to "You"),mapOf("playerId" to viewer,"name" to "Again"))))
        assertNull(publicOpponents(duplicate,viewer,1))
    }

    @Test fun missingOpponentFieldRemainsCompatibleWithOlderSavedRows() {
        assertNull(decodeRecordedOpponents(mapOf("deckName" to "Old match")))
        assertNull(decodeRecordedOpponents(mapOf("opponents" to null)))
        assertEquals(listOf(RecordedOpponent(rival,"AI rival",listOf("Aurelia"))),
            decodeRecordedOpponents(mapOf("opponents" to listOf(mapOf(
                "playerId" to rival,"name" to "AI rival","commanders" to listOf("Aurelia"))))))
    }
}
