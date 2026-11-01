#!/usr/bin/env python3
"""Build an Arena board world in Blender: one .blend with a Landscape and a Portrait scene, each on the table's exact
camera, with its own ground and props placed in board points, and stand-in cards pinned to the camera so every card,
pile and control shows where the real board puts it. Stand-ins never reach the plate. A world is a JSON file in
scripts/brand/arena_worlds/.

  blender -b --factory-startup --python-exit-code 1 -P scripts/brand/arena_world.py -- \
      --world scripts/brand/arena_worlds/radio_night.json --out <dir> [--render] [--scale 100] [--samples 64] \
      [--assets ~/Movies/motion-assets/magicmobile-boards] [--only landscape]

Textures and models stay outside the repo in --assets: polyhaven/textures/<id>/, polyhaven/models/<id>/ and <world>/meshy/.

Writes <dir>/<world>.blend and qa.json; with --render also <variant>.png and <variant>-cards.png. The landscape and
portrait cameras see different ground, so each scene keeps its own set and they share materials and the moon.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, str(Path(__file__).parent))
from arena_camera import SENSOR, View
from arena_props_halloween import HALLOWEEN_PROPS, HALLOWEEN_ROOM
from arena_props_utopia import UTOPIA_PROPS, UTOPIA_ROOM
from arena_props_volcano import VOLCANO_PROPS, VOLCANO_ROOM
from arena_zones import CLEARINGS, GHOSTS, RAIL_TOP, SEATS, ZONES, inside

VARIANTS = ("landscape", "portrait")
WARM = (1.0, 0.42, 0.13)
GREEN = (0.2, 1.0, 0.45)


def linear(hex_colour):
    channels = [int(hex_colour[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels)


# --- materials -------------------------------------------------------------------

def new_material(name):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    return mat, next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def plain(name, colour, rough=0.8, metal=0.0, glow=0.0, glass=0.0):
    mat, bsdf = new_material(name)
    bsdf.inputs["Base Color"].default_value = (*colour, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Transmission Weight"].default_value = glass
    if glow:
        bsdf.inputs["Emission Color"].default_value = (*colour, 1)
        bsdf.inputs["Emission Strength"].default_value = glow
    mat.diffuse_color = (*colour, 1)
    return mat


class TextureSets:
    """Poly Haven sets in --assets: <id>_diff.jpg, _nor.jpg and _rough.jpg."""

    def __init__(self, root):
        self.root = root / "polyhaven" / "textures"

    def image(self, set_id, map_name):
        image = bpy.data.images.load(str(self.root / set_id / f"{set_id}_{map_name}.jpg"), check_existing=True)
        if map_name != "diff":
            image.colorspace_settings.name = "Non-Color"
        return image

    def node(self, tree, set_id, map_name, vector, box=False):
        node = tree.nodes.new("ShaderNodeTexImage")
        node.image = self.image(set_id, map_name)
        if box:
            node.projection, node.projection_blend = "BOX", 0.25
        tree.links.new(vector, node.inputs["Vector"])
        return node.outputs["Color"]

    def sample(self, tree, set_id, vector, box=False):
        return tuple(self.node(tree, set_id, m, vector, box) for m in ("diff", "rough", "nor"))


def scaled(tree, vector, scale, turn=0.0):
    mapping = tree.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale, scale, scale)
    mapping.inputs["Rotation"].default_value = (0, 0, turn)
    tree.links.new(vector, mapping.inputs["Vector"])
    return mapping.outputs["Vector"]


def mixed(tree, factor, a, b, blend="MIX"):
    mix = tree.nodes.new("ShaderNodeMix")
    mix.data_type, mix.blend_type = "RGBA", blend
    if isinstance(factor, float):
        mix.inputs["Factor"].default_value = factor
    else:
        tree.links.new(factor, mix.inputs["Factor"])
    for socket, value in (("A", a), ("B", b)):
        target = next(i for i in mix.inputs if i.name == socket and i.type == "RGBA")
        if isinstance(value, tuple):
            target.default_value = (*value, 1)
        else:
            tree.links.new(value, target)
    return mix.outputs["Result"] if "Result" in mix.outputs else mix.outputs[2]


def textured(textures, name, set_id, tile, tint=(1, 1, 1), metal=0.0, bump=1.0, wear=0.0):
    """A boxed texture set for props without UVs. `wear` mixes the tint back toward the bare texture."""
    mat, bsdf = new_material(name)
    tree = mat.node_tree
    coords = tree.nodes.new("ShaderNodeTexCoord").outputs["Object"]
    colour, rough, normal = textures.sample(tree, set_id, scaled(tree, coords, tile), box=True)
    painted = mixed(tree, 1.0, colour, tint, "MULTIPLY")
    tree.links.new(mixed(tree, wear, painted, colour) if wear else painted, bsdf.inputs["Base Color"])
    tree.links.new(rough, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = metal
    bumped = tree.nodes.new("ShaderNodeNormalMap")
    bumped.inputs["Strength"].default_value = bump
    tree.links.new(normal, bumped.inputs["Color"])
    tree.links.new(bumped.outputs["Normal"], bsdf.inputs["Normal"])
    mat.diffuse_color = (*tint, 1)
    return mat


def ground_material(textures, spec, open_tint, rough_tint):
    """One continuous ground: calm dirt where `open` is 0, stones and cracks as the land rises, no line between them."""
    mat, bsdf = new_material("ground")
    tree = mat.node_tree
    nodes, links = tree.nodes, tree.links
    where = nodes.new("ShaderNodeNewGeometry").outputs["Position"]
    rise = nodes.new("ShaderNodeAttribute")
    rise.attribute_name = "open"
    # Large, soft patches break up the edge of the clearing and hide the textures' repeats.
    patches = nodes.new("ShaderNodeTexNoise")
    patches.inputs["Scale"].default_value = 1.1
    patches.inputs["Detail"].default_value = 6
    links.new(where, patches.inputs["Vector"])
    offset = nodes.new("ShaderNodeMath")
    offset.operation = "MULTIPLY"
    offset.use_clamp = True
    links.new(rise.outputs["Fac"], offset.inputs[0])
    wobble = nodes.new("ShaderNodeMapRange")
    wobble.inputs["From Min"].default_value, wobble.inputs["From Max"].default_value = 0.35, 0.65
    wobble.inputs["To Min"].default_value, wobble.inputs["To Max"].default_value = 0.5, 2.0
    links.new(patches.outputs["Fac"], wobble.inputs["Value"])
    links.new(wobble.outputs["Result"], offset.inputs[1])
    edge = offset.outputs["Value"]

    calm_a = textures.sample(tree, spec["calm"], scaled(tree, where, spec["calm_tile"]))
    calm_b = textures.sample(tree, spec["calm"], scaled(tree, where, spec["calm_tile"] * 0.57, 0.9))
    rough = textures.sample(tree, spec["rough"], scaled(tree, where, spec["rough_tile"]))
    cracks = textures.sample(tree, spec["cracks"], scaled(tree, where, spec["cracks_tile"], 0.4))
    swap = patches.outputs["Fac"]
    calm = [mixed(tree, swap, a, b) for a, b in zip(calm_a, calm_b)]
    # The open ground keeps only a little of the texture's contrast, so cards read on it.
    grit = mixed(tree, spec["calm_grit"], calm[0], rough[0])
    quiet = mixed(tree, spec["calm_flatten"], grit, tuple(spec["calm_mean"]))
    cracked = mixed(tree, spec["cracks_mix"], quiet, cracks[0], "MULTIPLY")
    open_ground = mixed(tree, 1.0, cracked, open_tint, "MULTIPLY")
    if spec.get("grass"):
        # Grass patches from the ground's own mask, so the 3D tufts grow exactly where the texture is green.
        lawn = nodes.new("ShaderNodeAttribute")
        lawn.attribute_name = "grass"
        blades = scaled(tree, where, spec["grass_tile"])
        green = textures.sample(tree, spec["grass_set"], blades)
        open_ground = mixed(tree, lawn.outputs["Fac"], open_ground, mixed(tree, 1.0, green[0], linear(spec["grass_tint"]), "MULTIPLY"))
    colour = mixed(tree, edge, open_ground, mixed(tree, 1.0, rough[0], rough_tint, "MULTIPLY"))
    # Broad light and dark drifts across the dirt.
    drift = nodes.new("ShaderNodeTexNoise")
    drift.inputs["Scale"].default_value = spec["drift_scale"]
    drift.inputs["Detail"].default_value = 5
    links.new(where, drift.inputs["Vector"])
    level = nodes.new("ShaderNodeMapRange")
    level.inputs["From Min"].default_value, level.inputs["From Max"].default_value = 0.34, 0.66
    level.inputs["To Min"].default_value, level.inputs["To Max"].default_value = spec["drift_dark"], spec["drift_light"]
    links.new(drift.outputs["Fac"], level.inputs["Value"])
    shaded = nodes.new("ShaderNodeVectorMath")
    shaded.operation = "SCALE"
    links.new(colour, shaded.inputs[0])
    links.new(level.outputs["Result"], shaded.inputs["Scale"])
    links.new(shaded.outputs["Vector"], bsdf.inputs["Base Color"])
    links.new(mixed(tree, edge, calm[1], rough[1]), bsdf.inputs["Roughness"])
    bumped = nodes.new("ShaderNodeNormalMap")
    links.new(mixed(tree, edge, calm[2], rough[2]), bumped.inputs["Color"])
    strength = nodes.new("ShaderNodeMapRange")
    strength.inputs["To Min"].default_value, strength.inputs["To Max"].default_value = spec["calm_bump"], 1.0
    links.new(edge, strength.inputs["Value"])
    links.new(strength.outputs["Result"], bumped.inputs["Strength"])
    links.new(bumped.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def ghost_material(name, colour, alpha):
    mat, bsdf = new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    out = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
    nodes.remove(bsdf)
    glow = nodes.new("ShaderNodeEmission")
    glow.inputs["Color"].default_value = (*colour, 1)
    clear = nodes.new("ShaderNodeBsdfTransparent")
    blend = nodes.new("ShaderNodeMixShader")
    blend.inputs[0].default_value = alpha
    links.new(clear.outputs[0], blend.inputs[1])
    links.new(glow.outputs[0], blend.inputs[2])
    links.new(blend.outputs[0], out.inputs["Surface"])
    mat.diffuse_color = (*colour, alpha)
    return mat


# --- ground ----------------------------------------------------------------------

def smooth(points, passes=3):
    for _ in range(passes):
        points = [p for a, b in zip(points, points[1:] + points[:1])
                  for p in (((3 * a[0] + b[0]) / 4, (3 * a[1] + b[1]) / 4), ((a[0] + 3 * b[0]) / 4, (a[1] + 3 * b[1]) / 4))]
    return points


def signed_distance(x, y, outline):
    """Distance to the outline: negative inside it."""
    best, odd = np.full(x.shape, np.inf), np.zeros(x.shape, bool)
    for (ax, ay), (bx, by) in zip(outline, np.roll(outline, -1, axis=0)):
        ex, ey = bx - ax, by - ay
        t = np.clip(((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey), 0, 1)
        best = np.minimum(best, np.hypot(x - ax - t * ex, y - ay - t * ey))
        odd ^= ((ay > y) != (by > y)) & (x < (bx - ax) * (y - ay) / (by - ay + 1e-12) + ax)
    return np.where(odd, -best, best)


def waves(x, y, rng, scale, count=7):
    """Soft noise from 0 to 1."""
    total = np.zeros(x.shape)
    for i in range(count):
        angle, phase = rng.uniform(0, math.tau, 2)
        k = scale * (1.5 ** i)
        total += np.sin((x * math.cos(angle) + y * math.sin(angle)) * k + phase) / (1.3 ** i)
    return 0.5 + 0.5 * total / np.abs(total).max()


class Ground:
    STEP = 0.05

    def __init__(self, view, rng, clear, relief=1.0, grass=None, grass_in_rows=1.0):
        width, height = view.screen
        corners = [view.to_ground(p) for p in ((0, 0), (width, 0), (0, height), (width, height))]
        self.xs = np.arange(min(c[0] for c in corners) - 2, max(c[0] for c in corners) + 2, self.STEP)
        self.ys = np.arange(min(c[1] for c in corners) - 1.5, max(c[1] for c in corners) + 2.5, self.STEP)
        x, y = np.meshgrid(self.xs, self.ys)
        outline = np.array([view.to_ground(p)[:2] for p in smooth(CLEARINGS[view.variant])])
        edge = signed_distance(x, y, outline) + (waves(x, y, rng, 1.8) - 0.5) * 0.5
        rise = np.clip((edge + 0.1) / 0.55, 0, 1)
        self.open = rise * rise * (3 - 2 * rise)
        # The card piles rest on calm ground: the land settles around them.
        for rect in clear:
            px, py, pw, ph = rect
            corners = np.array([view.to_ground(p)[:2] for p in ((px, py), (px + pw, py), (px + pw, py + ph), (px, py + ph))])
            settle = np.clip((signed_distance(x, y, corners) - 0.05) / 0.35, 0, 1)
            self.open *= settle * settle * (3 - 2 * settle)
        px, py, pw, ph = ZONES[view.variant]["cards"][0][1]
        corners = np.array([view.to_ground(p)[:2] for p in ((px, py), (px + pw, py), (px + pw, py + ph), (px, py + ph))])
        settle = np.clip((signed_distance(x, y, corners) - 0.02) / 0.3, 0, 1)
        self.open *= settle * settle * (3 - 2 * settle)
        self.height = relief * (self.open * (0.04 + 0.2 * waves(x, y, rng, 1.1)) + self.open * 0.05 * waves(x, y, rng, 7))
        self.clusters = waves(x, y, rng, 2.2, 4)
        patches = waves(x, y, rng, 1.5, 6) * 0.72 + waves(x, y, rng, 9, 5) * 0.28
        self.grass = np.clip((patches - grass[0]) / max(grass[1] - grass[0], 1e-3), 0, 1) if grass else np.zeros(x.shape)
        # Cards read on calm stone, so grass thins out toward the rows.
        thin = np.clip((signed_distance(x, y, corners) + 0.3) / 0.6, 0, 1)
        self.grass *= grass_in_rows + (1 - grass_in_rows) * thin

    def sample(self, x, y, grid):
        i = int(np.clip((y - self.ys[0]) / self.STEP, 0, len(self.ys) - 1))
        j = int(np.clip((x - self.xs[0]) / self.STEP, 0, len(self.xs) - 1))
        return float(grid[i, j])

    def mesh(self, name, material):
        rows, cols = self.height.shape
        x, y = np.meshgrid(self.xs, self.ys)
        verts = np.stack((x, y, self.height), axis=-1).reshape(-1, 3)
        base = (np.arange(rows - 1)[:, None] * cols + np.arange(cols - 1)[None, :]).ravel()
        faces = np.stack((base, base + 1, base + cols + 1, base + cols), axis=1)
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(verts.tolist(), [], faces.tolist())
        mesh.attributes.new("open", "FLOAT", "POINT").data.foreach_set("value", self.open.ravel().astype(np.float32))
        mesh.attributes.new("grass", "FLOAT", "POINT").data.foreach_set("value", self.grass.ravel().astype(np.float32))
        mesh.polygons.foreach_set("use_smooth", np.ones(len(mesh.polygons), bool))
        mesh.materials.append(material)
        return bpy.data.objects.new(name, mesh)


def clear_of_cards(view, x, y, z, height, margin=8, moon=None, spread=0.0):
    rects = [ZONES[view.variant]["cards"][0][1], *SEATS[view.variant].values()]
    if view.variant in RAIL_TOP:
        rects.append((0, RAIL_TOP[view.variant] - 16, view.screen[0], 40))
    points = [(x + dx, y + dy, z + h) for dx, dy in ((0, 0), (spread, 0), (-spread, 0), (0, spread), (0, -spread)) for h in (0, height)]
    if moon is not None:
        points += [(px + moon[0] / -moon[2] * pz_h, py + moon[1] / -moon[2] * pz_h, z)
                   for px, py, pz in points for pz_h in (pz - z,)]
    return not any(inside(view.to_screen(p), rect, margin) for p in points for rect in rects)


def seen(view, x, y):
    return inside(view.to_screen((x, y, 0)), (0, 0, *view.screen), 36)


def scatter_pebbles(name, count, ground, view, rng, material):
    """Small stones in one mesh, thickest where the land rises."""
    bm = bmesh.new()
    placed = 0
    for _ in range(count * 40):
        if placed >= count:
            break
        x, y = rng.uniform(ground.xs[0], ground.xs[-1]), rng.uniform(ground.ys[0], ground.ys[-1])
        rise = ground.sample(x, y, ground.open)
        if rise < 0.04 or rng.random() > rise + 0.15 or not seen(view, x, y):
            continue
        size = rng.uniform(0.005, 0.03) * (0.6 + rise)
        z = ground.sample(x, y, ground.height)
        if not clear_of_cards(view, x, y, z, size, 4):
            continue
        spot = Matrix.Translation((x, y, z)) @ Euler(rng.uniform(0, 3.14, 3)).to_matrix().to_4x4()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=size, matrix=spot @ Matrix.Diagonal((1.3, 1, 0.65, 1)))
        placed += 1
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    mesh.polygons.foreach_set("use_smooth", np.ones(len(mesh.polygons), bool))
    return bpy.data.objects.new(name, mesh)


def raked(view, x, y, target):
    """Forced perspective: the turn that shows an upright at (x, y) as if seen from `target` degrees off vertical, leaning
    it away from the point under the camera, as a painter draws fronts the high table camera can't see."""
    dx, dy = x - view.location[0], y - view.location[1]
    away = math.hypot(dx, dy)
    natural = math.degrees(math.atan2(away, view.location[2]))
    angle = math.radians(max(0.0, target - natural))
    return Matrix.Rotation(angle, 4, Vector((-dy, dx, 0)).normalized()), Vector((dx, dy, 0)).normalized()


