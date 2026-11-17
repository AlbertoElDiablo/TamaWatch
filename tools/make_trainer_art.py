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

# Route Crossing's walking trainers: tools/walkers.png, two rows (the boy, the girl) of 8 frames in
# 20 x 28 cells (front, back, left, right standing, then the same walking), each figure standing
# on its cell's floor. Here at 1x (about a creature's height), each in its own 48 x 72 cell after the two big ones: cell
# 2 + character * 8 + view * 2 + frame (views 0 front, 1 back, 2 left, 3 right), centred, on the
# cell's floor.
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
walk = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "walkers.png")).convert("RGBA")
for k in range(2):
    for i in range(8):
        fr = walk.crop((i * 20, k * 28, i * 20 + 20, k * 28 + 28))
        fr = fr.crop(fr.getbbox())
        cell = 2 + k * 8 + (i % 4) * 2 + i // 4
        img.alpha_composite(fr, (cell * 48 + (48 - fr.width) // 2, 72 - fr.height))

d = os.path.join(APP, "resources", "drawables", "kids")
os.makedirs(d, exist_ok=True)
img.save(os.path.join(d, "kids.png"))
cols = sorted({p[:3] for p in img.get_flattened_data() if p[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(APP, "resources", "drawables", "kids.xml"), "w").write(
    '<drawables>\n    <bitmap id="kids" filename="kids/kids.png"><palette disableTransparency="false">%s</palette></bitmap>\n</drawables>\n' % pal)
print("kids", img.size, len(cols), "colours")
