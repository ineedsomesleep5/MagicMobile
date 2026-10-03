package io.magicmobile.android.ui

import android.content.res.Resources
import android.graphics.BitmapFactory
import androidx.annotation.DrawableRes
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shader
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import io.magicmobile.android.R
import kotlin.math.ceil
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/*
 * The Walnut Tavern UI kit (iOS Board/BoardChrome.swift "Walnut Tavern UI kit" and BrandUI.swift's
 * Walnut & Ember controls): brass parts rendered in Blender and leather, parchment and ember fills,
 * staged from the iOS asset catalogue at 3 px per point, so cap insets below are in points (dp).
 * Text stays live Compose text. Android always ships the art, so there are no drawn stand-ins.
 */

/** True while the Walnut Tavern table is the board: controls draw as table objects and pop-ups wear the kit. */
val LocalTavernBoard = compositionLocalOf { false }

object TavernPalette {
    val brass = rgb(0.86, 0.64, 0.30)
    val brassDark = rgb(0.36, 0.22, 0.08)
    val leather = rgb(0.16, 0.08, 0.045)
    val enamel = rgb(0.42, 0.07, 0.05)
    val ember = rgb(1.0, 0.50, 0.34)
    val parchment = rgb(0.95, 0.88, 0.74)
    /** Dark ink for text on parchment. */
    val ink = rgb(0.22, 0.11, 0.04)
    /** The label colour of tavern sections and stack trays. */
    val label = rgb(0.96, 0.80, 0.48)
    /** A brass hairline for parchment rows and inset boxes. */
    val brassLine: Brush get() = Brush.verticalGradient(listOf(rgb(0.92, 0.72, 0.38), rgb(0.50, 0.33, 0.11)))
    /** Engraved gold for titles. */
    val goldText: Brush get() = Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.56), rgb(0.80, 0.56, 0.22)))
}

/** Decoded kit images, unscaled (they live in drawable-nodpi) and shared by every tile and panel. */
object TavernImages {
    private val cache = HashMap<Int, ImageBitmap>()

    fun load(resources: Resources, @DrawableRes id: Int): ImageBitmap = synchronized(cache) {
        cache.getOrPut(id) { decode(resources, id) }
    }

    /** Large art (the table plates) is decoded on demand and not kept here. */
    fun decode(resources: Resources, @DrawableRes id: Int): ImageBitmap =
        BitmapFactory.decodeResource(resources, id, BitmapFactory.Options().apply { inScaled = false }).asImageBitmap()

    /** The pass disc's full turn: frame 0 is the glowing face (scripts/brand/pass_button_flip.py). */
    val passFlips = intArrayOf(
        R.drawable.tavern_pass_flip_00, R.drawable.tavern_pass_flip_01, R.drawable.tavern_pass_flip_02, R.drawable.tavern_pass_flip_03,
        R.drawable.tavern_pass_flip_04, R.drawable.tavern_pass_flip_05, R.drawable.tavern_pass_flip_06, R.drawable.tavern_pass_flip_07,
        R.drawable.tavern_pass_flip_08, R.drawable.tavern_pass_flip_09, R.drawable.tavern_pass_flip_10, R.drawable.tavern_pass_flip_11,
        R.drawable.tavern_pass_flip_12, R.drawable.tavern_pass_flip_13, R.drawable.tavern_pass_flip_14, R.drawable.tavern_pass_flip_15,
        R.drawable.tavern_pass_flip_16, R.drawable.tavern_pass_flip_17, R.drawable.tavern_pass_flip_18, R.drawable.tavern_pass_flip_19,
        R.drawable.tavern_pass_flip_20, R.drawable.tavern_pass_flip_21, R.drawable.tavern_pass_flip_22, R.drawable.tavern_pass_flip_23,
        R.drawable.tavern_pass_flip_24, R.drawable.tavern_pass_flip_25, R.drawable.tavern_pass_flip_26, R.drawable.tavern_pass_flip_27,
        R.drawable.tavern_pass_flip_28, R.drawable.tavern_pass_flip_29, R.drawable.tavern_pass_flip_30, R.drawable.tavern_pass_flip_31,
        R.drawable.tavern_pass_flip_32, R.drawable.tavern_pass_flip_33, R.drawable.tavern_pass_flip_34, R.drawable.tavern_pass_flip_35,
        R.drawable.tavern_pass_flip_36, R.drawable.tavern_pass_flip_37, R.drawable.tavern_pass_flip_38, R.drawable.tavern_pass_flip_39,
        R.drawable.tavern_pass_flip_40, R.drawable.tavern_pass_flip_41, R.drawable.tavern_pass_flip_42, R.drawable.tavern_pass_flip_43,
        R.drawable.tavern_pass_flip_44, R.drawable.tavern_pass_flip_45, R.drawable.tavern_pass_flip_46, R.drawable.tavern_pass_flip_47)

    fun manaGem(symbol: String): Int = when (symbol.uppercase()) {
        "W" -> R.drawable.tavern_mana_w; "U" -> R.drawable.tavern_mana_u; "B" -> R.drawable.tavern_mana_b
        "R" -> R.drawable.tavern_mana_r; "G" -> R.drawable.tavern_mana_g; "C" -> R.drawable.tavern_mana_c
        else -> R.drawable.tavern_mana_generic
    }
}

@Composable
fun tavernImage(@DrawableRes id: Int): ImageBitmap {
    val resources = LocalContext.current.resources
    return remember(id) { TavernImages.load(resources, id) }
}

