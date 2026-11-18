"""TamaPoke's egg (SPR_EGG in species.h, MIT) as a TamaWatch bitmap.

usage: python3 make_egg.py <TamaPoke repo> <TamaWatch>

The 32x32 pixel map drawn at 3x (TamaPoke draws it at 5x on 466 px; 3x is the same size on
280 px), snapped to the watch's 64 colours. The cracks (CRACK1 / CRACK2) are drawn by the app.
"""
import os, re, sys
from PIL import Image

SRC, APP = sys.argv[1], sys.argv[2]
SCALE = 3
LEVELS = [0, 85, 170, 255]

def snap(v):
    return min(LEVELS, key=lambda x: abs(x - v))

text = open(os.path.join(SRC, "species.h"), encoding="utf-8").read()
colours = {ch: tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
           for ch, h in re.findall(r"case '(.)': return 0x[0-9A-F]+;\s*//\s*#([0-9a-f]{6})", text)}
block = re.search(r"SPR_EGG\[32\] = \{[^\n]*\n(.*?)\};", text, re.S).group(1)
rows = re.findall(r'"([^"]{32})"', block)
assert len(rows) == 32

im = Image.new("RGBA", (32 * SCALE, 32 * SCALE), (0, 0, 0, 0))
for y, row in enumerate(rows):
    for x, ch in enumerate(row):
        if ch == ".":
            continue
        c = tuple(snap(v) for v in colours[ch]) + (255,)
        for dy in range(SCALE):
            for dx in range(SCALE):
                im.putpixel((x * SCALE + dx, y * SCALE + dy), c)

out = os.path.join(APP, "resources", "drawables", "egg")
os.makedirs(out, exist_ok=True)
# the 1x egg (the party screen's) beside the big one, in the same picture (Connect IQ allows 254
# pictures, and the gym room needed one more): x 96-127; drawn clipped (PetView, Trainer)
both = Image.new("RGBA", (im.width + 32, im.height), (0, 0, 0, 0))
both.paste(im, (0, 0))
both.paste(im.resize((32, 32), Image.NEAREST), (im.width, 0))
im = both
im.save(os.path.join(out, "egg.png"))
cols = sorted({p[:3] for p in im.get_flattened_data() if p[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(APP, "resources", "drawables", "egg.xml"), "w").write(
    '<drawables>\n    <bitmap scope="application" id="egg" filename="egg/egg.png"><palette disableTransparency="false">%s</palette></bitmap>\n</drawables>\n' % pal)
print("egg:", im.size, "colours", len(cols))
