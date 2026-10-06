package io.magicmobile.android.studio

import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import io.magicmobile.android.R
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LaunchEnvironment
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.abs
import kotlin.math.max

/**
 * GrimoireStage.swift: the spell book's moving parts. The page that turns between Deck Studio's screens
 * (GrimoirePages) and the film of the book opening when Decks is tapped and closing on Done (GrimoireFilm).
 *
 * With animations switched off in the system settings none of it plays: the change simply happens.
 */
class GrimoireStage internal constructor(private val scope: CoroutineScope, internal val layer: GraphicsLayer) {
    /**
     * The pictures on the stage while a page turns: `base` lies still under `page`, which swings. Each shows
     * the whole screen (half 0) or only its left (-1) or right (+1) half; a half swings about the middle.
     */
    internal class Turn(val base: ImageBitmap?, val baseClip: Rect?, val page: ImageBitmap?, val pageClip: Rect?, val pivot: Float)

    internal var turn by mutableStateOf<Turn?>(null)
    internal val angle = Animatable(0f)
    internal var spread = false
    /** One turn at a time; anything asked for meanwhile just makes its change. */
    private var busy = false

    /**
     * The binder's pages on screen (GrimoireBinder.kt), by screen in the order the screens appeared, in the stage's
     * coordinates. A turn moves only the paper of the newest screen's pages; the binder around them (its leather,
     * head and index tabs) stays still. With none registered the whole screen turns.
     */
    private val binderScreens = LinkedHashMap<Any, LinkedHashMap<Any, Rect>>()
    internal var origin = Offset.Zero
    fun setBinderPage(bounds: Rect, page: Any, screen: Any) { binderScreens.getOrPut(screen) { LinkedHashMap() }[page] = bounds.translate(-origin) }
    fun removeBinderPage(page: Any, screen: Any) {
        val pages = binderScreens[screen] ?: return
        pages.remove(page)
        if (pages.isEmpty()) binderScreens.remove(screen)
    }
    private val binderPages: List<Rect> get() = binderScreens.values.lastOrNull()?.values?.sortedBy { it.left } ?: emptyList()

    /**
     * Turns the page. `change` swaps what is on screen while a picture of the old page swings over the spine:
     * forward, the old page lifts away to the left; back, the new page comes down from the left onto the old
     * one. Upright, the spine is the screen's left edge. Sideways, the book lies open as a spread with its spine
     * down the middle: the far half lifts, then the near half of the new spread lands.
     */
    fun turnPage(forward: Boolean, change: () -> Unit) {
        if (!motionEnabled || busy) { change(); return }
        busy = true
        scope.launch {
            var changed = false
            try {
                val old = layer.toImageBitmap()
                val sideways = spread
                val bounds = Rect(0f, 0f, old.width.toFloat(), old.height.toFloat())
                // In the binder only its pages turn: each picture is cut to the pages it shows.
                val pages = binderPages.filter { it.overlaps(bounds) }
                val single = pages.singleOrNull()
                val (left, right) = if (pages.size == 2) pages[0] to pages[1]
                    else Rect(0f, 0f, bounds.width / 2, bounds.height) to Rect(bounds.width / 2, 0f, bounds.width, bounds.height)
                // Upright, forward: the old page itself lifts. Otherwise the old page (or the page of it that
                // stays) lies still while a page moves over it.
                val far = if (forward) 1 else -1
                turn = when {
                    sideways -> Turn(old, if (forward) left else right, old, if (forward) right else left, if (forward) right.left else left.right)
                    forward -> Turn(null, null, old, single, single?.left ?: 0f)
                    else -> Turn(old, single, null, null, 0f)
                }
                angle.snapTo(0f)
                change(); changed = true
                GameAudio.play(GameSound.PAGE_FLIP)
                if (forward && !sideways) {
                    angle.animateTo(-UPRIGHT, tween(420, easing = FastOutLinearInEasing))
                    return@launch
                }
                // The new page needs a frame or two to be drawn beneath before it can be pictured.
                withFrameNanos {}; withFrameNanos {}
                val new = layer.toImageBitmap()
                if (sideways) {
                    angle.animateTo(-far * UPRIGHT, tween(240, easing = FastOutLinearInEasing))
                    turn = Turn(old, if (forward) left else right, new, if (forward) left else right, if (forward) left.right else right.left)
                    angle.snapTo(far * UPRIGHT)
                    angle.animateTo(0f, tween(260, easing = LinearOutSlowInEasing))
                } else {
                    val landing = binderPages.filter { it.overlaps(bounds) }.singleOrNull()
                    turn = Turn(old, single, new, landing, landing?.left ?: 0f)
                    angle.snapTo(-UPRIGHT)
                    angle.animateTo(0f, tween(420, easing = LinearOutSlowInEasing))
                }
            } finally {
                if (!changed) change()
                turn = null; busy = false
            }
        }
    }