/** Draws a whole kit image stretched over `size` (SwiftUI `.resizable()`). */
fun DrawScope.drawStretched(image: ImageBitmap, topLeft: Offset = Offset.Zero, size: Size = this.size, alpha: Float = 1f,
                            colorFilter: androidx.compose.ui.graphics.ColorFilter? = null) {
    if (size.width <= 0f || size.height <= 0f) return
    drawImage(image, IntOffset.Zero, IntSize(image.width, image.height), IntOffset(topLeft.x.roundToInt(), topLeft.y.roundToInt()),
        IntSize(size.width.roundToInt().coerceAtLeast(1), size.height.roundToInt().coerceAtLeast(1)), alpha = alpha,
        colorFilter = colorFilter, filterQuality = FilterQuality.High)
}

/**
 * SwiftUI `.resizable(capInsets:resizingMode:)`: corners keep their size (`capsDp`, in points), edges and
 * the middle stretch, or with `tileX` repeat horizontally. Caps shrink together when the space is smaller.
 * `sourceCaps` are the image's insets in pixels (left, top, right, bottom).
 */
fun DrawScope.drawNineSlice(image: ImageBitmap, sourceCaps: IntArray, capsDp: FloatArray, tileX: Boolean = false, alpha: Float = 1f) {
    val w = size.width; val h = size.height
    if (w <= 0f || h <= 0f) return
    var l = capsDp[0] * density; var t = capsDp[1] * density; var r = capsDp[2] * density; var b = capsDp[3] * density
    if (l + r > w) { val k = w / (l + r); l *= k; r *= k }
    if (t + b > h) { val k = h / (t + b); t *= k; b *= k }
    val sx = intArrayOf(0, sourceCaps[0], image.width - sourceCaps[2], image.width)
    val sy = intArrayOf(0, sourceCaps[1], image.height - sourceCaps[3], image.height)
    val dx = floatArrayOf(0f, l, w - r, w)
    val dy = floatArrayOf(0f, t, h - b, h)
    for (row in 0..2) for (col in 0..2) {
        val srcW = sx[col + 1] - sx[col]; val srcH = sy[row + 1] - sy[row]
        val dstX = dx[col]; val dstW = dx[col + 1] - dx[col]
        val dstY = dy[row]; val dstH = dy[row + 1] - dy[row]
        if (srcW <= 0 || srcH <= 0 || dstW <= 0.5f || dstH <= 0.5f) continue
        if (tileX && col == 1) {
            // The middle column repeats at the scale of its row's caps, clipping the last copy.
            val scale = if (row == 1) (t / maxOf(sourceCaps[1], 1)) else (dstH / srcH)
            val stepW = maxOf(srcW * scale, 1f)
            val count = ceil(dstW / stepW).toInt()
            for (i in 0 until count) {
                val x = dstX + i * stepW
                val remaining = minOf(stepW, dstX + dstW - x)
                val srcPart = (srcW * remaining / stepW).roundToInt().coerceIn(1, srcW)
                drawImage(image, IntOffset(sx[col], sy[row]), IntSize(srcPart, srcH), IntOffset(x.roundToInt(), dstY.roundToInt()),
                    IntSize(ceil(remaining).toInt().coerceAtLeast(1), ceil(dstH).toInt().coerceAtLeast(1)), alpha = alpha, filterQuality = FilterQuality.High)
            }
        } else {
            drawImage(image, IntOffset(sx[col], sy[row]), IntSize(srcW, srcH), IntOffset(dstX.roundToInt(), dstY.roundToInt()),
                IntSize(ceil(dstW).toInt().coerceAtLeast(1), ceil(dstH).toInt().coerceAtLeast(1)), alpha = alpha, filterQuality = FilterQuality.High)
        }
    }
}

enum class TavernMaterial(@DrawableRes val resource: Int) {
    LEATHER(R.drawable.tavern_ui_leather), PARCHMENT(R.drawable.tavern_ui_parchment), EMBER(R.drawable.tavern_ui_ember)
}

/** A brush that tiles a @3x kit texture at one point per three pixels (SwiftUI `.resizable(resizingMode: .tile)`). */
private fun tiledBrush(image: ImageBitmap, density: Float): Brush {
    val shader: Shader = ImageShader(image, TileMode.Repeated, TileMode.Repeated)
    shader.setLocalMatrix(android.graphics.Matrix().apply { setScale(density / 3f, density / 3f) })
    return ShaderBrush(shader)
}

/** TavernFill: leather and parchment tile seamlessly, ember glass stretches; clipped to `shape`, with an optional tint on top. */
fun Modifier.tavernFill(material: TavernMaterial, shape: Shape = RectangleShape, overlay: Color = Color.Transparent,
                        overlayBrush: Brush? = null): Modifier = composed {
    val image = tavernImage(material.resource)
    drawWithCache {
        val outline = shape.createOutline(size, layoutDirection, this)
        val path = Path().apply { addOutline(outline) }
        val brush = if (material == TavernMaterial.EMBER) null else tiledBrush(image, density)
        onDrawBehind {
            clipPath(path) {
                if (brush != null) drawRect(brush) else drawStretched(image)
                if (overlay.alpha > 0f) drawRect(overlay)
                overlayBrush?.let { drawRect(it) }
            }
        }
    }
}

private fun Path.addOutline(outline: Outline) {
    when (outline) {
        is Outline.Rectangle -> addRect(outline.rect)
        is Outline.Rounded -> addRoundRect(outline.roundRect)
        is Outline.Generic -> addPath(outline.path)
    }
}

