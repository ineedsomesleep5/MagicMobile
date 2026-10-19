"""3D sprites for the board's card moments (docs/BOARD_FX_ROADMAP.md, phase 16), built headlessly in Blender 5.2.

    blender -b --factory-startup --python-exit-code 1 -P scripts/brand/fx_sprites.py -- --out-dir build_output/fx-sprites
    zsh scripts/brand/install_fx_sprites.sh [build_output/fx-sprites]

Each sprite is one PNG strip of FRAMES square frames, left to right, on a transparent background, a quarter turn of
spin apart at the start (the apps play the strip as a short spin while the piece drops onto a card):
  counter-plus    a faceted emerald for +1/+1 counters
  counter-minus   a violet drop for -1/-1 counters
  counter-loyalty a blue enamel shield for loyalty
  counter-coin    a brass coin for any other counter
  exile-ring      a pale sigil ring seen from above at an angle, turning, for cards leaving to exile

The apps read them as the image sets tavern-fx-<name> (iOS asset catalogue, scale 3x); Android's prepareBrandAssets
copies every tavern-*.png into drawable-nodpi, so both apps use the same files.

Blender 5.2 rules (blender-core skill): data API instead of operators, nodes found by type, no material.use_nodes
(new materials already have nodes), EEVEE is BLENDER_EEVEE. Nothing is downloaded.
"""

import argparse
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Vector

FRAMES = 12


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="build_output/fx-sprites")
    parser.add_argument("--only", nargs="*", help="sprite names to render (default: all)")
    parser.add_argument("--samples", type=int, default=32)
    return parser.parse_args(argv)


# ---------- scene

def reset_scene(samples):
    for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras, bpy.data.images):
        for item in list(collection):
            collection.remove(item)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = samples
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    background.inputs["Color"].default_value = (0.02, 0.015, 0.012, 1)
    background.inputs["Strength"].default_value = 0.3
    return scene


def light(name, kind, location, energy, size=1.0, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 0)) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(obj)
    return obj


def camera(elevation_degrees, ortho_scale, resolution):
    scene = bpy.context.scene
    data = bpy.data.cameras.new("Camera")
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    obj = bpy.data.objects.new("Camera", data)
    e = math.radians(elevation_degrees)
    obj.location = (0, -6 * math.cos(e), 6 * math.sin(e))
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(obj)
    scene.camera = obj
    scene.render.resolution_x = scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100


def rig():
    # Warm key like the tavern's lamps, cool rim to lift the silhouette off the leather, soft fill.
    light("Key", "AREA", (2.2, -3.0, 3.2), 260, size=2.0, color=(1.0, 0.9, 0.78))
    light("Rim", "AREA", (-2.4, 2.2, 2.4), 220, size=1.5, color=(0.8, 0.88, 1.0))
    light("Fill", "AREA", (0.0, -3.5, 0.2), 45, size=3.0)


