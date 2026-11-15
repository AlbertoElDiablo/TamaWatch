"""Original battle backdrops for TamaWatch: 7 biomes x day/night, drawn from scratch.

usage: python3 make_battle_backs.py <out dir> [<TamaWatch>]

With a TamaWatch path, also dithers them onto the watch's 64 colours into
resources/drawables/battle/ with battle.xml (ids battle_<biome index>_<day|night>).

Chunky pixel art drawn at 140x75 and scaled 2x to 280x150: a sky, layered scenery
and two ground patches (the far one for the opponent, the near one for your pet).
Writes battle_<biome>_<day|night>.png (full colour; the watch conversion dithers them).
"""
import math, os, random, sys
from PIL import Image, ImageDraw

OUT = sys.argv[1]
W, H = 140, 75
HORIZON = 34
BIOMES = ["meadow", "beach", "forest", "volcano", "mountain", "snow", "graveyard"]


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def night_tone(c, amount=0.62):
    """Darken toward a cool night blue."""
    return mix(c, (14, 20, 44), amount)


class Scene:
    def __init__(self, night):
        self.night = night
        self.im = Image.new("RGB", (W, H))
        self.d = ImageDraw.Draw(self.im)

    def c(self, col):
        return night_tone(col) if self.night else col

    def sky(self, top, bottom, bands=6):
        if self.night:
            top, bottom = (10, 14, 34), (32, 42, 78)
        for i in range(bands):
            y0 = HORIZON * i // bands
            y1 = HORIZON * (i + 1) // bands
            self.d.rectangle([0, y0, W, y1], fill=mix(top, bottom, i / (bands - 1)))

    def sun_or_moon(self, x=112, y=9):
        if self.night:
            self.d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(236, 232, 200))
            self.d.ellipse([x - 2, y - 7, x + 7, y + 3], fill=(16, 22, 46))   # crescent bite
            rnd = random.Random(7)
            for _ in range(26):
                sx, sy = rnd.randrange(W), rnd.randrange(HORIZON - 4)
                self.d.point((sx, sy), fill=(220, 226, 255) if rnd.random() < 0.5 else (150, 160, 210))
        else:
            self.d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=(255, 236, 150))
            self.d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 250, 214))

    def cloud(self, x, y, s=1.0):
        col = self.c((255, 255, 255)) if not self.night else (60, 70, 108)
        for dx, dy, r in [(0, 2, 4), (5, 0, 5), (11, 2, 4), (6, 3, 4)]:
            r = int(r * s)
            self.d.ellipse([x + int(dx * s) - r, y + dy - r, x + int(dx * s) + r, y + dy + r], fill=col)

    def ground(self, near, far):
        for y in range(HORIZON, H):
            self.d.line([0, y, W, y], fill=self.c(mix(far, near, (y - HORIZON) / (H - HORIZON))))

    def patch(self, cx, cy, rx, ry, base, rim, detail=None):
        """A raised ground patch: shadow rim, top, highlight band, optional texture."""
        self.d.ellipse([cx - rx, cy - ry + 2, cx + rx, cy + ry + 2], fill=self.c(rim))
        self.d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=self.c(base))
        self.d.ellipse([cx - rx + 4, cy - ry + 1, cx + rx - 10, cy - 1], fill=self.c(mix(base, (255, 255, 255), 0.18)))
        if detail:
            detail(cx, cy, rx, ry)

    def both_patches(self, base, rim, detail=None):
        self.patch(104, 40, 26, 6, base, rim, detail)   # opponent, far right
        self.patch(36, 64, 34, 8, base, rim, detail)    # your pet, near left


# ---------- biomes ----------

