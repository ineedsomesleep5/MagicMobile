package io.magicmobile.android.board

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.offset
import androidx.compose.ui.zIndex
import io.magicmobile.android.R
import io.magicmobile.android.game.ArenaPermanentLayout
import io.magicmobile.android.game.BattlefieldAdaptiveSizing
import io.magicmobile.android.game.BattlefieldAttachments
import io.magicmobile.android.game.BattlefieldCardGroup
import io.magicmobile.android.game.BattlefieldRowArrangement
import io.magicmobile.android.game.BattlefieldRowOverflow
import io.magicmobile.android.game.GameBoardInteractionState
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.PortraitInteractionPolicy
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.colorAdjust
import io.magicmobile.android.ui.drawStretched
import io.magicmobile.android.ui.glow
import io.magicmobile.android.game.BattlefieldTokenStack
import androidx.compose.ui.draw.drawBehind

/**
 * BattlefieldBackdrop (GameBoardTheme.swift). Persisted identifiers are shared with iOS. Walnut Tavern is the only
 * table players get; ARENA is the classic board layout on the plain gradient, kept for previews and tests. The old
 * moss, wood, ember, tide and stone textures were removed on 2026-10-14 and their stored values resolve to the tavern.
 */
enum class BattlefieldBackdrop(val rawValue: String) {
    ARENA("arena"), TAVERN("tavern");

    /**
     * A composed table rendered for each orientation (scripts/brand/tavern_table.py): its frame and play mat
     * are placed for the board layout, so it cannot share one crop.
     */
    val composedDrawables: Pair<Int, Int>? get() =
        if (this == TAVERN) R.drawable.battlefield_tavern_portrait to R.drawable.battlefield_tavern_landscape else null

    /** Composed art carries its own lamp and vignette; the generic shading would muddy it. */
    val hasBakedLighting: Boolean get() = composedDrawables != null

    companion object {
        /** Walnut Tavern is the default board; unknown values resolve to it. */
        fun resolved(value: String): BattlefieldBackdrop = entries.firstOrNull { it.rawValue == value } ?: TAVERN
    }
}

object BoardAppearancePreference {
    const val key = "magicmobile.boardAppearance"
    /** Walnut Tavern is the only board players can choose since 2026-10-11 (the picker is gone);
     *  "arena" (the classic layout) stays for previews and tests. */
    const val defaultValue = "tavern"
    fun normalized(value: String): String = if (BattlefieldBackdrop.entries.any { it.rawValue == value }) value else defaultValue
}

val midnightGradient: Brush get() = Brush.verticalGradient(listOf(rgb(0.055, 0.085, 0.10), rgb(0.10, 0.16, 0.16)))

/**
 * Composed tables pick the render made for the orientation and fill the screen exactly: the controls sit on its
 * sockets through the same both-axes mapping (TavernFrame), so a phone a little taller or wider than the 440 x 956
 * design canvas stretches the plate by a few percent instead of cropping its sockets away. The classic board draws
 * the plain gradient.
 */
@Composable
fun BattlefieldBackdropArt(theme: BattlefieldBackdrop, modifier: Modifier = Modifier) {
    val composed = theme.composedDrawables
    if (composed != null) {
        BoxWithConstraints(modifier) {
            val portrait = maxHeight >= maxWidth
            val resources = androidx.compose.ui.platform.LocalContext.current.resources
            val id = if (portrait) composed.first else composed.second
            val plate = remember(id) { io.magicmobile.android.ui.TavernImages.decode(resources, id) }
            Image(androidx.compose.ui.graphics.painter.BitmapPainter(plate), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
        }
    } else Box(modifier.background(midnightGradient))
}

@Composable
fun BattlefieldSurface(modifier: Modifier = Modifier) {
    val appearance by AppPreferences.string(BoardAppearancePreference.key, BoardAppearancePreference.defaultValue)
    val theme = BattlefieldBackdrop.resolved(appearance)
    BoxWithConstraints(modifier) {
        val w = constraints.maxWidth.toFloat(); val h = constraints.maxHeight.toFloat()
        BattlefieldBackdropArt(theme, Modifier.fillMaxSize())
        if (!theme.hasBakedLighting) {
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.34f), Color.Black.copy(alpha = 0.05f),
                Color.Black.copy(alpha = 0.08f), Color.Black.copy(alpha = 0.38f)))))
            Box(Modifier.fillMaxSize().background(radialVignette(w, h, 0.20f, 0.62f, listOf(Color.Transparent, Color.Black.copy(alpha = 0.10f), Color.Black.copy(alpha = 0.24f)))))
        }
    }
}

