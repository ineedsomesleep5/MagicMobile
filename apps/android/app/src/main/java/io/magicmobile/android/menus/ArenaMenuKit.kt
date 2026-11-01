package io.magicmobile.android.menus

import android.graphics.BlurMaskFilter
import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import io.magicmobile.android.game.ArenaMenuTab
import io.magicmobile.android.game.ArenaMenuType
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.ranked.RankEmblem
import io.magicmobile.android.ui.BoardMotionFlags
import io.magicmobile.android.ui.BrandBackdrop
import io.magicmobile.android.ui.BrandMark
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LocalBrandAmbientMotion
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.colorAdjust
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.shineSweep

/*
 * Port of Menus/ArenaMenuKit.swift: the menus in MTG Arena's layout (Caleb, 2026-10-22: every page follows Arena, nothing
 * carried over), drawn in the Arena board's glass, gold hairline and plaques over the 3D tavern room
 * (docs/ARENA_STYLE.md, "Menus"). Every menu screen builds on these pieces.
 */

/** True over the menus (iOS `\.arenaBoard`): the tavern kit's buttons, toggles, sliders and panels draw Arena's look. A game sets its own board's. */
val LocalArenaBoard = compositionLocalOf { false }

/** The menu shell draws the room under its pages; a page shown inside it leaves its own backdrop out (`\.arenaMenuBackdrop`). */
val LocalArenaMenuBackdrop = compositionLocalOf { false }

/** The Arena board's smoked glass (ArenaBoardViews.swift `ArenaGlass`). */
object ArenaGlass {
    val top = rgb(0.10, 0.11, 0.14)
    val bottom = rgb(0.04, 0.045, 0.06)
    val hairlineTop = rgb(0.96, 0.80, 0.46).copy(alpha = 0.85f)
    val hairlineBottom = rgb(0.55, 0.38, 0.14).copy(alpha = 0.7f)
    val hairline: Brush get() = Brush.verticalGradient(listOf(hairlineTop, hairlineBottom))
    val text = rgb(0.95, 0.92, 0.86)
}

object ArenaMenuStyle {
    val gold = rgb(0.98, 0.84, 0.52)
    val text = ArenaGlass.text
    val dim = ArenaGlass.text.copy(alpha = 0.66f)
    val ember = rgb(1.0, 0.50, 0.30)
    /** The Play panel's lit seam. */
    val seam = rgb(1.0, 0.52, 0.20)
    /** A win in gold, a loss in a muted rose (no web green and red). */
    val win = rgb(0.98, 0.84, 0.52)
    val loss = rgb(0.84, 0.56, 0.53)
    /** Engraved metal for the chosen emblem; a dull pewter for the rest. */
    val metal: Brush get() = Brush.verticalGradient(listOf(rgb(1.0, 0.95, 0.78), rgb(0.94, 0.75, 0.42), rgb(0.60, 0.39, 0.14)))
    val pewter: Brush get() = Brush.verticalGradient(listOf(rgb(0.90, 0.87, 0.80), rgb(0.58, 0.54, 0.48)))
    /** The chosen segment, row diamond or tab fill. */
    val goldFill: Brush get() = Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.56), rgb(0.80, 0.56, 0.22)))
    val barHeight = 46.dp
    /** The call to action's orange (Arena's Play), top to bottom. */
    val orange: Brush get() = Brush.verticalGradient(0f to rgb(1.0, 0.70, 0.29), 0.48f to rgb(0.957, 0.478, 0.11), 1f to rgb(0.79, 0.26, 0.05))
    /** The thin warm rim around the orange. */
    val orangeRim = rgb(1.0, 0.84, 0.59).copy(alpha = 0.9f)
    /** Dark ink on gold (a chosen gem or tile). */
    val inkOnGold = rgb(0.11, 0.06, 0.03)

    /**
     * Arena's type: the serif display face for titles, names on plates and big numbers; a clean sans for labels, rows,
     * captions and body (Caleb chose Arena's mix, 2026-10-22). From 17 pt up a size is a title; [title] sets a smaller
     * serif heading on purpose.
     */
    fun font(size: Float, weight: FontWeight = SfWeight.semibold): TextStyle =
        if (ArenaMenuType.isTitle(size)) title(size, weight) else sf(size, weight)

    fun title(size: Float, weight: FontWeight = SfWeight.bold): TextStyle = sf(size, weight, SfDesign.SERIF)
}

/**
 * The phone's safe area for Arena's full-table layers (iOS `ArenaSafeArea`). Their dim reaches every edge, so their content
 * must clear the camera cutout and the gesture bar itself: a centred title starts at [top], and in landscape a row of cards
 * keeps [side] clear of the cutout. The Arena board measures it once and passes it down ([LocalArenaSafeArea]); a layer
 * never reads the window's insets for padding on its own (LESSONS 2026-10-22).
 */
data class ArenaSafeArea(val top: Dp = 0.dp, val bottom: Dp = 0.dp, val leading: Dp = 0.dp, val trailing: Dp = 0.dp) {
    /** Top padding for a layer's title: below the cutout, and never less than [minimum]. */
    fun top(minimum: Dp): Dp = maxOf(minimum, top + 8.dp)

    /** Room kept on both sides in landscape, where the cutout sits at one of them. */
    val side: Dp get() = maxOf(leading, trailing)
}

