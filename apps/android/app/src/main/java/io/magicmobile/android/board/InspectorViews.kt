package io.magicmobile.android.board

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.BattlefieldLayoutMetrics
import io.magicmobile.android.game.BoardFXLevel
import io.magicmobile.android.game.BoardSize
import io.magicmobile.android.game.CardIdentity
import io.magicmobile.android.game.CardInspectorFit
import io.magicmobile.android.game.GameBoardInteractionState
import io.magicmobile.android.game.GameLogEntry
import io.magicmobile.android.game.GameLogPresentation
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameplayAffordances
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.LegalActionDisplay
import io.magicmobile.android.game.NativeCardArtworkPolicy
import io.magicmobile.android.game.StackTargetPresentation
import io.magicmobile.android.game.XmageCardIcon
import io.magicmobile.android.game.XmageStackObject
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlinx.coroutines.launch

/** Every permanent visible on the battlefield, so an inspector can show what is attached. */
val LocalInspectorBattlefield = compositionLocalOf<List<ZoneCard>> { emptyList() }

/** Printed card text from the bundled catalogue, for cards named in the public log. */
data class PrintedCard(val typeLine: String?, val oracleText: String?, val manaCost: String?)
val LocalPrintedCardLookup = compositionLocalOf<(String) -> PrintedCard?> { { null } }

/** Short notes for rules players often read differently than the engine applies them. */
object CardRulesReminder {
    fun text(card: ZoneCard): String? {
        val rules = (card.card.oracleText ?: "").lowercase()
        if (rules.contains("triggers an additional time")) {
            return "Only triggered abilities (“when”, “whenever”, “at”) happen again. Effects that say “instead”, like Chatterfang’s extra Squirrels, are not triggers and are not doubled."
        }
        return null
    }
}

/**
 * The holographic foil on an inspected card (Swift InspectionFoil + mmFoil shader): a
 * soft rainbow wash, a moving glint and a gentle 3D sway at the Full effects level.
 */
fun Modifier.inspectionFoil(): Modifier = this.then(Modifier.composed {
    val level by AppPreferences.string(BoardFXLevel.key, BoardFXLevel.defaultValue)
    if (BoardFXLevel.of(level) != BoardFXLevel.FULL || BoardMotion.reduceMotion) return@composed Modifier
    val transition = rememberInfiniteTransition(label = "foil")
    val t by transition.animateFloat(0f, 1000f, infiniteRepeatable(tween(1_000_000, easing = LinearEasing)), label = "foilTime")
    Modifier.graphicsLayer {
        rotationY = (sin(t * 0.9) * 3).toFloat()
        cameraDistance = 12f * density
    }.drawWithContent {
        drawContent()
        val phase = t * 0.3f
        val shift = ((phase * 0.35f) % 1f)
        // Rainbow wash along the card diagonal.
        val rainbow = listOf(rgb(1.0, 0.5, 0.5), rgb(1.0, 1.0, 0.5), rgb(0.5, 1.0, 0.6), rgb(0.5, 0.8, 1.0), rgb(0.85, 0.55, 1.0), rgb(1.0, 0.5, 0.5))
            .map { it.copy(alpha = 0.16f * 0.55f) }
        val span = size.width + size.height
        val offset = Offset(-shift * span, -shift * span * 0.75f)
        drawRect(Brush.linearGradient(rainbow + rainbow, start = offset, end = Offset(offset.x + span * 1.6f, offset.y + span * 1.2f)), blendMode = BlendMode.Plus)
        // The bright diagonal glint.
        val glint = (phase % 1f) * 1.6f - 0.3f
        val center = Offset(size.width * glint * 0.8f * 1.25f, size.height * glint * 0.6f * 1.25f)
        drawRect(Brush.linearGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.5f * 0.55f), Color.Transparent),
            start = Offset(center.x - size.width * 0.12f, center.y - size.height * 0.09f), end = Offset(center.x + size.width * 0.12f, center.y + size.height * 0.09f)),
            blendMode = BlendMode.Plus)
    }
})

