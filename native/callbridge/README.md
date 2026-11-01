# Call audio bridge (prototype)

Talk on a **cellular call through the Mac**: the caller's voice plays on the Mac, and the Mac microphone goes into the call. No hardware, no root. It runs a small helper on the phone with the **adb shell user's privileges** (started over wireless debugging).

**Status:** works on one device (Pixel 9a, Android 17) on a real call, confirmed by the person on the other end: clear voice both ways. Not yet integrated into the Splurter apps.

## Why apps can't do this, and the shell user can
- App microphone capture is silenced by Android during cellular calls (exact zeros).
- Bluetooth hands-free audio on macOS is refused by the OS, and the Mac's Bluetooth controller rejects the connection timing Android's hearing-aid protocol requires (both tried, see the repo history).
- The shell user holds permissions apps cannot get: `CAPTURE_AUDIO_OUTPUT`, `CALL_AUDIO_INTERCEPTION`, `MODIFY_PHONE_STATE`, `MODIFY_AUDIO_ROUTING`.

## How it works
| Direction | Mechanism |
|---|---|
| Caller → Mac | `AudioRecord` with source `VOICE_DOWNLINK` (3). |
| Mac → caller | `AudioTrack` with the **system usage `USAGE_CALL_ASSISTANT` (17)**. Android's audio policy maps it to `STRATEGY_CALL_ASSISTANT` → `AUDIO_DEVICE_OUT_TELEPHONY_TX`, the call uplink. (`VOICE_COMMUNICATION`, `MEDIA`, `UNKNOWN` and `FLAG_CALL_REDIRECTION` all go to the speaker instead.) |
| Phone mic | Muted with `setMicrophoneMute(true)` so only the Mac voice reaches the caller. Restored on exit. |

Transport: PCM16 mono 16 kHz, both ways, over an abstract Unix socket on the phone, forwarded to the Mac with `adb forward`.

**Getting an audio client as the shell user** needs scrcpy's setup code (the plain `AudioRecord` constructor fails with "Could not get audioflinger"). The helper is run with scrcpy's server jar on its classpath and calls `Workarounds.apply()`, `FakeContext`, and the hidden `AudioRecord.Builder.setContext(...)`. The system usage needs the hidden `AudioAttributes.Builder.setSystemUsage(17)` (the public `setUsage(17)` throws "Invalid usage 17"). scrcpy is Apache-2.0: https://github.com/Genymobile/scrcpy.

## Tuning that mattered (measured, not guessed)
- **Mac mic level.** An earbud mic was already at ~0.30 RMS; extra gain clipped 56% of speech and sounded hazy. The Mac client now steers toward ~0.10 RMS (cuts fast, recovers slowly, soft limiter): 0% clipping.
- **No macOS voice processing** on the mic path; it squashed and chopped speech. (On macOS 27 it cannot run together with playback in one engine anyway.)
- **Jitter buffers.** Wireless adb and Android's capture arrive in bursts. Mac playback starts at 150 ms stored, skips ahead only past 500 ms. Phone uplink prebuffers ~100 ms, fills gaps with silence, and keeps a short ~80 ms track buffer.
- **Headphones required** on the Mac: there is no echo cancellation, so speakers would feed the caller back into the mic.

## Run it
```bash
./fetch_scrcpy_server.sh              # downloads scrcpy-server.jar and checks its SHA-256
./build.sh                            # helper/bridge.dex and mac/CBMac.app
ADB_SERIAL=<phone-ip:port> ./run.sh   # start a call first; wireless debugging must be paired and connected
```
Logs: `/tmp/bridge_phone.log` (phone helper) and `/tmp/cbmac.log` (Mac client; `CB_RECORD=1` also saves the mic before/after gain to `/tmp` for analysis).

## Debugging tips
- `adb shell dumpsys media.audio_policy` shows strategies, the `in-call-playback` output and `telephony-tx/rx`.
- Uncaught exceptions in `app_process` just print `Killed`; the helper catches and prints them.
- Dual-SIM phones: `dumpsys telephony.registry` has several `mCallState` lines (the call may be on slot 2).
- scrcpy's server deletes its own jar when it exits unless started with `cleanup=false`.

## Known limits / before shipping
- One device and one Android version tested. Vendor builds may differ.
- Needs wireless debugging on, re-paired after phone reboots; the Mac app would need to drive `adb` (pairing code) and bundle or locate it.
- **Harden the socket:** it is a fixed abstract socket name with no authentication. Use a random per-session name plus a token before shipping.
- No echo cancellation, no reconnect handling, no automatic start/stop with the call.
- The phone's local call volume is left alone (`vol=1` lowers it; untested for quality).