/** The Arena board's measured safe area (iOS `\.arenaSafeArea`). */
val LocalArenaSafeArea = compositionLocalOf { ArenaSafeArea() }

/** A black text shadow (`.shadow(color: .black, radius:)`). */
fun TextStyle.arenaShadow(radius: Float = 2f, alpha: Float = 1f, y: Float = 0f): TextStyle =
    copy(shadow = Shadow(Color.Black.copy(alpha = alpha), Offset(0f, y), radius * 2f))

/** A blurred rounded rectangle behind content (a coloured `.shadow` or a blurred fill). */
internal fun DrawScope.blurredRoundRect(color: Color, blur: Float, rect: Rect, corner: Float) {
    if (color.alpha <= 0f) return
    drawIntoCanvas { canvas ->
        val paint = Paint()
        paint.asFrameworkPaint().apply {
            this.color = color.toArgb()
            maskFilter = BlurMaskFilter(blur.coerceAtLeast(0.5f), BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawRoundRect(rect.left, rect.top, rect.right, rect.bottom, corner, corner, paint)
    }
}

/** Gold small capitals over a section or a value ("RANKED · GOLD II"). Read in normal case. */
@Composable
fun ArenaCaps(text: String, size: Float = 10.5f, modifier: Modifier = Modifier) {
    val style = ArenaMenuStyle.font(size, SfWeight.heavy)
    FitText(text.uppercase(), style.copy(letterSpacing = (style.letterSpacing.value + 0.16f).em),
        modifier.semantics { contentDescription = text }, color = ArenaMenuStyle.gold, maxLines = 1, minimumScale = 0.75f)
}

/** A glyph painted with a brush (engraved metal), with the black emboss under it. */
@Composable
fun ArenaGlyph(symbol: String, size: Dp, brush: Brush, modifier: Modifier = Modifier, emboss: Boolean = true) {
    Box(modifier, contentAlignment = Alignment.Center) {
        if (emboss) SfImage(symbol, Color.Black.copy(alpha = 0.9f), size, Modifier.offset(y = 1.dp))
        SfImage(symbol, Color.White, size, Modifier
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent { drawContent(); drawRect(brush, blendMode = BlendMode.SrcIn) })
    }
}

/** A menu icon as an engraved metal emblem, lit gold when chosen (not a thin system glyph). */
@Composable
fun ArenaEmblem(symbol: String, size: Dp = 19.dp, lit: Boolean = false, modifier: Modifier = Modifier) {
    Box(modifier.alpha(if (lit) 1f else 0.82f).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        if (lit) Box(Modifier.requiredSize(size * 1.2f).drawBehind {
            drawCircle(Brush.radialGradient(listOf(ArenaMenuStyle.ember.copy(alpha = 0.45f), Color.Transparent), radius = this.size.minDimension))
        })
        ArenaGlyph(symbol, size, if (lit) ArenaMenuStyle.metal else ArenaMenuStyle.pewter)
    }
}

/** Something new waiting: a small lit diamond under an icon, where Arena puts it (no count bubble). */
@Composable
fun ArenaUnreadPip(modifier: Modifier = Modifier) {
    Box(modifier.size(6.5.dp).rotate(45f).glow(ArenaMenuStyle.ember, 3.dp, 1.dp)
        .background(Brush.verticalGradient(listOf(rgb(1.0, 0.82, 0.5), ArenaMenuStyle.ember))))
}

// MARK: - Top bar

/**
 * Arena's top bar: the mark, the tabs (labels under the emblems), and on the right your rank, messages, news, downloads and
 * the gear. Portrait keeps the tabs, messages and the gear; news and downloads move down onto the home page. The bar's
 * glass runs up under the status bar.
 */
@Composable
fun ArenaTopBar(selected: ArenaMenuTab?, compact: Boolean, select: (ArenaMenuTab) -> Unit, settings: () -> Unit, modifier: Modifier = Modifier,
                rank: RankPosition? = null, openRank: (() -> Unit)? = null, unread: Boolean = false, messages: (() -> Unit)? = null,
                updates: (() -> Unit)? = null, downloads: (() -> Unit)? = null, lit: String? = null,
                /** Set while placing, in place of the rank's own title. */
                rankTitle: String? = null) {
    Column(modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth()) {
            ArenaTopBarBackground(Modifier.matchParentSize())
            Column {
                Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                BoxWithConstraints(Modifier.fillMaxWidth().height(ArenaMenuStyle.barHeight)
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal))) {
                // Upright, phones narrower than the iPhone share the room left beside the mark and the icons among the tabs.
                val icons = 1 + (if (messages != null) 1 else 0)
                val tabWidth = if (compact) ((maxWidth - 44.dp - 40.dp * icons - 4.dp) / 5).coerceIn(44.dp, 56.dp) else 64.dp
                Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(if (compact) 44.dp else 52.dp).fillMaxHeight().testTag("menu.brand")
                        .semantics { contentDescription = "MagicMobile"; role = Role.Image }, contentAlignment = Alignment.Center) {
                        BrandMark(if (compact) 26.dp else 28.dp, glint = false)
                    }
                    ArenaMenuTab.entries.forEach { tab -> TopBarTab(tab, selected == tab, compact, tabWidth, select) }
                    Spacer(Modifier.weight(1f).widthIn(min = 4.dp))
                    if (!compact && rank != null) {
                        BrandPressable({ GameAudio.play(GameSound.UI_OPEN); openRank?.invoke() },
                            Modifier.padding(end = 4.dp).defaultMinSize(minHeight = 44.dp).testTag("menu.rank")
                                .semantics(mergeDescendants = true) { contentDescription = "Your rank, ${rankTitle ?: rank.title}" }) {
                            Row(Modifier.height(28.dp).background(Color.White.copy(alpha = 0.05f), CircleShape)
                                .border(0.8.dp, ArenaGlass.hairline, CircleShape).padding(horizontal = 10.dp),
                                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                RankEmblem(rank.tier, 22.dp, Modifier.colorAdjust(saturation = if (rankTitle != null) 0f else 1f))
                                Text(rankTitle ?: rank.title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(12f, SfWeight.bold), maxLines = 1)
                            }
                        }
                    }
                    messages?.let { BarIcon("envelope.fill", "Friends and messages", "menu.friends", compact, lit, it, unread) }
                    if (!compact) updates?.let { BarIcon("newspaper.fill", "Updates", "menu.updates", compact, lit, it) }
                    if (!compact) downloads?.let { BarIcon("arrow.down.circle.fill", "Downloads", "menu.downloads", compact, lit, it) }
                    BarIcon("gearshape.fill", "Settings", "menu.settings", compact, lit, settings)
                }
                }
            }
        }
    }
}

