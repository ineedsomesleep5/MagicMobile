package io.magicmobile.android.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.CardArtwork
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlinx.coroutines.delay

/*
 * Port of BrandUI.swift and CommanderPresentation.swift: MagicMobile's brand, shared with
 * the app icon and the download site. Charcoal canvas, ember coral, warm-white ink, heavy
 * sans type and small-corner controls, all drawn in code.
 */

/** False while something covers the menu, so ambient animation stops drawing frames nobody sees. */
val LocalBrandAmbientMotion = compositionLocalOf { true }

/** Seconds since this composable appeared, advancing every frame unless `paused`. */
@Composable
fun rememberAnimationSeconds(paused: Boolean = false): Float {
    var seconds by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(paused) {
        if (paused) return@LaunchedEffect
        val start = withFrameMillis { it } - (seconds * 1000).toLong()
        while (true) withFrameMillis { seconds = (it - start) / 1000f }
    }
    return seconds
}

private fun frac(x: Double) = x - floor(x)

/** The app icon's mark: cream monogram under a coral card with a four-point sparkle. */
@Composable
fun BrandMark(size: Dp = 72.dp, glint: Boolean = true, tile: Boolean = false, modifier: Modifier = Modifier) {
    val still = BoardMotionFlags.reduceMotion || !glint || !LocalBrandAmbientMotion.current
    val t = rememberAnimationSeconds(still)
    Canvas(modifier.requiredSize(size).semantics { }) {
        // A glint every 4.5 s: a quick swell, then settle.
        val phase = if (still) 0.0 else t.toDouble() % 4.5
        val flash = if (!still && phase < 0.6) sin(PI * phase / 0.6) else 0.0
        val full = Rect(Offset.Zero, this.size)
        if (tile) drawRoundRect(BrandTheme.markTile, cornerRadius = CornerRadius(this.size.width * 0.22f))
        val mark = if (tile) Rect(full.left + full.width * 0.04f, full.top + full.height * 0.04f, full.right - full.width * 0.04f, full.bottom - full.height * 0.04f) else full
        drawPath(BrandMarkPaths.cardFrame(mark), BrandTheme.markCoral)
        val center = Offset(mark.left + BrandMarkPaths.sparkleCenter.x * mark.width, mark.top + BrandMarkPaths.sparkleCenter.y * mark.height)
        if (flash > 0.01) {
            val r = mark.width * 0.2f
            drawCircle(Brush.radialGradient(listOf(BrandTheme.emberLight, Color.Transparent), center, r), r, center, alpha = (flash * 0.9).toFloat(), blendMode = BlendMode.Plus)
        }
        val s = (1 + 0.14 * flash).toFloat()
        rotate((12 * flash).toFloat(), center) {
            scale(s, s, center) { drawPath(BrandMarkPaths.sparkle(mark), if (flash > 0.5) BrandTheme.emberLight else BrandTheme.markCoral) }
        }
        drawPath(BrandMarkPaths.monogram(mark), BrandTheme.markCream)
    }
}

/** The sparkle from the mark on its own, for dividers and accents. */
@Composable
fun BrandSparkle(size: Dp = 10.dp, color: Color = BrandTheme.ember) {
    val height = size * (BrandMarkPaths.sparkleHeight / BrandMarkPaths.sparkleWidth)
    Canvas(Modifier.requiredSize(size, height)) {
        val unitW = this.size.width / BrandMarkPaths.sparkleWidth; val unitH = this.size.height / BrandMarkPaths.sparkleHeight
        val left = this.size.width / 2 - BrandMarkPaths.sparkleCenter.x * unitW
        val top = this.size.height / 2 - BrandMarkPaths.sparkleCenter.y * unitH
        drawPath(BrandMarkPaths.sparkle(Rect(left, top, left + unitW, top + unitH)), color)
    }
}

