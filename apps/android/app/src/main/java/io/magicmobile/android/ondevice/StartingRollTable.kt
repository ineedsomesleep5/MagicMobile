package io.magicmobile.android.ondevice

import android.content.Context
import android.graphics.SurfaceTexture
import android.view.Choreographer
import android.view.TextureView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.filament.Camera
import com.google.android.filament.ColorGrading
import com.google.android.filament.EntityManager
import com.google.android.filament.Engine
import com.google.android.filament.Filament
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.SwapChain
import com.google.android.filament.ToneMapper
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.FilamentInstance
import com.google.android.filament.gltfio.Gltfio
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import io.magicmobile.android.ui.Quat
import io.magicmobile.android.ui.Vec3
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min

/**
 * The shared dice assets (scripts/brand/d20.py): the die, tables and soft discs as .glb, the face list and the
 * bank of recorded throws as JSON, read from the app's assets. Null when a build does not carry them.
 */
class D20Assets private constructor(val model: D20Model, val bank: List<D20Throw>, val die: ByteBuffer, val shadow: ByteBuffer,
                                    val glow: ByteBuffer, val portrait: ByteBuffer, val landscape: ByteBuffer) {
    fun table(landscape: Boolean): ByteBuffer = (if (landscape) this.landscape else portrait).duplicate()

    companion object {
        /** Cheap check, without decoding anything: does this build carry the dice? */
        fun available(context: Context): Boolean = try {
            context.assets.list("d20")?.contains("d20.glb") == true
        } catch (error: Exception) {
            false
        }

        fun load(context: Context): D20Assets? = try {
            fun bytes(name: String): ByteBuffer {
                val data = context.assets.open("d20/$name").use { it.readBytes() }
                return ByteBuffer.allocateDirect(data.size).put(data).also { it.flip() }
            }
            fun text(name: String) = context.assets.open("d20/$name").bufferedReader().use { it.readText() }
            D20Assets(D20Model.parse(text("d20.json")), D20Throw.parseBank(text("d20-throws.json")), bytes("d20.glb"), bytes("d20-shadow.glb"),
                bytes("d20-glow.glb"), bytes("d20-table-portrait.glb"), bytes("d20-table-landscape.glb"))
        } catch (error: Exception) {
            null
        }
    }
}

/**
 * Filament scene of the tavern table with up to four dice on it. Dice are posed from recorded throws
 * (D20ThrowPlan); there is no physics in the app, so the result can never differ from the game's.
 * Frames are drawn only while a die is in the air (and once after any change): an idle table costs nothing.
 */
class D20TableScene(context: Context, private val assets: D20Assets) {
    private val engine: Engine
    private val renderer: Renderer
    private val scene: Scene
    private val view: View
    private val camera: Camera
    private val cameraEntity: Int
    private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
    private var swapChain: SwapChain? = null
    private val assetLoader: AssetLoader
    private val resourceLoader: ResourceLoader
    private val materials: UbershaderProvider
    private val lights = ArrayList<Int>()
    private var indirectLight: IndirectLight? = null
    private var colorGrading: ColorGrading? = null
    private var tableAsset: FilamentAsset? = null
    private var tableLandscape: Boolean? = null
    private val dieAsset: FilamentAsset
    private val dieInstances = arrayOfNulls<FilamentInstance>(SLOTS)
    private val shadowAsset: FilamentAsset
    private val shadowInstances = arrayOfNulls<FilamentInstance>(SLOTS)
    private val glowAsset: FilamentAsset
    private val glowInstances = arrayOfNulls<FilamentInstance>(SLOTS)
    private var viewWidth = 0
    private var viewHeight = 0
    private var density = 1f
    private var layoutKey: List<Any>? = null
    private var lastRegion = Rect.Zero
    private var lastSeatCount = 0
    private var layout: D20TableLayout? = null
    private val dice = HashMap<String, Die>()
    private val dying = ArrayList<Pair<Die, Long>>()
    private var lastTurn = 0
    private var animations = HashMap<String, Animation>()
    private var frameRequested = false
    private var destroyed = false
    var onEdgeHit: ((Int) -> Unit)? = null
    var onRebound: ((Int) -> Unit)? = null
    var onRest: ((Int) -> Unit)? = null
    /** Called once the first frames are on their way to the screen, so the first throw is not wasted on a table still starting. */
    var onReady: (() -> Unit)? = null
    private var framesDrawn = 0

