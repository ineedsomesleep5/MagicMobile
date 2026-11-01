#include <metal_stdlib>
using namespace metal;

// The moving surfaces of an Arena world: each patch redraws a small piece of the painted plate, so lava, water and wind
// move the paint itself (docs/ARENA_WORLDS.md "Motion"). Kept in step with ArenaFlowUniforms in ArenaWorldLife.swift.

struct ArenaFlowUniforms {
    float time;
    float kind;
    float speed;
    float strength;
    float seed;
    float surge;
    float2 dir;
    float2 scale;   // Board units (100 points) across the plate.
    float2 pixel;   // One board point, in plate coordinates.
    float4 rect;    // The patch, in plate coordinates.
    float4 tint;
};

struct ArenaFlowVertex {
    float4 position [[position]];
    float2 uv;
    float2 local;
};

vertex ArenaFlowVertex arenaFlowVertex(uint id [[vertex_id]], constant ArenaFlowUniforms &u [[buffer(0)]]) {
    float2 t = float2(float(id & 1), float((id >> 1) & 1));
    ArenaFlowVertex out;
    out.position = float4(t.x * 2 - 1, 1 - t.y * 2, 0, 1);
    out.uv = u.rect.xy + u.rect.zw * t;
    out.local = t;
    return out;
}

static float arenaHash(float2 p) {
    p -= 289 * floor(p / 289);   // Past a few thousand, floats run out and the noise collapses: a long game gets there.
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float arenaNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 w = f * f * (3 - 2 * f);
    return mix(mix(arenaHash(i), arenaHash(i + float2(1, 0)), w.x),
               mix(arenaHash(i + float2(0, 1)), arenaHash(i + float2(1, 1)), w.x), w.y);
}

static float arenaFbm(float2 p) {
    return arenaNoise(p) * 0.55 + arenaNoise(p * 2.07 + 3.1) * 0.3 + arenaNoise(p * 4.3 + 7.7) * 0.15;
}

// Two phases of the same crawl, crossfaded, so paint keeps moving along its flow without ever stretching far.
static float3 arenaCrawl(float2 uv, float2 shift, float t, float period, texture2d<float> plate, sampler s, float2 pixel, float2 warp) {
    float a = fract(t / period), b = fract(t / period + 0.5);
    float3 first = plate.sample(s, uv - (shift * (a - 0.5) + warp) * pixel).rgb;
    float3 second = plate.sample(s, uv - (shift * (b - 0.5) + warp) * pixel).rgb;
    return mix(first, second, abs(2 * a - 1));
}

