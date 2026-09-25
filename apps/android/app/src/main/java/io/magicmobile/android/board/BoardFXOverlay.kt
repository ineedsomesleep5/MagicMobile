package io.magicmobile.android.board

import android.graphics.BlurMaskFilter
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.ActiveBoardFX
import io.magicmobile.android.game.BoardFXEntrance
import io.magicmobile.android.game.BoardFXEvent
import io.magicmobile.android.game.BoardFXScheduler
import io.magicmobile.android.game.BoardFXSpellWeight
import io.magicmobile.android.game.BoardFXStrikeTarget
import io.magicmobile.android.game.BoardFXTint
import io.magicmobile.android.game.BoardFXZone
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.game.BoardSize
import io.magicmobile.android.game.ScheduledBoardFX
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.dissolveEffect
import io.magicmobile.android.ui.foilEffect
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

/*
 * Port of BoardFXOverlay.swift. One Canvas draws every active effect as a pure function of
 * elapsed time, with card flights layered above it: no per-particle state, no work while
 * idle, and no hit testing. Event derivation lives in core's BoardEventTimeline.
 */

val BoardFXTint.color: Color get() = when (this) {
    BoardFXTint.WHITE -> rgb(1.0, 0.95, 0.78); BoardFXTint.BLUE -> rgb(0.36, 0.66, 1.0); BoardFXTint.BLACK -> rgb(0.72, 0.48, 0.95)
    BoardFXTint.RED -> rgb(1.0, 0.42, 0.22); BoardFXTint.GREEN -> rgb(0.42, 0.9, 0.45); BoardFXTint.MULTICOLOR -> rgb(1.0, 0.8, 0.32)
    BoardFXTint.COLORLESS -> rgb(0.82, 0.84, 0.9)
}

/** Board positions in the overlay's coordinate space (dp). */
data class BoardFXAnchors(val viewerID: String, val viewerPoint: BoardPoint, val opponentPoint: BoardPoint, val stackPoint: BoardPoint,
                          val viewerHandPoint: BoardPoint, val opponentHandPoint: BoardPoint) {
    fun playerPoint(playerID: String): BoardPoint = if (playerID == viewerID) viewerPoint else opponentPoint
    fun handPoint(playerID: String?): BoardPoint = if (playerID == viewerID) viewerHandPoint else opponentHandPoint
}

/** Drawing helpers; every length is in dp and converted here. */
object BoardFXPainter {
    enum class SparkStyle { RISE, FALL, BURST }

    val gold = BoardFXColors.gold
    val attackRed = BoardFXColors.attackRed
    val blockSteel = BoardFXColors.blockSteel

    fun easeOut(t: Double): Double = 1 - (1 - t.coerceIn(0.0, 1.0)).pow(3)
    fun easeIn(t: Double): Double = t.coerceIn(0.0, 1.0).pow(2.2)

    /** 0 → 1 → 0 envelope over progress with linear fades. */
    fun window(p: Double, fadeIn: Double, fadeOut: Double): Double = when {
        p < fadeIn -> max(0.0, p / fadeIn)
        p > fadeOut -> max(0.0, 1 - (p - fadeOut) / max(0.001, 1 - fadeOut))
        else -> 1.0
    }

    /** Deterministic 0..<1 noise so particles need no stored state (same hash as iOS). */
    fun noise(seed: Int, index: Int, salt: Int): Double {
        var x = ((seed.toLong() * 73_856_093L) xor (index.toLong() * 19_349_663L) xor (salt.toLong() * 83_492_791L))
        x = x xor (x ushr 33); x *= -0xae502812aa7333L; x = x xor (x ushr 33); x *= -0x3b314601e57a13adL; x = x xor (x ushr 33)
        return java.lang.Long.remainderUnsigned(x, 10_000L).toDouble() / 10_000
    }

    private fun DrawScope.px(v: Double): Float = (v * density).toFloat()
    private fun DrawScope.pt(p: BoardPoint): Offset = Offset(p.x * density, p.y * density)
    private fun DrawScope.rect(r: BoardRect): Rect = Rect(r.x * density, r.y * density, (r.x + r.width) * density, (r.y + r.height) * density)
    private fun alpha(c: Color, a: Double): Color = c.copy(alpha = (c.alpha * a).toFloat().coerceIn(0f, 1f))

    fun DrawScope.sparks(from: BoardRect, color: Color, count: Int, p: Double, seed: Int, style: SparkStyle) {
        val t = p * 0.9
        for (i in 0 until count) {
            val ox = from.x + from.width * noise(seed, i, 1); val oy = from.y + from.height * noise(seed, i, 2)
            val speed = 40 + 90 * noise(seed, i, 3)
            val (angle, gravity) = when (style) {
                BoardFXPainter.SparkStyle.RISE -> -PI / 2 + (noise(seed, i, 4) - 0.5) * 0.9 to -30.0
                BoardFXPainter.SparkStyle.FALL -> PI / 2 + (noise(seed, i, 4) - 0.5) * 1.4 to 120.0
                BoardFXPainter.SparkStyle.BURST -> noise(seed, i, 4) * 2 * PI to 60.0
            }
            val x = ox + cos(angle) * speed * t
            val y = oy + sin(angle) * speed * t + gravity * t * t
            val r = (1.2 + 2.2 * noise(seed, i, 5)) * (1 - p * 0.6)
            drawCircle(alpha(color, (1 - p) * (0.6 + 0.4 * noise(seed, i, 6))), px(r), Offset(px(x), px(y)), blendMode = BlendMode.Plus)
        }
    }

