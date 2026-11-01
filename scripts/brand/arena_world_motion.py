#!/usr/bin/env python3
"""Build a world's motion data from its finished plates (docs/ARENA_WORLDS.md). The masks come from the paint itself, so they
never drift from it: lava, water and lit windows are found by colour, and the patches and particles come from
scripts/brand/arena_worlds/<name>.motion.json.

  python scripts/brand/arena_world_motion.py [--preview <dir>]        (needs Pillow, numpy and scipy)

Writes, for every world with a motion file:
  Assets.xcassets/arena-world-<slug>-<variant>-mask    which pixels flow (greyscale JPEG, half size)
  Assets.xcassets/arena-world-<slug>-<variant>-glow    what the lights add, over black (JPEG, half size)
  Resources/arena-worlds.json                          every world's flows, lights, particles and drifters
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
WORLDS = ROOT / "scripts/brand/arena_worlds"
CATALOG = ROOT / "apps/ios/MagicMobile/Assets.xcassets"
OUTPUT = ROOT / "apps/ios/MagicMobile/Resources/arena-worlds.json"
BOARD = {"landscape": (956, 440), "portrait": (440, 956)}
ROWS = {"landscape": (80, 54, 792, 306), "portrait": (12, 95, 416, 604)}


def ramp(x, low, high):
    return np.clip((x - low) / (high - low), 0, 1)


def pick(rgb, rule):
    """How much each pixel belongs to a material, from its painted colour."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    top = rgb.max(axis=-1)
    if rule == "lava":
        return ramp(r, 0.5, 0.8) * ramp(r - b, 0.25, 0.55)
    if rule == "water":
        return ramp(np.maximum(g, b) - r, 0.0, 0.1) * ramp(top, 0.25, 0.5)
    if rule == "white":
        return ramp(rgb.min(axis=-1), 0.55, 0.85)
    if rule == "warm":
        return ramp(r, 0.55, 0.9) * ramp(r - b, 0.18, 0.5)
    if rule == "green":
        return ramp(g - np.maximum(r, b), 0.1, 0.3) * ramp(g, 0.45, 0.8)
    if rule == "cool":
        return ramp(np.minimum(g, b) - r, 0.08, 0.3) * ramp(top, 0.6, 0.9)
    if rule == "plants":
        return ramp(g - b, 0.03, 0.14) * ramp(top, 0.14, 0.4)
    return np.ones(r.shape)


def oval(shape, box):
    """A soft oval over a rectangle of the mask."""
    height, width = shape
    x0, y0, x1, y1 = box
    ys, xs = np.mgrid[0:height, 0:width]
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    distance = np.hypot((xs - cx) / max((x1 - x0) / 2, 1), (ys - cy) / max((y1 - y0) / 2, 1))
    return np.clip((1 - distance) / 0.35, 0, 1)


def blobs(emissive, keep, limit):
    """Separate lit shapes, biggest first, as (x0, y0, x1, y1) boxes in mask pixels."""
    solid = ndimage.binary_dilation(emissive > 0.3, iterations=3)
    labels, count = ndimage.label(solid)
    found = []
    for index, area in enumerate(ndimage.sum(solid, labels, range(1, count + 1)), start=1):
        if area >= keep:
            ys, xs = np.where(labels == index)
            found.append((float(area), (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)))
    return [box for _, box in sorted(found, reverse=True)[:limit]]


