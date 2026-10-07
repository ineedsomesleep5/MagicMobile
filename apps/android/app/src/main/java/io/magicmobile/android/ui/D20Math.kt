package io.magicmobile.android.ui

import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** Small vector and rotation maths for the starting roll's dice (ondevice/StartingRollDice.kt). */
data class Vec3(val x: Float, val y: Float, val z: Float) {
    operator fun plus(o: Vec3) = Vec3(x + o.x, y + o.y, z + o.z)
    operator fun minus(o: Vec3) = Vec3(x - o.x, y - o.y, z - o.z)
    operator fun times(s: Float) = Vec3(x * s, y * s, z * s)
    operator fun unaryMinus() = Vec3(-x, -y, -z)
    infix fun dot(o: Vec3) = x * o.x + y * o.y + z * o.z
    infix fun cross(o: Vec3) = Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    val length: Float get() = sqrt(this dot this)
    fun normalized(): Vec3 = length.let { if (it == 0f) this else this * (1f / it) }
}

/** A unit rotation quaternion (simd_quatf). */
data class Quat(val w: Float, val x: Float, val y: Float, val z: Float) {
    operator fun times(q: Quat) = Quat(
        w * q.w - x * q.x - y * q.y - z * q.z,
        w * q.x + x * q.w + y * q.z - z * q.y,
        w * q.y - x * q.z + y * q.w + z * q.x,
        w * q.z + x * q.y - y * q.x + z * q.w)
    fun inverse() = Quat(w, -x, -y, -z)
    fun normalized(): Quat = sqrt(w * w + x * x + y * y + z * z).let { Quat(w / it, x / it, y / it, z / it) }
    fun rotate(v: Vec3): Vec3 {
        val u = Vec3(x, y, z)
        val t = (u cross v) * 2f
        return v + t * w + (u cross t)
    }

    companion object {
        val identity = Quat(1f, 0f, 0f, 0f)
        fun axisAngle(axis: Vec3, angle: Float): Quat {
            val a = axis.normalized(); val s = sin(angle / 2)
            return Quat(cos(angle / 2), a.x * s, a.y * s, a.z * s)
        }
        /** The rotation whose matrix columns are the given orthonormal basis. */
        fun basis(right: Vec3, up: Vec3, normal: Vec3): Quat {
            val m00 = right.x; val m10 = right.y; val m20 = right.z
            val m01 = up.x; val m11 = up.y; val m21 = up.z
            val m02 = normal.x; val m12 = normal.y; val m22 = normal.z
            val trace = m00 + m11 + m22
            return if (trace > 0) {
                val s = sqrt(trace + 1f) * 2
                Quat(0.25f * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s)
            } else if (m00 > m11 && m00 > m22) {
                val s = sqrt(1f + m00 - m11 - m22) * 2
                Quat((m21 - m12) / s, 0.25f * s, (m01 + m10) / s, (m02 + m20) / s)
            } else if (m11 > m22) {
                val s = sqrt(1f + m11 - m00 - m22) * 2
                Quat((m02 - m20) / s, (m01 + m10) / s, 0.25f * s, (m12 + m21) / s)
            } else {
                val s = sqrt(1f + m22 - m00 - m11) * 2
                Quat((m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25f * s)
            }.normalized()
        }
        fun slerp(a: Quat, b0: Quat, t: Float): Quat {
            var b = b0
            var dot = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z
            if (dot < 0) { b = Quat(-b.w, -b.x, -b.y, -b.z); dot = -dot }
            if (dot > 0.9995f) return Quat(a.w + (b.w - a.w) * t, a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t).normalized()
            val theta = acos(dot.coerceIn(-1f, 1f)); val s = sin(theta)
            val wa = sin((1 - t) * theta) / s; val wb = sin(t * theta) / s
            return Quat(a.w * wa + b.w * wb, a.x * wa + b.x * wb, a.y * wa + b.y * wb, a.z * wa + b.z * wb)
        }
    }
}
