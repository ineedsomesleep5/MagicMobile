package io.magicmobile.android.ui

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.drawText
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

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

/**
 * The D20 from MultiplayerD20View.swift: a real icosahedron (12 vertices, 20 flat faces, 30 edges),
 * every face numbered. A result is shown by turning its face to the camera; drawing never picks it.
 */
object D20Die {
    private val phi = ((1 + sqrt(5.0)) / 2).toFloat()
    val vertices: List<Vec3> = listOf(
        Vec3(-1f, phi, 0f), Vec3(1f, phi, 0f), Vec3(-1f, -phi, 0f), Vec3(1f, -phi, 0f),
        Vec3(0f, -1f, phi), Vec3(0f, 1f, phi), Vec3(0f, -1f, -phi), Vec3(0f, 1f, -phi),
        Vec3(phi, 0f, -1f), Vec3(phi, 0f, 1f), Vec3(-phi, 0f, -1f), Vec3(-phi, 0f, 1f)).map { it.normalized() }
    private val rawFaces = listOf(
        intArrayOf(0, 11, 5), intArrayOf(0, 5, 1), intArrayOf(0, 1, 7), intArrayOf(0, 7, 10), intArrayOf(0, 10, 11),
        intArrayOf(1, 5, 9), intArrayOf(5, 11, 4), intArrayOf(11, 10, 2), intArrayOf(10, 7, 6), intArrayOf(7, 1, 8),
        intArrayOf(3, 9, 4), intArrayOf(3, 4, 2), intArrayOf(3, 2, 6), intArrayOf(3, 6, 8), intArrayOf(3, 8, 9),
        intArrayOf(4, 9, 5), intArrayOf(2, 4, 11), intArrayOf(6, 2, 10), intArrayOf(8, 6, 7), intArrayOf(9, 8, 1))

    class Face(val a: Int, val b: Int, val c: Int, val normal: Vec3, val centroid: Vec3, val basis: Quat)

    val faces: List<Face> = rawFaces.map { f ->
        val a = vertices[f[0]]; var bi = f[1]; var ci = f[2]
        var normal = ((vertices[bi] - a) cross (vertices[ci] - a)).normalized()
        if (normal dot (a + vertices[bi] + vertices[ci]) < 0) { val t = bi; bi = ci; ci = t; normal = -normal }
        val vertical = Vec3(0f, 1f, 0f)
        val reference = if (kotlin.math.abs(normal dot vertical) > 0.95f) Vec3(1f, 0f, 0f) else vertical
        val up = (reference - normal * (reference dot normal)).normalized()
        val right = (up cross normal).normalized()
        Face(f[0], bi, ci, normal, (a + vertices[bi] + vertices[ci]) * (1f / 3f), Quat.basis(right, normal cross right, normal))
    }

    /** Each physical edge once. */
    private val edges: List<Pair<Int, Int>> = faces.flatMap { listOf(it.a to it.b, it.b to it.c, it.c to it.a) }
        .map { (p, q) -> min(p, q) to max(p, q) }.distinct()

    /** The orientation that shows `value` toward the camera, upright. */
    fun restOrientation(value: Int?): Quat =
        if (value != null && value in 1..20) faces[value - 1].basis.inverse() else Quat.axisAngle(Vec3(0f, 1f, 0f), 0.55f)

    private val enamel = Vec3(0.73f, 0.31f, 0.13f)
    private val light = Vec3(-2f, 3f, 4f).normalized()
    private val metal = Color(1f, 0.78f, 0.46f)
    val ink = Color(243 / 255f, 241 / 255f, 236 / 255f)

