"""SPRINT START's pictures, from the user's three: the stadium track (tools/sprint_track.png, 1254 x
1254), the traffic light (tools/sprint_light.png) and the rail between the lanes (tools/sprint_rail.png),
pixel for pixel: every watch pixel the commonest colour of the picture's pixels under it (never a
blend), in the watch's 64 colours, a colour between them a checkerboard of two (laid after any
resizing: tools/sprint_src.png holds placeholders, tools/sprint_dither.json what they stand for and the
parts make_scaled.py shrinks one by one).

One picture (Connect IQ allows an app 254), resources/drawables/sprint/sprint.png, 280 wide:
  0-279    the track at a quarter size, its lanes across the screen's middle; the middle of the
           straight cut (212 of the picture's columns) so the start and the finish line both sit
           inside the round screen, and its left and right edges carried on a little
  280-345  the light: lit (x 0) and dark (x 40), 38 x 66
  346-372  the rail, 232 x 27
and source/SprintArt.mc with where everything is.

usage: python3 make_sprint_art.py <TamaWatch>
"""
import json, os, sys
from collections import Counter
from PIL import Image

APP = sys.argv[1]
T = os.path.join(APP, "tools")
LV = (0, 85, 170, 255)
SOLID = [(r, g, b) for r in LV for g in LV for b in LV]
MIX = {}
for i, a in enumerate(SOLID):
    for b in SOLID[i + 1:]:
        if all(abs(x - y) <= 85 for x, y in zip(a, b)):
            MIX.setdefault(tuple((x + y) // 2 for x, y in zip(a, b)), (a, b))
CHOICES = SOLID + list(MIX)
CLEAR = (0, 0, 0, 0)
_near = {}


def nearest(c):
    if c not in _near:
        _near[c] = min(CHOICES, key=lambda p: sum((x - y) ** 2 for x, y in zip(c, p)) + (300 if p in MIX else 0))
    return _near[c]


def pixelate(img, w, h):
    """img (RGBA) to w x h: each pixel the commonest colour (or clear) of those under it."""
    px = img.load()
    W0, H0 = img.size
    kx, ky = W0 / w, H0 / h
    out = Image.new("RGBA", (w, h), CLEAR)
    op = out.load()
    for y in range(h):
        y0, y1 = int(y * ky), max(int(y * ky) + 1, int((y + 1) * ky))
        for x in range(w):
            x0, x1 = int(x * kx), max(int(x * kx) + 1, int((x + 1) * kx))
            # the commonest group of like colours under it (or clear), then the watch colour
            # nearest that group's average: even areas stay even (no specks where the picture's
            # colour falls between two of the watch's)
            votes = Counter()
            sums = {}
            for yy in range(y0, min(y1, H0)):
                for xx in range(x0, min(x1, W0)):
                    p = px[xx, yy]
                    key = None if p[3] < 128 else (p[0] // 40, p[1] // 40, p[2] // 40)
                    votes[key] += 1
                    if key is not None:
                        t = sums.setdefault(key, [0, 0, 0])
                        t[0] += p[0]; t[1] += p[1]; t[2] += p[2]
            key, n = votes.most_common(1)[0]
            if key is None:
                op[x, y] = CLEAR
            else:
                t = sums[key]
                op[x, y] = nearest((t[0] // n, t[1] // n, t[2] // n)) + (255,)
    return out


# ---------- the track ----------
src = Image.open(os.path.join(T, "sprint_track.png")).convert("RGBA")
S = 4                                       # picture pixels per watch pixel
PAD_L, CUT_A, CUT_B = 32, 600, 812          # columns 600-811 left out
TOP = 248                                   # the picture's row at the screen's top (lanes centred)
canvas = Image.new("RGBA", (280 * S, 280 * S))
x = 0
for _ in range(PAD_L):                      # the left edge carried on
    canvas.paste(src.crop((0, 0, 1, 1254)), (x, -TOP)); x += 1
canvas.paste(src.crop((0, 0, CUT_A, 1254)), (x, -TOP)); x += CUT_A
canvas.paste(src.crop((CUT_B, 0, 1254, 1254)), (x, -TOP)); x += 1254 - CUT_B
while x < canvas.width:                     # the right edge carried on
    canvas.paste(src.crop((1253, 0, 1254, 1254)), (x, -TOP)); x += 1
y = 1254 - TOP
while y < canvas.height:                    # the grass carried on below
    canvas.paste(canvas.crop((0, 1234 - TOP, canvas.width, 1235 - TOP)), (0, y)); y += 1
track = pixelate(canvas, 280, 280)


def at(sx):                                 # a picture column on the screen
    return (PAD_L + (sx if sx < CUT_A else sx - (CUT_B - CUT_A))) / S


def row(sy):
    return (sy - TOP) / S


# ---------- the light: lit, and dark (each lamp a dark shade of its colour) ----------
light = Image.open(os.path.join(T, "sprint_light.png")).convert("RGBA")
light = light.crop(light.getchannel("A").point(lambda a: 255 if a > 128 else 0).getbbox())
LH = 66
LW = round(light.width * LH / light.height)
lit = pixelate(light, LW, LH)


def lamp(c):
    """Which lamp a colour belongs to (0 red, 1 yellow, 2 green), or None."""
    r, g, b = c[:3]
    if r >= 170 and g <= 85 and b <= 85: return 0
    if r >= 170 and g >= 170 and b <= 85: return 1
    if g >= 170 and r <= 127 and b <= 85: return 2
    return None


DARK = [(85, 0, 0), (85, 85, 0), (0, 85, 0)]
dark = lit.copy()
dp = dark.load()
rows = [[], [], []]
for yy in range(LH):
    for xx in range(LW):
        p = dp[xx, yy]
        if p[3] and lamp(p) is not None:
            rows[lamp(p)].append(yy)
            dp[xx, yy] = DARK[lamp(p)] + (255,)
LAMPS = [[min(r) - 1, max(r) + 2] for r in rows]

# ---------- the rail ----------
rail = Image.open(os.path.join(T, "sprint_rail.png")).convert("RGBA")
rail = rail.crop(rail.getchannel("A").point(lambda a: 255 if a > 128 else 0).getbbox())
RW = 232
RH = round(rail.height * RW / rail.width)
railp = pixelate(rail, RW, RH)

# ---------- one picture ----------
LIGHT_Y, LIT_X, DARK_X = 280, 0, 40
RAIL_Y = LIGHT_Y + LH
sheet = Image.new("RGBA", (280, RAIL_Y + RH), CLEAR)
sheet.paste(track, (0, 0))
sheet.paste(lit, (LIT_X, LIGHT_Y))
sheet.paste(dark, (DARK_X, LIGHT_Y))
sheet.paste(railp, (0, RAIL_Y))
regions = [[0, 0, 280, 280], [LIT_X, LIGHT_Y, LW, LH], [DARK_X, LIGHT_Y, LW, LH], [0, RAIL_Y, RW, RH]]


def dither(img):
    img = img.copy()
    p = img.load()
    for yy in range(img.height):
        for xx in range(img.width):
            c = p[xx, yy]
            if c[3] and c[:3] in MIX:
                p[xx, yy] = MIX[c[:3]][(xx + yy) & 1] + (255,)
    return img


used = {c[:3] for c in sheet.get_flattened_data() if c[3]}
sheet.save(os.path.join(T, "sprint_src.png"))
json.dump({"mix": [[list(c), [list(MIX[c][0]), list(MIX[c][1])]] for c in sorted(used) if c in MIX],
           "regions": regions}, open(os.path.join(T, "sprint_dither.json"), "w"))
out = dither(sheet)
d_out = os.path.join(APP, "resources", "drawables", "sprint")
os.makedirs(d_out, exist_ok=True)
out.save(os.path.join(d_out, "sprint.png"))
cols = sorted({c[:3] for c in out.get_flattened_data() if c[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(APP, "resources", "drawables", "sprint.xml"), "w").write(
    '<drawables>\n    <bitmap scope="application" id="sprint" filename="sprint/sprint.png"><palette disableTransparency="false">%s</palette></bitmap>\n</drawables>\n' % pal)

lane1 = (round(row(628)), round(row(800)))
lane2 = (round(row(815)), round(row(991)))
open(os.path.join(APP, "source", "SprintArt.mc"), "w").write('''import Toybox.Lang;

// GENERATED by tools/make_sprint_art.py - do not edit by hand.
// Where things are in SPRINT START's picture (Rez.Drawables.sprint) and on its track.
module SprintArt {
    const LIGHT_Y = %d;         // the light's row in the picture; lit at x LIT_X, dark at DARK_X
    const LIT_X = %d;
    const DARK_X = %d;
    const LW = %d;
    const LH = %d;
    const LAMPS = %s;     // each lamp's rows in the light (red, yellow, green)
    const RAIL_Y = %d;          // the rail's row in the picture, its size
    const RAIL_W = %d;
    const RAIL_H = %d;
    const START_X = %d;         // the start and finish lines on the screen
    const FINISH_X = %d;
    const LANE1 = [%d, %d];     // the lanes' top and bottom on the screen
    const LANE2 = [%d, %d];
}
''' % (LIGHT_Y, LIT_X, DARK_X, LW, LH, json.dumps(LAMPS).replace(" ", ""), RAIL_Y, RW, RH,
       round(at(49)), round(at(1203)), lane1[0], lane1[1], lane2[0], lane2[1]))
print("sprint", sheet.size, len(cols), "colours; light", LW, LH, LAMPS, "rail", RW, RH,
      "start", round(at(49)), "finish", round(at(1203)), "lanes", lane1, lane2)