    private class Die(val slot: Int, var value: Int, var plan: D20ThrowPlan, val seatIndex: Int, val round: Int)

    private class Animation(val seat: String, val turn: Int, val die: Die) {
        val plan: D20ThrowPlan get() = die.plan
        var start = 0L
        var firedEdge = false
        var firedRebound = false
    }

    init {
        Filament.init()
        Gltfio.init()
        engine = Engine.create()
        renderer = engine.createRenderer()
        scene = engine.createScene()
        view = engine.createView()
        cameraEntity = EntityManager.get().create()
        camera = engine.createCamera(cameraEntity)
        view.scene = scene
        view.camera = camera
        view.isPostProcessingEnabled = true
        view.antiAliasing = View.AntiAliasing.NONE
        view.multiSampleAntiAliasingOptions = View.MultiSampleAntiAliasingOptions().also { it.enabled = true; it.sampleCount = 4 }
        // Linear tone mapping keeps the table picture's colours exactly as painted; the die is lit to suit.
        colorGrading = ColorGrading.Builder().toneMapper(ToneMapper.Linear()).build(engine)
        view.colorGrading = colorGrading
        renderer.setClearOptions(Renderer.ClearOptions().also { it.clear = true; it.clearColor = doubleArrayOf(0.09, 0.05, 0.03, 1.0) })
        camera.setProjection(D20TableLayout.VERTICAL_FOV.toDouble() * 180 / Math.PI, 0.5, 1.0, 400.0, Camera.Fov.VERTICAL)

        materials = UbershaderProvider(engine)
        assetLoader = AssetLoader(engine, materials, EntityManager.get())
        resourceLoader = ResourceLoader(engine)
        dieAsset = loadInstanced(assets.die, dieInstances)
        shadowAsset = loadInstanced(assets.shadow, shadowInstances)
        glowAsset = loadInstanced(assets.glow, glowInstances)
        buildLights()
        for (i in 0 until SLOTS) { hide(dieInstances[i]!!); hide(shadowInstances[i]!!); hide(glowInstances[i]!!) }
        if (io.magicmobile.android.BuildConfig.DEBUG) for (i in 0 until SLOTS) {
            android.util.Log.d("D20Table", "slot $i die root=${dieInstances[i]!!.root} entities=${dieInstances[i]!!.entities.size} " +
                "shadow=${shadowInstances[i]!!.entities.size} glow=${glowInstances[i]!!.entities.size}")
        }

        uiHelper.renderCallback = object : UiHelper.RendererCallback {
            override fun onNativeWindowChanged(surface: android.view.Surface) {
                swapChain?.let { engine.destroySwapChain(it) }
                swapChain = engine.createSwapChain(surface, uiHelper.swapChainFlags)
                requestFrame()
            }
            override fun onDetachedFromSurface() {
                swapChain?.let { engine.destroySwapChain(it); engine.flushAndWait() }
                swapChain = null
            }
            override fun onResized(width: Int, height: Int) {
                viewWidth = width
                viewHeight = height
                view.viewport = Viewport(0, 0, width, height)
                if (lastSeatCount > 0) configure(width, height, lastRegion, lastSeatCount, density)
                requestFrame()
            }
        }
    }

    private fun loadInstanced(buffer: ByteBuffer, instances: Array<FilamentInstance?>): FilamentAsset {
        val asset = assetLoader.createInstancedAsset(buffer.duplicate(), instances) ?: error("could not read a dice model")
        resourceLoader.loadResources(asset)
        asset.releaseSourceData()
        for (i in instances.indices) scene.addEntities(instances[i]!!.entities)
        return asset
    }

