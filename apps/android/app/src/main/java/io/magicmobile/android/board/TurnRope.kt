package io.magicmobile.android.board

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.TurnClockBoard
import io.magicmobile.android.game.TurnClockRules
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernTag
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

private fun uptime(): Double = android.os.SystemClock.elapsedRealtime() / 1000.0

/**
 * The online turn timer's burning rope (iOS TurnRope.swift), laid across the middle of the table for
 * the last [TurnClockRules.rope] seconds of a decision. It only reads the table's [TurnClockBoard];
 * the host's TurnClock decides what a timeout does.
 */
@Composable
fun TurnRopeOverlay(board: TurnClockBoard, localSeat: String?, seatNames: Map<String, String>) {
    var burning by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    // Sleeps until the rope should light, then until it burns out.
    LaunchedEffect(board, localSeat) {
        while (true) {
            val now = uptime()
            val wait = board.secondsUntilRope(localSeat, now)
            if (wait == null) { burning = false; break }
            if (wait > 0) { burning = false; delay((wait * 1000).toLong()) }
            else {
                val rope = board.rope(localSeat, now)
                if (!burning && rope?.isLocal == true) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                burning = true
                delay(((rope?.remaining ?: 0.0) * 1000).toLong() + 250)
            }
        }
    }
    if (!burning) return
    // Redrawn at 20 Hz only while a rope burns; nothing ticks before that.
    val now by produceState(uptime(), board) {
        while (true) { delay(50); value = uptime() }
    }
    val rope = board.rope(localSeat, now) ?: return
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        TurnRope(rope, seatNames[rope.seat], now)
    }
}

@Composable
private fun TurnRope(rope: TurnClockBoard.Rope, name: String?, time: Double) {
    var label = if (rope.isLocal) "Your time" else "${name ?: "Opponent"}’s time"
    if (rope.strikes > 0) label += " · timeout ${rope.strikes} of ${TurnClockRules.ONLINE.strikesToForfeit}"
    label = label.uppercase()
    val seconds = kotlin.math.ceil(rope.remaining).toInt()
    Column(Modifier.fillMaxWidth().padding(horizontal = 28.dp).semantics { contentDescription = "$label, $seconds seconds left" },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        TavernTag(label, leather = true, accent = if (rope.remaining <= 5) TavernPalette.ember else TavernPalette.brass)
        val flicker = if (BoardMotion.reduceMotion) 1f else (1 + 0.18 * sin(time * 23) * cos(time * 7)).toFloat()
        Canvas(Modifier.fillMaxWidth().height(22.dp)) {
            val width = size.width
            val burnX = width * (1 - rope.fraction).toFloat()
            val centerY = size.height / 2
            // The burnt-out stretch: a scorched line.
            val scorch = 3.dp.toPx()
            drawRoundRect(Color.Black.copy(alpha = 0.45f), Offset(0f, centerY - scorch / 2), Size(max(0f, burnX), scorch), CornerRadius(scorch / 2))
            // What is left of the rope: brass-and-hemp with diagonal twists.
            val strand = 9.dp.toPx()
            val top = centerY - strand / 2
            val ropeWidth = max(0f, width - burnX)
            if (ropeWidth > 0f) {
                val capsule = Path().apply {
                    addRoundRect(androidx.compose.ui.geometry.RoundRect(burnX, top, width, top + strand, CornerRadius(strand / 2)))
                }
                drawPath(capsule, Color.Black.copy(alpha = 0.35f), style = Stroke(2.dp.toPx()))
                drawPath(capsule, Brush.verticalGradient(listOf(TavernPalette.parchment, TavernPalette.brass, TavernPalette.brassDark), top, top + strand))
                clipPath(capsule) {
                    var x = burnX - strand
                    val step = 7.dp.toPx()
                    while (x < width + strand) {
                        drawLine(TavernPalette.brassDark.copy(alpha = 0.55f), Offset(x, top + strand), Offset(x + strand, top), 1.6.dp.toPx())
                        x += step
                    }
                }
            }
            // The ember at the burning end.
            val ember = 11.dp.toPx() * flicker
            drawCircle(Brush.radialGradient(listOf(TavernPalette.ember.copy(alpha = 0.55f), Color.Transparent),
                Offset(burnX, centerY), ember * 1.8f), ember * 1.8f, Offset(burnX, centerY))
            drawCircle(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.95f), TavernPalette.ember, TavernPalette.enamel.copy(alpha = 0f)),
                Offset(burnX, centerY), ember), ember, Offset(burnX, centerY))
        }
    }
}
