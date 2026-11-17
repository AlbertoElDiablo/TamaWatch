"""The two trainer characters you choose from (TamaWatch's own pixel art), in a chunky bead-art
style: a big cap with a band, hair showing at the sides, a round face with an open mouth, arms
out, two-tone trousers, a heavy dark outline. 16 x 21 maps drawn at 3x side by side into
resources/drawables/kids/kids.png (48 x 72 each, the figure at the bottom). Only the left half is
written; the right half mirrors it. No gender symbols.

usage: python3 make_trainer_art.py <TamaWatch>
"""
import os, sys
from PIL import Image

APP = sys.argv[1]
S = 3
A = [  # green cap with a yellow band, brown jacket over a yellow shirt, navy trousers
    ".....KKK",
    "....KcCC",
    "...KcCCC",
    "...KCCCC",
    "..KHCCCC",
    "..KHBBBB",
    ".KHSHddd",
    ".KHSSKSS",
    "..KSSKSS",
    "..KSSSSS",
    "...KSSMM",
    "..KJJKKT",
    ".KSKJJTT",
    ".KSSJJTT",
    "..KKJJTW",
    "...KPPPP",
    "...KPpPP",
    "...KPPPK",
    "...KPPPK",
    "...KKKK.",
    "...KKKK.",
]
B = [  # purple cap with a pink band, long hair, pink top, navy skirt, lilac boots
    ".....KKK",
    "....KcCC",
    "...KcCCC",
    "...KCCCC",
    "..KHCCCC",
    "..KHBBBB",
    ".KHHHddd",
    ".KHHSKSS",
    ".KHHSKSS",
    ".KHHSSSS",
    ".KHHKSMM",
    ".KHHJKKJ",
    ".KSKJJJJ",
    ".KSSJJJJ",
    "..KKJJJW",
    "...KQQQQ",
    "..KQqQQQ",
    "...KSSSK",
    "...KSSSK",
    "...KLLL.",
    "...KKKK.",
]
BASE = {"K": (34, 17, 0), "S": (255, 170, 85), "M": (170, 0, 0), "W": (255, 255, 255),
        "d": (85, 0, 0)}
COLA = dict(BASE, c=(85, 255, 85), C=(0, 170, 0), B=(255, 255, 0), H=(85, 0, 0),
            J=(170, 85, 0), T=(255, 255, 85), P=(0, 0, 85), p=(0, 85, 170))
COLB = dict(BASE, c=(255, 85, 255), C=(170, 0, 170), B=(255, 85, 170), H=(85, 0, 0),
            J=(255, 85, 170), Q=(0, 0, 85), q=(0, 85, 170), L=(170, 170, 255))
for cols in (COLA, COLB):
    cols["K"] = (0, 0, 0)

# Route Crossing's walking trainers (tools/walkers.py): each character from the front, back, left
# and right, two walking frames each, 16 x 24 at 2x, each in its own 48 x 72 cell after the two big
# ones: cell 2 + character * 8 + view * 2 + frame (views 0 front, 1 back, 2 left, 3 right),
# standing on the cell's floor, centred.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walkers

img = Image.new("RGBA", (18 * 48, 72), (0, 0, 0, 0))
for k, (half, col) in enumerate([(A, COLA), (B, COLB)]):
    top = 72 - len(half) * S
    for y, row in enumerate(half):
        full = row + row[::-1]
        for x, ch in enumerate(full):
            if ch == ".":
                continue
            for dy in range(S):
                for dx in range(S):
                    img.putpixel((k * 48 + x * S + dx, top + y * S + dy), col[ch] + (255,))
for k, who in enumerate(("boy", "girl")):
    col = walkers.COLOURS[who]
    for v, view in enumerate(("front", "back", "left", "right")):
        for f, rows in enumerate(walkers.WALKERS[who][view]):
            x0, y0 = (2 + k * 8 + v * 2 + f) * 48 + 8, 72 - 48
            for y, row in enumerate(rows):
                for x, ch in enumerate(row):
                    if ch == ".":
                        continue
                    for dy in range(2):
                        for dx in range(2):
                            img.putpixel((x0 + x * 2 + dx, y0 + y * 2 + dy), col[ch] + (255,))

d = os.path.join(APP, "resources", "drawables", "kids")
os.makedirs(d, exist_ok=True)
img.save(os.path.join(d, "kids.png"))
cols = sorted({p[:3] for p in img.get_flattened_data() if p[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(APP, "resources", "drawables", "kids.xml"), "w").write(
    '<drawables>\n    <bitmap id="kids" filename="kids/kids.png"><palette disableTransparency="false">%s</palette></bitmap>\n</drawables>\n' % pal)
print("kids", img.size, len(cols), "colours")
