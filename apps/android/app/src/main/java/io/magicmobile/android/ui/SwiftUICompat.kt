package io.magicmobile.android.ui

import android.graphics.BlurMaskFilter
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.PaintingStyle
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp

/**
 * SwiftUI behaviours Compose lacks, so ported views keep iOS geometry:
 * `.minimumScaleFactor`, coloured `.shadow` glows, and `.saturation`/`.brightness`.
 */

/** `Text(...).lineLimit(n).minimumScaleFactor(m)`: shrinks the font until the text fits, down to `minimumScale`. */
@Composable
fun FitText(text: String, style: TextStyle, modifier: Modifier = Modifier, color: Color = Color.Unspecified, maxLines: Int = 1,
            minimumScale: Float = 1f, textAlign: TextAlign? = null) {
    if (minimumScale >= 1f) {
        Text(text, modifier, color = color, style = style, maxLines = maxLines, overflow = TextOverflow.Ellipsis, textAlign = textAlign)
        return
    }
    BoxWithConstraints(modifier) {
        val measurer = rememberTextMeasurer()
        val base = if (style.fontSize.isSpecified) style.fontSize.value else 14f
        val maxWidth = constraints.maxWidth
        val maxHeight = constraints.maxHeight
        val fitted = remember(text, style, maxWidth, maxHeight, maxLines, minimumScale) {
            fun fits(scale: Float): Boolean {
                if (maxWidth == Constraints.Infinity) return true
                val result: TextLayoutResult = measurer.measure(text, style.copy(fontSize = (base * scale).sp), overflow = TextOverflow.Clip,
                    maxLines = maxLines, constraints = Constraints(maxWidth = maxWidth))
                return !result.hasVisualOverflow && (maxHeight == Constraints.Infinity || result.size.height <= maxHeight)
            }
            if (fits(1f)) 1f else {
                var low = minimumScale; var high = 1f
                repeat(6) { val mid = (low + high) / 2; if (fits(mid)) low = mid else high = mid }
                low
            }
        }
        Text(text, color = color, style = style.copy(fontSize = (base * fitted).sp), maxLines = maxLines, overflow = TextOverflow.Ellipsis,
            textAlign = textAlign)
    }
}

/** A coloured `.shadow(color:radius:)` glow around a rounded rectangle (Android 9+ draws it; older phones skip it). */
fun Modifier.glow(color: Color, radius: Dp, cornerRadius: Dp = 8.dp, spread: Dp = 0.dp): Modifier =
    if (color.alpha <= 0f || radius <= 0.dp) this else drawBehind {
        drawIntoCanvas { canvas ->
            val paint = Paint()
            val frame = paint.asFrameworkPaint()
            frame.color = color.toArgb()
            frame.maskFilter = BlurMaskFilter(radius.toPx().coerceAtLeast(0.5f), BlurMaskFilter.Blur.NORMAL)
            val s = spread.toPx()
            canvas.drawRoundRect(-s, -s, size.width + s, size.height + s, cornerRadius.toPx(), cornerRadius.toPx(), paint)
        }
    }

/** A glowing outline: a blurred stroke under a crisp one (SwiftUI `.stroke(...).shadow(...)`). */
fun Modifier.glowingStroke(color: Color, width: Dp, glowColor: Color, glowRadius: Dp, cornerRadius: Dp, inset: Dp = 0.dp): Modifier = drawWithContent {
    drawContent()
    val offset = inset.toPx()
    val topLeft = Offset(offset, offset)
    val rectSize = Size(size.width - offset * 2, size.height - offset * 2)
    drawIntoCanvas { canvas ->
        if (glowRadius > 0.dp && glowColor.alpha > 0f) {
            val paint = Paint().apply { style = PaintingStyle.Stroke; strokeWidth = width.toPx() }
            val frame = paint.asFrameworkPaint()
            frame.color = glowColor.toArgb()
            frame.maskFilter = BlurMaskFilter(glowRadius.toPx(), BlurMaskFilter.Blur.NORMAL)
            canvas.drawRoundRect(topLeft.x, topLeft.y, topLeft.x + rectSize.width, topLeft.y + rectSize.height, cornerRadius.toPx(), cornerRadius.toPx(), paint)
        }
    }
    drawRoundRect(color, topLeft, rectSize, CornerRadius(cornerRadius.toPx()), style = androidx.compose.ui.graphics.drawscope.Stroke(width.toPx()))
}

/** SwiftUI `.saturation(s).brightness(b)` for arbitrary content, via an offscreen layer with a colour matrix. */
fun Modifier.colorAdjust(saturation: Float = 1f, brightness: Float = 0f): Modifier =
    if (saturation == 1f && brightness == 0f) this else drawWithContent {
        val matrix = ColorMatrix().apply { setToSaturation(saturation) }
        if (brightness != 0f) {
            val shift = brightness * 255f
            val values = matrix.values
            values[4] += shift; values[9] += shift; values[14] += shift
        }
        val paint = Paint().apply { colorFilter = ColorFilter.colorMatrix(matrix) }
        drawIntoCanvas { canvas ->
            canvas.saveLayer(androidx.compose.ui.geometry.Rect(0f, 0f, size.width, size.height), paint)
            drawContent()
            canvas.restore()
        }
    }

/** Points to sp for fonts that SwiftUI sizes in points. */
val Float.pt: TextUnit get() = this.sp
