package io.magicmobile.android.board

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import io.magicmobile.android.game.ArenaAutoPay
import io.magicmobile.android.game.ArenaCanvas
import io.magicmobile.android.game.ArenaCombatPhase
import io.magicmobile.android.game.ArenaCommanderSteal
import io.magicmobile.android.game.ArenaCornerText
import io.magicmobile.android.game.ArenaExtraHand
import io.magicmobile.android.game.ArenaHandFanLayout
import io.magicmobile.android.game.ArenaHandPosture
import io.magicmobile.android.game.ArenaLaneChoice
import io.magicmobile.android.game.ArenaScreenContext
import io.magicmobile.android.game.ArenaScreens
import io.magicmobile.android.game.PromptDisplayText
import io.magicmobile.android.game.XmagePromptAbility
import io.magicmobile.android.game.ArenaLanePlanner
import io.magicmobile.android.game.ArenaTableRules
import io.magicmobile.android.game.BoardFXDirector
import io.magicmobile.android.game.BoardOpponentFocus
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardPresentationHold
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.game.BoardSize
import io.magicmobile.android.game.BoardZoneReference
import io.magicmobile.android.game.CardFramesPreference
import io.magicmobile.android.game.CombatArrow
import io.magicmobile.android.game.CombatHighlightSet
import io.magicmobile.android.game.CombatPlayerIdentity
import io.magicmobile.android.game.CombatSelectionState
import io.magicmobile.android.game.CompactPromptPopup
import io.magicmobile.android.game.GameActionDockModel
import io.magicmobile.android.game.GameBoardInteractionMode
import io.magicmobile.android.game.GameBoardInteractionState
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameplayAffordances
import io.magicmobile.android.game.InlinePaymentPromptState
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.OpeningHandChoice
import io.magicmobile.android.game.PlayerGameState
import io.magicmobile.android.game.PlayerStatusSummary
import io.magicmobile.android.game.PromptCommandBuilder
import io.magicmobile.android.game.PromptEnvelopeV2
import io.magicmobile.android.game.TavernEffectOrbit
import io.magicmobile.android.game.UniversalPromptResponseCommandBuilder
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.game.visibleBattlefield
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaPanel
import io.magicmobile.android.menus.ArenaSafeArea
import io.magicmobile.android.menus.LocalArenaBoard
import io.magicmobile.android.menus.LocalArenaSafeArea
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.yield
import kotlin.math.max
import kotlin.math.min

/*
 * Port of Board/NativeGameView+Arena.swift and NativeGameView+ArenaActions.swift: the Arena board (BoardMode.ARENA), laid out
 * by ArenaLayout on the leaning tavern table. Everything the board does goes through the same commands as the Hearth board:
 * BattlefieldRow for permanents, the hand's drop resolver, submitTarget and the combat helpers, the zone inspector,
 * GameActionDockModel for passing. No engine change (docs/ARENA_STYLE.md principle 8).
 */

/** An Auto Pay in progress: the payment states it has already acted on, so it stops instead of tapping in circles. */
data class ArenaAutoPayRun(val steps: Int = 0, val signatures: Map<String, Int> = emptyMap(),
                           /** The colour to name when XMage asks what a mana of any colour should be. */
                           val color: String? = null,
                           /** Auto Pay's last tap may be asking a colour: only then does it answer a colour question. */
                           val awaitingColor: Boolean = false,
                           /** The colour question ("id:messageId") Auto Pay answered, kept from the pop-up until its answer lands. */
                           val answeredColor: String? = null,
                           /** Snapshots in a row without the payment: XMage can send one between answers. */
                           val quiet: Int = 0)

/** The corner's buttons for the moment: the call to action and, above it, the secondary choice. */
data class ArenaButtonPlan(val primary: Choice? = null, val secondary: Choice? = null) {
    data class Choice(val title: String, val subtitle: String? = null, val kind: ArenaPlaqueKind = ArenaPlaqueKind.PRIMARY,
                      val enabled: Boolean = true, val action: () -> Unit)
}

/** What the Arena board needs from NativeGameView: its state and the same helpers the Hearth board calls. */
class ArenaBoardHost(
    val snapshot: GameSnapshot, val human: PlayerGameState, val opponent: PlayerGameState, val selection: BoardSelection,
    val pendingActionId: String?, val pendingCardInstanceId: String?, val liveUpdateStatus: String,
    val combatSelection: CombatSelectionState, val setCombatSelection: (CombatSelectionState) -> Unit, val combatPreviewArrows: List<CombatArrow>,
    val isOverPlayerDropZone: Boolean, val setOverPlayerDropZone: (Boolean) -> Unit,
    val interactionMode: GameBoardInteractionMode, val setInteractionMode: (GameBoardInteractionMode) -> Unit,
    val inspectingZoneTitle: String?, val inspectingZoneCards: List<ZoneCard>, val inspectingZoneReference: BoardZoneReference?, val closeZone: () -> Unit,
    val isPromptDetailOpen: Boolean, val openPromptDetailSheet: () -> Unit, val isCardChoiceOpen: Boolean, val cardPlanRunning: Boolean,
    val dragActionChoice: DragActionChoice?, val setDragActionChoice: (DragActionChoice?) -> Unit,
    val aiWaitBeganAt: Long, val didRefresh: Boolean, val didReconnect: Boolean, val didDiagnose: Boolean,
    val boardFX: BoardFXDirector, val boardFXClock: BoardFXClock, val pruneFX: () -> Unit,
    val onInteractionFeedback: (String) -> Unit, val runAction: (LegalAction) -> Unit, val runCommand: (GameCommand, String, String) -> Unit,
    val refreshGame: () -> Unit, val reconnectGame: () -> Unit,
    val submitTarget: (ZoneCard) -> Unit, val handleCombatCardTap: (ZoneCard) -> Boolean, val submitAttackers: (String) -> Unit,
    val submitBlockers: () -> Unit, val finishAttackers: () -> Unit, val finishBlockers: () -> Unit, val combatBack: (() -> Unit)?,
    val selectOpponent: (String) -> Unit, val openLog: () -> Unit, val openSettings: () -> Unit, val openPromptDetails: () -> Unit,
    val viewZone: (String, List<ZoneCard>) -> Unit, val inspectBoardZone: (BoardZoneReference) -> Unit,
    val isStackOpen: Boolean, val setStackOpen: (Boolean) -> Unit,
    val notice: String?, val showNotice: (String, Double) -> Unit,
)

/**
 * The Arena board. Its layers keep iOS's z-order: lanes, the opponent's seat, the stack card, the caption, the revealed chips,
 * your seat, the front rail (portrait), the hand, the spread tab, the corner, then the overlays and the drawn arrows and effects.
 */