def scatter_tufts(name, count, ground, view, rng, material):
    """Short grass and tiny flowers where the ground is green, in one mesh, kept off the card rows."""
    bm = bmesh.new()
    placed = 0
    for _ in range(count * 30):
        if placed >= count:
            break
        x, y = rng.uniform(ground.xs[0], ground.xs[-1]), rng.uniform(ground.ys[0], ground.ys[-1])
        if ground.sample(x, y, ground.grass) < 0.5 or not seen(view, x, y):
            continue
        z = ground.sample(x, y, ground.height)
        if not clear_of_cards(view, x, y, z, 0.12, 12):
            continue
        for _ in range(5):
            lean = Euler((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0, 6.28))).to_matrix().to_4x4()
            height = rng.uniform(0.05, 0.12)
            spot = Matrix.Translation((x + rng.normal(0, 0.02), y + rng.normal(0, 0.02), z)) @ lean @ Matrix.Translation((0, 0, height / 2))
            bmesh.ops.create_cone(bm, segments=3, radius1=0.012, radius2=0, depth=height, matrix=spot)
        placed += 1
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    return bpy.data.objects.new(name, mesh)


def scatter_models(kit, name, spec, ground, view, rng, moon, spots):
    """Shrubs and stones in loose clusters along the edge of the clearing, never over the card rows."""
    root = kit.root(name, (0, 0, 0), 0, 1)
    placed = 0
    for _ in range(spec["count"] * 60):
        if placed >= spec["count"]:
            break
        x, y = rng.uniform(ground.xs[0], ground.xs[-1]), rng.uniform(ground.ys[0], ground.ys[-1])
        rise = ground.sample(x, y, ground.open)
        if not spec["from"] <= rise <= spec["to"] or ground.sample(x, y, ground.clusters) < spec["clusters"] or not seen(view, x, y):
            continue
        model, low, high = spec["models"][rng.integers(len(spec["models"]))]
        size = rng.uniform(low, high)
        z = ground.sample(x, y, ground.height)
        if not clear_of_cards(view, x, y, z, size * spec.get("tall", 0.8), 7, moon, size * 0.42):
            continue
        if any(math.hypot(x - sx, y - sy) < reach for sx, sy, reach in spots):
            continue
        tilt = (0, 0)
        if kit.rake:
            tilt = raked(view, x, y, kit.rake)[0].to_euler()[:2]
        kit.model(root, model, size, (x, y, z - 0.01), rng.uniform(0, 360), tilt)
        placed += 1


