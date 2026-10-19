package io.magicmobile.android.board

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import io.magicmobile.android.game.BoardFXCounterKind
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardRect
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.max
import kotlin.math.sin

/**
 * The card moments' 3D pieces: Blender-rendered sprite strips (scripts/brand/fx_sprites.py), each SPRITE_FRAMES square
 * frames of a spin, copied in as drawables by prepareBrandAssets (tavern-fx-counter-plus -> tavern_fx_counter_plus).
 */
class FXSprites(val plus: ImageBitmap, val minus: ImageBitmap, val loyalty: ImageBitmap, val coin: ImageBitmap, val exileRing: ImageBitmap) {
    fun counter(kind: BoardFXCounterKind): ImageBitmap = when (kind) {
        BoardFXCounterKind.PLUS_ONE -> plus
        BoardFXCounterKind.MINUS_ONE -> minus
        BoardFXCounterKind.LOYALTY -> loyalty
        BoardFXCounterKind.OTHER -> coin
    }
}

/**
 * Card moments (docs/BOARD_FX_ROADMAP.md, phase 16), the port of BoardFXCardMoments.swift: counters by kind, power and
 * toughness changes, phasing, exile, transforms, control changes and tokens. Lengths are in dp, like BoardFXPainter.
 */
object BoardFXCardMoments {
    const val SPRITE_FRAMES = 12
    val exileCyan = Color(0.72f, 0.9f, 1f)
    val phaseViolet = Color(0.66f, 0.62f, 1f)
    val brassChain = Color(0.86f, 0.66f, 0.32f)

    private fun DrawScope.px(v: Double): Float = (v * density).toFloat()
    private fun DrawScope.rect(r: BoardRect): Rect = Rect(r.x * density, r.y * density, (r.x + r.width) * density, (r.y + r.height) * density)
    private fun BoardRect.square(cx: Double, cy: Double, side: Double) = BoardRect((cx - side / 2).toFloat(), (cy - side / 2).toFloat(), side.toFloat(), side.toFloat())

    fun counterColor(kind: BoardFXCounterKind): Color = when (kind) {
        BoardFXCounterKind.PLUS_ONE -> Color(0.45f, 1f, 0.55f)
        BoardFXCounterKind.MINUS_ONE -> Color(0.78f, 0.5f, 1f)
        BoardFXCounterKind.LOYALTY -> Color(0.5f, 0.75f, 1f)
        BoardFXCounterKind.OTHER -> BoardFXPainter.gold
    }

    /** A bounce that settles: 0 → overshoot → 1. */
    fun bounce(t: Double): Double {
        val x = t.coerceIn(0.0, 1.0)
        if (x < 0.6) return BoardFXPainter.easeIn(x / 0.6)
        val k = (x - 0.6) / 0.4
        return 1 - 0.18 * sin(k * Math.PI) * (1 - k)
    }

    /** One frame of a sprite strip, drawn into `into`. */
    fun DrawScope.sprite(image: ImageBitmap, frame: Int, into: BoardRect, alpha: Double = 1.0, additive: Boolean = false) {
        if (alpha <= 0.01 || into.width <= 1f) return
        val frameSize = image.height
        val index = ((frame % SPRITE_FRAMES) + SPRITE_FRAMES) % SPRITE_FRAMES
        val r = rect(into)
        drawImage(image, srcOffset = IntOffset(index * frameSize, 0), srcSize = IntSize(frameSize, frameSize),
            dstOffset = IntOffset(r.left.toInt(), r.top.toInt()), dstSize = IntSize(r.width.toInt(), r.height.toInt()),
            alpha = alpha.toFloat().coerceIn(0f, 1f), blendMode = if (additive) BlendMode.Plus else BlendMode.SrcOver)
    }

