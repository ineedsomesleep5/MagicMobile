"""Props for the Utopia world, built from shapes so they stay crisp and white-and-gold. Used by arena_world.py."""
import math


def _ring(inner, outer, start, end, low, high, segments=36):
    """An arc of a raised ring: its top, both walls and both ends."""
    verts, faces = [], []
    for i in range(segments + 1):
        angle = math.radians(start + (end - start) * i / segments)
        c, s = math.cos(angle), math.sin(angle)
        verts += [(inner * c, inner * s, high), (outer * c, outer * s, high), (outer * c, outer * s, low), (inner * c, inner * s, low)]
    for i in range(segments):
        a, b = i * 4, (i + 1) * 4
        faces += [(a, a + 1, b + 1, b), (a + 1, a + 2, b + 2, b + 1), (a + 2, a + 3, b + 3, b + 2), (a + 3, a, b, b + 3)]
    faces += [(0, 3, 2, 1), (segments * 4, segments * 4 + 1, segments * 4 + 2, segments * 4 + 3)]
    return verts, faces


def terrace(k, r, p):
    """Curved stone tiers around a pool, edged in gold."""
    radius, start, end = p.get("radius", 1.1), p.get("start", -100), p.get("end", 100)
    k.mesh(r, "pool", *_ring(0.01, radius * 0.72, start, end, 0.0, 0.17), "water", True)
    k.mesh(r, "tier", *_ring(radius * 0.72, radius, start, end, 0.0, 0.26), "marble", True)
    k.mesh(r, "rim", *_ring(radius * 0.97, radius * 1.01, start, end, 0.26, 0.3), "gold", True)
    k.mesh(r, "lip", *_ring(radius * 0.7, radius * 0.75, start, end, 0.17, 0.32), "gold", True)
    k.mesh(r, "upper", *_ring(0.01, radius * 0.36, start, end, 0.0, 0.42), "stone", True)
    k.mesh(r, "upper-rim", *_ring(radius * 0.33, radius * 0.37, start, end, 0.42, 0.46), "gold", True)


def waterfall(k, r, p):
    """Water running down a steep stone slope, so it shows from the table's high camera."""
    height, width = p.get("height", 0.75), p.get("width", 0.34)
    run = height * 0.8
    slope = math.atan2(run, height)
    length = math.hypot(run, height)
    k.part(r, "box", "marble", (width + 0.14, 0.2, height), (0, run + 0.1, height / 2))
    k.part(r, "box", "gold", (width + 0.17, 0.22, 0.025), (0, run + 0.1, height + 0.012))
    for side in (-1, 1):
        k.part(r, "box", "marble", (0.05, run + 0.1, height * 0.5), (side * (width / 2 + 0.03), run / 2, height * 0.25))
    k.part(r, "box", "foam", (width, 0.03, length), (0, run / 2, height / 2), (-slope, 0, 0))
    k.mesh(r, "pool", *_ring(0.01, width * 1.1, 0, 360, 0.0, 0.03), "water", True)
    k.lamp(r, (0, -0.3, 0.3), k.cool, 2, 0.2)


def cascade(k, r, p):
    """The hero fountain: three curved basins stepping up from the plaza, with water spilling down between them."""
    radius, start, end = p.get("radius", 1.2), p.get("start", 200), p.get("end", 340)
    tiers = ((1.0, 0.0, 0.2), (0.7, 0.18, 0.46), (0.42, 0.42, 0.74))
    for share, low, high in tiers:
        outer, inner = radius * share, radius * share * 0.84
        k.mesh(r, "basin", *_ring(0.01, outer, start, end, low, high - 0.03), "water", True)
        k.mesh(r, "wall", *_ring(inner, outer, start, end, low, high), "marble", True)
        k.mesh(r, "rim", *_ring(outer * 0.985, outer * 1.015, start, end, high, high + 0.03), "gold", True)
    for share, top, foot, width in ((0.42, 0.72, 0.44, 0.34), (0.7, 0.44, 0.18, 0.5), (1.0, 0.18, 0.0, 0.62)):
        for spread in (-1, 1):
            angle = math.radians((start + end) / 2 + spread * 18 * (2 - share))
            x, y = math.cos(angle) * radius * share, math.sin(angle) * radius * share
            drop = top - foot
            k.part(r, "box", "foam", (width * 0.34, 0.02, drop + 0.02), (x, y - 0.03, foot + drop / 2), (0.12, 0, 0))
    k.part(r, "cyl", "gold", (0.09, 0.09, 0.42), (0, radius * 0.08, 0.9))
    k.part(r, "ball", "glow_cool", (0.13, 0.13, 0.2), (0, radius * 0.08, 1.2))
    k.lamp(r, (0, -radius * 0.7, 0.5), k.cool, 3, 0.3)


def dome(k, r, p):
    """A glass dome on a stone drum, with gold ribs."""
    radius, ribs = p.get("radius", 0.8), 10
    k.part(r, "cyl", "stone", (radius * 2.1, radius * 2.1, 0.16), (0, 0, 0.08))
    k.part(r, "cyl", "gold", (radius * 2.14, radius * 2.14, 0.03), (0, 0, 0.17))
    k.part(r, "ball", "glass", (radius * 2, radius * 2, radius * 1.5), (0, 0, 0.17))
    pairs = []
    for rib in range(ribs):
        around = math.tau * rib / ribs
        line = [(radius * math.cos(t) * math.cos(around), radius * math.cos(t) * math.sin(around), 0.17 + radius * 0.75 * math.sin(t))
                for t in (math.pi / 2 * i / 10 for i in range(11))]
        pairs += list(zip(line, line[1:]))
    k.beams(r, "gold", pairs, 0.022)
    k.part(r, "ball", "glow_soft", (0.1, 0.1, 0.1), (0, 0, 0.26 + radius * 0.75))
    k.lamp(r, (0, 0, 0.4), k.warm, 6, 0.4)


