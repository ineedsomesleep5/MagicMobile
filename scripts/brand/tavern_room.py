"""Renders the main menu's tavern room: a real 3D scene, drawn as three depth layers the app slides
against each other as the phone tilts (TavernRoomBackdrop on iOS and Android).

  blender -b -P scripts/brand/tavern_room.py -- --props <dir> --out-dir build_output/tavern/room [--samples 96] [--preview]

The room (walls, floor, ceiling beams, rug, table) is built here; the props are Meshy models
(<dir>/<name>/model.glb: bookshelf, fireplace, barrel, lantern, tankard). A missing prop is left out.
For each orientation (portrait, landscape) it writes:

  tavern-room-<o>-back.jpg     the room itself, with everything nearer hidden from the camera but
                               still lighting it, so a shifted nearer layer never reveals a copy
  tavern-room-<o>-mid.png      shelves and lanterns, transparent elsewhere
  tavern-room-<o>-front.png    the barrel, table and front beam, transparent elsewhere
  tavern-room-<o>-lights.json  where each flame sits on screen (0-1 from the top left) and its layer,
                               for the app's flickering glows

Stylised, not photoreal (Caleb, 2026-10-04): warm walnut, brass and candlelight like the tavern board.
"""
import bpy, bmesh, json, math, os, sys
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return ARGV[ARGV.index(name) + 1] if name in ARGV else default


