"""Pokedex thumbnails for TamaWatch (like TamaPoke's thumbs.bin), from SpriteCollab sprites.

usage: python3 make_thumbs.py <SpriteCollab-master> <TamaWatch>

Each Kanto species' first front-facing idle frame, cropped and fitted (never upscaled) into a
CELL x CELL square, in two atlases of 16 columns: thumbs.png in colour, thumbs_sil.png as an
ink silhouette for species not raised yet. Thumb n (1-151) is at ((n-1) % 16, (n-1) / 16).
"""
import os, sys, xml.etree.ElementTree as ET
from PIL import Image

SRC, APP = sys.argv[1], sys.argv[2]
CELL = 38
COLS = 16
LEVELS = [0, 85, 170, 255]
INK = (0, 0, 0)

def snap(v):
    return min(LEVELS, key=lambda x: abs(x - v))

rows = -(-151 // COLS)
colour = Image.new("RGBA", (COLS * CELL, rows * CELL), (0, 0, 0, 0))
sil = Image.new("RGBA", (COLS * CELL, rows * CELL), (0, 0, 0, 0))
for n in range(1, 152):
    d = os.path.join(SRC, "sprite", "%04d" % n)
    table = {a.findtext("Name"): a for a in ET.parse(os.path.join(d, "AnimData.xml")).getroot().iter("Anim")}
    name = "Idle"
    anim = table[name]
    if anim.find("CopyOf") is not None:          # "Idle" can be a copy of another animation
        name = anim.findtext("CopyOf")
        anim = table[name]
    fw, fh = int(anim.findtext("FrameWidth")), int(anim.findtext("FrameHeight"))
    frame = Image.open(os.path.join(d, name + "-Anim.png")).convert("RGBA").crop((0, 0, fw, fh))
    frame = frame.crop(frame.getbbox())
    k = min(1.0, (CELL - 2) / max(frame.size))
    if k < 1.0:
        frame = frame.resize((max(1, round(frame.width * k)), max(1, round(frame.height * k))), Image.NEAREST)
    x = ((n - 1) % COLS) * CELL + (CELL - frame.width) // 2
    y = ((n - 1) // COLS) * CELL + (CELL - frame.height)        # stand on the cell's floor
    px = frame.load()
    for j in range(frame.height):
        for i in range(frame.width):
            r, g, b, a = px[i, j]
            if a >= 128:
                colour.putpixel((x + i, y + j), (snap(r), snap(g), snap(b), 255))
                sil.putpixel((x + i, y + j), INK + (255,))

out = os.path.join(APP, "resources", "drawables", "thumbs")
os.makedirs(out, exist_ok=True)
xml = []
for rid, im in (("thumbs", colour), ("thumbs_sil", sil)):
    im.save(os.path.join(out, rid + ".png"), optimize=True)
    cols = sorted({p[:3] for p in im.getdata() if p[3]})
    pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
    xml.append('    <bitmap id="%s" filename="thumbs/%s.png"><palette disableTransparency="false">%s</palette></bitmap>' % (rid, rid, pal))
open(os.path.join(APP, "resources", "drawables", "thumbs.xml"), "w").write("<drawables>\n" + "\n".join(xml) + "\n</drawables>\n")
print("thumbs: 151 in", colour.size, "colours", len({p[:3] for p in colour.getdata() if p[3]}))
