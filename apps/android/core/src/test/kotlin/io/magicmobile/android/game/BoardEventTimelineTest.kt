package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors BoardEventTimelineTests.swift testCommanderCastAndEntranceAreCeremonial (iOS build 26). */
class BoardEventTimelineTest {
    private fun state(cards: List<BoardFXState.Card>, stack: List<BoardFXState.StackItem> = emptyList()) =
        BoardFXState("match", "main", mapOf("a" to 40, "b" to 40), cards.associateBy { it.id }, stack)

    private fun fxCard(id: String, player: String, zone: BoardFXZone = BoardFXZone.BATTLEFIELD, name: String = "Bear") =
        BoardFXState.Card(id, player, zone, name, BoardFXTint.GREEN, 0, 0, false)

    @Test fun commanderCastIsItsOnlyCeremony() {
        val inCommand = state(listOf(fxCard("cmd", "a", BoardFXZone.COMMAND, name = "Atraxa")))
        val cast = state(emptyList(), listOf(BoardFXState.StackItem("s", "Atraxa", "a", BoardFXTint.MULTICOLOR, manaValue = 4)))
        assertEquals(listOf(BoardFXEvent.SpellCast("s", "Atraxa", "a", BoardFXTint.MULTICOLOR, BoardFXSpellWeight.COMMANDER)),
            BoardEventDiffer.events(inCommand, cast, setOf("Atraxa")))
        val entered = state(listOf(fxCard("cmd-2", "a", name = "Atraxa")))
        // The cast was the ceremony; the commander then flies off the stack without a second one.
        assertEquals(listOf(BoardFXEvent.EnteredBattlefield("cmd-2", "a", BoardFXZone.STACK, BoardFXTint.GREEN, BoardFXEntrance.PLAIN)),
            BoardEventDiffer.events(cast, entered, setOf("Atraxa")))
        // Put straight onto the battlefield (no cast seen), it gets the ceremony on arrival.
        assertEquals(BoardFXEvent.EnteredBattlefield("cmd-2", "a", null, BoardFXTint.GREEN, BoardFXEntrance.COMMANDER),
            BoardEventDiffer.events(inCommand, entered, setOf("Atraxa")).last())
    }

    /** Mirrors testSmartPassHoldsForSpellsAndRemovalButNotTriggers. */
    @Test fun smartPassHoldsForSpellsAndRemovalButNotTriggers() {
        val held = listOf(
            BoardFXEvent.SpellCast("s", "Path to Exile", "b", BoardFXTint.WHITE, BoardFXSpellWeight.SPELL),
            BoardFXEvent.LeftBattlefield("bear", "a", BoardFXZone.EXILE, BoardFXTint.GREEN),
            BoardFXEvent.EnteredBattlefield("angel", "b", BoardFXZone.HAND, BoardFXTint.WHITE, BoardFXEntrance.SHOWCASE))
        val quick = listOf(
            BoardFXEvent.SpellCast("t", "Soul Warden", "b", BoardFXTint.WHITE, BoardFXSpellWeight.ABILITY),
            BoardFXEvent.LifeChanged("b", 1),
            BoardFXEvent.EnteredBattlefield("land", "a", BoardFXZone.HAND, BoardFXTint.COLORLESS, BoardFXEntrance.PLAIN))
        for (level in listOf(BoardFXLevel.FULL, BoardFXLevel.REDUCED)) {
            assertTrue("$level", BoardFXScheduler.schedule(held, level).all { it.holdsSmartPass })
            assertFalse("$level", BoardFXScheduler.schedule(quick, level).any { it.holdsSmartPass })
        }
    }
}
