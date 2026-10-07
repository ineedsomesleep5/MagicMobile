"""The starting-roll D20 and the tavern table it is thrown on, built headlessly in Blender.

    blender -b --python-exit-code 1 -P scripts/brand/d20.py -- --mode all --out-dir build_output/d20

Modes (--mode; `all` runs model, throws, table and a die preview):
  model     the die: a beveled icosahedron with engraved, gold-filled numerals on oxblood resin.
            Writes d20.glb (the one model both apps load) and d20.json (face number, normal and
            vertex directions, so the apps can land the die on any face).
  throws    a bank of recorded throws (a small rigid-body integrator run in Python): each one tumbles
            along the table, bounces off the far rail and settles with some face up. Writes
            d20-throws.json. The apps play one and re-label the die with an icosahedral symmetry
            (docs/STARTING_ROLL.md) so the same path ends on whichever face the game decided.
  table     the tavern table top-down for portrait and landscape: walnut boards, the board's own
            leather mat with its compass, a raised walnut and brass rail. Rendered with Cycles and
            wrapped in d20-table-<portrait|landscape>.glb (an unlit textured quad, so the lighting
            is the picture's) and d20-shadow.glb (a soft blob the die casts).
  preview   imports the finished GLBs back into Blender and renders contact sheets, so the model,
            numbering and table can be checked without the apps.

Conventions: Blender is Z-up; everything written for the apps is Y-up (x, z, -y), the glTF and
SceneKit convention. In the throws file the die starts near the viewer (+z) and the rail is the plane
z = 0, with the table at y = 0. The die has circumradius 1.

Nothing here is downloaded. The leather is cropped from the board's tavern plates and the walnut is
the board's own battlefield-wood.jpg; the numerals use the system serif (NewYork).
"""

import argparse
import json
import math
import os
import random
import struct
import subprocess
import sys
import zlib

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CATALOG = os.path.join(REPO, "apps/ios/MagicMobile/Assets.xcassets")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--mode", default="all", choices=["all", "model", "throws", "table", "preview"])
    p.add_argument("--out-dir", required=True)
    p.add_argument("--tile", type=int, default=320, help="texture pixels per numeral tile")
    p.add_argument("--candidates", type=int, default=900, help="throws simulated before the best are kept")
    p.add_argument("--keep", type=int, default=12, help="throws kept in the bank")
    p.add_argument("--seed", type=int, default=20)
    p.add_argument("--samples", type=int, default=96)
    p.add_argument("--table-scale", type=float, default=1.0, help="table pixels per scene unit are 100 x this")
    p.add_argument("--font", default="/System/Library/Fonts/NewYork.ttf")
    return p.parse_args(argv)


ARGS = parse_args()
os.makedirs(ARGS.out_dir, exist_ok=True)


def out(name):
    return os.path.join(ARGS.out_dir, name)


# --- the icosahedron ----------------------------------------------------------------------------

PHI = (1 + 5 ** 0.5) / 2
RAW = [(-1, PHI, 0), (1, PHI, 0), (-1, -PHI, 0), (1, -PHI, 0), (0, -1, PHI), (0, 1, PHI),
       (0, -1, -PHI), (0, 1, -PHI), (PHI, 0, -1), (PHI, 0, 1), (-PHI, 0, -1), (-PHI, 0, 1)]
