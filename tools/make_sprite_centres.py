"""Where each creature's visible body is centred in its idle frame, so screens can centre the
creature itself rather than its (padded) frame.

usage: python3 make_sprite_centres.py <TamaWatch>

Reads frame 0 of the idle row of resources/drawables/sprites/pNNN.png and writes "ic" (the x of
the middle of its opaque pixels, from the frame's left edge) into resources/jsondata/dNNN.json.
Run again after make_sprites.py.
"""
import json, os, sys
from PIL import Image

APP = sys.argv[1]
for n in range(1, 152):
    jp = os.path.join(APP, "resources", "jsondata", "d%03d.json" % n)
    meta = json.load(open(jp))
    a = meta["idle"]
    sheet = Image.open(os.path.join(APP, "resources", "drawables", "sprites", "p%03d.png" % n)).convert("RGBA")
    fr = sheet.crop((0, a["r"], a["w"], a["r"] + a["h"]))
    bb = fr.getchannel("A").getbbox()
    meta["ic"] = (bb[0] + bb[2]) // 2 if bb else a["w"] // 2
    json.dump(meta, open(jp, "w"), separators=(",", ":"))
print("centres written")