@Composable
fun ArenaBoard(host: ArenaBoardHost) {
    val snapshot = host.snapshot
    val human = host.human
    val opponent = host.opponent
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val startingRollVisible = LocalStartingRollVisible.current
    val turnControl = LocalNativeTurnControl.current
    val answerActions = LocalBoardAnswerActions.current
    val registry = LocalCardBounds.current
    val emoteCenter = LocalEmoteCenter.current
    val turnClock = LocalTurnClock.current
    val density = LocalDensity.current.density
    val arenaFrames by AppPreferences.boolean(CardFramesPreference.arenaKey, CardFramesPreference.arenaDefault)

    var handOpen by remember { mutableStateOf(false) }
    var handSpread by remember { mutableStateOf(false) }
    var liftedCardID by remember { mutableStateOf<String?>(null) }
    var autoPay by remember { mutableStateOf<ArenaAutoPayRun?>(null) }
    var attackQueue by remember { mutableStateOf<List<String>?>(null) }
    var cornerMenu by remember { mutableStateOf<String?>(null) }
    var playerCardID by remember { mutableStateOf<String?>(null) }
    var revealID by remember { mutableStateOf<String?>(null) }
    var landedStackIDs by remember { mutableStateOf(setOf<String>()) }
    var showPhaseStops by remember { mutableStateOf(false) }
    var safeArea by remember { mutableStateOf(ArenaSafeArea()) }
    /** The trigger order chosen in the ability browser (ability ids, first to place first) and the prompt it last answered. */
    var triggerPlan by remember { mutableStateOf(listOf<String>()) }
    var triggerSent by remember { mutableStateOf<String?>(null) }
    val current by rememberUpdatedState(host)

    fun haptic() = GameHaptics.selection(view)

    // MARK: Decisions

    val targetableIds = GameBoardInteractionState.boardTargetableIds(snapshot)
    val combatPhase = ArenaCombatPhase.current(snapshot)
    val openingHand = OpeningHandChoice.of(snapshot) != null
    fun handPosture(spread: Boolean = handSpread): ArenaHandPosture {
        val decision = InlinePaymentPromptState.isActive(snapshot) || targetableIds.isNotEmpty() || combatPhase != null ||
            host.isCardChoiceOpen || host.isPromptDetailOpen || host.cardPlanRunning ||
            (!startingRollVisible && CompactPromptPopup.shouldShow(snapshot, null))
        return ArenaHandPosture.resolve(ArenaHandPosture.Situation(handOpen, spread, decision,
            host.interactionMode is GameBoardInteractionMode.DraggingCard, snapshot.isSpectating))
    }
    val posture = handPosture()
    /** The raised hand covers the corner, as in the reference, except while the table asks you something. */
    val controlsOnTop = InlinePaymentPromptState.isActive(snapshot) || snapshot.stackTopFirst.isNotEmpty() || combatPhase != null || targetableIds.isNotEmpty()
    // The full-table screens (docs/ARENA_STYLE.md, "Gating a new Arena screen"): each takes the question its Hearth panel would.
    val screenContext = ArenaScreenContext(startingRollVisible, autoPay?.awaitingColor == true, autoPay?.answeredColor, triggerPlan, triggerSent)
    val abilityPrompt = ArenaScreens.abilityPrompt(snapshot, screenContext)
    val modePrompt = if (abilityPrompt == null) ArenaScreens.modePrompt(snapshot) else null
    val choicePrompt = if (abilityPrompt == null && modePrompt == null) ArenaScreens.choicePrompt(snapshot, screenContext) else null
    val playerPrompt = if (abilityPrompt == null && modePrompt == null && choicePrompt == null) ArenaScreens.playerPrompt(snapshot, screenContext) else null
    val splitPrompt = if (abilityPrompt == null && modePrompt == null && choicePrompt == null && playerPrompt == null) ArenaScreens.splitPrompt(snapshot, screenContext) else null
    val pilePrompt = if (abilityPrompt == null && modePrompt == null && choicePrompt == null && playerPrompt == null && splitPrompt == null)
        ArenaScreens.pilePrompt(snapshot, screenContext) else null
    val question = ArenaScreens.question(snapshot, targetableIds, host.pendingActionId, host.isPromptDetailOpen, screenContext)
    /** A full-table screen is up: it hides the corner, the caption, the stack card and the arrows over the table. */
    val screenUp = host.isCardChoiceOpen || host.isStackOpen || host.inspectingZoneTitle != null || abilityPrompt != null || modePrompt != null ||
        choicePrompt != null || playerPrompt != null || splitPrompt != null || pilePrompt != null || question != null
    val amountPrompt = if (screenUp) null else ArenaTableRules.amountPrompt(snapshot, startingRollVisible)

    /** XMage's own answers beside a screen's (Cancel, Done), leaving out the ones the screen makes itself. */
    fun promptAnswers(excluding: Set<String>): List<ArenaAnswer> = CompactPromptPopup.compactLegalPromptActions(snapshot)
        .filter { it.type !in excluding }.map { action -> ArenaAnswer(action.id, action.compactPromptTitle) { host.runAction(action) } }
    /** The same command the Hearth panel sends for this answer. */
    fun answer(prompt: PromptEnvelopeV2, type: String, label: String, key: String, ids: List<String> = emptyList(), amounts: List<Int>? = null, pile: Int? = null) {
        if (host.pendingActionId != null) return
        val command = UniversalPromptResponseCommandBuilder.command(snapshot.id, snapshot.bridgeRevision, prompt, type,
            prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, ids, amounts = amounts, pile = pile) ?: return
        haptic()
        host.runCommand(command, label, key)
    }
    fun chooseAbility(ability: XmagePromptAbility, prompt: PromptEnvelopeV2, remember: Boolean) {
        val snap = current.snapshot
        if (current.pendingActionId != null) return
        var command = PromptCommandBuilder.command(snap.id, prompt, "choose_ability", prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId,
            listOf(ability.id)) ?: return
        if (remember) command = command.copy(answerActions = listOf("rememberTriggerFirst"))
        haptic()
        current.runCommand(command, if (prompt.isTriggerOrder) "Put a trigger on the stack" else "Choose ability", "${prompt.id}-${ability.id}")
    }
    /** `resolveOrder` runs first to last; each ordering prompt then gets the first planned trigger it still offers (triggerStep). */
    fun orderTriggers(resolveOrder: List<XmagePromptAbility>, remember: Boolean, prompt: PromptEnvelopeV2) {
        val plan = ArenaScreens.triggerPlan(resolveOrder)
        val ability = plan.firstOrNull()?.let { id -> resolveOrder.firstOrNull { it.id == id } } ?: return
        triggerPlan = plan
        triggerSent = "${prompt.id}:${prompt.messageId}"
        chooseAbility(ability, prompt, remember)
    }
    fun triggerStep() {
        val snap = current.snapshot
        val step = ArenaScreens.triggerStep(snap, triggerPlan, triggerSent, current.pendingActionId != null)
        triggerPlan = step.plan; triggerSent = step.sent
        val prompt = snap.promptEnvelopeV2
        val pick = step.pick
        if (pick != null && prompt != null) chooseAbility(pick, prompt, false)
    }

    fun playerTargetID(playerID: String): String? {
        if (targetableIds.isEmpty()) return null
        return CombatPlayerIdentity.ids(playerID, snapshot).firstOrNull { it in targetableIds }
    }
    fun submitPlayerTarget(id: String) {
        val prompt = snapshot.promptEnvelopeV2 ?: return
        if ((prompt.maxChoices ?: 1) > 1 || (prompt.minChoices ?: 1) > 1) { host.openPromptDetailSheet(); return }
        val promptId = prompt.responseCommand?.promptId ?: prompt.id
        val command = UniversalPromptResponseCommandBuilder.command(snapshot.id, snapshot.bridgeRevision, prompt, "choose_target", promptId, prompt.playerId, listOf(id))
            ?: run { GameHaptics.warning(view); host.onInteractionFeedback("XMage did not expose a mobile-safe target command"); return }
        GameHaptics.success(view)
        host.runCommand(command, "Target ${snapshot.playerLabel(id)}", "$promptId-$id")
    }
    fun tapTable() {
        if (liftedCardID != null) liftedCardID = null
        else if (posture == ArenaHandPosture.RAISED || posture == ArenaHandPosture.SPREAD) { handOpen = false; handSpread = false; GameAudio.play(GameSound.CARD_PICKUP) }
        if (host.selection.selectedCard != null || host.selection.inspectedCard != null) {
            host.selection.selectedCard = null; host.selection.inspectedCard = null; haptic()
        }
    }

    // MARK: Auto Pay, All Attack

    fun autoPayNext(snap: GameSnapshot): ArenaAutoPay.Step {
        if (!InlinePaymentPromptState.isActive(snap)) return ArenaAutoPay.Step.Done
        if (snap.manaPayment?.active == true || snap.promptEnvelopeV2?.responseKind?.lowercase() == "mana") return ArenaAutoPay.next(snap)
        // The gateway's synthetic stack payment: no prompt text of its own, so read the cost from it.
        val prompt = CompactPromptPopup.syntheticStackPaymentPrompt(snap)
        return ArenaAutoPay.next(snap.manaPayment?.remainingText ?: prompt.message, emptyMap(), snap.legalActions ?: emptyList())
    }
    /** One Auto Pay step per settled snapshot: one tap, then XMage's answer before the next; a colour question gets the plan's colour. */
    fun autoPayStep() {
        val snap = current.snapshot
        var run = autoPay ?: return
        if (current.pendingActionId != null) return
        val prompt = snap.promptEnvelopeV2
        if (run.awaitingColor && prompt != null && snap.isViewer(prompt.playerId)) {
            val choice = ArenaCornerText.colorChoice(prompt, run.color)
            if (choice != null) {
                autoPay = run.copy(color = null, awaitingColor = false, answeredColor = "${prompt.id}:${prompt.messageId}", quiet = 0)
                val command = PromptCommandBuilder.command(snap.id, prompt, "resolve_choice", prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, listOf(choice))
                if (command != null) current.runCommand(command, "Choose mana colour", "autopay-colour-${prompt.id}-${prompt.messageId}") else autoPay = null
                return
            }
        }
        val payment = InlinePaymentPromptState.paymentPrompt(snap)
        if (!InlinePaymentPromptState.isActive(snap) || payment == null) {
            // Another question means the payment is over; a quiet snapshot or two can come between XMage's answers.
            val asked = prompt?.let { snap.isViewer(it.playerId) } ?: false
            run = run.copy(quiet = run.quiet + 1, awaitingColor = if (run.quiet + 1 > 1) false else run.awaitingColor)
            autoPay = if (asked || run.quiet > 3) null else run
            return
        }
        // Back at the payment: the last tap asked nothing.
        run = run.copy(awaitingColor = false, color = null, quiet = 0)
        val remaining = snap.manaPayment?.remainingText ?: payment.message
        val signature = remaining + "|" + (snap.legalActions ?: emptyList()).map { it.id }.sorted().joinToString(",")
        if ((run.signatures[signature] ?: 0) >= 2 || run.steps >= 30) {
            autoPay = null
            current.showNotice("Auto Pay stopped: tap the rest yourself", 2.4)
            return
        }
        run = run.copy(signatures = run.signatures + (signature to (run.signatures[signature] ?: 0) + 1), steps = run.steps + 1)
        autoPay = run
        when (val next = autoPayNext(snap)) {
            is ArenaAutoPay.Step.Tap -> {
                val action = snap.legalActions?.firstOrNull { it.id == next.actionID }
                if (action != null) { autoPay = run.copy(color = next.color, awaitingColor = true); current.runAction(action) } else autoPay = null
            }
            is ArenaAutoPay.Step.Spend -> {
                val command = GameplayAffordances.floatingManaCommand(next.symbol, snap)
                if (command != null) current.runCommand(command, "Spend floating {${next.symbol}}", "autopay-${payment.id}-${next.symbol}-${run.steps}") else autoPay = null
            }
            ArenaAutoPay.Step.Done -> autoPay = null
            is ArenaAutoPay.Step.Blocked -> { autoPay = null; current.showNotice(next.reason, 2.4) }
        }
    }
    /** The on-device engine takes one attacker per answer: send the next as soon as XMage has taken the last. */
    fun attackStep() {
        val snap = current.snapshot
        val queue = attackQueue ?: return
        if (current.pendingActionId != null) return
        if (ArenaCombatPhase.current(snap) != ArenaCombatPhase.ATTACKERS) {
            // A snapshot between XMage's answers can lack the attacker prompt: only leaving the step ends the queue.
            if (!(snap.step ?: snap.phase).lowercase().replace("_", "-").contains("declare-attack")) attackQueue = null
            return
        }
        val targetable = GameBoardInteractionState.boardTargetableIds(snap)
        if (targetable.isEmpty()) return
        val mine = snap.human?.zones?.battlefield ?: emptyList()
        fun creature(id: String) = mine.firstOrNull { it.instanceId == id || it.id == id }
        // XMage asking which defender offers none of your creatures: wait for it.
        if (mine.none { it.instanceId in targetable || it.id in targetable }) return
        val remaining = queue.filter { id -> id in targetable && creature(id)?.let { it.isAttacking != true } == true }
        val next = remaining.firstOrNull()?.let(::creature)
        if (next == null) { attackQueue = null; return }
        attackQueue = remaining.drop(1).ifEmpty { null }
        current.submitTarget(next)
    }
    // Every new answer from XMage steps the helpers: its revision, a new prompt or the pending answer clearing.
    val stepKey = "${snapshot.bridgeRevision ?: -1}|${snapshot.promptEnvelopeV2?.id ?: ""}|${snapshot.promptEnvelopeV2?.messageId ?: -1}|${host.pendingActionId ?: ""}"
    LaunchedEffect(stepKey) {
        if (autoPay == null && attackQueue == null && triggerPlan.isEmpty()) return@LaunchedEffect
        // Let the snapshot's own updates land before acting on it.
        yield()
        autoPayStep()
        attackStep()
        triggerStep()
    }

    fun allAttackTargets(): List<String>? {
        if (BoardOpponentFocus.opponents(snapshot).size != 1) return null
        val actions = snapshot.legalActions ?: emptyList()
        if (CombatSelectionState.isDeclareAttackers(snapshot)) {
            return if (host.combatSelection.defenderHighlightIds(actions).size == 1) host.combatSelection.attackerHighlightIds(actions).sorted() else null
        }
        val mine = snapshot.human?.zones?.battlefield ?: emptyList()
        return mine.filter { it.isAttacking != true && (it.instanceId in targetableIds || it.id in targetableIds) }
            .map { if (it.instanceId in targetableIds) it.instanceId else it.id }
    }
    fun startAllAttack(ids: List<String>) {
        if (CombatSelectionState.isDeclareAttackers(snapshot)) {
            // The gateway takes every attacker in one declaration.
            val defender = host.combatSelection.defenderHighlightIds(snapshot.legalActions ?: emptyList()).firstOrNull() ?: return
            host.setCombatSelection(host.combatSelection.copy(selectedAttackerIds = ids.toSet()))
            host.submitAttackers(defender)
            return
        }
        attackQueue = ids
        haptic()
        attackStep()
    }
    fun finishCombat(phase: ArenaCombatPhase) {
        val done = (snapshot.legalActions ?: emptyList()).firstOrNull { it.type == "answer_yes_no" && it.confirmed != false }
        when {
            done != null -> host.runAction(done)
            phase == ArenaCombatPhase.ATTACKERS -> host.finishAttackers()
            host.combatSelection.hasPendingBlockers -> host.submitBlockers()
            else -> host.finishBlockers()
        }
    }

    // MARK: The corner's plan

    fun buttonPlan(): ArenaButtonPlan {
        if (snapshot.isCompleted || snapshot.isSpectating) return ArenaButtonPlan()
        val pending = host.pendingActionId
        if (InlinePaymentPromptState.isActive(snapshot)) {
            val cancel = ManaPaymentTrayRules.manaUndoActions(snapshot).firstOrNull { it.type == "cancel_payment" || it.type == "cancel_mana_payment" }
            val secondary = cancel?.let { action -> ArenaButtonPlan.Choice("Cancel", kind = ArenaPlaqueKind.SECONDARY, enabled = pending == null) { autoPay = null; host.runAction(action) } }
            if (autoPay != null) return ArenaButtonPlan(ArenaButtonPlan.Choice("Paying…", enabled = false) {},
                ArenaButtonPlan.Choice("Stop", kind = ArenaPlaqueKind.SECONDARY) { autoPay = null })
            return when (autoPayNext(snapshot)) {
                is ArenaAutoPay.Step.Tap, is ArenaAutoPay.Step.Spend ->
                    ArenaButtonPlan(ArenaButtonPlan.Choice("Auto Pay", enabled = pending == null) { autoPay = ArenaAutoPayRun(); haptic(); autoPayStep() }, secondary)
                // Nothing Auto Pay can do: the button stays, dimmed, and the sources on the table still take taps.
                else -> ArenaButtonPlan(ArenaButtonPlan.Choice("Auto Pay", enabled = false) {}, secondary)
            }
        }
        if (combatPhase != null) {
            val mine = snapshot.human?.zones?.battlefield ?: emptyList()
            val back = host.combatBack?.let { ArenaButtonPlan.Choice("Take Back", kind = ArenaPlaqueKind.SECONDARY, action = it) }
            if (combatPhase == ArenaCombatPhase.ATTACKERS) {
                val declared = mine.count { it.isAttacking == true }
                if (CombatSelectionState.isDeclareAttackers(snapshot) && host.combatSelection.selectedAttackerIds.isNotEmpty()) {
                    // The gateway's two-tap declaration: an attacker is chosen and waits for its defender.
                    return ArenaButtonPlan(ArenaButtonPlan.Choice("Cancel", kind = ArenaPlaqueKind.SECONDARY) { host.setCombatSelection(host.combatSelection.clearAttackers()) })
                }
                val finish = ArenaButtonPlan.Choice(when (declared) { 0 -> "No Attacks"; 1 -> "1 Attacker"; else -> "$declared Attackers" },
                    kind = if (declared == 0) ArenaPlaqueKind.SECONDARY else ArenaPlaqueKind.PRIMARY, enabled = pending == null) { finishCombat(ArenaCombatPhase.ATTACKERS) }
                val all = if (declared == 0 && attackQueue == null) allAttackTargets() else null
                if (!all.isNullOrEmpty()) return ArenaButtonPlan(ArenaButtonPlan.Choice("All Attack", enabled = pending == null) { startAllAttack(all) }, finish)
                if (attackQueue != null) return ArenaButtonPlan(ArenaButtonPlan.Choice("Attacking…", enabled = false) {},
                    ArenaButtonPlan.Choice("Stop", kind = ArenaPlaqueKind.SECONDARY) { attackQueue = null })
                return ArenaButtonPlan(finish, if (declared > 0) back else null)
            }
            val declared = mine.count { !it.blocking.isNullOrEmpty() }
            if (CombatSelectionState.isDeclareBlockers(snapshot) && host.combatSelection.selectedBlockerId != null) {
                return ArenaButtonPlan(ArenaButtonPlan.Choice("Cancel", kind = ArenaPlaqueKind.SECONDARY) { host.setCombatSelection(host.combatSelection.clearBlockers()) })
            }
            val finish = ArenaButtonPlan.Choice(when (declared) { 0 -> "No Blocks"; 1 -> "1 Blocker"; else -> "$declared Blockers" },
                kind = if (declared == 0) ArenaPlaqueKind.SECONDARY else ArenaPlaqueKind.PRIMARY, enabled = pending == null) { finishCombat(ArenaCombatPhase.BLOCKERS) }
            return ArenaButtonPlan(finish, if (declared > 0) back else null)
        }
        val actions = snapshot.legalActions ?: emptyList()
        val passAction = actions.firstOrNull { it.type == "pass_priority" } ?: actions.firstOrNull { it.type == "pass_until_response" }
        val model = GameActionDockModel.make(snapshot, passAction, CompactPromptPopup.compactLegalPromptActions(snapshot),
            !startingRollVisible && CompactPromptPopup.shouldShow(snapshot, null), pending)
        return when (model.mode) {
            GameActionDockModel.Mode.GAME_OVER -> ArenaButtonPlan()
            GameActionDockModel.Mode.WAITING -> ArenaButtonPlan(ArenaButtonPlan.Choice("Waiting…", kind = ArenaPlaqueKind.WAITING, enabled = false) {})
            GameActionDockModel.Mode.PROMPT -> {
                val primaryAction = model.primaryAction
                val primary = if (primaryAction != null) ArenaButtonPlan.Choice(primaryAction.label) { host.runAction(primaryAction) }
                    else ArenaButtonPlan.Choice("Choices", kind = ArenaPlaqueKind.SECONDARY) { host.openPromptDetails() }
                val other = model.promptActions.firstOrNull { it.id != primaryAction?.id }
                ArenaButtonPlan(primary, other?.let { action -> ArenaButtonPlan.Choice(action.label, kind = ArenaPlaqueKind.SECONDARY) { host.runAction(action) } })
            }
            GameActionDockModel.Mode.PRIORITY -> {
                val pass = model.primaryAction ?: return ArenaButtonPlan(ArenaButtonPlan.Choice(ArenaCornerText.waitingTitle(snapshot), kind = ArenaPlaqueKind.WAITING, enabled = false) {})
                val (title, subtitle) = ArenaCornerText.passTitle(pass, snapshot)
                val resolve = GameplayAffordances.resolveStackCommand(snapshot, pending, answerActions.supported)
                ArenaButtonPlan(ArenaButtonPlan.Choice(title, subtitle) { host.runAction(pass) },
                    resolve?.let { command -> ArenaButtonPlan.Choice("Resolve All", kind = ArenaPlaqueKind.SECONDARY) {
                        host.runCommand(command, "Resolve the stack", "resolve-stack-${command.promptId ?: ""}")
                    } })
            }
        }
    }

    // MARK: Effects

    LaunchedEffect(snapshot.step ?: snapshot.phase) { handOpen = false }
    // The spread hand tucks at a new turn and when the phone turns (landscape has no spread).
    LaunchedEffect(snapshot.turn) { handSpread = false }
    // A new decision puts a player's card and the corner's menus away.
    OnChange(snapshot.promptEnvelopeV2?.id) { _, _ -> playerCardID = null; cornerMenu = null }
    // Reading a card holds smart pass until the inspector closes (BoardPresentationHold.reading).
    LaunchedEffect(host.selection.inspectedCard?.id) { BoardPresentationHold.shared.reading = host.selection.inspectedCard != null }
    DisposableEffect(Unit) { onDispose { BoardPresentationHold.shared.reading = false } }
    // Your commander taken by an opponent: say who has it and why it never went home.
    OnChange(ArenaCommanderSteal.taken(snapshot)) { old, now ->
        now.firstOrNull { it !in old }?.let { host.showNotice(ArenaCommanderSteal.notice(it, snapshot), 7.0) }
    }
    // The stack browser closes once the stack empties, so it doesn't reopen with the next spell.
    OnChange(snapshot.stackTopFirst.isEmpty()) { _, empty -> if (empty) { host.setStackOpen(false); landedStackIDs = emptySet() } }
    // Design fixtures only: MAGICMOBILE_ARENA_HAND=open shows the hand opened, =pop one card popped out of it, =spread the hand spread.
    LaunchedEffect(Unit) {
        if (!io.magicmobile.android.BuildConfig.DEBUG || !snapshot.id.startsWith("design-preview-")) return@LaunchedEffect
        when (io.magicmobile.android.ui.LaunchEnvironment["MAGICMOBILE_ARENA_HAND"]) {
            "open" -> handOpen = true
            "spread" -> handSpread = true
            "pop" -> liftedCardID = BoardOpponentFocus.seatHand(snapshot).drop(3).firstOrNull()?.id
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { registry?.boardOrigin = it.positionInRoot() }) {
        val screen = BoardSize(maxWidth.value, maxHeight.value)
        val canvas = remember(screen) { ArenaCanvas(screen) }
        val layout = canvas.layout
        val lean = remember(canvas) { ArenaTableLean(canvas) }
        LaunchedEffect(layout.landscape) { handSpread = false }
        // The safe area, measured from the board's own geometry (never read from the window in a layer): an inset box's place.
        Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).onGloballyPositioned { coordinates ->
            val position = coordinates.positionInParent()
            val size = coordinates.size
            val next = ArenaSafeArea(top = (position.y / density).dp, bottom = (screen.height - position.y / density - size.height / density).coerceAtLeast(0f).dp,
                leading = (position.x / density).dp, trailing = (screen.width - position.x / density - size.width / density).coerceAtLeast(0f).dp)
            if (next != safeArea) safeArea = next
        })
        CompositionLocalProvider(LocalArenaSafeArea provides safeArea, LocalArenaTableLean provides lean, LocalArenaBoard provides true,
            io.magicmobile.android.ui.LocalTavernBoard provides true, LocalCardFrames provides arenaFrames) {
            ArenaTableBackdrop(layout.landscape)
            // A tap on the empty table: drops a lifted card, then puts a raised hand down, then clears any selection.
            Box(Modifier.fillMaxSize().clearAndSetSemantics { }.clickable(remember { MutableInteractionSource() }, null) { tapTable() })

            // Lanes: each side the current reference game's way, sized by ArenaRowFit.
            val choice = ArenaLaneChoice(targetableIds, GameBoardInteractionState.boardChosenTargetIds(snapshot),
                CombatHighlightSet(host.combatSelection, snapshot.legalActions ?: emptyList(), snapshot.xmage?.combat ?: emptyList()).cardIds,
                snapshot.manaPayment?.active == true)
            val allBattlefield = snapshot.players.flatMap { it.zones.battlefield }
            val playerIDs = snapshot.players.map { it.playerId }.toSet()
            CompositionLocalProvider(LocalArenaPaying provides choice.paying) {
                for ((player, viewer) in listOf(opponent to false, human to true)) {
                    for (plan in ArenaLanePlanner.plans(player, viewer, allBattlefield, playerIDs, canvas, choice, arenaFrames)) key("${player.playerId}:${plan.title}") {
                        BattlefieldRow(plan.title, plan.cards, snapshot.legalActions ?: emptyList(), choice.targetableIds, choice.chosenIds, choice.highlights,
                            host.selection, plan.card.width, plan.card.height, plan.rect.width, host.runAction, host.submitTarget, host.handleCombatCardTap,
                            Modifier.place(plan.rect).arenaLean(lean, plan.rect), flipped = !viewer, adaptsToDensity = true, availableHeight = plan.rect.height,
                            allowsManaUndo = viewer, manaPaymentActive = choice.paying, alignment = plan.alignment, preferredRows = plan.rows)
                    }
                }
            }
            if (host.isOverPlayerDropZone) {
                // Over the table a carried card lights the table's edge, the reference's way: soft warm light, no box.
                val area = canvas.area(layout.dropArea)
                Box(Modifier.place(area).clearAndSetSemantics { }.graphicsLayer { compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.Offscreen }) {
                    Box(Modifier.fillMaxSize().blur(18.dp).border(16.dp, TavernPalette.ember.copy(alpha = 0.75f), RoundedCornerShape(34.dp)))
                    Box(Modifier.fillMaxSize().padding(6.dp).blur(3.dp).border(3.dp, rgb(1.0, 0.86, 0.6).copy(alpha = 0.35f), RoundedCornerShape(28.dp)))
                }
            }

            ArenaOpponentSeat(host, canvas, lean, playerTargetID(opponent.playerId), ::submitPlayerTarget, { playerCardID = it }, { cornerMenu = "game" })

            // The stack's top card on the right, under the opponent's piles.
            val top = snapshot.stackTopFirst.firstOrNull()
            if (top != null) key(top.id) {
                val rect = canvas.rect(layout.stack)
                LaunchedEffect(Unit) {
                    landedStackIDs = landedStackIDs + top.id
                    // An opponent's spell (not an ability) is revealed larger toward the middle for its first 1.3 s, then settles.
                    val controller = top.controllerId
                    if (BoardMotion.reduceMotion || ArenaTableRules.isAbility(top) || controller == null || snapshot.isViewer(controller)) return@LaunchedEffect
                    revealID = top.id
                    kotlinx.coroutines.delay(1300)
                    if (revealID == top.id) revealID = null
                }
                val revealing = revealID == top.id
                val reveal by animateFloatAsState(if (revealing) 1f else 0f, tween(300), label = "stackReveal")
                Box(Modifier.zIndex(30f).alpha(if (screenUp) 0f else 1f).place(rect).graphicsLayer {
                    val scale = 1 + 0.2f * reveal; scaleX = scale; scaleY = scale
                    translationX = -rect.width * 0.8f * reveal * density; translationY = rect.height * 0.14f * reveal * density
                }.cardBounds("arena.stack")) {
                    ArenaStackCard(top, snapshot.xmage?.stack?.size ?: snapshot.stackTopFirst.size, DpSize(rect.width.dp, rect.height.dp),
                        commander = ArenaTableRules.isCommanderSpell(top, snapshot), fallbackSource = ArenaTableRules.sourceCard(top, snapshot),
                        lands = top.id !in landedStackIDs || revealing, inspect = { host.selection.inspectedCard = it }, openStack = { host.setStackOpen(true) })
                }
            }

            // The caption over the midline: what the table wants now, kept left of the stack card while one is up.
            if (!screenUp) {
                val text = host.notice ?: ArenaCornerText.caption(snapshot, host.combatSelection)
                if (text != null) {
                    val center = if (layout.landscape) canvas.x(478f) else canvas.screen.width / 2
                    val width = canvas.screen.width * (if (layout.landscape) 0.6f else 0.9f)
                    val left = center - width / 2
                    val right = if (top == null) center + width / 2 else min(center + width / 2, canvas.rect(layout.stack).minX - canvas.length(10f))
                    ArenaPromptCaption(text, Modifier.zIndex(35f).centerAt((left + right) / 2, canvas.y(layout.captionY)).widthIn(max = max(0f, right - left).dp))
                }
                ArenaRevealedChips(snapshot, canvas, host.inspectBoardZone)
            }

            ArenaViewerSeat(host, canvas, lean, playerTargetID(human.playerId), ::submitPlayerTarget, { playerCardID = it })
            layout.railTop?.let { rail ->
                // The front rail drawn again over a resting hand, so the hand tucks behind the table's edge.
                ArenaFrontRail(canvas.y(rail), Modifier.zIndex(if (posture == ArenaHandPosture.RESTING) 60f else 40f))
            }

            // The hand: the opening hand's own screen shows these cards, so the fan waits behind it.
            if (!openingHand) {
                val handZ = if (posture == ArenaHandPosture.RAISED || posture == ArenaHandPosture.SPREAD || (liftedCardID != null && layout.railTop == null)) 68f else 50f
                val extra = if (snapshot.isViewer(human.playerId)) ArenaExtraHand.cards(human, snapshot.legalActions ?: emptyList()) else emptyList()
                ArenaHandFan(BoardOpponentFocus.seatHand(snapshot), extra, snapshot.legalActions ?: emptyList(), host.pendingCardInstanceId, canvas, posture,
                    host.selection, host.setInteractionMode, host.setOverPlayerDropZone, liftedCardID, { liftedCardID = it },
                    hiddenCount = if (snapshot.isViewer(human.playerId)) null else human.zones.visibleHandCount,
                    raise = { handOpen = true }, lower = { handOpen = false; handSpread = false }, onDropFeedback = host.onInteractionFeedback,
                    onActionChoice = { actions, message -> host.setDragActionChoice(DragActionChoice(message, actions)) }, runAction = host.runAction,
                    modifier = Modifier.zIndex(handZ))
                // Portrait: the tab at the hand's left lays every card out whole (▲), and tucks them again (▼).
                val handCount = BoardOpponentFocus.seatHand(snapshot).size
                if (layout.hand.spreadBottom != null && !screenUp && !snapshot.isSpectating && handCount > 0 &&
                    (handPosture(spread = true) == ArenaHandPosture.SPREAD || posture == ArenaHandPosture.SPREAD)) {
                    val spread = posture == ArenaHandPosture.SPREAD
                    val gridTop = ArenaHandFanLayout.spread(handCount + extra.size, layout.hand)?.top ?: 700f
                    val center = canvas.point(BoardPoint(22f, if (spread) gridTop - 6 else 740f))
                    Box(Modifier.zIndex(69f).centerAt(center.x, center.y).size(44.dp).clickable {
                        handSpread = !spread; liftedCardID = null; GameAudio.play(GameSound.CARD_PICKUP); haptic()
                    }.semantics { contentDescription = if (spread) "Tuck your hand" else "Spread your hand"; testTag = "arena.hand.spread" },
                        contentAlignment = Alignment.Center) {
                        Box(Modifier.size(34.dp).glow(Color.Black.copy(alpha = 0.55f), 3.dp, 17.dp)
                            .background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)), CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape),
                            contentAlignment = Alignment.Center) { SfImage(if (spread) "chevron.down" else "chevron.up", ArenaPalette.gold, 14.dp) }
                    }
                }
            }

            // The corner: the amount pill for a number, else the phase strip and plaques.
            if (amountPrompt != null) key("${amountPrompt.id}:${amountPrompt.messageId}") {
                val setup = ArenaTableRules.amountSetup(amountPrompt, snapshot)
                val primary = canvas.rect(layout.primary); val secondary = canvas.rect(layout.secondary)
                val back = CompactPromptPopup.compactLegalPromptActions(snapshot).firstOrNull { it.type != "choose_amount" }
                ArenaAmountPill(setup.label, setup.range, setup.initial, host.pendingActionId != null, { value ->
                    if (host.pendingActionId == null) UniversalPromptResponseCommandBuilder.command(snapshot.id, snapshot.bridgeRevision, amountPrompt,
                        PromptCommandBuilder.amountCommandType(amountPrompt.responseCommand?.type), amountPrompt.responseCommand?.promptId ?: amountPrompt.id,
                        amountPrompt.playerId, amount = value, amounts = listOf(value))?.let { command ->
                        haptic(); host.runCommand(command, "Choose $value", "${amountPrompt.id}-amount-$value")
                    }
                }, Modifier.zIndex(75f).centerAt(primary.midX.coerceIn(142f, max(142f, canvas.screen.width - 142f)), secondary.midY + if (back == null) 0f else 24f),
                    back?.let { action -> action.compactPromptTitle to { host.runAction(action) } })
            } else if (!snapshot.isSpectating && !openingHand && !screenUp) {
                ArenaControls(host, canvas, buttonPlan(), Modifier.zIndex(if (controlsOnTop || posture != ArenaHandPosture.RAISED) 70f else 45f),
                    { showPhaseStops = true }, { cornerMenu = "pass" })
            }

            // Arrows and effects: drawn layers only, hidden from TalkBack and touches.
            ArenaDrawnLayers(host, canvas, revealID, show = host.selection.inspectedCard == null && playerCardID == null && !screenUp, Modifier.zIndex(85f))

            // Overlays: the corner's menus, a player's card, the prompt pop-up, the zone and card inspectors.
            Box(Modifier.fillMaxSize().zIndex(90f)) {
                val promptWidth = min(max(canvas.screen.width * (if (layout.landscape) 0.34f else 0.86f), 260f), 360f)
                val promptCenter = BoardPoint(if (layout.landscape) canvas.x(478f) else canvas.screen.width / 2, canvas.y(if (layout.landscape) 196f else 446f))
                cornerMenu?.let { menu ->
                    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.25f)).clearAndSetSemantics { }
                        .clickable(remember { MutableInteractionSource() }, null) { cornerMenu = null })
                    val items = if (menu == "game") arenaGameMenuItems(snapshot, turnControl, host, { host.setStackOpen(true) }, { showPhaseStops = true })
                        else turnControl?.let(::arenaPassAheadItems) ?: emptyList()
                    val gear = canvas.point(layout.menu)
                    val modifier = if (menu == "game") Modifier.align(Alignment.TopEnd).padding(top = (gear.y + 26).dp, end = max(12f, canvas.screen.width - gear.x - 22).dp)
                        else Modifier.align(Alignment.BottomEnd).padding(bottom = (canvas.screen.height - canvas.y(if (layout.landscape) 326f else 628f)).dp, end = 14.dp)
                    ArenaMenuCard(items, { cornerMenu = null }, modifier)
                }
                playerCardID?.let { id -> snapshot.players.firstOrNull { it.playerId == id } }?.let { player ->
                    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)).clearAndSetSemantics { }
                        .clickable(remember { MutableInteractionSource() }, null) { playerCardID = null })
                    val viewer = snapshot.isViewer(player.playerId)
                    val medallion = canvas.point(if (viewer) layout.viewerMedallion else layout.opponentMedallion)
                    val center = ArenaTableRules.playerCardCenter(medallion, viewer, layout.landscape, canvas.screen)
                    ArenaPlayerCard(player, snapshot, host.pendingActionId,
                        Modifier.centerAt(center.x, center.y).heightIn(max = (canvas.screen.height - 24).dp),
                        opponents = if (viewer) emptyList() else BoardOpponentFocus.opponents(snapshot),
                        swap = { id -> host.selectOpponent(id); playerCardID = id },
                        open = { reference -> playerCardID = null; host.inspectBoardZone(reference) }, close = { playerCardID = null })
                }
                val pending = host.pendingActionId != null
                val inspect: (ZoneCard) -> Unit = { host.selection.inspectedCard = it }
                abilityPrompt?.let { ability -> key("${ability.prompt.id}:${ability.prompt.messageId}") {
                    // A choice XMage lets you back out of keeps its Cancel inside the browser (the corner is hidden behind it).
                    val back = CompactPromptPopup.compactLegalPromptActions(snapshot).firstOrNull { it.type != "choose_ability" }
                    ArenaAbilityBrowser(ability.prompt, ability.prompt.abilities ?: emptyList(), ability.ordering, pending,
                        canRemember = ability.ordering && "rememberTriggerFirst" in answerActions.supported,
                        cancel = back?.let { action -> ArenaAnswer(action.id, action.compactPromptTitle) { host.runAction(action) } },
                        choose = { chooseAbility(it, ability.prompt, false) },
                        order = { resolveOrder, remember -> orderTriggers(resolveOrder, remember, ability.prompt) }, inspect = inspect)
                } }
                modePrompt?.let { modes -> key("${modes.id}:${modes.messageId}") {
                    ArenaModeBrowser(ArenaScreens.modeTitle(modes), ArenaScreens.modeDetail(modes), ArenaScreens.modeSource(modes, snapshot), modes.modes ?: emptyList(),
                        pending, promptAnswers(setOf("choose_mode")), choose = { mode ->
                            answer(modes, PromptCommandBuilder.idCommandType(modes.responseCommand?.type, "choose_mode"), "Choose mode", "${modes.id}-${mode.id}", listOf(mode.id))
                        }, inspect = inspect)
                } }
                choicePrompt?.let { choice -> key("${choice.id}:${choice.messageId}") {
                    val lines = PromptDisplayText.clean(choice.message).split("\n")
                    ArenaChoiceBrowser(lines.firstOrNull()?.ifEmpty { null } ?: "Make a choice", lines.getOrNull(1), ArenaScreens.choiceOptions(choice, snapshot),
                        snapshot.stackTopFirst.firstOrNull(), pending, promptAnswers(setOf("resolve_choice")), choose = { option, remember ->
                            val id = if (remember) option.rememberID ?: option.id else option.id
                            answer(choice, PromptCommandBuilder.idCommandType(choice.responseCommand?.type, "resolve_choice"), PromptDisplayText.clean(option.label),
                                "${choice.id}-$id", listOf(id))
                        }, inspect = inspect)
                } }
                playerPrompt?.let { players -> key("${players.prompt.id}:${players.prompt.messageId}") {
                    ArenaPlayerChoice(ArenaScreens.playerChoiceTitle(players.prompt.message), players.seats, pending,
                        promptAnswers(setOf("choose_player", "choose_target")), choose = { seat ->
                            answer(players.prompt, players.type, "Choose ${seat.name}", "${players.prompt.id}-${seat.id}", listOf(seat.id))
                        })
                } }
                splitPrompt?.let { split -> key("${split.id}:${split.messageId}") {
                    val setup = ArenaScreens.splitSetup(split, snapshot)
                    ArenaSplitBrowser(setup.title, setup.rows, split.multiAmounts ?: emptyList(), split.totalMin, split.totalMax, setup.source, setup.sourceCard,
                        pending, promptAnswers(setOf("choose_multi_amount")), submit = { values ->
                            answer(split, "choose_multi_amount", "Assign amounts", "${split.id}-choose-multi-amount", amounts = values)
                        }, inspect = inspect)
                } }
                pilePrompt?.let { piles -> key("${piles.id}:${piles.messageId}") {
                    ArenaPileBrowser("Choose a pile", PromptDisplayText.clean(piles.message), piles.piles ?: emptyList(), snapshot.stackTopFirst.firstOrNull(), pending,
                        choose = { pile -> answer(piles, "choose_pile", "Choose ${pile.label}", "${piles.id}-pile-${pile.id}", pile = pile.explicitPileNumber) },
                        inspect = inspect)
                } }
                if (host.isStackOpen && snapshot.stackTopFirst.isNotEmpty()) {
                    val resolve = GameplayAffordances.resolveStackCommand(snapshot, host.pendingActionId, answerActions.supported)
                    ArenaStackBrowser(snapshot, resolve?.let { command -> {
                        host.setStackOpen(false)
                        host.runCommand(command, "Resolve the stack", "resolve-stack-${command.promptId ?: ""}")
                    } }, turnControl?.let { control -> if (control.isAutoPassing) control.stop else null }, inspect) { host.setStackOpen(false) }
                }
                // Questions: the question stage for yours (a yes or no, a few choices), the pop-up for players the table doesn't show.
                val playerTargets = targetableIds.any { id -> snapshot.players.any { CombatPlayerIdentity.ids(it.playerId, snapshot).contains(id) } } &&
                    targetableIds.any { id -> id !in CombatPlayerIdentity.ids(human.playerId, snapshot) && id !in CombatPlayerIdentity.ids(opponent.playerId, snapshot) &&
                        snapshot.players.any { CombatPlayerIdentity.ids(it.playerId, snapshot).contains(id) } }
                if (!startingRollVisible && !openingHand && amountPrompt == null && abilityPrompt == null && modePrompt == null &&
                    !ArenaScreens.screenPrompt(snapshot, screenContext) && CompactPromptPopup.shouldShow(snapshot, host.pendingActionId) &&
                    !host.isPromptDetailOpen && (targetableIds.isEmpty() || playerTargets)) {
                    if (question != null) key(question.key) {
                        ArenaQuestionStage(question.title, question.stackObject, question.card, inspect) {
                            CompactPromptPopupView(snapshot, host.pendingActionId, host.runAction, host.runCommand, host.openPromptDetailSheet,
                                Modifier.widthIn(max = min(520f, canvas.screen.width - 48).dp), stage = true)
                        }
                    } else CompactPromptPopupView(snapshot, host.pendingActionId, host.runAction, host.runCommand, host.openPromptDetailSheet,
                        Modifier.requiredWidth(promptWidth.dp).centerAt(promptCenter.x, promptCenter.y))
                }
                host.dragActionChoice?.let { choice ->
                    DragActionChoicePopup(choice, host.pendingActionId, { action -> host.setDragActionChoice(null); host.selection.selectedCard = null; host.runAction(action) },
                        { host.setDragActionChoice(null); host.selection.selectedCard = null },
                        Modifier.requiredWidth(promptWidth.dp).centerAt(promptCenter.x, promptCenter.y))
                }
                host.inspectingZoneTitle?.let { title ->
                    ArenaZoneBrowser(host.inspectingZoneReference?.title(snapshot) ?: title, host.inspectingZoneReference?.cards(snapshot) ?: host.inspectingZoneCards,
                        snapshot.legalActions ?: emptyList(), host.pendingActionId, targetableIds, host.submitTarget, host.selection, host.runAction, host.closeZone)
                }
                host.selection.inspectedCard?.let { card ->
                    // The reference dims the table a little behind a card you're reading.
                    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)).clickable(remember { MutableInteractionSource() }, null) {
                        host.selection.inspectedCard = null })
                    val size = if (layout.landscape) {
                        val height = canvas.screen.height * 0.86f
                        BoardSize(min(canvas.screen.width * 0.82f, height / io.magicmobile.android.game.BattlefieldLayoutMetrics.magicCardHeightToWidth + 316), height)
                    } else BoardSize(canvas.screen.width - 32, canvas.screen.height * 0.78f)
                    val center = BoardPoint(if (layout.landscape) canvas.x(478f) else canvas.screen.width / 2,
                        canvas.screen.height * if (layout.landscape) 0.47f else 0.44f)
                    CardInspector(card, Modifier.place(BoardRect(center.x - size.width / 2, center.y - size.height / 2, size.width, size.height)))
                }
                if (snapshot.isWaitingOnAIOrStalled) {
                    AIWaitFallbackControls(snapshot, host.pendingActionId, host.liveUpdateStatus, host.aiWaitBeganAt, host.didRefresh, host.didReconnect, host.didDiagnose,
                        host.refreshGame, host.reconnectGame, Modifier.requiredWidth(min(canvas.screen.width - 28, 360f).dp).centerAt(canvas.screen.width / 2, canvas.screen.height / 2))
                }
            }
            // Panels on the table in glass, never a sheet: the phase stops.
            Box(Modifier.fillMaxSize().zIndex(95f)) {
                ArenaPanel(showPhaseStops, { showPhaseStops = false }, maxWidth = 560.dp, fitsContent = true) {
                    Column(Modifier.padding(16.dp)) { PhaseStopsGrid() }
                }
            }
        }
    }
}