@Composable
private fun RowScope.TopBarTab(tab: ArenaMenuTab, lit: Boolean, compact: Boolean, width: Dp, select: (ArenaMenuTab) -> Unit) {
    BrandPressable({ if (!lit || tab == ArenaMenuTab.LEARN) { GameAudio.play(GameSound.UI_TAP); select(tab) } },
        Modifier.width(width).fillMaxHeight().testTag(tab.identifier)
            .semantics(mergeDescendants = true) { contentDescription = tab.title; selected = lit }) {
        Box(Modifier.fillMaxSize().then(if (lit) Modifier.background(Brush.verticalGradient(listOf(Color.Transparent, ArenaMenuStyle.ember.copy(alpha = 0.18f))))
            else Modifier)) {
            // Every emblem in the same box and every label on one line, so the labels share a baseline.
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                ArenaEmblem(tab.symbol, 17.dp, lit, Modifier.size(26.dp, 22.dp))
                FitText(tab.title, ArenaMenuStyle.font(if (compact) 9f else 10f, SfWeight.semibold), Modifier.height(12.dp),
                    color = if (lit) Color.White else ArenaMenuStyle.text.copy(alpha = 0.7f), minimumScale = 0.75f)
            }
            if (lit) Box(Modifier.align(Alignment.BottomCenter).padding(horizontal = 9.dp).fillMaxWidth().height(3.dp)
                .glow(ArenaMenuStyle.ember, 6.dp, 2.dp).background(ArenaMenuStyle.ember, CircleShape))
        }
    }
}

@Composable
private fun BarIcon(symbol: String, label: String, identifier: String, compact: Boolean, lit: String?, action: () -> Unit, unread: Boolean = false) {
    BrandPressable({ GameAudio.play(GameSound.UI_OPEN); action() },
        Modifier.width(if (compact) 40.dp else 38.dp).fillMaxHeight().testTag(identifier)
            .semantics(mergeDescendants = true) { contentDescription = label; if (unread) stateDescription = "New" }) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            ArenaEmblem(symbol, 17.dp, lit == identifier)
            ArenaTabBar(lit == identifier, Modifier.align(Alignment.BottomCenter).padding(horizontal = 8.dp))
            if (unread) ArenaUnreadPip(Modifier.align(Alignment.BottomCenter).padding(bottom = 5.dp))
        }
    }
}

/** The bar's backing: near-black glass under the status bar, edged in the gold hairline. */
@Composable
fun ArenaTopBarBackground(modifier: Modifier = Modifier) {
    Box(modifier.drawBehind {
        blurredRoundRect(Color.Black.copy(alpha = 0.55f), 8.dp.toPx(), Rect(0f, 3.dp.toPx(), size.width, size.height + 3.dp.toPx()), 0f)
        drawRect(Brush.verticalGradient(listOf(rgb(0.055, 0.052, 0.065).copy(alpha = 0.97f), rgb(0.035, 0.035, 0.045).copy(alpha = 0.94f))))
        drawRect(ArenaGlass.hairline, Offset(0f, size.height - 1.dp.toPx()), androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx()), alpha = 0.75f)
    })
}

/** A round glass emblem button with a caption, for the home page's corner (friends, and in portrait news and downloads). */
@Composable
fun ArenaCornerButton(symbol: String, title: String, identifier: String, action: () -> Unit, badge: String? = null, unread: Boolean = false) {
    BrandPressable({ GameAudio.play(GameSound.UI_OPEN); action() },
        Modifier.defaultMinSize(44.dp, 44.dp).testTag(identifier).semantics(mergeDescendants = true) {
            contentDescription = title; badge?.let { stateDescription = it }
        }) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(38.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape),
                contentAlignment = Alignment.Center) {
                ArenaEmblem(symbol, 18.dp, unread)
                if (unread) ArenaUnreadPip(Modifier.align(Alignment.BottomCenter).offset(y = 3.dp))
            }
            badge?.let {
                Text(it, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.bold).copy(fontFeatureSettings = "tnum").arenaShadow())
            }
        }
    }
}