/** TavernBrassFrame: brass trim 9-sliced from tavern-ui-frame (96 pt, 24 pt riveted corners); `scale` shrinks the trim. */
fun Modifier.tavernBrassFrame(scale: Float = 1f): Modifier = composed {
    val image = tavernImage(R.drawable.tavern_ui_frame)
    val cap = 24f * scale
    drawWithContent {
        drawContent()
        drawNineSlice(image, intArrayOf(72, 72, 72, 72), floatArrayOf(cap, cap, cap, cap))
    }
}

/** TavernCapsuleRim: a riveted brass capsule for buttons (44 pt tall; the rim tiles as it widens) or a thin plain one for tags (22 pt). */
fun Modifier.tavernCapsuleRim(thin: Boolean = false): Modifier = composed {
    val image = tavernImage(if (thin) R.drawable.tavern_ui_capsule_thin else R.drawable.tavern_ui_capsule)
    drawWithContent {
        drawContent()
        if (thin) drawNineSlice(image, intArrayOf(33, 30, 33, 30), floatArrayOf(11f, 10f, 11f, 10f))
        else drawNineSlice(image, intArrayOf(66, 63, 66, 63), floatArrayOf(22f, 21f, 22f, 21f), tileX = true)
    }
}

/** TavernPanelChrome on the tavern table: tooled leather in brass trim whose corners follow `cornerRadius` (12 pt is the trim's full size). */
fun Modifier.tavernPanel(cornerRadius: Dp = 12.dp): Modifier {
    val scale = (cornerRadius.value / 12f).coerceIn(0.4f, 1f)
    val shape = RoundedCornerShape((12f * scale).dp)
    return this.tavernFill(TavernMaterial.LEATHER, shape, overlayBrush = Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.3f))))
        .tavernBrassFrame(scale)
}

/** TavernPanelChrome: the classic fill and edge off the tavern table, leather in brass on it. */
fun Modifier.tavernPanelChrome(tavern: Boolean, cornerRadius: Dp = 12.dp, classicFill: Color = MagicPalette.iron.copy(alpha = 0.94f),
                               classicStroke: Color = MagicPalette.antiqueGold.copy(alpha = 0.38f)): Modifier =
    if (tavern) tavernPanel(cornerRadius)
    else this.background(classicFill, RoundedCornerShape(cornerRadius)).border(1.dp, classicStroke, RoundedCornerShape(cornerRadius))

/** TavernTitleBar: the leather title bar of tavern panels, in brass trim. */
fun Modifier.tavernTitleBar(): Modifier = this
    .tavernFill(TavernMaterial.LEATHER, RoundedCornerShape(10.dp), overlay = Color.Black.copy(alpha = 0.22f))
    .tavernBrassFrame(0.5f)
    .defaultMinSize(minHeight = 48.dp)
    .padding(start = 12.dp, end = 2.dp)

/** TavernFieldChrome: a recessed parchment slot for search fields. */
fun Modifier.tavernField(): Modifier = this
    .tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(9.dp),
        overlayBrush = Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.18f), 0.5f to Color.Transparent))
    .border(1.2.dp, TavernPalette.brassLine, RoundedCornerShape(9.dp))
    .defaultMinSize(minHeight = 40.dp)
    .padding(horizontal = 12.dp)

/** The text style of a field in a tavern slot (serif ink). */
val tavernFieldTextStyle: TextStyle get() = sf(15f, SfWeight.medium, SfDesign.SERIF).copy(color = TavernPalette.ink)

/** TavernSheetBackground: dark tooled leather under a brass rule along the top. */
@Composable
fun TavernSheetBackground(modifier: Modifier = Modifier, shape: Shape = RectangleShape) {
    Box(modifier.tavernFill(TavernMaterial.LEATHER, shape, overlayBrush = Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.35f))))
        .drawBehind {
            drawRect(Brush.verticalGradient(listOf(TavernPalette.brass, rgb(0.42, 0.28, 0.09)), 0f, 3.dp.toPx()), size = Size(size.width, 3.dp.toPx()))
        })
}

/** Text with a soft drop shadow, as tavern labels on leather draw. */
fun TextStyle.engraved(alpha: Float = 0.7f, y: Float = 1f): TextStyle = copy(shadow = Shadow(Color.Black.copy(alpha = alpha), Offset(0f, y), 1f))

/** TavernPanelTitle: a panel title engraved in gold capitals (read in normal case by accessibility services). */
@Composable
fun TavernPanelTitle(text: String, modifier: Modifier = Modifier, size: Float = 16f) {
    FitText(text.uppercase(), sf(size, SfWeight.heavy, SfDesign.SERIF, tracking = 1.2f).copy(brush = TavernPalette.goldText).engraved(),
        modifier.semantics { contentDescription = text }, minimumScale = 0.7f)
}

/** TavernSealLabel: the wax-seal close button of tavern panels. */
@Composable
fun TavernSealButton(onClick: () -> Unit, modifier: Modifier = Modifier, contentDescription: String = "Close") {
    Box(modifier.size(44.dp).clickable(remember { MutableInteractionSource() }, null, onClick = onClick)
        .semantics { this.contentDescription = contentDescription; role = Role.Button }, contentAlignment = Alignment.Center) {
        val seal = tavernImage(R.drawable.tavern_ui_seal)
        Box(Modifier.size(32.dp).glow(Color.Black.copy(alpha = 0.5f), 3.dp, 16.dp).drawBehind { drawStretched(seal) })
    }
}

