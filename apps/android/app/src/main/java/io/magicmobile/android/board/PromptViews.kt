package io.magicmobile.android.board

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.CombatSelectionState
import io.magicmobile.android.game.CompactPromptPopup
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GuidanceTone
import io.magicmobile.android.game.InlinePaymentPromptState
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.LegalActionDisplay
import io.magicmobile.android.game.MobilePromptKind
import io.magicmobile.android.game.MobilePromptPresentation
import io.magicmobile.android.game.PromptCommandBuilder
import io.magicmobile.android.game.PromptDisplayText
import io.magicmobile.android.game.PromptEnvelope
import io.magicmobile.android.game.PromptEnvelopeV2
import io.magicmobile.android.game.PromptGuidance
import io.magicmobile.android.game.ChoicePrompt
import io.magicmobile.android.game.UniversalPromptResponseCommandBuilder
import io.magicmobile.android.game.XmageResponseCommand
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.sf

val GuidanceTone.color: Color get() = when (this) {
    GuidanceTone.GOLD -> MagicPalette.antiqueGold
    GuidanceTone.OXBLOOD -> MagicPalette.oxblood
    GuidanceTone.AMBER -> MagicPalette.warningAmber
    GuidanceTone.EMERALD -> MagicPalette.emerald
    GuidanceTone.ARCANE -> MagicPalette.arcaneBlue
}

/** The center-strip guidance: whose decision it is and what to do. */
@Composable
fun PromptPill(snapshot: GameSnapshot, modifier: Modifier = Modifier, combatSelection: CombatSelectionState = CombatSelectionState()) {
    val waitingOnHuman = snapshot.isViewer(snapshot.waitingOnPlayerId) ||
        (snapshot.waitingOnPlayerId == null && snapshot.isViewer(snapshot.priorityPlayerId)) ||
        CompactPromptPopup.compactLegalPromptActions(snapshot).isNotEmpty()
    val guidance = PromptGuidance(snapshot, waitingOnHuman, combatSelection)
    val color = guidance.tone.color
    Row(modifier.fillMaxWidth().background(MagicPalette.iron.copy(alpha = 0.74f), RoundedCornerShape(8.dp))
        .border(1.5.dp, color.copy(alpha = if (guidance.isUrgent) 0.72f else 0.5f), RoundedCornerShape(8.dp))
        .padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).glow(color.copy(alpha = 0.8f), 5.dp, 4.dp).background(color, CircleShape))
        Text(guidance.label, Modifier.background(color.copy(alpha = 0.12f), RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp),
            color = color, style = sf(9f, SfWeight.black), maxLines = 1)
        FitText(guidance.message, sf(11f, SfWeight.black), Modifier.weight(1f), color = Color.White, maxLines = 2, minimumScale = 0.75f)
    }
}

/** The mana-payment rules behind ManaPaymentTray (its static helpers in ContentView.swift). */
object ManaPaymentTrayRules {
    fun manaUndoActions(snapshot: GameSnapshot): List<LegalAction> {
        val undoTypes = setOf("undo_mana", "cancel_payment", "cancel_mana_payment")
        return (snapshot.legalActions ?: emptyList()).filter { action ->
            if (action.type in undoTypes) return@filter true
            val prompt = snapshot.promptEnvelopeV2
            if (snapshot.source != "xmage-ondevice" || prompt == null || !CompactPromptPopup.isManaPaymentPrompt(prompt)) return@filter false
            action.type == "resolve_choice" && action.choiceIds == listOf("special") &&
                action.promptId == (prompt.responseCommand?.promptId ?: prompt.id) &&
                action.messageId == (prompt.responseCommand?.messageId ?: prompt.messageId) && action.playerId == prompt.playerId
        }
    }

    fun compactPaymentActions(snapshot: GameSnapshot): List<LegalAction> =
        manaUndoActions(snapshot).take(if (snapshot.source == "xmage-ondevice") 2 else 1)