// MARK: - Plaques

/**
 * What an Arena button asks for: the call to action, the other choice, a destructive one, a word on the table with no pill
 * (the opponent's turn), or Arena's blue pill beside the orange one (Mulligan beside Keep).
 */
enum class ArenaButtonKind { PRIMARY, SECONDARY, DANGER, QUIET, COOL }

/** The text style an Arena button's label takes (set by the face). */
val LocalArenaButtonTextStyle = compositionLocalOf { ArenaMenuStyle.title(16f) }

/** A button's word in the face's type, shrinking to fit. */
@Composable
fun ArenaButtonText(text: String, modifier: Modifier = Modifier) {
    FitText(text, LocalArenaButtonTextStyle.current, modifier, color = LocalContentColor.current, maxLines = 1, minimumScale = 0.6f)
}

private fun arenaFill(kind: ArenaButtonKind): Brush = when (kind) {
    ArenaButtonKind.PRIMARY -> ArenaMenuStyle.orange
    ArenaButtonKind.DANGER -> Brush.verticalGradient(listOf(rgb(0.78, 0.22, 0.18), rgb(0.49, 0.09, 0.07)))
    ArenaButtonKind.COOL -> Brush.verticalGradient(0f to rgb(0.55, 0.60, 1.0), 0.5f to rgb(0.31, 0.27, 0.86), 1f to rgb(0.19, 0.12, 0.58))
    ArenaButtonKind.SECONDARY, ArenaButtonKind.QUIET ->
        Brush.verticalGradient(listOf(rgb(0.16, 0.17, 0.20).copy(alpha = 0.92f), rgb(0.08, 0.085, 0.10).copy(alpha = 0.94f)))
}

private fun arenaRim(kind: ArenaButtonKind): Color = when (kind) {
    ArenaButtonKind.PRIMARY -> ArenaMenuStyle.orangeRim
    ArenaButtonKind.DANGER -> rgb(1.0, 0.66, 0.58).copy(alpha = 0.7f)
    ArenaButtonKind.COOL -> rgb(0.76, 0.80, 1.0).copy(alpha = 0.85f)
    else -> rgb(1.0, 0.9, 0.75).copy(alpha = 0.5f)
}

/**
 * Arena's button face (Caleb chose option A, 2026-10-22): the call to action is an orange pill with a thin warm rim, a lit top
 * edge and a soft glow; the other choice is a dark glass pill edged in a pale line; danger is a deep red pill. No brass,
 * rivets, leather or stitching (those stay with the Hearth board). `fills`: the pill fills the frame the caller gives, `inset`
 * inside it top and bottom; otherwise it hugs its word with `inset` above and below.
 */
@Composable
fun ArenaButtonFace(kind: ArenaButtonKind, style: TextStyle, pressed: Boolean, modifier: Modifier = Modifier, enabled: Boolean = true,
                    fills: Boolean = true, inset: Dp = 0.dp, glow: Float = 1f, shine: Boolean = false, content: @Composable RowScope.() -> Unit) {
    val reduce = BoardMotionFlags.reduceMotion
    val ambient = LocalBrandAmbientMotion.current
    val lit = kind == ArenaButtonKind.PRIMARY && enabled
    val edge = if (fills) inset else 0.dp
    val scale by animateFloatAsState(if (pressed && !reduce) 0.97f else 1f, tween(if (reduce) 0 else 120), label = "arenaPress")
    val ink = if (kind == ArenaButtonKind.SECONDARY || kind == ArenaButtonKind.QUIET) rgb(0.95, 0.91, 0.85) else Color.White
    val density = LocalDensity.current
    val shadow = Shadow(if (kind == ArenaButtonKind.PRIMARY) rgb(0.35, 0.1, 0.0).copy(alpha = 0.75f) else Color.Black.copy(alpha = 0.6f),
        Offset(0f, with(density) { 1.dp.toPx() }), with(density) { 3.dp.toPx() })
    Box(modifier.graphicsLayer { scaleX = scale; scaleY = scale }
        .colorAdjust(if (enabled) 1f else 0.15f, if (!enabled) -0.15f else if (pressed) 0.08f else 0f)
        .drawBehind {
            if (lit && glow > 0f) {
                val e = (edge + 2.dp).toPx()
                val rect = Rect(0f, e, size.width, size.height - e)
                blurredRoundRect(rgb(1.0, 0.47, 0.12).copy(alpha = (0.55f * glow).coerceIn(0f, 1f)), 10.dp.toPx(), rect, rect.height / 2)
            }
        }) {
        if (kind != ArenaButtonKind.QUIET) {
            Box(Modifier.matchParentSize().padding(vertical = edge).clip(CircleShape).background(arenaFill(kind))
                .then(if (kind == ArenaButtonKind.PRIMARY) Modifier.background(Brush.verticalGradient(0.5f to Color.Transparent,
                    1f to rgb(0.43, 0.08, 0.0).copy(alpha = 0.35f))) else Modifier)
                .then(if (shine && lit && !reduce && ambient) Modifier.shineSweep() else Modifier)
                .border(if (kind == ArenaButtonKind.SECONDARY) 1.dp else 1.5.dp, arenaRim(kind), CircleShape))
            // The top edge catches the light.
            Box(Modifier.matchParentSize().padding(vertical = edge).padding(1.5.dp)
                .border(1.dp, Brush.verticalGradient(0f to Color.White.copy(alpha = if (kind == ArenaButtonKind.SECONDARY) 0.14f else 0.55f), 0.5f to Color.Transparent), CircleShape))
        }
        Row((if (fills) Modifier.matchParentSize() else Modifier).padding(horizontal = 16.dp, vertical = if (fills) 0.dp else inset),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            CompositionLocalProvider(LocalContentColor provides ink, LocalArenaButtonTextStyle provides style.copy(shadow = shadow)) { content() }
        }
    }
}

