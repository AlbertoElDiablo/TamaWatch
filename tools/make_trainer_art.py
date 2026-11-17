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
# on its cell's floor. Here at 2x (the partner's zoom on the home screen), each in its own 48 x 72 cell after the two big ones: cell
# 2 + character * 8 + view * 2 + frame (views 0 front, 1 back, 2 left, 3 right), centred, on the
# cell's floor.
img = Image.new("RGBA", (33 * 48, 72), (0, 0, 0, 0))
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
        # at 2x like the partner on the home screen; front and back views a little stockier (whole
        # pixels repeated, no blending)
        wide = 1.18 if i % 4 < 2 else 1.0
        fr = fr.resize((round(fr.width * wide) * 2, fr.height * 2), Image.NEAREST)
        cell = 2 + k * 8 + (i % 4) * 2 + i // 4
        img.alpha_composite(fr, (cell * 48 + (48 - fr.width) // 2, 72 - fr.height))

# Route Crossing's grass lanes: tools/route_objects.png, 12 things in 32 x 28 cells, each standing on
# its cell's floor (4 rocks, 4 trees, 4 bushes). Here at 2x like the trainers (a wide one a little
# less, to fit its 48-pixel cell), in cells 18-29, centred, on the cell's floor.
obj = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "route_objects.png")).convert("RGBA")
for i in range(12):
    fr = obj.crop((i * 32, 0, i * 32 + 32, 28))
    fr = fr.crop(fr.getbbox())
    k = min(2.0, 46.0 / fr.width)
    fr = fr.resize((round(fr.width * k), round(fr.height * k)), Image.NEAREST)
    img.alpha_composite(fr, ((18 + i) * 48 + (48 - fr.width) // 2, 72 - fr.height))

# The train (tools/route_train.png: the engine, nose to the left, then a carriage), each stretched
# so a carriage spans 36 pixels: cell 30 the engine facing left, 31 facing right, 32 the carriage,
# each against its cell's left edge, on the floor.
tr = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "route_train.png")).convert("RGBA")
car = tr.crop((32, 0, 64, 24)); car = car.crop(car.getbbox())
eng = tr.crop((0, 0, 32, 24)); eng = eng.crop(eng.getbbox())
k = 36.0 / car.width
car = car.resize((36, round(car.height * k)), Image.NEAREST)
eng = eng.resize((42, round(eng.height * k)), Image.NEAREST)
img.alpha_composite(eng, (30 * 48, 72 - eng.height))
img.alpha_composite(eng.transpose(Image.FLIP_LEFT_RIGHT), (31 * 48, 72 - eng.height))
img.alpha_composite(car, (32 * 48, 72 - car.height))

d = os.path.join(APP, "resources", "drawables", "kids")
os.makedirs(d, exist_ok=True)
img.save(os.path.join(d, "kids.png"))
cols = sorted({p[:3] for p in img.get_flattened_data() if p[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(APP, "resources", "drawables", "kids.xml"), "w").write(
    '<drawables>\n    <bitmap id="kids" filename="kids/kids.png"><palette disableTransparency="false">%s</palette></bitmap>\n</drawables>\n' % pal)
print("kids", img.size, len(cols), "colours")
