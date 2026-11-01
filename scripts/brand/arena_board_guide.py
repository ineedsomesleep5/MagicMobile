#!/usr/bin/env python3
"""A grey 3D guide of the Arena table for concept art, seen through the plates' exact camera
(scripts/brand/tavern_table.py, arena_layout.json): a natural clearing, a one-unit grid and upright posts that show how
anything standing around it leans in this view. Colours: pale shape = open ground for cards, red posts = tall scenery.

  blender -b -P scripts/brand/arena_board_guide.py -- <out dir>
"""
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).parent))
from arena_camera import CAMERAS, LAYOUTS, U, View
from arena_zones import CLEARINGS

OUT = Path(sys.argv[sys.argv.index("--") + 1])


def material(name, colour):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*colour, 1)
    return mat


def box(name, centre, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
    obj = bpy.context.active_object
    obj.name, obj.scale = name, size
    obj.data.materials.append(mat)


def smooth(points, passes=3):
    for _ in range(passes):
        points = [p for a, b in zip(points, points[1:] + points[:1])
                  for p in (((3 * a[0] + b[0]) / 4, (3 * a[1] + b[1]) / 4), ((a[0] + 3 * b[0]) / 4, (a[1] + 3 * b[1]) / 4))]
    return points


def build(variant):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    sw, sh = LAYOUTS[variant]["screen"]
    x0, y0, x1, y1 = LAYOUTS[variant]["mat"]
    W, H = sw * U, sh * U
    left, right = x0 * U - W / 2, x1 * U - W / 2
    top, bottom = H / 2 - y0 * U, H / 2 - y1 * U
    ground = material("ground", (0.42, 0.42, 0.42))
    line = material("line", (0.30, 0.30, 0.32))
    clearing = material("clearing", (0.98, 0.95, 0.86))
    post = material("post", (0.75, 0.12, 0.10))
    reach = 30
    box("ground", (0, 0, -0.03), (reach * 2, reach * 2, 0.02), ground)
    for n in range(-reach, reach + 1):
        box(f"gx{n}", (n, 0, -0.018), (0.012, reach * 2, 0.004), line)
        box(f"gy{n}", (0, n, -0.018), (reach * 2, 0.012, 0.004), line)
    # Posts one unit tall stand a step off the mat, along every edge.
    step, gap = 1.0, 0.45
    for n in range(-14, 15):
        for x, y in ((n * step, top + gap), (n * step, bottom - gap), (left - gap, n * step), (right + gap, n * step)):
            if left - gap <= x <= right + gap and bottom - gap <= y <= top + gap:
                box(f"post{x}{y}", (x, y, 0.5), (0.1, 0.1, 1.0), post)

    data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", data)
    scene.collection.objects.link(cam)
    view = View(variant)
    data.lens = view.lens
    cam.location = view.location
    cam.rotation_euler = (view.pitch, 0, 0)
    data.clip_end = 200
    scene.camera = cam

    outline = [view.to_ground(p, -0.012) for p in smooth(CLEARINGS[variant])]
    mesh = bpy.data.meshes.new("clearing")
    mesh.from_pydata(outline, [], [list(range(len(outline)))])
    mesh.materials.append(clearing)
    scene.collection.objects.link(bpy.data.objects.new("clearing", mesh))

    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = False
    scene.render.resolution_x, scene.render.resolution_y = sw * 2, sh * 2
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(OUT / f"tilt-guide-{variant}.png")
    bpy.ops.render.render(write_still=True)


for name in CAMERAS:
    build(name)