/** A pressable frame for an Arena face: plays its press sound, reports `pressed`, carries the role and tag. */
@Composable
private fun ArenaPressFrame(onClick: () -> Unit, modifier: Modifier, enabled: Boolean, sound: GameSound?, label: String?, identifier: String?,
                            content: @Composable BoxScope.(Boolean) -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    LaunchedEffect(pressed) { if (pressed && sound != null) GameAudio.play(sound) }
    Box(modifier.then(if (identifier != null) Modifier.testTag(identifier) else Modifier)
        .clickable(interaction, null, enabled, role = Role.Button, onClick = onClick)
        .then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier), contentAlignment = Alignment.Center) { content(pressed) }
}

/** Arena's button for menus and panels, in place of the Hearth board's tavern plaque (same options). */
@Composable
fun ArenaButton(onClick: () -> Unit, modifier: Modifier = Modifier, kind: ArenaButtonKind = ArenaButtonKind.PRIMARY, compact: Boolean = false,
                fontSize: Float? = null, fullWidth: Boolean = false, enabled: Boolean = true, label: String? = null, identifier: String? = null,
                content: @Composable RowScope.() -> Unit) {
    ArenaPressFrame(onClick, modifier.defaultMinSize(minWidth = if (compact) 64.dp else 96.dp).then(if (fullWidth) Modifier.fillMaxWidth() else Modifier).height(44.dp),
        enabled, if (kind == ArenaButtonKind.SECONDARY) GameSound.UI_BACK else GameSound.UI_CONFIRM, label, identifier) { pressed ->
        ArenaButtonFace(kind, ArenaMenuStyle.title(fontSize ?: if (compact) 14f else 16f, if (kind == ArenaButtonKind.SECONDARY) SfWeight.semibold else SfWeight.bold),
            pressed, if (fullWidth) Modifier.fillMaxSize() else Modifier, enabled, fills = fullWidth,
            inset = if (fullWidth) 2.dp else if (compact) 7.dp else 10.dp, glow = if (compact) 0.6f else 1f, content = content)
    }
}

/** The Play plaque: Arena's orange pill with its glow and a slow sweep of light, filling the frame the caller gives. `cancel` is the dark pill that stands in while a search runs. */
@Composable
fun ArenaPlayButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, cancel: Boolean = false, fontSize: Float = 21f,
                    enabled: Boolean = true, identifier: String? = null) {
    ArenaPressFrame(onClick, modifier, enabled, if (cancel) GameSound.UI_BACK else GameSound.UI_CONFIRM, title, identifier) { pressed ->
        ArenaButtonFace(if (cancel) ArenaButtonKind.SECONDARY else ArenaButtonKind.PRIMARY, ArenaMenuStyle.title(fontSize, SfWeight.bold), pressed,
            Modifier.fillMaxSize(), enabled, shine = true) { ArenaButtonText(title) }
    }
}

/** A small pill (filters, quiet links), the reference's dropdown chips: dark glass, orange when lit. */
@Composable
fun ArenaPillButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, lit: Boolean = false, enabled: Boolean = true,
                    identifier: String? = null, symbol: String? = null) {
    ArenaPressFrame(onClick, modifier.height(44.dp), enabled, null, title, identifier) { pressed ->
        ArenaButtonFace(if (lit) ArenaButtonKind.PRIMARY else ArenaButtonKind.SECONDARY, ArenaMenuStyle.font(12.5f, SfWeight.bold), pressed,
            enabled = enabled, fills = false, inset = 6.dp, glow = 0.4f) {
            symbol?.let { SfImage(it, LocalContentColor.current, 12.dp) }
            ArenaButtonText(title)
        }
    }
}

/** The round close button of a glass panel. */
@Composable
fun ArenaCloseButton(action: () -> Unit, modifier: Modifier = Modifier, identifier: String = "arena.close", enabled: Boolean = true) {
    BrandPressable({ GameAudio.play(GameSound.UI_BACK); action() }, modifier.size(44.dp).alpha(if (enabled) 1f else 0.4f).testTag(identifier)
        .semantics { contentDescription = "Close"; role = Role.Button }, enabled = enabled) {
        Box(Modifier.size(30.dp).border(1.5.dp, ArenaMenuStyle.text.copy(alpha = 0.7f), CircleShape), contentAlignment = Alignment.Center) {
            SfImage("xmark", ArenaMenuStyle.text, 12.dp)
        }
    }
}

// MARK: - Choices

/**
 * Arena's tab strip (its Play blade, its Decks filters, its social panel): the words in a row over a faint hairline, the
 * chosen one bright with a glowing gold bar under it. No pills.
 */
