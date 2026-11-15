"""The football dock icon (TamaWatch's own), in the classic style: big black panels, white panels
between them, black seams and outline, drawn pixel by pixel on the 32x32 icon grid into
slot 3 of resources/drawables/dock/icons.png (where the dumbbell was; it still opens training).

usage: python3 make_ball_icon.py <TamaWatch>
"""
import os, re, sys
from PIL import Image

APP = sys.argv[1]
SLOT = 3
import math

def ball_rows():
    """Black panels where the reference ball has them (top left, right, bottom, a sliver on the
    left edge), seams joining them so the white panels between read as hexagons, and the outline."""
    def pent(cx, cy, r, rot):
        return [(cx + r * math.cos(math.radians(rot + 72 * k)), cy + r * math.sin(math.radians(rot + 72 * k))) for k in range(5)]
    def inside(px, py, poly):
        ok = False
        for i in range(len(poly)):
            x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % len(poly)]
            if (y1 > py) != (y2 > py) and px < x1 + (py - y1) * (x2 - x1) / (y2 - y1):
                ok = not ok
        return ok
    def seg(px, py, a, b):
        ax, ay = a; bx, by = b
        t = max(0, min(1, ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / ((bx - ax) ** 2 + (by - ay) ** 2)))
        return math.hypot(px - ax - t * (bx - ax), py - ay - t * (by - ay))
    S = 2.0                                   # the layout is on a 16 grid; drawn on 32
    def sc(p): return (p[0] * S, p[1] * S)
    P1, P2, P3, P4 = sc((5.4, 5.0)), sc((14.6, 8.4)), sc((8.4, 14.0)), sc((0.4, 11.4))
    pents = [pent(*P1, 3.0 * S, 90), pent(*P2, 2.7 * S, 162), pent(*P3, 2.7 * S, 18), pent(*P4, 2.3 * S, 0)]
    seams = [(P1, P2), (P2, P3), (P3, P1), (P1, P4), (P4, P3), (P1, sc((9.0, -1))), (P2, sc((13.5, -0.5))),
             (P2, sc((16.5, 14.5))), (P3, sc((14.5, 16.5))), (P3, sc((2.5, 16))), (P4, sc((1.5, 16)))]
    rows = []
    for y in range(32):
        row = ""
        for x in range(32):
            px, py = x + 0.5, y + 0.5
            d = math.hypot(px - 16, py - 16)
            if d > 15.6:
                row += "."
            elif d > 13.8 or any(inside(px, py, q) for q in pents) or any(seg(px, py, a, b) < 0.75 for a, b in seams):
                row += "K"
            else:
                row += "W"
        rows.append(row)
    return rows

ROWS = ball_rows()
COL = {"K": (0, 0, 0), "W": (255, 255, 255)}

p = os.path.join(APP, "resources", "drawables", "dock", "icons.png")
strip = Image.open(p).convert("RGBA")
for y in range(32):
    for x in range(32):
        strip.putpixel((32 * SLOT + x, y), (0, 0, 0, 0))
for y, row in enumerate(ROWS):
    for x, ch in enumerate(row):
        if ch == ".":
            continue
        strip.putpixel((32 * SLOT + x, y), COL[ch] + (255,))
strip.save(p)
cols = sorted({px[:3] for px in strip.get_flattened_data() if px[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
x = os.path.join(APP, "resources", "drawables", "dock.xml")
s = open(x).read()
s = re.sub(r"<palette([^>]*)>.*?</palette>", lambda m: "<palette%s>%s</palette>" % (m.group(1), pal), s, flags=re.S)
open(x, "w").write(s)
print("ball in slot", SLOT)