/**
 * Held-card inspection. It lasts only while the finger is down, so nothing here scrolls by
 * touch: the printed card carries its own rules, and the panel adds only live state.
 */
@Composable
fun CardInspector(card: ZoneCard, modifier: Modifier = Modifier) {
    val battlefield = LocalInspectorBattlefield.current
    var artMissing by remember(card.instanceId) { mutableStateOf(false) }
    val attachments = battlefield.filter { it.attachedToInstanceId == card.instanceId && it.instanceId != card.instanceId }
    val attachedTo = card.attachedToInstanceId?.let { parent -> battlefield.firstOrNull { it.instanceId == parent } }
    val liveState = remember(card, attachedTo) {
        val details = mutableListOf<String>()
        if (card.card.isToken == true) details += if (card.card.copySourceArtworkName == null) "Token" else "Token copy"
        if (card.card.typeLine.isNotEmpty()) details += card.card.typeLine
        if (card.visibleXmageIcons.any { it.iconType == "COMMANDER" }) details += "Commander"
        if (card.showsPowerToughness && card.displayPower != null && card.displayToughness != null) details += "${card.displayPower}/${card.displayToughness}"
        card.tapped?.let { details += if (it) "Tapped" else "Untapped" }
        if (card.isCreature && card.summoningSickness == true) details += "Summoning sick"
        if (card.isAttacking == true) details += "Attacking"
        card.blocking?.takeIf { it.isNotEmpty() }?.let { details += if (it.size == 1) "Blocking" else "Blocking ${it.size}" }
        card.damage?.takeIf { it > 0 }?.let { details += "$it damage" }
        if (card.attachedToInstanceId != null) details += attachedTo?.let { "Attached to ${it.card.name}" } ?: "Attached"
        if (card.isPhasedOut) details += "Phased out"
        details += card.counterBadges.map { "${it.label} ×${it.count}" }
        details += card.visibleXmageIcons.mapNotNull { it.displayText ?: XmageCardIcon.keywordName(it.iconType) }
        val seen = mutableSetOf<String>()
        details.filter { seen.add(it.lowercase()) }
    }
    val showsRules = artMissing || card.card.isToken == true || !NativeCardArtworkPolicy.permitsLookup(card)
    val rules = card.card.oracleText?.trim() ?: ""
    val rulesVisible = showsRules && rules.isNotEmpty()
    val reminder = CardRulesReminder.text(card)
    val hasFooter = rulesVisible || liveState.isNotEmpty() || attachments.isNotEmpty() || reminder != null
    val shape = RoundedCornerShape(10.dp)

    @Composable
    fun cardFace(width: Float, height: Float) {
        CompositionLocalProvider(LocalCardArtPlaceholderShown provides { shown -> artMissing = shown }) {
            androidx.compose.runtime.key(card.instanceId) {
                CardTile(card, false, Modifier.inspectionFoil(), zoneName = "Inspector", width = width.dp, height = height.dp, ignoreTappedRotation = true)
            }
        }
    }

    @Composable
    fun footer(scale: Float) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy((8 * scale).dp)) {
            if (liveState.isNotEmpty()) InspectorStateChips(liveState, scale)
            if (rulesVisible) GameRulesText(rules, cardName = card.card.name, isHidden = !NativeCardArtworkPolicy.permitsLookup(card),
                symbolSize = (16 * scale).dp, style = sf(17f * scale), color = MagicPalette.parchment)
            if (reminder != null) Row(horizontalArrangement = Arrangement.spacedBy((6 * scale).dp)) {
                SfImage("info.circle", MagicPalette.parchment.copy(alpha = 0.82f), (14 * scale).dp)
                Text(reminder, color = MagicPalette.parchment.copy(alpha = 0.82f), style = sf(13f * scale, SfWeight.semibold))
            }
            if (attachments.isNotEmpty()) {
                // A thumbnail's missing art must not read as the main card's.
                CompositionLocalProvider(LocalCardArtPlaceholderShown provides null) { InspectorAttachmentList(attachments, scale) }
            }
        }
    }

    // Rules get their room first; CardInspectorFit shrinks the card, then the text (Swift CardInspectorLayout + ViewThatFits).
    SubcomposeLayout(modifier.background(InspectorBackdrop, shape).border(1.dp, Color.Cyan.copy(alpha = 0.35f), shape).padding(9.dp)) { constraints ->
        // Unbounded sides fall back to 320 × 480 (Swift replacingUnspecifiedDimensions).
        val widthPx = if (constraints.hasBoundedWidth) constraints.maxWidth else (320 * density).roundToInt()
        val heightPx = if (constraints.hasBoundedHeight) constraints.maxHeight else (480 * density).roundToInt()
        val available = BoardSize(maxOf(widthPx / density, 1f), maxOf(heightPx / density, 1f))
        fun naturalHeight(slot: String, widthPx: Int, scale: Float): Float =
            subcompose(slot) { footer(scale) }.maxOfOrNull { it.measure(Constraints(minWidth = widthPx, maxWidth = widthPx)).height }?.div(density) ?: 0f
        var probe = 0
        val fit = CardInspectorFit.plan(available, hasFooter = hasFooter) { width ->
            naturalHeight("probe-${probe++}", (width * density).roundToInt().coerceAtLeast(1), 1f)
        }
        val cardWidthPx = (fit.cardSize.width * density).roundToInt()
        val cardHeightPx = (fit.cardSize.height * density).roundToInt()
        val face = subcompose("card") { cardFace(fit.cardSize.width, fit.cardSize.height) }.map { it.measure(Constraints.fixed(cardWidthPx, cardHeightPx)) }
        val footerWidthPx = ((if (fit.horizontal) fit.footerSize.width else available.width) * density).roundToInt().coerceAtLeast(1)
        val footerTop = if (fit.horizontal) 0f else fit.cardSize.height + CardInspectorFit.SPACING
        val room = maxOf(available.height - footerTop, 0f)
        val footer = if (!hasFooter) emptyList() else {
            val scale = CardInspectorFit.textScale(room) { s -> naturalHeight("scale-$s", footerWidthPx, s) }
            subcompose("footer") { Box(Modifier.clipToBounds()) { footer(scale) } }
                .map { it.measure(Constraints(minWidth = footerWidthPx, maxWidth = footerWidthPx, maxHeight = (room * density).roundToInt())) }
        }
        layout(widthPx, heightPx) {
            val cardX = if (fit.horizontal) 0 else (widthPx - cardWidthPx) / 2
            face.forEach { it.place(cardX, 0) }
            val footerX = if (fit.horizontal) ((fit.cardSize.width + CardInspectorFit.COLUMN_SPACING) * density).roundToInt() else 0
            footer.forEach { it.place(footerX, (footerTop * density).roundToInt()) }
        }
    }
}

