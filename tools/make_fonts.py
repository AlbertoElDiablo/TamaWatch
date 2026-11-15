"""TamaPoke's UI font (Fredoka, SIL Open Font License 1.1) as Connect IQ bitmap fonts.

usage: python3 make_fonts.py <TamaPoke repo> <TamaWatch>

Rasterises ASCII 32..126 of tools/fonts/Fredoka.ttf with TamaPoke's own weight axes (600, 100)
at four sizes, into BMFont text files + PNG atlases (white glyphs, antialiased) under
resources/fonts/, with fonts.xml. Ids: ui_tiny, ui_small, ui_mid, ui_big.
"""
import os, shutil, sys
from PIL import Image, ImageDraw, ImageFont

SRC, APP = sys.argv[1], sys.argv[2]
TTF = os.path.join(SRC, "tools", "fonts", "Fredoka.ttf")
SIZES = {"ui_tiny": 14, "ui_small": 17, "ui_mid": 20, "ui_big": 25}
out = os.path.join(APP, "resources", "fonts")
shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)

xml = []
for rid, px in SIZES.items():
    font = ImageFont.truetype(TTF, px)
    font.set_variation_by_axes([600, 100])
    ascent, descent = font.getmetrics()
    glyphs = []
    for cp in range(32, 127):
        ch = chr(cp)
        adv = round(font.getlength(ch))
        bb = font.getbbox(ch, anchor="ls")
        w, h = bb[2] - bb[0], bb[3] - bb[1]
        img = None
        if cp != 32 and w > 0 and h > 0:
            img = Image.new("L", (w, h), 0)
            ImageDraw.Draw(img).text((-bb[0], -bb[1]), ch, font=font, fill=255, anchor="ls")
        glyphs.append((cp, img, bb, adv))
    # pack into rows of an atlas 256 wide
    W = 256
    x = y = rowh = 0
    places = []
    for cp, img, bb, adv in glyphs:
        gw = img.width if img else 0
        gh = img.height if img else 0
        if x + gw + 1 > W:
            x, y, rowh = 0, y + rowh + 1, 0
        places.append((x, y))
        x += gw + 1
        rowh = max(rowh, gh)
    H = y + rowh + 1
    atlas = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    lines = []
    for (cp, img, bb, adv), (gx, gy) in zip(glyphs, places):
        if img:
            atlas.paste(Image.merge("RGBA", (img.point(lambda v: 255),) * 3 + (img,)), (gx, gy))
            lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
                         % (cp, gx, gy, img.width, img.height, bb[0], ascent + bb[1], adv))
        else:
            lines.append("char id=%d x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15" % (cp, adv))
    atlas.save(os.path.join(out, rid + ".png"))
    with open(os.path.join(out, rid + ".fnt"), "w") as f:
        f.write('info face="Fredoka" size=%d bold=1 italic=0 charset="" unicode=0 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1\n' % px)
        f.write("common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0\n" % (ascent + descent, ascent, W, H))
        f.write('page id=0 file="%s.png"\n' % rid)
        f.write("chars count=%d\n" % len(lines))
        f.write("\n".join(lines) + "\n")
    xml.append('    <font id="%s" filename="fonts/%s.fnt" antialias="true"/>' % (rid, rid))

open(os.path.join(APP, "resources", "fonts.xml"), "w").write("<fonts>\n" + "\n".join(xml) + "\n</fonts>\n")
print("fonts:", SIZES)
