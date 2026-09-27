package io.magicmobile.android.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.GameResumeText
import io.magicmobile.android.game.GameplayActionPresentation
import io.magicmobile.android.game.HowToPlayPage
import io.magicmobile.android.game.HowToPlayText
import io.magicmobile.android.studio.DeckStudioPlayText
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Port of HowToPlayView.swift: the paged "How to play" walkthrough in the menu brand. It opens once by
 * itself on the main menu (HowToPlayLaunch) and any time from the menu or the Game Menu.
 */
@Composable
fun HowToPlayView(close: () -> Unit, modifier: Modifier = Modifier) {
    val pages = HowToPlayText.pages
    val pager = rememberPagerState(pageCount = { pages.size })
    val scope = rememberCoroutineScope()
    val reduceMotion = BoardMotionFlags.reduceMotion
    val index = pager.currentPage
    val isLast = index == pages.size - 1
    var turned by remember { mutableStateOf(false) }
    LaunchedEffect(index) { if (turned) GameAudio.play(GameSound.PAGE_FLIP) else turned = true }

    fun go(step: Int) {
        val next = (index + step).coerceIn(0, pages.size - 1)
        if (next == index) return
        scope.launch { if (reduceMotion) pager.scrollToPage(next) else pager.animateScrollToPage(next) }
    }
    fun finish() { GameAudio.play(GameSound.UI_CLOSE); close() }

    BoxWithConstraints(modifier.background(BrandTheme.canvas).drawBehind {
        drawRect(Brush.radialGradient(listOf(BrandTheme.ember.copy(alpha = 0.12f), Color.Transparent), Offset(size.width / 2, 0f), 420.dp.toPx()))
    }) {
        val wide = maxWidth > maxHeight
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                BrandMark(28.dp, glint = false)
                Spacer(Modifier.width(10.dp))
                Text(HowToPlayText.TITLE.uppercase(), Modifier.semantics { heading(); contentDescription = HowToPlayText.TITLE },
                    color = BrandTheme.ember, style = sf(13f, SfWeight.heavy, tracking = 2.4f))
                Spacer(Modifier.weight(1f))
                Box(Modifier.defaultMinSize(44.dp, 44.dp).alpha(if (isLast) 0f else 1f).testTag("howToPlay.skip")
                    .then(if (isLast) Modifier.clearAndSetSemantics {} else Modifier.clickable(role = Role.Button) { finish() }),
                    contentAlignment = Alignment.Center) {
                    Text(HowToPlayText.SKIP, color = BrandTheme.inkSecondary, style = sf(17f, SfWeight.semibold))
                }
            }
            HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth()) { page -> HowToPlayPageView(pages[page], wide) }
            Column(Modifier.fillMaxWidth().widthIn(max = 560.dp).padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                ProgressDots(index, pages.size, reduceMotion, next = { go(1) }, back = { go(-1) })
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    BrandButton({ go(-1) }, Modifier.weight(1f).testTag("howToPlay.back"), kind = BrandButtonKind.SECONDARY, enabled = index > 0) {
                        BrandButtonText(HowToPlayText.BACK, BrandButtonKind.SECONDARY)
                    }
                    if (isLast) BrandButton({ finish() }, Modifier.weight(1f).testTag("howToPlay.done")) { BrandButtonText(HowToPlayText.DONE) }
                    else BrandButton({ go(1) }, Modifier.weight(1f).testTag("howToPlay.next")) { BrandButtonText(HowToPlayText.NEXT) }
                }
            }
        }
    }
}