    /**
     * Counters arriving or leaving: the piece drops onto the card's corner with a spin and a bounce (or lifts away), its
     * label rises from it, and a -1/-1 drop splashes a violet ripple over the card.
     */
    fun DrawScope.counterMoment(measurer: TextMeasurer, sprites: FXSprites?, kind: BoardFXCounterKind, delta: Int, on: BoardRect,
                                p: Double, motion: Boolean, seed: Int) = with(BoardFXPainter) {
        val color = counterColor(kind)
        val side = min(on.width * 0.5, 46.0)
        val restX = on.x + on.width - side * 0.42
        val restY = on.y + side * 0.5
        val image = sprites?.counter(kind)
        val label = kind.label(delta)
        if (!motion) {
            val fade = window(p, 0.15, 0.7)
            image?.let { sprite(it, 0, on.square(restX, restY, side), fade) }
            number(measurer, label, BoardPoint(restX.toFloat(), (restY + side * 0.55).toFloat()), color, 18.0, p, false)
            return@with
        }
        val impact = 0.42
        if (delta > 0) {
            val fall = bounce(p / impact)
            val y = restY - (1 - fall) * (on.height * 0.9 + 30)
            // Two quick turns while it falls, slowing to its face as it lands.
            val turn = if (p < impact) (easeOut(p / impact) * SPRITE_FRAMES * 2).toInt() else 0
            val fade = if (p > 0.82) (1 - p) / 0.18 else 1.0
            val scale = if (p < impact) 0.7 + 0.3 * fall else 1 + 0.12 * max(0.0, 1 - (p - impact) / 0.12)
            image?.let { sprite(it, turn, on.square(restX, y, side * scale), fade) }
            if (p >= impact) {
                val q = (p - impact) / (1 - impact)
                val rest = BoardPoint(restX.toFloat(), restY.toFloat())
                shockwave(rest, color, side * 1.1, min(1.0, q * 1.6))
                sparks(on.square(restX, restY, side), color, 12, q, seed, BoardFXPainter.SparkStyle.BURST)
                if (kind == BoardFXCounterKind.MINUS_ONE) {
                    // Ichor: the card dims violet for a beat under the ripple.
                    flash(on, color.copy(alpha = 0.7f), q)
                    shockwave(BoardPoint(on.x + on.width / 2, on.y + on.height / 2), color.copy(alpha = 0.7f), on.width * 0.8, q)
                }
                number(measurer, label, BoardPoint(restX.toFloat(), (restY + side * 0.6).toFloat()), color, 22.0, q, true)
            }
        } else {
            // Removed: the piece lifts off the card, turning, and fades as its label drops away.
            val q = easeOut(p)
            image?.let { sprite(it, (q * SPRITE_FRAMES).toInt(), on.square(restX, restY - q * 46, side * (1 - 0.35 * q)), 1 - p) }
            number(measurer, label, BoardPoint(restX.toFloat(), (restY + side * 0.6).toFloat()), color.copy(alpha = 0.85f), 20.0, p, true)
        }
    }

    /** Power and toughness changed beyond the counters: the change floats up over the card and its stat corner pulses. */
    fun DrawScope.statsMoment(measurer: TextMeasurer, power: Int, toughness: Int, on: BoardRect, p: Double, motion: Boolean) = with(BoardFXPainter) {
        fun signed(value: Int) = if (value >= 0) "+$value" else "$value"
        val total = power + toughness
        val color = if (total > 0) Color(0.45f, 1f, 0.55f) else if (total < 0) Color(0.78f, 0.5f, 1f) else gold
        shockwave(BoardPoint(on.x + on.width - 12, on.y + on.height - 12), color, if (motion) 34.0 else 20.0, min(1.0, p * 1.5))
        if (motion) arrivalGlow(on, color.copy(alpha = 0.6f), min(1.0, p * 1.3), false)
        number(measurer, "${signed(power)}/${signed(toughness)}", BoardPoint(on.x + on.width / 2, on.y + on.height / 2), color, 22.0, p, motion)
    }

    /**
     * Phasing: bands of violet light sweep the card as it thins out of the world (or back in). The tile itself shows the
     * phased-out state for as long as it lasts; this is only the moment.
     */
    fun DrawScope.phaseMoment(out: Boolean, on: BoardRect, p: Double, motion: Boolean, seed: Int) = with(BoardFXPainter) {
        val r = rect(on)
        val fade = window(p, 0.12, 0.7)
        val bands = if (motion) 4 else 2
        clipRect(r.left - px(4.0), r.top - px(4.0), r.right + px(4.0), r.bottom + px(4.0)) {
            for (i in 0 until bands) {
                // Bands sweep down when leaving, up when returning.
                val phase = (p * 1.6 + i.toDouble() / bands) % 1.0
                val y = if (out) r.top + r.height * phase.toFloat() else r.bottom - r.height * phase.toFloat()
                drawRect(Brush.verticalGradient(listOf(Color.Transparent, phaseViolet, Color.Transparent), startY = y - px(6.0), endY = y + px(6.0)),
                    topLeft = Offset(r.left - px(4.0), y - px(6.0)), size = Size(r.width + px(8.0), px(12.0)),
                    alpha = (0.55 * fade).toFloat(), blendMode = BlendMode.Plus)
            }
        }
        if (motion) {
            shockwave(BoardPoint(on.x + on.width / 2, on.y + on.height / 2), phaseViolet.copy(alpha = 0.8f), on.width * 0.9, if (out) p else 1 - p)
            sparks(on, phaseViolet, 14, p, seed, if (out) BoardFXPainter.SparkStyle.RISE else BoardFXPainter.SparkStyle.FALL)
        }
    }