# --- props -----------------------------------------------------------------------

# Poly Haven files that hold a row of variants: each mesh is its own plant.
SHEETS = {"shrub_03", "weed_plant_02", "shrub_sorrel_01", "flower_heliophila", "periwinkle_plant", "fern_02", "celandine_01",
          "didelta_spinosa", "leipoldtia_schultzei"}


def twig_mesh(rng, material):
    """A dry bush: thin branches fanning out of one root, each with a few side twigs. About one unit across."""
    bm = bmesh.new()

    def branch(start, direction, length, radius, twigs):
        up = Vector((0, 0, 1)).rotation_difference(direction).to_matrix().to_4x4()
        spot = Matrix.Translation(start + direction * (length / 2)) @ up
        bmesh.ops.create_cone(bm, cap_ends=False, segments=4, radius1=radius, radius2=radius * 0.15, depth=length, matrix=spot)
        for _ in range(twigs):
            along = float(rng.uniform(0.35, 0.95))
            side = (direction + Vector(rng.normal(0, 0.8, 3))).normalized()
            side.z = abs(side.z) * 0.8 + 0.1
            branch(start + direction * (length * along), side.normalized(), length * float(rng.uniform(0.3, 0.55)), radius * 0.5, max(twigs - 2, 0))

    for _ in range(26):
        angle, lift = rng.uniform(0, math.tau), rng.uniform(0.25, 1.3)
        direction = Vector((math.cos(angle) * math.cos(lift), math.sin(angle) * math.cos(lift), math.sin(lift))).normalized()
        branch(Vector(rng.normal(0, 0.03, 3) * (1, 1, 0)), direction, float(rng.uniform(0.3, 0.55)), 0.012, 3)
    mesh = bpy.data.meshes.new("twig_bush")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    mesh.use_fake_user = True
    return mesh


