#!/bin/bash
# Every region for every watch: for each region, tools/make_region.py, tools/make_scaled.py and
# tools/build_all.sh, then its builds into bin/release/TamaWatch-<region>-<device>.prg (the files
# of a GitHub release; the download page links to releases/latest/download/<that name>). Ends with
# the copy back on Kanto.
#
# usage: tools/make_release.sh <TamaPoke repo> <SpriteCollab-master> [region ...]
cd "$(dirname "$0")/.."
TP="$1"; SC="$2"; shift 2
regions="$*"
[ -z "$regions" ] && regions="kanto johto hoenn sinnoh unova kalos alola"
mkdir -p bin/release
for r in $regions; do
    echo "== $r $(date +%H:%M)"
    python3 tools/make_region.py $r "$TP" "$SC" . > /dev/null || { echo "make_region $r failed"; exit 1; }
    python3 -W ignore tools/make_scaled.py . > /dev/null || exit 1
    rm -rf bin/devices
    tools/build_all.sh | grep -v "^ok"
    rm -f bin/release/TamaWatch-$r-*.prg
    n=0; missing=""
    for d in $(grep -ho 'iq:product id="[^"]*"' manifest.xml manifest-app.xml manifest-new.xml | cut -d'"' -f2); do
        if [ -f bin/devices/$d/TamaWatch.prg ]; then
            cp bin/devices/$d/TamaWatch.prg bin/release/TamaWatch-$r-$d.prg; n=$((n+1))
        else
            missing="$missing $d"
        fi
    done
    echo "$r: $n files"; [ -n "$missing" ] && echo "$r not built:$missing"
done
if [ "$(cat REGION.txt)" != "kanto" ]; then
    python3 tools/make_region.py kanto "$TP" "$SC" . > /dev/null && python3 -W ignore tools/make_scaled.py . > /dev/null
fi
ls bin/release | wc -l; du -sh bin/release
