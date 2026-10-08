package io.magicmobile.android.studio

import android.graphics.BitmapShader
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.graphics.SurfaceTexture
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animate
import kotlin.math.min
import kotlin.math.ceil
import kotlin.math.floor
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import androidx.compose.animation.core.Animatable
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
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.abs
import kotlin.math.max

/** What a page turn looks like right now: the curl, or a quick crossfade when animations are switched off. */
internal enum class PageEffect { CURL, CROSSFADE }

/**
 * GrimoireStage.swift: the spell book's moving parts. The page that turns between Deck Studio's screens
 * (GrimoirePages) and the film of the book opening when Decks is tapped and closing on Done (GrimoireFilm).
 *
 * A page turn is a curl (PageCurlShader.kt): the paper of the binder's pages bends over a moving fold, and follows
 * a finger that drags it (GrimoireChrome.kt watches the drags). With animations switched off in the system settings
 * it is a crossfade that takes no time, so the change simply happens.
 */
class GrimoireStage internal constructor(private val scope: CoroutineScope, internal val layer: GraphicsLayer) {
    /** The pictures on the stage while a page turns: the screen before (`old`) and, once it has been drawn, after (`new`). */
    internal class Turn(val forward: Boolean, val layout: PageCurlLayout, val old: ImageBitmap, val crossfade: Boolean) {
        var new by mutableStateOf<ImageBitmap?>(null)
    }

    internal var turn by mutableStateOf<Turn?>(null)
    /** How far the page has turned, 0 to 1. */
    internal var progress by mutableFloatStateOf(0f)
    internal var tilt by mutableFloatStateOf(PageCurlModel.TILT)
    internal var spread = false
    internal var density = 1f
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
    /**
     * Whether a drag that begins at this point (in the stage) may turn the page: it has to begin on the paper, below the
     * page's head (Done, Save, the tags and the other plaques sit at the top of each page, and a finger that slides off one
     * of them is not turning anything). With no binder pages registered, anywhere will do.
     */
    internal fun pageMayCurl(point: Offset): Boolean {
        val pages = binderPages
        if (pages.isEmpty()) return true
        val page = pages.firstOrNull { it.contains(point) } ?: return false
        return point.y >= page.top + Grimoire.headBand.value * density
    }
    private val binderPages: List<Rect> get() = binderScreens.values.lastOrNull()?.values?.sortedBy { it.left } ?: emptyList()

    internal val effect: PageEffect get() = if (LaunchEnvironment.reduceMotion) PageEffect.CROSSFADE else PageEffect.CURL

    // The screens' own chapter turns, for the drag that turns them (grimoireSwipe registers them while on show).
    private class Swipe(val next: () -> Unit, val previous: () -> Unit)
    private val swipes = LinkedHashMap<Any, Swipe>()
    internal fun registerSwipe(token: Any, next: () -> Unit, previous: () -> Unit) { swipes[token] = Swipe(next, previous) }
    internal fun unregisterSwipe(token: Any) { swipes.remove(token) }
    internal val hasSwipes: Boolean get() = swipes.isNotEmpty()
    internal fun swipeNext() { swipes.values.lastOrNull()?.next?.invoke() }
    internal fun swipePrevious() { swipes.values.lastOrNull()?.previous?.invoke() }

    /**
     * A page turned by a finger. The drag watcher arms one (`beginDrag`) and calls the screen's own "next chapter" or
     * "previous chapter", which reaches `turnPage` as it always did; `turnPage` then follows the finger instead of
     * playing the turn by itself.
     */
    private class DragSession(val forward: Boolean, val startX: Float, val revert: () -> Unit) {
        var engaged = false
        var ready = false
        var travel = 1f
        var distance = 0f
        var lift = 0f
        /** The finger's speed along the turn (px per second) and whether the touch was cancelled. */
        var released: Pair<Float, Boolean>? = null
        /** A turn that moved to another screen (the library, a deck) cannot be put back from here. */
        var revertible = true
        var finishing = false
        /** The turn is falling back and still has to put the screen back. */
        var reverting = false
        val done = CompletableDeferred<Unit>()
    }
    private var armed: DragSession? = null
    private var drag: DragSession? = null

