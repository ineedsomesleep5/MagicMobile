package io.magicmobile.android.board

import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.PorterDuffXfermode
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.zIndex
import io.magicmobile.android.R
import io.magicmobile.android.game.ArenaAmountRange
import io.magicmobile.android.game.ArenaCanvas
import io.magicmobile.android.game.ArenaCardLook
import io.magicmobile.android.game.ArenaGlowTone
import io.magicmobile.android.game.ArenaPhaseStripRules
import io.magicmobile.android.game.ArenaTableRules
import io.magicmobile.android.game.BoardFXLevel
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.game.BoardZoneReference
import io.magicmobile.android.game.CombatArrowKind
import io.magicmobile.android.game.CombatArrowModel
import io.magicmobile.android.game.CombatArrow
import io.magicmobile.android.game.CombatPlayerIdentity
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameplayAffordances
import io.magicmobile.android.game.ManaPool
import io.magicmobile.android.game.PlayerGameState
import io.magicmobile.android.game.PlayerStatusSummary
import io.magicmobile.android.game.PromptDisplayText
import io.magicmobile.android.game.TavernFrameKind
import io.magicmobile.android.game.TavernPhaseTrack
import io.magicmobile.android.game.XmageCardIcon
import io.magicmobile.android.game.XmageStackObject
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.menus.ArenaButtonFace
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.arenaGlassPanel
import io.magicmobile.android.menus.arenaShadow
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernImages
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.drawStretched
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.tan

/*
 * Port of Board/ArenaBoardViews.swift: the Arena board's table pieces (BoardMode.ARENA). Positions come from ArenaLayout
 * through ArenaCanvas (core); behaviour stays with the views and helpers the Hearth board already uses (BattlefieldRow,
 * CardTile, the prompt pop-up). The full-table browsers (abilities, modes, choices, splits, piles, zones, the stack, the
 * question stage and the result) are in ArenaBrowsers.kt.
 */

/** Tavern frames on battlefield cards (CardFramesPreference, per board mode); off draws the reference game's card. */
val LocalCardFrames = compositionLocalOf { true }

/** A mana payment is open on the Arena board: the permanents that can pay glow orange instead of cyan. */
val LocalArenaPaying = compositionLocalOf { false }
/** The battlefield tile being drawn has a non-mana ability to use now (ArenaBattlefieldCard sets it for its own frame). */
val LocalArenaAbility = compositionLocalOf { false }

/**
 * The table's camera, so lanes and piles lying on it lean the way the rendered table does: the plate's pitch (landscape 22°,
 * portrait 16°), the camera's distance in dp (half the screen's long side over tan 27°) and the screen's centre, toward which
 * everything converges. iOS leans each tile; Android leans each lane and pile as one layer (one camera, the same anchor).
 */
data class ArenaTableLean(val pitch: Float, val distance: Float, val centerX: Float) {
    constructor(canvas: ArenaCanvas) : this(if (canvas.layout.landscape) 22f else 16f,
        max(canvas.screen.width, canvas.screen.height) / 2 / tan(27.0 * PI / 180).toFloat(), canvas.screen.width / 2)
}

val LocalArenaTableLean = compositionLocalOf<ArenaTableLean?> { null }

/** Lays a layer at `rect` (screen dp) on the table: tilted by the table camera's pitch, its axis under the screen's centre. */
fun Modifier.arenaLean(lean: ArenaTableLean?, rect: BoardRect): Modifier = if (lean == null) this else graphicsLayer {
    rotationX = lean.pitch
    transformOrigin = TransformOrigin((lean.centerX - rect.minX) / max(rect.width, 1f), 0.5f)
    cameraDistance = lean.distance * density
}

object ArenaPalette {
    val cream = rgb(1.0, 0.965, 0.88)
    val viewerRim = rgb(0.91, 0.54, 0.23)
    val opponentRim = rgb(0.31, 0.55, 1.0)
    val attackGlow = rgb(1.0, 0.22, 0.12)
    val targetGlow = rgb(0.55, 0.9, 1.0)
    val iconFill = rgb(0.08, 0.045, 0.025)
    /** Gold labels on glass. */
    val gold = rgb(0.98, 0.84, 0.52)
}

/** The web board's colours (playable #7ff0ff, target #c6f8ff, selected #ffe08f, attacking #ff5a2e, blocking #ffd38a). */
val ArenaGlowTone.color: Color get() = when (this) {
    ArenaGlowTone.PLAYABLE -> rgb(0.5, 0.94, 1.0)
    // A permanent with an ability you can use now (Caleb, 2026-10-26: not the same white as a card to cast).
    ArenaGlowTone.ABILITY -> rgb(1.0, 0.88, 0.23)
    ArenaGlowTone.TARGET -> rgb(0.78, 0.97, 1.0)
    ArenaGlowTone.PAYABLE -> rgb(1.0, 0.62, 0.3)
    ArenaGlowTone.SELECTED -> rgb(1.0, 0.88, 0.56)
    ArenaGlowTone.ATTACKING -> rgb(1.0, 0.35, 0.18)
    ArenaGlowTone.BLOCKING -> rgb(1.0, 0.83, 0.54)
    ArenaGlowTone.SOURCE -> rgb(1.0, 0.84, 0.5)
    ArenaGlowTone.SHADOW -> Color.Black
}

/** The outline a glow follows: a tavern frame, the reference's tile (a token's arched), or a printed card. */
sealed class ArenaGlowOutline {
    data class Frame(val kind: TavernFrameKind) : ArenaGlowOutline()
    data class Tile(val arched: Boolean) : ArenaGlowOutline()
    object Card : ArenaGlowOutline()
}

/**
 * The outline glows' light, made once per outline and kept (a live blur on every tile is too slow with dozens of tokens).
 * Built the way the web board's `glowCanvas` is: the outline's white silhouette on a canvas 1.3x the card, drawn 16 px larger
 * (on a 330 px tile) and blurred, then the card's own area (inset 4 px) cut back out.
 */
object ArenaGlowImages {
    /** The canvas reaches this share of the card past each edge (1.3x overall). */
    const val PAD = 0.15f
    private val cache = HashMap<ArenaGlowOutline, ImageBitmap>()

    fun image(outline: ArenaGlowOutline, resources: Resources): ImageBitmap? = synchronized(cache) {
        cache[outline] ?: make(outline, resources)?.also { cache[outline] = it }
    }

    private fun make(outline: ArenaGlowOutline, resources: Resources): ImageBitmap? {
        val shape = when (outline) {
            is ArenaGlowOutline.Frame -> Size(165f, 178f)
            is ArenaGlowOutline.Tile -> Size(165f, 137.5f)
            ArenaGlowOutline.Card -> Size(126f, 176f)
        }
        val unit = shape.width / 330f
        val canvasWidth = (shape.width * (1 + 2 * PAD)).roundToInt(); val canvasHeight = (shape.height * (1 + 2 * PAD)).roundToInt()
        val box = Rect((canvasWidth - shape.width) / 2, (canvasHeight - shape.height) / 2, (canvasWidth + shape.width) / 2, (canvasHeight + shape.height) / 2)
        val frame = (outline as? ArenaGlowOutline.Frame)?.let { TavernImages.load(resources, tavernFrameDrawable(it.kind)).asAndroidBitmap() }
        fun silhouette(rect: Rect): Bitmap {
            val bitmap = Bitmap.createBitmap(canvasWidth, canvasHeight, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            val white = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE }
            val target = android.graphics.RectF(rect.left, rect.top, rect.right, rect.bottom)
            when (outline) {
                is ArenaGlowOutline.Frame -> {
                    if (frame != null) {
                        // The frame's alpha in white, its arched window filled so the glow has the whole tile.
                        val tint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG).apply {
                            colorFilter = PorterDuffColorFilter(android.graphics.Color.WHITE, PorterDuff.Mode.SRC_IN)
                        }
                        canvas.drawBitmap(frame, null, target, tint)
                    }
                    val window = outline.kind.window
                    canvas.drawRect(rect.left + rect.width * window.minX, rect.top + rect.height * window.minY,
                        rect.left + rect.width * (window.minX + window.width), rect.top + rect.height * (window.minY + window.height), white)
                }
                is ArenaGlowOutline.Tile -> canvas.drawPath(arenaTilePath(rect, outline.arched, rect.width * 0.07f).asAndroidPath(), white)
                ArenaGlowOutline.Card -> canvas.drawRoundRect(target, rect.width * 0.055f, rect.width * 0.055f, white)
            }
            return bitmap
        }
        return runCatching {
            val spread = silhouette(Rect(box.left - 8 * unit, box.top - 8 * unit, box.right + 8 * unit, box.bottom + 8 * unit))
            val inner = silhouette(Rect(box.left + 4 * unit, box.top + 4 * unit, box.right - 4 * unit, box.bottom - 4 * unit))
            val sigma = 14 * unit
            val radius = max(1f, (sigma - 0.5f) / 0.57735f)
            val offset = IntArray(2)
            val blurred = spread.extractAlpha(android.graphics.Paint().apply { maskFilter = BlurMaskFilter(radius, BlurMaskFilter.Blur.NORMAL) }, offset)
            val output = Bitmap.createBitmap(canvasWidth, canvasHeight, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(output)
            val light = android.graphics.Paint().apply { color = android.graphics.Color.WHITE }
            // Three passes over each other: 1 - (1 - a)^3, about three times the light where it is thin.
            repeat(3) { canvas.drawBitmap(blurred, offset[0].toFloat(), offset[1].toFloat(), light) }
            canvas.drawBitmap(inner, 0f, 0f, android.graphics.Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT) })
            spread.recycle(); inner.recycle(); blurred.recycle()
            output.asImageBitmap()
        }.getOrNull()
    }
}

/**
 * The Arena board's highlight ("the glow border", memory frame-outline-glow): soft light that follows the card's own outline,
 * never a box. Drawn behind the card and added to the light under it, so only the glow outside its edge shows. `breath`
 * (the shared board clock) makes a playable hand card breathe; it is read at draw time only.
 */