    fun paymentCancelTitle(action: LegalAction): String = when {
        action.type == "resolve_choice" && action.choiceIds == listOf("special") -> action.label
        action.type == "cancel_payment" || action.type == "cancel_mana_payment" -> "Cancel cast"
        action.type == "undo_mana" -> "Undo mana"
        else -> action.shortLabel ?: LegalActionDisplay.displayLabel(action)
    }

    fun manaUndoUnavailableText(snapshot: GameSnapshot): String? =
        if (hasFloatingMana(snapshot) && manaUndoActions(snapshot).isEmpty()) "XMage has not exposed mana undo" else null

    private fun hasFloatingMana(snapshot: GameSnapshot): Boolean {
        val pool = snapshot.human?.manaPool ?: return false
        return pool.W + pool.U + pool.B + pool.R + pool.G + pool.C > 0
    }

    fun canPay(symbol: String, snapshot: GameSnapshot): Boolean {
        if (manaPoolValue(symbol, snapshot) > 0) return true
        return symbol == "C" && listOf("W", "U", "B", "R", "G", "C").any { manaPoolValue(it, snapshot) > 0 }
    }

    private fun manaPoolValue(symbol: String, snapshot: GameSnapshot): Int {
        val pool = snapshot.human?.manaPool
        return when (symbol) { "W" -> pool?.W; "U" -> pool?.U; "B" -> pool?.B; "R" -> pool?.R; "G" -> pool?.G; "C" -> pool?.C; else -> 0 } ?: 0
    }

    private val requiredPattern = Regex("\\{([0-9WUBRGC/XP]+)\\}")
    fun requiredManaSymbols(snapshot: GameSnapshot, prompt: PromptEnvelopeV2): List<String> =
        requiredPattern.findAll(snapshot.manaPayment?.remainingText ?: prompt.message).map { it.groupValues[1] }.toList()

    fun requiredManaText(prompt: PromptEnvelopeV2): String {
        val message = prompt.message.trim()
        return if (message.isEmpty()) "Tap for mana" else if (message.length > 28) "Pay mana" else message
    }

    fun hasBattlefieldManaSources(snapshot: GameSnapshot): Boolean =
        (snapshot.legalActions ?: emptyList()).any { it.type == "make_mana" && (it.sourceInstanceId != null || it.cardInstanceId != null) }
}

