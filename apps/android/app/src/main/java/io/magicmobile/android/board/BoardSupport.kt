package io.magicmobile.android.board

import androidx.compose.runtime.Composable
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
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
 */
@Composable
fun rememberBoardBreath(periodMillis: Int, low: Float = 0f, high: Float = 1f): () -> Float {
    val now = produceState(System.currentTimeMillis()) {
        while (true) {
            kotlinx.coroutines.delay(BOARD_BREATH_STEP_MS - System.currentTimeMillis() % BOARD_BREATH_STEP_MS)
            value = System.currentTimeMillis() / BOARD_BREATH_STEP_MS * BOARD_BREATH_STEP_MS
        }
    }
    return remember(now, periodMillis, low, high) {
        {
            val phase = (now.value % (2L * periodMillis)).toDouble() / periodMillis
            low + (high - low) * (0.5 - 0.5 * kotlin.math.cos(Math.PI * phase)).toFloat()
        }
    }
}

private const val BOARD_BREATH_STEP_MS = 50L

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