/**
 * Animated menu background: a warm hearth glow below, a faint fan of cards carrying the
 * sparkle, and ember sparks rising through the room. Static under reduced motion.
 */
@Composable
fun BrandBackdrop(modifier: Modifier = Modifier, cards: Boolean = true) {
    val still = BoardMotionFlags.reduceMotion || !LocalBrandAmbientMotion.current
    val t = rememberAnimationSeconds(still).toDouble()
    Canvas(modifier.fillMaxSize()) {
        drawRect(BrandTheme.canvas)
        drawRect(Brush.radialGradient(listOf(BrandTheme.ember.copy(alpha = 0.22f), BrandTheme.rust.copy(alpha = 0.08f), Color.Transparent),
            Offset(size.width * 0.5f, size.height * 1.08f), max(1f, size.height * 0.62f)))
        drawRect(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.06f), Color.Transparent), Offset(size.width * 0.5f, size.height * -0.05f), max(1f, size.height * 0.5f)))
        if (cards) drawFan(t)
        // Ember sparks rising from the hearth.
        for (i in 0 until 42) {
            val seed = i * 12.9898
            val r1 = frac(sin(seed) * 43758.5453); val r2 = frac(sin(seed * 1.7) * 24634.6345); val r3 = frac(sin(seed * 2.3) * 93245.1)
            val life = frac(t * (0.03 + 0.045 * r1) + r2)
            val x = size.width * r3 + sin(t * (0.35 + r1) + seed) * 20 * density
            val y = size.height * (1.04 - life * 1.08)
            val radius = (0.7 + 1.7 * r1 * (1 - life * 0.5)) * density
            val opacity = sin(PI * life) * (0.4 + 0.35 * sin(t * 2.6 + seed)) * (1 - life * 0.4)
            drawCircle((if (i % 5 == 0) BrandTheme.emberLight else BrandTheme.ember).copy(alpha = opacity.toFloat().coerceIn(0f, 1f)), radius.toFloat(),
                Offset(x.toFloat(), y.toFloat()), blendMode = BlendMode.Plus)
        }
        val vignetteStart = min(size.width, size.height) * 0.4f
        val vignetteEnd = max(max(size.width, size.height) * 0.78f, vignetteStart + 1f)
        drawRect(Brush.radialGradient(0f to Color.Transparent, vignetteStart / vignetteEnd to Color.Transparent, 1f to Color.Black.copy(alpha = 0.6f),
            center = Offset(size.width / 2, size.height / 2), radius = vignetteEnd))
    }
}

/** Three card outlines fanned like the logo, breathing slowly. */
private fun DrawScope.drawFan(t: Double) {
    val cardWidth = min(size.width, size.height) * 0.62f
    val cardHeight = cardWidth / 0.716f
    val pivot = Offset(size.width / 2, size.height * 0.42f + cardHeight * 0.5f)
    val breathe = (sin(t * 0.35) * 1.5).toFloat()
    listOf(-16f, 16f, 0f).forEachIndexed { index, angle ->
        val tilt = angle + if (angle == 0f) 0f else if (angle > 0) breathe else -breathe
        translate(pivot.x, pivot.y) {
            rotate(tilt, Offset.Zero) {
                val topLeft = Offset(-cardWidth / 2, -cardHeight)
                drawRoundRect(BrandTheme.canvas.copy(alpha = if (index == 2) 0.85f else 0.6f), topLeft, Size(cardWidth, cardHeight), CornerRadius(cardWidth * 0.08f))
                drawRoundRect(if (index == 2) BrandTheme.ember.copy(alpha = 0.16f) else Color.White.copy(alpha = 0.05f), topLeft, Size(cardWidth, cardHeight),
                    CornerRadius(cardWidth * 0.08f), Stroke(1.2f * density))
            }
        }
    }
    // The sparkle glows faintly on the front card.
    val glow = 0.5 + 0.5 * sin(t * 0.7)
    val sparkleWidth = cardWidth * 0.34f
    val center = Offset(pivot.x, pivot.y - cardHeight * 0.55f)
    val unit = sparkleWidth / BrandMarkPaths.sparkleWidth
    val left = center.x - BrandMarkPaths.sparkleCenter.x * unit; val top = center.y - BrandMarkPaths.sparkleCenter.y * unit
    drawCircle(Brush.radialGradient(listOf(BrandTheme.ember, Color.Transparent), center, max(1f, sparkleWidth)), sparkleWidth, center,
        alpha = (0.12 + 0.08 * glow).toFloat(), blendMode = BlendMode.Plus)
    drawPath(BrandMarkPaths.sparkle(Rect(left, top, left + unit, top + unit)), BrandTheme.ember.copy(alpha = (0.1 + 0.06 * glow).toFloat()))
}