/** Remaining cost pips and floating-mana buttons for the payment prompt XMage is asking. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ManaPaymentTray(snapshot: GameSnapshot, prompt: PromptEnvelopeV2, pendingActionId: String?, runAction: (LegalAction) -> Unit,
                    runCommand: (GameCommand, String, String) -> Unit, modifier: Modifier = Modifier, compact: Boolean = false) {
    val remaining = snapshot.manaPayment?.remaining
    val hasSources = ManaPaymentTrayRules.hasBattlefieldManaSources(snapshot)

    fun canPay(symbol: String): Boolean =
        if (snapshot.source == "xmage-ondevice") (prompt.manaChoices?.firstOrNull { (it.manaType ?: it.id) == symbol }?.amount ?: 0) > 0
        else ManaPaymentTrayRules.canPay(symbol, snapshot)
    fun exposes(symbol: String): Boolean = prompt.manaChoices?.any { (it.manaType ?: it.id) == symbol } == true

    @Composable
    fun manaButton(symbol: String, label: String, pendingId: String, size: Float) {
        val type = if (snapshot.source == "xmage-ondevice") "play_mana" else prompt.responseCommand?.type ?: "play_mana"
        val command = UniversalPromptResponseCommandBuilder.command(snapshot.id, snapshot.bridgeRevision, snapshot.promptEnvelopeV2, type,
            prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, listOf(symbol), manaType = symbol)
        val enabled = pendingActionId == null && canPay(symbol) && exposes(symbol) && command != null
        PressableBox({ command?.let { runCommand(it, label, pendingId) } }, Modifier.defaultMinSize(44.dp, 44.dp).semantics { contentDescription = label },
            enabled = enabled) {
            ManaSymbolView(symbol, size.dp, Modifier.alpha(if (canPay(symbol) && exposes(symbol)) 1f else 0.42f))
        }
    }

    @Composable
    fun pipRow() {
        when {
            remaining != null && remaining.total > 0 -> Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                if (remaining.generic > 0) Box(Modifier.size(18.dp).background(Color.Gray.copy(alpha = 0.55f), CircleShape), contentAlignment = Alignment.Center) {
                    Text("${remaining.generic}", color = Color.White, style = sf(11f, SfWeight.black))
                }
                remaining.orderedColors.forEachIndexed { offset, (symbol, count) ->
                    repeat(count) { manaButton(symbol, "Pay {$symbol}", "${prompt.id}-pip-$symbol-$offset", 18f) }
                }
            }
            ManaPaymentTrayRules.requiredManaSymbols(snapshot, prompt).isNotEmpty() -> Row(Modifier.semantics {
                contentDescription = ManaPaymentTrayRules.requiredManaText(prompt) }, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for (symbol in ManaPaymentTrayRules.requiredManaSymbols(snapshot, prompt)) {
                    val amount = symbol.toIntOrNull()
                    if (amount != null) Box(Modifier.size(24.dp).background(Color.Gray, CircleShape), contentAlignment = Alignment.Center) {
                        Text("$amount", color = Color.White, style = SfText.caption(SfWeight.bold))
                    } else ManaSymbolView(symbol, 24.dp)
                }
            }
            else -> FitText(ManaPaymentTrayRules.requiredManaText(prompt), sf(9f, SfWeight.black), color = MagicPalette.antiqueGold, minimumScale = 0.65f)
        }
    }

    if (compact) {
        Row(modifier.height(44.dp), horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).defaultMinSize(48.dp, 44.dp).horizontalScroll(rememberScrollState())
                .semantics { contentDescription = "Remaining cost and mana choices; swipe to view" },
                horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                pipRow()
                val choices = prompt.manaChoices
                if (!choices.isNullOrEmpty()) {
                    Box(Modifier.width(1.dp).height(24.dp).background(Color.White.copy(alpha = 0.25f)))
                    Text("Use floating mana", color = MagicPalette.parchment, style = SfText.caption2(SfWeight.bold))
                    // Keep every supplied payment choice reachable while cancel stays fixed.
                    for (choice in choices) {
                        val symbol = choice.manaType ?: choice.id
                        manaButton(symbol, choice.label, "${prompt.id}-mana-choice-${choice.id}", 22f)
                    }
                } else {
                    FitText(if (hasSources) "Tap sources" else "Waiting for mana options", sf(9f, SfWeight.black),
                        color = if (hasSources) MagicPalette.parchment.copy(alpha = 0.78f) else MagicPalette.arcaneBlue, minimumScale = 0.72f)
                }
            }
            for (action in ManaPaymentTrayRules.compactPaymentActions(snapshot)) {
                Box(Modifier.alpha(if (pendingActionId != null) 0.5f else 1f)) {
                    GameIconButton(if (action.type == "resolve_choice") "sparkles" else "arrow.uturn.backward",
                        { if (pendingActionId == null) runAction(action) }, small = true, contentDescription = ManaPaymentTrayRules.paymentCancelTitle(action))
                }
            }
        }
    } else {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Pay cost", color = MagicPalette.antiqueGold, style = sf(9f, SfWeight.black)); pipRow()
            }
            val choices = prompt.manaChoices
            if (!choices.isNullOrEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Use floating mana", color = MagicPalette.parchment.copy(alpha = 0.72f), style = sf(8f, SfWeight.black))
                    for (choice in choices.take(6)) {
                        val symbol = choice.manaType ?: choice.id
                        manaButton(symbol, choice.label, "${prompt.id}-mana-choice-${choice.id}", 24f)
                    }
                }
            }
            val undo = ManaPaymentTrayRules.manaUndoActions(snapshot)
            if (undo.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (action in undo.take(2)) {
                        PanelActionButton({ runAction(action) }, Modifier.weight(1f), compact = true, enabled = pendingActionId == null) {
                            PromptButtonLabel(ManaPaymentTrayRules.paymentCancelTitle(action), systemImage = if (action.type == "resolve_choice") "sparkles" else "arrow.uturn.backward",
                                isPending = pendingActionId == action.id)
                        }
                    }
                }
            } else ManaPaymentTrayRules.manaUndoUnavailableText(snapshot)?.let {
                FitText(it, sf(8f, SfWeight.bold), color = MagicPalette.parchment.copy(alpha = 0.58f), minimumScale = 0.72f)
            }
            if (!hasSources && prompt.manaChoices.isNullOrEmpty()) {
                Text("Waiting for XMage mana options", color = MagicPalette.arcaneBlue, style = sf(10f, SfWeight.bold))
            }
        }
    }
}

/** The inline "PAY COST" strip in the center of the board. */
@Composable
fun InlinePaymentPromptBar(snapshot: GameSnapshot, pendingActionId: String?, runAction: (LegalAction) -> Unit,
                           runCommand: (GameCommand, String, String) -> Unit, openDetails: () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().background(MagicPalette.iron.copy(alpha = 0.78f), RoundedCornerShape(8.dp))
        .border(1.5.dp, MagicPalette.antiqueGold.copy(alpha = 0.72f), RoundedCornerShape(8.dp)).padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).glow(MagicPalette.antiqueGold.copy(alpha = 0.8f), 5.dp, 4.dp).background(MagicPalette.antiqueGold, CircleShape))
        Text("PAY COST", Modifier.background(MagicPalette.antiqueGold.copy(alpha = 0.12f), RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp),
            color = MagicPalette.antiqueGold, style = sf(9f, SfWeight.black))
        val prompt = InlinePaymentPromptState.paymentPrompt(snapshot)
        // SwiftUI splits the free width between the tray's scroll view and the trailing spacer.
        if (prompt != null) ManaPaymentTray(snapshot, prompt, pendingActionId, runAction, runCommand, Modifier.weight(1f), compact = true)
        else Text("Tap mana sources", color = Color.White, style = sf(11f, SfWeight.black))
        Spacer(Modifier.weight(1f))
        if (snapshot.source == "xmage-ondevice") {
            Box(Modifier.alpha(if (pendingActionId != null) 0.5f else 1f)) {
                GameIconButton("list.bullet.rectangle", { if (pendingActionId == null) openDetails() }, small = true, contentDescription = "Payment choices")
            }
        }
    }
}