/** The gear's menu, as an Arena menu card on the table. */
private fun arenaGameMenuItems(snapshot: GameSnapshot, control: NativeTurnControl?, host: ArenaBoardHost, openStack: () -> Unit,
                               openStops: () -> Unit): List<ArenaMenuItem> = buildList {
    add(ArenaMenuItem("log", "Game Log", symbol = "list.bullet.rectangle", action = host.openLog))
    if (snapshot.stackTopFirst.isNotEmpty()) add(ArenaMenuItem("stack", "Stack (${snapshot.stackTopFirst.size})", symbol = "square.stack.3d.up", action = openStack))
    add(ArenaMenuItem("stops", "Phase Stops", symbol = "pause.circle", action = openStops))
    control?.let {
        add(ArenaMenuItem("full-control", "Full control", if (it.isFullControl) "On for this turn" else "Stop at every priority this turn", "hand.raised.fill",
            lit = it.isFullControl, action = it.toggleFullControl))
    }
    if (snapshot.source == "xmage-ondevice") add(ArenaMenuItem("more", "More actions", symbol = "ellipsis", action = host.openPromptDetails))
    add(ArenaMenuItem("settings", "Game Settings", symbol = "gearshape.fill", action = host.openSettings))
}

/** Revealed and looked-at cards, as small glass pills beside the opponent's piles, clear of the creature rows. */
@Composable
private fun ArenaRevealedChips(snapshot: GameSnapshot, canvas: ArenaCanvas, inspect: (BoardZoneReference) -> Unit) {
    val revealed = snapshot.xmage?.revealed?.flatMap { it.cards } ?: emptyList()
    val lookedAt = snapshot.xmage?.lookedAt?.flatMap { it.cards } ?: emptyList()
    if (revealed.isEmpty() && lookedAt.isEmpty()) return
    @Composable
    fun pill(symbol: String, count: Int, label: String, open: () -> Unit) {
        Box(Modifier.size(width = 56.dp, height = 22.dp).clickable(onClick = open)
            .semantics { contentDescription = if (count == 1) "$label, 1 card" else "$label, $count cards"; testTag = "arena.chip.${label.lowercase().replace(" ", "")}" },
            contentAlignment = Alignment.Center) {
            Row(Modifier.height(22.dp).glow(Color.Black.copy(alpha = 0.5f), 3.dp, 11.dp)
                .background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)), CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape)
                .padding(horizontal = 9.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage(symbol, ArenaGlass.text, 11.dp)
                Text("$count", color = ArenaGlass.text, style = ArenaMenuStyle.font(12f, SfWeight.heavy).copy(fontFeatureSettings = "tnum"))
            }
        }
    }
    val content: @Composable () -> Unit = {
        if (revealed.isNotEmpty()) pill("eye.fill", revealed.size, "Revealed") { inspect(BoardZoneReference.Collection(BoardZoneReference.NamedKind.REVEALED)) }
        if (lookedAt.isNotEmpty()) pill("eye", lookedAt.size, "Looked at") { inspect(BoardZoneReference.Collection(BoardZoneReference.NamedKind.LOOKED_AT)) }
    }
    if (canvas.layout.landscape) {
        // One over the other in the gap between the opponent's graveyard and the gear.
        Column(Modifier.zIndex(36f).centerAt(canvas.x(818f), canvas.y(12f) + (if (revealed.isEmpty() || lookedAt.isEmpty()) 22f else 44f) / 2)) { content() }
    } else {
        val at = canvas.point(BoardPoint(122f, 74f))
        Row(Modifier.zIndex(36f).centerAt(at.x, at.y), horizontalArrangement = Arrangement.spacedBy(6.dp)) { content() }
    }
}

