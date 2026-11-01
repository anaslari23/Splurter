#!/bin/sh
# Builds helper/bridge.dex (phone side) and mac/CBMac.app (Mac side). Needs Android Studio (JDK, SDK) and Xcode.
set -e; cd "$(dirname "$0")"
./build_helper.sh
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
