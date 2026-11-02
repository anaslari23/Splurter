#!/bin/sh
# Builds Splurter.app (menu-bar agent, ad-hoc signed) next to this script.
set -e; cd "$(dirname "$0")"
# Call-audio helper (phone side) + scrcpy's server jar (checksum-verified), bundled as resources.
../callbridge/build_helper.sh
[ -f ../callbridge/scrcpy-server.jar ] || ../callbridge/fetch_scrcpy_server.sh
swift build -c release
A=Splurter.app; rm -rf $A; mkdir -p $A/Contents/MacOS
mkdir -p $A/Contents/Resources
cp .build/release/Splurter $A/Contents/MacOS/
cp ../icons/AppIcon.icns $A/Contents/Resources/
cp ../callbridge/helper/bridge.dex ../callbridge/scrcpy-server.jar ../callbridge/THIRD_PARTY_NOTICES.txt $A/Contents/Resources/
cat > $A/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.splurter.desktop</string>
<key>CFBundleName</key><string>Splurter</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>Splurter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION:-0.2}</string>
<key>CFBundleVersion</key><string>${VERSION:-0.2}</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Splurter talks directly to your phone on your Wi-Fi.</string>
<key>NSMicrophoneUsageDescription</key><string>Splurter uses your Mac microphone to let you talk on phone calls.</string>
<key>NSBonjourServices</key><array><string>_splurter._tcp</string></array>
</dict></plist>
PL
codesign --force -s - $A
echo "built $PWD/$A"
if [ "$1" = "--install" ]; then
  LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  pkill -x Splurter || true; sleep 1
  rm -rf /Applications/Splurter.app && ditto $A /Applications/Splurter.app
  $LSR -f /Applications/Splurter.app
  # Only the installed copy may own the bundle id, or Notification Center can pick a stale one and show a blank icon.
  rm -rf "$A"; $LSR -u "$PWD/$A" 2>/dev/null || true
  echo "installed /Applications/Splurter.app"
fi