/** Commander damage, poison, the monarch… curve around a medallion, toward the table (TavernEffectOrbitBadges). */
@Composable
private fun ArenaEffectOrbit(summary: PlayerStatusSummary, center: BoardPoint, radius: Float, bearing: Float, limit: Int) {
    val (shown, more) = TavernEffectOrbit.shown(summary, limit)
    if (shown.isEmpty()) return
    val size = (radius * TavernEffectOrbit.BADGE_SHARE).dp
    val slots = TavernEffectOrbit.offsets(shown.size + if (more > 0) 1 else 0, radius, bearing)
    shown.forEachIndexed { index, badge ->
        Box(Modifier.centerAt(center.x + slots[index].x, center.y + slots[index].y).clearAndSetSemantics { }) { TavernStatusBadge(badge, size) }
    }
    if (more > 0) {
        val slot = slots.last()
        Box(Modifier.centerAt(center.x + slot.x, center.y + slot.y).requiredSize(size * 0.8f).tavernCoinBack().clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
            Text("+$more", color = TavernPalette.parchment, style = sf(size.value * 0.4f, SfWeight.black, io.magicmobile.android.ui.SfDesign.SERIF))
        }
    }
}

/** The opponent's seat: their hand of backs, piles, exile, medallion, the effects orbit, "Thinking…" and the gear. */
@Composable
private fun ArenaOpponentSeat(host: ArenaBoardHost, canvas: ArenaCanvas, lean: ArenaTableLean, targetID: String?, submitPlayerTarget: (String) -> Unit,
                              openPlayerCard: (String) -> Unit, openMenu: () -> Unit) {
    val snapshot = host.snapshot
    val opponent = host.opponent
    val layout = canvas.layout
    val name = snapshot.playerLabel(opponent.playerId)
    val pile = canvas.size(layout.opponentPile)
    val pileSize = DpSize(pile.width.dp, pile.height.dp)
    fun leanAt(point: BoardPoint): (Modifier) -> Modifier = { it.arenaLean(lean, BoardRect(point.x - pile.width / 2, point.y - pile.height / 2, pile.width, pile.height)) }
    val handCard = canvas.size(layout.opponentHandCard)
    val handAt = canvas.point(layout.opponentHand)
    ArenaOpponentHandFan(opponent.zones.visibleHandCount, DpSize(handCard.width.dp, handCard.height.dp), canvas.length(layout.opponentHandPitch),
        Modifier.centerAt(handAt.x, handAt.y))
    val library = canvas.point(layout.opponentLibrary)
    Box(Modifier.centerAt(library.x, library.y)) {
        ArenaDeckPile(opponent.zones.visibleLibraryCount, pileSize, "$name's library, ${opponent.zones.visibleLibraryCount} cards", lean = leanAt(library))
        // A revealed top card (Courser of Kruphix, Future Sight…) lies face up on the deck.
        ArenaTableRules.revealedTop(opponent)?.let { top ->
            TopOfLibraryCard(top, "$name's", Modifier.align(Alignment.Center), height = pile.height.dp) { host.viewZone("Top of $name's library", listOf(top)) }
        }
    }
    val graveyard = canvas.point(layout.opponentGraveyard)
    ArenaGraveyardPile(opponent.zones.graveyard, pileSize, "$name's graveyard", Modifier.centerAt(graveyard.x, graveyard.y), lean = leanAt(graveyard)) {
        host.inspectBoardZone(BoardZoneReference.Player(opponent.playerId, BoardZoneReference.PlayerZone.GRAVEYARD))
    }
    val medallion = canvas.point(layout.opponentMedallion)
    val diameter = canvas.length(layout.opponentMedallionDiameter)
    ArenaEffectOrbit(PlayerStatusSummary(opponent, snapshot), medallion, diameter / 2 + 14, if (layout.landscape) 90f else 45f, if (layout.landscape) 5 else 3)
    if (opponent.zones.exile.isNotEmpty()) {
        val exile = canvas.point(layout.opponentExile)
        ArenaGraveyardPile(opponent.zones.exile, pileSize, "$name's exile", Modifier.centerAt(exile.x, exile.y), exile = true, lean = leanAt(exile)) {
            host.inspectBoardZone(BoardZoneReference.Player(opponent.playerId, BoardZoneReference.PlayerZone.EXILE))
        }
    }
    // The medallion: attack this player, choose them as a target, or open their card on the table.
    val defenders = CombatHighlightSet(host.combatSelection, snapshot.legalActions ?: emptyList(), snapshot.xmage?.combat ?: emptyList()).defenderIds
    val attackID = CombatPlayerIdentity.targetID(opponent.playerId, snapshot, defenders)?.takeIf { host.combatSelection.selectedAttackerIds.isNotEmpty() }
    val label = if (opponent.isOut) "$name, out of the game" else "$name, ${opponent.life} life"
    Box(Modifier.centerAt(medallion.x, medallion.y).size((diameter + 8).dp).clickable {
        when {
            attackID != null -> host.submitAttackers(attackID)
            targetID != null -> submitPlayerTarget(targetID)
            else -> openPlayerCard(opponent.playerId)
        }
    }.semantics { contentDescription = label; testTag = "board.zones.${opponent.playerId}" }, contentAlignment = Alignment.Center) {
        Box(Modifier.cardBounds(TavernSeatAnchor.top)) {
            ArenaHeroMedallion(opponent, diameter.dp, active = snapshot.activePlayerId == opponent.playerId,
                glow = if (attackID != null) ArenaPalette.attackGlow else if (targetID != null) ArenaPalette.targetGlow else null)
        }
        LocalTurnClock.current?.let { feed -> opponent.displayName?.let { TurnClockRing(feed, it, (diameter * 1.08f).dp) } }
        LocalEmoteCenter.current?.let { center ->
            OpponentEmoteSlot(center, snapshot, opponent.playerId, Modifier.align(Alignment.BottomCenter).offset(y = (diameter * 0.9f).dp).wrapContentSize(unbounded = true))
        }
    }
    if (snapshot.thinkingPlayerID == opponent.playerId) {
        val radius = diameter / 2
        Text("Thinking…", Modifier.centerAt(medallion.x + if (layout.landscape) radius + 40 else 0f, medallion.y + if (layout.landscape) 0f else radius + 12)
            .semantics { contentDescription = "$name is thinking" }, color = TavernPalette.parchment.copy(alpha = 0.85f),
            style = ArenaMenuStyle.font(11f, SfWeight.semibold).copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic).let {
                it.copy(shadow = androidx.compose.ui.graphics.Shadow(Color.Black, Offset.Zero, 4f)) })
    }
    // Arena's gear: a light symbol on a dark glass disc, no brass coin.
    val gear = canvas.point(layout.menu)
    Box(Modifier.centerAt(gear.x, gear.y).size(44.dp).clickable { GameAudio.play(GameSound.UI_OPEN); openMenu() }
        .semantics { contentDescription = "Game menu"; testTag = "board.arena.menu" }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(30.dp).glow(Color.Black.copy(alpha = 0.5f), 2.dp, 15.dp)
            .background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)), CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape),
            contentAlignment = Alignment.Center) { SfImage("gearshape.fill", ArenaGlass.text, 14.dp) }
    }
}

