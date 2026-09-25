package io.magicmobile.android.board

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.ChoicePrompt
import io.magicmobile.android.game.CompactPromptPopup
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameplayActionPresentation
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.LegalActionDisplay
import io.magicmobile.android.game.MobilePromptPresentation
import io.magicmobile.android.game.PromptAmountBounds
import io.magicmobile.android.game.PromptCommandBuilder
import io.magicmobile.android.game.PromptDisplayText
import io.magicmobile.android.game.PromptEnvelope
import io.magicmobile.android.game.PromptEnvelopeV2
import io.magicmobile.android.game.PromptSelectionRules
import io.magicmobile.android.game.UniversalPromptResponseCommandBuilder
import io.magicmobile.android.game.XmageNamedZone
import io.magicmobile.android.game.XmagePromptAbility
import io.magicmobile.android.game.XmagePromptConfirmation
import io.magicmobile.android.game.XmagePromptManaChoice
import io.magicmobile.android.game.XmagePromptMultiAmount
import io.magicmobile.android.game.XmagePromptPile
import io.magicmobile.android.game.XmagePromptPlayer
import io.magicmobile.android.game.XmageResponseCommand
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.game.capitalizedWords
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.sf
import kotlinx.serialization.json.JsonPrimitive

/** PromptPanelSection: a titled, bronze-edged group in the choices panel. */
@Composable
fun PromptPanelSection(title: String, detail: String, isHighlighted: Boolean = false, isEmbedded: Boolean = false,
                       content: @Composable ColumnScope.() -> Unit) {
    if (isEmbedded) { Column(verticalArrangement = Arrangement.spacedBy(7.dp), content = content); return }
    val shape = RoundedCornerShape(8.dp)
    Column(Modifier.fillMaxWidth()
        .background(if (isHighlighted) MagicPalette.warningAmber.copy(alpha = 0.10f) else MagicPalette.iron.copy(alpha = 0.42f), shape)
        .border(if (isHighlighted) 1.5.dp else 1.dp, if (isHighlighted) MagicPalette.warningAmber.copy(alpha = 0.48f) else MagicPalette.borderBronze.copy(alpha = 0.28f), shape)
        .padding(7.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            FitText(title.uppercase(), sf(8f, SfWeight.black), Modifier.weight(1f, fill = false),
                color = if (isHighlighted) MagicPalette.warningAmber else MagicPalette.antiqueGold, minimumScale = 0.7f)
            Spacer(Modifier.weight(1f))
            FitText(detail.uppercase(), sf(7f, SfWeight.black), color = if (isHighlighted) MagicPalette.warningAmber.copy(alpha = 0.86f) else MagicPalette.parchment.copy(alpha = 0.58f),
                minimumScale = 0.6f)
        }
        content()
    }
}

/** A LazyVGrid(.adaptive(minimum:)) for a handful of buttons inside a scrolling sheet. */
@Composable
fun AdaptiveGrid(minimum: Float, spacing: Float, count: Int, item: @Composable (Int) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val columns = maxOf(1, ((maxWidth.value + spacing) / (minimum + spacing)).toInt())
        Column(verticalArrangement = Arrangement.spacedBy(spacing.dp)) {
            for (start in 0 until count step columns) {
                Row(horizontalArrangement = Arrangement.spacedBy(spacing.dp)) {
                    for (index in start until start + columns) {
                        Box(Modifier.weight(1f)) { if (index < count) item(index) }
                    }
                }
            }
        }
    }
}

