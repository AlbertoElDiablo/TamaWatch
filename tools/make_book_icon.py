"""The book dock icon (closed) (TamaWatch's own), in the style of the other dock icons: a 16x16
pixel map with a black outline, drawn at 2x into slot 7 of resources/drawables/dock/icons.png.

usage: python3 make_book_icon.py <TamaWatch>
"""
import os, re, sys
from PIL import Image

APP = sys.argv[1]
SLOT = 7
# a closed book seen from the front: spine on the left, a label on the cover, pages below
ROWS = [
    "................",
    "...KKKKKKKKKKK..",
    "..KbBBBBBBBBBBK.",
    "..KbBhhhhhhhBBK.",
    "..KbBKKKKKKKBBK.",
    "..KbBKWWWWWKBBK.",
    "..KbBKWLLLWKBBK.",
    "..KbBKWWWWWKBBK.",
    "..KbBKKKKKKKBBK.",
    "..KbBBBBBBBBBBK.",
    "..KbBBBBBBBBBBK.",
    "..KbBBBBBBBBBBK.",
    "..KbKKKKKKKKKKK.",
    "..KbWWWWWWWWWWK.",
    "...KKKKKKKKKKKK.",
    "................",
]
COL = {"K": (0, 0, 0), "W": (255, 255, 255), "L": (85, 85, 255), "G": (170, 170, 170),
       "B": (255, 85, 0), "b": (170, 85, 0), "h": (255, 170, 85)}

p = os.path.join(APP, "resources", "drawables", "dock", "icons.png")
strip = Image.open(p).convert("RGBA")
if strip.width < 32 * (SLOT + 1):
    wide = Image.new("RGBA", (32 * (SLOT + 1), 32), (0, 0, 0, 0))
    wide.paste(strip, (0, 0))
    strip = wide
for y in range(32):
    for x in range(32):
        strip.putpixel((32 * SLOT + x, y), (0, 0, 0, 0))
for y, row in enumerate(ROWS):
    for x, ch in enumerate(row):
        if ch == ".":
            continue
        c = COL[ch] + (255,)
        for dy in range(2):
            for dx in range(2):
                strip.putpixel((32 * SLOT + 2 * x + dx, 2 * y + dy), c)
strip.save(p)
cols = sorted({px[:3] for px in strip.get_flattened_data() if px[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
x = os.path.join(APP, "resources", "drawables", "dock.xml")
s = open(x).read()
s = re.sub(r"<palette([^>]*)>.*?</palette>", lambda m: "<palette%s>%s</palette>" % (m.group(1), pal), s, flags=re.S)
open(x, "w").write(s)
print("book in slot", SLOT, "strip", strip.size, "colours", len(cols))
