package io.magicmobile.android.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.View
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.LayoutDirection
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/**
 * `windowInsetsPadding(WindowInsets.safeDrawing)` that also works inside a screen-sized Dialog. On 3-button navigation
 * (an Android tester, 2026-10-26: the message box sat under the Back/Home/Recents buttons) a Dialog with
 * `decorFitsSystemWindows = false` gets no insets at all, and its content sits one status bar lower than its window, running
 * off the bottom of the screen. So each side takes the larger of the window's own inset and how far the activity's system
 * bars and cutout actually reach over this view where it sits on screen. Outside a Dialog the two agree.
 */
@Composable
fun Modifier.safeDrawingPaddingEverywhere(sides: WindowInsetsSides = WindowInsetsSides.Horizontal + WindowInsetsSides.Vertical): Modifier {
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    LocalConfiguration.current // a rotation moves the navigation bar: read again
    val view = LocalView.current
    EdgeToEdgeDialogWindow()
    var placed by remember(view) { mutableStateOf(IntArray(4)) }
    DisposableEffect(view) {
        fun read() {
            val at = IntArray(2).also(view::getLocationOnScreen)
            val next = intArrayOf(at[0], at[1], at[0] + view.width, at[1] + view.height)
            if (!next.contentEquals(placed)) placed = next
        }
        val listener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> read() }
        view.addOnLayoutChangeListener(listener); read()
        onDispose { view.removeOnLayoutChangeListener(listener) }
    }
    val own = WindowInsets.safeDrawing.only(sides)
    val decor = LocalContext.current.findActivity()?.window?.decorView
    val outer = decor?.let { ViewCompat.getRootWindowInsets(it) }
        ?.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
    // How far each bar reaches into this view: the bar's size, less the gap between the screen edge and the view's edge.
    val screenWidth = decor?.width ?: 0
    val screenHeight = decor?.height ?: 0
    fun reach(size: Int, gap: Int, side: WindowInsetsSides) = if (outer == null || view.width == 0 || !sides.hasAny(side)) 0 else (size - gap).coerceAtLeast(0)
    val left = maxOf(own.getLeft(density, direction), reach(outer?.left ?: 0, placed[0], WindowInsetsSides.Left))
    val right = maxOf(own.getRight(density, direction), reach(outer?.right ?: 0, screenWidth - placed[2], WindowInsetsSides.Right))
    val top = maxOf(own.getTop(density), reach(outer?.top ?: 0, placed[1], WindowInsetsSides.Top))
    val bottom = maxOf(own.getBottom(density), reach(outer?.bottom ?: 0, screenHeight - placed[3], WindowInsetsSides.Bottom))
    return with(density) {
        val (start, end) = if (direction == LayoutDirection.Ltr) left to right else right to left
        this@safeDrawingPaddingEverywhere.padding(start = start.toDp(), top = top.toDp(), end = end.toDp(), bottom = bottom.toDp())
    }
}

private fun WindowInsetsSides.hasAny(side: WindowInsetsSides): Boolean = (this + side) == this

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/**
 * Inside a screen-sized Dialog (`decorFitsSystemWindows = false`), call first: the window was fitted between the system
 * bars, shifted one status bar down past the screen's bottom, and got no insets at all, not even the keyboard's (an Android
 * tester on 3-button navigation, 2026-10-26). This spans it over the screen so it takes insets itself, resizes for the
 * keyboard instead of panning, and keeps light status bar icons on the dark screens. Outside a Dialog it does nothing.
 */
@Composable
fun EdgeToEdgeDialogWindow() {
    val view = LocalView.current
    DisposableEffect(view) {
        (view.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window?.let { window ->
            androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
            window.setLayout(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
            @Suppress("DEPRECATION")
            window.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            window.attributes = window.attributes.apply {
                if (android.os.Build.VERSION.SDK_INT >= 30) { fitInsetsTypes = 0; fitInsetsSides = 0 }
                if (android.os.Build.VERSION.SDK_INT >= 28) layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
            androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
                isAppearanceLightStatusBars = false; isAppearanceLightNavigationBars = false
            }
        }
        onDispose { }
    }
}