/**
 * ContentView.swift UniversalPromptActionPanel: every control XMage exposes for the current
 * prompt — choices, targets, cards, abilities, piles, amounts, order, mana — plus the game's
 * other legal actions and zones.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun UniversalPromptActionPanel(snapshot: GameSnapshot, selectedCardActions: List<LegalAction>, selection: BoardSelection, pendingActionId: String?,
                               runAction: (LegalAction) -> Unit, runCommand: (GameCommand, String, String) -> Unit,
                               viewZone: (String, List<ZoneCard>) -> Unit, dismiss: () -> Unit, modifier: Modifier = Modifier,
                               showsGameSurfaceSections: Boolean = true) {
    val haptics = rememberHaptics()
    var orderPromptId by remember { mutableStateOf<String?>(null) }
    var orderedIds by remember { mutableStateOf(listOf<String>()) }
    var multiAmountPromptId by remember { mutableStateOf<String?>(null) }
    val multiAmountValues = remember { mutableStateMapOf<String, Int>() }
    val manualAmountValues = remember { mutableStateMapOf<String, Int>() }
    var selectedSearchPromptId by remember { mutableStateOf<String?>(null) }
    var selectedSearchCardIds by remember { mutableStateOf(listOf<String>()) }
    var choiceSearch by remember { mutableStateOf("") }
    val legalActions = snapshot.legalActions ?: emptyList()
    val passTypes = setOf("pass_priority", "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn",
        "yield_until_next_turn", "pass_until_next_turn", "advance_phase")
    val spellTypes = setOf("play_land", "cast_spell")
    val abilityTypes = setOf("activate_ability", "make_mana", "play_mana", "choose_mana", "choose_ability")
    val passActions = legalActions.filter { it.type in passTypes }
    val spellsAndLands = legalActions.filter { it.type in spellTypes }
    val abilitiesAndMana = legalActions.filter { it.type in abilityTypes }
    val sourceManaActions = legalActions.filter { it.type == "make_mana" && (it.sourceInstanceId != null || it.cardInstanceId != null) }
    val otherActions = legalActions.filter { it.type !in passTypes && it.type !in spellTypes && it.type !in abilityTypes }
    val presentation = MobilePromptPresentation.make(snapshot, legalActions)
    val priorityLabel = if (snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId)) "YOUR PRIORITY"
        else snapshot.playerLabel(snapshot.priorityPlayerId ?: snapshot.waitingOnPlayerId)
    val selectedCard = selection.selectedCard

    fun command(type: String, promptId: String, playerId: String, ids: List<String> = emptyList(), amount: Int? = null, amounts: List<Int>? = null,
                pile: Int? = null, useCommandZone: Boolean? = null, manaType: String? = null, pay: Boolean? = null): GameCommand? =
        UniversalPromptResponseCommandBuilder.command(snapshot.id, snapshot.bridgeRevision, snapshot.promptEnvelopeV2, type, promptId, playerId, ids,
            amount, amounts, pile, useCommandZone, manaType, pay)

    fun responseType(prompt: PromptEnvelopeV2): String = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
    fun isManaPrompt(prompt: PromptEnvelopeV2): Boolean = responseType(prompt) in setOf("play_mana", "choose_mana", "mana", "pay_cost", "cost")
    fun isManaOrPaymentPrompt(prompt: PromptEnvelopeV2): Boolean {
        val type = prompt.responseCommand?.type?.lowercase() ?: ""
        val kind = prompt.responseKind.lowercase()
        return isManaPrompt(prompt) || type in setOf("pay_cost", "choose_mana", "play_x_mana") || kind in setOf("pay_cost", "cost", "mana", "x_mana") ||
            prompt.message.contains("pay", ignoreCase = true) || prompt.message.contains("mana", ignoreCase = true)
    }
    fun isConfirmationPrompt(prompt: PromptEnvelopeV2): Boolean = prompt.confirmation != null || responseType(prompt) in setOf("answer_yes_no", "confirmation", "pay_cost")
    fun isTriggerOrderPrompt(prompt: PromptEnvelopeV2) = responseType(prompt) == "order_triggers"
    fun isSearchPrompt(prompt: PromptEnvelopeV2) = responseType(prompt) == "search_select" || prompt.method.contains("search", ignoreCase = true)
    fun isCardSelectionPrompt(prompt: PromptEnvelopeV2) = responseType(prompt) in setOf("choose_card", "card", "choose_target", "target")
    fun isPlayerSelectionPrompt(prompt: PromptEnvelopeV2) = responseType(prompt) in setOf("choose_player", "player")
    fun isChooseColorPrompt(prompt: PromptEnvelopeV2) = responseType(prompt) in setOf("choose_mana", "choose_color")
    fun isAmountPrompt(prompt: PromptEnvelopeV2) = responseType(prompt) in setOf("play_x_mana", "choose_amount")
    fun isDamageAssignmentPrompt(prompt: PromptEnvelopeV2) = PromptCommandBuilder.isCombatDamageAllocationPrompt(prompt, snapshot.phase, snapshot.step)
    fun isOrderCommand(type: String) = type == "order_triggers" || type == "order_items"
    fun hasRenderablePromptControls(prompt: PromptEnvelopeV2): Boolean =
        isManaOrPaymentPrompt(prompt) || isDamageAssignmentPrompt(prompt) || PromptCommandBuilder.isCommanderReplacement(prompt) || isConfirmationPrompt(prompt) ||
            isManaPrompt(prompt) || isTriggerOrderPrompt(prompt) || isSearchPrompt(prompt) || isCardSelectionPrompt(prompt) || isPlayerSelectionPrompt(prompt) ||
            isChooseColorPrompt(prompt) || isAmountPrompt(prompt) || !prompt.choices.isNullOrEmpty() || !prompt.targets.isNullOrEmpty() ||
            !prompt.players.isNullOrEmpty() || !prompt.cards.isNullOrEmpty() || !prompt.modes.isNullOrEmpty() || !prompt.abilities.isNullOrEmpty() ||
            !prompt.piles.isNullOrEmpty() || !prompt.amounts.isNullOrEmpty() || !prompt.multiAmounts.isNullOrEmpty() || !prompt.orderedItems.isNullOrEmpty() ||
            !prompt.manaChoices.isNullOrEmpty() || prompt.method == "GAME_SELECT"
    fun yesNoIcon(label: String): String? = when (label.trim().lowercase()) {
        "yes", "ok", "accept" -> "checkmark.circle"; "no", "cancel", "decline" -> "xmark.circle"; else -> null
    }
    fun single(values: List<String>?) = values?.size == 1
    fun isDirectlyRunnable(action: LegalAction): Boolean = when (action.type) {
        "choose_target" -> single(action.targetIds) || single(action.validTargetIds)
        "choose_card", "search_select" -> single(action.cardInstanceIds) || single(action.validCardInstanceIds) || single(action.targetIds) || single(action.validTargetIds)
        "choose_player" -> single(action.playerIds) || single(action.validPlayerIds) || single(action.targetIds) || single(action.validTargetIds)
        "choose_mode" -> single(action.modeIds) || single(action.targetIds) || single(action.validTargetIds)
        "resolve_choice" -> single(action.choiceIds) || single(action.targetIds) || single(action.validTargetIds)
        "declare_attackers", "declare_blockers" -> PromptCommandBuilder.hasPrebuiltCombatPayload(action)
        "choose_multi_amount", "order_triggers", "order_items" -> false
        else -> true
    }
    val availableManaSymbols = listOf("W", "U", "B", "R", "G", "C").filter { symbol ->
        val pool = snapshot.human?.manaPool
        (when (symbol) { "W" -> pool?.W; "U" -> pool?.U; "B" -> pool?.B; "R" -> pool?.R; "G" -> pool?.G; else -> pool?.C } ?: 0) > 0
    }
    fun searchZoneName(prompt: PromptEnvelopeV2): String =
        ((prompt.options?.get("zone") as? JsonPrimitive)?.takeIf { it.isString }?.content?.takeIf { it.isNotEmpty() })?.let(::capitalizedWords) ?: "Library"
    fun explicitConfirmationCommand(confirmation: XmageResponseCommand?, prompt: PromptEnvelopeV2): GameCommand? {
        confirmation ?: return null
        val type = confirmation.type ?: return null
        val promptId = confirmation.promptId ?: return null
        val confirmed = confirmation.confirmed ?: confirmation.pay ?: return null
        return command(type, promptId, prompt.playerId, listOf(if (confirmed) "true" else "false"), pay = confirmation.pay ?: confirmed)
    }

    @Composable
    fun promptButton(label: String, pendingId: String, command: GameCommand?, subtitle: String? = null, systemImage: String? = null,
                     large: Boolean = false, buttonModifier: Modifier = Modifier.fillMaxWidth()) {
        PanelActionButton({ command?.let { runCommand(it, label, pendingId) } }, buttonModifier, isPrimary = true, enabled = pendingActionId == null && command != null) {
            PromptButtonLabel(label, subtitle, systemImage, pendingActionId == pendingId, large = large)
        }
    }

    @Composable
    fun optionGrid(options: List<Pair<String, String>>, prompt: PromptEnvelopeV2, fallbackType: String, icon: String) {
        val type = PromptCommandBuilder.idCommandType(prompt.responseCommand?.type, fallbackType)
        val promptId = prompt.responseCommand?.promptId ?: prompt.id
        // Modes and other sentence-length options get full-width rows so the whole text is readable.
        if (options.any { PromptDisplayText.clean(it.second).length > 16 }) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((id, label) in options) promptButton(label, "${prompt.id}-$id", command(type, promptId, prompt.playerId, listOf(id)), systemImage = yesNoIcon(label) ?: icon, large = true)
            }
        } else AdaptiveGrid(110f, 8f, options.size) { index ->
            val (id, label) = options[index]
            promptButton(label, "${prompt.id}-$id", command(type, promptId, prompt.playerId, listOf(id)), systemImage = yesNoIcon(label) ?: icon)
        }
    }

    @Composable
    fun actionSection(title: String, detail: String, actions: List<LegalAction>, compact: Boolean = false) {
        PromptPanelSection(title, detail) {
            if (actions.isEmpty()) Text("No exposed actions", color = Color.White.copy(alpha = 0.48f), style = sf(10f, SfWeight.bold))
            else AdaptiveGrid(if (compact) 72f else 98f, 6f, actions.size) { index ->
                val action = actions[index]
                val runnable = isDirectlyRunnable(action)
                PanelActionButton({ if (runnable) runAction(action) }, Modifier.fillMaxWidth(), isDanger = action.type == "concede",
                    isPrimary = action.isPrimary == true || action.type == "cast_spell" || action.type == "play_land", compact = compact,
                    enabled = pendingActionId == null && runnable) {
                    PromptButtonLabel(GameplayActionPresentation.title(action, snapshot), if (runnable) LegalActionDisplay.actionDetail(action) else "Use prompt picker",
                        LegalActionDisplay.systemImage(action), pendingActionId == action.id)
                }
            }
        }
    }

    @Composable
    fun cardPicker(cards: List<ZoneCard>, prompt: PromptEnvelopeV2) {
        val type = PromptCommandBuilder.idCommandType(prompt.responseCommand?.type, if (isSearchPrompt(prompt)) "search_select" else "choose_card")
        val selectedId = PromptSelectionRules.selectedPromptCardId(selectedCard, cards)
        val validSelection = selectedId != null && PromptSelectionRules.isValidSelectedCount(1, prompt.minChoices ?: 1, prompt.maxChoices ?: 1)
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                for (card in cards) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        CardTile(card, selectedCard?.id == card.id || selectedCard?.instanceId == card.instanceId, Modifier.onCardInteraction(tap = {
                            selection.selectedCard = if (selection.selectedCard?.instanceId == card.instanceId) null else card
                            selection.inspectedCard = null
                            GameHaptics.selection(haptics)
                        }, inspect = { selection.inspectedCard = card; GameHaptics.impact(haptics) },
                            release = { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null }),
                            legal = true, zoneName = "Prompt", width = 42.dp, height = 59.dp)
                        FitText(card.card.name, sf(8f, SfWeight.black), Modifier.width(70.dp), color = Color.White.copy(alpha = 0.74f), minimumScale = 0.6f,
                            textAlign = TextAlign.Center)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                if (selectedId != null) PanelActionButton({ selection.selectedCard = null; GameHaptics.selection(haptics) }, Modifier.weight(1f),
                    enabled = pendingActionId == null) { PromptButtonLabel("Clear", systemImage = "xmark.circle") }
                promptButton("Confirm Card", "${prompt.id}-choose-card",
                    if (validSelection && selectedId != null) command(type, prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, listOf(selectedId)) else null,
                    subtitle = if (selectedId == null) "Select a card first" else selectedCard?.card?.name, systemImage = "checkmark.circle",
                    buttonModifier = Modifier.weight(1f))
            }
        }
    }

    @Composable
    fun searchSelectionPicker(cards: List<ZoneCard>, prompt: PromptEnvelopeV2) {
        val selectableIds = cards.filter { it.isPromptSelectable }.map { it.instanceId }
        val selectedIds = if (selectedSearchPromptId == prompt.id) selectedSearchCardIds.filter { it in selectableIds } else emptyList()
        val valid = PromptSelectionRules.isValidSelectedCount(selectedIds.size, prompt.minChoices, prompt.maxChoices)
        val type = PromptCommandBuilder.idCommandType(prompt.responseCommand?.type, "search_select")
        val zone = searchZoneName(prompt)
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                PromptMiniLabel(zone)
                Spacer(Modifier.weight(1f))
                FitText("${selectedIds.size} selected · ${PromptSelectionRules.boundsText(prompt.minChoices, prompt.maxChoices)}", sf(7f, SfWeight.black),
                    color = if (valid) MagicPalette.legalEmerald.copy(alpha = 0.86f) else MagicPalette.warningAmber.copy(alpha = 0.86f), minimumScale = 0.62f)
                if (selectedIds.isNotEmpty()) Text("Clear", Modifier.defaultMinSize(44.dp, 44.dp).clickable(enabled = pendingActionId == null) {
                    selectedSearchPromptId = prompt.id; selectedSearchCardIds = emptyList(); GameHaptics.selection(haptics)
                }.padding(top = 14.dp), color = MagicPalette.parchment, style = sf(9f, SfWeight.black))
            }
            Box(Modifier.heightIn(max = 154.dp).verticalScroll(rememberScrollState())) {
                AdaptiveGrid(54f, 7f, cards.size) { index ->
                    val card = cards[index]
                    val selectable = card.isPromptSelectable
                    val isSelected = card.instanceId in selectedIds
                    Box(Modifier.clickable(enabled = pendingActionId == null && selectable) {
                        if (selectedSearchPromptId != prompt.id) { selectedSearchPromptId = prompt.id; selectedSearchCardIds = emptyList() }
                        else selectedSearchCardIds = selectedSearchCardIds.filter { it in selectableIds }
                        selectedSearchCardIds = when {
                            card.instanceId in selectedSearchCardIds -> selectedSearchCardIds - card.instanceId
                            prompt.maxChoices != null && selectedSearchCardIds.size >= prompt.maxChoices!! -> selectedSearchCardIds
                            else -> selectedSearchCardIds + card.instanceId
                        }
                        GameHaptics.selection(haptics)
                    }, contentAlignment = Alignment.BottomCenter) {
                        CardTile(card, isSelected, Modifier.alpha(if (selectable) 1f else 0.34f), legal = selectable, targetable = selectable, zoneName = zone,
                            width = 50.dp, height = 70.dp)
                        if (!selectable) FitText(card.disabledReason ?: "Not valid", sf(6f, SfWeight.black), Modifier.padding(2.dp)
                            .background(Color.Black.copy(alpha = 0.72f), RoundedCornerShape(50)).padding(horizontal = 3.dp, vertical = 2.dp),
                            color = Color.White.copy(alpha = 0.82f), minimumScale = 0.55f)
                    }
                }
            }
            promptButton("Submit selection", "${prompt.id}-search-select",
                if (valid) command(type, prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, selectedIds) else null,
                subtitle = if (valid) "${selectedIds.size} cards from $zone" else "Select ${PromptSelectionRules.boundsText(prompt.minChoices, prompt.maxChoices)}",
                systemImage = "checkmark.circle")
        }
    }

    @Composable
    fun abilityPicker(abilities: List<XmagePromptAbility>, prompt: PromptEnvelopeV2) {
        PromptMiniLabel("Abilities")
        val compactHeight = LocalConfigurationHeightCompact()
        AdaptiveGrid(160f, 12f, abilities.size) { index ->
            // Occurrences are distinct rows even if XMage repeats an ability UUID.
            val ability = abilities[index]
            val choiceCommand = command("choose_ability", prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, listOf(ability.id))
            Column(Modifier.fillMaxWidth().background(MagicPalette.iron.copy(alpha = 0.7f), RoundedCornerShape(12.dp)).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val source = ability.sourceCard
                if (source != null) {
                    val enabled = pendingActionId == null && choiceCommand != null
                    Box(Modifier.fillMaxWidth().semantics { contentDescription = "Choose ${source.card.name} ability. Tap to choose. Hold to inspect the source card." },
                        contentAlignment = Alignment.Center) {
                        CardTile(source, false, Modifier.onCardInteraction(tap = {
                            if (enabled && choiceCommand != null) { selection.inspectedCard = null; runCommand(choiceCommand, "Choose ability", "${prompt.id}-${ability.id}") }
                        }, inspect = { selection.inspectedCard = source }, release = { if (selection.inspectedCard?.id == source.id) selection.inspectedCard = null },
                            enabled = enabled), zoneName = "Ability source", width = if (compactHeight) 80.dp else 100.dp, height = if (compactHeight) 112.dp else 140.dp)
                    }
                }
                Text(ability.sourceName ?: "Ability", color = MagicPalette.parchment, style = SfText.subheadline(SfWeight.bold))
                GameRulesText(ability.rulesText ?: ability.label, cardName = ability.sourceName, style = SfText.callout(), color = MagicPalette.parchment)
                if (source == null) Text(ability.sourceUnavailableReason ?: "Source details unavailable", color = MagicPalette.parchment.copy(alpha = 0.6f), style = SfText.caption())
                promptButton("Choose ability", "${prompt.id}-${ability.id}", choiceCommand, systemImage = "bolt.fill")
            }
        }
    }

    @Composable
    fun pilePicker(piles: List<XmagePromptPile>, prompt: PromptEnvelopeV2) {
        PromptMiniLabel("Piles")
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            for (pile in piles) {
                Column(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.06f), RoundedCornerShape(8.dp)).padding(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${pile.label} · ${pile.cards.size} cards", color = MagicPalette.parchment, style = SfText.subheadline(SfWeight.bold))
                    if (pile.cards.isEmpty()) Text("This pile is empty.", color = MagicPalette.parchment.copy(alpha = 0.7f), style = SfText.caption())
                    else Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                        for (card in pile.cards) {
                            Column(Modifier.width(96.dp).clickable { selection.inspectedCard = card }.semantics { contentDescription = "Inspect ${card.card.name} in ${pile.label}" },
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                CardTile(card, false, zoneName = pile.label, width = 76.dp, height = 106.dp)
                                Text(card.card.name, color = MagicPalette.parchment, style = SfText.caption(), textAlign = TextAlign.Center)
                                Text("Inspect", Modifier.defaultMinSize(minHeight = 44.dp).padding(top = 12.dp), color = MagicPalette.parchment, style = SfText.caption(SfWeight.bold))
                            }
                        }
                    }
                    promptButton("Choose ${pile.label}", "${prompt.id}-pile-${pile.id}",
                        command("choose_pile", prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, pile = pile.explicitPileNumber),
                        subtitle = "${pile.cards.size} cards", systemImage = "tray.full")
                }
            }
        }
    }

    @Composable
    fun multiAmountPicker(slots: List<XmagePromptMultiAmount>, prompt: PromptEnvelopeV2) {
        val values = slots.map { slot -> if (multiAmountPromptId == prompt.id) multiAmountValues[slot.id] ?: PromptCommandBuilder.defaultMultiAmountValue(slot)
            else PromptCommandBuilder.defaultMultiAmountValue(slot) }
        val total = values.sum()
        val valid = PromptCommandBuilder.isValidMultiAmountValues(values, slots, prompt.totalMin, prompt.totalMax)
        val damage = isDamageAssignmentPrompt(prompt)
        fun adjust(slot: XmagePromptMultiAmount, delta: Int) {
            if (multiAmountPromptId != prompt.id) {
                multiAmountPromptId = prompt.id
                multiAmountValues.clear(); slots.forEach { multiAmountValues[it.id] = PromptCommandBuilder.defaultMultiAmountValue(it) }
            }
            val current = multiAmountValues[slot.id] ?: PromptCommandBuilder.defaultMultiAmountValue(slot)
            multiAmountValues[slot.id] = PromptCommandBuilder.adjustedMultiAmountValue(current, delta, slot)
        }
        PromptMiniLabel(if (damage) "Damage Assignment" else "Multi Amount")
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            slots.forEachIndexed { index, slot ->
                val value = values[index]
                Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.06f), RoundedCornerShape(8.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(8.dp)).padding(horizontal = 7.dp, vertical = 5.dp),
                    horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        FitText(slot.label, sf(10f, SfWeight.black), color = Color.White.copy(alpha = 0.88f), minimumScale = 0.7f)
                        Text("${slot.min}-${slot.max}", color = Color.White.copy(alpha = 0.52f), style = sf(7f, SfWeight.bold))
                    }
                    PressableBox({ adjust(slot, -1) }, Modifier.size(44.dp), enabled = pendingActionId == null && value > slot.min) {
                        SfImage("minus.circle.fill", if (value <= slot.min) Color.White.copy(alpha = 0.24f) else MagicPalette.parchment, 20.dp)
                    }
                    Text("$value", Modifier.width(28.dp), color = Color.White, style = sf(13f, SfWeight.black), textAlign = TextAlign.Center)
                    PressableBox({ adjust(slot, 1) }, Modifier.size(44.dp), enabled = pendingActionId == null && value < slot.max) {
                        SfImage("plus.circle.fill", if (value >= slot.max) Color.White.copy(alpha = 0.24f) else MagicPalette.parchment, 20.dp)
                    }
                }
            }
            val bounds = listOfNotNull(prompt.totalMin?.let { "min $it" }, prompt.totalMax?.let { "max $it" })
            val suffix = if (bounds.isEmpty()) "" else " · ${bounds.joinToString(", ")}"
            promptButton(if (damage) "Assign damage" else "Submit amounts", "${prompt.id}-choose-multi-amount",
                if (valid) command("choose_multi_amount", prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, amounts = values) else null,
                subtitle = if (valid) "total $total$suffix" else "invalid total $total$suffix", systemImage = "number")
        }
    }

    @Composable
    fun amountPicker(amounts: List<Int>, prompt: PromptEnvelopeV2) {
        val type = PromptCommandBuilder.amountCommandType(prompt.responseCommand?.type)
        if (type == "choose_multi_amount") {
            val slots = prompt.multiAmounts
            if (!slots.isNullOrEmpty()) multiAmountPicker(slots, prompt)
            else {
                PromptMiniLabel("Multi Amount")
                Text("Unsupported prompt/action: XMage did not expose slot metadata for this multi-amount prompt.",
                    color = MagicPalette.warningAmber.copy(alpha = 0.9f), style = sf(10f, SfWeight.bold), maxLines = 3)
            }
        } else {
            PromptMiniLabel("Amount")
            AdaptiveGrid(44f, 6f, amounts.size) { index ->
                val amount = amounts[index]
                promptButton("$amount", "${prompt.id}-amount-$amount",
                    command(type, prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, amount = amount, amounts = listOf(amount)), systemImage = "number")
            }
        }
    }

    @Composable
    fun manualAmountPicker(prompt: PromptEnvelopeV2) {
        val type = PromptCommandBuilder.amountCommandType(prompt.responseCommand?.type)
        val bounds = PromptAmountBounds(prompt.minChoices, prompt.maxChoices)
        val current = bounds.clamp(manualAmountValues[prompt.id] ?: 0)
        PromptMiniLabel(if (type == "play_x_mana") "X Amount" else "Amount")
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            PressableBox({ manualAmountValues[prompt.id] = bounds.stepping(current, -1) }, Modifier.size(44.dp), enabled = pendingActionId == null && current > bounds.minimum) {
                SfImage("minus.circle.fill", if (current <= bounds.minimum) Color.White.copy(alpha = 0.24f) else MagicPalette.parchment, 26.dp)
            }
            var text by remember(prompt.id, current) { mutableStateOf(current.toString()) }
            BasicTextField(text, { value -> text = value.filter { it.isDigit() || it == '-' }.take(10); text.toIntOrNull()?.let { manualAmountValues[prompt.id] = bounds.clamp(it) } },
                Modifier.widthIn(min = 70.dp).defaultMinSize(minHeight = 44.dp).padding(top = 10.dp)
                    .semantics { contentDescription = "Amount, from ${bounds.minimum} to ${bounds.maximum}" },
                enabled = pendingActionId == null, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                textStyle = sf(16f, SfWeight.black).copy(color = Color.White, textAlign = TextAlign.Center), cursorBrush = SolidColor(Color.White))
            PressableBox({ manualAmountValues[prompt.id] = bounds.stepping(current, 1) }, Modifier.size(44.dp), enabled = pendingActionId == null && current < bounds.maximum) {
                SfImage("plus.circle.fill", MagicPalette.parchment, 26.dp)
            }
            Spacer(Modifier.weight(1f))
            promptButton("Submit $current", "${prompt.id}-amount-$current",
                command(type, prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, amount = current, amounts = listOf(current)),
                systemImage = "number", buttonModifier = Modifier.widthIn(min = 120.dp))
        }
    }

    @Composable
    fun confirmationPicker(confirmation: XmagePromptConfirmation, prompt: PromptEnvelopeV2) {
        val yes = explicitConfirmationCommand(confirmation.yesCommand, prompt)
        val no = explicitConfirmationCommand(confirmation.noCommand, prompt)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            promptButton(confirmation.yesLabel ?: "Yes", "${prompt.id}-yes", yes, systemImage = "checkmark.circle", buttonModifier = Modifier.weight(1f))
            promptButton(confirmation.noLabel ?: "No", "${prompt.id}-no", no, systemImage = "xmark.circle", buttonModifier = Modifier.weight(1f))
        }
        if (yes == null || no == null) Text("XMage did not expose explicit yes/no command metadata for every option, so missing choices stay disabled.",
            color = MagicPalette.warningAmber.copy(alpha = 0.82f), style = sf(9f, SfWeight.bold), maxLines = 3)
    }

    @Composable
    fun orderPicker(title: String, prompt: PromptEnvelopeV2, type: String, options: List<Pair<String, String>>) {
        val defaultIds = options.map { it.first }
        val currentIds = if (orderPromptId == prompt.id && orderedIds.isNotEmpty()) orderedIds else defaultIds
        val labels = options.toMap()
        val canSubmit = currentIds.isNotEmpty() && currentIds.toSet() == defaultIds.toSet() && currentIds.size == defaultIds.size
        fun move(from: Int, delta: Int) {
            if (orderPromptId != prompt.id || orderedIds.isEmpty()) { orderPromptId = prompt.id; orderedIds = defaultIds }
            orderedIds = PromptCommandBuilder.movedOrder(orderedIds, from, from + delta)
        }
        PromptMiniLabel(title)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            currentIds.forEachIndexed { index, id ->
                Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.06f), RoundedCornerShape(8.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(8.dp)).padding(horizontal = 7.dp, vertical = 5.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("${index + 1}", Modifier.width(18.dp).background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(6.dp)).padding(vertical = 4.dp),
                        color = MagicPalette.antiqueGold, style = sf(10f, SfWeight.black), textAlign = TextAlign.Center)
                    FitText(labels[id] ?: id, sf(10f, SfWeight.bold), Modifier.weight(1f), color = Color.White.copy(alpha = 0.84f), maxLines = 2, minimumScale = 0.7f)
                    PressableBox({ move(index, -1) }, Modifier.size(44.dp), enabled = pendingActionId == null && index > 0) {
                        SfImage("chevron.up", if (index == 0) Color.White.copy(alpha = 0.24f) else MagicPalette.parchment, 12.dp)
                    }
                    PressableBox({ move(index, 1) }, Modifier.size(44.dp), enabled = pendingActionId == null && index < currentIds.size - 1) {
                        SfImage("chevron.down", if (index == currentIds.size - 1) Color.White.copy(alpha = 0.24f) else MagicPalette.parchment, 12.dp)
                    }
                }
            }
            promptButton("Submit order", "${prompt.id}-$type-ordered",
                if (canSubmit) command(type, prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, currentIds) else null,
                subtitle = if (canSubmit) "${currentIds.size} items" else "Order incomplete", systemImage = "arrow.up.arrow.down")
        }
    }

    @Composable
    fun manaSymbolButton(symbol: String, pendingId: String, label: String, command: GameCommand?, amount: Int? = null) {
        PressableBox({ command?.let { runCommand(it, label, pendingId) } }, Modifier.size(44.dp).semantics { contentDescription = label }, enabled = pendingActionId == null) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Box(contentAlignment = Alignment.Center) {
                    ManaSymbolView(symbol, if (amount != null) 24.dp else 26.dp)
                    if (pendingActionId == pendingId) CircularProgressIndicator(Modifier.size(14.dp), color = Color.White, strokeWidth = 1.5.dp)
                }
                if (amount != null) Text("x$amount", color = Color.White.copy(alpha = 0.76f), style = sf(8f, SfWeight.black))
            }
        }
    }

    @Composable
    fun placeholderSubmit(title: String, button: String, prompt: PromptEnvelopeV2, type: String, ids: List<String>) {
        val canSubmit = if (isOrderCommand(type)) PromptCommandBuilder.canSubmitShownOrder(ids) else ids.isNotEmpty()
        PromptMiniLabel(title)
        promptButton(button, "${prompt.id}-$type", if (canSubmit) command(type, prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, ids) else null,
            subtitle = when { ids.isEmpty() -> "Waiting for exposed ids"; isOrderCommand(type) && !PromptCommandBuilder.canSubmitShownOrder(ids) -> "No auto-order"; else -> "${ids.size} ids" },
            systemImage = if (type == "order_triggers") "arrow.up.arrow.down" else "magnifyingglass")
    }

    @Composable
    fun unsupportedBox(title: String, detail: String, footer: String, color: Color) {
        Column(Modifier.fillMaxWidth().background(color.copy(alpha = 0.10f), RoundedCornerShape(8.dp)).border(1.dp, color.copy(alpha = 0.24f), RoundedCornerShape(8.dp))
            .padding(horizontal = 7.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(title, color = color, style = sf(10f, SfWeight.black), maxLines = 2)
            Text(detail, color = Color.White.copy(alpha = 0.68f), style = sf(9f, SfWeight.bold), maxLines = 3)
            Text(footer, color = Color.White.copy(alpha = 0.44f), style = sf(8f, SfWeight.bold), maxLines = 1)
        }
    }

    @Composable
    fun promptV2Section(prompt: PromptEnvelopeV2) {
        val promptId = prompt.responseCommand?.promptId ?: prompt.id
        PromptPanelSection(presentation?.title ?: "Choose", "", isHighlighted = true, isEmbedded = true) {
            GameRulesText(PromptDisplayText.clean(prompt.message), symbolSize = 16.dp, style = sf(16f, SfWeight.semibold), color = Color.White.copy(alpha = 0.92f))
            if (isManaOrPaymentPrompt(prompt) && sourceManaActions.isNotEmpty()) {
                PromptMiniLabel(if (prompt.responseCommand?.type?.lowercase() == "pay_cost") "Pay with sources" else "Available mana sources")
                AdaptiveGrid(112f, 6f, sourceManaActions.size) { index ->
                    val action = sourceManaActions[index]
                    val id = action.sourceInstanceId ?: action.cardInstanceId
                    val name = action.cardName?.takeIf { it.isNotEmpty() } ?: snapshot.human?.zones?.battlefield?.firstOrNull { it.instanceId == id }?.card?.name ?: action.label
                    PanelActionButton({ runAction(action) }, Modifier.fillMaxWidth(), isPrimary = true, enabled = pendingActionId == null) {
                        PromptButtonLabel("Tap $name", action.producedMana?.takeIf { it.isNotEmpty() }?.joinToString(" ") { "{$it}" } ?: LegalActionDisplay.actionDetail(action),
                            "sparkles", pendingActionId == action.id)
                    }
                }
            }
            if (PromptCommandBuilder.isCommanderReplacement(prompt)) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                promptButton("Command zone", "${prompt.id}-command-zone", command("commander_replacement", promptId, prompt.playerId, useCommandZone = true), buttonModifier = Modifier.weight(1f))
                promptButton("Original zone", "${prompt.id}-original-zone", command("commander_replacement", promptId, prompt.playerId, useCommandZone = false), buttonModifier = Modifier.weight(1f))
            }
            val confirmation = prompt.confirmation
            if (confirmation != null && isConfirmationPrompt(prompt)) confirmationPicker(confirmation, prompt)
            val choices = prompt.choices
            if (!choices.isNullOrEmpty()) {
                LaunchedEffect("${prompt.id}:${prompt.messageId}") { choiceSearch = "" }
                val matching = choices.filter { choices.size <= 20 || choiceSearch.isEmpty() || it.label.contains(choiceSearch, ignoreCase = true) }
                if (choices.size > 20) BasicTextField(choiceSearch, { choiceSearch = it }, Modifier.fillMaxWidth()
                    .background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(6.dp)).padding(10.dp).semantics { contentDescription = "Search choices" },
                    singleLine = true, textStyle = SfText.body().copy(color = Color.White), cursorBrush = SolidColor(Color.White),
                    decorationBox = { inner -> Box { if (choiceSearch.isEmpty()) Text("Search choices", color = Color.White.copy(alpha = 0.4f), style = SfText.body()); inner() } })
                if (matching.isEmpty()) Text("No matching choices", color = MagicPalette.parchment.copy(alpha = 0.6f), style = SfText.subheadline())
                else optionGrid(matching.map { it.id to it.label }, prompt, "resolve_choice", "checkmark.circle")
            }
            prompt.targets?.takeIf { it.isNotEmpty() }?.let { optionGrid(it.map { t -> t.id to t.label }, prompt, "choose_target", "scope") }
            prompt.players?.takeIf { it.isNotEmpty() }?.let { players ->
                optionGrid(players.map { p: XmagePromptPlayer -> p.playerId to (p.life?.let { life -> "${p.label} ($life)" } ?: p.label) }, prompt, "choose_player", "person.crop.circle")
            }
            prompt.cards?.takeIf { it.isNotEmpty() }?.let { cards -> if (isSearchPrompt(prompt)) searchSelectionPicker(cards, prompt) else cardPicker(cards, prompt) }
            prompt.modes?.takeIf { it.isNotEmpty() }?.let { optionGrid(it.map { m -> m.id to m.label }, prompt, "choose_mode", "square.stack.3d.up") }
            prompt.abilities?.takeIf { it.isNotEmpty() }?.let { abilityPicker(it, prompt) }
            prompt.piles?.takeIf { it.isNotEmpty() }?.let { pilePicker(it, prompt) }
            val amounts = prompt.amounts
            val multiAmounts = prompt.multiAmounts
            when {
                !amounts.isNullOrEmpty() -> amountPicker(amounts, prompt)
                !multiAmounts.isNullOrEmpty() -> multiAmountPicker(multiAmounts, prompt)
                isAmountPrompt(prompt) -> manualAmountPicker(prompt)
            }
            prompt.orderedItems?.takeIf { it.isNotEmpty() }?.let { items -> orderPicker("Order", prompt, "order_items", items.map { it.id to it.label }) }
            prompt.manaChoices?.takeIf { it.isNotEmpty() }?.let { manaChoices ->
                PromptMiniLabel("Mana")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (choice: XmagePromptManaChoice in manaChoices) {
                        val symbol = choice.manaType ?: choice.id
                        manaSymbolButton(symbol, "${prompt.id}-mana-choice-${choice.id}", "Pay with ${choice.label}",
                            command(if (snapshot.source == "xmage-ondevice") "play_mana" else prompt.responseCommand?.type ?: "play_mana", promptId, prompt.playerId,
                                listOf(symbol), manaType = symbol), choice.amount)
                    }
                }
            }
            if (prompt.manaChoices.isNullOrEmpty() && isChooseColorPrompt(prompt)) {
                PromptMiniLabel("Choose Color")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (mana in listOf("W", "U", "B", "R", "G", "C")) manaSymbolButton(mana, "${prompt.id}-choose-color-$mana", mana,
                        command(prompt.responseCommand?.type ?: "choose_mana", promptId, prompt.playerId, manaType = mana))
                }
            } else if (prompt.manaChoices.isNullOrEmpty() && isManaPrompt(prompt) && availableManaSymbols.isNotEmpty()) {
                PromptMiniLabel("Mana")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (mana in availableManaSymbols) manaSymbolButton(mana, "${prompt.id}-mana-$mana", "Pay with $mana mana",
                        command("play_mana", promptId, prompt.playerId, manaType = mana))
                }
            }
            if (isTriggerOrderPrompt(prompt)) {
                val options = prompt.cards?.takeIf { it.isNotEmpty() }?.map { it.id to it.card.name }
                    ?: prompt.targets?.takeIf { it.isNotEmpty() }?.map { it.id to it.label }
                    ?: prompt.choices?.takeIf { it.isNotEmpty() }?.map { it.id to it.label } ?: emptyList()
                orderPicker("Trigger order", prompt, "order_triggers", options)
            }
            if (isSearchPrompt(prompt) && prompt.cards.isNullOrEmpty() && prompt.targets.isNullOrEmpty()) {
                placeholderSubmit("Search/select", "Submit exposed selection", prompt, "search_select", prompt.targetIds ?: emptyList())
            } else if (isCardSelectionPrompt(prompt) && prompt.cards.isNullOrEmpty() && prompt.targets.isNullOrEmpty()) {
                placeholderSubmit("Select card on battlefield", "Submit selected card", prompt, prompt.responseCommand?.type ?: "choose_card",
                    selectedCard?.let { listOf(it.id) } ?: prompt.targetIds ?: emptyList())
            }
            if (isPlayerSelectionPrompt(prompt) && prompt.players.isNullOrEmpty()) {
                optionGrid(snapshot.players.map { it.playerId to snapshot.playerLabel(it.playerId) }, prompt, prompt.responseCommand?.type ?: "choose_player", "person.crop.circle")
            }
            if (isDamageAssignmentPrompt(prompt) && prompt.multiAmounts.isNullOrEmpty()) {
                PromptMiniLabel("Damage Assignment")
                unsupportedBox("Unsupported prompt/action: damage assignment is not mobile-safe yet.",
                    "No default damage split will be submitted. Refresh or reconnect after the bridge exposes attacker/blocker allocation choices.",
                    "${prompt.method} | ${prompt.responseKind}", Color(0xFFFF9500))
            }
            if (!hasRenderablePromptControls(prompt)) {
                Text("Unsupported prompt/action: XMage has not exposed a mobile-safe control for this route yet.",
                    color = MagicPalette.warningAmber.copy(alpha = 0.9f), style = sf(10f, SfWeight.bold), maxLines = 3)
            }
        }
    }

    @Composable
    fun legacyPromptSection(prompt: PromptEnvelope) {
        PromptPanelSection("Choose", "", isHighlighted = true) {
            Text(prompt.message, color = Color.White.copy(alpha = 0.86f), style = sf(11f, SfWeight.bold), maxLines = 3)
            val choices = prompt.choices
            val targets = prompt.targetIds
            if (!choices.isNullOrEmpty()) AdaptiveGrid(92f, 6f, choices.size) { index ->
                val choice = choices[index]
                promptButton(choice.label, "${prompt.id}-${choice.id}", command("resolve_choice", prompt.id, prompt.playerId, listOf(choice.id)), systemImage = yesNoIcon(choice.label))
            }
            if (!targets.isNullOrEmpty()) AdaptiveGrid(92f, 6f, targets.size) { index ->
                val id = targets[index]
                promptButton(id, "${prompt.id}-$id", command("choose_target", prompt.id, prompt.playerId, listOf(id)))
            }
            if (choices.isNullOrEmpty() && targets.isNullOrEmpty()) unsupportedBox("Unsupported prompt/action",
                "No default answer will be sent. Refresh or reconnect after the bridge exposes a mobile-safe response.",
                "${prompt.method} | ${prompt.responseKind}", MagicPalette.warningAmber)
        }
    }

    @Composable
    fun choicePromptSection(prompt: ChoicePrompt) {
        PromptPanelSection("Choice", "${prompt.minChoices}-${prompt.maxChoices}", isHighlighted = true) {
            Text(prompt.message, color = Color.White.copy(alpha = 0.86f), style = sf(11f, SfWeight.bold), maxLines = 3)
            AdaptiveGrid(92f, 6f, prompt.choices.size) { index ->
                val choice = prompt.choices[index]
                val composedId = "${prompt.id}-${choice.id}"
                val action = legalActions.firstOrNull { a -> a.id == choice.id || a.id == composedId || a.targetIds?.contains(choice.id) == true ||
                    a.validTargetIds?.contains(choice.id) == true || a.id.endsWith("-${choice.id}") }
                val fallback = command("resolve_choice", prompt.id, prompt.playerId, listOf(choice.id))
                PanelActionButton({ if (action != null) runAction(action) else fallback?.let { runCommand(it, choice.label, composedId) } }, Modifier.fillMaxWidth(),
                    isPrimary = action?.isPrimary == true, enabled = pendingActionId == null && (action != null || fallback != null)) {
                    PromptButtonLabel(choice.label, systemImage = yesNoIcon(choice.label), isPending = pendingActionId == action?.id || pendingActionId == composedId)
                }
            }
        }
    }

    val shape = RoundedCornerShape(8.dp)
    Box(modifier) {
        Column(Modifier.fillMaxSize().glow(Color.Black.copy(alpha = 0.22f), 8.dp, 8.dp)
            .background(Brush.verticalGradient(listOf(MagicPalette.iron.copy(alpha = 0.88f), MagicPalette.leather.copy(alpha = 0.80f), MagicPalette.laneWood.copy(alpha = 0.70f))), shape)
            .border(1.dp, MagicPalette.borderBronze.copy(alpha = 0.46f), shape).padding(8.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("wand.and.stars", MagicPalette.antiqueGold, 12.dp)
                Text(presentation?.title?.uppercase() ?: "PROMPT", color = MagicPalette.antiqueGold, style = sf(10f, SfWeight.black))
                Spacer(Modifier.weight(1f))
                FitText(priorityLabel, sf(8f, SfWeight.black), color = Color.White.copy(alpha = 0.68f), minimumScale = 0.7f)
                GameIconButton("xmark", { GameHaptics.selection(haptics); dismiss() }, small = true, contentDescription = "Cancel prompt details")
            }
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(bottom = 10.dp).semantics { contentDescription = "prompt.details.scroll" },
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (presentation != null && snapshot.promptEnvelopeV2 == null && snapshot.promptEnvelope == null) {
                    PromptPanelSection("Choose", "", isHighlighted = presentation.isUnsupported) {
                        GameRulesText(PromptDisplayText.clean(presentation.message), symbolSize = 16.dp, style = sf(15f, SfWeight.medium),
                            color = if (presentation.isUnsupported) MagicPalette.warningAmber else Color.White.copy(alpha = 0.78f))
                    }
                }
                val v2 = snapshot.promptEnvelopeV2
                val legacy = snapshot.promptEnvelope
                if (v2 != null) promptV2Section(v2) else if (legacy != null) legacyPromptSection(legacy)
                snapshot.choicePrompt?.let { choicePromptSection(it) }
                if (showsGameSurfaceSections) {
                    if (selectedCardActions.isNotEmpty() && selectedCard != null) actionSection("Selected", selectedCard.card.name, selectedCardActions)
                    else if (selectedCard != null && snapshot.human?.zones?.hand?.any { it.instanceId == selectedCard.instanceId } == true) {
                        PromptPanelSection("Selected", selectedCard.card.name) {
                            Text(selectedCardBlockedReason(snapshot, selectedCard, pendingActionId), color = Color.White.copy(alpha = 0.72f), style = sf(10f, SfWeight.bold), maxLines = 3)
                            PanelActionButton({ selection.inspectedCard = selectedCard }, Modifier.fillMaxWidth(), enabled = pendingActionId == null) {
                                PromptButtonLabel("Inspect", "Long press cards also opens this", "doc.text.magnifyingglass", false)
                            }
                        }
                    }
                    if (spellsAndLands.isNotEmpty()) actionSection("Spells & Lands", "${spellsAndLands.size}", spellsAndLands)
                    if (abilitiesAndMana.isNotEmpty()) actionSection("Abilities & Mana", "${abilitiesAndMana.size}", abilitiesAndMana)
                    if (passActions.isNotEmpty()) actionSection("Pass / Steps", "${passActions.size}", passActions,
                        compact = spellsAndLands.isNotEmpty() || abilitiesAndMana.isNotEmpty() || selectedCardActions.isNotEmpty())
                    if (otherActions.isNotEmpty()) actionSection("Other Actions", "${otherActions.size}", otherActions)
                    MobileSurfacesPanel(snapshot, viewZone)
                }
            }
        }
        selection.inspectedCard?.let { card ->
            Box(Modifier.matchParentSize()) {
                CardInspector(card, Modifier.fillMaxSize())
                Text("Close card", Modifier.align(Alignment.TopEnd).padding(8.dp).defaultMinSize(minHeight = 44.dp)
                    .clickable { selection.inspectedCard = null }.padding(8.dp), color = io.magicmobile.android.ui.rgb(0.04, 0.52, 1.0), style = SfText.body())
            }
        }
    }
}

private fun selectedCardBlockedReason(snapshot: GameSnapshot, card: ZoneCard, pendingActionId: String?): String = when {
    pendingActionId != null -> "Action sent. Waiting for XMage to confirm the next game state."
    snapshot.waitingOnPlayerId != null && !snapshot.isViewer(snapshot.waitingOnPlayerId) ->
        "Waiting on ${snapshot.playerLabel(snapshot.waitingOnPlayerId)}. XMage has not exposed a cast/play action for this card."
    snapshot.priorityPlayerId != null && !snapshot.isViewer(snapshot.priorityPlayerId) -> "Not your priority. XMage will expose cast/play actions when this card is legal."
    snapshot.promptEnvelopeV2 != null || snapshot.promptEnvelope != null || snapshot.choicePrompt != null ->
        "Answer the current XMage prompt first. This card remains inspectable, but XMage is not accepting a cast/play action for it right now."
    else -> "XMage did not expose a cast/play action for ${card.card.name}. It may need mana, timing, a target, or another required choice."
}

/** Compact-height (landscape phone) check for sizing ability art, like `verticalSizeClass == .compact`. */
@Composable
fun LocalConfigurationHeightCompact(): Boolean = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp < 480

