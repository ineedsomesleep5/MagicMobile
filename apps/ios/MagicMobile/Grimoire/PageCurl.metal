#include <metal_stdlib>
using namespace metal;

// The spell book's page curl (docs/deck-studio/PAGE_CURL.md). A page is a flat sheet that bends over a
// cylinder whose axis sweeps across it. The fragment function inverts the bend for every pixel: it finds the
// point of the sheet that lands there (the back of the flap, the front where it is still flat or only just
// rising) and shades it, over the page revealed underneath and the shadow the flap throws on it. Android's
// PageCurlShader.kt is the same algorithm in AGSL; keep the two in step.
//
// All lengths are drawable pixels in the stage rectangle's own coordinates, x to the right and y down.
// With `mirror` set the x axis is flipped first, so a left page turning onto the right one is the same
// calculation as a right page turning onto the left. Only paper is drawn: the sheet (`rectA`) and the page it
// lands on (`rectB`, empty upright) are rounded rectangles, and everything outside them, apart from the
// strip between them, is left transparent so the binder shows through untouched.
//
// Reference for the cylinder model: the folded-sheet-over-a-cylinder maths of harism/android_page_curl
// (Apache 2.0) and the Shadertoy/Flutter page-curl write-ups; nothing is copied, this is written for the app.

struct PageCurlUniforms {
    float2 size;     // the stage rectangle
    float2 normal;   // unit vector across the fold, pointing from the flat part to the flap
    float4 paper;    // rgb: the back of the paper
    float4 pose;     // x foot (where the flat part ends, along the normal), y radius, z spine x, w mirror (0 or 1)
    int4 slots;      // texture of: the sheet's front, its back (-1: plain paper), what is under the sheet, what is under the landing side
    float4 look;     // x shadow strength, y show-through of the front's ink on a plain back, z page corner radius
    float4 rectA;    // the sheet's page: min x, min y, max x, max y
    float4 rectB;    // the page it lands on (empty upright)
};

struct CurlVertexOut {
    float4 position [[position]];
};

vertex CurlVertexOut pageCurlVertex(uint index [[vertex_id]]) {
    const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(-1, 1), float2(1, -1), float2(1, 1) };
    CurlVertexOut out;
    out.position = float4(corners[index], 0, 1);
    return out;
}

constant float kPi = 3.14159265;

