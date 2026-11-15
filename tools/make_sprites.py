"""Convert SpriteCollab Kanto sprites into TamaWatch resources.

usage: python3 -P make_sprites.py <SpriteCollab-master> <TamaWatch>

For each Pokemon #1-151 and each anim (Idle, Sleep, Eat|Charge, Hop, Hurt):
  - take the front-facing row (row 0 = facing down/camera)
  - crop every frame to the union of visible pixels (keeps motion intact)
  - scale 2x nearest-neighbour (1x for big Pokemon)
  - write one horizontal strip PNG + metadata in a per-species JSON resource
Also generates source/SpriteIndex.mc (resource lookup) and CREDITS.md.
"""
import json, os, re, shutil, sys, xml.etree.ElementTree as ET
from PIL import Image

SRC, APP = sys.argv[1], sys.argv[2]
ANIMS = [("idle", ["Idle"]), ("sleep", ["Sleep"]), ("eat", ["Eat", "Charge"]),
         ("hop", ["Hop"]), ("hurt", ["Hurt"])]
MAX_IDLE = 100        # 2x only if the idle pose stays within this many px
STRIP_BUDGET = 30000  # max pixels per strip (runtime memory), frames get thinned above it

draw_dir = os.path.join(APP, "resources", "drawables", "sprites")
json_dir = os.path.join(APP, "resources", "jsondata")
shutil.rmtree(draw_dir, ignore_errors=True)
os.makedirs(draw_dir)
os.makedirs(json_dir, exist_ok=True)

tracker = json.load(open(os.path.join(SRC, "tracker.json")))
who = {}
for line in open(os.path.join(SRC, "credit_names.txt"), encoding="utf-8").read().split("\n")[1:]:
    p = line.split("\t")
    if len(p) >= 2 and p[0]:
        who[p[1]] = p[0]

def anim_table(n):
    root = ET.parse(os.path.join(SRC, "sprite", "%04d" % n, "AnimData.xml")).getroot()
    return {a.findtext("Name"): a for a in root.iter("Anim")}

def resolve(table, names):
    for nm in names:
        a = table.get(nm)
        if a is None:
            continue
        if a.find("CopyOf") is not None:
            nm = a.findtext("CopyOf")
            a = table[nm]
        return nm, a
    raise KeyError(names)

def frames_of(n, nm, a, shiny=False):
    fw, fh = int(a.findtext("FrameWidth")), int(a.findtext("FrameHeight"))
    durs = [int(x.text) for x in a.findall("Durations/Duration")]
    base = os.path.join(SRC, "sprite", "%04d" % n, *(["0000", "0001"] if shiny else []))
    sheet = Image.open(os.path.join(base, nm + "-Anim.png")).convert("RGBA")
    frames = [sheet.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(len(durs))]
    return fw, fh, frames, durs

LEVELS = [0, 85, 170, 255]   # the watch's 64-colour palette is every combination of these

def snap(v):
    return min(LEVELS, key=lambda x: abs(x - v))

def to_device_colours(im):
    """Snap to device colours, max 15 + transparent, so the compiler packs 4 bits/pixel."""
    alpha = im.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
    rgb = im.convert("RGB")
    if len({c for c, a in zip(rgb.getdata(), alpha.getdata()) if a}) > 15:
        rgb = rgb.quantize(15).convert("RGB")
    rgb = rgb.point(snap)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return Image.composite(out, Image.new("RGBA", im.size, (0, 0, 0, 0)), alpha)

def union_bbox(frames):
    boxes = [f.getbbox() for f in frames if f.getbbox()]
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))

