package io.magicmobile.android.studio

import androidx.compose.ui.geometry.Rect
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin

/**
 * The spell book's page curl (docs/deck-studio/PAGE_CURL.md): the maths and the AGSL shader. GrimoirePageCurl.swift
 * and PageCurl.metal are the same algorithm; keep them in step.
 *
 * A page is a flat sheet that bends over a cylinder whose axis sweeps across it. The shader inverts the bend for
 * every pixel: it finds the point of the sheet that lands there (the back of the flap, the front where it is
 * still flat or only just rising) and shades it, over the page revealed underneath and the shadow the flap throws
 * on it. Reference for the cylinder model: the folded-sheet-over-a-cylinder maths of harism/android_page_curl
 * (Apache 2.0) and the Shadertoy page-curl write-ups; nothing is copied, this is written for the app.
 */

/**
 * Where a turn happens: the rectangle that holds the paper that turns (a binder page, or a spread's two pages) in stage pixels,
 * the spine's x, the pages themselves (left to right) and their rounded corners, all in the rectangle's own coordinates. Nothing
 * is drawn outside the pages but the strip between them.
 */
internal class PageCurlLayout(val rect: Rect, val spine: Float, val spread: Boolean, val pages: List<Rect>, val cornerRadius: Float)

/** Where the fold is for a given progress: a cylinder of `radius` lying along the fold, `foot` away from the origin across `normal`. */
internal class PageCurlPose(val normalX: Float, val normalY: Float, val foot: Float, val radius: Float)

internal object PageCurlModel {
    /** The fold's lean at the start, in radians: the bottom corner is lifted first, as a hand would. */
    const val TILT = 0.20f
    /** The roll's radius as a share of the sheet's width, and its limits in dp. */
    const val RADIUS_SHARE = 0.12f
    const val RADIUS_MIN_DP = 26f
    const val RADIUS_MAX_DP = 60f
    /** Past this share of the way (or this speed along it, dp per second) a release finishes the turn. */
    const val COMPLETE_SHARE = 0.4f
    const val FLING_DP_PER_SECOND = 300f

    fun maxRadius(sheetWidth: Float, density: Float): Float = (sheetWidth * RADIUS_SHARE).coerceIn(RADIUS_MIN_DP * density, RADIUS_MAX_DP * density)

    /**
     * `progress` runs 0 (the sheet lies flat, nothing curled) to 1 (it has turned over the spine). Lengths are in the
     * unit of `width` and `height`, the sheet's rectangle with its spine at x = `spine` (a lone page: its left edge).
     * The fold sweeps from the far corner to the spine, levelling out as it goes so that the finished page lies
     * exactly over the one beside it; the roll is tight at both ends and fullest in the middle.
     */
    fun pose(progress: Float, width: Float, height: Float, spine: Float, tilt: Float, maxRadius: Float): PageCurlPose {
        val k = progress.coerceIn(0f, 1f)
        val lean = tilt * (1 - k)
        val far = width * cos(tilt) + height * sin(tilt) + 1f
        val foot = far + (spine - far) * k
        val radius = maxRadius * max(sin(Math.PI.toFloat() * k), 0f).pow(0.55f)
        return PageCurlPose(cos(lean), sin(lean), foot, max(radius, 0.75f))
    }

    fun progress(distance: Float, travel: Float): Float = if (travel > 1f) (distance / travel).coerceIn(0f, 1f) else 0f

    /** Whether letting go finishes the turn. `along` is the finger's speed in the direction of the turn, in px per second. */
    fun completes(progress: Float, along: Float, density: Float): Boolean {
        val fling = FLING_DP_PER_SECOND * density
        if (progress >= 0.6f) return true
        if (along < -fling) return false
        return progress >= COMPLETE_SHARE || (along > fling && progress > 0.12f)
    }
}

