package io.magicmobile.android

import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Test

class GameplayCuesTest {
    private val viewer="00000000-0000-0000-0000-000000000001"
    private val card="00000000-0000-0000-0000-000000000002"
    private val prompt=Decision("prompt",1,"SELECT",mapOf("selectMode" to "priority","manaPlayerId" to viewer),setOf("uuid","boolean"),false,null,null)
    private fun snapshot(family:String="basicCastAbilities"):Obj=mapOf("enginePlayerId" to viewer,"gameView" to mapOf("myPlayerId" to viewer,
        "players" to listOf(mapOf("playerId" to viewer,"commandList" to listOf(mapOf("id" to card)))),
        "canPlayObjects" to mapOf("objects" to mapOf(card to mapOf(family to listOf(mapOf("id" to card,"value" to "Cast commander")))))))

    @Test fun commanderCueRequiresCurrentAuthorizedCastFamily() {
        assertEquals(setOf(card),castableCommanderIds(prompt,snapshot(),viewer))
        assertTrue(castableCommanderIds(prompt.copy(submitted=true),snapshot(),viewer).isEmpty())
        assertTrue(castableCommanderIds(prompt.copy(kind="PLAY_MANA"),snapshot(),viewer).isEmpty())
        assertTrue(castableCommanderIds(prompt,snapshot("basicManaAbilities"),viewer).isEmpty())
        assertTrue(castableCommanderIds(prompt,snapshot(),"other").isEmpty())
        assertTrue(castableCommanderIds(prompt.copy(responseTypes=setOf("boolean")),snapshot(),viewer).isEmpty())
    }

    @Test fun floatingManaUsesExactPlayerAndColorResponse() {
        val choice=Choice("Use floating BLUE","mana",mapOf("playerId" to viewer,"manaType" to "BLUE"))
        assertEquals(choice,floatingManaChoice(listOf(choice),viewer,"blue"))
        assertNull(floatingManaChoice(listOf(choice),"other","blue"))
        assertNull(floatingManaChoice(listOf(choice),viewer,"black"))
        assertNull(floatingManaChoice(listOf(choice.copy(type="string")),viewer,"blue"))
    }

    @Test fun transportSeatResolvesEngineIdentityForBothCues() {
        val poll=GamePoll("match","player-1",1,"running",snapshot(),prompt,false,emptyList(),null)
        assertNotEquals(viewer,poll.viewerId)
        assertEquals(viewer,gameplayViewerId(poll))
        assertEquals(setOf(card),castableCommanderIds(poll.decision,poll.snapshot,gameplayViewerId(poll)))
        val choice=Choice("Use floating BLUE","mana",mapOf("playerId" to viewer,"manaType" to "BLUE"))
        assertEquals(choice,floatingManaChoice(listOf(choice),gameplayViewerId(poll),"blue"))
        assertNull(gameplayViewerId(poll.copy(snapshot=snapshot()-("enginePlayerId"))))
        assertNull(gameplayViewerId(poll.copy(snapshot=snapshot()+("enginePlayerId" to card))))
        assertNull(gameplayViewerId(poll.copy(snapshot=snapshot()+("enginePlayerId" to "player-1"))))
    }
}
