package io.magicmobile.android.board

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import io.magicmobile.android.game.BattlefieldAttachments
import io.magicmobile.android.game.BoardDecisionPresentation
import io.magicmobile.android.game.BoardFXDirector
import io.magicmobile.android.game.BoardOpponentFocus
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardSize
import io.magicmobile.android.game.BoardZoneReference
import io.magicmobile.android.game.CombatArrow
import io.magicmobile.android.game.CombatArrowModel
import io.magicmobile.android.game.CombatHighlightSet
import io.magicmobile.android.game.CombatPlayerIdentity
import io.magicmobile.android.game.CombatSelectionState
import io.magicmobile.android.game.CombatViewportAnchors
import io.magicmobile.android.game.CompactPromptPopup
import io.magicmobile.android.game.GameBoardInteractionMode
import io.magicmobile.android.game.GameBoardInteractionState
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameplayActionPresentation
import io.magicmobile.android.game.InlinePaymentPromptState
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.PlayerGameState
import io.magicmobile.android.game.PortraitBattlefieldLayoutMetrics
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.MagicPalette

/**
 * The portrait board (NativeGameView.portraitGameContent): opponent HUD, their permanents and
 * lands, the center strip, your permanents and lands, the hand and the command bar, with
 * combat arrows and board effects above.
 */
