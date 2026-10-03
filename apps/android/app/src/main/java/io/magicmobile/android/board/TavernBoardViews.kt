package io.magicmobile.android.board

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.R
import io.magicmobile.android.game.BattlefieldLayoutMetrics
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.game.BoardSize
import io.magicmobile.android.game.PlayerGameState
import io.magicmobile.android.game.PlayerStatusSummary
import io.magicmobile.android.game.TavernDesign
import io.magicmobile.android.game.TavernPhaseTrack
import io.magicmobile.android.game.TavernSockets
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.game.tavernLength
import io.magicmobile.android.game.tavernPoint
import io.magicmobile.android.game.tavernRect
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernCoin
import io.magicmobile.android.ui.TavernImages
import io.magicmobile.android.ui.TavernMenuDivider
import io.magicmobile.android.ui.TavernNamePlate
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.colorAdjust
import io.magicmobile.android.ui.drawStretched
import io.magicmobile.android.ui.engraved
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernImage
import io.magicmobile.android.ui.tavernPanel
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/*
 * The Walnut Tavern board's table objects (iOS Board/BoardChrome.swift "Walnut Tavern chrome", "Player
 * status in the tavern zones pop-over" and "Glows", ArenaBoardPresentation.swift TavernArtCrop).
 */

/**
 * Where the tavern plate is on screen: the full screen (`canvas`, dp, in which the plate's design points
 * are mapped) and the top-left of the board's safe-area box in it (`origin`). Socket points convert to
 * the board's own coordinates, so controls land on the plate whatever the insets (iOS tavernCanvas).
 */
data class TavernFrame(val canvas: BoardSize, val origin: BoardPoint) {
    val sockets: TavernSockets get() = TavernSockets.current(canvas)
    val isLandscape: Boolean get() = canvas.width > canvas.height

    /** A design point in the board's coordinates. */
    fun point(design: BoardPoint): BoardPoint = canvas.tavernPoint(design).let { BoardPoint(it.x - origin.x, it.y - origin.y) }
    fun length(design: Float): Float = canvas.tavernLength(design)
    fun rect(design: BoardRect): BoardRect = canvas.tavernRect(design).let { BoardRect(it.x - origin.x, it.y - origin.y, it.width, it.height) }
}

val LocalTavernFrame = compositionLocalOf<TavernFrame?> { null }

/** Keys under which the tavern medallions publish their bounds, so arrows and life changes aim at them (TavernSeatAnchor). */
object TavernSeatAnchor {
    const val bottom = "tavern-seat:bottom"
    const val top = "tavern-seat:top"
}

/** Centers a child on a socket of the plate, in the board's coordinates. */
fun Modifier.tavernPosition(frame: TavernFrame, design: BoardPoint): Modifier {
    val point = frame.point(design)
    return this.centerAt(point.x, point.y)
}

/**
 * TavernMedallion: a round portrait in a brass socket with the life total on an enamel badge at the bottom.
 * Your turn glows ember, an attackable player glows red (light only), and your commander medallion breathes
 * emerald and gold with a crown spark when the commander can be cast.
 */
@Composable
fun TavernMedallion(diameter: Dp, life: Int?, modifier: Modifier = Modifier, active: Boolean = false, targetable: Boolean = false,
                    commanderReady: Boolean = false, portrait: @Composable () -> Unit) {
    val activeGlow by animateFloatAsState(if (active) 1f else 0f, tween(350), label = "medallionActive")
    Box(modifier.requiredSize(diameter + 8.dp), contentAlignment = Alignment.Center) {
        if (targetable) {
            Box(Modifier.requiredSize(diameter * 1.3f).glow(rgb(1.0, 0.18, 0.1), diameter * 0.12f, diameter * 0.65f))
        }
        if (commanderReady) TavernCommanderReadyGlow(diameter)
        Box(Modifier.requiredSize(diameter)
            .glow(if (activeGlow > 0f) TavernPalette.ember.copy(alpha = 0.75f * activeGlow) else Color.Black.copy(alpha = 0.5f), if (active) 10.dp else 4.dp, diameter / 2)
            .clip(CircleShape)) { portrait() }
        Box(Modifier.requiredSize(diameter).border(2.dp, Color.Black.copy(alpha = 0.55f), CircleShape))
        if (life != null) {
            Box(Modifier.offset(y = diameter * 0.47f).requiredSize(diameter * 0.58f, diameter * 0.40f)
                .background(Brush.radialGradient(listOf(TavernPalette.enamel, Color.Black.copy(alpha = 0.92f))), CircleShape)
                .border(1.5.dp, TavernPalette.brass, CircleShape), contentAlignment = Alignment.Center) {
                BoardLifeTotal(life, sf(diameter.value * 0.30f, SfWeight.heavy, SfDesign.SERIF), baseColor = TavernPalette.parchment)
            }
        }
    }
}