def bush_mesh(rng, material):
    """A soft round bush: overlapping lumps, about one unit across."""
    bm = bmesh.new()
    for _ in range(22):
        angle, lift = rng.uniform(0, math.tau), rng.uniform(-0.2, 1.3)
        reach = rng.uniform(0.12, 0.36)
        at = Vector((math.cos(angle) * math.cos(lift) * reach, math.sin(angle) * math.cos(lift) * reach, 0.28 + math.sin(lift) * reach))
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=float(rng.uniform(0.11, 0.2)), matrix=Matrix.Translation(at))
    for vert in bm.verts:
        vert.co += vert.normal * float(rng.normal(0, 0.012))
    for face in bm.faces:
        face.smooth = True
    mesh = bpy.data.meshes.new("bush")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    mesh.use_fake_user = True
    return mesh


def dried(material, spec):
    """Turn a green plant's colour map dry."""
    tree = material.node_tree
    bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
    links = bsdf.inputs["Base Color"].links
    if not links:
        return
    source = links[0].from_socket
    shift = tree.nodes.new("ShaderNodeHueSaturation")
    shift.inputs["Hue"].default_value, shift.inputs["Saturation"].default_value, shift.inputs["Value"].default_value = spec
    tree.links.new(source, shift.inputs["Color"])
    tree.links.new(shift.outputs["Color"], bsdf.inputs["Base Color"])


class Library:
    """Models from --assets, imported once and placed as linked copies, scaled by their longest side."""

    def __init__(self, root, world_name, rng, twig_material, dry, trims):
        self.root, self.world, self.models = root, world_name, {}
        self.rng, self.twig_material, self.dry, self.trims = rng, twig_material, dry, trims
        self.materials = {}

    def path(self, name):
        meshy = sorted((self.root / self.world / "meshy" / name).glob("*.glb"))
        return meshy[0] if meshy else self.root / "polyhaven" / "models" / name / f"{name}_1k.gltf"

    @staticmethod
    def trimmed(mesh, matrix, spec):
        """Cut a share of the model off its front and top: steps that would reach the card rows, roof clutter under a pile."""
        mesh.transform(matrix)
        bm = bmesh.new()
        bm.from_mesh(mesh)
        front, back = min(v.co.y for v in bm.verts), max(v.co.y for v in bm.verts)
        floor, peak = min(v.co.z for v in bm.verts), max(v.co.z for v in bm.verts)
        cuts = (((0, front + (back - front) * spec.get("front", 0), 0), (0, -1, 0)), ((0, 0, floor + (peak - floor) * spec.get("top", 1)), (0, 0, 1)))
        for at, facing in cuts:
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=at, plane_no=facing, clear_outer=True)
        bm.to_mesh(mesh)
        bm.free()
        return mesh, Matrix.Identity(4)

    @staticmethod
    def entry(parts):
        points = []
        for mesh, matrix in parts:
            co = np.empty(len(mesh.vertices) * 3)
            mesh.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)
            points.append(co @ np.array(matrix.to_3x3()).T + np.array(matrix.translation))
        points = np.concatenate(points)
        low, high = points.min(0), points.max(0)
        return dict(parts=parts, longest=float((high - low).max()), size=high - low,
                    base=Vector(((low[0] + high[0]) / 2, (low[1] + high[1]) / 2, low[2])))

    def get(self, name):
        if name in self.models:
            return self.models[name]
        if name.startswith("bush_"):
            self.models[name] = [self.entry([(bush_mesh(self.rng, self.materials[name[5:]]), Matrix.Identity(4))]) for _ in range(3)]
            return self.models[name]
        if name == "twig_bush":
            self.models[name] = [self.entry([(twig_mesh(self.rng, self.twig_material), Matrix.Identity(4))]) for _ in range(3)]
            return self.models[name]
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(self.path(name)))
        new = [o for o in bpy.data.objects if o not in before]
        bpy.context.view_layer.update()
        for obj in new:
            if obj.type == "MESH" and len(obj.data.polygons) > 90000:
                # Meshy models arrive up to 1.5M faces; a corner of a phone screen needs far fewer.
                decimate = obj.modifiers.new("decimate", "DECIMATE")
                decimate.ratio = 90000 / len(obj.data.polygons)
                with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
                    bpy.ops.object.modifier_apply(modifier=decimate.name)
        parts = [(o.data, o.matrix_world.copy()) for o in new if o.type == "MESH"]
        if name in self.trims:
            parts = [self.trimmed(mesh, matrix, self.trims[name]) for mesh, matrix in parts]
        for mesh, _ in parts:
            mesh.use_fake_user = True
            for mat in mesh.materials:
                for node in mat.node_tree.nodes if mat and mat.node_tree else ():
                    if node.type == "TEX_IMAGE" and node.image and max(node.image.size) > 1024:
                        node.image.scale(1024, 1024)
                        node.image.pack()
        for mat in {m for mesh, _ in parts for m in mesh.materials}:
            if name.startswith(("shrub", "weed")):
                dried(mat, self.dry)
            elif name.startswith(("rock", "stone")):
                dried(mat, (0.5, 0.4, 0.5))
        for obj in new:
            bpy.data.objects.remove(obj)
        groups = [[part] for part in parts] if name in SHEETS else [parts]
        self.models[name] = [self.entry(group) for group in groups]
        return self.models[name]


