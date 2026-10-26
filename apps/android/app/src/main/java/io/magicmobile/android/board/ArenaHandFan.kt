package io.magicmobile.android.board

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import io.magicmobile.android.game.ArenaCanvas
import io.magicmobile.android.game.ArenaHandFanLayout
import io.magicmobile.android.game.ArenaHandPosture
import io.magicmobile.android.game.ArenaHandSlot
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.game.DragCastDropResolver
import io.magicmobile.android.game.DragCastDropResult
import io.magicmobile.android.game.GameBoardInteractionMode
import io.magicmobile.android.game.GameBoardInteractionState
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.game.union
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.tan

/**
 * Port of Board/ArenaHandFan.swift. The Arena board's hand, the reference game's way (Caleb, 2026-10-20): it rests tucked
 * along the bottom edge with only the cards' tops showing (in portrait, behind the front rail). A tap or a slide along the
 * hand pops up the card under the finger while the rest stay put; a second tap plays it, and carrying it up off the hand
 * and onto the table plays it too. A hold magnifies the card under the finger and follows it along the hand. A card you
 * draw flies off the top of your deck, shows itself, then joins the fan. Every play is DragCastDropResolver's, the same
 * action the Hearth hand sends.
 */
@Composable
fun ArenaHandFan(
    cards: List<ZoneCard>, extraCards: List<ZoneCard>, legalActions: List<LegalAction>, pendingCardInstanceId: String?, canvas: ArenaCanvas,
    posture: ArenaHandPosture, selection: BoardSelection, setInteractionMode: (GameBoardInteractionMode) -> Unit,
    setOverPlayerDropZone: (Boolean) -> Unit, liftedCardID: String?, setLiftedCardID: (String?) -> Unit,
    /** A spectator's stand-in: their hand stays hidden and only its size shows. */
    hiddenCount: Int?, raise: () -> Unit, lower: () -> Unit, onDropFeedback: (String) -> Unit,
    onActionChoice: (List<LegalAction>, String) -> Unit, runAction: (LegalAction) -> Unit, modifier: Modifier = Modifier,
) {
    val layout = canvas.layout
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val inspection = LocalHoldCardInspection.current
    val reduceMotion = BoardMotion.reduceMotion
    val cardSize = canvas.size(layout.hand.card)
    val all = cards + extraCards
    var dragging by remember { mutableStateOf<Triple<String, BoardPoint, BoardPoint>?>(null) }
    /** Where the popped card was when it was picked up: its touch surface stays there until the carry ends. */
    var carrySurface by remember { mutableStateOf<BoardRect?>(null) }
    /** The spread row's swipe, in design points from its first card. */
    var spreadScroll by remember { mutableStateOf(0f) }
    /** A touch on the spread row: where it began, the swipe then, and whether it is swiping. */
    var spreadTouch by remember { mutableStateOf<Triple<BoardPoint, Float, Boolean>?>(null) }
    /** Where a hold began: pulled up off the hand, the held card is carried like a drag (ArenaHandFan.swift). */
    var holdStart by remember { mutableStateOf<BoardPoint?>(null) }
    var known by remember { mutableStateOf<Set<String>?>(null) }
    /** Cards on their way in from the deck: 0 at the deck, 1 on show, 2 home in the fan. */
    val arrivals = remember { mutableStateMapOf<String, Int>() }

    fun slot(index: Int): ArenaHandSlot {
        val design = ArenaHandFanLayout.slot(index, all.size, posture, layout.hand, spreadScroll)
        return ArenaHandSlot(canvas.point(design.center), design.rotation, design.scale)
    }
    /** Past eight cards the fan is crowded: costs show only on the popped card, which pops larger (ArenaHandFan.swift). */
    val crowded = cards.size + extraCards.size > 8
    val liftedScale = when (posture) { ArenaHandPosture.SPREAD -> slot(0).scale * 1.1f; ArenaHandPosture.RAISED -> 1.24f; else -> if (crowded) 1.3f else 1.18f }
    fun liftedPoint(home: ArenaHandSlot, lifted: Boolean): BoardPoint {
        if (!lifted) return home.center
        // A spread card is already whole: it only rises a little.
        val rise = canvas.length(when (posture) { ArenaHandPosture.SPREAD -> 14f; ArenaHandPosture.RAISED -> layout.hand.lift; else -> layout.hand.liftDown })
        // Never below the point where the whole card clears the bottom edge.
        val highest = canvas.screen.height - cardSize.height * liftedScale / 2 - canvas.length(8f)
        return BoardPoint(home.center.x, min(home.center.y - rise, highest))
    }
    fun homeFrame(index: Int): BoardRect {
        val home = slot(index)
        val width = cardSize.width * home.scale; val height = cardSize.height * home.scale
        return BoardRect(home.center.x - width / 2, home.center.y - height / 2, width, height)
    }
    fun liftedFrame(index: Int): BoardRect {
        val center = liftedPoint(slot(index), true)
        val width = cardSize.width * liftedScale; val height = cardSize.height * liftedScale
        return BoardRect(center.x - width / 2, center.y - height / 2, width, height)
    }
    val liftedIndex = liftedCardID?.let { id -> all.indexOfFirst { it.id == id }.takeIf { it >= 0 } }
    val liftedRect = liftedIndex?.let(::liftedFrame)
    /** The fan's touch surface: every card's home frame, down to the layout's touch line. */
    val band: BoardRect = run {
        if (all.isEmpty()) return@run BoardRect.zero
        val union = all.indices.map(::homeFrame).reduce { a, b -> a.union(b) }
        val bottom = min(canvas.screen.height, layout.hand.touchBottom?.let(canvas::y) ?: canvas.screen.height)
        BoardRect(union.minX, union.minY, union.width, max(0f, bottom - union.minY))
    }

    /** The card under a point: of the cards whose home slot spans its x, the top one; the popped card first. */
    fun spreadCard(point: BoardPoint): ZoneCard? {
        if (liftedIndex != null && liftedFrame(liftedIndex).contains(point)) return all[liftedIndex]
        all.indices.firstOrNull { homeFrame(it).let { f -> BoardRect(f.x - 3, f.y - 10, f.width + 6, f.height + 20) }.contains(point) }?.let { return all[it] }
        return all.indices.minByOrNull { hypot(point.x - slot(it).center.x, point.y - slot(it).center.y) }?.let { all[it] }
    }
    fun card(point: BoardPoint): ZoneCard? {
        if (all.isEmpty()) return null
        if (posture == ArenaHandPosture.SPREAD) return spreadCard(point)
        val homes = all.indices.map(::slot)
        if (liftedIndex != null && abs(point.x - homes[liftedIndex].center.x) <= cardSize.width * liftedScale / 2 &&
            point.y >= liftedPoint(homes[liftedIndex], true).y - cardSize.height * liftedScale / 2) return all[liftedIndex]
        all.indices.lastOrNull { abs(point.x - homes[it].center.x) <= cardSize.width * homes[it].scale / 2 }?.let { return all[it] }
        return all.indices.minByOrNull { abs(point.x - homes[it].center.x) }?.let { all[it] }
    }
    /** The card a slide along the hand is over: each card owns the strip of it that shows, measured at the finger's height
     *  along its tilt, so a slide moves one card at a time; the finger passes a few points into the next strip first. */
    fun scrubCard(point: BoardPoint): ZoneCard? {
        if (all.isEmpty()) return null
        val homes = all.indices.map(::slot)
        fun left(index: Int): Float {
            val home = homes[index]
            val angle = Math.toRadians(home.rotation.toDouble())
            // Each card turns about the bottom of its frame.
            val pivotY = home.center.y + cardSize.height / 2
            val centerline = home.center.x + (pivotY - point.y) * tan(angle).toFloat()
            return centerline - cardSize.width * home.scale / 2 / max(0.5f, cos(angle).toFloat())
        }
        val index = all.indices.lastOrNull { left(it) <= point.x } ?: 0
        if (liftedIndex != null && liftedIndex != index) {
            val margin = canvas.length(6f)
            val next = if (liftedIndex + 1 < all.size) left(liftedIndex + 1) else Float.POSITIVE_INFINITY
            if (point.x >= left(liftedIndex) - margin && point.x < next + margin) return all[liftedIndex]
        }
        return all[index]
    }

    fun play(card: ZoneCard) {
        setLiftedCardID(null)
        when (val result = DragCastDropResolver.resolve(card, legalActions, true)) {
            is DragCastDropResult.Submit -> {
                setInteractionMode(GameBoardInteractionMode.AwaitingCastSnapshot(result.action.id))
                if (result.action.type == "cast_spell") GameAudio.play(GameSound.CARD_PLAY)
                runAction(result.action)
                lower()
            }
            is DragCastDropResult.RequiresChoice -> onActionChoice(result.actions, result.message)
            is DragCastDropResult.Rejected -> { onDropFeedback(result.message); GameHaptics.warning(view) }
            DragCastDropResult.Ignored -> {}
        }
    }
    fun tapped(point: BoardPoint) {
        val card = card(point) ?: return
        when {
            liftedCardID == card.id -> play(card)
            posture == ArenaHandPosture.RESTING && layout.hand.opensOnTap -> raise()
            else -> { setLiftedCardID(card.id); GameAudio.play(GameSound.CARD_PICKUP); GameHaptics.selection(view) }
        }
    }
    fun startCarry(card: ZoneCard, start: BoardPoint, offset: BoardPoint, finger: BoardPoint) {
        GameAudio.play(GameSound.CARD_PICKUP)
        carrySurface = liftedRect
        setLiftedCardID(null)
        selection.inspectedCard = null
        dragging = Triple(card.id, start, offset)
        setOverPlayerDropZone(canvas.drops(finger, start))
        setInteractionMode(GameBoardInteractionMode.DraggingCard(card.instanceId, GameBoardInteractionState.legalPlayActions(card, legalActions).map { it.id }))
    }
    /** Along the hand the card under the finger pops up; carried up off the hand, that card follows the finger until dropped. */
    fun panned(point: BoardPoint) {
        dragging?.let { (id, start, _) ->
            dragging = Triple(id, start, BoardPoint(point.x - start.x, point.y - start.y))
            setOverPlayerDropZone(canvas.drops(point, start))
            return
        }
        // Spread, every card shows whole: a sideways swipe moves the row, a slide up carries the card it starts on.
        val touch = spreadTouch
        if (posture == ArenaHandPosture.SPREAD && touch != null) {
            val dx = point.x - touch.first.x; val dy = point.y - touch.first.y
            // Decide nothing until the finger has moved: 0 >= 0 would lock the drag into a swipe (ArenaHandFan.swift).
            if (!touch.third && hypot(dx, dy) < canvas.length(6f)) return
            if (touch.third || abs(dx) >= abs(dy) || dy > 0) {
                spreadTouch = Triple(touch.first, touch.second, true)
                val maxScroll = ArenaHandFanLayout.spread(all.size, layout.hand)?.maxScroll ?: 0f
                spreadScroll = (touch.second - dx / max(canvas.scale, 0.01f)).coerceIn(0f, maxScroll)
                return
            }
            val card = spreadCard(touch.first) ?: return
            spreadTouch = null
            startCarry(card, touch.first, BoardPoint(dx, dy), point)
            return
        }
        if (point.y >= band.minY - canvas.length(12f)) {
            val card = scrubCard(point) ?: return
            if (liftedCardID == card.id) return
            setLiftedCardID(card.id)
            GameHaptics.selection(view)
            return
        }
        val popped = liftedCardID?.let { id -> all.firstOrNull { it.id == id } }
        val card = popped ?: card(BoardPoint(point.x, band.midY)) ?: return
        startCarry(card, point, BoardPoint(0f, 0f), point)
        setOverPlayerDropZone(false)
    }
    fun panStarted(point: BoardPoint) { spreadTouch = if (posture == ArenaHandPosture.SPREAD) Triple(point, spreadScroll, false) else null }
    /** A slide that never left the hand leaves its card popped up; a carried card plays if it lands on the table. */
    fun panEnded(point: BoardPoint, cancelled: Boolean) {
        carrySurface = null
        spreadTouch = null
        val current = dragging ?: return
        val card = all.firstOrNull { it.id == current.first } ?: return
        val dropped = !cancelled && canvas.drops(point, current.second)
        dragging = null
        setOverPlayerDropZone(false)
        if (!dropped) { setInteractionMode(GameBoardInteractionMode.Idle); return }
        when (val result = DragCastDropResolver.resolve(card, legalActions, true)) {
            DragCastDropResult.Ignored -> setInteractionMode(GameBoardInteractionMode.Idle)
            is DragCastDropResult.Rejected -> { onDropFeedback(result.message); setInteractionMode(GameBoardInteractionMode.Idle) }
            is DragCastDropResult.RequiresChoice -> { onDropFeedback(result.message); onActionChoice(result.actions, result.message); setInteractionMode(GameBoardInteractionMode.Idle) }
            is DragCastDropResult.Submit -> {
                setInteractionMode(GameBoardInteractionMode.AwaitingCastSnapshot(result.action.id))
                if (result.action.type == "cast_spell") GameAudio.play(GameSound.CARD_PLAY)
                runAction(result.action)
                lower()
            }
        }
    }

    /**
     * A hold magnifies the card under the finger; sliding while holding moves the magnifier along the hand. Pulled up off
     * the hand, the held card is picked up and carried (a press that paused before the drag never carried).
     */
    fun held(point: BoardPoint) {
        dragging?.let { (id, start, _) ->
            dragging = Triple(id, start, BoardPoint(point.x - start.x, point.y - start.y))
            setOverPlayerDropZone(canvas.drops(point, start))
            return
        }
        val start = holdStart ?: point.also { holdStart = it }
        if (start.y - point.y >= canvas.length(36f)) {
            card(start)?.let { held ->
                if (inspection != null) inspection.end() else selection.inspectedCard = null
                startCarry(held, start, BoardPoint(point.x - start.x, point.y - start.y), point)
                return
            }
        }
        val card = card(point) ?: return
        if (selection.inspectedCard?.id == card.id) return
        if (selection.inspectedCard == null) inspection?.begin { selection.inspectedCard = null }
        selection.inspectedCard = card
        GameHaptics.selection(view)
    }
    /** A hold that carried its card plays it where it lands, as a drag does; otherwise the magnifier closes. */
    fun endHold(point: BoardPoint, cancelled: Boolean) {
        holdStart = null
        if (dragging != null) return panEnded(point, cancelled)
        if (inspection != null) inspection.end() else selection.inspectedCard = null
    }

    // A card that joins the hand after the opening hand flies in from the deck. Several at once just slide in.
    val ids = cards.map { it.id }
    LaunchedEffect(ids) {
        val before = known
        known = ids.toSet()
        if (before == null || reduceMotion) return@LaunchedEffect
        val new = ids.filter { it !in before }
        if (new.isEmpty() || new.size > 3) return@LaunchedEffect
        new.forEachIndexed { offset, id ->
            arrivals[id] = 0
            scope.launch {
                delay((offset * 250 + 20).toLong()); arrivals[id] = 1
                delay(900); arrivals[id] = 2
                delay(240); arrivals.remove(id)
            }
        }
    }
    val allIds = all.map { it.id }
    LaunchedEffect(allIds) {
        dragging?.let { if (it.first !in allIds) { dragging = null; carrySurface = null; setOverPlayerDropZone(false) } }
        if (liftedCardID != null && liftedCardID !in allIds) setLiftedCardID(null)
        spreadScroll = min(spreadScroll, ArenaHandFanLayout.spread(all.size, layout.hand)?.maxScroll ?: 0f)
    }
    LaunchedEffect(posture) {
        if (posture == ArenaHandPosture.RESTING) setLiftedCardID(null)
        if (posture != ArenaHandPosture.SPREAD) spreadScroll = 0f
    }
    DisposableEffect(Unit) { onDispose { setOverPlayerDropZone(false) } }

    Box(modifier.fillMaxSize().semantics { testTag = "board.hand.scroll" }) {
        if (hiddenCount != null) {
            val shown = min(hiddenCount, 12)
            Box(Modifier.fillMaxSize().semantics { contentDescription = if (hiddenCount == 1) "1 card in hand" else "$hiddenCount cards in hand" }) {
                for (index in 0 until shown) {
                    val design = ArenaHandFanLayout.slot(index, shown, ArenaHandPosture.RESTING, layout.hand)
                    val center = canvas.point(design.center)
                    ArenaCardBack(Modifier.place(BoardRect(center.x - cardSize.width / 2, center.y - cardSize.height / 2, cardSize.width, cardSize.height))
                        .graphicsLayer { transformOrigin = TransformOrigin(0.5f, 1f); rotationZ = design.rotation; scaleX = design.scale; scaleY = design.scale })
                }
            }
            return@Box
        }
        if (posture == ArenaHandPosture.SPREAD) ArenaHandFanLayout.spread(all.size, layout.hand)?.let { grid ->
            // A soft shade under the spread cards, so the table behind doesn't read through the gaps.
            val top = canvas.y(grid.top) - canvas.length(10f)
            val bottom = layout.railTop?.let(canvas::y) ?: canvas.screen.height
            Box(Modifier.place(BoardRect(0f, top, canvas.screen.width, max(0f, bottom - top))).clearAndSetSemantics { }
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0f), Color.Black.copy(alpha = 0.55f), Color.Black.copy(alpha = 0.62f)))))
            if (grid.maxScroll > 0) {
                // Where the row is swiped to: a thin gold track over the row.
                val track = canvas.length(90f)
                val thumb = track * ArenaHandFanLayout.spreadWidth / grid.contentWidth
                Box(Modifier.centerAt(canvas.screen.width / 2, canvas.y(grid.top) - canvas.length(2f)).requiredSize(track.dp, 3.dp).clearAndSetSemantics { }
                    .drawBehind {
                        drawRoundRect(Color.White.copy(alpha = 0.18f), cornerRadius = CornerRadius(size.height / 2))
                        val x = (track - thumb) * (spreadScroll / grid.maxScroll).coerceIn(0f, 1f)
                        drawRoundRect(ArenaPalette.gold, Offset(x.dp.toPx(), 0f), Size(thumb.dp.toPx(), size.height), CornerRadius(size.height / 2))
                    })
            }
        }
        all.forEachIndexed { index, card ->
            key(card.id) {
                val extra = index >= cards.size
                val playable = GameBoardInteractionState.legalPlayActions(card, legalActions)
                val lifted = liftedCardID == card.id
                val home = slot(index)
                // A card drawn this moment starts at the deck in its very first frame, before the arrival is recorded.
                val fresh = !extra && !reduceMotion && known?.let { before -> card.id !in before && ids.count { it !in before } in 1..3 } == true
                val arrival = arrivals[card.id] ?: if (fresh) 0 else null
                val target = when (arrival) {
                    0 -> canvas.point(layout.viewerLibrary)
                    1 -> canvas.point(BoardPoint(layout.draw.midX, layout.draw.midY))
                    else -> liftedPoint(home, lifted)
                }
                val targetScale = when (arrival) {
                    0 -> layout.viewerPile.width / layout.hand.card.width
                    1 -> layout.draw.width / layout.hand.card.width
                    else -> if (lifted) liftedScale else home.scale
                }
                // Up: a quick ease-out with a small overshoot; down: a quicker ease-in (the reference's 0.22 s and 0.18 s).
                val duration = if (reduceMotion) 0 else when {
                    arrival == 1 -> 500
                    posture == ArenaHandPosture.RESTING && !lifted -> 180
                    posture == ArenaHandPosture.SPREAD -> 280
                    else -> 220
                }
                val x by animateFloatAsState(target.x, tween(duration), label = "handX")
                val y by animateFloatAsState(target.y, tween(duration), label = "handY")
                val rotation by animateFloatAsState(if (lifted || arrival != null) 0f else home.rotation, tween(duration), label = "handTurn")
                val scale by animateFloatAsState(targetScale, tween(duration), label = "handScale")
                val hidden = dragging?.first == card.id
                Box(Modifier
                    .zIndex(if (lifted) 900f else if (arrival == 1) 950f else index.toFloat())
                    .offset { IntOffset(((x - cardSize.width / 2) * density).roundToInt(), ((y - cardSize.height / 2) * density).roundToInt()) }
                    .requiredSize(cardSize.width.dp, cardSize.height.dp)
                    .graphicsLayer { transformOrigin = TransformOrigin(0.5f, 1f); rotationZ = rotation; alpha = if (hidden) 0f else 1f }
                    .graphicsLayer { scaleX = scale; scaleY = scale }
                    .semantics {
                        contentDescription = if (extra) "${card.card.name}, playable from your ${playable.firstOrNull()?.sourceZone ?: "zone"}" else card.card.name
                        customActions = listOf(CustomAccessibilityAction("Inspect card") { selection.inspectedCard = card; true },
                            CustomAccessibilityAction("Play card") { play(card); true })
                    }) {
                    CardTile(card, selected = false, pending = pendingCardInstanceId == card.instanceId, legal = playable.any { it.type == "play_land" },
                        castOffered = playable.any { it.type == "cast_spell" }, zoneName = "Hand", width = cardSize.width.dp, height = cardSize.height.dp)
                    if (!crowded || lifted || posture == ArenaHandPosture.SPREAD)
                        HandManaCost(card.card.manaCost ?: playable.firstOrNull()?.manaCost, Modifier.align(Alignment.TopCenter).offset(y = (-14).dp).clearAndSetSemantics { })
                    if (extra) ArenaExtraCardShimmer(playable.firstOrNull()?.sourceZone ?: "", cardSize.width)
                }
            }
        }
        if (all.isNotEmpty()) {
            ArenaHandTouch(band, Modifier.zIndex(1500f), ::tapped, ::held, ::endHold, ::panned, ::panEnded, ::panStarted)
            // The popped card takes touches over its whole picture too, on a surface of its own that stays where it was while
            // the card is carried, so the drag that started on it keeps going.
            (liftedRect ?: carrySurface)?.let { ArenaHandTouch(it, Modifier.zIndex(1501f), ::tapped, ::held, ::endHold, ::panned, ::panEnded, ::panStarted) }
        }
        dragging?.let { (id, start, offset) ->
            val card = all.firstOrNull { it.id == id } ?: return@let
            // The dragged card follows the finger, half again its size, leaning with the drag; over the table it settles smaller.
            val finger = BoardPoint(start.x + offset.x, start.y + offset.y)
            val over = canvas.drops(finger, start)
            val actions = GameBoardInteractionState.legalPlayActions(card, legalActions)
            Box(Modifier.zIndex(2000f).place(BoardRect(finger.x - cardSize.width / 2, finger.y - 10 - cardSize.height / 2, cardSize.width, cardSize.height))
                .graphicsLayer { val s = if (over) 1.38f else 1.5f; scaleX = s; scaleY = s; rotationZ = (offset.x * 0.06f).coerceIn(-12f, 12f) }
                .glow((if (over && actions.isNotEmpty()) TavernPalette.ember else Color.Black).copy(alpha = 0.7f), (if (over) 16 else 10).dp, 8.dp)
                .clearAndSetSemantics { }) {
                CardTile(card, selected = false, legal = actions.any { it.type == "play_land" }, castOffered = actions.any { it.type == "cast_spell" },
                    zoneName = "Hand", width = cardSize.width.dp, height = cardSize.height.dp)
            }
        }
    }
}

