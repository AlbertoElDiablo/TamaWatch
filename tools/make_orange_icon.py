"""The orange (in place of TamaPoke's green berry): the blue berry's round shape, leaf and
shading recoloured to orange tones, into slot 5 of resources/drawables/dock/icons.png.

usage: python3 make_orange_icon.py <TamaWatch>
"""
import os, re, sys
from PIL import Image

APP = sys.argv[1]
SRC, DST = 4, 5
MAP = {(0, 170, 255): (255, 170, 0),     # body
       (0, 170, 170): (255, 85, 0),      # shade
       (0, 0, 170): (170, 85, 0),        # deep shade
       (0, 85, 85): (85, 85, 0)}         # stem
p = os.path.join(APP, "resources", "drawables", "dock", "icons.png")
im = Image.open(p).convert("RGBA")
for y in range(32):
    for x in range(32):
        r, g, b, a = im.getpixel((32 * SRC + x, y))
        c = MAP.get((r, g, b), (r, g, b))
        im.putpixel((32 * DST + x, y), c + (a,) if a else (0, 0, 0, 0))
im.save(p)
cols = sorted({px[:3] for px in im.get_flattened_data() if px[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
x = os.path.join(APP, "resources", "drawables", "dock.xml")
s = open(x).read()
s = re.sub(r"<palette([^>]*)>.*?</palette>", lambda m: "<palette%s>%s</palette>" % (m.group(1), pal), s, flags=re.S)
open(x, "w").write(s)
print("orange in slot", DST)