/** TavernCoin: a number struck on a brass coin (a generic mana cost, a count). */
@Composable
fun TavernCoin(value: Int, size: Dp = 24.dp, modifier: Modifier = Modifier) {
    val coin = tavernImage(R.drawable.tavern_ui_coin)
    Box(modifier.requiredSize(size).drawBehind { drawStretched(coin) }, contentAlignment = Alignment.Center) {
        Text("$value", color = rgb(0.25, 0.12, 0.04), maxLines = 1,
            style = sf(size.value * 0.52f, SfWeight.black, SfDesign.SERIF).copy(fontFeatureSettings = "tnum",
                shadow = Shadow(Color.White.copy(alpha = 0.35f), Offset(0f, 1f), 0f)))
    }
}

/** TavernGenericGem: a generic mana cost as the smoky crystal with the number engraved in gold. */
@Composable
fun TavernGenericGem(value: Int, size: Dp = 30.dp, modifier: Modifier = Modifier) {
    val gem = tavernImage(R.drawable.tavern_mana_generic)
    Box(modifier.requiredSize(size).drawBehind { drawStretched(gem) }.semantics { contentDescription = "$value generic mana" },
        contentAlignment = Alignment.Center) {
        Text("$value", maxLines = 1, style = sf(size.value * 0.46f, SfWeight.black, SfDesign.SERIF)
            .copy(brush = Brush.verticalGradient(listOf(rgb(1.0, 0.9, 0.6), rgb(0.86, 0.6, 0.24))), fontFeatureSettings = "tnum").engraved(0.8f))
    }
}

/** TavernTag: a small tag in a thin brass rim; parchment for labels ("PAY COST"), leather for status chips, with an optional coloured jewel. */
@Composable
fun TavernTag(text: String, modifier: Modifier = Modifier, leather: Boolean = false, accent: Color? = null) {
    Row(modifier.tavernCapsuleRim(thin = true).defaultMinSize(minHeight = 22.dp)
        .padding(1.5.dp).tavernFill(if (leather) TavernMaterial.LEATHER else TavernMaterial.PARCHMENT, CircleShape)
        .padding(horizontal = 10.5.dp), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        if (accent != null) {
            Box(Modifier.size(8.dp).glow(accent.copy(alpha = 0.9f), 3.dp, 4.dp)
                .background(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.9f), accent, accent.copy(alpha = 0.6f))), CircleShape))
        }
        FitText(text, sf(10f, SfWeight.heavy, SfDesign.SERIF, tracking = 0.8f),
            color = if (leather) rgb(0.98, 0.82, 0.48) else rgb(0.24, 0.12, 0.05), minimumScale = 0.7f)
    }
}

enum class TavernButtonKind { PRIMARY, SECONDARY, DANGER }

/** The label style of tavern plaque buttons, for content that sets its own text. */
val LocalTavernButtonTextStyle = compositionLocalOf { sf(14f, SfWeight.heavy, SfDesign.SERIF) }

/** A title in the current tavern button's type. */
@Composable
fun TavernButtonText(text: String, modifier: Modifier = Modifier, maxLines: Int = 2) {
    FitText(text, LocalTavernButtonTextStyle.current, modifier, color = LocalContentColor.current, maxLines = maxLines, minimumScale = 0.75f,
        textAlign = TextAlign.Center)
}

/**
 * TavernButtonStyle: plaque buttons from the kit, primary ember glass, secondary dark leather, danger oxblood
 * leather, each in a riveted brass rim like the pass button.
 */
@Composable
fun TavernButton(onClick: () -> Unit, modifier: Modifier = Modifier, kind: TavernButtonKind = TavernButtonKind.PRIMARY, compact: Boolean = false,
                 fontSize: Float? = null, fullWidth: Boolean = false, enabled: Boolean = true, pressSound: GameSound? = null,
                 content: @Composable RowScope.() -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    LaunchedEffect(pressed) { if (pressed && pressSound != null) GameAudio.play(pressSound) }
    val scale by animateFloatAsState(if (pressed) 0.96f else 1f, if (BoardMotionFlags.reduceMotion) tween(0) else tween(120), label = "tavernPress")
    val style = sf(fontSize ?: if (compact) 12f else 14f, SfWeight.heavy, SfDesign.SERIF).engraved(0.75f)
    val ink = if (kind == TavernButtonKind.SECONDARY) TavernPalette.parchment else rgb(1.0, 0.91, 0.66)
    Row(modifier.graphicsLayer { scaleX = scale; scaleY = scale }
        .glow(Color.Black.copy(alpha = 0.45f), 4.dp, 22.dp)
        .then(if (fullWidth) Modifier.fillMaxWidth() else Modifier)
        .defaultMinSize(minHeight = 44.dp)
        .colorAdjust(if (enabled) 1f else 0.15f, if (!enabled) -0.12f else if (pressed) 0.08f else 0f)
        .drawBehindFill(kind)
        .tavernCapsuleRim()
        .clip(CircleShape)
        .clickable(interaction, null, enabled, role = Role.Button, onClick = onClick)
        .padding(horizontal = if (compact) 16.dp else 22.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        CompositionLocalProvider(LocalContentColor provides ink, LocalTavernButtonTextStyle provides style) { content() }
    }
}

/** The plaque's face, inset 3 pt inside the rim. */
private fun Modifier.drawBehindFill(kind: TavernButtonKind): Modifier =
    tavernFaceInset(if (kind == TavernButtonKind.PRIMARY) TavernMaterial.EMBER else TavernMaterial.LEATHER,
        if (kind == TavernButtonKind.DANGER) MagicPalette.oxblood.copy(alpha = 0.7f) else Color.Transparent)

private fun Modifier.tavernFaceInset(material: TavernMaterial, overlay: Color): Modifier = composed {
    val image = tavernImage(material.resource)
    drawWithCache {
        val inset = 3.dp.toPx()
        val faceSize = Size((size.width - inset * 2).coerceAtLeast(0f), (size.height - inset * 2).coerceAtLeast(0f))
        val path = Path().apply {
            addRoundRect(androidx.compose.ui.geometry.RoundRect(inset, inset, inset + faceSize.width, inset + faceSize.height,
                androidx.compose.ui.geometry.CornerRadius(faceSize.height / 2)))
        }
        val brush = if (material == TavernMaterial.EMBER) null else tiledBrush(image, density)
        onDrawBehind {
            clipPath(path) {
                if (brush != null) drawRect(brush) else drawStretched(image, Offset(inset, inset), faceSize)
                if (overlay.alpha > 0f) drawRect(overlay)
            }
        }
    }
}

/** A text button as a tavern plaque. */
@Composable
fun TavernPlaqueButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, kind: TavernButtonKind = TavernButtonKind.PRIMARY,
                       compact: Boolean = true, enabled: Boolean = true, systemImage: String? = null, fullWidth: Boolean = false) {
    TavernButton(onClick, modifier.semantics { contentDescription = title }, kind, compact, enabled = enabled, fullWidth = fullWidth) {
        systemImage?.let { SfImage(it, LocalContentColor.current, if (compact) 12.dp else 14.dp) }
        TavernButtonText(title)
    }
}