/**
 * One touch surface over `rect` (screen dp): a tap; a hold (0.3 s) that reports where the finger is while it stays down; and a
 * pan that starts once the finger moves before the hold, in any direction (ArenaHandTouch). Every report is in screen dp.
 */
@Composable
private fun ArenaHandTouch(rect: BoardRect, modifier: Modifier, tap: (BoardPoint) -> Unit, hold: (BoardPoint) -> Unit, holdEnded: (BoardPoint, Boolean) -> Unit,
                           pan: (BoardPoint) -> Unit, panEnded: (BoardPoint, Boolean) -> Unit, panStart: (BoardPoint) -> Unit) {
    val current by rememberUpdatedState(rect)
    val onTap by rememberUpdatedState(tap); val onHold by rememberUpdatedState(hold); val onHoldEnded by rememberUpdatedState(holdEnded)
    val onPan by rememberUpdatedState(pan); val onPanEnded by rememberUpdatedState(panEnded); val onPanStart by rememberUpdatedState(panStart)
    val density = LocalDensity.current.density
    Box(modifier.place(rect).clearAndSetSemantics { }.pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            val origin = current
            fun point(position: Offset) = BoardPoint(origin.minX + position.x / density, origin.minY + position.y / density)
            val slop = viewConfiguration.touchSlop
            var last = down.position
            // 0 tap, 1 pan, 2 cancelled; null: the finger held still (a hold).
            val outcome = withTimeoutOrNull(300) {
                while (true) {
                    val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: return@withTimeoutOrNull 2
                    last = change.position
                    if (!change.pressed) return@withTimeoutOrNull 0
                    if ((change.position - down.position).getDistance() > slop) { change.consume(); return@withTimeoutOrNull 1 }
                }
                @Suppress("UNREACHABLE_CODE") 2
            }
            when (outcome) {
                0 -> onTap(point(down.position))
                1 -> {
                    onPanStart(point(down.position))
                    onPan(point(last))
                    var cancelled = false
                    try {
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                            if (change == null) { cancelled = true; break }
                            last = change.position
                            change.consume()
                            if (!change.pressed) break
                            onPan(point(change.position))
                        }
                    } finally { onPanEnded(point(last), cancelled) }
                }
                null -> {
                    onHold(point(last))
                    var cancelled = false
                    try {
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                            if (change == null) { cancelled = true; break }
                            last = change.position
                            change.consume()
                            if (!change.pressed) break
                            onHold(point(change.position))
                        }
                    } finally { onHoldEnded(point(last), cancelled) }
                }
                else -> {}
            }
        }
    })
}

