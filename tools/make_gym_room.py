"""The strength game's room (TRAINING BAG): a small gym seen from its doorway, drawn from scratch in
pixel art at the app's design size (280 x 280) in the watch's 64 colours (no dithering: every colour
is one of them), with heavy dark outlines.

One-point perspective onto the back wall (red, glowing behind a dumbbell and GYM, with streaks), a
squat rack with its barbell and a bench in front of it; a recessed light panel in the ceiling (the
game's title and score sit on it); on the left a door, a strongman poster, a shelf of towels and a
bottle, a treadmill and a dumbbell rack; on the right a mirror, a shelf of kettlebells, foam rolls
and boxes, and a plant; a tiled floor and a red mat where the partner stands. The punching bag is
drawn by the game (it swings): only its ceiling bracket is here, at the pivot (MiniGame.drawBag:
140, 70).

usage: python3 make_gym_room.py <TamaWatch> [preview.png]
"""
import os, sys
from PIL import Image, ImageDraw

APP = sys.argv[1]
N = 280

K = (0, 0, 0)
DG = (85, 85, 85)
LG = (170, 170, 170)
W = (255, 255, 255)
CEIL = (170, 170, 170)
CEIL_D = (85, 85, 85)
LIGHT = (255, 255, 170)
WALL = (255, 170, 170)
WALL_L = (255, 255, 255)
WALL_S = (170, 85, 85)
RED = (170, 0, 0)
RED_M = (255, 85, 0)
RED_L = (255, 85, 85)
RED_D = (85, 0, 0)
FLOOR = (170, 170, 170)
FLOOR_L = (85, 85, 85)
FLOOR_H = (170, 170, 255)
WOOD = (170, 85, 0)
WOOD_L = (255, 170, 85)
WOOD_D = (85, 0, 0)
GLASS = (85, 170, 255)
GLASS_L = (170, 255, 255)
GREEN = (85, 170, 0)
GREEN_L = (170, 255, 85)
GREEN_D = (0, 85, 0)
YEL = (255, 170, 0)
YEL_L = (255, 255, 85)
BLUE = (0, 85, 170)
BLUE_L = (85, 170, 255)
PURP = (170, 85, 255)
PURP_D = (85, 0, 170)
SKIN = (255, 170, 85)
DOOR = (85, 85, 170)

im = Image.new("RGB", (N, N), K)
d = ImageDraw.Draw(im)

# the back wall's corners and the vanishing point: its edges run out to the screen's corners
BL, BR, BT, BB = 88, 192, 80, 176
VX, VY = 140, 128


def floor_y(x):
    """y of the floor's edge along a side wall at column x."""
    cx = BL if x < VX else BR
    return VY + (BB - VY) * (x - VX) / (cx - VX)


def ceil_y(x):
    cx = BL if x < VX else BR
    return VY + (BT - VY) * (x - VX) / (cx - VX)


def box(x0, y0, x1, y1, fill, out=K):
    d.rectangle((x0, y0, x1, y1), fill=out)
    d.rectangle((x0 + 1, y0 + 1, x1 - 1, y1 - 1), fill=fill)


def poly(pts, fill, out=K):
    d.polygon(pts, fill=fill, outline=out)


# ---------- floor: tiles (rays from the vanishing point, rows closer toward the back) ----------
d.rectangle((0, 0, N, N), fill=FLOOR)
y = BB
step = 6
rows = []
while y < N:
    rows.append(int(y))
    y += step
    step += 4
for r in rows:
    d.line([(0, r + 1), (N, r + 1)], fill=FLOOR_H)          # each tile's lit front edge
    d.line([(0, r), (N, r)], fill=FLOOR_L)
for x in range(BL - 8 * 26, BR + 8 * 26 + 1, 26):
    d.line([(x, BB), (VX + (x - VX) * (N + 40 - VY) / (BB - VY), N + 40)], fill=FLOOR_L)

# ---------- ceiling ----------
poly([(0, 0), (N, 0), (BR, BT), (BL, BT)], CEIL, CEIL)
# darker toward the walls (a band along each edge)
for i in range(1, 7):
    d.line([(i * 2, 0), (BL + i, BT - 1)], fill=CEIL_D)
    d.line([(N - i * 2, 0), (BR - i, BT - 1)], fill=CEIL_D)