/** Your commander medallion when the commander can be cast: an emerald-and-gold ring of light breathing round it and a crown spark above. */
@Composable
fun TavernCommanderReadyGlow(diameter: Dp) {
    val reduce = BoardMotion.reduceMotion
    val breath = if (reduce) null else rememberBoardBreath(900, 0.45f, 1f)
    Box(Modifier.requiredSize(diameter * 1.42f), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize().graphicsLayer {
            val strength = breath?.invoke() ?: 0.9f
            val s = if (breath == null) 1f else 0.96f + 0.06f * strength
            scaleX = s; scaleY = s; alpha = strength
        }) {
            val width = diameter.toPx() * 0.09f
            val brush = Brush.sweepGradient(listOf(rgb(0.45, 1.0, 0.55), rgb(1.0, 0.86, 0.45), rgb(0.3, 0.9, 0.5), rgb(1.0, 0.86, 0.45), rgb(0.45, 1.0, 0.55)))
            // A soft ring: a wide faint stroke under the ring itself, light only.
            drawCircle(brush, size.minDimension / 2 - width, style = Stroke(width * 2.4f), alpha = 0.35f)
            drawCircle(brush, size.minDimension / 2 - width, style = Stroke(width))
        }
        Box(Modifier.offset(y = -diameter * 0.84f)) {
            SfImage("crown.fill", rgb(1.0, 0.86, 0.5), diameter * 0.26f, Modifier.glow(rgb(0.5, 1.0, 0.55).copy(alpha = 0.9f), 5.dp, diameter * 0.13f))
        }
    }
}

/** The opponent's hand as face-down cards fanned above their medallion, one per card up to twenty (TavernCardBackFan). */
@Composable
fun TavernCardBackFan(count: Int, modifier: Modifier = Modifier) {
    val shown = minOf(count, 20)
    val arc = minOf(shown * 7f, 84f)
    val width = minOf(shown * 11f, 150f)
    Box(modifier.height(40.dp).semantics { contentDescription = if (count == 1) "1 card in hand" else "$count cards in hand" },
        contentAlignment = Alignment.BottomCenter) {
        for (index in 0 until shown) {
            val spread = if (shown > 1) index.toFloat() / (shown - 1) - 0.5f else 0f
            Box(Modifier.offset(x = (spread * width).dp, y = (abs(spread) * 8).dp)
                .graphicsLayer { rotationZ = spread * arc; transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 1f) }
                .requiredSize(24.dp, 34.dp).glow(Color.Black.copy(alpha = 0.45f), 2.dp, 3.dp)
                .background(Brush.verticalGradient(listOf(rgb(0.12, 0.15, 0.24), rgb(0.06, 0.07, 0.12))), RoundedCornerShape(3.dp))
                .border(1.2.dp, TavernPalette.brass, RoundedCornerShape(3.dp)), contentAlignment = Alignment.Center) {
                SfImage("sparkle", TavernPalette.brass, 9.dp)
            }
        }
    }
}

/** A small brass ring button that sits on the table beside the hourglass (TavernRingLabel). */
@Composable
fun TavernRingLabel(pressed: Boolean = false, content: @Composable () -> Unit) {
    Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size(34.dp).glow(Color.Black.copy(alpha = 0.55f), 3.dp, 17.dp)
            .background(Brush.radialGradient(listOf(if (pressed) TavernPalette.brassDark else rgb(0.24, 0.13, 0.07), Color.Black.copy(alpha = 0.92f))), CircleShape)
            .border(2.5.dp, Brush.verticalGradient(listOf(TavernPalette.brass, TavernPalette.brassDark)), CircleShape),
            contentAlignment = Alignment.Center) {
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides TavernPalette.parchment) { content() }
        }
    }
}

