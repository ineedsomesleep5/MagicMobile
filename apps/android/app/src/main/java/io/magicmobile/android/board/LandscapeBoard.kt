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
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import androidx.compose.ui.zIndex
import io.magicmobile.android.game.BattlefieldAttachments
import io.magicmobile.android.game.BattlefieldLayoutMetrics
import io.magicmobile.android.game.BattlefieldRowArrangement
import io.magicmobile.android.game.BoardDecisionPresentation
import io.magicmobile.android.game.BoardFXDirector
import io.magicmobile.android.game.BoardOpponentFocus
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardResponseCue
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
import io.magicmobile.android.game.GameplayAffordances
import io.magicmobile.android.game.InlinePaymentPromptState
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.PhaseTitles
import io.magicmobile.android.game.PlayerGameState
import io.magicmobile.android.game.TargetingHelperVisibility
import io.magicmobile.android.game.XmageStackObject
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf

/** Swift GameOrientationMode: the portrait board only when portrait play is on and the screen is taller than wide. */
object GameOrientationMode {
    fun isPortraitLayout(width: Float, height: Float, portraitEnabled: Boolean): Boolean = portraitEnabled && height > width
}

/** LandscapeActionDockLayout: the right rail's padding and width. */
object LandscapeActionDockLayout {
    val horizontalPadding = 6.dp
    val bottomPadding = 4.dp
    val controlSpacing = 4.dp
    const val primaryLineLimit = 1
    fun sidebarWidth(hasStack: Boolean) = if (hasStack) 176.dp else 160.dp
}

private val railBrush = Brush.verticalGradient(listOf(MagicPalette.iron.copy(alpha = 0.96f), MagicPalette.leather.copy(alpha = 0.90f)))

/**
 * The landscape board (NativeGameView's landscape branch): player summaries in a left rail,
 * the battlefield and hand in the middle, phases, stack and the action dock in a right rail.
 */