fun Modifier.arenaOutlineGlow(outline: ArenaGlowOutline, tone: ArenaGlowTone, strength: Float = 1f, breath: (() -> Float)? = null,
                              offset: Offset = Offset.Zero): Modifier = composed {
    val resources = LocalContext.current.resources
    val image = remember(outline) { ArenaGlowImages.image(outline, resources) } ?: return@composed this
    val filter = remember(tone) { ColorFilter.tint(tone.color, BlendMode.SrcIn) }
    drawBehind {
        val width = size.width * (1 + 2 * ArenaGlowImages.PAD); val height = size.height * (1 + 2 * ArenaGlowImages.PAD)
        drawImage(image, IntOffset.Zero, IntSize(image.width, image.height),
            IntOffset(((size.width - width) / 2 + offset.x * density).roundToInt(), ((size.height - height) / 2 + offset.y * density).roundToInt()),
            IntSize(width.roundToInt(), height.roundToInt()), alpha = (strength * (breath?.invoke() ?: 1f)).coerceIn(0f, 1f), colorFilter = filter,
            // Light adds to the table under it, as the web board's additive halo does; a shadow darkens.
            blendMode = if (tone == ArenaGlowTone.SHADOW) BlendMode.SrcOver else BlendMode.Plus)
    }
}

/** The reference game's battlefield card outline: a rounded rectangle, or an arched top for a token. */
fun arenaTilePath(rect: Rect, arched: Boolean, corner: Float): Path = Path().apply {
    if (!arched) {
        addRoundRect(androidx.compose.ui.geometry.RoundRect(rect, CornerRadius(max(0f, corner))))
        return@apply
    }
    val shoulder = rect.height * 0.34f
    moveTo(rect.left, rect.bottom)
    lineTo(rect.left, rect.top + shoulder)
    quadraticTo(rect.left, rect.top, rect.center.x, rect.top)
    quadraticTo(rect.right, rect.top, rect.right, rect.top + shoulder)
    lineTo(rect.right, rect.bottom)
    close()
}

fun arenaTileShape(arched: Boolean, cornerFraction: Float = 0.07f) = GenericShape { size, _ ->
    addPath(arenaTilePath(Rect(0f, 0f, size.width, size.height), arched, size.width * cornerFraction))
}

/** The loyalty and defense shield: a flat top with notched corners, straight sides, then a point. */
val ArenaShieldShape = GenericShape { size, _ ->
    val notch = size.width * 0.14f
    moveTo(notch, 0f); lineTo(size.width - notch, 0f); lineTo(size.width, notch); lineTo(size.width, size.height * 0.55f)
    quadraticTo(size.width, size.height - size.height * 0.12f, size.width / 2, size.height)
    quadraticTo(0f, size.height - size.height * 0.12f, 0f, size.height * 0.55f)
    lineTo(0f, notch); close()
}

/** Arena's life plaque: a flat-topped, six-sided badge. */
val ArenaPlaqueShape = GenericShape { size, _ ->
    val inset = size.width * 0.14f
    moveTo(inset, 0f); lineTo(size.width - inset, 0f); lineTo(size.width, size.height / 2)
    lineTo(size.width - inset, size.height); lineTo(inset, size.height); lineTo(0f, size.height / 2); close()
}

/** A card's colour for its frame, the reference's way: its one colour, gold for several, grey for none. */
object ArenaCardColor {
    fun frame(card: ZoneCard): Color = when (ArenaCardLook.colorKey(card)) {
        "M" -> rgb(0.93, 0.74, 0.32); "W" -> rgb(0.93, 0.88, 0.72); "U" -> rgb(0.25, 0.52, 0.95); "B" -> rgb(0.42, 0.30, 0.48)
        "R" -> rgb(0.86, 0.22, 0.14); "G" -> rgb(0.22, 0.66, 0.30); else -> rgb(0.62, 0.62, 0.66)
    }

    /** The plain tile's colour line (a little lighter white). */
    fun edge(card: ZoneCard): Color = if (ArenaCardLook.colorKey(card) == "W") rgb(0.96, 0.92, 0.78) else frame(card)
}

/** The Arena table's plate for the current orientation, decoded once and shared by the backdrop and the front rail (one at a time). */
object ArenaPlates {
    private var id = 0
    private var plate: ImageBitmap? = null

    fun plate(resources: Resources, landscape: Boolean): ImageBitmap = synchronized(this) {
        val wanted = if (landscape) R.drawable.tavern_arena_landscape else R.drawable.tavern_arena_portrait
        plate?.takeIf { id == wanted } ?: TavernImages.decode(resources, wanted).also { plate = it; id = wanted }
    }
}

/** The leaning tavern table: the plate stretches to the screen the way the layout does, so the mat sits under the lanes. */
@Composable
fun ArenaTableBackdrop(landscape: Boolean, modifier: Modifier = Modifier) {
    val resources = LocalContext.current.resources
    val plate = remember(landscape) { ArenaPlates.plate(resources, landscape) }
    Box(modifier.fillMaxSize().clearAndSetSemantics { }) {
        Image(BitmapPainter(plate), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
        // The lamp over the middle of the mat: warm light only, no texture.
        Box(Modifier.fillMaxSize().drawBehind {
            drawRect(Brush.radialGradient(listOf(rgb(1.0, 0.77, 0.47).copy(alpha = 0.13f), Color.Transparent), center,
                max(size.width, size.height) * 0.42f), blendMode = BlendMode.Screen)
        })
    }
}

/** Portrait only: the plate's own front rail drawn again over a resting hand, so the hand tucks behind the table's edge. */
@Composable
fun ArenaFrontRail(top: Float, modifier: Modifier = Modifier) {
    val resources = LocalContext.current.resources
    val plate = remember { ArenaPlates.plate(resources, landscape = false) }
    Box(modifier.fillMaxSize().clearAndSetSemantics { }.drawBehind {
        val y = top.dp.toPx()
        clipRect(top = y) { drawStretched(plate) }
        drawRect(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent), y, y + 8.dp.toPx()),
            Offset(0f, y), Size(size.width, 8.dp.toPx()))
    })
}

/**
 * A player's life medallion as Arena draws it: their picture in a thin gold ring, the life total on a dark plaque edged in
 * gold over the ring's foot. It glows ember on its owner's turn and red (attack) or blue (target) while it can be chosen.
 */
@Composable
fun ArenaHeroMedallion(player: PlayerGameState, diameter: Dp, modifier: Modifier = Modifier, active: Boolean = false, glow: Color? = null,
                       commanderReady: Boolean = false, showsLife: Boolean = true) {
    val portrait = diameter * 0.9f
    val activeGlow by animateFloatAsState(if (active) 1f else 0f, tween(300), label = "medallionActive")
    Box(modifier.requiredSize(diameter).alpha(if (player.isOut) 0.5f else 1f).drawBehind {
        val r = size.minDimension / 2
        if (glow != null) blurredCircle(glow, r * 1.15f, size.minDimension * 0.12f)
        else if (activeGlow > 0f) blurredCircle(TavernPalette.ember.copy(alpha = 0.7f * activeGlow), r * 1.05f, size.minDimension * 0.1f)
        blurredCircle(Color.Black.copy(alpha = 0.6f), r, 4.dp.toPx(), Offset(0f, 3.dp.toPx()))
    }, contentAlignment = Alignment.Center) {
        if (commanderReady) TavernCommanderReadyGlow(portrait)
        Box(Modifier.requiredSize(portrait).clip(CircleShape)) {
            PlayerPortrait(player, portrait)
            Box(Modifier.fillMaxSize().background(Brush.radialGradient(0.55f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.3f))))
        }
        Box(Modifier.requiredSize(diameter * 0.96f).border(maxOf(1.5.dp, diameter * 0.045f),
            Brush.verticalGradient(listOf(rgb(1.0, 0.90, 0.62), ArenaMenuStyle.gold, rgb(0.62, 0.44, 0.18))), CircleShape))
        if (showsLife) {
            Box(Modifier.align(Alignment.BottomCenter).offset(y = diameter * 0.1f).wrapContentSize(unbounded = true)) {
                Box(Modifier.requiredSize(diameter * 0.56f, diameter * 0.34f)
                    .background(Brush.verticalGradient(listOf(rgb(0.16, 0.16, 0.19), rgb(0.05, 0.05, 0.07))), ArenaPlaqueShape)
                    .border(maxOf(1.dp, diameter * 0.02f), ArenaMenuStyle.gold.copy(alpha = 0.85f), ArenaPlaqueShape),
                    contentAlignment = Alignment.Center) {
                    if (player.isOut) Text("Out", color = Color.Gray, style = sf(diameter.value * 0.17f, SfWeight.bold))
                    else FitText("${player.life}", ArenaMenuStyle.title(diameter.value * 0.26f, SfWeight.bold).copy(fontFeatureSettings = "tnum"),
                        color = Color.White, minimumScale = 0.6f)
                }
            }
        }
    }
}