/** Solid, so the board never shows through the text while you read (Swift CardInspector.backdrop). */
private val InspectorBackdrop = rgb(0.07, 0.08, 0.10)

/** Live card state as compact chips that wrap onto as many lines as they need. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun InspectorStateChips(items: List<String>, scale: Float = 1f) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy((6 * scale).dp), verticalArrangement = Arrangement.spacedBy((6 * scale).dp)) {
        for (item in items) {
            FitText(item, sf(15f * scale, SfWeight.bold), Modifier.background(MagicPalette.iron.copy(alpha = 0.9f), CircleShape)
                .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.55f), CircleShape).padding(horizontal = (8 * scale).dp, vertical = (3 * scale).dp),
                color = MagicPalette.parchment, minimumScale = 0.7f)
        }
    }
}

/** What is attached to the inspected card: each Aura or Equipment with its rules text. */
@Composable
private fun InspectorAttachmentList(cards: List<ZoneCard>, scale: Float = 1f) {
    Column(verticalArrangement = Arrangement.spacedBy((6 * scale).dp)) {
        Text(if (cards.size == 1) "ATTACHED" else "ATTACHED · ${cards.size}", color = MagicPalette.antiqueGold, style = sf(12f * scale, SfWeight.black, tracking = 1.2f))
        for (attachment in cards.take(4)) {
            Row(Modifier.fillMaxWidth().background(MagicPalette.iron.copy(alpha = 0.85f), RoundedCornerShape(9.dp))
                .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.35f), RoundedCornerShape(9.dp)).padding(7.dp),
                horizontalArrangement = Arrangement.spacedBy((10 * scale).dp)) {
                CardTile(attachment, false, zoneName = "Inspector attachment", width = (40 * scale).dp,
                    height = (40 * scale * BattlefieldLayoutMetrics.magicCardHeightToWidth).dp, ignoreTappedRotation = true)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(attachment.card.name, color = Color.White, style = sf(15f * scale, SfWeight.heavy))
                    if (attachment.card.typeLine.isNotEmpty()) Text(attachment.card.typeLine, color = MagicPalette.parchment.copy(alpha = 0.7f), style = sf(12f * scale, SfWeight.semibold))
                    attachment.card.oracleText?.trim()?.takeIf { it.isNotEmpty() }?.let { text ->
                        GameRulesText(text, cardName = attachment.card.name, isHidden = !NativeCardArtworkPolicy.permitsLookup(attachment),
                            symbolSize = (16 * scale).dp, style = sf(13f * scale), color = MagicPalette.parchment, maxLines = 4)
                    }
                }
            }
        }
        if (cards.size > 4) Text("+${cards.size - 4} more attached", color = MagicPalette.parchment.copy(alpha = 0.75f), style = SfText.caption(SfWeight.bold))
    }
}