/**
 * TavernManaGemFace: one mana gem in the tavern rail, centred on its socket. It glows in its colour and
 * breathes while that mana floats, with the amount on a small badge, and sits dim when the pool has none.
 */
@Composable
fun TavernManaGemFace(symbol: String, count: Int, modifier: Modifier = Modifier, payable: Boolean = false, diameter: Dp = 26.dp) {
    val lit = count > 0
    val glowColor = when (symbol) {
        "W" -> rgb(1.0, 0.93, 0.70); "U" -> rgb(0.35, 0.62, 1.0); "B" -> rgb(0.66, 0.42, 0.86)
        "R" -> rgb(1.0, 0.38, 0.20); "G" -> rgb(0.32, 0.88, 0.42); else -> rgb(0.86, 0.86, 0.92)
    }
    val breathing = if (lit && !BoardMotion.reduceMotion) {
        rememberBoardBreath(1200)()
    } else 0f
    val image = tavernImage(TavernImages.manaGem(symbol))
    Box(modifier.requiredSize(diameter), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize()
            .glow(if (lit || payable) glowColor.copy(alpha = 0.7f + 0.25f * breathing) else Color.Black.copy(alpha = 0.6f),
                // A fixed blur keeps the drawn glow cached; only its brightness breathes.
                if (lit || payable) 7.5.dp else 1.5.dp, diameter / 2)
            .colorAdjust(if (lit) 1.15f else 0.75f, if (lit) 0.04f + 0.08f * breathing else -0.08f)
            .drawBehind { drawStretched(image) })
        if (lit) {
            Text("$count", Modifier.align(Alignment.BottomEnd).offset(x = diameter * 0.12f, y = diameter * 0.12f)
                .background(Color.Black.copy(alpha = 0.8f), CircleShape).border(1.dp, TavernPalette.brass, CircleShape).padding(horizontal = 3.dp),
                color = Color.White, style = sf(diameter.value * 0.36f, SfWeight.heavy, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"))
        }
    }
}

/** TavernAwareManaSymbol: a mana symbol drawn as the tavern's crystal gem on the tavern board. */
@Composable
fun TavernAwareManaSymbol(symbol: String, size: Dp, modifier: Modifier = Modifier) {
    if (io.magicmobile.android.ui.LocalTavernBoard.current && symbol.uppercase() in setOf("W", "U", "B", "R", "G", "C")) {
        val image = tavernImage(TavernImages.manaGem(symbol))
        Box(modifier.requiredSize(size * 1.2f).drawBehind { drawStretched(image) }.semantics { contentDescription = symbol })
    } else ManaSymbolView(symbol, size, modifier)
}

/** The tavern's phase plate, mirroring the opponent's nameplate: the turn, the step in words and the five phases with the current one lit. */
@Composable
fun TavernPhasePlate(step: String?, turn: Int, modifier: Modifier = Modifier, width: Dp = 118.dp) {
    val (title, phase) = TavernPhaseTrack.describe(step)
    Column(modifier.width(width).glow(Color.Black.copy(alpha = 0.45f), 4.dp, 7.dp).tavernPanel(7.dp).padding(horizontal = 9.dp, vertical = 6.dp)
        .semantics { contentDescription = if (title.isEmpty()) "Turn $turn" else "Turn $turn, $title" },
        verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text("TURN $turn", style = sf(9f, SfWeight.heavy, SfDesign.SERIF, tracking = 1f).copy(brush = BrandTheme.brassGradient).engraved(0.6f), maxLines = 1)
        FitText(title, sf(12.5f, SfWeight.semibold, SfDesign.SERIF).engraved(0.6f), color = TavernPalette.parchment, minimumScale = 0.7f)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            for (index in TavernPhaseTrack.phases.indices) {
                val current = index == phase
                Box(Modifier.weight(1f).height(if (current) 5.dp else 4.dp)
                    .glow(if (current) BrandTheme.ember.copy(alpha = 0.9f) else Color.Transparent, 3.dp, 3.dp)
                    .background(if (current) Brush.verticalGradient(listOf(rgb(1.0, 0.62, 0.36), BrandTheme.ember))
                        else Brush.verticalGradient(List(2) { BrandTheme.brass.copy(alpha = 0.32f) }), CircleShape))
            }
        }
    }
}