/** Your seat: piles, exile, your medallion with its glance, quick chat and floating mana. */
@Composable
private fun ArenaViewerSeat(host: ArenaBoardHost, canvas: ArenaCanvas, lean: ArenaTableLean, targetID: String?, submitPlayerTarget: (String) -> Unit,
                            openPlayerCard: (String) -> Unit) {
    val snapshot = host.snapshot
    val human = host.human
    val layout = canvas.layout
    val pile = canvas.size(layout.viewerPile)
    val pileSize = DpSize(pile.width.dp, pile.height.dp)
    fun leanAt(point: BoardPoint): (Modifier) -> Modifier = { it.arenaLean(lean, BoardRect(point.x - pile.width / 2, point.y - pile.height / 2, pile.width, pile.height)) }
    val castable = GameplayAffordances.castableZones(human, snapshot, host.pendingActionId)
    val library = canvas.point(layout.viewerLibrary)
    // On the portrait rail, over the rail drawn across a resting hand.
    Box(Modifier.zIndex(64f).centerAt(library.x, library.y)) {
        ArenaDeckPile(human.zones.visibleLibraryCount, pileSize, "Your library, ${human.zones.visibleLibraryCount} cards", lean = leanAt(library))
        ArenaTableRules.revealedTop(human)?.let { top ->
            TopOfLibraryCard(top, "your", Modifier.align(Alignment.Center), playable = BoardZoneReference.PlayerZone.LIBRARY in castable, height = pile.height.dp) {
                host.viewZone("Top of your library", listOf(top))
            }
        }
    }
    val graveyard = canvas.point(layout.viewerGraveyard)
    ArenaGraveyardPile(human.zones.graveyard, pileSize, "Your graveyard", Modifier.zIndex(64f).centerAt(graveyard.x, graveyard.y), lean = leanAt(graveyard)) {
        host.inspectBoardZone(BoardZoneReference.Player(human.playerId, BoardZoneReference.PlayerZone.GRAVEYARD))
    }
    if (human.zones.exile.isNotEmpty()) {
        val exile = canvas.point(layout.viewerExile)
        ArenaGraveyardPile(human.zones.exile, pileSize, "Your exile", Modifier.zIndex(64f).centerAt(exile.x, exile.y), exile = true, lean = leanAt(exile)) {
            host.inspectBoardZone(BoardZoneReference.Player(human.playerId, BoardZoneReference.PlayerZone.EXILE))
        }
    }
    val medallion = canvas.point(layout.viewerMedallion)
    val diameter = canvas.length(layout.viewerMedallionDiameter)
    val pool = human.manaPool
    val floating = pool != null && pool.W + pool.U + pool.B + pool.R + pool.G + pool.C > 0
    Box(Modifier.zIndex(65f).centerAt(medallion.x, medallion.y).size((diameter + 8).dp).clickable {
        if (targetID != null) submitPlayerTarget(targetID) else openPlayerCard(human.playerId)
    }.semantics { contentDescription = "Your life: ${human.life}" + GameplayAffordances.castableDescription(castable); testTag = "board.lifeOrb" },
        contentAlignment = Alignment.Center) {
        Box(Modifier.cardBounds(TavernSeatAnchor.bottom)) {
            ArenaHeroMedallion(human, diameter.dp, active = snapshot.isViewer(snapshot.activePlayerId), glow = if (targetID != null) ArenaPalette.targetGlow else null,
                commanderReady = castable.isNotEmpty())
        }
        LocalTurnClock.current?.let { TurnClockRing(it, null, (diameter * 1.08f).dp) }
        // Poison and commander damage at a glance; the player's card lists every status.
        TavernStatusGlance(PlayerStatusSummary(human, snapshot), Modifier.align(Alignment.BottomEnd).offset((diameter * 0.3f).dp, (diameter * 0.05f).dp).wrapContentSize(unbounded = true))
        LocalEmoteCenter.current?.let { center ->
            // Above the floating mana when there is some (it sits right over the medallion).
            Row(Modifier.align(Alignment.TopCenter).offset(y = (-diameter * 0.85f - if (floating) 30f else 0f).dp).wrapContentSize(unbounded = true),
                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                EmoteBubbleSlot(center, human.playerId)
                TableChatButton(center)
            }
        }
    }
    if (floating) {
        // The reference's floating mana: plain symbols right above your avatar; a symbol takes a tap while you pay.
        ArenaFloatingMana(pool, GameplayAffordances.floatingManaSymbols(host.snapshot, host.pendingActionId), { symbol ->
            if (host.pendingActionId == null) GameplayAffordances.floatingManaCommand(symbol, snapshot)?.let { command ->
                host.runCommand(command, "Spend floating {$symbol}", "floating-${snapshot.promptEnvelopeV2?.id ?: ""}-$symbol")
            }
        }, Modifier.zIndex(67f).centerAt(medallion.x + if (layout.landscape) 0f else 6f, medallion.y - diameter / 2 - if (layout.landscape) 13f else 15f))
    }
}

