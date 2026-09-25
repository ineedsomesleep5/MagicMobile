package io.magicmobile.android.board

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.changedToUp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import io.magicmobile.android.game.ArenaHandLayout
import io.magicmobile.android.game.BoardFXLevel
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.game.DragCastDropResolver
import io.magicmobile.android.game.DragCastDropResult
import io.magicmobile.android.game.GameBoardInteractionMode
import io.magicmobile.android.game.GameBoardInteractionState
import io.magicmobile.android.game.HandScrubberGeometry
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.withTimeoutOrNull

/** PortraitScrollScrubber: a gold thumb that scrolls the hand. */
@Composable
fun PortraitScrollScrubber(progress: Float, visible: Boolean, drag: (Float) -> Unit, modifier: Modifier = Modifier) {
    val currentProgress by rememberUpdatedState(progress)
    BoxWithConstraints(modifier.height(44.dp).graphicsLayer { alpha = if (visible) 1f else 0f }
        .semantics { contentDescription = "Scroll hand, ${(progress.coerceIn(0f, 1f) * 100).roundToInt()} percent" }
        .then(if (!visible) Modifier else Modifier.pointerInput(Unit) {
            awaitEachGesture {
                val down = awaitFirstDown()
                val trackWidth = size.width.toFloat() / density
                val thumbWidth = HandScrubberGeometry.thumbWidth(trackWidth)
                val travel = maxOf(trackWidth - thumbWidth, 1f)
                val thumbStart = travel * currentProgress.coerceIn(0f, 1f)
                val within = down.position.x / density - thumbStart
                val grab = if (within in 0f..thumbWidth) within else thumbWidth / 2
                drag(HandScrubberGeometry.progress(down.position.x / density, trackWidth, grab))
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                    if (change.changedToUp()) break
                    change.consume()
                    drag(HandScrubberGeometry.progress(change.position.x / density, trackWidth, grab))
                }
            }
        }), contentAlignment = Alignment.CenterStart) {
        val trackWidth = maxWidth.value.coerceAtLeast(1f)
        val thumbWidth = HandScrubberGeometry.thumbWidth(trackWidth)
        val travel = maxOf(trackWidth - thumbWidth, 1f)
        Box(Modifier.fillMaxWidth().height(8.dp).background(Color.White.copy(alpha = if (visible) 0.14f else 0f), CircleShape)) {
            Box(Modifier.offset(x = (travel * progress.coerceIn(0f, 1f)).dp).width(thumbWidth.dp).height(8.dp)
                .background(MagicPalette.antiqueGold.copy(alpha = if (visible) 0.78f else 0f), CircleShape))
        }
    }
}

/**
 * ContentView.swift PortraitHandRow: an Arena-style fanned hand. Tap expands it, hold
 * inspects, sideways swipes browse, and an upward drag onto your battlefield plays a card.
 */