def meadow(s):
    s.sky((120, 190, 236), (214, 238, 236))
    s.sun_or_moon(); s.cloud(18, 8); s.cloud(60, 13, 0.8)
    # rolling hills
    for i, (col, base) in enumerate([((126, 196, 120), 30), ((98, 172, 96), 33)]):
        pts = [(x, base - int(4 * math.sin(x / (14 + i * 6) + i * 2))) for x in range(0, W + 1, 2)]
        s.d.polygon(pts + [(W, HORIZON + 2), (0, HORIZON + 2)], fill=s.c(col))
    s.ground((86, 160, 80), (122, 192, 110))
    rnd = random.Random(1)
    for _ in range(70):   # grass blades
        x, y = rnd.randrange(W), rnd.randrange(HORIZON + 2, H)
        s.d.line([x, y, x + rnd.choice([-1, 0, 1]), y - 2], fill=s.c((60, 126, 62)))
    for _ in range(14):   # flowers
        x, y = rnd.randrange(W), rnd.randrange(HORIZON + 4, H)
        s.d.point((x, y), fill=s.c(rnd.choice([(250, 236, 120), (244, 140, 160), (255, 255, 255)])))

    def tufts(cx, cy, rx, ry):
        for k in range(-rx + 4, rx - 4, 5):
            s.d.line([cx + k, cy + 1, cx + k + 1, cy - 2], fill=s.c((70, 140, 66)))
    s.both_patches((150, 206, 120), (88, 146, 74), tufts)


