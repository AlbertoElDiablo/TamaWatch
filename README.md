# TamaWatch

A virtual pet for Garmin watches that grows with how active you are. A Garmin Connect IQ port of
[TamaPoke](https://github.com/socquique/TamaPoke), reworked around your watch's own data.

**Install it:** pick your region and your watch on the download page,
**https://albertoeldiablo.github.io/TamaWatch/**, and follow the steps there. It runs on 105 Garmin
watch models.

> Unofficial, non-commercial fan project. Not affiliated with or endorsed by Nintendo, Game Freak,
> The Pokémon Company or Garmin. Pokémon names and characters are © Nintendo / Game Freak / The
> Pokémon Company. Free to use; there is nothing to buy.

## What it does

- **Your activity raises it.** Every 50 steps give it 1 EXP and every 3,000 steps an apple (steps add
  up over time). Each activity you record pays EXP by its length and sport, per minute: running or
  swimming 20, strength/gym 27, cycling 15, hiking 12, walking 8, anything else 15. Strength raises
  your heart rate less but is as hard, so 45 minutes of weights pay like an hour's run or 80 minutes
  on the bike (about 1,200 EXP). It also fills joy, trains a stat (running speed, cycling and
  swimming defence, strength attack) and gives fruit. Intensity minutes outside recorded activities
  give 10 EXP each.
- **It lives your day.** Its energy is your Body Battery and it sleeps when you do. Feed it, bathe
  it, clean up after it.
- **Eggs from walking.** Every 15,000 steps earn an egg (at most 2 a week); walk more to hatch it.
- **A team and a pet box.** Your partner plus 5 in the team, the rest in the box.
- **One region per watch.** Pick Kanto (151), Johto (100), Hoenn (135), Sinnoh (107), Unova (143),
  Kalos (71) or Alola (84) on the download page. Each region is its own app with its own game, so
  you can switch, or keep two, without losing anything. Kanto is the version TamaWatch always had:
  installing it over an older TamaWatch keeps your game.
- **HP that carries over.** The bar under your partner's name is its HP. Battles take it and it
  keeps what's left, so your next battle starts from there; a battle that costs 40 % or more of it
  also costs some food. HP refills by itself from empty in 15 minutes; each fruit and each training
  game gives some back at once, and a recorded activity gives back half.
- **Good care wins fights.** When food, hygiene or joy is under half, your partner's attacks miss
  more often (up to 4 in 10 with all three empty).
- **Training games find fruit.** Now and then (about 1 game in 3) a training game turns up one
  apple, blue berry or orange.
- **Quiet while you train.** Care alerts wait while you're recording an activity.
- **Battles.** Wild battles, 8 gyms with our own leaders and badges (easy or hard; hard gyms need
  some Body Battery), and link battles with a friend, **whatever region each of you plays** (a
  creature your watch has no picture of is shown as an orb in its type's colours).
- **Trading.** Swap team members with a friend who plays the same region (a creature only lives
  in its own region; the watch explains this if your regions differ).
- **7 languages:** Català, Deutsch, English, Español, Français, Italiano, Português.

### Playing with a friend

Both watches need this version (or newer). Link battles and trades connect two watches either **online** (each watch posts short messages to
a public [ntfy.sh](https://ntfy.sh) topic named by a 4-letter room code, through the paired phone)
or **nearby** (watch to watch over ANT, no phone; still untested on real watches). Online, the
pet's name, level and team pass through ntfy.sh's public servers while you play.

### Your data

TamaWatch reads your steps, activities, intensity minutes, floors, Body Battery and sleep times
**on the watch** to drive the game. Nothing is sent anywhere, except the game messages of an online
link battle or trade described above.

## Credits

- **TamaWatch** (the Garmin port, its rules, screens and new features): AlbertoElDiablo.
- **TamaPoke** (the original game, rules and battle engine this is ported from; MIT):
  Quique Tortosa (https://github.com/socquique/TamaPoke) and Cheng Ren
  (https://github.com/crenberries428/TamaPoke). The home-screen scenery and the dock are drawn from
  TamaPoke's code.
- **Pokémon sprites:** [PMD SpriteCollab](https://sprites.pmdcollab.org), CC BY-NC 4.0; every
  artist is listed in [CREDITS.md](CREDITS.md).
- **Font:** Roboto Condensed Bold (Google, Apache 2.0) on watches that don't have it built in.
- Gym leaders, badges, battle backdrops, trainers and icons are original to TamaWatch.

## Licence

The code is MIT (see [LICENSE](LICENSE)), keeping TamaPoke's copyright notices. The Pokémon
sprites are CC BY-NC 4.0 (non-commercial only) and Pokémon names and characters belong to their
owners; they are **not** covered by the MIT licence.

## Building it yourself

Needs the [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (with the device
files from its SDK Manager), Java, Python 3 with Pillow, and your own developer key.

```
export PATH=<java>/bin:$PATH
SDK=$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)
"$SDK/bin/monkeyc" -d fenix6pro -f monkey.jungle -o bin/TamaWatch.prg -y <your developer_key.der>
tools/build_all.sh                 # every supported watch into bin/devices/<watch>/
```

- Three build files: `monkey.jungle` (a widget, Connect IQ before 5.1), `monkey-new.jungle`
  (Connect IQ 5.1+: an app with a glance and its own notifications) and `monkey-app.jungle`
  (older watches that give a widget too little memory).
- Every screen is laid out once for a 280 x 280 screen and scaled to each watch by
  `source/Sdc.mc`. After changing any picture or text, run `python3 tools/make_lang.py .` and
  `python3 tools/make_scaled.py .`.
- Connect IQ allows 254 bitmaps per app and TamaWatch uses all of them.
- Regions: `python3 tools/make_region.py <kanto|johto|hoenn|sinnoh|unova|kalos|alola> <TamaPoke repo>
  <SpriteCollab-master>` turns the copy into that region's build (species, sprites, moves, gym
  teams, app id), then run `make_scaled.py` and build. `tools/make_release.sh` does every region
  and every watch into `bin/release/TamaWatch-<region>-<watch>.prg`.