def imageset(name, image, quality):
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(exist_ok=True)
    (folder / "Contents.json").write_text(json.dumps({"images": [{"filename": f"{name}.jpg", "idiom": "universal"}],
                                                      "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    image.save(folder / f"{name}.jpg", quality=quality, optimize=True)


def build(slug, variant, spec, preview):
    plate = Image.open(CATALOG / f"arena-world-{slug}-{variant}.imageset/arena-world-{slug}-{variant}.jpg").convert("RGB")
    board = BOARD[variant]
    size = (plate.width // 2, plate.height // 2)
    rgb = np.asarray(plate.resize(size, Image.LANCZOS), dtype=np.float32) / 255
    sx, sy = size[0] / board[0], size[1] / board[1]
    fraction = lambda rect: [round(rect[0] / board[0], 4), round(rect[1] / board[1], 4), round(rect[2] / board[0], 4), round(rect[3] / board[1], 4)]

    rows = np.zeros(rgb.shape[:2])
    x, y, w, h = ROWS[variant]
    rows[int(y * sy):int((y + h) * sy), int(x * sx):int((x + w) * sx)] = 1
    rows = ndimage.gaussian_filter(rows, 5)

    mask = np.zeros(rgb.shape[:2], dtype=np.float32)
    flows = []
    for flow in spec.get("flows", []):
        x, y, w, h = flow["rect"]
        box = (int(max(x, 0) * sx), int(max(y, 0) * sy), int(min(x + w, board[0]) * sx), int(min(y + h, board[1]) * sy))
        patch = np.zeros(mask.shape, dtype=np.float32)
        patch[box[1]:box[3], box[0]:box[2]] = 1
        patch = ndimage.gaussian_filter(patch, 3) * pick(rgb, flow.get("pick", "all"))
        if flow.get("oval"):
            patch = patch * oval(mask.shape, box)
        patch = ndimage.gaussian_filter(patch, 0.8) * (1 - rows)
        mask = np.maximum(mask, patch)
        flows.append(dict(kind=flow["kind"], rect=fraction((x, y, w, h)), dir=flow.get("dir", [0, 0]), speed=flow.get("speed", 1.0),
                          strength=flow.get("strength", 1.0), seed=round(abs(hash((x, y))) % 997 / 97.0, 2)))
    imageset(f"arena-world-{slug}-{variant}-mask", Image.fromarray((mask * 255).astype(np.uint8), "L"), 70)

    emissive = np.zeros(rgb.shape[:2], dtype=np.float32)
    lights = []
    for group in spec.get("lights", []):
        found = pick(rgb, group["pick"])
        if group.get("region"):
            x, y, w, h = group["region"]
            area = np.zeros(found.shape)
            area[int(y * sy):int((y + h) * sy), int(x * sx):int((x + w) * sx)] = 1
            found = found * area
        else:
            found = found * (1 - rows)
        emissive = np.maximum(emissive, found)
        for box in blobs(found, group.get("keep", 30), group.get("limit", 12)):
            pad = 4
            rect = (max(box[0] - pad, 0) / sx, max(box[1] - pad, 0) / sy, (box[2] - box[0] + pad * 2) / sx, (box[3] - box[1] + pad * 2) / sy)
            crop = rgb[box[1]:box[3], box[0]:box[2]]
            weight = found[box[1]:box[3], box[0]:box[2]][..., None] + 1e-4
            colour = (crop * weight).sum((0, 1)) / weight.sum()
            lights.append(dict(rect=fraction(rect), colour=[round(float(c), 3) for c in colour], style=group.get("style", "flicker"),
                               power=group.get("power", 1.0), halo=group.get("halo", 1.0)))
    # What a light adds: the painted shape, pushed hotter, over black, so turning it up really changes the picture. The cracks
    # in the card rows breathe with the rest.
    crack = spec.get("cracks")
    if crack:
        emissive = np.maximum(emissive, pick(rgb, crack) * 0.8)
    hot = np.clip(rgb * 1.2 + np.array(spec.get("hot", [0.34, 0.27, 0.1]), dtype=np.float32), 0, 1)
    glow = hot * emissive[..., None]
    imageset(f"arena-world-{slug}-{variant}-glow", Image.fromarray((glow * 255).astype(np.uint8), "RGB"), 72)

    if preview:
        sheet = plate.resize(size, Image.LANCZOS).convert("RGB")
        draw = ImageDraw.Draw(sheet)
        overlay = np.asarray(sheet, dtype=np.float32) * (1 - mask[..., None] * 0.6) + np.array([0, 255, 255]) * mask[..., None] * 0.6
        sheet = Image.fromarray(overlay.astype(np.uint8))
        draw = ImageDraw.Draw(sheet)
        for light in lights:
            x, y, w, h = light["rect"]
            draw.rectangle([x * size[0], y * size[1], (x + w) * size[0], (y + h) * size[1]], outline=(255, 255, 0))
        sheet.save(Path(preview) / f"{slug}-{variant}.jpg", quality=85)

    emit = [dict(kind=e["kind"], rect=fraction(e["rect"]), rate=e.get("rate", 1.0)) for e in spec.get("particles", [])]
    drift = spec.get("drifters", [])
    return dict(flows=flows, lights=lights, particles=emit, drifters=drift, cracks=bool(crack),
                hotspots=[fraction(h) for h in spec.get("hotspots", [])])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview")
    args = parser.parse_args()
    if args.preview:
        Path(args.preview).mkdir(parents=True, exist_ok=True)
    worlds = {}
    for path in sorted(WORLDS.glob("*.motion.json")):
        slug = path.name.removesuffix(".motion.json").replace("_", "-")
        spec = json.loads(path.read_text())
        worlds[slug] = dict(reactions=spec.get("reactions", {}), **{variant: build(slug, variant, spec[variant], args.preview) for variant in BOARD})
    OUTPUT.write_text(json.dumps(worlds, separators=(",", ":")) + "\n")
    print({slug: {v: (len(w[v]["flows"]), len(w[v]["lights"])) for v in BOARD} for slug, w in worlds.items()}, OUTPUT.stat().st_size)


main()
