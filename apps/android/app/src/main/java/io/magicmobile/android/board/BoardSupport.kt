package io.magicmobile.android.board

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import io.magicmobile.android.ArtworkTokenIdentity
import io.magicmobile.android.game.BoardFXLevel
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.LaunchEnvironment

/**
 * The board's breathing glows (playable hand cards, floating mana, a castable commander), rising from `low`
 * to `high` over `periodMillis` and back. They step on one shared 20-a-second clock instead of every frame
 * each, so a quiet board redraws a third as often and all of them in the same frame. Read the returned
 * value inside a draw or graphicsLayer block, so a step redraws the glow without recomposing its card.
 * While the phone is hot (DeviceHeat) they step 10 times a second, and once the board is idle
 * ([BoardActivity]) they rest at `high` and stop redrawing. iOS: BoardBreath.
 */
@Composable
fun rememberBoardBreath(periodMillis: Int, low: Float = 0f, high: Float = 1f): () -> Float {
    val resting = BoardActivity.idle
    val step = if (io.magicmobile.android.ui.DeviceHeat.isHot) BOARD_BREATH_HOT_STEP_MS else BOARD_BREATH_STEP_MS
    val now = produceState(System.currentTimeMillis(), resting, step) {
        if (resting) return@produceState
        while (true) {
            kotlinx.coroutines.delay(step - System.currentTimeMillis() % step)
            value = System.currentTimeMillis() / step * step
        }
    }
    return remember(now, periodMillis, low, high, resting) {
        {
            if (resting) high else {
                val phase = (now.value % (2L * periodMillis)).toDouble() / periodMillis
                low + (high - low) * (0.5 - 0.5 * kotlin.math.cos(Math.PI * phase)).toFloat()
            }
        }
    }
}

private const val BOARD_BREATH_STEP_MS = 50L
private const val BOARD_BREATH_HOT_STEP_MS = 100L

/**
 * Whether anyone is using the board (iOS BoardActivity). Once nothing has changed in the game and nobody has touched
 * the screen for [IDLE_AFTER_MS], the breathing glows rest; the next touch (MainActivity.dispatchTouchEvent) or game
 * change (NativeGameView) wakes them.
 */
object BoardActivity {
    const val IDLE_AFTER_MS = 15_000L
    var idle by mutableStateOf(false)
        private set
    private var last = System.currentTimeMillis()
    private var watcher: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** Main thread only. */
    fun note(now: Long = System.currentTimeMillis()) {
        last = now
        if (idle) idle = false
        if (watcher?.isActive == true) return
        watcher = scope.launch {
            while (true) {
                val wait = remaining(last, System.currentTimeMillis())
                if (wait <= 0) { idle = true; return@launch }
                delay(wait)
            }
        }
    }

    /** Milliseconds until the board counts as idle; zero or less once it does. */
    fun remaining(lastActivity: Long, now: Long): Long = IDLE_AFTER_MS - (now - lastActivity)
}

/** Swift `GameBoardMotion`: reduced motion (the large-text preview forces it) and large-text layouts. */
object BoardMotion {
    val reduceMotion: Boolean get() = LaunchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] == "large-text" || LaunchEnvironment.reduceMotion
    /** iOS accessibility text sizes start around 1.35x; Android's largest font settings map to the same layouts. */
    val largeText: Boolean get() = LaunchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] == "large-text" || LaunchEnvironment.systemFontScale >= 1.35f
}

object BoardFXSettings {
    val levelState get() = AppPreferences.string(BoardFXLevel.key, BoardFXLevel.defaultValue)
    val level: BoardFXLevel get() = BoardFXLevel.resolved(levelState.value, BoardMotion.reduceMotion)
    val soundsEnabled get() = AppPreferences.boolean("magicmobile.boardSoundsEnabled", true)
}

object BoardArtwork {
    /** UI previews and tests draw the iOS placeholder instead of downloaded art (MAGICMOBILE_FORCE_CARD_PLACEHOLDERS). */
    val forcePlaceholders: Boolean get() = LaunchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] == "true"
}

/** The token identity iOS passes to its artwork view (template first, then the live card). */
fun boardTokenIdentity(card: ZoneCard): ArtworkTokenIdentity {
    val template = card.card.tokenArtwork
    return ArtworkTokenIdentity(card.card.name, template?.typeLine ?: card.card.typeLine, template?.oracleText ?: card.card.oracleText ?: "",
        template?.power ?: card.displayPower, template?.toughness ?: card.displayToughness,
        (template?.colors ?: card.card.tokenColors ?: emptyList()).toSet())
}