private fun PlayerStatusSummary.Tint.color(): Color = rgb(red, green, blue)

/** One status badge: a leather coin in a brass ring with its symbol and its count on a brass coin; a red ring near lethal. */
@Composable
fun TavernStatusBadge(badge: PlayerStatusSummary.Badge, size: Dp = 40.dp) {
    val tint = badge.tint.color()
    Box(Modifier.requiredSize(size).semantics { contentDescription = badge.label }) {
        Box(Modifier.fillMaxSize().glow(Color.Black.copy(alpha = 0.5f), 2.dp, size / 2)
            .background(Brush.radialGradient(listOf(rgb(0.3, 0.17, 0.09), TavernPalette.leather)), CircleShape), contentAlignment = Alignment.Center) {
            when (val icon = badge.icon) {
                PlayerStatusSummary.Icon.Poison -> Canvas(Modifier.requiredSize(size * 0.5f, size * 0.56f)) {
                    // Poison as the Phyrexian symbol: a ring split by an upright stroke.
                    val stroke = Stroke(size.toPx() * 0.08f, cap = StrokeCap.Round)
                    drawOval(tint, Offset(this.size.width * 0.2f, this.size.height * 0.24f),
                        Size(this.size.width * 0.6f, this.size.height * 0.52f), style = stroke)
                    drawLine(tint, Offset(this.size.width / 2, 0f), Offset(this.size.width / 2, this.size.height), stroke.width, StrokeCap.Round)
                }
                is PlayerStatusSummary.Icon.Symbol -> SfImage(icon.name, tint, size * 0.42f)
                is PlayerStatusSummary.Icon.Commander -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    val card = icon.card
                    if (card != null) Box(Modifier.padding(2.dp).fillMaxSize().clip(CircleShape)) { TavernArtCrop(card, "Command") }
                    else SfImage("crown.fill", tint, size * 0.4f)
                    Box(Modifier.align(Alignment.TopStart).offset(x = size * 0.05f, y = size * 0.05f)) {
                        SfImage("shield.lefthalf.filled", TavernPalette.parchment, size * 0.26f)
                    }
                }
            }
            Box(Modifier.fillMaxSize().border(if (badge.nearLethal) 2.4.dp else 1.6.dp,
                if (badge.nearLethal) rgb(0.95, 0.2, 0.12) else TavernPalette.brass, CircleShape))
        }
        badge.count?.let { TavernCoin(it, size * 0.5f, Modifier.align(Alignment.BottomEnd).offset(x = size * 0.12f, y = size * 0.1f)) }
    }
}

/** The top of a player's zones pop-over: their name, status badges and the cards attached to them (tap one to inspect it). */
@Composable
fun TavernPlayerStatusPanel(name: String, summary: PlayerStatusSummary, inspect: ((String, List<ZoneCard>) -> Unit)?) {
    val select = io.magicmobile.android.ui.LocalTavernMenuSelect.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FitText(name.uppercase(), sf(13f, SfWeight.heavy, SfDesign.SERIF, tracking = 1f).copy(brush = TavernPalette.goldText),
            Modifier.fillMaxWidth(), minimumScale = 0.7f, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (summary.badges.isNotEmpty()) {
            Column(Modifier.semantics { contentDescription = "board.zones.status" }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (row in summary.badges.chunked(5)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (badge in row) Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { TavernStatusBadge(badge) }
                    }
                }
            }
        }
        if (summary.attachments.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("link", TavernPalette.brass, 12.dp)
                for (card in summary.attachments) {
                    Box(Modifier.size(38.dp).glow(Color.Black.copy(alpha = 0.5f), 2.dp, 5.dp).clip(RoundedCornerShape(5.dp))
                        .border(1.2.dp, TavernPalette.brass, RoundedCornerShape(5.dp))
                        .clickable { select { inspect?.invoke("Attached to $name", listOf(card)) } }
                        .semantics { contentDescription = "${card.card.name}, attached" }) {
                        TavernArtCrop(card, "Battlefield")
                    }
                }
            }
        }
        if (!summary.isEmpty) TavernMenuDivider()
    }
}

