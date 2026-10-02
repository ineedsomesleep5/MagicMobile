"""Render the Walnut Tavern pass button's inner disc turning over, as sprite frames.

The disc is a real 3D coin: the painted glass-and-hourglass face (cut from
pass-button-art.png by scripts/brand/cut_pass_layers.sh) on the front, a dim
bronze "waiting" face on the back and a copper edge. It turns a full circle about its
horizontal axis in FRAMES steps; frame 0 is the front, FRAMES/2 the back. The app plays
the frames inside the static brass ring (tavern-pass-ring), like Hearthstone's end-turn
button.

  blender -b -P scripts/brand/pass_button_flip.py -- --out-dir build_output/tavern/pass-flip

Inputs (~/Movies/motion-assets/magicmobile-brand): pass-face-front.png, pass-face-back.png.
Every frame is the full button frame (the ring's outer edge at 0.98 of the half width), so
frames, ring and the app's 1:1 frame line up.
"""

import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HOME = os.path.expanduser("~/Movies/motion-assets/magicmobile-brand")
FRAMES = 48
# The glass reaches 272 of the art's 384 px half width (measured on the squared art).
DISC_RADIUS = 272 / 384
DISC_DEPTH = 0.11


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out-dir", required=True)
    p.add_argument("--px", type=int, default=300)
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--front", default=os.path.join(HOME, "pass-face-front.png"))
    p.add_argument("--back", default=os.path.join(HOME, "pass-face-back.png"))
    return p.parse_args(argv)


ARGS = parse_args()


def face_material(name, image_path, glow):
    """The painted face shown as painted (emission at `glow`, Standard view transform), under
    a clear glossy coat that catches the key light as the disc turns."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    n, l = nt.nodes, nt.links
    n.remove(n["Principled BSDF"])
    tex = n.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(image_path)
    tex.extension = "EXTEND"
    emit = n.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = glow
    l.new(tex.outputs["Color"], emit.inputs["Color"])
    gloss = n.new("ShaderNodeBsdfGlossy")
    gloss.inputs["Roughness"].default_value = 0.12
    fresnel = n.new("ShaderNodeLayerWeight")
    fresnel.inputs["Blend"].default_value = 0.25
    coat = n.new("ShaderNodeMixShader")
    l.new(fresnel.outputs["Fresnel"], coat.inputs["Fac"])
    l.new(emit.outputs["Emission"], coat.inputs[1])
    add = n.new("ShaderNodeAddShader")
    l.new(emit.outputs["Emission"], add.inputs[0])
    l.new(gloss.outputs["BSDF"], add.inputs[1])
    l.new(fresnel.outputs["Fresnel"], coat.inputs["Fac"])
    l.new(add.outputs["Shader"], coat.inputs[2])
    l.new(coat.outputs["Shader"], n["Material Output"].inputs["Surface"])
    return mat


def copper_material():
    mat = bpy.data.materials.new("CopperEdge")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.92, 0.52, 0.30, 1)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.3
    return mat


def build_disc():
    """A coin with UVs mapping each cap onto its image, so both faces read upright when
    they face the camera (the back is seen after a half turn about X, which mirrors Y)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    n, r, h = 160, DISC_RADIUS, DISC_DEPTH / 2
    top = [bm.verts.new((r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n), h)) for k in range(n)]
    bottom = [bm.verts.new((v.co.x, v.co.y, -h)) for v in top]
    front = bm.faces.new(top)
    back = bm.faces.new(list(reversed(bottom)))
    front.material_index, back.material_index = 0, 1
    for loop in front.loops:
        loop[uv].uv = (0.5 + loop.vert.co.x / (2 * r), 0.5 + loop.vert.co.y / (2 * r))
    for loop in back.loops:
        loop[uv].uv = (0.5 + loop.vert.co.x / (2 * r), 0.5 - loop.vert.co.y / (2 * r))
    for k in range(n):
        kn = (k + 1) % n
        side = bm.faces.new((top[k], bottom[k], bottom[kn], top[kn]))
        side.material_index = 2
        side.smooth = True
    me = bpy.data.meshes.new("PassDisc")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("PassDisc", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(face_material("Front", ARGS.front, 1.0))
    me.materials.append(face_material("Back", ARGS.back, 1.0))
    me.materials.append(copper_material())
    bevel = ob.modifiers.new("Edge", "BEVEL")
    bevel.width = DISC_DEPTH * 0.3
    bevel.segments = 3
    bevel.limit_method = "ANGLE"
    bevel.harden_normals = True
    return ob


def light(scene, name, loc, energy, color, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.size = energy, color, size
    ob = bpy.data.objects.new(name, data)
    ob.location = loc
    ob.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(ob)


def main():
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
    scene.render.resolution_x = scene.render.resolution_y = ARGS.px
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"  # painted faces keep their colours
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.035, 0.025, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    scene.world = world

    disc = build_disc()
    light(scene, "Key", (-1.6, 1.8, 2.6), 160, (1.0, 0.88, 0.72), 1.4)
    light(scene, "Rim", (2.0, -1.4, 0.8), 60, (1.0, 0.6, 0.32), 1.0)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.0  # the full button frame: half width 1.0
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0, 0, 5)
    scene.collection.objects.link(cam)
    scene.camera = cam

    os.makedirs(ARGS.out_dir, exist_ok=True)
    for i in range(FRAMES):
        disc.rotation_euler = (math.radians(360 * i / FRAMES), 0, 0)
        scene.render.filepath = os.path.join(ARGS.out_dir, f"tavern-pass-flip-{i:02d}.png")
        bpy.ops.render.render(write_still=True)
    print("WROTE", FRAMES, "frames to", ARGS.out_dir)


main()