internal fun DrawScope.blurredCircle(color: Color, radius: Float, blur: Float, offset: Offset = Offset.Zero) {
    if (color.alpha <= 0f) return
    drawIntoCanvas { canvas ->
        val paint = Paint()
        paint.asFrameworkPaint().apply {
            this.color = android.graphics.Color.argb((color.alpha * 255).roundToInt(), (color.red * 255).roundToInt(), (color.green * 255).roundToInt(), (color.blue * 255).roundToInt())
            maskFilter = BlurMaskFilter(blur.coerceAtLeast(0.5f), BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawCircle(center + offset, radius, paint)
    }
}

/**
 * The real Magic card back (iOS ArenaCardBackArt), fetched once from Scryfall with the player's artwork consent and kept
 * in the cache directory; until then the tavern's leather back stands in.
 */
object ArenaCardBackArt {
    /** The Magic card back as Scryfall serves it (iOS CardImageURL's hidden-card image). */
    private const val URL_STRING = "https://backs.scryfall.io/large/0/a/0aeebaf5-8c7d-4636-9e82-8c27447861f7.jpg"
    var image by mutableStateOf<ImageBitmap?>(null)
        private set
    private var started = false

    fun load(context: android.content.Context, scope: kotlinx.coroutines.CoroutineScope) {
        if (started) return
        started = true
        val file = java.io.File(context.cacheDir, "magic-card-back.jpg")
        scope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val cached = runCatching { if (file.exists()) android.graphics.BitmapFactory.decodeFile(file.path) else null }.getOrNull()
            if (cached != null) { image = cached.asImageBitmap(); return@launch }
            if (!io.magicmobile.android.Artwork.enabled(context)) { started = false; return@launch }
            val bytes = runCatching {
                io.magicmobile.android.ArtworkTransport.bytes(context, java.net.URL(URL_STRING), 2 * 1024 * 1024, setOf("image/jpeg"))
            }.getOrNull()
            val bitmap = bytes?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size) }
            if (bitmap == null) { started = false; return@launch }
            runCatching { val part = java.io.File(file.path + ".part"); part.writeBytes(bytes); part.renameTo(file) }
            image = bitmap.asImageBitmap()
        }
    }
}

/** A face-down Magic card. */
@Composable
fun ArenaCardBack(modifier: Modifier = Modifier) {
    val context = androidx.compose.ui.platform.LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { ArenaCardBackArt.load(context, scope) }
    val art = ArenaCardBackArt.image
    Box(modifier.clearAndSetSemantics { }.drawBehind {
        val corner = CornerRadius(size.width * 0.06f)
        if (art != null) {
            val clip = androidx.compose.ui.graphics.Path().apply {
                addRoundRect(androidx.compose.ui.geometry.RoundRect(androidx.compose.ui.geometry.Rect(Offset.Zero, size), corner))
            }
            clipPath(clip) {
                drawImage(art, dstSize = androidx.compose.ui.unit.IntSize(size.width.roundToInt(), size.height.roundToInt()),
                    filterQuality = androidx.compose.ui.graphics.FilterQuality.Medium)
            }
            return@drawBehind
        }
        drawRoundRect(Brush.verticalGradient(listOf(rgb(0.16, 0.15, 0.16), rgb(0.07, 0.065, 0.07))), cornerRadius = corner)
        drawRoundRect(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.08f), 0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.28f)), cornerRadius = corner)
        val line = max(1.dp.toPx(), size.width * 0.06f)
        drawRoundRect(Color.Black.copy(alpha = 0.85f), Offset(line / 2, line / 2), Size(size.width - line, size.height - line), corner, style = Stroke(line))
    })
}

/**
 * A pile on the table, the library's look for every zone: slivers whose thickness follows the count under the top card, a
 * contact shadow, leaning with the table, and the count on a lozenge.
 */
@Composable
fun ArenaPileStack(count: Int, size: DpSize, modifier: Modifier = Modifier, lean: (Modifier) -> Modifier = { it }, top: @Composable () -> Unit) {
    val thickness = if (count > 0) max(1.5f, count * size.height.value * 0.0055f) else 0f
    val layers = min(16, (thickness / 1.1f).roundToInt())
    Box(modifier.requiredSize(size)) {
        Box(lean(Modifier.fillMaxSize()).drawBehind {
            val w = this.size.width; val h = this.size.height
            if (count > 0) drawIntoCanvas { canvas ->
                val paint = Paint()
                paint.asFrameworkPaint().apply { color = android.graphics.Color.argb(140, 0, 0, 0); maskFilter = BlurMaskFilter(4.dp.toPx(), BlurMaskFilter.Blur.NORMAL) }
                canvas.drawOval(Rect(w / 2 - w * 0.55f, h / 2 + h * 0.32f - h * 0.25f, w / 2 + w * 0.55f, h / 2 + h * 0.32f + h * 0.25f), paint)
            } else {
                drawRoundRect(TavernPalette.brass.copy(alpha = 0.35f), cornerRadius = CornerRadius(4.dp.toPx()),
                    style = Stroke(1.dp.toPx(), pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))))
            }
            val corner = CornerRadius(w * 0.08f)
            for (index in 0 until layers) {
                val fraction = if (layers > 1) index.toFloat() / (layers - 1) else 1f
                val brightness = (0.62f + 0.26f * fraction + if (index % 2 == 0) 0f else 0.05f).coerceAtMost(1f)
                val color = Color(android.graphics.Color.HSVToColor(floatArrayOf(0.105f * 360, 0.32f, brightness)))
                val dx = -thickness * 0.22f * index / max(layers, 1) * density
                val dy = -thickness * index / max(layers, 1) * density
                drawRoundRect(color, Offset(dx, dy), this.size, corner)
                drawRoundRect(Color.Black.copy(alpha = 0.35f), Offset(dx, dy), this.size, corner, style = Stroke(0.5.dp.toPx()))
            }
        }) {
            if (count > 0) Box(Modifier.fillMaxSize().offset((-thickness * 0.22f).dp, (-thickness).dp)) { top() }
        }
        if (count > 0) ArenaCountBadge(count, Modifier.align(Alignment.BottomEnd).offset(8.dp, (-2).dp))
    }
}

/** A library as a real stack of cards, the back on top. */
@Composable
fun ArenaDeckPile(count: Int, size: DpSize, label: String, modifier: Modifier = Modifier, lean: (Modifier) -> Modifier = { it }) {
    ArenaPileStack(count, size, modifier.semantics { contentDescription = label }, lean) { ArenaCardBack(Modifier.fillMaxSize()) }
}

/** A count on the Arena table: a white number on a dark oval in a thin gold line, as Arena marks counts. */
@Composable
fun ArenaCountBadge(count: Int, modifier: Modifier = Modifier, size: Dp = 17.dp) {
    Box(modifier.wrapContentSize(unbounded = true).defaultMinSize(size + 3.dp, size).glow(Color.Black.copy(alpha = 0.6f), 2.dp, size)
        .background(rgb(0.07, 0.07, 0.08).copy(alpha = 0.94f), CircleShape).border(1.dp, ArenaMenuStyle.gold.copy(alpha = 0.7f), CircleShape)
        .padding(horizontal = maxOf(5.dp, size * 0.18f)).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        Text("$count", color = Color.White, style = sf(maxOf(11f, size.value * 0.5f), SfWeight.bold).copy(fontFeatureSettings = "tnum"))
    }
}

/** A graveyard (or exile): a pile like the library with its top card face up, or an empty dashed slot; a tap opens the zone. */
@Composable
fun ArenaGraveyardPile(cards: List<ZoneCard>, size: DpSize, label: String, modifier: Modifier = Modifier, exile: Boolean = false,
                       lean: (Modifier) -> Modifier = { it }, open: () -> Unit) {
    Box(modifier.defaultMinSize(44.dp, 44.dp).clickable(enabled = cards.isNotEmpty(), onClick = { GameAudio.play(GameSound.UI_OPEN); open() })
        .semantics { contentDescription = if (cards.isEmpty()) "$label, empty" else "$label, ${cards.size} cards" }, contentAlignment = Alignment.Center) {
        ArenaPileStack(cards.size, size, lean = lean) {
            val top = cards.lastOrNull()
            if (top != null) Box(Modifier.fillMaxSize()) {
                CardTile(top, selected = false, zoneName = if (exile) "Exile" else "Graveyard", width = size.width, height = size.height, ignoreTappedRotation = true)
                if (exile) Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(rgb(0.55, 0.7, 1.0).copy(alpha = 0.42f),
                    rgb(0.3, 0.25, 0.6).copy(alpha = 0.5f))), RoundedCornerShape(size.width * 0.07f))) {
                    SfImage("sparkles", Color.White.copy(alpha = 0.9f), size.width * 0.24f, Modifier.padding(size.width * 0.06f))
                }
            }
        }
    }
}

/** The opponent's hand as a fan of card backs along the top edge. */
@Composable
fun ArenaOpponentHandFan(count: Int, card: DpSize, pitch: Float, modifier: Modifier = Modifier) {
    val shown = min(count, 12)
    // A few cards still fan out past the medallion in front of them.
    val step = if (shown > 1) max(pitch, card.width.value * 1.8f / (shown - 1)) else 0f
    Box(modifier.requiredSize(card.width + (max(shown - 1, 0) * step).dp, card.height)
        .semantics { contentDescription = if (count == 1) "1 card in hand" else "$count cards in hand" }, contentAlignment = Alignment.Center) {
        for (index in 0 until shown) {
            val offset = index - (shown - 1) / 2f
            ArenaCardBack(Modifier.requiredSize(card).graphicsLayer {
                translationX = offset * step * density; translationY = -offset * offset * 0.9f * density
                rotationZ = 180 - offset * 4
            })
        }
    }
}

// MARK: - Phase strip

/**
 * The reference's phase strip: all eight steps of a turn as dark icons on a thin track, always shown, the current one lit in
 * the active player's colour; moving on sends a spark along the track to the next icon.
 */
