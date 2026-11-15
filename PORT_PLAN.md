# Porting TamaPoke to TamaWatch (Garmin fēnix 6X Pro)

Goal: a functional TamaWatch that does what TamaPoke does
(https://github.com/crenberries428/TamaPoke, MIT code; original by socquique),
then modify it to suit. Code and rules are ported; see "Not ported" for assets that can't be.

## Phases (each ends with a working build, checked in the simulator)

1. ✅ **Life sim parity** (done 2026-11-13; evolution/endings/catch-up not yet seen in the simulator) (`pet.cpp`): time-based levels (+1/h, cap 100), needs drain per minute
   (FOOD/JOY/ENE/HYG, start 80/80/80/100), poops, sleep rules and floors, care slip-ups,
   evolution offered at its level when every stat ≥ 40 (witness / decline), weight, berries
   (3 flavours + hidden favourite) and candy, pet-it, bond / streak, medals, IVs, the three
   endings (farewell at final form + 3 days, run-away, release) and egg rarity tiers + shiny.
   Starter choice (Bulbasaur / Charmander / Squirtle) on a first game.
2. 🔨 **Battles** (engine, moves, learnsets and battle screen built 2026-11-13; being checked in the simulator) (`battle.cpp`, `moves.h`, `types.h`): turn- and move-based engine with the
   type chart, STAB, ailments, level-up moves + TMs at 40. Battle screen on the **foe's biome
   backdrop** (day/night), as TamaPoke's `drawBattleBack()`.
3. 🔨 **Trainers and gyms** (built 2026-11-13: Menu > Gyms, easy/hard, level cap, badges, win screen, training) (`trainers.h`): TamaPoke's ladder structure (8 gyms, Elite 4, champion,
   easy/hard, its level curve, gym-win training) with **our own** leaders: original names and towns,
   each a type specialist matching our badges, teams drawn from Kanto species of that type. Badges are **our own** 8 designs from `tools/make_badges.py`
   (Cairn, Tide, Spark, Sprout, Spore, Mind, Ember, Quake), not the games'.
4. 🔨 **Training minigames** (built 2026-11-13: the dumbbell opens Training; UP/START/DOWN replace taps): training bag (STRENGTH), dodge run (SPEED), brace-and-block (DEFENSE),
   remapped from taps to the watch's buttons.
5. 🔨 **Collection** (built 2026-11-13: party + box, team pick for gyms, Pokédex list, 4-page stat card, rename): party (6) + box, Pokédex (Kanto), stat card (Profile / Battle / Medals / Progress),
   rename.
6. 🔨 **Rest** (built: step milestones, retire, auto-sleep, care-alert setting, bath bubbles): step milestones (2,500 / 5,000 / 10,000), retire early, auto-sleep at night,
   settings that make sense on a watch.

## Watch adaptations

- No touchscreen: UP/DOWN move a highlight, START presses, MENU (hold UP) opens menus, BACK goes back.
- Kanto only for now (151 + the six cross-generation evolutions excluded until those sprites exist).
- English UI first.
- Data tables (moves, learnsets, trainers) as JSON resources loaded on demand: 1.3 MB of app memory.

## Not ported

