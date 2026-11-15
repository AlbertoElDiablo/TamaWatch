# TamaWatch

A virtual pet for Garmin watches that grows with how active you are. A Garmin Connect IQ port of
[TamaPoke](https://github.com/socquique/TamaPoke), reworked around your watch's own data.

**Install it:** pick your watch on the download page, **https://albertoeldiablo.github.io/TamaWatch/**,
and follow the steps there. It runs on 105 Garmin watch models.

> Unofficial, non-commercial fan project. Not affiliated with or endorsed by Nintendo, Game Freak,
> The Pokémon Company or Garmin. Pokémon names and characters are © Nintendo / Game Freak / The
> Pokémon Company. Free to use; there is nothing to buy.

## What it does

- **Your activity raises it.** Every 50 steps give it 1 EXP and every 3,000 steps an apple (steps add
  up over time). Intensity minutes give EXP, recorded workouts fill its joy and train a stat
  (running speed, cycling and swimming defence, strength attack).
- **It lives your day.** Its energy is your Body Battery and it sleeps when you do. Feed it, bathe
  it, clean up after it.
- **Eggs from walking.** Every 15,000 steps earn an egg (at most 2 a week); walk more to hatch it.
- **A team and a pet box.** Your partner plus 5 in the team, the rest in the box; 151 to collect
  in the Pokédex.
- **Battles.** Wild battles, 8 gyms with our own leaders and badges (easy or hard; hard gyms need
  some Body Battery), and link battles with a friend.
- **Trading.** Swap team members with a friend.
- **7 languages:** Català, Deutsch, English, Español, Français, Italiano, Português.

### Playing with a friend

Link battles and trades connect two watches either **online** (each watch posts short messages to
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
