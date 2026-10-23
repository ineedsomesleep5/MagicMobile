package io.magicmobile.android.menus

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.board.ManaSymbolView
import io.magicmobile.android.game.ArenaBoxGeometry
import io.magicmobile.android.ui.BoardMotionFlags
import io.magicmobile.android.ui.BrandMark
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.colorAdjust
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/*
 * Port of Menus/ArenaDeckBox.swift: a deck as Arena's deck box (Caleb, 2026-10-22: "very similar to how Magic Arena does
 * it"). The proportions are core's ArenaBoxGeometry, in dp.
 */

/** What a deck box shows: its name, commander and colours, and a line about it for TalkBack (its bracket). */
data class ArenaDeckBoxModel(
    /** The deck's selection id ("precon:…", "included:…", "local:…"). */
    val id: String,
    val name: String,
    val commander: String?,
    val colors: List<String>,
    val subtitle: String,
    /** A word on the box's corner ("PLAYING", "FIX"). */
    val tag: String? = null,
)

private val Float.d: Dp get() = this.dp

/**
 * A black box seen almost straight on, the commander's art on its front under a lid band stamped with the name, a dark side
 * with a clasp, the colours just above a black name plate. Choosing the deck opens the box: the lid lifts, the front folds
 * down to half height and the commander card rises out in front of the deck's card backs.
 */
@Composable
fun ArenaDeckBox(deck: ArenaDeckBoxModel, modifier: Modifier = Modifier, selected: Boolean = false, width: Dp = 120.dp, edit: (() -> Unit)? = null) {
    val g = ArenaBoxGeometry(width.value)
    val reduce = BoardMotionFlags.reduceMotion
    val openness by animateFloatAsState(if (selected) 1f else 0f, if (reduce) tween(0) else spring(dampingRatio = 0.74f, stiffness = 158f), label = "boxOpen")
    // One picture, so dimming the box (a search running) never shows the cards through its front.
    Box(modifier.width(width).height((g.boxHeight + g.plateHeight - g.plateOverlap).d)
        .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
        .semantics(mergeDescendants = true) {
            contentDescription = deck.commander?.let { "${deck.name}, $it" } ?: deck.name
            if (deck.subtitle.isNotEmpty()) stateDescription = deck.subtitle
            this.selected = selected
        }) {
        Box(Modifier.size(width, g.boxHeight.d).clearAndSetSemantics { }) {
            ArenaBoxBody(g, openness, deck.commander, deck.colors)
            // On a shut box only: an open one shows its cards, and the chosen deck says so beside the boxes.
            if (deck.tag != null && openness < 0.05f) {
                Text(deck.tag, Modifier.padding(start = 5.dp, top = (g.top + g.lidBand + 4f + g.cut * openness).d)
                    .background(Color.Black.copy(alpha = 0.78f), RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 3.dp),
                    color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(8.5f, SfWeight.heavy).copy(letterSpacing = 0.09.em))
            }
        }
        ArenaNamePlate(deck.name, Modifier.offset(y = (g.boxHeight - g.plateOverlap).d), selected, width, edit)
    }
}

/** Arena's "+" tile for a new deck: a dark rounded square with a glowing plus, as tall as a deck box. */
@Composable
fun ArenaNewDeckBox(modifier: Modifier = Modifier, width: Dp = 120.dp) {
    val g = ArenaBoxGeometry(width.value)
    val shape = RoundedCornerShape((g.width * 0.07f).d)
    Box(modifier.width(width).semantics { contentDescription = "New deck" }, contentAlignment = Alignment.Center) {
        Box(Modifier.size((g.width - g.side * 0.5f).d, (g.boxHeight + g.plateHeight - g.plateOverlap).d)
            .glow(Color.Black.copy(alpha = 0.6f), 6.dp, (g.width * 0.07f).d)
            .background(Brush.verticalGradient(listOf(rgb(0.14, 0.135, 0.15), rgb(0.06, 0.06, 0.07))), shape)
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape), contentAlignment = Alignment.Center) {
            // White with the menus' gold glow.
            Box(Modifier.requiredSize(width * 0.7f).drawBehind {
                drawCircle(Brush.radialGradient(listOf(ArenaMenuStyle.gold.copy(alpha = 0.45f), ArenaMenuStyle.ember.copy(alpha = 0.15f), Color.Transparent),
                    radius = size.minDimension / 2))
            })
            SfImage("plus", Color.White, width * 0.36f)
        }
    }
}

