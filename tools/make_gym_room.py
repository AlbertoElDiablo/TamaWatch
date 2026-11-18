"""The strength game's room (TRAINING BAG), from the user's picture tools/gym_room_ref.png (a pixel-art
gym, 1446 x 1087): its full height fills the round screen (280 x 280, the app's design size), cut to
the middle 280 columns, every screen pixel the commonest colour of the picture's pixels under it
(never a blend), in the watch's 64 colours.

A colour between those 64 (the picture's beige walls, grey-lavender ceiling and floor, tomato red)
becomes a checkerboard of the two nearest it, when that's closer than any one of them. The checker
must be laid at the picture's final size (resizing a checkerboard breaks its pattern), so this writes
tools/gym_room_src.png with a placeholder colour for each such pair (tools/gym_room_dither.json:
placeholder -> the two colours) and the 280-pixel picture checkered; make_scaled.py resizes the
source for each screen, then checkers it.

The punching bag is the game's own (it swings from the ceiling: MiniGame.drawBag, which also draws
its bracket); the partner stands on the picture's mat.

usage: python3 make_gym_room.py <TamaWatch> [preview.png]
"""
import json, os, sys
from collections import Counter
from PIL import Image, ImageDraw

APP = sys.argv[1]
N = 280
LV = (0, 85, 170, 255)

# the 64 colours, and the checkerboards of two of them that differ by one step in each channel at most
SOLID = [(r, g, b) for r in LV for g in LV for b in LV]
MIX = {}                                   # placeholder (their average) -> the pair
for i, a in enumerate(SOLID):
    for b in SOLID[i + 1:]:
        if all(abs(x - y) <= 85 for x, y in zip(a, b)):
            avg = tuple((x + y) // 2 for x, y in zip(a, b))
            MIX.setdefault(avg, (a, b))
CHOICES = SOLID + list(MIX)


# The home screen's shades (tools/boost_colours.py): each non-grey colour's weakest channel(s) one
# step down, so colours hold up on the MIP screen as the rest of the app's do. Applied to the solid
# colours and to both colours of every checkerboard.
def boost(c):
    lv = [min(range(4), key=lambda i: abs(i * 85 - v)) for v in c[:3]]
    m, M = min(lv), max(lv)
    if M != m:
        lv = [max(0, v - 1) if v == m else v for v in lv]
    return tuple(v * 85 for v in lv)


for _k in list(MIX):
    MIX[_k] = (boost(MIX[_k][0]), boost(MIX[_k][1]))


GREYS = [p for p in CHOICES if max(p) - min(p) == 0 or (p in MIX and all(max(q) == min(q) for q in MIX[p]))]


def nearest(c, cache={}):
    if c not in cache and max(c) - min(c) < 26:
        # nearly grey (the treadmill's frame, the outlines): a grey, never a tinted checkerboard
        # (lavender ones turned purple in the boost)
        cache[c] = min(GREYS, key=lambda p: sum((x - y) ** 2 for x, y in zip(c, p)) + (300 if p in MIX else 0))
    if c not in cache and not (c[0] - c[1] > 40 and c[2] - c[1] > 40):
        # not a real purple (the treadmill's lavender grey): no checkerboard the boost turns magenta
        ok = [p for p in CHOICES if not (p in MIX and any(q[0] == q[2] and q[0] > q[1] for q in MIX[p]))]
        cache[c] = min(ok, key=lambda p: sum((x - y) ** 2 for x, y in zip(c, p)) + (300 if p in MIX else 0))
    if c not in cache:
        # a little weight against the checkerboards: a solid colour when about as close
        cache[c] = min(CHOICES, key=lambda p: sum((x - y) ** 2 for x, y in zip(c, p)) + (300 if p in MIX else 0))
    return cache[c]


ref = Image.open(os.path.join(APP, "tools", "gym_room_ref.png")).convert("RGB")
W0, H0 = ref.size
k = H0 / N                                 # source pixels per screen pixel
x_off = (W0 - N * k) / 2                   # the middle 280 columns
px = ref.load()
src = Image.new("RGB", (N, N))
sp = src.load()
for y in range(N):
    y0, y1 = int(y * k), max(int(y * k) + 1, int((y + 1) * k))
    for x in range(N):
        x0 = int(x_off + x * k)
        x1 = max(x0 + 1, int(x_off + (x + 1) * k))
        votes = Counter()
        for yy in range(y0, min(y1, H0)):
            for xx in range(x0, min(x1, W0)):
                votes[nearest(px[xx, yy])] += 1
        sp[x, y] = votes.most_common(1)[0][0]


def dither(img):
    img = img.convert("RGB")
    p = img.load()
    for y in range(img.height):
        for x in range(img.width):
            c = p[x, y]
            if c in MIX:
                p[x, y] = MIX[c][(x + y) & 1]
    return img


sp = src.load()
for y in range(N):
    for x in range(N):
        if sp[x, y] not in MIX:
            sp[x, y] = boost(sp[x, y])
used = {c for c in src.get_flattened_data()}
src.save(os.path.join(APP, "tools", "gym_room_src.png"))
json.dump([[list(c), [list(MIX[c][0]), list(MIX[c][1])]] for c in sorted(used) if c in MIX],
          open(os.path.join(APP, "tools", "gym_room_dither.json"), "w"))
im = dither(src)
d_out = os.path.join(APP, "resources", "drawables", "gym")
os.makedirs(d_out, exist_ok=True)
im.save(os.path.join(d_out, "gym.png"))
cols = sorted(set(im.get_flattened_data()))
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(APP, "resources", "drawables", "gym.xml"), "w").write(
    '<drawables>\n    <bitmap scope="application" id="gym" filename="gym/gym.png"><palette disableTransparency="true">%s</palette></bitmap>\n</drawables>\n' % pal)
print("gym room", im.size, len(cols), "colours,", sum(1 for c in used if c in MIX), "checkered")
if len(sys.argv) > 2:
    prev = im.resize((N * 2, N * 2), Image.NEAREST)
    mask = Image.new("L", prev.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, prev.width - 1, prev.height - 1), fill=255)
    out = Image.new("RGB", prev.size, (30, 30, 30))
    out.paste(prev, (0, 0), mask)
    out.save(sys.argv[2])