    private fun buildLights() {
        // One warm lamp up and to the left (the table picture is lit the same way) and a dim room around it.
        val lamp = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL).color(1f, 0.82f, 0.62f).intensity(95_000f)
            .direction(0.45f, -0.78f, -0.42f).castShadows(false).build(engine, lamp)
        scene.addEntity(lamp)
        lights += lamp
        val glint = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.POINT).color(1f, 0.9f, 0.72f).intensity(2_600_000f).position(-4f, 8f, -3f)
            .falloff(60f).castShadows(false).build(engine, glint)
        scene.addEntity(glint)
        lights += glint
        // Constant warm ambient light (spherical harmonics band 0).
        indirectLight = IndirectLight.Builder().irradiance(1, floatArrayOf(0.62f, 0.42f, 0.30f)).intensity(38_000f).build(engine)
        scene.indirectLight = indirectLight
    }

    fun attach(textureView: TextureView) {
        uiHelper.attachTo(textureView)
        textureView.isOpaque = true
    }

    // MARK: Layout

    /** Fits the camera and lanes to the stage (sizes in pixels), and swaps the table picture for the orientation. */
    fun configure(width: Int, height: Int, region: Rect, seatCount: Int, density: Float) {
        this.density = density
        lastRegion = region
        lastSeatCount = seatCount
        if (width <= 0 || height <= 0) return
        val landscape = width > height
        val hasRegion = region.width > 1f && region.height > 1f
        val area = if (hasRegion) region else Rect(0f, height * 0.2f, width.toFloat(), height * 0.6f)
        val key = listOf(width, height, area.top, area.bottom, area.width, seatCount)
        if (key == layoutKey) return
        layoutKey = key
        val mat = D20TableLayout.matSize(landscape)
        val next = D20TableLayout(width / density, height / density, area.center.y / density, area.width / density, area.height / density,
            seatCount, mat.second)
        layout = next
        if (tableLandscape != landscape) {
            tableLandscape = landscape
            tableAsset?.let { removeAsset(it) }
            val asset = assetLoader.createAsset(assets.table(landscape)) ?: error("could not read the table")
            resourceLoader.loadResources(asset)
            asset.releaseSourceData()
            scene.addEntities(asset.entities)
            tableAsset = asset
        }
        val p = next.cameraPosition
        val f = next.cameraForward
        camera.setProjection(D20TableLayout.VERTICAL_FOV.toDouble() * 180 / Math.PI, width.toDouble() / height, 1.0, 400.0, Camera.Fov.VERTICAL)
        camera.lookAt(p.x.toDouble(), p.y.toDouble(), p.z.toDouble(), (p.x + f.x).toDouble(), (p.y + f.y).toDouble(), (p.z + f.z).toDouble(), 0.0, 1.0, 0.0)
        for (die in dice.values) {
            die.plan = makePlan(die.seatIndex, die.round, die.value, next)
            place(die, die.plan.restPose)
        }
        requestFrame()
    }

    private fun removeAsset(asset: FilamentAsset) {
        scene.removeEntities(asset.entities)
        assetLoader.destroyAsset(asset)
    }

    // MARK: Following the state

    fun apply(state: D20TableState, reduceMotion: Boolean) {
        val layout = layout ?: return
        val throwing = if (reduceMotion) null else state.throwing
        // Dice whose seats left the table, or whose value changed, go (a skipped or reduced roll snaps the die in the air to rest).
        for ((seat, die) in dice.toList()) {
            if (state.resting[seat] != die.value && throwing?.seatID != seat) remove(seat, die, animated = !reduceMotion)
        }
        for ((seat, animation) in animations.toList()) {
            if (throwing?.seatID != seat) {
                animations.remove(seat)
                dice[seat]?.let { place(it, it.plan.restPose) }
                onRest?.invoke(animation.turn)
            }
        }
        for ((seat, value) in state.resting) {
            if (dice[seat] == null && throwing?.seatID != seat) {
                val die = makeDie(seat, value, state, layout) ?: continue
                dice[seat] = die
                place(die, die.plan.restPose)
            }
        }
        if (throwing != null && throwing.turn != lastTurn) {
            lastTurn = throwing.turn
            dice[throwing.seatID]?.let { remove(throwing.seatID, it, animated = false) }
            val die = makeDie(throwing.seatID, throwing.value, state, layout)
            if (io.magicmobile.android.BuildConfig.DEBUG) android.util.Log.d("D20Table", "throw ${throwing.seatID} value ${throwing.value} slot ${die?.slot} " +
                "lane ${die?.plan?.origin?.x} rest ${die?.plan?.restPose?.position}")
            if (die != null) {
                dice[throwing.seatID] = die
                hideDie(die)
                animations[throwing.seatID] = Animation(throwing.seatID, throwing.turn, die)
            }
        }
        for ((seat, die) in dice) setGlow(die, state.highlighted == seat)
        requestFrame()
    }

    /** A seat's throw for this round, laid out in its lane. Which recording it gets depends only on the round and the seat. */
    private fun makePlan(seatIndex: Int, round: Int, value: Int, layout: D20TableLayout): D20ThrowPlan {
        val pick = assets.bank[D20Landing.throwIndex(round, seatIndex, assets.bank.size)]
        val lane = layout.laneX[min(seatIndex, layout.laneX.size - 1)]
        return D20ThrowPlan(assets.model, pick, value, Vec3(lane, 0f, layout.railZ), layout.footprint,
            jitter = D20Landing.jitter(round, seatIndex, 0.2f))
    }

    private fun makeDie(seat: String, value: Int, state: D20TableState, layout: D20TableLayout): Die? {
        val slot = (0 until SLOTS).firstOrNull { s -> dice.values.none { it.slot == s } && dying.none { it.first.slot == s } } ?: return null
        val seatIndex = state.seatOrder.indexOf(seat).coerceAtLeast(0)
        return Die(slot, value, makePlan(seatIndex, state.round, value, layout), seatIndex, state.round)
    }

    private fun remove(seat: String, die: Die, animated: Boolean) {
        dice.remove(seat)
        animations.remove(seat)
        if (animated) dying += die to System.nanoTime() else hideDie(die)
    }

    // MARK: Transforms

    private fun hide(instance: FilamentInstance) = setTransform(instance.root, Vec3(0f, -50f, 0f), Quat.identity, 0.0001f)

    private fun hideDie(die: Die) {
        hide(dieInstances[die.slot]!!)
        hide(shadowInstances[die.slot]!!)
        hide(glowInstances[die.slot]!!)
    }

    private fun setGlow(die: Die, on: Boolean) {
        val instance = glowInstances[die.slot]!!
        if (!on || animations.values.any { it.plan === die.plan }) { hide(instance); return }
        val pos = die.plan.restPose.position
        setTransform(instance.root, Vec3(pos.x, 0.03f, pos.z), Quat.identity, 1f)
    }

    private fun place(die: Die, pose: D20Pose, scale: Float = 1f, shadowAlpha: Float = 0.75f, height: Float = 0f) {
        setTransform(dieInstances[die.slot]!!.root, pose.position, pose.orientation, scale)
        val spread = (1 + height * 0.5f) * 0.9f * scale
        setTransform(shadowInstances[die.slot]!!.root, Vec3(pose.position.x + 0.35f + height * 0.55f, 0.02f, pose.position.z + 0.35f + height * 0.55f),
            Quat.identity, spread)
        tint(shadowInstances[die.slot]!!, shadowAlpha)
    }

    private fun tint(instance: FilamentInstance, alpha: Float) {
        val rm = engine.renderableManager
        for (entity in instance.entities) {
            if (!rm.hasComponent(entity)) continue
            val ri = rm.getInstance(entity)
            for (i in 0 until rm.getPrimitiveCount(ri)) rm.getMaterialInstanceAt(ri, i).setParameter("baseColorFactor", 1f, 1f, 1f, alpha)
        }
    }

    private fun setTransform(entity: Int, position: Vec3, orientation: Quat, scale: Float) {
        val tm = engine.transformManager
        val instance = tm.getInstance(entity)
        val q = orientation
        val xx = q.x * q.x; val yy = q.y * q.y; val zz = q.z * q.z
        val xy = q.x * q.y; val xz = q.x * q.z; val yz = q.y * q.z
        val wx = q.w * q.x; val wy = q.w * q.y; val wz = q.w * q.z
        // Column-major, rotation scaled uniformly, translation in the last column.
        val m = floatArrayOf(
            (1 - 2 * (yy + zz)) * scale, (2 * (xy + wz)) * scale, (2 * (xz - wy)) * scale, 0f,
            (2 * (xy - wz)) * scale, (1 - 2 * (xx + zz)) * scale, (2 * (yz + wx)) * scale, 0f,
            (2 * (xz + wy)) * scale, (2 * (yz - wx)) * scale, (1 - 2 * (xx + yy)) * scale, 0f,
            position.x, position.y, position.z, 1f)
        tm.setTransform(instance, m)
    }

    // MARK: Frames

    private val frameCallback = Choreographer.FrameCallback { nanos ->
        frameRequested = false
        if (destroyed) return@FrameCallback
        advance(nanos)
        val chain = swapChain
        if (chain != null && uiHelper.isReadyToRender && renderer.beginFrame(chain, nanos)) {
            renderer.render(view)
            renderer.endFrame()
            if (++framesDrawn == 3) onReady?.invoke()
        }
        if (animations.isNotEmpty() || dying.isNotEmpty()) requestFrame()
    }

    fun requestFrame() {
        if (frameRequested || destroyed) return
        frameRequested = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun advance(nanos: Long) {
        val finished = ArrayList<Animation>()
        for (animation in animations.values) {
            val die = dice[animation.seat] ?: continue
            if (animation.start == 0L) animation.start = nanos
            val t = (nanos - animation.start) / 1e9f
            val plan = animation.plan
            val pose = plan.pose(t)
            val appear = min(1f, t / 0.12f)
            val height = max(pose.position.y - plan.model.inradius, 0f)
            place(die, pose, 0.5f + 0.5f * appear, max(0.15f, 0.75f - height * 0.22f) * appear, height)
            if (!animation.firedEdge && t >= plan.railTime) { animation.firedEdge = true; onEdgeHit?.invoke(animation.turn) }
            if (!animation.firedRebound && t >= plan.railTime + 0.3f) { animation.firedRebound = true; onRebound?.invoke(animation.turn) }
            if (t >= plan.duration) finished += animation
        }
        for (animation in finished) {
            animations.remove(animation.seat)
            dice[animation.seat]?.let { place(it, it.plan.restPose) }
            onRest?.invoke(animation.turn)
        }
        val now = System.nanoTime()
        val gone = dying.filter { (now - it.second) / 1e9f >= 0.22f }
        for ((die, _) in gone) hideDie(die)
        dying.removeAll(gone.toSet())
        for ((die, started) in dying) {
            val t = ((now - started) / 1e9f / 0.22f).coerceIn(0f, 1f)
            place(die, die.plan.restPose, 1 - 0.4f * t, 0.75f * (1 - t))
        }
    }

    fun destroy() {
        destroyed = true
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        uiHelper.detach()
        swapChain?.let { engine.destroySwapChain(it) }
        swapChain = null
        tableAsset?.let { assetLoader.destroyAsset(it) }
        assetLoader.destroyAsset(dieAsset)
        assetLoader.destroyAsset(shadowAsset)
        assetLoader.destroyAsset(glowAsset)
        assetLoader.destroy()
        resourceLoader.destroy()
        materials.destroyMaterials()
        materials.destroy()
        for (light in lights) { engine.lightManager.destroy(light); engine.destroyEntity(light); EntityManager.get().destroy(light) }
        indirectLight?.let { engine.destroyIndirectLight(it) }
        colorGrading?.let { engine.destroyColorGrading(it) }
        engine.destroyCameraComponent(cameraEntity)
        EntityManager.get().destroy(cameraEntity)
        engine.destroyView(view)
        engine.destroyScene(scene)
        engine.destroyRenderer(renderer)
        engine.destroy()
    }

    private companion object {
        const val SLOTS = 4
    }
}

