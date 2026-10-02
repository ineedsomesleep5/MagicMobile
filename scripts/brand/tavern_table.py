"""Walnut Tavern board: the table plate and the control sprites, rendered in Blender.

Everything is seen straight down through an orthographic camera, the way the board is
played. Layout comes from tavern_layout.json, the same points the app uses to place its
live controls, so a socket in the render always sits under its control.

    blender -b --python-exit-code 1 -P scripts/brand/tavern_table.py -- \
        --variant portrait --scale 3 --out-dir build_output/tavern

Inputs (all optional; missing ones fall back to procedural stand-ins):
  --textures  Poly Haven CC0 maps: black_walnut_veneer_02_*, brown_leather_* (diff/nor/rough)
  --props     Meshy models: medallion-frame.glb, crest.glb, hourglass-button.glb,
              corner-ornament.glb, candle.glb, tankard.glb, books.glb, coins.glb, ivy.glb,
              gem-blank.glb
  --emblem    compass-emblem.png, white lines on black, pressed into the leather

Outputs in --out-dir: tavern-<variant>.png (the plate) and transparent sprites the app layers
over its sockets: tavern-hourglass-button.png and tavern-mana-{W,U,B,R,G,C}.png.
scripts/brand/install_tavern_assets.sh copies them into the iOS asset catalog.
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    home = os.path.expanduser("~/Movies/motion-assets/magicmobile-brand")
    p = argparse.ArgumentParser()
    p.add_argument("--layout", default=os.path.join(HERE, "tavern_layout.json"))
    p.add_argument("--variant", default="portrait")
    p.add_argument("--scale", type=float, default=3)
    p.add_argument("--samples", type=int, default=128)
    p.add_argument("--textures", default=os.path.join(home, "textures"))
    p.add_argument("--props", default=os.path.join(home, "meshy"))
    p.add_argument("--emblem", default=os.path.join(home, "compass-emblem.png"))
    p.add_argument("--out-dir", required=True)
    p.add_argument("--skip-sprites", action="store_true")
    p.add_argument("--sprites-only", action="store_true")
    p.add_argument("--max-faces", type=int, default=60000)
    p.add_argument("--tooling", default=os.path.join(home, "tooled-leather-pattern.png"))
    return p.parse_args(argv)


ARGS = parse_args()
LAYOUT = json.load(open(ARGS.layout))[ARGS.variant]
SW, SH = LAYOUT["screen"]
U = 0.01                      # one point in scene units
W, H = SW * U, SH * U
FRAME_TOP = 0.10              # walnut frame height above the leather
MAT_Z = 0.0


def pt(x, y):
    """Layout point (top-left origin, y down) to scene XY (centered, y up)."""
    return (x * U - W / 2, H / 2 - y * U)


# --- materials -------------------------------------------------------------------

def node_mat(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat, nt, bsdf


def texture_set(stem):
    paths = {k: os.path.join(ARGS.textures, f"{stem}_{k}.jpg") for k in ("diff", "nor", "rough")}
    return paths if all(os.path.exists(p) for p in paths.values()) else None


def pbr_material(name, stem, tile, tint=(1, 1, 1), darken=1.0, rotate=0.0, rough_bias=0.0,
                 normal_strength=1.0, mottle=0.0):
    """Image-based material from a Poly Haven set, tiled every `tile` scene units."""
    maps = texture_set(stem)
    mat, nt, bsdf = node_mat(name)
    n, l = nt.nodes, nt.links
    if maps is None:
        print(f"[tavern] missing textures for {stem}; using flat colour")
        bsdf.inputs["Base Color"].default_value = (0.08 * tint[0], 0.04 * tint[1], 0.02 * tint[2], 1)
        bsdf.inputs["Roughness"].default_value = 0.5
        return mat
    coord = n.new("ShaderNodeTexCoord")
    mapping = n.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / tile, 1 / tile, 1)
    mapping.inputs["Rotation"].default_value = (0, 0, rotate)
    l.new(coord.outputs["Object"], mapping.inputs["Vector"])

    def img(key, non_color):
        t = n.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(maps[key])
        if non_color:
            t.image.colorspace_settings.name = "Non-Color"
        l.new(mapping.outputs["Vector"], t.inputs["Vector"])
        return t

    diff, nor, rough = img("diff", False), img("nor", True), img("rough", True)
    tint_node = n.new("ShaderNodeMix")
    tint_node.data_type = "RGBA"
    tint_node.blend_type = "MULTIPLY"
    tint_node.inputs["Factor"].default_value = 1.0
    l.new(diff.outputs["Color"], tint_node.inputs["A"])
    tint_node.inputs["B"].default_value = (tint[0] * darken, tint[1] * darken, tint[2] * darken, 1)
    color_out = tint_node.outputs["Result"]
    if mottle:
        # Broad, soft wear so a large surface never reads as one flat tile.
        wear = n.new("ShaderNodeTexNoise")
        wear.inputs["Scale"].default_value = 0.9
        wear.inputs["Detail"].default_value = 3
        l.new(coord.outputs["Object"], wear.inputs["Vector"])
        wear_ramp = n.new("ShaderNodeMapRange")
        wear_ramp.inputs["To Min"].default_value = 1 - mottle
        wear_ramp.inputs["To Max"].default_value = 1 + mottle * 0.4
        l.new(wear.outputs["Fac"], wear_ramp.inputs["Value"])
        worn = n.new("ShaderNodeMix")
        worn.data_type = "RGBA"
        worn.blend_type = "MULTIPLY"
        worn.inputs["Factor"].default_value = 1.0
        l.new(color_out, worn.inputs["A"])
        gray = n.new("ShaderNodeCombineColor")
        for ch in ("Red", "Green", "Blue"):
            l.new(wear_ramp.outputs["Result"], gray.inputs[ch])
        l.new(gray.outputs["Color"], worn.inputs["B"])
        color_out = worn.outputs["Result"]
    l.new(color_out, bsdf.inputs["Base Color"])
    rmap = n.new("ShaderNodeMath")
    rmap.operation = "ADD"
    rmap.use_clamp = True
    rmap.inputs[1].default_value = rough_bias
    l.new(rough.outputs["Color"], rmap.inputs[0])
    l.new(rmap.outputs["Value"], bsdf.inputs["Roughness"])
    nmap = n.new("ShaderNodeNormalMap")
    nmap.inputs["Strength"].default_value = normal_strength
    l.new(nor.outputs["Color"], nmap.inputs["Color"])
    l.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    mat["base_color_socket"] = tint_node.name
    return mat


def add_emblem(mat, center, size):
    """Press the compass emblem into a leather material: darker, slightly glossy grooves
    with a faint gold-leaf fill, mapped once over a square of `size` at `center`."""
    if not os.path.exists(ARGS.emblem):
        print("[tavern] no compass emblem; leather stays plain")
        return
    nt = mat.node_tree
    n, l = nt.nodes, nt.links
    bsdf = next(x for x in n if x.type == "BSDF_PRINCIPLED")
    base_link = bsdf.inputs["Base Color"].links[0]
    base_out = base_link.from_socket
    coord = n.new("ShaderNodeTexCoord")
    mapping = n.new("ShaderNodeMapping")
    mapping.inputs["Location"].default_value = (0.5 - center[0] / size, 0.5 - center[1] / size, 0)
    mapping.inputs["Scale"].default_value = (1 / size, 1 / size, 1)
    l.new(coord.outputs["Object"], mapping.inputs["Vector"])
    tex = n.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(ARGS.emblem)
    tex.image.colorspace_settings.name = "Non-Color"
    tex.extension = "CLIP"
    l.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    mask = n.new("ShaderNodeMath")
    mask.operation = "MULTIPLY"
    mask.inputs[1].default_value = 0.5
    l.new(tex.outputs["Color"], mask.inputs[0])
    gold = n.new("ShaderNodeMix")
    gold.data_type = "RGBA"
    l.new(mask.outputs["Value"], gold.inputs["Factor"])
    l.new(base_out, gold.inputs["A"])
    gold.inputs["B"].default_value = (0.15, 0.085, 0.032, 1)
    l.new(gold.outputs["Result"], bsdf.inputs["Base Color"])
    bump = n.new("ShaderNodeBump")
    bump.invert = True
    bump.inputs["Strength"].default_value = 0.45
    bump.inputs["Distance"].default_value = 0.003
    l.new(tex.outputs["Color"], bump.inputs["Height"])
    old_normal = bsdf.inputs["Normal"].links[0].from_socket if bsdf.inputs["Normal"].links else None
    if old_normal is not None:
        l.new(old_normal, bump.inputs["Normal"])
    l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def add_tooling(mat, tile, depth=0.5, gilt=0.25):
    """Press a tileable tooled pattern (white on black height map) into a material."""
    if not os.path.exists(ARGS.tooling):
        print("[tavern] no tooled pattern; bands stay plain")
        return
    nt = mat.node_tree
    n, l = nt.nodes, nt.links
    bsdf = next(x for x in n if x.type == "BSDF_PRINCIPLED")
    base_out = bsdf.inputs["Base Color"].links[0].from_socket
    coord = n.new("ShaderNodeTexCoord")
    mapping = n.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / tile, 1 / tile, 1)
    l.new(coord.outputs["Object"], mapping.inputs["Vector"])
    tex = n.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(ARGS.tooling)
    tex.image.colorspace_settings.name = "Non-Color"
    l.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    # The generator draws the lines as opaque white on transparent: the height is in alpha.
    height = tex.outputs["Alpha"] if tex.image.channels == 4 else tex.outputs["Color"]
    mix = n.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    fac = n.new("ShaderNodeMath")
    fac.operation = "MULTIPLY"
    fac.inputs[1].default_value = gilt
    l.new(height, fac.inputs[0])
    l.new(fac.outputs["Value"], mix.inputs["Factor"])
    l.new(base_out, mix.inputs["A"])
    mix.inputs["B"].default_value = (0.45, 0.28, 0.10, 1)
    l.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = depth
    bump.inputs["Distance"].default_value = 0.002
    l.new(height, bump.inputs["Height"])
    if bsdf.inputs["Normal"].links:
        l.new(bsdf.inputs["Normal"].links[0].from_socket, bump.inputs["Normal"])
    l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def rivet_rail(x0, y0, x1, y1, z, brass, pitch=0.3):
    """A thin brass strip with domed rivets, run along the frame from (x0, y0) to (x1, y1)."""
    length = math.hypot(x1 - x0, y1 - y0)
    horiz = abs(y1 - y0) < 1e-6
    strip = box("RivetRail", (x0 + x1) / 2, (y0 + y1) / 2, z, length if horiz else 0.03, 0.03 if horiz else length,
                0.008, brass)
    bevel(strip, 0.003, 2)
    count = max(int(length / pitch), 1)
    for i in range(count + 1):
        t = i / count
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.016, segments=16, ring_count=8,
                                             location=(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z + 0.006))
        bpy.context.active_object.data.materials.append(brass)


def brass_material(name="Brass", tone=1.0, rough=(0.34, 0.58)):
    """Antique brass: bright on the raised faces, dark and rough in the recesses (AO)."""
    mat, nt, bsdf = node_mat(name)
    n, l = nt.nodes, nt.links
    bsdf.inputs["Metallic"].default_value = 1.0
    ao = n.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.03
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.16 * tone, 0.09 * tone, 0.03 * tone, 1)
    ramp.color_ramp.elements[1].color = (0.86 * tone, 0.62 * tone, 0.28 * tone, 1)
    l.new(ao.outputs["AO"], ramp.inputs["Fac"])
    l.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    noise = n.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 40
    rmap = n.new("ShaderNodeMapRange")
    rmap.inputs["To Min"].default_value = rough[0]
    rmap.inputs["To Max"].default_value = rough[1]
    l.new(noise.outputs["Fac"], rmap.inputs["Value"])
    l.new(rmap.outputs["Result"], bsdf.inputs["Roughness"])
    return mat


def flat_material(name, color, rough=0.6, metallic=0.0, emission=None, strength=0.0):
    mat, _, bsdf = node_mat(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


# --- geometry ----------------------------------------------------------------------

def box(name, cx, cy, cz, sx, sy, sz, mat):
    bpy.ops.mesh.primitive_cube_add(location=(cx, cy, cz))
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (sx / 2, sy / 2, sz / 2)
    bpy.ops.object.transform_apply(scale=True)
    ob.data.materials.append(mat)
    return ob


def bevel(ob, width, segments=3):
    mod = ob.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    return mod


def smooth(ob):
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    except Exception:
        bpy.ops.object.shade_smooth()
    ob.select_set(False)


def cut(target, cutter):
    mod = target.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier="Cut")
    bpy.data.objects.remove(cutter)


def cylinder(name, x, y, z, r, depth, mat, verts=96):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=(x, y, z))
    ob = bpy.context.active_object
    ob.name = name
    if mat:
        ob.data.materials.append(mat)
    return ob


def ring(name, x, y, z, r_out, r_in, depth, mat):
    ob = cylinder(name, x, y, z, r_out, depth, mat)
    cut(ob, cylinder(name + "-hole", x, y, z, r_in, depth * 3, None))
    bevel(ob, min(0.006, (r_out - r_in) * 0.3), 3)
    smooth(ob)
    return ob


def socket(name, center, radius, surfaces, brass, floor):
    """A round recess in the frame: dark floor, brass lip, cut through the walnut."""
    x, y = pt(*center)
    r = radius * U
    for surface in surfaces:
        cut(surface, cylinder(name + "-cut", x, y, FRAME_TOP, r + 0.006, 0.08, None))
    ring(name + "-lip", x, y, FRAME_TOP + 0.006, r + 0.05, r + 0.004, 0.024, brass)
    cylinder(name + "-floor", x, y, FRAME_TOP - 0.035, r + 0.01, 0.01, floor)
    return (x, y, r)


def stitches(x0, y0, x1, y1, pitch, mat):
    length, width, height = pitch * 0.55, 0.011, 0.005
    parts = []

    def run(xa, ya, xb, yb):
        horiz = abs(yb - ya) < 1e-6
        count = int(math.hypot(xb - xa, yb - ya) / pitch)
        for i in range(count + 1):
            t = i / max(count, 1)
            x, y = xa + (xb - xa) * t, ya + (yb - ya) * t
            sx, sy = (length, width) if horiz else (width, length)
            parts.append(box("Stitch", x, y, MAT_Z + height / 2, sx, sy, height, mat))
    run(x0 + pitch, y0, x1 - pitch, y0)
    run(x0 + pitch, y1, x1 - pitch, y1)
    run(x0, y0 + pitch, x0, y1 - pitch)
    run(x1, y0 + pitch, x1, y1 - pitch)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()


_PROP_CACHE = {}


def _load_template(path, flat):
    """Import a Meshy GLB once, joined, laid face-up (flat props) and centred; later
    placements are linked copies so repeated props cost no extra memory."""
    key = (path, flat)
    if key in _PROP_CACHE:
        return _PROP_CACHE[key]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    # The importer's Y-up to Z-up turn can live on a parent empty: bake each mesh's world
    # transform before dropping the empties.
    bpy.context.view_layer.update()
    for o in new:
        world = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = world
    for o in [o for o in bpy.data.objects if o not in before and o.type != "MESH"]:
        bpy.data.objects.remove(o)
    if not new:
        _PROP_CACHE[key] = None
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.parent = None
    # glTF imports use quaternion rotation, which ignores rotation_euler.
    ob.rotation_mode = "XYZ"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Meshy models a flat prop standing up, facing the viewer; lay it face-up by turning
    # its thinnest bounding axis to the scene's Z. Upright props keep the importer's Z-up.
    dims = ob.dimensions
    thin = min(range(3), key=lambda i: dims[i])
    if flat and thin == 1:
        # The front faces -Y after import; tip it back so the front looks up, top edge north.
        ob.rotation_euler = (math.radians(-90), 0, 0)
    elif flat and thin == 0:
        ob.rotation_euler = (0, math.radians(-90), 0)
    bpy.ops.object.transform_apply(rotation=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    # Meshy meshes carry far more triangles than a small prop seen from above needs;
    # thinning them keeps renders fast and memory low on the 8 GB Mac.
    faces = len(ob.data.polygons)
    if faces > ARGS.max_faces:
        mod = ob.modifiers.new("Thin", "DECIMATE")
        mod.ratio = ARGS.max_faces / faces
        bpy.ops.object.modifier_apply(modifier="Thin")
    ob.location = (0, 0, -50)
    ob.hide_render = True
    ob.hide_viewport = True
    _PROP_CACHE[key] = ob
    return ob


def import_prop(path, width, center, z, rotate_deg=0.0, mirror_x=False, mirror_y=False, flat=True):
    """Place a Meshy prop on the table with its footprint scaled to `width`."""
    if not os.path.exists(path):
        print(f"[tavern] prop missing: {os.path.basename(path)}")
        return None
    template = _load_template(path, flat)
    if template is None:
        return None
    ob = template.copy()
    bpy.context.scene.collection.objects.link(ob)
    ob.hide_render = False
    ob.hide_viewport = False
    s = width / max(template.dimensions.x, template.dimensions.y)
    ob.scale = (s * (-1 if mirror_x else 1), s * (-1 if mirror_y else 1), s)
    ob.rotation_euler = (0, 0, math.radians(rotate_deg))
    ob.location = (center[0], center[1], z + template.dimensions.z * s / 2)
    return ob


# --- scene -------------------------------------------------------------------------

def reset():
    _PROP_CACHE.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)


def lights(scene, mat_center_y):
    def light(name, kind, loc, energy, color, size=None, target=None):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        data.color = color
        if size is not None:
            if kind == "AREA":
                data.size = size
            else:
                data.shadow_soft_size = size
        ob = bpy.data.objects.new(name, data)
        ob.location = loc
        scene.collection.objects.link(ob)
        if kind in ("AREA", "SPOT"):
            aim = Vector(target or (0, 0, 0))
            ob.rotation_euler = (aim - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        return ob

    area = W * H
    # Hanging lamp: a warm pool on the leather that falls off toward the frame.
    lamp = light("Lamp", "SPOT", (0.1, mat_center_y + 0.4, 9.0), 5200 * area / 42, (1.0, 0.80, 0.56),
                 size=1.4, target=(0, mat_center_y, 0))
    lamp.data.spot_size = math.radians(44 if H >= W else 58)
    lamp.data.spot_blend = 1.0
    light("Fill", "AREA", (0, 0, 9.0), 105 * area / 42, (1.0, 0.84, 0.66), size=max(W, H) * 1.2)
    # The near rail, where the hand and controls rest, gets its own low warm light.
    light("NearRail", "AREA", (0, -H / 2 - 0.8, 2.2), 150 * area / 42, (1.0, 0.70, 0.45), size=W,
          target=(0, -H / 2 + 1.4, 0))
    # The far corners, where the books and candle sit, get warm light from just off the table.
    light("FarLeft", "AREA", (-W * 0.7, H * 0.55, 1.8), 60 * area / 42, (1.0, 0.62, 0.34), size=1.6,
          target=(-W * 0.3, H * 0.42, 0))
    light("FarRight", "AREA", (W * 0.7, H * 0.55, 1.8), 60 * area / 42, (1.0, 0.68, 0.42), size=1.6,
          target=(W * 0.3, H * 0.42, 0))
    # Low grazing key from the top-left so carving and grain read from straight above.
    light("Graze", "AREA", (-W * 0.9, H * 0.7, 1.4), 70 * area / 42, (1.0, 0.75, 0.5), size=2.0)
    return light


def rect_scene(r):
    """Layout rect [x0, y0, x1, y1] in points to scene (x0, y0, x1, y1) with y up."""
    (x0, y1), (x1, y0) = pt(r[0], r[1]), pt(r[2], r[3])
    return x0, y0, x1, y1


def inset_panel(name, r, z, depth, mat, brass, edge=0.018):
    """A recessed panel (leather band, play mat) with a raised brass edge around it."""
    x0, y0, x1, y1 = rect_scene(r)
    box(name, (x0 + x1) / 2, (y0 + y1) / 2, z - depth / 2, x1 - x0, y1 - y0, depth, mat)
    trim = box(name + "Trim", (x0 + x1) / 2, (y0 + y1) / 2, z + 0.006, x1 - x0 + edge * 2, y1 - y0 + edge * 2, 0.016, brass)
    cut(trim, box(name + "TrimHole", (x0 + x1) / 2, (y0 + y1) / 2, z, x1 - x0, y1 - y0, 0.2, brass))
    bevel(trim, 0.005, 2)
    return x0, y0, x1, y1


def prop_at(path, spec, z, flat=True):
    x, y = pt(*spec["at"])
    return import_prop(path, spec["width"] * U, (x, y), z, rotate_deg=spec.get("rotate", 0.0), flat=flat)


def inner_radius(ob):
    """Radius of the empty centre of a ring-shaped prop, from its vertices."""
    cx, cy = ob.location.x, ob.location.y
    world = ob.matrix_world
    radii = [math.hypot((world @ v.co).x - cx, (world @ v.co).y - cy) for v in ob.data.vertices]
    return min(radii) if radii else 0.0


def ring_prop(path, center, hole_radius, z):
    """Place a ring prop (the Meshy medallion frame) so its hole matches the socket."""
    x, y = pt(*center)
    ob = import_prop(path, 1.0, (x, y), z)
    if ob is None:
        return None
    bpy.context.view_layer.update()
    inner = inner_radius(ob)
    if inner > 0.01:
        k = hole_radius * U / inner
        height = ob.dimensions.z
        ob.scale = (ob.scale[0] * k, ob.scale[1] * k, ob.scale[2] * k)
        ob.location.z = z + height * k / 2
    return ob


def build_mana_rail(spec, brass, floor):
    """The gem rail as in the concept: a dark recessed tray with a riveted brass border
    and a brass-rimmed cup for each mana gem."""
    x0, y0, x1, y1 = rect_scene(spec["rect"])
    cx, cy, w, h = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
    box("ManaRailFloor", cx, cy, FRAME_TOP + 0.004, w, h, 0.008, floor)
    border = box("ManaRailBorder", cx, cy, FRAME_TOP + 0.016, w + 0.03, h + 0.03, 0.018, brass)
    cut(border, box("ManaRailHole", cx, cy, FRAME_TOP, w - 0.02, h - 0.02, 0.2, brass))
    bevel(border, 0.004, 2)
    for rx in (x0 + 0.004, x1 - 0.004):
        for ry in (y0 + 0.004, y1 - 0.004):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.012, segments=16, ring_count=8, location=(rx, ry, FRAME_TOP + 0.028))
            bpy.context.active_object.data.materials.append(brass)
    # No cups of its own: each gem's brass bezel (a sprite in the app) is its cup, so
    # nothing peeks out around a gem that sits slightly off a painted rim.


def build_table(scene):
    L = LAYOUT
    planks = pbr_material("Planks", "dark_wooden_planks", tile=3.2, tint=(1.0, 0.72, 0.50), darken=0.9,
                          normal_strength=0.6)
    walnut = pbr_material("Walnut", "black_walnut_veneer_02", tile=2.2, tint=(1.0, 0.80, 0.62), darken=0.7)
    leather = pbr_material("Leather", "brown_leather", tile=2.0, tint=(1.0, 0.74, 0.56), darken=0.95,
                           rough_bias=0.22, normal_strength=0.35, mottle=0.35)
    red = pbr_material("RedLeather", "leather_red_02", tile=1.6, tint=(1.0, 0.40, 0.32), darken=0.72,
                       rough_bias=0.15, normal_strength=0.4, mottle=0.25)
    add_tooling(red, tile=0.42)
    brass = brass_material()
    floor = flat_material("SocketFloor", (0.018, 0.010, 0.006), rough=0.9)

    # The whole table: worn planks; then a raised carved walnut frame around the mat.
    box("Table", 0, 0, -0.06, W + 1.0, H + 1.0, 0.04, planks)
    mx0, my0, mx1, my1 = rect_scene(L["mat"])
    frame_w = 0.13
    frame = box("Frame", (mx0 + mx1) / 2, (my0 + my1) / 2, FRAME_TOP / 2 - 0.02,
                mx1 - mx0 + frame_w * 2, my1 - my0 + frame_w * 2, FRAME_TOP + 0.04, walnut)
    cut(frame, box("FrameHole", (mx0 + mx1) / 2, (my0 + my1) / 2, 0, mx1 - mx0, my1 - my0, 1.0, walnut))
    bevel(frame, 0.035, 4)
    smooth(frame)
    mat_cy = (my0 + my1) / 2
    rail_z = FRAME_TOP + 0.024
    off = frame_w * 0.55
    rivet_rail(mx0 - off, my0 - off, mx0 - off, my1 + off, rail_z, brass)
    rivet_rail(mx1 + off, my0 - off, mx1 + off, my1 + off, rail_z, brass)
    add_emblem(leather, (0, mat_cy), min(mx1 - mx0, my1 - my0) * 0.56)
    inset_panel("Mat", L["mat"], MAT_Z, 0.04, leather, brass)
    stitches(mx0 + 0.07, my0 + 0.07, mx1 - 0.07, my1 - 0.07, 0.058,
             flat_material("Thread", (0.52, 0.36, 0.17), rough=0.85))

    # Red tooled-leather bands: behind the opponent's crest and where your hand rests.
    inset_panel("TopBand", L["topBand"], FRAME_TOP + 0.004, 0.02, red, brass)
    inset_panel("HandBand", L["handBand"], FRAME_TOP + 0.004, 0.02, red, brass)

    # Carved brass corner ornaments on the mat corners.
    orn = os.path.join(ARGS.props, "corner-ornament.glb")
    size = 0.56
    for (cx, cy, mxr, myr) in [(mx0, my1, False, False), (mx1, my1, True, False),
                               (mx0, my0, False, True), (mx1, my0, True, True)]:
        ox = cx + (size / 2 - 0.03) * (-1 if mxr else 1)
        oy = cy + (size / 2 - 0.03) * (1 if myr else -1)
        import_prop(orn, size, (ox, oy), MAT_Z + 0.004, mirror_x=mxr, mirror_y=myr)

    # The opponent's crest and your medallion ring; the app draws portraits in their holes.
    crest = L["crest"]
    cx, cy = pt(*crest["center"])
    if import_prop(os.path.join(ARGS.props, "crest.glb"), crest["width"] * U, (cx, cy), FRAME_TOP + 0.02) is None:
        ring_prop(os.path.join(ARGS.props, "medallion-frame.glb"), crest["center"],
                  L["opponentMedallion"]["radius"], FRAME_TOP + 0.02)
    ring_prop(os.path.join(ARGS.props, "medallion-frame.glb"), L["lifeMedallion"]["center"],
              L["lifeMedallion"]["radius"], FRAME_TOP)
    for key in ("opponentMedallion", "lifeMedallion"):
        x, y = pt(*L[key]["center"])
        cylinder(key + "Floor", x, y, FRAME_TOP + 0.002, L[key]["radius"] * U * 1.02, 0.006, floor)

    # The pass socket: just a dark recess. The button sprite brings its own riveted brass
    # ring, so a second lip here would double it.
    px, py = pt(*L["passButton"]["center"])
    pr = L["passButton"]["radius"] * U
    cylinder("PassFloor", px, py, FRAME_TOP + 0.002, pr * 1.04, 0.006, floor)

    build_mana_rail(L["manaRail"], brass, floor)

    props = L.get("props", {})
    if "candle" in props:
        candle = prop_at(os.path.join(ARGS.props, "candle.glb"), props["candle"], FRAME_TOP, flat=False)
        x, y = pt(*props["candle"]["at"])
        glow = bpy.data.lights.new("CandleLight", "POINT")
        glow.energy, glow.color, glow.shadow_soft_size = 45, (1.0, 0.55, 0.22), 0.2
        g = bpy.data.objects.new("CandleLight", glow)
        g.location = (x + 0.12, y - 0.12, FRAME_TOP + 1.1)
        scene.collection.objects.link(g)
    if "tankard" in props:
        prop_at(os.path.join(ARGS.props, "tankard.glb"), props["tankard"], FRAME_TOP, flat=False)
    if "books" in props:
        prop_at(os.path.join(ARGS.props, "books.glb"), props["books"], FRAME_TOP, flat=False)
    for spec in props.get("coins", []):
        prop_at(os.path.join(ARGS.props, "coins.glb"), spec, FRAME_TOP, flat=False)
    for spec in props.get("ivy", []):
        prop_at(os.path.join(ARGS.props, "ivy.glb"), spec, FRAME_TOP + 0.01, flat=False)
    return mat_cy


def setup_render(scene, res_x, res_y, transparent=False, samples=None):
    r = scene.render
    r.engine = "CYCLES"
    r.resolution_x, r.resolution_y = res_x, res_y
    r.resolution_percentage = 100
    r.film_transparent = transparent
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA" if transparent else "RGB"
    scene.cycles.samples = samples or ARGS.samples
    scene.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = "GPU"
    except Exception as exc:
        print("[tavern] GPU unavailable:", exc)
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"


def ortho_camera(scene, span, horizontal):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span
    cam_data.sensor_fit = "HORIZONTAL" if horizontal else "VERTICAL"
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0, 0, 20)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def world(scene, strength=0.25):
    w = bpy.data.worlds.new("World")
    scene.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.008, 0.006, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = strength


def render_plate():
    reset()
    scene = bpy.context.scene
    world(scene)
    mat_cy = build_table(scene)
    lights(scene, mat_cy)
    ortho_camera(scene, H if H >= W else W, horizontal=W > H)
    setup_render(scene, round(SW * ARGS.scale), round(SH * ARGS.scale))
    out = os.path.join(ARGS.out_dir, f"tavern-{ARGS.variant}.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("WROTE", out)


MANA_TINTS = {
    "W": (1.0, 0.93, 0.72), "U": (0.06, 0.26, 1.0), "B": (0.34, 0.10, 0.52),
    "R": (0.95, 0.05, 0.03), "G": (0.04, 0.60, 0.14), "C": (0.52, 0.55, 0.62),
    # Generic costs: a smoky stone with no glyph; the app engraves the number on it.
    "generic": (0.40, 0.38, 0.42),
}


def glyph_svg(symbol):
    """The app's own mana symbol (Assets.xcassets/mana-x.svg) with its coloured disc removed,
    leaving only the glyph. The disc is a <circle> in some files and a path id='Shape' in others."""
    import re
    import tempfile
    src = os.path.join(HERE, "..", "..", "apps", "ios", "MagicMobile", "Assets.xcassets",
                       f"mana-{symbol.lower()}.imageset", f"mana-{symbol.lower()}.svg")
    svg = re.sub(r"<circle[^>]*/>|<path[^>]*id='Shape'[^>]*/>", "", open(src).read(), count=1)
    out = os.path.join(tempfile.gettempdir(), f"tavern-glyph-{symbol}.svg")
    open(out, "w").write(svg)
    return out


def import_glyph(symbol, size, z, mat):
    """Import the glyph as curves, give it a little depth and lay it on the gem's top."""
    import addon_utils
    addon_utils.enable("io_curve_svg", default_set=False)
    before = set(bpy.data.objects)
    bpy.ops.import_curve.svg(filepath=glyph_svg(symbol))
    curves = [o for o in bpy.data.objects if o not in before and o.type == "CURVE"]
    if not curves:
        return None
    span = max(max(c.dimensions.x, c.dimensions.y) for c in curves)
    bpy.ops.object.select_all(action="DESELECT")
    for c in curves:
        c.data.extrude = span * 0.04
        c.data.bevel_depth = span * 0.006
        c.select_set(True)
    bpy.context.view_layer.objects.active = curves[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    ob = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    k = size / max(ob.dimensions.x, ob.dimensions.y)
    ob.scale = (k, k, k)
    ob.location = (0, 0, z + ob.dimensions.z * k / 2)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def seat_crystal(gem, color):
    """Swap the Meshy gem's moulded dome for a cut crystal: delete the dome inside the brass
    bezel, lay a coloured foil seat in the cup and set a flat-shaded brilliant-style crown
    (octagonal table, star, kite and girdle facets) of refractive glass on it. Returns the
    height of the table, where the glyph goes."""
    import bmesh
    me = gem.data
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    R = max(max(xs) - min(xs), max(ys) - min(ys)) / 2
    z0, h = min(zs), max(zs) - min(zs)
    # Measured profile of gem-blank.glb: the dome fills r < 0.78 R above 0.59 h, the bezel
    # lip rises to 0.59 h at 0.80-0.85 R.
    bm = bmesh.new()
    bm.from_mesh(me)
    doomed = [f for f in bm.faces
              if all(math.hypot(v.co.x - cx, v.co.y - cy) < 0.77 * R and v.co.z > z0 + 0.45 * h for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(me)
    bm.free()

    s = gem.scale.x
    wx, wy = gem.location.x + cx * s, gem.location.y + cy * s
    wz0, wh, wR = gem.location.z + z0 * s, h * s, R * s
    foil = flat_material("CrystalFoil", tuple(0.25 + 0.6 * c for c in color), rough=0.18, metallic=1.0)
    cylinder("CrystalSeat", wx, wy, wz0 + 0.50 * wh, 0.80 * wR, 0.01 * wh, foil, verts=64)

    g, zg, zt = 0.81 * wR, wz0 + 0.60 * wh, wz0 + 0.97 * wh
    zs_ = zt - 0.42 * (zt - zg)
    bm = bmesh.new()
    def ring(n, r, z, phase):
        return [bm.verts.new((wx + r * math.cos(math.radians(phase + k * 360 / n)),
                              wy + r * math.sin(math.radians(phase + k * 360 / n)), z)) for k in range(n)]
    T = ring(8, 0.50 * g, zt, 22.5)       # table corners
    S = ring(8, 0.76 * g, zs_, 0.0)       # star points, between table corners
    G = ring(16, g, zg, 0.0)              # girdle, top edge
    B = ring(16, g, zg - 0.04 * wh, 0.0)  # girdle, bottom edge
    bm.faces.new(T)
    for j in range(8):
        jn = (j + 1) % 8
        bm.faces.new((T[j], T[jn], S[jn]))                       # star
        bm.faces.new((S[j], G[2 * j + 1], S[jn], T[j]))          # kite
        bm.faces.new((S[j], G[2 * j], G[2 * j + 1]))             # upper girdle
        bm.faces.new((S[jn], G[2 * j + 1], G[(2 * j + 2) % 16]))
    for k in range(16):
        kn = (k + 1) % 16
        bm.faces.new((G[k], B[k], B[kn], G[kn]))
    bm.faces.new(list(reversed(B)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    cm = bpy.data.meshes.new("Crystal")
    bm.to_mesh(cm)
    bm.free()
    crystal = bpy.data.objects.new("Crystal", cm)
    bpy.context.scene.collection.objects.link(crystal)
    glass, _, bsdf = node_mat("CrystalGlass")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.0
    bsdf.inputs["IOR"].default_value = 1.8
    bsdf.inputs["Emission Color"].default_value = (*color, 1)
    bsdf.inputs["Emission Strength"].default_value = 0.06
    cm.materials.append(glass)
    return zt


def sprite_lights(scene):
    for nm, kind, loc, energy, color, sz in [
        ("Key", "AREA", (-0.8, 0.9, 2.5), 180, (1.0, 0.85, 0.65), 1.5),
        ("Fill", "AREA", (0.6, -0.4, 3.0), 60, (1.0, 0.9, 0.8), 2.0),
        ("Rim", "AREA", (1.2, 1.2, 0.6), 50, (1.0, 0.6, 0.3), 1.0),
    ]:
        data = bpy.data.lights.new(nm, kind)
        data.energy, data.color, data.size = energy, color, sz
        ob = bpy.data.objects.new(nm, data)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(ob)


def render_gem_sprite(symbol, diameter_pt):
    path = os.path.join(ARGS.props, "gem-blank.glb")
    if not os.path.exists(path):
        print("[tavern] gem sprites skipped, missing gem-blank.glb")
        return
    reset()
    scene = bpy.context.scene
    world(scene, 0.4)
    gem = import_prop(path, 1.0, (0, 0), 0, flat=False)
    table = seat_crystal(gem, MANA_TINTS[symbol])
    if symbol != "generic":
        # Pale gold that reads on any stone: part metal, a touch of its own light.
        inlay = flat_material("GlyphGold", (1.0, 0.80, 0.42), rough=0.4, metallic=0.35,
                              emission=(1.0, 0.72, 0.32), strength=0.35)
        import_glyph(symbol, 0.40, table + 0.002, inlay)
    # No light near the camera axis: the flat table facet would mirror it as a pale patch
    # behind the glyph. Key from the upper left, warm rim from the lower right.
    for nm, loc, energy, color, sz in [("Key", (-1.4, 1.6, 1.9), 220, (1.0, 0.88, 0.70), 1.2),
                                       ("Rim", (1.9, -1.4, 0.35), 70, (1.0, 0.62, 0.32), 0.8)]:
        data = bpy.data.lights.new(nm, "AREA")
        data.energy, data.color, data.size = energy, color, sz
        light = bpy.data.objects.new(nm, data)
        light.location = loc
        light.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(light)
    # Small lights low around the gem: from straight above, the steep kite and star facets
    # only flash when lit from near the horizon, so each one catches a different light.
    for i, (az, el, energy) in enumerate([(30, 12, 60), (150, 18, 45), (260, 10, 55), (340, 35, 10), (95, 40, 12)]):
        data = bpy.data.lights.new(f"Glint{i}", "AREA")
        data.energy, data.size, data.color = energy, 0.25, (1.0, 0.95, 0.88)
        glint = bpy.data.objects.new(f"Glint{i}", data)
        a, e = math.radians(az), math.radians(el)
        glint.location = (2.2 * math.cos(e) * math.cos(a), 2.2 * math.cos(e) * math.sin(a), 2.2 * math.sin(e))
        glint.rotation_euler = (Vector((0, 0, 0)) - glint.location).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(glint)
    ortho_camera(scene, 1.04, horizontal=True)
    px = round(diameter_pt * ARGS.scale * 1.04)
    setup_render(scene, px, px, transparent=True, samples=96)
    out = os.path.join(ARGS.out_dir, f"tavern-mana-{symbol}.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("WROTE", out)


def render_sprite(glb, name, diameter_pt, flat=True):
    """One control, alone, from straight above, on a transparent background."""
    path = os.path.join(ARGS.props, glb)
    if not os.path.exists(path):
        print(f"[tavern] sprite skipped, missing {glb}")
        return
    reset()
    scene = bpy.context.scene
    world(scene, 0.4)
    size = 1.0
    import_prop(path, size, (0, 0), 0, flat=flat)
    sprite_lights(scene)
    ortho_camera(scene, size * 1.04, horizontal=True)
    px = round(diameter_pt * ARGS.scale * 1.04)
    setup_render(scene, px, px, transparent=True, samples=96)
    out = os.path.join(ARGS.out_dir, f"{name}.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("WROTE", out)


os.makedirs(ARGS.out_dir, exist_ok=True)
if not ARGS.sprites_only:
    render_plate()
if not ARGS.skip_sprites:
    # The medallion rings and crest are part of the plate; only the hourglass is a sprite,
    # so the app can press, tilt and glow it.
    # A stand-in pass button; install_tavern_assets.sh swaps in the painted porthole button
    # (pass-button-art.png) when it is present.
    render_sprite("hourglass-button.glb", "tavern-hourglass-button", LAYOUT["passButton"]["radius"] * 2)
    # Six gems from one blank stone: same shape and size, each with its real mana glyph.
    for symbol in ["W", "U", "B", "R", "G", "C", "generic"]:
        render_gem_sprite(symbol, 30)