    /**
     * Starts a page turn that follows the finger. `probe` makes the screen's change (the call a swipe always made); if it
     * turns a page, the turn is live and this returns true. `revert` puts the screen back if the finger lets go
     * before the turn is half done.
     */
    internal fun beginDrag(forward: Boolean, startX: Float, probe: () -> Unit, revert: () -> Unit): Boolean {
        finishEarly()
        if (effect != PageEffect.CURL || busy || drag != null) return false
        val session = DragSession(forward, startX, revert)
        armed = session
        probe()
        armed = null
        return session.engaged
    }

    /** The finger's total movement since it touched, in stage pixels. */
    internal fun dragChanged(dx: Float, dy: Float) {
        val session = drag ?: return
        session.distance = if (session.forward) -dx else dx
        session.lift = -dy
        applyDrag(session)
    }

    /** The finger lifted (or the touch was cancelled). `speed` is its sideways speed in px per second. */
    internal fun dragEnded(speed: Float, cancelled: Boolean) {
        val session = drag ?: return
        session.released = (if (session.forward) -speed else speed) to cancelled
        if (session.ready) settle(session)
    }

    private fun applyDrag(session: DragSession) {
        if (!session.ready) return
        val rect = turn?.layout?.rect ?: return
        tilt = (PageCurlModel.TILT + session.lift / max(rect.height, 1f) * 0.7f).coerceIn(0.05f, 0.4f)
        progress = PageCurlModel.progress(session.distance, session.travel)
    }

    /** Lets the page go to the finished turn, or back where it was, and then lets the stage go. */
    private fun settle(session: DragSession) {
        val released = session.released ?: return
        if (session.finishing) return
        session.finishing = true
        val complete = !session.revertible || (!released.second && PageCurlModel.completes(progress, released.first, density))
        session.reverting = !complete
        settleJob = scope.launch {
            try {
                val remaining = if (complete) 1f - progress else progress
                animate(progress, if (complete) 1f else 0f, animationSpec = tween((160 + 340 * remaining).toInt(), easing = LinearOutSlowInEasing)) { value, _ -> progress = value }
                if (!complete) {
                    // The page lies flat again over the old screen: put the screen back and give it a moment to draw.
                    if (session.reverting) { session.reverting = false; putBack(session) }
                    withFrameNanos {}; withFrameNanos {}
                }
            } finally {
                session.done.complete(Unit)
            }
        }
    }

    /**
     * A curl that plays by itself (or is settling after a finger let go) lets touches through, so a tap or a drag during it
     * is never lost: it is taken to its end at once (what is underneath already shows the new page, or has the old one put
     * back) and the new turn begins.
     */
    private fun finishEarly() {
        if (!busy || turn == null) return
        val session = drag
        if (session != null) {
            if (!session.finishing) return
            if (session.reverting) { session.reverting = false; putBack(session) }
            session.done.complete(Unit)
        }
        generation++
        settleJob?.cancel(); settleJob = null
        job?.cancel(); job = null
        turn = null; drag = null; busy = false; progress = 0f
    }

    /** Puts the screen back as a plain change, with no turn of its own. */
    private var silent = false
    private fun putBack(session: DragSession) {
        silent = true
        try { session.revert() } finally { silent = false }
    }
    private var generation = 0
    private var job: Job? = null
    private var settleJob: Job? = null

