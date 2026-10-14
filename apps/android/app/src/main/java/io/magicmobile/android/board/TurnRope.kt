package io.magicmobile.android.board

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.TurnClockBoard
import io.magicmobile.android.game.TurnClockRules
import io.magicmobile.android.ui.TavernPalette
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

private fun uptime(): Double = android.os.SystemClock.elapsedRealtime() / 1000.0

/**
 * What the online turn timer shows (iOS TurnClockFeed). Each value is read lazily from the table's
 * snapshot state, so a clock tick recomposes only the rings, not the board under the provider.
 */
@Stable
class TurnClockFeed(private val boardSource: () -> TurnClockBoard, private val localSeatSource: () -> String?,
                    private val seatNamesSource: () -> Map<String, String>) {
    val board: TurnClockBoard get() = boardSource()
    val localSeat: String? get() = localSeatSource()
    val seatNames: Map<String, String> get() = seatNamesSource()

    /** The seat a board player sits in: seat names are unique and are the engine's player names. */
    fun seat(named: String?): String? = named?.let { name -> seatNames.entries.firstOrNull { it.value == name }?.key }
}

/** The online table's turn clocks; null in solo games, which have no clock. */
val LocalTurnClock = compositionLocalOf<TurnClockFeed?> { null }

/**
 * The online turn timer (iOS TurnRope.swift; it replaced the burning rope, 2026-10-13): for the last
 * [TurnClockRules.rope] seconds of a seat's decision an ember runs clockwise round a ring, eating the
 * glowing arc behind it; the arc turns ember red for the last 5 seconds. Your own clock rings the pass
 * button and an opponent's rings their medallion, so whose time it is needs no words. Timeouts show
 * as studs at three o'clock. [playerName] is the table name of whose clock to show; null is yours.
 */
@Composable
fun TurnClockRing(feed: TurnClockFeed, playerName: String?, diameter: Dp, modifier: Modifier = Modifier) {
    val seat = if (playerName != null) feed.seat(playerName) else feed.localSeat
    val localSeat = feed.localSeat
    val all = feed.board
    // Only this seat's clock; the board's own pick prefers yours and then the soonest.
    val board = remember(all, seat) { TurnClockBoard(all.paused, all.clocks.filter { it.seat == seat }) }
    val isLocal = seat != null && seat == localSeat
    var burning by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    // Sleeps until the ring should light, then until it burns out.
    LaunchedEffect(board, seat) {
        while (true) {
            val now = uptime()
            val wait = seat?.let { board.secondsUntilRope(it, now) }
            if (wait == null) { burning = false; break }
            if (wait > 0) { burning = false; delay((wait * 1000).toLong()) }
            else {
                if (!burning && isLocal) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                burning = true
                delay(((board.rope(seat, now)?.remaining ?: 0.0) * 1000).toLong() + 250)
            }
        }
    }
    if (!burning || seat == null) return
    // Redrawn at 30 Hz only while the ring burns; nothing ticks before that.
    val now by produceState(uptime(), board) {
        while (true) { delay(33); value = uptime() }
    }
    val rope = board.rope(seat, now) ?: return
    TurnClockRingFace(rope, isLocal, feed.seatNames[seat], diameter, now, modifier)
}

private val frost = Color(0.45f, 0.72f, 1f)

