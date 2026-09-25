package io.magicmobile.android.board

import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import io.magicmobile.android.game.AIWaitRecoveryAction
import io.magicmobile.android.game.AIWaitRecoveryPolicy
import io.magicmobile.android.game.BattlefieldAttachments
import io.magicmobile.android.game.BoardDecisionPresentation
import io.magicmobile.android.game.BoardFXDirector
import io.magicmobile.android.game.BoardFXEntrance
import io.magicmobile.android.game.BoardFXEvent
import io.magicmobile.android.game.BoardFXLevel
import io.magicmobile.android.game.BoardFXRevisionKey
import io.magicmobile.android.game.BoardOpponentFocus
import io.magicmobile.android.game.BoardPhaseAnnouncement
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.game.BoardSize
import io.magicmobile.android.game.BoardZoneReference
import io.magicmobile.android.game.CardChoiceCommandFailure
import io.magicmobile.android.game.CardChoicePlan
import io.magicmobile.android.game.CombatArrow
import io.magicmobile.android.game.CombatArrowKind
import io.magicmobile.android.game.CombatArrowModel
import io.magicmobile.android.game.CombatHighlightSet
import io.magicmobile.android.game.CombatPlayerIdentity
import io.magicmobile.android.game.CombatSelectionState
import io.magicmobile.android.game.CombatViewportAnchors
import io.magicmobile.android.game.CompactPromptPopup
import io.magicmobile.android.game.EngineHealth
import io.magicmobile.android.game.GameBoardInteractionMode
import io.magicmobile.android.game.GameBoardInteractionState
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameStats
import io.magicmobile.android.game.GameplayActionPresentation
import io.magicmobile.android.game.InlinePaymentPromptState
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.OpeningHandChoice
import io.magicmobile.android.game.PlayerGameState
import io.magicmobile.android.game.PortraitBattlefieldLayoutMetrics
import io.magicmobile.android.game.PortraitInteractionPolicy
import io.magicmobile.android.game.ScheduledBoardFX
import io.magicmobile.android.game.TargetingHelperVisibility
import io.magicmobile.android.game.UniversalPromptResponseCommandBuilder
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.game.combatSelectionResetKey
import io.magicmobile.android.game.visibleBattlefield
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** SwiftUI `.onChange(of:)`: runs `action` when `value` changes, never on first composition. */
@Composable
fun <T> OnChange(value: T, action: (old: T, new: T) -> Unit) {
    val previous = remember { arrayOfNulls<Any?>(1).also { it[0] = value } }
    val currentAction by rememberUpdatedState(action)
    LaunchedEffect(value) {
        @Suppress("UNCHECKED_CAST") val old = previous[0] as T
        if (old != value) { previous[0] = value; currentAction(old, value) }
    }
}

/** Places a child with its top-left at `rect` (dp), sized to it: SwiftUI `.frame(...).position(...)`. */
fun Modifier.place(rect: BoardRect): Modifier = this.offset { IntOffset((rect.x * density).roundToInt(), (rect.y * density).roundToInt()) }
    .requiredSize(rect.width.dp, rect.height.dp)

/** Centers a child on a point (dp) without constraining its size. */
fun Modifier.centerAt(x: Float, y: Float): Modifier = this.layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
    layout(placeable.width, placeable.height) {
        placeable.place(((x * density) - placeable.width / 2f).roundToInt(), ((y * density) - placeable.height / 2f).roundToInt())
    }
}


/**
 * ContentView.swift NativeGameView: the whole on-device board. It owns only presentation
 * state; every game decision is the engine's, delivered as authorized commands.
 */