VERTS = [np.array(v, float) / np.linalg.norm(v) for v in RAW]           # circumradius 1
FACES = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
         [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
         [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
         [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
INRADIUS = 0.7946544722917661                                          # circumradius 1
BEVEL = 0.055
TILE_COLS, TILE_ROWS = 5, 4
TILE_SPAN = 1.3                                                         # world units across one tile


def face_geometry():
    """Per face: outward normal, centre, and the three in-plane directions to its corners (CCW from
    outside, starting at the corner the numeral points to)."""
    faces = []
    for tri in FACES:
        a, b, c = (VERTS[i] for i in tri)
        n = np.cross(b - a, c - a)
        n /= np.linalg.norm(n)
        if np.dot(n, a + b + c) < 0:
            tri = [tri[0], tri[2], tri[1]]
            n = -n
        a, b, c = (VERTS[i] for i in tri)
        centre = (a + b + c) / 3
        dirs = []
        for v in (a, b, c):
            d = v - centre
            d -= n * np.dot(d, n)
            dirs.append(d / np.linalg.norm(d))
        faces.append({"tri": tri, "n": n, "centre": centre, "dirs": dirs})
    return faces


FACE = face_geometry()


def adjacency():
    adj = [set() for _ in FACE]
    for i, f in enumerate(FACE):
        for j, g in enumerate(FACE):
            if i != j and len(set(f["tri"]) & set(g["tri"])) == 2:
                adj[i].add(j)
    return adj


def number_faces(seed=7):
    """Standard d20: opposite faces sum to 21. Among those, the numbering that keeps neighbouring
    numbers furthest apart (no 1 beside 2) and the sums around each corner most even."""
    adj = adjacency()
    n = len(FACE)
    opposite = [min(range(n), key=lambda j: float(np.dot(FACE[i]["n"], FACE[j]["n"]))) for i in range(n)]
    pairs = sorted({tuple(sorted((i, opposite[i]))) for i in range(n)})
    corner_faces = [[i for i, f in enumerate(FACE) if v in f["tri"]] for v in range(12)]
    rng = random.Random(seed)
    best, best_score = None, None
    for _ in range(40000):
        ks = list(range(1, 11))
        rng.shuffle(ks)
        number = [0] * n
        for (a, b), k in zip(pairs, ks):
            number[a], number[b] = (k, 21 - k) if rng.random() < 0.5 else (21 - k, k)
        gaps = [abs(number[a] - number[b]) for a in range(n) for b in adj[a] if a < b]
        sums = [sum(number[i] for i in fs) for fs in corner_faces]
        score = (min(gaps), -float(np.var(sums)))
        if best_score is None or score > best_score:
            best, best_score = number, score
    assert all(best[i] + best[opposite[i]] == 21 for i in range(n))
    print(f"[d20] numbering: min neighbour gap {best_score[0]}, corner-sum variance {-best_score[1]:.2f}")
    return best


# --- textures -----------------------------------------------------------------------------------

def write_png(path, array):
    """Minimal PNG writer (8-bit gray, RGB or RGBA) so no imaging library is needed."""
    h, w = array.shape[:2]
    channels = 1 if array.ndim == 2 else array.shape[2]
    colour = {1: 0, 3: 2, 4: 6}[channels]
    raw = np.ascontiguousarray(array, dtype=np.uint8).reshape(h, w * channels)
    body = b"".join(b"\x00" + raw[y].tobytes() for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, colour, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(body, 9)) + chunk(b"IEND", b""))


def to_jpeg(png, jpg, quality=88, extra=()):
    subprocess.run(["magick", png, "-strip", "-interlace", "none", "-quality", str(quality), *extra, jpg], check=True)


def glyph_mask(text, size, font, height_frac):
    """White-on-black numeral, centred, as a float array (rows top to bottom)."""
    png = out("_glyph.png")
    target = int(size * height_frac)
    subprocess.run(["magick", "-size", f"{size}x{size}", "xc:black", "-font", font, "-pointsize", str(target * 1.45),
                    "-fill", "white", "-stroke", "white", "-strokewidth", str(max(3, size // 55)), "-gravity", "center",
                    "-annotate", "+0+0", text, "-depth", "8", png], check=True)
    img = bpy.data.images.load(png)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)[:, :, 0]
    bpy.data.images.remove(img)
    px = px[::-1]                                      # Blender stores rows bottom to top
    ys, xs = np.nonzero(px > 0.5)
    # Centre the ink, not the font's box, so every numeral sits in the middle of its face.
    shifted = np.roll(px, (size // 2 - (ys.min() + ys.max()) // 2, size // 2 - (xs.min() + xs.max()) // 2), axis=(0, 1))
    return shifted


def blur(a, sigma):
    if sigma <= 0:
        return a
    radius = max(1, int(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-radius, radius + 1) / sigma) ** 2)
    k /= k.sum()
    a = np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 0, a)
    return np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 1, a)


def value_noise(h, w, cells, rng):
    grid = rng.random((cells + 2, cells + 2)).astype(np.float32)
    ys = np.linspace(0, cells, h, dtype=np.float32)
    xs = np.linspace(0, cells, w, dtype=np.float32)
    y0, x0 = ys.astype(int), xs.astype(int)
    fy, fx = (ys - y0)[:, None], (xs - x0)[None, :]
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    g = grid
    top = g[y0][:, x0] * (1 - fx) + g[y0][:, x0 + 1] * fx
    bot = g[y0 + 1][:, x0] * (1 - fx) + g[y0 + 1][:, x0 + 1] * fx
    return top * (1 - fy) + bot * fy


def build_textures(numbers, tile):
    """Atlas of 5 x 4 tiles, one per face: base colour, normal map and metallic-roughness."""
    rng = np.random.default_rng(ARGS.seed)
    W, H = tile * TILE_COLS, tile * TILE_ROWS
    base = np.zeros((H, W, 3), np.float32)
    normal = np.zeros((H, W, 3), np.float32)
    orm = np.zeros((H, W, 3), np.float32)
    units_per_px = TILE_SPAN / tile
    resin_a = np.array([0.30, 0.025, 0.035], np.float32)       # deep oxblood
    resin_b = np.array([0.62, 0.075, 0.045], np.float32)       # ember red
    gold = np.array([1.0, 0.74, 0.30], np.float32)
    gold_dark = np.array([0.55, 0.33, 0.09], np.float32)
    yy, xx = np.mgrid[0:tile, 0:tile].astype(np.float32)
    for f in range(20):
        col, row = f % TILE_COLS, f // TILE_COLS
        text = str(numbers[f])
        # Two-digit numerals shrink a touch so they clear the face's corners.
        mask = glyph_mask(text, tile, ARGS.font, 0.17 if len(text) == 2 else 0.19)
        if text in ("6", "9"):
            # The underline that tells 6 from 9, as on a real die.
            ys, xs = np.nonzero(mask > 0.5)
            y1 = ys.max() + int(0.035 / units_per_px)
            mask[y1:y1 + max(2, int(0.022 / units_per_px)), xs.mean().astype(int) - int(0.07 / units_per_px):
                 xs.mean().astype(int) + int(0.07 / units_per_px)] = 1.0
        soft = blur(mask, 0.7)
        height = blur(mask, 1.4) * 1.0                          # engraved depth profile (1 = deepest)
        # Resin: swirled red with slow marbling, a darker pool toward the middle and a few gold flecks.
        marble = 0.55 * value_noise(tile, tile, 3, rng) + 0.3 * value_noise(tile, tile, 7, rng) + 0.15 * value_noise(tile, tile, 19, rng)
        swirl = np.clip((marble - 0.25) * 1.9, 0, 1)[:, :, None]
        resin = resin_a * (1 - swirl) + resin_b * swirl
        radial = np.clip(np.sqrt((xx - tile / 2) ** 2 + (yy - tile / 2) ** 2) / (tile * 0.42), 0, 1)[:, :, None]
        resin = resin * (0.82 + 0.22 * radial)
        flecks = (rng.random((tile, tile)) > 0.9996).astype(np.float32)
        flecks = blur(flecks, 0.8) * 9
        resin = resin + np.clip(flecks, 0, 1)[:, :, None] * np.array([0.55, 0.38, 0.12], np.float32)
        # Gold fill, a little darker in the deepest part of the cut.
        shade = np.clip(1 - 0.5 * np.clip(height * 1.4 - 0.4, 0, 1), 0, 1)[:, :, None]
        fill = gold * shade + gold_dark * (1 - shade)
        colour = resin * (1 - soft[:, :, None]) + fill * soft[:, :, None]
        # Normal map from the engraved height (tangent space, +Y up, image rows run downward).
        gy, gx = np.gradient(height)
        strength = 5.5
        nx, ny = -gx * strength, gy * strength
        nz = np.ones_like(nx)
        length = np.sqrt(nx * nx + ny * ny + nz * nz)
        n = np.stack([nx / length, ny / length, nz / length], axis=2)
        rough = 0.16 + 0.1 * marble
        rough = rough * (1 - soft) + 0.30 * soft
        metal = 0.95 * soft
        sl = (slice(row * tile, (row + 1) * tile), slice(col * tile, (col + 1) * tile))
        base[sl] = colour
        normal[sl] = n * 0.5 + 0.5
        orm[sl[0], sl[1], 0] = 1.0
        orm[sl[0], sl[1], 1] = rough
        orm[sl[0], sl[1], 2] = metal
    # Colour is authored in sRGB-ish values already; the maps are stored as they are.
    def u8(a):
        return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    return u8(base), u8(normal), u8(orm)


# --- the mesh -----------------------------------------------------------------------------------

def build_die_mesh():
    """The beveled die as Blender builds it. Returns arrays per face-corner after splitting."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = bpy.data.meshes.new("d20")
    bm = bmesh.new()
    verts = [bm.verts.new(tuple(v)) for v in VERTS]
    for f in FACE:
        bm.faces.new([verts[i] for i in f["tri"]])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("d20", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = BEVEL
    mod.segments = 4
    mod.profile = 0.5
    mod.limit_method = "NONE"
    mod.harden_normals = True
    bpy.ops.object.modifier_apply(modifier="bevel")
    return obj


def corner_arrays(obj, numbers, tile):
    """Per triangle corner: position, normal, uv, tangent (all Blender Z-up for now)."""
    mesh = obj.data
    mesh.calc_loop_triangles()
    normals = np.array([tuple(n.vector) for n in mesh.corner_normals], float)
    positions = np.array([tuple(v.co) for v in mesh.vertices], float)
    face_normals = np.array([f["n"] for f in FACE])
    # Which face's tile each polygon samples: the face its centre looks most nearly toward.
    group = []
    for poly in mesh.polygons:
        pn = np.array(poly.normal)
        group.append(int(np.argmax(face_normals @ pn)))
    out_pos, out_nrm, out_uv, out_tan = [], [], [], []
    for tri in mesh.loop_triangles:
        g = group[tri.polygon_index]
        f = FACE[g]
        up = f["dirs"][0]
        right = np.cross(up, f["n"])
        col, row = g % TILE_COLS, g // TILE_COLS
        for loop in tri.loops:
            p = positions[mesh.loops[loop].vertex_index]
            a = float(np.dot(p - f["centre"], right))
            b = float(np.dot(p - f["centre"], up))
            u = (col + 0.5 + a / TILE_SPAN) / TILE_COLS
            v = (row + 0.5 - b / TILE_SPAN) / TILE_ROWS
            n = normals[loop]
            t = right - n * np.dot(right, n)
            t /= np.linalg.norm(t)
            out_pos.append(p)
            out_nrm.append(n)
            out_uv.append((u, v))
            out_tan.append((*t, 1.0))
    return (np.array(out_pos), np.array(out_nrm), np.array(out_uv), np.array(out_tan))


# --- glTF writer --------------------------------------------------------------------------------

class Glb:
    def __init__(self):
        self.bin = bytearray()
        self.views, self.accessors, self.images, self.textures, self.materials, self.meshes, self.nodes = [], [], [], [], [], [], []
        self.samplers = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}]

    def _align(self):
        while len(self.bin) % 4:
            self.bin.append(0)

    def view(self, data, target=None):
        self._align()
        entry = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target:
            entry["target"] = target
        self.bin += data
        self.views.append(entry)
        return len(self.views) - 1

    def accessor(self, array, kind, component, target=None, minmax=False):
        entry = {"bufferView": self.view(np.ascontiguousarray(array).tobytes(), target), "componentType": component,
                 "count": int(len(array)), "type": kind}
        if minmax:
            entry["min"] = [float(x) for x in array.min(axis=0)]
            entry["max"] = [float(x) for x in array.max(axis=0)]
        self.accessors.append(entry)
        return len(self.accessors) - 1

    def image(self, path, mime):
        with open(path, "rb") as f:
            data = f.read()
        self.images.append({"bufferView": self.view(data), "mimeType": mime})
        self.textures.append({"sampler": 0, "source": len(self.images) - 1})
        return len(self.textures) - 1

    def mesh(self, name, pos, nrm, uv, tan, indices, material):
        attributes = {"POSITION": self.accessor(pos.astype(np.float32), "VEC3", 5126, 34962, True),
                      "NORMAL": self.accessor(nrm.astype(np.float32), "VEC3", 5126, 34962),
                      "TEXCOORD_0": self.accessor(uv.astype(np.float32), "VEC2", 5126, 34962)}
        if tan is not None:
            attributes["TANGENT"] = self.accessor(tan.astype(np.float32), "VEC4", 5126, 34962)
        idx = self.accessor(indices.astype(np.uint32).reshape(-1), "SCALAR", 5125, 34963)
        self.meshes.append({"name": name, "primitives": [{"attributes": attributes, "indices": idx, "material": material}]})
        self.nodes.append({"name": name, "mesh": len(self.meshes) - 1})

    def write(self, path, extensions=()):
        doc = {"asset": {"version": "2.0", "generator": "MagicMobile scripts/brand/d20.py"},
               "scene": 0, "scenes": [{"nodes": list(range(len(self.nodes)))}], "nodes": self.nodes, "meshes": self.meshes,
               "materials": self.materials, "textures": self.textures, "images": self.images, "samplers": self.samplers,
               "accessors": self.accessors, "bufferViews": self.views, "buffers": [{"byteLength": len(self.bin)}]}
        if extensions:
            doc["extensionsUsed"] = list(extensions)
        js = json.dumps(doc, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        self._align()
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942) + bytes(self.bin))
        print(f"[d20] wrote {os.path.relpath(path)} ({os.path.getsize(path) / 1024:.0f} KB)")


def zup_to_yup(a):
    a = np.asarray(a, float)
    return np.stack([a[..., 0], a[..., 2], -a[..., 1]], axis=-1)


def dedupe(pos, nrm, uv, tan):
    """Merge corners that share position, normal and uv into a vertex buffer plus indices."""
    keys, remap, rows = {}, [], []
    for i in range(len(pos)):
        key = (tuple(np.round(pos[i], 5)), tuple(np.round(nrm[i], 3)), tuple(np.round(uv[i], 5)))
        if key not in keys:
            keys[key] = len(rows)
            rows.append(i)
        remap.append(keys[key])
    rows = np.array(rows)
    return pos[rows], nrm[rows], uv[rows], tan[rows], np.array(remap).reshape(-1, 3)


def build_model():
    numbers = number_faces()
    obj = build_die_mesh()
    atlas = build_textures(numbers, ARGS.tile)
    for name, arr in zip(("base", "normal", "orm"), atlas):
        write_png(out(f"_{name}.png"), arr)
    to_jpeg(out("_base.png"), out("_base.jpg"), 90)
    to_jpeg(out("_orm.png"), out("_orm.jpg"), 90)
    pos, nrm, uv, tan = corner_arrays(obj, numbers, ARGS.tile)
    pos, nrm, tan = zup_to_yup(pos), zup_to_yup(nrm), zup_to_yup(tan[:, :3])
    tan = np.concatenate([tan, np.ones((len(tan), 1))], axis=1)
    pos, nrm, uv, tan, idx = dedupe(pos, nrm, uv, tan)
    print(f"[d20] mesh: {len(pos)} vertices, {len(idx)} triangles")
    glb = Glb()
    base_t = glb.image(out("_base.jpg"), "image/jpeg")
    normal_t = glb.image(out("_normal.png"), "image/png")
    orm_t = glb.image(out("_orm.jpg"), "image/jpeg")
    glb.materials.append({"name": "resin", "pbrMetallicRoughness": {
        "baseColorTexture": {"index": base_t}, "metallicRoughnessTexture": {"index": orm_t},
        "metallicFactor": 1.0, "roughnessFactor": 1.0}, "normalTexture": {"index": normal_t, "scale": 1.0}})
    glb.mesh("d20", pos, nrm, uv, tan, idx, 0)
    glb.write(out("d20.glb"))

    faces = []
    for i, f in enumerate(FACE):
        n = zup_to_yup(f["n"])
        faces.append({"index": i, "number": numbers[i], "normal": [round(float(x), 6) for x in n],
                      "cornerDirections": [[round(float(x), 6) for x in zup_to_yup(d)] for d in f["dirs"]]})
    info = {"circumradius": 1.0, "inradius": INRADIUS, "faces": faces,
            "vertices": [[round(float(x), 6) for x in zup_to_yup(v)] for v in VERTS],
            "up": "y", "note": "Local, Y-up. cornerDirections[0] is where the numeral points."}
    with open(out("d20.json"), "w") as f:
        json.dump(info, f, separators=(",", ":"))
    return numbers


# --- recorded throws ----------------------------------------------------------------------------

TIME_SCALE = 1.7          # playback slows the simulated tumble by this much (a stylised, weighty table)
LANE_DRIFT = 0.38          # how far (die radii) a throw may stray from its lane
DURATION = (1.7, 3.2)     # seconds a kept throw may last, from launch to rest
GRAVITY = 62.0            # die radii per second squared: a stylised, slightly floaty table
DT = 1.0 / 120.0
TABLE = {"e": 0.46, "mu": 0.55}
RAIL = {"e": 0.58, "mu": 0.25}
INERTIA = 0.4 * 0.76 ** 2  # unit mass; an icosahedron's inertia tensor is isotropic
VERT_ARRAY = np.array(VERTS)


def quat_to_matrix(q):
    w, x, y, z = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def quat_integrate(q, w, dt):
    """Plain-float quaternion step (w is the world angular velocity); returns a new 4-list."""
    wx, wy, wz = w
    speed = math.sqrt(wx * wx + wy * wy + wz * wz)
    angle = speed * dt
    if angle < 1e-9:
        return q
    s = math.sin(angle / 2) / speed
    aw, ax, ay, az = math.cos(angle / 2), wx * s, wy * s, wz * s
    bw, bx, by, bz = q
    nw = aw * bw - ax * bx - ay * by - az * bz
    nx = aw * bx + ax * bw + ay * bz - az * by
    ny = aw * by - ax * bz + ay * bw + az * bx
    nz = aw * bz + ax * by - ay * bx + az * bw
    n = math.sqrt(nw * nw + nx * nx + ny * ny + nz * nz)
    return [nw / n, nx / n, ny / n, nz / n]


def q_matrix(q):
    w, x, y, z = q
    return (1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
            2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
            2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y))


VERT_LIST = [tuple(float(c) for c in v) for v in VERTS]


def cross3(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def contact(v, w, rel, normal, material, hard):
    """One corner touching a wall: normal and friction impulses on the body. Returns (v, w, normal impulse)."""
    wr = cross3(w, rel)
    vc = (v[0] + wr[0], v[1] + wr[1], v[2] + wr[2])
    vn = normal[0] * vc[0] + normal[1] * vc[1] + normal[2] * vc[2]
    if vn >= 0:
        return v, w, 0.0
    rn = cross3(rel, normal)
    e = material["e"] if vn < -hard else 0.0
    jn = -(1 + e) * vn / (1 + (rn[0] ** 2 + rn[1] ** 2 + rn[2] ** 2) / INERTIA)
    v = (v[0] + normal[0] * jn, v[1] + normal[1] * jn, v[2] + normal[2] * jn)
    imp = cross3(rel, (normal[0] * jn, normal[1] * jn, normal[2] * jn))
    w = (w[0] + imp[0] / INERTIA, w[1] + imp[1] / INERTIA, w[2] + imp[2] / INERTIA)
    wr = cross3(w, rel)
    vc = (v[0] + wr[0], v[1] + wr[1], v[2] + wr[2])
    dn = normal[0] * vc[0] + normal[1] * vc[1] + normal[2] * vc[2]
    vt = (vc[0] - normal[0] * dn, vc[1] - normal[1] * dn, vc[2] - normal[2] * dn)
    speed = math.sqrt(vt[0] ** 2 + vt[1] ** 2 + vt[2] ** 2)
    if speed > 1e-6:
        t = (vt[0] / speed, vt[1] / speed, vt[2] / speed)
        rt = cross3(rel, t)
        jt = min(speed / (1 + (rt[0] ** 2 + rt[1] ** 2 + rt[2] ** 2) / INERTIA), material["mu"] * jn)
        v = (v[0] - t[0] * jt, v[1] - t[1] * jt, v[2] - t[2] * jt)
        imp = cross3(rel, (t[0] * jt, t[1] * jt, t[2] * jt))
        w = (w[0] - imp[0] / INERTIA, w[1] - imp[1] / INERTIA, w[2] - imp[2] / INERTIA)
    return v, w, jn


# Launch profiles tried in turn (the best-yielding one makes the bank): throw speed toward the rail, drag along the
# table, how hard the lane pulls the die back to its middle, and how end-over-end the spin is.
PROFILES = [
    {"speed": (15.5, 20.5), "drag": 0.5, "lane": 30.0, "bias": 0.3},
    {"speed": (13.0, 18.0), "drag": 0.35, "lane": 30.0, "bias": 0.25},
    {"speed": (17.0, 23.0), "drag": 0.45, "lane": 30.0, "bias": 0.3},
    {"speed": (11.0, 15.0), "drag": 0.2, "lane": 30.0, "bias": 0.2},
]


def simulate(rng, profile):
    """One throw from the viewer's side toward the far rail (the plane y = 0, die on y < 0, Blender
    axes). Returns the recorded frames or None when the throw is not worth keeping."""
    p = [rng.uniform(-0.12, 0.12), -rng.uniform(7.2, 8.4), rng.uniform(1.8, 3.0)]
    v = (rng.uniform(-0.15, 0.15), rng.uniform(*profile["speed"]), rng.uniform(-1.0, 2.0))
    # Mostly end over end (a spin about the lateral x axis), a little of the others: thrown dice roll forward.
    axis = [rng.choice((-1.0, 1.0)), rng.gauss(0, profile["bias"]), rng.gauss(0, profile["bias"])]
    norm = math.sqrt(sum(a * a for a in axis))
    spin = rng.uniform(12, 26)
    w = tuple(a / norm * spin for a in axis)
    q = [rng.gauss(0, 1) for _ in range(4)]
    qn = math.sqrt(sum(a * a for a in q))
    q = [a / qn for a in q]
    states, rail_hits, bounces = [], [], []
    resting = 0
    up = (0.0, 0.0, 1.0)
    toward = (0.0, -1.0, 0.0)
    for step in range(int(4.2 / DT)):
        v = (v[0], v[1], v[2] - GRAVITY * DT)
        p[0] += v[0] * DT
        p[1] += v[1] * DT
        p[2] += v[2] * DT
        q = quat_integrate(q, w, DT)
        m = q_matrix(q)
        world = [(m[0] * u[0] + m[1] * u[1] + m[2] * u[2], m[3] * u[0] + m[4] * u[1] + m[5] * u[2], m[6] * u[0] + m[7] * u[1] + m[8] * u[2])
                 for u in VERT_LIST]
        low = p[2] + min(c[2] for c in world)
        far = p[1] + max(c[1] for c in world)
        if low < 0 or far > 0:
            for _ in range(3):
                for rel in world:
                    z = p[2] + rel[2]
                    if z < 0:
                        v, w, jn = contact(v, w, rel, up, TABLE, 1.2)
                        if jn > 2.0:
                            bounces.append((step * DT, jn))
                        p[2] -= z * 0.6
                    y = p[1] + rel[1]
                    if y > 0:
                        v, w, jn = contact(v, w, rel, toward, RAIL, 1.0)
                        if jn > 0.5:
                            rail_hits.append((step * DT, p[2] + rel[2]))
                        p[1] -= y * 0.6
        # Light air drag, and the extra rolling drag a faceted die has on felt.
        grounded = low < 0.05
        decay_v = math.exp(-(0.10 + (profile["drag"] if grounded else 0.0)) * DT)
        decay_w = math.exp(-(0.20 + (1.6 if grounded else 0.0)) * DT)
        # The lane: a soft pull toward the middle and damping of sideways drift, so neighbours never meet.
        v = (v[0] * decay_v * math.exp(-7.0 * DT) - profile["lane"] * p[0] * DT, v[1] * decay_v, v[2] * decay_v)
        w = (w[0] * decay_w, w[1] * decay_w, w[2] * decay_w)
        states.append((tuple(p), tuple(q)))
        if grounded and math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) < 0.35 and math.sqrt(w[0] ** 2 + w[1] ** 2 + w[2] ** 2) < 0.9:
            resting += 1
            if resting > 24:
                break
        else:
            resting = 0
    else:
        return None
    return {"states": states, "rail": [(t * TIME_SCALE, h) for t, h in rail_hits],
            "bounces": [(t * TIME_SCALE, j) for t, j in bounces]}


def resample(states):
    """The simulated states as 60 fps keyframes of the slowed-down playback (positions lerped, orientations slerped)."""
    count = int((len(states) - 1) * DT * TIME_SCALE * 60) + 1
    frames = []
    for k in range(count + 1):
        exact = min(k / 60.0 / TIME_SCALE / DT, len(states) - 1)
        i = min(int(exact), len(states) - 2)
        f = exact - i
        (p0, q0), (p1, q1) = states[i], states[i + 1]
        pos = np.array([p0[j] + (p1[j] - p0[j]) * f for j in range(3)])
        q = Quaternion(q0).slerp(Quaternion(q1), f)
        frames.append((pos, np.array([q.w, q.x, q.y, q.z])))
    return frames


def settle(frames):
    """Snap the last pose to flat on its resting face (small residual rotation removed) and spread
    the correction over the last frames. Returns frames and the face now pointing up."""
    p_end, q_end = frames[-1]
    R = quat_to_matrix(q_end)
    normals = np.array([f["n"] for f in FACE])
    up_face = int(np.argmax((R @ normals.T).T[:, 2]))
    world_n = R @ normals[up_face]
    # Smallest rotation that turns the face normal to +z.
    axis = np.cross(world_n, [0, 0, 1.0])
    s = np.linalg.norm(axis)
    if s > 1e-9:
        angle = math.atan2(s, float(np.dot(world_n, [0, 0, 1.0])))
        fix = Quaternion(tuple(float(x) for x in axis / s), angle)
        q_final = (fix @ Quaternion(tuple(float(x) for x in q_end))).normalized()
    else:
        q_final = Quaternion(tuple(float(x) for x in q_end))
    z_final = INRADIUS
    out_frames = list(frames)
    blend = min(10, len(out_frames) - 1)
    for k in range(blend):
        i = len(out_frames) - blend + k
        t = (k + 1) / blend
        p, q = out_frames[i]
        qi = Quaternion(tuple(float(x) for x in q)).slerp(q_final, t)
        out_frames[i] = (np.array([p[0] * (1 - t) + p_end[0] * t, p[1] * (1 - t) + p_end[1] * t, p[2] * (1 - t) + z_final * t]),
                         np.array([qi.w, qi.x, qi.y, qi.z]))
    return out_frames, up_face


def throw_is_good(result):
    """The rules for a throw worth keeping, and the reason it is not. Returns (ok, reason)."""
    states = result["states"]
    duration = (len(states) - 1) * DT * TIME_SCALE
    xs = [st[0][0] for st in states]
    ys = [st[0][1] for st in states]
    end = states[-1][0]
    if not DURATION[0] <= duration <= DURATION[1]:
        return False, "duration"
    if not result["rail"] or len(result["rail"]) > 3 or result["rail"][0][1] > 2.0:
        return False, "rail"           # it must clearly hit the rail, low down, not skim over it
    if len(result["bounces"]) < 3:
        return False, "too few bounces"
    if max(abs(x) for x in xs) > LANE_DRIFT:
        return False, "left its lane"
    if not -3.6 <= end[1] <= -1.35:
        return False, "rest spot"
    if max(ys) > 0.3:
        return False, "rode the wall"  # it must not ride up the wall either
    return True, ""


def choose_profile(rng):
    """Try each launch profile on a batch of throws and keep the one whose throws pass most often."""
    best, best_score = PROFILES[0], -1
    for profile in PROFILES:
        score = 0
        reasons = {}
        for _ in range(120):
            result = simulate(rng, profile)
            ok, why = (False, "never settled") if result is None else throw_is_good(result)
            score += ok
            reasons[why] = reasons.get(why, 0) + 1
        print(f"[d20] profile {profile}: {score}/120 pass; {reasons}")
        if score > best_score:
            best, best_score = profile, score
    return best


def build_throws():
    import collections
    rng = random.Random(ARGS.seed)
    kept = []
    rejected = collections.Counter()
    durations, rail_counts, lanes, ends = [], [], [], []
    # Simulate until there is a good pick to choose from (and at least a modest number of tries), up to a cap.
    profile = choose_profile(rng)
    cap, tried = ARGS.candidates * 4, 0
    while tried < cap and not (len(kept) >= ARGS.keep * 5 and tried >= ARGS.candidates // 3):
        tried += 1
        result = simulate(rng, profile)
        if result is None:
            rejected["never settled"] += 1
            continue
        states = result["states"]
        duration = (len(states) - 1) * DT * TIME_SCALE
        end = states[-1][0]
        durations.append(duration)
        rail_counts.append(len(result["rail"]))
        lanes.append(max(abs(st[0][0]) for st in states))
        ends.append(float(end[1]))
        ok, why = throw_is_good(result)
        if not ok:
            rejected[why] += 1
            continue
        flat, face = settle(resample(states))
        kept.append({"frames": flat, "rail": result["rail"], "bounces": result["bounces"], "face": face, "duration": duration})
    def pct(values, q):
        values = sorted(values)
        return values[min(len(values) - 1, int(q * len(values)))] if values else float("nan")
    print(f"[d20] tried {tried}; rejected {dict(rejected)}")
    print("[d20] duration p10/p50/p90 %.2f %.2f %.2f; rail hits p50 %d; lane drift p50/p90 %.2f %.2f; rest y p10/p50/p90 %.2f %.2f %.2f" % (
        pct(durations, .1), pct(durations, .5), pct(durations, .9), pct(rail_counts, .5), pct(lanes, .5), pct(lanes, .9),
        pct(ends, .1), pct(ends, .5), pct(ends, .9)))
    print(f"[d20] {len(kept)} usable throws")
    # Prefer a spread of resting faces, then variety in timing.
    chosen, seen = [], set()
    for t in sorted(kept, key=lambda t: (t["face"] in seen, t["duration"])):
        if len(chosen) >= ARGS.keep:
            break
        chosen.append(t)
        seen.add(t["face"])
    if len(chosen) < 6:
        raise SystemExit("[d20] too few usable throws; raise --candidates")
    C = Matrix.Rotation(-math.pi / 2, 3, "X")
    qC = C.to_quaternion()
    bank = []
    for t in chosen:
        pos, quat = [], []
        for p, q in t["frames"]:
            py = zup_to_yup(p)
            qq = qC @ Quaternion(tuple(float(x) for x in q)) @ qC.inverted()          # basis change: Blender frame to Y-up frame
            pos += [round(float(py[0]), 4), round(float(py[1]), 4), round(float(py[2]), 4)]
            quat += [round(float(qq.x), 5), round(float(qq.y), 5), round(float(qq.z), 5), round(float(qq.w), 5)]
        rail_t = t["rail"][0][0] / 1.0
        bank.append({"frames": len(t["frames"]), "faceUp": int(t["face"]), "position": pos, "orientation": quat,
                     "railTime": round(rail_t, 3), "tableHits": [[round(a, 3), round(min(b / 8.0, 1.0), 2)] for a, b in t["bounces"][:8]]})
    doc = {"fps": 60, "up": "y", "railPlane": "z=0", "note": "position x,y,z per frame; orientation x,y,z,w per frame; "
           "orientations take the die's local Y-up frame to the world. tableHits are [time, strength 0-1].", "throws": bank}
    with open(out("d20-throws.json"), "w") as f:
        json.dump(doc, f, separators=(",", ":"))
    print(f"[d20] wrote d20-throws.json ({os.path.getsize(out('d20-throws.json')) / 1024:.0f} KB), faces {[b['faceUp'] for b in bank]}")


# --- the table ----------------------------------------------------------------------------------

PX_PER_UNIT = 80
MAT = {"portrait": (9.6, 15.2), "landscape": (15.2, 9.6)}
PLANE = {"portrait": (15.0, 34.0), "landscape": (34.0, 15.0)}
RAIL_WIDTH, RAIL_HEIGHT = 0.85, 0.6
LEATHER_SOURCE = os.path.join(CATALOG, "battlefield-tavern-landscape.imageset/battlefield-tavern-landscape.jpg")
WOOD_SOURCE = os.path.join(CATALOG, "battlefield-wood.imageset/battlefield-wood.jpg")


def prepare_leather(orientation):
    """The board's own leather mat, cropped inside its stitching (no sockets, no frame)."""
    path = out(f"_leather-{orientation}.png")
    # Inner leather of the landscape plate: the stitched border and the four corner ornaments are in,
    # the walnut frame and the socket bar are out.
    args = ["magick", LEATHER_SOURCE, "-crop", "1760x1120+552+58", "+repage"]
    if orientation == "portrait":
        args += ["-rotate", "90"]
    mw, mh = MAT[orientation]
    args += ["-resize", f"{int(mw * PX_PER_UNIT * ARGS.table_scale * 1.5)}x{int(mh * PX_PER_UNIT * ARGS.table_scale * 1.5)}!", path]
    subprocess.run(args, check=True)
    return path


def make_material(name, nodes_builder):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out_node = nt.nodes.new("ShaderNodeOutputMaterial")
    shader = nodes_builder(nt)
    nt.links.new(shader.outputs[0], out_node.inputs["Surface"])
    return mat


def image_node(nt, path, extension="REPEAT", non_color=False):
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = bpy.data.images.load(path)
    node.extension = extension
    if non_color:
        node.image.colorspace_settings.name = "Non-Color"
    return node


def box(name, size, location, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if material:
        obj.data.materials.append(material)
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier="bevel")
    return obj


def ring(name, outer, inner, height, z, material, bevel=0.0):
    a = box(name, (outer[0], outer[1], height), (0, 0, z), material, 0)
    cutter = box(name + "_cut", (inner[0], inner[1], height * 3), (0, 0, z), None, 0)
    mod = a.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    bpy.context.view_layer.objects.active = a
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(cutter, do_unlink=True)
    if bevel:
        mod = a.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier="bevel")
    return a


