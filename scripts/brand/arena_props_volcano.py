"""Props for the Volcano world. Plain shapes: the Codex repaint gives them their detail (docs/ARENA_WORLDS.md)."""
import math


def _blob(k, r, name, material, spots, low, high, turn=0.0):
    """A low uneven shape from overlapping discs."""
    for i, (x, y, size) in enumerate(spots):
        k.part(r, "cyl", material, (size, size * 0.8, high - low), (x, y, (low + high) / 2), (0, 0, turn + i))


def lava_pool(k, r, p):
    """A pool of lava inside a rim of cooled rock."""
    size = p.get("span", 1.0)
    spots = [(0, 0, size), (size * 0.42, size * 0.14, size * 0.7), (-size * 0.4, -size * 0.1, size * 0.66)]
    _blob(k, r, "rim", "basalt", [(x, y, s + 0.2) for x, y, s in spots], 0.0, 0.05)
    _blob(k, r, "lava", "lava", spots, 0.02, 0.07)
    k.lamp(r, (0, 0, 0.4), k.warm, p.get("power", 9) * size, 0.5)


def basalt_columns(k, r, p):
    """A cluster of hexagonal columns, tallest at the back."""
    size = p.get("size_top", 0.24)
    for ring in range(3):
        for i in range(3 + ring * 3):
            angle = math.tau * i / (3 + ring * 3) + ring
            x, y = math.cos(angle) * ring * size * 0.95, math.sin(angle) * ring * size * 0.95
            height = p.get("height", 0.8) * (1 - ring * 0.25) * float(k.rng.uniform(0.75, 1.1))
            k.hexagon(r, "basalt", size * 0.52, height, (x, y))


def obsidian_spire(k, r, p):
    """Jagged black glass shards rising from one foot."""
    height = p.get("height", 1.0)
    for i in range(5):
        lean = (float(k.rng.uniform(-0.3, 0.3)), float(k.rng.uniform(-0.3, 0.3)), float(k.rng.uniform(0, 3)))
        share = 1 - i * 0.14
        at = (float(k.rng.uniform(-0.14, 0.14)), float(k.rng.uniform(-0.14, 0.14)), height * share * 0.45)
        k.part(r, "spike", "obsidian", (0.26 * share, 0.2 * share, height * share), at, lean)


def ember_vent(k, r, p):
    """A low crack in the rock with a little light in it."""
    k.part(r, "cyl", "basalt", (0.5, 0.38, 0.1), (0, 0, 0.05))
    k.part(r, "cyl", "lava", (0.2, 0.12, 0.02), (0, 0, 0.1))
    k.lamp(r, (0, 0, 0.3), k.warm, p.get("power", 2), 0.1)


VOLCANO_PROPS = dict(lava_pool=lava_pool, basalt_columns=basalt_columns, obsidian_spire=obsidian_spire, ember_vent=ember_vent)
VOLCANO_ROOM = dict(lava_pool=0.8, basalt_columns=0.6, obsidian_spire=0.4, ember_vent=0.25)