/** Heavy display type, as on the download site (`.brandTitle(size)`). */
fun brandTitleStyle(size: Float): TextStyle = sf(size, SfWeight.black, tracking = -0.6f).copy(color = BrandTheme.ink,
    shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(alpha = 0.6f), Offset(0f, 4f), 10f))

@Composable
fun BrandTitle(text: String, size: Float, modifier: Modifier = Modifier, textAlign: TextAlign? = null) {
    Text(text, modifier, style = brandTitleStyle(size), textAlign = textAlign)
}

/** A thin rule with the brand sparkle at its center and an optional small label. */
@Composable
fun BrandDivider(modifier: Modifier = Modifier, title: String? = null) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f).height(1.dp).background(Brush.horizontalGradient(listOf(BrandTheme.ember.copy(alpha = 0f), BrandTheme.ember.copy(alpha = 0.7f)))))
        BrandSparkle(9.dp)
        if (title != null) {
            Text(title.uppercase(), color = BrandTheme.ember, style = sf(11f, SfWeight.heavy, tracking = 2.4f), maxLines = 1)
            BrandSparkle(9.dp)
        }
        Box(Modifier.weight(1f).height(1.dp).background(Brush.horizontalGradient(listOf(BrandTheme.ember.copy(alpha = 0.7f), BrandTheme.ember.copy(alpha = 0f)))))
    }
}

/** Dark surface with a hairline border and a warm edge of light along the top (BrandPanel). */
fun Modifier.brandPanel(padding: Dp = 18.dp): Modifier {
    val radius = 16.dp
    val shape = RoundedCornerShape(radius)
    return this.glow(Color.Black.copy(alpha = 0.45f), 16.dp, radius)
        .background(Brush.verticalGradient(listOf(BrandTheme.surface.copy(alpha = 0.96f), rgb(0.11, 0.115, 0.13).copy(alpha = 0.97f))), shape)
        .border(1.dp, BrandTheme.border, shape)
        .drawWithContent {
            drawContent()
            val inset = radius.toPx()
            drawRect(Brush.horizontalGradient(listOf(Color.Transparent, BrandTheme.ember.copy(alpha = 0.55f), Color.Transparent), inset, size.width - inset),
                Offset(inset, 0f), Size(max(0f, size.width - inset * 2), 1.dp.toPx()))
        }
        .padding(padding)
}

enum class BrandButtonKind { PRIMARY, SECONDARY }

/**
 * Ember call to action (dark ink on coral) or a dark secondary button with a hairline border.
 * Presses sink a pixel, darken and click, like the site's download buttons.
 */
