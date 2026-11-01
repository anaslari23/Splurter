#!/bin/sh
# Starts the bridge on a live call. Usage: ADB_SERIAL=<ip:port> ./run.sh [mute=1] [vol=0]
# Wear headphones on the Mac (no echo cancellation yet). Stop with Ctrl-C / by ending the call.
set -e; cd "$(dirname "$0")"
S="${ADB_SERIAL:?set ADB_SERIAL to the phone, e.g. 192.168.0.134:43633}"; PORT=27300
adb -s "$S" push helper/bridge.dex /data/local/tmp/bridge.dex >/dev/null
adb -s "$S" push scrcpy-server.jar /data/local/tmp/scrcpy-server.jar >/dev/null
pkill -x cbmac 2>/dev/null || true; adb -s "$S" shell "pkill -f Bridge" 2>/dev/null || true; sleep 1
adb -s "$S" forward tcp:$PORT localabstract:splurter_bridge_$PORT >/dev/null
(adb -s "$S" shell "CLASSPATH=/data/local/tmp/scrcpy-server.jar:/data/local/tmp/bridge.dex app_process / Bridge $PORT ${1:-mute=1} ${2:-vol=0}" > /tmp/bridge_phone.log 2>&1 &)
for i in 1 2 3 4 5 6 7 8 9 10; do grep -q listening /tmp/bridge_phone.log 2>/dev/null && break; sleep 1; done
open mac/CBMac.app --args $PORT
echo "phone log: /tmp/bridge_phone.log   Mac log: /tmp/cbmac.log"
