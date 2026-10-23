package io.magicmobile.android.studio

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import io.magicmobile.android.R
import io.magicmobile.android.ui.BrandSparkle
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.tavernImage
import kotlin.math.abs
import kotlin.math.hypot

/**
 * GrimoireChrome.swift: Deck Studio as a spell book. Every screen is a parchment page of the grimoire the
 * opening film shows. The page's colours stay the Deck Studio palette; this file adds what makes it a book:
 * the paper grain under everything, the shadow in the gutter by the spine, the cut edges of the leaves beyond
 * the page, ribbon markers for chapters and serif type throughout (StudioTheme's `sf`).
 */
object Grimoire {
    /** How wide the gutter's shadow and the stack of leaf edges are. */
    val gutterWidth = 26.dp
    val edgeWidth = 7.dp

    /** The height of a page's head (the plaques along its top): a drag that begins there turns nothing (PAGE_CURL.md). */
    val headBand = 64.dp

    /** How far each page's content keeps clear of the fold of a spread, beyond its own margins. */
    val foldInset = 12.dp

    /** Sideways the book lies open as a spread of two pages, each with its own content. */
    fun isSpread(width: Int, height: Int): Boolean = width > height

}

/**
 * GrimoirePaper: a page's surface. It was the book's grained parchment; since the Arena menus (Caleb, 2026-10-22) a page
 * ([DeckStudioPalette.background], the default) is Arena's dark glass, a little lighter at the top, and anything lighter
 * (a plate, [DeckStudioPalette.surface]) a lighter pane over it. `grain` is kept for callers.
 */
fun Modifier.grimoirePaper(tone: Color = DeckStudioPalette.background, @Suppress("UNUSED_PARAMETER") grain: Float = 0.26f, shape: Shape = RectangleShape): Modifier =
    drawWithCache {
        val outline = shape.createOutline(size, layoutDirection, this)
        val page = tone == DeckStudioPalette.background
        val brush = Brush.verticalGradient(listOf(io.magicmobile.android.menus.ArenaGlass.top.copy(alpha = 0.94f),
            io.magicmobile.android.menus.ArenaGlass.bottom.copy(alpha = 0.96f)))
        onDrawBehind {
            if (page) drawOutline(outline, brush) else drawOutline(outline, Color.White.copy(alpha = 0.055f))
        }
    }

/** Makes a full screen of Deck Studio a page: Arena's dark glass (the book's spine and leaf edges are gone). */
fun Modifier.grimoirePage(@Suppress("UNUSED_PARAMETER") bound: Boolean = true): Modifier = grimoirePaper()

/** A place to write on the page (a search or text field): a darker pane in the gold hairline. */
fun Modifier.grimoireField(shape: Shape): Modifier =
    background(Color.Black.copy(alpha = 0.5f), shape).border(0.9.dp, binderHairline(0.7f), shape)

/** A chapter heading: gold small capitals over a serif title with a black shadow, and a dim line under it. */
@Composable
fun GrimoireHeading(kicker: String, title: String, subtitle: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        io.magicmobile.android.menus.ArenaCaps(kicker, 11f)
        Text(title, color = io.magicmobile.android.menus.ArenaMenuStyle.text,
            style = sf(30f, SfWeight.bold, SfDesign.SERIF).copy(shadow = Shadow(Color.Black, Offset.Zero, 4f)))
        subtitle?.let { Text(it, color = io.magicmobile.android.menus.ArenaMenuStyle.dim, style = sf(14f)) }
    }
}

/** A gold hairline across the page. */
@Composable
fun GrimoireRule(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(1.dp).background(binderHairline(0.5f)).clearAndSetSemantics {})
}

/**
 * Turns the page on a sideways drag anywhere on it: leftward for `next`, rightward for `previous`. The page curls
 * under the finger (GrimoireStage, PageCurlShader) and finishes or springs back when it lets go. This only registers
 * the screen's chapter turns with the book while the screen is on show; the drags themselves are watched by
 * `watchGrimoireDrags` on the book (GrimoirePages), which carry on when a turn takes the screen away. Outside a
 * book it watches the swipe itself and turns the page when it ends.
 */
