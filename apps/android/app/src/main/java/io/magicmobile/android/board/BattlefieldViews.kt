package io.magicmobile.android.board

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.offset
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
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import io.magicmobile.android.R
import io.magicmobile.android.game.ArenaPermanentLayout
import io.magicmobile.android.game.BattlefieldAdaptiveSizing
import io.magicmobile.android.game.BattlefieldAttachments
import io.magicmobile.android.game.BattlefieldCardGroup
import io.magicmobile.android.game.BattlefieldRowArrangement
import io.magicmobile.android.game.GameBoardInteractionState
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.PortraitInteractionPolicy
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/** BattlefieldBackdrop (GameBoardTheme.swift). Persisted identifiers are shared with iOS. */
enum class BattlefieldBackdrop(val rawValue: String, val title: String) {
    ARENA("arena", "Stone Arena"), MIDNIGHT("midnight", "Midnight"), WOOD("wood", "Classic Wood"),
    MOSS("moss", "Moss Sanctuary"), EMBER("ember", "Obsidian Ember"), TIDE("tide", "Tidal Slate");

    val drawable: Int? get() = when (this) {
        ARENA -> R.drawable.battlefield_arena; WOOD -> R.drawable.battlefield_wood; MOSS -> R.drawable.battlefield_moss
        EMBER -> R.drawable.battlefield_ember; TIDE -> R.drawable.battlefield_tide; MIDNIGHT -> null
    }

    companion object {
        fun resolved(value: String): BattlefieldBackdrop = entries.firstOrNull { it.rawValue == value } ?: ARENA
    }
}

object BoardAppearancePreference {
    const val key = "magicmobile.boardAppearance"
    const val defaultValue = "arena"
    fun normalized(value: String): String = if (BattlefieldBackdrop.entries.any { it.rawValue == value }) value else defaultValue
}

object MenuAppearancePreference {
    const val key = "magicmobile.menuAppearance"
    const val defaultValue = "tavern"
    val options = listOf("tavern", "arena", "midnight")
    fun normalized(value: String): String = if (value in options) value else defaultValue
}

val midnightGradient: Brush get() = Brush.verticalGradient(listOf(rgb(0.055, 0.085, 0.10), rgb(0.10, 0.16, 0.16)))

/** A square material crop keeps both orientations independent of painted slots. */
@Composable
fun BattlefieldBackdropArt(theme: BattlefieldBackdrop, modifier: Modifier = Modifier) {
    val drawable = theme.drawable
    if (drawable != null) Image(painterResource(drawable), null, modifier, contentScale = ContentScale.Crop)
    else Box(modifier.background(midnightGradient))
}

@Composable
fun BattlefieldSurface(modifier: Modifier = Modifier) {
    val appearance by AppPreferences.string(BoardAppearancePreference.key, BoardAppearancePreference.defaultValue)
    BoxWithConstraints(modifier) {
        val w = constraints.maxWidth.toFloat(); val h = constraints.maxHeight.toFloat()
        BattlefieldBackdropArt(BattlefieldBackdrop.resolved(appearance), Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.34f), Color.Black.copy(alpha = 0.05f),
            Color.Black.copy(alpha = 0.08f), Color.Black.copy(alpha = 0.38f)))))
        Box(Modifier.fillMaxSize().background(radialVignette(w, h, 0.20f, 0.62f, listOf(Color.Transparent, Color.Black.copy(alpha = 0.10f), Color.Black.copy(alpha = 0.24f)))))
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

