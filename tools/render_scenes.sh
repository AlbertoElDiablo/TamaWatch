#!/bin/bash
# Renders TamaPoke's idle-screen scenery (MIT-licensed drawing code) to images,
# without the UI, the pet or the resident Pokemon, for TamaWatch backgrounds.
# Compiles TamaPoke's firmware sources with its own desktop-emulator stubs, minus the
# SDL window layer, and runs drawScene() for 7 biomes x 4 times of day.
# Writes only inside the work dir; scenes end up in <work dir>/scenebuild/out.
set -e
# usage: bash tools/render_scenes.sh <TamaPoke clone> <work dir>
R="$1"
S="$2"
E=$R/tools/emu
B=$S/scenebuild
rm -rf "$B" && mkdir -p "$B/out" "$B/nosprites"

# same steps as tools/emu/build.sh: prototypes for the .ino, then compile it as C++
cd "$B"   # genproto.py writes proto.h into the current folder
python3 -I "$E/genproto.py" "$R/TamaPoke.ino"
{ echo '#include "proto.h"'; cat "$R/TamaPoke.ino"; } > "$B/sketch.cpp"

# the emulator's main file up to (not including) its SDL main(), plus a small main of our own
awk 'NR<457' "$E/main_sdl.cpp" | grep -v '#include <SDL.h>' > "$B/scene_main.cpp"
cat >> "$B/scene_main.cpp" <<'EOF'

// TamaWatch: render TamaPoke's idle scenery only (no UI, no pet, no residents).
extern bool gNight;
void drawScene(uint8_t biome, uint32_t now, bool night);
int main(int argc, char **argv) {
  g_argv = argv;
  emuSetSpriteDir(argv[1]);          // empty dir: resident sprites never load
  const char *outDir = argv[2];
  setup();
  const int hours[4] = {7, 12, 19, 23};   // sunrise, day, sunset, night
  const char *names[4] = {"dawn", "day", "dusk", "night"};
  for (int t = 0; t < 4; t++) {
    rtcSetEpoch(1767225600UL + hours[t] * 3600UL);
    pet.lastSeenEpoch = rtcEpoch();
    bool night = hours[t] < 6 || hours[t] >= 20;
    gNight = night;
    for (int b = 0; b < 7; b++) {
      drawScene((uint8_t)b, 20000, night);
      char path[512];
      snprintf(path, sizeof path, "%s/b%d_%s.ppm", outDir, b, names[t]);
      writePPM(path);
    }
  }
  return 0;
}
EOF

cd "$B"
g++ -std=c++17 -O1 -w -I"$B" -I"$E" -I"$R" -DSPRITE_DIR="\"$B/nosprites\"" -o scene-render \
  sketch.cpp scene_main.cpp "$E/wavout.cpp" "$R/gbsynth.cpp" "$R/cry.cpp" "$R/pet.cpp" \
  "$R/i18n.cpp" "$R/party.cpp" "$R/battle.cpp" "$R/link.cpp" "$R/save.cpp" "$R/steps.cpp" \
  "$E/host_impl.cpp" "$E/font.cpp" "$E/clock.cpp"
./scene-render "$B/nosprites" "$B/out"
echo "done: $(ls "$B/out" | wc -l) scenes in $B/out"