/** SwiftUI RadialGradient(startRadius: min*a, endRadius: max*b) as a Compose brush. */
fun radialVignette(width: Float, height: Float, start: Float, end: Float, colors: List<Color>): Brush {
    val startRadius = minOf(width, height) * start
    val endRadius = maxOf(maxOf(width, height) * end, startRadius + 1f)
    val stops = colors.mapIndexed { index, color ->
        val t = if (colors.size == 1) 0f else index.toFloat() / (colors.size - 1)
        (startRadius + (endRadius - startRadius) * t) / endRadius to color
    }.toTypedArray()
    return Brush.radialGradient(*stops, center = Offset(width / 2, height / 2), radius = endRadius)
}

/** iOS-style thin scroll indicator along the bottom, visible while the row scrolls. */
fun Modifier.horizontalScrollIndicator(state: ScrollState, enabled: Boolean): Modifier = if (!enabled) this else drawWithContent {
    drawContent()
    if (state.maxValue <= 0 || !state.isScrollInProgress) return@drawWithContent
    val track = size.width
    val content = track + state.maxValue
    val thumb = maxOf(track * track / content, 24.dp.toPx())
    val x = (track - thumb) * state.value / state.maxValue
    drawRoundRect(Color.White.copy(alpha = 0.45f), Offset(x, size.height - 4.dp.toPx()), Size(thumb, 3.dp.toPx()), CornerRadius(2.dp.toPx()))
}

/** The visible strip of an attachment tucked behind its creature: its name on a small tab (a parchment ribbon on the tavern table). */
@Composable
fun AttachmentNameTab(card: ZoneCard, height: Dp, modifier: Modifier = Modifier, more: Int = 0) {
    if (io.magicmobile.android.ui.LocalTavernBoard.current) {
        val ribbon = io.magicmobile.android.ui.tavernImage(R.drawable.tavern_card_ribbon)
        val brown = rgb(0.55, 0.32, 0.1)
        // The tab is about the ribbon's own shape (about 5 : 1), so it stretches to fit.
        Row(modifier.fillMaxWidth().height(height * 1.25f)
            .glow(Color.Black.copy(alpha = 0.45f), 1.5.dp, 4.dp)
            .drawBehind { drawStretched(ribbon) }
            .padding(horizontal = height * 1.1f), horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically) {
            SfImage(if (card.card.typeLine.contains("equipment", ignoreCase = true)) "shield.lefthalf.filled" else "sparkles", brown, maxOf(7.dp, height * 0.5f))
            FitText(card.card.name, sf(maxOf(7f, height.value * 0.6f), SfWeight.bold, io.magicmobile.android.ui.SfDesign.SERIF), Modifier.weight(1f, fill = false),
                color = rgb(0.17, 0.10, 0.05), minimumScale = 0.6f)
            if (more > 0) Text("+$more", color = brown, style = sf(maxOf(7f, height.value * 0.55f), SfWeight.black, io.magicmobile.android.ui.SfDesign.SERIF))
        }
        return
    }
    val shape = RoundedCornerShape(topStart = 6.dp, topEnd = 6.dp)
    Row(modifier.fillMaxWidth().height(height)
        .background(Brush.verticalGradient(listOf(MagicPalette.iron, Color.Black.copy(alpha = 0.92f))), shape)
        .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.6f), shape)
        .padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage(if (card.card.typeLine.contains("equipment", ignoreCase = true)) "shield.lefthalf.filled" else "sparkles",
            MagicPalette.antiqueGold, maxOf(7.dp, height * 0.5f))
        FitText(card.card.name, sf(maxOf(7f, height.value * 0.58f), SfWeight.heavy), Modifier.weight(1f, fill = false), color = Color.White, minimumScale = 0.6f)
        Spacer(Modifier.weight(1f))
        if (more > 0) Text("+$more", color = MagicPalette.antiqueGold, style = sf(maxOf(7f, height.value * 0.55f), SfWeight.black))
    }
}

