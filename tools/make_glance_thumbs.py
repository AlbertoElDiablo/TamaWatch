"""Tiny run-length thumbnails of every Kanto species for the widget glance.

usage: python3 make_glance_thumbs.py <SpriteCollab-master> <TamaWatch>

The glance has 32 KB and cannot load sprite sheets, so each species' first idle frame (normal
and shiny) is fitted into CELL x CELL, snapped to the watch's 64 colours and stored as runs in
its own resources/jsondata/dNNN.json under "g" (normal) and "gs" (shiny). One run is one number:
colour << 18 | y << 12 | x << 6 | length, colour = r*16 + g*4 + b with each channel 0..3.
The game copies the current pet's runs into storage, where the glance reads them.
Run after make_sprites.py (which keeps these keys when it rewrites the JSON).
"""
import json, os, sys, xml.etree.ElementTree as ET
from PIL import Image

SRC, APP = sys.argv[1], sys.argv[2]
CELL = 40

def frame_of(n, shiny):
    d = os.path.join(SRC, "sprite", "%04d" % n)
    table = {a.findtext("Name"): a for a in ET.parse(os.path.join(d, "AnimData.xml")).getroot().iter("Anim")}
    name = "Idle"
    anim = table[name]
    if anim.find("CopyOf") is not None:
        name = anim.findtext("CopyOf")
        anim = table[name]
    fw, fh = int(anim.findtext("FrameWidth")), int(anim.findtext("FrameHeight"))
    path = os.path.join(d, "0000", "0001", name + "-Anim.png") if shiny else os.path.join(d, name + "-Anim.png")
    if not os.path.exists(path):
        path = os.path.join(d, name + "-Anim.png")
    fr = Image.open(path).convert("RGBA").crop((0, 0, fw, fh))
    fr = fr.crop(fr.getbbox())
    k = min(1.0, (CELL - 2) / max(fr.size))
    if k < 1.0:
        fr = fr.resize((max(1, round(fr.width * k)), max(1, round(fr.height * k))), Image.NEAREST)
    return fr

def runs(fr):
    ox = (CELL - fr.width) // 2
    oy = CELL - fr.height                     # stands on the floor
    px = fr.load()
    out = []
    for j in range(fr.height):
        i = 0
        while i < fr.width:
            r, g, b, a = px[i, j]
            if a < 128:
                i += 1
                continue
            c = (round(r / 85) << 4) | (round(g / 85) << 2) | round(b / 85)
            s = i
            while i < fr.width:
                r2, g2, b2, a2 = px[i, j]
                if a2 < 128 or ((round(r2 / 85) << 4) | (round(g2 / 85) << 2) | round(b2 / 85)) != c:
                    break
                i += 1
            out.append(c << 18 | (oy + j) << 12 | (ox + s) << 6 | (i - s))
    return out

total = 0
for n in range(1, 152):
    p = os.path.join(APP, "resources", "jsondata", "d%03d.json" % n)
    meta = json.load(open(p))
    meta["g"] = runs(frame_of(n, False))
    meta["gs"] = runs(frame_of(n, True))
    total += len(meta["g"]) + len(meta["gs"])
    json.dump(meta, open(p, "w"), separators=(",", ":"))
print("glance thumbs: 151 species, %d runs, avg %d per thumb" % (total, total / 302))