d.line([(BL, BT - 2), (BR, BT - 2)], fill=CEIL_D)
d.line([(BL, BT - 1), (BR, BT - 1)], fill=CEIL_D)
# recessed light panel: dark rim, cream bevel, white glass with brighter bars
poly([(70, 4), (210, 4), (200, 62), (80, 62)], K)
poly([(73, 6), (207, 6), (198, 60), (82, 60)], LIGHT, LIGHT)
poly([(80, 11), (200, 11), (193, 55), (87, 55)], W, W)
d.line([(81, 10), (199, 10)], fill=CEIL_D)                 # the bevel's inner shadow
for (y0, y1) in ((13, 15), (52, 53)):
    d.rectangle((86, y0, 194, y1), fill=LIGHT)
d.line([(73, 6), (82, 60)], fill=W)
d.line([(207, 6), (198, 60)], fill=W)
# the bag's bracket (the chain's pivot at 140, 70): a plate on the ceiling and a hook
box(124, 63, 156, 68, DG)
d.line([(126, 64), (154, 64)], fill=LG)
box(135, 67, 145, 73, LG)
d.point((137, 69), fill=W)

# ---------- side walls ----------
poly([(0, 0), (BL, BT), (BL, BB), (0, floor_y(0))], WALL, WALL)
poly([(N, 0), (BR, BT), (BR, BB), (N, floor_y(N))], WALL, WALL)
# shading into the corners, the wall's top edge, the room's corners
for i in range(4):
    d.line([(BL - 1 - i, ceil_y(BL - 1 - i) + 1), (BL - 1 - i, floor_y(BL - 1 - i) - 1)], fill=WALL_S if i < 2 else WALL)
    d.line([(BR + 1 + i, ceil_y(BR + 1 + i) + 1), (BR + 1 + i, floor_y(BR + 1 + i) - 1)], fill=WALL_S if i < 2 else WALL)
d.line([(0, 0), (BL, BT)], fill=K, width=2)
d.line([(N, 0), (BR, BT)], fill=K, width=2)
# skirting boards
for s in (0, 1):
    xa, xb = (0, BL) if s == 0 else (BR, N)
    d.line([(xa, floor_y(xa) - 3), (xb, BB - 3)], fill=WOOD, width=3)
    d.line([(xa, floor_y(xa) - 5), (xb, BB - 5)], fill=WOOD_D)
    d.line([(xa, floor_y(xa)), (xb, BB)], fill=K, width=2)

# ---------- back wall: red, glowing behind the dumbbell and GYM ----------
d.rectangle((BL, BT, BR, BB), fill=RED)
glow = Image.new("RGB", (N, N), RED)                       # the glow: a wide arc of light, the edges
ImageDraw.Draw(glow).ellipse((64, 46, 216, 240), fill=RED_M)   # dark (clipped to the wall)
im.paste(glow.crop((BL, BT, BR + 1, BB + 1)), (BL, BT))
d.rectangle((BL, BT, BR, BT + 3), fill=RED_D)              # the ceiling's shadow
d.rectangle((BL, BB - 6, BR, BB), fill=RED_D)              # skirting
d.line([(BL, BB - 6), (BR, BB - 6)], fill=WOOD)
d.line([(BL, BT), (BL, BB)], fill=K, width=2)
d.line([(BR, BT), (BR, BB)], fill=K, width=2)
# streaks either side
for s in (-1, 1):
    for i, (yy, ln) in enumerate(((106, 14), (114, 18), (122, 12))):
        x0 = VX + s * 34
        d.line([(x0, yy), (x0 + s * ln, yy - 6)], fill=LIGHT, width=3)
# dumbbell
box(114, 94, 166, 99, W)
for x0 in (110, 162):
    box(x0, 86, x0 + 8, 107, W)
    d.line([(x0 + 2, 88), (x0 + 2, 104)], fill=LG)
for x0 in (104, 170):
    box(x0, 90, x0 + 6, 103, W)
# GYM in a framed box
box(116, 112, 164, 128, RED_D, W)
d.rectangle((117, 113, 163, 127), fill=W)
d.rectangle((119, 115, 161, 125), fill=RED_D)
LET = {"G": ["0111", "1000", "1011", "1001", "0111"], "Y": ["101", "101", "010", "010", "010"],
       "M": ["10001", "11011", "10101", "10001", "10001"]}
x = 125
for ch in "GYM":
    rows_ = LET[ch]
    for yy, r in enumerate(rows_):
        for xx, c in enumerate(r):
            if c == "1":
                d.rectangle((x + xx * 2 - 1, 116 + yy * 2, x + xx * 2, 117 + yy * 2), fill=W)
    x += len(rows_[0]) * 2 + 3