@Composable
fun NativeGameView(
    snapshot: GameSnapshot?, selection: BoardSelection, pendingActionId: String?, pendingCardInstanceId: String?,
    commandFailure: CardChoiceCommandFailure?, liveUpdateStatus: String, onInteractionFeedback: (String) -> Unit,
    runAction: (LegalAction) -> Unit, runCommand: (GameCommand, String, String) -> Unit, refreshGame: () -> Unit, reconnectGame: () -> Unit,
    checkBridgeHealth: suspend () -> EngineHealth?, newGame: () -> Unit, quitGame: () -> Unit, portraitModeEnabled: Boolean,
    setPortraitModeEnabled: (Boolean) -> Unit, loadingMessage: String? = null, loadingError: String? = null,
) {
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    var isLogOpen by remember { mutableStateOf(false) }
    var isGameMenuOpen by remember { mutableStateOf(false) }
    var isPromptInspectorOpen by remember { mutableStateOf(false) }
    var gameMenuConfirmation by remember { mutableStateOf<GameMenuConfirmation?>(null) }
    var isOverPlayerDropZone by remember { mutableStateOf(false) }
    var interactionMode by remember { mutableStateOf<GameBoardInteractionMode>(GameBoardInteractionMode.Idle) }
    var inspectingZoneTitle by remember { mutableStateOf<String?>(null) }
    var inspectingZoneCards by remember { mutableStateOf(listOf<ZoneCard>()) }
    var inspectingZoneReference by remember { mutableStateOf<BoardZoneReference?>(null) }
    var isPromptDetailOpen by remember { mutableStateOf(false) }
    var isCardChoiceOpen by remember { mutableStateOf(false) }
    var committedCardChoice by remember { mutableStateOf<CardChoicePlan?>(null) }
    var cardChoiceCompletionJob by remember { mutableStateOf<Job?>(null) }
    var reviewCardChoiceAfterPending by remember { mutableStateOf(false) }
    var isStackSheetOpen by remember { mutableStateOf(false) }
    var dragActionChoice by remember { mutableStateOf<DragActionChoice?>(null) }
    var combatSelection by remember { mutableStateOf(CombatSelectionState()) }
    var combatPreviewArrows by remember { mutableStateOf(listOf<CombatArrow>()) }
    var focusedOpponentId by remember { mutableStateOf<String?>(null) }
    var lastTurnCueKey by remember { mutableStateOf<String?>(null) }
    var showsTurnCue by remember { mutableStateOf(false) }
    var lastTurnBannerKey by remember { mutableStateOf<String?>(null) }
    var lastTurnSoundKey by remember { mutableStateOf<String?>(null) }
    var showsTurnBanner by remember { mutableStateOf(false) }
    var phaseCueMerging by remember { mutableStateOf(false) }
    var hudPulse by remember { mutableIntStateOf(0) }
    var aiWaitBeganAt by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var aiWaitKey by remember { mutableStateOf("") }
    var didAutoRefreshAIWaitKey by remember { mutableStateOf<String?>(null) }
    var didAutoReconnectAIWaitKey by remember { mutableStateOf<String?>(null) }
    var didAutoDiagnoseAIWaitKey by remember { mutableStateOf<String?>(null) }
    val boardFX = remember { BoardFXDirector() }
    val boardFXClock = remember { BoardFXClock() }
    var fxVersion by remember { mutableIntStateOf(0) }
    val boardShake = remember { Animatable(0f) }
    var boardShakeAmplitude by remember { mutableFloatStateOf(6f) }
    val hitVignette = remember { Animatable(0f) }
    val gameStats = remember { GameStats() }
    val boardFXLevel by AppPreferences.string(BoardFXLevel.key, BoardFXLevel.defaultValue)
    val boardSoundsEnabled by AppPreferences.boolean(GameAudio.effectsKey, true)
    val cardBounds = remember { CardBoundsRegistry() }
    val holdInspection = remember { HoldCardInspection() }
    val density = LocalDensity.current.density
    cardBounds.density = density

    if (snapshot == null) { LoadingGameView(if (loadingError != null) "failed" else null, loadingMessage, loadingError); return }
    val board = BoardOpponentFocus.snapshot(snapshot, focusedOpponentId)
    val human = board.human
    val opponent = board.opponent
    if (human == null || opponent == null) { LoadingGameView(null, loadingMessage, loadingError); return }
    val currentSnapshot by rememberUpdatedState(board)
    val currentPending by rememberUpdatedState(pendingActionId)

    fun openPromptDetails() {
        if (PortraitInteractionPolicy.cardChoiceKey(currentSnapshot) != null) isCardChoiceOpen = true else isPromptDetailOpen = true
    }

    fun advanceCommittedCardChoice() {
        val plan = committedCardChoice ?: return
        val snap = currentSnapshot
        if (snap.promptEnvelopeV2 == null && currentPending == null && plan.lastPrompt != null) {
            if (cardChoiceCompletionJob == null) {
                val lastPrompt = plan.lastPrompt
                cardChoiceCompletionJob = scope.launch {
                    delay(5000)
                    if (committedCardChoice?.lastPrompt == lastPrompt && currentSnapshot.promptEnvelopeV2 == null && currentPending == null) committedCardChoice = null
                    cardChoiceCompletionJob = null
                }
            }
            return
        }
        cardChoiceCompletionJob?.cancel(); cardChoiceCompletionJob = null
        val command = plan.next(snap, currentPending != null)
        committedCardChoice = if (plan.stopped) null else plan
        if (plan.stopped) {
            isCardChoiceOpen = PortraitInteractionPolicy.cardChoiceKey(snap) != null
            isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(snap) != null
        }
        if (command != null) runCommand(command, "Apply card choice", "card-plan-${command.promptId ?: ""}-${command.messageId ?: 0}")
    }

    fun cancelCommittedCardChoice() {
        cardChoiceCompletionJob?.cancel(); cardChoiceCompletionJob = null
        committedCardChoice = null
        val snap = currentSnapshot
        if (currentPending != null) {
            reviewCardChoiceAfterPending = true; isCardChoiceOpen = false; isPromptDetailOpen = false
        } else {
            isCardChoiceOpen = PortraitInteractionPolicy.cardChoiceKey(snap) != null
            isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(snap) != null
        }
    }

    fun commitCardChoicePlan(plan: CardChoicePlan) {
        cardChoiceCompletionJob?.cancel(); cardChoiceCompletionJob = null
        reviewCardChoiceAfterPending = false
        committedCardChoice = plan
        isCardChoiceOpen = false
        advanceCommittedCardChoice()
    }

    fun inspectBoardZone(reference: BoardZoneReference) {
        inspectingZoneReference = reference
        inspectingZoneTitle = reference.title(currentSnapshot)
        inspectingZoneCards = reference.cards(currentSnapshot)
        selection.inspectedCard = null
    }

    fun localViewZone(title: String, cards: List<ZoneCard>) {
        val snap = currentSnapshot
        if (title.startsWith("Enchanting ") && cards.isNotEmpty()) {
            val player = snap.players.firstOrNull { p ->
                ZoneCard.enchanting(p.playerId, snap.players.flatMap { it.zones.battlefield }).map { it.id }.toSet() == cards.map { it.id }.toSet()
            }
            if (player != null) { inspectBoardZone(BoardZoneReference.PlayerEnchantments(player.playerId)); return }
        }
        inspectingZoneReference = null
        inspectingZoneTitle = title
        inspectingZoneCards = cards
    }

    fun clearBoardSelection() {
        if (selection.selectedCard == null && selection.inspectedCard == null) return
        selection.selectedCard = null; selection.inspectedCard = null
        GameHaptics.selection(view)
        onInteractionFeedback("Selection cleared")
    }

    fun submitTarget(card: ZoneCard) {
        val snap = currentSnapshot
        val targetable = GameBoardInteractionState.boardTargetableIds(snap)
        if (card.instanceId !in targetable && card.id !in targetable) {
            GameHaptics.warning(view); onInteractionFeedback("${card.card.name} is not an exposed XMage target"); return
        }
        val prompt = snap.promptEnvelopeV2 ?: run { GameHaptics.warning(view); onInteractionFeedback("XMage target prompt is no longer active"); return }
        if ((prompt.maxChoices ?: 1) > 1 || (prompt.minChoices ?: 1) > 1) { selection.selectedCard = card; isPromptDetailOpen = true; return }
        val promptId = prompt.responseCommand?.promptId ?: prompt.id
        val command = UniversalPromptResponseCommandBuilder.command(snap.id, snap.bridgeRevision, prompt, "choose_target", promptId, prompt.playerId, listOf(card.instanceId))
            ?: run { GameHaptics.warning(view); onInteractionFeedback("XMage did not expose a mobile-safe target command"); return }
        GameHaptics.success(view)
        runCommand(command, "Target ${card.card.name}", "$promptId-${card.instanceId}")
    }

    fun submitAttackers(defenderId: String) {
        val snap = currentSnapshot
        val actions = snap.legalActions ?: emptyList()
        if (combatSelection.selectedAttackerIds.isEmpty()) { onInteractionFeedback("Select at least one attacker first"); return }
        if (defenderId !in combatSelection.defenderHighlightIds(actions)) { onInteractionFeedback("XMage did not expose that defender"); return }
        val you = snap.human ?: return
        val command = combatSelection.attackCommand(snap.id, you.playerId, defenderId, actions, snap.bridgeRevision)
            ?: run { onInteractionFeedback("XMage did not expose mobile-safe attacker data"); return }
        val removesExistingAttack = command.attackers?.all { pair ->
            val defender = pair.defenderId ?: return@all false
            (snap.xmage?.combat ?: emptyList()).any { group -> group.defenderId == defender && group.attackers.any { it.instanceId == pair.attackerId || it.id == pair.attackerId } }
        } == true
        combatPreviewArrows = if (removesExistingAttack) emptyList() else command.attackers?.mapNotNull { pair ->
            val defender = pair.defenderId ?: return@mapNotNull null
            CombatArrow(CombatArrowKind.PREVIEW_ATTACK, pair.attackerId, defender, combatSelection.defenderKind(defender, actions))
        } ?: emptyList()
        runCommand(command, if (removesExistingAttack) "Remove attacker" else "Declare attacker", "declare-attacker-${snap.bridgeRevision ?: snap.turn}-$defenderId")
        combatSelection = combatSelection.clearAttackers()
    }

    fun submitBlockers() {
        val snap = currentSnapshot
        val you = snap.human ?: return
        val command = combatSelection.pendingBlockActionPayload(you.playerId, snap.id, snap.bridgeRevision)
            ?: run { onInteractionFeedback("Select a blocker and the attacker it blocks"); return }
        combatPreviewArrows = command.blockers?.mapNotNull { pair -> pair.attackerId?.let { CombatArrow(CombatArrowKind.PREVIEW_BLOCK, pair.blockerId, it, null) } } ?: emptyList()
        runCommand(command, "Declare blocker", "declare-blocker-${snap.bridgeRevision ?: snap.turn}")
        combatSelection = combatSelection.clearBlockers()
    }

    fun finishAttackers() {
        val snap = currentSnapshot
        val you = snap.human ?: return
        runCommand(CombatSelectionState.finishAttackCommand(snap.id, you.playerId, snap.bridgeRevision), "Finish attackers",
            "declare-attackers-finish-${snap.bridgeRevision ?: snap.turn}")
        combatSelection = combatSelection.clearAttackers()
    }

    fun finishBlockers() {
        val snap = currentSnapshot
        val you = snap.human ?: return
        runCommand(CombatSelectionState.finishBlockCommand(snap.id, you.playerId, snap.bridgeRevision), "Finish blockers",
            "declare-blockers-finish-${snap.bridgeRevision ?: snap.turn}")
        combatSelection = combatSelection.clearBlockers()
    }

    fun handleCombatCardTap(card: ZoneCard): Boolean {
        val snap = currentSnapshot
        val actions = snap.legalActions ?: emptyList()
        if (CombatSelectionState.isDeclareAttackers(snap)) {
            CombatSelectionState.matchingCardId(card, combatSelection.attackerHighlightIds(actions))?.let { attackerId ->
                val defenders = combatSelection.defenderIds(attackerId, actions)
                combatSelection = combatSelection.selectAttacker(attackerId)
                if (defenders.size == 1) { submitAttackers(defenders.first()); onInteractionFeedback("Combat selection sent") }
                else onInteractionFeedback("Choose who to attack")
                return true
            }
            CombatSelectionState.matchingCardId(card, combatSelection.defenderHighlightIds(actions))?.let { defenderId ->
                if (combatSelection.selectedAttackerId == null) { onInteractionFeedback("Select an attacker first"); return true }
                submitAttackers(defenderId); return true
            }
        }
        if (CombatSelectionState.isDeclareBlockers(snap)) {
            val groups = snap.xmage?.combat ?: emptyList()
            CombatSelectionState.matchingCardId(card, combatSelection.blockerHighlightIds(actions))?.let { blockerId ->
                val attackers = combatSelection.attackingCreatureIds(blockerId, actions, groups)
                combatSelection = combatSelection.selectBlocker(blockerId)
                if (attackers.size == 1) {
                    combatSelection = combatSelection.pairSelectedBlocker(attackers.first())
                    submitBlockers(); onInteractionFeedback("Block selection sent")
                } else onInteractionFeedback("Choose attacker to block")
                return true
            }
            CombatSelectionState.matchingCardId(card, combatSelection.attackingCreatureHighlightIds(actions, groups))?.let { attackerId ->
                if (combatSelection.selectedBlockerId == null) { onInteractionFeedback("Select a blocker first"); return true }
                combatSelection = combatSelection.pairSelectedBlocker(attackerId)
                submitBlockers(); onInteractionFeedback("Block selection sent")
                return true
            }
        }
        return false
    }

    fun ingestBoardFX(snap: GameSnapshot) {
        val level = BoardFXLevel.resolved(boardFXLevel, BoardMotion.reduceMotion)
        val scheduled = boardFX.ingest(snap, level, System.currentTimeMillis())
        fxVersion += 1
        if (scheduled.isEmpty()) return
        playBoardFXHaptics(scope, view, scheduled, snap.viewerID)
        if (boardSoundsEnabled) {
            val arrived = scheduled.mapNotNull { (it.event as? BoardFXEvent.EnteredBattlefield)?.cardID }.toSet()
            val arrivals = snap.players.flatMap { it.zones.battlefield }.filter { it.instanceId in arrived }
                .associate { it.instanceId to BoardFXSound.Arrival(it.card.typeLine.contains("land", ignoreCase = true), it.card.isToken == true) }
            BoardFXSound.play(scheduled, snap.viewerID, arrivals)
        }
        if (level != BoardFXLevel.FULL) return
        // Shake when the hit lands, scaled to it: the viewer losing life, a big hit on an
        // opponent, or a commander touching down. Five or more to you also flares red.
        val shakes = mutableListOf<Triple<Double, Float, Boolean>>()
        for (fx in scheduled) when (val event = fx.event) {
            is BoardFXEvent.LifeChanged -> if (event.delta < 0) {
                if (event.playerID == snap.viewerID) shakes += Triple(fx.delay, if (event.delta <= -5) 12f else 6f, event.delta <= -5)
                else if (event.delta <= -5) shakes += Triple(fx.delay, 5f, false)
            }
            is BoardFXEvent.EnteredBattlefield -> if (event.entrance == BoardFXEntrance.COMMANDER) shakes += Triple(fx.landing, 6f, false)
            else -> {}
        }
        for ((at, amplitude, flare) in shakes.take(3)) scope.launch {
            delay((at * 1000).toLong())
            boardShakeAmplitude = amplitude
            launch { boardShake.animateTo(floor(boardShake.value) + 1, tween(if (amplitude > 8) 500 else 360, easing = LinearEasing)) }
            if (flare) {
                view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                hitVignette.animateTo(1f, tween(120))
                delay(150)
                hitVignette.animateTo(0f, tween(700))
            }
        }
    }

    fun updateAIWaitStart(snap: GameSnapshot) {
        val key = snap.aiWaitSignature
        if (key != aiWaitKey) {
            aiWaitKey = key; aiWaitBeganAt = System.currentTimeMillis()
            didAutoRefreshAIWaitKey = null; didAutoReconnectAIWaitKey = null; didAutoDiagnoseAIWaitKey = null
        }
    }

    // --- Observation (boardObservation) ---
    LaunchedEffect(BoardFXRevisionKey(board)) { ingestBoardFX(board); gameStats.record(board) }
    LaunchedEffect(Unit) {
        updateAIWaitStart(board)
        isCardChoiceOpen = PortraitInteractionPolicy.cardChoiceKey(board) != null
        isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(board) != null
        interactionMode = GameBoardInteractionState.mode(board, pendingActionId, selection.selectedCard)
        if (board.id == "design-preview-zone-inspection") inspectBoardZone(BoardZoneReference.Player(board.viewerID, BoardZoneReference.PlayerZone.GRAVEYARD))
    }
    OnChange(board.id) { _, _ ->
        cardChoiceCompletionJob?.cancel(); cardChoiceCompletionJob = null
        committedCardChoice = null; reviewCardChoiceAfterPending = false; focusedOpponentId = null
        lastTurnCueKey = null; lastTurnBannerKey = null
        inspectingZoneTitle = null; inspectingZoneCards = emptyList(); inspectingZoneReference = null
        selection.selectedCard = null; selection.inspectedCard = null
    }
    OnChange(board.bridgeRevision) { _, _ ->
        advanceCommittedCardChoice()
        val cards = PortraitInteractionPolicy.authorizedCards(board)
        selection.inspectedCard?.let { card -> selection.inspectedCard = cards.firstOrNull { it.id == card.id } }
        selection.selectedCard?.let { card -> selection.selectedCard = cards.firstOrNull { it.id == card.id } }
        val reference = inspectingZoneReference
        if (reference != null && inspectingZoneTitle != null) { inspectingZoneCards = reference.cards(board); inspectingZoneTitle = reference.title(board) }
        else if (inspectingZoneTitle != null) { inspectingZoneCards = emptyList(); inspectingZoneTitle = null }
        dragActionChoice?.let { choice ->
            if (!choice.actions.all { old -> board.legalActions?.any { it.id == old.id && it.messageId == old.messageId } == true }) dragActionChoice = null
        }
    }
    OnChange(board.promptEnvelopeV2?.id) { _, _ ->
        advanceCommittedCardChoice()
        isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(board) != null
    }
    OnChange(board.promptEnvelopeV2?.messageId) { _, _ -> advanceCommittedCardChoice() }
    OnChange(pendingActionId) { old, new ->
        if (new == null) {
            combatPreviewArrows = emptyList()
            if (reviewCardChoiceAfterPending) {
                reviewCardChoiceAfterPending = false
                isCardChoiceOpen = PortraitInteractionPolicy.cardChoiceKey(board) != null
                isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(board) != null
            } else if (old != null && committedCardChoice?.submittedPromptIsUnchanged(board) == true) cancelCommittedCardChoice()
            else advanceCommittedCardChoice()
        }
    }
    OnChange(isLogOpen) { _, open -> GameAudio.play(if (open) GameSound.PAGE_FLIP else GameSound.UI_CLOSE) }
    OnChange(commandFailure) { old, new -> if (committedCardChoice != null && CardChoiceCommandFailure.isNewFailure(old, new)) cancelCommittedCardChoice() }
    OnChange(PortraitInteractionPolicy.detailChoiceKey(board)) { _, key ->
        isPromptDetailOpen = key != null
        // A decision that needs you, not a routine priority pass.
        if (key != null) GameAudio.play(GameSound.RESPONSE_ALERT)
    }
    OnChange(PortraitInteractionPolicy.cardChoiceKey(board)) { _, key ->
        if (key != null && committedCardChoice == null) GameAudio.play(GameSound.RESPONSE_ALERT)
        isCardChoiceOpen = key != null && committedCardChoice == null && !reviewCardChoiceAfterPending
        selection.inspectedCard = null; selection.selectedCard = null
        if (key != null) { isPromptDetailOpen = false; isStackSheetOpen = false }
    }
    OnChange(board.combatSelectionResetKey) { _, _ -> combatSelection = combatSelection.resetIfInactive(board); combatPreviewArrows = emptyList() }
    OnChange(selection.selectedCard?.id) { _, _ ->
        val card = selection.selectedCard ?: return@OnChange
        if (pendingActionId != null || GameBoardInteractionState.boardTargetableIds(board).isNotEmpty()) return@OnChange
        val actions = GameBoardInteractionState.cardActions(card, board.legalActions ?: emptyList())
        if (actions.isNotEmpty()) dragActionChoice = DragActionChoice(card.card.name, actions)
    }
    OnChange(board.isCompleted) { _, completed ->
        if (!completed) return@OnChange
        isLogOpen = false; isStackSheetOpen = false; isPromptDetailOpen = false; isCardChoiceOpen = false; dragActionChoice = null; selection.inspectedCard = null
        val won = board.winnerPlayerIds?.contains(board.viewerID) == true
        GameAudio.duckMusic(6.0)
        GameAudio.play(if (won) GameSound.VICTORY else GameSound.DEFEAT, 0.25)
    }
    OnChange(GameSoundSignatureKey(board)) { old, new ->
        io.magicmobile.android.ui.GameSoundSignature.cues(old.signature, new.signature).forEachIndexed { index, sound -> GameAudio.play(sound, index * 0.11) }
    }
    OnChange(board.aiWaitSignature) { _, _ -> updateAIWaitStart(board) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(2000)
            val snap = currentSnapshot
            val key = snap.aiWaitSignature
            if (key != aiWaitKey) continue
            when (AIWaitRecoveryPolicy.action(snap, (System.currentTimeMillis() - aiWaitBeganAt) / 1000.0, didAutoRefreshAIWaitKey == key,
                didAutoReconnectAIWaitKey == key, didAutoDiagnoseAIWaitKey == key)) {
                AIWaitRecoveryAction.NONE -> {}
                AIWaitRecoveryAction.REFRESH -> { didAutoRefreshAIWaitKey = key; onInteractionFeedback("Refreshing player wait"); refreshGame() }
                AIWaitRecoveryAction.RECONNECT -> { didAutoReconnectAIWaitKey = key; onInteractionFeedback("Reconnecting player wait"); reconnectGame() }
                AIWaitRecoveryAction.DIAGNOSE -> { didAutoDiagnoseAIWaitKey = key; onInteractionFeedback("Checking bridge health"); launch { checkBridgeHealth() } }
            }
        }
    }

    // --- Phase presentation: the turn banner and the phase pill that flies into the top bar ---
    val announcement = BoardPhaseAnnouncement.make(board)
    LaunchedEffect(announcement?.key) {
        val key = announcement?.key
        if (key == null || key == lastTurnCueKey) { showsTurnCue = false; return@LaunchedEffect }
        lastTurnCueKey = key
        suspend fun mergePhaseCueIntoBar() {
            phaseCueMerging = true
            delay(300)
            showsTurnCue = false; phaseCueMerging = false; hudPulse += 1
        }
        // The first phase of a new turn gets the turn-start banner instead of a phase card.
        val turnKey = "${board.id}:${board.turn}:${board.activePlayerId ?: ""}"
        if (turnKey != lastTurnSoundKey) {
            val firstTurn = lastTurnSoundKey == null
            lastTurnSoundKey = turnKey
            if ((!firstTurn || board.turn > 1) && board.isViewer(board.activePlayerId)) GameAudio.play(GameSound.TURN_YOU)
        }
        if (turnKey != lastTurnBannerKey && BoardFXLevel.of(boardFXLevel) != BoardFXLevel.OFF) {
            val firstBanner = lastTurnBannerKey == null
            lastTurnBannerKey = turnKey
            if (!firstBanner || board.turn > 1) {
                if (board.isViewer(board.activePlayerId)) view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                showsTurnBanner = true; showsTurnCue = true
                delay(1600)
                showsTurnBanner = false
                mergePhaseCueIntoBar()
                return@LaunchedEffect
            }
        }
        phaseCueMerging = false
        showsTurnCue = true
        delay(1100)
        mergePhaseCueIntoBar()
    }

    val shakeValue = boardShake.value
    val decay = 1 - (shakeValue - floor(shakeValue))
    val shakeX = if (decay >= 1f) 0f else (sin(shakeValue * Math.PI * 6) * boardShakeAmplitude * decay).toFloat()
    val shakeY = if (boardShakeAmplitude > 8 && decay < 1f) (abs(sin(shakeValue * Math.PI * 4)) * boardShakeAmplitude * 0.35 * decay).toFloat() else 0f
    @Suppress("UNUSED_VARIABLE") val fxTick = fxVersion

    CompositionLocalProvider(LocalBoardFXCardMotion provides boardFX.cardMotion(board.viewerID), LocalBoardFXClock provides boardFXClock,
        LocalBoardHUDPulse provides hudPulse, LocalBoardZoneInspectionAction provides ::inspectBoardZone, LocalCardBounds provides cardBounds,
        LocalHoldCardInspection provides holdInspection, LocalInspectorBattlefield provides board.visibleBattlefield) {
        Box(Modifier.fillMaxSize().background(rgb(0.055, 0.085, 0.10))) {
            // The board surface, shaken as one piece by big hits.
            Box(Modifier.fillMaxSize().graphicsLayer { translationX = shakeX * density; translationY = shakeY * density }) {
                BattlefieldSurface(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null, onClick = ::clearBoardSelection))
                BoxWithConstraints(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)
                    .onGloballyPositioned { cardBounds.boardOrigin = it.positionInRoot() }) {
                    val size = BoardSize(maxWidth.value, maxHeight.value)
                    PortraitGameContent(board, human, opponent, size, selection, pendingActionId, pendingCardInstanceId, liveUpdateStatus,
                        combatSelection, combatPreviewArrows, isOverPlayerDropZone, { isOverPlayerDropZone = it }, { interactionMode = it },
                        inspectingZoneTitle, inspectingZoneCards, inspectingZoneReference, { inspectingZoneTitle = null; inspectingZoneCards = emptyList(); inspectingZoneReference = null },
                        isPromptDetailOpen, dragActionChoice, { dragActionChoice = it }, aiWaitBeganAt, didAutoRefreshAIWaitKey == aiWaitKey,
                        didAutoReconnectAIWaitKey == aiWaitKey, didAutoDiagnoseAIWaitKey == aiWaitKey, boardFX, boardFXClock, { boardFX.prune(System.currentTimeMillis()); fxVersion += 1 },
                        onInteractionFeedback, runAction, runCommand, refreshGame, reconnectGame, ::submitTarget, ::handleCombatCardTap, ::submitAttackers,
                        ::submitBlockers, ::finishAttackers, ::finishBlockers, { combatSelection = it }, { focusedOpponentId = it },
                        { isLogOpen = true }, { isGameMenuOpen = true }, ::openPromptDetails, ::localViewZone, { isPromptDetailOpen = true })
                }
                if (board.source == "design-preview") {
                    Text("DEVELOPMENT FIXTURE · NO ENGINE", Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.safeDrawing)
                        .background(Color.Yellow, CircleShape).padding(horizontal = 6.dp, vertical = 1.dp), color = Color.Black, style = sf(8f, SfWeight.bold))
                }
            }
            if (hitVignette.value > 0f) BoardHitVignette(hitVignette.value)

            // --- Choices (boardChoicePresentation) ---
            val cardChoiceKey = PortraitInteractionPolicy.cardChoiceKey(board)
            val choicePrompt = board.promptEnvelopeV2
            if (isCardChoiceOpen && cardChoiceKey != null && choicePrompt != null) {
                key(cardChoiceKey) {
                    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
                        BoardCardChoiceView(board, choicePrompt, pendingActionId, runCommand, runAction, ::commitCardChoicePlan) { isCardChoiceOpen = false }
                    }
                }
            }
            if (committedCardChoice != null) {
                // Block manual board/answer taps until Stop returns control to the current prompt.
                Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null) {})
                Row(Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.safeDrawing).background(MagicPalette.iron, CircleShape).padding(8.dp)
                    .semantics { contentDescription = "board.choice.progress" }, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(16.dp), color = MagicPalette.parchment, strokeWidth = 2.dp)
                    Text("Applying card choices…", color = MagicPalette.parchment, style = SfText.caption())
                    Text("Stop", Modifier.clickable(onClick = ::cancelCommittedCardChoice).padding(horizontal = 12.dp, vertical = 12.dp),
                        color = rgb(0.04, 0.52, 1.0), style = SfText.caption(SfWeight.semibold))
                }
            }

            // --- Phase presentation ---
            val activeId = board.activePlayerId
            AnimatedVisibility(showsTurnBanner && activeId != null && !isCardChoiceOpen && !isPromptDetailOpen, Modifier.align(Alignment.Center),
                enter = fadeIn(), exit = scaleOut(targetScale = 0.2f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 0f)) +
                    slideOutVertically { -it * 2 } + fadeOut()) {
                if (activeId != null) BoardTurnBanner(if (board.isViewer(activeId)) "Your turn" else "${board.playerLabel(activeId)}’s turn", board.turn,
                    board.isViewer(activeId), Modifier.semantics { contentDescription = "board.turn.banner" })
            }
            val cue = announcement
            AnimatedVisibility(showsTurnCue && cue != null && !isCardChoiceOpen && !isPromptDetailOpen,
                Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.safeDrawing).padding(top = 64.dp),
                enter = if (BoardMotion.reduceMotion) fadeIn() else slideInVertically { -it } + fadeIn(),
                exit = if (BoardMotion.reduceMotion) fadeOut() else slideOutVertically { -it } + fadeOut()) {
                if (cue != null) {
                    val merge by animateFloatAsState(if (phaseCueMerging) 1f else 0f, tween(300), label = "phaseMerge")
                    Row(Modifier.graphicsLayer { scaleX = 1 - 0.5f * merge; scaleY = 1 - 0.5f * merge; translationY = -46 * merge * density; alpha = 1 - merge }
                        .glow(Color.Black.copy(alpha = 0.4f), 10.dp, 20.dp)
                        .background(MagicPalette.iron.copy(alpha = 0.92f), CircleShape).border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.7f), CircleShape)
                        .padding(horizontal = 16.dp, vertical = 8.dp).semantics { contentDescription = "board.phase.announcement" },
                        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(cue.owner.uppercase(), color = MagicPalette.antiqueGold, style = SfText.caption2(SfWeight.heavy).copy(letterSpacing = androidx.compose.ui.unit.TextUnit(1f, androidx.compose.ui.unit.TextUnitType.Sp)))
                        io.magicmobile.android.ui.FitText(cue.title, sf(17f, SfWeight.bold, io.magicmobile.android.ui.SfDesign.SERIF), color = MagicPalette.parchment, minimumScale = 0.7f)
                    }
                }
            }

            // --- Opening hand, spectator bar and the result (above the HUD, dock and choice layers) ---
            val openingChoice = OpeningHandChoice.of(board)
            val hand = board.human?.zones?.hand ?: emptyList()
            if (openingChoice != null && hand.isNotEmpty()) OpeningHandOverlay(openingChoice, hand, pendingActionId != null, runCommand)
            AnimatedVisibility(board.isSpectating, Modifier.align(Alignment.BottomCenter).navigationBarsPadding(),
                enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
                SpectatorBar(board, quitGame, Modifier.widthIn(max = 460.dp).padding(horizontal = 12.dp).padding(bottom = 8.dp))
            }
            AnimatedVisibility(board.isCompleted, enter = if (BoardMotion.reduceMotion) fadeIn() else scaleIn() + fadeIn(), exit = fadeOut()) {
                GameCompletionOverlay(board, newGame, quitGame, gameStats)
            }
        }

        // --- Sheets ---
        if (isLogOpen) BoardSheet({ isLogOpen = false }, sound = false) {
            GameLogDrawer(board.log, { isLogOpen = false }, Modifier.padding(14.dp).fillMaxWidth().heightInScreen(0.8f))
        }
        if (isStackSheetOpen) BoardSheet({ isStackSheetOpen = false }) { BoardStackInspector(board, selection) { isStackSheetOpen = false } }
        if (isPromptDetailOpen) BoardSheet({ isPromptDetailOpen = false }) {
            key("${board.promptEnvelopeV2?.id ?: ""}:${board.promptEnvelopeV2?.messageId ?: 0}") {
                UniversalPromptActionPanel(board, selection.selectedCard?.let { GameBoardInteractionState.cardActions(it, board.legalActions ?: emptyList()) } ?: emptyList(),
                    selection, pendingActionId, runAction, runCommand, { title, cards -> isPromptDetailOpen = false; localViewZone(title, cards) },
                    { isPromptDetailOpen = false }, Modifier.padding(14.dp).fillMaxWidth().heightInScreen(0.85f), showsGameSurfaceSections = board.promptEnvelopeV2 == null)
            }
        }
        if (isGameMenuOpen) BoardSheet({ isGameMenuOpen = false }) {
            GameManagementMenu(board, board.legalActions?.firstOrNull { it.type == "concede" }, runAction, portraitModeEnabled, setPortraitModeEnabled,
                { isGameMenuOpen = false; isPromptInspectorOpen = true }, { gameMenuConfirmation = GameMenuConfirmation.START_NEW },
                { gameMenuConfirmation = GameMenuConfirmation.QUIT }) { isGameMenuOpen = false }
        }
        if (isPromptInspectorOpen) BoardSheet({ isPromptInspectorOpen = false }) { PromptDebugInspector(board, liveUpdateStatus) }
        gameMenuConfirmation?.let { confirmation ->
            ConfirmationDialog(confirmation.title, confirmation.message, listOf(
                if (confirmation == GameMenuConfirmation.START_NEW) ConfirmationAction("Start New Game", true) { isGameMenuOpen = false; newGame() }
                else ConfirmationAction("Quit to Menu", true) { isGameMenuOpen = false; quitGame() })) { gameMenuConfirmation = null }
        }
    }
}