def pavilion(k, r, p):
    """A white pavilion with a flat deck on top, so cards can rest there, lit windows and slim columns."""
    width, depth, height = p.get("width", 2.4), p.get("depth", 1.5), p.get("height", 0.46)
    k.part(r, "box", "stone", (width, depth, height), (0, 0, height / 2))
    k.part(r, "box", "gold", (width + 0.05, depth + 0.05, 0.03), (0, 0, height + 0.015))
    k.part(r, "box", "deck", (width - 0.12, depth - 0.12, 0.012), (0, 0, height + 0.034))
    k.part(r, "box", "glow_soft", (width * 0.7, 0.012, height * 0.42), (0, -depth / 2 - 0.006, height * 0.52))
    for i in range(7):
        k.part(r, "cyl", "gold", (0.05, 0.05, height), (-width * 0.42 + i * width * 0.14, -depth / 2 - 0.03, height / 2))
    k.lamp(r, (0, -depth / 2 - 0.35, 0.34), k.warm, p.get("power", 5), 0.3)


def stairs(k, r, p):
    steps, width = p.get("steps", 5), p.get("width", 1.0)
    for i in range(steps):
        k.part(r, "box", "stone", (width, 0.13, 0.05 * (steps - i)), (0, 0.13 * i, 0.025 * (steps - i)))
    for x in (-1, 1):
        k.part(r, "box", "gold", (0.05, 0.13 * steps, 0.05), (x * width / 2, 0.13 * (steps - 1) / 2, 0.3))


def bridge(k, r, p):
    """A slim arched footbridge."""
    span, rise = p.get("span", 1.8), p.get("rise", 0.32)
    line = [(span * (i / 16 - 0.5), 0.0, 0.1 + rise * math.sin(math.pi * i / 16)) for i in range(17)]
    for a, b in zip(line, line[1:]):
        k.beams(r, "stone", [(a, b)], 0.13, width=0.46)
    rail = [[(x, side * 0.23, z + 0.13) for x, _, z in line] for side in (-1, 1)]
    k.beams(r, "gold", [pair for side in rail for pair in zip(side, side[1:])], 0.02)


def sail(k, r, p):
    """A white solar sail on a slim gold mast."""
    height, width = p.get("height", 1.5), p.get("width", 1.0)
    k.part(r, "cyl", "gold", (0.05, 0.05, height), (0, 0, height / 2))
    verts, faces, rows = [], [], 8
    for row in range(rows + 1):
        taper = 1 - row / rows
        for col in range(rows + 1):
            u = col / rows
            verts.append((u * width * taper, 0.22 * math.sin(math.pi * u) * taper, 0.25 + (height - 0.3) * row / rows))
    for row in range(rows):
        for col in range(rows):
            a = row * (rows + 1) + col
            faces.append((a, a + 1, a + rows + 2, a + rows + 1))
    k.mesh(r, "sail", verts, faces, "sailcloth", True)


def cypress(k, r, p):
    height = p.get("height", 1.1)
    k.part(r, "cyl", "bark", (0.06, 0.06, 0.2), (0, 0, 0.1))
    k.part(r, "ball", "leaf_dark", (height * 0.3, height * 0.3, height), (0, 0, 0.14 + height / 2))


def blossom_tree(k, r, p):
    k.part(r, "cyl", "bark", (0.05, 0.05, 0.34), (0, 0, 0.17), (0.05, 0.04, 0))
    k.model(r, f"bush_{p.get('bloom', 'blossom')}", p.get("span", 1.0), (0, 0, 0.2))


def crystal_lamp(k, r, p):
    height = p.get("height", 0.62)
    k.part(r, "cyl", "gold", (0.035, 0.035, height), (0, 0, height / 2))
    k.part(r, "ball", "glow_cool", (0.09, 0.09, 0.2), (0, 0, height + 0.1))
    k.lamp(r, (0, 0, height + 0.1), k.cool, p.get("power", 1.5), 0.08)


def balustrade(k, r, p):
    """A low curved wall with gold posts."""
    radius, start, end = p.get("radius", 3.5), p.get("start", 65), p.get("end", 115)
    k.mesh(r, "wall", *_ring(radius - 0.11, radius + 0.11, start, end, 0.0, 0.2), "stone", True)
    k.mesh(r, "rail", *_ring(radius - 0.12, radius + 0.12, start, end, 0.2, 0.24), "gold", True)


UTOPIA_PROPS = dict(cascade=cascade, terrace=terrace, waterfall=waterfall, dome=dome, pavilion=pavilion, stairs=stairs, bridge=bridge, sail=sail,
                    cypress=cypress, blossom_tree=blossom_tree, crystal_lamp=crystal_lamp, balustrade=balustrade)
UTOPIA_ROOM = dict(cascade=1.2, terrace=0.9, waterfall=0.4, dome=1.0, pavilion=1.4, stairs=0.5, bridge=0.8, sail=0.3, cypress=0.15,
                   blossom_tree=0.35, crystal_lamp=0.1, balustrade=0.5)