/** TavernRibbon: a leather ribbon in brass trim with pennant end caps, for the banners across the board (cost, targets, combat). */
@Composable
fun TavernRibbon(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    val left = tavernImage(R.drawable.tavern_ui_cap_left)
    val right = tavernImage(R.drawable.tavern_ui_cap_right)
    // Room for the end caps inside the banner's slot.
    Row(modifier.padding(horizontal = 12.dp)
        .glow(Color.Black.copy(alpha = 0.5f), 6.dp, 6.dp)
        .drawWithContent {
            drawContent()
            val cap = 36.dp.toPx()
            val y = (size.height - cap) / 2
            // Each 36 pt cap overhangs its end by 22 pt (SwiftUI overlay alignment plus offset).
            drawStretched(left, Offset(-22.dp.toPx(), y), Size(cap, cap))
            drawStretched(right, Offset(size.width - cap + 22.dp.toPx(), y), Size(cap, cap))
        }
        .tavernFill(TavernMaterial.LEATHER, RoundedCornerShape(6.dp))
        .tavernBrassFrame(0.5f)
        .fillMaxWidth().defaultMinSize(minHeight = 46.dp)
        .padding(horizontal = 16.dp, vertical = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically, content = content)
}

/** TavernNamePlate: an engraved brass nameplate with a rivet at each end, like the label on a ship's porthole. */
@Composable
fun TavernNamePlate(text: String, modifier: Modifier = Modifier) {
    @Composable
    fun rivet() {
        Box(Modifier.size(5.dp).background(Brush.radialGradient(listOf(rgb(1.0, 0.9, 0.62), rgb(0.45, 0.29, 0.09))), CircleShape))
    }
    val shape = RoundedCornerShape(4.dp)
    Row(modifier.glow(Color.Black.copy(alpha = 0.55f), 2.dp, 4.dp)
        .background(Brush.verticalGradient(listOf(rgb(0.98, 0.84, 0.52), rgb(0.78, 0.55, 0.22), rgb(0.58, 0.38, 0.13))), shape)
        .border(1.dp, rgb(0.36, 0.22, 0.07), shape)
        .defaultMinSize(minHeight = 16.dp).padding(horizontal = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        rivet()
        FitText(text.uppercase(), sf(8.5f, SfWeight.heavy, SfDesign.SERIF, tracking = 0.4f)
            .copy(shadow = Shadow(Color.White.copy(alpha = 0.35f), Offset(0f, 1f), 0f)), Modifier.weight(1f, fill = false),
            color = TavernPalette.ink, minimumScale = 0.7f)
        rivet()
    }
}

/** TavernStackTray: the stack on the tavern table, a leather tray with the top spell and how many wait; a tap opens it. */
@Composable
fun TavernStackTray(count: Int, topName: String?, open: () -> Unit, modifier: Modifier = Modifier, width: Dp = 124.dp,
                    /** The top of the stack, shown as a small framed picture with the count on a coin. */
                    thumbnail: (@Composable () -> Unit)? = null) {
    Row(modifier.width(width).height(42.dp).glow(Color.Black.copy(alpha = 0.45f), 4.dp, 7.dp).tavernPanel(7.dp)
        .clickable(remember { MutableInteractionSource() }, null, onClick = open)
        .semantics {
            contentDescription = "Inspect stack. " + (topName?.let { "$count on the stack, top: $it" } ?: "$count on the stack")
            role = Role.Button
        }
        .padding(start = 6.dp, end = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (thumbnail != null) {
            Box(Modifier.size(30.dp, 32.dp)) {
                Box(Modifier.fillMaxSize().clip(RoundedCornerShape(4.dp)).border(1.dp, BrandTheme.brassGradient, RoundedCornerShape(4.dp))) { thumbnail() }
                TavernCoin(count, 16.dp, Modifier.align(Alignment.BottomEnd).offset(x = 5.dp, y = 4.dp))
            }
        } else {
            TavernCoin(count, 26.dp)
        }
        Column(Modifier.weight(1f)) {
            Text("STACK", color = TavernPalette.label, style = sf(9f, SfWeight.heavy, SfDesign.SERIF, tracking = 1f), maxLines = 1)
            FitText(topName ?: "", sf(13f, SfWeight.semibold, SfDesign.SERIF), color = TavernPalette.parchment, minimumScale = 0.7f)
        }
        SfImage("chevron.up", TavernPalette.label, 10.dp)
    }
}

// --- Menus and dialogs -------------------------------------------------------------------------

/** How a tavern menu row hands its action to the menu: close first, then act. */
val LocalTavernMenuSelect = compositionLocalOf<(() -> Unit) -> Unit> { { it() } }

/** Which side of its button a tavern pop-over opens on (SwiftUI's arrow edge: bottom opens above, top below). */
enum class TavernMenuEdge { ABOVE, BELOW }

private class TavernMenuPosition(val edge: TavernMenuEdge, val gapPx: Int, val marginPx: Int) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val x = (anchorBounds.center.x - popupContentSize.width / 2).coerceIn(marginPx, maxOf(marginPx, windowSize.width - popupContentSize.width - marginPx))
        val above = anchorBounds.top - gapPx - popupContentSize.height
        val below = anchorBounds.bottom + gapPx
        val fitsAbove = above >= marginPx
        val fitsBelow = below + popupContentSize.height <= windowSize.height - marginPx
        val y = when (edge) {
            TavernMenuEdge.ABOVE -> if (fitsAbove || !fitsBelow) above else below
            TavernMenuEdge.BELOW -> if (fitsBelow || !fitsAbove) below else above
        }
        return IntOffset(x, y.coerceIn(marginPx, maxOf(marginPx, windowSize.height - popupContentSize.height - marginPx)))
    }
}

/**
 * TavernMenu: a menu in the tavern's style instead of the system's, a leather pop-over of brass-edged
 * parchment rows anchored to its button. A chosen row closes the pop-over before its action runs.
 */
@Composable
fun TavernMenu(modifier: Modifier = Modifier, edge: TavernMenuEdge = TavernMenuEdge.ABOVE, enabled: Boolean = true,
               scrollHeight: Dp? = null, width: Dp = 270.dp, contentDescription: String? = null,
               label: @Composable (pressed: Boolean) -> Unit, items: @Composable ColumnScope.() -> Unit) {
    var open by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val density = androidx.compose.ui.platform.LocalDensity.current
    Box(modifier.clickable(interaction, null, enabled, role = Role.Button) { open = true; GameAudio.play(GameSound.UI_OPEN) }
        .then(if (contentDescription != null) Modifier.semantics { this.contentDescription = contentDescription } else Modifier),
        contentAlignment = Alignment.Center) {
        label(pressed)
        if (open) {
            Popup(popupPositionProvider = remember(edge) { TavernMenuPosition(edge, with(density) { 6.dp.roundToPx() }, with(density) { 8.dp.roundToPx() }) },
                onDismissRequest = { open = false }, properties = PopupProperties(focusable = true)) {
                val select: (() -> Unit) -> Unit = { action ->
                    open = false
                    GameAudio.play(GameSound.UI_CLOSE)
                    scope.launch { delay(350); action() }
                }
                CompositionLocalProvider(LocalTavernBoard provides true, LocalTavernMenuSelect provides select) {
                    Column(Modifier.width(width).glow(Color.Black.copy(alpha = 0.55f), 14.dp, 12.dp).tavernPanel(12.dp)
                        .then(if (scrollHeight != null) Modifier.heightIn(max = scrollHeight).verticalScroll(rememberScrollState()) else Modifier)
                        .padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp), content = items)
                }
            }
        }
    }
}

