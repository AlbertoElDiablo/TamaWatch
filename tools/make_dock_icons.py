"""Dock and food icons from TamaPoke (MIT): apple, moon, water drop, dumbbell, two berries, candy.

usage: python3 make_dock_icons.py <TamaPoke repo> <TamaWatch>

Reads the four 16x16 pixel maps from TamaPoke's species.h with its colour table
(spriteColor), draws them at 2x (32x32), snaps to the watch's 64 colours and
writes resources/drawables/dock/ + dock.xml.
"""
import os, re, shutil, sys
from PIL import Image

SRC, APP = sys.argv[1], sys.argv[2]
ICONS = [("dock_food", "SPR_ICON_FOOD"), ("dock_light", "SPR_ICON_LIGHT"),
         ("dock_bath", "SPR_ICON_CLEAN"), ("dock_play", "SPR_ICON_TRAIN"),
         # food picker: the apple above plus two berries and candy
         ("food_blue", "SPR_ICON_BERRY_B"), ("food_green", "SPR_ICON_BERRY_G"), ("food_candy", "SPR_ICON_CANDY")]
SCALE = 2
LEVELS = [0, 85, 170, 255]

def snap(v):
    return min(LEVELS, key=lambda x: abs(x - v))

text = open(os.path.join(SRC, "species.h"), encoding="utf-8").read()
colours = {ch: tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
           for ch, h in re.findall(r"case '(.)': return 0x[0-9A-F]+;\s*//\s*#([0-9a-f]{6})", text)}

out_dir = os.path.join(APP, "resources", "drawables", "dock")
shutil.rmtree(out_dir, ignore_errors=True)
os.makedirs(out_dir)
# One strip of 32x32 icons (Connect IQ allows at most 254 drawables): icon i at x = 32 * i.
strip = Image.new("RGBA", (32 * len(ICONS), 32), (0, 0, 0, 0))
for k, (rid, name) in enumerate(ICONS):
    block = re.search(re.escape(name) + r"\[16\] = \{[^\n]*\n(.*?)\};", text, re.S).group(1)
    rows = re.findall(r'"([^"]{16})"', block)
    assert len(rows) == 16, name
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            c = tuple(snap(v) for v in colours[ch]) + (255,)
            for dy in range(SCALE):
                for dx in range(SCALE):
                    strip.putpixel((32 * k + x * SCALE + dx, y * SCALE + dy), c)
strip.save(os.path.join(out_dir, "icons.png"))
cols = sorted({p[:3] for p in strip.getdata() if p[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
with open(os.path.join(APP, "resources", "drawables", "dock.xml"), "w") as f:
    f.write('<drawables>\n    <bitmap id="icons" filename="dock/icons.png"><palette disableTransparency="false">%s</palette></bitmap>\n</drawables>\n' % pal)
print("icon strip:", [r for r, _ in ICONS], "colours", len(cols))
