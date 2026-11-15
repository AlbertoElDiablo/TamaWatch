"""The launcher icon (also what the widget glance shows on its left): a Poke Ball, 40x40,
drawn here pixel by pixel in the watch's 64 colours.

usage: python3 make_icon.py <TamaWatch>
"""
import os, sys
from PIL import Image

APP = sys.argv[1]
N, C, R = 40, 19.5, 18.5
RED, WHITE, INK, GREY = (255, 0, 0, 255), (255, 255, 255, 255), (0, 0, 0, 255), (170, 170, 170, 255)
im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
for y in range(N):
    for x in range(N):
        dx, dy = x - C, y - C
        d = (dx * dx + dy * dy) ** 0.5
        if d > R:
            continue
        if d > R - 2:
            col = INK                                  # outline
        elif abs(dy) <= 2:
            col = INK                                  # the band
        else:
            col = RED if dy < 0 else WHITE
            if dy < 0 and dx < -4 and dy < -8 and (dx + 9) ** 2 + (dy + 11) ** 2 < 6:
                col = WHITE                            # shine
            if dy > 0 and dx > 6 and dy > 6:
                col = GREY                             # shade
        if d <= 6.5:
            col = INK                                  # button ring
        if d <= 4.5:
            col = WHITE                                # button
        im.putpixel((x, y), col)
im.save(os.path.join(APP, "resources", "drawables", "launcher_icon.png"))
print("launcher icon: Poke Ball 40x40")