/** Dots with the current page drawn long; TalkBack hears "Page 3 of 10", with Next and Back actions. */
@Composable
private fun ProgressDots(index: Int, count: Int, reduceMotion: Boolean, next: () -> Unit, back: () -> Unit) {
    Row(Modifier.heightIn(min = 20.dp).testTag("howToPlay.progress").clearAndSetSemantics {
        contentDescription = HowToPlayText.progress(index + 1, count)
        liveRegion = LiveRegionMode.Polite
        customActions = listOf(CustomAccessibilityAction(HowToPlayText.NEXT) { next(); true },
            CustomAccessibilityAction(HowToPlayText.BACK) { back(); true })
    }, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(count) { page ->
            val width by animateDpAsState(if (page == index) 22.dp else 7.dp, tween(if (reduceMotion) 0 else 200), label = "howToPlayDot")
            Box(Modifier.size(width, 7.dp).background(if (page == index) BrandTheme.ember else BrandTheme.border, CircleShape))
        }
    }
}

/** One page: the drawing, then the title and body. The page scrolls, so large text never clips. */
@Composable
private fun HowToPlayPageView(page: HowToPlayPage, wide: Boolean) {
    val words: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier.widthIn(max = 480.dp), horizontalAlignment = if (wide) Alignment.Start else Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val align = if (wide) TextAlign.Start else TextAlign.Center
            Text(page.title, Modifier.semantics { heading() }, color = BrandTheme.ink, style = sf(28f, SfWeight.black, tracking = -0.4f), textAlign = align)
            Text(page.body, color = BrandTheme.inkSecondary, style = SfText.body(), textAlign = align)
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 18.dp).testTag("howToPlay.page.${page.id}"),
        horizontalAlignment = Alignment.CenterHorizontally) {
        if (wide) Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
            HowToPlayIllustration(page.id, Modifier.widthIn(max = 300.dp).fillMaxWidth(0.45f).height(200.dp))
            words(Modifier.weight(1f))
        } else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
            HowToPlayIllustration(page.id, Modifier.widthIn(max = 360.dp).fillMaxWidth().height(200.dp))
            words(Modifier)
        }
    }
}

// Illustrations

/**
 * Small drawn mockups of the real controls. Decorative: the page's words say the same, so TalkBack
 * skips them, and their type ignores the font scale so they never grow out of their frame.
 */
@Composable
fun HowToPlayIllustration(pageID: String, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    val shape = RoundedCornerShape(20.dp)
    CompositionLocalProvider(LocalDensity provides Density(density.density, 1f)) {
        Box(modifier.clip(shape).background(Brush.verticalGradient(listOf(BrandTheme.surfaceRaised, BrandTheme.canvas)))
            .drawBehind { drawRect(Brush.radialGradient(listOf(BrandTheme.ember.copy(alpha = 0.16f), Color.Transparent), center, 170.dp.toPx())) }
            .border(1.dp, BrandTheme.border, shape).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            when (pageID) {
                "welcome" -> Welcome()
                "decks" -> Decks()
                "start" -> Start()
                "board" -> MiniBoard()
                "casting" -> Casting()
                "priority" -> Priority()
                "combat" -> Combat()
                "reading" -> Reading()
                "resume" -> Resume()
                "friends" -> Friends()
            }
        }
    }
}

@Composable
private fun Welcome() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        BrandMark(84.dp)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Chip("COMMANDER"); Chip("RULES BY XMAGE") }
    }
}

@Composable
private fun Decks() {
    Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
        MiniCard(78.dp, BrandTheme.ember, "crown.fill")
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Text("YOUR DECK", color = BrandTheme.ember, style = sf(9f, SfWeight.heavy, tracking = 2f))
            Text("Token Triumph", color = BrandTheme.ink, style = sf(17f, SfWeight.heavy))
            Row(Modifier.background(MagicPalette.emerald.copy(alpha = 0.16f), CircleShape).border(1.dp, MagicPalette.emerald.copy(alpha = 0.6f), CircleShape)
                .padding(horizontal = 8.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("checkmark.seal.fill", MagicPalette.emerald, 10.dp)
                Text(DeckStudioPlayText.playing, color = MagicPalette.emerald, style = sf(10f, SfWeight.heavy))
            }
            Pill(DeckStudioPlayText.play, PillStyle.EMBER, "play.fill")
        }
    }
}