fun Modifier.grimoireSwipe(next: () -> Unit, previous: () -> Unit): Modifier = composed {
    val stage = LocalGrimoireStage.current
    val currentNext by rememberUpdatedState(next)
    val currentPrevious by rememberUpdatedState(previous)
    if (stage == null) Modifier.pointerInput(Unit) { watchSwipeWhenItEnds({ currentNext() }, { currentPrevious() }) }
    else {
        DisposableEffect(stage) {
            val token = Any()
            stage.registerSwipe(token, { currentNext() }, { currentPrevious() })
            onDispose { stage.unregisterSwipe(token) }
        }
        Modifier
    }
}

/** A swipe of more than 80 dp, mostly sideways and not used by a child (a row of cards scrolling), turns the page when it ends. */
private suspend fun PointerInputScope.watchSwipeWhenItEnds(next: () -> Unit, previous: () -> Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Final)
        var last = down.position; var claimed = false
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Final)
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            // A sideways scroller under the finger consumes the movement it uses.
            val across = abs(change.position.x - change.previousPosition.x); val along = abs(change.position.y - change.previousPosition.y)
            if (change.isConsumed && across > along) claimed = true
            last = change.position
            if (!change.pressed) break
        }
        val across = last.x - down.position.x; val along = last.y - down.position.y
        if (!claimed && abs(across) > 80.dp.toPx() && abs(across) > 2.5f * abs(along)) { if (across < 0) next() else previous() }
    }
}

private enum class DragPhase { UNDECIDED, DRAGGING, IGNORED, LEGACY }

/**
 * Watches every gesture on the book, only watching: a drag that starts sideways turns the page under the finger. Once
 * the finger has moved 12 dp a mostly sideways drag that no child has used for itself (a row of cards scrolling, a
 * vertical scroll, a slider) starts the turn; anything else is left alone for the rest of the gesture. With animations
 * off a swipe turns the page when it ends instead.
 */
internal suspend fun PointerInputScope.watchGrimoireDrags(stage: GrimoireStage) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Final)
        if (!stage.hasSwipes) return@awaitEachGesture
        val slop = 12.dp.toPx()
        val tracker = VelocityTracker().also { it.addPosition(down.uptimeMillis, down.position) }
        var phase = if (stage.effect == PageEffect.CURL) DragPhase.UNDECIDED else DragPhase.LEGACY
        var consumed = false
        var last = down.position
        var cancelled = false
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Final)
            val change = event.changes.firstOrNull { it.id == down.id }
            if (change == null) { cancelled = true; break }
            tracker.addPosition(change.uptimeMillis, change.position)
            if (change.isConsumed) consumed = true
            last = change.position
            val dx = last.x - down.position.x; val dy = last.y - down.position.y
            if (phase == DragPhase.UNDECIDED && hypot(dx, dy) >= slop) {
                phase = if (consumed || abs(dx) <= 2f * abs(dy) || !stage.pageMayCurl(down.position)) DragPhase.IGNORED else {
                    val forward = dx < 0
                    val begun = stage.beginDrag(forward, down.position.x, probe = { if (forward) stage.swipeNext() else stage.swipePrevious() },
                        revert = { if (forward) stage.swipePrevious() else stage.swipeNext() })
                    if (begun) DragPhase.DRAGGING else DragPhase.IGNORED
                }
            }
            if (phase == DragPhase.DRAGGING) stage.dragChanged(dx, dy)
            if (!change.pressed) break
        }
        val dx = last.x - down.position.x; val dy = last.y - down.position.y
        when (phase) {
            DragPhase.DRAGGING -> stage.dragEnded(if (cancelled) 0f else tracker.calculateVelocity().x, cancelled)
            DragPhase.LEGACY -> if (!consumed && stage.pageMayCurl(down.position) && abs(dx) > 80.dp.toPx() && abs(dx) > 2.5f * abs(dy)) { if (dx < 0) stage.swipeNext() else stage.swipePrevious() }
            else -> {}
        }
    }
}