/** The zones summary under the choices panel. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MobileSurfacesPanel(snapshot: GameSnapshot, viewZone: (String, List<ZoneCard>) -> Unit) {
    fun unique(cards: List<ZoneCard>): List<ZoneCard> { val seen = mutableSetOf<String>(); return cards.filter { seen.add(it.instanceId) } }
    val xmage = snapshot.xmage
    val stackCards = xmage?.stack?.mapNotNull { it.displaySourceCard }?.takeIf { it.isNotEmpty() } ?: snapshot.players.flatMap { it.zones.stack }
    val stackObjectCount = maxOf(xmage?.stack?.size ?: 0, stackCards.size)
    val stackNames = xmage?.stack?.map { it.displayName }?.filter { it.isNotEmpty() } ?: emptyList()
    val commandCards = unique(snapshot.players.flatMap { it.zones.command } + (xmage?.players?.flatMap { it.command } ?: emptyList()))
    val graveyardCards = unique(snapshot.players.flatMap { it.zones.graveyard } + (xmage?.players?.flatMap { it.zones.graveyard } ?: emptyList()))
    val exileCards = unique(snapshot.players.flatMap { it.zones.exile } + (xmage?.players?.flatMap { it.zones.exile } ?: emptyList()) + (xmage?.exileZones?.flatMap { it.cards } ?: emptyList()))
    val libraryCount = snapshot.players.sumOf { it.zones.visibleLibraryCount }
    val revealed = xmage?.revealed?.flatMap { it.cards } ?: emptyList()
    val lookedAt = xmage?.lookedAt?.flatMap { it.cards } ?: emptyList()
    val priorityOwner = if (snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId) ||
        CompactPromptPopup.compactLegalPromptActions(snapshot).isNotEmpty()) "You" else snapshot.playerLabel(snapshot.priorityPlayerId ?: snapshot.waitingOnPlayerId)
    val summary = when { xmage?.panels?.search == true -> "search"; xmage?.panels?.revealed == true -> "revealed"; xmage?.panels?.lookedAt == true -> "looked"; else -> priorityOwner }
    var commanderDetailsOpen by remember { mutableStateOf(false) }

    PromptPanelSection("Zones", summary) {
        val chips = buildList<@Composable () -> Unit> {
            fun zone(title: String, value: String, icon: String, cards: List<ZoneCard>) = add {
                Box(Modifier.clickable { viewZone(if (title == "Grave") "Graveyard" else title, cards) }.semantics { contentDescription = "$title zone, $value cards" }) {
                    SurfaceChip(title, value, icon)
                }
            }
            zone("Stack", "$stackObjectCount", "sparkles", stackCards)
            zone("Command", "${commandCards.size}", "crown", commandCards)
            zone("Grave", "${graveyardCards.size}", "archivebox", graveyardCards)
            zone("Exile", "${exileCards.size}", "moon.stars", exileCards)
            add { SurfaceChip("Library", "$libraryCount", "books.vertical") }
            if (revealed.isNotEmpty() || xmage?.panels?.revealed == true) zone("Revealed", "${revealed.size}", "eye", revealed)
            if (lookedAt.isNotEmpty() || xmage?.panels?.lookedAt == true) zone("Looked", "${lookedAt.size}", "eye.trianglebadge.exclamationmark", lookedAt)
            xmage?.companion?.takeIf { it.isNotEmpty() }?.let { companions -> zone("Companion", "${companions.flatMap { it.cards }.size}", "person.crop.square", companions.flatMap { it.cards }) }
            add { SurfaceChip("Priority", priorityOwner, "hand.raised") }
            add { SurfaceChip("Actions", "${(snapshot.legalActions ?: emptyList()).size}", "bolt") }
        }
        AdaptiveGrid(76f, 5f, chips.size) { chips[it]() }
        if (snapshot.source == "xmage-ondevice") {
            val named: List<XmageNamedZone> = xmage?.let { it.exileZones + it.revealed + it.lookedAt } ?: emptyList()
            for (group in named) if (group.cards.isNotEmpty()) {
                Text("${group.name} (${group.cards.size})", Modifier.defaultMinSize(minHeight = 44.dp).clickable { viewZone(group.name, group.cards) }.padding(top = 12.dp),
                    color = io.magicmobile.android.ui.rgb(0.04, 0.52, 1.0), style = SfText.body())
            }
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { commanderDetailsOpen = !commanderDetailsOpen },
                verticalAlignment = Alignment.CenterVertically) {
                Text("Commander tax and damage", Modifier.weight(1f), color = io.magicmobile.android.ui.rgb(0.04, 0.52, 1.0), style = SfText.body())
                SfImage(if (commanderDetailsOpen) "chevron.down" else "chevron.right", io.magicmobile.android.ui.rgb(0.04, 0.52, 1.0), 13.dp)
            }
            if (commanderDetailsOpen) for (player in snapshot.players) for (commander in player.commanders ?: emptyList()) {
                Column(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${player.displayName ?: player.playerId} · ${commander.name ?: "Commander ${commander.id.take(8)}"}", color = MagicPalette.parchment, style = SfText.caption(SfWeight.bold))
                    Text("Command-zone casts: ${commander.castsFromCommandZone?.toString() ?: "unknown"} · Next tax: ${commander.commanderTax?.let { "{$it}" } ?: "unknown"}",
                        color = MagicPalette.parchment, style = SfText.caption())
                    val damage = commander.damageToPlayers
                    if (damage != null) for (recipient in snapshot.players) Text("Damage to ${snapshot.playerLabel(recipient.playerId)}: ${damage[recipient.playerId] ?: 0}",
                        color = MagicPalette.parchment, style = SfText.caption())
                    else Text("Commander damage unavailable", color = MagicPalette.parchment, style = SfText.caption())
                }
            }
        }
        stackNames.firstOrNull()?.let { top ->
            FitText("Stack top: $top", sf(10f, SfWeight.bold), color = MagicPalette.priorityArcane.copy(alpha = 0.88f), minimumScale = 0.64f)
        }
    }
}