def material(name, color, metallic=0.0, roughness=0.2, emission=None, strength=0.0, coat=0.0):
    mat = bpy.data.materials.new(name)
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if coat:
        bsdf.inputs["Coat Weight"].default_value = coat
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def mesh_object(name, bm, mat, smooth=False):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def bevel(obj, width, segments=3):
    modifier = obj.modifiers.new("Bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"


# ---------- pieces (each about one unit across, centred on the origin, facing -Y towards the camera)

def gem():
    """A brilliant-cut emerald: octagonal table, crown down to the girdle, pavilion to a point."""
    bm = bmesh.new()
    n = 8
    table = [bm.verts.new((0.27 * math.cos(2 * math.pi * i / n), 0.27 * math.sin(2 * math.pi * i / n), 0.24)) for i in range(n)]
    girdle = [bm.verts.new((0.5 * math.cos(2 * math.pi * (i + 0.5) / n), 0.5 * math.sin(2 * math.pi * (i + 0.5) / n), 0.04)) for i in range(n)]
    culet = bm.verts.new((0, 0, -0.56))
    bm.faces.new(table)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((table[i], girdle[i], table[j]))
        bm.faces.new((table[j], girdle[i], girdle[j]))
        bm.faces.new((girdle[j], girdle[i], culet))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object("Gem", bm, material("Emerald", (0.01, 0.30, 0.08), roughness=0.04, emission=(0.04, 0.55, 0.16), strength=0.18, coat=1.0))
    obj.rotation_euler = (math.radians(90), 0, 0)
    obj.scale = (1, 1, 1)
    return obj


def drop():
    """A violet drop: a sphere drawn up to a point, like ichor."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=18, radius=0.36)
    for v in bm.verts:
        if v.co.z > 0:
            t = v.co.z / 0.36
            shrink = 1 - 0.92 * t ** 1.3
            v.co.x *= shrink
            v.co.y *= shrink
            v.co.z *= 1.85
    obj = mesh_object("Drop", bm, material("Ichor", (0.16, 0.02, 0.26), roughness=0.06, emission=(0.42, 0.08, 0.7), strength=0.22, coat=1.0),
                      smooth=True)
    obj.location.z = -0.12
    return obj


def shield():
    """A loyalty shield: a flat top, curved sides to a point, blue enamel with a bevelled edge."""
    outline = []
    for i in range(9):  # right side, top corner down to the point
        t = i / 8
        outline.append((0.44 * (1 - t ** 2.2), 0.46 - 0.98 * t))
    points = outline + [(-x, z) for x, z in reversed(outline[:-1])]
    bm = bmesh.new()
    front = [bm.verts.new((x, -0.08, z)) for x, z in points]
    face = bm.faces.new(front)
    bmesh.ops.extrude_face_region(bm, geom=[face])
    for v in bm.verts:
        if v not in front:
            v.co.y = 0.08
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object("Shield", bm, material("Enamel", (0.03, 0.16, 0.55), metallic=0.35, roughness=0.12,
                                             emission=(0.12, 0.35, 1.0), strength=0.15, coat=1.0))
    bevel(obj, 0.035)
    return obj


def coin():
    """A brass coin with a raised rim, standing so the spin shows its face and edge."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=48, radius1=0.46, radius2=0.46, depth=0.09)
    obj = mesh_object("Coin", bm, material("Brass", (0.86, 0.64, 0.3), metallic=1.0, roughness=0.28), smooth=True)
    obj.rotation_euler = (math.radians(90), 0, 0)
    bevel(obj, 0.02, segments=2)
    return obj


def ring():
    """The exile sigil: a thin glowing ring with seven rune ticks, lying flat."""
    bm = bmesh.new()
    major, minor, u, v = 1.0, 0.035, 96, 10
    rows = []
    for i in range(u):
        a = 2 * math.pi * i / u
        rows.append([bm.verts.new(((major + minor * math.cos(2 * math.pi * j / v)) * math.cos(a),
                                   (major + minor * math.cos(2 * math.pi * j / v)) * math.sin(a),
                                   minor * math.sin(2 * math.pi * j / v))) for j in range(v)])
    for i in range(u):
        for j in range(v):
            bm.faces.new((rows[i][j], rows[(i + 1) % u][j], rows[(i + 1) % u][(j + 1) % v], rows[i][(j + 1) % v]))
    glow = material("Sigil", (0.01, 0.02, 0.04), roughness=0.6, emission=(0.35, 0.72, 1.0), strength=1.6)
    obj = mesh_object("Ring", bm, glow, smooth=True)
    for k in range(7):  # uneven ticks, so the turn reads
        tick = bmesh.new()
        bmesh.ops.create_cube(tick, size=1)
        t = mesh_object(f"Rune{k}", tick, glow)
        a = 2 * math.pi * k / 7
        t.location = (1.16 * math.cos(a), 1.16 * math.sin(a), 0)
        t.rotation_euler = (0, 0, a)
        t.scale = (0.05 + 0.06 * (k % 3), 0.035, 0.03)
        t.parent = obj
    return obj


SPRITES = {
    # name: (builder, resolution, ortho scale, camera elevation, spin axis tilt)
    "counter-plus": (gem, 128, 1.45, 14),
    "counter-minus": (drop, 128, 1.45, 14),
    "counter-loyalty": (shield, 128, 1.35, 10),
    "counter-coin": (coin, 128, 1.3, 10),
    "exile-ring": (ring, 288, 2.75, 58),
}


# ---------- render and pack

def render_strip(name, out_dir, samples):
    builder, resolution, scale, elevation = SPRITES[name]
    scene = reset_scene(samples)
    rig()
    camera(elevation, scale, resolution)
    piece = builder()
    base = piece.rotation_euler.copy()
    frames = []
    for i in range(FRAMES):
        piece.rotation_euler = Euler((base.x, base.y, base.z + 2 * math.pi * i / FRAMES))
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "frames", f"{name}-{i:02d}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        frames.append(path)
    strip = np.zeros((resolution, resolution * FRAMES, 4), dtype=np.float32)
    for i, path in enumerate(frames):
        image = bpy.data.images.load(path)
        pixels = np.empty(resolution * resolution * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        strip[:, i * resolution:(i + 1) * resolution, :] = pixels.reshape(resolution, resolution, 4)
        bpy.data.images.remove(image)
    packed = bpy.data.images.new(f"tavern-fx-{name}", resolution * FRAMES, resolution, alpha=True)
    packed.pixels.foreach_set(strip.ravel())
    packed.filepath_raw = os.path.join(out_dir, f"tavern-fx-{name}.png")
    packed.file_format = "PNG"
    packed.save()
    # A contact sheet over the tavern leather (TavernPalette), to judge the sprite as the board shows it.
    leather = np.array([0.16, 0.10, 0.07], dtype=np.float32)
    alpha = strip[:, :, 3:4]
    sheet = np.concatenate([strip[:, :, :3] * alpha + leather * (1 - alpha), np.ones_like(alpha)], axis=2)
    preview = bpy.data.images.new(f"preview-{name}", resolution * FRAMES, resolution, alpha=True)
    preview.pixels.foreach_set(sheet.ravel())
    preview.filepath_raw = os.path.join(out_dir, "preview", f"{name}.png")
    preview.file_format = "PNG"
    preview.save()
    triangles = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
    return {"name": name, "file": packed.filepath_raw, "frames": FRAMES, "frame": resolution, "triangles": triangles,
            "bytes": os.path.getsize(packed.filepath_raw)}


def main():
    options = args()
    out_dir = os.path.abspath(options.out_dir)
    os.makedirs(os.path.join(out_dir, "frames"), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "preview"), exist_ok=True)
    names = options.only or list(SPRITES)
    results = [render_strip(name, out_dir, options.samples) for name in names]
    import json
    print("@@JSON@@" + json.dumps({"ok": True, "sprites": results}))


if __name__ == "__main__":
    main()