/** The bottom of an opponent's pop-over in a pod: swap the board to another opponent; the current one wears an ember ring. */
@Composable
fun TavernOpponentSwap(opponents: List<PlayerGameState>, current: String, label: (String) -> String, select: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        TavernMenuDivider()
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("arrow.left.arrow.right.circle.fill", TavernPalette.brass, 22.dp)
            for (opponent in opponents) {
                val chosen = opponent.playerId == current
                Box(Modifier.alpha(if (opponent.isOut) 0.45f else 1f)
                    .glow(if (chosen) TavernPalette.ember.copy(alpha = 0.7f) else Color.Transparent, 4.dp, 18.dp)
                    .clickable { select(opponent.playerId) }
                    .semantics { contentDescription = "Swap to ${label(opponent.playerId)}" + if (chosen) ", selected" else "" }) {
                    PlayerPortrait(opponent, 36.dp)
                    Box(Modifier.requiredSize(36.dp).border(if (chosen) 2.5.dp else 1.2.dp,
                        if (chosen) TavernPalette.ember else TavernPalette.brass.copy(alpha = 0.6f), CircleShape))
                }
            }
            Spacer(Modifier.weight(1f))
        }
    }
}

/** A glance at the most pressing status beside a medallion: poison and the worst commander damage. Taps pass through. */
@Composable
fun TavernStatusGlance(summary: PlayerStatusSummary, modifier: Modifier = Modifier) {
    val shown = summary.glance
    if (shown.isEmpty()) return
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (badge in shown) TavernStatusBadge(badge, 22.dp)
    }
}

/**
 * TavernTileGlow: the tavern board's highlight for a battlefield tile, soft light around the frame and no
 * line. One pre-blurred image tinted to `color`; also the framed tiles' drop shadow, in black.
 */
fun Modifier.tavernTileGlow(color: Color, strength: Float = 0.95f, offset: Offset = Offset.Zero): Modifier = composed {
    val image = tavernImage(R.drawable.tavern_tile_glow)
    val filter = remember(color) { ColorFilter.tint(color, BlendMode.SrcIn) }
    drawBehind {
        // The image's light runs 30 px past a 240 x 260 card on a 300 x 320 canvas.
        val w = size.width * 300f / 240f; val h = size.height * 320f / 260f
        drawStretched(image, Offset((size.width - w) / 2 + offset.x * density, (size.height - h) / 2 + offset.y * density), Size(w, h), strength, filter)
    }
}

/** The back of a small brass coin, for badges on the tavern board (abilities, tapped, more). */
fun Modifier.tavernCoinBack(): Modifier = this
    .glow(Color.Black.copy(alpha = 0.5f), 1.5.dp, 99.dp)
    .background(Brush.radialGradient(listOf(rgb(0.32, 0.19, 0.09), TavernPalette.leather)), CircleShape)
    .border(1.2.dp, BrandTheme.brassGradient, CircleShape)

/**
 * TavernArtCrop: only a card's illustration, the card image scaled so its art box (on a modern frame, 85% of
 * the width and 44% of the height, centred a third of the way down) fills the window.
 */
@Composable
fun TavernArtCrop(card: ZoneCard, zoneName: String, modifier: Modifier = Modifier, tagReserve: Dp = 0.dp) {
    var artMissing by remember(card.card.name) { mutableStateOf(false) }
    BoxWithConstraints(modifier.fillMaxSize().clipToBounds()) {
        val window = BoardSize(maxWidth.value, maxHeight.value)
        val ratio = BattlefieldLayoutMetrics.magicCardHeightToWidth
        val cardWidth = maxOf(window.width / 0.85f, window.height / (0.44f * ratio))
        val cardHeight = cardWidth * ratio
        androidx.compose.runtime.CompositionLocalProvider(LocalCardArtPlaceholderShown provides { shown -> artMissing = shown }) {
            Box(Modifier.requiredSize(cardWidth.dp, cardHeight.dp).offset(y = ((0.5f - 0.335f) * cardHeight).dp).align(Alignment.Center)) {
                CardTile(card, selected = false, zoneName = zoneName, width = cardWidth.dp, height = cardHeight.dp, ignoreTappedRotation = true,
                    tokenCopyTagTrailingReserve = tagReserve)
            }
        }
        if (artMissing) {
            // The stand-in prints the name large, so the crop would show stray letters: a quiet art stand-in instead.
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(rgb(0.20, 0.24, 0.17), rgb(0.09, 0.10, 0.08)))),
                contentAlignment = Alignment.Center) {
                SfImage("sparkle", BrandTheme.brass.copy(alpha = 0.7f), (minOf(window.width, window.height) * 0.32f).dp)
            }
        }
    }
}