@Composable
fun BrandButton(onClick: () -> Unit, modifier: Modifier = Modifier, kind: BrandButtonKind = BrandButtonKind.PRIMARY, enabled: Boolean = true,
                content: @Composable RowScope.() -> Unit) {
    val primary = kind == BrandButtonKind.PRIMARY
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    LaunchedEffect(pressed) { if (pressed && primary) GameAudio.play(GameSound.UI_CONFIRM) }
    val reduceMotion = BoardMotionFlags.reduceMotion
    val ambient = LocalBrandAmbientMotion.current
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.985f else 1f, tween(100), label = "brandPress")
    val shape = RoundedCornerShape(12.dp)
    Box(modifier.graphicsLayer { scaleX = scale; scaleY = scale; translationY = if (pressed) density else 0f }
        .glow(if (primary) BrandTheme.ember.copy(alpha = if (enabled) 0.45f else 0f) else Color.Black.copy(alpha = 0.35f), if (primary) 16.dp else 8.dp, 12.dp)
        .clip(shape)
        .background(if (primary) BrandTheme.emberVertical() else Brush.verticalGradient(listOf(BrandTheme.surfaceRaised, BrandTheme.surface)))
        .then(if (primary) Modifier.drawWithContent {
            drawContent()
            drawRect(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.35f), Color.Transparent), 0f, size.height / 2))
        } else Modifier)
        .then(if (primary && enabled && !reduceMotion && ambient) Modifier.shineSweep() else Modifier)
        .border(1.dp, if (primary) Color.White.copy(alpha = 0.22f) else BrandTheme.border, shape)
        .colorAdjust(if (enabled) 1f else 0.1f, if (pressed) -0.08f else 0f)
        .alpha(if (enabled) 1f else 0.5f)
        .clickable(interaction, null, enabled, onClick = onClick)
        .fillMaxWidth().defaultMinSize(minHeight = if (primary) 58.dp else 50.dp)
        .padding(horizontal = 18.dp, vertical = if (primary) 16.dp else 13.dp), contentAlignment = Alignment.Center) {
        CompositionLocalProvider(LocalContentColor provides if (primary) BrandTheme.emberInk else BrandTheme.ink) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically, content = content)
        }
    }
}

/** Text in the brand button face's type. */
@Composable
fun BrandButtonText(text: String, kind: BrandButtonKind = BrandButtonKind.PRIMARY) {
    Text(text, color = LocalContentColor.current, style = sf(if (kind == BrandButtonKind.PRIMARY) 19f else 17f,
        if (kind == BrandButtonKind.PRIMARY) SfWeight.heavy else SfWeight.bold), maxLines = 2, textAlign = TextAlign.Center)
}

/** A glint that crosses the button every few seconds, drawn inside it. */
fun Modifier.shineSweep(): Modifier = this.then(Modifier.composed {
    val t = rememberAnimationSeconds()
    Modifier.drawWithContent {
        drawContent()
        val p = ((t % 3.6f) / 0.9f) * 1.4f - 0.2f
        val band = 0.14f
        if (p > -band && p < 1 + band) {
            val stops = arrayOf((p - band).coerceIn(0f, 1f) to Color.Transparent, p.coerceIn(0f, 1f) to Color.White.copy(alpha = 0.5f),
                (p + band).coerceIn(0f, 1f) to Color.Transparent)
            drawRect(Brush.linearGradient(*stops, start = Offset(0f, size.height * 0.2f), end = Offset(size.width, size.height * 0.8f)), blendMode = BlendMode.Plus)
        }
    }
})

/** Small-corner tile with an icon over a caption (menu utilities). */
@Composable
fun BrandIconButton(title: String, systemImage: String, action: () -> Unit, modifier: Modifier = Modifier) {
    BrandPressable(action, modifier.defaultMinSize(72.dp, 44.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.requiredSize(52.dp, 46.dp).glow(Color.Black.copy(alpha = 0.45f), 6.dp, 11.dp)
                .background(Brush.verticalGradient(listOf(BrandTheme.surfaceRaised, BrandTheme.surface)), RoundedCornerShape(11.dp))
                .border(1.dp, BrandTheme.border, RoundedCornerShape(11.dp)), contentAlignment = Alignment.Center) {
                SfImage(systemImage, BrandTheme.ember, 20.dp)
            }
            Text(title, color = BrandTheme.inkSecondary, style = sf(12f, SfWeight.semibold))
        }
    }
}