@Composable
private fun Start() {
    Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
        D20(78.dp)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.height(60.dp), contentAlignment = Alignment.Center) {
                listOf(MagicPalette.arcaneBlue, MagicPalette.emerald, BrandTheme.ember).forEachIndexed { card, tint ->
                    MiniCard(38.dp, tint, modifier = Modifier.offset(x = 16.dp * (card - 1))
                        .graphicsLayer { rotationZ = (card - 1) * 12f; transformOrigin = TransformOrigin(0.5f, 1f) })
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { Pill("Mulligan", PillStyle.QUIET); Pill("Keep", PillStyle.EMBER) }
        }
    }
}

@Composable
private fun Priority() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            MiniCard(22.dp, MagicPalette.oxblood, "bolt.fill")
            Text("On the stack", color = MagicPalette.parchment.copy(alpha = 0.7f), style = sf(10f, SfWeight.bold))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Pill("Pass Priority", PillStyle.DOCK, "forward.end.fill")
            Text(GameplayActionPresentation.priorityDetail(false), color = MagicPalette.parchment.copy(alpha = 0.8f), style = sf(10f))
        }
        Pill("Skip…", PillStyle.QUIET, "forward.end")
    }
}

@Composable
private fun Combat() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(30.dp), verticalAlignment = Alignment.CenterVertically) {
            MiniCard(56.dp, MagicPalette.oxblood, "bolt.fill", Color.Red, Modifier.rotate(12f))
            MiniCard(56.dp, MagicPalette.arcaneBlue, "shield.fill")
        }
        Pill("Done Attacking", PillStyle.DOCK)
    }
}

@Composable
private fun Reading() {
    Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(contentAlignment = Alignment.BottomCenter) {
            MiniCard(84.dp, MagicPalette.arcaneBlue, "eye.fill")
            Box(Modifier.offset(y = 10.dp).size(30.dp).background(BrandTheme.ember.copy(alpha = 0.28f), CircleShape).border(2.dp, BrandTheme.ember, CircleShape))
        }
        Column(Modifier.background(MagicPalette.iron.copy(alpha = 0.7f), RoundedCornerShape(10.dp))
            .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.3f), RoundedCornerShape(10.dp)).padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("text.book.closed", MagicPalette.antiqueGold, 9.dp)
                Text("GAME LOG", color = MagicPalette.antiqueGold, style = sf(9f, SfWeight.heavy, tracking = 1.6f))
            }
            for (width in listOf(96, 70, 84, 58)) Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(5.dp).background(MagicPalette.antiqueGold.copy(alpha = 0.6f), CircleShape))
                Box(Modifier.size(width.dp, 5.dp).background(MagicPalette.parchment.copy(alpha = 0.3f), CircleShape))
            }
        }
    }
}

@Composable
private fun Resume() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("hourglass", BrandTheme.ember, 20.dp)
            Text("10 min", color = BrandTheme.ink, style = sf(26f, SfWeight.black))
        }
        val shape = RoundedCornerShape(12.dp)
        Column(Modifier.background(BrandTheme.surface, shape).border(1.dp, BrandTheme.border, shape).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(GameResumeText.PROMPT_TITLE, color = BrandTheme.ink, style = sf(13f, SfWeight.heavy))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Pill(GameResumeText.RESUME, PillStyle.EMBER, "play.fill")
                Pill(GameResumeText.ABANDON, PillStyle.QUIET)
            }
        }
    }
}

@Composable
private fun Friends() {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Phone()
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text("TABLE CODE", color = BrandTheme.inkSecondary, style = sf(8f, SfWeight.heavy, tracking = 1.4f))
            Text("K7Q 2MX", color = BrandTheme.ink, style = sf(19f, SfWeight.black, SfDesign.MONOSPACED))
            Box(Modifier.size(76.dp, 2.dp).background(BrandTheme.ember.copy(alpha = 0.7f), CircleShape))
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("globe", BrandTheme.ember, 10.dp)
                Text("Online", color = BrandTheme.ember, style = sf(10f, SfWeight.bold))
            }
        }
        Phone()
    }
}

