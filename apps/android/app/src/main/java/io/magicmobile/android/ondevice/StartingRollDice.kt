package io.magicmobile.android.ondevice

import io.magicmobile.android.ui.Quat
import io.magicmobile.android.ui.Vec3
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.float
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.tan

/*
 * The starting roll's dice as pure data and maths (no Filament, no Android), ported from
 * StartingRollDice.swift so the landing rule can be unit-tested and stays identical on both platforms:
 * the die's faces, the recorded throws, the symmetry that lets one throw end on any number, and where
 * the table's camera and lanes go. docs/STARTING_ROLL.md has the picture. Keep the two in step.
 */

/** d20.json: what each face of the die is called, where it points and which way its numeral reads. */
class D20Model(val inradius: Float, val faces: List<Face>, val vertices: List<Vec3>) {
    class Face(val index: Int, val number: Int, val normal: Vec3, val corners: List<Vec3>) {
        fun corner(k: Int): Vec3 = corners[k % corners.size]
    }

    fun face(number: Int): Face? = faces.firstOrNull { it.number == number }

    companion object {
        private fun vec(array: JsonArray) = Vec3(array[0].jsonPrimitive.float, array[1].jsonPrimitive.float, array[2].jsonPrimitive.float)

        fun parse(text: String): D20Model {
            val root = Json.parseToJsonElement(text).jsonObject
            val faces = root["faces"]!!.jsonArray.map { element ->
                val face = element.jsonObject
                Face(face["index"]!!.jsonPrimitive.int, face["number"]!!.jsonPrimitive.int, vec(face["normal"]!!.jsonArray),
                    face["cornerDirections"]!!.jsonArray.map { vec(it.jsonArray) })
            }
            return D20Model(root["inradius"]!!.jsonPrimitive.float, faces, root["vertices"]!!.jsonArray.map { vec(it.jsonArray) })
        }
    }
}

/** One recorded tumble along the table, ending with some face up (d20-throws.json). */
class D20Throw(val frames: Int, val faceUp: Int, private val position: FloatArray, private val orientation: FloatArray,
               val railTime: Float, val tableHits: List<Pair<Float, Float>>) {
    val duration: Float get() = (frames - 1) / 60f
    fun position(frame: Int): Vec3 {
        val i = frame.coerceIn(0, frames - 1) * 3
        return Vec3(position[i], position[i + 1], position[i + 2])
    }
    fun orientation(frame: Int): Quat {
        val i = frame.coerceIn(0, frames - 1) * 4
        return Quat(orientation[i + 3], orientation[i], orientation[i + 1], orientation[i + 2])
    }

    companion object {
        fun parseBank(text: String): List<D20Throw> = Json.parseToJsonElement(text).jsonObject["throws"]!!.jsonArray.map { element ->
            val t = element.jsonObject
            fun floats(key: String) = t[key]!!.jsonArray.let { a -> FloatArray(a.size) { a[it].jsonPrimitive.float } }
            D20Throw(t["frames"]!!.jsonPrimitive.int, t["faceUp"]!!.jsonPrimitive.int, floats("position"), floats("orientation"),
                t["railTime"]!!.jsonPrimitive.float, t["tableHits"]!!.jsonArray.map { it.jsonArray[0].jsonPrimitive.float to it.jsonArray[1].jsonPrimitive.float })
        }
    }
}

class D20Pose(val position: Vec3, val orientation: Quat)

/**
 * One die's throw, re-labelled so the recorded path ends with `number` on top.
 *
 * A regular icosahedron looks the same after any of its 60 rotations. The recording ends with face F up;
 * to make it end with face T up, the body is turned by the symmetry S that carries T onto F before the
 * recorded motion is applied: world orientation = recorded orientation * S. Nothing about the motion
 * changes, only which numeral sits on which face. Three symmetries carry T onto F (a third of a turn about
 * the face apart); the one that leaves the numeral reading closest to upright is used, and the last stretch
 * of the throw turns the die the rest of the way, as a die skids to a stop.
 */