/** The box: back wall, lid, what's inside, the front and the side, drawn for `openness` 0 (shut) to 1 (open). */
@Composable
private fun ArenaBoxBody(g: ArenaBoxGeometry, openness: Float, commander: String?, colors: List<String>) {
    val rise = g.rise * openness
    val frontTop = g.frontTop(openness)
    Box(Modifier.size(g.width.d, g.boxHeight.d).drawBehind {
        blurredRoundRect(Color.Black.copy(alpha = 0.65f), 6.dp.toPx(), Rect(0f, 5.dp.toPx(), size.width, size.height + 5.dp.toPx()), 3.dp.toPx())
    }) {
        // The back wall: the box's dark inside, seen once the lid is up.
        Box(Modifier.offset((g.side * 0.5f).d, (-rise).d).size((g.width - g.side * 0.5f).d, (g.boxHeight - g.top + rise).d)
            .alpha(minOf(1f, openness * 3))
            .background(Brush.verticalGradient(listOf(rgb(0.10, 0.10, 0.11), rgb(0.02, 0.02, 0.025))), RoundedCornerShape(topStart = 3.dp, topEnd = 3.dp)))
        // Shut: the lid's top and its front band, stamped like Arena's.
        if (openness < 0.5f) ArenaBoxLid(g, Modifier.alpha(maxOf(0f, 1 - openness * 2)))
        // Open: the lid standing raised and tilted back on the back wall, the deck's art on its top.
        if (openness > 0f) {
            Box(Modifier.offset((g.side * 0.5f).d, (-rise - g.frontHeight * 0.34f + 1f).d).size(g.frontWidth.d, (g.frontHeight * 0.34f).d)
                .graphicsLayer {
                    alpha = openness
                    rotationX = 62f
                    transformOrigin = TransformOrigin(0.5f, 1f)
                    cameraDistance = 5f * density
                }
                .clip(RoundedCornerShape(2.dp))) {
                ArenaArt(commander ?: "", colors, Modifier.fillMaxSize())
                Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.38f)).drawBehind {
                    drawRect(Color.Black.copy(alpha = 0.85f), Offset(0f, size.height - 2.dp.toPx()), Size(size.width, 2.dp.toPx()))
                    drawRect(Color.White.copy(alpha = 0.25f), size = Size(size.width, 1.dp.toPx()))
                })
            }
            // The deck itself, risen out of the box.
            ArenaBoxContents(g, commander, colors, Modifier.offset(y = ((1 - openness) * g.frontHeight * 0.55f).d).alpha(minOf(1f, openness * 2.5f)))
        }
        // The front: the art below the lid, folding down to half height as the box opens.
        Box(Modifier.offset(y = g.top.d).size(g.frontWidth.d, g.frontHeight.d).clip(FrontShape(frontTop - g.top))) {
            ArenaArt(commander ?: "", colors, Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.6f))))
            ArenaPips(colors, g.pip.d, Modifier.align(Alignment.BottomCenter).padding(bottom = (g.plateOverlap + g.width * 0.025f).d))
            // The folded edge of the open front: a lit lip with its shadow under it.
            if (openness > 0f) Box(Modifier.offset(y = (frontTop - g.top).d).fillMaxWidth().height(8.dp).alpha(openness).drawBehind {
                val lip = 3.dp.toPx()
                drawRect(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.55f), Color.White.copy(alpha = 0.12f)), 0f, lip), size = Size(size.width, lip))
                drawRect(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent), lip, size.height), Offset(0f, lip),
                    Size(size.width, size.height - lip))
            })
        }
        // The right side with its clasp, following the lid up.
        Canvas(Modifier.offset(x = g.frontWidth.d).size(g.side.d, g.boxHeight.d)) {
            val top = g.top.dp.toPx(); val cut = g.cut.dp.toPx(); val lift = g.rise.dp.toPx()
            val side = Path().apply {
                moveTo(0f, top + cut * openness)
                lineTo(size.width, -lift * openness)
                // The far edge a little shorter than the near one: the side recedes.
                lineTo(size.width, size.height - top * 2.2f)
                lineTo(0f, size.height)
                close()
            }
            drawPath(side, Brush.horizontalGradient(listOf(rgb(0.13, 0.13, 0.14), rgb(0.03, 0.03, 0.035))))
            val claspW = size.width * 0.24f; val claspH = g.frontHeight.dp.toPx() * 0.34f
            val center = Offset(size.width / 2 - size.width * 0.04f, size.height / 2 + g.frontHeight.dp.toPx() * 0.16f)
            val clasp = Rect(center.x - claspW / 2, center.y - claspH / 2, center.x + claspW / 2, center.y + claspH / 2)
            drawRoundRect(Color.Black.copy(alpha = 0.75f), clasp.topLeft, clasp.size, CornerRadius(claspW / 2))
            drawRoundRect(Color.White.copy(alpha = 0.12f), clasp.topLeft, clasp.size, CornerRadius(claspW / 2),
                style = androidx.compose.ui.graphics.drawscope.Stroke(0.6.dp.toPx()))
        }
    }
}