@Composable
fun ArenaPhaseStrip(step: String?, viewerTurn: Boolean, width: Dp, modifier: Modifier = Modifier, iconSize: Dp = 16.dp) {
    val icons = ArenaPhaseStripRules.icons
    val current = ArenaPhaseStripRules.current(step)
    val rim = if (viewerTurn) ArenaPalette.viewerRim else ArenaPalette.opponentRim
    val reduce = BoardMotion.reduceMotion
    val spacing = (width.value - 12) / icons.size
    val positions = icons.indices.map { 6 + spacing * (it + 0.5f) }
    val spark = remember { Animatable(-1f) }
    val ignite = remember { Animatable(0f) }
    var previous by remember { mutableStateOf(current) }
    var travelling by remember { mutableStateOf(false) }
    val lit by animateFloatAsState(if (current != null && current > 0) positions[current] - positions[0] else 0f, tween(if (reduce) 0 else 300), label = "phaseLit")
    LaunchedEffect(current) {
        val old = previous
        previous = current
        if (reduce || old == null || current == null || old == current) { travelling = false; return@LaunchedEffect }
        val distance = kotlin.math.abs(positions[current] - positions[old])
        val duration = (220 + min(260f, distance * 2.2f)).toInt()
        travelling = true
        spark.snapTo(positions[old])
        spark.animateTo(positions[current], tween(duration, easing = FastOutSlowInEasing))
        travelling = false
        ignite.animateTo(1f, tween(80)); ignite.animateTo(0f, tween(350))
    }
    val y = iconSize.value / 2 + 2
    Box(modifier.requiredSize(width, iconSize + 4.dp).semantics { contentDescription = TavernPhaseTrack.describe(step).first; testTag = "board.phase.plate" }) {
        Canvas(Modifier.fillMaxSize()) {
            val track = 1.4.dp.toPx()
            drawRect(Brush.horizontalGradient(listOf(Color.Transparent, TavernPalette.brass.copy(alpha = 0.75f), TavernPalette.brass.copy(alpha = 0.75f), Color.Transparent)),
                Offset(0f, y.dp.toPx() - track / 2), Size(size.width, track))
            if (lit > 0f) drawRoundRect(Brush.horizontalGradient(listOf(rim.copy(alpha = 0.2f), rim), positions[0].dp.toPx(), (positions[0] + lit).dp.toPx()),
                Offset(positions[0].dp.toPx(), y.dp.toPx() - 1.dp.toPx()), Size(lit.dp.toPx(), 2.dp.toPx()), CornerRadius(1.dp.toPx()))
        }
        icons.forEachIndexed { index, icon ->
            // The current step stays dark only while the spark is still on its way to it.
            val on = index == current && !travelling
            val size = iconSize * (if (icon == ArenaPhaseStripRules.Icon.DIAMOND) 0.7f else 0.9f) * (if (on) 1.2f else 1f)
            ArenaPhaseIcon(icon, rim, on, size, Modifier.centerAt(positions[index], y).graphicsLayer {
                val scale = if (on) 1 + 0.45f * ignite.value else 1f; scaleX = scale; scaleY = scale
            })
        }
        if (travelling) Box(Modifier.centerAt(0f, y).requiredSize(14.dp).graphicsLayer { translationX = spark.value * density }
            .background(Brush.radialGradient(listOf(Color.White, rim, Color.Transparent)), CircleShape))
    }
}

/** One phase icon: a small enamel piece in a brass rim with an engraved detail, lit gold-white into the turn's colour while current. */
@Composable
fun ArenaPhaseIcon(icon: ArenaPhaseStripRules.Icon, rim: Color, on: Boolean, size: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.requiredSize(size)) {
        val s = this.size.minDimension
        if (on) drawCircle(Brush.radialGradient(listOf(rim.copy(alpha = 0.7f), rim.copy(alpha = 0f)), center, s), s)
        val silhouette = arenaPhaseShape(icon, s)
        val enamel = if (on) listOf(Color.White, rgb(1.0, 0.86, 0.56), rim) else listOf(rgb(0.42, 0.33, 0.24), rgb(0.2, 0.14, 0.1), rgb(0.08, 0.05, 0.04))
        drawPath(silhouette, Brush.verticalGradient(enamel, 0f, s))
        // Facet shading: the lower right turns away from the lamp.
        drawPath(silhouette, Brush.linearGradient(listOf(Color.Transparent, Color.Black.copy(alpha = if (on) 0.16f else 0.32f)), Offset.Zero, Offset(s, s)))
        drawPath(arenaPhaseDetail(icon, s), if (on) rgb(0.42, 0.2, 0.04).copy(alpha = 0.8f) else TavernPalette.brass.copy(alpha = 0.6f),
            style = Stroke(max(0.7.dp.toPx(), s * 0.05f), cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawPath(silhouette, Brush.verticalGradient(listOf(rgb(1.0, 0.9, 0.62), TavernPalette.brass, rgb(0.33, 0.2, 0.07)), 0f, s),
            style = Stroke(max(1.dp.toPx(), s * 0.07f), join = StrokeJoin.Round))
        clipRect(bottom = s / 2) { drawPath(silhouette, Color.White.copy(alpha = if (on) 0.7f else 0.25f), style = Stroke(max(0.5.dp.toPx(), s * 0.03f))) }
    }
}

/** The strip's icons, drawn on a 20 × 20 grid like the prototype's SVGs. */
private fun arenaPhaseShape(icon: ArenaPhaseStripRules.Icon, size: Float): Path {
    val scale = size / 20
    fun polygon(path: Path, points: List<Pair<Float, Float>>) {
        path.moveTo(points[0].first * scale, points[0].second * scale)
        for (point in points.drop(1)) path.lineTo(point.first * scale, point.second * scale)
        path.close()
    }
    val path = Path()
    when (icon) {
        ArenaPhaseStripRules.Icon.DIAMOND -> polygon(path, listOf(10f to 3.5f, 16.5f to 10f, 10f to 16.5f, 3.5f to 10f))
        ArenaPhaseStripRules.Icon.CARD -> path.addRoundRect(androidx.compose.ui.geometry.RoundRect(5 * scale, 2.5f * scale, 15 * scale, 17.5f * scale, CornerRadius(2 * scale)))
        ArenaPhaseStripRules.Icon.SWORD -> {
            polygon(path, listOf(17.6f to 2.4f, 17.1f to 5.4f, 8.6f to 13.9f, 6.1f to 11.4f, 14.6f to 2.9f))
            polygon(path, listOf(3.9f to 10.6f, 9.4f to 16.1f, 8.2f to 17.3f, 2.7f to 11.8f))
            polygon(path, listOf(5.6f to 15.2f, 3.3f to 17.5f, 2.5f to 16.7f, 4.8f to 14.4f))
        }
        ArenaPhaseStripRules.Icon.SHIELD -> {
            path.moveTo(10 * scale, 2.2f * scale); path.lineTo(16.4f * scale, 4.4f * scale); path.lineTo(16.4f * scale, 9.4f * scale)
            path.cubicTo(16.4f * scale, 13.6f * scale, 13.5f * scale, 16.3f * scale, 10 * scale, 17.8f * scale)
            path.cubicTo(6.5f * scale, 16.3f * scale, 3.6f * scale, 13.6f * scale, 3.6f * scale, 9.4f * scale)
            path.lineTo(3.6f * scale, 4.4f * scale); path.close()
        }
        ArenaPhaseStripRules.Icon.BURST -> polygon(path, listOf(10f to 1.6f, 11.9f to 6.4f, 16.8f to 4.5f, 14.6f to 9.2f, 18.9f to 11.9f, 13.9f to 12.7f,
            14.1f to 17.8f, 10f to 14.7f, 5.9f to 17.8f, 6.1f to 12.7f, 1.1f to 11.9f, 5.4f to 9.2f, 3.2f to 4.5f, 8.1f to 6.4f))
    }
    return path
}

/** The engraved line inside each phase icon, on the same 20 × 20 grid. */
private fun arenaPhaseDetail(icon: ArenaPhaseStripRules.Icon, size: Float): Path {
    val scale = size / 20
    val path = Path()
    fun move(x: Float, y: Float) = path.moveTo(x * scale, y * scale)
    fun line(x: Float, y: Float) = path.lineTo(x * scale, y * scale)
    when (icon) {
        ArenaPhaseStripRules.Icon.DIAMOND -> { move(10f, 6.6f); line(13.4f, 10f); line(10f, 13.4f); line(6.6f, 10f); path.close() }
        ArenaPhaseStripRules.Icon.CARD -> {
            path.addRoundRect(androidx.compose.ui.geometry.RoundRect(6.7f * scale, 4.3f * scale, 13.3f * scale, 10.5f * scale, CornerRadius(scale)))
            move(7f, 12.9f); line(13f, 12.9f); move(7f, 14.9f); line(11.4f, 14.9f)
        }
        ArenaPhaseStripRules.Icon.SWORD -> { move(16.2f, 3.8f); line(8.8f, 11.2f); path.addOval(Rect(1.6f * scale, 16.4f * scale, 3.6f * scale, 18.4f * scale)) }
        ArenaPhaseStripRules.Icon.SHIELD -> {
            path.addOval(Rect(7.8f * scale, 6.8f * scale, 12.2f * scale, 11.2f * scale)); move(10f, 3.4f); line(10f, 6.8f); move(10f, 11.2f); line(10f, 16.4f)
        }
        ArenaPhaseStripRules.Icon.BURST -> path.addOval(Rect(7.4f * scale, 7.8f * scale, 12.6f * scale, 13f * scale))
    }
    return path
}

// MARK: - Controls

enum class ArenaPlaqueKind { PRIMARY, SECONDARY, WAITING }

/**
 * The corner's plaque buttons on Arena's button face: the orange pill for the call to action, the dark glass pill for the
 * other choice, a quiet word when it's the opponent's turn. The pill is drawn a little inside its 44 dp target.
 */
@Composable
fun ArenaPlaqueButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, subtitle: String? = null,
                      kind: ArenaPlaqueKind = ArenaPlaqueKind.PRIMARY, fontSize: Float = 18f, enabled: Boolean = true, identifier: String? = null) {
    PressableBox(onClick, modifier.semantics { contentDescription = subtitle?.let { "$title, $it" } ?: title; identifier?.let { testTag = it } },
        enabled, GameSound.UI_TAP) { pressed ->
        val face = when (kind) { ArenaPlaqueKind.PRIMARY -> ArenaButtonKind.PRIMARY; ArenaPlaqueKind.SECONDARY -> ArenaButtonKind.SECONDARY; ArenaPlaqueKind.WAITING -> ArenaButtonKind.QUIET }
        ArenaButtonFace(face, ArenaMenuStyle.title(if (kind == ArenaPlaqueKind.WAITING) fontSize * 0.8f else fontSize, SfWeight.bold), pressed,
            Modifier.fillMaxSize(), enabled, inset = 3.dp, glow = 0.8f) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                ArenaButtonText(title)
                subtitle?.let {
                    Text(it.uppercase(), Modifier.alpha(0.85f), color = LocalContentColor.current,
                        style = sf(fontSize * 0.42f, SfWeight.heavy, SfDesign.SERIF).copy(letterSpacing = 0.1.em), maxLines = 1)
                }
            }
        }
    }
}

