"""Render the Walnut Tavern UI kit's brass parts from straight above, on transparent
backgrounds, lit like the table (scripts/brand/tavern_table.py).

  blender -b -P scripts/brand/tavern_ui_kit.py -- --out-dir build_output/tavern/ui

Every part is modelled in points (1 Blender unit = 1 pt) and rendered at --scale px per pt,
so the app can slice it with exact cap insets (TavernUIKit in Board/TavernUIKit.swift):
  tavern-ui-frame        rounded brass trim, 96x96 pt, 9-slice (insets 24 pt), clear inside
  tavern-ui-capsule      riveted brass capsule rim, 44 pt tall, 3-slice: caps 22 pt, and the
                         12 pt middle holds one rivet pitch so it can tile as buttons widen
  tavern-ui-capsule-thin plain thin capsule rim for tags, 22 pt tall, 3-slice (caps 11 pt)
  tavern-ui-coin         brass coin blank for numbers, 30 pt
  tavern-ui-bullet       brass dome bullet, 12 pt
  tavern-ui-cap-left / tavern-ui-cap-right   ribbon end caps, 16x36 pt
  tavern-ui-seal         the wax-seal close button, 32 pt, from the Meshy model
                         ~/Movies/motion-assets/magicmobile-brand/meshy/wax-seal.glb (Pro, private)
"""

import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out-dir", required=True)
    p.add_argument("--scale", type=int, default=3)
    p.add_argument("--samples", type=int, default=64)
    return p.parse_args(argv)


ARGS = parse_args()


# --- materials ----------------------------------------------------------------------