/** The floating prompt card: the engine's question and its compact answers. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CompactPromptPopupView(snapshot: GameSnapshot, pendingActionId: String?, runAction: (LegalAction) -> Unit,
                           runCommand: (GameCommand, String, String) -> Unit, openDetails: () -> Unit, modifier: Modifier = Modifier) {
    val promptV2 = snapshot.promptEnvelopeV2
    val legalActions = snapshot.legalActions ?: emptyList()
    val compactPromptActions = CompactPromptPopup.compactLegalPromptActions(snapshot)
    val presentation = MobilePromptPresentation.make(snapshot, legalActions)
    val paymentPrompt = when {
        promptV2 != null && CompactPromptPopup.isManaPaymentPrompt(promptV2) -> promptV2
        CompactPromptPopup.shouldShowStackPaymentTray(snapshot) -> CompactPromptPopup.syntheticStackPaymentPrompt(snapshot)
        else -> null
    }
    val isManaPayment = presentation?.kind == MobilePromptKind.PAYMENT || (promptV2 != null && CompactPromptPopup.isManaPaymentPrompt(promptV2))
    val borderColor = if (isManaPayment) MagicPalette.arcaneBlue else MagicPalette.borderBronze
    val priorityLabel = if (snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId)) "YOUR DECISION" else "WAITING"
    val messageText = presentation?.message ?: promptV2?.message ?: snapshot.choicePrompt?.message ?: snapshot.promptEnvelope?.message
        ?: snapshot.promptText ?: "XMage is waiting"

    fun command(type: String, promptId: String, playerId: String, ids: List<String> = emptyList(), useCommandZone: Boolean? = null,
                pay: Boolean? = null): GameCommand? = UniversalPromptResponseCommandBuilder.command(snapshot.id, snapshot.bridgeRevision,
        snapshot.promptEnvelopeV2, type, promptId, playerId, ids, useCommandZone = useCommandZone, pay = pay)

    fun explicitConfirmationCommand(confirmation: XmageResponseCommand?, prompt: PromptEnvelopeV2): GameCommand? {
        confirmation ?: return null
        val type = confirmation.type ?: return null
        val promptId = confirmation.promptId ?: return null
        val confirmed = confirmation.confirmed ?: confirmation.pay ?: return null
        return command(type, promptId, prompt.playerId, listOf(if (confirmed) "true" else "false"), pay = confirmation.pay ?: confirmed)
    }

    @Composable
    fun detailButton() {
        PanelActionButton(openDetails, enabled = pendingActionId == null) {
            PromptButtonLabel("Open choices", "XMage prompt controls", "list.bullet.rectangle", false)
        }
    }

    @Composable
    fun commandButton(label: String, systemImage: String?, pendingId: String, command: GameCommand?, buttonModifier: Modifier = Modifier) {
        PanelActionButton({ command?.let { runCommand(it, label, pendingId) } }, buttonModifier, isPrimary = true, compact = true,
            enabled = pendingActionId == null && command != null) {
            PromptButtonLabel(label, systemImage = systemImage, isPending = pendingActionId == pendingId)
        }
    }

    @Composable
    fun actionButtons(actions: List<LegalAction>) {
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            for (action in actions.take(3)) {
                PanelActionButton({ runAction(action) }, Modifier.weight(1f), isPrimary = action.isPrimary == true || action.type == "keep_hand",
                    compact = true, enabled = pendingActionId == null) {
                    PromptButtonLabel(CompactPromptPopup.compactActionLabel(action), systemImage = LegalActionDisplay.systemImage(action),
                        isPending = pendingActionId == action.id)
                }
            }
            if (actions.size > 3 || (snapshot.source == "xmage-ondevice" && CompactPromptPopup.needsDetails(snapshot))) detailButton()
        }
    }

    @Composable
    fun unsupportedFallback() {
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("exclamationmark.triangle.fill", MagicPalette.warningAmber, 11.dp)
            Text("Needs app support", Modifier.weight(1f), color = Color.White.copy(alpha = 0.86f), style = sf(10f, SfWeight.black), maxLines = 1)
            detailButton()
        }
    }

    @Composable
    fun promptControls(prompt: PromptEnvelopeV2) {
        val battlefieldIds = snapshot.players.flatMap { it.zones.battlefield }.map { it.instanceId }.toSet()
        val options = (prompt.targets ?: emptyList()).filter { it.id !in battlefieldIds }
        val promptId = prompt.responseCommand?.promptId ?: prompt.id
        val confirmation = prompt.confirmation
        val choices = prompt.choices
        when {
            options.isNotEmpty() && prompt.maxChoices == 1 -> FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (option in options) {
                    commandButton(option.label, "person.crop.circle", "${prompt.id}-${option.id}",
                        command(prompt.responseCommand?.type ?: "choose_target", promptId, prompt.playerId, listOf(option.id)), Modifier.widthIn(min = 125.dp))
                }
            }
            PromptCommandBuilder.isCommanderReplacement(prompt) -> Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                commandButton("Command zone", "crown.fill", "${prompt.id}-command-zone", command("commander_replacement", promptId, prompt.playerId, useCommandZone = true), Modifier.weight(1f))
                commandButton("Original", "arrow.uturn.backward", "${prompt.id}-original-zone", command("commander_replacement", promptId, prompt.playerId, useCommandZone = false), Modifier.weight(1f))
            }
            confirmation != null && CompactPromptPopup.isConfirmationPrompt(prompt) -> Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                commandButton(confirmation.yesLabel ?: "Yes", "checkmark.circle", "${prompt.id}-yes", explicitConfirmationCommand(confirmation.yesCommand, prompt), Modifier.weight(1f))
                commandButton(confirmation.noLabel ?: "No", "xmark.circle", "${prompt.id}-no", explicitConfirmationCommand(confirmation.noCommand, prompt), Modifier.weight(1f))
            }
            CompactPromptPopup.shouldPreferCompactActionsBeforeRawChoices(snapshot) -> actionButtons(compactPromptActions)
            !choices.isNullOrEmpty() && choices.size <= 3 -> {
                Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    for (choice in choices) {
                        commandButton(choice.label, CompactPromptPopup.yesNoIcon(choice.label), "${prompt.id}-${choice.id}",
                            command(PromptCommandBuilder.idCommandType(prompt.responseCommand?.type, "resolve_choice"), promptId, prompt.playerId, listOf(choice.id)),
                            Modifier.weight(1f))
                    }
                }
                val extra = CompactPromptPopup.supplementalChoiceActions(snapshot)
                if (extra.isNotEmpty()) actionButtons(extra)
            }
            compactPromptActions.isNotEmpty() -> actionButtons(compactPromptActions)
            CompactPromptPopup.needsDetails(snapshot) -> detailButton()
            else -> unsupportedFallback()
        }
    }

    @Composable
    fun choicePromptControls(prompt: ChoicePrompt) {
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            for (choice in prompt.choices.take(3)) {
                val composedId = "${prompt.id}-${choice.id}"
                val action = legalActions.firstOrNull { a ->
                    a.id == choice.id || a.id == composedId || a.targetIds?.contains(choice.id) == true || a.validTargetIds?.contains(choice.id) == true ||
                        a.id.endsWith("-${choice.id}")
                }
                val fallback = command("resolve_choice", prompt.id, prompt.playerId, listOf(choice.id))
                PanelActionButton({
                    if (action != null) runAction(action) else fallback?.let { runCommand(it, choice.label, composedId) }
                }, Modifier.weight(1f), isPrimary = action?.isPrimary == true, enabled = pendingActionId == null && (action != null || fallback != null)) {
                    PromptButtonLabel(choice.label, systemImage = CompactPromptPopup.yesNoIcon(choice.label),
                        isPending = pendingActionId == action?.id || pendingActionId == composedId)
                }
            }
            if (prompt.choices.size > 3) detailButton()
        }
    }

    @Composable
    fun legacyPromptControls(prompt: PromptEnvelope) {
        val choices = prompt.choices
        when {
            !choices.isNullOrEmpty() -> Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                for (choice in choices.take(3)) {
                    commandButton(choice.label, CompactPromptPopup.yesNoIcon(choice.label), "${prompt.id}-${choice.id}",
                        command("resolve_choice", prompt.id, prompt.playerId, listOf(choice.id)), Modifier.weight(1f))
                }
            }
            compactPromptActions.isNotEmpty() -> actionButtons(compactPromptActions)
            else -> unsupportedFallback()
        }
    }

    Column(modifier.glow(Color.Black.copy(alpha = 0.30f), 10.dp, 10.dp)
        .background(Brush.linearGradient(listOf(MagicPalette.iron.copy(alpha = 0.92f), MagicPalette.leather.copy(alpha = 0.86f))), RoundedCornerShape(10.dp))
        .border(1.2.dp, borderColor.copy(alpha = 0.60f), RoundedCornerShape(10.dp)).padding(horizontal = 10.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            GameRulesText(PromptDisplayText.clean(messageText), Modifier.weight(1f), symbolSize = 14.dp, style = sf(14f, SfWeight.black),
                color = Color.White.copy(alpha = 0.94f), maxLines = 3)
            FitText(priorityLabel, sf(8f, SfWeight.black), Modifier.padding(top = 3.dp), color = Color.White.copy(alpha = 0.68f), minimumScale = 0.65f)
        }
        when {
            paymentPrompt != null -> ManaPaymentTray(snapshot, paymentPrompt, pendingActionId, runAction, runCommand)
            pendingActionId != null -> Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(14.dp), color = MagicPalette.arcaneBlue, strokeWidth = 2.dp)
                Text("Waiting for XMage", color = MagicPalette.arcaneBlue, style = sf(10f, SfWeight.black))
            }
            promptV2 != null -> promptControls(promptV2)
            snapshot.choicePrompt != null -> choicePromptControls(snapshot.choicePrompt!!)
            snapshot.promptEnvelope != null -> legacyPromptControls(snapshot.promptEnvelope!!)
        }
    }
}

/** A dragged or tapped card with several engine offers (cast, adventure, MDFC land…). */
data class DragActionChoice(val message: String, val actions: List<LegalAction>, val id: Long = System.nanoTime())