@Composable
fun PortraitHandRow(
    cards: List<ZoneCard>, legalActions: List<LegalAction>, selection: BoardSelection, pendingCardInstanceId: String?,
    onInteractionMode: (GameBoardInteractionMode) -> Unit, playerDropZone: BoardRect, onOverPlayerDropZone: (Boolean) -> Unit,
    cardWidth: Float, cardHeight: Float, rowWidth: Float, onDropFeedback: (String) -> Unit,
    onActionChoice: (List<LegalAction>, String) -> Unit, runAction: (LegalAction) -> Unit, modifier: Modifier = Modifier,
) {
    val boardFXLevel by AppPreferences.string(BoardFXLevel.key, BoardFXLevel.defaultValue)
    val registry = LocalCardBounds.current
    val inspection = LocalHoldCardInspection.current
    val density = LocalDensity.current.density
    var handExpanded by remember { mutableStateOf(false) }
    var draggingCardId by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableStateOf(Offset.Zero) }
    var dragStartCenter by remember { mutableStateOf(Offset.Zero) }
    val handCardBounds = remember { mutableStateMapOf<String, BoardRect>() }
    var handOrigin by remember { mutableStateOf(Offset.Zero) }
    val scroll = rememberBoardScrollState()
    val reduceMotion = BoardMotion.reduceMotion
    val fansHand = !handExpanded && BoardFXLevel.of(boardFXLevel) != BoardFXLevel.OFF && !reduceMotion
    val spacing = ArenaHandLayout.spacing(cards.size, rowWidth, cardWidth, handExpanded)
    val contentWidth = cards.size * cardWidth + maxOf(cards.size - 1, 0) * spacing
    val restingHeight = ArenaHandLayout.restingHeight(cardHeight)
    val cardIds = cards.map { it.id }

    LaunchedEffect(cardIds) {
        val dragging = draggingCardId
        if (dragging != null && dragging !in cardIds) {
            draggingCardId = null; dragOffset = Offset.Zero; onOverPlayerDropZone(false)
        }
    }
    DisposableEffect(Unit) { onDispose { draggingCardId = null; onOverPlayerDropZone(false) } }

    fun boardPoint(bounds: BoardRect, start: Offset, translation: Offset): BoardPoint =
        BoardPoint(bounds.minX + (start.x + translation.x) / density, bounds.minY + (start.y + translation.y) / density)

    fun play(card: ZoneCard) {
        when (val result = DragCastDropResolver.resolve(card, legalActions, true)) {
            is DragCastDropResult.Submit -> runAction(result.action)
            is DragCastDropResult.RequiresChoice -> onActionChoice(result.actions, result.message)
            is DragCastDropResult.Rejected -> onDropFeedback(result.message)
            DragCastDropResult.Ignored -> {}
        }
    }

    @Composable
    fun handCard(index: Int, card: ZoneCard) {
        val playableActions = GameBoardInteractionState.legalPlayActions(card, legalActions)
        val selected = selection.selectedCard?.id == card.id
        val isDragging = draggingCardId == card.id
        val lift by animateFloatAsState(if (selected) -10f else 0f, if (reduceMotion) tween(0) else spring(0.8f, 500f), label = "handLift")
        val scale by animateFloatAsState(if (selected) 1.05f else 1f, if (reduceMotion) tween(0) else spring(0.8f, 500f), label = "handScale")
        val currentCard by rememberUpdatedState(card)
        val currentActions by rememberUpdatedState(playableActions)
        val cardX = 4 + index * (cardWidth + spacing)
        Box(Modifier
            .zIndex(if (isDragging) 1000f else if (selected) 900f else index.toFloat())
            .semantics { contentDescription = "${card.card.name} in hand. Tap to expand your hand. Hold to inspect. Drag upward to your battlefield to play." }
            .onGloballyPositioned { coordinates ->
                val origin = registry?.boardOrigin ?: Offset.Zero
                val rect = coordinates.boundsInRoot()
                handCardBounds[card.id] = BoardRect((rect.left - origin.x) / density, (rect.top - origin.y) / density, rect.width / density, rect.height / density)
            }
            .pointerInput(card.id) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val slop = viewConfiguration.touchSlop
                    // 0 = tap, 1 = hold, 2 = drag up, 3 = browse (the scroller owns it) or cancel.
                    val outcome = withTimeoutOrNull(350) {
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: return@withTimeoutOrNull 3
                            if (change.changedToUp()) return@withTimeoutOrNull 0
                            if (change.isConsumed) return@withTimeoutOrNull 3
                            val delta = change.position - down.position
                            if (delta.getDistance() > slop) {
                                // Reject sideways pans so the hand scroller owns browsing (HandCardPan).
                                return@withTimeoutOrNull if (delta.y < 0 && abs(delta.y) > abs(delta.x) * 1.35f) { change.consume(); 2 } else 3
                            }
                        }
                        @Suppress("UNREACHABLE_CODE") 3
                    } ?: 1
                    when (outcome) {
                        0 -> if (handExpanded) { selection.selectedCard = null; selection.inspectedCard = currentCard } else handExpanded = true
                        1 -> {
                            val release = { if (selection.inspectedCard?.id == currentCard.id) selection.inspectedCard = null }
                            inspection?.begin(release)
                            selection.selectedCard = null; selection.inspectedCard = currentCard
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                change.consume()
                                if (change.changedToUp()) break
                            }
                            if (inspection != null) inspection.end() else release()
                        }
                        2 -> {
                            val bounds = handCardBounds[currentCard.id] ?: return@awaitEachGesture
                            dragStartCenter = Offset(bounds.midX, bounds.midY)
                            GameAudio.play(GameSound.CARD_PICKUP)
                            var translation = Offset.Zero
                            var cancelled = false
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == down.id }
                                if (change == null) { cancelled = true; break }
                                translation = change.position - down.position
                                selection.selectedCard = null; selection.inspectedCard = null
                                draggingCardId = currentCard.id
                                dragOffset = translation / density
                                onOverPlayerDropZone(playerDropZone.contains(boardPoint(bounds, down.position, translation)))
                                onInteractionMode(GameBoardInteractionMode.DraggingCard(currentCard.instanceId, currentActions.map { it.id }))
                                change.consume()
                                if (change.changedToUp()) break
                            }
                            selection.selectedCard = null
                            val shouldPlay = !cancelled && playerDropZone.contains(boardPoint(bounds, down.position, translation))
                            draggingCardId = null; dragOffset = Offset.Zero; onOverPlayerDropZone(false)
                            if (!shouldPlay) { onInteractionMode(GameBoardInteractionMode.SelectedCard(currentCard.instanceId)); return@awaitEachGesture }
                            when (val result = DragCastDropResolver.resolve(currentCard, legalActions, true)) {
                                DragCastDropResult.Ignored -> onInteractionMode(GameBoardInteractionMode.SelectedCard(currentCard.instanceId))
                                is DragCastDropResult.Rejected -> {
                                    onDropFeedback(result.message); onInteractionMode(GameBoardInteractionMode.SelectedCard(currentCard.instanceId))
                                }
                                is DragCastDropResult.RequiresChoice -> {
                                    onDropFeedback(result.message); onActionChoice(result.actions, result.message)
                                    onInteractionMode(GameBoardInteractionMode.SelectedCard(currentCard.instanceId))
                                }
                                is DragCastDropResult.Submit -> {
                                    onInteractionMode(GameBoardInteractionMode.AwaitingCastSnapshot(result.action.id))
                                    if (result.action.type == "cast_spell") GameAudio.play(GameSound.CARD_PLAY)
                                    runAction(result.action)
                                }
                            }
                        }
                    }
                }
            }
            .graphicsLayer {
                // Arena-style fan: cards tilt and dip away from the visible center of the hand.
                val spread = if (fansHand) ((cardX + cardWidth / 2 - scroll.offset / density - rowWidth / 2) / maxOf(rowWidth / 2, 1f)).coerceIn(-1f, 1f) else 0f
                transformOrigin = TransformOrigin(0.5f, 1f)
                rotationZ = spread * 7f
                translationY = (spread * spread * 9f + lift) * density
                scaleX = scale; scaleY = scale
                alpha = if (isDragging) 0f else 1f
            }) {
            CardTile(card, selected, pending = pendingCardInstanceId == card.instanceId, legal = playableActions.any { it.type == "play_land" },
                castOffered = playableActions.any { it.type == "cast_spell" }, zoneName = "Hand", width = cardWidth.dp, height = cardHeight.dp)
            HandManaCost(card.card.manaCost ?: playableActions.firstOrNull()?.manaCost, Modifier.align(Alignment.TopEnd).offset(y = (-15).dp))
        }
    }

    @Composable
    fun handScroller() {
        BoardHorizontalScroller(scroll, Modifier.width(rowWidth.dp).height(if (handExpanded) (cardHeight + 20).dp else restingHeight.dp),
            clipHorizontal = 12.dp, clipTop = 48.dp, clipBottom = 0.dp, alignTop = true) {
            Row(Modifier.height((cardHeight + 20).dp).padding(top = 18.dp, start = 4.dp, end = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(spacing.dp), verticalAlignment = Alignment.Top) {
                cards.forEachIndexed { index, card -> key(card.id) { handCard(index, card) } }
            }
        }
    }

    @Composable
    fun controls() {
        Row(Modifier.width(rowWidth.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            PressableBox({ handExpanded = !handExpanded }, Modifier.semantics { contentDescription = if (handExpanded) "Tuck hand" else "Expand hand" }) {
                Row(Modifier.heightIn(min = 44.dp).background(Color.Black.copy(alpha = 0.78f), CircleShape)
                    .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.55f), CircleShape).padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    SfImage(if (handExpanded) "chevron.down" else "chevron.up", MagicPalette.parchment, 11.dp)
                    Text("Hand · ${cards.size}", color = MagicPalette.parchment, style = sf(11f, SfWeight.bold))
                }
            }
            PortraitScrollScrubber(scroll.progress, contentWidth + 8 > rowWidth + 1, scroll::scrollTo, Modifier.weight(1f))
        }
    }

    Box(modifier.width(rowWidth.dp).height(restingHeight.dp).onGloballyPositioned { coordinates ->
        val origin = registry?.boardOrigin ?: Offset.Zero
        val rect = coordinates.boundsInRoot()
        handOrigin = Offset((rect.left - origin.x) / density, (rect.top - origin.y) / density)
    }) {
        Box(Modifier.fillMaxSize().wrapContentHeight(Alignment.Bottom, unbounded = true)) {
            if (handExpanded) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { handScroller(); controls() }
            } else {
                Box(contentAlignment = Alignment.BottomCenter) { handScroller(); controls() }
            }
        }
        val dragging = draggingCardId?.let { id -> cards.firstOrNull { it.id == id } }
        if (dragging != null) {
            val actions = GameBoardInteractionState.legalPlayActions(dragging, legalActions)
            Box(Modifier.offset { IntOffset(((dragStartCenter.x + dragOffset.x - handOrigin.x - cardWidth / 2) * density).roundToInt(),
                ((dragStartCenter.y + dragOffset.y - handOrigin.y - cardHeight / 2) * density).roundToInt()) }.zIndex(2000f)) {
                CardTile(dragging, false, pending = pendingCardInstanceId == dragging.instanceId, legal = actions.any { it.type == "play_land" },
                    castOffered = actions.any { it.type == "cast_spell" }, zoneName = "Hand", width = cardWidth.dp, height = cardHeight.dp)
            }
        }
    }
}
