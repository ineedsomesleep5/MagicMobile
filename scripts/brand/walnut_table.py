"""Walnut & Ember board table, built and rendered headlessly in Blender (superseded concept).

Kept for history: scripts/brand/tavern_table.py, driven by tavern_layout.json, replaced it for the
shipped Walnut Tavern plates.

Proof of concept for the Blender-baked board route: one procedural scene (no downloaded
textures or paid assets), rendered from the game's own fixed top-down camera to a
backdrop image the native board draws behind its cards.

    blender -b --python-exit-code 1 -P scripts/brand/walnut_table.py -- \
        --width 440 --height 956 --scale 3 --out build_output/walnut/portrait.png

Scene units are points / 100, so 4.40 x 9.56 is an iPhone 17 Pro Max in portrait.
Insets (also in points) put the thick frame in the safe areas and keep the leather
play area where the battlefield rows sit.
"""

import argparse
import math
import sys

import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--width", type=float, default=440)
    p.add_argument("--height", type=float, default=956)
    p.add_argument("--scale", type=float, default=3)
    p.add_argument("--inset-top", type=float, default=56)
    p.add_argument("--inset-bottom", type=float, default=30)
    p.add_argument("--inset-side", type=float, default=12)
    p.add_argument("--samples", type=int, default=96)
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


ARGS = parse_args()
U = 0.01  # one point in scene units
W, H = ARGS.width * U, ARGS.height * U
FRAME_H = 0.16   # frame rises this far above the leather
MAT_Z = 0.0


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


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


def walnut_material(name, grain_scale=1.0, tone=1.0, along_y=False):
    mat, nt, bsdf = node_mat(name)
    n, l = nt.nodes, nt.links
    coord = n.new("ShaderNodeTexCoord")
    mapping = n.new("ShaderNodeMapping")
    # Long grain: squash coordinates along the plank so features stretch along it.
    stretch = (3.0, 0.22, 1) if along_y else (0.22, 3.0, 1)
    mapping.inputs["Scale"].default_value = tuple(s * grain_scale for s in stretch)
    l.new(coord.outputs["Object"], mapping.inputs["Vector"])

    warp = n.new("ShaderNodeTexNoise")
    warp.inputs["Scale"].default_value = 1.6
    warp.inputs["Detail"].default_value = 4
    l.new(mapping.outputs["Vector"], warp.inputs["Vector"])
    mix_vec = n.new("ShaderNodeMix")
    mix_vec.data_type = "VECTOR"
    mix_vec.inputs["Factor"].default_value = 0.35
    l.new(mapping.outputs["Vector"], mix_vec.inputs["A"])
    l.new(warp.outputs["Color"], mix_vec.inputs["B"])

    wave = n.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X" if along_y else "Y"
    wave.inputs["Scale"].default_value = 2.2
    wave.inputs["Distortion"].default_value = 6
    wave.inputs["Detail"].default_value = 3
    wave.inputs["Detail Scale"].default_value = 1.5
    l.new(mix_vec.outputs["Result"], wave.inputs["Vector"])

    fine = n.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 60
    fine.inputs["Detail"].default_value = 8
    l.new(mapping.outputs["Vector"], fine.inputs["Vector"])

    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (0.030 * tone, 0.014 * tone, 0.007 * tone, 1)
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = (0.150 * tone, 0.072 * tone, 0.032 * tone, 1)
    mid = ramp.color_ramp.elements.new(0.55)
    mid.color = (0.085 * tone, 0.040 * tone, 0.018 * tone, 1)
    combine = n.new("ShaderNodeMath")
    combine.operation = "MULTIPLY_ADD"
    combine.inputs[1].default_value = 0.85
    l.new(wave.outputs["Fac"], combine.inputs[0])
    l.new(fine.outputs["Fac"], combine.inputs[2])
    clamp = n.new("ShaderNodeClamp")
    l.new(combine.outputs["Value"], clamp.inputs["Value"])
    l.new(clamp.outputs["Result"], ramp.inputs["Fac"])
    l.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])

    bsdf.inputs["Roughness"].default_value = 0.42
    bsdf.inputs["Coat Weight"].default_value = 0.35
    bsdf.inputs["Coat Roughness"].default_value = 0.25
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.18
    bump.inputs["Distance"].default_value = 0.002
    l.new(wave.outputs["Fac"], bump.inputs["Height"])
    l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def leather_material():
    mat, nt, bsdf = node_mat("Leather")
    n, l = nt.nodes, nt.links
    coord = n.new("ShaderNodeTexCoord")
    pebble = n.new("ShaderNodeTexVoronoi")
    pebble.feature = "DISTANCE_TO_EDGE"
    pebble.inputs["Scale"].default_value = 140
    l.new(coord.outputs["Object"], pebble.inputs["Vector"])
    mottle = n.new("ShaderNodeTexNoise")
    mottle.inputs["Scale"].default_value = 3.5
    mottle.inputs["Detail"].default_value = 6
    l.new(coord.outputs["Object"], mottle.inputs["Vector"])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.030, 0.010, 0.007, 1)
    ramp.color_ramp.elements[1].color = (0.085, 0.030, 0.018, 1)
    l.new(mottle.outputs["Fac"], ramp.inputs["Fac"])
    l.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.62
    bsdf.inputs["Sheen Weight"].default_value = 0.25
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.22
    bump.inputs["Distance"].default_value = 0.001
    l.new(pebble.outputs["Distance"], bump.inputs["Height"])
    l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def brass_material(name="Brass", dark=False):
    mat, nt, bsdf = node_mat(name)
    n, l = nt.nodes, nt.links
    bsdf.inputs["Metallic"].default_value = 1.0
    base = (0.50, 0.33, 0.13, 1) if dark else (0.80, 0.56, 0.24, 1)
    bsdf.inputs["Base Color"].default_value = base
    coord = n.new("ShaderNodeTexCoord")
    noise = n.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 30
    l.new(coord.outputs["Object"], noise.inputs["Vector"])
    rough = n.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.22
    rough.inputs["To Max"].default_value = 0.42
    l.new(noise.outputs["Fac"], rough.inputs["Value"])
    l.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    return mat


