"""Props for the Halloween world. Plain shapes: the Codex repaint gives them their detail (docs/ARENA_WORLDS.md)."""
import math


def _pumpkin(k, r, at, size, lit):
    x, y = at
    k.part(r, "ball", "pumpkin", (size, size, size * 0.74), (x, y, size * 0.36))
    k.part(r, "cyl", "vine", (size * 0.12, size * 0.12, size * 0.2), (x, y, size * 0.78))
    if lit:
        k.part(r, "box", "glow_soft", (size * 0.42, size * 0.02, size * 0.24), (x, y - size * 0.47, size * 0.38))
        k.lamp(r, (x, y - size * 0.7, size * 0.4), k.warm, 2.2 * size, 0.1)


def pumpkins(k, r, p):
    """A patch: one big carved pumpkin and a few smaller ones."""
    size = p.get("big", 0.5)
    _pumpkin(k, r, (0, 0), size, True)
    for x, y, share, lit in ((0.5, 0.12, 0.62, True), (-0.46, 0.2, 0.7, False), (0.2, 0.46, 0.5, True), (-0.2, -0.38, 0.42, False)):
        _pumpkin(k, r, (x, y), size * share, lit)


def cottage(k, r, p):
    """A crooked cottage with a steep roof and lit windows."""
    k.part(r, "box", "planks", (1.3, 0.96, 0.6), (0, 0, 0.3))
    for side in (-1, 1):
        k.part(r, "box", "roof", (1.54, 0.72, 0.05), (0, side * 0.27, 0.86), (side * 0.72, 0, 0))
    k.part(r, "box", "stone", (0.24, 0.24, 0.9), (0.42, 0.2, 0.86), (0, 0.05, 0))
    for x in (-0.4, 0.42):
        k.part(r, "box", "glow_soft", (0.24, 0.015, 0.24), (x, -0.485, 0.34))
    k.part(r, "box", "door", (0.28, 0.02, 0.46), (0.02, -0.49, 0.23))
    k.part(r, "box", "stone", (0.5, 0.28, 0.07), (0.02, -0.62, 0.035))
    k.lamp(r, (0, -0.8, 0.46), k.warm, p.get("power", 9), 0.14)


def headstones(k, r, p):
    for x, y, w, h, lean in ((0, 0, 0.3, 0.44, 0.06), (0.42, 0.16, 0.26, 0.36, -0.09), (-0.42, 0.14, 0.26, 0.38, 0.1), (0.2, 0.46, 0.24, 0.34, -0.05), (-0.2, 0.5, 0.26, 0.4, 0.08)):
        k.part(r, "box", "stone", (w, 0.09, h), (x, y, h / 2), (0, lean, 0))
        k.part(r, "cyl", "stone", (w, 0.09, w), (x, y, h), (math.pi / 2, 0, 0))


def iron_fence(k, r, p):
    span, posts = p.get("span", 1.7), 9
    pairs = [((-span / 2 + span * i / (posts - 1), 0, 0), (-span / 2 + span * i / (posts - 1), 0, 0.5)) for i in range(posts)]
    pairs += [((-span / 2, 0, z), (span / 2, 0, z)) for z in (0.14, 0.4)]
    k.beams(r, "gold", pairs, 0.025)


def gnarled_tree(k, r, p):
    """A bare twisted tree."""
    height = p.get("height", 1.2)
    k.part(r, "cyl", "bark", (0.2, 0.2, height * 0.55), (0, 0, height * 0.27), (0.1, 0.08, 0))
    pairs, tips = [], [(0.02, 0.0, height * 0.5)]
    for depth, reach in enumerate((0.42, 0.3, 0.2)):
        grown = []
        for tip in tips:
            for turn in (k.rng.uniform(0, 6.28), k.rng.uniform(0, 6.28)):
                end = (tip[0] + math.cos(turn) * reach, tip[1] + math.sin(turn) * reach, tip[2] + reach * 0.75)
                pairs.append((tip, end))
                grown.append(end)
        tips = grown
    k.beams(r, "bark", pairs, 0.03)


def scarecrow(k, r, p):
    k.part(r, "cyl", "bark", (0.06, 0.06, 1.0), (0, 0, 0.5))
    k.part(r, "box", "bark", (0.8, 0.05, 0.05), (0, 0, 0.74))
    k.part(r, "box", "cloth", (0.36, 0.14, 0.46), (0, 0, 0.56))
    k.part(r, "ball", "cloth", (0.2, 0.2, 0.22), (0, 0, 0.92))
    k.part(r, "cyl", "hat", (0.34, 0.34, 0.03), (0, 0, 1.02))
    k.part(r, "cyl", "hat", (0.16, 0.16, 0.2), (0, 0, 1.12))


def lantern(k, r, p):
    height = p.get("height", 0.8)
    k.part(r, "cyl", "gold", (0.04, 0.04, height), (0, 0, height / 2))
    k.part(r, "box", "gold", (0.24, 0.03, 0.03), (0.1, 0, height))
    k.part(r, "box", "glow_soft", (0.1, 0.1, 0.14), (0.2, 0, height - 0.1))
    k.lamp(r, (0.2, 0, height - 0.12), k.warm, p.get("power", 5), 0.1)


HALLOWEEN_PROPS = dict(pumpkins=pumpkins, cottage=cottage, headstones=headstones, iron_fence=iron_fence, gnarled_tree=gnarled_tree,
                       scarecrow=scarecrow, lantern=lantern)
HALLOWEEN_ROOM = dict(pumpkins=0.6, cottage=1.1, headstones=0.6, iron_fence=0.6, gnarled_tree=0.3, scarecrow=0.3, lantern=0.15)