class Kit:
    """Props from textured shapes and library models, placed in board points."""

    def __init__(self, collection, materials, library, rng, warm=None, cool=None):
        self.collection, self.materials, self.library, self.rng = collection, materials, library, rng
        self.warm, self.cool = warm or WARM, cool or GREEN
        self.rake = 0

    def root(self, name, location, turn, size):
        root = bpy.data.objects.new(name, None)
        root.location, root.rotation_euler = location, (0, 0, math.radians(turn))
        root.scale = (size, size, size)
        self.collection.objects.link(root)
        return root

    def part(self, root, shape, material, size, at, tilt=(0, 0, 0)):
        bm = bmesh.new()
        if shape == "box":
            bmesh.ops.create_cube(bm, size=1)
        elif shape == "ball":
            bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=8, radius=0.5)
        elif shape == "spike":
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=5, radius1=0.5, radius2=0.02, depth=1)
        else:
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16, radius1=0.5, radius2=0.5, depth=1)
        bmesh.ops.scale(bm, vec=size, verts=bm.verts)
        bm.normal_update()
        for face in bm.faces:
            face.smooth = shape == "ball" or (shape == "cyl" and abs(face.normal.z) < 0.5)
        mesh = bpy.data.meshes.new(f"{root.name}-{material}")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(self.materials[material])
        obj = bpy.data.objects.new(mesh.name, mesh)
        obj.parent, obj.location, obj.rotation_euler = root, at, tilt
        self.collection.objects.link(obj)
        return obj

    def hexagon(self, root, material, radius, height, at):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=radius, radius2=radius, depth=height,
                              matrix=Matrix.Translation((at[0], at[1], height / 2)))
        mesh = bpy.data.meshes.new(f"{root.name}-{material}")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(self.materials[material])
        obj = bpy.data.objects.new(mesh.name, mesh)
        obj.parent = root
        self.collection.objects.link(obj)

    def mesh(self, root, name, verts, faces, material, smooth=False):
        mesh = bpy.data.meshes.new(f"{root.name}-{name}")
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        mesh.materials.append(self.materials[material])
        if smooth:
            mesh.polygons.foreach_set("use_smooth", np.ones(len(mesh.polygons), bool))
        obj = bpy.data.objects.new(mesh.name, mesh)
        obj.parent = root
        self.collection.objects.link(obj)
        return obj

    def beams(self, root, material, pairs, thick, width=None):
        """Thin bars between pairs of points, in one mesh."""
        bm = bmesh.new()
        for a, b in pairs:
            a, b = Vector(a), Vector(b)
            along = (b - a).normalized()
            turn = Vector((0, 0, 1)).rotation_difference(along).to_matrix().to_4x4()
            size = Matrix.Diagonal((width or thick, thick, (b - a).length + thick, 1))
            if width:
                turn = Vector((1, 0, 0)).rotation_difference(along).to_matrix().to_4x4()
                size = Matrix.Diagonal(((b - a).length + 0.01, width, thick, 1))
            bmesh.ops.create_cube(bm, size=1, matrix=Matrix.Translation((a + b) / 2) @ turn @ size)
        mesh = bpy.data.meshes.new(f"{root.name}-{material}")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(self.materials[material])
        obj = bpy.data.objects.new(mesh.name, mesh)
        obj.parent = root
        self.collection.objects.link(obj)

    def model(self, root, name, size, at=(0, 0, 0), turn=0.0, tilt=(0, 0), material=None, squash=1.0):
        choices = self.library.get(name)
        entry = choices[self.rng.integers(len(choices))]
        scale = size / entry["longest"]
        place = Matrix.Translation(at) @ Euler((tilt[0], tilt[1], math.radians(turn))).to_matrix().to_4x4() \
            @ Matrix.Diagonal((scale, scale, scale * squash, 1)) @ Matrix.Translation(-entry["base"])
        for mesh, matrix in entry["parts"]:
            obj = bpy.data.objects.new(f"{root.name}-{name}", mesh)
            obj.parent, obj.matrix_basis = root, place @ matrix
            self.collection.objects.link(obj)
            if material:
                for slot in obj.material_slots:
                    slot.link, slot.material = "OBJECT", self.materials[material]

    def lamp(self, root, at, colour, power, radius=0.14):
        light = bpy.data.lights.new(f"{root.name}-lamp", "POINT")
        light.color, light.energy, light.shadow_soft_size = colour, power, radius
        obj = bpy.data.objects.new(light.name, light)
        obj.parent, obj.location = root, at
        self.collection.objects.link(obj)


def diner(k, r, p):
    squash = p.get("squash", 1)
    k.model(r, "diner", 2.7, turn=p.get("face", 0), squash=squash)
    # A clean deck over the cut roof, so piles rest on one flat surface.
    entry = k.library.get("diner")[0]
    width, depth, height = entry["size"] * (2.7 / entry["longest"])
    k.part(r, "box", "roof", (width * 0.93, depth * 0.93, 0.012), (0, 0, height * squash + 0.004))
    k.lamp(r, (0, -1.25, 0.5), WARM, 16, 0.4)
    k.lamp(r, (1.2, -0.5, 0.5), WARM, 7, 0.3)


def fuel_pump(k, r, p):
    k.part(r, "box", "concrete", (0.44, 0.36, 0.05), (0, 0, 0.025))
    k.part(r, "box", "pump", (0.26, 0.19, 0.5), (0, 0, 0.3))
    k.part(r, "cyl", "pump", (0.26, 0.19, 0.1), (0, 0, 0.58))
    k.part(r, "box", "pump_top", (0.27, 0.2, 0.05), (0, 0, 0.5))
    k.part(r, "box", "glow_warm", (0.15, 0.01, 0.1), (0, -0.1, 0.36))
    k.part(r, "cyl", "tire", (0.02, 0.02, 0.4), (0.17, -0.02, 0.28), (0.1, 0.1, 0))
    k.lamp(r, (0, -0.2, 0.42), WARM, 1.4, 0.05)


def lamp_post(k, r, p):
    k.part(r, "cyl", "rust", (0.05, 0.05, 1.25), (0, 0, 0.62))
    k.part(r, "box", "rust", (0.34, 0.035, 0.035), (0.15, 0, 1.22))
    k.part(r, "ball", "glow_warm", (0.1, 0.1, 0.08), (0.3, 0, 1.17))
    k.lamp(r, (0.3, 0, 1.12), WARM, p.get("power", 16), 0.1)


def glow(k, r, p):
    k.lamp(r, (0, 0, p.get("z", 0.6)), GREEN if p.get("colour") == "green" else WARM, p.get("power", 8), 0.25)


def sandbags(k, r, p):
    for row, count in ((0, 7), (1, 5), (2, 2)):
        for i in range(count):
            angle = (i - (count - 1) / 2) * 0.27
            k.model(r, "cement_bag", 0.36, (math.sin(angle) * 1.0, math.cos(angle) * 1.0 - 1.0, row * 0.1),
                    math.degrees(-angle) + 90 + float(k.rng.uniform(-8, 8)), material="burlap")


def crates(k, r, p):
    k.model(r, "wooden_crate_01", 0.56, (0, 0, 0), 12)
    k.model(r, "old_military_crate", 0.62, (0.56, 0.12, 0), -18)
    k.model(r, "wooden_crate_02", 0.4, (0.06, 0.02, 0.4), 40)


def drums(k, r, p):
    for at, lean in (((0, 0), 0.0), ((0.3, 0.1), 0.05), ((0.08, 0.32), -0.04)):
        k.part(r, "cyl", "rust", (0.27, 0.27, 0.4), (*at, 0.2), (lean, 0, 0))
        for z in (0.13, 0.27):
            k.part(r, "cyl", "rust", (0.285, 0.285, 0.02), (*at, z), (lean, 0, 0))
    k.model(r, "oil_tin", 0.14, (-0.24, -0.18, 0), 10)


def tires(k, r, p):
    k.model(r, "old_tyre", 0.42, (0, 0, 0), 10)
    k.model(r, "old_tyre", 0.42, (0.04, 0.03, 0.1), 50)
    k.model(r, "rusted_wheel_rim_01", 0.3, (0.42, 0.1, 0), 40)


def robot(k, r, p):
    k.model(r, "robot", p.get("span", 1.05), turn=p.get("face", 0))