    /** Continuous color-identity particles around a showcased card; `fade` scales it all. */
    fun DrawScope.elemental(tint: BoardFXTint, around: BoardRect, elapsed: Double, fade: Double, seed: Int) {
        if (fade <= 0.01) return
        val r = rect(around)
        val grown = Rect(r.left - px(10.0), r.top - px(10.0), r.right + px(10.0), r.bottom + px(10.0))
        drawRoundRect(Brush.radialGradient(listOf(alpha(tint.color, 0.8), Color.Transparent), r.center, max(1f, r.height * 0.75f)),
            grown.topLeft, grown.size, CornerRadius(px(16.0)), alpha = (0.35 * fade).toFloat(), blendMode = BlendMode.Plus)
        val count = if (tint == BoardFXTint.BLACK) 16 else 30
        for (i in 0 until count) {
            val rate = 0.55 + 0.6 * noise(seed, i, 11)
            val life = (elapsed * rate + noise(seed, i, 12)) % 1.0
            val edge = noise(seed, i, 13)
            val side = (noise(seed, i, 14) * 4).toInt()
            val (sx, sy) = when (side) {
                0 -> around.x + around.width * edge to around.maxY.toDouble()
                1 -> around.x + around.width * edge to around.y.toDouble()
                2 -> around.x.toDouble() to around.y + around.height * edge
                else -> around.maxX.toDouble() to around.y + around.height * edge
            }
            val outX = sx - around.midX; val outY = sy - around.midY
            val length = max(1.0, hypot(outX, outY))
            val ux = outX / length; val uy = outY / length
            val a = fade * sin(PI * life)
            when (tint) {
                BoardFXTint.RED -> {
                    val x = sx + sin(elapsed * 6 + i) * 5 + ux * 12 * life
                    val y = sy - 70 * life
                    val rr = 2.6 * (1 - life) + 0.8
                    val c = if (life < 0.4) rgb(1.0, 0.85, 0.4) else rgb(1.0, 0.4, 0.12)
                    drawOval(alpha(c, a * (0.7 + 0.3 * sin(elapsed * 20 + i))), Offset(px(x - rr), px(y - rr * 1.6)), Size(px(rr * 2), px(rr * 3.2)), blendMode = BlendMode.Plus)
                }
                BoardFXTint.BLUE -> {
                    val x = sx + ux * 34 * life; val y = sy + uy * 34 * life + 10 * life
                    val s = 4.5 * (1 - life * 0.5)
                    translate(px(x), px(y)) {
                        rotate(Math.toDegrees(elapsed * 2 + i).toFloat(), Offset.Zero) {
                            val shard = Path().apply {
                                moveTo(0f, px(-s * 1.6)); lineTo(px(s * 0.6), 0f); lineTo(0f, px(s * 1.6)); lineTo(px(-s * 0.6), 0f); close()
                            }
                            drawPath(shard, alpha(rgb(0.78, 0.93, 1.0), a * 0.9), blendMode = BlendMode.Plus)
                        }
                    }
                }
                BoardFXTint.GREEN -> {
                    val x = sx + sin(elapsed * 3 + i * 1.7) * 14 * life + ux * 10 * life; val y = sy - 55 * life
                    translate(px(x), px(y)) {
                        rotate(Math.toDegrees(elapsed * 3 + i).toFloat(), Offset.Zero) {
                            drawOval(alpha(if (i % 3 == 0) rgb(0.8, 1.0, 0.45) else rgb(0.35, 0.85, 0.4), a * 0.85), Offset(px(-4.5), px(-2.0)), Size(px(9.0), px(4.0)), blendMode = BlendMode.Plus)
                        }
                    }
                }
                BoardFXTint.WHITE -> {
                    val x = sx + ux * 8 * life; val y = sy - 40 * life
                    val rr = 3 * (1 - life) + 1
                    drawCircle(alpha(rgb(1.0, 0.96, 0.8).copy(alpha = 0.35f), a * 0.8), px(rr * 2), Offset(px(x), px(y)), blendMode = BlendMode.Plus)
                    drawCircle(alpha(Color.White, a * 0.8), px(rr / 2), Offset(px(x), px(y)), blendMode = BlendMode.Plus)
                }
                BoardFXTint.BLACK -> {
                    val x = sx + ux * 26 * life; val y = sy + uy * 26 * life - 18 * life
                    val rr = 8 + 16 * life
                    drawCircle(alpha(rgb(0.16, 0.05, 0.24), fade * 0.22 * (1 - life)), px(rr), Offset(px(x), px(y)))
                    drawCircle(alpha(rgb(0.78, 0.5, 1.0), a * 0.8), px(1.4), Offset(px(x), px(y)), blendMode = BlendMode.Plus)
                }
                BoardFXTint.MULTICOLOR, BoardFXTint.COLORLESS -> {
                    val x = sx + ux * 10; val y = sy + uy * 10
                    val s = 5 * sin(PI * life)
                    val star = Path().apply {
                        moveTo(px(x), px(y - s)); lineTo(px(x + s * 0.25), px(y)); lineTo(px(x), px(y + s)); lineTo(px(x - s * 0.25), px(y)); close()
                        moveTo(px(x - s), px(y)); lineTo(px(x), px(y + s * 0.25)); lineTo(px(x + s), px(y)); lineTo(px(x), px(y - s * 0.25)); close()
                    }
                    drawPath(star, alpha(if (tint == BoardFXTint.MULTICOLOR) gold else Color(0.92f, 0.92f, 0.92f), a), blendMode = BlendMode.Plus)
                }
            }
        }
    }

    /** Slowly turning light rays behind a hero card. */
    fun DrawScope.rays(at: BoardPoint, color: Color, radius: Double, p: Double, elapsed: Double) {
        val c = pt(at)
        val opacity = 0.5 * window(p, 0.12, 0.8)
        val brush = Brush.radialGradient(listOf(alpha(color, 0.9 * opacity), Color.Transparent), c, max(1f, px(radius)))
        for (i in 0 until 14) {
            val angle = i / 14.0 * 2 * PI + elapsed * 0.35
            val w = 0.09
            val ray = Path().apply {
                moveTo(c.x, c.y)
                lineTo(c.x + (cos(angle - w) * px(radius)).toFloat(), c.y + (sin(angle - w) * px(radius)).toFloat())
                lineTo(c.x + (cos(angle + w) * px(radius)).toFloat(), c.y + (sin(angle + w) * px(radius)).toFloat())
                close()
            }
            drawPath(ray, brush, blendMode = BlendMode.Plus)
        }
    }

