"""The download page (docs/index.html, served by GitHub Pages): pick your watch, download its
TamaWatch file from the latest GitHub release, and the steps to put it on the watch.

The watch list comes from the three manifests (which watch gets which build) and the Connect IQ
SDK's device files (their names). The release files are named TamaWatch-<device>.prg
(tools/make_release.sh).

usage: python3 make_site.py <TamaWatch>
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

PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TamaWatch</title>
<meta name="description" content="A virtual pet for Garmin watches that grows with how active you are. Free download for 105 watches.">
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

  <section class="card step" aria-labelledby="s1">
    <span class="num">1</span>
    <div>
      <h2 id="s1">Find your watch</h2>
      <label for="watch" class="note">Your exact model is in the watch's settings, under System &gt; About.</label>
      <select id="watch"></select>
      <p class="note">Not in the list? TamaWatch needs a colour Garmin watch with Connect IQ 3.2 or newer and enough
      memory for apps, so some models (black-and-white ones, and a few with very little app memory) can't run it.</p>
    </div>
  </section>

  <section class="card step" aria-labelledby="s2">
    <span class="num">2</span>
    <div>
      <h2 id="s2">Download its file</h2>
      <p><a id="dl" class="btn" href="#" aria-disabled="true">Download TamaWatch</a></p>
      <p class="note">Each watch model has its own file; the one for another model won't start. After it downloads,
      rename it to <code>TamaWatch.prg</code> (so a later update simply replaces it).</p>
    </div>
  </section>

  <section class="card step" aria-labelledby="s3">
    <span class="num">3</span>
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
    <span class="num">4</span>
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
      Your pet, team and progress are kept.</p></details>
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
const REPO = "__REPO__";
const WHERE = {
  widget: "On this watch TamaWatch is a <b>widget</b>: scroll the widget list from the watch face (UP / DOWN) and select it.",
  new: "On this watch TamaWatch opens from the <b>apps list</b> (START on the watch face, or the Activities &amp; Apps menu), and its preview also shows in the widget / glance list.",
  app: "On this watch TamaWatch opens from the <b>apps list</b> (START on the watch face, or the Activities &amp; Apps menu)."
};
const sel = document.getElementById("watch"), dl = document.getElementById("dl"), where = document.getElementById("where");

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
  dl.href = "https://github.com/" + REPO + "/releases/latest/download/TamaWatch-" + w.id + ".prg";
  dl.setAttribute("aria-disabled", "false");
  dl.textContent = "Download TamaWatch for " + w.name.split(" / ")[0];
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
let saved = null;
try { saved = localStorage.getItem("tamawatch-watch"); } catch (e) {}
choose(WATCHES.find(w => w.id === saved));
</script>
</body>
</html>
"""

page = PAGE.replace("__WATCHES__", json.dumps(watches, ensure_ascii=False)).replace("__REPO__", REPO)
os.makedirs(os.path.join(APP, "docs"), exist_ok=True)
open(os.path.join(APP, "docs", "index.html"), "w", encoding="utf-8").write(page)
print(len(watches), "watches on the page")
