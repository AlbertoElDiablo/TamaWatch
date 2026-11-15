"""TamaWatch's own gym badges: 8 original pixel-art emblems, one per Kanto gym type.

usage: python3 make_badges.py <out dir> [<TamaWatch>]

With a TamaWatch path, also snaps them to the watch's 64 colours into
resources/drawables/badges/ with badges.xml (ids badge_0 .. badge_7).

Each is drawn at 24x24 on a transparent background with a dark outline, a two-tone
metal body and a white glint, then scaled 2x (48x48). Our designs, not the games'.
  0 Cairn  (rock)     stacked stones
  1 Tide   (water)    a breaking wave in a shield
  2 Spark  (electric) a bolt across a hexagon
  3 Sprout (grass)    a seedling with two leaves
  4 Spore  (poison)   a spotted mushroom
  5 Mind   (psychic)  a crescent with a star
  6 Ember  (fire)     a sun-ring around a flame core
  7 Quake  (ground)   a cracked twin peak
"""
import os, shutil, sys
from PIL import Image, ImageDraw

OUT = sys.argv[1]
S = 24
OUTLINE = (34, 30, 44)
GLINT = (255, 255, 255)
NAMES = ["Cairn", "Tide", "Spark", "Sprout", "Spore", "Mind", "Ember", "Quake"]


def new():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def finish(im, d, glints):
    """Outline every opaque pixel's empty neighbours, then add glints."""
    px = im.load()
    solid = {(x, y) for x in range(S) for y in range(S) if px[x, y][3] > 0}
    for x, y in solid:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < S and 0 <= ny < S and (nx, ny) not in solid:
                px[nx, ny] = OUTLINE + (255,)
    for g in glints:
        px[g] = GLINT + (255,)
    return im


def cairn():
    im, d = new()
    light, dark = (196, 188, 176), (128, 120, 112)
    for (x0, y0, x1, y1) in [(5, 15, 18, 20), (7, 9, 16, 14), (9, 4, 14, 8)]:
        d.ellipse([x0, y0, x1, y1], fill=dark)
        d.ellipse([x0, y0, x1 - 2, y1 - 2], fill=light)
    return finish(im, d, [(9, 16), (9, 10), (10, 5)])


def tide():
    im, d = new()
    d.polygon([(4, 3), (19, 3), (19, 13), (12, 21), (4, 13)], fill=(70, 130, 210))
    d.polygon([(4, 3), (12, 3), (12, 21), (4, 13)], fill=(110, 170, 236))
    d.arc([6, 7, 17, 18], 180, 360, fill=(236, 248, 255), width=2)   # the wave's curl
    d.line([6, 15, 17, 15], fill=(236, 248, 255))
    return finish(im, d, [(6, 5), (7, 5)])


def spark():
    im, d = new()
    d.regular_polygon((12, 12, 10), 6, fill=(232, 176, 48))
    d.regular_polygon((12, 12, 7), 6, fill=(250, 214, 96))
    d.polygon([(13, 4), (8, 13), (12, 13), (10, 20), (16, 10), (12, 10)], fill=(255, 250, 220))
    return finish(im, d, [(5, 9), (6, 8)])


def sprout():
    im, d = new()
    d.rectangle([11, 10, 12, 20], fill=(90, 140, 60))
    d.ellipse([3, 5, 12, 12], fill=(96, 178, 84))       # left leaf
    d.ellipse([12, 3, 21, 11], fill=(120, 200, 100))    # right leaf
    d.ellipse([7, 18, 16, 22], fill=(150, 110, 70))     # soil
    return finish(im, d, [(6, 7), (16, 5)])


def spore():
    im, d = new()
    d.rectangle([9, 13, 14, 20], fill=(226, 214, 236))  # stem
    d.pieslice([3, 3, 20, 20], 180, 360, fill=(150, 80, 180))  # cap
    for x, y in [(7, 8), (12, 6), (16, 9)]:
        d.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(236, 220, 250))
    return finish(im, d, [(6, 6), (9, 4)])


def mind():
    im, d = new()
    d.ellipse([3, 3, 20, 20], fill=(236, 140, 200))
    d.ellipse([8, 1, 23, 16], fill=(0, 0, 0, 0))        # carve the crescent
    star = [(17, 14), (18, 16), (20, 16), (18, 17), (19, 19), (17, 18), (15, 19), (16, 17), (14, 16), (16, 16)]
    d.polygon(star, fill=(255, 230, 120))
    return finish(im, d, [(5, 9), (5, 10)])


def ember():
    im, d = new()
    d.ellipse([2, 2, 21, 21], fill=(220, 80, 50))
    d.ellipse([5, 5, 18, 18], fill=(0, 0, 0, 0))        # the ring
    d.polygon([(12, 6), (16, 13), (14, 17), (10, 17), (8, 13)], fill=(255, 170, 60))
    d.polygon([(12, 10), (14, 14), (12, 16), (10, 14)], fill=(255, 236, 150))
    return finish(im, d, [(5, 6), (6, 5)])


def quake():
    im, d = new()
    d.polygon([(2, 20), (9, 5), (13, 12), (16, 7), (22, 20)], fill=(176, 140, 90))
    d.polygon([(2, 20), (9, 5), (9, 20)], fill=(206, 172, 116))
    d.line([(12, 20), (11, 16), (13, 13), (12, 10)], fill=OUTLINE)   # the crack
    return finish(im, d, [(8, 7), (16, 9)])


DRAW = [cairn, tide, spark, sprout, spore, mind, ember, quake]

os.makedirs(OUT, exist_ok=True)
for i, fn in enumerate(DRAW):
    fn().resize((S * 2, S * 2), Image.NEAREST).save(os.path.join(OUT, "badge_%d_%s.png" % (i, NAMES[i].lower())))
print("badges:", ", ".join(n + " Badge" for n in NAMES))

if len(sys.argv) > 2:
    APP = sys.argv[2]
    snap = lambda v: min((0, 85, 170, 255), key=lambda x: abs(x - v))
    dst = os.path.join(APP, "resources", "drawables", "badges")
    shutil.rmtree(dst, ignore_errors=True)
    os.makedirs(dst)
    # One strip, badge i at x = 48 * i (Connect IQ allows at most 254 drawables).
    strip = Image.new("RGBA", (48 * len(NAMES), 48), (0, 0, 0, 0))
    for i, n in enumerate(NAMES):
        im = Image.open(os.path.join(OUT, "badge_%d_%s.png" % (i, n.lower()))).convert("RGBA")
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                r, g, b, a = px[x, y]
                px[x, y] = (snap(r), snap(g), snap(b), 255) if a >= 128 else (0, 0, 0, 0)
        strip.paste(im, (48 * i, 0))
    strip.save(os.path.join(dst, "badges.png"))
    cols = sorted({p[:3] for p in strip.getdata() if p[3]})
    pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
    xml = ['    <bitmap id="badges" filename="badges/badges.png"><palette disableTransparency="false">%s</palette></bitmap>' % pal]
    open(os.path.join(APP, "resources", "drawables", "badges.xml"), "w").write("<drawables>\n" + "\n".join(xml) + "\n</drawables>\n")
    print("installed", len(xml), "badges into", dst)
