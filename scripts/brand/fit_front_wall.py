#!/usr/bin/env python3
"""Move a painted portrait plate's front wall onto the hand's line, without repainting (docs/ARENA_WORLDS.md).

  python3 scripts/brand/fit_front_wall.py <plate> <out> --top 1549 --bottom 1675 [--height 88]

--top and --bottom are the wall's rows in the 1912-row plate. It lands with its top on row 1630, slimmed to --height so your
piles stay clear of it. Everything below follows it, and the gap above is filled with a mirror of the ground over the wall.
Needs Pillow.
"""
import argparse

from PIL import Image, ImageOps

LINE = 1630

parser = argparse.ArgumentParser()
parser.add_argument("plate")
parser.add_argument("out")
parser.add_argument("--top", type=int, required=True)
parser.add_argument("--bottom", type=int, required=True)
parser.add_argument("--height", type=int, default=88)
args = parser.parse_args()

image = Image.open(args.plate).convert("RGB")
width, height = image.size
wall = image.crop((0, args.top, width, args.bottom)).resize((width, args.height), Image.LANCZOS)
result = image.copy()
gap = LINE - args.top
if gap > 0:
    result.paste(ImageOps.flip(image.crop((0, args.top - gap, width, args.top))), (0, args.top))
result.paste(wall, (0, LINE))
foot = LINE + args.height
result.paste(image.crop((0, args.bottom, width, args.bottom + height - foot)), (0, foot))
result.save(args.out)
