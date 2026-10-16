package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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

    /** Mirrors testRemovalPlaysInOrderBeforeAnythingElse (Caleb, 2026-10-15: Path to Exile flashed by under the next plays). */
    @Test fun removalPlaysInOrderBeforeAnythingElse() {
        for (level in listOf(BoardFXLevel.FULL, BoardFXLevel.REDUCED)) {
            val batch = BoardFXScheduler.schedule(listOf(
                BoardFXEvent.SpellCast("s", "Path to Exile", "b", BoardFXTint.WHITE, BoardFXSpellWeight.SPELL),
                BoardFXEvent.LeftBattlefield("commander", "a", BoardFXZone.EXILE, BoardFXTint.GREEN),
                BoardFXEvent.EnteredBattlefield("plains", "b", BoardFXZone.HAND, BoardFXTint.WHITE, BoardFXEntrance.PLAIN),
                BoardFXEvent.LifeChanged("b", 1)), level)
            assertTrue("$level: the exile waits for the whole read", batch[1].delay >= batch[0].end - 1e-9)
            assertTrue("$level: the next play waits for the exile", batch[2].delay >= batch[1].end - 1e-9)
            assertEquals(batch[0].end, batch[0].holdsLaterBatchesUntil)
            assertEquals(batch[1].end, batch[1].holdsLaterBatchesUntil)
        }
        val triggers = BoardFXScheduler.schedule(listOf(
            BoardFXEvent.SpellCast("t", "Trigger", "b", BoardFXTint.WHITE, BoardFXSpellWeight.ABILITY),
            BoardFXEvent.LifeChanged("b", 1)), BoardFXLevel.FULL)
        assertTrue("repeated triggers keep their pace", triggers[1].delay < triggers[0].end)
    }

    /** Mirrors testTokenPileChoosesTheNextAndShowsChosenBeside. */
    @Test fun tokenPileChoosesTheNextAndShowsChosenBeside() {
        val squirrels = (1..10).map { ZoneCard("sq$it", CardIdentity("Squirrel", "Token Creature — Squirrel", isToken = true)) }
        val pile = BattlefieldCardGroup("pile", squirrels)
        val all = squirrels.map { it.instanceId }.toSet()
        assertEquals(listOf(10), BattlefieldTokenStack.displayGroups(pile, false, emptySet()).map { it.count })
        assertEquals("sq1", BattlefieldTokenStack.nextTargetable(pile, all, emptySet())?.instanceId)
        val chosen = setOf("sq1", "sq2")
        val tiles = BattlefieldTokenStack.displayGroups(pile, false, chosen)
        assertEquals(listOf(8, 1, 1), tiles.map { it.count })
        assertEquals("pile", tiles.first().id)
        assertEquals(listOf("sq1", "sq2"), tiles.drop(1).map { it.representative.instanceId })
        assertEquals("sq3", BattlefieldTokenStack.nextTargetable(pile, all, chosen)?.instanceId)
        assertEquals(listOf(9, 1), BattlefieldTokenStack.displayGroups(pile, false, setOf("sq2")).map { it.count })
        assertEquals(10, BattlefieldTokenStack.displayGroups(pile, true, chosen).size)
        assertNull(BattlefieldTokenStack.nextTargetable(pile, all, all))
    }
}