    companion object {
        internal const val UPRIGHT = 88f
        val motionEnabled: Boolean get() = !LaunchEnvironment.reduceMotion
    }
}

/** The book whose pages turn; null outside Deck Studio. */
val LocalGrimoireStage = staticCompositionLocalOf<GrimoireStage?> { null }

@Composable
fun rememberGrimoireStage(): GrimoireStage {
    val layer = rememberGraphicsLayer()
    val scope = rememberCoroutineScope()
    return remember(layer) { GrimoireStage(scope, layer) }
}

/**
 * Hosts Deck Studio's screens as the pages of one book: `content` is pictured as it is drawn, so a turning page
 * can carry the picture of the screen that was there (or of the one arriving).
 */
@Composable
fun GrimoirePages(stage: GrimoireStage, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val configuration = LocalConfiguration.current
    stage.spread = Grimoire.isSpread(configuration.screenWidthDp, configuration.screenHeightDp)
    CompositionLocalProvider(LocalGrimoireStage provides stage) {
        Box(modifier.fillMaxSize().onGloballyPositioned { stage.origin = it.positionInRoot() }) {
            Box(Modifier.fillMaxSize().drawWithContent {
                stage.layer.record { this@drawWithContent.drawContent() }
                drawLayer(stage.layer)
            }, content = content)
            stage.turn?.let { TurningPage(it, stage.angle.value) }
        }
    }
}

@Composable
private fun TurningPage(turn: GrimoireStage.Turn, angle: Float) {
    /** Draws only what lies in `clip` of what follows (null: all of it), under an optional shade. */
    fun Modifier.clipTo(clip: Rect?, shade: Float = 0f) = drawWithContent {
        val area = clip ?: Rect(0f, 0f, size.width, size.height)
        clipRect(area.left, area.top, area.right, area.bottom) {
            this@drawWithContent.drawContent()
            if (shade > 0f) drawRect(Color.Black.copy(alpha = shade), area.topLeft, area.size)
        }
    }
    // Nothing underneath is tapped mid-turn.
    Box(Modifier.fillMaxSize().pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } } }) {
        turn.base?.let { Image(it, null, Modifier.fillMaxSize().clipTo(turn.baseClip), contentScale = ContentScale.FillBounds) }
        val page = turn.page ?: return@Box
        // A page swings about its edge at the spine.
        Image(page, null, Modifier.fillMaxSize().graphicsLayer {
            transformOrigin = TransformOrigin(if (size.width > 0f) (turn.pivot / size.width).coerceIn(0f, 1f) else 0f, 0.5f)
            rotationY = angle
            cameraDistance = 16f * density
        }.clipTo(turn.pageClip, shade = 0.42f * abs(angle) / 90f), contentScale = ContentScale.FillBounds)
    }
}

/**
 * The film of the book opening on the tavern table and closing again. `open` plays it over the menu, then
 * `present` puts Deck Studio underneath and the film fades into its first page; `close` fades the open page
 * over Deck Studio, `dismiss` removes it underneath, and the book closes before the menu returns.
 */
class GrimoireFilm {
    internal class Playing(val opening: Boolean, val change: () -> Unit)