# ---------- squat rack with a barbell, and a bench (in front of the back wall) ----------
for x0 in (110, 162):
    box(x0, 128, x0 + 8, 188, DG)
    d.line([(x0 + 2, 130), (x0 + 2, 186)], fill=LG)
    box(x0 - 4, 186, x0 + 12, 192, DG)
box(110, 126, 170, 131, DG)                                # the top bar
for x0 in (108, 166):
    box(x0, 150, x0 + 6, 156, YEL)                         # J-hooks
box(96, 150, 184, 154, LG)                                 # the bar
d.line([(97, 151), (183, 151)], fill=W)
for x0 in (92, 178):
    box(x0, 140, x0 + 10, 164, DG)                          # plates
    box(x0 + 2, 144, x0 + 8, 160, K)
    d.line([(x0 + 3, 145), (x0 + 3, 158)], fill=DG)
# bench
box(126, 170, 154, 180, RED)
d.line([(128, 172), (152, 172)], fill=RED_L)
box(136, 180, 144, 192, LG)
box(130, 191, 150, 195, LG)

# ---------- left wall ----------
# door: frame, panel, little window, handle
poly([(12, 50), (46, 62), (46, 214), (12, 236)], LG)
poly([(16, 56), (42, 65), (42, 211), (16, 229)], DOOR)
d.line([(17, 58), (17, 227)], fill=(85, 85, 255))
poly([(23, 92), (37, 96), (37, 110), (23, 107)], GLASS)
d.line([(26, 103), (33, 97)], fill=GLASS_L)
d.line([(28, 106), (35, 100)], fill=GLASS_L)
box(36, 150, 40, 158, W)
# strongman poster
poly([(52, 68), (76, 76), (76, 124), (52, 124)], WOOD_D)
poly([(54, 71), (74, 78), (74, 122), (54, 122)], RED)
fig = ["..1..1..", ".11..11.", "11.11.11", "1.1111.1", "...11...", "..1111..", "..1..1..", "..1..1..", ".11..11."]
for yy, r in enumerate(fig):
    for xx, c in enumerate(r):
        if c == "1":
            d.rectangle((56 + xx * 2, 84 + yy * 3, 57 + xx * 2, 86 + yy * 3), fill=SKIN)
d.rectangle((56, 114, 72, 116), fill=SKIN)
# shelf with towels and a bottle
box(70, 116, 96, 120, WOOD)
d.line([(72, 121), (72, 124)], fill=WOOD_D, width=2)
for i, yy in enumerate((110, 104)):
    box(72, yy, 86, yy + 6, W, LG)
box(88, 98, 94, 115, YEL)
box(89, 95, 93, 98, BLUE)
d.line([(89, 101), (89, 112)], fill=YEL_L)
# treadmill: belt, frame, upright and console
poly([(66, 200), (112, 180), (124, 188), (80, 210)], DG)
poly([(70, 199), (112, 182), (118, 186), (78, 204)], K, K)
d.line([(72, 203), (116, 186)], fill=LG)
box(70, 138, 76, 202, LG)                                  # the upright
poly([(60, 126), (92, 132), (90, 146), (62, 140)], LG)     # the console
poly([(66, 130), (86, 134), (85, 142), (66, 138)], BLUE)
for i, hh in enumerate((4, 6, 3)):
    d.rectangle((70 + i * 4, 140 - hh, 71 + i * 4, 140), fill=BLUE_L)
d.line([(86, 136), (110, 154)], fill=K, width=3)            # handrail
d.line([(86, 136), (110, 154)], fill=LG)
# dumbbell rack (bottom left): a white stand with two rows of dumbbells
poly([(28, 186), (86, 174), (86, 226), (28, 238)], LG)
poly([(32, 190), (82, 180), (82, 222), (32, 233)], W, W)
d.line([(32, 208), (82, 198)], fill=LG, width=2)
for row, y0 in enumerate((180, 200)):
    for i in range(4):
        bx = 34 + i * 12
        by = y0 + 6 - i * 2 + row * 2
        box(bx, by, bx + 9, by + 9, DG)
        d.rectangle((bx + 2, by + 2, bx + 3, by + 3), fill=LG)
        d.line([(bx + 9, by + 4), (bx + 11, by + 4)], fill=K, width=2)
for x0 in (30, 80):
    box(x0, 226 if x0 == 30 else 216, x0 + 5, 244 if x0 == 30 else 232, DG)

