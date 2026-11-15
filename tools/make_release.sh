#!/bin/bash
# Gathers every watch's build (tools/build_all.sh) into bin/release/TamaWatch-<device>.prg, the
# files of a GitHub release (the download page links to releases/latest/download/<that name>).
#
# usage: tools/make_release.sh
cd "$(dirname "$0")/.."
rm -rf bin/release; mkdir -p bin/release
n=0; missing=""
for d in $(grep -ho 'iq:product id="[^"]*"' manifest.xml manifest-app.xml manifest-new.xml | cut -d'"' -f2); do
    if [ -f bin/devices/$d/TamaWatch.prg ]; then
        cp bin/devices/$d/TamaWatch.prg bin/release/TamaWatch-$d.prg; n=$((n+1))
    else
        missing="$missing $d"
    fi
done
echo "$n files in bin/release"; [ -n "$missing" ] && echo "not built:$missing"
du -sh bin/release