    internal var playing by mutableStateOf<Playing?>(null)

    fun open(present: () -> Unit) = play(true, present)
    fun close(dismiss: () -> Unit) = play(false, dismiss)

    private fun play(opening: Boolean, change: () -> Unit) {
        if (!GrimoireStage.motionEnabled || playing != null) { change(); return }
        playing = Playing(opening, change)
    }
}

/** Draws the film over everything while it plays. Place it last in the app's root. */
@Composable
fun GrimoireFilmLayer(film: GrimoireFilm) {
    val playing = film.playing ?: return
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val portrait = configuration.screenHeightDp >= configuration.screenWidthDp
    val resource = when {
        playing.opening && portrait -> R.raw.grimoire_open_portrait
        playing.opening -> R.raw.grimoire_open_landscape
        portrait -> R.raw.grimoire_close_portrait
        else -> R.raw.grimoire_close_landscape
    }
    val alpha = remember(playing) { Animatable(0f) }
    val player = remember(playing) { MediaPlayer() }
    val firstFrame = remember(playing) { CompletableDeferred<Unit>() }
    val ended = remember(playing) { CompletableDeferred<Unit>() }
    DisposableEffect(playing) { onDispose { runCatching { player.release() } } }
    LaunchedEffect(playing) {
        var changed = false
        try {
            // Never strand the player behind a film that fails to load or end: a decoder that will not start
            // (the emulator's) fails the first frame at once, and a slow one gives up after a moment.
            val shown = withTimeoutOrNull(1200) { runCatching { firstFrame.await() }.isSuccess } ?: false
            if (!shown) return@LaunchedEffect
            GameAudio.play(GameSound.PAGE_FLIP)
            alpha.animateTo(1f, tween(200))
            // Closing: Deck Studio leaves underneath once the film covers it.
            if (!playing.opening) { playing.change(); changed = true }
            runCatching { player.start() }
            withTimeoutOrNull(4000) { ended.await() }
            if (playing.opening) { playing.change(); changed = true }
            // The page (or the menu) underneath gets a moment to draw before the film lifts.
            delay(80)
            alpha.animateTo(0f, tween(if (playing.opening) 320 else 360))
        } finally {
            if (!changed) playing.change()
            film.playing = null
        }
    }
    AndroidView({ viewContext ->
        TextureView(viewContext).apply {
            isOpaque = false
            surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                    runCatching {
                        context.resources.openRawResourceFd(resource).use { player.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                        player.setSurface(Surface(texture))
                        player.setVolume(0f, 0f)
                        // The film fills the screen; its edges crop on screens of another shape.
                        player.setOnVideoSizeChangedListener { _, videoWidth, videoHeight ->
                            if (videoWidth > 0 && videoHeight > 0 && this@apply.width > 0 && this@apply.height > 0) {
                                val viewWidth = this@apply.width.toFloat(); val viewHeight = this@apply.height.toFloat()
                                val fill = max(viewWidth / videoWidth, viewHeight / videoHeight)
                                setTransform(android.graphics.Matrix().apply {
                                    setScale(fill * videoWidth / viewWidth, fill * videoHeight / viewHeight, viewWidth / 2, viewHeight / 2)
                                })
                            }
                        }
                        // The first frame is shown still (the film starts once it has faded in).
                        player.setOnInfoListener { _, what, _ ->
                            if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START && !firstFrame.isCompleted) {
                                runCatching { player.pause() }; firstFrame.complete(Unit)
                            }
                            false
                        }
                        player.setOnCompletionListener { ended.complete(Unit) }
                        player.setOnErrorListener { _, what, extra ->
                            firstFrame.completeExceptionally(IllegalStateException("The film could not play ($what/$extra)"))
                            ended.complete(Unit); true
                        }
                        player.setOnPreparedListener { it.start() }
                        player.prepareAsync()
                    }
                }
                override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {}
                override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean = true
                override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}
            }
        }
    }, Modifier.fillMaxSize().graphicsLayer { this.alpha = alpha.value }
        .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } } })
}
