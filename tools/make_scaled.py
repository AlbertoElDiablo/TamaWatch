"""Everything TamaWatch needs to look the same on other watches as on the fenix 6X.

The app is laid out for the fenix 6X (280 x 280); source/Sdc.mc scales that layout to any screen.
For the text to look the same too, every watch but the fenix 6X gets the fenix 6X's own fonts
as custom fonts: Roboto Condensed Bold (Apache 2.0, it ships with the Connect IQ SDK), sized to
match the fenix 6X's text widths and drawn at each screen's scale, with the same line height and
baseline. Screen sizes that include watches older than Connect IQ 4 (which can't scale bitmaps
when drawing) also get every picture resized ahead of time, pixel for pixel (nearest neighbour,
so the pixel art stays crisp).

Writes, per screen size (resources-round-240x240 etc., picked up by the compiler automatically):
  fonts/   f0..f5 .fnt + .png (XTINY, TINY, SMALL, MEDIUM, LARGE, NUMBER_MEDIUM) and fonts.xml
  drawables/ the resized pictures and their xml (same ids), when pre-resized
  strings/ ScaleInfo: "1" when the pictures are pre-resized
The 280 x 280 fonts go in resources/fonts (used by other 280-pixel watches); the fenix 6X itself
keeps its system fonts (resources-fenix6xpro/strings: NativeUi = 1).

usage: python3 make_scaled.py <TamaWatch>
"""
import glob, json, os, re, shutil, sys
from PIL import Image, ImageDraw, ImageFont

APP = sys.argv[1]
RES = os.path.join(APP, "resources")
TTF = os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Fonts/RobotoCondensed-Bold.ttf")
# point sizes that give the fenix 6X's text widths, and its line height and ascent (measured there)
FONTS = [(15.3, 19, 15), (25.3, 31, 25), (28.2, 34, 27), (32.8, 40, 32), (35.7, 43, 34), (56.4, 79, 58)]
# the fenix-style (MIP) screens keep the watch's own fonts: the same Roboto Condensed Bold, hand-tuned
# for them (ours, drawn without anti-aliasing, came out thin and uneven on a fenix 6 Pro)
SYS_FONTS = {"round-218x218", "round-240x240", "round-260x260"}
FAMILIES = {   # screen size -> (width, height, pre-resize the pictures)
    "round-218x218": (218, 218, True), "round-240x240": (240, 240, True), "round-260x260": (260, 260, True),
    "round-360x360": (360, 360, False), "round-390x390": (390, 390, True), "round-416x416": (416, 416, False),
    "round-454x454": (454, 454, False), "round-466x466": (466, 466, False),
    "rectangle-240x240": (240, 240, True), "rectangle-320x360": (320, 360, False),
    "rectangle-448x486": (448, 486, False),
}


def charset():
    chars = set(chr(c) for c in range(32, 127))
    texts = []
    for f in glob.glob(os.path.join(RES, "jsondata", "*.json")):
        if re.search(r"d\d{3}\.json$", f):
            continue
        texts.append(open(f, encoding="utf-8").read())
    for f in glob.glob(os.path.join(APP, "source", "*.mc")):
        texts += re.findall(r'"((?:[^"\\]|\\.)*)"', open(f, encoding="utf-8").read())
    for t in texts:
        chars |= set(c for c in t if ord(c) >= 32 and c not in "\n\r\t")
    return sorted(chars)