    /** Exile: a pillar of pale light over the card and the sigil ring turning under it while the card burns away cold. */
    fun DrawScope.exileMoment(sprites: FXSprites?, on: BoardRect, p: Double, motion: Boolean, elapsed: Double, seed: Int) = with(BoardFXPainter) {
        val fade = window(p, 0.1, 0.65)
        val r = rect(on)
        val height = r.height * (if (motion) 2.6f else 1.4f) * easeOut(min(1.0, p / 0.35)).toFloat()
        val width = r.width * 0.76f
        val left = r.center.x - width / 2
        drawRoundRect(Brush.verticalGradient(listOf(exileCyan.copy(alpha = 0f), exileCyan, Color.White), startY = r.bottom - height, endY = r.bottom),
            topLeft = Offset(left, r.bottom - height), size = Size(width, height), cornerRadius = CornerRadius(width / 2, width / 2),
            alpha = (0.75 * fade).toFloat(), blendMode = BlendMode.Plus)
        if (!motion) return@with
        val ringWidth = on.width * 1.7
        val ring = BoardRect((on.x + on.width / 2 - ringWidth / 2).toFloat(), (on.y + on.height - ringWidth * 0.62).toFloat(), ringWidth.toFloat(), ringWidth.toFloat())
        sprites?.let { sprite(it.exileRing, (elapsed * 16).toInt(), ring, fade, additive = true) }
        sparks(on, exileCyan, 18, p, seed + 31, BoardFXPainter.SparkStyle.RISE)
    }

    /** Control change: a brass chain reaches from the old controller to the card, then snaps as the card settles. */
    fun DrawScope.chainMoment(from: BoardPoint, to: BoardRect, p: Double, motion: Boolean, seed: Int) = with(BoardFXPainter) {
        val start = Offset(from.x * density, from.y * density)
        val target = rect(to).center
        val reach = easeOut(min(1.0, p / 0.45)).toFloat()
        val end = Offset(start.x + (target.x - start.x) * reach, start.y + (target.y - start.y) * reach)
        val alpha = if (p > 0.55) max(0.0, 1 - (p - 0.55) / 0.3).toFloat() else 1f
        val dash = PathEffect.dashPathEffect(floatArrayOf(px(9.0), px(5.0)))
        drawLine(brassChain.copy(alpha = 0.35f * alpha), start, end, strokeWidth = px(10.0), cap = StrokeCap.Round, blendMode = BlendMode.Plus)
        drawLine(brassChain.copy(alpha = alpha), start, end, strokeWidth = px(4.0), cap = StrokeCap.Round, pathEffect = dash, blendMode = BlendMode.Plus)
        drawLine(Color.White.copy(alpha = 0.55f * alpha), start, end, strokeWidth = px(1.2), cap = StrokeCap.Round, pathEffect = dash, blendMode = BlendMode.Plus)
        if (p > 0.45) {
            val q = (p - 0.45) / 0.55
            arrivalGlow(to, brassChain, q, motion)
            if (motion) sparks(to, gold, 14, q, seed, BoardFXPainter.SparkStyle.BURST)
        }
    }

    /** A token forming: motes of its colour gather into the card from around it. */
    fun DrawScope.gather(into: BoardRect, color: Color, count: Int, p: Double, seed: Int) = with(BoardFXPainter) {
        val q = easeOut(min(1.0, p / 0.7))
        val cx = into.x + into.width / 2.0
        val cy = into.y + into.height / 2.0
        val alpha = window(p, 0.1, 0.75).toFloat()
        for (i in 0 until count) {
            val angle = noise(seed, i, 11) * 2 * Math.PI
            val distance = (into.width * 0.9 + 40 * noise(seed, i, 12)) * (1 - q)
            val x = cx + cos(angle) * distance
            val y = cy + sin(angle) * distance * 1.2
            val radius = 1.5 + 2.5 * noise(seed, i, 13)
            drawCircle(color.copy(alpha = alpha), radius = px(radius), center = Offset(px(x), px(y)), blendMode = BlendMode.Plus)
        }
    }

    /** A new face: a ring of light around the card while the tile itself turns over (BoardFXCardMotion.flips). */
    fun DrawScope.transformMoment(on: BoardRect, color: Color, p: Double, motion: Boolean, seed: Int) = with(BoardFXPainter) {
        arrivalGlow(on, color, p, motion)
        if (motion) {
            shockwave(BoardPoint(on.x + on.width / 2, on.y + on.height / 2), color, on.width.toDouble(), p)
            sparks(on, color, 12, p, seed, BoardFXPainter.SparkStyle.BURST)
        }
    }
}