/** The stack in the stack sheet: each object with its source art, targets and rules. */
@Composable
fun PortraitStackLane(snapshot: GameSnapshot, humanStack: List<ZoneCard>, legalActions: List<LegalAction>, selection: BoardSelection,
                      modifier: Modifier = Modifier, horizontal: Boolean = false) {
    val stackCount = snapshot.xmage?.stack?.size?.takeIf { it > 0 } ?: humanStack.size
    val respond = legalActions.any { it.type in setOf("pass_priority", "pass_until_response", "advance_phase") }
    val xmageObjects = snapshot.stackTopFirst
    val shape = RoundedCornerShape(8.dp)
    Column(modifier.background(MagicPalette.iron.copy(alpha = 0.78f), shape).border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.30f), shape).padding(7.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Row(Modifier.padding(horizontal = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("STACK", color = MagicPalette.antiqueGold, style = SfText.headline())
            Text("$stackCount", color = Color.White.copy(alpha = 0.68f), style = SfText.headline())
            Spacer(Modifier.weight(1f))
            Text(if (respond) "RESPOND" else "WAIT", color = if (respond) MagicPalette.legalEmerald else Color.White.copy(alpha = 0.55f), style = SfText.caption(SfWeight.bold))
        }
        HorizontalDivider(color = MagicPalette.antiqueGold.copy(alpha = 0.22f))
        if (stackCount == 0) {
            Column(Modifier.fillMaxWidth().weight(1f, fill = false).padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterVertically)) {
                SfImage("square.stack.3d.up", MagicPalette.antiqueGold.copy(alpha = 0.76f), 20.dp)
                Text("No stack", color = Color.White, style = sf(9f, SfWeight.black))
                Text("Spells and abilities appear here", color = MagicPalette.parchment.copy(alpha = 0.68f), style = sf(7f, SfWeight.bold))
            }
        } else {
            LazyColumn(Modifier.fillMaxWidth().semantics { contentDescription = "board.stack.items" }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(xmageObjects, key = { it.id }) { item -> StackObjectView(item, snapshot, selection, horizontal) }
                if (xmageObjects.isEmpty()) items(humanStack.reversed(), key = { it.id }) { card -> StackCardView(card, selection, horizontal) }
            }
        }
    }
}

