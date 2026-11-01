#!/bin/sh
# Builds release artifacts into native/release/:
#   Splurter-<ver>.dmg  (Mac app, ad-hoc signed — not notarized)
#   Splurter-<ver>.apk  (Android, signed with android/splurter-release.jks)
set -e; cd "$(dirname "$0")"
V=0.2
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
rm -rf release && mkdir -p release/dmg

(cd mac && ./build_app.sh)
cp -R mac/Splurter.app release/dmg/ && ln -s /Applications release/dmg/Applications
hdiutil create -volname Splurter -srcfolder release/dmg -ov -format UDZO release/Splurter-$V.dmg >/dev/null
rm -rf release/dmg
rm -rf mac/Splurter.app; $LSR -u "$PWD/mac/Splurter.app" 2>/dev/null || true # a stray build copy confuses Notification Center's icon cache

(cd android && ./gradlew :app:assembleRelease)
cp android/app/build/outputs/apk/release/app-release.apk release/Splurter-$V.apk
ls -la release