/** The rendered pass button parts: the still ring and the disc's full turn in 48 frames, frame 0 the glowing face. */
object TavernPassAssets {
    const val frameCount = 48
}

/**
 * The state of the pass button's glass disc (TavernPassStage): the bright red face while you hold priority,
 * the dim bronze face while you wait. A tap turns it over at once and it turns back when priority returns,
 * so a pass that leaves you with priority spins it all the way round. It lives outside the button, whose
 * identity changes with every action, so a turn is never cut short.
 */
class TavernPassDisc(enabled: Boolean) {
    /** Half turns: even shows the glowing face, odd the waiting face. */
    val turns = Animatable(if (enabled) 0f else 1f)
    var wantsFront by mutableStateOf(enabled)
    var turning by mutableStateOf(false)
    val showsFront: Boolean get() = (turns.value.roundToInt() % 2) == 0

    suspend fun turnOver(reduceMotion: Boolean) {
        if (turning) return
        turning = true
        val target = turns.value.roundToInt() + 1f
        if (reduceMotion) turns.snapTo(target) else turns.animateTo(target, tween(450))
        turning = false
        settle(reduceMotion)
    }

    /** Turns to the face that matches who holds priority, unless it is already showing. */
    suspend fun settle(reduceMotion: Boolean) {
        if (turning || showsFront == wantsFront) return
        turnOver(reduceMotion)
    }

    val frameIndex: Int get() {
        val phase = ((turns.value % 2f) + 2f) % 2f / 2f
        return (phase * TavernPassAssets.frameCount).roundToInt() % TavernPassAssets.frameCount
    }
}

/**
 * TavernPassStage + TavernPrimaryButtonStyle: the glass disc turning inside the still brass ring, with the
 * button over it. Passing and waiting need no words; other actions (Confirm, Attack…) name themselves on an
 * engraved brass plate riveted to the ring's top. A tap turns the disc and runs the action. The tap target is
 * rebuilt for each action (`actionKey`), so a finger-down on Pass never becomes a new prompt's action; the
 * disc stays, so a turn is never cut short. Without priority the dim face shows and taps do nothing.
 */
@Composable
fun TavernPassStage(enabled: Boolean, turnsOnTap: Boolean, title: String, showsTitle: Boolean, diameter: Dp, actionKey: Any,
                    onClick: () -> Unit, modifier: Modifier = Modifier, contentDescription: String = title) {
    val disc = remember { TavernPassDisc(enabled) }
    val scope = rememberCoroutineScope()
    val reduce = BoardMotion.reduceMotion
    val resources = LocalContext.current.resources
    LaunchedEffect(Unit) { withContext(Dispatchers.Default) { TavernImages.passFlips.forEach { TavernImages.load(resources, it) } } }
    LaunchedEffect(enabled) { disc.wantsFront = enabled; disc.settle(reduce) }
    val frame = tavernImage(TavernImages.passFlips[disc.frameIndex])
    val ring = tavernImage(R.drawable.tavern_pass_ring)
    Box(modifier.requiredSize(diameter), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.align(Alignment.Center).requiredSize(diameter * 0.74f).background(rgb(0.05, 0.03, 0.02), CircleShape))
        Box(Modifier.fillMaxSize().drawBehind { drawStretched(frame) })
        Box(Modifier.fillMaxSize().drawBehind { drawStretched(ring) })
        if (showsTitle) TavernNamePlate(title, Modifier.widthIn(max = diameter * 0.86f).offset(y = 1.dp))
        androidx.compose.runtime.key(actionKey) {
            // The whole square takes taps: a slightly bigger target than the round face.
            Box(Modifier.matchParentSize().clickable(remember { MutableInteractionSource() }, null, enabled,
                role = androidx.compose.ui.semantics.Role.Button) {
                GameAudio.play(GameSound.UI_TAP)
                if (turnsOnTap) scope.launch { disc.turnOver(reduce) }
                onClick()
            }.semantics { this.contentDescription = contentDescription })
        }
    }
}

/** The pass button diameter on this canvas (its ring matches the life medallion's frame). */
fun TavernFrame.passDiameter(): Float = TavernDesign.passDiameter(canvas)

