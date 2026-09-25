package io.magicmobile.android.board

import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.ScrollableState
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * A horizontal scroller that clips only where iOS masks (`.scrollClipDisabled()` plus a
 * mask): Compose's `horizontalScroll` clips every side, which cut card glows, fan tilt and
 * attack stances. It also exposes progress for the hand scrubber (HandScrollController).
 */
class BoardScrollState {
    var offset by mutableFloatStateOf(0f); private set
    var maxOffset by mutableFloatStateOf(0f); internal set
    val progress: Float get() = if (maxOffset > 0f) (offset / maxOffset).coerceIn(0f, 1f) else 0f

    val scrollable = ScrollableState { delta ->
        val next = (offset - delta).coerceIn(0f, maxOf(0f, maxOffset))
        val consumed = offset - next
        offset = next
        consumed
    }

    fun scrollTo(progress: Float) { offset = progress.coerceIn(0f, 1f) * maxOf(0f, maxOffset) }

    internal fun clamp() { if (offset > maxOffset) offset = maxOf(0f, maxOffset) }
}

/** Clip rect grown by the given insets (negative padding on the iOS mask). */
class InsetClipShape(private val horizontal: Dp, private val top: Dp, private val bottom: Dp) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline = with(density) {
        Outline.Rectangle(Rect(-horizontal.toPx(), -top.toPx(), size.width + horizontal.toPx(), size.height + bottom.toPx()))
    }
}

@Composable
fun BoardHorizontalScroller(state: BoardScrollState, modifier: Modifier = Modifier, clipHorizontal: Dp = 4.dp, clipTop: Dp = 28.dp,
                            clipBottom: Dp = 28.dp, showsIndicator: Boolean = false, alignTop: Boolean = false,
                            content: @Composable () -> Unit) {
    val indicator = if (!showsIndicator) Modifier else Modifier.drawWithContent {
        drawContent()
        if (state.maxOffset <= 0f || !state.scrollable.isScrollInProgress) return@drawWithContent
        val track = size.width
        val thumb = maxOf(track * track / (track + state.maxOffset), 24.dp.toPx())
        val x = (track - thumb) * state.progress
        drawRoundRect(Color.White.copy(alpha = 0.45f), Offset(x, size.height - 4.dp.toPx()), Size(thumb, 3.dp.toPx()), CornerRadius(2.dp.toPx()))
    }
    Layout(content, modifier
        .clip(InsetClipShape(clipHorizontal, clipTop, clipBottom))
        .scrollable(state.scrollable, Orientation.Horizontal)
        .then(indicator)) { measurables, constraints ->
        val placeable = measurables.first().measure(Constraints())
        val width = if (constraints.hasBoundedWidth) constraints.maxWidth else placeable.width
        val height = placeable.height.coerceIn(constraints.minHeight, constraints.maxHeight)
        state.maxOffset = maxOf(0f, (placeable.width - width).toFloat())
        state.clamp()
        layout(width, height) {
            placeable.placeRelative(-state.offset.roundToInt(), if (alignTop) 0 else (height - placeable.height) / 2)
        }
    }
}

@Composable
fun rememberBoardScrollState(): BoardScrollState = remember { BoardScrollState() }