    /** Whole-board tint for big spells and commanders; `p` 0...1 over the flash. */
    fun DrawScope.screenFlash(color: Color, p: Double) {
        if (p >= 1) return
        drawRect(alpha(color, 0.32 * (1 - max(0.0, p))), blendMode = BlendMode.Plus)
    }

    fun DrawScope.shockwave(at: BoardPoint, color: Color, maxRadius: Double, p: Double) {
        if (p >= 1) return
        val r = 8 + (maxRadius - 8) * easeOut(p)
        drawCircle(alpha(color, 1 - p), px(r), pt(at), style = Stroke(px(1 + 5 * (1 - p))), blendMode = BlendMode.Plus)
    }

    /** Diagonal claw mark across an attacker as it is declared. */
    fun DrawScope.slash(across: BoardRect, color: Color, p: Double) {
        if (p >= 0.6) return
        val q = p / 0.6
        for (offset in listOf(-8.0, 0.0, 8.0)) {
            val sx = across.x + 4 + offset; val sy = across.y + 4.0
            val ex = across.maxX - 4 + offset; val ey = across.maxY - 4.0
            val k = easeOut(q * 1.6)
            drawLine(alpha(color, 1 - q), Offset(px(sx), px(sy)), Offset(px(sx + (ex - sx) * k), px(sy + (ey - sy) * k)), px(2.5), StrokeCap.Round, blendMode = BlendMode.Plus)
        }
    }

    /** Glowing tether pairing a blocker with its attacker. */
    fun DrawScope.link(from: BoardRect, to: BoardRect, color: Color, p: Double) {
        val o = window(p, 0.15, 0.7)
        val reach = easeOut(p / 0.35)
        val start = Offset(from.midX * density, from.midY * density)
        val end = Offset(to.midX * density, to.midY * density)
        val tip = Offset(start.x + (end.x - start.x) * reach.toFloat(), start.y + (end.y - start.y) * reach.toFloat())
        drawLine(alpha(color, 0.35 * o), start, tip, px(9.0), StrokeCap.Round, blendMode = BlendMode.Plus)
        drawLine(alpha(color, o), start, tip, px(2.5), StrokeCap.Round, PathEffect.dashPathEffect(floatArrayOf(px(7.0), px(5.0)), px(p * 60)), blendMode = BlendMode.Plus)
    }

    /** Motion streak behind a charging attacker. */
    fun DrawScope.trail(from: BoardPoint, to: BoardPoint, color: Color, p: Double) {
        val head = easeIn(p) * 0.82
        val tail = max(0.0, head - 0.3)
        val a = Offset(px(from.x + (to.x - from.x) * tail), px(from.y + (to.y - from.y) * tail))
        val b = Offset(px(from.x + (to.x - from.x) * head), px(from.y + (to.y - from.y) * head))
        drawLine(alpha(color, 0.4 * 0.8), a, b, px(18.0), StrokeCap.Round, blendMode = BlendMode.Plus)
        drawLine(Color.White.copy(alpha = 0.7f * 0.8f), a, b, px(3.0), StrokeCap.Round, blendMode = BlendMode.Plus)
    }

    fun DrawScope.arrivalGlow(r: BoardRect, color: Color, p: Double, motion: Boolean) {
        val grow = if (motion) 14 * easeOut(p) else 0.0
        val frame = Rect(px(r.x - grow), px(r.y - grow), px(r.maxX + grow), px(r.maxY + grow))
        drawRoundRect(alpha(color, 1 - p), frame.topLeft, frame.size, CornerRadius(px(8 + grow / 2)), Stroke(px(1 + 3 * (1 - p))), blendMode = BlendMode.Plus)
        val base = rect(r)
        drawRoundRect(alpha(color, 0.35 * (1 - p)), base.topLeft, base.size, CornerRadius(px(6.0)), blendMode = BlendMode.Plus)
    }

    fun DrawScope.departure(r: BoardRect, color: Color, destination: BoardFXZone?, p: Double, motion: Boolean) {
        val shrink = if (motion) 0.2 * easeOut(p) else 0.0
        val drift = if (motion) (if (destination == BoardFXZone.EXILE) -18.0 else 14.0) * easeOut(p) else 0.0
        val frame = Rect(px(r.x + r.width * shrink / 2), px(r.y + r.height * shrink / 2 + drift), px(r.maxX - r.width * shrink / 2), px(r.maxY - r.height * shrink / 2 + drift))
        val o = 0.7 * (1 - p)
        drawRoundRect(Color.Black.copy(alpha = (0.55 * o).toFloat()), frame.topLeft, frame.size, CornerRadius(px(6.0)))
        drawRoundRect(alpha(color, o), frame.topLeft, frame.size, CornerRadius(px(6.0)), Stroke(px(2.0)))
    }

    fun DrawScope.flash(r: BoardRect, color: Color, p: Double) {
        val base = rect(r)
        drawRoundRect(alpha(color, 0.55 * max(0.0, 1 - p * 2.2)), base.topLeft, base.size, CornerRadius(px(6.0)), blendMode = BlendMode.Plus)
    }