PROPS = arg("--props", os.path.expanduser("~/Movies/motion-assets/magicmobile-brand/tavern-room/meshy"))
OUT = arg("--out-dir", "build_output/tavern/room")
SAMPLES = int(arg("--samples", "96"))
PREVIEW = "--preview" in ARGV
ORIENTATIONS = {"portrait": (1200, 2600), "landscape": (2600, 1200)}
if PREVIEW:
    ORIENTATIONS = {k: (w // 3, h // 3) for k, (w, h) in ORIENTATIONS.items()}

ROOM_W, ROOM_D, ROOM_H = 7.0, 9.0, 4.6   # x -3.5..3.5, y -6..3, floor 0..ceiling
BACK_Y = 3.0

# MARK: - Materials


def node_material(name, build):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    shader = build(nt)
    nt.links.new(shader.outputs[0], out.inputs["Surface"])
    return mat


def wood_planks(name, base=(0.16, 0.085, 0.045), board=0.22, length=2.4, vertical=False, scale=1.0):
    """Long boards with grain and colour variation: the tavern's walnut."""
    def build(nt):
        coord = nt.nodes.new("ShaderNodeTexCoord")
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (scale, scale, scale)
        if vertical:
            mapping.inputs["Rotation"].default_value = (0, 0, math.radians(90))
        nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
        bricks = nt.nodes.new("ShaderNodeTexBrick")
        bricks.offset = 0.37
        bricks.inputs["Scale"].default_value = 1.0
        bricks.inputs["Mortar Size"].default_value = 0.006
        bricks.inputs["Brick Width"].default_value = length
        bricks.inputs["Row Height"].default_value = board
        bricks.inputs["Color1"].default_value = (*base, 1)
        bricks.inputs["Color2"].default_value = (base[0] * 0.72, base[1] * 0.7, base[2] * 0.68, 1)
        bricks.inputs["Mortar"].default_value = (0.02, 0.012, 0.008, 1)
        nt.links.new(mapping.outputs["Vector"], bricks.inputs["Vector"])
        grain = nt.nodes.new("ShaderNodeTexWave")
        grain.wave_type = "BANDS"
        grain.bands_direction = "X"
        grain.inputs["Scale"].default_value = 3.0
        grain.inputs["Distortion"].default_value = 3.5
        grain.inputs["Detail"].default_value = 3.0
        nt.links.new(mapping.outputs["Vector"], grain.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 0.35
        nt.links.new(bricks.outputs["Color"], mix.inputs[6])
        nt.links.new(grain.outputs["Color"], mix.inputs[7])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.35
        nt.links.new(bricks.outputs["Fac"], bump.inputs["Height"])
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Roughness"].default_value = 0.62
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        return bsdf
    return node_material(name, build)


def stone(name):
    def build(nt):
        coord = nt.nodes.new("ShaderNodeTexCoord")
        bricks = nt.nodes.new("ShaderNodeTexBrick")
        bricks.inputs["Scale"].default_value = 2.2
        bricks.inputs["Mortar Size"].default_value = 0.025
        bricks.inputs["Color1"].default_value = (0.2, 0.17, 0.14, 1)
        bricks.inputs["Color2"].default_value = (0.13, 0.11, 0.095, 1)
        bricks.inputs["Mortar"].default_value = (0.05, 0.04, 0.035, 1)
        nt.links.new(coord.outputs["Object"], bricks.inputs["Vector"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.6
        nt.links.new(bricks.outputs["Fac"], bump.inputs["Height"])
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Roughness"].default_value = 0.85
        nt.links.new(bricks.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        return bsdf
    return node_material(name, build)


def flat(name, color, roughness=0.6, metallic=0.0, emission=None, strength=0.0):
    def build(nt):
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if emission:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1)
            bsdf.inputs["Emission Strength"].default_value = strength
        return bsdf
    return node_material(name, build)


def rug(name):
    """A worn red rug with a gold border, like the table's cloth."""
    def build(nt):
        coord = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(coord.outputs["UV"], sep.inputs["Vector"])
        # Border: distance from the UV edge.
        def edge(axis):
            a = nt.nodes.new("ShaderNodeMath"); a.operation = "PINGPONG"; a.inputs[1].default_value = 0.5
            nt.links.new(sep.outputs[axis], a.inputs[0])
            return a
        ex, ey = edge(0), edge(1)
        mn = nt.nodes.new("ShaderNodeMath"); mn.operation = "MINIMUM"
        nt.links.new(ex.outputs[0], mn.inputs[0]); nt.links.new(ey.outputs[0], mn.inputs[1])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        els = ramp.color_ramp.elements
        els[0].position = 0.0; els[0].color = (0.16, 0.018, 0.014, 1)
        els[1].position = 0.06; els[1].color = (0.42, 0.27, 0.07, 1)
        mid = els.new(0.1); mid.color = (0.16, 0.018, 0.014, 1)
        nt.links.new(mn.outputs[0], ramp.inputs["Fac"])
        noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 40
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 0.25
        nt.links.new(ramp.outputs["Color"], mix.inputs[6]); nt.links.new(noise.outputs["Color"], mix.inputs[7])
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Roughness"].default_value = 0.95
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        return bsdf
    return node_material(name, build)


# MARK: - Geometry


def box(name, size, location, material, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(material)
    # Bevelled edges catch the candlelight like carved wood.
    bevel = obj.modifiers.new("bevel", "BEVEL")
    bevel.width = min(0.02, min(size) * 0.2)
    bevel.segments = 2
    return obj


def plane(name, size, location, rotation, material):
    bpy.ops.mesh.primitive_plane_add(size=1, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[1], 1)
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(material)
    return obj


def cylinder(name, radius, depth, location, material, vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, vertices=vertices)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return obj


_PROP_CACHE = {}  # name -> (template root, its children, unscaled size)


def _instance(name):
    """A copy of an already imported prop sharing its mesh data (the second shelf and lantern)."""
    template, children, size = _PROP_CACHE[name]
    root = bpy.data.objects.new(f"{name}_root", None)
    bpy.context.scene.collection.objects.link(root)
    copies = []
    for child in children:
        c = child.copy()
        bpy.context.scene.collection.objects.link(c)
        c.parent = root
        copies.append(c)
    return root, copies, size


def import_prop(name, height, location, rotation_z=0.0, width=None):
    """A Meshy model scaled to `height` (or `width`), standing on `location`'s z."""
    if name in _PROP_CACHE:
        root, objs, size = _instance(name)
    else:
        path = os.path.join(PROPS, name, "model.glb")
        if not os.path.exists(path):
            print(f"prop missing, skipped: {name}")
            return []
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        objs = [o for o in bpy.data.objects if o not in before]
        meshes = [o for o in objs if o.type == "MESH"]
        if not meshes:
            return objs
        # Meshy models arrive at 4K and up to 1.5M faces; the room shows them a few hundred pixels
        # tall, so 1K textures and ~60k faces keep an 8 GB Mac rendering quickly.
        for o in meshes:
            faces = len(o.data.polygons)
            if faces > 60000:
                bpy.context.view_layer.objects.active = o
                dec = o.modifiers.new("decimate", "DECIMATE")
                dec.ratio = 60000 / faces
                bpy.ops.object.modifier_apply(modifier=dec.name)
            for slot in o.material_slots:
                if slot.material and slot.material.use_nodes:
                    for node in slot.material.node_tree.nodes:
                        if node.type == "TEX_IMAGE" and node.image and max(node.image.size) > 1024:
                            node.image.scale(1024, 1024)
                        if node.type == "BSDF_PRINCIPLED":
                            # Meshy textures carry their own soft lighting; a little rougher so candles don't glare.
                            node.inputs["Roughness"].default_value = max(0.45, node.inputs["Roughness"].default_value)
        root = bpy.data.objects.new(f"{name}_root", None)
        bpy.context.scene.collection.objects.link(root)
        bpy.context.view_layer.update()
        corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
        lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
        hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
        size = hi - lo
        center = (lo + hi) / 2
        tops = [o for o in objs if o.parent is None]
        for o in tops:
            o.parent = root
            o.location -= Vector((center.x, center.y, lo.z))
        _PROP_CACHE[name] = (root, tops, size)
        objs = tops + [c for o in tops for c in o.children_recursive]
    factor = (width / max(size.x, 1e-6)) if width else (height / max(size.z, 1e-6))
    root.scale = (factor, factor, factor)
    root.rotation_euler = (0, 0, rotation_z)
    root.location = location
    return [root] + list(objs)


# MARK: - Scene


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    layers = {"back": [], "mid": [], "front": []}
    flames = []  # (object, layer, kind, radius)
    placements = {}  # group name -> (empty, {orientation: (x, y, z, rotation_z)})

    walnut = wood_planks("walnut_wall", vertical=True, scale=1.0)
    floor = wood_planks("oak_floor", base=(0.2, 0.11, 0.055), board=0.26, length=3.0)
    ceiling = wood_planks("ceiling", base=(0.09, 0.05, 0.03), board=0.3)
    beam_wood = flat("beam", (0.07, 0.04, 0.022), roughness=0.75)
    brass = flat("brass", (0.8, 0.55, 0.22), roughness=0.32, metallic=1.0)
    wax = flat("wax", (0.92, 0.84, 0.66), roughness=0.4)
    # Modest emission keeps flames orange under AgX; the app adds the bloom (flickering glows).
    flame = flat("flame", (1.0, 0.4, 0.08), emission=(1.0, 0.38, 0.06), strength=6)
    cloth = flat("cloth", (0.36, 0.04, 0.035), roughness=0.9)

    half_w = ROOM_W / 2
    # The room shell.
    layers["back"] += [
        plane("floor", (ROOM_W, ROOM_D), (0, BACK_Y - ROOM_D / 2, 0), (0, 0, 0), floor),
        plane("ceiling", (ROOM_W, ROOM_D), (0, BACK_Y - ROOM_D / 2, ROOM_H), (math.pi, 0, 0), ceiling),
        plane("back_wall", (ROOM_W, ROOM_H), (0, BACK_Y, ROOM_H / 2), (math.pi / 2, 0, 0), walnut),
        plane("left_wall", (ROOM_D, ROOM_H), (-half_w, BACK_Y - ROOM_D / 2, ROOM_H / 2), (math.pi / 2, 0, math.pi / 2), walnut),
        plane("right_wall", (ROOM_D, ROOM_H), (half_w, BACK_Y - ROOM_D / 2, ROOM_H / 2), (math.pi / 2, 0, -math.pi / 2), walnut),
    ]
    # Ceiling beams and posts.
    for i, y in enumerate([2.4, 0.4, -1.6, -3.6]):
        layers["back"].append(box(f"beam_{i}", (ROOM_W, 0.28, 0.32), (0, y, ROOM_H - 0.16), beam_wood))
    for x in (-half_w + 0.2, half_w - 0.2):
        layers["back"].append(box(f"post_{x:+.0f}", (0.3, 0.3, ROOM_H), (x, BACK_Y - 0.2, ROOM_H / 2), beam_wood))
    layers["back"].append(box("wainscot", (ROOM_W, 0.06, 0.12), (0, BACK_Y - 0.03, 1.05), beam_wood))
    # Rug before the hearth.
    rug_obj = plane("rug", (3.4, 2.2), (0, 0.6, 0.006), (0, 0, 0), rug("rug"))
    layers["back"].append(rug_obj)

    # The hearth: Meshy's fireplace, or a stone one.
    fire = import_prop("fireplace", 2.3, (0, BACK_Y - 0.55, 0), width=2.6)
    if fire:
        layers["back"] += fire
    else:
        st = stone("stone")
        layers["back"] += [box("hearth_l", (0.5, 0.7, 1.6), (-1.0, BACK_Y - 0.35, 0.8), st),
                           box("hearth_r", (0.5, 0.7, 1.6), (1.0, BACK_Y - 0.35, 0.8), st),
                           box("mantel", (2.8, 0.8, 0.25), (0, BACK_Y - 0.4, 1.7), beam_wood),
                           box("chimney", (2.2, 0.6, 2.6), (0, BACK_Y - 0.3, 3.1), st)]
    fire_glow = cylinder("fire_core", 0.22, 0.18, (0, BACK_Y - 0.45, 0.3), flame, vertices=12)
    fire_glow.scale = (1.5, 0.5, 1.0)
    layers["back"].append(fire_glow)
    flames.append((fire_glow, "back", "hearth", 0.9))
    bpy.ops.object.light_add(type="AREA", location=(0, BACK_Y - 0.9, 0.6), rotation=(math.radians(-80), 0, 0))
    hearth = bpy.context.active_object
    hearth.data.energy = 420
    hearth.data.color = (1.0, 0.5, 0.2)
    hearth.data.size = 1.6

    # Candles on the mantel.
    for i, x in enumerate((-0.9, 0.9)):
        cyl = cylinder(f"mantel_candle_{i}", 0.045, 0.28, (x, BACK_Y - 0.55, 2.12), wax)
        tip = cylinder(f"mantel_flame_{i}", 0.02, 0.07, (x, BACK_Y - 0.55, 2.31), flame, vertices=8)
        layers["back"] += [cyl, tip]
        flames.append((tip, "back", "candle", 0.22))
        bpy.ops.object.light_add(type="POINT", location=(x, BACK_Y - 0.7, 2.4))
        light = bpy.context.active_object
        light.data.energy = 12; light.data.color = (1.0, 0.62, 0.3); light.data.shadow_soft_size = 0.05

    # Wall sconces either side of the hearth light the planks.
    for side in (-1, 1):
        x = side * 2.3
        plate = box(f"sconce_plate_{side}", (0.16, 0.04, 0.28), (x, BACK_Y - 0.03, 2.35), brass)
        arm = box(f"sconce_arm_{side}", (0.04, 0.22, 0.04), (x, BACK_Y - 0.13, 2.25), brass)
        cup = cylinder(f"sconce_cup_{side}", 0.06, 0.03, (x, BACK_Y - 0.24, 2.27), brass)
        cyl = cylinder(f"sconce_candle_{side}", 0.035, 0.22, (x, BACK_Y - 0.24, 2.39), wax)
        tip = cylinder(f"sconce_flame_{side}", 0.017, 0.06, (x, BACK_Y - 0.24, 2.53), flame, vertices=8)
        layers["back"] += [plate, arm, cup, cyl, tip]
        flames.append((tip, "back", "candle", 0.22))
        bpy.ops.object.light_add(type="POINT", location=(x, BACK_Y - 0.45, 2.6))
        sconce = bpy.context.active_object
        sconce.data.energy = 30; sconce.data.color = (1.0, 0.58, 0.26); sconce.data.shadow_soft_size = 0.08

    # Nearer props sit in groups placed per orientation: portrait sees a narrow, tall slice of the
    # room, so its shelves, lanterns, barrel and table stand closer to the middle.
    def group(name, layer, portrait, landscape):
        empty = bpy.data.objects.new(name, None)
        scene.collection.objects.link(empty)
        placements[name] = (empty, {"portrait": portrait, "landscape": landscape})
        return empty

    def adopt(parent, objs):
        for o in objs:
            if o.parent is None:
                o.parent = parent
        return objs

    def light(kind, location, energy, color=(1.0, 0.6, 0.28), soft=0.05):
        bpy.ops.object.light_add(type=kind, location=location)
        lamp = bpy.context.active_object
        lamp.data.energy = energy; lamp.data.color = color
        if hasattr(lamp.data, "shadow_soft_size"):
            lamp.data.shadow_soft_size = soft
        return lamp

    # Mid layer: shelves on both sides, angled to the room, and lanterns from the beams.
    for side in (-1, 1):
        g = group(f"shelf_{side}", "mid", (side * 1.45, 0.4, 0, side * math.radians(-72)), (side * 2.25, 1.2, 0, side * math.radians(-62)))
        shelf = import_prop("bookshelf", 3.0, (0, 0, 0)) or [box(f"shelf_fb_{side}", (1.6, 0.5, 3.0), (0, 0, 1.5), beam_wood)]
        cyl = cylinder(f"shelf_candle_{side}", 0.04, 0.24, (0, -0.15, 3.12), wax)
        tip = cylinder(f"shelf_flame_{side}", 0.018, 0.06, (0, -0.15, 3.28), flame, vertices=8)
        lamp = light("POINT", (0, -0.45, 3.3), 22)
        layers["mid"] += adopt(g, shelf + [cyl, tip, lamp])
        flames.append((tip, "mid", "candle", 0.22))
    for side in (-1, 1):
        g = group(f"lantern_{side}", "mid", (side * 0.62, -1.3, 0, 0), (side * 1.0, -0.6, 0, 0))
        lamp_obj = import_prop("lantern", 0.55, (0, 0, ROOM_H - 1.35))
        chain = cylinder(f"chain_{side}", 0.012, 1.0, (0, 0, ROOM_H - 0.5), brass, vertices=6)
        core = cylinder(f"lantern_core_{side}", 0.03, 0.07, (0, 0, ROOM_H - 1.1), flame, vertices=10)
        lamp = light("POINT", (0, -0.25, ROOM_H - 1.75), 16, color=(1.0, 0.58, 0.26), soft=0.25)
        layers["mid"] += adopt(g, lamp_obj + [chain, core, lamp])
        flames.append((core, "mid", "lantern", 0.45))

    # Front layer: a barrel bottom left, a table corner with a tankard bottom right, a beam across the top.
    g = group("barrel", "front", (-0.62, -3.25, 0, math.radians(20)), (-1.25, -2.6, 0, math.radians(20)))
    layers["front"] += adopt(g, import_prop("barrel", 1.05, (0, 0, 0)) or [cylinder("barrel_fallback", 0.42, 1.0, (0, 0, 0.5), beam_wood)])
    g = group("table", "front", (0.72, -3.15, 0, math.radians(-14)), (1.3, -2.7, 0, math.radians(-14)))
    table_top = box("table_top", (1.6, 1.1, 0.08), (0, 0, 0.92), wood_planks("table_wood", base=(0.22, 0.12, 0.06), board=0.18))
    table_leg = box("table_leg", (0.12, 0.12, 0.9), (-0.45, 0.25, 0.45), beam_wood)
    runner = plane("table_cloth", (0.6, 1.05), (-0.15, 0, 0.965), (0, 0, 0), cloth)
    tankard = import_prop("tankard", 0.42, (-0.2, -0.05, 0.96), rotation_z=math.radians(-20))
    cyl = cylinder("table_candle", 0.05, 0.3, (0.3, 0.15, 1.11), wax)
    tip = cylinder("table_flame", 0.022, 0.08, (0.3, 0.15, 1.31), flame, vertices=8)
    holder = cylinder("table_holder", 0.09, 0.03, (0.3, 0.15, 0.975), brass)
    lamp = light("POINT", (0.25, -0.1, 1.45), 14)
    layers["front"] += adopt(g, [table_top, table_leg, runner] + tankard + [cyl, tip, holder, lamp])
    flames.append((tip, "front", "candle", 0.26))
    layers["front"].append(box("front_beam", (ROOM_W, 0.32, 0.36), (0, -3.6, ROOM_H - 0.55), beam_wood))

    # A cool moonlit fill so the shadows read as a room, not a void.
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(60), 0, math.radians(30)))
    moon = bpy.context.active_object
    moon.data.energy = 0.08; moon.data.color = (0.5, 0.6, 1.0)
    world = bpy.data.worlds.new("world"); scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.02, 0.016, 1)

    return scene, layers, flames, placements


def place(placements, orientation):
    for empty, spots in placements.values():
        x, y, z, rz = spots[orientation]
        empty.location = (x, y, z)
        empty.rotation_euler = (0, 0, rz)
    bpy.context.view_layer.update()


def setup_render(scene, size):
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = "GPU"
    except Exception as e:  # CPU is fine, only slower
        print("GPU unavailable:", e)
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Punchy"
    except TypeError:
        pass
    scene.view_settings.exposure = 0.25


def camera(scene, orientation):
    bpy.ops.object.camera_add(location=(0, -5.4, 1.75))
    cam = bpy.context.active_object
    target = Vector((0, BACK_Y, 1.55))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.sensor_fit = "VERTICAL" if orientation == "portrait" else "HORIZONTAL"
    # Portrait sees the room tall (beams to rug); landscape sees it wide (shelf to shelf).
    cam.data.angle = math.radians(62 if orientation == "portrait" else 70)
    scene.camera = cam
    return cam


def show(objs, camera_visible):
    for o in objs:
        if hasattr(o, "visible_camera"):
            o.visible_camera = camera_visible


def render_layer(scene, layers, which, path):
    for name, objs in layers.items():
        show(objs, name == which)
    scene.render.film_transparent = which != "back"
    scene.render.image_settings.file_format = "JPEG" if which == "back" else "PNG"
    if which == "back":
        scene.render.image_settings.quality = 90
    else:
        scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    scene, layers, flames, placements = build()
    # Everything parented under a prop root inherits the layer through the root's children.
    for name, objs in layers.items():
        extra = []
        for o in objs:
            extra += list(o.children_recursive)
        layers[name] = list(dict.fromkeys(objs + extra))
    for orientation, size in ORIENTATIONS.items():
        setup_render(scene, size)
        place(placements, orientation)
        cam = camera(scene, orientation)
        for which in ("back", "mid", "front"):
            ext = "jpg" if which == "back" else "png"
            render_layer(scene, layers, which, os.path.abspath(os.path.join(OUT, f"tavern-room-{orientation}-{which}.{ext}")))
        lights = []
        for obj, layer, kind, radius in flames:
            p = world_to_camera_view(scene, cam, obj.matrix_world.translation)
            if 0 <= p.x <= 1 and 0 <= p.y <= 1 and p.z > 0:
                # Radius as a fraction of the frame's height, shrinking with distance.
                lights.append({"x": round(p.x, 4), "y": round(1 - p.y, 4), "layer": layer, "kind": kind,
                               "radius": round(radius / max(p.z, 0.5) * (1.2 if orientation == "portrait" else 1.6), 4)})
        with open(os.path.join(OUT, f"tavern-room-{orientation}-lights.json"), "w") as f:
            json.dump({"lights": lights}, f, indent=1)
        bpy.data.objects.remove(cam)
    print("tavern room rendered to", OUT)


main()