@Composable
fun LandscapeGameContent(
    snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState, selection: BoardSelection,
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
    openPromptDetailSheet: () -> Unit, openStack: () -> Unit,
) {
    val actions = snapshot.legalActions ?: emptyList()
    val humanName = snapshot.playerLabel(human.playerId)
    val opponentName = snapshot.playerLabel(opponent.playerId)
    val sideCombatHighlights = CombatHighlightSet(combatSelection, actions, snapshot.xmage?.combat ?: emptyList())
    val allBattlefield = snapshot.players.flatMap { it.zones.battlefield }
    val passAction = actions.firstOrNull { it.type == "pass_priority" } ?: actions.firstOrNull { it.type == "pass_until_response" }
    val yieldActions = GameplayActionPresentation.yieldActions(actions)
    HideStatusBarWhileShown()

    Row(Modifier.fillMaxSize()) {
        // LEFT COLUMN
        Column(Modifier.width(88.dp).fillMaxHeight().background(railBrush).padding(horizontal = 6.dp)) {
            val opponentTarget = CombatPlayerIdentity.targetID(opponent.playerId, snapshot, sideCombatHighlights.defenderIds)
            LandscapePlayerSummary(opponentName, opponent, snapshot.activePlayerId == opponent.playerId, human.playerId, opponentTarget != null,
                { opponentTarget?.let(submitAttackers) }, snapshot.thinkingPlayerID == opponent.playerId, Modifier.padding(top = 12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                PlayerZoneMenu(opponent, viewZone)
                BoardPlayerEffects(opponent, BattlefieldAttachments.enchanting(opponent.playerId, allBattlefield), viewZone,
                    BoardOpponentFocus.opponents(snapshot), selectOpponent)
            }
            Spacer(Modifier.weight(1f))
            Box(Modifier.padding(vertical = 8.dp).fillMaxWidth().height(1.dp).background(MagicPalette.antiqueGold.copy(alpha = 0.18f)))
            Column(Modifier.padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                ManaPoolHUD(human.manaPool, compact = true, grid = true, payableSymbols = GameplayAffordances.floatingManaSymbols(snapshot, pendingActionId),
                    payMana = { symbol ->
                        if (pendingActionId == null) GameplayAffordances.floatingManaCommand(symbol, snapshot)?.let { command ->
                            runCommand(command, "Spend floating {$symbol}", "floating-${snapshot.promptEnvelopeV2?.id ?: ""}-$symbol")
                        }
                    })
                LandscapePlayerSummary(humanName, human, snapshot.activePlayerId == human.playerId, opponent.playerId,
                    chatSnapshot = if (snapshot.isViewer(human.playerId)) snapshot else null)
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    PlayerZoneMenu(human, viewZone, snapshot, pendingActionId)
                    BoardPlayerEffects(human, BattlefieldAttachments.enchanting(human.playerId, allBattlefield), viewZone)
                }
            }
        }
        Box(Modifier.width(1.dp).fillMaxHeight().background(MagicPalette.antiqueGold.copy(alpha = 0.28f)))

        // CENTER COLUMN
        BoxWithConstraints(Modifier.weight(1f).fillMaxHeight()) {
            val metrics = BattlefieldLayoutMetrics(BoardSize(maxWidth.value, maxHeight.value),
                centerControlsVisible = BoardDecisionPresentation.needsCenterSpace(snapshot, false))
            val targetableIds = GameBoardInteractionState.boardTargetableIds(snapshot)
            val combatHighlights = CombatHighlightSet(combatSelection, actions, snapshot.xmage?.combat ?: emptyList())
            val shouldShowCompactPrompt = CompactPromptPopup.shouldShow(snapshot, pendingActionId)
            val interactionMode = GameBoardInteractionState.mode(snapshot, pendingActionId, selection.selectedCard)
            val playerIDs = snapshot.players.map { it.playerId }.toSet()
            fun lane(cards: List<ZoneCard>, resources: Boolean) = BattlefieldAttachments.lane(cards, allBattlefield, resources, playerIDs, includesManaRocks = true)
            val registry = LocalCardBounds.current
            val manaActive = snapshot.manaPayment?.active == true

            Box(Modifier.fillMaxSize()) {
                BattlefieldRow("Opponent board", lane(opponent.zones.battlefield, false), actions, targetableIds, combatHighlights.cardIds, selection,
                    metrics.permanentCardWidth, metrics.permanentCardHeight, metrics.opponentBattlefieldRect.width, runAction, submitTarget, handleCombatCardTap,
                    Modifier.place(metrics.opponentBattlefieldRect), flipped = true, adaptsToDensity = true, availableHeight = metrics.opponentBattlefieldRect.height)
                BattlefieldRow("Opponent lands", lane(opponent.zones.battlefield, true), actions, targetableIds, combatHighlights.cardIds, selection,
                    metrics.landCardWidth, metrics.landCardHeight, metrics.opponentLandsRect.width, runAction, submitTarget, handleCombatCardTap,
                    Modifier.place(metrics.opponentLandsRect), flipped = true, adaptsToDensity = true, availableHeight = metrics.opponentLandsRect.height,
                    arrangement = BattlefieldRowArrangement.LANDSCAPE_RESOURCES)
                Box(Modifier.centerAt(metrics.centerStripRect.midX, metrics.centerStripRect.midY)
                    .requiredWidth(maxOf(metrics.centerStripRect.width - 28, 80f).dp).height(1.5.dp).background(Color.White.copy(alpha = 0.13f)))
                BattlefieldRow("Your board", lane(human.zones.battlefield, false), actions, targetableIds, combatHighlights.cardIds, selection,
                    metrics.permanentCardWidth, metrics.permanentCardHeight, metrics.playerBattlefieldRect.width, runAction, submitTarget, handleCombatCardTap,
                    Modifier.place(metrics.playerBattlefieldRect), adaptsToDensity = true, availableHeight = metrics.playerBattlefieldRect.height,
                    allowsManaUndo = true, manaPaymentActive = manaActive)
                BattlefieldRow("Your lands", lane(human.zones.battlefield, true), actions, targetableIds, combatHighlights.cardIds, selection,
                    metrics.landCardWidth, metrics.landCardHeight, metrics.playerLandsRect.width, runAction, submitTarget, handleCombatCardTap,
                    Modifier.place(metrics.playerLandsRect), adaptsToDensity = true, availableHeight = metrics.playerLandsRect.height,
                    arrangement = BattlefieldRowArrangement.LANDSCAPE_RESOURCES, allowsManaUndo = true, manaPaymentActive = manaActive)

                val paymentActive = InlinePaymentPromptState.isActive(snapshot)
                val stripHeight = maxOf(if (paymentActive) 52f else metrics.centerStripRect.height, metrics.centerStripRect.height)
                Column(Modifier.place(metrics.centerStripRect.copy(y = metrics.centerStripRect.midY - stripHeight / 2, height = stripHeight)),
                    verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (paymentActive) InlinePaymentPromptBar(snapshot, pendingActionId, runAction, runCommand, openPromptDetails, Modifier.weight(1f))
                        else if (BoardDecisionPresentation.showsGuidance(snapshot)) PromptPill(snapshot, Modifier.weight(1f), combatSelection)
                        val revealed = snapshot.xmage?.revealed?.flatMap { it.cards } ?: emptyList()
                        val lookedAt = snapshot.xmage?.lookedAt?.flatMap { it.cards } ?: emptyList()
                        val inspect = LocalBoardZoneInspectionAction.current
                        if (revealed.isNotEmpty()) FloatingZoneChip("Revealed", revealed.size, "eye") { inspect?.invoke(BoardZoneReference.Collection(BoardZoneReference.NamedKind.REVEALED)) }
                        if (lookedAt.isNotEmpty()) FloatingZoneChip("Looked", lookedAt.size, "eye.trianglebadge.exclamationmark") {
                            inspect?.invoke(BoardZoneReference.Collection(BoardZoneReference.NamedKind.LOOKED_AT))
                        }
                    }
                }

                if (isOverPlayerDropZone) {
                    Box(Modifier.place(metrics.playerDropZone).background(MagicPalette.antiqueGold.copy(alpha = 0.14f), RoundedCornerShape(14.dp))
                        .border(2.dp, MagicPalette.antiqueGold.copy(alpha = 0.72f), RoundedCornerShape(14.dp)))
                }

                PortraitHandRow(BoardOpponentFocus.seatHand(snapshot), actions, selection, pendingCardInstanceId, setInteractionMode, metrics.playerDropZone, setOverPlayerDropZone,
                    metrics.handCardWidth, metrics.handCardHeight, metrics.handRect.width, onInteractionFeedback,
                    { choiceActions, message -> setDragActionChoice(DragActionChoice(message, choiceActions)) }, runAction,
                    Modifier.place(metrics.handRect).zIndex(4f), hiddenCount = if (snapshot.isViewer(human.playerId)) null else human.zones.visibleHandCount)

                if (TargetingHelperVisibility.shouldShow(snapshot, pendingActionId, interactionMode, targetableIds)) {
                    TargetingStatusPill(targetableIds.size, Modifier.centerAt(metrics.bottomActionRect.midX, metrics.bottomActionRect.midY))
                }

                if (CombatSelectionState.isDeclareAttackers(snapshot)) {
                    val declared = snapshot.xmage?.combat?.flatMap { it.attackers }?.size ?: 0
                    val hasPending = combatSelection.selectedAttackerIds.isNotEmpty()
                    CombatSubmitPill(if (hasPending) "Cancel Selection" else if (declared == 0) "No Attacks" else "Done Attacking",
                        maxOf(declared, combatSelection.selectedAttackerIds.size), {
                            if (hasPending) setCombatSelection(combatSelection.clearAttackers()) else finishAttackers()
                        }, Modifier.centerAt(metrics.bottomActionRect.midX, metrics.centerStripRect.maxY + 18).zIndex(19f))
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
                        }, Modifier.centerAt(metrics.bottomActionRect.midX, metrics.centerStripRect.maxY + 18).zIndex(19f))
                }

                // Combat arrows and board effects, drawn over the lanes in board coordinates.
                val bounds = registry?.bounds ?: emptyMap()
                if (inspectingZoneTitle == null && selection.inspectedCard == null) {
                    CombatArrowOverlay(snapshot, snapshot.xmage?.combat ?: emptyList(), combatPreviewArrows, metrics, human.zones.battlefield,
                        opponent.zones.battlefield, bounds, Modifier.zIndex(6f))
                    Box(Modifier.fillMaxSize().zIndex(7f)) {
                        CombatEdgeIndicators(human.zones.battlefield + opponent.zones.battlefield,
                            CombatArrowModel.arrows(snapshot.xmage?.combat ?: emptyList(), combatPreviewArrows).flatMap { listOf(it.fromId, it.toId) }.toSet(),
                            bounds, listOf(metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect),
                            CombatViewportAnchors.laneIndices(human.zones.battlefield, opponent.zones.battlefield)) { selection.inspectedCard = it }
                    }
                }
                BoardFXOverlay(boardFX.active, boardFX.subjects, bounds, BoardFXAnchors(snapshot.viewerID,
                    viewerPoint = BoardPoint(metrics.playerLandsRect.minX + 34, metrics.playerLandsRect.maxY),
                    opponentPoint = BoardPoint(metrics.opponentBattlefieldRect.minX + 44, metrics.opponentBattlefieldRect.minY + 26),
                    stackPoint = BoardPoint(metrics.centerStripRect.midX, metrics.centerStripRect.midY),
                    viewerHandPoint = BoardPoint(metrics.handRect.midX, metrics.handRect.midY),
                    opponentHandPoint = BoardPoint(metrics.opponentBattlefieldRect.midX, metrics.opponentBattlefieldRect.minY - 40)),
                    boardFXClock, pruneFX, Modifier.zIndex(8f))

                BoardOverlayTransition(inspectingZoneTitle != null, Modifier.place(metrics.safeFrame).zIndex(70f)) {
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

                BoardOverlayTransition(shouldShowCompactPrompt && !isPromptDetailOpen && CompactPromptPopup.compactLegalPromptActions(snapshot).isEmpty(),
                    Modifier.requiredSize(minOf(maxOf(metrics.size.width * 0.30f, 260f), 340f).dp, minOf(maxOf(metrics.size.height * 0.20f, 98f), 178f).dp)
                        .centerAt(metrics.boardColumnRect.midX, metrics.compactPromptRect.midY).zIndex(20f)) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CompactPromptPopupView(snapshot, pendingActionId, runAction, runCommand, openPromptDetailSheet, Modifier.fillMaxWidth())
                    }
                }

                dragActionChoice?.let { choice ->
                    DragActionChoicePopup(choice, pendingActionId, { action -> setDragActionChoice(null); selection.selectedCard = null; runAction(action) },
                        { setDragActionChoice(null); selection.selectedCard = null },
                        Modifier.requiredWidth(minOf(maxOf(metrics.size.width * 0.30f, 260f), 340f).dp)
                            .centerAt(metrics.boardColumnRect.midX, metrics.compactPromptRect.midY).zIndex(21f))
                }
            }
        }
        Box(Modifier.width(1.dp).fillMaxHeight().background(MagicPalette.antiqueGold.copy(alpha = 0.28f)))

        // RIGHT COLUMN
        Box(Modifier.width(LandscapeActionDockLayout.sidebarWidth(snapshot.stackTopFirst.isNotEmpty())).fillMaxHeight().background(railBrush)) {
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    PhaseRail(snapshot, Modifier.padding(top = 12.dp))
                    if (pendingActionId == null) BoardResponseCue.make(snapshot)?.let { BoardResponseBanner(it, Modifier.padding(horizontal = 8.dp)) }
                    Box(Modifier.padding(horizontal = 8.dp).fillMaxWidth().height(1.dp).background(MagicPalette.antiqueGold.copy(alpha = 0.18f)))
                    GameLogAccessButton(snapshot.log.size, openLog, Modifier.padding(horizontal = 8.dp))
                    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable(onClick = openStack).semantics { contentDescription = "Inspect stack" },
                        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                        SfImage("square.stack.3d.up", rgb(0.04, 0.52, 1.0), 14.dp)
                        Text("Stack · ${snapshot.stackTopFirst.size}", color = rgb(0.04, 0.52, 1.0), style = sf(13f, SfWeight.semibold))
                    }
                    val xmageStack = snapshot.xmage?.stack
                    if (!xmageStack.isNullOrEmpty()) {
                        XmageStackPeek(if (snapshot.source == "xmage-ondevice") xmageStack.reversed() else xmageStack, actions,
                            snapshot.promptEnvelopeV2?.message ?: snapshot.promptText, selection, Modifier.padding(horizontal = 10.dp))
                    } else if (human.zones.stack.isNotEmpty()) StackPeek(human.zones.stack, selection, Modifier.padding(horizontal = 10.dp))
                }
                Box(Modifier.padding(horizontal = 8.dp).fillMaxWidth().height(1.dp).background(MagicPalette.antiqueGold.copy(alpha = 0.18f)))
                GameplayActionDock(snapshot, passAction, yieldActions, pendingActionId, openPromptDetails, openLog, openSettings, runAction,
                    Modifier.padding(horizontal = LandscapeActionDockLayout.horizontalPadding).padding(bottom = LandscapeActionDockLayout.bottomPadding),
                    compact = true, landscapeSidebar = true)
            }
            if (snapshot.isWaitingOnAIOrStalled) {
                AIWaitFallbackControls(snapshot, pendingActionId, liveUpdateStatus, aiWaitBeganAt, didRefresh, didReconnect, didDiagnose, refreshGame, reconnectGame,
                    Modifier.align(Alignment.Center).padding(horizontal = 10.dp))
            }
        }
    }
}