def thread_material():
    mat, _, bsdf = node_mat("Thread")
    bsdf.inputs["Base Color"].default_value = (0.55, 0.38, 0.18, 1)
    bsdf.inputs["Roughness"].default_value = 0.8
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


def ring(name, x0, y0, x1, y1, ix0, iy0, ix1, iy1, z0, z1, mat, bevel_w):
    """A rectangular frame: outer rect minus inner rect, from z0 to z1."""
    outer = box(name, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0, mat)
    cutter = box(name + "-cut", (ix0 + ix1) / 2, (iy0 + iy1) / 2, (z0 + z1) / 2,
                 ix1 - ix0, iy1 - iy0, (z1 - z0) * 3, mat)
    mod = outer.modifiers.new("Hole", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    bpy.context.view_layer.objects.active = outer
    bpy.ops.object.modifier_apply(modifier="Hole")
    bpy.data.objects.remove(cutter)
    if bevel_w:
        bevel(outer, bevel_w)
    shade_smooth(outer)
    return outer


def shade_smooth(ob):
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    except Exception:
        bpy.ops.object.shade_smooth()
    ob.select_set(False)


def stitches(ix0, iy0, ix1, iy1, inset, pitch, mat):
    """Saddle stitching around the leather, as short raised thread dashes."""
    length, width, height = pitch * 0.55, 0.012, 0.006
    coll = []
    def run(xa, ya, xb, yb):
        dist = math.hypot(xb - xa, yb - ya)
        count = int(dist / pitch)
        horiz = abs(yb - ya) < 1e-6
        for i in range(count + 1):
            t = i / max(count, 1)
            x, y = xa + (xb - xa) * t, ya + (yb - ya) * t
            sx, sy = (length, width) if horiz else (width, length)
            coll.append(box("Stitch", x, y, MAT_Z + height / 2, sx, sy, height, mat))
    a, b, c, d = ix0 + inset, iy0 + inset, ix1 - inset, iy1 - inset
    run(a + pitch, b, c - pitch, b)
    run(a + pitch, d, c - pitch, d)
    run(a, b + pitch, a, d - pitch)
    run(c, b + pitch, c, d - pitch)
    # One object keeps the render fast.
    bpy.ops.object.select_all(action="DESELECT")
    for ob in coll:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = coll[0]
    bpy.ops.object.join()


def corner_bracket(x, y, sx, sy, mat):
    """A brass book-corner on the leather: an L plate with two rivets. (sx, sy) point
    from the corner into the mat."""
    arm, width, thick = 0.34, 0.05, 0.014
    plates = [
        box("BracketH", x + sx * arm / 2, y + sy * width / 2, MAT_Z + thick / 2, arm, width, thick, mat),
        box("BracketV", x + sx * width / 2, y + sy * arm / 2, MAT_Z + thick / 2, width, arm, thick, mat),
    ]
    for ob in plates:
        bevel(ob, 0.005, 2)
    for rx, ry in [(x + sx * arm * 0.78, y + sy * width / 2), (x + sx * width / 2, y + sy * arm * 0.78)]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.012, location=(rx, ry, MAT_Z + thick))
        rivet = bpy.context.active_object
        rivet.data.materials.append(mat)
        shade_smooth(rivet)