/** The table behind the starting roll, as a Compose view: transparent to touches and to TalkBack. */
@Composable
fun D20TableView(region: Rect, state: D20TableState, reduceMotion: Boolean, modifier: Modifier = Modifier,
                 onEdgeHit: (Int) -> Unit = {}, onRebound: (Int) -> Unit = {}, onRest: (Int) -> Unit = {}, onReady: () -> Unit = {}) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    val scene = remember { D20Assets.load(context)?.let { D20TableScene(context, it) } }
    DisposableEffect(scene) { onDispose { scene?.destroy() } }
    val edge by rememberUpdatedState(onEdgeHit)
    val rebound by rememberUpdatedState(onRebound)
    val rest by rememberUpdatedState(onRest)
    val ready by rememberUpdatedState(onReady)
    if (scene == null) return
    SideEffect {
        scene.onEdgeHit = { edge(it) }
        scene.onRebound = { rebound(it) }
        scene.onRest = { rest(it) }
        scene.onReady = { ready() }
    }
    AndroidView(factory = { ctx -> TextureView(ctx).also { scene.attach(it) } }, modifier = modifier,
        update = { textureView ->
            scene.configure(textureView.width, textureView.height, region, state.seatOrder.size, density)
            scene.apply(state, reduceMotion)
        })
}