def shack(k, r, p):
    k.part(r, "box", "planks", (1.2, 0.92, 0.6), (0, 0, 0.3))
    k.part(r, "box", "iron", (1.46, 1.16, 0.035), (0, 0, 0.66), (0.09, 0, 0))
    k.part(r, "box", "glow_warm", (0.26, 0.015, 0.2), (-0.28, -0.465, 0.36))
    k.part(r, "box", "rust", (0.3, 0.02, 0.03), (-0.28, -0.47, 0.47))
    k.part(r, "box", "door", (0.3, 0.02, 0.48), (0.26, -0.47, 0.24))
    k.part(r, "box", "concrete", (0.5, 0.26, 0.07), (0.26, -0.6, 0.035))
    k.model(r, "industrial_wall_lamp", 0.16, (0.0, -0.53, 0.5), 0)
    k.lamp(r, (0.02, -0.72, 0.44), WARM, p.get("power", 12), 0.1)


def mast(k, r, p):
    k.part(r, "box", "concrete", (0.76, 0.76, 0.24), (0, 0, 0.12))
    height, foot = 2.6, 0.27
    for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        k.part(r, "cyl", "rust", (0.045, 0.045, height), (sx * foot / 2, sy * foot / 2, 0.24 + height / 2),
               (sy * math.atan(foot / height), -sx * math.atan(foot / height), 0))
    for level in range(1, 7):
        z = 0.24 + level * height / 7
        span = foot * 2 * (1 - level / 7)
        for sx, sy, wide in ((0, 1, True), (0, -1, True), (1, 0, False), (-1, 0, False)):
            k.part(r, "box", "rust", (span if wide else 0.02, 0.02 if wide else span, 0.022),
                   (sx * span / 2, sy * span / 2, z))
    k.part(r, "ball", "glow_green", (0.09, 0.09, 0.09), (0, 0, 0.3 + height))
    k.lamp(r, (0, 0, 0.3 + height), GREEN, 2.5)


def radio_box(k, r, p):
    k.part(r, "box", "paint", (0.34, 0.26, 0.42), (0, 0, 0.21))
    k.part(r, "box", "glow_green", (0.2, 0.012, 0.09), (0, -0.135, 0.28))
    k.lamp(r, (0, -0.28, 0.3), GREEN, 1.6, 0.06)


def fence(k, r, p):
    for i in range(5):
        k.part(r, "box", "planks", (0.07, 0.07, 0.5), (-0.8 + i * 0.4, 0, 0.25), (0, 0.06 * (i - 2), 0))
    for z, drop in ((0.18, 0.02), (0.38, -0.03)):
        k.part(r, "box", "planks", (1.74, 0.035, 0.07), (0, 0, z), (0, drop, 0))


def scrap(k, r, p):
    k.part(r, "box", "rust", (0.3, 0.3, 0.2), (0, 0, 0.1), (0, 0, 0.3))
    k.model(r, "metal_jerrycan", 0.26, (0.34, -0.1, 0), 30)
    k.part(r, "cyl", "rust", (0.27, 0.27, 0.4), (0.36, 0.2, 0.2))
    k.model(r, "rusted_wheel_rim_01", 0.32, (-0.1, -0.36, 0), 200)


def wall(k, r, p):
    for x, width, height, lean in ((-0.72, 0.72, 0.34, 0.03), (0.06, 0.6, 0.2, -0.06), (0.72, 0.46, 0.27, 0.05)):
        k.part(r, "box", "concrete", (width, 0.22, height), (x, 0, height / 2), (0, lean, 0))
    k.part(r, "cyl", "rust", (0.022, 0.022, 0.3), (0.42, 0, 0.3), (0.25, 0.3, 0))
    if p.get("rubble", True):
        k.model(r, "stone_01", 0.3, (-0.3, -0.26, 0), 40)
        k.model(r, "rock_07", 0.34, (0.42, -0.22, 0), 120)


def dead_tree(k, r, p):
    k.model(r, "dry_branches_medium_01", p.get("span", 1.2), turn=p.get("face", 30))


# How far plants and stones keep from each prop, in scene units, so nothing grows over them.
ROOM = dict(diner=1.7, shack=1.0, robot=0.75, mast=0.6, fuel_pump=0.35, drums=0.5, crates=0.6, tires=0.45, sandbags=0.7, glow=0.0,
            lamp_post=0.2, fence=0.7, dead_tree=0.2, wall=0.7, radio_box=0.3)
ROOM |= UTOPIA_ROOM | HALLOWEEN_ROOM | VOLCANO_ROOM
PROPS = dict(diner=diner, fuel_pump=fuel_pump, lamp_post=lamp_post, glow=glow, sandbags=sandbags, crates=crates, drums=drums,
             tires=tires, robot=robot, shack=shack, mast=mast, radio_box=radio_box, fence=fence, scrap=scrap, wall=wall,
             dead_tree=dead_tree) | UTOPIA_PROPS | HALLOWEEN_PROPS | VOLCANO_PROPS


# --- scene -----------------------------------------------------------------------

def add_ghosts(scene, camera, view):
    """Stand-ins pinned to the camera, one unit away: each lands exactly where the board draws it and nothing hides it."""
    collection = bpy.data.collections.new(f"{view.variant} stand-ins (not rendered)")
    scene.collection.children.link(collection)
    colours = dict(table=((0.92, 0.88, 0.78), 0.5), hand=((0.5, 0.72, 1.0), 0.45), pile=((1.0, 0.82, 0.4), 0.6),
                   ui=((1.0, 0.45, 0.15), 0.55))
    objects = []
    for layer, (kind, rects) in enumerate(GHOSTS[view.variant].items()):
        verts, faces = [], []
        for i, (x, y, w, h) in enumerate(rects):
            depth = 1 - (layer * 40 + i) * 2e-5
            corners = [view.lens_point(p) for p in ((x, y + h), (x + w, y + h), (x + w, y), (x, y))]
            faces.append(list(range(len(verts), len(verts) + 4)))
            verts += [(cx * depth, cy * depth, -depth) for cx, cy, _ in corners]
        mesh = bpy.data.meshes.new(f"{view.variant}-{kind}")
        mesh.from_pydata(verts, [], faces)
        colour, alpha = colours[kind]
        mesh.materials.append(ghost_material(mesh.name, colour, alpha))
        obj = bpy.data.objects.new(mesh.name, mesh)
        obj.parent, obj.hide_render = camera, True
        collection.objects.link(obj)
        objects.append(obj)
    return collection, objects


def add_front_wall(kit, view, spec):
    """A wall across the whole screen. Its highest point on screen is the foot of its table side, because the camera stands
    over the table, so that foot goes on the line where the hand tucks away and no card overlaps the wall."""
    height, depth = spec["height"], spec["depth"]
    line = view.to_ground((view.screen[0] / 2, RAIL_TOP[view.variant]))[1]
    root = kit.root(f"{view.variant}-front-wall", (0, line - depth / 2, 0), 0, 1)
    kit.part(root, "box", spec["material"], (16, depth, height + 0.6), (0, 0, height / 2 - 0.3))
    # Thin trim along both edges; the top stays the wall's own stone.
    for side in (-1, 1):
        kit.part(root, "box", spec["cap"], (16, 0.035, 0.016), (0, side * (depth / 2 - 0.012), height + 0.006))


def world_matrix(obj):
    matrix = obj.matrix_basis.copy()
    while obj.parent:
        obj = obj.parent
        matrix = obj.matrix_basis @ matrix
    return matrix