@Composable
fun <T> ArenaSegmented(options: List<Pair<String, T>>, selection: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier,
                       identifier: String? = null, stretch: Boolean = false) {
    Box(modifier) {
        Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(bottom = 2.dp).height(1.dp).alpha(0.35f).background(ArenaGlass.hairline))
        Row(Modifier.then(if (stretch) Modifier.fillMaxWidth() else Modifier), horizontalArrangement = Arrangement.spacedBy(if (stretch) 0.dp else 18.dp)) {
            options.forEach { (label, value) ->
                val on = value == selection
                BrandPressable({ GameAudio.play(GameSound.UI_TAP); onSelect(value) },
                    (if (stretch) Modifier.weight(1f) else Modifier).defaultMinSize(minWidth = 32.dp, minHeight = 44.dp)
                        .testTag(identifier?.let { "$it.$label" } ?: label).semantics { selected = on }) {
                    Box(Modifier.height(40.dp).padding(horizontal = 4.dp), contentAlignment = Alignment.Center) {
                        FitText(label, ArenaMenuStyle.font(14f, if (on) SfWeight.bold else SfWeight.semibold),
                            color = if (on) ArenaMenuStyle.text else ArenaMenuStyle.dim, minimumScale = 0.7f)
                        ArenaTabBar(on, Modifier.align(Alignment.BottomCenter))
                    }
                }
            }
        }
    }
}

/** The glowing gold bar under a chosen tab. */
@Composable
fun ArenaTabBar(on: Boolean, modifier: Modifier = Modifier) {
    val alpha by animateFloatAsState(if (on) 1f else 0f, tween(if (BoardMotionFlags.reduceMotion) 0 else 160), label = "tabBar")
    Box(modifier.offset(y = (-1).dp).padding(horizontal = 6.dp).fillMaxWidth().height(3.dp).alpha(alpha)
        .glow(ArenaMenuStyle.gold.copy(alpha = 0.9f), 5.dp, 2.dp).background(ArenaMenuStyle.gold, CircleShape))
}

/** A diamond: lit gold when chosen, an outline otherwise. */
@Composable
fun ArenaDiamond(selected: Boolean, modifier: Modifier = Modifier, size: Dp = 9.dp) {
    Box(modifier.width(14.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size(size).rotate(45f)
            .glow(if (selected) rgb(1.0, 0.6, 0.24) else Color.Transparent, 4.dp, 1.dp)
            .then(if (selected) Modifier.background(Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.56), rgb(1.0, 0.6, 0.24)))) else Modifier)
            .border(1.5.dp, if (selected) rgb(1.0, 0.88, 0.56) else ArenaMenuStyle.gold.copy(alpha = 0.6f)))
    }
}

/** One option in a panel's list: a diamond lit when chosen, the title, and a value on the right. */
@Composable
fun ArenaOptionRow(title: String, action: () -> Unit, modifier: Modifier = Modifier, detail: String? = null, value: String? = null,
                   selected: Boolean? = null, chevron: Boolean = false, identifier: String? = null, enabled: Boolean = true) {
    BrandPressable({ GameAudio.play(GameSound.UI_TAP); action() }, modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.5f)
        .testTag(identifier ?: title).semantics(mergeDescendants = true) { if (selected == true) this.selected = true }, enabled = enabled) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = if (detail == null) 38.dp else 46.dp)
            .drawBehind { drawRect(Color.White.copy(alpha = 0.07f), size = androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx())) }
            .padding(4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            selected?.let { ArenaDiamond(it) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                FitText(title, ArenaMenuStyle.font(14f, if (selected == true) SfWeight.bold else SfWeight.medium),
                    color = if (selected == false) ArenaMenuStyle.dim else ArenaMenuStyle.text, minimumScale = 0.8f)
                detail?.let { FitText(it, ArenaMenuStyle.font(11f, SfWeight.medium), color = ArenaMenuStyle.dim, minimumScale = 0.85f) }
            }
            value?.let { Text(it, color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(13f, SfWeight.bold), maxLines = 1) }
            if (chevron) SfImage("chevron.right", ArenaMenuStyle.gold.copy(alpha = 0.8f), 11.dp)
        }
    }
}

/**
 * Arena's Options checkbox (options-gameplay-1): off a dim diamond, on an orange tick edged in white with an ember glow; the
 * title greyer while off. The explanation is TalkBack's only (AGENTS.md: no secondary labels).
 */
@Composable
fun ArenaCheckbox(title: String, isOn: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, subtitle: String? = null,
                  identifier: String? = null, enabled: Boolean = true) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.5f)
        .clickable(remember { MutableInteractionSource() }, null, enabled, role = Role.Checkbox) { GameAudio.play(GameSound.UI_TOGGLE); onChange(!isOn) }
        .testTag(identifier ?: title)
        .semantics(mergeDescendants = true) {
            contentDescription = subtitle?.let { "$title. $it" } ?: title
            toggleableState = ToggleableState(isOn)
        }, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
            if (isOn) {
                Box(Modifier.size(22.dp).drawBehind {
                    drawCircle(Brush.radialGradient(listOf(ArenaMenuStyle.ember.copy(alpha = 0.55f), Color.Transparent), radius = size.minDimension * 0.7f))
                })
                SfImage("checkmark", Color.White.copy(alpha = 0.9f), 19.dp)
                ArenaGlyph("checkmark", 15.dp, Brush.verticalGradient(listOf(rgb(1.0, 0.66, 0.32), rgb(0.86, 0.34, 0.10))), emboss = false)
            } else {
                Box(Modifier.size(12.dp).rotate(45f).background(Color.White.copy(alpha = 0.08f)).border(1.dp, Color.White.copy(alpha = 0.35f)))
            }
        }
        FitText(title, ArenaMenuStyle.font(15f, SfWeight.semibold), Modifier.weight(1f), color = ArenaMenuStyle.text.copy(alpha = if (isOn) 1f else 0.62f),
            maxLines = 2, minimumScale = 0.85f)
    }
}