/** The brass chip on the last card of a spread-out pile (BattlefieldStackChip in BattlefieldRow.swift): tap to stack it back together. */
@Composable
fun BattlefieldStackChip(cardWidth: Float, modifier: Modifier = Modifier, action: () -> Unit) {
    Box(modifier.size(44.dp).clickable(onClick = action).semantics { contentDescription = "Stack the group"; testTag = "battlefield.restack" },
        contentAlignment = Alignment.Center) {
        Row(Modifier.defaultMinSize(minHeight = 20.dp).glow(Color.Black.copy(alpha = 0.6f), 2.dp, 10.dp)
            .background(Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.56), rgb(0.80, 0.56, 0.22))), CircleShape)
            .border(1.dp, Color.Black.copy(alpha = 0.45f), CircleShape).padding(horizontal = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("square.stack.3d.up.fill", rgb(0.25, 0.12, 0.04), 9.dp)
            if (cardWidth >= 44f) Text("Stack", color = rgb(0.25, 0.12, 0.04), style = sf(10f, SfWeight.heavy, SfDesign.SERIF))
        }
    }
}

/** A battlefield lane (Board/BattlefieldRow.swift BattlefieldRow): grouped, attachment-stacked, density-sized permanents. */
@Composable
fun BattlefieldRow(
    title: String, cards: List<ZoneCard>, legalActions: List<LegalAction>, targetableIds: Set<String>, chosenIds: Set<String>, combatHighlightIds: Set<String>,
    selection: BoardSelection, cardWidth: Float, cardHeight: Float, rowWidth: Float,
    runAction: (LegalAction) -> Unit, runTargetAction: (ZoneCard) -> Unit, runCombatCardAction: (ZoneCard) -> Boolean,
    modifier: Modifier = Modifier, flipped: Boolean = false, adaptsToDensity: Boolean = false, availableHeight: Float? = null,
    arrangement: BattlefieldRowArrangement = BattlefieldRowArrangement.AUTOMATIC, allowsManaUndo: Boolean = false, manaPaymentActive: Boolean = false,
    /** Where the tiles sit in the lane while they fit: centred, or (the Arena board's lands) from its leading edge. */
    alignment: io.magicmobile.android.game.ArenaLaneAlignment = io.magicmobile.android.game.ArenaLaneAlignment.CENTER,
    /** The Arena board sizes its rows itself (ArenaRowFit): this many rows, whatever the tile count. */
    preferredRows: Int? = null,
) {
    /** The Arena board piles identical lands the reference's way and tucks attachments behind their creature as cards. */
    val arena = io.magicmobile.android.menus.LocalArenaBoard.current
    val contentAlignment = when (alignment) {
        io.magicmobile.android.game.ArenaLaneAlignment.LEADING -> Alignment.CenterStart
        io.magicmobile.android.game.ArenaLaneAlignment.TRAILING -> Alignment.CenterEnd
        io.magicmobile.android.game.ArenaLaneAlignment.CENTER -> Alignment.Center
    }
    var expandedGroupIds by rememberSaveable(title) { mutableStateOf(setOf<String>()) }
    // Piles opened with a hold while choosing from them stack again once the choice or combat ends; a pile opened just to look
    // stays open until its Stack chip (Caleb, 2026-10-16).
    var choiceOpenedGroupIds by rememberSaveable(title) { mutableStateOf(setOf<String>()) }
    val settled = targetableIds.isEmpty() && combatHighlightIds.isEmpty()
    LaunchedEffect(settled) {
        if (settled && choiceOpenedGroupIds.isNotEmpty()) {
            expandedGroupIds = BattlefieldTokenStack.openAfterChoice(expandedGroupIds, choiceOpenedGroupIds)
            choiceOpenedGroupIds = emptySet()
        }
    }
    val haptics = rememberHaptics()
    val cardGroups = remember(cards) { BattlefieldAttachments.groups(cards) }

    val tavern = io.magicmobile.android.ui.LocalTavernBoard.current

    fun isExpanded(group: BattlefieldCardGroup): Boolean {
        if (group.id.startsWith("attachment:")) return false
        if (expandedGroupIds.contains(group.id)) return true
        // Eight or more identical tokens stay one pile even in combat or targeting (Caleb, 2026-10-02): a tap acts on the next one, a hold opens the pile.
        if (group.count >= BattlefieldTokenStack.threshold) return false
        return group.cards.any { targetableIds.contains(it.instanceId) || targetableIds.contains(it.id) } ||
            requiresIndividualCombatCards(group, combatHighlightIds)
    }

    /** The card a tap on a stack acts on: the first that can be targeted, then the first that combat highlights; null when the stack simply opens. */
    fun nextChoosable(group: BattlefieldCardGroup): Pair<ZoneCard, Boolean>? {
        BattlefieldTokenStack.nextTargetable(group, targetableIds, chosenIds)?.let { return it to true }
        group.cards.firstOrNull { combatHighlightIds.contains(it.instanceId) || combatHighlightIds.contains(it.id) }?.let { return it to false }
        return null
    }

    // A pile shows the cards already chosen from it beside it (BattlefieldTokenStack.displayGroups).
    val renderedGroups = cardGroups.flatMap { BattlefieldTokenStack.displayGroups(it, isExpanded(it), chosenIds) }
    val visibleCards = renderedGroups.map { it.representative }
    val visibleCardCount = renderedGroups.size
    val permanentLayout = availableHeight?.let { height ->
        val proposed = arrangement.rows(renderedGroups, flipped, preferredRows?.let { it == 2 }
            ?: (arrangement == BattlefieldRowArrangement.LANDSCAPE_RESOURCES || visibleCardCount > 5))
        ArenaPermanentLayout.of(proposed.map { it.size }, rowWidth, height, cardWidth, cardHeight / maxOf(cardWidth, 1f))
    }
    val targetRenderedWidth = permanentLayout?.cardWidth ?: if (!adaptsToDensity) cardWidth else
        BattlefieldAdaptiveSizing.cardWidth(rowWidth, cardWidth, 1f, List(minOf(5, visibleCards.size)) { false })
    val renderedCardWidth by animateFloatAsState(targetRenderedWidth, if (BoardMotion.reduceMotion) tween(0) else tween(200), label = "rowCardWidth")
    val renderedCardHeight = cardHeight * renderedCardWidth / maxOf(cardWidth, 1f)
    val rows = permanentLayout?.rows ?: 1
    val arranged = arrangement.rows(renderedGroups, flipped, rows == 2)
    val manaUndoAction = legalActions.firstOrNull { it.type == "undo_mana" }

    fun legalAction(card: ZoneCard): LegalAction? {
        if (card.isPhasedOut) return null
        if (allowsManaUndo && manaPaymentActive && card.tapped == true && manaUndoAction != null &&
            (manaUndoAction.sourceInstanceId == card.instanceId || manaUndoAction.cardInstanceId == card.instanceId)) return manaUndoAction
        return legalActions.firstOrNull { it.cardInstanceId == card.instanceId || it.sourceInstanceId == card.instanceId }
    }

    fun handleCardTap(card: ZoneCard, targetable: Boolean, combatHighlighted: Boolean) {
        if (card.isPhasedOut) return
        if (targetable) runTargetAction(card)
        else if (targetableIds.isNotEmpty()) GameHaptics.warning(haptics)
        else if (combatHighlighted && runCombatCardAction(card)) GameHaptics.selection(haptics)
        else {
            val immediate = PortraitInteractionPolicy.automaticCardAction(GameBoardInteractionState.cardActions(card, legalActions))
            if (immediate != null && immediate.type in setOf("make_mana", "undo_mana")) runAction(immediate)
            else {
                selection.selectedCard = if (selection.selectedCard?.instanceId == card.instanceId) null else card
                selection.inspectedCard = null
                GameHaptics.selection(haptics)
            }
        }
    }

    val tappedOffset = { card: ZoneCard -> if (card.tapped == true && rows == 1) 5.dp else 0.dp }
    val stackChips = if (expandedGroupIds.isEmpty()) emptyMap() else BattlefieldTokenStack.stackChipPiles(cardGroups, expandedGroupIds)

    @Composable
    fun cardTile(card: ZoneCard) {
        val action = legalAction(card)
        val targetable = !card.isPhasedOut && (targetableIds.contains(card.instanceId) || targetableIds.contains(card.id))
        val combatHighlighted = combatHighlightIds.contains(card.instanceId) || combatHighlightIds.contains(card.id)
        Box(Modifier.offset(y = tappedOffset(card))) {
        ArenaBattlefieldCard(card, title, renderedCardWidth.dp, renderedCardHeight.dp,
            Modifier
                .cardBounds(card.instanceId)
                .boardFXCardMotion(card.instanceId)
                .alpha(if (targetableIds.isNotEmpty() && !targetable) 0.54f else 1f)
                .onCardInteraction(tap = { handleCardTap(card, targetable, combatHighlighted) }, inspect = {
                    selection.inspectedCard = card
                    GameHaptics.impact(haptics)
                }, release = { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null }),
            selected = selection.selectedCard?.id == card.id || BattlefieldTokenStack.isChosen(card, chosenIds), legal = action != null,
            targetable = targetable || combatHighlighted)
        // Chosen in a multi-card prompt: an ember seal, so it reads apart from the cards still to choose from.
        if (BattlefieldTokenStack.isChosen(card, chosenIds)) {
            Box(Modifier.align(Alignment.TopEnd).offset(3.dp, (-3).dp).size(maxOf(18f, renderedCardWidth * 0.22f).dp)
                .background(io.magicmobile.android.ui.TavernPalette.ember, CircleShape).border(1.2.dp, MagicPalette.antiqueGold, CircleShape),
                contentAlignment = Alignment.Center) {
                SfImage("checkmark", Color.White, maxOf(9f, renderedCardWidth * 0.11f).dp)
            }
        }
        // The last card of a pile the player spread out: tap to stack it back together.
        stackChips[card.instanceId]?.let { pile ->
            BattlefieldStackChip(renderedCardWidth, Modifier.align(Alignment.BottomEnd).offset(10.dp, 10.dp)) {
                expandedGroupIds = expandedGroupIds - pile
                choiceOpenedGroupIds = choiceOpenedGroupIds - pile
                GameHaptics.selection(haptics)
            }
        }
        }
    }

    @Composable
    fun collapsedGroupTile(group: BattlefieldCardGroup) {
        val card = group.representative
        val groupIds = group.cards.flatMap { listOf(it.instanceId, it.id) }.toSet()
        val targetable = targetableIds.any { it in groupIds }
        val combatHighlighted = combatHighlightIds.any { it in groupIds }
        val legal = group.cards.any { legalAction(it) != null }
        val next = nextChoosable(group)
        // The Arena board piles identical lands the reference's way: each copy peeks out from under the one on top.
        val peeks = if (arena && card.card.isLand) minOf(group.count - 1, 5) else 0
        Box(Modifier.offset(y = tappedOffset(card)).padding(start = (peeks * renderedCardWidth * 0.12f).dp)
            .semantics { contentDescription = "${group.count} grouped ${card.card.name} cards in $title. " +
                if (next != null) "Tap to choose the next one. Long press to open the group." else "Tap to expand the group. Long press to inspect a card." }
            .cardBounds(card.instanceId)
            .boardFXCardMotion(card.instanceId)
            .alpha(if (targetableIds.isNotEmpty() && !targetable) 0.54f else 1f)
            .onCardInteraction(tap = {
                val choosable = nextChoosable(group)
                if (choosable != null) {
                    // A stack being chosen from: the tap targets or declares its next card.
                    handleCardTap(choosable.first, targetable = choosable.second, combatHighlighted = !choosable.second)
                } else {
                    expandedGroupIds = expandedGroupIds + group.id
                    selection.selectedCard = null
                    selection.inspectedCard = null
                    GameHaptics.selection(haptics)
                }
            }, inspect = {
                if (nextChoosable(group) != null) {
                    // Hold to open the pile and pick a particular card; it stacks again when the choice ends.
                    expandedGroupIds = expandedGroupIds + group.id
                    choiceOpenedGroupIds = choiceOpenedGroupIds + group.id
                } else selection.inspectedCard = card
                GameHaptics.impact(haptics)
            }, release = { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null })) {
            for (layer in peeks downTo 1) {
                ArenaBattlefieldCard(group.cards[layer], title, renderedCardWidth.dp, renderedCardHeight.dp,
                    Modifier.offset((-layer * renderedCardWidth * 0.12f).dp, (layer * 2).dp).clearAndSetSemantics { })
            }
            if (tavern && LocalCardFrames.current && group.count >= BattlefieldTokenStack.threshold) {
                // A big stack reads as a pile: two more frames peek out behind it (frame art only).
                val frame = io.magicmobile.android.ui.tavernImage(tavernFrameDrawable(io.magicmobile.android.game.TavernFrameKind.of(card)))
                for (layer in 1 downTo 0) {
                    Box(Modifier.offset(x = (3.5f * (layer + 1)).dp, y = (-3.5f * (layer + 1)).dp).requiredSize(renderedCardWidth.dp, renderedCardHeight.dp)
                        .colorAdjust(1f, -0.18f - 0.1f * layer).drawBehind { drawStretched(frame) })
                }
            }
            ArenaBattlefieldCard(card, title, renderedCardWidth.dp, renderedCardHeight.dp, selected = false, legal = legal,
                targetable = targetable || combatHighlighted)
            if (group.count > peeks + 1) Text("×${group.count}", Modifier.align(Alignment.BottomStart).padding(3.dp)
                .background(MagicPalette.iron.copy(alpha = 0.94f), CircleShape)
                .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.58f), CircleShape)
                .padding(horizontal = 5.dp, vertical = 3.dp), color = Color.White, style = sf(10f, SfWeight.black))
        }
    }

    /**
     * Arena-style: Auras and Equipment tuck behind their creature, each showing a named tab above it. The creature
     * keeps its full size (Caleb, 2026-10-02): the tabs rise above it, over the gap. In a lower row ([tucked]) they would
     * cover the power and toughness of the card above (Caleb, 2026-10-15), so there they sit inside the creature's top edge.
     */
    @Composable
    fun attachmentGroupTile(group: BattlefieldCardGroup, tucked: Boolean = false) {
        if (arena) {
            // The Arena board (the reference's): each Aura and Equipment is its own card tucked behind the creature, shifted left
            // and a little up so its name and left edge show, one step further per card; the row makes room for them on the left.
            val attachments = group.cards.drop(1)
            val shown = attachments.take(3)
            val step = renderedCardHeight * (if (tucked) 0f else 0.1f)
            val side = -renderedCardWidth * 0.3f
            Box(Modifier.padding(start = (renderedCardWidth * 0.3f * shown.size).dp).requiredSize(renderedCardWidth.dp, renderedCardHeight.dp),
                contentAlignment = Alignment.BottomCenter) {
                shown.withIndex().reversed().forEach { (index, card) ->
                    Box(Modifier.offset((side * (index + 1)).dp, (-step * (index + 1)).dp)) { cardTile(card) }
                }
                cardTile(group.representative)
                if (attachments.size > shown.size) {
                    Text("+${attachments.size - shown.size}", Modifier.align(Alignment.TopEnd).offset(4.dp, (-step * shown.size - 6).dp)
                        .background(io.magicmobile.android.ui.TavernPalette.leather, CircleShape)
                        .border(1.dp, io.magicmobile.android.ui.TavernPalette.brass, CircleShape).padding(horizontal = 4.dp),
                        color = io.magicmobile.android.ui.TavernPalette.label, style = sf(maxOf(9f, renderedCardWidth * 0.13f), SfWeight.heavy, SfDesign.SERIF))
                }
            }
            return
        }
        val attachments = group.cards.drop(1)
        // Two tabs at most; the rest count on the top tab.
        val shown = attachments.take(2)
        val peek = maxOf(11f, minOf(14f, renderedCardHeight * 0.13f))
        if (tucked) {
            Box(Modifier.requiredSize(renderedCardWidth.dp, renderedCardHeight.dp), contentAlignment = Alignment.TopCenter) {
                cardTile(group.representative)
                Column(Modifier.padding(top = (peek * 0.35f).dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    shown.withIndex().forEach { (index, card) ->
                        AttachmentNameTab(card, peek.dp, Modifier.width(renderedCardWidth.dp)
                            .semantics { contentDescription = "${card.card.name}. Attached to ${group.representative.card.name}. Tap to select; hold to inspect." }
                            .onCardInteraction(tap = {
                                handleCardTap(card, !card.isPhasedOut && (targetableIds.contains(card.instanceId) || targetableIds.contains(card.id)), false)
                            }, inspect = {
                                selection.inspectedCard = card
                                GameHaptics.impact(haptics)
                            }, release = { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null }),
                            more = if (index == shown.size - 1) attachments.size - shown.size else 0)
                    }
                }
            }
            return
        }
        Box(Modifier.requiredSize(renderedCardWidth.dp, renderedCardHeight.dp), contentAlignment = Alignment.BottomCenter) {
            shown.withIndex().reversed().forEach { (index, card) ->
                Box(Modifier.offset(y = (-peek * (index + 1)).dp)) {
                    cardTile(card)
                    AttachmentNameTab(card, peek.dp, Modifier.align(Alignment.TopCenter).width(renderedCardWidth.dp),
                        more = if (index == shown.size - 1) attachments.size - shown.size else 0)
                }
            }
            cardTile(group.representative)
        }
    }

    @Composable
    /** [tucked]: a row sits above this one in the lane, so attachment tabs stay inside their creature. */
    fun rowTiles(groups: List<BattlefieldCardGroup>, tucked: Boolean = false) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            for (group in groups) androidx.compose.runtime.key(group.id) {
                when {
                    group.id.startsWith("attachment:") -> attachmentGroupTile(group, tucked)
                    group.count > 1 -> collapsedGroupTile(group)
                    else -> cardTile(group.representative)
                }
            }
        }
    }

    fun rowContentWidth(groups: List<BattlefieldCardGroup>): Float = 16 + groups.size * renderedCardWidth + maxOf(groups.size - 1, 0) * 4
    val showsOverflowIndicator = cardGroups.any { it.id.startsWith("attachment:") } ||
        (permanentLayout?.let { it.contentWidth > rowWidth } ?: ((16 + visibleCards.size * renderedCardWidth + maxOf(visibleCardCount - 1, 0) * 4) > rowWidth))

    Box(modifier.semantics { contentDescription = "board.battlefield.$title" }, contentAlignment = Alignment.TopStart) {
        if (arrangement == BattlefieldRowArrangement.LANDSCAPE_RESOURCES && rows == 2) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                for (row in 0 until 2) {
                    val scroll = rememberBoardScrollState()
                    BattlefieldRowScroller(scroll, title, rowWidth, targetRenderedWidth, listOf(arranged[row].map { it.count }),
                        showsIndicator = rowContentWidth(arranged[row]) > rowWidth) {
                        Box(Modifier.defaultMinSize(minWidth = rowWidth.dp, minHeight = (((availableHeight ?: 0f) - 4) / 2).dp), contentAlignment = contentAlignment) {
                            Box(Modifier.padding(horizontal = 8.dp)) { rowTiles(arranged[row], tucked = row > 0) }
                        }
                    }
                }
            }
        } else {
            val scroll = rememberBoardScrollState()
            BattlefieldRowScroller(scroll, title, rowWidth, targetRenderedWidth, (0 until rows).map { row -> arranged.getOrElse(row) { emptyList() }.map { it.count } },
                showsIndicator = showsOverflowIndicator) {
                // Rows keep their leading edges together; the block is centered in the lane.
                Box(Modifier.defaultMinSize(minWidth = rowWidth.dp, minHeight = (availableHeight ?: maxOf(cardHeight + 6, 44f)).dp), contentAlignment = contentAlignment) {
                    Column(Modifier.padding(horizontal = 8.dp, vertical = if (availableHeight == null) 0.dp else 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        for (row in 0 until rows) rowTiles(arranged.getOrElse(row) { emptyList() }, tucked = row > 0)
                    }
                }
            }
        }
    }
}