@Composable
fun PortraitGameContent(
    snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState, size: BoardSize, selection: BoardSelection,
    pendingActionId: String?, pendingCardInstanceId: String?, liveUpdateStatus: String, combatSelection: CombatSelectionState,
    combatPreviewArrows: List<CombatArrow>, isOverPlayerDropZone: Boolean, setOverPlayerDropZone: (Boolean) -> Unit,
    setInteractionMode: (GameBoardInteractionMode) -> Unit, inspectingZoneTitle: String?, inspectingZoneCards: List<ZoneCard>,
    inspectingZoneReference: BoardZoneReference?, closeZone: () -> Unit, isPromptDetailOpen: Boolean, dragActionChoice: DragActionChoice?,
    setDragActionChoice: (DragActionChoice?) -> Unit, aiWaitBeganAt: Long, didRefresh: Boolean, didReconnect: Boolean, didDiagnose: Boolean,
    boardFX: BoardFXDirector, boardFXClock: BoardFXClock, pruneFX: () -> Unit, onInteractionFeedback: (String) -> Unit,
    runAction: (LegalAction) -> Unit, runCommand: (GameCommand, String, String) -> Unit, refreshGame: () -> Unit, reconnectGame: () -> Unit,
    submitTarget: (ZoneCard) -> Unit, handleCombatCardTap: (ZoneCard) -> Boolean, submitAttackers: (String) -> Unit, submitBlockers: () -> Unit,
    finishAttackers: () -> Unit, finishBlockers: () -> Unit, setCombatSelection: (CombatSelectionState) -> Unit, selectOpponent: (String) -> Unit,
    openLog: () -> Unit, openSettings: () -> Unit, openPromptDetails: () -> Unit, viewZone: (String, List<ZoneCard>) -> Unit,
    openPromptDetailSheet: () -> Unit,
) {
    val metrics = PortraitBattlefieldLayoutMetrics(size, paymentActive = InlinePaymentPromptState.isActive(snapshot), largeText = BoardMotion.largeText,
        centerControlsVisible = BoardDecisionPresentation.needsCenterSpace(snapshot, false))
    val actions = snapshot.legalActions ?: emptyList()
    val targetableIds = GameBoardInteractionState.boardTargetableIds(snapshot)
    val combatHighlights = CombatHighlightSet(combatSelection, actions, snapshot.xmage?.combat ?: emptyList())
    val shouldShowCompactPrompt = CompactPromptPopup.shouldShow(snapshot, pendingActionId)
    val allBattlefield = snapshot.players.flatMap { it.zones.battlefield }
    val playerIDs = snapshot.players.map { it.playerId }.toSet()
    fun lane(cards: List<ZoneCard>, lands: Boolean) = BattlefieldAttachments.lane(cards, allBattlefield, lands, playerIDs)
    val registry = LocalCardBounds.current
    val passAction = actions.firstOrNull { it.type == "pass_priority" } ?: actions.firstOrNull { it.type == "pass_until_response" }

    Box(Modifier.fillMaxSize()) {
        PortraitOpponentStatusBar(snapshot, snapshot.playerLabel(opponent.playerId), opponent, human.playerId,
            CombatPlayerIdentity.targetID(opponent.playerId, snapshot, combatHighlights.defenderIds) != null,
            { CombatPlayerIdentity.targetID(opponent.playerId, snapshot, combatHighlights.defenderIds)?.let(submitAttackers) },
            openLog, Modifier.place(metrics.topHUDRect).zIndex(3f), viewZone, selectOpponent)

        PortraitBattlefieldPermanentGroup("Opponent board", lane(opponent.zones.battlefield, false), actions, targetableIds, combatHighlights.cardIds, selection,
            metrics.permanentCardWidth, metrics.permanentCardHeight, metrics.opponentBattlefieldRect.width, metrics.opponentBattlefieldRect.height,
            runAction, submitTarget, handleCombatCardTap, Modifier.place(metrics.opponentBattlefieldRect), flipped = true)

        BattlefieldRow("Opponent lands", lane(opponent.zones.battlefield, true), actions, targetableIds, combatHighlights.cardIds, selection,
            metrics.landCardWidth, metrics.landCardHeight, metrics.opponentLandsRect.width, runAction, submitTarget, handleCombatCardTap,
            Modifier.place(metrics.opponentLandsRect), flipped = true)

        Column(Modifier.place(metrics.centerStripRect), verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (InlinePaymentPromptState.isActive(snapshot)) {
                    InlinePaymentPromptBar(snapshot, pendingActionId, runAction, runCommand, openPromptDetails, Modifier.weight(1f))
                } else if (BoardDecisionPresentation.showsGuidance(snapshot)) {
                    PromptPill(snapshot, Modifier.weight(1f), combatSelection)
                }
                val revealed = snapshot.xmage?.revealed?.flatMap { it.cards } ?: emptyList()
                val lookedAt = snapshot.xmage?.lookedAt?.flatMap { it.cards } ?: emptyList()
                val inspect = LocalBoardZoneInspectionAction.current
                if (revealed.isNotEmpty()) FloatingZoneChip("Revealed", revealed.size, "eye") { inspect?.invoke(BoardZoneReference.Collection(BoardZoneReference.NamedKind.REVEALED)) }
                if (lookedAt.isNotEmpty()) FloatingZoneChip("Looked", lookedAt.size, "eye.trianglebadge.exclamationmark") {
                    inspect?.invoke(BoardZoneReference.Collection(BoardZoneReference.NamedKind.LOOKED_AT))
                }
            }
        }

        PortraitBattlefieldPermanentGroup("Your board", lane(human.zones.battlefield, false), actions, targetableIds, combatHighlights.cardIds, selection,
            metrics.permanentCardWidth, metrics.permanentCardHeight, metrics.playerBattlefieldRect.width, metrics.playerBattlefieldRect.height,
            runAction, submitTarget, handleCombatCardTap, Modifier.place(metrics.playerBattlefieldRect),
            allowsManaUndo = true, manaPaymentActive = snapshot.manaPayment?.active == true)

        BattlefieldRow("Your lands", lane(human.zones.battlefield, true), actions, targetableIds, combatHighlights.cardIds, selection,
            metrics.landCardWidth, metrics.landCardHeight, metrics.playerLandsRect.width, runAction, submitTarget, handleCombatCardTap,
            Modifier.place(metrics.playerLandsRect), allowsManaUndo = true, manaPaymentActive = snapshot.manaPayment?.active == true)

        PortraitHandRow(BoardOpponentFocus.seatHand(snapshot), actions, selection, pendingCardInstanceId, setInteractionMode, metrics.playerDropZone, setOverPlayerDropZone,
            metrics.handCardWidth, metrics.handCardHeight, metrics.handRect.width, onInteractionFeedback,
            { choiceActions, message -> setDragActionChoice(DragActionChoice(message, choiceActions)) }, runAction,
            Modifier.place(metrics.handRect).zIndex(4f), hiddenCount = if (snapshot.isViewer(human.playerId)) null else human.zones.visibleHandCount)

        if (isOverPlayerDropZone) {
            Box(Modifier.place(metrics.playerDropZone).background(MagicPalette.antiqueGold.copy(alpha = 0.13f), RoundedCornerShape(14.dp))
                .border(2.dp, MagicPalette.antiqueGold.copy(alpha = 0.70f), RoundedCornerShape(14.dp)))
        }

        if (!snapshot.isSpectating) {
            PortraitBottomCommandBar(snapshot.playerLabel(human.playerId), human, opponent.playerId, human.manaPool, passAction,
                GameplayActionPresentation.yieldActions(actions), pendingActionId, snapshot, selection, openLog, openSettings, openPromptDetails, viewZone,
                runAction, runCommand, Modifier.place(metrics.bottomControlsRect).zIndex(5f))
        }

        if (CombatSelectionState.isDeclareAttackers(snapshot)) {
            val declared = snapshot.xmage?.combat?.flatMap { it.attackers }?.size ?: 0
            val hasPending = combatSelection.selectedAttackerIds.isNotEmpty()
            CombatSubmitPill(if (hasPending) "Cancel Selection" else if (declared == 0) "No Attacks" else "Done Attacking",
                maxOf(declared, combatSelection.selectedAttackerIds.size), {
                    if (hasPending) setCombatSelection(combatSelection.clearAttackers()) else finishAttackers()
                }, Modifier.centerAt(metrics.centerStripRect.midX, metrics.centerStripRect.maxY + 20).zIndex(19f))
        } else if (CombatSelectionState.isDeclareBlockers(snapshot)) {
            val declared = snapshot.xmage?.combat?.flatMap { it.blockers }?.size ?: 0
            val hasPending = combatSelection.selectedBlockerId != null
            CombatSubmitPill(if (hasPending) "Cancel Selection" else if (declared == 0) "No Blocks" else "Done Blocking",
                maxOf(declared, combatSelection.blockerPairCount), {
                    when {
                        hasPending -> setCombatSelection(combatSelection.clearBlockers())
                        combatSelection.hasPendingBlockers -> submitBlockers()
                        else -> finishBlockers()
                    }
                }, Modifier.centerAt(metrics.centerStripRect.midX, metrics.centerStripRect.maxY + 20).zIndex(19f))
        }

        // Combat arrows and board effects, drawn over the lanes in board coordinates.
        val bounds = registry?.bounds ?: emptyMap()
        if (inspectingZoneTitle == null && selection.inspectedCard == null) {
            PortraitCombatArrowOverlay(snapshot, snapshot.xmage?.combat ?: emptyList(), combatPreviewArrows, metrics, human.zones.battlefield,
                opponent.zones.battlefield, bounds, opponent.playerId, Modifier.zIndex(6f))
            Box(Modifier.fillMaxSize().zIndex(7f)) {
                CombatEdgeIndicators(human.zones.battlefield + opponent.zones.battlefield,
                    CombatArrowModel.arrows(snapshot.xmage?.combat ?: emptyList(), combatPreviewArrows).flatMap { listOf(it.fromId, it.toId) }.toSet(),
                    bounds, listOf(metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect),
                    CombatViewportAnchors.laneIndices(human.zones.battlefield, opponent.zones.battlefield)) { selection.inspectedCard = it }
            }
        }
        BoardFXOverlay(boardFX.active, boardFX.subjects, bounds, BoardFXAnchors(snapshot.viewerID,
            viewerPoint = BoardPoint(metrics.bottomHUDRect.minX + 34, metrics.bottomHUDRect.maxY - 78),
            opponentPoint = BoardPoint(metrics.topHUDRect.minX + 44, metrics.topHUDRect.maxY + 26),
            stackPoint = BoardPoint(metrics.centerStripRect.midX, metrics.centerStripRect.midY),
            viewerHandPoint = BoardPoint(metrics.handRect.midX, metrics.handRect.midY),
            opponentHandPoint = BoardPoint(metrics.opponentBattlefieldRect.midX, metrics.opponentBattlefieldRect.minY - 40)),
            boardFXClock, pruneFX, Modifier.zIndex(8f))

        AnimatedVisibility(inspectingZoneTitle != null, Modifier.place(metrics.detailSheetRect).zIndex(70f),
            enter = if (BoardMotion.reduceMotion) fadeIn() else scaleIn() + fadeIn(), exit = if (BoardMotion.reduceMotion) fadeOut() else scaleOut() + fadeOut()) {
            val title = inspectingZoneReference?.title(snapshot) ?: inspectingZoneTitle ?: ""
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CompactZoneInspectorOverlay(title, inspectingZoneReference?.cards(snapshot) ?: inspectingZoneCards, actions, pendingActionId, selection,
                    runAction, closeZone, targetableIDs = targetableIds, runTargetAction = submitTarget)
            }
        }

        selection.inspectedCard?.let { card ->
            Box(Modifier.fillMaxSize().zIndex(99f).clickable(remember { MutableInteractionSource() }, null) { selection.inspectedCard = null })
            CardInspector(card, Modifier.place(metrics.detailSheetRect).zIndex(100f))
        }

        val playerTargets = targetableIds.any { id -> snapshot.players.any { CombatPlayerIdentity.ids(it.playerId, snapshot).contains(id) } }
        AnimatedVisibility(shouldShowCompactPrompt && !isPromptDetailOpen && (targetableIds.isEmpty() || playerTargets),
            Modifier.place(metrics.compactPromptRect).zIndex(20f), enter = if (BoardMotion.reduceMotion) fadeIn() else scaleIn() + fadeIn(),
            exit = if (BoardMotion.reduceMotion) fadeOut() else scaleOut() + fadeOut()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CompactPromptPopupView(snapshot, pendingActionId, runAction, runCommand, openPromptDetailSheet, Modifier.fillMaxWidth())
            }
        }

        dragActionChoice?.let { choice ->
            DragActionChoicePopup(choice, pendingActionId, { action -> setDragActionChoice(null); selection.selectedCard = null; runAction(action) },
                { setDragActionChoice(null); selection.selectedCard = null },
                Modifier.requiredWidth(metrics.compactPromptRect.width.dp).centerAt(metrics.compactPromptRect.midX, metrics.compactPromptRect.midY).zIndex(21f))
        }

        if (snapshot.isWaitingOnAIOrStalled) {
            AIWaitFallbackControls(snapshot, pendingActionId, liveUpdateStatus, aiWaitBeganAt, didRefresh, didReconnect, didDiagnose, refreshGame, reconnectGame,
                Modifier.requiredWidth(minOf(metrics.safeFrame.width - 28, 360f).dp).centerAt(metrics.safeFrame.midX, metrics.safeFrame.midY).zIndex(80f))
        }
    }
}