/** TavernMenuItem: one row of a tavern menu, a parchment strip (oxblood when destructive). */
@Composable
fun TavernMenuItem(title: String, action: () -> Unit, systemImage: String? = null, destructive: Boolean = false, enabled: Boolean = true) {
    val select = LocalTavernMenuSelect.current
    TavernRowButton({ select(action) }, isPrimary = true, isDanger = destructive, enabled = enabled,
        modifier = Modifier.semantics { contentDescription = title }) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            systemImage?.let { SfImage(it, LocalContentColor.current, 13.dp) }
            Text(title, Modifier.weight(1f), color = LocalContentColor.current, style = sf(14f, SfWeight.semibold, SfDesign.SERIF))
        }
    }
}

/** A heading inside a tavern menu. */
@Composable
fun TavernMenuHeading(title: String) {
    Text(title.uppercase(), Modifier.padding(top = 4.dp), style = sf(10f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.6f).copy(brush = TavernPalette.goldText))
}

/** TavernMenuDivider: a thin brass rule between groups of tavern menu rows. */
@Composable
fun TavernMenuDivider() {
    Box(Modifier.fillMaxWidth().padding(vertical = 2.dp).height(1.dp).alpha(0.7f).background(TavernPalette.brassLine))
}

/**
 * PanelActionButtonStyle on the tavern table: a primary choice is parchment in brass trim with dark ink,
 * a plain one dark leather with a brass hairline, a dangerous one oxblood leather.
 */
@Composable
fun TavernRowButton(onClick: () -> Unit, modifier: Modifier = Modifier, isPrimary: Boolean = false, isDanger: Boolean = false, compact: Boolean = false,
                    enabled: Boolean = true, content: @Composable () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shape = RoundedCornerShape(10.dp)
    val parchment = isPrimary && !isDanger
    val base = modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
        .graphicsLayer { val s = if (pressed) 0.98f else 1f; scaleX = s; scaleY = s }
        .glow(Color.Black.copy(alpha = 0.35f), 2.dp, 10.dp)
        .colorAdjust(if (enabled) 1f else 0.35f, if (pressed) -0.06f else 0f)
        .alpha(if (enabled) 1f else 0.6f)
    val face = when {
        isDanger -> base.tavernFill(TavernMaterial.LEATHER, shape, overlay = MagicPalette.oxblood.copy(alpha = 0.7f)).border(1.2.dp, TavernPalette.brassLine, shape)
        parchment -> base.tavernFill(TavernMaterial.PARCHMENT, shape).tavernBrassFrame(0.42f)
        else -> base.tavernFill(TavernMaterial.LEATHER, shape, overlay = Color.White.copy(alpha = 0.06f)).border(1.2.dp, TavernPalette.brassLine, shape)
    }
    Box(face.clip(shape).clickable(interaction, null, enabled, role = Role.Button, onClick = onClick)
        .padding(horizontal = if (compact) 9.dp else 11.dp, vertical = if (compact) 4.dp else 5.dp), contentAlignment = Alignment.CenterStart) {
        CompositionLocalProvider(LocalContentColor provides if (parchment) TavernPalette.ink else TavernPalette.parchment) { content() }
    }
}