    fun DrawScope.runeBurst(at: BoardPoint, color: Color, p: Double, seed: Int, motion: Boolean) {
        if (p >= 1) return
        val outer = if (motion) 24 + 90 * easeOut(p) else 46.0
        val inner = if (motion) 14 + 50 * easeOut(min(1.0, p * 1.3)) else 30.0
        drawCircle(alpha(color, 1 - p), px(outer), pt(at), style = Stroke(px(2.5)), blendMode = BlendMode.Plus)
        drawCircle(alpha(color, 0.7 * (1 - p)), px(inner), pt(at),
            style = Stroke(px(1.5), pathEffect = PathEffect.dashPathEffect(floatArrayOf(px(4.0), px(6.0)), px(p * 40))), blendMode = BlendMode.Plus)
        if (motion) sparks(BoardRect(at.x - 6, at.y - 6, 12f, 12f), color, 18, p, seed, BoardFXPainter.SparkStyle.BURST)
    }

    fun DrawScope.banner(measurer: TextMeasurer, title: String, subtitle: String?, at: BoardPoint, color: Color, p: Double) {
        val fade = window(p, 0.08, 0.82)
        if (fade <= 0) return
        val text = measurer.measure(title, sf(16f, SfWeight.heavy, SfDesign.SERIF).copy(color = Color.White), maxLines = 1,
            constraints = Constraints(maxWidth = px(300.0).roundToInt()))
        val caption = subtitle?.let { measurer.measure(it, sf(10f, SfWeight.black, tracking = 2f).copy(color = color), maxLines = 1) }
        val captionHeight = if (caption == null) 0f else px(13.0)
        val c = pt(at)
        val frame = Rect(c.x - text.size.width / 2f - px(14.0), c.y - text.size.height / 2f - px(7.0) - captionHeight / 2,
            c.x + text.size.width / 2f + px(14.0), c.y + text.size.height / 2f + px(7.0) + captionHeight / 2)
        val o = fade.toFloat()
        drawRoundRect(Color.Black.copy(alpha = 0.78f * o), frame.topLeft, frame.size, CornerRadius(px(12.0)))
        drawRoundRect(color.copy(alpha = o), frame.topLeft, frame.size, CornerRadius(px(12.0)), Stroke(px(1.5)))
        if (caption != null) {
            drawText(caption, topLeft = Offset(c.x - caption.size.width / 2f, frame.top + px(11.0) - caption.size.height / 2f), alpha = o)
            drawText(text, topLeft = Offset(c.x - text.size.width / 2f, c.y + captionHeight / 2 - text.size.height / 2f), alpha = o)
        } else drawText(text, topLeft = Offset(c.x - text.size.width / 2f, c.y - text.size.height / 2f), alpha = o)
    }

    fun DrawScope.number(measurer: TextMeasurer, value: String, at: BoardPoint, color: Color, size: Double, p: Double, motion: Boolean) {
        val pop = if (motion && p < 0.18) 1 + 0.45 * (1 - p / 0.18) else 1.0
        val rise = if (motion) -34 * easeOut(p) else -8 * p
        val fade = (if (p > 0.65) (1 - p) / 0.35 else 1.0).toFloat()
        val style = sf(size.toFloat(), SfWeight.black, SfDesign.ROUNDED)
        val shadow = measurer.measure(value, style.copy(color = Color.Black.copy(alpha = 0.8f)))
        val text = measurer.measure(value, style.copy(color = color))
        translate(px(at.x.toDouble()), px(at.y + rise)) {
            scale(pop.toFloat(), pop.toFloat(), Offset.Zero) {
                drawText(shadow, topLeft = Offset(px(1.5) - shadow.size.width / 2f, px(2.0) - shadow.size.height / 2f), alpha = fade)
                drawText(text, topLeft = Offset(-text.size.width / 2f, -text.size.height / 2f), alpha = fade)
            }
        }
    }
}

/** One card face moving across the board for an effect. */
class BoardFXFlight(val effect: ActiveBoardFX, val card: ZoneCard, val kind: Kind) {
    sealed class Kind {
        data class Arrive(val from: BoardPoint, val to: BoardRect) : Kind()
        /** Rise to the center, hold long enough to read, then settle into the slot. */
        data class ShowcaseArrive(val from: BoardPoint, val center: BoardPoint, val to: BoardRect, val commander: Boolean) : Kind()
        data class Depart(val from: BoardRect, val to: BoardPoint, val destination: BoardFXZone?) : Kind()
        data class Cast(val from: BoardPoint, val to: BoardPoint, val weight: BoardFXSpellWeight) : Kind()
        /** Wind up, charge the target, hit, and return to the slot. */
        data class Strike(val from: BoardRect, val to: BoardPoint) : Kind()
    }

    data class Placement(val center: BoardPoint, val size: BoardSize, val scale: Double, val rotation: Double, val opacity: Double,
                         val fullCard: Boolean = false, val lift: Double = 0.0)

    sealed class Shading {
        object None : Shading()
        data class Dissolve(val progress: Double, val edge: Color) : Shading()
        data class Foil(val phase: Double) : Shading()
    }

    val id: Int get() = effect.id

    fun shading(p: Double): Shading = when {
        kind is Kind.Depart && dissolves(kind.destination) ->
            Shading.Dissolve(p, if (kind.destination == BoardFXZone.EXILE) rgb(0.75, 0.92, 1.0) else rgb(1.0, 0.52, 0.12))
        kind is Kind.Cast || kind is Kind.ShowcaseArrive -> Shading.Foil(p * 2.2)
        else -> Shading.None
    }

    private fun showcase(from: BoardPoint, center: BoardPoint, size: BoardSize, p: Double, duration: Double, holdEnd: Double): Placement {
        val rise = min(0.3, 0.42 / duration)
        if (p < rise) {
            val t = BoardFXPainter.easeOut(p / rise)
            return Placement(arc(from, center, 50.0, t), size, 0.45 + 0.6 * t, -8 * (1 - t), min(1.0, p / rise * 3), true, t)
        }
        // Hold still (a slow breath) so the card can be read.
        val hold = (p - rise) / max(0.001, holdEnd - rise)
        val bob = sin(min(hold, 1.0) * PI * 2) * 3
        return Placement(BoardPoint(center.x, (center.y + bob).toFloat()), size, 1.05 - 0.05 * min(hold, 1.0), 0.0, 1.0, true, 1.0)
    }

