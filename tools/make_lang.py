"""The app's translations: tools/lang/table_*.py (English -> Catalan, Spanish, French, Italian,
Portuguese; German in table_de.py) into resources/jsondata/lang_{ca,es,fr,it,pt}.json, registered in jsondata.xml.
English needs no file: the code is written in it.

usage: python3 make_lang.py <TamaWatch> [keys.json]

With keys.json (the list of every text the app shows), reports any without a translation.
"""
import json, os, re, sys, importlib.util

APP = sys.argv[1]
CODES = ["ca", "es", "fr", "it", "pt", "de"]
table = {}
here = os.path.join(APP, "tools", "lang")
for f in sorted(os.listdir(here)):
    if f.startswith("table_") and f.endswith(".py"):
        spec = importlib.util.spec_from_file_location(f[:-3], os.path.join(here, f))
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        for k, v in getattr(m, "T", {}).items():
            assert len(v) == 5, k
            table[k] = v
        if hasattr(m, "DE"):
            de = m.DE
missing_de = [k for k in table if k not in de]
assert not missing_de, ("no German for", missing_de)
table = {k: v + (de[k],) for k, v in table.items()}
if len(sys.argv) > 2:
    keys = json.load(open(sys.argv[2]))
    want = keys["ui"] + keys["moves"] + keys["types"]
    missing = [k for k in want if k not in table]
    print("missing:", missing)
jd = os.path.join(APP, "resources", "jsondata")
for i, c in enumerate(CODES):
    json.dump({k: v[i] for k, v in table.items()}, open(os.path.join(jd, "lang_%s.json" % c), "w"),
              ensure_ascii=False, separators=(",", ":"))
x = os.path.join(jd, "jsondata.xml")
s = open(x).read()
for c in CODES:
    if 'id="lang_%s"' % c not in s:
        s = s.replace("</resources>", '    <jsonData id="lang_%s" filename="lang_%s.json"/>\n</resources>' % (c, c))
open(x, "w").write(s)
print("languages:", len(table), "texts each")
