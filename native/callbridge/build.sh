#!/bin/sh
# Builds helper/bridge.dex (phone side) and mac/CBMac.app (Mac side). Needs Android Studio (JDK, SDK) and Xcode.
set -e; cd "$(dirname "$0")"
J="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"; export JAVA_HOME="$J"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"; AJ=$(ls -d "$SDK"/platforms/android-*/android.jar | tail -1); D8=$(ls -d "$SDK"/build-tools/*/d8 | tail -1)
rm -rf helper/out helper/dex; mkdir -p helper/out helper/dex
"$J/bin/javac" --release 11 -cp "$AJ" -d helper/out helper/Bridge.java
"$D8" --lib "$AJ" --output helper/dex helper/out/*.class && mv helper/dex/classes.dex helper/bridge.dex && rm -rf helper/out helper/dex
cd mac; swiftc -O main.swift -o cbmac
rm -rf CBMac.app; mkdir -p CBMac.app/Contents/MacOS; cp cbmac CBMac.app/Contents/MacOS/; rm cbmac
cat > CBMac.app/Contents/Info.plist <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.splurter.callbridge</string><key>CFBundleName</key><string>CBMac</string>
<key>CFBundleExecutable</key><string>cbmac</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Talk on your phone call through this Mac.</string>
</dict></plist>
PL
codesign --force -s - CBMac.app; echo "built helper/bridge.dex and mac/CBMac.app"
