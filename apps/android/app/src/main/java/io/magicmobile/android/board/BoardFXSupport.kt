package io.magicmobile.android.board

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.ActiveBoardFX
import io.magicmobile.android.game.BoardFXCardMotion
import io.magicmobile.android.ui.glowingStroke
import io.magicmobile.android.ui.rgb
import kotlinx.coroutines.delay

/**
 * Frame clock for effect batches (BoardFXOverlay.swift BoardFXClock). Each batch starts on
 * its first drawn frame instead of at ingest, so no opening plays off-screen. Written while
 * drawing, so it is a plain object, not state.
 */
class BoardFXClock {
    private val firstFrames = HashMap<Long, Long>()

    fun observe(effects: List<ActiveBoardFX>, now: Long) {
        for (effect in effects) if (!firstFrames.containsKey(effect.start)) firstFrames[effect.start] = now
        if (firstFrames.size > 32) {
            val live = effects.map { it.start }.toSet()
            firstFrames.keys.retainAll(live)
        }
    }

    fun origin(batch: Long): Long? = firstFrames[batch]
}

val LocalBoardFXClock = staticCompositionLocalOf { BoardFXClock() }
val LocalBoardFXCardMotion = compositionLocalOf { BoardFXCardMotion() }

object BoardFXColors {
    val gold = rgb(1.0, 0.8, 0.36)
    val attackRed = rgb(1.0, 0.36, 0.2)
    val blockSteel = rgb(0.55, 0.78, 1.0)
}

/**
 * Applied to real board tiles: hides a card while a flight stands in for it, lunges new
 * attackers, and holds attackers and blockers forward with a glow. Layout is unaffected.
 */
fun Modifier.boardFXCardMotion(cardID: String): Modifier = composed {
    val motion = LocalBoardFXCardMotion.current
    val clock = LocalBoardFXClock.current
    val windows = motion.hidden[cardID] ?: emptyList()
    var hiding by remember { mutableStateOf<BoardFXCardMotion.Hidden?>(null) }
    // Windows that have finished; the tile shows again unless another window covers it.
    var revealed by remember { mutableStateOf(emptySet<BoardFXCardMotion.Hidden>()) }
    val hidden = windows.any { it !in revealed && (it.from <= 0 || hiding == it) }
    val lunge = motion.lunges[cardID]
    val stance = motion.stances[cardID]
    val direction = (lunge?.direction ?: 0.0).toFloat()
    val stanceColor = if (stance?.kind == BoardFXCardMotion.Stance.Kind.BLOCKING) BoardFXColors.blockSteel else BoardFXColors.attackRed
    val forwardTarget = if (stance?.moves == true) stance.direction.toFloat() * (if (stance.kind == BoardFXCardMotion.Stance.Kind.ATTACKING) 12f else 7f) else 0f
    val stanceSpring = spring<Float>(dampingRatio = 0.72f, stiffness = 273f)
    val forward by animateFloatAsState(forwardTarget, stanceSpring, label = "stanceOffset")
    val scale by animateFloatAsState(if (stance?.moves == true) 1.05f else 1f, stanceSpring, label = "stanceScale")
    val stanceAlpha by animateFloatAsState(if (stance != null) 1f else 0f, tween(200), label = "stanceGlow")
    val lungeOffset = remember { Animatable(0f) }

    LaunchedEffect(lunge?.token ?: -1) {
        if (lunge == null) { lungeOffset.snapTo(0f); return@LaunchedEffect }
        lungeOffset.animateTo(22f, spring(dampingRatio = 0.85f, stiffness = 1200f))
        lungeOffset.animateTo(0f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = 340f))
    }
    LaunchedEffect(windows) {
        revealed = revealed intersect windows.toSet()
        if (windows.isEmpty()) return@LaunchedEffect
        // Time the windows on the overlay's frame clock (see BoardFXClock). A double striker has
        // one window per strike, so its tile shows between them.
        var polls = 0
        while (windows.any { clock.origin(it.batch) == null } && polls < 60) { delay(33); polls += 1 }
        val timed = windows.map { it to (clock.origin(it.batch) ?: System.currentTimeMillis()) }
            .sortedBy { (window, origin) -> origin + (window.from * 1000).toLong() }
        for ((window, origin) in timed) {
            if (window in revealed) continue
            if (window.from > 0) {
                val start = origin + (window.from * 1000).toLong() - System.currentTimeMillis()
                if (start > 0) delay(start)
                hiding = window
            }
            val wait = origin + (window.until * 1000).toLong() - System.currentTimeMillis()
            if (wait > 0) delay(wait)
            revealed = revealed + window
            if (hiding == window) hiding = null
        }
    }

    val glow = if (stanceAlpha > 0f) Modifier.glowingStroke(stanceColor.copy(alpha = stanceAlpha), 2.dp,
        stanceColor.copy(alpha = 0.9f * stanceAlpha), 8.dp, 8.dp, inset = (-2).dp) else Modifier
    this.graphicsLayer {
        translationY = (forward + lungeOffset.value * direction) * density
        scaleX = scale; scaleY = scale
        alpha = if (hidden) 0f else 1f
    }.then(glow)
}

/** A red edge that flares when you take a big hit. */
val BoardHitVignetteColor: Color = rgb(0.85, 0.05, 0.02).copy(alpha = 0.55f)