def make_font(out, idx, k, chars):
    pt, lh, asc = FONTS[idx]
    font = ImageFont.truetype(TTF, pt * k)
    ascent_pil = font.getmetrics()[0]
    line = max(1, round(lh * k))
    base = round((asc + 1) * k)
    glyphs = []
    for ch in chars:
        if idx == 5 and ch not in "0123456789 -+":
            continue
        bbox = font.getbbox(ch)
        w, h = max(0, bbox[2] - bbox[0]), max(0, bbox[3] - bbox[1])
        img = Image.new("L", (w + 2, h + 2), 0)
        if w > 0 and h > 0:
            dr = ImageDraw.Draw(img)
            if k < 1.2:
                dr.fontmode = "1"   # the 8-colour MIP screens can't blend edges: crisp pixels, like the fenix's own
            dr.text((1 - bbox[0], 1 - bbox[1]), ch, font=font, fill=255)
        glyphs.append((ch, img, bbox, round(font.getlength(ch))))
    # shelf-pack into one page
    width = 256 if k < 1.2 else 512
    x = y = rowh = 0
    pos = []
    for ch, img, bbox, adv in glyphs:
        if x + img.width > width:
            x, y, rowh = 0, y + rowh, 0
        pos.append((x, y))
        x += img.width
        rowh = max(rowh, img.height)
    height = y + rowh
    page = Image.new("RGBA", (width, max(1, height)), (255, 255, 255, 0))
    lines = ["info face=\"Roboto Condensed Bold\" size=%d bold=1 italic=0 charset=\"\" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0" % round(pt * k),
             "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0" % (line, base, width, max(1, height)),
             "page id=0 file=\"f%d.png\"" % idx,
             "chars count=%d" % len(glyphs)]
    for (ch, img, bbox, adv), (px, py) in zip(glyphs, pos):
        white = Image.new("RGBA", img.size, (255, 255, 255, 0))
        white.putalpha(img)
        page.paste(white, (px, py))
        xo = bbox[0] - 1
        yo = base - ascent_pil + bbox[1] - 1
        lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
                     % (ord(ch), px, py, img.width, img.height, xo, yo, adv))
    page.save(os.path.join(out, "f%d.png" % idx))
    open(os.path.join(out, "f%d.fnt" % idx), "w", encoding="utf-8").write("\n".join(lines) + "\n")


def fonts_for(folder, k, chars):
    out = os.path.join(folder, "fonts")
    os.makedirs(out, exist_ok=True)
    for i in range(len(FONTS)):
        make_font(out, i, k, chars)
    aa = "true" if k >= 1.2 else "false"
    xml = "<fonts>\n" + "".join('    <font id="f%d" filename="f%d.fnt" antialias="%s"/>\n' % (i, i, aa) for i in range(len(FONTS))) + "</fonts>\n"
    open(os.path.join(out, "fonts.xml"), "w", encoding="utf-8").write(xml)


# Pictures drawn in cells (a strip or grid of icons, badges, thumbnails, trainers): each cell is
# shrunk on its own to exactly where the app expects it (Sdc.R), and fine pixel art (1 px outlines:
# the egg, the thumbnails) is shrunk by dropping the columns and rows that repeat their neighbour, or
# differ least from it, never an outline. Plain nearest-neighbour dropped the egg's side outlines.
CELLS = {"thumbs/thumbs.png": (38, 38), "thumbs/thumbs_sil.png": (38, 38), "dock/icons.png": (32, 32),
         "badges/badges.png": (48, 48), "kids/kids.png": (48, 48), "egg/egg.png": (96, 96),
         "gym/gym.png": None}


def R(v, k):
    return int(v * k + 0.5)


def keep(lines, n):
    """Which of these lines (tuples of pixels) to keep so n remain: drop the least different."""
    m = len(lines)
    if n >= m:
        return list(range(m))
    def diff(a, b):
        return sum(1 for p, q in zip(a, b) if p != q and (p[3] > 0 or q[3] > 0))
    cost = []
    for j in range(m):
        c = []
        if j > 0: c.append(diff(lines[j], lines[j - 1]))
        if j < m - 1: c.append(diff(lines[j], lines[j + 1]))
        cost.append(min(c) if c else 0)
    order = sorted(range(m), key=lambda j: (cost[j], abs(j - m / 2)))
    drop = set()
    for j in order:
        if len(drop) == m - n: break
        if j - 1 in drop or j + 1 in drop: continue
        drop.add(j)
    for j in order:                     # not enough without neighbours: take the next cheapest
        if len(drop) == m - n: break
        drop.add(j)
    return [j for j in range(m) if j not in drop]


