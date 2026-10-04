"""Render the ranked tier badges from their Meshy models: a still and a full turn per tier.

The six badges (Bronze to Mythic) were painted as one Codex sheet, cut apart and turned into
textured 3D models with Meshy's image-to-3D (meshy-cli, 2026-10-04). This lays each model face-up
to an orthographic camera and renders, with a transparent background:

  tavern-rank-<tier>.png             the still, front on (the app's badge everywhere)
  tavern-rank-<tier>-spin-NN.png     FRAMES steps of a full turn about the vertical axis, frame 0
                                     front on (the rank-up and rank-down moments)

  blender -b -P scripts/brand/rank_badges.py -- --out-dir build_output/tavern/rank [--tiers bronze,gold]

Inputs: ~/Movies/motion-assets/magicmobile-brand/rank-badges/meshy/<tier>/model.glb.
Every frame keeps the badge's own size (the widest tier, Mythic, sets the frame), so the app can
play the spin and swap to the still without a jump.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

HOME = os.path.expanduser("~/Movies/motion-assets/magicmobile-brand/rank-badges/meshy")
TIERS = ["bronze", "silver", "gold", "platinum", "diamond", "mythic"]
FRAMES = 16


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out-dir", required=True)
    p.add_argument("--px", type=int, default=600, help="still size")
    p.add_argument("--spin-px", type=int, default=300, help="spin frame size")
    p.add_argument("--samples", type=int, default=48)
    p.add_argument("--tiers", default=",".join(TIERS))
    p.add_argument("--no-spin", action="store_true")
    p.add_argument("--test", action="store_true", help="one still per axis guess, to check orientation")
    return p.parse_args(argv)


ARGS = parse_args()


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for device in prefs.devices:
        device.use = True
    scene.cycles.device = "GPU"
    scene.cycles.samples = ARGS.samples
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.compression = 90
    # The painted texture keeps its colours; light adds shape and a moving glint.
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.26, 0.22, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.1
    scene.world = world
    light(scene, "Key", (-1.8, 2.0, 3.0), 220, (1.0, 0.9, 0.76), 2.0)
    light(scene, "Fill", (2.2, 0.6, 2.4), 80, (0.85, 0.88, 1.0), 2.5)
    light(scene, "Rim", (1.6, -2.0, 0.6), 90, (1.0, 0.62, 0.34), 1.2)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.0
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0, 0, 6)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return scene


def light(scene, name, loc, energy, color, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.size = energy, color, size
    ob = bpy.data.objects.new(name, data)
    ob.location = loc
    ob.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(ob)


def import_badge(tier):
    """The model, parented to an empty at the origin, face-up toward the camera (+Z), its
    widest extent 2.0 (the camera's full frame) scaled by `fit`."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(HOME, tier, "model.glb"))
    imported = set(bpy.data.objects) - before
    meshes = [ob for ob in imported if ob.type == "MESH"]
    pivot = bpy.data.objects.new(f"{tier}-pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    # glTF's front (+Z there) imports as Blender's -Y: stand the badge up to face +Z.
    for ob in imported:
        if ob.parent is None:
            ob.parent = pivot
    pivot.rotation_euler = (math.radians(-90), 0, 0)
    bpy.context.view_layer.update()
    corners = [ob.matrix_world @ Vector(c) for ob in meshes for c in ob.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    centre = (lo + hi) / 2
    return pivot, meshes, centre, hi - lo


def render(scene, path, px):
    scene.render.resolution_x = scene.render.resolution_y = px
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(ARGS.out_dir, exist_ok=True)
    tiers = [t for t in ARGS.tiers.split(",") if t]
    # One frame size for all tiers: the largest badge fills 96% of the frame.
    sizes = {}
    for tier in TIERS:
        scene = setup_scene()
        _, _, _, size = import_badge(tier)
        sizes[tier] = max(size.x, size.y)
    largest = max(sizes.values())
    for tier in tiers:
        scene = setup_scene()
        pivot, meshes, centre, size = import_badge(tier)
        scale = 1.92 / largest
        holder = bpy.data.objects.new(f"{tier}-holder", None)
        scene.collection.objects.link(holder)
        pivot.parent = holder
        pivot.location = -centre
        holder.scale = (scale, scale, scale)
        print(tier, "size", tuple(round(v, 3) for v in size), "depth axis z", round(size.z, 3))
        if ARGS.test:
            render(scene, os.path.join(ARGS.out_dir, f"test-{tier}.png"), 360)
            continue
        holder.rotation_euler = (0, 0, 0)
        render(scene, os.path.join(ARGS.out_dir, f"tavern-rank-{tier}.png"), ARGS.px)
        if ARGS.no_spin:
            continue
        for i in range(FRAMES):
            holder.rotation_euler = (0, math.radians(360 * i / FRAMES), 0)
            render(scene, os.path.join(ARGS.out_dir, f"tavern-rank-{tier}-spin-{i:02d}.png"), ARGS.spin_px)
    print("DONE", tiers)


main()