/** A card silhouette: frame, name bar, art box with an optional symbol, and rules lines. */
@Composable
private fun MiniCard(width: Dp, tint: Color, symbol: String? = null, outline: Color = MagicPalette.antiqueGold.copy(alpha = 0.75f),
                     modifier: Modifier = Modifier) {
    val height = width * 1.395f
    val shape = RoundedCornerShape(width * 0.08f)
    Column(modifier.size(width, height).glow(Color.Black.copy(alpha = 0.45f), 4.dp, width * 0.08f).clip(shape).background(rgb(0.09, 0.09, 0.09))
        .border(maxOf(1.dp, width * 0.03f), outline, shape).padding(width * 0.09f), verticalArrangement = Arrangement.spacedBy(width * 0.05f)) {
        Box(Modifier.size(width * 0.55f, maxOf(1.5.dp, width * 0.06f)).background(MagicPalette.parchment.copy(alpha = 0.55f), CircleShape))
        Box(Modifier.fillMaxWidth().height(height * 0.42f).background(Brush.linearGradient(listOf(tint, tint.copy(alpha = 0.45f))), RoundedCornerShape(width * 0.04f)),
            contentAlignment = Alignment.Center) {
            symbol?.let { SfImage(it, Color.White.copy(alpha = 0.9f), width * 0.3f) }
        }
        repeat(3) { line ->
            Box(Modifier.size(width * (if (line == 2) 0.5f else 0.8f), maxOf(1.dp, width * 0.04f)).background(MagicPalette.parchment.copy(alpha = 0.28f), CircleShape))
        }
    }
}

private enum class PillStyle { EMBER, DOCK, QUIET }

/** A button face as a label: ember (menu call to action), dock (the board's orange Pass Priority capsule) or quiet. */
@Composable
private fun Pill(text: String, style: PillStyle, systemImage: String? = null) {
    val dock = style == PillStyle.DOCK
    val fill = when (style) {
        PillStyle.EMBER -> BrandTheme.emberGradient
        PillStyle.DOCK -> Brush.linearGradient(listOf(rgb(0.78, 0.31, 0.065), rgb(0.64, 0.20, 0.05)))
        PillStyle.QUIET -> Brush.linearGradient(listOf(MagicPalette.iron.copy(alpha = 0.88f), MagicPalette.leather.copy(alpha = 0.76f)))
    }
    val stroke = when (style) {
        PillStyle.EMBER -> Color.White.copy(alpha = 0.22f)
        PillStyle.DOCK -> rgb(1.0, 0.79, 0.39)
        PillStyle.QUIET -> MagicPalette.parchment.copy(alpha = 0.25f)
    }
    val ink = when (style) { PillStyle.EMBER -> BrandTheme.emberInk; PillStyle.DOCK -> Color.White; PillStyle.QUIET -> MagicPalette.parchment }
    Row(Modifier.height(if (dock) 36.dp else 28.dp).background(fill, CircleShape).border(if (dock) 1.5.dp else 1.dp, stroke, CircleShape)
        .padding(horizontal = if (dock) 22.dp else 12.dp), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        systemImage?.let { SfImage(it, ink, 10.dp) }
        Text(text, color = ink, style = if (dock) sf(14f, SfWeight.bold, SfDesign.SERIF) else sf(12f, SfWeight.heavy), maxLines = 1)
    }
}

@Composable
private fun Chip(text: String) {
    Text(text, Modifier.background(BrandTheme.surface, CircleShape).border(1.dp, BrandTheme.border, CircleShape).padding(horizontal = 10.dp, vertical = 5.dp),
        color = BrandTheme.ember, style = sf(10f, SfWeight.heavy, tracking = 1.4f))
}

