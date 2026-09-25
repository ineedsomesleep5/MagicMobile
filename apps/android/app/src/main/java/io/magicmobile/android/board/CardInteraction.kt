package io.magicmobile.android.board

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import io.magicmobile.android.game.BoardRect

/**
 * Port of HoldCardInspection.swift and the card-bounds preference. A tap selects or acts; a
 * hold (0.35 s) shows the inspector for as long as the finger stays down.
 */
class HoldCardInspection {
    var isActive by mutableStateOf(false); private set
    private var dismiss: (() -> Unit)? = null

    fun begin(dismiss: () -> Unit) {
        end()
        this.dismiss = dismiss
        isActive = true
    }

    fun end() {
        if (!isActive) return
        val completion = dismiss
        dismiss = null
        isActive = false
        completion?.invoke()
    }
}

val LocalHoldCardInspection = compositionLocalOf<HoldCardInspection?> { null }

/** `.onCardInteraction(tap:inspect:release:)`. */
fun Modifier.onCardInteraction(tap: () -> Unit, inspect: () -> Unit, release: () -> Unit, enabled: Boolean = true): Modifier = composed {
    val inspection = LocalHoldCardInspection.current
    val currentTap by rememberUpdatedState(tap)
    val currentInspect by rememberUpdatedState(inspect)
    val currentRelease by rememberUpdatedState(release)
    if (!enabled) return@composed this
    this.pointerInput(Unit) {
        detectTapGestures(
            onTap = { currentTap() },
            onLongPress = {
                if (inspection != null) inspection.begin(currentRelease) else Unit
                currentInspect()
            },
            onPress = {
                tryAwaitRelease()
                if (inspection != null) inspection.end() else currentRelease()
            })
    }
}

/** Where each rendered card is, in board coordinates (dp), for combat arrows and effect flights (Swift PortraitCardBoundsKey). */
class CardBoundsRegistry {
    val bounds = mutableStateMapOf<String, BoardRect>()
    var boardOrigin: Offset = Offset.Zero
    var density = 1f

    fun update(id: String, coordinates: LayoutCoordinates) {
        if (!coordinates.isAttached) return
        val rect = coordinates.boundsInRoot()
        val next = BoardRect((rect.left - boardOrigin.x) / density, (rect.top - boardOrigin.y) / density, rect.width / density, rect.height / density)
        if (bounds[id] != next) bounds[id] = next
    }

    fun remove(id: String) { bounds.remove(id) }
}

val LocalCardBounds = compositionLocalOf<CardBoundsRegistry?> { null }

/** Records this card's rendered bounds in the board's coordinate space. */
fun Modifier.cardBounds(id: String): Modifier = composed {
    val registry = LocalCardBounds.current ?: return@composed this
    this.onGloballyPositioned { registry.update(id, it) }
}

/** Board haptics (Swift GameHaptics). */
object GameHaptics {
    fun selection(view: android.view.View) { view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
    fun impact(view: android.view.View) { view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY) }
    fun success(view: android.view.View) { view.performHapticFeedback(HapticFeedbackConstants.CONFIRM) }
    fun warning(view: android.view.View) { view.performHapticFeedback(HapticFeedbackConstants.REJECT) }
}

@Composable
fun rememberHaptics(): android.view.View = LocalView.current

@Composable
fun densityValue(): Float = LocalDensity.current.density
