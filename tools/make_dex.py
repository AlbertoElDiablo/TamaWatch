"""Kanto species table for TamaWatch, from TamaPoke's dex.h (MIT).

usage: python3 make_dex.py <TamaPoke repo> <TamaWatch>

Writes resources/jsondata/dex.json: one row per dex number 1-151,
  [evolvesTo, evolveLevel, rarity, hp, atk, def, spe, spa, spd, biome, type1, type2, accent]
rarity: 0 = only by evolution, 1 common, 2 rare, 3 legendary.
type2 = -1 when single-typed. Types follow TamaPoke's PkType order.

Kanto only: an evolution into a later generation (Golbat -> Crobat and five
others) is cut, so those six are final forms here, as in the original games.
"""
import json, os, re, sys

SRC, APP = sys.argv[1], sys.argv[2]
text = open(os.path.join(SRC, "dex.h"), encoding="utf-8").read()
types = re.search(r"enum PkType : uint8_t \{\s*(.*?)\s*T_NONE", text, re.S).group(1)
TYPE = {name.strip(): i for i, name in enumerate(t for t in types.split(",") if t.strip())}
RARITY = {"R_EVO": 0, "R_COMUN": 1, "R_RARO": 2, "R_LEGENDARIO": 3}

rows = {}
for m in re.finditer(r'\{\s*"([^"]+)",\s*([^}]*)\},\s*//\s*(\d+)', text):
    n = int(m.group(3))
    if not 1 <= n <= 151:
        continue
    f = [x.strip() for x in m.group(2).split(",")]
    evo, evl = int(f[0]), int(f[1])
    if evo > 151:
        evo, evl = 0, 0
    t2 = f[12] if len(f) > 12 else "T_NONE"
    acc = int(f[3], 16)   # RGB565 accent, as 0xRRGGBB
    rgb = ((acc >> 11) & 31) * 255 // 31 << 16 | ((acc >> 5) & 63) * 255 // 63 << 8 | (acc & 31) * 255 // 31
    rows[n] = [evo, evl, RARITY[f[2]], int(f[4]), int(f[5]), int(f[6]), int(f[7]), int(f[8]), int(f[9]),
               int(f[10]), TYPE[f[11]], -1 if t2 == "T_NONE" else TYPE[t2], rgb]
assert sorted(rows) == list(range(1, 152)), "missing rows"

out = os.path.join(APP, "resources", "jsondata")
json.dump([rows[n] for n in range(1, 152)], open(os.path.join(out, "dex.json"), "w"), separators=(",", ":"))
xml = os.path.join(out, "jsondata.xml")
s = open(xml).read()
if 'id="dex"' not in s:
    s = s.replace("</resources>", '    <jsonData id="dex" filename="dex.json"/>\n</resources>')
    open(xml, "w").write(s)
tiers = [sum(1 for r in rows.values() if r[2] == t) for t in range(4)]
print("dex rows:", len(rows), "| evo-only/common/rare/legendary:", tiers)