fragment float4 arenaFlowFragment(ArenaFlowVertex in [[stage_in]], constant ArenaFlowUniforms &u [[buffer(0)]],
                                  texture2d<float> plate [[texture(0)]], texture2d<float> mask [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float edge = smoothstep(0.0, 0.07, in.local.x) * smoothstep(0.0, 0.07, 1 - in.local.x)
               * smoothstep(0.0, 0.07, in.local.y) * smoothstep(0.0, 0.07, 1 - in.local.y);
    float m = mask.sample(s, in.uv).r * edge;
    if (m < 0.01) { return float4(0); }
    float2 p = in.uv * u.scale;
    float t = u.time * u.speed;
    int kind = int(u.kind);
    float3 colour = float3(0);

    if (kind == 0) {           // Lava: the paint creeps, a crust shifts over it, and seams glow through.
        float2 warp = float2(arenaFbm(p * 1.8 + u.seed), arenaFbm(p * 1.8 + u.seed + 9.3)) - 0.5;
        colour = arenaCrawl(in.uv, u.dir * 4.5, t, 8, plate, s, u.pixel, warp * 1.8);
        float heat = dot(colour, float3(0.62, 0.33, 0.05));
        float cell = arenaFbm(p * 3.2 - u.dir * t * 0.16 + warp * 1.4);
        float crust = smoothstep(0.52, 0.7, cell) * (1 - smoothstep(0.55, 0.95, heat));
        colour *= 1 - crust * 0.26;
        float seam = clamp(1 - abs(cell - 0.5) * 7, 0.0, 1.0);
        float pulse = 0.5 + 0.5 * sin(t * 0.8 + cell * 10 + u.seed);
        float3 hot = mix(float3(1, 0.3, 0.04), float3(1, 0.86, 0.4), smoothstep(0.3, 0.9, heat));
        colour += hot * seam * (0.1 + 0.26 * pulse + u.surge * 0.55) * smoothstep(0.12, 0.5, heat) * u.strength;
        colour += hot * u.surge * 0.18 * heat;
    } else if (kind == 1) {    // Water: the paint ripples, and small lights ride it.
        float2 warp = float2(arenaFbm(p * 3 + t * 0.14), arenaFbm(p * 3 - t * 0.12 + 5.1)) - 0.5;
        colour = arenaCrawl(in.uv, u.dir * 4, t, 6, plate, s, u.pixel, warp * 2.4);
        float glint = pow(arenaNoise(p * 16 + float2(t * 0.5, -t * 0.32) + warp * 3), 9) * (0.55 + u.surge);
        float ripple = arenaFbm(p * 6 - u.dir * t * 0.3);
        colour += u.tint.rgb * (glint * 1.8 + smoothstep(0.55, 0.8, ripple) * 0.1) * u.strength;
    } else if (kind == 2) {    // A fall: bright strands rush along the painted fall, with a little wander.
        float2 along = normalize(u.dir);
        float2 across = float2(along.y, -along.x);
        float2 flow = float2(dot(p, across), dot(p, along));
        float wander = arenaNoise(float2(flow.x * 7, flow.y * 1.2 - t * 1.1)) - 0.5;
        float2 stretched = float2(flow.x * 26 + wander * 2, flow.y * 1.7 - t * 3.2);
        float strand = arenaNoise(stretched) * 0.65 + arenaNoise(stretched * float2(2.3, 2.1) + 4.0) * 0.35;
        colour = plate.sample(s, in.uv + along * (strand - 0.5) * 5 * u.pixel).rgb;
        float bright = smoothstep(0.54, 0.8, strand);
        colour = mix(colour, min(colour * 1.5 + u.tint.rgb * 0.14, float3(1)), bright * u.strength);
        colour += u.tint.rgb * u.surge * 0.3 * bright;
    } else if (kind == 3) {    // Sway: tall things lean from their foot, in slow gusts.
        float height = pow(1 - in.local.y, 1.6);
        float gust = sin(t * 1.3 + u.seed) + 0.45 * sin(t * 2.9 + u.seed * 1.7) + u.surge * 2.2;
        colour = plate.sample(s, in.uv - float2(gust * height * 3.4 * u.strength, 0) * u.pixel).rgb;
    } else if (kind == 4) {    // Heat haze over lava, rising.
        float2 lift = float2(arenaNoise(float2(p.x * 8, p.y * 5 + t * 1.5)), arenaNoise(float2(p.x * 8 + 7, p.y * 5 + t * 1.2))) - 0.5;
        colour = plate.sample(s, in.uv + lift * 3.2 * (u.strength + u.surge) * u.pixel).rgb;
    } else if (kind == 5) {    // Mist or smoke: no paint of its own, a soft sheet drifting over the ground.
        float2 slow = p * 0.85 + u.dir * t * 0.09 + u.seed;
        float sheet = arenaFbm(slow + arenaFbm(slow * 1.3 - t * 0.03) * 1.3);
        float amount = smoothstep(0.34, 0.72, sheet) * u.strength * (1 + u.surge * 0.8);
        return float4(u.tint.rgb, 1) * amount * m;
    } else {                   // Wind in leaves: slow gusts cross the bed, and the leaves lean together.
        float travel = p.x * 0.9 + p.y * 0.5 - t * 0.55 + u.seed;
        float gust = smoothstep(0.42, 0.78, arenaNoise(float2(travel, u.seed)));
        float rustle = sin(p.x * 5 + p.y * 4 + t * 2.4) * 0.5 + (arenaNoise(p * 5 + t * 0.7) - 0.5);
        float2 shift = float2(0.55 + rustle * 0.5, 0.2 + rustle * 0.28) * (0.3 + gust * 1.5 + u.surge * 2.4);
        colour = plate.sample(s, in.uv + shift * u.strength * u.pixel).rgb;
    }
    return float4(colour * m, m);
}