drawables, jsons, index, credits = [], [], [], {}
shiny_sheets = []
missing_shiny = []
total_bytes, biggest = 0, (0, "")
for n in range(1, 152):
    table = anim_table(n)
    nm, a = resolve(table, ["Idle"])
    fw, fh, fr, _ = frames_of(n, nm, a)
    x0, y0, x1, y1 = union_bbox(fr)
    scale = 2 if max(x1 - x0, y1 - y0) * 2 <= MAX_IDLE else 1
    meta = {"s": scale, "foot": (y1 - fh // 2) * scale}  # idle feet below anchor
    rows = []
    shiny_rows = []
    for key, names in ANIMS:
        nm, a = resolve(table, names)
        fw, fh, fr, durs = frames_of(n, nm, a)
        x0, y0, x1, y1 = union_bbox(fr)
        w, h = (x1 - x0) * scale, (y1 - y0) * scale
        # thin frames until the strip fits the memory budget
        try:
            _, _, sfr, _ = frames_of(n, nm, a, shiny=True)   # same layout (AnimData is identical)
        except FileNotFoundError:
            sfr = list(fr)        # this anim has no shiny file: use the normal frames
            missing_shiny.append("%d:%s" % (n, nm))
        while len(fr) > 2 and w * h * len(fr) > STRIP_BUDGET:
            durs = [durs[i] + durs[i + 1] if i + 1 < len(durs) else durs[i] for i in range(0, len(durs), 2)]
            fr = fr[::2]
            sfr = sfr[::2]
        cells = [f.crop((x0, y0, x1, y1)).resize((w, h), Image.NEAREST) for f in fr]
        scells = [f.crop((x0, y0, x1, y1)).resize((w, h), Image.NEAREST) for f in sfr]
        shiny_rows.append(scells)
        meta[key] = {"w": w, "h": h,
                     "x": (x0 - fw // 2) * scale, "y": (y0 - fh // 2) * scale,
                     "d": [max(100, round(d * 1000 / 60)) for d in durs]}
        rows.append((key, cells))
    # One sheet per Pokemon (Connect IQ allows <=254 drawables). Each anim is a block of
    # frames wrapped into a grid of "c" columns starting at row offset "r"; pick the sheet
    # width that wastes the least space.
    best = None
    for W in sorted({len(c) * c[0].width for _, c in rows} | {c[0].width * k for _, c in rows for k in range(1, len(c) + 1)}):
        if W < max(c[0].width for _, c in rows):
            continue
        H = 0
        for _, c in rows:
            cols = W // c[0].width
            H += -(-len(c) // cols) * c[0].height
        if best is None or W * H < best[0]:
            best = (W * H, W, H)
    _, W, H = best
    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ssheet = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    yy = 0
    for (key, c), sc in zip(rows, shiny_rows):
        fw_, fh_ = c[0].size
        cols = W // fw_
        meta[key]["r"] = yy
        meta[key]["c"] = cols
        for i, cell in enumerate(c):
            sheet.paste(cell, ((i % cols) * fw_, yy + (i // cols) * fh_))
            if i < len(sc):
                ssheet.paste(sc[i], ((i % cols) * fw_, yy + (i // cols) * fh_))
        yy += -(-len(c) // cols) * fh_
    sheet = to_device_colours(sheet)
    shiny_sheets.append((n, to_device_colours(ssheet), meta))
    rid = "p%03d" % n
    path = os.path.join(draw_dir, rid + ".png")
    sheet.save(path, optimize=True)
    total_bytes += os.path.getsize(path)
    if sheet.width * sheet.height > biggest[0]:
        biggest = (sheet.width * sheet.height, rid, sheet.size)
    pal = "".join("<color>%02X%02X%02X</color>" % c for c in sorted({c[:3] for c in sheet.getdata() if c[3]}))
    drawables.append('    <bitmap id="%s" filename="sprites/%s.png"><palette disableTransparency="false">%s</palette></bitmap>' % (rid, rid, pal))
    index.append(rid)
    jid = "d%03d" % n
    jsons.append('    <jsonData id="%s" filename="%s.json"/>' % (jid, jid))
    cred = open(os.path.join(SRC, "sprite", "%04d" % n, "credits.txt")).read().split("\n")
    credits[n] = sorted({who.get(l.split("\t")[1], l.split("\t")[1]) for l in cred if l.count("\t") >= 2})

# Shiny sheets: same layout as the normal ones, packed several to an "atlas" bitmap
# (stacked vertically) because Connect IQ allows at most 254 drawables. "sh" = [atlas, y].
# Group sheets whose colours overlap so each atlas stays within 15 colours (the compiler then
# stores it at 4 bits per pixel), biggest first, up to ATLAS_PX pixels per atlas.
ATLAS_PX = 300000
groups = []          # each: [px, colours, items]
for item in sorted(shiny_sheets, key=lambda t: -t[1].width * t[1].height):
    px = item[1].width * item[1].height
    cols = {c[:3] for c in item[1].getdata() if c[3]}
    best = None
    for g in groups:
        u = g[1] | cols
        if len(u) <= 15 and g[0] + px <= ATLAS_PX and (best is None or len(u) < len(best[1] | cols)):
            best = g
    if best is None:
        best = [0, set(), []]
        groups.append(best)
    best[0] += px
    best[1] |= cols
    best[2].append(item)
groups = [g[2] for g in groups]
budget = ATLAS_PX
shiny_dir = os.path.join(APP, "resources", "drawables", "shiny")
shutil.rmtree(shiny_dir, ignore_errors=True)
os.makedirs(shiny_dir)
shiny_xml, shiny_ids = [], []
for gi, g in enumerate(groups):
    atlas = Image.new("RGBA", (max(sh.width for _, sh, _ in g), sum(sh.height for _, sh, _ in g)), (0, 0, 0, 0))
    y = 0
    for n, sh, meta in g:
        atlas.paste(sh, (0, y))
        meta["sh"] = [gi, y]
        y += sh.height
    rid = "s%02d" % gi
    atlas.save(os.path.join(shiny_dir, rid + ".png"), optimize=True)
    pal = "".join("<color>%02X%02X%02X</color>" % c for c in sorted({c[:3] for c in atlas.getdata() if c[3]}))
    shiny_xml.append('    <bitmap id="%s" filename="shiny/%s.png"><palette disableTransparency="false">%s</palette></bitmap>' % (rid, rid, pal))
    shiny_ids.append(rid)
with open(os.path.join(APP, "resources", "drawables", "shiny.xml"), "w") as f:
    f.write("<drawables>\n" + "\n".join(shiny_xml) + "\n</drawables>\n")

# per-species JSON, keeping the learnset ("L") that make_moves.py adds
for n, sh, meta in shiny_sheets:
    p = os.path.join(json_dir, "d%03d.json" % n)
    if os.path.exists(p):
        old = json.load(open(p))
        for k in ("L", "g", "gs", "ic"):     # learnset, glance thumbnails, body centre
            if k in old:
                meta[k] = old[k]
    json.dump(meta, open(p, "w"), separators=(",", ":"))

with open(os.path.join(APP, "resources", "drawables", "sprites.xml"), "w") as f:
    f.write("<drawables>\n" + "\n".join(drawables) + "\n</drawables>\n")
# jsondata.xml: our species entries, keeping every other entry (dex, moves, types, trainers)
xml_path = os.path.join(json_dir, "jsondata.xml")
others = []
if os.path.exists(xml_path):
    others = [l for l in open(xml_path).read().split("\n") if "<jsonData" in l and not re.search(r'id="d\d{3}"', l)]
with open(xml_path, "w") as f:
    f.write("<resources>\n" + "\n".join(jsons + others) + "\n</resources>\n")

# Resource lookup, built inside functions so the big arrays only exist while called.
names = [tracker["%04d" % n]["name"] for n in range(1, 152)]
with open(os.path.join(APP, "source", "SpriteIndex.mc"), "w") as f:
    f.write("// GENERATED by make_sprites.py - do not edit by hand.\n")
    f.write("import Toybox.WatchUi;\n\nmodule SpriteIndex {\n\n")
    f.write("    const ANIMS = [\"idle\", \"sleep\", \"eat\", \"hop\", \"hurt\"];\n\n")
    f.write("    // Sprite sheet for dex number n (1-151); frame layout in data(n).\n")
    f.write("    function sheet(n) {\n        var ids = [\n")
    for i in range(0, len(index), 8):
        f.write("            " + ", ".join("Rez.Drawables." + r for r in index[i:i + 8]) + ",\n")
    f.write("        ];\n        return ids[n - 1];\n    }\n\n")
    f.write("    // Shiny atlas i (several species' shiny sheets stacked; offset in data(n)[\"sh\"]).\n")
    f.write("    function shiny(i) {\n        var ids = [\n")
    for i in range(0, len(shiny_ids), 8):
        f.write("            " + ", ".join("Rez.Drawables." + r for r in shiny_ids[i:i + 8]) + ",\n")
    f.write("        ];\n        return ids[i];\n    }\n\n")
    f.write("    // The bitmap to draw a creature from and the y where its sheet starts in it.\n")
    f.write("    function art(meta, n, isShiny) {\n")
    f.write("        if (isShiny && meta[\"sh\"] != null) {\n")
    f.write("            return [WatchUi.loadResource(shiny(meta[\"sh\"][0])), meta[\"sh\"][1]];\n")
    f.write("        }\n")
    f.write("        return [WatchUi.loadResource(sheet(n)), 0];\n    }\n\n")
    f.write("    function data(n) {\n        var ids = [\n")
    for i in range(1, 152, 8):
        f.write("            " + ", ".join("Rez.JsonData.d%03d" % k for k in range(i, min(i + 8, 152))) + ",\n")
    f.write("        ];\n        return ids[n - 1];\n    }\n\n")
    f.write("    function name(n) {\n        var all = [\n")
    for i in range(0, 151, 6):
        f.write("            " + ", ".join(json.dumps(x) for x in names[i:i + 6]) + ",\n")
    f.write("        ];\n        return all[n - 1];\n    }\n}\n")

cred_path = os.path.join(APP, "CREDITS.md")
head = ""
if os.path.exists(cred_path):
    old = open(cred_path).read()
    if "## Sprites" in old:
        head = old[:old.index("## Sprites")]
with open(cred_path, "w") as f:
    f.write(head + "## Sprites\n\nPokemon sprites (normal and shiny) from the PMD SpriteCollab project "
            "(https://sprites.pmdcollab.org), licensed CC BY-NC 4.0. "
            "Front-facing frames were cropped, scaled and re-packed for the watch.\n\n")
    for n in range(1, 152):
        f.write("- #%03d %s: %s\n" % (n, names[n - 1], ", ".join(credits[n])))

print("shiny atlases:", len(groups), "budget px", budget, "| anims without a shiny file:", len(missing_shiny), missing_shiny[:8])
print("strips:", len(index), "png bytes: %.1f KB" % (total_bytes / 1024),
      "biggest strip px:", biggest)