    fun placement(p: Double): Placement? {
        val duration = effect.scheduled.duration
        return when (kind) {
            is Kind.Arrive -> {
                val landing = BoardFXScheduler.arrivalFlightFraction
                if (p >= landing) null else {
                    val t = BoardFXPainter.easeOut(p / landing)
                    Placement(arc(kind.from, BoardPoint(kind.to.midX, kind.to.midY), 60.0, t), BoardSize(kind.to.width, kind.to.height),
                        1.35 - 0.35 * t, -8 * (1 - t), min(1.0, p / landing * 4), lift = 1 - t)
                }
            }
            is Kind.ShowcaseArrive -> {
                val landing = BoardFXScheduler.landingFraction(if (kind.commander) BoardFXEntrance.COMMANDER else BoardFXEntrance.SHOWCASE)
                if (p >= landing) return null
                val size = castSize(if (kind.commander) BoardFXSpellWeight.COMMANDER else BoardFXSpellWeight.SPELL)
                val settle = landing - min(0.2, 0.48 / duration)
                if (p < settle) return showcase(kind.from, kind.center, size, p, duration, settle)
                // Settle into the slot, shrinking to the tile's width.
                val t = BoardFXPainter.easeIn((p - settle) / (landing - settle))
                val finalScale = kind.to.width / size.width
                Placement(arc(kind.center, BoardPoint(kind.to.midX, kind.to.midY), 20.0, t), size, 1 - (1 - finalScale) * t, 0.0, 1.0, true, 1 - t)
            }
            is Kind.Depart -> if (dissolves(kind.destination)) {
                // Burn away in place with a slight lift; the shader does the rest.
                val t = BoardFXPainter.easeOut(p)
                Placement(BoardPoint(kind.from.midX, (kind.from.midY - 10 * t).toFloat()), BoardSize(kind.from.width, kind.from.height), 1 + 0.06 * t, 0.0, 1.0, lift = t * 0.3)
            } else {
                val t = p * p
                Placement(arc(BoardPoint(kind.from.midX, kind.from.midY), kind.to, 30.0, t), BoardSize(kind.from.width, kind.from.height),
                    1 - 0.6 * t, 14 * t, 1 - t, lift = 0.4)
            }
            is Kind.Cast -> {
                val size = castSize(kind.weight)
                // Exit: shrink toward the stack and fade over the last third of a second.
                val exit = 1 - min(0.3, 0.35 / duration)
                if (p < exit) showcase(kind.from, kind.to, size, p, duration, exit)
                else {
                    val t = BoardFXPainter.easeIn((p - exit) / (1 - exit))
                    Placement(kind.to, size, 1 - 0.45 * t, 0.0, 1 - t, true, 1 - t)
                }
            }
            is Kind.Strike -> {
                val home = BoardPoint(kind.from.midX, kind.from.midY)
                val dx = (kind.to.x - home.x).toDouble(); val dy = (kind.to.y - home.y).toDouble()
                val distance = max(1.0, hypot(dx, dy))
                val ux = dx / distance; val uy = dy / distance
                val windup = 0.15; val impact = BoardFXScheduler.strikeImpactFraction; val recoil = impact + 0.1
                // Stop with the card's leading edge on the target.
                val reach = max(0.0, distance - kind.from.height * 0.45)
                val hit = BoardPoint((home.x + ux * reach).toFloat(), (home.y + uy * reach).toFloat())
                val back = BoardPoint((home.x - ux * 14).toFloat(), (home.y - uy * 14).toFloat())
                val tilt = if (ux >= 0) 1.0 else -1.0
                val size = BoardSize(kind.from.width, kind.from.height)
                when {
                    p < windup -> { val t = BoardFXPainter.easeOut(p / windup); Placement(lerp(home, back, t), size, 1 + 0.1 * t, -5 * tilt * t, 1.0, lift = t) }
                    p < impact -> {
                        val t = BoardFXPainter.easeIn((p - windup) / (impact - windup))
                        Placement(lerp(back, hit, t), size, 1.1 + 0.08 * t, -5 * tilt * (1 - t) + 6 * tilt * t, 1.0, lift = 1.0)
                    }
                    // Brief squash on contact.
                    p < recoil -> Placement(hit, size, 1.12, 6 * tilt, 1.0, lift = 0.8)
                    else -> {
                        val t = BoardFXPainter.easeOut((p - recoil) / (1 - recoil))
                        Placement(lerp(hit, home, t), size, 1.12 - 0.12 * t, 6 * tilt * (1 - t), 1.0, lift = 0.8 * (1 - t))
                    }
                }
            }
        }
    }

    companion object {
        /** Showcase size: large enough to read the card at the center of the board. */
        fun castSize(weight: BoardFXSpellWeight): BoardSize = when (weight) {
            BoardFXSpellWeight.ABILITY -> BoardSize(76f, 106f)
            BoardFXSpellWeight.SPELL -> BoardSize(150f, 210f)
            BoardFXSpellWeight.BIG, BoardFXSpellWeight.COMMANDER -> BoardSize(166f, 232f)
        }

        /** Quadratic arc between two points, lifted toward the top of the screen. */
        fun arc(a: BoardPoint, b: BoardPoint, lift: Double, t: Double): BoardPoint {
            val cx = (a.x + b.x) / 2.0; val cy = min(a.y, b.y) - lift
            val u = 1 - t
            return BoardPoint((u * u * a.x + 2 * u * t * cx + t * t * b.x).toFloat(), (u * u * a.y + 2 * u * t * cy + t * t * b.y).toFloat())
        }

        fun lerp(a: BoardPoint, b: BoardPoint, t: Double) = BoardPoint((a.x + (b.x - a.x) * t).toFloat(), (a.y + (b.y - a.y) * t).toFloat())

        /** Graveyard (or unknown) and exile departures burn away; bounces fly. */
        fun dissolves(destination: BoardFXZone?): Boolean = destination == null || destination == BoardFXZone.GRAVEYARD || destination == BoardFXZone.EXILE
    }
}