| What | Why |
|---|---|
| Battle backgrounds `tools/backs/*.png` | provenance unknown (TamaPoke's own CREDITS says so); replaced by original ones from `tools/make_battle_backs.py` |
| Game Boy music (`music.h`) and cries (`cries.h`) | transcribed from the games, not licensed (TamaPoke's CREDITS says so); the watch also has only beeps/vibration |
| Gym badge artwork (`badges.h`) and trainer avatars (`avatars.h`) | traced from the games' designs; TamaWatch has its own original badges instead |
| Hand-drawn fallback creature sprites (`species.h` SPR_*) | drawings of the games' characters; TamaWatch uses the SpriteCollab sprites |
| LAN battles (`link.cpp`, `linknow.cpp`) | ESP-NOW between boards; no equivalent between two Garmin watches |
| Jukebox | depends on the music above |
| Sound effects, brightness, language pages | hardware-specific; the watch handles these itself |

## Phase 1 notes

- On the watch the app is closed most of the day, so opening it replays every minute since the
  last time with the same rules ("Catching up..." for long gaps, at most 2 weeks), as if the
  device had stayed on. App closed = TamaPoke's "screen off": between 00:00 and 06:00 it puts
  the creature to bed, and opening the app wakes it.
- Decisions (evolve / goodbye / run-away) show a banner and live at the top of the menu (hold UP).
- Not yet: party snapshot on farewell/release (phase 5), rename (phase 5), bath animation.

## Phase 2 notes

- Engine: a straight port of TamaPoke's battle.cpp (damage formula, STAB, crits, rolls, type chart,
  priority/speed, paralysis/burn/poison/sleep/freeze/confusion, stages, recoil, drain, recharge,
  charge, multi-hit, easy/smart AI). Data from tools/make_moves.py (90 moves, type chart, learnsets).
- Moves on the pet: level-up moves fill free slots or wait as an offer (banner + menu "New move!");
  "Moves" in the menu lists what it knows and what it can learn now (TMs from level 40).
- Battle screen: TamaPoke's layout scaled to 280 px, on our original backdrops for the foe's biome.
- Entry point until gyms exist: "Wild battle" in the menu (TamaWatch's own practice fight,
  a random non-legendary Kanto foe at your level, no rewards). SWITCH waits for the party (phase 5).

## Phase 3-4 notes

- Our ladder (resources/jsondata/trainers.json): PETRA (rock, Cairn), MARINA (water, Tide), OHM (electric,
  Spark), FERN (grass, Sprout), NETTLE (poison, Spore), LUMEN (psychic, Mind), CINDER (fire, Ember),
  TERRA (ground, Quake), Elite 4 RIME / BRAWN / VESPER / SABLE, champion AUREL. Levels 12 -> 63.
  Easy = foes IV 16 + random moves, hard = IV 31 + smart AI (TamaPoke's EASY_IV / HARD_IV).
- Your pet fights at most at the trainer's top level (TamaPoke's buildSquad cap). A win pays a badge the
  first time (easy and hard tracked apart) and 3-5 / 6-10 training (+1 per 3 trainers up the ladder).
- Training games: bag (START on the line), dodge run (UP/DOWN lanes), brace & block (UP left, START top,
  DOWN right); BACK quits and keeps what was earned. Rewards are TamaPoke's trainStrength / trainSpeed /
  playResult.

## Phase 5-6 notes and remaining gaps

- Party: goodbye / release add the creature (frozen at its level) to the party, then the box (120),
  as TamaPoke; only when both are full does a banner + "Make room" ask who it replaces, or let it go.
- Gym team: a checklist of your pet + party before each gym fight (TamaPoke's squad pick). Training
  from a win only goes to the live pet, and only if it fought.
- Rename: a letter wheel (no keyboard on the watch). Settings: care alerts on/off.
- Shiny sprites: SpriteCollab's shiny sheets (sprite/NNNN/0000/0001) in the same layout as the normal
  ones, packed into 60 atlases grouped by shared colours (<= 15 each, 4 bits/pixel) to stay under the
  254-drawable limit; icons, badges and battle backdrops were merged into strips to make room.
  Three anims have no shiny file (16/26/132 Eat) and use the normal frames. App size ~16 MB.
- Not done: the six cross-generation evolutions (Kanto only).

## Round 2 (2026-11-13): closer to TamaPoke

Ported: the step plate on the left rim (arc toward 10,000, gold at the goal), the floating heart
(drawHeartFloat), the snoring Zs (drawSnore), the evolution flicker between old and new forms,
TamaPoke's full status line (statusMsg), the shiny "*" marks and "It's SHINY!!", the badge case
(stat card page 5), a Pokedex grid with sprites + detail page, a member sheet for party/box,
sound cues as watch tones + vibration (Settings: sounds, vibration), twinkling night stars.
Battles now play one action at a time (each attack its own step: message, lunge, hit, HP drain).

Not ported, and why:
- Background residents (small creatures behind the pet): the 6X Pro (Connect IQ 3.4) cannot scale
  bitmaps at runtime and our sheets are 2x, so they would be as big as the pet; there is no room
  under the 254-drawable limit for small copies.
- Live-animated scenery (drifting clouds, waves, lava): a full redraw every frame costs battery on
  the watch; the scenes stay as rendered images (night stars twinkle on top).
- Music, cries, jukebox, LAN battles, trainer portraits, other regions: see "Not ported" above.
