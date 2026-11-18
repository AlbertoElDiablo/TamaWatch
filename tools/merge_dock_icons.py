"""The dock's icons (tools/make_dock_icons.py: resources/drawables/dock/icons.png, 8 icons of 32 x 32)
moved under the badges (tools/make_badges.py: badges/badges.png, 8 of 48 x 48) into one picture,
384 x 80, the icons in rows 48-79: Connect IQ allows an app 254 pictures. Run after either of
those two (it removes the dock's own picture). PetView.drawIcon draws from rows 48-79.

usage: python3 merge_dock_icons.py <TamaWatch>
"""
import os, sys
from PIL import Image

APP = sys.argv[1]
D = os.path.join(APP, "resources", "drawables")
badges = Image.open(os.path.join(D, "badges", "badges.png")).convert("RGBA")
icons_png = os.path.join(D, "dock", "icons.png")
if os.path.exists(icons_png):
    icons = Image.open(icons_png).convert("RGBA")
else:                                   # already merged: the icons are rows 48-79
    icons = badges.crop((0, 48, 256, 80))
both = Image.new("RGBA", (384, 80), (0, 0, 0, 0))
both.paste(badges.crop((0, 0, 384, 48)), (0, 0))
both.paste(icons, (0, 48))
both.save(os.path.join(D, "badges", "badges.png"))
cols = sorted({p[:3] for p in both.get_flattened_data() if p[3]})
pal = "".join("<color>%02X%02X%02X</color>" % c for c in cols)
open(os.path.join(D, "badges.xml"), "w").write(
    '<drawables>\n    <bitmap scope="application" id="badges" filename="badges/badges.png"><palette disableTransparency="false">%s</palette></bitmap>\n</drawables>\n' % pal)
for f in (icons_png, os.path.join(D, "dock.xml")):
    if os.path.exists(f):
        os.remove(f)
print("badges + dock icons:", both.size, len(cols), "colours")