@Composable
fun DragActionChoicePopup(choice: DragActionChoice, pendingActionId: String?, runAction: (LegalAction) -> Unit, cancel: () -> Unit,
                          modifier: Modifier = Modifier) {
    // Ability text is sentence length; give each action its own full-width row.
    val usesRows = choice.actions.size > 2 || choice.actions.any { (it.shortLabel ?: it.label).length > 18 }
    Column(modifier.glow(Color.Black.copy(alpha = 0.5f), 16.dp, 12.dp)
        .background(Brush.linearGradient(listOf(MagicPalette.iron.copy(alpha = 0.96f), MagicPalette.leather.copy(alpha = 0.92f))), RoundedCornerShape(12.dp))
        .border(1.2.dp, MagicPalette.antiqueGold.copy(alpha = 0.7f), RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 11.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            FitText(PromptDisplayText.clean(choice.message), sf(17f, SfWeight.black, SfDesign.SERIF), Modifier.weight(1f),
                color = MagicPalette.parchment, maxLines = 2, minimumScale = 0.7f)
            PressableBox(cancel, Modifier.size(44.dp).semantics { contentDescription = "Cancel action choice" }, enabled = pendingActionId == null) {
                Box(Modifier.size(32.dp).background(Color.White.copy(alpha = 0.08f), CircleShape), contentAlignment = Alignment.Center) {
                    SfImage("xmark", Color.White.copy(alpha = 0.8f), 14.dp)
                }
            }
        }
        @Composable
        fun button(action: LegalAction, buttonModifier: Modifier) {
            PanelActionButton({ runAction(action) }, buttonModifier, isPrimary = true, compact = !usesRows, enabled = pendingActionId == null) {
                PromptButtonLabel(action.shortLabel ?: action.label, systemImage = LegalActionDisplay.systemImage(action), isPending = pendingActionId == action.id,
                    cardName = action.cardName ?: choice.message, large = usesRows)
            }
        }
        if (usesRows) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { choice.actions.take(4).forEach { button(it, Modifier.fillMaxWidth()) } }
        else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { choice.actions.take(4).forEach { button(it, Modifier.weight(1f)) } }
    }
}

@Composable
fun CombatSubmitPill(title: String, count: Int, submit: () -> Unit, modifier: Modifier = Modifier) {
    PressableBox(submit, modifier) {
        Row(Modifier.glow(MagicPalette.oxblood.copy(alpha = 0.42f), 10.dp, 20.dp).background(MagicPalette.oxblood.copy(alpha = 0.88f), CircleShape)
            .border(1.2.dp, MagicPalette.antiqueGold.copy(alpha = 0.45f), CircleShape).padding(horizontal = 14.dp, vertical = 9.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("arrow.triangle.branch", Color.White, 12.dp)
            Text(title.uppercase(), color = Color.White, style = sf(10f, SfWeight.black))
            Text("$count", Modifier.background(Color.Black.copy(alpha = 0.28f), CircleShape).padding(horizontal = 7.dp, vertical = 3.dp),
                color = Color.White, style = sf(10f, SfWeight.black))
        }
    }
}
