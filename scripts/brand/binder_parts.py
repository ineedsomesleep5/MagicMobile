"""Renders the Deck Studio binder's brass parts (concept B, 2026-10-06) from Meshy models as sprites.

Caleb asked that anything new be made with Meshy. The models are Meshy text-to-3D results kept in
~/Movies/motion-assets/magicmobile-brand/meshy/binder/<part>/model.glb; this renders each one straight
on, orthographic, with a transparent background and warm tavern light, at 3 px per point.

    blender -b -P scripts/brand/binder_parts.py -- --out-dir build_output/tavern/binder [--parts tavern-binder-buckle]
    zsh scripts/brand/install_binder_parts.sh

Parts (sprite name, Meshy model folder):
    tavern-binder-buckle       buckle   the Done strap's buckle (text-to-3D)
    tavern-binder-jewel        jewel    the ember jewel on Play (text-to-3D)
    tavern-binder-corner       l-page   the L-shaped corner pieces of pages and plates (image-to-3D from a painting)
    tavern-binder-card-corner  l-card   the slimmer L corners of card sleeves and the commander's art (likewise)
    tavern-binder-leaf-corner  l-leaf   gilded acanthus corners of plates (image-to-3D from Caleb's inspiration)
    tavern-binder-book-corner  l-book   book-corner protectors on the library's decks (after Caleb's book photo)
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

MESHY = os.path.expanduser("~/Movies/motion-assets/magicmobile-brand/meshy/binder")

# Each part: the Meshy model's folder, its width in points, the view that shows its face, a turn about the
# view axis in degrees, and how much empty margin to leave round it (the corners leave none, so their outer
# edges sit exactly on the image's edge and the piece sits flush on the corner it guards).
PARTS = {
    "tavern-binder-buckle": dict(model="buckle", width=48, view="front"),
    "tavern-binder-jewel": dict(model="jewel", width=40, view="front"),
    # L-shaped corner pieces (Caleb, 2026-10-06: "we want an L shape corner", "a real nice corner piece"):
    # Meshy image-to-3D from painted references, the outer corner at the top-left.
    "tavern-binder-corner": dict(model="l-page", width=48, view="front", margin=1.0, flip="x", exposure=-0.45),
    "tavern-binder-card-corner": dict(model="l-card", width=40, view="front", margin=1.0, exposure=-0.45),
    # Gilded acanthus leaves for the plates set into a page, from Caleb's inspiration image (image-to-3D).
    "tavern-binder-leaf-corner": dict(model="l-leaf", width=40, view="front", margin=1.0, exposure=-0.6),
    # Book-corner protectors for the decks in the library, after Caleb's photo of a leather book (image-to-3D).
    "tavern-binder-book-corner": dict(model="l-book", width=40, view="front", margin=1.0, exposure=-0.3),
    # The index tabs (Caleb, 2026-10-06: "make the tabs on the right look more like tabs maybe a 3d effect"):
    # a stitched oxblood leather tab with a brass rivet, Meshy image-to-3D from a painted reference. The app
    # 9-slices it to each tab's height; "width" is the long side, so it comes out 40 pt wide.
    "tavern-binder-tab": dict(model="l-tab", width=115, view="front", margin=1.0, exposure=-0.2),
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="build_output/tavern/binder")
    parser.add_argument("--parts", default=",".join(PARTS))
    parser.add_argument("--samples", type=int, default=96)
    parser.add_argument("--view", help="render the parts from this view instead (front, left, right, top), to choose one")
    return parser.parse_args(argv)


def import_model(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in objs if o.type == "MESH"]
    # Meshy models arrive at 4K and up to 1.5M faces; a sprite a few dozen points wide needs neither.
    for o in meshes:
        faces = len(o.data.polygons)
        if faces > 80000:
            bpy.context.view_layer.objects.active = o
            dec = o.modifiers.new("decimate", "DECIMATE")
            dec.ratio = 80000 / faces
            bpy.ops.object.modifier_apply(modifier=dec.name)
        for slot in o.material_slots:
            if slot.material and slot.material.use_nodes:
                for node in slot.material.node_tree.nodes:
                    if node.type == "TEX_IMAGE" and node.image and max(node.image.size) > 1024:
                        node.image.scale(1024, 1024)
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return meshes, lo, hi


def light(name, kind, location, energy, color, size=1.0):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    direction = -Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


def render(name, folder, width_pt, view, roll, out_dir, samples, margin=1.04, flip=False, exposure=0.0):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    path = os.path.join(MESHY, folder, "model.glb")
    if not os.path.exists(path):
        print(f"missing model, skipped: {path}")
        return
    meshes, lo, hi = import_model(path)
    center = (lo + hi) / 2
    size = hi - lo
    for o in meshes:
        o.location -= center
    bpy.context.view_layer.update()

    # Straight on: "front" looks along +Y at the model's face, "top" looks down -Z.
    camera_data = bpy.data.cameras.new("camera")
    camera_data.type = "ORTHO"
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    if view == "front":
        camera.location = (0, -10, 0)
        camera.rotation_euler = (math.radians(90), math.radians(roll), 0)
        span_w, span_h = size.x, size.z
    elif view == "right":
        camera.location = (10, 0, 0)
        camera.rotation_euler = (math.radians(90), math.radians(roll), math.radians(90))
        span_w, span_h = size.y, size.z
    elif view == "left":
        camera.location = (-10, 0, 0)
        camera.rotation_euler = (math.radians(90), math.radians(roll), math.radians(-90))
        span_w, span_h = size.y, size.z
    else:
        camera.location = (0, 0, 10)
        camera.rotation_euler = (0, 0, math.radians(roll))
        span_w, span_h = size.x, size.y
    camera_data.ortho_scale = max(span_w, span_h) * margin

    px_w = width_pt * 3
    aspect = span_h / max(span_w, 1e-6)
    scene.render.resolution_x = px_w if span_w >= span_h else max(1, round(px_w / aspect))
    scene.render.resolution_y = round(px_w * aspect) if span_w >= span_h else px_w
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.device = "CPU"
    scene.view_settings.view_transform = "Standard"
    # Deeper recesses for engraved brass seen small.
    scene.view_settings.exposure = exposure

    # Warm tavern light: a candle-coloured key from the upper left, a cool soft fill, a rim behind.
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.06, 0.04, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    scene.world = world
    reach = max(size) * 3
    toward = {"front": Vector((0, -1, 0)), "right": Vector((1, 0, 0)), "left": Vector((-1, 0, 0))}.get(view, Vector((0, 0, 1)))
    key = Vector((-reach, 0, reach)) if view == "front" else Vector((-reach, reach, reach))
    light("key", "AREA", key + toward * reach, 900 * reach * reach / 9, (1.0, 0.85, 0.62), size=reach * 0.6)
    fill = Vector((reach, 0, -reach * 0.3)) if view == "front" else Vector((reach, -reach, reach * 0.6))
    light("fill", "AREA", fill + toward * reach, 260 * reach * reach / 9, (0.80, 0.86, 1.0), size=reach)
    rim = Vector((0, reach * 1.5, reach)) if view == "front" else Vector((0, -reach, reach * 0.3))
    light("rim", "AREA", rim, 300 * reach * reach / 9, (1.0, 0.75, 0.45), size=reach * 0.5)

    os.makedirs(out_dir, exist_ok=True)
    scene.render.filepath = os.path.join(out_dir, f"{name}.png")
    bpy.ops.render.render(write_still=True)
    if flip:
        mirror(scene.render.filepath, flip)
    print(f"rendered {scene.render.filepath} {scene.render.resolution_x}x{scene.render.resolution_y}")


def mirror(path, flip):
    """Turns a rendered corner so its outer corner is at the top-left: flip is "x", "y" or "xy"."""
    import numpy as np
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)
    if "x" in flip:
        pixels = pixels[:, ::-1]
    if "y" in flip:
        pixels = pixels[::-1]
    image.pixels[:] = np.ascontiguousarray(pixels).ravel()
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()


def main():
    options = args()
    for name in options.parts.split(","):
        part = PARTS[name]
        view = part["view"]
        if options.view:
            view, name = options.view, f"{name}-{options.view}"
        render(name, part["model"], part["width"], view, part.get("roll", 0), os.path.abspath(options.out_dir), options.samples,
               part.get("margin", 1.04), part.get("flip", False), part.get("exposure", 0.0))

main()
