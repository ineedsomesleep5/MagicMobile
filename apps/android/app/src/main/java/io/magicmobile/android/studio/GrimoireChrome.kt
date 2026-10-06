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
import androidx.compose.runtime.remember
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
import androidx.compose.ui.input.pointer.pointerInput
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

    /** How far each page's content keeps clear of the fold of a spread, beyond its own margins. */
    val foldInset = 12.dp

    /** Sideways the book lies open as a spread of two pages, each with its own content. */
    fun isSpread(width: Int, height: Int): Boolean = width > height

}

/** GrimoirePaper: a parchment tone with the tavern's paper grain multiplied into it. */
fun Modifier.grimoirePaper(tone: Color = DeckStudioPalette.background, grain: Float = 0.26f, shape: Shape = RectangleShape): Modifier = composed {
    val image = tavernImage(R.drawable.tavern_ui_parchment)
    drawWithCache {
        // The texture is a @3x kit image: one point per three pixels, tiled.
        val shader = ImageShader(image, TileMode.Repeated, TileMode.Repeated)
        shader.setLocalMatrix(android.graphics.Matrix().apply { setScale(density / 3f, density / 3f) })
        val brush = ShaderBrush(shader)
        val outline = shape.createOutline(size, layoutDirection, this)
        onDrawBehind {
            drawOutline(outline, tone)
            drawOutline(outline, brush, alpha = grain, blendMode = BlendMode.Multiply)
        }
    }
}

/**
 * Makes a full screen of Deck Studio a page of the book: grained parchment, and over it only the gutter's
 * shadow and the leaf edges at the page's sides. Nothing is laid over the middle of the page, so card art keeps
 * its own colours. A loose leaf (a sheet) has no spine.
 */
fun Modifier.grimoirePage(bound: Boolean = true): Modifier = grimoirePaper().drawWithContent {
    drawContent()
    if (!bound) return@drawWithContent
    // Upright the spine is the left edge. Sideways the book is a spread: the spine runs down the middle (the
    // screens lay their content out as two pages, clear of it) with leaf edges at both sides.
    if (size.width > size.height) {
        gutter(size.width / 2, leading = true); gutter(size.width / 2, leading = false)
        leafEdges(trailing = true); leafEdges(trailing = false)
    } else {
        gutter(0f, leading = false); leafEdges(trailing = true)
    }
}

/** The shadow where a page curves down into the spine at `x`, falling away to one side. */
private fun DrawScope.gutter(x: Float, leading: Boolean) {
    val width = Grimoire.gutterWidth.toPx(); val ink = DeckStudioPalette.ink
    val left = if (leading) x - width else x
    val from = if (leading) left + width else left; val to = if (leading) left else left + width
    drawRect(Brush.horizontalGradient(0f to ink.copy(alpha = 0.34f), 0.35f to ink.copy(alpha = 0.12f), 1f to Color.Transparent, startX = from, endX = to),
        Offset(left, 0f), Size(width, size.height))
}

/** The cut edges of the leaves behind this page: a few fine lines down the fore-edge. */
private fun DrawScope.leafEdges(trailing: Boolean) {
    val width = Grimoire.edgeWidth.toPx(); val ink = DeckStudioPalette.ink
    val origin = if (trailing) size.width - width else 0f
    drawRect(Brush.horizontalGradient(listOf(ink.copy(alpha = if (trailing) 0.02f else 0.16f), ink.copy(alpha = if (trailing) 0.16f else 0.02f)),
        startX = origin, endX = origin + width), Offset(origin, 0f), Size(width, size.height))
    for (index in 0 until 4) {
        drawRect(ink.copy(alpha = 0.22f), Offset(origin + (index + 0.5f) * width / 4, 0f), Size(0.6.dp.toPx(), size.height))
    }
}

/** A place to write on the page (a search or text field): paler paper inside a hairline of ink. */
fun Modifier.grimoireField(shape: Shape): Modifier =
    background(DeckStudioPalette.surfaceElevated, shape).border(0.8.dp, DeckStudioPalette.ink.copy(alpha = 0.2f), shape)

/** A chapter heading in the book's hand: small capitals over a title, closed by an inked rule with the brand's sparkle. */
@Composable
fun GrimoireHeading(kicker: String, title: String, subtitle: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(kicker.uppercase(), color = DeckStudioPalette.accent, style = sf(12f, SfWeight.semibold, SfDesign.SERIF, tracking = 2.2f))
        Text(title, color = DeckStudioPalette.ink, style = sf(36f, SfWeight.bold, SfDesign.SERIF))
        subtitle?.let { Text(it, color = DeckStudioPalette.secondaryInk, style = sf(15f, design = SfDesign.SERIF).copy(fontStyle = FontStyle.Italic)) }
        GrimoireRule()
    }
}

/** An inked rule across the page with the sparkle at its centre. */
@Composable
fun GrimoireRule(modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().height(10.dp).clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        val ink = DeckStudioPalette.ink
        Canvas(Modifier.weight(1f).height(1.dp)) { drawRect(Brush.horizontalGradient(listOf(ink.copy(alpha = 0f), ink.copy(alpha = 0.45f)))) }
        BrandSparkle(9.dp, DeckStudioPalette.accent)
        Canvas(Modifier.weight(1f).height(1.dp)) { drawRect(Brush.horizontalGradient(listOf(ink.copy(alpha = 0.45f), ink.copy(alpha = 0f)))) }
    }
}

/**
 * Turns the page on a sideways swipe anywhere on it: leftward for `next`, rightward for `previous`. The swipe
 * is only watched (never consumed), and one that a child used for itself (a row of cards scrolling sideways)
 * turns nothing.
 */
fun Modifier.grimoireSwipe(next: () -> Unit, previous: () -> Unit): Modifier = pointerInput(Unit) {
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
