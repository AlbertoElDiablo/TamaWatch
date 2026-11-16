"""Battle data for TamaWatch, from TamaPoke's moves.h and dex.h (MIT).

usage: python3 make_moves.py <TamaPoke repo> <TamaWatch>

Writes (run make_sprites.py first: the learnsets go into its per-species JSON):
  resources/jsondata/moves.json  one row per move id:
      [name, type, cat, power, acc, effect, param, statMask, stages, target, ailment, ailChance]
  resources/jsondata/types.json  {"fx": 18x18 chart in tenths, "names": [...], "colors": [...]}
  resources/jsondata/dNNN.json   gains "L": [move, level, move, level, ...] (level 0 = TM)
"""
import json, os, re, sys

SRC, APP = sys.argv[1], sys.argv[2]
moves_h = open(os.path.join(SRC, "moves.h"), encoding="utf-8").read()
dex_h = open(os.path.join(SRC, "dex.h"), encoding="utf-8").read()
types_h = open(os.path.join(SRC, "types.h"), encoding="utf-8").read()
out = os.path.join(APP, "resources", "jsondata")

def enum_values(text, names):
    """Map enum member names to ints for one or more `enum : uint8_t { ... }` blocks."""
    vals = {}
    for block in re.findall(r"enum[^{]*\{([^}]*)\}", text):
        n = 0
        for part in re.sub(r"//[^\n]*", "", block).split(","):
            part = part.strip()
            if not part:
                continue
            if "=" in part:
                k, v = [x.strip() for x in part.split("=")]
                n = int(v, 0)
            else:
                k = part
            vals[k] = n
            n += 1
    return vals

E = enum_values(moves_h, None)
E.update(enum_values(dex_h, None))
E["T_NONE"] = -1

# --- moves ---
rows = []
for m in re.finditer(r'\{\s*"([^"]+)",\s*([^}]*)\},\s*//\s*(\d+)', moves_h[moves_h.index("MOVE_TBL"):moves_h.index("LEARN_TBL")]):
    f = [x.strip() for x in m.group(2).split(",")]
    vals = [eval(x, {}, E) for x in f]   # handles "ST_ATK | ST_SPE" and negative stages
    rows.append([m.group(1)] + vals)
assert len(rows) == int(re.search(r"#define MOVE_COUNT (\d+)", moves_h).group(1)), len(rows)
json.dump(rows, open(os.path.join(out, "moves.json"), "w"), separators=(",", ":"))

# --- type chart, names, chip colours ---
fx_block = dex_h[dex_h.index("TYPE_FX["):]
fx_block = fx_block[fx_block.index("{") + 1:fx_block.index("};")]   # inside the outer braces
fx = [[int(v) for v in row.split(",") if v.strip()] for row in re.findall(r"\{([^}]*)\}", fx_block)]
assert len(fx) == 18 and all(len(r) == 18 for r in fx)
names = re.findall(r'"([A-Z]+)"', types_h[types_h.index("typeName"):types_h.index("typeName") + 600])[:18]
col_block = types_h[types_h.index("TYPE_COL["):]
cols565 = [int(c, 16) for c in re.findall(r"0x([0-9A-Fa-f]{4})", col_block)[:18]]
def rgb(c):
    return ((c >> 11) & 31) * 255 // 31 << 16 | ((c >> 5) & 63) * 255 // 63 << 8 | (c & 31) * 255 // 31
json.dump({"fx": fx, "names": names, "colors": [rgb(c) for c in cols565]},
          open(os.path.join(out, "types.json"), "w"), separators=(",", ":"))

# --- learnsets into each species' JSON ---
learn = [(int(a), int(b)) for a, b in re.findall(r"\{\s*(\d+),\s*(\d+)\s*\}", moves_h[moves_h.index("LearnEntry LEARN_TBL[") :moves_h.index("uint16_t LEARN_OFS[")])]
ofs = [int(x) for x in re.findall(r"\d+", moves_h[moves_h.index("uint16_t LEARN_OFS[") :].split("{", 1)[1].split("}", 1)[0])]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import region as R
for k in range(1, R.COUNT + 1):
    n = R.nat(k)
    p = os.path.join(out, "d%03d.json" % k)
    d = json.load(open(p))
    flat = []
    for mv, lv in learn[ofs[n]:ofs[n + 1]]:
        flat += [mv, lv]
    d["L"] = flat
    json.dump(d, open(p, "w"), separators=(",", ":"))

xml = os.path.join(out, "jsondata.xml")
s = open(xml).read()
for rid in ("moves", "types"):
    if 'id="%s"' % rid not in s:
        s = s.replace("</resources>", '    <jsonData id="%s" filename="%s.json"/>\n</resources>' % (rid, rid))
open(xml, "w").write(s)
print("moves:", len(rows), "| learnsets:", R.COUNT, "species")