@Composable
private fun StackCardView(card: ZoneCard, selection: BoardSelection, horizontal: Boolean) {
    CardTile(card, false, Modifier.clickable { selection.inspectedCard = card }.semantics { contentDescription = "${card.card.name}. Tap to inspect source card" },
        zoneName = "Stack", width = if (horizontal) 150.dp else 180.dp, height = if (horizontal) 210.dp else 252.dp, ignoreTappedRotation = true)
}

@Composable
private fun StackObjectView(item: XmageStackObject, snapshot: GameSnapshot, selection: BoardSelection, horizontal: Boolean) {
    @Composable
    fun artwork() {
        val card = item.displaySourceCard
        if (card != null) StackCardView(card, selection, horizontal)
        else SyntheticStackObjectTile(item, if (horizontal) 150.dp else 180.dp, if (horizontal) 210.dp else 252.dp)
    }
    @Composable
    fun details(detailModifier: Modifier) {
        Column(detailModifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(item.displayName, color = MagicPalette.parchment, style = SfText.headline())
            Text("Source: ${item.displaySourceName}", color = MagicPalette.parchment.copy(alpha = 0.6f), style = SfText.caption())
            item.targetIds?.takeIf { it.isNotEmpty() }?.let { targets ->
                Text("Targets: ${StackTargetPresentation.labels(targets, snapshot).joinToString(", ")}", color = MagicPalette.parchment, style = SfText.subheadline())
            }
            if (!horizontal) artwork()
            item.rulesText?.let { rules ->
                GameRulesText(rules, cardName = item.displaySourceCard?.card?.name ?: item.sourceName,
                    isHidden = item.displaySourceCard?.let { !NativeCardArtworkPolicy.permitsLookup(it) } ?: false, style = SfText.body(), color = MagicPalette.parchment)
            }
        }
    }
    if (horizontal) Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) { artwork(); details(Modifier.weight(1f)) }
    else details(Modifier.fillMaxWidth().padding(vertical = 8.dp))
}

/** The stack sheet: every object on the stack, with a held inspector over it. */
@Composable
fun BoardStackInspector(snapshot: GameSnapshot, selection: BoardSelection, done: () -> Unit) {
    val turnControl = LocalNativeTurnControl.current
    BoxWithConstraints(Modifier.fillMaxWidth().heightIn(min = 460.dp).padding(12.dp)) {
        val horizontal = maxWidth > maxHeight && maxHeight != Dp.Infinity
        Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Stack", color = MagicPalette.parchment, style = SfText.headline())
                Spacer(Modifier.weight(1f))
                if (turnControl != null && turnControl.isAutoPassing) {
                    Text("Stop skipping", Modifier.defaultMinSize(minHeight = 44.dp).clickable(onClick = turnControl.stop).padding(8.dp),
                        color = rgb(0.04, 0.52, 1.0), style = SfText.body())
                }
                Text("Done", Modifier.defaultMinSize(minHeight = 44.dp).clickable { selection.inspectedCard = null; done() }.padding(8.dp)
                    .semantics { contentDescription = "board.stack.done" }, color = rgb(0.04, 0.52, 1.0), style = SfText.body())
            }
            Box {
                PortraitStackLane(snapshot, snapshot.human?.zones?.stack ?: emptyList(), snapshot.legalActions ?: emptyList(), selection,
                    Modifier.fillMaxWidth().heightIn(max = 620.dp), horizontal)
                selection.inspectedCard?.let { card ->
                    Box(Modifier.matchParentSize()) {
                        CardInspector(card, Modifier.fillMaxSize())
                        Text("Close card", Modifier.align(Alignment.TopEnd).padding(8.dp).defaultMinSize(minHeight = 44.dp)
                            .clickable { selection.inspectedCard = null }.padding(8.dp), color = rgb(0.04, 0.52, 1.0), style = SfText.body())
                    }
                }
            }
        }
    }
}