/** The visible strip of an attachment tucked behind its creature: its name on a small tab. */
@Composable
fun AttachmentNameTab(card: ZoneCard, height: Dp, modifier: Modifier = Modifier, more: Int = 0) {
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

/** A battlefield lane (ContentView.swift BattlefieldRow): grouped, attachment-stacked, density-sized permanents. */
@Composable
fun BattlefieldRow(
    title: String, cards: List<ZoneCard>, legalActions: List<LegalAction>, targetableIds: Set<String>, combatHighlightIds: Set<String>,
    selection: BoardSelection, cardWidth: Float, cardHeight: Float, rowWidth: Float,
    runAction: (LegalAction) -> Unit, runTargetAction: (ZoneCard) -> Unit, runCombatCardAction: (ZoneCard) -> Boolean,
    modifier: Modifier = Modifier, flipped: Boolean = false, adaptsToDensity: Boolean = false, availableHeight: Float? = null,
    arrangement: BattlefieldRowArrangement = BattlefieldRowArrangement.AUTOMATIC, allowsManaUndo: Boolean = false, manaPaymentActive: Boolean = false,
) {
    var expandedGroupIds by rememberSaveable(title) { mutableStateOf(setOf<String>()) }
    val haptics = rememberHaptics()
    val cardGroups = remember(cards) { BattlefieldAttachments.groups(cards) }

    fun isExpanded(group: BattlefieldCardGroup): Boolean = !group.id.startsWith("attachment:") && (expandedGroupIds.contains(group.id) ||
        group.cards.any { targetableIds.contains(it.instanceId) || targetableIds.contains(it.id) } ||
        requiresIndividualCombatCards(group, combatHighlightIds))

    val visibleCards = cardGroups.flatMap { if (isExpanded(it)) it.cards else listOf(it.representative) }
    val visibleCardCount = cardGroups.sumOf { if (isExpanded(it)) it.count else 1 }
    val renderedGroups = cardGroups.flatMap { group ->
        if (isExpanded(group)) group.cards.map { BattlefieldCardGroup("card:" + it.instanceId, listOf(it)) } else listOf(group)
    }
    val permanentLayout = availableHeight?.let { height ->
        val proposed = arrangement.rows(renderedGroups, flipped, arrangement == BattlefieldRowArrangement.LANDSCAPE_RESOURCES || visibleCardCount > 5)
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

    @Composable
    fun cardTile(card: ZoneCard) {
        val action = legalAction(card)
        val targetable = !card.isPhasedOut && (targetableIds.contains(card.instanceId) || targetableIds.contains(card.id))
        val combatHighlighted = combatHighlightIds.contains(card.instanceId) || combatHighlightIds.contains(card.id)
        ArenaBattlefieldCard(card, title, renderedCardWidth.dp, renderedCardHeight.dp,
            Modifier.offset(y = tappedOffset(card))
                .cardBounds(card.instanceId)
                .boardFXCardMotion(card.instanceId)
                .alpha(if (targetableIds.isNotEmpty() && !targetable) 0.54f else 1f)
                .onCardInteraction(tap = { handleCardTap(card, targetable, combatHighlighted) }, inspect = {
                    selection.inspectedCard = card
                    GameHaptics.impact(haptics)
                }, release = { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null }),
            selected = selection.selectedCard?.id == card.id, legal = action != null, targetable = targetable || combatHighlighted)
    }

    @Composable
    fun collapsedGroupTile(group: BattlefieldCardGroup) {
        val card = group.representative
        val groupIds = group.cards.flatMap { listOf(it.instanceId, it.id) }.toSet()
        val targetable = targetableIds.any { it in groupIds }
        val combatHighlighted = combatHighlightIds.any { it in groupIds }
        val legal = group.cards.any { legalAction(it) != null }
        Box(Modifier.offset(y = tappedOffset(card))
            .semantics { contentDescription = "${group.count} grouped ${card.card.name} cards in $title" }
            .cardBounds(card.instanceId)
            .boardFXCardMotion(card.instanceId)
            .alpha(if (targetableIds.isNotEmpty() && !targetable) 0.54f else 1f)
            .onCardInteraction(tap = {
                expandedGroupIds = expandedGroupIds + group.id
                selection.selectedCard = null
                selection.inspectedCard = null
                GameHaptics.selection(haptics)
            }, inspect = {
                selection.inspectedCard = card
                GameHaptics.impact(haptics)
            }, release = { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null })) {
            ArenaBattlefieldCard(card, title, renderedCardWidth.dp, renderedCardHeight.dp, selected = false, legal = legal,
                targetable = targetable || combatHighlighted)
            Text("×${group.count}", Modifier.align(Alignment.BottomStart).padding(3.dp)
                .background(MagicPalette.iron.copy(alpha = 0.94f), CircleShape)
                .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.58f), CircleShape)
                .padding(horizontal = 5.dp, vertical = 3.dp), color = Color.White, style = sf(10f, SfWeight.black))
        }
    }

    /** Arena-style: Auras and Equipment tuck behind their creature, each showing a named tab above it. */
    @Composable
    fun attachmentGroupTile(group: BattlefieldCardGroup) {
        val attachments = group.cards.drop(1)
        val shown = attachments.take(2)
        val peek = maxOf(11f, minOf(14f, renderedCardHeight * 0.13f))
        val lift = peek * shown.size
        val scale = renderedCardHeight / (renderedCardHeight + lift)
        Box(Modifier.requiredSize(renderedCardWidth.dp, renderedCardHeight.dp), contentAlignment = Alignment.BottomCenter) {
            // Bottom-aligned like SwiftUI's `.frame(alignment: .bottom)`: the tabs rise above the creature.
            Box(Modifier.wrapContentSize(Alignment.BottomCenter, unbounded = true).requiredSize(renderedCardWidth.dp, (renderedCardHeight + lift).dp)
                .graphicsLayer { scaleX = scale; scaleY = scale; transformOrigin = TransformOrigin(0.5f, 1f) },
                contentAlignment = Alignment.BottomCenter) {
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
    }

    @Composable
    fun rowTiles(groups: List<BattlefieldCardGroup>) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            for (group in groups) androidx.compose.runtime.key(group.id) {
                when {
                    group.id.startsWith("attachment:") -> attachmentGroupTile(group)
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
                    BoardHorizontalScroller(scroll, Modifier.width(rowWidth.dp), showsIndicator = rowContentWidth(arranged[row]) > rowWidth) {
                        Box(Modifier.defaultMinSize(minWidth = rowWidth.dp, minHeight = (((availableHeight ?: 0f) - 4) / 2).dp), contentAlignment = Alignment.Center) {
                            Box(Modifier.padding(horizontal = 8.dp)) { rowTiles(arranged[row]) }
                        }
                    }
                }
            }
        } else {
            val scroll = rememberBoardScrollState()
            BoardHorizontalScroller(scroll, Modifier.width(rowWidth.dp), showsIndicator = showsOverflowIndicator) {
                // Rows keep their leading edges together; the block is centered in the lane.
                Box(Modifier.defaultMinSize(minWidth = rowWidth.dp, minHeight = (availableHeight ?: maxOf(cardHeight + 6, 44f)).dp), contentAlignment = Alignment.Center) {
                    Column(Modifier.padding(horizontal = 8.dp, vertical = if (availableHeight == null) 0.dp else 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        for (row in 0 until rows) rowTiles(arranged.getOrElse(row) { emptyList() })
                    }
                }
            }
        }
    }
}

fun requiresIndividualCombatCards(group: BattlefieldCardGroup, highlightedIDs: Set<String>): Boolean = group.cards.any {
    it.isAttacking == true || it.blocking?.isNotEmpty() == true || highlightedIDs.contains(it.instanceId) || highlightedIDs.contains(it.id)
}

/** ContentView.swift PortraitBattlefieldPermanentGroup: creatures and other permanents in portrait's two-row lane. */
@Composable
fun PortraitBattlefieldPermanentGroup(
    title: String, cards: List<ZoneCard>, legalActions: List<LegalAction>, targetableIds: Set<String>, combatHighlightIds: Set<String>,
    selection: BoardSelection, cardWidth: Float, cardHeight: Float, rowWidth: Float, availableHeight: Float,
    runAction: (LegalAction) -> Unit, runTargetAction: (ZoneCard) -> Unit, runCombatCardAction: (ZoneCard) -> Boolean,
    modifier: Modifier = Modifier, flipped: Boolean = false, allowsManaUndo: Boolean = false, manaPaymentActive: Boolean = false,
) {
    BattlefieldRow(title, cards, legalActions, targetableIds, combatHighlightIds, selection, cardWidth, cardHeight, rowWidth,
        runAction, runTargetAction, runCombatCardAction, modifier, flipped, adaptsToDensity = true, availableHeight = availableHeight,
        arrangement = BattlefieldRowArrangement.PORTRAIT_PERMANENTS, allowsManaUndo = allowsManaUndo, manaPaymentActive = manaPaymentActive)
}
