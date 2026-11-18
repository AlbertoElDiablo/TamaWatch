"""The strength game's room (TRAINING BAG): a small gym seen from its doorway, drawn from scratch in
chunky pixel art on a 140 x 140 grid, saved at 2x (280 x 280, the app's design size) in the watch's
64 colours (no dithering: every colour is one of them).

One-point perspective onto the back wall (a red wall with a dumbbell and GYM); a light panel in the
ceiling (the game's title and score sit on it); on the left a door, a poster, a towel shelf and a
dumbbell rack; on the right a mirror, a shelf of kettlebells and a plant; a tiled floor and a red mat
where the partner stands. The punching bag itself is drawn by the game (it swings): only its ceiling
bracket is here, at the pivot (MiniGame.drawBag: 140, 70).

usage: python3 make_gym_room.py <TamaWatch> [preview.png]
"""
import os, sys
from PIL import Image, ImageDraw

APP = sys.argv[1]
G = 140

K = (0, 0, 0)
DG = (85, 85, 85)
LG = (170, 170, 170)
W = (255, 255, 255)
CEIL = (85, 85, 170)
CEIL_D = (0, 0, 85)
LIGHT = (255, 255, 170)
WALL = (255, 255, 170)
WALL_S = (255, 170, 85)
RED = (170, 0, 0)
RED_L = (255, 85, 85)
RED_D = (85, 0, 0)
FLOOR = (170, 170, 170)
FLOOR_L = (85, 85, 85)
WOOD = (170, 85, 0)
WOOD_D = (85, 0, 0)
GLASS = (85, 170, 255)
GREEN = (85, 170, 0)
GREEN_L = (170, 255, 85)
GREEN_D = (0, 85, 0)
YEL = (255, 170, 0)
BLUE = (0, 85, 170)
PURP = (170, 85, 255)

im = Image.new("RGB", (G, G), K)
d = ImageDraw.Draw(im)

# the back wall's corners, and the vanishing point (70, 64): its edges run out to the screen's
BL, BR, BT, BB = 44, 96, 40, 88
VX, VY = 70, 64


def edge_y(x, top):
    """y of the ceiling (top) or floor line along a side wall at column x."""
    cx = BL if x < VX else BR
    cy = BT if top else BB
    return VY + (cy - VY) * (x - VX) / (cx - VX)


# floor: tiles (rays from the vanishing point, rows closer together toward the back), then the
# ceiling and the side walls over it
d.rectangle((0, 0, G, G), fill=FLOOR)
for x in range(BL - 4 * 52, BR + 4 * 52 + 1, 13):
    d.line([(x, BB), (VX + (x - VX) * (G + 20 - VY) / (BB - VY), G + 20)], fill=FLOOR_L)
y = BB
step = 3
while y < G:
    d.line([(0, y), (G, y)], fill=FLOOR_L)
    y += step
    step += 2
d.polygon([(0, 0), (G, 0), (BR, BT), (BL, BT)], fill=CEIL)
d.polygon([(0, 0), (BL, BT), (BL, BB), (0, edge_y(0, False))], fill=WALL)
d.polygon([(G, 0), (BR, BT), (BR, BB), (G, edge_y(G, False))], fill=WALL)
# the side walls a shade darker toward the room's corners (a strip along each)
d.line([(BL - 1, BT + 1), (BL - 1, BB - 1)], fill=WALL_S)
d.line([(BR + 1, BT + 1), (BR + 1, BB - 1)], fill=WALL_S)
# skirting boards
d.line([(0, edge_y(0, False) - 1), (BL, BB - 1)], fill=WOOD, width=2)
d.line([(BR, BB - 1), (G, edge_y(G, False) - 1)], fill=WOOD, width=2)
# the ceiling's edges
d.line([(0, 0), (BL, BT)], fill=CEIL_D)
d.line([(G, 0), (BR, BT)], fill=CEIL_D)