internal const val PAGE_CURL_AGSL = """
uniform shader tex0;
uniform shader tex1;
uniform float2 size;
uniform float2 nrm;
uniform float4 paper;
uniform float4 pose;      // foot, radius, spine x, mirror
uniform float4 slots;     // front, back (-1: plain paper), under the sheet, under the landing side
uniform float4 look;      // shadow strength, show-through, page corner radius
uniform float4 rectA;     // the sheet's page: min x, min y, max x, max y
uniform float4 rectB;     // the page it lands on (empty upright)
uniform float2 texOffset;

const float kPi = 3.14159265;

// Signed distance from q to a rounded rectangle (negative inside).
float roundedBox(float2 q, float4 rect, float radius) {
    float2 centre = (rect.xy + rect.zw) * 0.5;
    float2 extent = (rect.zw - rect.xy) * 0.5;
    float r = min(radius, min(extent.x, extent.y));
    float2 d = abs(q - centre) - (extent - r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

bool hasArea(float4 rect) { return rect.z > rect.x && rect.w > rect.y; }

// The back of the flap: on the cylinder's upper half (t in 0..r) or lying flat over the page (t < 0).
bool backHit(float2 p, float foot, float r, out float2 src, out float theta) {
    src = p; theta = kPi;
    float t = dot(p, nrm) - foot;
    if (t > r) { return false; }
    float s;
    if (t >= 0.0) { theta = kPi - asin(clamp(t / r, 0.0, 1.0)); s = r * theta; }
    else { s = kPi * r - t; }
    src = p + nrm * (s - t);
    return roundedBox(src, rectA, look.z) < 0.5;
}

// The front of the sheet while it rises over the cylinder's near side (t in 0..r).
bool frontHit(float2 p, float foot, float r, out float2 src, out float theta) {
    src = p; theta = 0.0;
    float t = dot(p, nrm) - foot;
    if (t <= 0.0 || t > r) { return false; }
    theta = asin(clamp(t / r, 0.0, 1.0));
    src = p + nrm * (r * theta - t);
    return roundedBox(src, rectA, look.z) < 0.5;
}

float flapMask(float2 p, float foot, float r) {
    if (dot(p, nrm) - foot > r) { return 0.0; }
    float2 s; float th;
    if (backHit(p, foot, r, s, th)) { return 1.0; }
    return frontHit(p, foot, r, s, th) ? 1.0 : 0.0;
}

// The shadow the flap throws on whatever lies under it: a soft copy of its outline pushed away from the light
// (upper left), plus a tighter halo that keeps its edges readable. The outline is a 0/1 mask, so it is sampled on a
// spiral of points turned a little differently at every pixel: the steps of a handful of binary samples turn into
// fine grain instead of visible bands.
float flapShadow(float2 p, float foot, float r, float jitter) {
    float2 shift = nrm * (0.5 * r + 3.0) + float2(0.0, 0.14 * r);
    float blur = 0.62 * r + 6.0;
    float thrown = 0.0;
    for (int i = 0; i < 12; i++) {
        float angle = float(i) * 2.399963 + jitter;
        float reach = sqrt((float(i) + 0.5) / 12.0) * blur;
        thrown += flapMask(p - shift + float2(cos(angle), sin(angle)) * reach, foot, r);
    }
    thrown /= 12.0;
    float halo = 0.0;
    float tight = 0.26 * r + 3.0;
    for (int i = 0; i < 6; i++) {
        float angle = float(i) * 2.399963 + jitter * 1.7;
        float reach = sqrt((float(i) + 0.5) / 6.0) * tight;
        halo += flapMask(p + float2(cos(angle), sin(angle)) * reach, foot, r);
    }
    halo /= 6.0;
    return clamp(0.85 * thrown + 0.30 * halo, 0.0, 1.0);
}

float3 curlSample(float slot, float2 local) {
    float2 q = local;
    if (pose.w > 0.5) { q.x = size.x - q.x; }
    q += texOffset;
    return slot < 0.5 ? float3(tex0.eval(q).rgb) : float3(tex1.eval(q).rgb);
}

// Lays a layer of paper (premultiplied) over what is already there.
float4 over(float3 colour, float alpha, float4 below) {
    return float4(colour * alpha, alpha) + below * (1.0 - alpha);
}

half4 main(float2 fragCoord) {
    float2 p = fragCoord;
    if (pose.w > 0.5) { p.x = size.x - p.x; }
    float foot = pose.x;
    float r = max(pose.y, 0.75);
    float t = dot(p, nrm) - foot;
    float corner = look.z;

    // Where there is paper: the two pages, and the strip between them that a flap crosses.
    float coverA = clamp(0.5 - roundedBox(p, rectA, corner), 0.0, 1.0);
    bool landing = hasArea(rectB);
    float coverB = landing ? clamp(0.5 - roundedBox(p, rectB, corner), 0.0, 1.0) : 0.0;
    float coverGap = 0.0;
    if (landing) {
        float4 strip = float4(rectB.z, max(rectA.y, rectB.y), rectA.x, min(rectA.w, rectB.w));
        if (hasArea(strip)) { coverGap = clamp(0.5 - roundedBox(p, strip, 0.0), 0.0, 1.0); }
    }
    float clip = max(max(coverA, coverB), coverGap);
    if (clip <= 0.0) { return half4(0.0); }

    // What the flap uncovers, with the flap's shadow on it.
    float jitter = 6.2831853 * fract(52.9829189 * fract(dot(fragCoord, float2(0.06711056, 0.00583715))));
    float shade = flapShadow(p, foot, r, jitter) * look.x;
    float baseAlpha = max(coverA, coverB);
    float3 base = curlSample(coverA >= coverB ? slots.z : slots.w, p) * (1.0 - shade);
    float4 result = float4(base * baseAlpha, baseAlpha);

    // The front of the sheet: flat where the fold has not reached, then rising over the cylinder.
    if (t <= 0.0) {
        if (coverA > 0.0) { result = over(curlSample(slots.x, p) * (1.0 - shade), coverA, result); }
    } else {
        float2 fs; float ft;
        if (frontHit(p, foot, r, fs, ft)) {
            float3 ink = curlSample(slots.x, fs) * (0.58 + 0.42 * cos(ft));
            float alpha = clamp(0.5 - roundedBox(fs, rectA, corner), 0.0, 1.0) * clip;
            result = over(ink, alpha, result);
        }
    }

    // The back of the flap, over everything: lit across the bend, darkest where it turns away.
    float2 bs; float bt;
    if (backHit(p, foot, r, bs, bt)) {
        float3 face = paper.rgb;
        if (slots.y >= 0.0) {
            // The other face of this sheet is the page that lands (a spread): the same spot, mirrored about the
            // spine. Where that page has no paper (it is shorter than this one) the back is plain parchment.
            float2 across = float2(2.0 * pose.z - bs.x, bs.y);
            if (roundedBox(across, rectB, corner) < 0.5) { face = curlSample(slots.y, across); }
        } else {
            float3 ghost = curlSample(slots.x, bs);
            face = mix(face, ghost * 0.9, look.y);
        }
        float2 n2 = float2(sin(bt), -cos(bt));
        float2 light = normalize(float2(0.5, 0.86));
        float diffuse = clamp(dot(n2, light), 0.0, 1.0);
        float lit = 0.42 + 0.58 * diffuse / light.y;
        float2 halfway = normalize(light + float2(0.0, 1.0));
        float sheen = pow(clamp(dot(n2, halfway), 0.0, 1.0), 14.0) * 0.16;
        face = face * (0.93 * lit) + float3(sheen);
        // The paper's thin edge, a little darker than its face.
        float inside = -roundedBox(bs, rectA, corner);
        face *= 0.80 + 0.20 * smoothstep(0.0, 3.0, inside);
        float silhouette = t >= 0.0 ? clamp(r - t + 0.5, 0.0, 1.0) : 1.0;
        float alpha = clamp(0.5 + inside, 0.0, 1.0) * silhouette * clip;
        result = over(face, alpha, result);
    }
    return half4(result);
}
"""