/** Press feedback without chrome, for custom-drawn controls (BrandPressStyle). */
@Composable
fun BrandPressable(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && !BoardMotionFlags.reduceMotion) 0.95f else 1f, tween(100), label = "press")
    Box(modifier.graphicsLayer { scaleX = scale; scaleY = scale }.colorAdjust(1f, if (pressed) -0.06f else 0f)
        .clickable(interaction, null, enabled, onClick = onClick), contentAlignment = Alignment.Center) { content() }
}

/** A commander's card art in a rounded frame, or the "choose your commander" placeholder. */
@Composable
fun CommanderDeckPortrait(name: String?, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(12.dp)
    val placeholder: @Composable () -> Unit = {
        Box(Modifier.fillMaxSize().background(BrandTheme.surface), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SfImage("rectangle.stack.fill", BrandTheme.ember, 34.dp)
                Text(name ?: "Choose your commander", Modifier.padding(horizontal = 18.dp), color = BrandTheme.ink, style = SfText.headline(), textAlign = TextAlign.Center)
            }
        }
    }
    Box(modifier.glow(Color.Black.copy(alpha = 0.45f), 18.dp, 12.dp).clip(shape).border(1.4.dp, BrandTheme.border, shape)) {
        if (!name.isNullOrBlank() && !BoardMotionFlags.forcePlaceholders) CardArtwork(name, Modifier.fillMaxSize().background(BrandTheme.surface), placeholder = placeholder)
        else placeholder()
    }
}

/** The selected commander presented like a prize: floating, catching the light, with a warm halo. */
@Composable
fun HeroCommanderCard(name: String?, width: Dp, modifier: Modifier = Modifier) {
    val height = width / 0.716f
    val still = BoardMotionFlags.reduceMotion || !LocalBrandAmbientMotion.current
    val t = rememberAnimationSeconds(still).toDouble()
    Box(modifier.requiredSize(width * 1.3f, height * 1.12f), contentAlignment = Alignment.Center) {
        Canvas(Modifier.requiredSize(width * 1.9f, height * 1.2f).alpha((0.55 + 0.15 * sin(t * 1.1)).toFloat())) {
            drawOval(Brush.radialGradient(listOf(BrandTheme.ember.copy(alpha = 0.42f), Color.Transparent), center, max(1f, width.toPx() * 0.9f)))
        }
        Box(Modifier.offset(y = height * 0.56f).requiredSize(width * (0.8f - 0.05f * sin(t * 0.9).toFloat()), 16.dp)
            .glow(Color.Black.copy(alpha = 0.6f), 8.dp, 8.dp))
        Box(Modifier.requiredSize(width, height)
            .graphicsLayer {
                rotationY = (6 * sin(t * 0.55)).toFloat(); rotationX = (3 * sin(t * 0.4 + 1)).toFloat()
                rotationZ = (-3 + 1.2 * sin(t * 0.6)).toFloat(); translationY = (-5 * sin(t * 0.9)).toFloat() * density
                cameraDistance = 10f * density
            }
            .glow(BrandTheme.ember.copy(alpha = 0.3f), 22.dp, 12.dp)
            .drawWithContent {
                drawContent()
                // Light sliding across the card face as it turns.
                val f = frac(t / 5).toFloat()
                drawRect(Brush.linearGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.2f), Color.Transparent),
                    start = Offset(size.width * (-0.2f + 1.4f * f), 0f), end = Offset(size.width * (0.3f + 1.4f * f), size.height)), blendMode = BlendMode.Plus)
            }) {
            CommanderDeckPortrait(name, Modifier.fillMaxSize())
        }
    }
}