/** A level as Arena's thin line: an ember fill and a gold diamond knob. A touch puts the knob under the finger. */
@Composable
fun ArenaSlider(value: Float, onChange: (Float) -> Unit, label: String, modifier: Modifier = Modifier, range: ClosedFloatingPointRange<Float> = 0f..1f,
                identifier: String? = null, valueText: String? = null) {
    val span = (range.endInclusive - range.start).coerceAtLeast(0.0001f)
    val fraction = ((value - range.start) / span).coerceIn(0f, 1f)
    val latest by rememberUpdatedState(onChange)
    BoxWithConstraints(modifier.fillMaxWidth().height(32.dp).testTag(identifier ?: label).semantics {
        contentDescription = label
        stateDescription = valueText ?: "${(fraction * 100).toInt()} percent"
        progressBarRangeInfo = ProgressBarRangeInfo(value, range)
        setProgress { target -> latest(target.coerceIn(range.start, range.endInclusive)); true }
    }) {
        val knob = 16.dp
        val knobPx = with(LocalDensity.current) { knob.toPx() }
        val travelPx = maxOf(constraints.maxWidth - knobPx, 1f)
        val travel = with(LocalDensity.current) { travelPx.toDp() }
        fun set(x: Float) { latest(range.start + ((x - knobPx / 2) / travelPx).coerceIn(0f, 1f) * span) }
        Box(Modifier.fillMaxSize().pointerInput(travelPx) { detectTapGestures { set(it.x) } }
            .pointerInput(travelPx) { detectHorizontalDragGestures(onDragStart = { set(it.x) }) { change, _ -> set(change.position.x) } },
            contentAlignment = Alignment.CenterStart) {
            Box(Modifier.fillMaxWidth().height(3.dp).background(Color.White.copy(alpha = 0.14f), CircleShape))
            Box(Modifier.width(knob / 2 + travel * fraction).height(3.dp)
                .background(Brush.horizontalGradient(listOf(rgb(1.0, 0.66, 0.32), ArenaMenuStyle.ember)), CircleShape))
            Box(Modifier.offset(x = travel * fraction).size(knob), contentAlignment = Alignment.Center) {
                Box(Modifier.size(11.dp).rotate(45f).glow(Color.Black.copy(alpha = 0.6f), 2.dp, 1.dp).background(ArenaMenuStyle.goldFill))
            }
        }
    }
}

/** A count with glass − and + on either side of the value. */
@Composable
fun ArenaStepper(title: String, value: Int, range: IntRange, onChange: (Int) -> Unit, modifier: Modifier = Modifier, identifier: String? = null,
                 valueText: String? = null, showsValue: Boolean = true, compact: Boolean = false, enabled: Boolean = true) {
    @Composable
    fun ring(symbol: String, canStep: Boolean, step: Int) {
        BrandPressable({ GameAudio.play(GameSound.UI_TAP); onChange((value + step).coerceIn(range.first, range.last)) },
            Modifier.size(if (compact) 36.dp else 44.dp, 44.dp).semantics { contentDescription = (if (step > 0) "Increase " else "Decrease ") + title },
            enabled = enabled && canStep) {
            Box(Modifier.size(28.dp).alpha(if (canStep) 1f else 0.35f).background(Color.White.copy(alpha = 0.06f), CircleShape)
                .border(1.dp, ArenaGlass.hairline, CircleShape), contentAlignment = Alignment.Center) {
                SfImage(symbol, ArenaMenuStyle.text, 11.dp)
            }
        }
    }
    Row(modifier.defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.5f).testTag(identifier ?: title)
        .semantics { stateDescription = valueText ?: "$value" },
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        FitText(title, ArenaMenuStyle.font(14f, SfWeight.medium), Modifier.weight(1f, fill = false), color = ArenaMenuStyle.text, minimumScale = 0.8f)
        Spacer(Modifier.weight(1f).widthIn(min = 6.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            ring("minus", value > range.first, -1)
            if (showsValue) Text(valueText ?: "$value", Modifier.widthIn(min = 30.dp), color = ArenaMenuStyle.gold,
                style = ArenaMenuStyle.font(15f, SfWeight.bold).copy(fontFeatureSettings = "tnum", textAlign = androidx.compose.ui.text.style.TextAlign.Center))
            ring("plus", value < range.last, 1)
        }
    }
}