/** One choice in a tavern confirmation. */
data class TavernDialogAction(val title: String, val destructive: Boolean = false, val action: () -> Unit)

/** tavernConfirmation: the tavern's leather dialog in place of the system's action sheet. */
@Composable
fun TavernConfirmationDialog(title: String, message: String?, actions: List<TavernDialogAction>, cancelTitle: String = "Cancel", dismiss: () -> Unit) {
    Dialog(dismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))
            .clickable(remember { MutableInteractionSource() }, null, onClick = dismiss), contentAlignment = Alignment.Center) {
            Column(Modifier.padding(horizontal = 24.dp).widthIn(max = 330.dp).glow(Color.Black.copy(alpha = 0.6f), 18.dp, 16.dp)
                .tavernPanel(16.dp).clickable(remember { MutableInteractionSource() }, null) {}.padding(22.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(title.uppercase(), style = sf(17f, SfWeight.heavy, SfDesign.SERIF, tracking = 1f).copy(brush = TavernPalette.goldText).engraved(),
                    textAlign = TextAlign.Center)
                message?.let { Text(it, color = TavernPalette.parchment.copy(alpha = 0.9f), style = sf(14f, SfWeight.regular, SfDesign.SERIF), textAlign = TextAlign.Center) }
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (choice in actions) {
                        TavernPlaqueButton(choice.title, { dismiss(); choice.action() }, kind = if (choice.destructive) TavernButtonKind.DANGER else TavernButtonKind.PRIMARY,
                            compact = false, fullWidth = true)
                    }
                    TavernPlaqueButton(cancelTitle, dismiss, kind = TavernButtonKind.SECONDARY, compact = false, fullWidth = true)
                }
            }
        }
    }
}

// --- Walnut & Ember controls (BrandUI.swift) ------------------------------------------------------

private val brassKnob: Brush get() = Brush.radialGradient(listOf(rgb(1.0, 0.9, 0.62), rgb(0.70, 0.48, 0.17), rgb(0.40, 0.25, 0.08)))

/** TavernSwitchFace: dark leather when off, glowing ember glass with the brass knob to the right when on. */
@Composable
fun TavernSwitchFace(isOn: Boolean, modifier: Modifier = Modifier) {
    val knob by animateFloatAsState(if (isOn) 1f else 0f, if (BoardMotionFlags.reduceMotion) tween(0) else spring(0.75f, 630f), label = "tavernSwitch")
    Box(modifier.requiredSize(51.dp, 31.dp)
        .glow(if (isOn) BrandTheme.ember.copy(alpha = 0.55f) else Color.Transparent, 5.dp, 16.dp)
        .background(if (isOn) Brush.verticalGradient(listOf(rgb(1.0, 0.55, 0.3), rgb(0.72, 0.22, 0.08))) else Brush.verticalGradient(List(2) { rgb(0.16, 0.10, 0.06) }), CircleShape)
        .border(1.5.dp, BrandTheme.brassGradient, CircleShape)) {
        Box(Modifier.padding(3.dp).offset(x = (20 * knob).dp).size(25.dp).glow(Color.Black.copy(alpha = 0.5f), 2.dp, 13.dp).background(brassKnob, CircleShape))
    }
}

/** TavernToggle: a title (and an optional faded subtitle) with the brass-rimmed switch. */
@Composable
fun TavernToggle(title: String, isOn: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, subtitle: String? = null,
                 enabled: Boolean = true, color: Color = BrandTheme.ink) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.5f)
        .clickable(remember { MutableInteractionSource() }, null, enabled) { GameAudio.play(GameSound.UI_TOGGLE); onChange(!isOn) }
        .semantics { contentDescription = title; role = Role.Switch; stateDescription = if (isOn) "On" else "Off" },
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = color, style = sf(16f, SfWeight.semibold, SfDesign.SERIF))
            subtitle?.let { Text(it, Modifier.alpha(0.65f), color = color, style = sf(12f, SfWeight.regular, SfDesign.SERIF), maxLines = 2) }
        }
        TavernSwitchFace(isOn)
    }
}

