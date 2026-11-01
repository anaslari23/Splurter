#!/bin/sh
# Downloads scrcpy's server jar (Apache-2.0, https://github.com/Genymobile/scrcpy) and verifies its SHA-256.
# The helper reuses scrcpy's shell-user audio setup (Workarounds / FakeContext) instead of reimplementing it.
set -e; cd "$(dirname "$0")"
V=v5.0.1; SHA=764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536
curl -fL -o scrcpy-server.jar "https://github.com/Genymobile/scrcpy/releases/download/$V/scrcpy-server-$V"
echo "$SHA  scrcpy-server.jar" | shasum -a 256 -c -