/**
 * One BattlefieldRow scroller (Board/BattlefieldRow.swift battlefieldRowOverflow): a soft fade at an edge that clips
 * cards and "+N" markers for cards entirely out of view. The markers only draw, so taps, drags and holds
 * reach the lane beneath. Every tile is one card wide; a group counts all of its cards.
 */
@Composable
private fun BattlefieldRowScroller(scroll: BoardScrollState, title: String, rowWidth: Float, cardWidth: Float,
                                   cardsPerSlotByRow: List<List<Int>>, showsIndicator: Boolean, content: @Composable () -> Unit) {
    val density = LocalDensity.current.density
    // Scrolling recomposes only when a count or an edge changes, not on every frame.
    val overflow by remember(scroll, rowWidth, cardWidth, cardsPerSlotByRow, density) {
        derivedStateOf { BattlefieldRowOverflow.lane(scroll.offset / density, rowWidth, cardWidth, cardsPerSlotByRow) }
    }
    val motion = tween<Float>(if (BoardMotion.reduceMotion) 0 else 180)
    val leadingFade by animateFloatAsState(if (overflow.clipsLeading) 1f else 0f, motion, label = "rowFadeLeading")
    val trailingFade by animateFloatAsState(if (overflow.clipsTrailing) 1f else 0f, motion, label = "rowFadeTrailing")
    Box {
        BoardHorizontalScroller(scroll, Modifier.width(rowWidth.dp).battlefieldRowEdgeFade({ leadingFade }, { trailingFade }),
            showsIndicator = showsIndicator, content = content)
        Row(Modifier.matchParentSize().padding(horizontal = 3.dp), verticalAlignment = Alignment.CenterVertically) {
            BattlefieldRowOverflowMarker(overflow.hiddenLeading, "left", title)
            Spacer(Modifier.weight(1f))
            BattlefieldRowOverflowMarker(overflow.hiddenTrailing, "right", title)
        }
    }
}