/** TavernSlider: an ember-filled groove in a brass rim with a brass knob. */
@Composable
fun TavernSlider(value: Float, onChange: (Float) -> Unit, modifier: Modifier = Modifier, range: ClosedFloatingPointRange<Float> = 0f..1f, label: String = "") {
    val fraction = ((value - range.start) / (range.endInclusive - range.start)).coerceIn(0f, 1f)
    BoxWithConstraints(modifier.fillMaxWidth().height(34.dp).semantics { contentDescription = label; stateDescription = "${(fraction * 100).roundToInt()} percent" }) {
        val knob = 22.dp
        val knobPx = with(androidx.compose.ui.platform.LocalDensity.current) { knob.toPx() }
        val travelPx = maxOf(constraints.maxWidth - knobPx, 1f)
        fun set(x: Float) {
            val f = ((x - knobPx / 2) / travelPx).coerceIn(0f, 1f)
            onChange(range.start + f * (range.endInclusive - range.start))
        }
        Box(Modifier.fillMaxSize().pointerInput(travelPx) { detectTapGestures { set(it.x) } }
            .pointerInput(travelPx) { detectHorizontalDragGestures { change, _ -> set(change.position.x) } }, contentAlignment = Alignment.CenterStart) {
            Box(Modifier.fillMaxWidth().height(8.dp).background(rgb(0.12, 0.07, 0.04), CircleShape).border(1.dp, BrandTheme.brassGradient, CircleShape))
            val travelDp = with(androidx.compose.ui.platform.LocalDensity.current) { travelPx.toDp() }
            Box(Modifier.padding(start = 1.dp).width(knob / 2 + travelDp * fraction).height(6.dp)
                .background(Brush.verticalGradient(listOf(rgb(1.0, 0.62, 0.32), rgb(0.74, 0.26, 0.1))), CircleShape))
            Box(Modifier.offset(x = travelDp * fraction).size(knob).glow(Color.Black.copy(alpha = 0.5f), 2.dp, 11.dp).background(brassKnob, CircleShape))
        }
    }
}

/** TavernStepper: a title with two brass rings, minus and plus. */
@Composable
fun TavernStepper(title: String, value: Int, range: IntRange, onChange: (Int) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                  color: Color = BrandTheme.ink) {
    @Composable
    fun ring(symbol: String, canStep: Boolean, step: Int) {
        Box(Modifier.size(32.dp).alpha(if (canStep) 1f else 0.4f).glow(Color.Black.copy(alpha = 0.45f), 2.dp, 16.dp)
            .tavernFill(TavernMaterial.LEATHER, CircleShape).border(2.5.dp, BrandTheme.brassGradient, CircleShape)
            .clickable(remember { MutableInteractionSource() }, null, enabled && canStep, role = Role.Button) { GameAudio.play(GameSound.UI_TICK); onChange(value + step) }
            .semantics { contentDescription = (if (step > 0) "Increase " else "Decrease ") + title }, contentAlignment = Alignment.Center) {
            SfImage(symbol, BrandTheme.brass, 13.dp)
        }
    }
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.5f).semantics { stateDescription = "$value" },
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), color = color, style = sf(16f, SfWeight.semibold, SfDesign.SERIF))
        Row(horizontalArrangement = Arrangement.spacedBy(15.dp)) {
            ring("minus", value > range.first, -1)
            ring("plus", value < range.last, 1)
        }
    }
}

/** A section of TavernPicker choices. */
data class TavernPickerSection<T>(val title: String?, val options: List<Pair<String, T>>)

/** TavernPicker: a recessed parchment slot (title in brass, the current choice in ink) that opens the tavern pop-over. */
@Composable
fun <T> TavernPicker(title: String, selection: T, sections: List<TavernPickerSection<T>>, onSelect: (T) -> Unit, modifier: Modifier = Modifier,
                     showsTitle: Boolean = true, enabled: Boolean = true) {
    val current = sections.flatMap { it.options }.firstOrNull { it.second == selection }?.first ?: "Choose"
    val count = sections.sumOf { it.options.size + if (it.title == null) 0 else 1 }
    TavernMenu(modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.5f), edge = TavernMenuEdge.BELOW, enabled = enabled, scrollHeight = if (count > 7) 420.dp else null,
        contentDescription = "$title, $current", label = { pressed ->
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).graphicsLayer { val s = if (pressed) 0.98f else 1f; scaleX = s; scaleY = s }
                .tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(10.dp),
                    overlayBrush = Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.16f), 0.5f to Color.Transparent))
                .border(1.2.dp, TavernPalette.brassLine, RoundedCornerShape(10.dp)).padding(horizontal = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    if (showsTitle) Text(title.uppercase(), color = TavernPickerAccent, style = sf(10f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.4f))
                    FitText(current, sf(16f, SfWeight.semibold, SfDesign.SERIF), color = TavernPalette.ink, minimumScale = 0.75f)
                }
                SfImage("chevron.up.chevron.down", TavernPickerAccent, 12.dp)
            }
        }) {
        for (section in sections) {
            section.title?.let { TavernMenuHeading(it) }
            for ((label, value) in section.options) {
                TavernMenuItem(label, { onSelect(value) }, systemImage = if (value == selection) "checkmark" else null)
            }
        }
    }
}

/** A text field as a recessed parchment slot in serif ink (TavernFieldChrome). */
@Composable
fun TavernTextField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, enabled: Boolean = true,
                    singleLine: Boolean = true) {
    androidx.compose.foundation.text.BasicTextField(value, onChange, modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.6f).tavernField(),
        enabled = enabled, singleLine = singleLine, textStyle = tavernFieldTextStyle,
        cursorBrush = androidx.compose.ui.graphics.SolidColor(TavernPalette.ink),
        decorationBox = { inner ->
            Box(Modifier.defaultMinSize(minHeight = 40.dp), contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty()) Text(placeholder, color = TavernPalette.ink.copy(alpha = 0.5f), style = tavernFieldTextStyle)
                inner()
            }
        })
}

/** Deck Studio's accent on parchment (DeckStudioPalette.accent), the picker's brass ink. */
val TavernPickerAccent = rgb(0.60, 0.23, 0.10)

/** A spacer that takes the remaining width of a row. */
@Composable
fun RowScope.TavernFlexibleSpace() = Spacer(Modifier.weight(1f))