/** The board's effect layer: particle Canvas plus flying card faces. */
@Composable
fun BoardFXOverlay(effects: List<ActiveBoardFX>, subjects: Map<String, ZoneCard>, cardBounds: Map<String, BoardRect>, anchors: BoardFXAnchors,
                   clock: BoardFXClock, prune: () -> Unit, modifier: Modifier = Modifier) {
    val lastKnownBounds = remember { HashMap<String, BoardRect>() }
    lastKnownBounds.putAll(cardBounds)
    if (lastKnownBounds.size > 400) { lastKnownBounds.clear(); lastKnownBounds.putAll(cardBounds) }
    if (effects.isEmpty()) return
    val measurer = rememberTextMeasurer()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(effects) { while (true) withFrameMillis { now = System.currentTimeMillis() } }
    LaunchedEffect(effects.lastOrNull()?.id) {
        // Wait for the last effect's end on the frame clock; batches not yet drawn count from now.
        while (true) {
            val current = System.currentTimeMillis()
            val end = effects.maxOfOrNull { (clock.origin(it.start) ?: current) + (it.scheduled.end * 1000).toLong() } ?: current
            val wait = end - current + 50
            if (wait <= 50 && effects.all { clock.origin(it.start) != null }) break
            kotlinx.coroutines.delay(maxOf(wait, 50))
        }
        prune()
    }
    clock.observe(effects, now)

    fun rect(id: String): BoardRect? = cardBounds[id] ?: lastKnownBounds[id]
    fun point(target: BoardFXStrikeTarget): BoardPoint? = when (target) {
        is BoardFXStrikeTarget.Card -> rect(target.id)?.let { BoardPoint(it.midX, it.midY) }
        is BoardFXStrikeTarget.Player -> anchors.playerPoint(target.id)
    }
    fun progress(effect: ActiveBoardFX): Double? {
        val origin = clock.origin(effect.start) ?: return null
        val elapsed = (now - origin) / 1000.0 - effect.scheduled.delay
        if (elapsed < 0 || elapsed > effect.scheduled.duration) return null
        return elapsed / effect.scheduled.duration
    }

    val flights = effects.mapNotNull { effect ->
        val fx = effect.scheduled
        val card = subjects[fx.event.subjectID]
        if (!fx.usesMotion || card == null) return@mapNotNull null
        when (val event = fx.event) {
            is BoardFXEvent.EnteredBattlefield -> {
                val target = rect(event.cardID) ?: return@mapNotNull null
                val origin = if (event.from == BoardFXZone.STACK) anchors.stackPoint else anchors.handPoint(event.playerID)
                val kind = if (event.entrance == BoardFXEntrance.PLAIN) BoardFXFlight.Kind.Arrive(origin, target)
                    else BoardFXFlight.Kind.ShowcaseArrive(origin, anchors.stackPoint, target, event.entrance == BoardFXEntrance.COMMANDER)
                BoardFXFlight(effect, card, kind)
            }
            is BoardFXEvent.LeftBattlefield -> {
                val origin = rect(event.cardID) ?: return@mapNotNull null
                val target = if (event.to == BoardFXZone.HAND) anchors.handPoint(event.playerID) else anchors.playerPoint(event.playerID)
                BoardFXFlight(effect, card, BoardFXFlight.Kind.Depart(origin, target, event.to))
            }
            is BoardFXEvent.SpellCast -> BoardFXFlight(effect, card, BoardFXFlight.Kind.Cast(anchors.handPoint(event.controllerID), anchors.stackPoint, event.weight))
            is BoardFXEvent.CombatStrike -> {
                val origin = rect(event.attackerID) ?: return@mapNotNull null
                val hit = point(event.target) ?: return@mapNotNull null
                BoardFXFlight(effect, card, BoardFXFlight.Kind.Strike(origin, hit))
            }
            else -> null
        }
    }

    Box(modifier.fillMaxSize()) {
        Canvas(Modifier.fillMaxSize()) {
            for (effect in effects) {
                val p = progress(effect) ?: continue
                drawEffect(effect.scheduled, p, p * effect.scheduled.duration, measurer, anchors, subjects, ::rect, ::point)
            }
        }
        for (flight in flights) key(flight.id) {
            val p = progress(flight.effect) ?: return@key
            val placement = flight.placement(p) ?: return@key
            val w = placement.size.width; val h = placement.size.height
            val shading = flight.shading(p)
            val shaded = when (shading) {
                is BoardFXFlight.Shading.Dissolve -> Modifier.dissolveEffect(shading.progress.toFloat(), shading.edge)
                is BoardFXFlight.Shading.Foil -> Modifier.foilEffect(shading.phase.toFloat(), 1f)
                BoardFXFlight.Shading.None -> Modifier
            }
            Box(Modifier.offset { IntOffset(((placement.center.x - w / 2) * density).roundToInt(), ((placement.center.y - h / 2) * density).roundToInt()) }
                .requiredSize(w.dp, h.dp)
                .graphicsLayer {
                    scaleX = placement.scale.toFloat(); scaleY = placement.scale.toFloat()
                    rotationZ = placement.rotation.toFloat(); alpha = placement.opacity.toFloat().coerceIn(0f, 1f)
                }
                .drawBehind {
                    // Deeper shadow when held high above the table.
                    drawIntoCanvas { canvas ->
                        val paint = Paint()
                        val frame = paint.asFrameworkPaint()
                        frame.color = Color.Black.copy(alpha = 0.55f).toArgb()
                        frame.maskFilter = BlurMaskFilter(((10 + 8 * placement.lift) * density).toFloat(), BlurMaskFilter.Blur.NORMAL)
                        val dy = ((6 + 10 * placement.lift) * density).toFloat()
                        canvas.drawRoundRect(0f, dy, size.width, size.height + dy, 6.dp.toPx(), 6.dp.toPx(), paint)
                    }
                }
                .then(shaded)) {
                if (placement.fullCard) CardTile(flight.card, false, zoneName = "Effect", width = w.dp, height = h.dp, ignoreTappedRotation = true)
                // Same frame as the battlefield tile, so take-off and landing are seamless.
                else ArenaBattlefieldCard(flight.card, "Effect", w.dp, h.dp)
            }
        }
    }
}

