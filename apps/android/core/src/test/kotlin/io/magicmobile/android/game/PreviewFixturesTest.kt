package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The ported DEBUG board fixtures decode and keep the facts the iOS tests rely on (Build19LogicTests.swift). */
class PreviewFixturesTest {
    @Test fun everyPreviewStateDecodes() {
        for (state in GameBoardDesignPreviewState.entries) {
            val snapshot = GameBoardPreviewFixtures.snapshot(state)
            assertEquals("design-preview-${state.rawValue}", snapshot.id)
            assertNotNull(state.rawValue, snapshot.human)
        }
        for (step in 0 until GameBoardPreviewFixtures.boardFXStepCount) assertNotNull(GameBoardPreviewFixtures.boardFXStep(step).xmage)
    }

    @Test fun spectatingAndThinkingComeFromThePlayers() {
        val watching = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.SPECTATING)
        assertTrue(watching.isSpectating)
        assertEquals("one of three opponents is out as well", 2, watching.remainingOpponents.size)
        val thinking = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.AI_THINKING)
        assertFalse(thinking.isSpectating)
        assertNotNull(thinking.thinkingPlayerID)
        assertNull("your own priority is not the AI thinking", GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.NORMAL_BATTLEFIELD).thinkingPlayerID)
    }

    @Test fun fourPlayerSpectatingSeatsTheNextPlayerAndFollowsTheTurn() {
        val snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.FOUR_PLAYER_SPECTATING)
        assertTrue(snapshot.isSpectating)
        assertEquals(3, snapshot.remainingOpponents.size)
        val board = BoardOpponentFocus.snapshot(snapshot, BoardFocusTracker().observe(snapshot, followTurns = true).focusedID)
        assertEquals("Aurelia, next in turn order, stands in", "ai-1", board.seat?.playerId)
        assertEquals("the top follows Kozilek's turn", "ai-2", board.opponent?.playerId)
        assertEquals("human", board.human?.playerId)
        assertTrue("a stand-in's hand is a count only", BoardOpponentFocus.seatHand(board).isEmpty())
        assertEquals(2, board.seat!!.zones.visibleHandCount)
        assertEquals("Watching Aurelia", SpectatorSeatPresentation.title(board))
    }

    @Test fun boardShapesMatchIOS() {
        val normal = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.NORMAL_BATTLEFIELD)
        assertEquals(8, normal.human!!.zones.hand.size)
        assertEquals(listOf("human-plains-1", "human-forest-1", "human-commander", "human-preview-creature-0", "human-preview-creature-1",
            "human-preview-land-2", "human-sol-ring"), normal.human!!.zones.battlefield.map { it.instanceId })
        val tray = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.STACK_TRAY)
        assertEquals(13, tray.xmage!!.stack.size)
        val four = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.FOUR_PLAYER_FOCUS)
        assertEquals(listOf("You", "Aurelia", "Kozilek", "Meren"), four.players.map { it.displayName })
        assertEquals("Mulligan to 6 cards?", GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.OPENING_HAND).promptText)
    }
}