/** A small pill: pass ahead (">>") and Undo. Dark glass, orange while lit. */
@Composable
fun ArenaPill(onClick: () -> Unit, modifier: Modifier = Modifier, lit: Boolean = false, enabled: Boolean = true, label: String? = null,
              content: @Composable () -> Unit) {
    PressableBox(onClick, modifier.then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier), enabled) { pressed ->
        ArenaButtonFace(if (lit) ArenaButtonKind.PRIMARY else ArenaButtonKind.SECONDARY, ArenaMenuStyle.font(13f, SfWeight.heavy), pressed,
            Modifier.fillMaxSize(), enabled, glow = 0.7f) {
            CompositionLocalProvider(LocalContentColor provides LocalContentColor.current) { content() }
        }
    }
}

/** One row of an Arena menu card. */
data class ArenaMenuItem(val id: String, val title: String, val subtitle: String? = null, val symbol: String? = null, val lit: Boolean = false,
                         val enabled: Boolean = true, val action: () -> Unit)

/** The skip choices in a few words each (ArenaPassAheadPill.items). */
fun arenaPassAheadItems(control: NativeTurnControl): List<ArenaMenuItem> = listOf(
    ArenaMenuItem("skip-responses", "To end of turn", "Skips responses", "forward.end.fill", enabled = control.canSkipResponses, action = control.skipResponses),
    ArenaMenuItem("skip-to-my-turn", "To my turn", "Skips responses", "forward.end.alt.fill", enabled = control.canSkipToMyTurn, action = control.skipToMyTurn),
    ArenaMenuItem("end-turn", "To end of turn", "Stops if they respond", "forward.fill", enabled = control.canEndTurn, action = control.endTurn),
    ArenaMenuItem("full-control", "Full control", if (control.isFullControl) "On for this turn" else "Stop at every priority this turn",
        "hand.raised.fill", lit = control.isFullControl, action = control.toggleFullControl))

/** Pass ahead: the skip options while you play, Stop while the table skips for you. */
@Composable
fun ArenaPassAheadPill(openMenu: () -> Unit, modifier: Modifier = Modifier) {
    val control = LocalNativeTurnControl.current ?: return
    if (control.isAutoPassing) {
        ArenaPill(control.stop, modifier, lit = true, label = "Stop skipping") { SfImage("forward.fill", LocalContentColor.current, 13.dp) }
    } else {
        ArenaPill(openMenu, modifier, enabled = control.canEndTurn || control.canSkipResponses || control.canSkipToMyTurn, label = "Skip options") {
            SfImage("forward.fill", LocalContentColor.current, 13.dp)
        }
    }
}

/** A row or option on glass: a lighter pane in the hairline; primary rows a touch brighter. */
fun Modifier.arenaGlassRow(primary: Boolean = false, danger: Boolean = false, cornerRadius: Dp = 10.dp): Modifier {
    val shape = RoundedCornerShape(cornerRadius)
    return this.background(if (danger) rgb(0.42, 0.08, 0.07).copy(alpha = 0.85f) else Color.White.copy(alpha = if (primary) 0.11f else 0.06f), shape)
        .then(if (danger) Modifier.border(0.8.dp, rgb(0.9, 0.4, 0.3).copy(alpha = 0.7f), shape) else Modifier.border(if (primary) 1.2.dp else 0.8.dp, ArenaGlass.hairline, shape))
}

/**
 * A menu on the Arena table (the gear's, the skip pill's): glass rows in a gold hairline on a glass card, an icon, a title and a
 * line under it, drawn on the table (never a pop-over). A row closes the card, then acts.
 */
@Composable
fun ArenaMenuCard(items: List<ArenaMenuItem>, close: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.width(280.dp).arenaGlassPanel(16.dp, 0.96f).padding(10.dp).semantics { testTag = "arena.menuCard" },
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (item in items) {
            Row(Modifier.fillMaxWidth().heightIn(min = 46.dp).alpha(if (item.enabled) 1f else 0.45f).arenaGlassRow(item.lit)
                .clickable(enabled = item.enabled) { GameAudio.play(GameSound.UI_TAP); close(); item.action() }
                .semantics { contentDescription = item.subtitle?.let { "${item.title}, $it" } ?: item.title; testTag = "arena.menu.${item.id}" }
                .padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                item.symbol?.let { SfImage(it, if (item.lit) TavernPalette.ember else ArenaPalette.gold, 15.dp, Modifier.width(22.dp)) }
                Column(Modifier.weight(1f)) {
                    FitText(item.title, ArenaMenuStyle.font(16f, SfWeight.semibold), color = ArenaGlass.text, minimumScale = 0.8f)
                    item.subtitle?.let { FitText(it, ArenaMenuStyle.font(11f, SfWeight.medium), Modifier.alpha(0.65f), color = ArenaGlass.text, minimumScale = 0.8f) }
                }
            }
        }
    }
}

/** The glass close button. */
@Composable
fun ArenaCloseLabel(modifier: Modifier = Modifier) {
    Box(modifier.size(32.dp).background(Color.White.copy(alpha = 0.1f), CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape), contentAlignment = Alignment.Center) {
        SfImage("xmark", ArenaGlass.text, 13.dp)
    }
}

// MARK: - The stack card

/**
 * The stack card's eye (iOS ArenaStackTab, ArenaStackTuck): at the card's lower left, under the tab that opens the whole
 * stack, it tucks the card aside; tucked, a slim tab at the table's edge with the stack's count brings it back. A 44 dp
 * target around the slim tab, the tab at its right edge (against the card, or the table's edge).
 */
@Composable
fun ArenaStackTab(tucked: Boolean, count: Int, modifier: Modifier = Modifier, action: () -> Unit) {
    val shape = RoundedCornerShape(topStart = 12.dp, bottomStart = 12.dp, topEnd = if (tucked) 4.dp else 0.dp, bottomEnd = if (tucked) 4.dp else 0.dp)
    Box(modifier.size(44.dp, if (tucked) 92.dp else 44.dp)
        .clickable(onClick = action)
        .semantics {
            contentDescription = if (tucked) "Show the stack, $count on it" else "Tuck the stack away"
            testTag = if (tucked) "arena.stack.show" else "arena.stack.tuck"
        }, contentAlignment = Alignment.CenterEnd) {
        Column(Modifier.size(if (tucked) 30.dp else 26.dp, if (tucked) 84.dp else 40.dp)
            .background(Brush.verticalGradient(listOf(io.magicmobile.android.menus.ArenaGlass.top.copy(alpha = 0.96f),
                io.magicmobile.android.menus.ArenaGlass.bottom.copy(alpha = 0.96f))), shape)
            .border(1.dp, io.magicmobile.android.menus.ArenaMenuStyle.gold.copy(alpha = 0.55f), shape),
            verticalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
            val gold = io.magicmobile.android.menus.ArenaMenuStyle.gold
            io.magicmobile.android.ui.SfImage(if (tucked) "eye.fill" else "eye.slash.fill", gold, 12.dp)
            if (tucked) {
                io.magicmobile.android.ui.SfImage("chevron.left", gold, 11.dp)
                if (count > 1) Text("$count", color = gold, style = io.magicmobile.android.ui.sf(12f, io.magicmobile.android.ui.SfWeight.black,
                    io.magicmobile.android.ui.SfDesign.SERIF))
            }
        }
    }
}

/**
 * The top of the stack as a big card on the right (the reference's stack), with a tab on its left edge that opens the whole
 * stack and says how many objects it holds. It lands with a settle, a bloom of its colour, a shine and a few motes.
 */
