#!/bin/sh
# Builds helper/bridge.dex (the phone-side helper). Needs a JDK and the Android SDK (android.jar, d8).
set -e; cd "$(dirname "$0")"
. ../find_java.sh; J="$JAVA_HOME"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"; AJ=$(ls -d "$SDK"/platforms/android-*/android.jar | tail -1); D8=$(ls -d "$SDK"/build-tools/*/d8 | tail -1)
rm -rf helper/out helper/dex; mkdir -p helper/out helper/dex
"$J/bin/javac" --release 11 -cp "$AJ" -d helper/out helper/Bridge.java
"$D8" --lib "$AJ" --output helper/dex helper/out/*.class && mv helper/dex/classes.dex helper/bridge.dex && rm -rf helper/out helper/dex
echo "built helper/bridge.dex"