private fun DrawScope.drawEffect(fx: ScheduledBoardFX, p: Double, elapsed: Double, measurer: TextMeasurer, anchors: BoardFXAnchors,
                                 subjects: Map<String, ZoneCard>, rect: (String) -> BoardRect?, point: (BoardFXStrikeTarget) -> BoardPoint?) = with(BoardFXPainter) {
    val motion = fx.usesMotion
    when (val event = fx.event) {
        is BoardFXEvent.SpellCast -> {
            val center = anchors.stackPoint
            val showcase = BoardFXFlight.castSize(event.weight)
            val heroColor = if (event.weight == BoardFXSpellWeight.COMMANDER) gold else event.tint.color
            if (event.weight == BoardFXSpellWeight.BIG || event.weight == BoardFXSpellWeight.COMMANDER) {
                screenFlash(heroColor, elapsed / 0.6)
                if (motion) rays(center, heroColor, showcase.height * 1.3, p, elapsed)
            }
            runeBurst(center, event.tint.color, min(1.0, elapsed / 1.1), fx.id, motion)
            if (motion && event.weight != BoardFXSpellWeight.ABILITY) {
                val hold = BoardRect(center.x - showcase.width / 2, center.y - showcase.height / 2, showcase.width, showcase.height)
                elemental(event.tint, hold, elapsed, window(p, 0.12, 0.85), fx.id)
            }
            val bannerY = center.y + if (event.weight == BoardFXSpellWeight.ABILITY || !motion) 54f else showcase.height / 2 + 22
            banner(measurer, event.name, if (event.weight == BoardFXSpellWeight.COMMANDER) "COMMANDER" else null, BoardPoint(center.x, bannerY), heroColor, p)
        }
        is BoardFXEvent.EnteredBattlefield -> {
            val r = rect(event.cardID) ?: return@with
            // With a flight, the glow is the landing; without one it plays immediately.
            val flying = motion && subjects[event.cardID] != null
            val landing = if (flying) BoardFXScheduler.landingFraction(event.entrance) else 0.0
            if (flying && event.entrance != BoardFXEntrance.PLAIN && p < landing) {
                val center = anchors.stackPoint
                val showcase = BoardFXFlight.castSize(if (event.entrance == BoardFXEntrance.COMMANDER) BoardFXSpellWeight.COMMANDER else BoardFXSpellWeight.SPELL)
                val hold = BoardRect(center.x - showcase.width / 2, center.y - showcase.height / 2, showcase.width, showcase.height)
                val fade = window(p / landing, 0.15, 0.75)
                if (event.entrance == BoardFXEntrance.COMMANDER) {
                    screenFlash(gold, elapsed / 0.7)
                    rays(center, gold, showcase.height * 1.35, p / landing, elapsed)
                }
                elemental(event.tint, hold, elapsed, fade, fx.id)
                subjects[event.cardID]?.card?.name?.let { name ->
                    banner(measurer, name, if (event.entrance == BoardFXEntrance.COMMANDER) "COMMANDER" else null,
                        BoardPoint(center.x, center.y + showcase.height / 2 + 22), if (event.entrance == BoardFXEntrance.COMMANDER) gold else event.tint.color,
                        min(1.0, p / (landing * 0.8)))
                }
            }
            if (flying && p < landing) return@with
            val glow = if (flying) (p - landing) / (1 - landing) else p
            val color = if (event.entrance == BoardFXEntrance.COMMANDER) gold else event.tint.color
            arrivalGlow(r, color, glow, motion)
            if (motion) {
                sparks(r, color, if (event.entrance == BoardFXEntrance.COMMANDER) 34 else 16, glow, fx.id, BoardFXPainter.SparkStyle.RISE)
                if (event.entrance == BoardFXEntrance.COMMANDER) shockwave(BoardPoint(r.midX, r.midY), color, 150.0, glow)
            }
        }
        is BoardFXEvent.LeftBattlefield -> {
            val r = rect(event.cardID) ?: return@with
            if (!(motion && subjects[event.cardID] != null)) departure(r, event.tint.color, event.to, p, motion)
            if (motion) {
                val exile = event.to == BoardFXZone.EXILE
                sparks(r, if (exile) rgb(0.72, 0.9, 1.0) else rgb(1.0, 0.45, 0.16), 22, p, fx.id, if (exile) BoardFXPainter.SparkStyle.RISE else BoardFXPainter.SparkStyle.FALL)
            }
        }
        is BoardFXEvent.DamageMarked -> {
            val r = rect(event.cardID) ?: return@with
            flash(r, Color.Red, p)
            if (motion) sparks(r, rgb(1.0, 0.3, 0.2), 12, p, fx.id, BoardFXPainter.SparkStyle.BURST)
            number(measurer, "-${event.amount}", BoardPoint(r.midX, r.midY), rgb(1.0, 0.32, 0.28), 26.0, p, motion)
        }
        is BoardFXEvent.CountersAdded -> {
            val r = rect(event.cardID) ?: return@with
            if (motion) sparks(r, rgb(0.55, 1.0, 0.55), 10, p, fx.id, BoardFXPainter.SparkStyle.RISE)
            number(measurer, "+${event.amount}", BoardPoint(r.midX, r.y + 12), rgb(0.55, 1.0, 0.55), 20.0, p, motion)
        }
        is BoardFXEvent.AttackDeclared -> {
            val r = rect(event.cardID) ?: return@with
            arrivalGlow(r, attackRed, p, motion)
            if (motion) { sparks(r, event.tint.color, 10, p, fx.id, BoardFXPainter.SparkStyle.BURST); slash(r, attackRed, p) }
        }
        is BoardFXEvent.BlockDeclared -> {
            val blocker = rect(event.cardID) ?: return@with
            arrivalGlow(blocker, blockSteel, p, motion)
            rect(event.attackerID)?.let { link(blocker, it, blockSteel, p) }
        }
        is BoardFXEvent.CombatStrike -> {
            val origin = rect(event.attackerID) ?: return@with
            val hit = point(event.target) ?: return@with
            val impact = BoardFXScheduler.strikeImpactFraction
            if (motion && p > 0.15 && p < impact + 0.05) trail(BoardPoint(origin.midX, origin.midY), hit, event.tint.color, (p - 0.15) / (impact - 0.15))
            if (p >= impact) {
                val q = (p - impact) / (1 - impact)
                shockwave(hit, attackRed, if (motion) 70.0 else 40.0, q)
                if (motion) sparks(BoardRect(hit.x - 30, hit.y - 30, 60f, 60f), rgb(1.0, 0.75, 0.35), 20, q, fx.id, BoardFXPainter.SparkStyle.BURST)
            }
        }
        is BoardFXEvent.LifeChanged -> {
            val at = anchors.playerPoint(event.playerID)
            val color = if (event.delta < 0) rgb(1.0, 0.3, 0.26) else rgb(0.45, 1.0, 0.55)
            // Bigger swings read bigger.
            val size = min(64.0, 34 + abs(event.delta) * 2.5)
            number(measurer, if (event.delta < 0) "${event.delta}" else "+${event.delta}", at, color, size, p, motion)
        }
    }
}