@Composable
fun ArenaStackCard(item: XmageStackObject, count: Int, size: DpSize, modifier: Modifier = Modifier, commander: Boolean = false,
                   fallbackSource: ZoneCard? = null, lands: Boolean = true, inspect: (ZoneCard) -> Unit, openStack: () -> Unit) {
    val ability = ArenaTableRules.isAbility(item)
    val source = item.displaySourceCard ?: fallbackSource
    val fxLevel by io.magicmobile.android.ui.AppPreferences.string(BoardFXLevel.key, BoardFXLevel.defaultValue)
    val animate = lands && !BoardMotion.reduceMotion && BoardFXLevel.of(fxLevel) != BoardFXLevel.OFF
    val settle = remember { Animatable(if (animate) 1.07f else 1f) }
    val landing = remember { Animatable(if (animate) 0f else 1f) }
    LaunchedEffect(Unit) {
        if (!animate) return@LaunchedEffect
        launch { settle.animateTo(1f, spring(0.6f, 260f)) }
        landing.animateTo(1f, tween(550, easing = LinearEasing))
    }
    val arrival = when (ArenaTableRules.arrivalColor(item, commander)) {
        "M" -> rgb(1.0, 0.82, 0.45); "W" -> rgb(1.0, 0.95, 0.78); "U" -> rgb(0.4, 0.7, 1.0); "B" -> rgb(0.72, 0.5, 0.9)
        "R" -> rgb(1.0, 0.45, 0.25); "G" -> rgb(0.45, 0.9, 0.5); else -> rgb(0.85, 0.88, 0.95)
    }
    Box(modifier.requiredSize(size).semantics {
        contentDescription = if (ability) "Top of the stack: an ability of ${item.displaySourceName}" else "Top of the stack: ${item.displayName}"
    }) {
        // Light of the spell's colour behind the card, flaring as it lands and fading as it settles, and motes drifting off.
        Box(Modifier.fillMaxSize().drawBehind {
            val t = landing.value
            if (t >= 1f) return@drawBehind
            val flare = sin(PI * t).toFloat()
            val pad = this.size.width * (0.04f + 0.1f * flare)
            drawIntoCanvas { canvas ->
                val paint = Paint()
                paint.asFrameworkPaint().apply {
                    color = android.graphics.Color.argb((0.85f * flare * 255).roundToInt(), (arrival.red * 255).roundToInt(), (arrival.green * 255).roundToInt(), (arrival.blue * 255).roundToInt())
                    maskFilter = BlurMaskFilter(max(1f, this@drawBehind.size.width * 0.12f), BlurMaskFilter.Blur.NORMAL)
                }
                canvas.drawRoundRect(-pad, -pad, this.size.width + pad, this.size.height + pad, this.size.width * 0.12f, this.size.width * 0.12f, paint)
            }
            for (index in 0 until 6) {
                val angle = index / 6.0 * 2 * PI + 0.4
                val point = center + Offset((cos(angle) * this.size.width * (0.42 + 0.3 * t)).toFloat(),
                    (sin(angle) * this.size.height * (0.38 + 0.24 * t) - 14 * t * density).toFloat())
                drawCircle(arrival.copy(alpha = flare * 0.6f), 5.dp.toPx(), point, blendMode = BlendMode.Plus)
                drawCircle(Color.White.copy(alpha = flare), 2.dp.toPx(), point)
            }
        })
        Box(Modifier.fillMaxSize().graphicsLayer { scaleX = settle.value; scaleY = settle.value }.glow(Color.Black.copy(alpha = 0.6f), 10.dp, size.width * 0.05f)) {
            when {
                source != null && ability -> Box(Modifier.fillMaxSize().clickable { inspect(source) }) {
                    ArenaAbilityCard(source, text = item.rulesText ?: item.displayName, size = size)
                }
                item.displaySourceCard != null -> Box(Modifier.fillMaxSize().clickable { inspect(item.displaySourceCard!!) }) {
                    // The printed card already shows its power and toughness: no badges over it.
                    CardTile(item.displaySourceCard!!, selected = false, zoneName = "Stack", width = size.width, height = size.height, ignoreTappedRotation = true)
                }
                // A spell or ability whose card isn't known: its name and text on the Arena's ability card.
                else -> ArenaAbilityCard(null, name = item.displayName, text = item.rulesText ?: item.displaySourceName, size = size)
            }
            if (commander) Box(Modifier.fillMaxSize().glow(rgb(1.0, 0.8, 0.35).copy(alpha = 0.8f), 8.dp, size.width * 0.05f)
                .border(3.dp, Brush.verticalGradient(listOf(rgb(1.0, 0.9, 0.55), TavernPalette.brass, rgb(0.6, 0.42, 0.12))), RoundedCornerShape(size.width * 0.05f)))
            // A band of light that sweeps once across the card as it lands.
            Box(Modifier.fillMaxSize().clip(RoundedCornerShape(size.width * 0.05f)).drawBehind {
                val t = landing.value
                if (t >= 1f) return@drawBehind
                val band = this.size.width * 0.45f
                val x = this.size.width * (-1 + 2 * t) + this.size.width / 2
                rotate(18f, Offset(x, center.y)) {
                    drawRect(Brush.horizontalGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.5f), Color.Transparent), x - band / 2, x + band / 2),
                        Offset(x - band / 2, -this.size.height * 0.3f), Size(band, this.size.height * 1.6f), blendMode = BlendMode.Plus)
                }
            })
        }
        if (commander) Box(Modifier.align(Alignment.TopCenter).offset(y = (-14).dp).size(28.dp).glow(Color.Black.copy(alpha = 0.5f), 2.dp, 14.dp)
            .background(Brush.verticalGradient(listOf(rgb(1.0, 0.9, 0.58), TavernPalette.brass)), CircleShape)
            .border(0.8.dp, Color.Black.copy(alpha = 0.5f), CircleShape).semantics { contentDescription = "Commander" }, contentAlignment = Alignment.Center) {
            SfImage("crown.fill", rgb(0.3, 0.17, 0.03), 13.dp)
        }
        // A tab on the card's left edge opens the whole stack, with how many objects are on it.
        val tabHeight = if (count > 1) 58.dp else 44.dp
        Box(Modifier.align(Alignment.CenterStart).offset(x = (-43).dp).requiredSize(44.dp, tabHeight).clickable { openStack() }
            .semantics { contentDescription = if (count > 1) "Open the stack, $count objects" else "Open the stack"; testTag = "board.stack.tray" },
            contentAlignment = Alignment.CenterEnd) {
            val shape = RoundedCornerShape(topStart = 9.dp, bottomStart = 9.dp)
            Column(Modifier.requiredSize(26.dp, tabHeight).glow(Color.Black.copy(alpha = 0.5f), 3.dp, 9.dp)
                .background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)), shape).border(1.dp, ArenaGlass.hairline, shape),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
                if (count > 1) Text("$count", color = ArenaPalette.gold, style = ArenaMenuStyle.font(15f, SfWeight.heavy).copy(fontFeatureSettings = "tnum"))
                SfImage("chevron.left", ArenaGlass.text, 10.dp)
            }
        }
    }
}

/** An ability on the stack the reference game's way: its source's frame colour and art, a type line, its text and a rounded foot. */
@Composable
fun ArenaAbilityCard(source: ZoneCard?, modifier: Modifier = Modifier, name: String? = null, kind: String = "Ability", text: String, size: DpSize,
                     loyalty: String? = null) {
    val frame = source?.let(ArenaCardColor::frame) ?: rgb(0.62, 0.62, 0.66)
    val edge = maxOf(3.dp, size.width * 0.035f)
    val w = size.width.value
    val shape = ArenaAbilityShape
    val icon = XmageCardIcon.keywordIcons(text).firstOrNull()?.let { xmageIconDrawable(it.iconType) }
    val ink = rgb(0.08, 0.07, 0.06)
    Box(modifier.requiredSize(size).semantics { contentDescription = "Ability of ${source?.card?.name ?: name ?: "a permanent"}: ${PromptDisplayText.clean(text)}" }) {
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(frame, frame.copy(alpha = 0.75f))), shape))
        Column(Modifier.fillMaxSize().padding(edge).clip(shape)) {
            Box(Modifier.fillMaxWidth().height(size.height * 0.085f).background(rgb(0.94, 0.94, 0.94)).background(frame.copy(alpha = 0.28f))
                .padding(horizontal = size.width * 0.05f), contentAlignment = Alignment.CenterStart) {
                FitText(source?.card?.name ?: name ?: "Ability", sf(maxOf(10f, w * 0.075f), SfWeight.bold, SfDesign.SERIF), color = ink, minimumScale = 0.6f)
            }
            Box(Modifier.fillMaxWidth().height(size.height * 0.4f)) {
                if (source != null) TavernArtCrop(source, "Stack")
                else Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(frame.copy(alpha = 0.6f), rgb(0.1, 0.1, 0.12)))), contentAlignment = Alignment.Center) {
                    SfImage("sparkles", Color.White.copy(alpha = 0.5f), size.width * 0.2f)
                }
            }
            Box(Modifier.fillMaxWidth().height(size.height * 0.07f).background(rgb(0.9, 0.9, 0.9)).background(frame.copy(alpha = 0.22f))
                .padding(horizontal = size.width * 0.05f), contentAlignment = Alignment.CenterStart) {
                Text(kind, color = ink, style = sf(maxOf(9f, w * 0.062f), SfWeight.semibold, SfDesign.SERIF), maxLines = 1)
            }
            Box(Modifier.fillMaxWidth().weight(1f).background(rgb(0.97, 0.95, 0.9)).padding(size.width * 0.06f)) {
                GameRulesText(PromptDisplayText.clean(text), symbolSize = maxOf(9f, w * 0.06f).dp,
                    style = sf(maxOf(9f, w * 0.062f), design = SfDesign.SERIF), color = rgb(0.1, 0.08, 0.06), maxLines = 8)
            }
        }
        Box(Modifier.fillMaxSize().border(1.dp, Color.Black.copy(alpha = 0.85f), shape))
        loyalty?.let {
            Box(Modifier.align(Alignment.BottomCenter).offset(y = size.width * 0.1f).requiredSize(size.width * 0.32f, size.width * 0.24f)
                .background(rgb(0.08, 0.08, 0.1), ArenaShieldShape).border(1.2.dp, Color.White.copy(alpha = 0.85f), ArenaShieldShape)
                .semantics { contentDescription = "Loyalty $it" }, contentAlignment = Alignment.Center) {
                Text(it, color = Color.White, style = sf(maxOf(12f, w * 0.1f), SfWeight.heavy, SfDesign.SERIF))
            }
        }
        icon?.let {
            Box(Modifier.align(Alignment.TopStart).offset(-size.width * 0.06f, size.height * 0.1f).requiredSize(size.width * 0.16f)
                .background(rgb(0.12, 0.1, 0.08), CircleShape).border(1.dp, TavernPalette.brass, CircleShape).padding(4.dp)) {
                Image(androidx.compose.ui.res.painterResource(it), null, Modifier.fillMaxSize())
            }
        }
    }
}

/** An ability card's outline (ArenaAbilityShape): rounded top corners (a twentieth of its width) and a rounded foot. */
internal val ArenaAbilityShape = GenericShape { size, _ ->
    val c = size.width * 0.05f
    val foot = size.height * 0.1f
    moveTo(c, 0f); lineTo(size.width - c, 0f)
    arcTo(Rect(size.width - 2 * c, 0f, size.width, 2 * c), -90f, 90f, false)
    lineTo(size.width, size.height - foot)
    quadraticTo(size.width, size.height, size.width / 2, size.height)
    quadraticTo(0f, size.height, 0f, size.height - foot)
    lineTo(0f, c)
    arcTo(Rect(0f, 0f, 2 * c, 2 * c), 180f, 90f, false)
    close()
}

