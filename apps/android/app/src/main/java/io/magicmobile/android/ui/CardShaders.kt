package io.magicmobile.android.ui

import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import kotlin.math.max

/**
 * Ports of BoardFXShaders.metal (mmDissolve, mmFoil). Android 13+ runs the same shaders as
 * AGSL; older phones get a close approximation drawn with gradients and alpha.
 */
object CardShaders {
    private const val common = """
        float mmHash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
        float mmNoise(float2 p) {
            float2 i = floor(p); float2 f = fract(p);
            float a = mmHash(i); float b = mmHash(i + float2(1.0, 0.0));
            float c = mmHash(i + float2(0.0, 1.0)); float d = mmHash(i + float2(1.0, 1.0));
            float2 u = f * f * (3.0 - 2.0 * f);
            return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
        }
        float mmFbm(float2 p) {
            float value = 0.0; float amplitude = 0.5;
            for (int i = 0; i < 4; i++) { value += amplitude * mmNoise(p); p *= 2.03; amplitude *= 0.5; }
            return value;
        }
    """

    const val dissolveSource = """
        uniform shader content;
        uniform float2 size;
        uniform float progress;
        layout(color) uniform half4 edgeColor;
        $common
        half4 main(float2 position) {
            half4 color = content.eval(position);
            if (color.a == 0.0) { return color; }
            float2 uv = position / max(size, float2(1.0));
            float n = mmFbm(uv * 5.0) * 0.8 + (1.0 - uv.y) * 0.2;
            float threshold = progress * 1.15 - 0.08;
            if (n < threshold) { return half4(0.0); }
            float edge = 1.0 - smoothstep(threshold, threshold + 0.07, n);
            half4 glow = half4(edgeColor.rgb * color.a, color.a);
            return mix(color, glow, half(edge));
        }
    """

    const val foilSource = """
        uniform shader content;
        uniform float2 size;
        uniform float phase;
        uniform float intensity;
        half4 main(float2 position) {
            half4 color = content.eval(position);
            if (color.a == 0.0) { return color; }
            float2 uv = position / max(size, float2(1.0));
            float diagonal = uv.x * 0.8 + uv.y * 0.6;
            float t = fract(diagonal * 1.3 - phase * 0.35);
            float3 rainbow = 0.5 + 0.5 * cos(6.28318 * (t + float3(0.0, 0.33, 0.67)));
            float glintPosition = fract(phase) * 1.6 - 0.3;
            float glint = pow(max(0.0, 1.0 - abs(diagonal - glintPosition) * 5.0), 3.0);
            float3 add = (rainbow * 0.16 + glint * 0.5) * intensity;
            half3 rgb = min(color.rgb + half3(add) * color.a, half3(color.a));
            return half4(rgb, color.a);
        }
    """

    val supported: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    fun dissolve(width: Float, height: Float, progress: Float, edge: Color): RenderEffect {
        val shader = RuntimeShader(dissolveSource)
        shader.setFloatUniform("size", width, height)
        shader.setFloatUniform("progress", progress)
        shader.setColorUniform("edgeColor", edge.toArgb())
        return RenderEffect.createRuntimeShaderEffect(shader, "content")
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    fun foil(width: Float, height: Float, phase: Float, intensity: Float): RenderEffect {
        val shader = RuntimeShader(foilSource)
        shader.setFloatUniform("size", width, height)
        shader.setFloatUniform("phase", phase)
        shader.setFloatUniform("intensity", intensity)
        return RenderEffect.createRuntimeShaderEffect(shader, "content")
    }
}

/** Burns content away from the bottom edge (mmDissolve); progress 0 = intact, 1 = gone. */
fun Modifier.dissolveEffect(progress: Float, edge: Color): Modifier =
    if (CardShaders.supported) this.graphicsLayer {
        renderEffect = CardShaders.dissolve(size.width, size.height, progress, edge).asComposeRenderEffect()
    } else this.graphicsLayer { alpha = (1f - progress).coerceIn(0f, 1f) }.drawWithContent {
        drawContent()
        drawRect(Brush.verticalGradient(listOf(Color.Transparent, edge.copy(alpha = 0.6f * (1 - progress)))), blendMode = BlendMode.Plus)
    }

/** Holographic foil (mmFoil): a rainbow wash and a moving diagonal glint. */
fun Modifier.foilEffect(phase: Float, intensity: Float): Modifier =
    if (CardShaders.supported) this.graphicsLayer {
        renderEffect = CardShaders.foil(size.width, size.height, phase, intensity).asComposeRenderEffect()
    } else this.drawWithContent {
        drawContent()
        val shift = (phase * 0.35f) % 1f
        val rainbow = listOf(rgb(1.0, 0.5, 0.5), rgb(1.0, 1.0, 0.5), rgb(0.5, 1.0, 0.6), rgb(0.5, 0.8, 1.0), rgb(0.85, 0.55, 1.0), rgb(1.0, 0.5, 0.5))
            .map { it.copy(alpha = 0.16f * intensity) }
        val span = size.width + size.height
        val offset = Offset(-shift * span, -shift * span * 0.75f)
        drawRect(Brush.linearGradient(rainbow + rainbow, start = offset, end = Offset(offset.x + span * 1.6f, offset.y + span * 1.2f)), blendMode = BlendMode.Plus)
        val glint = (phase % 1f) * 1.6f - 0.3f
        val center = Offset(size.width * glint, size.height * glint * 0.75f)
        drawRect(Brush.linearGradient(listOf(Color.Transparent, Color.White.copy(alpha = max(0f, 0.5f * intensity)), Color.Transparent),
            start = Offset(center.x - size.width * 0.12f, center.y - size.height * 0.09f),
            end = Offset(center.x + size.width * 0.12f, center.y + size.height * 0.09f)), blendMode = BlendMode.Plus)
    }