private fun rgb(red: Double, green: Double, blue: Double) = io.magicmobile.android.ui.rgb(red, green, blue)

/** boardOverlayTransition: scale and fade in, or only fade with Reduce Motion. */
@Composable
private fun BoardOverlayTransition(visible: Boolean, modifier: Modifier, content: @Composable () -> Unit) {
    AnimatedVisibility(visible, modifier, enter = if (BoardMotion.reduceMotion) fadeIn() else scaleIn() + fadeIn(),
        exit = if (BoardMotion.reduceMotion) fadeOut() else scaleOut() + fadeOut()) { content() }
}

/** Fits the narrow landscape rail without intruding into the battlefield. */
@Composable
private fun LandscapePlayerSummary(name: String, player: PlayerGameState, active: Boolean, opponentId: String?, combatTargetable: Boolean = false,
                                   combatTargetAction: (() -> Unit)? = null, thinking: Boolean = false, modifier: Modifier = Modifier,
                                   chatSnapshot: GameSnapshot? = null) {
    val summary = CommanderHudSummary.of(player, opponentId)
    val emoteCenter = LocalEmoteCenter.current
    var chatOpen by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(9.dp)
    Box(modifier) {
        Column(Modifier.fillMaxWidth().background(MagicPalette.iron.copy(alpha = 0.64f), shape)
            .border(if (combatTargetable) 2.dp else 1.dp, if (combatTargetable) MagicPalette.oxblood else MagicPalette.antiqueGold.copy(alpha = if (active) 0.8f else 0.3f), shape)
            .clickable(remember { MutableInteractionSource() }, null) {
                if (combatTargetable) combatTargetAction?.invoke() else if (chatSnapshot != null && emoteCenter != null) chatOpen = true
            }
            .padding(6.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(name, color = MagicPalette.parchment, style = sf(11f, SfWeight.bold), maxLines = 1)
            // The portrait stands in for the heart; the column is narrow.
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                PlayerPortrait(player, 24.dp, active, thinking)
                BoardLifeTotal(summary.life, sf(22f, SfWeight.bold, SfDesign.ROUNDED), Modifier.semantics { contentDescription = "${summary.life} life" })
            }
            Text("Hand ${summary.handCount} · Lib ${summary.libraryCount}", color = MagicPalette.parchment, style = sf(9f, SfWeight.semibold), maxLines = 1)
            Text("Tax ${summary.commanderTaxLabel} · Dmg ${summary.commanderDamageLabel}", color = MagicPalette.parchment, style = sf(9f, SfWeight.semibold), maxLines = 1)
        }
        if (emoteCenter != null) EmoteBubbleSlot(emoteCenter, player.playerId, modifier = Modifier.align(Alignment.TopEnd).offset(x = 12.dp, y = (-18).dp))
        if (chatOpen && emoteCenter != null && chatSnapshot != null) {
            Popup(alignment = Alignment.BottomStart, offset = IntOffset(0, -170), onDismissRequest = { chatOpen = false }, properties = PopupProperties(focusable = true)) {
                EmotePicker(emoteCenter, chatSnapshot) { chatOpen = false }
            }
        }
    }
}