def brass(name="Brass", tone=1.0):
    """Polished antique brass: bright on raised faces, dark in recesses (AO), like the table's."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    n, l = nt.nodes, nt.links
    bsdf = n["Principled BSDF"]
    bsdf.inputs["Metallic"].default_value = 1.0
    ao = n.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 2.0
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.12 * tone, 0.06 * tone, 0.015 * tone, 1)
    ramp.color_ramp.elements[1].color = (0.82 * tone, 0.52 * tone, 0.17 * tone, 1)
    l.new(ao.outputs["AO"], ramp.inputs["Fac"])
    l.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    noise = n.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.6
    rough = n.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.22
    rough.inputs["To Max"].default_value = 0.42
    l.new(noise.outputs["Fac"], rough.inputs["Value"])
    l.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    return mat


# --- geometry -----------------------------------------------------------------------

def rounded_rect(w, h, r, per_corner=16):
    """Points of a rounded rectangle centred on the origin, counter-clockwise."""
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
               (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)]
    for cx, cy, start in corners:
        for k in range(per_corner + 1):
            a = math.radians(start + 90 * k / per_corner)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def ring_mesh(name, w, h, r, band, depth, mat, bevel_frac=0.4):
    """A rounded-rectangle trim band: outer edge w x h, `band` wide, bevelled into a
    rounded profile so it reads as cast metal."""
    outer = rounded_rect(w, h, r)
    inner = rounded_rect(w - 2 * band, h - 2 * band, max(r - band, 0.5))
    bm = bmesh.new()
    top_o = [bm.verts.new((x, y, depth)) for x, y in outer]
    top_i = [bm.verts.new((x, y, depth)) for x, y in inner]
    bot_o = [bm.verts.new((x, y, 0)) for x, y in outer]
    bot_i = [bm.verts.new((x, y, 0)) for x, y in inner]
    n = len(outer)
    for k in range(n):
        kn = (k + 1) % n
        bm.faces.new((top_o[k], top_o[kn], top_i[kn], top_i[k]))
        bm.faces.new((bot_o[kn], bot_o[k], bot_i[k], bot_i[kn]))
        bm.faces.new((top_o[kn], top_o[k], bot_o[k], bot_o[kn]))
        bm.faces.new((top_i[k], top_i[kn], bot_i[kn], bot_i[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    bev = ob.modifiers.new("Round", "BEVEL")
    bev.width = band * bevel_frac
    bev.segments = 5
    bev.limit_method = "ANGLE"
    for p in me.polygons:
        p.use_smooth = True
    return ob


def rivet(x, y, z, radius, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=radius, location=(x, y, z))
    ob = bpy.context.active_object
    ob.scale.z = 0.55
    bpy.ops.object.shade_smooth()
    ob.data.materials.append(mat)
    return ob


def disc(name, radius, depth, mat, bevel):
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=radius, depth=depth, location=(0, 0, depth / 2))
    ob = bpy.context.active_object
    ob.name = name
    ob.data.materials.append(mat)
    mod = ob.modifiers.new("Round", "BEVEL")
    mod.width = bevel
    mod.segments = 5
    mod.limit_method = "ANGLE"
    bpy.ops.object.shade_smooth()
    return ob


def arrow_cap(mat, pointing_left=True):
    """A pennant-shaped brass end cap: a point on the outside, square on the ribbon side."""
    w, h = 16, 36
    s = -1 if pointing_left else 1
    shape = [(-w / 2, 0), (-w / 2 + 6, h / 2), (w / 2, h / 2), (w / 2, -h / 2), (-w / 2 + 6, -h / 2)]
    if not pointing_left:
        shape = [(-x, y) for x, y in shape]
    bm = bmesh.new()
    top = [bm.verts.new((x, y, 3)) for x, y in shape]
    bot = [bm.verts.new((x, y, 0)) for x, y in shape]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(shape)
    for k in range(n):
        kn = (k + 1) % n
        bm.faces.new((top[kn], top[k], bot[k], bot[kn]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Cap")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Cap", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    mod = ob.modifiers.new("Round", "BEVEL")
    mod.width = 1.4
    mod.segments = 4
    mod.limit_method = "ANGLE"
    rivet(s * -1.5, 0, 3.0, 2.6, mat)
    return ob


def meshy_flat(path, width):
    """Import a Meshy GLB, join it, lay it face-up (Meshy models flat props standing, front
    to -Y) and scale its footprint to `width`, centred on the origin."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    for o in meshes:
        world = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = world
    for o in [o for o in bpy.data.objects if o not in before and o.type != "MESH"]:
        bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.rotation_mode = "XYZ"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    dims = ob.dimensions
    thin = min(range(3), key=lambda i: dims[i])
    if thin == 1:
        ob.rotation_euler = (math.radians(-90), 0, 0)
    elif thin == 0:
        ob.rotation_euler = (0, math.radians(-90), 0)
    bpy.ops.object.transform_apply(rotation=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    k = width / max(ob.dimensions.x, ob.dimensions.y)
    ob.scale = (k, k, k)
    ob.location = (0, 0, ob.dimensions.z * k / 2)
    return ob


# --- scene --------------------------------------------------------------------------

def reset():
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
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.06, 0.04, 0.03, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.world = world
    # Key from the upper left and a warm low rim, like the table's sprites.
    for nm, loc, energy, color, size in [("Key", (-60, 70, 110), 0.8e5, (1.0, 0.86, 0.66), 60),
                                         ("Fill", (40, -20, 140), 0.25e5, (1.0, 0.9, 0.8), 90),
                                         ("Rim", (80, -60, 30), 0.25e5, (1.0, 0.6, 0.3), 40)]:
        data = bpy.data.lights.new(nm, "AREA")
        data.energy, data.color, data.size = energy, color, size
        light = bpy.data.objects.new(nm, data)
        light.location = loc
        light.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(light)
    return scene


def render(scene, name, w_pt, h_pt):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(w_pt, h_pt)
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0, 0, 200)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x = round(w_pt * ARGS.scale)
    scene.render.resolution_y = round(h_pt * ARGS.scale)
    scene.render.filepath = os.path.join(ARGS.out_dir, f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("WROTE", name)


def main():
    os.makedirs(ARGS.out_dir, exist_ok=True)

    # 9-slice panel frame: trim 6 pt wide, a rivet in each corner.
    scene = reset()
    mat = brass()
    ring_mesh("Frame", 94, 94, 12, 6, 4, mat)
    for sx in (-1, 1):
        for sy in (-1, 1):
            rivet(sx * 41.5, sy * 41.5, 4.2, 2.4, mat)
    render(scene, "tavern-ui-frame", 96, 96)

    # Riveted capsule: caps of 22 pt and one 12 pt rivet pitch between them.
    scene = reset()
    mat = brass()
    ring_mesh("Capsule", 55.6, 43, 21.5, 5, 4, mat)
    # Straight edges: one rivet per 12 pt pitch, centred in the tiling middle slice.
    rivet(0, 19.0, 4.0, 1.7, mat)
    rivet(0, -19.0, 4.0, 1.7, mat)
    # No rivet at the cap's middle: that row stretches when a button is taller than 44 pt.
    for side in (-1, 1):
        for a in (-55, 55):
            ang = math.radians(a)
            rivet(side * (6 + 19.0 * math.cos(ang)), 19.0 * math.sin(ang), 4.0, 1.7, mat)
    render(scene, "tavern-ui-capsule", 56, 44)

    # Thin capsule for tags: plain rim, a small rivet at each end.
    scene = reset()
    mat = brass()
    ring_mesh("Thin", 33.6, 21.4, 10.7, 2.6, 2.6, mat, bevel_frac=0.45)
    for side in (-1, 1):
        rivet(side * 11.3, 0, 2.6, 1.3, mat)
    render(scene, "tavern-ui-capsule-thin", 34, 22)

    # Coin blank with a raised rim.
    scene = reset()
    mat = brass("CoinBrass", tone=1.05)
    disc("Coin", 14.4, 3.0, mat, 1.2)
    ring_mesh("CoinRim", 28.8, 28.8, 14.4, 2.4, 4.4, mat, bevel_frac=0.5)
    render(scene, "tavern-ui-coin", 30, 30)

    # Dome bullet.
    scene = reset()
    mat = brass()
    rivet(0, 0, 0, 5.6, mat).scale.z = 0.7
    render(scene, "tavern-ui-bullet", 12, 12)

    # Wax-seal close button.
    seal = os.path.expanduser("~/Movies/motion-assets/magicmobile-brand/meshy/wax-seal.glb")
    if os.path.exists(seal):
        scene = reset()
        # Red wax reads dark under the brass lighting; lift it so the X stands out.
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.exposure = 0.9
        meshy_flat(seal, 30)
        render(scene, "tavern-ui-seal", 32, 32)

    # Ribbon end caps.
    for name, left in (("tavern-ui-cap-left", True), ("tavern-ui-cap-right", False)):
        scene = reset()
        arrow_cap(brass(), pointing_left=left)
        render(scene, name, 36, 36)


main()