/** "+N" count of cards scrolled entirely out of view on one side. */
@Composable
private fun RowScope.BattlefieldRowOverflowMarker(count: Int, side: String, title: String) {
    var shown by remember { mutableIntStateOf(count) }
    if (count > 0) shown = count // Keep the last count while the marker fades out.
    val motion = if (BoardMotion.reduceMotion) 0 else 180
    AnimatedVisibility(count > 0, enter = fadeIn(tween(motion)), exit = fadeOut(tween(motion)), label = "rowOverflow-$side") {
        val label = "$shown more ${if (shown == 1) "card" else "cards"} off-screen to the $side"
        Text("+$shown", Modifier.semantics { contentDescription = label; testTag = "board.battlefield.$title.hidden.$side" }
            .background(MagicPalette.iron.copy(alpha = 0.94f), CircleShape)
            .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.58f), CircleShape)
            .padding(horizontal = 6.dp, vertical = 3.dp), color = Color.White, style = sf(11f, SfWeight.black).copy(fontFeatureSettings = "tnum"))
    }
}

/**
 * iOS BattlefieldRowFadeMask: the lane's content fades out across 28 dp at an edge where it clips cards.
 * The fade layer grows by the scroller's clip insets, so glows above and below the row still draw; its
 * layout nets out to zero, so the row keeps its size, position and touch area.
 */