/** The corner: the phase strip over the plaques, the day/night and storm hints, the pass-ahead pill and Undo. */
@Composable
private fun ArenaControls(host: ArenaBoardHost, canvas: ArenaCanvas, plan: ArenaButtonPlan, modifier: Modifier, openPhaseStops: () -> Unit, openPassMenu: () -> Unit) {
    val snapshot = host.snapshot
    val layout = canvas.layout
    val turnControl = LocalNativeTurnControl.current
    var swallowNextPass by remember { mutableStateOf(false) }
    val primaryRect = canvas.rect(layout.primary); val secondaryRect = canvas.rect(layout.secondary)
    val stripWidth = canvas.length(layout.phaseStripX.endInclusive - layout.phaseStripX.start)
    val stripX = canvas.x((layout.phaseStripX.start + layout.phaseStripX.endInclusive) / 2)
    val stripY = canvas.y(if (plan.secondary == null) layout.phaseStripY else layout.phaseStripRaisedY)
    Box(modifier.fillMaxSize()) {
        ArenaPhaseStrip(snapshot.step ?: snapshot.phase, snapshot.isViewer(snapshot.activePlayerId), stripWidth.dp,
            Modifier.centerAt(stripX, stripY).clickable(remember { MutableInteractionSource() }, null) { openPhaseStops() },
            canvas.length(if (layout.landscape) 19f else 18f).dp)
        TavernTableHints(snapshot.dayNight, snapshot.stormCount, Modifier.centerAt(stripX, stripY - canvas.y(18f)))
        @Composable
        fun plaque(choice: ArenaButtonPlan.Choice, rect: BoardRect, fontSize: Float, primary: Boolean) {
            key("${choice.title}|${snapshot.promptEnvelopeV2?.id ?: ""}|${snapshot.promptEnvelopeV2?.messageId ?: -1}") {
                val place = Modifier.centerAt(rect.midX, rect.midY).requiredSize(rect.width.dp, max(44f, rect.height + 8).dp)
                val button: @Composable (Modifier) -> Unit = { m ->
                    ArenaPlaqueButton(choice.title, { if (swallowNextPass) swallowNextPass = false else choice.action() }, m, choice.subtitle, choice.kind,
                        canvas.length(fontSize), choice.enabled, if (primary) "board.action.primary" else null)
                }
                if (primary) FullControlHold(turnControl, tavern = false, modifier = place) { button(Modifier.fillMaxSize()) } else button(place)
            }
        }
        plan.secondary?.let { plaque(it, secondaryRect, if (layout.landscape) 17f else 16f, false) }
        plan.primary?.let { plaque(it, primaryRect, if (layout.landscape) 19f else 18f, true) }
        val passAhead = canvas.rect(layout.passAhead)
        ArenaPassAheadPill(openPassMenu, Modifier.place(passAhead))
        ManaPaymentTrayRules.manaUndoActions(snapshot).firstOrNull { it.type == "undo_mana" }?.let { undo ->
            ArenaPill({ host.runAction(undo) }, Modifier.place(canvas.rect(layout.undo)), enabled = host.pendingActionId == null, label = "Undo mana") {
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Undo", color = androidx.compose.material3.LocalContentColor.current, style = ArenaMenuStyle.font(13f, SfWeight.heavy))
                    SfImage("arrow.uturn.backward", androidx.compose.material3.LocalContentColor.current, 10.dp)
                }
            }
        }
    }
}