def render_table(orientation):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    pw, ph = PLANE[orientation]
    mw, mh = MAT[orientation]
    ppu = PX_PER_UNIT * ARGS.table_scale
    scene.render.engine = "CYCLES"
    scene.cycles.samples = ARGS.samples
    scene.cycles.use_denoising = True
    scene.cycles.device = "CPU"
    scene.render.resolution_x, scene.render.resolution_y = int(pw * ppu), int(ph * ppu)
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"

    leather_path = prepare_leather(orientation)

    def wood_builder(tint, rotate=0.0, tile=15.0):
        def build(nt):
            coord = nt.nodes.new("ShaderNodeTexCoord")
            mapping = nt.nodes.new("ShaderNodeMapping")
            mapping.inputs["Scale"].default_value = (1 / tile, 1 / tile, 1)
            mapping.inputs["Rotation"].default_value = (0, 0, rotate)
            nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
            img = image_node(nt, WOOD_SOURCE, "MIRROR")
            nt.links.new(mapping.outputs["Vector"], img.inputs["Vector"])
            tinted = nt.nodes.new("ShaderNodeMix")
            tinted.data_type = "RGBA"
            tinted.blend_type = "MULTIPLY"
            tinted.inputs["Factor"].default_value = 1
            nt.links.new(img.outputs["Color"], tinted.inputs["A"])
            tinted.inputs["B"].default_value = (*tint, 1)
            bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
            nt.links.new(tinted.outputs["Result"], bsdf.inputs["Base Color"])
            bsdf.inputs["Roughness"].default_value = 0.5
            bump = nt.nodes.new("ShaderNodeBump")
            bump.inputs["Strength"].default_value = 0.25
            nt.links.new(img.outputs["Color"], bump.inputs["Height"])
            nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
            return bsdf
        return build

    def leather_builder(nt):
        coord = nt.nodes.new("ShaderNodeTexCoord")
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (1 / mw, 1 / mh, 1)
        mapping.inputs["Location"].default_value = (0.5, 0.5, 0)
        nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
        img = image_node(nt, leather_path, "EXTEND")
        nt.links.new(mapping.outputs["Vector"], img.inputs["Vector"])
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.55
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.12
        nt.links.new(img.outputs["Color"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        return bsdf

    def brass_builder(nt):
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Base Color"].default_value = (0.86, 0.60, 0.24, 1)
        bsdf.inputs["Metallic"].default_value = 1.0
        bsdf.inputs["Roughness"].default_value = 0.32
        return bsdf

    wood = make_material("table-wood", wood_builder((1.05, 0.93, 0.84)))
    rail_wood = make_material("rail-wood", wood_builder((1.45, 1.05, 0.78), rotate=math.pi / 2, tile=9.0))
    leather = make_material("leather", leather_builder)
    brass = make_material("brass", brass_builder)

    box("boards", (pw, ph, 0.1), (0, 0, -0.05), wood)
    box("leather", (mw + 0.2, mh + 0.2, 0.06), (0, 0, 0.0), leather)
    outer = (mw + 2 * RAIL_WIDTH, mh + 2 * RAIL_WIDTH)
    ring("rail", outer, (mw, mh), RAIL_HEIGHT, RAIL_HEIGHT / 2 - 0.02, rail_wood, 0.09)
    ring("inlay", (outer[0] - 0.26, outer[1] - 0.26), (outer[0] - 0.4, outer[1] - 0.4), 0.05, RAIL_HEIGHT - 0.03, brass, 0.015)
    # A brass stud at each corner of the rail.
    for sx in (-1, 1):
        for sy in (-1, 1):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(sx * (outer[0] / 2 - 0.36), sy * (outer[1] / 2 - 0.36), RAIL_HEIGHT - 0.02),
                                                 segments=24, ring_count=12)
            stud = bpy.context.active_object
            stud.scale = (1, 1, 0.55)
            stud.data.materials.append(brass)
            bpy.ops.object.shade_smooth()

    # Light: a warm lamp up and to the left, a soft cool-warm fill, and a dim room.
    sun = bpy.data.lights.new("lamp", "SUN")
    sun.energy = 5.2
    sun.color = (1.0, 0.80, 0.58)
    sun.angle = math.radians(14)
    sun_obj = bpy.data.objects.new("lamp", sun)
    scene.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(52), 0, math.radians(-35))          # from upper left toward lower right
    fill = bpy.data.lights.new("fill", "AREA")
    fill.energy = 420
    fill.color = (1.0, 0.72, 0.5)
    fill.size = 14
    fill_obj = bpy.data.objects.new("fill", fill)
    scene.collection.objects.link(fill_obj)
    fill_obj.location = (0, 0, 9)
    world = bpy.data.worlds.new("room")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.09, 0.05, 0.03, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world

    cam = bpy.data.cameras.new("top")
    cam.type = "ORTHO"
    cam.ortho_scale = max(pw, ph)
    cam_obj = bpy.data.objects.new("top", cam)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 20)
    scene.camera = cam_obj
    raw = out(f"_table-{orientation}.png")
    scene.render.filepath = raw
    bpy.ops.render.render(write_still=True)
    # Warm lamp pool: the middle a touch brighter, the corners falling away into the room.
    final = out(f"_table-{orientation}.jpg")
    w, h = scene.render.resolution_x, scene.render.resolution_y
    subprocess.run(["magick", raw, "(", "-size", f"{w}x{h}", "radial-gradient:#ffffff-#a88c76", ")", "-compose", "multiply", "-composite",
                    "-modulate", "100,104,100", "-strip", "-interlace", "none", "-quality", "80", final], check=True)
    return final, (pw, ph)