# ---------- right wall ----------
# mirror: grey frame, blue glass with white shine
poly([(204, 66), (262, 52), (262, 152), (204, 146)], LG)
poly([(209, 71), (257, 59), (257, 147), (209, 141)], GLASS)
d.line([(205, 67), (205, 145)], fill=W)
for (x0, ln) in ((216, 26), (228, 34), (242, 20)):
    d.line([(x0, 128), (x0 + ln // 2, 128 - ln)], fill=GLASS_L, width=3)
d.line([(209, 141), (257, 147)], fill=BLUE)
# shelf: kettlebells, foam rolls, boxes
poly([(200, 158), (238, 164), (238, 238), (200, 226)], WOOD)
for (ya, yb) in ((162, 184), (188, 208), (212, 230)):
    poly([(204, ya + 1), (234, ya + 5), (234, yb + 5), (204, yb)], WOOD_D, WOOD_D)
d.line([(201, 159), (201, 225)], fill=WOOD_L)
for kx in (206, 220):                                      # kettlebells
    d.ellipse((kx, 174 + (kx - 206) // 5, kx + 11, 186 + (kx - 206) // 5), fill=K)
    d.ellipse((kx + 1, 175 + (kx - 206) // 5, kx + 10, 185 + (kx - 206) // 5), fill=DG)
    d.arc((kx + 2, 168 + (kx - 206) // 5, kx + 9, 180 + (kx - 206) // 5), 180, 360, fill=K, width=2)
    d.point((kx + 3, 177 + (kx - 206) // 5), fill=LG)
for (rx, c, cd) in ((205, BLUE, BLUE_L), (219, PURP, (255, 170, 255))):  # foam rolls, end on
    d.ellipse((rx, 196 + (rx - 205) // 5, rx + 12, 208 + (rx - 205) // 5), fill=K)
    d.ellipse((rx + 1, 197 + (rx - 205) // 5, rx + 11, 207 + (rx - 205) // 5), fill=c)
    d.arc((rx + 3, 199 + (rx - 205) // 5, rx + 9, 205 + (rx - 205) // 5), 0, 300, fill=cd)
for bx in (205, 219):                                      # boxes
    oy = (bx - 205) // 5
    box(bx, 218 + oy, bx + 12, 230 + oy, YEL)
    d.line([(bx + 3, 222 + oy), (bx + 9, 222 + oy)], fill=WOOD)
# plant in a white pot
poly([(236, 208), (258, 208), (255, 236), (239, 236)], W, K)
d.line([(240, 210), (242, 234)], fill=LG, width=2)
d.rectangle((236, 207, 258, 210), fill=LG)
d.line([(236, 207), (258, 207)], fill=K)
leaves = [(247, 207, 232, 176), (247, 207, 240, 168), (247, 207, 250, 164), (247, 207, 260, 172),
          (247, 207, 266, 184), (247, 207, 230, 190), (247, 207, 262, 196)]
for (x0, y0, x1, y1) in leaves:
    d.line([(x0, y0), (x1, y1)], fill=GREEN_D, width=5)
for (x0, y0, x1, y1) in leaves:
    d.line([(x0, y0), (x1, y1)], fill=GREEN, width=3)
    d.line([((x0 + x1) // 2, (y0 + y1) // 2), (x1, y1)], fill=GREEN_L)

# ---------- the mat the partner stands on (its feet at 232, x ~92: MiniGame.drawBag) ----------
poly([(58, 220), (128, 220), (134, 246), (52, 246)], RED_L)
d.line([(59, 221), (127, 221)], fill=W)
d.line([(66, 222), (62, 244)], fill=W, width=2)
d.line([(120, 222), (124, 244)], fill=W, width=2)
d.line([(53, 245), (133, 245)], fill=RED, width=2)

d_out = os.path.join(APP, "resources", "drawables", "gym")
os.makedirs(d_out, exist_ok=True)
im.save(os.path.join(d_out, "gym.png"))
cols = sorted(set(im.get_flattened_data()))
assert all(all(v in (0, 85, 170, 255) for v in c) for c in cols), cols
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(APP, "resources", "drawables", "gym.xml"), "w").write(
    '<drawables>\n    <bitmap scope="application" id="gym" filename="gym/gym.png"><palette disableTransparency="true">%s</palette></bitmap>\n</drawables>\n' % pal)
print("gym room", im.size, len(cols), "colours")
if len(sys.argv) > 2:
    prev = im.resize((N * 2, N * 2), Image.NEAREST)
    mask = Image.new("L", prev.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, prev.width - 1, prev.height - 1), fill=255)
    out = Image.new("RGB", prev.size, (40, 40, 40))
    out.paste(prev, (0, 0), mask)
    out.save(sys.argv[2])
