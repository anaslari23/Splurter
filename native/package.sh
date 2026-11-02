#!/bin/sh
# Builds all release artifacts into native/release/ (what the GitHub release workflow publishes):
#   Splurter-<ver>.dmg, Splurter-<ver>.pkg  (Mac app, ad-hoc signed — not notarized)
#   Splurter-<ver>.apk                      (Android, signed with android/splurter-release.jks when present)
# VERSION=0.3.0 sh package.sh
set -e; cd "$(dirname "$0")"
V="${VERSION:-0.2}"; export VERSION="$V"
. ./find_java.sh
rm -rf release
sh ./package_mac.sh

(cd android && ./gradlew :app:assembleRelease -Pver="$V")
cp android/app/build/outputs/apk/release/app-release.apk "release/Splurter-$V.apk"
ls -la release