/** "VS" medallion between two decks. */
@Composable
fun VersusMedallion(size: Dp = 54.dp, modifier: Modifier = Modifier) {
    Box(modifier.requiredSize(size).glow(BrandTheme.ember.copy(alpha = 0.6f), 12.dp, size / 2)
        .background(Brush.radialGradient(listOf(BrandTheme.surfaceRaised, BrandTheme.canvas)), CircleShape)
        .border(2.5.dp, BrandTheme.emberVertical(), CircleShape), contentAlignment = Alignment.Center) {
        Text("VS", color = BrandTheme.ink, style = sf(size.value * 0.36f, SfWeight.black, tracking = -0.5f))
    }
}

/** A seat in the versus reveal. */
data class VersusSeat(val id: String, val name: String, val commander: String?)

/**
 * The two sides meet before the first draw: commanders slide in, the medallion slams down
 * with a shockwave, then the table is revealed. Purely visual; touches pass through.
 */
@Composable
fun VersusIntroOverlay(you: VersusSeat, opponents: List<VersusSeat>, finished: () -> Unit) {
    var phase by remember { mutableIntStateOf(0) }
    val view = androidx.compose.ui.platform.LocalView.current
    LaunchedEffect(Unit) {
        phase = 1
        delay(480)
        phase = 2
        view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        delay(1500)
        phase = 3
        delay(480)
        finished()
    }
    val slide by animateFloatAsState(if (phase >= 1) 0f else 1f, spring(0.82f, 195f), label = "versusSlide")
    val medallionScale by animateFloatAsState(if (phase >= 2) 1f else 3.2f, spring(0.55f, 500f), label = "medallion")
    val ringScale by animateFloatAsState(if (phase >= 2) 4.5f else 0.6f, tween(700), label = "ring")
    val ringAlpha by animateFloatAsState(if (phase == 1) 0.9f else 0f, tween(700), label = "ringAlpha")
    val fade by animateFloatAsState(if (phase >= 3) 0f else 1f, tween(450), label = "versusFade")
    BoxWithConstraints(Modifier.fillMaxSize().alpha(fade).semantics { contentDescription = "${you.name} versus ${opponents.joinToString(", ") { it.name }}" },
        contentAlignment = Alignment.Center) {
        val width = maxWidth
        val cardWidth = min(150f, width.value * 0.34f).dp
        val opponentWidth = if (opponents.size > 1) cardWidth * 0.62f else cardWidth
        BrandBackdrop(cards = false)
        @Composable
        fun seat(seat: VersusSeat, w: Dp, tilt: Float) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CommanderDeckPortrait(seat.commander, Modifier.requiredSize(w, w / 0.716f).rotate(tilt).glow(BrandTheme.ember.copy(alpha = 0.35f), 18.dp, 12.dp))
                FitText(seat.name, sf(max(12f, w.value * 0.11f), SfWeight.heavy), Modifier.widthIn(max = w + 20.dp), color = BrandTheme.ink, minimumScale = 0.6f)
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.graphicsLayer { translationX = -slide * width.toPx() }) { seat(you, cardWidth, -5f) }
            Spacer(Modifier.weight(1f).widthIn(min = 12.dp))
            Column(Modifier.graphicsLayer { translationX = slide * width.toPx() }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                opponents.forEach { seat(it, opponentWidth, 5f) }
            }
        }
        Box(Modifier.requiredSize(90.dp).graphicsLayer { scaleX = ringScale; scaleY = ringScale; alpha = ringAlpha }.border(3.dp, BrandTheme.ember, CircleShape))
        VersusMedallion(86.dp, Modifier.graphicsLayer { scaleX = medallionScale; scaleY = medallionScale; alpha = if (phase >= 2) 1f else 0f })
    }
}

/** Launch-time flags the brand views read (reduced motion, forced placeholders). */
object BoardMotionFlags {
    val reduceMotion: Boolean get() = LaunchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] == "large-text" || LaunchEnvironment.reduceMotion
    val forcePlaceholders: Boolean get() = LaunchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] == "true"
}