/** A floating grid of a zone's cards, with each card's legal action, target or inspect button. */
@Composable
fun CompactZoneInspectorOverlay(title: String, cards: List<ZoneCard>, legalActions: List<LegalAction>, pendingActionId: String?,
                                selection: BoardSelection, runAction: (LegalAction) -> Unit, closeAction: () -> Unit, modifier: Modifier = Modifier,
                                targetableIDs: Set<String> = emptySet(), runTargetAction: ((ZoneCard) -> Unit)? = null, availableHeight: Float = 410f) {
    fun perform(action: LegalAction) {
        if (pendingActionId != null || legalActions.none { it.id == action.id }) return
        if (GameplayAffordances.dismissesZone(action)) { selection.selectedCard = null; selection.inspectedCard = null; closeAction() }
        runAction(action)
    }
    val shape = RoundedCornerShape(12.dp)
    Column(modifier.widthIn(max = 360.dp).height(minOf(availableHeight, if (cards.isEmpty()) 150f else if (cards.size <= 3) 290f else 410f).dp)
        .glow(Color.Black.copy(alpha = 0.45f), 16.dp, 12.dp)
        .background(MagicPalette.iron.copy(alpha = 0.94f), shape).border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.38f), shape),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("$title · ${cards.size}", Modifier.weight(1f), color = MagicPalette.antiqueGold, style = sf(11f, SfWeight.black))
            PressableBox(closeAction, Modifier.size(44.dp).semantics { contentDescription = "Close $title" }) {
                SfImage("xmark.circle.fill", MagicPalette.parchment.copy(alpha = 0.6f), 16.dp)
            }
        }
        HorizontalDivider(color = MagicPalette.antiqueGold.copy(alpha = 0.18f))
        if (cards.isEmpty()) {
            Text("No cards in this zone.", Modifier.fillMaxWidth().padding(top = 20.dp), color = MagicPalette.parchment.copy(alpha = 0.78f),
                style = sf(12f, SfWeight.semibold), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        } else {
            LazyVerticalGrid(GridCells.Adaptive(100.dp), Modifier.fillMaxWidth().weight(1f), contentPadding = androidx.compose.foundation.layout.PaddingValues(8.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(cards, key = { it.id }) { card ->
                    val cardActions = GameBoardInteractionState.cardActions(card, legalActions)
                    val targetable = runTargetAction != null && (targetableIDs.contains(card.instanceId) || targetableIDs.contains(card.id))
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        CardTile(card, selection.selectedCard?.id == card.id, Modifier.onCardInteraction(tap = {
                            selection.selectedCard = card; selection.inspectedCard = null
                        }, inspect = { selection.inspectedCard = card }, release = { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null }),
                            legal = cardActions.isNotEmpty() || targetable, zoneName = title, width = 76.dp, height = 106.dp)
                        if (targetable) PanelActionButton({
                            if (pendingActionId == null && (targetableIDs.contains(card.instanceId) || targetableIDs.contains(card.id))) runTargetAction?.invoke(card)
                        }, Modifier.fillMaxWidth().semantics { contentDescription = "Target ${card.card.name}" }, isPrimary = true, compact = true, enabled = pendingActionId == null) {
                            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
                                verticalAlignment = Alignment.CenterVertically) {
                                SfImage("scope", Color.White, 12.dp); Text("Target", color = Color.White, style = sf(12f, SfWeight.semibold))
                            }
                        }
                        val single = cardActions.singleOrNull()
                        if (single != null) PanelActionButton({ perform(single) }, Modifier.fillMaxWidth(), isPrimary = true, compact = true, enabled = pendingActionId == null) {
                            Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp), contentAlignment = Alignment.Center) {
                                Text(LegalActionDisplay.displayLabel(single), color = Color.White, style = sf(12f, SfWeight.semibold), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            }
                        }
                        if (cardActions.size > 1) BoardMenu({ cardActions.map { action -> MenuEntry.Item(LegalActionDisplay.displayLabel(action)) { perform(action) } } },
                            enabled = pendingActionId == null) {
                            Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp), contentAlignment = Alignment.Center) {
                                Text("Actions", color = rgb(0.04, 0.52, 1.0), style = sf(12f, SfWeight.semibold))
                            }
                        }
                        Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { selection.inspectedCard = card }
                            .semantics { contentDescription = "Inspect ${card.card.name}" }, contentAlignment = Alignment.Center) {
                            Text("Inspect", color = MagicPalette.parchment, style = sf(12f, SfWeight.semibold))
                        }
                    }
                }
            }
        }
    }
}

