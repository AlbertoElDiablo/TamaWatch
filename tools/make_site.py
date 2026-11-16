"""The download page (docs/index.html, served by GitHub Pages): pick your watch, download its
TamaWatch file from the latest GitHub release, and the steps to put it on the watch.

The watch list comes from the three manifests (which watch gets which build) and the Connect IQ
SDK's device files (their names), the regions from tools/region.py. The release files are named
TamaWatch-<region>-<device>.prg (tools/make_release.sh).

usage: python3 make_site.py <TamaWatch>      (TW_SITE_REGIONS="kanto johto ...": list only these)
"""
import html, json, os, re, sys

APP = sys.argv[1]
REPO = "AlbertoElDiablo/TamaWatch"
DEVICES = os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Devices")
BUILDS = [("manifest.xml", "widget"), ("manifest-new.xml", "new"), ("manifest-app.xml", "app")]

watches = []
for manifest, kind in BUILDS:
    for d in re.findall(r'iq:product id="([^"]+)"', open(os.path.join(APP, manifest)).read()):
        j = json.load(open(os.path.join(DEVICES, d, "compiler.json")))
        name = (j.get("displayName") or d).replace("®", "").replace("™", "")
        watches.append({"id": d, "name": re.sub(r"\s+", " ", name).strip(), "kind": kind})
watches.sort(key=lambda w: w["name"].lower())
sys.path.insert(0, os.path.join(APP, "tools"))
import region as RG
regions = [{"id": k, "name": RG.REGIONS[k][2].title(), "first": RG.REGIONS[k][0], "last": RG.REGIONS[k][1],
            "count": len(RG.species(k))} for k in RG.ORDER]
# TW_SITE_REGIONS="kanto johto": only those (the ones already in the release)
if os.environ.get("TW_SITE_REGIONS"):
    keep = os.environ["TW_SITE_REGIONS"].split()
    later = [r["name"] for r in regions if r["id"] not in keep]
    regions = [r for r in regions if r["id"] in keep]
else:
    later = []

PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TamaWatch</title>
<meta name="description" content="A virtual pet for Garmin watches that grows with how active you are. Seven regions, free download for 105 watches.">
<style>
  :root {
    --bg: #f6f4ef; --card: #ffffff; --ink: #1d1b16; --muted: #5d5a52; --line: #e3dfd5;
    --accent: #d8402c; --accent-ink: #ffffff; --soft: #fbe9e5; --ok: #2f7d32; --code: #f0ede5;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #15140f; --card: #1f1d17; --ink: #f1eee6; --muted: #b3ae9f; --line: #34312a;
            --accent: #ef5a44; --accent-ink: #ffffff; --soft: #3a201b; --ok: #7cc47f; --code: #2a2821; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink);
         font: 16px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 760px; margin: 0 auto; padding: 32px 16px 64px; }
  header { margin-bottom: 28px; }
  h1 { font-size: 40px; line-height: 1.1; margin: 0 0 8px; letter-spacing: -0.5px; }
  h2 { font-size: 20px; margin: 0 0 12px; }
  .lead { font-size: 18px; color: var(--muted); margin: 0; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 14px;
          padding: 20px; margin: 16px 0; }
  .step { display: flex; gap: 14px; }
  .num { flex: none; width: 30px; height: 30px; border-radius: 50%; background: var(--accent);
         color: var(--accent-ink); font-weight: 700; display: grid; place-items: center; }
  .step > div { flex: 1; min-width: 0; }
  select { width: 100%; font: inherit; padding: 12px 14px; border-radius: 10px; margin-top: 8px;
         border: 1px solid var(--line); background: var(--bg); color: var(--ink); }
  .btn { display: inline-block; background: var(--accent); color: var(--accent-ink);
         text-decoration: none; font-weight: 700; padding: 12px 20px; border-radius: 10px; }
  .btn[aria-disabled=true] { opacity: .45; pointer-events: none; }
  .regions { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 8px; margin-top: 10px; }
  .regions button { font: inherit; text-align: left; padding: 10px 12px; border-radius: 10px; cursor: pointer;
         border: 1px solid var(--line); background: var(--bg); color: var(--ink); }
  .regions button b { display: block; font-size: 17px; }
  .regions button span { font-size: 13px; color: var(--muted); }
  .regions button[aria-pressed=true] { border-color: var(--accent); box-shadow: inset 0 0 0 2px var(--accent); }
  ul.plain { padding-left: 20px; margin: 8px 0; }
  .tabs { display: flex; gap: 8px; margin: 4px 0 12px; flex-wrap: wrap; }
  .tabs button { font: inherit; padding: 8px 14px; border-radius: 999px; cursor: pointer;
         border: 1px solid var(--line); background: var(--bg); color: var(--ink); }
  .tabs button[aria-selected=true] { background: var(--ink); color: var(--bg); border-color: var(--ink); }
  ol { padding-left: 20px; margin: 8px 0; }
  li { margin: 4px 0; }
  code { background: var(--code); padding: 1px 6px; border-radius: 6px; font-size: 0.92em; }
  .note { color: var(--muted); font-size: 14px; }
  .where { background: var(--soft); border-radius: 10px; padding: 10px 14px; margin-top: 10px; }
  details { border-top: 1px solid var(--line); padding: 10px 0; }
  details:first-of-type { border-top: 0; }
  summary { cursor: pointer; font-weight: 600; }
  footer { margin-top: 32px; font-size: 14px; color: var(--muted); }
  footer a, .card a:not(.btn) { color: var(--accent); }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<main>
  <header>
    <h1>TamaWatch</h1>
    <p class="lead">A virtual pet for your Garmin watch. Walk, train and sleep well, and it grows with you.
    Free, for 105 watches.</p>
  </header>

  <section class="card step" aria-labelledby="s0">
    <span class="num">1</span>
    <div>
      <h2 id="s0">Choose your region</h2>
      <p class="note">Each region is its own TamaWatch, with its own creatures and its own game, so trying another
      never touches the one you have. <b>Kanto</b> is the original: installing it over an older TamaWatch keeps your game.</p>
      <div id="regions" class="regions" role="group" aria-label="Region"></div>__LATER__
    </div>
  </section>

  <section class="card step" aria-labelledby="s1">
    <span class="num">2</span>
    <div>
      <h2 id="s1">Find your watch</h2>
      <label for="watch" class="note">Your exact model is in the watch's settings, under System &gt; About.</label>
      <select id="watch"></select>
      <p class="note">Not in the list? TamaWatch needs a colour Garmin watch with Connect IQ 3.2 or newer and enough
      memory for apps, so some models (black-and-white ones, and a few with very little app memory) can't run it.</p>
    </div>
  </section>

  <section class="card step" aria-labelledby="s2">
    <span class="num">3</span>
    <div>
      <h2 id="s2">Download its file</h2>
      <p><a id="dl" class="btn" href="#" aria-disabled="true">Download TamaWatch</a></p>
      <p class="note">Each watch model has its own file; the one for another model won't start. After it downloads,
      rename it to <code>TamaWatch.prg</code> (so a later update simply replaces it). To keep two regions on one
      watch, give the second its own name, such as <code>TamaWatch-johto.prg</code>.</p>
    </div>
  </section>

  <section class="card step" aria-labelledby="s3">
    <span class="num">4</span>
    <div>
      <h2 id="s3">Copy it onto the watch</h2>
      <div class="tabs" role="tablist">
        <button role="tab" aria-selected="true" data-tab="win">Windows</button>
        <button role="tab" aria-selected="false" data-tab="mac">Mac</button>
      </div>
      <div data-panel="win">
        <ol>
          <li>Connect the watch to the computer with its charging cable.</li>
          <li>Open <b>File Explorer</b>. The watch appears under <b>This PC</b> (as its name, or as a drive).</li>
          <li>Open <code>Internal Storage</code> (if shown), then <code>GARMIN</code>, then <code>Apps</code>.</li>
          <li>Copy <code>TamaWatch.prg</code> into <code>Apps</code>. If an older TamaWatch.prg is there, replace it: your pet and progress stay on the watch.</li>
          <li>Eject the watch and unplug it. It takes a moment to install.</li>
        </ol>
      </div>
      <div data-panel="mac" hidden>
        <ol>
          <li>Install <a href="https://openmtp.ganeshrvel.com">OpenMTP</a> (free). macOS can't open Garmin watches on its own.
              Quit Garmin Express first if it's running.</li>
          <li>Connect the watch with its charging cable and open OpenMTP.</li>
          <li>On the watch's side, open <code>GARMIN</code>, then <code>Apps</code>.</li>
          <li>Drag <code>TamaWatch.prg</code> into <code>Apps</code>. If an older TamaWatch.prg is there, replace it: your pet and progress stay on the watch.</li>
          <li>Unplug the watch. It takes a moment to install.</li>
        </ol>
        <p class="note">Some older watches show up in Finder as a drive; then just copy the file into <code>GARMIN/Apps</code> there.</p>
      </div>
    </div>
  </section>

  <section class="card step" aria-labelledby="s4">
    <span class="num">5</span>
    <div>
      <h2 id="s4">Open it</h2>
      <p id="where" class="where">Pick your watch above to see where TamaWatch appears on it.</p>
      <ol>
        <li>The first time, choose your language, your trainer's name and look, and how many workouts you do in a usual week.</li>
        <li>Pick your first partner, and keep moving: steps, workouts and sleep all count.</li>
        <li><b>UP</b> and <b>DOWN</b> move, <b>START</b> picks, <b>BACK</b> goes back, and holding <b>UP</b> (or the book on screen) opens the menu.
            The guide in the menu explains everything else.</li>
      </ol>
    </div>
  </section>

  <section class="card" aria-labelledby="how">
    <h2 id="how">How it plays</h2>
    <details open><summary>Latest updates</summary>
      <ul class="plain">
        <li><b>Pick your region.</b> Kanto, Johto, Hoenn, Sinnoh, Unova, Kalos or Alola, one per app.</li>
        <li><b>HP that carries over.</b> A bar under your partner's name: battles take it, it refills in 15 minutes.</li>
        <li><b>Care counts in battle.</b> A hungry, dirty or unhappy partner misses more of its attacks.</li>
        <li><b>Training games can find fruit</b>, one piece at most, now and then.</li>
        <li><b>No alerts mid-workout.</b> Care reminders wait while you're recording an activity.</li>
        <li><b>Workouts pay EXP by length and sport</b>, so weights earn as much as cardio.</li>
        <li><b>A result screen after every battle</b>, won or lost: both sides, EXP, HP and more. A loss pays a tenth of a win's EXP.</li>
        <li><b>No steps lost</b>: steps from a day you didn't open the app (your long run!) now count for eggs, EXP and apples.</li>
        <li><b>Fruit fills 40% more</b> of the food bar.</li>
        <li><b>Only your partner gets hungry.</b> Team and Pokébox creatures recover to full within 24 hours (HP within 15 minutes) and keep their own care when they become partner.</li>
        <li><b>Each step counts once for eggs:</b> a waiting egg hatches first, then steps count toward the next one.</li>
        <li><b>Recorded activities count again.</b> Watches that date them differently were skipping every workout; now each one pays.</li>
        <li><b>Battle friends from any region.</b> Trades stay within one region.</li>
        <li>A new page at the start of the game points you to the in-app <b>GUIDE</b>. Worth a read!</li>
      </ul>
    </details>
    <details><summary>HP</summary>
      <p>The bar under your partner's name is its HP. Battles take it, and it keeps what's left: your next battle
      (wild, gym or link) starts from there. A battle that costs 40% or more of its HP also costs some food, a
      quarter of what it lost.</p>
      <p>HP refills by itself, from empty to full in 15 minutes. Each fruit gives some back at once (its favourite
      more), and so does every training game; a recorded activity gives back half the bar.</p></details>
    <details><summary>Good care wins fights</summary>
      <p>When food, hygiene or joy is under half, your partner's attacks miss more often: the lower they are, the
      more it misses, up to 4 attacks in 10 when all three are empty. Feed it, bathe it and keep training.</p></details>
    <details><summary>Fruit from training games</summary>
      <p>The three training games on the football button sometimes turn up a piece of fruit: an apple, a blue berry
      or an orange. One piece at most per game, and about one game in three.</p></details>
    <details><summary>Your activities</summary>
      <p>Every activity you record on the watch (5 minutes or more) pays EXP by its length and sport. Per minute:
      running or swimming 20, strength or gym 27, cycling 15, hiking 12, walking 8, anything else 15. Weights raise
      your heart rate less but are just as hard, so 45 minutes of weights pay like an hour's run or 80 minutes on the
      bike (about 1,200 EXP). It also fills your partner's joy, trains a stat (running speed, cycling and swimming
      defence, strength attack), gives a berry or an orange (one more for every 45 minutes) and gives back HP.
      Intensity minutes outside your recorded activities still give 10 EXP each. Care alerts wait while you're
      recording, so nothing buzzes mid-run.</p></details>
    <details><summary>Regions, battles and trades</summary>
      <p>Your watch holds one region. Link battles work with a friend playing any region: a creature your watch has
      no picture of shows as an orb in its type's colours, and fights with its real types and moves. Trades need the
      same region on both watches, because a creature can only live in its own region; the watch tells you so if
      yours differ. Both watches need version 1.1 or newer.</p></details>
  </section>

  <section class="card" aria-labelledby="faq">
    <h2 id="faq">If something's not right</h2>
    <details><summary>The watch shows an "IQ" icon with an exclamation mark</summary>
      <p>The file is for a different model. Check the exact model in your watch's settings (System &gt; About),
      download that one and replace the file.</p></details>
    <details><summary>TamaWatch doesn't appear on the watch</summary>
      <p>Make sure the file is directly inside <code>GARMIN/Apps</code> (not in a folder of its own) and ends in <code>.prg</code>,
      then unplug the watch and give it a minute.</p></details>
    <details><summary>Online battles and trades don't connect</summary>
      <p>Online play goes through your phone: keep it near, with Garmin Connect running and internet on.
      "Nearby" play connects two watches directly but hasn't been tried on real watches yet.</p></details>
    <details><summary>Updating to a new version</summary>
      <p>Download the new file for your watch and replace the old <code>TamaWatch.prg</code> in <code>GARMIN/Apps</code>.
      Your pet, team and progress are kept. Before version 1.1 TamaWatch was Kanto only: choose Kanto to carry on
      with that game.</p></details>
    <details><summary>Switching region</summary>
      <p>Another region is a separate app with its own new game: your game in the first region stays on the watch,
      untouched, as long as you keep its file (or put it back later).</p></details>
    <details><summary>What does TamaWatch do with my data?</summary>
      <p>It reads your steps, activities, Body Battery and sleep on the watch to run the game, and sends nothing anywhere.
      The only exception is online battles and trades: their game messages (your pet's name, level and team) pass
      through the public service ntfy.sh while you play.</p></details>
  </section>

  <footer>
    <p><b>TamaWatch</b> by <a href="https://github.com/AlbertoElDiablo">AlbertoElDiablo</a> ·
       <a href="https://github.com/__REPO__">source code</a> ·
       a Garmin port of <a href="https://github.com/socquique/TamaPoke">TamaPoke</a> by Quique Tortosa and Cheng Ren (MIT).
       Pokémon sprites from <a href="https://sprites.pmdcollab.org">PMD SpriteCollab</a> (CC BY-NC 4.0); artists in
       <a href="https://github.com/__REPO__/blob/main/CREDITS.md">CREDITS.md</a>.</p>
    <p>Unofficial, non-commercial fan project, not affiliated with or endorsed by Nintendo, Game Freak, The Pokémon Company
       or Garmin. Pokémon names and characters are © Nintendo / Game Freak / The Pokémon Company.</p>
  </footer>
</main>

<script>
const WATCHES = __WATCHES__;
const REGIONS = __REGIONS__;
const REPO = "__REPO__";
const WHERE = {
  widget: "On this watch TamaWatch is a <b>widget</b>: scroll the widget list from the watch face (UP / DOWN) and select it.",
  new: "On this watch TamaWatch opens from the <b>apps list</b> (START on the watch face, or the Activities &amp; Apps menu), and its preview also shows in the widget / glance list.",
  app: "On this watch TamaWatch opens from the <b>apps list</b> (START on the watch face, or the Activities &amp; Apps menu)."
};
const sel = document.getElementById("watch"), dl = document.getElementById("dl"), where = document.getElementById("where");
let region = REGIONS[0];
const rbox = document.getElementById("regions");
for (const r of REGIONS) {
  const b = document.createElement("button");
  b.type = "button"; b.dataset.region = r.id;
  b.innerHTML = "<b>" + r.name + "</b><span>" + r.count + " creatures · #" + r.first + "–" + r.last + "</span>";
  b.addEventListener("click", () => pickRegion(r));
  rbox.appendChild(b);
}
function pickRegion(r) {
  region = r;
  for (const b of rbox.querySelectorAll("button")) b.setAttribute("aria-pressed", b.dataset.region === r.id ? "true" : "false");
  try { localStorage.setItem("tamawatch-region", r.id); } catch (e) {}
  choose(WATCHES.find(w => w.id === sel.value));
}

// a dropdown, the watches grouped by family
const FAMILIES = ["Approach", "D2", "Descent", "Enduro", "epix", "fenix", "Forerunner", "Instinct", "MARQ", "Venu", "vivoactive"];
function family(name) {
  const n = name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  for (const f of FAMILIES) if (n.startsWith(f.toLowerCase())) return f === "fenix" ? "fēnix" : (f === "vivoactive" ? "vívoactive" : f);
  return "Other";
}
const first = document.createElement("option");
first.value = ""; first.textContent = "Choose your watch…"; sel.appendChild(first);
const groups = {};
for (const w of WATCHES) {
  const f = family(w.name);
  if (!groups[f]) { groups[f] = document.createElement("optgroup"); groups[f].label = f; }
  const o = document.createElement("option"); o.value = w.id; o.textContent = w.name; groups[f].appendChild(o);
}
for (const f of Object.keys(groups).sort((a, b) => a === "Other" ? 1 : b === "Other" ? -1 : a.localeCompare(b))) sel.appendChild(groups[f]);

function choose(w) {
  if (!w) {
    dl.href = "#"; dl.setAttribute("aria-disabled", "true"); dl.textContent = "Download TamaWatch";
    where.textContent = "Pick your watch above to see where TamaWatch appears on it.";
    return;
  }
  sel.value = w.id;
  dl.href = "https://github.com/" + REPO + "/releases/latest/download/TamaWatch-" + region.id + "-" + w.id + ".prg";
  dl.setAttribute("aria-disabled", "false");
  dl.textContent = "Download TamaWatch " + region.name + " for " + w.name.split(" / ")[0];
  where.innerHTML = WHERE[w.kind];
  try { localStorage.setItem("tamawatch-watch", w.id); } catch (e) {}
}
sel.addEventListener("change", () => choose(WATCHES.find(w => w.id === sel.value)));
for (const t of document.querySelectorAll("[role=tab]")) {
  t.addEventListener("click", () => {
    for (const u of document.querySelectorAll("[role=tab]")) u.setAttribute("aria-selected", u === t ? "true" : "false");
    for (const p of document.querySelectorAll("[data-panel]")) p.hidden = p.dataset.panel !== t.dataset.tab;
  });
}
if (/Mac/.test(navigator.platform)) document.querySelector("[data-tab=mac]").click();
let saved = null, savedRegion = null;
try { saved = localStorage.getItem("tamawatch-watch"); savedRegion = localStorage.getItem("tamawatch-region"); } catch (e) {}
const sw = WATCHES.find(w => w.id === saved);
if (sw) sel.value = sw.id;
pickRegion(REGIONS.find(r => r.id === savedRegion) || REGIONS[0]);
</script>
</body>
</html>
"""

LATER = ("" if not later else '\n      <p class="note">%s %s on %s way: %s appear here as soon as %s files are up.</p>'
         % (", ".join(later[:-1]) + (" and " if len(later) > 1 else "") + later[-1], "are" if len(later) > 1 else "is",
            "their" if len(later) > 1 else "its", "they'll" if len(later) > 1 else "it'll", "their" if len(later) > 1 else "its"))
PAGE = PAGE.replace("__LATER__", LATER)
page = PAGE.replace("__WATCHES__", json.dumps(watches, ensure_ascii=False)).replace("__REGIONS__", json.dumps(regions)).replace("__REPO__", REPO)
os.makedirs(os.path.join(APP, "docs"), exist_ok=True)
open(os.path.join(APP, "docs", "index.html"), "w", encoding="utf-8").write(page)
print(len(watches), "watches on the page")
