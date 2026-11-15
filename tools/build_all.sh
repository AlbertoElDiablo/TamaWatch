#!/bin/bash
# Builds TamaWatch for every supported watch: bin/devices/<device>/TamaWatch.prg (and bin/TamaWatch.prg
# for the fenix 6X Pro). manifest.xml lists the widget builds, manifest-app.xml the watches that get
# it as an app (512 KB for a widget there). Two builds at a time; screens of 390 px (pictures
# resized for them, a bigger build) one at a time with more memory for the compiler.
#
# usage: tools/build_all.sh [device ...]     (no devices: all of them)
cd "$(dirname "$0")/.."
export PATH=~/.connectiq/jdk/bin:$PATH
SDK=$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)
DEV=~/Library/Application\ Support/Garmin/ConnectIQ/Devices
one() {
    d=$1; heap=$2
    jungle=monkey.jungle
    grep -q "\"$d\"" manifest-app.xml && jungle=monkey-app.jungle
    grep -q "\"$d\"" manifest-new.xml && jungle=monkey-new.jungle
    mkdir -p bin/devices/$d
    if _JAVA_OPTIONS=-Xmx$heap "$SDK/bin/monkeyc" -d $d -f $jungle -o bin/devices/$d/TamaWatch.prg -y ~/.connectiq/developer_key.der > bin/devices/$d/build.log 2>&1 \
       && grep -q "BUILD SUCCESSFUL" bin/devices/$d/build.log; then
        rm -f bin/devices/$d/TamaWatch.prg.debug.xml bin/devices/$d/build.log; echo "ok   $d"
    else
        echo "FAIL $d (bin/devices/$d/build.log)"
    fi
}
export -f one; export SDK
all="$*"
[ -z "$all" ] && all=$(grep -ho 'iq:product id="[^"]*"' manifest.xml manifest-app.xml manifest-new.xml | cut -d'"' -f2)
big=""; small=""
for d in $all; do
    if grep -q '"round-390x390"' "$DEV/$d/compiler.json"; then big="$big $d"; else small="$small $d"; fi
done
echo $small | tr ' ' '\n' | grep . | xargs -P 2 -I{} bash -c 'one {} 3g'
for d in $big; do one $d 5g; done
[ -f bin/devices/fenix6xpro/TamaWatch.prg ] && cp bin/devices/fenix6xpro/TamaWatch.prg bin/TamaWatch.prg
echo done