/** A D20 seen face-on: a hexagon with the center face and its edges (HowToPlayD20Shape on iOS). */
@Composable
private fun D20(size: Dp) {
    Box(Modifier.size(size).glow(BrandTheme.ember.copy(alpha = 0.4f), 10.dp, size / 2), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val radius = min(this.size.width, this.size.height) / 2
            fun point(degrees: Double, scale: Double) = Offset(center.x + (cos(degrees * PI / 180) * scale).toFloat() * radius,
                center.y + (sin(degrees * PI / 180) * scale).toFloat() * radius)
            val outer = listOf(-90.0, -30.0, 30.0, 90.0, 150.0, 210.0).map { point(it, 1.0) }
            val outline = Path().apply { moveTo(outer[0].x, outer[0].y); outer.drop(1).forEach { lineTo(it.x, it.y) }; close() }
            val inner = listOf(-90.0, 30.0, 150.0).map { point(it, 0.55) }
            val facets = Path().apply {
                moveTo(inner[0].x, inner[0].y); lineTo(inner[1].x, inner[1].y); lineTo(inner[2].x, inner[2].y); close()
                // Each inner corner meets its own outer corner and the two beside it.
                for ((corner, outerIndex) in inner.zip(listOf(0, 2, 4))) for (step in -1..1) {
                    val to = outer[(outerIndex + step + 6) % 6]
                    moveTo(corner.x, corner.y); lineTo(to.x, to.y)
                }
            }
            drawPath(outline, BrandTheme.emberGradient)
            drawPath(facets, BrandTheme.emberInk.copy(alpha = 0.45f), style = Stroke(1.5.dp.toPx()))
            drawPath(outline, Color.White.copy(alpha = 0.3f), style = Stroke(1.dp.toPx()))
        }
        Text("20", Modifier.offset(y = size * 0.04f), color = BrandTheme.emberInk, style = sf(size.value * 0.24f, SfWeight.black))
    }
}

/** The portrait board in miniature, labelled region by region. */
@Composable
private fun MiniBoard() {
    val rows = listOf("Opponents" to 26.dp, "Their battlefield" to 28.dp, "Your battlefield" to 28.dp, "Turn bar" to 14.dp, "Your hand" to 30.dp)
    val spacing = 5.dp
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        val board = RoundedCornerShape(14.dp)
        Column(Modifier.width(138.dp).background(Brush.verticalGradient(listOf(rgb(0.055, 0.085, 0.10), rgb(0.10, 0.16, 0.16))), board)
            .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.45f), board).padding(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(spacing)) {
            Row(Modifier.fillMaxWidth().height(rows[0].second).background(MagicPalette.iron.copy(alpha = 0.85f), RoundedCornerShape(6.dp))
                .border(1.dp, rgb(0.62, 0.74, 1.0).copy(alpha = 0.7f), RoundedCornerShape(6.dp)).padding(horizontal = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(14.dp).background(MagicPalette.arcaneBlue, CircleShape))
                Column {
                    Text("AI 1", color = MagicPalette.parchment, style = sf(6f, SfWeight.bold))
                    Text("40", color = MagicPalette.antiqueGold, style = sf(10f, SfWeight.black))
                }
                Spacer(Modifier.weight(1f))
                Box(Modifier.size(16.dp).background(MagicPalette.iron, RoundedCornerShape(4.dp)), contentAlignment = Alignment.Center) {
                    SfImage("person.2.fill", MagicPalette.antiqueGold, 7.dp)
                }
            }
            CardRow(4, MagicPalette.arcaneBlue, rows[1].second)
            CardRow(3, MagicPalette.emerald, rows[2].second)
            Box(Modifier.height(rows[3].second).background(MagicPalette.iron.copy(alpha = 0.9f), CircleShape).padding(horizontal = 6.dp),
                contentAlignment = Alignment.Center) {
                Text("YOUR TURN · Main 1", color = MagicPalette.antiqueGold, style = sf(7f, SfWeight.black))
            }
            Box(Modifier.height(rows[4].second), contentAlignment = Alignment.Center) {
                listOf(MagicPalette.emerald, MagicPalette.arcaneBlue, BrandTheme.ember, MagicPalette.oxblood, MagicPalette.emerald).forEachIndexed { card, tint ->
                    MiniCard(20.dp, tint, modifier = Modifier.offset(x = 13.dp * (card - 2), y = 3.dp)
                        .graphicsLayer { rotationZ = (card - 2) * 9f; transformOrigin = TransformOrigin(0.5f, 1f) })
                }
            }
        }
        Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(spacing)) {
            for ((label, height) in rows) Row(Modifier.height(height), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(10.dp, 2.dp).background(BrandTheme.ember, CircleShape))
                Text(label, color = BrandTheme.ink, style = sf(10f, SfWeight.bold))
            }
        }
    }
}