// Signed distance from `q` to a rounded rectangle (negative inside).
static float roundedBox(float2 q, float4 rect, float radius) {
    float2 centre = (rect.xy + rect.zw) * 0.5;
    float2 extent = (rect.zw - rect.xy) * 0.5;
    float r = min(radius, min(extent.x, extent.y));
    float2 d = abs(q - centre) - (extent - r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

static bool hasArea(float4 rect) { return rect.z > rect.x && rect.w > rect.y; }

struct CurlHit {
    bool valid;
    float2 source;   // the point of the sheet that lands here
    float theta;     // how far round the cylinder it has gone, 0 flat ... pi lying back
};

// The back of the flap: on the cylinder's upper half (t in 0...r) or lying flat over the page (t < 0).
static CurlHit backHit(float2 p, float2 n, float foot, float r, constant PageCurlUniforms &u) {
    CurlHit hit;
    hit.valid = false; hit.source = p; hit.theta = kPi;
    float t = dot(p, n) - foot;
    if (t > r) { return hit; }
    float s;
    if (t >= 0.0) { hit.theta = kPi - asin(clamp(t / r, 0.0, 1.0)); s = r * hit.theta; }
    else { s = kPi * r - t; }
    hit.source = p + n * (s - t);
    hit.valid = roundedBox(hit.source, u.rectA, u.look.z) < 0.5;
    return hit;
}

// The front of the sheet while it rises over the cylinder's near side (t in 0...r).
static CurlHit frontHit(float2 p, float2 n, float foot, float r, constant PageCurlUniforms &u) {
    CurlHit hit;
    hit.valid = false; hit.source = p; hit.theta = 0.0;
    float t = dot(p, n) - foot;
    if (t <= 0.0 || t > r) { return hit; }
    hit.theta = asin(clamp(t / r, 0.0, 1.0));
    hit.source = p + n * (r * hit.theta - t);
    hit.valid = roundedBox(hit.source, u.rectA, u.look.z) < 0.5;
    return hit;
}

static float flapMask(float2 p, float2 n, float foot, float r, constant PageCurlUniforms &u) {
    if (dot(p, n) - foot > r) { return 0.0; }
    if (backHit(p, n, foot, r, u).valid) { return 1.0; }
    return frontHit(p, n, foot, r, u).valid ? 1.0 : 0.0;
}

// The shadow the flap throws on whatever lies under it: a soft copy of its outline pushed away from the
// light (which comes from the upper left), plus a tighter halo that keeps its edges readable. The outline is a
// 0/1 mask, so it is sampled on a spiral of points turned a little differently at every pixel: the steps of a
// handful of binary samples turn into fine grain instead of visible bands.
static float flapShadow(float2 p, float2 n, float foot, float r, float jitter, constant PageCurlUniforms &u) {
    float2 shift = n * (0.5 * r + 3.0) + float2(0.0, 0.14 * r);
    float blur = 0.62 * r + 6.0;
    float cast = 0.0;
    for (int i = 0; i < 12; i++) {
        float angle = float(i) * 2.399963 + jitter;
        float reach = sqrt((float(i) + 0.5) / 12.0) * blur;
        cast += flapMask(p - shift + float2(cos(angle), sin(angle)) * reach, n, foot, r, u);
    }
    cast /= 12.0;
    float halo = 0.0;
    float tight = 0.26 * r + 3.0;
    for (int i = 0; i < 6; i++) {
        float angle = float(i) * 2.399963 + jitter * 1.7;
        float reach = sqrt((float(i) + 0.5) / 6.0) * tight;
        halo += flapMask(p + float2(cos(angle), sin(angle)) * reach, n, foot, r, u);
    }
    halo /= 6.0;
    return clamp(0.85 * cast + 0.30 * halo, 0.0, 1.0);
}

static float3 curlSample(int slot, texture2d<float> a, texture2d<float> b, float2 local, constant PageCurlUniforms &u) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 q = local;
    if (u.pose.w > 0.5) { q.x = u.size.x - q.x; }
    float2 uv = q / u.size;
    return slot == 0 ? a.sample(linearClamp, uv).rgb : b.sample(linearClamp, uv).rgb;
}

// Lays a layer of paper (premultiplied) over what is already there.
static float4 over(float3 colour, float alpha, float4 below) {
    return float4(colour * alpha, alpha) + below * (1.0 - alpha);
}

fragment float4 pageCurlFragment(CurlVertexOut in [[stage_in]],
                                 texture2d<float> tex0 [[texture(0)]],
                                 texture2d<float> tex1 [[texture(1)]],
                                 constant PageCurlUniforms &u [[buffer(0)]]) {
    float2 p = in.position.xy;
    if (u.pose.w > 0.5) { p.x = u.size.x - p.x; }
    const float foot = u.pose.x;
    const float r = max(u.pose.y, 0.75);
    const float2 n = u.normal;
    const float t = dot(p, n) - foot;
    const float corner = u.look.z;

    // Where there is paper: the two pages, and the strip between them that a flap crosses.
    const float coverA = clamp(0.5 - roundedBox(p, u.rectA, corner), 0.0, 1.0);
    const bool landing = hasArea(u.rectB);
    const float coverB = landing ? clamp(0.5 - roundedBox(p, u.rectB, corner), 0.0, 1.0) : 0.0;
    float coverGap = 0.0;
    if (landing) {
        float4 strip = float4(u.rectB.z, max(u.rectA.y, u.rectB.y), u.rectA.x, min(u.rectA.w, u.rectB.w));
        if (hasArea(strip)) { coverGap = clamp(0.5 - roundedBox(p, strip, 0.0), 0.0, 1.0); }
    }
    const float clip = max(max(coverA, coverB), coverGap);
    if (clip <= 0.0) { return float4(0.0); }

    // What the flap uncovers, with the flap's shadow on it.
    const float jitter = 6.2831853 * fract(52.9829189 * fract(dot(in.position.xy, float2(0.06711056, 0.00583715))));
    const float shade = flapShadow(p, n, foot, r, jitter, u) * u.look.x;
    const float baseAlpha = max(coverA, coverB);
    float3 base = curlSample(coverA >= coverB ? u.slots.z : u.slots.w, tex0, tex1, p, u) * (1.0 - shade);
    float4 result = float4(base * baseAlpha, baseAlpha);

    // The front of the sheet: flat where the fold has not reached, then rising over the cylinder.
    if (t <= 0.0) {
        if (coverA > 0.0) {
            result = over(curlSample(u.slots.x, tex0, tex1, p, u) * (1.0 - shade), coverA, result);
        }
    } else {
        CurlHit front = frontHit(p, n, foot, r, u);
        if (front.valid) {
            float3 ink = curlSample(u.slots.x, tex0, tex1, front.source, u);
            ink *= 0.58 + 0.42 * cos(front.theta);
            float alpha = clamp(0.5 - roundedBox(front.source, u.rectA, corner), 0.0, 1.0) * clip;
            result = over(ink, alpha, result);
        }
    }

    // The back of the flap, over everything: lit across the bend, darkest where it turns away.
    CurlHit back = backHit(p, n, foot, r, u);
    if (back.valid) {
        float3 paper = u.paper.rgb;
        if (u.slots.y >= 0) {
            // The other face of this sheet is the page that lands (a spread): the same spot, mirrored about the
            // spine. Where that page has no paper (it is shorter than this one) the back is plain parchment.
            float2 across = float2(2.0 * u.pose.z - back.source.x, back.source.y);
            if (roundedBox(across, u.rectB, corner) < 0.5) { paper = curlSample(u.slots.y, tex0, tex1, across, u); }
        } else {
            float3 ghost = curlSample(u.slots.x, tex0, tex1, back.source, u);
            paper = mix(paper, ghost * 0.9, u.look.y);
        }
        float2 normal2 = float2(sin(back.theta), -cos(back.theta));
        float2 light = normalize(float2(0.5, 0.86));
        float diffuse = clamp(dot(normal2, light), 0.0, 1.0);
        float lit = 0.42 + 0.58 * diffuse / light.y;
        float2 halfway = normalize(light + float2(0.0, 1.0));
        float sheen = pow(clamp(dot(normal2, halfway), 0.0, 1.0), 14.0) * 0.16;
        float3 face = paper * (0.93 * lit) + float3(sheen);
        // The paper's thin edge, a little darker than its face.
        float inside = -roundedBox(back.source, u.rectA, corner);
        face *= 0.80 + 0.20 * smoothstep(0.0, 3.0, inside);
        float silhouette = t >= 0.0 ? clamp(r - t + 0.5, 0.0, 1.0) : 1.0;
        float alpha = clamp(0.5 + inside, 0.0, 1.0) * silhouette * clip;
        result = over(face, alpha, result);
    }
    return result;
}
