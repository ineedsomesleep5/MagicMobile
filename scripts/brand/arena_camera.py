"""The Arena table's camera (scripts/brand/tavern_table.py, arena_layout.json) as plain maths: board points on screen to
scene units on the ground and back. One board point is 0.01 scene units at the table's plane."""
import json
import math
from pathlib import Path

U = 0.01
SENSOR = 36
CAMERAS = {"landscape": dict(pitch=22, lens=35, zoom=1.07), "portrait": dict(pitch=16, lens=35, zoom=1.0)}
LAYOUTS = json.load(open(Path(__file__).with_name("arena_layout.json")))


class View:
    def __init__(self, variant):
        self.variant = variant
        self.screen = tuple(LAYOUTS[variant]["screen"])
        camera = CAMERAS[variant]
        self.lens, self.pitch = camera["lens"], math.radians(camera["pitch"])
        self.span = max(self.screen) * U
        distance = (self.span / 2) * (camera["lens"] / (SENSOR / 2)) * camera["zoom"]
        self.location = (0.0, -distance * math.sin(self.pitch), distance * math.cos(self.pitch))
        # Camera-space units per board point, one unit in front of the lens.
        self.per_point = (SENSOR / 2 / self.lens) / (max(self.screen) / 2)

    def lens_point(self, point):
        """A board point in camera space, one unit in front of the lens."""
        return ((point[0] - self.screen[0] / 2) * self.per_point, (self.screen[1] / 2 - point[1]) * self.per_point, -1.0)

    def to_ground(self, point, z=0.0):
        """Where the ray through a board point meets the plane at height z."""
        x, y, _ = self.lens_point(point)
        s, c = math.sin(self.pitch), math.cos(self.pitch)
        ray = (x, y * c + s, y * s - c)
        t = (z - self.location[2]) / ray[2]
        return (self.location[0] + t * ray[0], self.location[1] + t * ray[1], z)

    def to_screen(self, co):
        """The board point a scene position lands on."""
        s, c = math.sin(self.pitch), math.cos(self.pitch)
        dx, dy, dz = co[0] - self.location[0], co[1] - self.location[1], co[2] - self.location[2]
        y, z = dy * c + dz * s, -dy * s + dz * c
        return (dx / -z / self.per_point + self.screen[0] / 2, self.screen[1] / 2 - y / -z / self.per_point)

    def to_screen_many(self, points):
        """to_screen for a numpy array of positions."""
        s, c = math.sin(self.pitch), math.cos(self.pitch)
        dx, dy, dz = points[:, 0] - self.location[0], points[:, 1] - self.location[1], points[:, 2] - self.location[2]
        y, z = dy * c + dz * s, -dy * s + dz * c
        return dx / -z / self.per_point + self.screen[0] / 2, self.screen[1] / 2 - y / -z / self.per_point

    def lean_point(self):
        """The board point every upright object leans away from: straight below the camera."""
        return self.to_screen((self.location[0], self.location[1], 0.0))
