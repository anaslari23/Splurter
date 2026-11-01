#!/bin/sh
# Builds Splurter.app (menu-bar agent, ad-hoc signed) next to this script.
set -e; cd "$(dirname "$0")"
swift build -c release
A=Splurter.app; rm -rf $A; mkdir -p $A/Contents/MacOS
cp .build/release/Splurter $A/Contents/MacOS/
cat > $A/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.splurter.mac</string>
<key>CFBundleName</key><string>Splurter</string>
<key>CFBundleExecutable</key><string>Splurter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Splurter talks directly to your phone on your Wi-Fi.</string>
<key>NSMicrophoneUsageDescription</key><string>Splurter uses your Mac microphone to let you talk on phone calls.</string>
<key>NSBonjourServices</key><array><string>_splurter._tcp</string></array>
</dict></plist>
PL
codesign --force -s - $A
echo "built $PWD/$A"