/** The shimmer around a card you can play from your graveyard or exile, with that zone's mark in its corner. */
@Composable
private fun ArenaExtraCardShimmer(zone: String, width: Float) {
    val shape = RoundedCornerShape((width * 0.06f).dp)
    Box(Modifier.fillMaxSize().clearAndSetSemantics { }) {
        Box(Modifier.fillMaxSize().glow(rgb(0.6, 0.55, 1.0), (width * 0.06f).dp, (width * 0.06f).dp)
            .border(maxOf(1.5f, width * 0.025f).dp, Brush.linearGradient(listOf(rgb(0.75, 0.6, 1.0), rgb(0.45, 0.85, 1.0), rgb(0.75, 0.6, 1.0))), shape))
        Box(Modifier.align(Alignment.TopStart).offset((-width * 0.06f).dp, (-width * 0.06f).dp).wrapContentSize(unbounded = true)
            .background(rgb(0.32, 0.22, 0.55), CircleShape).border(1.dp, TavernPalette.brass, CircleShape).padding((width * 0.05f).dp)) {
            SfImage(if (zone.lowercase() == "graveyard") "flame.fill" else "sparkles", Color.White, maxOf(9f, width * 0.12f).dp, Modifier.size(maxOf(9f, width * 0.12f).dp))
        }
    }
}