/** The front's visible part: from `top` (where the folded edge stands) to the foot, the bottom corners rounded. */
private class FrontShape(private val top: Float) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val y = with(density) { top.dp.toPx() }.coerceIn(0f, size.height)
        val left = with(density) { 3.dp.toPx() }; val right = with(density) { 2.dp.toPx() }
        return Outline.Rounded(RoundRect(0f, y, size.width, size.height, topLeftCornerRadius = CornerRadius.Zero, topRightCornerRadius = CornerRadius.Zero,
            bottomRightCornerRadius = CornerRadius(right), bottomLeftCornerRadius = CornerRadius(left)))
    }
}

/** The lid: its thin top face and the black band across the front with the MagicMobile stamp. */
@Composable
private fun ArenaBoxLid(g: ArenaBoxGeometry, modifier: Modifier) {
    Box(modifier.size(g.width.d, (g.top + g.lidBand).d)) {
        Canvas(Modifier.size(g.width.d, g.top.d)) {
            val side = g.side.dp.toPx()
            val top = Path().apply { moveTo(0f, size.height); lineTo(side, 0f); lineTo(size.width, 0f); lineTo(size.width - side, size.height); close() }
            drawPath(top, Brush.verticalGradient(listOf(rgb(0.22, 0.22, 0.23), rgb(0.09, 0.09, 0.10))))
            drawRect(Color.White.copy(alpha = 0.22f), Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()))
        }
        Box(Modifier.offset(y = g.top.d).size(g.frontWidth.d, g.lidBand.d).clip(RoundedCornerShape(topStart = 2.5.dp))
            .background(Brush.verticalGradient(listOf(rgb(0.11, 0.11, 0.12), rgb(0.04, 0.04, 0.045))))
            .drawBehind { drawRect(Color.Black.copy(alpha = 0.8f), Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx())) },
            contentAlignment = Alignment.Center) {
            FitText("MAGICMOBILE", sf(maxOf(5f, g.lidBand * 0.62f), SfWeight.heavy, SfDesign.SERIF).copy(letterSpacing = 0.29.em,
                shadow = androidx.compose.ui.graphics.Shadow(Color.Black, Offset(0f, -1f), 0f)),
                Modifier.padding(horizontal = (g.frontWidth * 0.18f).d), color = rgb(0.42, 0.41, 0.40), minimumScale = 0.5f)
        }
    }
}

/** The app's own card back for the cards in an open box (never the Magic back in the menus): dark walnut under a gold frame line, the M mark with an ember glow behind it. */
@Composable
private fun ArenaBoxCardBack(width: Dp, height: Dp, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(width * 0.06f)
    Box(modifier.size(width, height).clip(shape).background(Brush.verticalGradient(listOf(rgb(0.17, 0.10, 0.06), rgb(0.07, 0.04, 0.03))))
        .drawBehind { drawCircle(Brush.radialGradient(listOf(ArenaMenuStyle.ember.copy(alpha = 0.35f), Color.Transparent), radius = size.width * 0.55f)) }
        .border(maxOf(1.dp, width * 0.035f), Color.Black.copy(alpha = 0.85f), shape), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().padding(width * 0.07f).border(maxOf(0.6.dp, width * 0.012f), ArenaMenuStyle.gold.copy(alpha = 0.7f), RoundedCornerShape(width * 0.04f)))
        BrandMark(width * 0.5f, glint = false)
    }
}

