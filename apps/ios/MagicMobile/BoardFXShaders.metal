#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Board FX card shaders (SwiftUI colorEffect). Written for MagicMobile; the
// value-noise approach follows the common public-domain hash/fbm pattern.

static float mmHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float mmNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = mmHash(i);
    float b = mmHash(i + float2(1.0, 0.0));
    float c = mmHash(i + float2(0.0, 1.0));
    float d = mmHash(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float mmFbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * mmNoise(p);
        p *= 2.03;
        amplitude *= 0.5;
    }
    return value;
}

/// Burns a card away: pixels below a rising noise threshold vanish and a glowing
/// edge in `edgeColor` rides the boundary. progress 0 = intact, 1 = gone.
[[ stitchable ]] half4 mmDissolve(float2 position, half4 color, float2 size, float progress, half4 edgeColor) {
    if (color.a == 0.0h) { return color; }
    float2 uv = position / max(size, float2(1.0));
    // Bias toward burning from the bottom edge first.
    float n = mmFbm(uv * 5.0) * 0.8 + (1.0 - uv.y) * 0.2;
    float threshold = progress * 1.15 - 0.08;
    if (n < threshold) { return half4(0.0h); }
    float edge = 1.0 - smoothstep(threshold, threshold + 0.07, n);
    half4 glow = half4(edgeColor.rgb * color.a, color.a);
    return mix(color, glow, half(edge));
}

/// Holographic foil: a soft rainbow wash plus a bright diagonal glint. `phase`
/// moves the glint across the card (any real value; it wraps).
[[ stitchable ]] half4 mmFoil(float2 position, half4 color, float2 size, float phase, float intensity) {
    if (color.a == 0.0h) { return color; }
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
