package io.magicmobile.android.board

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.CardChoicePlan
import io.magicmobile.android.game.ChoicePromptOption
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.PortraitInteractionPolicy
import io.magicmobile.android.game.PromptCommandBuilder
import io.magicmobile.android.game.PromptEnvelopeV2
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.game.stringArrayValue
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb

private val choicePurple = rgb(0.69, 0.32, 0.87)

/**
 * BoardCardChoiceView.swift: one UUID per native PICK_TARGET response. XMage owns later
 * selection, deselection and ordering prompts; the UI never invents a batch response.
 */
@Composable
fun BoardCardChoiceView(snapshot: GameSnapshot, prompt: PromptEnvelopeV2, pendingActionId: String?, runCommand: (GameCommand, String, String) -> Unit,
                        runAction: (LegalAction) -> Unit, commitPlan: (CardChoicePlan) -> Unit, close: () -> Unit) {
    val focusManager = LocalFocusManager.current
    var selectedID by remember { mutableStateOf<String?>(null) }
    var draftIDs by remember { mutableStateOf(listOf<String>()) }
    var topIDs by remember { mutableStateOf(listOf<String>()) }
    var search by remember { mutableStateOf("") }
    var searchFocused by remember { mutableStateOf(false) }
    var inspected by remember { mutableStateOf<ZoneCard?>(null) }
    val cards = prompt.cards ?: emptyList()
    val targets = run { val seen = cards.map { it.id }.toMutableSet(); (prompt.targets ?: emptyList()).filter { seen.add(it.id) } }
    val chosenIDs = prompt.options?.get("chosenTargets").stringArrayValue ?: emptyList()
    val draftKind = if (CardChoicePlan.supportsDraft(prompt)) CardChoicePlan.kind(prompt) else null
    val selectableIDs = cards.filter { it.isPromptSelectable }.map { it.id }
    val draftActive = draftKind != null
    val selected: Triple<String, String, Boolean>? = selectedID?.let { id ->
        cards.firstOrNull { it.id == id && it.isPromptSelectable }?.let { Triple(it.id, it.card.name, true) }
            ?: targets.firstOrNull { it.id == id }?.let { Triple(it.id, it.label, false) }
    }
    val filteredCards = cards.filter { PortraitInteractionPolicy.matchesCardSearch(it, search) }
    val largeText = BoardMotion.largeText

    LaunchedEffect(Unit) {
        if (draftActive) {
            draftIDs = chosenIDs.filter { it in selectableIDs }
            topIDs = selectableIDs.filter { it !in draftIDs }
        }
    }

    fun toggleSelection(id: String) {
        if (pendingActionId != null || !(cards.any { it.id == id && it.isPromptSelectable } || targets.any { it.id == id })) return
        val kind = draftKind
        if (kind != null) {
            when {
                kind == CardChoicePlan.Kind.TOP_ORDER || kind == CardChoicePlan.Kind.BOTTOM_ORDER -> draftIDs = CardChoicePlan.toggled(draftIDs, id)
                id in draftIDs -> { draftIDs = CardChoicePlan.toggled(draftIDs, id); if (kind == CardChoicePlan.Kind.SCRY) topIDs = topIDs + id }
                else -> { draftIDs = CardChoicePlan.toggled(draftIDs, id); topIDs = topIDs - id }
            }
            return
        }
        selectedID = if (selectedID == id) null else id
    }

    fun selectionState(id: String): String {
        val kind = draftKind
        if (kind != null) {
            val index = draftIDs.indexOf(id)
            if (index >= 0) return when (kind) {
                CardChoicePlan.Kind.SCRY -> "Put bottom, position ${index + 1}"
                CardChoicePlan.Kind.SELECTION -> "Selected ${index + 1}"
                else -> "Position ${index + 1}"
            }
            val topIndex = topIDs.indexOf(id)
            if (kind == CardChoicePlan.Kind.SCRY && topIndex >= 0) return "Keep top, position ${topIndex + 1}"
            return if (kind == CardChoicePlan.Kind.SCRY) "Keep top" else "Tap to select"
        }
        if (selectedID == id) return if (id in chosenIDs) "Selected to remove" else "Selected"
        return if (id in chosenIDs) "Chosen · select to remove" else "Not selected"
    }

    fun move(id: String, delta: Int, top: Boolean) {
        val ids = (if (top) topIDs else draftIDs).toMutableList()
        val source = ids.indexOf(id)
        if (source < 0 || source + delta !in ids.indices) return
        java.util.Collections.swap(ids, source, source + delta)
        if (top) topIDs = ids else draftIDs = ids
    }

    val draftCountIsValid = CardChoicePlan.selectionBounds(prompt.message)?.let { draftIDs.size >= it.first && draftIDs.size <= it.second } ?: false

    fun confirmSelection() {
        if (draftActive) {
            val kind = CardChoicePlan.kind(prompt)
            commitPlan(CardChoicePlan(snapshot, prompt, draftIDs, if (kind == CardChoicePlan.Kind.SCRY) topIDs else emptyList()))
            return
        }
        val chosen = selected ?: return
        if (pendingActionId != null) return
        val command = PromptCommandBuilder.command(snapshot.id, prompt, prompt.responseCommand?.type ?: "choose_target", prompt.id, prompt.playerId,
            listOf(chosen.first)) ?: return
        runCommand(command, "Choose ${chosen.second}", "${prompt.id}-card-choice")
    }

    @Composable
    fun cardArtwork(card: ZoneCard, width: Dp) {
        val selectable = card.isPromptSelectable
        val marked = card.id in draftIDs || selectedID == card.id || card.id in chosenIDs
        Box(Modifier.alpha(if (selectable) 1f else 0.48f)) {
            Box(Modifier.glow(if (selectable) choicePurple.copy(alpha = 0.5f) else Color.Transparent, 6.dp, 8.dp)
                .border(3.dp, if (selectable) choicePurple else Color.Transparent, RoundedCornerShape(8.dp))) {
                CardTile(card, card.id in draftIDs || selectedID == card.id, zoneName = "Choice", width = width, height = width * 1.4f)
            }
            if (marked) Text(if (draftActive) selectionState(card.id) else "✓", Modifier.align(Alignment.TopEnd).background(choicePurple, CircleShape).padding(4.dp),
                color = Color.White, style = SfText.caption2(SfWeight.bold))
        }
    }

    @Composable
    fun cardRow(card: ZoneCard, width: Dp) {
        Column(Modifier.width(width), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Box(Modifier.semantics { contentDescription = "${card.card.name}, ${if (card.isPromptSelectable) "legal choice" else "not a legal choice"}, ${selectionState(card.id)}" }
                .onCardInteraction(tap = { toggleSelection(card.id) }, inspect = { inspected = card }, release = { if (inspected?.id == card.id) inspected = null })) {
                cardArtwork(card, width)
            }
            Text(card.card.name, color = MagicPalette.parchment, style = SfText.caption(SfWeight.semibold), maxLines = 2)
            if (draftActive || selectedID == card.id || card.id in chosenIDs) Text(selectionState(card.id), color = MagicPalette.parchment, style = SfText.caption2())
        }
    }

    @Composable
    fun compactCardRow(card: ZoneCard) {
        val eligibility = if (card.isPromptSelectable) "legal choice" else "not a legal choice"
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 62.dp)
            .onCardInteraction(tap = { toggleSelection(card.id) }, inspect = { inspected = card }, release = { if (inspected?.id == card.id) inspected = null }),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            cardArtwork(card, 44.dp)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(card.card.name, color = MagicPalette.parchment, style = SfText.subheadline(SfWeight.semibold))
                Text("$eligibility · ${selectionState(card.id)}", color = MagicPalette.parchment, style = SfText.caption())
            }
        }
    }

    @Composable
    fun targetRow(target: ChoicePromptOption) {
        val isSelected = selectedID == target.id
        val isMarked = isSelected || target.id in chosenIDs
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
            .background(if (isSelected) Color(0xFFAF52DE).copy(alpha = 0.25f) else Color.White.copy(alpha = 0.06f), RoundedCornerShape(8.dp))
            .clickable(enabled = pendingActionId == null) { toggleSelection(target.id) }.padding(horizontal = 10.dp)
            .semantics { contentDescription = "${target.label}, ${selectionState(target.id)}" },
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage(if (isMarked) "checkmark.circle.fill" else "circle", choicePurple, 18.dp)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(target.label, color = MagicPalette.parchment, style = SfText.body())
                if (isMarked) Text(selectionState(target.id), color = MagicPalette.parchment, style = SfText.caption())
            }
        }
    }

    @Composable
    fun orderRows(ids: List<String>, title: String, top: Boolean) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = MagicPalette.parchment, style = SfText.caption(SfWeight.semibold))
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                ids.forEachIndexed { index, id ->
                    Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(6.dp)).padding(5.dp),
                        horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("${index + 1}. ${cards.firstOrNull { it.id == id }?.card?.name ?: "Card"}", Modifier.weight(1f), color = MagicPalette.parchment, style = SfText.caption())
                        PressableBox({ move(id, -1, top) }, Modifier.size(44.dp).semantics { contentDescription = "Move earlier" }, enabled = index > 0 && pendingActionId == null) {
                            SfImage("chevron.up", if (index > 0) rgb(0.04, 0.52, 1.0) else Color.White.copy(alpha = 0.3f), 14.dp)
                        }
                        PressableBox({ move(id, 1, top) }, Modifier.size(44.dp).semantics { contentDescription = "Move later" }, enabled = index < ids.size - 1 && pendingActionId == null) {
                            SfImage("chevron.down", if (index < ids.size - 1) rgb(0.04, 0.52, 1.0) else Color.White.copy(alpha = 0.3f), 14.dp)
                        }
                    }
                }
            }
        }
    }

    @Composable
    fun draftOrderControls() {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            if (draftKind == CardChoicePlan.Kind.SCRY) {
                Text("Tap cards to Put bottom or Keep top. Use arrows to set each order.", color = MagicPalette.parchment, style = SfText.caption())
                orderRows(draftIDs, "Put bottom · first to last", false)
                orderRows(topIDs, "Keep top · top first", true)
            } else {
                Text("Tap cards in order. Tap a numbered card again to remove it.", color = MagicPalette.parchment, style = SfText.caption())
                CardChoicePlan.selectionBounds(prompt.message)?.let { (min, max) ->
                    Text(if (min == max) "${draftIDs.size} of $max selected" else "${draftIDs.size} selected · choose $min–$max",
                        color = MagicPalette.parchment, style = SfText.caption(SfWeight.semibold))
                }
                orderRows(draftIDs, "Choice order", false)
            }
        }
    }

    @Composable
    fun emptySearch() {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("No cards match your search.", Modifier.weight(1f), color = MagicPalette.parchment, style = SfText.subheadline())
            Text("Clear search", Modifier.defaultMinSize(minHeight = 44.dp).clickable { search = "" }.padding(top = 12.dp), color = rgb(0.04, 0.52, 1.0), style = SfText.body())
        }
    }

    @Composable
    fun closeButton() {
        PressableBox(close, Modifier.size(44.dp).semantics { contentDescription = "Close card choices" }) { SfImage("xmark", rgb(0.04, 0.52, 1.0), 16.dp) }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.58f)).clickable(enabled = false) {}, contentAlignment = Alignment.Center) {
        val sizeW = maxWidth.value; val sizeH = maxHeight.value
        val compact = cards.size in 1..2
        val landscape = sizeW > sizeH
        val keyboardCompact = searchFocused && cards.size > 6 && sizeH < 400
        val sideBySideDraft = draftActive && sizeW >= 600 && sizeW > sizeH && !largeText && !keyboardCompact
        val height = maxOf(0f, minOf(sizeH - if (keyboardCompact) 12 else 24, 680f))
        val headerLimit = if (keyboardCompact) 44f else minOf(72f, maxOf(44f, height * 0.2f))
        val searchHeight = if (cards.size > 6 && !keyboardCompact) 44f else 0f
        val pendingHeight = if (pendingActionId != null) 32f else 0f
        val controlsHeight = headerLimit + searchHeight + (if (keyboardCompact) 32f else 112f) + pendingHeight
        val maximumCardWidth = if (compact) 180f else 130f
        val heightLimitedCard = maxOf(if (keyboardCompact) 70f else 90f, minOf(maximumCardWidth, (height - controlsHeight) / 1.4f))
        val preferredWidth = when {
            sideBySideDraft -> 600f
            compact -> if (cards.size == 1) 280f else minOf(420f, maxOf(350f, heightLimitedCard * 2 + 60))
            else -> if (landscape) 600f else 420f
        }
        val width = maxOf(0f, minOf(sizeW - 24, preferredWidth))
        val orderColumnWidth = if (sideBySideDraft) minOf(220f, maxOf(180f, width * 0.33f)) else 0f
        val gridWidth = width - if (sideBySideDraft) orderColumnWidth + 12 else 0f
        val columnCount = if (compact && cards.size == 2 && gridWidth >= 240) 2 else 1
        val availableCardWidth = (gridWidth - 48 - (columnCount - 1) * 12) / columnCount
        val cardWidth = maxOf(90f, minOf(heightLimitedCard, availableCardWidth))
        val panelHeight = if (draftActive) height else if (compact && targets.isEmpty()) minOf(height, cardWidth * 1.4f + controlsHeight) else height

        @Composable
        fun choiceItems() {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (targets.isNotEmpty()) {
                    Text("Other targets", color = MagicPalette.parchment, style = SfText.subheadline(SfWeight.semibold))
                    targets.forEach { targetRow(it) }
                }
                if (compact) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally)) {
                    filteredCards.forEach { cardRow(it, cardWidth.dp) }
                } else {
                    val columns = maxOf(1, ((gridWidth - 16 + 12) / (cardWidth + 12)).toInt())
                    val cellWidth = ((gridWidth - 16 - (columns - 1) * 12) / columns).coerceAtLeast(cardWidth)
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        filteredCards.chunked(columns).forEach { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                row.forEach { card -> Box(Modifier.width(cellWidth.dp), contentAlignment = Alignment.TopCenter) { cardRow(card, cardWidth.dp) } }
                            }
                        }
                    }
                }
                if (filteredCards.isEmpty() && search.isNotEmpty()) emptySearch()
                else if (cards.none { it.isPromptSelectable } && targets.isEmpty()) {
                    Text("No legal cards to select. You can still hold a card to inspect it.", color = MagicPalette.parchment, style = SfText.subheadline())
                }
            }
        }

        Column(Modifier.width(width.dp).height(panelHeight.dp).background(MagicPalette.iron, RoundedCornerShape(18.dp))
            .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.6f), RoundedCornerShape(18.dp)).padding(if (keyboardCompact) 8.dp else 12.dp)
            .semantics { contentDescription = "Card choice dialog" }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!keyboardCompact) Row(verticalAlignment = Alignment.Top) {
                Box(Modifier.weight(1f).heightIn(min = 24.dp, max = headerLimit.dp).verticalScroll(rememberScrollState())) {
                    Text(prompt.message, color = MagicPalette.parchment, style = SfText.headline())
                }
                Spacer(Modifier.width(8.dp)); closeButton()
            }
            if (cards.size > 6) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                BasicTextField(search, { search = it }, Modifier.weight(1f).defaultMinSize(minHeight = 44.dp)
                    .background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(6.dp)).padding(horizontal = 10.dp, vertical = 12.dp)
                    .onFocusChanged { searchFocused = it.isFocused }.semantics { contentDescription = "board.choice.search" },
                    singleLine = true, textStyle = SfText.body().copy(color = Color.White), cursorBrush = SolidColor(Color.White),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                    decorationBox = { inner -> Box { if (search.isEmpty()) Text("Name, type or rules text", color = Color.White.copy(alpha = 0.4f), style = SfText.body()); inner() } })
                if (keyboardCompact) {
                    Text("Prompt", Modifier.defaultMinSize(minHeight = 44.dp).clickable { focusManager.clearFocus() }.padding(top = 12.dp), color = rgb(0.04, 0.52, 1.0), style = SfText.body())
                    Text("Done", Modifier.defaultMinSize(44.dp, 44.dp).clickable { focusManager.clearFocus() }.padding(top = 12.dp), color = rgb(0.04, 0.52, 1.0), style = SfText.body())
                    closeButton()
                }
            }
            Box(Modifier.weight(1f)) {
                when {
                    keyboardCompact -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (pendingActionId != null) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp); Text("Waiting for XMage…", color = MagicPalette.parchment, style = SfText.caption())
                        }
                        if (targets.isNotEmpty()) { Text("Other targets", color = MagicPalette.parchment, style = SfText.subheadline(SfWeight.semibold)); targets.forEach { targetRow(it) } }
                        filteredCards.forEach { compactCardRow(it) }
                        if (draftActive) draftOrderControls()
                        if (filteredCards.isEmpty() && search.isNotEmpty()) emptySearch()
                        else if (cards.none { it.isPromptSelectable } && targets.isEmpty()) Text("No legal cards to select. You can still hold a card to inspect it.",
                            color = MagicPalette.parchment, style = SfText.subheadline())
                    }
                    sideBySideDraft -> Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.weight(1f).fillMaxSize().verticalScroll(rememberScrollState()).padding(8.dp)) { choiceItems() }
                        Box(Modifier.width(orderColumnWidth.dp).fillMaxSize().verticalScroll(rememberScrollState()).padding(8.dp)) { draftOrderControls() }
                    }
                    draftActive -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        choiceItems(); draftOrderControls()
                    }
                    else -> Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(8.dp)) { choiceItems() }
                }
            }
            if (!keyboardCompact) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val confirmTitle = if (draftActive) "Confirm plan" else when {
                        selected == null -> if (targets.isEmpty()) "Select a card" else "Select an option"
                        selected.first in chosenIDs -> "Remove selection"
                        selected.third -> "Confirm card"
                        else -> "Confirm target"
                    }
                    val enabled = !((!draftActive && selected == null) || pendingActionId != null ||
                        (draftKind == CardChoicePlan.Kind.SELECTION && !draftCountIsValid) ||
                        ((draftKind == CardChoicePlan.Kind.TOP_ORDER || draftKind == CardChoicePlan.Kind.BOTTOM_ORDER) && draftIDs.size != selectableIDs.size))
                    PanelActionButton(::confirmSelection, Modifier.weight(1f).semantics { contentDescription = "board.choice.confirm" }, isPrimary = true, enabled = enabled) {
                        Text(confirmTitle, color = Color.White, style = SfText.body(SfWeight.semibold))
                    }
                    if (!draftActive) {
                        (snapshot.legalActions ?: emptyList()).filter { it.promptId == prompt.id && it.type == "answer_yes_no" && it.confirmed == false }.forEach { action ->
                            PanelActionButton({ runAction(action) }, Modifier.weight(1f), enabled = pendingActionId == null) {
                                Text(action.label, color = Color.White, style = SfText.body(SfWeight.semibold))
                            }
                        }
                    }
                }
                if (pendingActionId != null) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp); Text("Waiting for XMage…", color = MagicPalette.parchment, style = SfText.caption())
                }
            }
        }
        inspected?.let { card ->
            Box(Modifier.fillMaxSize().padding(16.dp)) {
                CardInspector(card, Modifier.fillMaxSize())
                Text("Close inspection", Modifier.align(Alignment.TopEnd).padding(12.dp).defaultMinSize(minHeight = 44.dp).clickable { inspected = null },
                    color = rgb(0.04, 0.52, 1.0), style = SfText.body())
            }
        }
    }
}