/** What stands in the open box: three card backs, and the commander card in front of them. */
@Composable
private fun ArenaBoxContents(g: ArenaBoxGeometry, commander: String?, colors: List<String>, modifier: Modifier) {
    val height = g.frontHeight * 1.12f
    val cardWidth = height * 0.716f
    Box(modifier.offset((g.side * 0.5f).d, (g.top + g.lidBand * 0.5f - g.rise).d).size(g.frontWidth.d, height.d), contentAlignment = Alignment.TopCenter) {
        // Two backs fanned behind the commander, one to each side of it, and one standing behind; the fan stays inside the front face.
        listOf(-0.13f to -5f, 0.07f to 3f, 0.15f to 6f).forEach { (shift, angle) ->
            ArenaBoxCardBack((cardWidth * 0.84f).d, (height * 0.9f).d, Modifier.offset((g.frontWidth * shift).d, 3.dp)
                .graphicsLayer { rotationZ = angle; transformOrigin = TransformOrigin(0.5f, 1f) })
        }
        val corner = RoundedCornerShape((cardWidth * 0.05f).d)
        Box(Modifier.offset((-g.frontWidth * 0.06f).d, (-g.rise * 0.1f).d).size(cardWidth.d, height.d)
            .graphicsLayer { rotationZ = -3f; transformOrigin = TransformOrigin(0.5f, 1f) }
            .glow(Color.Black.copy(alpha = 0.7f), 4.dp, (cardWidth * 0.05f).d).clip(corner)) {
            CardArtwork(commander ?: "", Modifier.fillMaxSize()) { ArenaColorGlass(colors, Modifier.fillMaxSize()) }
        }
    }
}

/** The plate under a deck box: black, the name on one line, and Arena's pencil. */
@Composable
fun ArenaNamePlate(title: String, modifier: Modifier = Modifier, selected: Boolean = false, width: Dp, edit: (() -> Unit)? = null) {
    val g = ArenaBoxGeometry(width.value)
    Row(modifier.size(width, g.plateHeight.d)
        .glow(if (selected) rgb(1.0, 0.78, 0.36).copy(alpha = 0.55f) else Color.Transparent, 6.dp, (g.plateHeight / 2).d)
        .background(Color.Black.copy(alpha = 0.92f), CircleShape)
        .border(if (selected) 1.4.dp else 0.8.dp, if (selected) rgb(1.0, 0.88, 0.56) else Color.White.copy(alpha = 0.1f), CircleShape)
        .padding(start = if (edit == null) 8.dp else 10.dp, end = if (edit == null) 8.dp else 2.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
        // Small boxes (a table's seats) shrink the name further rather than cut it.
        FitText(title, ArenaMenuStyle.font(maxOf(11f, width.value * 0.098f), SfWeight.bold), Modifier.weight(1f), color = Color.White.copy(alpha = 0.95f),
            minimumScale = if (width < 90.dp) 0.55f else 0.7f, textAlign = TextAlign.Center)
        if (edit != null) BrandPressable(edit, Modifier.size(28.dp).testTag("deck.edit").semantics { contentDescription = "Edit $title"; role = androidx.compose.ui.semantics.Role.Button }) {
            SfImage("pencil", Color.White.copy(alpha = 0.55f), maxOf(10.dp, width * 0.085f))
        }
    }
}

/** A deck's colours as mana symbols, W U B R G order; colourless when it has none. Arena's pips are saturated. */
@Composable
fun ArenaPips(colors: List<String>, size: Dp = 15.dp, modifier: Modifier = Modifier) {
    val shown = listOf("W", "U", "B", "R", "G").filter { it in colors }
    Row(modifier.colorAdjust(saturation = 1.9f).clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        if (shown.isEmpty()) ManaSymbolView("C", size) else shown.forEach { ManaSymbolView(it, size) }
    }
}