/** Arrows and effects: the combat arcs, the stack's arc and reticles, and the board's effects. */
@Composable
private fun ArenaDrawnLayers(host: ArenaBoardHost, canvas: ArenaCanvas, revealID: String?, show: Boolean, modifier: Modifier) {
    val snapshot = host.snapshot
    val bounds = LocalCardBounds.current?.bounds ?: emptyMap()
    Box(modifier.fillMaxSize().clearAndSetSemantics { }) {
        if (show) {
            ArenaCombatArrows(snapshot, host.combatPreviewArrows, bounds, host.opponent.playerId)
            // The top of the stack points at its targets, a spell as well as an ability, with a reticle on each target while it
            // waits; an ability without targets points back at its source, as in the reference.
            val top = snapshot.stackTopFirst.firstOrNull()
            val from = bounds["arena.stack"]
            if (top != null && from != null && revealID != top.id) key(top.id) {
                val ability = ArenaTableRules.isAbility(top)
                val targetIds = top.targetIds ?: emptyList()
                val ids = targetIds.ifEmpty { if (ability) listOfNotNull(top.sourceInstanceId) else emptyList() }
                val targets = ids.mapNotNull { id ->
                    bounds[id] ?: when {
                        id in CombatPlayerIdentity.ids(host.human.playerId, snapshot) -> bounds[TavernSeatAnchor.bottom]
                        id in CombatPlayerIdentity.ids(host.opponent.playerId, snapshot) -> bounds[TavernSeatAnchor.top]
                        else -> null
                    }
                }
                // Yours in the playable cyan, the opponent's in red.
                val theirs = top.controllerId?.let { !snapshot.isViewer(it) } ?: false
                val color = if (theirs) rgb(1.0, 0.38, 0.27) else rgb(0.55, 0.85, 1.0)
                if (targets.isNotEmpty()) ArenaStackArc(from, targets, color)
                if (targetIds.isNotEmpty()) targets.forEach { ArenaTargetReticle(it, color) }
            }
        }
        val layout = canvas.layout
        val stack = canvas.rect(layout.stack)
        val viewerSeat = bounds[TavernSeatAnchor.bottom]
        val opponentSeat = bounds[TavernSeatAnchor.top]
        val handPoint = BoardPoint(canvas.x(layout.hand.centerX), canvas.y(layout.hand.upY))
        BoardFXOverlay(host.boardFX.active, host.boardFX.subjects, bounds, BoardFXAnchors(snapshot.viewerID,
            viewerPoint = viewerSeat?.let { BoardPoint(it.midX, it.minY - 8) } ?: canvas.point(layout.viewerMedallion),
            opponentPoint = opponentSeat?.let { BoardPoint(it.midX, it.maxY + 10) } ?: canvas.point(layout.opponentMedallion),
            stackPoint = BoardPoint(stack.midX, stack.midY), viewerHandPoint = handPoint,
            opponentHandPoint = canvas.point(layout.opponentHand),
            playerLabels = snapshot.players.associate { it.playerId to snapshot.playerLabel(it.playerId) }),
            host.boardFXClock, host.pruneFX)
    }
}