def beach(s):
    s.sky((112, 186, 240), (210, 236, 248))
    s.sun_or_moon(); s.cloud(24, 9)
    # sea with crests
    s.d.rectangle([0, HORIZON - 9, W, HORIZON + 6], fill=s.c((60, 150, 206)))
    rnd = random.Random(2)
    for _ in range(18):
        x, y = rnd.randrange(W - 6), rnd.randrange(HORIZON - 8, HORIZON + 5)
        s.d.line([x, y, x + rnd.randrange(3, 7), y], fill=s.c((200, 236, 250)))
    # little island
    s.d.ellipse([84, HORIZON - 13, 112, HORIZON - 3], fill=s.c((86, 150, 110)))
    s.d.rectangle([84, HORIZON - 8, 112, HORIZON - 7], fill=s.c((60, 150, 206)))
    # sand with a foam line
    for y in range(HORIZON + 6, H):
        s.d.line([0, y, W, y], fill=s.c(mix((236, 220, 168), (224, 200, 140), (y - HORIZON) / (H - HORIZON))))
    s.d.line([0, HORIZON + 6, W, HORIZON + 6], fill=s.c((248, 248, 240)))

    def shells(cx, cy, rx, ry):
        s.d.point((cx - rx // 2, cy), fill=s.c((244, 160, 150)))
        s.d.point((cx + rx // 3, cy + 1), fill=s.c((255, 255, 255)))
    s.both_patches((244, 230, 186), (196, 172, 120), shells)


def forest(s):
    s.sky((150, 206, 226), (220, 240, 224))
    s.sun_or_moon(); s.cloud(40, 7, 0.8)
    rnd = random.Random(3)
    for layer, (col, base, size) in enumerate([((86, 140, 104), 28, 9), ((56, 112, 74), 33, 12)]):
        x = -4
        while x < W + 8:
            r = size + rnd.randrange(-2, 3)
            s.d.ellipse([x - r, base - r, x + r, base + r], fill=s.c(col))
            x += r + rnd.randrange(2, 6)
        s.d.rectangle([0, base, W, HORIZON + 2], fill=s.c(col))
    for x in (8, 128):   # two near trunks
        s.d.rectangle([x, 4, x + 5, HORIZON + 6], fill=s.c((104, 76, 50)))
        s.d.ellipse([x - 10, -6, x + 15, 16], fill=s.c((48, 102, 62)))
    s.ground((62, 120, 70), (96, 156, 92))
    for _ in range(10):  # mushrooms
        x, y = rnd.randrange(W), rnd.randrange(HORIZON + 6, H)
        s.d.point((x, y), fill=s.c((230, 90, 80))); s.d.point((x, y + 1), fill=s.c((240, 236, 220)))

    def leaves(cx, cy, rx, ry):
        for k in range(-rx + 6, rx - 6, 7):
            s.d.point((cx + k, cy + (k % 3) - 1), fill=s.c((200, 150, 70)))
    s.both_patches((124, 170, 98), (70, 116, 66), leaves)


def volcano(s):
    s.sky((150, 70, 64), (240, 150, 96))
    s.sun_or_moon(); s.cloud(20, 10, 0.9)
    s.d.polygon([(30, HORIZON + 1), (62, 8), (76, 8), (110, HORIZON + 1)], fill=s.c((96, 64, 60)))
    s.d.polygon([(62, 8), (69, 4), (76, 8)], fill=(255, 150, 60))
    for x0, x1 in [(66, 58), (71, 80)]:   # lava streams (glow at night too)
        s.d.line([x0, 9, x1, HORIZON - 2], fill=(255, 120, 40), width=2)
    for i, r in enumerate([5, 4, 3]):     # smoke puffs
        y = 2 - i * 4
        s.d.ellipse([70 + i * 3 - r, y - r, 70 + i * 3 + r, y + r], fill=s.c((120, 104, 104)))
    s.ground((92, 70, 64), (130, 96, 82))
    rnd = random.Random(4)
    for _ in range(9):    # glowing cracks
        x, y = rnd.randrange(W - 8), rnd.randrange(HORIZON + 4, H)
        s.d.line([x, y, x + 3, y - 1, x + 4, y + 2, x + 8, y + 1], fill=(250, 130, 60))   # jagged

    def rocks(cx, cy, rx, ry):
        s.d.ellipse([cx - rx // 2 - 3, cy - 2, cx - rx // 2 + 2, cy + 1], fill=s.c((70, 56, 54)))   # one boulder,
        s.d.point((cx + rx // 4, cy + 2), fill=s.c((70, 56, 54)))                                  # a pebble
        s.d.point((cx + rx // 4 + 3, cy + 1), fill=s.c((70, 56, 54)))
    s.both_patches((150, 112, 96), (88, 64, 58), rocks)


def mountain(s):
    s.sky((126, 182, 228), (222, 236, 244))
    s.sun_or_moon(); s.cloud(14, 12, 0.8)
    for peaks, col, snow in [([(0, 30), (22, 10), (44, 28), (70, 6), (98, 26), (124, 12), (W, 28)], (130, 138, 168), True),
                             ([(0, 34), (30, 20), (58, 33), (90, 18), (120, 33), (W, 26)], (104, 116, 128), False)]:
        s.d.polygon(peaks + [(W, HORIZON + 1), (0, HORIZON + 1)], fill=s.c(col))
        if snow:
            for (x0, y0), (x1, y1), (x2, y2) in zip(peaks, peaks[1:], peaks[2:]):
                if y1 < y0 and y1 < y2:
                    s.d.polygon([(x1 - 5, y1 + 5), (x1, y1), (x1 + 5, y1 + 5)], fill=s.c((246, 248, 252)))
    s.ground((150, 136, 106), (178, 166, 132))
    rnd = random.Random(5)
    for _ in range(12):
        x, y = rnd.randrange(W), rnd.randrange(HORIZON + 4, H)
        s.d.rectangle([x, y, x + 1, y + 1], fill=s.c((120, 110, 92)))

    def pebbles(cx, cy, rx, ry):
        s.d.point((cx - rx // 3, cy), fill=s.c((236, 236, 240)))   # edelweiss
        s.d.point((cx + rx // 2, cy - 1), fill=s.c((236, 236, 240)))
    s.both_patches((180, 166, 128), (122, 108, 86), pebbles)


def snow(s):
    s.sky((170, 196, 222), (232, 242, 250))
    s.sun_or_moon(); s.cloud(30, 9)
    if s.night:   # aurora ribbons
        for i, col in enumerate([(70, 220, 150), (80, 200, 220)]):
            pts = [(x, 12 + i * 4 + int(3 * math.sin(x / 9 + i))) for x in range(0, W, 3)]
            s.d.line(pts, fill=col, width=2)
    for x0, w0, h0 in [(10, 26, 10), (72, 34, 14), (116, 20, 8)]:   # icebergs
        s.d.polygon([(x0, HORIZON), (x0 + w0 // 3, HORIZON - h0), (x0 + w0 * 2 // 3, HORIZON - h0 + 3), (x0 + w0, HORIZON)],
                    fill=s.c((214, 232, 246)))
        s.d.polygon([(x0 + w0 // 3, HORIZON - h0), (x0 + w0 // 2, HORIZON), (x0 + w0, HORIZON)], fill=s.c((170, 198, 226)))
    s.ground((222, 234, 246), (240, 246, 252))
    rnd = random.Random(6)
    for _ in range(40):   # snowfall
        s.d.point((rnd.randrange(W), rnd.randrange(H)), fill=(255, 255, 255) if not s.night else (200, 210, 240))

    def cracks(cx, cy, rx, ry):
        s.d.line([cx - rx // 2, cy, cx - rx // 4, cy + 1, cx, cy], fill=s.c((170, 196, 222)))
    s.both_patches((236, 244, 252), (168, 190, 216), cracks)


def graveyard(s):
    s.sky((96, 84, 128), (178, 160, 196))
    s.sun_or_moon(); s.cloud(22, 10, 0.8)
    s.d.rectangle([0, HORIZON - 3, W, HORIZON + 1], fill=s.c((70, 64, 92)))
    for x in range(0, W, 6):   # iron fence
        s.d.line([x, HORIZON - 9, x, HORIZON], fill=s.c((40, 36, 56)))
        s.d.point((x, HORIZON - 10), fill=s.c((40, 36, 56)))
    s.d.line([0, HORIZON - 6, W, HORIZON - 6], fill=s.c((40, 36, 56)))
    for x0 in (16, 124):   # bare trees
        s.d.line([x0, HORIZON, x0, 10], fill=s.c((52, 44, 60)), width=2)
        s.d.line([x0, 18, x0 - 6, 11], fill=s.c((52, 44, 60)))
        s.d.line([x0, 15, x0 + 7, 9], fill=s.c((52, 44, 60)))
    s.ground((84, 82, 96), (110, 106, 120))
    for x0, y0 in [(56, 38), (80, 46), (120, 54), (8, 48)]:   # tombstones
        s.d.rectangle([x0, y0 - 6, x0 + 6, y0], fill=s.c((150, 150, 164)))
        s.d.ellipse([x0, y0 - 9, x0 + 6, y0 - 3], fill=s.c((150, 150, 164)))
    if s.night:  # wisps
        for x, y in [(66, 26), (96, 30)]:
            s.d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(150, 220, 255))

    def bones(cx, cy, rx, ry):
        s.d.line([cx + rx // 3, cy, cx + rx // 3 + 4, cy], fill=s.c((230, 226, 210)))
    s.both_patches((128, 122, 136), (80, 74, 92), bones)


DRAW = [meadow, beach, forest, volcano, mountain, snow, graveyard]

os.makedirs(OUT, exist_ok=True)
for name, fn in zip(BIOMES, DRAW):
    for night in (False, True):
        sc = Scene(night)
        fn(sc)
        sc.im.resize((W * 2, H * 2), Image.NEAREST).save(
            os.path.join(OUT, "battle_%s_%s.png" % (name, "night" if night else "day")))
print("wrote", len(BIOMES) * 2, "backdrops to", OUT)

if len(sys.argv) > 2:
    APP = sys.argv[2]
    levels = [0, 85, 170, 255]
    pal = Image.new("P", (1, 1))
    pal.putpalette([c for r in levels for g in levels for b in levels for c in (r, g, b)] + [0, 0, 0] * 192)
    dst = os.path.join(APP, "resources", "drawables", "battle")
    import shutil
    shutil.rmtree(dst, ignore_errors=True)
    os.makedirs(dst)
    xml = []
    # One bitmap per biome, day on top and night below (Connect IQ allows at most 254 drawables).
    for bi, name in enumerate(BIOMES):
        pair = Image.new("RGB", (W * 2, H * 4))
        for k, t in enumerate(("day", "night")):
            im = Image.open(os.path.join(OUT, "battle_%s_%s.png" % (name, t))).convert("RGB")
            pair.paste(im.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG).convert("RGB"), (0, k * H * 2))
        rid = "battle_%d" % bi
        pair.save(os.path.join(dst, rid + ".png"), optimize=True)
        cols = sorted(c for _, c in pair.getcolors(1 << 16))
        p = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
        xml.append('    <bitmap id="%s" filename="battle/%s.png"><palette disableTransparency="true">%s</palette></bitmap>' % (rid, rid, p))
    open(os.path.join(APP, "resources", "drawables", "battle.xml"), "w").write("<drawables>\n" + "\n".join(xml) + "\n</drawables>\n")
    print("installed", len(xml), "battle backdrops into", dst)