/** The ring itself: a dark groove, the arc of time left from the ember back to twelve o'clock, the ember, and the timeout studs. */
@Composable
private fun TurnClockRingFace(rope: TurnClockBoard.Rope, isLocal: Boolean, name: String?, diameter: Dp, time: Double, modifier: Modifier) {
    var label = if (isLocal) "Your time" else "${name ?: "Opponent"}’s time"
    if (rope.strikes > 0) label += ", timeout ${rope.strikes} of ${TurnClockRules.ONLINE.strikesToForfeit}"
    val seconds = kotlin.math.ceil(rope.remaining).toInt()
    val reduceMotion = BoardMotion.reduceMotion
    val urgent = rope.remaining <= 5
    val flicker = if (reduceMotion) 1f else (1 + 0.18 * sin(time * 23) * cos(time * 7)).toFloat()
    val pulse = if (urgent && !reduceMotion) (0.5 + 0.5 * sin(time * 9)).toFloat() else 0f
    // Hottest next to the ember, cooling toward twelve o'clock. An opponent's burns cold blue until
    // the last 5 seconds, so it stands off their brass frame (and off your own ring).
    val arcColors = when {
        urgent -> listOf(Color(1f, 0.78f, 0.55f), TavernPalette.ember, TavernPalette.enamel)
        isLocal -> listOf(TavernPalette.parchment, TavernPalette.brass, TavernPalette.brassDark)
        else -> listOf(Color(0.88f, 0.95f, 1f), frost, Color(0.12f, 0.26f, 0.52f))
    }
    val spark = if (urgent || isLocal) TavernPalette.ember else frost
    val glow = if (urgent) TavernPalette.ember else if (isLocal) TavernPalette.brass else frost
    val fraction = rope.fraction.toFloat()
    Canvas(modifier.requiredSize(diameter).semantics { contentDescription = "$label, $seconds seconds left" }) {
        val lineWidth = max(4.dp.toPx(), size.minDimension * 0.055f)
        val radius = size.minDimension / 2 - lineWidth / 2
        val arcTopLeft = Offset(center.x - radius, center.y - radius)
        val arcSize = Size(radius * 2, radius * 2)
        drawCircle(Color.Black.copy(alpha = 0.55f), radius, style = Stroke(lineWidth + 2.dp.toPx()))
        // The arc of time left runs from the ember (clockwise from twelve) round to twelve o'clock.
        val start = -90f + (1 - fraction) * 360f
        val sweep = fraction * 360f
        // A soft halo under the arc stands in for SwiftUI's shadow.
        drawArc(glow.copy(alpha = (0.25f + 0.2f * pulse)), start, sweep, false, arcTopLeft, arcSize,
            style = Stroke(lineWidth * (2.2f + pulse), cap = StrokeCap.Round))
        // The sweep gradient starts at three o'clock; turned a quarter back, its stops line up with the arc.
        rotate(-90f) {
            val from = (1 - fraction).coerceIn(0f, 0.999f)
            val mid = from + (1 - from) / 2
            drawArc(Brush.sweepGradient(0f to arcColors[0], from to arcColors[0], mid to arcColors[1], 1f to arcColors[2], center = center),
                start + 90f, sweep, false, arcTopLeft, arcSize, style = Stroke(lineWidth, cap = StrokeCap.Round))
        }
        // Timeouts in a row: studs on the groove at three o'clock (twelve sits under the camera on the
        // opponent's medallion), lit for each one.
        if (rope.strikes > 0) {
            for (index in 0 until TurnClockRules.ONLINE.strikesToForfeit) {
                val stud = Math.toRadians((index - 1) * 11.0)
                val at = Offset(center.x + radius * cos(stud).toFloat(), center.y + radius * sin(stud).toFloat())
                val lit = index < rope.strikes
                if (lit) drawCircle(TavernPalette.ember.copy(alpha = 0.5f), lineWidth * 1.3f, at)
                drawCircle(if (lit) TavernPalette.ember else TavernPalette.brassDark, lineWidth * 0.75f, at)
                drawCircle(TavernPalette.brass, lineWidth * 0.75f, at, style = Stroke(1.dp.toPx()))
            }
        }
        val angle = Math.toRadians(start.toDouble())
        val ember = Offset(center.x + radius * cos(angle).toFloat(), center.y + radius * sin(angle).toFloat())
        val emberRadius = lineWidth * 1.4f * flicker
        drawCircle(Brush.radialGradient(listOf(spark.copy(alpha = 0.55f), Color.Transparent), ember, emberRadius * 2f), emberRadius * 2f, ember)
        drawCircle(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.95f), spark, spark.copy(alpha = 0f)), ember, emberRadius), emberRadius, ember)
    }
}