# back wall: red, lighter streaks to each side of a white dumbbell, GYM under it
d.rectangle((BL, BT, BR, BB), fill=RED)
d.rectangle((BL, BT, BR, BT + 2), fill=RED_D)                 # the ceiling's shadow
for s in (-1, 1):
    for i, yy in enumerate((54, 58)):
        x0 = VX + s * 14
        d.line([(x0 + s * 2 * i, yy), (x0 + s * (8 + 2 * i), yy - 3)], fill=RED_L, width=2)
# dumbbell (white with dark edges)
d.rectangle((60, 46, 80, 48), fill=W)
for x0 in (56, 79):
    d.rectangle((x0, 43, x0 + 4, 51), fill=W, outline=DG)
d.rectangle((53, 45, 55, 49), fill=W, outline=DG)
d.rectangle((85, 45, 87, 49), fill=W, outline=DG)
d.line([(60, 46), (79, 46)], fill=LG)
# GYM in a white box (3 x 5 letters)
LET = {"G": ["111", "100", "101", "101", "111"], "Y": ["101", "101", "010", "010", "010"],
       "M": ["10001", "11011", "10101", "10001", "10001"]}
d.rectangle((58, 55, 82, 63), outline=W)
x = 61
for ch in "GYM":
    rows = LET[ch]
    for yy, r in enumerate(rows):
        for xx, c in enumerate(r):
            if c == "1":
                d.point((x + xx, 57 + yy), fill=W)
    x += len(rows[0]) + 2
# floor line at the back
d.line([(BL, BB), (BR, BB)], fill=RED_D)

# ceiling light panel (the title and score go on it)
d.polygon([(40, 5), (100, 5), (97, 29), (43, 29)], fill=W, outline=LIGHT)
d.polygon([(43, 8), (97, 8), (95, 26), (45, 26)], fill=LIGHT)
for yy in (11, 15, 19, 23):
    d.line([(46, yy), (48, yy)], fill=W)
    d.line([(92, yy), (94, yy)], fill=W)
d.polygon([(38, 4), (102, 4), (102, 5), (38, 5)], fill=CEIL_D)
d.line([(42, 30), (98, 30)], fill=CEIL_D)
# the bag's bracket (pivot at 70, 35)
d.rectangle((63, 31, 77, 33), fill=DG, outline=K)
d.rectangle((68, 33, 72, 36), fill=LG, outline=K)

# --- left wall ---
# door (its top and bottom follow the wall's perspective)
def wall_quad(x0, x1, top_at_x0, bot_at_x0, side):
    """A rectangle on a side wall: its top and bottom slope as the wall does (toward the back)."""
    def slope(top):
        return (edge_y(x1, top) - edge_y(x0, top))
    return [(x0, top_at_x0), (x1, top_at_x0 + slope(True) * 0.55), (x1, bot_at_x0 + slope(False) * 0.55), (x0, bot_at_x0)]

door = wall_quad(9, 22, 34, 112, -1)
d.polygon(door, fill=DG, outline=K)
inner = [(11, 37), (20, 39.5), (20, 103), (11, 107)]
d.polygon(inner, fill=(85, 85, 170))
d.rectangle((13, 50, 18, 54), fill=GLASS, outline=K)
d.line([(14, 53), (17, 51)], fill=W)
d.rectangle((18, 73, 19, 76), fill=W)
# poster: red, a white strongman
d.polygon([(27, 46), (35, 48), (35, 66), (27, 66)], fill=WOOD_D)
d.polygon([(28, 47.5), (34, 49), (34, 65), (28, 65)], fill=RED)
for (px, py) in [(31, 52), (30, 52), (31, 53), (30, 53)]:
    d.point((px, py), fill=W)
d.rectangle((29, 54, 32, 55), fill=W)        # shoulders
d.point((28, 53), fill=W); d.point((33, 53), fill=W)
d.rectangle((30, 56, 31, 59), fill=W)        # body
d.point((29, 60), fill=W); d.point((32, 60), fill=W)
d.line([(28, 62), (34, 62)], fill=W)
# towel shelf with a bottle
d.rectangle((36, 64, 43, 65), fill=WOOD)
d.line([(37, 66), (37, 67)], fill=WOOD_D)
d.rectangle((37, 60, 40, 63), fill=W, outline=LG)
d.rectangle((41, 59, 42, 63), fill=YEL, outline=WOOD)
# dumbbell rack (bottom left)
d.polygon([(8, 96), (34, 92), (34, 111), (8, 117)], fill=LG, outline=DG)
for row, yy in enumerate((96, 104)):
    for i in range(4):
        bx = 10 + i * 6
        by = yy - i * 1 + (0 if row == 0 else 0)
        d.rectangle((bx, by, bx + 4, by + 4), fill=DG, outline=K)
        d.point((bx + 1, by + 1), fill=LG)