/** A search field as a dark capsule in the gold hairline. */
@Composable
fun ArenaSearchField(placeholder: String, text: String, onChange: (String) -> Unit, modifier: Modifier = Modifier, identifier: String? = null) {
    Row(modifier.defaultMinSize(minHeight = 44.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.fillMaxWidth().height(34.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape)
            .border(1.dp, ArenaGlass.hairline, CircleShape).padding(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("magnifyingglass", ArenaMenuStyle.dim, 13.dp)
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (text.isEmpty()) Text(placeholder, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(14f, SfWeight.medium), maxLines = 1)
                BasicTextField(text, onChange, Modifier.fillMaxWidth().testTag(identifier ?: placeholder).semantics { contentDescription = placeholder },
                    singleLine = true, textStyle = ArenaMenuStyle.font(14f, SfWeight.medium).copy(color = ArenaMenuStyle.text),
                    cursorBrush = SolidColor(ArenaMenuStyle.gold))
            }
            if (text.isNotEmpty()) BrandPressable({ onChange("") }, Modifier.size(30.dp).semantics { contentDescription = "Clear search" }) {
                SfImage("xmark.circle.fill", ArenaMenuStyle.dim, 14.dp)
            }
        }
    }
}

/** A section heading over a grid of deck boxes: a chevron (when it folds), the title and how many. */
@Composable
fun ArenaSectionHeader(title: String, modifier: Modifier = Modifier, count: Int? = null, collapsed: Boolean? = null, toggle: (() -> Unit)? = null) {
    val turn by animateFloatAsState(if (collapsed == true) -90f else 0f, tween(if (BoardMotionFlags.reduceMotion) 0 else 200), label = "shelfChevron")
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 36.dp)
        .then(if (toggle != null) Modifier.clickable(remember { MutableInteractionSource() }, null) { toggle() } else Modifier)
        .semantics(mergeDescendants = true) { heading() },
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (toggle != null) SfImage("chevron.down", ArenaMenuStyle.gold, 11.dp, Modifier.rotate(turn))
        Text(title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(18f, SfWeight.bold).arenaShadow())
        count?.let { Text("$it", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.bold).copy(fontFeatureSettings = "tnum")) }
    }
}

// MARK: - Backdrops

/** The tavern room behind a menu page, darkened so the glass reads (`dim` 0 on the home page, more behind a page or panel). */
@Composable
fun ArenaRoomBackdrop(dim: Float = 0f, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().clearAndSetSemantics { }) {
        BrandBackdrop(Modifier.fillMaxSize(), cards = false)
        val shade by animateFloatAsState(dim, tween(if (BoardMotionFlags.reduceMotion) 0 else 260), label = "roomDim")
        if (shade > 0f) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = shade)))
    }
}

/** ArenaGlassPanel: smoked glass in the gold hairline with a faint top light and a soft shadow. */
fun Modifier.arenaGlassPanel(cornerRadius: Dp = 14.dp, opacity: Float = 0.92f): Modifier {
    val shape = RoundedCornerShape(cornerRadius)
    return this
        .drawBehind {
            val r = cornerRadius.toPx()
            blurredRoundRect(Color.Black.copy(alpha = 0.55f), 14.dp.toPx(), Rect(0f, 6.dp.toPx(), size.width, size.height + 6.dp.toPx()), r)
        }
        .background(Brush.verticalGradient(listOf(ArenaGlass.top.copy(alpha = opacity), ArenaGlass.bottom.copy(alpha = opacity))), shape)
        .background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.06f), 0.5f to Color.Transparent), shape)
        .border(1.dp, ArenaGlass.hairline, shape)
}

/** A glass card for a page's section: the glass panel with padding (light text is the caller's). */
fun Modifier.arenaCard(padding: Dp = 14.dp, cornerRadius: Dp = 14.dp): Modifier =
    this.fillMaxWidth().arenaGlassPanel(cornerRadius, 0.9f).padding(padding)

/** A full glass backing (sheets, full-width surfaces) under a hairline along the top (ArenaGlassBackground). */
fun Modifier.arenaGlassBackground(): Modifier = this
    .background(Brush.verticalGradient(listOf(ArenaGlass.top.copy(alpha = 0.97f), ArenaGlass.bottom.copy(alpha = 0.98f))))
    .drawBehind { drawRect(ArenaGlass.hairline, size = androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx())) }

/**
 * The foot of a scrolling page (and its head, with `top`) fades out over `depth`, so a card running on past the edge never
 * rests cut by a hard line (ArenaScrollFade, used as a mask).
 */
fun Modifier.arenaScrollFade(depth: Dp = 36.dp, top: Dp = 0.dp): Modifier = this
    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
    .drawWithContent {
        drawContent()
        val foot = depth.toPx().coerceAtMost(size.height)
        drawRect(Brush.verticalGradient(listOf(Color.Black, Color.Transparent), size.height - foot, size.height),
            Offset(0f, size.height - foot), androidx.compose.ui.geometry.Size(size.width, foot), blendMode = BlendMode.DstIn)
        val head = top.toPx().coerceAtMost(size.height)
        if (head > 0f) drawRect(Brush.verticalGradient(listOf(Color.Transparent, Color.Black), 0f, head),
            size = androidx.compose.ui.geometry.Size(size.width, head), blendMode = BlendMode.DstIn)
    }

/** An underlined text link (Options' Support and About). */
@Composable
fun ArenaLink(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, identifier: String? = null) {
    BrandPressable({ GameAudio.play(GameSound.UI_OPEN); onClick() }, modifier.defaultMinSize(minHeight = 44.dp)
        .then(if (identifier != null) Modifier.testTag(identifier) else Modifier).semantics { contentDescription = title; role = Role.Button }) {
        Text(title, color = ArenaMenuStyle.text.copy(alpha = 0.75f), style = ArenaMenuStyle.font(13f, SfWeight.medium).copy(textDecoration = TextDecoration.Underline))
    }
}