/** The public game log, following the latest action unless you scroll back. */
@Composable
fun GameLogDrawer(log: List<GameLogEntry>, close: () -> Unit, modifier: Modifier = Modifier) {
    val lookup = LocalPrintedCardLookup.current
    var inspectedLogCard by remember { mutableStateOf<ZoneCard?>(null) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val followingLatest by remember { derivedStateOf {
        val last = listState.layoutInfo.visibleItemsInfo.lastOrNull()
        last == null || last.index >= listState.layoutInfo.totalItemsCount - 2
    } }
    LaunchedEffect(Unit) { if (log.isNotEmpty()) listState.scrollToItem(log.size) }
    LaunchedEffect(log.lastOrNull()?.id) {
        if (followingLatest && log.isNotEmpty()) {
            if (BoardMotion.reduceMotion) listState.scrollToItem(log.size) else listState.animateScrollToItem(log.size)
        }
    }
    val shape = RoundedCornerShape(8.dp)
    Column(modifier.background(Color.Black.copy(alpha = 0.72f), shape).border(1.dp, Color.White.copy(alpha = 0.16f), shape).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("LOG", color = Color(0xFFFF9500), style = SfText.caption(SfWeight.black))
            Spacer(Modifier.weight(1f))
            GameIconButton("xmark", close, small = true, contentDescription = "Close game log")
        }
        Box(Modifier.weight(1f, fill = false)) {
            LazyColumn(state = listState, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (log.isEmpty()) item { Text("No public game actions yet.", color = MagicPalette.parchment.copy(alpha = 0.6f), style = SfText.subheadline()) }
                items(log, key = { it.id }) { entry ->
                    GameLogText(entry.message, Modifier.fillMaxWidth().padding(top = if (GameLogPresentation(entry.message).plainText.startsWith("TURN ")) 12.dp else 0.dp),
                        style = SfText.subheadline(), onInspect = { reference ->
                            // The public log authorizes the printed identity, not a lookup of this object's current game state.
                            if (!NativeCardArtworkPolicy.permitsLookup(reference.name)) return@GameLogText
                            val printed = lookup(reference.name)
                            inspectedLogCard = ZoneCard(reference.objectID.toString().uppercase(), CardIdentity(reference.name,
                                printed?.typeLine ?: "Card referenced in game log", printed?.oracleText ?: "Rules unavailable in the local catalogue.", printed?.manaCost))
                        })
                }
                item { Spacer(Modifier.height(1.dp)) }
            }
            if (!followingLatest) {
                Text("Latest actions ↓", Modifier.align(Alignment.BottomEnd).padding(8.dp)
                    .background(rgb(0.04, 0.52, 1.0), CircleShape).clickable { scope.launch { listState.animateScrollToItem(log.size) } }
                    .padding(horizontal = 14.dp, vertical = 8.dp), color = Color.White, style = SfText.subheadline(SfWeight.semibold))
            }
        }
    }
    inspectedLogCard?.let { card ->
        BoardSheet({ inspectedLogCard = null }, skipPartiallyExpanded = true, sound = false) {
            Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("From the game log", color = MagicPalette.parchment.copy(alpha = 0.6f), style = SfText.caption())
                    Spacer(Modifier.weight(1f))
                    Text("Done", Modifier.defaultMinSize(minHeight = 44.dp).clickable { inspectedLogCard = null }.padding(8.dp), color = rgb(0.04, 0.52, 1.0), style = SfText.body())
                }
                CardInspector(card, Modifier.fillMaxWidth().height(620.dp))
            }
        }
    }
}
