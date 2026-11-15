"""Make every colour hold up on the fenix 6's transflective (MIP) screen.

usage: python3 boost_colours.py <TamaWatch>

The screen shows 64 colours (each channel 00/55/AA/FF) and pale ones read as white there. Each
non-grey colour has its weakest channel(s) dropped one step: FFAA55 -> FFAA00, AAAAFF -> 5555FF,
AAFFAA -> 55FF55. Greys, black and white are kept. Applied to every PNG under
resources/drawables (and their <palette> lists), the hex colours in source/*.mc, the accent
colour in dex.json and the glance thumbnail runs in jsondata/dNNN.json.

Run once, after the generator tools (make_sprites.py, make_backgrounds.py, ...): a marker file
stops a second pass. Delete resources/.colours_boosted after regenerating assets.
"""
import glob, json, os, re, sys
from PIL import Image

APP = sys.argv[1]
MARK = os.path.join(APP, "resources", ".colours_boosted")
if os.path.exists(MARK):
    sys.exit("already boosted (delete %s after regenerating assets)" % MARK)

def lvl(v):
    return min(range(4), key=lambda i: abs(i * 85 - v))

def boost_lv(c):
    m, M = min(c), max(c)
    if M == m:
        return c
    return tuple(max(0, v - 1) if v == m else v for v in c)

def boost(rgb):
    return tuple(v * 85 for v in boost_lv(tuple(lvl(v) for v in rgb)))

# images
n_png = 0
cache = {}
for f in glob.glob(os.path.join(APP, "resources", "drawables", "**", "*.png"), recursive=True):
    im = Image.open(f)
    mode = im.mode
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            k = (r, g, b)
            if k not in cache:
                cache[k] = boost(k)
            px[x, y] = cache[k] + (a,)
    (im.convert("RGB") if mode == "RGB" else im).save(f, optimize=True)
    n_png += 1

# palettes
def fix_palette(m):
    cols = []
    for c in re.findall(r"<color>([0-9A-Fa-f]{6})</color>", m.group(0)):
        h = "%02X%02X%02X" % boost(tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)))
        if h not in cols:
            cols.append(h)
    head = m.group(0)[:m.group(0).index(">") + 1]
    return head + "".join("<color>%s</color>" % c for c in cols) + "</palette>"

for f in glob.glob(os.path.join(APP, "resources", "drawables", "*.xml")):
    s = open(f).read()
    s = re.sub(r"<palette[^>]*>.*?</palette>", fix_palette, s)
    open(f, "w").write(s)

# code colours (6-digit hex literals)
def fix_hex(m):
    v = int(m.group(1), 16)
    r, g, b = boost(((v >> 16) & 255, (v >> 8) & 255, v & 255))
    return "0x%02X%02X%02X" % (r, g, b)

n_src = 0
for f in glob.glob(os.path.join(APP, "source", "*.mc")):
    s = open(f).read()
    t = re.sub(r"\b0x([0-9A-Fa-f]{6})\b", fix_hex, s)
    if t != s:
        open(f, "w").write(t)
        n_src += 1

# dex accent colours (last column of each row)
dp = os.path.join(APP, "resources", "jsondata", "dex.json")
dex = json.load(open(dp))
rows = dex if isinstance(dex, list) else None
def fix_rows(rs):
    for r in rs:
        if isinstance(r, list) and r and isinstance(r[-1], int) and r[-1] > 255:
            v = r[-1]
            c = boost(((v >> 16) & 255, (v >> 8) & 255, v & 255))
            r[-1] = c[0] << 16 | c[1] << 8 | c[2]
if isinstance(dex, list):
    fix_rows(dex)
elif isinstance(dex, dict):
    for k, v in dex.items():
        if isinstance(v, list):
            fix_rows(v)
json.dump(dex, open(dp, "w"), separators=(",", ":"))

# glance thumbnail runs: colour = r*16 + g*4 + b in levels
for f in glob.glob(os.path.join(APP, "resources", "jsondata", "d[0-9][0-9][0-9].json")):
    meta = json.load(open(f))
    for key in ("g", "gs"):
        if key in meta:
            out = []
            for v in meta[key]:
                c = (v >> 18) & 63
                nl = boost_lv(((c >> 4) & 3, (c >> 2) & 3, c & 3))
                out.append((nl[0] << 4 | nl[1] << 2 | nl[2]) << 18 | (v & ((1 << 18) - 1)))
            meta[key] = out
    json.dump(meta, open(f, "w"), separators=(",", ":"))

open(MARK, "w").write("boosted\n")
print("boosted: %d images, %d source files, %d distinct colours mapped" % (n_png, n_src, len(cache)))