class D20ThrowPlan(val model: D20Model, val recorded: D20Throw, val number: Int, val origin: Vec3 = Vec3(0f, 0f, 0f),
                   val footprint: Float = 1f, upright: Vec3 = Vec3(0f, 0f, -1f), jitter: Float = 0f) {
    val corner: Int
    val endYaw: Float
    val symmetry: Quat

    init {
        val target = model.face(number) ?: model.faces[0]
        val resting = model.faces[recorded.faceUp]
        val finish = recorded.orientation(recorded.frames - 1)
        var bestCorner = 0
        var bestYaw = 0f
        var bestSymmetry = Quat.identity
        for (k in 0 until 3) {
            val s = D20Landing.symmetry(target, resting, k)
            val up = finish.rotate(s.rotate(target.corner(0))).let { Vec3(it.x, 0f, it.z) }
            val yaw = D20Landing.yaw(up, upright)
            if (k == 0 || abs(yaw) < abs(bestYaw)) { bestCorner = k; bestYaw = yaw; bestSymmetry = s }
        }
        corner = bestCorner
        endYaw = bestYaw + jitter
        symmetry = bestSymmetry
    }

    val duration: Float get() = recorded.duration
    val railTime: Float get() = recorded.railTime
    val restPose: D20Pose get() = pose(duration)

    /** The die's pose `time` seconds into the throw (held at its resting pose afterwards). */
    fun pose(time: Float): D20Pose {
        val clamped = time.coerceIn(0f, duration)
        val exact = clamped * 60f
        val i = exact.toInt()
        val f = exact - i
        val p0 = recorded.position(i)
        val p1 = recorded.position(i + 1)
        val p = p0 + (p1 - p0) * f
        val q = Quat.slerp(recorded.orientation(i), recorded.orientation(i + 1), f)
        // The extra yaw comes in over the last stretch, after the final hard bounce.
        val settleStart = max(recorded.railTime + 0.3f, duration - 0.75f)
        val t = ((clamped - settleStart) / max(duration - settleStart, 0.001f)).coerceIn(0f, 1f)
        val eased = t * t * (3 - 2 * t)
        val yaw = Quat.axisAngle(Vec3(0f, 1f, 0f), endYaw * eased)
        return D20Pose(Vec3(origin.x + p.x * footprint, p.y, origin.z + p.z * footprint), (yaw * q * symmetry).normalized())
    }
}

object D20Landing {
    /** The rotation (in the die's own frame) that turns `target` into `resting`, with the numeral's corner 0 on `target` landing on corner `k`. */
    fun symmetry(target: D20Model.Face, resting: D20Model.Face, k: Int): Quat {
        fun frame(normal: Vec3, corner: Vec3): Triple<Vec3, Vec3, Vec3> {
            val n = normal.normalized()
            val u = (corner - n * (corner dot n)).normalized()
            return Triple(n, u, n cross u)
        }
        val a = frame(target.normal, target.corner(0))
        val b = frame(resting.normal, resting.corner(k))
        // S = B * A^T: column j is b0 a0[j] + b1 a1[j] + b2 a2[j].
        fun column(j: Int): Vec3 {
            fun at(v: Vec3) = when (j) { 0 -> v.x; 1 -> v.y; else -> v.z }
            return b.first * at(a.first) + b.second * at(a.second) + b.third * at(a.third)
        }
        return Quat.basis(column(0), column(1), column(2))
    }

    /** The turn about +y that carries one horizontal direction onto another, in -pi..pi. A turn of t takes the heading atan2(x, z) to heading + t. */
    fun yaw(from: Vec3, to: Vec3): Float {
        var turn = atan2(to.x, to.z) - atan2(from.x, from.z)
        val pi = Math.PI.toFloat()
        while (turn > pi) turn -= 2 * pi
        while (turn <= -pi) turn += 2 * pi
        return turn
    }

