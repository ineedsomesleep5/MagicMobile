#!/usr/bin/env python3
"""Safe-zone templates for new Arena board themes, from ArenaLayout (apps/ios/MagicMobile/ArenaBoardModel.swift).
Red stays quiet (cards land there), blue is UI over the table, green is the best place for scenery.

  python3 scripts/brand/arena_safe_zones.py <out dir>                       write the templates
  python3 scripts/brand/arena_safe_zones.py --check <mock.png> <out.png>    lay the zones over a mock-up (needs Pillow)
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

from arena_zones import RAIL_TOP, SEATS, ZONES as LAYOUTS

SCALE = 2
FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 20)

def scaled(rect):
    x, y, w, h = rect
    return [x * SCALE, y * SCALE, (x + w) * SCALE, (y + h) * SCALE]

def zones(layout, name=None):
    """The guide on a transparent layer. With a variant's name, also its pile seats (yellow) and the hand's line (white)."""
    size = tuple(v * SCALE for v in layout["canvas"])
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    groups = (("cards", (255, 40, 40, 70), (255, 70, 70, 255)), ("scenery", (40, 255, 110, 70), (70, 255, 130, 255)),
              ("ui", (40, 130, 255, 90), (110, 180, 255, 255)))
    for group, fill, line in groups:
        for label, rect in layout[group]:
            box = scaled(rect)
            draw.rectangle(box, fill=fill, outline=line, width=2)
            if label:
                draw.text((box[0] + 6, box[1] + 3), label, font=FONT, fill=(255, 255, 255, 255),
                          stroke_width=2, stroke_fill=(0, 0, 0, 255))
    for label, rect in SEATS.get(name, {}).items():
        box = scaled(rect)
        draw.rectangle(box, fill=(255, 225, 60, 80), outline=(255, 235, 90, 255), width=3)
        draw.text((box[0] + 4, box[1] + 3), label, font=FONT, fill=(255, 255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0, 255))
    if name in RAIL_TOP:
        row = RAIL_TOP[name] * SCALE
        draw.line([(0, row), (size[0], row)], fill=(255, 255, 255, 255), width=3)
    return layer

def input_image(layout):
    """Plain shapes for the image model, with no words to copy."""
    size = tuple(v * SCALE for v in layout["canvas"])
    image = Image.new("RGB", size, (235, 235, 235))
    ImageDraw.Draw(image).rectangle(scaled(layout["cards"][0][1]), fill=(55, 55, 55))
    return image

def check(mock, out):
    image = Image.open(mock).convert("RGBA")
    name = "landscape" if image.width > image.height else "portrait"
    layout = LAYOUTS[name]
    size = tuple(v * SCALE for v in layout["canvas"])
    ratio = max(size[0] / image.width, size[1] / image.height)
    image = image.resize((round(image.width * ratio), round(image.height * ratio)), Image.LANCZOS)
    left, top = (image.width - size[0]) // 2, (image.height - size[1]) // 2
    image = image.crop((left, top, left + size[0], top + size[1]))
    Image.alpha_composite(image, zones(layout, name)).convert("RGB").save(out, quality=88)

if __name__ == "__main__":
    if sys.argv[1] == "--check":
        check(sys.argv[2], sys.argv[3])
    else:
        out = Path(sys.argv[1])
        out.mkdir(parents=True, exist_ok=True)
        for name, layout in LAYOUTS.items():
            backing = Image.new("RGBA", zones(layout).size, (24, 24, 28, 255))
            Image.alpha_composite(backing, zones(layout)).convert("RGB").save(out / f"safe-zones-{name}.png")
            input_image(layout).save(out / f"codex-input-{name}.png")