private fun Modifier.battlefieldRowEdgeFade(leading: () -> Float, trailing: () -> Float, fadeWidth: Dp = 28.dp,
                                            bleedHorizontal: Dp = 4.dp, bleedVertical: Dp = 28.dp): Modifier = this
    .layout { measurable, constraints ->
        val h = bleedHorizontal.roundToPx(); val v = bleedVertical.roundToPx()
        val placeable = measurable.measure(constraints.offset(2 * h, 2 * v))
        layout(maxOf(0, placeable.width - 2 * h), maxOf(0, placeable.height - 2 * v)) { placeable.place(-h, -v) }
    }
    .graphicsLayer { compositingStrategy = if (leading() > 0f || trailing() > 0f) CompositingStrategy.Offscreen else CompositingStrategy.Auto }
    .drawWithContent {
        drawContent()
        val start = leading().coerceIn(0f, 1f); val end = trailing().coerceIn(0f, 1f)
        if (start <= 0f && end <= 0f || size.width <= 0f) return@drawWithContent
        val band = (fadeWidth.toPx() / size.width).coerceIn(0f, 0.5f)
        drawRect(Brush.horizontalGradient(0f to Color.Black.copy(alpha = 1f - start), band to Color.Black,
            1f - band to Color.Black, 1f to Color.Black.copy(alpha = 1f - end)), blendMode = BlendMode.DstIn)
    }
    .layout { measurable, constraints ->
        val h = bleedHorizontal.roundToPx(); val v = bleedVertical.roundToPx()
        val placeable = measurable.measure(constraints.offset(-2 * h, -2 * v))
        layout(placeable.width + 2 * h, placeable.height + 2 * v) { placeable.place(h, v) }
    }