    /**
     * Draws the die (radius in px) at `center`. `labels[i]` is face i+1's measured number; faces
     * turned edge-on skip their number, as SceneKit's depth test would hide it.
     */
    fun DrawScope.drawD20(orientation: Quat, center: Offset, radius: Float, labels: List<TextLayoutResult>?, showLabels: Boolean = true) {
        val rotated = vertices.map(orientation::rotate)
        fun project(v: Vec3) = Offset(center.x + v.x * radius, center.y - v.y * radius)
        val visible = faces.indices.filter { orientation.rotate(faces[it].normal).z > 0f }
            .sortedBy { orientation.rotate(faces[it].centroid).z }
        val view = Vec3(0f, 0f, 1f)
        val half = (light + view).normalized()
        val edgeWidth = max(1f, radius * 0.018f)
        for (index in visible) {
            val face = faces[index]
            val n = orientation.rotate(face.normal)
            val diffuse = max(0f, n dot light)
            val specular = max(0f, n dot half).pow(28f) * 0.42f
            val shade = 0.36f + 0.78f * diffuse
            val color = Color((enamel.x * shade + specular).coerceIn(0f, 1f), (enamel.y * shade + specular * 0.9f).coerceIn(0f, 1f),
                (enamel.z * shade + specular * 0.8f).coerceIn(0f, 1f))
            val path = Path().apply {
                val a = project(rotated[face.a]); val b = project(rotated[face.b]); val c = project(rotated[face.c])
                moveTo(a.x, a.y); lineTo(b.x, b.y); lineTo(c.x, c.y); close()
            }
            drawPath(path, color)
        }
        for ((p, q) in edges) {
            // An edge is visible when either face that shares it faces the camera.
            if (visible.none { i -> faces[i].let { f -> setOf(f.a, f.b, f.c).containsAll(listOf(p, q)) } }) continue
            drawLine(metal, project(rotated[p]), project(rotated[q]), edgeWidth)
        }
        if (!showLabels || labels == null) return
        for (index in visible) {
            val face = faces[index]
            val n = orientation.rotate(face.normal)
            if (n.z < 0.18f) continue
            val label = labels.getOrNull(index) ?: continue
            val basis = orientation * face.basis
            val right = basis.rotate(Vec3(1f, 0f, 0f)); val up = basis.rotate(Vec3(0f, 1f, 0f))
            val origin = project(orientation.rotate(face.centroid + face.normal * 0.025f))
            // Glyphs about 0.3 die-radius tall, lying flat on the face.
            val unit = radius * 0.3f / max(1f, label.size.height.toFloat())
            val matrix = Matrix().apply {
                values[Matrix.ScaleX] = right.x * unit; values[Matrix.SkewY] = -right.y * unit
                values[Matrix.SkewX] = -up.x * unit; values[Matrix.ScaleY] = up.y * unit
                values[Matrix.TranslateX] = origin.x; values[Matrix.TranslateY] = origin.y
            }
            withTransform({ transform(matrix) }) {
                drawText(label, ink.copy(alpha = (n.z * 1.6f).coerceIn(0f, 1f)),
                    Offset(-label.size.width / 2f, -label.size.height / 2f))
            }
        }
    }

    /** The flat hexagon face used when motion is reduced (DieOutline and DieFacets). */
    fun DrawScope.drawFlatD20(accent: Color, surface: Color) {
        fun p(x: Float, y: Float) = Offset(x * size.width, y * size.height)
        val outline = listOf(p(0.5f, 0.02f), p(0.91f, 0.23f), p(0.97f, 0.65f), p(0.5f, 0.98f), p(0.03f, 0.65f), p(0.09f, 0.23f))
        val path = Path().apply { moveTo(outline[0].x, outline[0].y); outline.drop(1).forEach { lineTo(it.x, it.y) }; close() }
        drawPath(path, androidx.compose.ui.graphics.Brush.linearGradient(listOf(accent.copy(alpha = 0.95f), accent.copy(alpha = 0.45f), surface),
            Offset.Zero, Offset(size.width, size.height)))
        val facets = Path().apply {
            moveTo(p(0.5f, 0.02f).x, p(0.5f, 0.02f).y); lineTo(p(0.5f, 0.27f).x, p(0.5f, 0.27f).y); lineTo(p(0.09f, 0.23f).x, p(0.09f, 0.23f).y)
            moveTo(p(0.5f, 0.27f).x, p(0.5f, 0.27f).y); lineTo(p(0.91f, 0.23f).x, p(0.91f, 0.23f).y)
            moveTo(p(0.09f, 0.23f).x, p(0.09f, 0.23f).y); lineTo(p(0.19f, 0.7f).x, p(0.19f, 0.7f).y); lineTo(p(0.5f, 0.98f).x, p(0.5f, 0.98f).y)
            moveTo(p(0.91f, 0.23f).x, p(0.91f, 0.23f).y); lineTo(p(0.81f, 0.7f).x, p(0.81f, 0.7f).y); lineTo(p(0.5f, 0.98f).x, p(0.5f, 0.98f).y)
        }
        drawPath(facets, ink.copy(alpha = 0.28f), style = Stroke(1f * density))
        drawPath(path, ink.copy(alpha = 0.7f), style = Stroke(1.5f * density))
    }
}
