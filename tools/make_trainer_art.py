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

# Route Crossing's walking trainer: each character from the front, back, left and right, 16 x 21
# at 2x, each in its own 48 x 72 cell after the two big ones (cell 2 + character * 4 + view;
# views 0 front, 1 back, 2 left, 3 right), standing on the cell's floor, centred.
BACK_A = [
    ".....KKK", "....KCCC", "...KCCCC", "...KCCCC", "..KCCCCC", "..KBBBBB", ".KHHHHHH", ".KHHHHHH",
    "..KHHHHH", "...KSSSS", "...KJJJJ", "..KJJJJJ", ".KSKJJJJ", ".KSSJJJJ", "..KKJJJJ", "...KPPPP",
    "...KPPPP", "...KPPPK", "...KPPPK", "...KKKK.", "...KKKK.",
]
BACK_B = [
    ".....KKK", "....KCCC", "...KCCCC", "...KCCCC", "..KCCCCC", "..KBBBBB", ".KHHHHHH", ".KHHHHHH",
    ".KHHHHHH", ".KHHHHHH", ".KHHJJJJ", ".KHHJJJJ", ".KSKJJJJ", ".KSSJJJJ", "..KKJJJJ", "...KQQQQ",
    "..KQQQQQ", "...KSSSK", "...KSSSK", "...KLLL.", "...KKKK.",
]
SIDE_A = [  # facing left, the whole 16 columns
    "......KKKK......", ".....KCCCCK.....", "....KCCCCCCK....", "....KCCCCCCK....", "..KcccBBBBBK....",
    "...KKKBBBBBK....", "....KSSHHHHK....", "...KSSSKHHHK....", "...KSSSSSHHK....", "....KMSSSSK.....",
    ".....KJJJJK.....", "....KJJTJJK.....", "....KJSSJJK.....", "....KJSSJJK.....", ".....KJJJJK.....",
    ".....KPPPPK.....", ".....KPPPPK.....", ".....KPPpPK.....", "....KPPK.KPK....", "....KKKK.KKK....",
    "................",
]
SIDE_B = [
    "......KKKK......", ".....KCCCCK.....", "....KCCCCCCK....", "....KCCCCCCK....", "..KcccBBBBBK....",
    "...KKKBBBBBHK...", "....KSSHHHHHK...", "...KSSSKHHHHK...", "...KSSSSSHHHK...", "....KMSSSSHHK...",
    ".....KJJJJHHK...", "....KJJJJJK.....", "....KJSSJJK.....", "....KJSSJJK.....", ".....KJJJJK.....",
    "....KQQQQQQK....", "....KQQqQQQK....", ".....KSSSSK.....", "....KSSK.KSK....", "....KLLK.KLK....",
    "................",
]

img = Image.new("RGBA", (10 * 48, 72), (0, 0, 0, 0))
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
def put(cell, rows, col, mirror_half):
    """A 16 x 21 view at 2x, centred on the floor of its 48 x 72 cell."""
    x0, y0 = cell * 48 + 8, 72 - 42
    for y, row in enumerate(rows):
        full = row + row[::-1] if mirror_half else row
        for x, ch in enumerate(full):
            if ch == ".":
                continue
            for dy in range(2):
                for dx in range(2):
                    img.putpixel((x0 + x * 2 + dx, y0 + y * 2 + dy), col[ch] + (255,))

for k, (front, back, side, col) in enumerate([(A, BACK_A, SIDE_A, COLA), (B, BACK_B, SIDE_B, COLB)]):
    base = 2 + k * 4
    put(base + 0, front, col, True)
    put(base + 1, back, col, True)
    put(base + 2, side, col, False)
    put(base + 3, [r[::-1] for r in side], col, False)        # right: the left view mirrored

d = os.path.join(APP, "resources", "drawables", "kids")
os.makedirs(d, exist_ok=True)
img.save(os.path.join(d, "kids.png"))
cols = sorted({p[:3] for p in img.get_flattened_data() if p[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(APP, "resources", "drawables", "kids.xml"), "w").write(
    '<drawables>\n    <bitmap id="kids" filename="kids/kids.png"><palette disableTransparency="false">%s</palette></bitmap>\n</drawables>\n' % pal)
print("kids", img.size, len(cols), "colours")