def surface_points(obj):
    """Scene positions across a part: its vertices, and points over each face of a low-poly shape."""
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    if len(co) < 200:
        fill = [sum(co[i] * w for i, w in zip(face.vertices, weights)) for face in obj.data.polygons if len(face.vertices) == 4
                for weights in ((u * v, (1 - u) * v, (1 - u) * (1 - v), u * (1 - v)) for u in np.linspace(0, 1, 7) for v in np.linspace(0, 1, 7))]
        co = np.array(fill) if fill else co
    matrix = np.array(world_matrix(obj))
    return co @ matrix[:3, :3].T + matrix[:3, 3]


def check(collection, ground, view, moon_dir):
    """What stands, or falls in shadow, on the card rows from this camera. Each entry is the part of it inside them."""
    x, y, w, h = ZONES[view.variant]["cards"][0][1]
    def within(points):
        sx, sy = view.to_screen_many(points)
        keep = (sx > x) & (sx < x + w) & (sy > y) & (sy < y + h)
        return sx[keep], sy[keep]
    fall = np.array(moon_dir)
    hits, shadows, tris = {}, {}, 0
    for obj in collection.all_objects:
        if obj.type != "MESH" or obj.name.endswith("-ground") or not obj.data.polygons:
            continue
        tris += sum(len(p.vertices) - 2 for p in obj.data.polygons)
        owner = obj.parent.name if obj.parent else obj.name
        points = surface_points(obj)
        sx, sy = within(points)
        if len(sx):
            box = hits.setdefault(owner, [1e9, 1e9, -1e9, -1e9])
            box[:] = [min(box[0], sx.min()), min(box[1], sy.min()), max(box[2], sx.max()), max(box[3], sy.max())]
        cast = points[points[:, 2] > 0.03]
        sx, sy = within(cast + np.outer(cast[:, 2] / -fall[2], fall))
        if len(sx):
            box = shadows.setdefault(owner, [1e9, 1e9, -1e9, -1e9])
            box[:] = [min(box[0], sx.min()), min(box[1], sy.min()), max(box[2], sx.max()), max(box[3], sy.max())]
    bumps = sum(1 for (i, j), z in np.ndenumerate(ground.height) if z > 0.02
                and inside(view.to_screen((ground.xs[j], ground.ys[i], z)), (x, y, w, h)))
    round_all = lambda found: {k: [round(float(v)) for v in box] for k, box in found.items()}
    return dict(in_card_rows=round_all(hits), shadows_in_card_rows=round_all(shadows), ground_bumps_in_card_rows=bumps,
                prop_tris=tris, ground_tris=(ground.height.shape[0] - 1) * (ground.height.shape[1] - 1) * 2)


def check_seats(scene, view):
    """What each resting place lands on, seen from the camera: one flat surface, or it fails."""
    scene.view_layers[0].update()
    depsgraph = scene.view_layers[0].depsgraph
    depsgraph.update()
    origin = Vector(view.location)
    report = {}
    for name, (x, y, w, h) in SEATS[view.variant].items():
        surfaces, heights, flat, spots = {}, [], [], {}
        for u in np.linspace(0.02, 0.98, 7):
            for v in np.linspace(0.02, 0.98, 7):
                ray = (Vector(view.to_ground((x + u * w, y + v * h))) - origin).normalized()
                hit, where, normal, _, obj, _ = scene.ray_cast(depsgraph, origin + ray * 3, ray)
                if not hit:
                    surfaces["nothing"] = surfaces.get("nothing", 0) + 1
                    continue
                source = obj.original
                owner = source.parent.name if source.parent else source.name
                owner = "floor" if owner.endswith(("-ground", "-pebbles")) else owner
                surfaces[owner] = surfaces.get(owner, 0) + 1
                spots.setdefault(owner, []).append((round(float(x + u * w)), round(float(y + v * h))))
                heights.append(where.z)
                flat.append(normal.z)
        rise = max(heights) - min(heights) if heights else 0
        level = float(np.median(flat)) if flat else 0
        report[name] = dict(ok=len(surfaces) == 1 and rise < 0.1 and level > 0.9, on=surfaces, rise=round(rise, 3), level=round(level, 2))
        if len(surfaces) > 1:
            report[name]["stray"] = min(spots.values(), key=len)
    return report


