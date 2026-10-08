"""Renders the Deck Studio spell book opening: a grimoire on the tavern table unclasps, its cover
swings open, a few leaves turn, and the camera settles straight over the page until parchment fills
the frame. The app plays it when Decks is tapped (and backwards on Done), then shows its own book
page in the same place (GrimoireStage on iOS, GrimoireStage.kt on Android).

  blender -b -P scripts/brand/grimoire.py -- --out-dir build_output/tavern/grimoire
      [--samples 48] [--preview] [--orientation portrait|landscape] [--frames 0,20,39]
      [--page-settle 0.86] [--reading 9]   (tuning: how flat the final page is, and its light)

Writes build_output/tavern/grimoire/<orientation>/frame-NNNN.png (40 frames at 30 a second);
scripts/brand/install_grimoire.sh encodes them to H.264 clips and installs them.

The book is built here (it has to open on a hinge, which a generated model cannot do) in the tavern's
materials: oxblood leather, brass corners and clasp, the app's mark on the cover, parchment leaves.
Portrait ends on the right-hand page with the gutter at the left edge; landscape ends on the spread
with the fold in the middle. Both match the page the app then draws.
"""
import bpy, math, os, sys
from mathutils import Vector, Quaternion, Matrix

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return ARGV[ARGV.index(name) + 1] if name in ARGV else default


REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = arg("--out-dir", "build_output/tavern/grimoire")
SAMPLES = int(arg("--samples", "48"))
PREVIEW = "--preview" in ARGV
ONLY = arg("--orientation")
ONLY_FRAMES = [int(f) for f in arg("--frames", "").split(",") if f]
FRAMES = 40
FPS = 30
READING = float(arg("--reading", "9"))             # the even light over the final page, in watts
SIZES = {"portrait": (810, 1755), "landscape": (1755, 810)}
if PREVIEW:
    SIZES = {k: (w // 2, h // 2) for k, (w, h) in SIZES.items()}

# The book, closed, lying on the table (z up). The spine runs along y at x = 0; pages reach +x.
W, H, T = 0.27, 0.50, 0.070          # page width, page height, closed thickness
BOARD = 0.006                        # cover board thickness
OVER = 0.010                         # how far the boards overhang the leaves
BLOCK_TOP = T - BOARD                # top of the page block
HINGE_Z = T / 2                      # the cover swings about the middle of the spine

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


def leather(name, color):
    """Worn leather: a pebbled bump and a little colour variation."""
    def build(nt):
        coord = nt.nodes.new("ShaderNodeTexCoord")
        grain = nt.nodes.new("ShaderNodeTexVoronoi")
        grain.inputs["Scale"].default_value = 520
        nt.links.new(coord.outputs["Object"], grain.inputs["Vector"])
        wear = nt.nodes.new("ShaderNodeTexNoise")
        wear.inputs["Scale"].default_value = 9
        wear.inputs["Detail"].default_value = 6
        nt.links.new(coord.outputs["Object"], wear.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.3
        ramp.color_ramp.elements[0].color = (color[0] * 0.55, color[1] * 0.55, color[2] * 0.55, 1)
        ramp.color_ramp.elements[1].position = 0.75
        ramp.color_ramp.elements[1].color = (*color, 1)
        nt.links.new(wear.outputs["Fac"], ramp.inputs["Fac"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.25
        bump.inputs["Distance"].default_value = 0.0006
        nt.links.new(grain.outputs["Distance"], bump.inputs["Height"])
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Roughness"].default_value = 0.5
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        return bsdf
    return node_material(name, build)


# The app's page (DeckStudioPalette.background under its paper grain), in scene-linear values. The film's
# last frames settle on exactly this, so the hand-off to the live page shows no change of colour.
PAGE_LINEAR = (0.665, 0.522, 0.301)   # tuned against the live page in the simulator, 2026-10-05
PAGE_SETTLE = float(arg("--page-settle", "0.86"))   # how far the page goes to the flat colour by the end
SETTLE_NODES = []                                   # each paper material's mix node, keyed in animate()


def parchment(name, base=(0.72, 0.56, 0.33)):
    """A leaf of the book: warm paper with soft mottling, mixed toward the app's flat page colour."""
    def build(nt):
        coord = nt.nodes.new("ShaderNodeTexCoord")
        mottle = nt.nodes.new("ShaderNodeTexNoise")
        mottle.inputs["Scale"].default_value = 7
        mottle.inputs["Detail"].default_value = 8
        mottle.inputs["Roughness"].default_value = 0.6
        nt.links.new(coord.outputs["Object"], mottle.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.25
        ramp.color_ramp.elements[0].color = (base[0] * 0.86, base[1] * 0.84, base[2] * 0.78, 1)
        ramp.color_ramp.elements[1].position = 0.8
        ramp.color_ramp.elements[1].color = (*base, 1)
        nt.links.new(mottle.outputs["Fac"], ramp.inputs["Fac"])
        fibre = nt.nodes.new("ShaderNodeTexNoise")
        fibre.inputs["Scale"].default_value = 420
        nt.links.new(coord.outputs["Object"], fibre.inputs["Vector"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.06
        nt.links.new(fibre.outputs["Fac"], bump.inputs["Height"])
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Roughness"].default_value = 0.85
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        flat_page = nt.nodes.new("ShaderNodeEmission")
        flat_page.inputs["Color"].default_value = (*PAGE_LINEAR, 1)
        flat_page.inputs["Strength"].default_value = 1.0
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.inputs["Fac"].default_value = 0.0
        nt.links.new(bsdf.outputs[0], mix.inputs[1])
        nt.links.new(flat_page.outputs[0], mix.inputs[2])
        SETTLE_NODES.append(mix)
        return mix
    return node_material(name, build)


def page_edges(name):
    """The cut edges of a few hundred leaves: fine stripes along the block's height."""
    def build(nt):
        coord = nt.nodes.new("ShaderNodeTexCoord")
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (1, 1, 900)
        nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
        lines = nt.nodes.new("ShaderNodeTexWave")
        lines.wave_type = "BANDS"
        lines.bands_direction = "Z"
        lines.inputs["Scale"].default_value = 1.0
        lines.inputs["Distortion"].default_value = 0.4
        nt.links.new(mapping.outputs["Vector"], lines.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (0.36, 0.25, 0.12, 1)
        ramp.color_ramp.elements[1].color = (0.70, 0.54, 0.31, 1)
        nt.links.new(lines.outputs["Fac"], ramp.inputs["Fac"])
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Roughness"].default_value = 0.8
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        return bsdf
    return node_material(name, build)


def walnut(name):
    def build(nt):
        coord = nt.nodes.new("ShaderNodeTexCoord")
        bricks = nt.nodes.new("ShaderNodeTexBrick")
        bricks.offset = 0.37
        bricks.inputs["Scale"].default_value = 1.0
        bricks.inputs["Mortar Size"].default_value = 0.0025
        bricks.inputs["Brick Width"].default_value = 2.4
        bricks.inputs["Row Height"].default_value = 0.19
        bricks.inputs["Color1"].default_value = (0.20, 0.095, 0.042, 1)
        bricks.inputs["Color2"].default_value = (0.15, 0.068, 0.03, 1)
        bricks.inputs["Mortar"].default_value = (0.03, 0.014, 0.007, 1)
        nt.links.new(coord.outputs["Object"], bricks.inputs["Vector"])
        grain = nt.nodes.new("ShaderNodeTexWave")
        grain.wave_type = "BANDS"
        grain.bands_direction = "X"
        grain.inputs["Scale"].default_value = 9.0
        grain.inputs["Distortion"].default_value = 2.2
        grain.inputs["Detail"].default_value = 3.0
        nt.links.new(coord.outputs["Object"], grain.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 0.4
        nt.links.new(bricks.outputs["Color"], mix.inputs[6])
        nt.links.new(grain.outputs["Color"], mix.inputs[7])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.3
        nt.links.new(bricks.outputs["Fac"], bump.inputs["Height"])
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Roughness"].default_value = 0.5
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        return bsdf
    return node_material(name, build)


def decal(name, image_path, metal=(0.86, 0.62, 0.26)):
    """The app's mark pressed into the cover in brass: the image's alpha picks brass over nothing."""
    def build(nt):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image_path)
        tex.extension = "CLIP"
        brass = nt.nodes.new("ShaderNodeBsdfPrincipled")
        brass.inputs["Base Color"].default_value = (*metal, 1)
        brass.inputs["Metallic"].default_value = 1.0
        brass.inputs["Roughness"].default_value = 0.28
        brass.inputs["Emission Color"].default_value = (1.0, 0.55, 0.18, 1)
        brass.inputs["Emission Strength"].default_value = 0.35
        clear = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(tex.outputs["Alpha"], mix.inputs["Fac"])
        nt.links.new(clear.outputs[0], mix.inputs[1])
        nt.links.new(brass.outputs[0], mix.inputs[2])
        return mix
    mat = node_material(name, build)
    mat.blend_method = "BLEND" if hasattr(mat, "blend_method") else mat.blend_method
    return mat


# MARK: - Geometry


def box(name, lo, hi, material, bevel=0.0015, parent=None):
    """An axis-aligned box from corner `lo` to corner `hi`, in the parent's space."""
    lo, hi = Vector(lo), Vector(hi)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(lo + hi) / 2)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = hi - lo
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(material)
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = min(bevel, min(hi - lo) * 0.45)
        mod.segments = 2
    if parent:
        obj.parent = parent
    return obj


def empty(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    if parent:
        obj.parent = parent
    return obj


def leaf(name, material, z, parent, segments=18):
    """One leaf as a grid from the spine to the fore-edge, with a 'curl' shape key for the turn."""
    verts, faces = [], []
    rows = 2
    for j in range(rows):
        for i in range(segments + 1):
            verts.append((W * i / segments, H * j / (rows - 1), z))
    for i in range(segments):
        faces.append((i, i + 1, i + 1 + segments + 1, i + segments + 1))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    obj.parent = parent
    obj.shape_key_add(name="flat")
    curl = obj.shape_key_add(name="curl")
    for index, point in enumerate(curl.data):
        t = (index % (segments + 1)) / segments
        # The middle of the leaf trails behind its edges, like paper in the air.
        point.co.z = z - 0.035 * math.sin(math.pi * t) - 0.012 * t
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * t * (t * (6 * t - 15) + 10)


def span(frame, start, end):
    return ease((frame - start) / max(1e-6, end - start))


# MARK: - Scene


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS

    cover_leather = leather("cover", (0.30, 0.055, 0.04))
    spine_leather = leather("spine", (0.20, 0.04, 0.03))
    endpaper = flat("endpaper", (0.20, 0.055, 0.04), roughness=0.85)
    brass = flat("brass", (0.86, 0.60, 0.24), roughness=0.3, metallic=1.0)
    paper = parchment("paper")
    edges = page_edges("edges")
    wax = flat("wax", (0.92, 0.84, 0.66), roughness=0.4)
    flame = flat("flame", (1.0, 0.4, 0.08), emission=(1.0, 0.42, 0.08), strength=14)
    ribbon_red = flat("ribbon_red", (0.45, 0.03, 0.03), roughness=0.7)
    ribbon_gold = flat("ribbon_gold", (0.62, 0.42, 0.10), roughness=0.6)
    card_back = flat("card_back", (0.16, 0.07, 0.05), roughness=0.55)

    # The table.
    bpy.ops.mesh.primitive_plane_add(size=6, location=(0.1, 0.25, 0))
    table = bpy.context.active_object
    table.name = "table"
    table.rotation_euler = (0, 0, math.radians(8))
    table.data.materials.append(walnut("walnut"))

    # Everything that stays put: back board, page block, spine.
    book = empty("book", (0, 0, 0))
    box("back_board", (-0.004, -OVER, 0), (W + OVER, H + OVER, BOARD), cover_leather, parent=book)
    block = box("page_block", (0.004, 0, BOARD), (W, H, BLOCK_TOP - 0.0006), edges, bevel=0, parent=book)
    # The spine stands while the book is shut and settles flat under the leaves as it opens (keyed in
    # animate()): its origin is on the table, so it sinks rather than shrinking toward its middle.
    spine_base = empty("spine_base", (0, 0, 0), parent=book)
    box("spine", (-0.016, -OVER, 0), (-0.002, H + OVER, T), spine_leather, bevel=0.005, parent=spine_base)
    for i, y in enumerate((0.07, 0.18, 0.32, 0.43)):
        box(f"spine_band_{i}", (-0.0185, y - 0.006, 0.004), (-0.004, y + 0.006, T - 0.004), brass, bevel=0.002, parent=spine_base)
    # The top leaf of the block: the page the camera settles on.
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0.004 + (W - 0.004) / 2, H / 2, BLOCK_TOP - 0.0004))
    page = bpy.context.active_object
    page.name = "right_page"
    page.scale = (W - 0.004, H, 1)
    bpy.ops.object.transform_apply(scale=True)
    page.data.materials.append(paper)
    page.parent = book
    # Ribbon markers trailing out of the foot of the book.
    for i, (x, mat, length) in enumerate(((0.07, ribbon_red, 0.075), (0.115, ribbon_gold, 0.055), (0.16, ribbon_red, 0.065))):
        box(f"ribbon_{i}", (x, -length, BLOCK_TOP * 0.55), (x + 0.012, 0.002, BLOCK_TOP * 0.55 + 0.0008), mat, bevel=0, parent=book).rotation_euler = (math.radians(-9), 0, 0)

    # The front board, hinged about the middle of the spine (so it comes to rest flat on the table).
    hinge = empty("cover_hinge", (-0.004, 0, HINGE_Z), parent=book)
    top = HINGE_Z                       # the board's underside sits this far above the hinge when closed
    cover = box("front_board", (0, -OVER, top - BOARD), (W + OVER + 0.004, H + OVER, top), cover_leather, parent=hinge)
    box("front_endpaper", (0.006, 0, top - BOARD - 0.0004), (W + 0.004, H, top - BOARD + 0.0002), endpaper, bevel=0, parent=hinge)
    corner = 0.058
    for i, (cx, cy) in enumerate(((W + OVER + 0.004, -OVER), (W + OVER + 0.004, H + OVER), (0.012, -OVER), (0.012, H + OVER))):
        sx = -1 if cx > 0.1 else 1
        sy = 1 if cy < 0.1 else -1
        verts = [(cx, cy, top + 0.0012), (cx + sx * corner, cy, top + 0.0012), (cx, cy + sy * corner, top + 0.0012),
                 (cx, cy, top - 0.0005), (cx + sx * corner, cy, top - 0.0005), (cx, cy + sy * corner, top - 0.0005)]
        mesh = bpy.data.meshes.new(f"corner_{i}")
        mesh.from_pydata(verts, [], [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)])
        mesh.update()
        plate = bpy.data.objects.new(f"corner_{i}", mesh)
        scene.collection.objects.link(plate)
        plate.data.materials.append(brass)
        plate.parent = hinge
    # A brass ring and the app's mark at the centre of the cover.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.062, minor_radius=0.0035, location=(0.004 + W / 2, H / 2, top + 0.0015))
    ring = bpy.context.active_object
    ring.name = "cover_ring"
    ring.data.materials.append(brass)
    ring.parent = hinge
    bpy.ops.object.shade_smooth()
    mark_path = os.path.join(REPO, "apps/ios/MagicMobile/Assets.xcassets/LaunchMark.imageset/launch-mark@3x.png")
    if os.path.exists(mark_path):
        bpy.ops.mesh.primitive_plane_add(size=0.105, location=(0.004 + W / 2, H / 2, top + 0.0009))
        mark = bpy.context.active_object
        mark.name = "cover_mark"
        mark.data.materials.append(decal("mark", mark_path))
        mark.parent = hinge
    # A ruled brass border on the cover.
    inset = 0.03
    for i, (lo, hi) in enumerate((((inset, inset - OVER, top), (W - inset + 0.01, inset - OVER + 0.0025, top + 0.0008)),
                                  ((inset, H - inset + OVER - 0.0025, top), (W - inset + 0.01, H - inset + OVER, top + 0.0008)),
                                  ((inset, inset - OVER, top), (inset + 0.0025, H - inset + OVER, top + 0.0008)),
                                  ((W - inset + 0.0075, inset - OVER, top), (W - inset + 0.01, H - inset + OVER, top + 0.0008)))):
        box(f"cover_rule_{i}", lo, hi, brass, bevel=0, parent=hinge)

    # The clasp: a strap from the back board over the fore-edge, which swings away first.
    clasp_hinge = empty("clasp_hinge", (W + OVER + 0.002, H / 2, 0.004), parent=book)
    box("clasp_strap", (-0.003, -0.016, 0), (0.003, 0.016, T - 0.002), spine_leather, bevel=0.001, parent=clasp_hinge)
    box("clasp_tongue", (-0.045, -0.016, T - 0.006), (0.003, 0.016, T - 0.001), spine_leather, bevel=0.001, parent=clasp_hinge)
    box("clasp_plate", (-0.047, -0.012, T - 0.0015), (-0.02, 0.012, T + 0.001), brass, bevel=0.001, parent=clasp_hinge)

    # A few leaves that turn after the cover. Their hinge sits mid-spine too, so they land on the open cover.
    leaf_hinge_z = (BLOCK_TOP + BOARD) / 2 + 0.003
    leaves = []
    for i in range(6):
        pivot = empty(f"leaf_hinge_{i}", (0.002, 0, leaf_hinge_z), parent=book)
        z_local = BLOCK_TOP - leaf_hinge_z + 0.0006 + (5 - i) * 0.0005
        leaves.append((pivot, leaf(f"leaf_{i}", paper, z_local, pivot)))

    # Dressing: a candle, a second one further off, a few cards and an inkwell.
    def candle(x, y, height, energy):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.016, depth=height, location=(x, y, height / 2), vertices=20)
        body = bpy.context.active_object
        body.data.materials.append(wax)
        bpy.ops.object.shade_smooth()
        bpy.ops.mesh.primitive_cylinder_add(radius=0.03, depth=0.008, location=(x, y, 0.004), vertices=24)
        bpy.context.active_object.data.materials.append(brass)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.007, location=(x, y, height + 0.012), segments=12, ring_count=8)
        tip = bpy.context.active_object
        tip.scale = (1, 1, 2.0)
        tip.data.materials.append(flame)
        bpy.ops.object.light_add(type="POINT", location=(x, y, height + 0.03))
        lamp = bpy.context.active_object
        lamp.data.energy = energy
        lamp.data.color = (1.0, 0.6, 0.28)
        lamp.data.shadow_soft_size = 0.02
        return lamp

    candle(-0.11, 0.66, 0.13, 4.5)
    candle(0.40, 0.70, 0.095, 3.5)
    candle(-0.43, 0.08, 0.07, 2.4)    # clear of where the cover lands
    for i, (x, y, r) in enumerate(((0.40, -0.13, 18), (0.43, -0.10, -12), (0.38, -0.07, 40))):
        card = box(f"card_{i}", (-0.0315, -0.044, 0), (0.0315, 0.044, 0.0006), card_back, bevel=0)
        card.location = (x, y, 0.0006 * (i + 1))
        card.rotation_euler = (0, 0, math.radians(r))
    bpy.ops.mesh.primitive_cylinder_add(radius=0.026, depth=0.04, location=(-0.10, -0.15, 0.02), vertices=24)
    ink = bpy.context.active_object
    ink.data.materials.append(brass)
    bpy.ops.object.shade_smooth()

    # Motes of light that lift out of the book as it opens (keyed in animate()).
    mote_light = flat("mote", (1.0, 0.75, 0.35), emission=(1.0, 0.68, 0.28), strength=60)
    motes = []
    for i in range(34):
        # A fixed scatter (no random module: every render of the film must be identical).
        u = (i * 0.618034) % 1.0
        v = (i * 0.754877) % 1.0
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.0016 + 0.0014 * ((i * 0.37) % 1.0),
                                              location=(0.03 + (W - 0.05) * u, 0.04 + (H - 0.08) * v, BLOCK_TOP))
        mote = bpy.context.active_object
        mote.name = f"mote_{i}"
        mote.data.materials.append(mote_light)
        motes.append((mote, u, v))

    # Light from the book itself as it opens, and a soft even light for the final page.
    bpy.ops.object.light_add(type="POINT", location=(W / 2, H / 2, 0.16))
    glow = bpy.context.active_object
    glow.name = "book_glow"
    glow.data.color = (1.0, 0.72, 0.36)
    glow.data.shadow_soft_size = 0.08
    bpy.ops.object.light_add(type="AREA", location=(W / 2, H / 2, 1.1))
    reading = bpy.context.active_object
    reading.name = "reading_light"
    reading.data.size = 1.2
    reading.data.color = (1.0, 0.9, 0.74)
    bpy.ops.object.light_add(type="AREA", location=(-0.5, -0.6, 0.9), rotation=(math.radians(50), 0, math.radians(-35)))
    fill = bpy.context.active_object
    fill.data.energy = 2.2
    fill.data.size = 1.0
    fill.data.color = (0.55, 0.62, 1.0)

    world = bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.008, 0.006, 1)

    return scene, hinge, clasp_hinge, leaves, glow, reading, motes, spine_base


def animate(scene, hinge, clasp_hinge, leaves, glow, reading, motes, spine_base, orientation):
    """Keys every frame directly (no curve editing): the clasp, the cover, the leaves, the lights, the camera."""
    bpy.ops.object.camera_add()
    cam = bpy.context.active_object
    cam.data.lens = 40
    scene.camera = cam
    portrait = orientation == "portrait"
    cam.data.sensor_fit = "VERTICAL" if portrait else "HORIZONTAL"
    half_fov = math.atan(cam.data.sensor_width / 2 / cam.data.lens)

    # Where the camera starts (a three-quarter view of the closed book) and where it lands.
    centre = Vector((W / 2, H / 2, T))
    if portrait:
        start_pos = Vector((W / 2 + 0.05, -0.74, 0.98))
        start_look = Vector((W / 2 - 0.005, H / 2 - 0.01, T))
        # Straight over the right page: its height fills the frame, the gutter sits at the left edge.
        end_look = Vector((W / 2 + 0.006, H / 2, BLOCK_TOP))
        end_height = (H * 0.5 * 0.985) / math.tan(half_fov)
    else:
        start_pos = Vector((W / 2 + 0.03, -0.62, 0.50))
        start_look = Vector((W / 2 - 0.01, H / 2 - 0.03, T))
        # Straight over the spine: the spread fills the frame, the fold sits in the middle (the app lays
        # a sideways screen out as two pages either side of it).
        end_look = Vector((0.0, H / 2, BLOCK_TOP * 0.6))
        end_height = (W * 0.96) / math.tan(half_fov)
    end_pos = end_look + Vector((0, 0, end_height))

    def look(position, target, roll_up=Vector((0, 1, 0))):
        forward = (target - position).normalized()
        right = forward.cross(roll_up)
        if right.length < 1e-5:
            right = Vector((1, 0, 0))
        right.normalize()
        up = right.cross(forward)
        m = Matrix((right, up, -forward)).transposed()
        return m.to_quaternion()

    q_start = look(start_pos, start_look, Vector((0, 0, 1)))
    q_end = look(end_pos, end_look, Vector((0, 1, 0)))
    cam.rotation_mode = "QUATERNION"

    for frame in range(FRAMES):
        scene.frame_set(frame)
        # The clasp swings off the fore-edge first.
        clasp_hinge.rotation_euler = (0, math.radians(150) * span(frame, 0, 7), 0)
        clasp_hinge.keyframe_insert("rotation_euler", frame=frame)
        # The cover swings over to the left.
        hinge.rotation_euler = (0, -math.radians(180) * span(frame, 3, 24), 0)
        hinge.keyframe_insert("rotation_euler", frame=frame)
        # The spine settles flat as the cover passes over it, so nothing stands in the open book's gutter.
        spine_base.scale = (1, 1, 1 - 0.9 * span(frame, 8, 20))
        spine_base.keyframe_insert("scale", frame=frame)
        # Leaves follow, each a little later, curling in the air.
        for index, (pivot, sheet) in enumerate(leaves):
            begin = 9 + index * 2.6
            t = span(frame, begin, begin + 13)
            pivot.rotation_euler = (0, -math.radians(179.0 - index * 0.25) * t, 0)
            pivot.keyframe_insert("rotation_euler", frame=frame)
            key = sheet.data.shape_keys.key_blocks["curl"]
            key.value = math.sin(math.pi * t) ** 1.2
            key.keyframe_insert("value", frame=frame)
        # The book's own light swells as it opens, then gives way to an even reading light.
        opening = span(frame, 2, 16)
        settle = span(frame, 22, FRAMES - 1)
        glow.data.energy = 0.9 * opening * (1 - 0.9 * settle)
        glow.data.keyframe_insert("energy", frame=frame)
        reading.data.energy = 1.5 + READING * settle
        reading.data.keyframe_insert("energy", frame=frame)
        for mix in SETTLE_NODES:
            mix.inputs["Fac"].default_value = PAGE_SETTLE * span(frame, 24, FRAMES - 2)
            mix.inputs["Fac"].keyframe_insert("default_value", frame=frame)
        # Motes rise from the pages once the cover is out of their way, drift, and go out.
        for index, (mote, u, v) in enumerate(motes):
            begin = 7 + (index % 9) * 1.3
            life = (frame - begin) / 14.0
            alive = 0.0 if life <= 0 or life >= 1 else math.sin(math.pi * life) ** 0.6
            rise = max(0.0, life)
            mote.location = (0.03 + (W - 0.05) * u + 0.035 * math.sin(index * 1.7 + rise * 3.0),
                             0.04 + (H - 0.08) * v + 0.02 * math.cos(index * 2.3 + rise * 2.2),
                             BLOCK_TOP + 0.005 + (0.05 + 0.09 * ((index * 0.29) % 1.0)) * rise)
            mote.scale = (alive, alive, alive)
            mote.keyframe_insert("location", frame=frame)
            mote.keyframe_insert("scale", frame=frame)
        # The camera drifts in at first, then rises over the page and comes straight down on it.
        move = span(frame, 8, FRAMES - 1)
        drift = start_pos + (start_look - start_pos) * 0.10 * span(frame, 0, 14)
        cam.location = drift.lerp(end_pos, move)
        cam.rotation_quaternion = q_start.slerp(q_end, span(frame, 6, FRAMES - 3))
        cam.keyframe_insert("location", frame=frame)
        cam.keyframe_insert("rotation_quaternion", frame=frame)
    return cam


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
    scene.cycles.max_bounces = 5
    scene.render.use_motion_blur = not PREVIEW
    scene.render.motion_blur_shutter = 0.4
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    # Standard, not a filmic transform: the final page has to come out as exactly PAGE_LINEAR.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0


def main():
    for orientation, size in SIZES.items():
        if ONLY and orientation != ONLY:
            continue
        SETTLE_NODES.clear()
        scene, hinge, clasp_hinge, leaves, glow, reading, motes, spine_base = build()
        setup_render(scene, size)
        animate(scene, hinge, clasp_hinge, leaves, glow, reading, motes, spine_base, orientation)
        out = os.path.abspath(os.path.join(OUT, orientation))
        os.makedirs(out, exist_ok=True)
        for frame in (ONLY_FRAMES or range(FRAMES)):
            scene.frame_set(frame)
            scene.render.filepath = os.path.join(out, f"frame-{frame:04d}.png")
            bpy.ops.render.render(write_still=True)
    print("spell book rendered to", OUT)


main()