def shrink_cells(im, k, cell):
    im = im.convert("RGBA")
    W, H = im.size
    cw, ch = cell if cell else (W, H)
    out = Image.new("RGBA", (R(W, k), R(H, k)), (0, 0, 0, 0))
    px = im.load()
    for y0 in range(0, H, ch):
        for x0 in range(0, W, cw):
            x1, y1 = min(x0 + cw, W), min(y0 + ch, H)
            tw, th = R(x1, k) - R(x0, k), R(y1, k) - R(y0, k)
            cols = keep([tuple(px[x, y] for y in range(y0, y1)) for x in range(x0, x1)], tw)
            rows = keep([tuple(px[x, y] for x in range(x0, x1)) for y in range(y0, y1)], th)
            cell_im = Image.new("RGBA", (tw, th))
            cp = cell_im.load()
            for ty, sy in enumerate(rows):
                for tx, sx in enumerate(cols):
                    cp[tx, ty] = px[x0 + sx, y0 + sy]
            out.paste(cell_im, (R(x0, k), R(y0, k)))
    return out


def pictures_for(folder, k):
    src = os.path.join(RES, "drawables")
    out = os.path.join(folder, "drawables")
    os.makedirs(out, exist_ok=True)
    for x in glob.glob(os.path.join(src, "*.xml")):
        s = open(x).read()
        s = re.sub(r'\s*<bitmap id="LauncherIcon"[^>]*/>', "", s)   # the launcher icon is the system's size
        if k > 1 and os.path.basename(x) == "thumbs.xml":
            # enlarged, the thumbnail atlas wouldn't fit in these watches' memory: they draw the
            # 280-pixel one, each thumbnail centred in its enlarged cell (strings: ThumbNative)
            continue
        open(os.path.join(out, os.path.basename(x)), "w").write(s)
        for fn in re.findall(r'filename="([^"]+)"', s):
            im = Image.open(os.path.join(src, fn))
            w, h = max(1, round(im.width * k)), max(1, round(im.height * k))
            dst = os.path.join(out, fn)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if k < 1 and fn in CELLS:
                shrink_cells(im, k, CELLS[fn]).save(dst)
            else:
                im.resize((w, h), Image.NEAREST).save(dst)


def strings_for(folder, scaled, native=False, thumbs_native=False, sys_fonts=None):
    out = os.path.join(folder, "strings")
    os.makedirs(out, exist_ok=True)
    s = "<strings>\n"
    if sys_fonts is not None:
        s += '    <string id="SysFonts">%s</string>\n' % ("1" if sys_fonts else "0")
    if scaled is not None:
        s += '    <string id="ScaleInfo">%s</string>\n' % ("1" if scaled else "0")
    if thumbs_native:
        s += '    <string id="ThumbNative">1</string>\n'
    if native:
        s += '    <string id="NativeUi">1</string>\n'
    open(os.path.join(out, "scale.xml"), "w").write(s + "</strings>\n")


chars = charset()
print(len(chars), "characters")
# the base: 280 x 280 fonts, pictures as they are, the fenix 6X's own fonts only on the fenix 6X
fonts_for(RES, 1.0, chars)
out = os.path.join(RES, "strings")
open(os.path.join(out, "scale.xml"), "w").write('<strings>\n    <string id="ScaleInfo">0</string>\n    <string id="NativeUi">0</string>\n    <string id="ThumbNative">0</string>\n    <string id="SysFonts">1</string>\n</strings>\n')
d6 = os.path.join(APP, "resources-fenix6xpro")
shutil.rmtree(d6, ignore_errors=True)
strings_for(d6, None, native=True)
for fam, (w, h, pre) in FAMILIES.items():
    folder = os.path.join(APP, "resources-" + fam)
    shutil.rmtree(folder, ignore_errors=True)
    k = min(w, h) / 280
    if fam not in SYS_FONTS:
        fonts_for(folder, k, chars)
    if pre:
        pictures_for(folder, k)
    strings_for(folder, pre, thumbs_native=pre and k > 1, sys_fonts=fam in SYS_FONTS)
    print(fam, "k=%.3f" % k, "pictures" if pre else "")


# Every resource is the app's alone: unscoped, the 32 KB glance and background processes would
# carry the whole resource table too (they use none of it), and that no longer fits.
def scope_all():
    for x in glob.glob(os.path.join(APP, "resources*", "**", "*.xml"), recursive=True):
        s = open(x, encoding="utf-8").read()
        t = re.sub(r'<(bitmap|jsonData|font|string)(?![^>]*\bscope=)(?![^>]*id="(?:LauncherIcon|AppName)")\b',
                   r'<\1 scope="application"', s)
        if t != s:
            open(x, "w", encoding="utf-8").write(t)


scope_all()
print("resources scoped to the app")
