#!/bin/sh
# Builds the Mac installers into native/release/:
#   Splurter-<ver>.dmg  (drag-to-Applications disk image)
#   Splurter-<ver>.pkg  (double-click installer, installs to /Applications)
# The app is ad-hoc signed, not notarized (no Apple Developer account yet): macOS asks for a right-click, Open on first launch.
# VERSION=0.3.0 sh package_mac.sh
set -e; cd "$(dirname "$0")"
V="${VERSION:-0.2}"; export VERSION="$V"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
mkdir -p release; rm -rf release/stage "release/Splurter-$V.dmg" "release/Splurter-$V.pkg"
mkdir -p release/stage/dmg release/stage/pkgroot/Applications

(cd mac && ./build_app.sh)
cp -R mac/Splurter.app release/stage/dmg/ && ln -s /Applications release/stage/dmg/Applications
cp -R mac/Splurter.app release/stage/pkgroot/Applications/

hdiutil create -volname Splurter -srcfolder release/stage/dmg -ov -format UDZO "release/Splurter-$V.dmg" >/dev/null
# --root (not --component) so the installer never "relocates" onto a stray copy of the app elsewhere on the disk
pkgbuild --root release/stage/pkgroot --identifier app.splurter.desktop.pkg --version "$V" --install-location / release/stage/Splurter-component.pkg >/dev/null
productbuild --package release/stage/Splurter-component.pkg "release/Splurter-$V.pkg" >/dev/null

rm -rf release/stage mac/Splurter.app; $LSR -u "$PWD/mac/Splurter.app" 2>/dev/null || true # a stray build copy confuses Notification Center's icon cache
ls -la release | grep Splurter