fun requiresIndividualCombatCards(group: BattlefieldCardGroup, highlightedIDs: Set<String>): Boolean = group.cards.any {
    it.isAttacking == true || it.blocking?.isNotEmpty() == true || highlightedIDs.contains(it.instanceId) || highlightedIDs.contains(it.id)
}

/** Board/PortraitBoardViews.swift PortraitBattlefieldPermanentGroup: creatures and other permanents in portrait's two-row lane. */
@Composable
fun PortraitBattlefieldPermanentGroup(
    title: String, cards: List<ZoneCard>, legalActions: List<LegalAction>, targetableIds: Set<String>, chosenIds: Set<String>, combatHighlightIds: Set<String>,
    selection: BoardSelection, cardWidth: Float, cardHeight: Float, rowWidth: Float, availableHeight: Float,
    runAction: (LegalAction) -> Unit, runTargetAction: (ZoneCard) -> Unit, runCombatCardAction: (ZoneCard) -> Boolean,
    modifier: Modifier = Modifier, flipped: Boolean = false, allowsManaUndo: Boolean = false, manaPaymentActive: Boolean = false,
) {
    BattlefieldRow(title, cards, legalActions, targetableIds, chosenIds, combatHighlightIds, selection, cardWidth, cardHeight, rowWidth,
        runAction, runTargetAction, runCombatCardAction, modifier, flipped, adaptsToDensity = true, availableHeight = availableHeight,
        arrangement = BattlefieldRowArrangement.PORTRAIT_PERMANENTS, allowsManaUndo = allowsManaUndo, manaPaymentActive = manaPaymentActive)
}