def quad_glb(path, image, size, unlit=True, blend=False, flat_y=0.0, repeat=False):
    """A horizontal textured quad (width x depth, centred), unlit, as glTF."""
    w, d = size[0] / 2, size[1] / 2
    pos = np.array([(-w, flat_y, -d), (w, flat_y, -d), (w, flat_y, d), (-w, flat_y, d)], np.float32)
    nrm = np.array([(0, 1, 0)] * 4, np.float32)
    uv = np.array([(0, 0), (1, 0), (1, 1), (0, 1)], np.float32)
    idx = np.array([(0, 2, 1), (0, 3, 2)], np.uint32)
    glb = Glb()
    tex = glb.image(image, "image/png" if image.endswith(".png") else "image/jpeg")
    material = {"name": "unlit", "pbrMetallicRoughness": {"baseColorTexture": {"index": tex}, "metallicFactor": 0, "roughnessFactor": 1},
                "extensions": {"KHR_materials_unlit": {}}, "doubleSided": True}
    if blend:
        material["alphaMode"] = "BLEND"
    glb.materials.append(material)
    glb.mesh("quad", pos, nrm, uv, None, idx, 0)
    glb.write(path, extensions=["KHR_materials_unlit"])


def make_shadow_png():
    """A soft round blob: black, alpha falling off smoothly."""
    size = 128
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.sqrt((xx - size / 2 + 0.5) ** 2 + (yy - size / 2 + 0.5) ** 2) / (size / 2)
    alpha = np.clip(1 - r, 0, 1) ** 1.6
    img = np.zeros((size, size, 4), np.uint8)
    img[..., 3] = (alpha * 255).astype(np.uint8)
    path = out("_shadow.png")
    write_png(path, img)
    return path