    /** A throw for a seat's roll, spread so neighbours look different: the roll round and the seat pick it. */
    fun throwIndex(round: Int, seatIndex: Int, count: Int): Int =
        if (count <= 0) 0 else (round * 5 + seatIndex * 3 + (if (round > 0) 1 else 0)) % count

    /** A small deterministic offset in -range..range for a seat's roll, so the numerals do not all stand to attention. */
    fun jitter(round: Int, seatIndex: Int, range: Float): Float {
        val h = ((round.toLong() * 7919L + seatIndex.toLong() * 104729L + 17L) and 0xFFFFFFFFL)
        val unit = (((h * 2654435761L) and 0xFFFFFFFFL) shr 16 and 0xFFFFL).toFloat() / 65535f
        return (unit * 2 - 1) * range
    }
}

/**
 * Where the camera sits, where each seat's lane runs and how far the throws travel, for one stage.
 * All in the die's units (circumradius 1) on the table plane at y = 0, +z toward the viewer.
 */
class D20TableLayout(stageWidth: Float, stageHeight: Float, regionMidY: Float, regionWidth: Float, regionHeight: Float,
                     seatCount: Int, matDepth: Float) {
    val laneX: List<Float>
    val railZ: Float
    val footprint: Float
    val pointsPerUnit: Float
    val cameraPosition: Vec3
    val cameraForward: Vec3

    init {
        val count = max(1, seatCount)
        val spacing = if (count <= 2) 3.1f else 2.45f
        val byWidth = max(regionWidth, 1f) / (spacing * count + 1.4f)
        val byHeight = max(regionHeight, 1f) / ((THROW_DEPTH + 1.6f) * MIN_FOOTPRINT)
        val ppu = min(min(byWidth, byHeight), 58f)
        footprint = min(1f, max(MIN_FOOTPRINT, max(regionHeight, 1f) / ((THROW_DEPTH + 1.6f) * ppu)))
        pointsPerUnit = ppu
        laneX = (0 until count).map { (it - (count - 1) / 2f) * spacing }
        railZ = -matDepth / 2
        // The ray through the middle of the roll area meets the table at the point halfway down the throw.
        val span = THROW_DEPTH * footprint
        val targetZ = railZ + span / 2 + 0.2f
        val fPx = stageHeight / 2 / tan(VERTICAL_FOV / 2)
        // The roll area need not sit in the middle of the stage: the camera's axis is turned by the angle
        // between the stage's middle and the roll area's, so the same ray lands on the area's middle.
        val beta = atan((regionMidY - stageHeight / 2) / fPx)
        val rayPitch = Math.PI.toFloat() / 2 - TILT
        val distance = fPx / (ppu * cos(beta))
        val h = distance * sin(rayPitch)
        cameraPosition = Vec3(0f, h, targetZ + h / tan(rayPitch))
        val axisPitch = rayPitch - beta
        cameraForward = Vec3(0f, -sin(axisPitch), -cos(axisPitch))
    }

    companion object {
        const val VERTICAL_FOV = 40f * Math.PI.toFloat() / 180f
        const val TILT = 18f * Math.PI.toFloat() / 180f
        const val THROW_DEPTH = 8.2f
        const val MIN_FOOTPRINT = 0.5f
        /** The mat's size in die radii (d20-table.json): portrait is tall. */
        fun matSize(landscape: Boolean): Pair<Float, Float> = if (landscape) 15.2f to 9.6f else 9.6f to 15.2f
    }
}

/** What the table should be showing right now. The roll's view owns this; the scene follows it. */
data class D20TableState(
    /** Every seat in lane order, left to right. */
    val seatOrder: List<String>,
    /** The roll round: a new round clears the table and throws different paths. */
    val round: Int,
    /** Dice at rest on the table, by seat. */
    val resting: Map<String, Int>,
    val throwing: Throw?,
    /** The seat whose die glows (the winner, once the roll is over). */
    val highlighted: String?,
) {
    data class Throw(val seatID: String, val value: Int, val turn: Int)
}