def build_variant(scene, world, materials, library, moon, moon_dir, rng):
    variant = scene.name.lower()
    view = View(variant)
    spec = world[variant]
    scene.collection.children.link(moon)
    collection = bpy.data.collections.new(f"{variant} set")
    scene.collection.children.link(collection)

    ground = Ground(view, rng, spec["clear"], world["ground"].get("relief", 1.0), world["ground"].get("grass"),
                    world["ground"].get("grass_in_rows", 1.0))
    collection.objects.link(ground.mesh(f"{variant}-ground", materials["ground"]))
    collection.objects.link(scatter_pebbles(f"{variant}-pebbles", spec["pebbles"], ground, view, rng, materials["rock"]))
    kit = Kit(collection, materials, library, rng, *(linear(world[key]) if key in world else None for key in ("warm", "cool")))
    kit.rake = world.get("rake", 0)
    spots = []
    for i, prop in enumerate(spec["props"]):
        x, y, _ = view.to_ground(prop["at"])
        size = prop.get("size", 1)
        z = ground.sample(x, y, ground.height) - 0.01
        root = kit.root(f"{variant}-{prop['kind']}.{i}", (x, y, z), prop.get("turn", 0), size)
        root.scale.z *= prop.get("low", 1)
        if world.get("rake") and not prop.get("seat") and prop["kind"] != "glow":
            lean, _ = raked(view, x, y, world["rake"])
            root.rotation_euler = (lean @ Matrix.Rotation(math.radians(prop.get("turn", 0)), 4, "Z")).to_euler()
        PROPS[prop["kind"]](kit, root, prop)
        spots.append((x, y, ROOM.get(prop["kind"], 0.4) * size))
    if spec.get("front_wall"):
        add_front_wall(kit, view, spec["front_wall"])
    if spec.get("tufts"):
        collection.objects.link(scatter_tufts(f"{variant}-tufts", spec["tufts"], ground, view, rng, materials["leaf"]))
    for name, band in spec["scatter"].items():
        scatter_models(kit, f"{variant}-{name}", band, ground, view, rng, moon_dir, spots)

    data = bpy.data.cameras.new(f"{variant} table camera")
    data.lens, data.sensor_width, data.sensor_height = view.lens, SENSOR, SENSOR
    data.sensor_fit, data.clip_end = "HORIZONTAL" if variant == "landscape" else "VERTICAL", 200
    camera = bpy.data.objects.new(data.name, data)
    camera.location, camera.rotation_euler = view.location, (view.pitch, 0, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera
    ghosts, ghost_objects = add_ghosts(scene, camera, view)
    return view, ground, collection, ghosts, ghost_objects


def render_settings(scene, world, width, height, percent, samples):
    render = scene.render
    render.engine = "CYCLES"
    render.resolution_x, render.resolution_y, render.resolution_percentage = width, height, percent
    render.image_settings.file_format = "PNG"
    render.film_transparent = False
    scene.cycles.samples, scene.cycles.use_denoising, scene.cycles.device = samples, True, "GPU"
    scene.view_settings.view_transform = world.get("view", "AgX")
    scene.view_settings.look = "AgX - Medium High Contrast" if world.get("view", "AgX") == "AgX" else "None"
    scene.view_settings.exposure = world["exposure"]
    scene.cycles.max_bounces, scene.cycles.sample_clamp_indirect = 6, 8
    tree = bpy.data.node_groups.new(f"{scene.name} glow", "CompositorNodeTree")
    tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers, bloom, out = tree.nodes.new("CompositorNodeRLayers"), tree.nodes.new("CompositorNodeGlare"), tree.nodes.new("NodeGroupOutput")
    layers.scene = scene
    source = layers.outputs["Image"]
    paint = world.get("paint")
    if paint:
        # Painted renders come from removing realism: Kuwahara turns detail into brush shapes, and shadows lift and shift colour.
        brush = tree.nodes.new("CompositorNodeKuwahara")
        brush.inputs["Size"].default_value = paint["brush"] * percent / 100
        brush.inputs["Type"].default_value = "Anisotropic"
        tree.links.new(source, brush.inputs["Image"])
        grade = tree.nodes.new("CompositorNodeColorBalance")
        for name, colour in (("Lift", paint["shadows"]), ("Gain", paint["lights"])):
            socket = next(i for i in grade.inputs if i.name == name and i.type == "RGBA")
            socket.default_value = (*colour, 1)
        tree.links.new(brush.outputs["Image"], grade.inputs["Image"])
        source = grade.outputs["Image"]
    tree.links.new(source, bloom.inputs["Image"])
    tree.links.new(bloom.outputs["Image"], out.inputs[0])
    bloom.inputs["Type"].default_value = "Bloom"
    bloom.inputs["Threshold"].default_value = world["bloom"]["threshold"]
    bloom.inputs["Strength"].default_value = world["bloom"]["strength"]
    scene.compositing_node_group = tree


def render_cards_over(scene, ghost_collection, ghost_objects, plate, out):
    """The plate with the stand-ins over it, as a check image."""
    layer = scene.view_layers[0].layer_collection
    excluded = [c for c in layer.children if c.collection is not ghost_collection]
    for child in excluded:
        child.exclude = True
    for obj in ghost_objects:
        obj.hide_render = False
    render, cycles = scene.render, scene.cycles
    render.film_transparent, cycles.samples, cycles.use_denoising = True, 8, False
    view_transform, look = scene.view_settings.view_transform, scene.view_settings.look
    scene.view_settings.view_transform, scene.view_settings.look = "Standard", "None"
    render.use_compositing = False
    render.filepath = str(out.with_suffix(".layer.png"))
    bpy.ops.render.render(scene=scene.name, write_still=True)
    scene.view_settings.view_transform, scene.view_settings.look = view_transform, look
    base, cards = bpy.data.images.load(str(plate)), bpy.data.images.load(render.filepath)
    width, height = base.size
    a, b = np.empty(width * height * 4, np.float32), np.empty(width * height * 4, np.float32)
    base.pixels.foreach_get(a)
    cards.pixels.foreach_get(b)
    alpha = b[3::4].repeat(4)
    mixed = a * (1 - alpha) + b * alpha
    mixed[3::4] = 1
    result = bpy.data.images.new(out.stem, width, height)
    result.pixels.foreach_set(mixed)
    result.filepath_raw, result.file_format = str(out), "PNG"
    result.save()
    out.with_suffix(".layer.png").unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--world", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--scale", type=int, default=100)
    parser.add_argument("--samples", type=int, default=64)
    parser.add_argument("--assets", default="~/Movies/motion-assets/magicmobile-boards")
    parser.add_argument("--only", choices=VARIANTS)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    world = json.load(open(args.world))
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(world["seed"])
    stem = Path(args.world).stem.replace("_", "-")
    root = Path(args.assets).expanduser()

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    first = bpy.context.scene
    first.name = "Landscape"
    scenes = [first, bpy.data.scenes.new("Portrait")]

    textures = TextureSets(root)
    materials = {}
    for key, spec in world["materials"].items():
        materials[key] = textured(textures, key, spec["set"], spec["tile"], linear(spec.get("tint", "#ffffff")),
                                  spec.get("metal", 0.0), spec.get("bump", 1.0), spec.get("wear", 0.0))
    for key, colour in world["palette"].items():
        materials[key] = plain(key, linear(colour))
    for key, spec in world.get("finishes", {}).items():
        materials[key] = plain(key, linear(spec["colour"]), spec.get("rough", 0.8), spec.get("metal", 0.0), spec.get("glow", 0.0), spec.get("glass", 0.0))
    library = Library(root, stem, rng, materials["twig"], world["dry_plants"], world.get("trim", {}))
    library.materials = materials
    materials["ground"] = ground_material(textures, world["ground"], linear(world["ground"]["open_tint"]), linear(world["ground"]["rough_tint"]))
    materials["glow_warm"] = plain("glow_warm", WARM, glow=world["glow"])
    materials["glow_green"] = plain("glow_green", GREEN, glow=world["glow"] * 1.5)
    materials["glow_soft"] = plain("glow_soft", linear(world.get("warm", "#ffc070")), glow=world["glow"])
    materials["glow_cool"] = plain("glow_cool", linear(world.get("cool", "#9fe8ff")), glow=world["glow"] * 1.5)

    moon = bpy.data.collections.new("moon")
    light = bpy.data.lights.new("moon", "SUN")
    light.color, light.energy, light.angle = linear(world["moon"]["colour"]), world["moon"]["energy"], math.radians(world["moon"]["soft"])
    sun = bpy.data.objects.new("moon", light)
    sun.rotation_euler = (-math.radians(world["moon"]["tilt"]), 0, math.radians(world["moon"]["turn"]))
    moon.objects.link(sun)
    moon_dir = sun.rotation_euler.to_matrix() @ Vector((0, 0, -1))

    sky = bpy.data.worlds.new("night")
    if sky.node_tree is None:
        sky.use_nodes = True
    background = next(n for n in sky.node_tree.nodes if n.type == "BACKGROUND")
    background.inputs["Color"].default_value = (*linear(world["sky"]), 1)
    background.inputs["Strength"].default_value = world["sky_strength"]

    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for device in prefs.devices:
            device.use = True
    except Exception as exc:
        print("[world] GPU unavailable:", exc)

    built, report = {}, {}
    for scene in scenes:
        scene.world = sky
        view, ground, collection, ghosts, objects = build_variant(scene, world, materials, library, moon, moon_dir, rng)
        render_settings(scene, world, *[v * 2 for v in view.screen], args.scale, args.samples)
        built[scene.name] = (view, ghosts, objects)
        report[view.variant] = check(collection, ground, view, moon_dir)
        report[view.variant]["seats"] = check_seats(scene, view)
    blend = out / f"{stem}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    (out / "qa.json").write_text(json.dumps(report, indent=1))
    print("@@JSON@@" + json.dumps(report))

    if args.render:
        for scene in scenes:
            view, ghosts, objects = built[scene.name]
            if args.only and args.only != view.variant:
                continue
            plate = out / f"{view.variant}.png"
            scene.render.filepath = str(plate)
            bpy.ops.render.render(scene=scene.name, write_still=True)
            render_cards_over(scene, ghosts, objects, plate, out / f"{view.variant}-cards.png")


main()