// MARK: - A player's card

/** A player's life, counters and zones, opened from their medallion (ArenaPlayerCard): glass, on the table, never a pop-over. */
@Composable
fun ArenaPlayerCard(player: PlayerGameState, snapshot: GameSnapshot, pendingActionID: String?, modifier: Modifier = Modifier,
                    opponents: List<PlayerGameState> = emptyList(), swap: ((String) -> Unit)? = null, open: (BoardZoneReference) -> Unit, close: () -> Unit) {
    val name = snapshot.playerLabel(player.playerId)
    val viewer = snapshot.isViewer(player.playerId)
    val castable = if (viewer) GameplayAffordances.castableZones(player, snapshot, pendingActionID) else emptySet()
    val commanderReady = viewer && GameplayAffordances.commanderCastAvailable(player, snapshot, pendingActionID)
    data class ZoneIcon(val zone: BoardZoneReference.PlayerZone, val name: String, val symbol: String, val count: Int, val lit: Boolean)
    val zones = buildList {
        if (player.zones.command.isNotEmpty() || !player.commanders.isNullOrEmpty()) add(ZoneIcon(BoardZoneReference.PlayerZone.COMMAND, "Command", "crown.fill", player.zones.command.size, commanderReady))
        add(ZoneIcon(BoardZoneReference.PlayerZone.GRAVEYARD, "Graveyard", "leaf.fill", player.zones.graveyard.size, BoardZoneReference.PlayerZone.GRAVEYARD in castable))
        add(ZoneIcon(BoardZoneReference.PlayerZone.EXILE, "Exile", "sparkles", player.zones.exile.size, BoardZoneReference.PlayerZone.EXILE in castable))
        add(ZoneIcon(BoardZoneReference.PlayerZone.LIBRARY, "Library", "books.vertical.fill", player.zones.visibleLibraryCount, BoardZoneReference.PlayerZone.LIBRARY in castable))
        if (!viewer) add(ZoneIcon(BoardZoneReference.PlayerZone.HAND, "Hand", "hand.raised.fill", player.zones.visibleHandCount, false))
    }.filter { it.count > 0 || it.zone == BoardZoneReference.PlayerZone.COMMAND || it.zone == BoardZoneReference.PlayerZone.LIBRARY }
    val breath = if (BoardMotion.reduceMotion) null else rememberBoardBreath(1100, 0.55f, 1f)
    Column(modifier.width(300.dp).arenaGlassPanel(18.dp, 0.96f).verticalScroll(rememberScrollState()).padding(14.dp).semantics { testTag = "arena.playerCard" },
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).border(1.dp, ArenaGlass.hairline, CircleShape)) { PlayerPortrait(player, 44.dp) }
            Column(Modifier.weight(1f)) {
                FitText(name, sf(17f, SfWeight.bold, SfDesign.SERIF), color = ArenaGlass.text, minimumScale = 0.7f)
                Text(if (player.isOut) "Out of the game" else "${player.life} life", color = ArenaPalette.gold, style = ArenaMenuStyle.font(13f, SfWeight.heavy))
            }
            Box(Modifier.size(44.dp).clickable(onClick = close).semantics { contentDescription = "Close $name's card" }, contentAlignment = Alignment.Center) {
                SfImage("xmark", ArenaGlass.text.copy(alpha = 0.8f), 13.dp)
            }
        }
        io.magicmobile.android.ondevice.LocalVoiceRoom.current?.takeIf { !viewer }?.let { room ->
            room.seatNamed(player.displayName)?.let { ArenaVoiceSilenceButton(room, it) }
        }
        val summary = PlayerStatusSummary(player, snapshot)
        if (summary.orbit.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (badge in summary.orbit) Row(Modifier.semantics(mergeDescendants = true) { contentDescription = badge.label },
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(30.dp).clearAndSetSemantics { }, contentAlignment = Alignment.Center) { TavernStatusBadge(badge, 26.dp) }
                Text(badge.label, color = if (badge.nearLethal) rgb(1.0, 0.62, 0.52) else ArenaGlass.text, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
            }
        }
        zones.chunked(4).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (icon in row) {
                    Column(Modifier.weight(1f).heightIn(min = 64.dp)
                        .then(if (icon.lit) Modifier.arenaOutlineGlow(ArenaGlowOutline.Card, ArenaGlowTone.PLAYABLE, breath = breath) else Modifier)
                        .arenaGlassRow(icon.lit).clickable { open(BoardZoneReference.Player(player.playerId, icon.zone)) }
                        .semantics { contentDescription = if (icon.lit) "${icon.name}, ${icon.count}, you can play from it" else "${icon.name}, ${icon.count}"; testTag = "arena.player.zone.${icon.zone.name.lowercase()}" }
                        .padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
                        val tint = if (icon.lit) rgb(1.0, 0.9, 0.7) else ArenaGlass.text
                        SfImage(icon.symbol, tint, 17.dp)
                        Text("${icon.count}", color = tint, style = ArenaMenuStyle.font(13f, SfWeight.heavy).copy(fontFeatureSettings = "tnum"))
                        FitText(icon.name.uppercase(), ArenaMenuStyle.font(8f, SfWeight.heavy).copy(letterSpacing = 0.1.em), color = tint, minimumScale = 0.7f)
                    }
                }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        val named = BoardZoneReference.namedReferences(snapshot)
        if (named.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (reference in named) Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).arenaGlassRow().clickable { open(reference) }.padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(reference.title(snapshot), Modifier.weight(1f), color = ArenaGlass.text, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
                Text("${reference.cards(snapshot).size}", color = ArenaGlass.text, style = ArenaMenuStyle.font(13f, SfWeight.heavy).copy(fontFeatureSettings = "tnum"))
            }
        }
        if (opponents.size > 1 && swap != null) TavernOpponentSwap(opponents, player.playerId, { snapshot.playerLabel(it) }, swap)
    }
}

// MARK: - Amounts

/** A button that keeps acting while it is held (after a short wait), like the reference's − and +. `action` returns false at an end. */
@Composable
fun ArenaRepeatButton(modifier: Modifier = Modifier, repeats: Boolean = true, enabled: Boolean = true, label: String, action: () -> Boolean,
                      content: @Composable () -> Unit) {
    val latest by rememberUpdatedState(action)
    var pressed by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (pressed) 0.94f else 1f, tween(90), label = "repeatPress")
    Box(modifier.graphicsLayer { scaleX = scale; scaleY = scale }.semantics { contentDescription = label }
        .pointerInput(enabled, repeats) {
            if (!enabled) return@pointerInput
            awaitEachGesture {
                awaitFirstDown()
                pressed = true
                val stepped = latest()
                if (stepped && repeats) {
                    val job = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch {
                        delay(420)
                        while (latest()) delay(90)
                    }
                    try { do { val event = awaitPointerEvent() } while (event.changes.any { it.pressed }) } finally { job.cancel() }
                } else {
                    do { val event = awaitPointerEvent() } while (event.changes.any { it.pressed })
                }
                pressed = false
            }
        }, contentAlignment = Alignment.Center) { content() }
}

/**
 * X and other numbers: the reference's pill takes the corner, [−5] [−] [Pay X = n] [+] [+5], with XMage's way back (Cancel)
 * under it. The board, caption and stack stay in view.
 */
@Composable
fun ArenaAmountPill(label: String, range: ArenaAmountRange, initial: Int, pending: Boolean, submit: (Int) -> Unit, modifier: Modifier = Modifier,
                    cancel: Pair<String, () -> Unit>? = null) {
    var value by remember { mutableStateOf<Int?>(null) }
    val current = value ?: range.clamp(initial)
    val view = LocalView.current
    @Composable
    fun lens(title: String, places: Int) {
        val blocked = if (places < 0) current <= range.minimum else current >= range.maximum
        ArenaRepeatButton(Modifier.requiredSize(if (kotlin.math.abs(places) == 1) 48.dp else 42.dp, 42.dp).semantics { testTag = "arena.amount.$places" },
            repeats = kotlin.math.abs(places) == 1, enabled = !blocked && !pending, label = if (places < 0) "Lower by ${-places}" else "Raise by $places", action = {
                val now = value ?: range.clamp(initial)
                val next = range.step(now, places)
                if (next == now) false else { value = next; GameHaptics.selection(view); true }
            }) {
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)), CircleShape)
                .border(1.dp, ArenaGlass.hairline, CircleShape), contentAlignment = Alignment.Center) {
                Text(title, color = ArenaGlass.text.copy(alpha = if (blocked) 0.35f else 1f),
                    style = sf(if (kotlin.math.abs(places) == 1) 22f else 15f, SfWeight.heavy, SfDesign.SERIF))
            }
        }
    }
    Column(modifier.semantics { testTag = "arena.amount" }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy((-6).dp), verticalAlignment = Alignment.CenterVertically) {
            if (range.values.size > 6) lens("−5", -5)
            lens("−", -1)
            Box(Modifier.zIndex(1f).requiredSize(112.dp, 50.dp).glow(TavernPalette.ember.copy(alpha = 0.7f), 8.dp, 25.dp)
                .background(ArenaMenuStyle.orange, CircleShape).border(1.2.dp, rgb(1.0, 0.85, 0.5).copy(alpha = 0.9f), CircleShape)
                .clickable(enabled = !pending) { submit(current) }
                .semantics { contentDescription = "$label $current"; testTag = "arena.amount.submit" }, contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    val ink = rgb(1.0, 0.93, 0.75)
                    Text(label, color = ink, style = ArenaMenuStyle.font(12f, SfWeight.bold).arenaShadow(1f, 0.7f, 1f))
                    Text(if (label.endsWith("X")) "X = $current" else "$current", color = ink,
                        style = sf(18f, SfWeight.heavy, SfDesign.SERIF).copy(fontFeatureSettings = "tnum").arenaShadow(1f, 0.7f, 1f))
                }
            }
            lens("+", 1)
            if (range.values.size > 6) lens("+5", 5)
        }
        cancel?.let { (title, action) ->
            ArenaPlaqueButton(title, action, Modifier.requiredSize(150.dp, 44.dp), kind = ArenaPlaqueKind.SECONDARY, fontSize = 15f, enabled = !pending,
                identifier = "arena.amount.cancel")
        }
    }
}

