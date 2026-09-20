package io.magicmobile.android

import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Test

class GameplayCuesTest {
    private val viewer="00000000-0000-0000-0000-000000000001"
    private val card="00000000-0000-0000-0000-000000000002"
    private val prompt=Decision("prompt",1,"SELECT",mapOf("selectMode" to "priority","manaPlayerId" to viewer),setOf("uuid","boolean"),false,null,null)
    @Test fun attachmentGroupingFollowsOnlyPresentAcyclicEngineHosts() {
        val host:Obj=mapOf("id" to "host","controllerId" to "opponent")
        val aura:Obj=mapOf("id" to "aura","attachedTo" to "host","controllerId" to "you")
        val nested:Obj=mapOf("id" to "nested","attachedTo" to "aura")
        val all=listOf(host,aura,nested)
        assertEquals("host",battlefieldAttachmentRoot(aura,all))
        assertEquals("host",battlefieldAttachmentRoot(nested,all))
        assertNull(battlefieldAttachmentRoot(host,all))
        assertNull(battlefieldAttachmentRoot(aura,listOf(aura)))
        assertNull(battlefieldAttachmentRoot(aura,listOf(aura,host+("attachedTo" to "aura"))))
        assertNull(battlefieldAttachmentRoot(aura+("attachedTo" to "aura"),all))
        val playerAura=aura+("attachedTo" to viewer)
        assertEquals(viewer,battlefieldAttachmentRoot(playerAura,listOf(playerAura,nested),setOf(viewer)))
        assertEquals(viewer,battlefieldAttachmentRoot(nested,listOf(playerAura,nested),setOf(viewer)))
        assertNull(battlefieldAttachmentRoot(playerAura,listOf(playerAura),emptySet()))
    }

    @Test fun phasedStateMustBeExplicitAndPublicPlayerCountersStayExact() {
        assertTrue(isPhasedOut(mapOf("phasedIn" to false)))
        assertFalse(isPhasedOut(emptyMap()))
        assertFalse(isPhasedOut(mapOf("phasedIn" to true)))
        assertFalse(isPhasedOut(mapOf("phasedIn" to "false")))
        val hiddenPhased:Obj=mapOf("phasedIn" to false,"faceDown" to true,"power" to "99","manaCostLeftStr" to listOf("{B}"))
        assertEquals("Phased out",GameplayPresentation.status(hiddenPhased))
        assertNull(GameplayPresentation.printedCost(hiddenPhased))
        assertEquals(listOf("3 poison","2 energy","Monarch","Initiative"),publicPlayerBadges(mapOf(
            "counters" to listOf(mapOf("name" to "poison","count" to 3),mapOf("name" to "energy","count" to 2),mapOf("name" to "experience","count" to 0)),
            "monarch" to true,"initiative" to true)))
        assertTrue(publicPlayerBadges(emptyMap()).isEmpty())
    }

    @Test fun responseCueIsOwnedCurrentPriorityWithActualStep() {
        val game:Obj=mapOf("step" to "UPKEEP")
        assertEquals("Your response window · Upkeep",priorityResponseCue(prompt,game,viewer))
        assertNull(priorityResponseCue(prompt.copy(submitted=true),game,viewer))
        assertNull(priorityResponseCue(prompt.copy(kind="PLAY_MANA"),game,viewer))
        assertNull(priorityResponseCue(prompt,game,"other"))
    }

    @Test fun responseCueSkipsOnlyOwnEmptyMainPhase() {
        listOf("PRECOMBAT_MAIN","POSTCOMBAT_MAIN","Main 1","MAIN2","precombat-main").forEach{step->
            val own:Obj=mapOf("activePlayerId" to viewer,"step" to step,"stack" to emptyList<Obj>())
            assertNull(priorityResponseCue(prompt,own,viewer))
            assertNotNull(priorityResponseCue(prompt,own+("activePlayerId" to "opponent"),viewer))
            assertTrue(priorityResponseCue(prompt,own+("stack" to listOf(mapOf("id" to card))),viewer)!!.startsWith("Respond to the stack ·"))
        }
        listOf("UPKEEP","DECLARE_ATTACKERS","DECLARE_BLOCKERS","END_COMBAT","END_TURN").forEach{step->
            assertNotNull(priorityResponseCue(prompt,mapOf("activePlayerId" to viewer,"step" to step),viewer))
        }
        assertNull(priorityResponseCue(prompt,mapOf("activePlayerId" to viewer,"phase" to "POSTCOMBAT_MAIN"),viewer))
        assertNotNull(priorityResponseCue(prompt,mapOf("step" to "PRECOMBAT_MAIN"),viewer))
    }

    @Test fun passHelperExplainsStackWithoutClaimingImmediateResolution() {
        val pass=Choice("Pass priority","boolean",true)
        val empty=priorityPassHelp(prompt,pass,mapOf("stack" to emptyList<Obj>()),viewer)!!
        assertEquals("Let this step continue",empty.text)
        assertEquals("Other players may respond. The step advances only if everyone passes.",empty.accessibility)
        val stacked=priorityPassHelp(prompt,pass,mapOf("stack" to mapOf(card to mapOf("id" to card))),viewer)!!
        assertEquals("Let others respond",stacked.text)
        assertEquals("Other players may respond. The top spell or ability resolves only if everyone passes.",stacked.accessibility)
    }

    @Test fun passHelperRequiresCurrentAuthorizedPriorityPass() {
        val pass=Choice("Pass priority","boolean",true)
        val game:Obj=mapOf("stack" to emptyList<Obj>())
        assertNull(priorityPassHelp(prompt.copy(submitted=true),pass,game,viewer))
        assertNull(priorityPassHelp(prompt,pass,game,null))
        assertNull(priorityPassHelp(prompt,pass,game,"opponent"))
        assertNull(priorityPassHelp(prompt,pass,null,viewer))
        assertNull(priorityPassHelp(prompt,pass,emptyMap(),viewer))
        listOf("ASK","PLAY_MANA","PLAY_X_MANA","PICK_TARGET").forEach{kind->assertNull(priorityPassHelp(prompt.copy(kind=kind),pass,game,viewer))}
        listOf("attackers","blockers").forEach{mode->assertNull(priorityPassHelp(prompt.copy(payload=prompt.payload+("selectMode" to mode)),pass,game,viewer))}
        assertNull(priorityPassHelp(prompt.copy(payload=prompt.payload+("options" to mapOf("possibleAttackers" to emptyList<String>()))),pass,game,viewer))
        assertNull(priorityPassHelp(prompt.copy(responseTypes=setOf("uuid")),pass,game,viewer))
        assertNull(priorityPassHelp(prompt,pass.copy(value=false),game,viewer))
        assertNull(priorityPassHelp(prompt,pass.copy(type="string",value="true"),game,viewer))
    }

    @Test fun analysisSymbolsResolveBothBracedAndBareMana() {
        assertEquals(ManaSymbols.drawable("B"),ManaSymbols.drawable("{B}"))
        assertNotNull(ManaSymbols.drawable("{U}"))
        assertEquals("2",ManaSymbols.normalized("{2}"))
        assertEquals("W/U",ManaSymbols.normalized("{W/U}"))
    }
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