    /** The paper that turns: the newest binder screen's page (one upright, two sideways), or the whole screen. */
    private fun layoutFor(bounds: Rect): PageCurlLayout {
        val registered = binderPages.filter { it.overlaps(bounds) }
        var frames = listOf(bounds)
        var corner = 0f
        if (spread) {
            if (registered.size == 2) { frames = registered; corner = 13f * density }
            else frames = listOf(Rect(0f, 0f, bounds.width / 2, bounds.height), Rect(bounds.width / 2, 0f, bounds.width, bounds.height))
        } else if (registered.size == 1) { frames = registered; corner = 13f * density }
        frames = frames.map { it.intersect(bounds) }
        val union = frames.reduce { a, b -> Rect(min(a.left, b.left), min(a.top, b.top), max(a.right, b.right), max(a.bottom, b.bottom)) }
        val whole = Rect(floor(union.left), floor(union.top), ceil(union.right), ceil(union.bottom)).intersect(bounds)
        val local = frames.map { it.translate(-whole.left, -whole.top) }
        val spine = if (!spread) 0f else if (local.size == 2) (local[0].right + local[1].left) / 2 else whole.width / 2
        return PageCurlLayout(whole, spine, spread, local, corner)
    }

    /**
     * Turns the page. `change` swaps what is on screen while the paper of the binder's pages curls: forward, the old page
     * peels away from its free corner toward the spine and the new page lies revealed under it; back, the new page unrolls
     * from the spine over the old one. Upright, the spine is the page's left edge. Sideways, the book lies open as a
     * spread, the right page curling over the spine onto the left for forward and the left onto the right for back.
     */
    fun turnPage(forward: Boolean, change: () -> Unit) {
        if (silent) { change(); return }
        val session = armed
        armed = null
        finishEarly()
        if (busy) { change(); return }
        busy = true
        val effect = effect
        if (session != null && effect == PageEffect.CURL) { session.engaged = true; drag = session }
        val mine = ++generation
        job = scope.launch {
            var changed = false
            try {
                val old = layer.toImageBitmap()
                val bounds = Rect(0f, 0f, old.width.toFloat(), old.height.toFloat())
                val layout = layoutFor(bounds)
                val picture = Turn(forward, layout, old, crossfade = effect == PageEffect.CROSSFADE)
                progress = 0f; tilt = PageCurlModel.TILT
                turn = picture
                val screenBefore = binderScreens.keys.lastOrNull()
                change(); changed = true
                GameAudio.play(GameSound.PAGE_FLIP)
                // The new page needs a frame or two to be drawn beneath before it can be pictured.
                withFrameNanos {}; withFrameNanos {}
                picture.new = layer.toImageBitmap()
                if (session != null && session.engaged) {
                    val unit = if (layout.spread) layout.rect.width / 2 else layout.rect.width
                    val farEnd = if (forward) layout.rect.left else layout.rect.right
                    session.travel = (abs(session.startX - farEnd) - 20f * density).coerceIn(0.5f * unit, 0.9f * unit)
                    session.revertible = binderScreens.keys.lastOrNull() == screenBefore
                    session.ready = true
                    applyDrag(session)
                    if (session.released != null) settle(session)
                    session.done.await()
                } else if (picture.crossfade) {
                    animate(0f, 1f, animationSpec = tween(180, easing = LinearEasing)) { value, _ -> progress = value }
                } else {
                    animate(0f, 1f, animationSpec = tween(500, easing = FastOutSlowInEasing)) { value, _ -> progress = value }
                }
            } finally {
                if (!changed) change()
                // A turn that was taken to its end early has been replaced; the new one's state is not this one's to clear.
                if (generation == mine) { turn = null; drag = null; busy = false; progress = 0f }
            }
        }
    }