// MARK: - Arcs, reticles, the caption and floating mana

/** The light arc from the spell or ability on the stack to what it points at, drawn in over 0.45 s. */
@Composable
fun ArenaStackArc(from: BoardRect, to: List<BoardRect>, color: Color, modifier: Modifier = Modifier) {
    val drawn = remember { Animatable(if (BoardMotion.reduceMotion) 1f else 0f) }
    LaunchedEffect(Unit) { drawn.animateTo(1f, tween(450, easing = FastOutSlowInEasing)) }
    Canvas(modifier.fillMaxSize()) {
        for (target in to) {
            val start = Offset(from.minX.dp.toPx(), (from.minY + from.height * 0.24f).dp.toPx())
            val end = Offset(target.midX.dp.toPx(), target.midY.dp.toPx())
            val control = Offset((start.x + end.x) / 2, min(start.y, end.y) - kotlin.math.abs(start.x - end.x) * 0.25f - 30.dp.toPx())
            val full = Path().apply { moveTo(start.x, start.y); quadraticTo(control.x, control.y, end.x, end.y) }
            val measure = PathMeasure().apply { setPath(full, false) }
            val path = Path()
            measure.getSegment(0f, measure.length * drawn.value, path, true)
            drawPath(path, color.copy(alpha = 0.35f), style = Stroke(9.dp.toPx(), cap = StrokeCap.Round))
            drawPath(path, color, style = Stroke(3.dp.toPx(), cap = StrokeCap.Round))
            drawPath(path, Color.White.copy(alpha = 0.85f), style = Stroke(1.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}

/** A spell or ability waiting on the stack marks what it targets: a ring with four ticks over the target. */
@Composable
fun ArenaTargetReticle(rect: BoardRect, color: Color) {
    val shown = remember { Animatable(if (BoardMotion.reduceMotion) 1f else 0f) }
    LaunchedEffect(Unit) { delay(350); shown.animateTo(1f, spring(0.7f, 400f)) }
    val diameter = max(34f, min(rect.width, rect.height) * 0.62f)
    Canvas(Modifier.centerAt(rect.midX, rect.midY).requiredSize(diameter.dp).graphicsLayer {
        val scale = 1.6f - 0.6f * shown.value; scaleX = scale; scaleY = scale; alpha = shown.value.coerceIn(0f, 1f)
    }) {
        val r = size.minDimension / 2
        drawCircle(color.copy(alpha = 0.35f), r, style = Stroke(7.dp.toPx()))
        drawCircle(color, r, style = Stroke(2.2.dp.toPx()))
        drawCircle(Color.White.copy(alpha = 0.8f), r * (1 - 0.36f), style = Stroke(0.8.dp.toPx()))
        for (quarter in 0 until 4) rotate(quarter * 90f) {
            drawRoundRect(color, Offset(center.x - 1.3.dp.toPx(), center.y - r - size.minDimension * 0.1f), Size(2.6.dp.toPx(), size.minDimension * 0.2f),
                CornerRadius(1.3.dp.toPx()))
        }
    }
}

/** The slim caption over the midline that says what the table wants ("Choose attackers.", "Pay {1}{R}"). */
@Composable
fun ArenaPromptCaption(text: String, modifier: Modifier = Modifier) {
    GameRulesText(text, modifier.semantics { testTag = "board.arena.caption" }, symbolSize = 15.dp,
        style = ArenaMenuStyle.font(15f, SfWeight.semibold).arenaShadow(4f, 1f).copy(textAlign = TextAlign.Center), color = TavernPalette.parchment, maxLines = 3)
}

/** Floating mana the reference's way: plain mana symbols by your portrait; a symbol takes a tap while you pay. */
@Composable
fun ArenaFloatingMana(pool: ManaPool?, payable: Set<String>, spend: (String) -> Unit, modifier: Modifier = Modifier) {
    val values = listOf("W" to (pool?.W ?: 0), "U" to (pool?.U ?: 0), "B" to (pool?.B ?: 0), "R" to (pool?.R ?: 0), "G" to (pool?.G ?: 0), "C" to (pool?.C ?: 0))
        .filter { it.second > 0 }
    Row(modifier.height(28.dp).background(Color.Black.copy(alpha = 0.45f), CircleShape).border(1.dp, TavernPalette.brass.copy(alpha = 0.55f), CircleShape)
        .padding(horizontal = 5.dp), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
        for ((symbol, count) in values) {
            val canPay = symbol in payable
            Box(Modifier.then(if (canPay) Modifier.defaultMinSize(minHeight = 44.dp).clickable { spend(symbol) }
                .semantics { contentDescription = "Spend floating $symbol mana, $count available"; testTag = "board.mana.spend.$symbol" }
                else Modifier.semantics { contentDescription = "$count floating $symbol mana" }).padding(horizontal = if (canPay) 4.dp else 2.dp),
                contentAlignment = Alignment.Center) {
                if (canPay) Box(Modifier.requiredSize(26.dp, 24.dp).border(1.2.dp, TavernPalette.ember.copy(alpha = 0.8f), CircleShape))
                ManaSymbolView(symbol, 20.dp)
                if (count > 1) Text("$count", Modifier.align(Alignment.BottomEnd).offset(5.dp, 4.dp).background(Color.Black.copy(alpha = 0.85f), CircleShape)
                    .padding(horizontal = 3.dp), color = Color.White, style = ArenaMenuStyle.font(10f, SfWeight.black).copy(fontFeatureSettings = "tnum"))
            }
        }
    }
}

/** Combat on the Arena table: red arcs from attackers to what they attack, gold from blockers to the attacker they hold. */
@Composable
fun ArenaCombatArrows(snapshot: GameSnapshot, previewArrows: List<CombatArrow>, bounds: Map<String, BoardRect>, opponentID: String, modifier: Modifier = Modifier) {
    val arrows = CombatArrowModel.arrows(snapshot.xmage?.combat ?: emptyList(), previewArrows)
    if (arrows.isEmpty()) return
    fun playerRect(id: String, kind: String?): BoardRect? {
        if (kind != null && kind.lowercase() != "player") return null
        if (id in CombatPlayerIdentity.ids(snapshot.seatID, snapshot)) return bounds[TavernSeatAnchor.bottom]
        if (id in CombatPlayerIdentity.ids(opponentID, snapshot)) return bounds[TavernSeatAnchor.top]
        return null
    }
    Canvas(modifier.fillMaxSize()) {
        for (arrow in arrows) {
            val from = bounds[arrow.fromId] ?: continue
            val to = bounds[arrow.toId] ?: playerRect(arrow.toId, arrow.toKind) ?: continue
            val color = when (arrow.kind) {
                CombatArrowKind.ATTACK -> rgb(1.0, 0.32, 0.2); CombatArrowKind.BLOCKED_ATTACK -> Color.Gray
                CombatArrowKind.BLOCK, CombatArrowKind.PREVIEW_BLOCK -> rgb(1.0, 0.82, 0.45); CombatArrowKind.PREVIEW_ATTACK -> MagicPalette.warningAmber
            }
            val preview = arrow.kind == CombatArrowKind.PREVIEW_ATTACK || arrow.kind == CombatArrowKind.PREVIEW_BLOCK
            val start = Offset(from.midX.dp.toPx(), from.midY.dp.toPx()); val end = Offset(to.midX.dp.toPx(), to.midY.dp.toPx())
            val lift = min(60.dp.toPx(), hypot(end.x - start.x, end.y - start.y) * 0.25f)
            val control = Offset((start.x + end.x) / 2, min(start.y, end.y) - lift)
            val path = Path().apply { moveTo(start.x, start.y); quadraticTo(control.x, control.y, end.x, end.y) }
            drawPath(path, color.copy(alpha = 0.35f), style = Stroke((if (preview) 6 else 9).dp.toPx(), cap = StrokeCap.Round))
            drawPath(path, color.copy(alpha = if (preview) 0.6f else 0.95f), style = Stroke((if (preview) 2 else 3).dp.toPx(), cap = StrokeCap.Round,
                pathEffect = if (preview) androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx())) else null))
            val angle = atan2(end.y - control.y, end.x - control.x)
            val head = 12.dp.toPx()
            for (side in listOf(-1, 1)) {
                val a = angle + side * PI.toFloat() / 6
                drawLine(color, end, Offset(end.x - head * cos(a), end.y - head * sin(a)), 3.dp.toPx(), StrokeCap.Round)
            }
        }
    }
}

/** A colour matrix: the tapped Arena tile's grey (grayscale 0.75 and a 0.64 multiply, the prototype's), so dark art still reads. */
fun Modifier.arenaTappedGrey(active: Boolean): Modifier = if (!active) this else drawWithContent {
    val matrix = ColorMatrix().apply { setToSaturation(0.25f) }
    val values = matrix.values
    for (row in 0 until 3) for (column in 0 until 4) values[row * 5 + column] *= 0.64f
    val paint = Paint().apply { colorFilter = ColorFilter.colorMatrix(matrix) }
    drawIntoCanvas { canvas ->
        canvas.saveLayer(Rect(-size.width, -size.height, size.width * 2, size.height * 2), paint)
        drawContent()
        canvas.restore()
    }
}