/** MagicPathPhaseRail(onlyPhases: true): the step and who holds priority. */
@Composable
private fun PhaseRail(snapshot: GameSnapshot, modifier: Modifier = Modifier) {
    Row(modifier.padding(horizontal = 8.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        PhaseChip("Phase", PhaseTitles.arenaPhaseTitle(snapshot.step ?: snapshot.phase), true, Modifier.weight(1f))
        PhaseChip("Priority", snapshot.playerLabel(snapshot.priorityPlayerId), snapshot.isViewer(snapshot.priorityPlayerId), Modifier.weight(1f))
    }
}

@Composable
private fun PhaseChip(label: String, phase: String, active: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(7.dp)
    Column(modifier.background(if (active) MagicPalette.antiqueGold else MagicPalette.iron.copy(alpha = 0.5f), shape)
        .border(1.dp, if (active) MagicPalette.brass.copy(alpha = 0.55f) else MagicPalette.borderBronze.copy(alpha = 0.2f), shape)
        .padding(horizontal = 4.dp, vertical = 3.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(label.uppercase(), color = if (active) Color.Black.copy(alpha = 0.7f) else Color.White.copy(alpha = 0.55f), style = sf(6f, SfWeight.black))
        FitText(PhaseTitles.compactPhaseTitle(phase), sf(9f, SfWeight.black), color = if (active) Color.Black else Color.White, minimumScale = 0.65f)
    }
}

@Composable
private fun GameLogAccessButton(entryCount: Int, openLog: () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).background(Color.Black.copy(alpha = 0.3f), CircleShape)
        .border(1.dp, MagicPalette.borderBronze.copy(alpha = 0.28f), CircleShape).clickable(onClick = openLog)
        .semantics { contentDescription = "Open game log, $entryCount actions" }.padding(horizontal = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        SfImage("list.bullet.rectangle", MagicPalette.antiqueGold, 16.dp)
        Text("$entryCount", color = MagicPalette.parchment.copy(alpha = 0.58f), style = sf(11f, SfWeight.semibold), maxLines = 1)
    }
}

/** StackPeek: the zone stack as overlapping tiles and the top card's name. */
@Composable
private fun StackPeek(cards: List<ZoneCard>, selection: BoardSelection, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.56f), RoundedCornerShape(8.dp))
        .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.24f), RoundedCornerShape(8.dp)).padding(8.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text("STACK", color = MagicPalette.antiqueGold, style = sf(10f, SfWeight.black))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box {
                cards.takeLast(4).forEachIndexed { index, card ->
                    CardTile(card, selection.selectedCard?.id == card.id, Modifier.offset(x = (index * 24).dp).zIndex(index.toFloat())
                        .onCardInteraction({ selection.selectedCard = card; selection.inspectedCard = null }, { selection.inspectedCard = card },
                            { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null }), zoneName = "Stack", width = 38.dp, height = 54.dp)
                }
                Spacer(Modifier.width((38 + 24 * (minOf(4, cards.size) - 1)).dp))
            }
            FitText(cards.lastOrNull()?.card?.name ?: "Resolving", sf(11f, SfWeight.black), color = Color.White, maxLines = 2, minimumScale = 0.65f)
        }
    }
}