    companion object {
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
 * can carry the picture of the screen that was there (or of the one arriving). The page drags that turn it are
 * watched here, on the book itself, so they carry on when a turn takes one screen away and brings another.
 */
@Composable
fun GrimoirePages(stage: GrimoireStage, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val configuration = LocalConfiguration.current
    stage.spread = Grimoire.isSpread(configuration.screenWidthDp, configuration.screenHeightDp)
    stage.density = LocalDensity.current.density
    // The first turn should not pay for compiling the shader.
    LaunchedEffect(Unit) { curlShaderWorks() }
    CompositionLocalProvider(LocalGrimoireStage provides stage) {
        Box(modifier.fillMaxSize().onGloballyPositioned { stage.origin = it.positionInRoot() }.pointerInput(stage) { watchGrimoireDrags(stage) }) {
            Box(Modifier.fillMaxSize().drawWithContent {
                stage.layer.record { this@drawWithContent.drawContent() }
                drawLayer(stage.layer)
            }, content = content)
            stage.turn?.let { TurningPage(stage, it) }
        }
    }
}

/** What the stage shows while a page turns. */
@Composable
private fun TurningPage(stage: GrimoireStage, turn: GrimoireStage.Turn) {
    // Touches go through: a tap or a drag during a turn takes it to its end (GrimoireStage.finishEarly).
    val blocker = Modifier.fillMaxSize()
    when {
        turn.crossfade -> Box(blocker.drawBehind {
            val rect = turn.layout.rect
            clipRect(rect.left, rect.top, rect.right, rect.bottom) { drawImage(turn.old, alpha = 1f - stage.progress) }
        })
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && curlShaderWorks() -> CurlSurface(stage, turn, blocker)
        else -> SwingSurface(stage, turn, blocker)
    }
}

/** Whether this device can run the curl's AGSL (Android 13 and up, and the shader compiles): checked once, so a shader that fails to compile costs the curl, never the app. */
private val curlShader: Boolean by lazy {
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && runCatching { RuntimeShader(PAGE_CURL_AGSL) }.isSuccess
}
private fun curlShaderWorks(): Boolean = curlShader

/** The curl itself: one AGSL shader over the paper's rectangle, bending the two pictures. */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
@Composable
private fun CurlSurface(stage: GrimoireStage, turn: GrimoireStage.Turn, modifier: Modifier) {
    val density = LocalDensity.current.density
    Box(modifier.drawWithCache {
        val layout = turn.layout
        val rect = layout.rect
        val sheetWidth = if (layout.spread) (layout.pages.lastOrNull()?.width ?: (rect.width - layout.spine)) else rect.width
        val maxRadius = PageCurlModel.maxRadius(sheetWidth, density)
        val forward = turn.forward
        val mirrored = !forward && layout.spread
        val spine = if (layout.spread) (if (mirrored) rect.width - layout.spine else layout.spine) else 0f
        // Which picture is the sheet's front, its back (-1: plain paper), and what lies under the sheet and on the landing side.
        val slots = when {
            layout.spread -> floatArrayOf(0f, 1f, 1f, 0f)
            forward -> floatArrayOf(0f, -1f, 1f, 1f)
            else -> floatArrayOf(1f, -1f, 0f, 0f)
        }
        // The paper that turns (rectA) and the page it lands on (rectB), in the turn's own (possibly mirrored) pixels.
        var sheet = layout.pages.first().let { floatArrayOf(it.left, it.top, it.right, it.bottom) }
        var landing = floatArrayOf(0f, 0f, 0f, 0f)
        if (layout.spread && layout.pages.size == 2) {
            val (a, b) = if (forward) layout.pages[1] to layout.pages[0] else layout.pages[0] to layout.pages[1]
            sheet = floatArrayOf(a.left, a.top, a.right, a.bottom); landing = floatArrayOf(b.left, b.top, b.right, b.bottom)
        }
        if (mirrored) {
            sheet = floatArrayOf(rect.width - sheet[2], sheet[1], rect.width - sheet[0], sheet[3])
            if (landing[2] > landing[0]) landing = floatArrayOf(rect.width - landing[2], landing[1], rect.width - landing[0], landing[3])
        }
        val shader = RuntimeShader(PAGE_CURL_AGSL)
        val brush = ShaderBrush(shader)
        val oldShader = BitmapShader(turn.old.asAndroidBitmap(), Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        var newImage: ImageBitmap? = null
        var newShader: BitmapShader? = null
        onDrawBehind {
            val new = turn.new
            if (new !== newImage) { newImage = new; newShader = new?.let { BitmapShader(it.asAndroidBitmap(), Shader.TileMode.CLAMP, Shader.TileMode.CLAMP) } }
            // A lone page that comes back is the new page, rolled up beside the spine, unrolling over the old one.
            val shown = if (!forward && !layout.spread) 1f - stage.progress else stage.progress
            val pose = PageCurlModel.pose(if (new == null) 0f else shown, rect.width, rect.height, spine, stage.tilt, maxRadius)
            shader.setInputShader("tex0", oldShader)
            shader.setInputShader("tex1", newShader ?: oldShader)
            shader.setFloatUniform("size", rect.width, rect.height)
            shader.setFloatUniform("nrm", pose.normalX, pose.normalY)
            shader.setFloatUniform("paper", 0.80f, 0.71f, 0.55f, 1f)
            shader.setFloatUniform("pose", pose.foot, pose.radius, spine, if (mirrored) 1f else 0f)
            shader.setFloatUniform("slots", slots)
            shader.setFloatUniform("look", 0.45f, 0.10f, layout.cornerRadius, 0f)
            shader.setFloatUniform("rectA", sheet)
            shader.setFloatUniform("rectB", landing)
            shader.setFloatUniform("texOffset", rect.left, rect.top)
            withTransform({ translate(rect.left, rect.top) }) { drawRect(brush, Offset.Zero, Size(rect.width, rect.height)) }
        }
    })
}

/**
 * Before Android 13 there is no AGSL: the page swings about the spine as a flat sheet, following the same progress
 * (and so the same drag) as the curl.
 */
@Composable
private fun SwingSurface(stage: GrimoireStage, turn: GrimoireStage.Turn, modifier: Modifier) {
    val layout = turn.layout
    val rect = layout.rect
    val spine = rect.left + layout.spine
    val left = Rect(rect.left, rect.top, spine, rect.bottom)
    val right = Rect(spine, rect.top, rect.right, rect.bottom)
    val upright = 88f
    val progress = stage.progress
    val forward = turn.forward
    val new = turn.new
    /** Draws only what lies in `clip` of what follows, under an optional shade. */
    fun Modifier.clipTo(clip: Rect, shade: Float = 0f) = drawWithContent {
        clipRect(clip.left, clip.top, clip.right, clip.bottom) {
            this@drawWithContent.drawContent()
            if (shade > 0f) drawRect(Color.Black.copy(alpha = shade), clip.topLeft, clip.size)
        }
    }
    @Composable
    fun Swinging(image: ImageBitmap, clip: Rect, pivot: Float, angle: Float) {
        Image(image, null, Modifier.fillMaxSize().graphicsLayer {
            transformOrigin = TransformOrigin(if (size.width > 0f) (pivot / size.width).coerceIn(0f, 1f) else 0f, 0.5f)
            rotationY = angle
            cameraDistance = 16f * density
        }.clipTo(clip, shade = 0.42f * abs(angle) / 90f), contentScale = ContentScale.FillBounds)
    }
    @Composable
    fun Still(image: ImageBitmap, clip: Rect) = Image(image, null, Modifier.fillMaxSize().clipTo(clip), contentScale = ContentScale.FillBounds)
    Box(modifier) {
        when {
            layout.spread && forward -> {
                Still(turn.old, left)
                if (progress < 0.5f || new == null) Swinging(turn.old, right, spine, -upright * 2 * progress)
                else Swinging(new, left, spine, upright * (2 - 2 * progress))
            }
            layout.spread -> {
                Still(turn.old, right)
                if (progress < 0.5f || new == null) Swinging(turn.old, left, spine, upright * 2 * progress)
                else Swinging(new, right, spine, -upright * (2 - 2 * progress))
            }
            forward -> Swinging(turn.old, rect, rect.left, -upright * progress)
            else -> { Still(turn.old, rect); if (new != null) Swinging(new, rect, rect.left, -upright * (1 - progress)) }
        }
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