d.line([(8, 110), (34, 105)], fill=W)
d.line([(10, 117), (10, 121)], fill=DG, width=2)
d.line([(32, 111), (32, 115)], fill=DG, width=2)

# --- right wall ---
# mirror
mir = [(105, 45), (128, 41), (128, 72), (105, 70)]
d.polygon(mir, fill=LG, outline=DG)
d.polygon([(107, 47), (126, 43.5), (126, 70), (107, 68)], fill=GLASS)
for o in (0, 6, 11):
    d.line([(110 + o, 62), (116 + o, 50)], fill=W)
# shelf of kettlebells, foam rolls and boxes
d.polygon([(102, 78), (118, 80), (118, 116), (102, 110)], fill=WOOD, outline=WOOD_D)
d.polygon([(104, 81), (116, 83), (116, 92), (104, 90)], fill=WOOD_D)
d.polygon([(104, 93), (116, 95), (116, 103), (104, 101)], fill=WOOD_D)
d.polygon([(104, 104), (116, 106), (116, 113), (104, 110)], fill=WOOD_D)
for kx in (105, 110):
    d.ellipse((kx, 85, kx + 4, 90), fill=DG, outline=K)
    d.arc((kx + 1, 83, kx + 3, 87), 180, 360, fill=K)
d.rectangle((105, 96, 109, 101), fill=BLUE, outline=K)
d.rectangle((110, 97, 114, 102), fill=PURP, outline=K)
d.rectangle((105, 105, 109, 109), fill=YEL, outline=WOOD)
d.rectangle((110, 106, 114, 110), fill=YEL, outline=WOOD)
# plant in a white pot
d.polygon([(118, 104), (127, 104), (126, 116), (119, 116)], fill=W, outline=LG)
for (x0, y0, x1, y1) in [(122, 104, 116, 90), (122, 104, 122, 86), (122, 104, 128, 91), (122, 104, 118, 96), (122, 104, 127, 97)]:
    d.line([(x0, y0), (x1, y1)], fill=GREEN, width=2)
for (x, y) in [(116, 90), (122, 86), (128, 91)]:
    d.point((x, y), fill=GREEN_L)
d.line([(120, 100), (124, 99)], fill=GREEN_D)

# the mat the partner stands on (partner's feet at 116, at x ~45: MiniGame.drawBag)
d.polygon([(27, 111), (66, 111), (69, 124), (24, 124)], fill=RED_L, outline=RED)
d.line([(31, 112), (29, 123)], fill=W)
d.line([(62, 112), (64, 123)], fill=W)
d.line([(25, 124), (68, 124)], fill=RED_D)

big = im.resize((280, 280), Image.NEAREST)
d_out = os.path.join(APP, "resources", "drawables", "gym")
os.makedirs(d_out, exist_ok=True)
big.save(os.path.join(d_out, "gym.png"))
cols = sorted(set(big.get_flattened_data()))
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(APP, "resources", "drawables", "gym.xml"), "w").write(
    '<drawables>\n    <bitmap scope="application" id="gym" filename="gym/gym.png"><palette disableTransparency="true">%s</palette></bitmap>\n</drawables>\n' % pal)
print("gym room", big.size, len(cols), "colours")
if len(sys.argv) > 2:
    prev = im.resize((G * 4, G * 4), Image.NEAREST)
    mask = Image.new("L", prev.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, prev.width - 1, prev.height - 1), fill=255)
    out = Image.new("RGB", prev.size, (40, 40, 40))
    out.paste(prev, (0, 0), mask)
    out.save(sys.argv[2])
