"""The Arena board's zones and stand-in cards in board points, from ArenaLayout (apps/ios/MagicMobile/ArenaBoardModel.swift)
and the plain card sizes in apps/web/src/ui/arena/layout.ts. Rectangles are (x, y, w, h)."""


def circle(cx, cy, d):
    return (cx - d / 2, cy - d / 2, d, d)


def centred(cx, cy, w, h):
    return (cx - w / 2, cy - h / 2, w, h)


# Red stays quiet (cards land there), blue is UI over the table, green is the best place for scenery.
ZONES = {
    "landscape": {
        "canvas": (956, 440),
        "cards": [("CARD ROWS", (80, 54, 792, 306))],
        "scenery": [("SCENERY", (0, 0, 368, 50)), ("", (0, 50, 56, 310)), ("", (884, 50, 72, 338))],
        "ui": [
            ("hand", (184, 302, 612, 138)), ("stack", (716, 60, 158, 222)), ("controls", (708, 314, 176, 110)),
            ("pass", (890, 392, 40, 28)), ("undo", (650, 343, 52, 26)), ("gear", centred(876, 28, 44, 44)),
            ("log", centred(842, 26, 30, 30)), ("them", circle(478, 25, 50)), ("you", circle(84, 402, 56)),
            ("their hand", (372, 0, 212, 34)), ("piles", (634, 5, 140, 50)), ("piles", (126, 374, 150, 60)),
        ],
    },
    "portrait": {
        "canvas": (440, 956),
        "cards": [("CARD ROWS", (12, 95, 416, 604))],
        "scenery": [("SCENERY", (185, 0, 85, 63)), ("", (0, 63, 440, 29))],
        "ui": [
            ("rail", (0, 815, 440, 141)), ("hand", (0, 711, 440, 104)), ("stack", (312, 363, 116, 166)),
            ("them", circle(42, 36, 54)), ("piles", (83, 12, 100, 42)), ("their hand", (270, 0, 140, 41)),
            ("gear", centred(412, 30, 44, 44)), ("exile", centred(30, 795, 38, 53)),
        ],
    },
}

# The open ground: an uneven outline around the card rows, not a table. Scenery may come in where the outline does;
# portrait's runs off both sides.
CLEARINGS = {
    "landscape": [(58, 62), (120, 40), (240, 46), (350, 36), (470, 58), (600, 40), (740, 46), (850, 38), (905, 74),
                  (888, 170), (900, 290), (880, 372), (760, 392), (610, 380), (470, 398), (300, 382), (130, 388),
                  (64, 352), (46, 240), (66, 150)],
    "portrait": [(-40, 96), (70, 84), (170, 90), (290, 80), (380, 90), (480, 92), (500, 500), (480, 806), (360, 798),
                 (230, 812), (110, 800), (-40, 808), (-60, 500)],
}


def _row(left, y, w, h, count, step):
    return [(left + i * step, y - h / 2, w, h) for i in range(count)]


def _centred_row(cx, y, w, h, count, step):
    return _row(cx - step * (count - 1) / 2 - w / 2, y, w, h, count, step)


# Stand-ins at full size: a full table in every row, the hand tucked, every pile and control.
GHOSTS = {
    "landscape": {
        "table": _row(84, 87, 68, 57, 5, 72) + _row(544, 87, 68, 57, 4, 80) + _row(84, 325, 68, 57, 5, 72)
        + _row(544, 325, 68, 57, 2, 80) + _centred_row(478, 146, 84, 70, 8, 92) + _centred_row(478, 248, 84, 70, 8, 92),
        "hand": _centred_row(490, 432, 93, 131, 7, 50) + _centred_row(478, 29, 36, 50, 7, 30),
        "pile": [centred(x, 404, 42, 59) for x in (147, 201, 255)] + [centred(x, 30, 36, 50) for x in (652, 704, 756)],
        "ui": [circle(84, 402, 56), circle(478, 25, 50), (708, 388, 176, 36), (708, 335, 176, 37), (708, 368, 176, 16),
               (890, 392, 40, 28), circle(876, 28, 44), circle(842, 26, 30)],
    },
    "portrait": {
        "table": _row(14, 126, 58, 58, 7, 59) + _row(14, 668, 58, 58, 7, 59) + _centred_row(220, 306, 70, 66, 6, 72)
        + _centred_row(220, 384, 70, 66, 6, 72) + _centred_row(220, 508, 70, 66, 6, 72) + _centred_row(220, 586, 70, 66, 6, 72),
        "hand": _centred_row(220, 779, 104, 146, 7, 46) + _centred_row(340, 20, 30, 42, 7, 14),
        "pile": [centred(x, 891, 38, 53) for x in (118, 168)] + [centred(30, 795, 38, 53)]
        + [centred(x, 33, 30, 42) for x in (98, 133, 168)],
        "ui": [circle(50, 890, 74), circle(42, 36, 54), (272, 882, 156, 40), (272, 840, 156, 36), (272, 824, 156, 12),
               (197, 887, 64, 30), (197, 843, 64, 30), circle(412, 30, 44)],
    },
}


# Where cards rest outside the rows. Each must sit wholly on one flat surface, a roof or the floor, never across an edge.
SEATS = {
    "landscape": {"their piles": (634, 5, 140, 50), "their hand": (372, 0, 212, 34), "your piles": (126, 374, 150, 60)},
    "portrait": {"their piles": (83, 12, 100, 42), "their hand": (283, 0, 114, 41), "your piles": (99, 864, 88, 54),
                 "your exile": (11, 768, 38, 32)},
}

# Portrait's exile pile stands in front of the wall, so its seat ends at the wall's foot.
# Portrait's hand tucks behind the plate from this line down (ArenaLayout.railTop), so a world puts a wall's top edge on it.
RAIL_TOP = {"portrait": 815}


def inside(point, rect, margin=0):
    x, y, w, h = rect
    return x - margin <= point[0] <= x + w + margin and y - margin <= point[1] <= y + h + margin