def make_glow_png():
    """An ember halo: warm orange-gold, bright at the middle and fading out (the winner's die stands in it)."""
    size = 128
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.sqrt((xx - size / 2 + 0.5) ** 2 + (yy - size / 2 + 0.5) ** 2) / (size / 2)
    alpha = np.clip(1 - r, 0, 1) ** 2.2
    img = np.zeros((size, size, 4), np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = 255, 150, 70
    img[..., 3] = (alpha * 235).astype(np.uint8)
    path = out("_glow.png")
    write_png(path, img)
    return path


def build_tables():
    for orientation in ("portrait", "landscape"):
        image, size = render_table(orientation)
        quad_glb(out(f"d20-table-{orientation}.glb"), image, size)
    quad_glb(out("d20-shadow.glb"), make_shadow_png(), (2.0, 2.0), blend=True)
    quad_glb(out("d20-glow.glb"), make_glow_png(), (4.6, 4.6), blend=True)
    with open(out("d20-table.json"), "w") as f:
        json.dump({"unit": "die circumradius", "pixelsPerUnit": PX_PER_UNIT * ARGS.table_scale,
                   "portrait": {"plane": PLANE["portrait"], "mat": MAT["portrait"]},
                   "landscape": {"plane": PLANE["landscape"], "mat": MAT["landscape"]},
                   "railWidth": RAIL_WIDTH, "railHeight": RAIL_HEIGHT,
                   "note": "The plane lies at y = 0 centred on the origin, image top toward -z. The far rail's inner face is "
                           "z = -mat[1] / 2 (the throws' rail plane)."}, f, indent=1)


# --- preview ------------------------------------------------------------------------------------

def build_preview():
    """Imports the finished die back from its GLB and renders a contact sheet: top-down views with
    several numbers up, and one oblique view. Checks numbering, numeral orientation and materials."""
    info = json.load(open(out("d20.json")))
    sheet = []
    for number, name in ((1, "one"), (6, "six"), (9, "nine"), (13, "thirteen"), (20, "twenty"), (0, "oblique")):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        bpy.ops.import_scene.gltf(filepath=out("d20.glb"))
        roots = [o for o in scene.objects if o.parent is None]
        die = bpy.data.objects.new("pivot", None)
        scene.collection.objects.link(die)
        for r in roots:
            r.parent = die
        face = next((f for f in info["faces"] if f["number"] == number), info["faces"][0])
        n = Vector((face["normal"][0], -face["normal"][2], face["normal"][1]))
        c = Vector((face["cornerDirections"][0][0], -face["cornerDirections"][0][2], face["cornerDirections"][0][1]))
        q1 = n.rotation_difference(Vector((0, 0, 1)))
        c2 = q1 @ c
        angle = math.atan2(c2.x, c2.y)              # turn about +z that brings the numeral's up to +y
        q2 = Quaternion((0, 0, 1), angle)
        die.rotation_mode = "QUATERNION"
        die.rotation_quaternion = q2 @ q1 if number else Quaternion((0, 0, 1), 0.5) @ q1
        die.location = (0, 0, info["inradius"])
        bpy.ops.mesh.primitive_plane_add(size=12)
        floor = bpy.context.active_object
        mat = bpy.data.materials.new("floor")
        mat.use_nodes = True
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.17, 0.07, 1)
        mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
        floor.data.materials.append(mat)
        sun = bpy.data.lights.new("sun", "SUN")
        sun.energy = 3.0
        sun.color = (1, 0.82, 0.6)
        so = bpy.data.objects.new("sun", sun)
        scene.collection.objects.link(so)
        so.rotation_euler = (math.radians(52), 0, math.radians(-35))
        world = bpy.data.worlds.new("w")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.3, 0.2, 1)
        world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
        scene.world = world
        cam = bpy.data.cameras.new("c")
        co = bpy.data.objects.new("c", cam)
        scene.collection.objects.link(co)
        scene.camera = co
        if number:
            cam.type = "ORTHO"
            cam.ortho_scale = 2.6
            co.location = (0, 0, 8)
        else:
            cam.lens = 70
            co.location = (0, -5.2, 3.4)
            co.rotation_euler = (math.radians(66), 0, 0)
        scene.render.engine = "CYCLES"
        scene.cycles.samples = 48
        scene.cycles.use_denoising = True
        scene.render.resolution_x = scene.render.resolution_y = 420
        scene.view_settings.view_transform = "Standard"
        path = out(f"_preview-{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        sheet.append(path)
    subprocess.run(["magick", *sheet, "+append", out("preview-die.png")], check=True)
    print("[d20] wrote preview-die.png")


if __name__ == "__main__":
    if ARGS.mode in ("all", "model"):
        build_model()
    if ARGS.mode in ("all", "throws"):
        build_throws()
    if ARGS.mode in ("all", "table"):
        build_tables()
    if ARGS.mode in ("all", "preview"):
        build_preview()