/** A sheet's content height as a share of the screen, like the medium/large detents. */
@Composable
fun Modifier.heightInScreen(fraction: Float): Modifier {
    val screen = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp
    return this.heightIn(max = (screen * fraction).dp)
}

/** Wraps GameSoundSignature for change detection. */
data class GameSoundSignatureKey(val signature: io.magicmobile.android.ui.GameSoundSignature) {
    constructor(snapshot: GameSnapshot) : this(io.magicmobile.android.ui.GameSoundSignature(snapshot))
}

/** Swift BoardFXHaptics: a heavy thud at a strike's impact, a nudge when you lose life, a jolt as a commander lands. */
private fun playBoardFXHaptics(scope: kotlinx.coroutines.CoroutineScope, view: android.view.View, scheduled: List<ScheduledBoardFX>, viewerID: String) {
    scheduled.filter { it.event is BoardFXEvent.CombatStrike }.minOfOrNull { it.handoff }?.let { strike ->
        scope.launch { delay((strike * 1000).toLong()); view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS) }
    }
    val hit = scheduled.firstOrNull { (it.event as? BoardFXEvent.LifeChanged)?.let { e -> e.playerID == viewerID && e.delta < 0 } == true }
    if (hit != null) scope.launch { delay((hit.delay * 1000).toLong()); view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY) }
    else if (scheduled.any { it.event is BoardFXEvent.LeftBattlefield }) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    scheduled.firstOrNull { (it.event as? BoardFXEvent.EnteredBattlefield)?.entrance == BoardFXEntrance.COMMANDER }?.let { hero ->
        scope.launch { delay((hero.landing * 1000).toLong()); view.performHapticFeedback(HapticFeedbackConstants.CONFIRM) }
    }
}