/** XmageStackPeek: the top stack object large, whether you can respond, and its text. */
@Composable
private fun XmageStackPeek(objects: List<XmageStackObject>, legalActions: List<LegalAction>, promptText: String?, selection: BoardSelection, modifier: Modifier = Modifier) {
    val top = objects.lastOrNull()
    val card = top?.displaySourceCard
    val passAvailable = legalActions.any { it.type in setOf("pass_priority", "pass_until_response", "advance_phase") }
    Column(modifier.fillMaxWidth().background(MagicPalette.iron.copy(alpha = 0.72f), RoundedCornerShape(8.dp))
        .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.3f), RoundedCornerShape(8.dp)).padding(8.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("STACK", color = MagicPalette.antiqueGold, style = sf(10f, SfWeight.black))
            Text("${objects.size}", color = Color.White.copy(alpha = 0.68f), style = sf(8f, SfWeight.black))
            Spacer(Modifier.weight(1f))
            Text(if (passAvailable) "RESPOND" else "WAIT", color = if (passAvailable) MagicPalette.legalEmerald else Color.White.copy(alpha = 0.55f), style = sf(7f, SfWeight.black))
        }
        if (card != null) {
            CardTile(card, selection.selectedCard?.id == card.id, Modifier.onCardInteraction({ selection.selectedCard = null; selection.inspectedCard = card },
                { selection.inspectedCard = card }, { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null }),
                zoneName = "Stack", width = 128.dp, height = 179.dp, ignoreTappedRotation = true)
        } else SyntheticStackObjectTile(top, 128.dp, 179.dp)
        if (top != null) {
            Text(top.displayName, color = MagicPalette.parchment, style = sf(12f, SfWeight.bold))
            top.rulesText?.takeIf { it.isNotEmpty() }?.let { GameRulesText(it, cardName = top.displayName, style = sf(12f), color = MagicPalette.parchment.copy(alpha = 0.9f)) }
        }
    }
}

/** iPhone hides the status bar in landscape; the board gets that height here too. A swipe still shows it. */
@Composable
private fun HideStatusBarWhileShown() {
    val view = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.DisposableEffect(view) {
        val window = (view.context as? android.app.Activity)?.window
        val controller = window?.let { androidx.core.view.WindowCompat.getInsetsController(it, view) }
        controller?.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller?.hide(androidx.core.view.WindowInsetsCompat.Type.statusBars())
        onDispose { controller?.show(androidx.core.view.WindowInsetsCompat.Type.statusBars()) }
    }
}
