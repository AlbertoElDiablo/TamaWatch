"""Turns this TamaWatch copy into the build of one region: its species, sprites, moves, thumbnails,
gym teams, scenes and app id. Each build holds one region (TamaPoke's data reaches #809):

    kanto 1-151   johto 152-251   hoenn 252-386   sinnoh 387-493
    unova 494-649 kalos 650-721   alola 722-809
    (less the few species SpriteCollab has no sprites for: region.MISSING)

usage: python3 make_region.py <region> <TamaPoke repo> <SpriteCollab-master> [TamaWatch]

Inside the app the species are numbered 1..COUNT (p001.png, d001.json, the thumbnails), so the
code is the same for every region. Kanto keeps TamaWatch's app id (an update keeps your game);
every other region is its own app with its own save. Run tools/make_scaled.py afterwards, then
build (tools/build_all.sh, or tools/make_release.sh for every region).

Writes: resources/jsondata/dex.json and trainers.json, the per-species sprites and JSON (through
make_sprites, make_moves, make_glance_thumbs, make_sprite_centres, make_thumbs and
make_thumb_centres), source/Dex.mc, source/Region.mc, the biome table in source/Scenes.mc and the
id in the three manifests.
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RID, SRC, SC = sys.argv[1], sys.argv[2], sys.argv[3]
APP = sys.argv[4] if len(sys.argv) > 4 else os.path.dirname(HERE)
os.environ["TW_REGION"] = RID
sys.path.insert(0, HERE)
import region as R

# ---------- the species table (TamaPoke's dex.h) ----------
text = open(os.path.join(SRC, "dex.h"), encoding="utf-8").read()
types = re.search(r"enum PkType : uint8_t \{\s*(.*?)\s*T_NONE", text, re.S).group(1)
TYPE = {name.strip(): i for i, name in enumerate(t for t in types.split(",") if t.strip())}
RARITY = {"R_EVO": 0, "R_COMUN": 1, "R_RARO": 2, "R_LEGENDARIO": 3}
nat = {}
tbl = text[text.index("DEX_TBL["):]
tbl = tbl[:tbl.index("};")]
for m in re.finditer(r'\{\s*"([^"]+)",\s*([^}]*)\},\s*//\s*(\d+)', tbl):
    n = int(m.group(3))
    if n == 0:
        continue                     # the unused row
    f = [x.strip() for x in m.group(2).split(",")]
    t2 = f[12] if len(f) > 12 else "T_NONE"
    acc = int(f[3], 16)   # RGB565 accent, as 0xRRGGBB
    rgb = ((acc >> 11) & 31) * 255 // 31 << 16 | ((acc >> 5) & 63) * 255 // 63 << 8 | (acc & 31) * 255 // 31
    nat[n] = [int(f[0]), int(f[1]), RARITY[f[2]], int(f[4]), int(f[5]), int(f[6]), int(f[7]), int(f[8]), int(f[9]),
              int(f[10]), TYPE[f[11]], -1 if t2 == "T_NONE" else TYPE[t2], rgb]

# each species' base EXP yield (PokeAPI's open data, capped at 255 as in the Gen 3 games): what
# beating it is worth (Battle EXP: yield x level / 7, x1.5 against a trainer, as in FireRed)
BASE_EXP = {int(k): v for k, v in json.load(open(os.path.join(HERE, "base_exp.json"))).items()}
rows = []
for k in range(1, R.COUNT + 1):
    r = list(nat[R.nat(k)])
    # a missing middle stage is skipped (it evolves straight into the next, at that one's level)
    while r[0] and r[0] in R.MISSING:
        r[0], r[1] = nat[r[0]][0], nat[r[0]][1]
    # an evolution into another region is cut: here it is a final form
    r[0] = R.local(r[0]) if r[0] else 0
    if r[0] == 0:
        r[1] = 0
    r.append(BASE_EXP.get(R.nat(k), 64))
    rows.append(r)
# a species that only comes by evolving from another region's (Crobat from Golbat, Pikachu's
# babies...) can't be reached here: it hatches from eggs instead, as a rare one
pre = {r[0] for r in rows if r[0]}
for k, r in enumerate(rows, 1):
    if r[2] == 0 and k not in pre:
        r[2] = 2
jd = os.path.join(APP, "resources", "jsondata")
json.dump(rows, open(os.path.join(jd, "dex.json"), "w"), separators=(",", ":"))
tiers = [sum(1 for r in rows if r[2] == t) for t in range(4)]
print(R.NAME, R.COUNT, "species | evo-only/common/rare/legendary:", tiers)

# ---------- gym teams ----------
# Kanto's are hand-made; another region's leaders (the same names, towns and types) field that
# region's species of their type at the same levels: at each level the strongest one that could be
# that far along its line, never a legendary (the champion takes the strongest of any type).
def bst(r):
    return sum(r[3:9])

reach = {}
def reach_level(k):
    """The lowest level species k can have (its pre-evolution's evolution level)."""
    if k not in reach:
        reach[k] = 1
        for j, r in enumerate(rows, 1):
            if r[0] == k:
                reach[k] = max(r[1], reach_level(j))
    return reach[k]

kanto_trainers = json.load(open(os.path.join(HERE, "trainers_kanto.json")))
if RID == "kanto":
    trainers = kanto_trainers
else:
    trainers = []
    seen = set()            # species earlier trainers field: the fallback picks others first
    for name, town, tp, badge, team in kanto_trainers:
        used = set()
        out = []
        for _, lvl in team:
            def ok(k, typed):
                r = rows[k - 1]
                if r[2] == 3 or k in used or reach_level(k) > lvl:
                    return False
                if r[0] and r[1] and r[1] <= lvl:
                    return False              # it would have evolved by now
                return not typed or tp in (r[10], r[11])
            pick = None
            for typed in ([True, False] if name != "AUREL" else [False]):
                c = [k for k in range(1, R.COUNT + 1) if ok(k, typed)]
                if c:
                    pick = max(c, key=lambda k: (typed or k not in seen, bst(rows[k - 1])))
                    break
            if pick is None:
                pick = max((k for k in range(1, R.COUNT + 1) if rows[k - 1][2] != 3), key=lambda k: bst(rows[k - 1]))
            used.add(pick)
            seen.add(pick)
            out.append([pick, lvl])
        trainers.append([name, town, tp, badge, out])
json.dump(trainers, open(os.path.join(jd, "trainers.json"), "w"), separators=(",", ":"))

# ---------- source: Dex.mc, Region.mc, the biomes ----------
eevee = R.local(133)
dex_mc = '''import Toybox.Lang;
import Toybox.WatchUi;

// GENERATED by tools/make_region.py - do not edit by hand.
// %s species table (from TamaPoke's dex.h), numbered 1-%d in the app (national #%d-%d,
// Region.NAT).
// Row: [evolvesTo, evolveLevel, rarity, hp, atk, def, spe, spa, spd, biome, type1, type2, accent]
module Dex {

    const R_EVO = 0;
    const R_COMMON = 1;
    const R_RARE = 2;
    const R_LEGEND = 3;
    const EEVEE = %d;
    const EEVEE_EVOS = [%s];
    const STARTERS = [%s];
    const COUNT = %d;

    var table = null;

    function rows() {
        if (table == null) { table = WatchUi.loadResource(Rez.JsonData.dex); }
        return table;
    }

    function row(n) {
        return rows()[n - 1];
    }

    function evolvesTo(n) { return row(n)[0]; }
    function evolveLevel(n) { return row(n)[1]; }
    function rarity(n) { return row(n)[2]; }
}
''' % (R.NAME.title(), R.COUNT, R.FIRST, R.LAST, eevee if eevee else -1,
       ", ".join(str(R.local(n)) for n in (134, 135, 136)) if eevee else "",
       ", ".join(str(R.local(n)) for n in R.STARTERS), R.COUNT)
open(os.path.join(APP, "source", "Dex.mc"), "w").write(dex_mc)

region_mc = '''import Toybox.Lang;

// GENERATED by tools/make_region.py - do not edit by hand.
// The one region this build holds. Another region is another build (and another app, with its
// own save): pick it on the TamaWatch website. Link battles work across regions (the friend's
// creatures come with their numbers and types); trades only within one.
module Region {
    const ID = "%s";
    const NAME = "%s";

    // A text naming the region: the translation, with KANTO (as the tables write it) replaced.
    function t(s) {
        var out = Tr.t(s);
        if (NAME.equals("KANTO")) { return out; }
        var at = out.find("KANTO");
        if (at == null) { return out; }
        return out.substring(0, at) + NAME + out.substring(at + 5, out.length());
    }

    // the national number of species n (an array built when asked: a constant would sit in every
    // process, the small glance too)
    function national(n) { return [%s][n - 1]; }
}
''' % (RID, R.NAME, ", ".join(str(n) for n in R.SPECIES))
open(os.path.join(APP, "source", "Region.mc"), "w").write(region_mc)

sc = os.path.join(APP, "source", "Scenes.mc")
s = open(sc).read()
s = re.sub(r'const BIOMES = "[0-9]*";', 'const BIOMES = "%s";' % "".join(str(r[9]) for r in rows), s)
s = s.replace("if (dex < 1 || dex > 151) { return 0; }", "if (dex < 1 || dex > Dex.COUNT) { return 0; }")
s = s.replace("// Biome per dex number 1-151 (0 meadow", "// Biome per species of the region (0 meadow")
open(sc, "w").write(s)

for mf in ("manifest.xml", "manifest-app.xml", "manifest-new.xml"):
    p = os.path.join(APP, mf)
    s = open(p).read()
    s = re.sub(r'(<iq:application[^>]*\bid=")[0-9a-f]{32}(")', r"\g<1>%s\2" % R.app_id(), s)
    open(p, "w").write(s)

# ---------- pictures and per-species data ----------
def run(script, *args):
    r = subprocess.run([sys.executable, "-P", os.path.join(HERE, script)] + list(args), capture_output=True, text=True)
    if r.returncode:
        sys.exit(script + " failed:\n" + r.stdout + r.stderr)
    for line in r.stdout.strip().split("\n"):
        if line.startswith("shiny atlases"):
            print(" ", script + ":", line)
    print(" ", script + ":", r.stdout.strip().split("\n")[-1])

# remove the last region's per-species JSON beyond this one's count
for f in os.listdir(jd):
    m = re.match(r"d(\d{3})\.json$", f)
    if m and int(m.group(1)) > R.COUNT:
        os.remove(os.path.join(jd, f))
run("make_sprites.py", SC, APP)
run("make_moves.py", SRC, APP)
run("make_glance_thumbs.py", SC, APP)
run("make_sprite_centres.py", APP)
run("make_thumbs.py", SC, APP)
run("make_thumb_centres.py", APP)
run("boost_colours.py", APP, "--species")       # the MIP screen's colours, as the rest of the app
open(os.path.join(APP, "REGION.txt"), "w").write(RID + "\n")
print("region:", RID, "app id", R.app_id())
