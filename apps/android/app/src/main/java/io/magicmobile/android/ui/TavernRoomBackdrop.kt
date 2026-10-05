package io.magicmobile.android.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.max
import kotlin.math.sin

/**
 * The tavern room behind the main menu (TavernRoomBackdrop.swift): a rendered 3D room (scripts/brand/tavern_room.py) in three
 * depth layers that slide against each other as the phone tilts, with its candles, lanterns and hearth flickering on top.
 */
class TavernRoomShot(val width: Float, val height: Float, val lights: List<Light>, val back: ImageBitmap, val mid: ImageBitmap, val front: ImageBitmap) {
    class Light(val x: Float, val y: Float, val layer: String, val kind: String, val radius: Float)

    companion object {
        /** Each layer is drawn this much larger than the screen so a tilt never shows its edge. */
        const val OVERSCAN = 1.08f
        /** The furthest the nearest layer slides, in dp. */
        const val REACH_DP = 16f
        fun depth(layer: String) = when (layer) { "back" -> 0.3f; "mid" -> 0.65f; else -> 1f }
    }
}

object TavernRoom {
    private val cache = HashMap<String, TavernRoomShot>()

    /** The room for an orientation, decoded once; null when the art isn't installed (the flat tavern wall shows instead). */
    fun load(context: Context, orientation: String): TavernRoomShot? {
        synchronized(cache) { cache[orientation] }?.let { return it }
        val shot = runCatching {
            val root = Json.parseToJsonElement(context.assets.open("tavern-room.json").bufferedReader().use { it.readText() }).jsonObject
            val view = root[orientation]?.jsonObject ?: return null
            fun image(layer: String, opaque: Boolean): ImageBitmap? {
                val id = context.resources.getIdentifier("tavern_room_${orientation}_$layer", "drawable", context.packageName)
                if (id == 0) return null
                val options = BitmapFactory.Options().apply {
                    inScaled = false
                    // The room behind everything needs no alpha: half the memory.
                    if (opaque) inPreferredConfig = Bitmap.Config.RGB_565
                }
                return BitmapFactory.decodeResource(context.resources, id, options)?.also { it.prepareToDraw() }?.asImageBitmap()
            }
            val lights = view["lights"]?.jsonArray.orEmpty().map { row ->
                val o = row as JsonObject
                TavernRoomShot.Light(o["x"]!!.jsonPrimitive.double.toFloat(), o["y"]!!.jsonPrimitive.double.toFloat(),
                    o["layer"]!!.jsonPrimitive.content, o["kind"]!!.jsonPrimitive.content, o["radius"]!!.jsonPrimitive.double.toFloat())
            }
            TavernRoomShot(view["width"]!!.jsonPrimitive.double.toFloat(), view["height"]!!.jsonPrimitive.double.toFloat(), lights,
                image("back", true) ?: return null, image("mid", false) ?: return null, image("front", false) ?: return null)
        }.getOrNull() ?: return null
        synchronized(cache) { cache.clear(); cache[orientation] = shot }  // one orientation in memory at a time
        return shot
    }
}

/** The room for this orientation, decoded off the main thread. */
@Composable
fun rememberTavernRoom(portrait: Boolean): State<TavernRoomShot?> {
    val context = LocalContext.current
    val state = remember(portrait) { mutableStateOf<TavernRoomShot?>(null) }
    LaunchedEffect(portrait) { state.value = withContext(Dispatchers.IO) { TavernRoom.load(context.applicationContext, if (portrait) "portrait" else "landscape") } }
    return state
}

/**
 * The phone's tilt from where it was held when the room appeared, smoothed, as -1..1 on each axis (DeviceTilt on iOS).
 * Read the state inside drawing so a tilt only redraws.
 */
@Composable
fun rememberDeviceTilt(active: Boolean): State<Offset> {
    val context = LocalContext.current
    val state = remember { mutableStateOf(Offset.Zero) }
    DisposableEffect(active) {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_GRAVITY) ?: manager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (!active || manager == null || sensor == null) { state.value = Offset.Zero; return@DisposableEffect onDispose {} }
        var reference: Offset? = null
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                // Android reports +x when the right edge dips; normalise by gravity like iOS's unit gravity vector.
                val g = Offset(-event.values[0] / SensorManager.GRAVITY_EARTH, -event.values[1] / SensorManager.GRAVITY_EARTH)
                val ref = reference ?: g
                reference = Offset(ref.x * 0.995f + g.x * 0.005f, ref.y * 0.995f + g.y * 0.005f)  // drifts back to centre
                val dx = ((g.x - ref.x) * 3).coerceIn(-1f, 1f); val dy = ((g.y - ref.y) * 3).coerceIn(-1f, 1f)
                val target = Offset(-dx, dy)
                val next = Offset(state.value.x * 0.8f + target.x * 0.2f, state.value.y * 0.8f + target.y * 0.2f)
                // Only a visible move (about a quarter dp at full reach): a still phone doesn't redraw the menu.
                if (kotlin.math.abs(next.x - state.value.x) >= 0.015f || kotlin.math.abs(next.y - state.value.y) >= 0.015f) state.value = next
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        onDispose { manager.unregisterListener(listener); state.value = Offset.Zero }
    }
    return state
}

/** Draws the room's layers shifted by `tilt` (-1..1) and its flickering glows at `t` seconds. */
fun DrawScope.drawTavernRoom(shot: TavernRoomShot, tilt: Offset, t: Double) {
    val scale = max(size.width * TavernRoomShot.OVERSCAN / shot.width, size.height * TavernRoomShot.OVERSCAN / shot.height)
    val drawn = Size(shot.width * scale, shot.height * scale)
    val origin = Offset((size.width - drawn.width) / 2, (size.height - drawn.height) / 2)
    val reach = TavernRoomShot.REACH_DP * density
    fun shift(layer: String) = Offset(tilt.x * reach * TavernRoomShot.depth(layer), tilt.y * reach * TavernRoomShot.depth(layer))
    for ((layer, image) in listOf("back" to shot.back, "mid" to shot.mid, "front" to shot.front)) {
        drawStretched(image, origin + shift(layer), drawn)
    }
    shot.lights.forEachIndexed { index, light ->
        val seed = index * 1.618
        val flicker = (0.78 + 0.14 * sin(t * (7.1 + seed) + seed) + 0.08 * sin(t * (13.3 + seed * 0.7))).toFloat()
        val center = origin + Offset(light.x * drawn.width, light.y * drawn.height) + shift(light.layer)
        val radius = max(8f * density, light.radius * drawn.height * (if (light.kind == "hearth") 1.2f else 1.6f)) * (0.94f + 0.06f * flicker)
        val warm = if (light.kind == "hearth") Color(1f, 0.45f, 0.12f) else Color(1f, 0.62f, 0.28f)
        drawCircle(Brush.radialGradient(listOf(warm.copy(alpha = 0.42f * flicker), warm.copy(alpha = 0.12f * flicker), Color.Transparent), center, radius),
            radius, center, blendMode = BlendMode.Plus)
    }
}