@Composable
private fun CardRow(count: Int, tint: Color, height: Dp) {
    Row(Modifier.height(height), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(count) { MiniCard(19.dp, tint, outline = MagicPalette.antiqueGold.copy(alpha = 0.5f)) }
    }
}

/** A hand card rising toward the battlefield, the Pay cost tray and a highlighted target. The card drifts unless Reduce Motion is on. */
@Composable
private fun Casting() {
    val reduceMotion = BoardMotionFlags.reduceMotion
    val t = rememberAnimationSeconds(reduceMotion)
    Row(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(96.dp, 40.dp).drawBehind {
                drawRoundRect(MagicPalette.antiqueGold.copy(alpha = 0.6f), cornerRadius = CornerRadius(8.dp.toPx()),
                    style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))))
            }, contentAlignment = Alignment.Center) {
                Text("Battlefield", color = MagicPalette.parchment.copy(alpha = 0.7f), style = sf(9f, SfWeight.bold))
            }
            SfImage("arrow.up", BrandTheme.ember, 16.dp)
            Box(Modifier.size(44.dp, 72.dp), contentAlignment = Alignment.Center) {
                val lift = if (reduceMotion) 0f else (-5 + 5 * cos(t * 2.4)).toFloat()
                MiniCard(44.dp, MagicPalette.emerald, "leaf.fill", modifier = Modifier.offset(y = lift.dp))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            val tray = RoundedCornerShape(9.dp)
            Row(Modifier.background(MagicPalette.iron.copy(alpha = 0.9f), tray).border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.6f), tray)
                .padding(horizontal = 10.dp, vertical = 7.dp), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Pay cost", color = MagicPalette.antiqueGold, style = sf(9f, SfWeight.black))
                Pip("2", Color.Gray.copy(alpha = 0.55f))
                Pip("", rgb(0.24, 0.6, 0.33))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.glow(MagicPalette.emerald.copy(alpha = 0.8f), 6.dp, 3.dp)) { MiniCard(30.dp, MagicPalette.arcaneBlue, outline = MagicPalette.emerald) }
                SfImage("scope", MagicPalette.emerald, 16.dp)
            }
        }
    }
}

@Composable
private fun Pip(text: String, fill: Color) {
    Box(Modifier.size(18.dp).background(fill, CircleShape), contentAlignment = Alignment.Center) {
        Text(text, color = Color.White, style = sf(10f, SfWeight.black))
    }
}

/** A phone outline with a player at its table. */
@Composable
private fun Phone() {
    val shape = RoundedCornerShape(10.dp)
    Box(Modifier.size(46.dp, 84.dp).background(BrandTheme.surface, shape).border(1.5.dp, BrandTheme.ink.copy(alpha = 0.55f), shape), contentAlignment = Alignment.Center) {
        SfImage("person.crop.circle", BrandTheme.ember, 22.dp)
        Box(Modifier.align(Alignment.TopCenter).padding(top = 5.dp).size(14.dp, 3.dp).background(BrandTheme.ink.copy(alpha = 0.4f), CircleShape))
    }
}