def sparkle_emblem(cx, cy, radius, mat):
    """The logo's four-point sparkle, tooled into the leather with a thin ring around it."""
    import bmesh
    mesh = bpy.data.meshes.new("Sparkle")
    bm = bmesh.new()
    rim = []
    for i in range(32):
        a = math.pi / 2 + i * math.tau / 32
        # Concave four-point star: long tips at the compass points, deep waist between.
        phase = (i % 8) / 8
        r = radius * (0.12 + 0.88 * abs(math.cos(phase * math.pi)) ** 6)
        rim.append(bm.verts.new((cx + r * math.cos(a), cy + r * math.sin(a), MAT_Z)))
    face = bm.faces.new(rim)
    bmesh.ops.extrude_face_region(bm, geom=[face])
    for v in bm.verts:
        if v not in rim:
            v.co.z = MAT_Z + 0.006
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new("Sparkle", mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
    bpy.ops.mesh.primitive_torus_add(major_radius=radius * 1.35, minor_radius=0.004,
                                     location=(cx, cy, MAT_Z + 0.002))
    bpy.context.active_object.data.materials.append(mat)


# --- scene -------------------------------------------------------------------------

def build():
    reset()
    scene = bpy.context.scene
    walnut = walnut_material("Walnut")
    leather = leather_material()
    brass = brass_material()
    thread = thread_material()

    # Screen rect centered on the origin.
    x0, y0, x1, y1 = -W / 2, -H / 2, W / 2, H / 2
    ix0 = x0 + ARGS.inset_side * U
    ix1 = x1 - ARGS.inset_side * U
    iy0 = y0 + ARGS.inset_bottom * U
    iy1 = y1 - ARGS.inset_top * U

    # Leather play area, slightly oversized so the frame sits on it.
    box("Leather", 0, 0, MAT_Z - 0.02, W, H, 0.04, leather)
    # Walnut frame, extending past the screen so no edge shows.
    pad = 0.4
    ring("Frame", x0 - pad, y0 - pad, x1 + pad, y1 + pad, ix0, iy0, ix1, iy1,
         MAT_Z - 0.02, FRAME_H, walnut, 0.035)
    # Brass inlay just outside the inner lip, and a thin walnut cap rail on top.
    lip = 0.05
    ring("Inlay", ix0 - lip - 0.022, iy0 - lip - 0.022, ix1 + lip + 0.022, iy1 + lip + 0.022,
         ix0 - lip, iy0 - lip, ix1 + lip, iy1 + lip, FRAME_H - 0.01, FRAME_H + 0.008, brass, 0.004)
    # A tooled inner border on the leather: dark groove plus stitching.
    stitches(ix0, iy0, ix1, iy1, inset=0.07, pitch=0.06, mat=thread)
    groove = ring("Groove", ix0 + 0.11, iy0 + 0.11, ix1 - 0.11, iy1 - 0.11,
                  ix0 + 0.118, iy0 + 0.118, ix1 - 0.118, iy1 - 0.118, MAT_Z - 0.004, MAT_Z + 0.002,
                  brass_material("BrassDark", dark=True), 0)
    for cx, cy, sx, sy in [(ix0, iy0, 1, 1), (ix1, iy0, -1, 1), (ix0, iy1, 1, -1), (ix1, iy1, -1, -1)]:
        corner_bracket(cx, cy, sx, sy, brass)
    # Gold-leaf tooling, rough and only half metallic: a flat mirror under an overhead
    # lamp would read as a white blob from the top-down camera.
    tooled, _, tooled_bsdf = node_mat("GoldLeaf")
    tooled_bsdf.inputs["Base Color"].default_value = (0.32, 0.19, 0.07, 1)
    tooled_bsdf.inputs["Metallic"].default_value = 0.5
    tooled_bsdf.inputs["Roughness"].default_value = 0.6
    sparkle_emblem(0, (iy0 + iy1) / 2, min(ix1 - ix0, iy1 - iy0) * 0.09, tooled)

    # Lighting: a hanging lamp pools warm light on the leather, two off-screen candles
    # glow at opposite corners, and a faint cool fill keeps the shadows from going flat.
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.010, 0.007, 0.005, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3

    def light(name, kind, loc, energy, color, size=None):
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
        if kind == "AREA":
            direction = Vector((0, 0, 0)) - Vector(loc)
            ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        return ob

    mat_cy = (iy0 + iy1) / 2
    lamp = light("Lamp", "SPOT", (0.15, mat_cy + 0.3, 7.5), 2600, (1.0, 0.78, 0.52), size=1.2)
    lamp.data.spot_size = math.radians(48 if H >= W else 62)
    lamp.data.spot_blend = 0.9
    lamp.rotation_euler = (Vector((0, mat_cy, 0)) - lamp.location).to_track_quat("-Z", "Y").to_euler()
    light("Fill", "AREA", (0, 0, 8.0), 45 * (W * H) / 42, (1.0, 0.85, 0.7), size=max(W, H))
    # The near rail, where your hand rests, gets its own low warm light so the grain reads.
    near = light("NearRail", "AREA", (0, y0 - 1.2, 2.2), 90 * W / 4.4, (1.0, 0.7, 0.45), size=W * 1.2)
    near.data.shape = "RECTANGLE"
    near.data.size_y = 0.8
    light("CandleTL", "POINT", (x0 - 0.9, y1 - 0.4, 1.6), 140, (1.0, 0.5, 0.2), size=0.5)
    light("CandleBR", "POINT", (x1 + 0.9, y0 + 1.2, 1.6), 120, (1.0, 0.48, 0.18), size=0.5)
    light("Rim", "AREA", (-W, -H, 2.0), 25, (0.55, 0.65, 0.9), size=2.0)

    # Camera straight down. A long lens keeps cards undistorted while the frame's
    # inner walls still show a little depth, the diorama look.
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam_data.sensor_fit = "VERTICAL" if H >= W else "HORIZONTAL"
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    sensor = cam_data.sensor_height if H >= W else cam_data.sensor_width
    span = H if H >= W else W
    cam.location = (0, 0, MAT_Z + span * cam_data.lens / sensor)
    scene.camera = cam

    r = scene.render
    r.engine = "CYCLES"
    r.resolution_x = round(ARGS.width * ARGS.scale)
    r.resolution_y = round(ARGS.height * ARGS.scale)
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.filepath = ARGS.out
    scene.cycles.samples = ARGS.samples
    scene.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = "GPU"
    except Exception as exc:  # CPU still renders, just slower.
        print("GPU unavailable:", exc)
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)
    print("WROTE", ARGS.out)


build()