/** Board events to recorded cues (Swift BoardFXSound). */
object BoardFXSound {
    data class Arrival(val isLand: Boolean = false, val isToken: Boolean = false)
    data class Cue(val sound: GameSound, val at: Double, val volume: Float = 1f)

    fun play(scheduled: List<ScheduledBoardFX>, viewerID: String, arrivals: Map<String, Arrival> = emptyMap()) {
        val hasStrike = scheduled.any { it.event is BoardFXEvent.CombatStrike }
        for (cue in cues(scheduled, viewerID, arrivals, hasStrike)) GameAudio.play(cue.sound, cue.at, cue.volume)
    }

    fun cues(scheduled: List<ScheduledBoardFX>, viewerID: String, arrivals: Map<String, Arrival>, hasStrike: Boolean): List<Cue> {
        val cues = mutableListOf<Cue>()
        for (fx in scheduled) when (val event = fx.event) {
            is BoardFXEvent.SpellCast -> {
                // Opponents' spells sit a little further back in the mix.
                val level = if (event.controllerID == viewerID) 1f else 0.75f
                when (event.weight) {
                    // Only your own abilities chime; a pod's triggers would otherwise chatter.
                    BoardFXSpellWeight.ABILITY -> if (event.controllerID == viewerID) cues += Cue(GameSound.ABILITY, fx.delay)
                    BoardFXSpellWeight.COMMANDER -> cues += Cue(GameSound.COMMANDER_CAST, fx.delay, level)
                    BoardFXSpellWeight.BIG -> { cues += Cue(GameSound.cast(event.tint), fx.delay, level); cues += Cue(GameSound.SPELL_BIG, fx.delay + 0.05, level) }
                    BoardFXSpellWeight.SPELL -> cues += Cue(GameSound.cast(event.tint), fx.delay, level)
                }
            }
            is BoardFXEvent.AttackDeclared -> cues += Cue(GameSound.ATTACK, fx.delay)
            is BoardFXEvent.BlockDeclared -> cues += Cue(GameSound.BLOCK, fx.delay)
            is BoardFXEvent.CombatStrike -> cues += Cue(if (event.target == BoardFXStrikeTarget.Player(viewerID)) GameSound.PLAYER_HIT else GameSound.STRIKE, fx.handoff)
            is BoardFXEvent.DamageMarked -> if (!hasStrike) cues += Cue(GameSound.STRIKE, fx.delay, 0.7f)
            is BoardFXEvent.LeftBattlefield -> cues += when (event.to) {
                BoardFXZone.EXILE -> Cue(GameSound.EXILE, fx.delay)
                BoardFXZone.HAND, BoardFXZone.LIBRARY -> Cue(GameSound.CARD_PICKUP, fx.delay)
                else -> Cue(GameSound.DEATH, fx.delay)
            }
            is BoardFXEvent.EnteredBattlefield -> {
                val arrival = arrivals[event.cardID] ?: Arrival()
                val sound = if (event.entrance == BoardFXEntrance.COMMANDER) GameSound.CREATURE_ENTER
                    else if (arrival.isLand) GameSound.LAND_DROP else if (arrival.isToken) GameSound.TOKEN_CREATE else GameSound.CREATURE_ENTER
                cues += Cue(sound, fx.landing)
            }
            is BoardFXEvent.CountersAdded -> cues += Cue(GameSound.COUNTER, fx.delay)
            is BoardFXEvent.LifeChanged -> if (event.delta > 0) cues += Cue(GameSound.LIFE_GAIN, fx.delay, if (event.playerID == viewerID) 1f else 0.55f)
                else if (event.playerID == viewerID && !hasStrike) cues += Cue(GameSound.LIFE_LOSS, fx.delay)
        }
        return cues
    }
}
