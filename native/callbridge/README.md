# Call audio bridge

Talk on a **cellular call through the Mac**: the caller plays on the Mac, and the Mac microphone goes into the call. No hardware, no root. A small helper runs on the phone with the **adb shell user's privileges** (started over wireless debugging).

**Status:** beta. It is built into the Splurter Mac app (**Use Mac audio** on the call card; see `CallAudio.swift`, `Adb.swift`, `CallAudioSetup.swift`). This folder holds the phone-side helper (`helper/Bridge.java`, bundled into the app by `build_app.sh`) and a standalone dev client (`mac/main.swift`, `run.sh`) that is handy for experiments. Confirmed on a Pixel 9a (Android 17) on real calls; not tested elsewhere.

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
Helper arguments: `name=<socket> token=<secret> wait=<seconds> mute=0|1 vol=0|1`. Handshake from the client: the token bytes, then one `0x01` "ready" byte once its audio engines run; the helper starts capturing only then (so no audio queues in the adb pipe while the Mac starts). Wrong or missing token: the client is dropped; with no client in `wait` seconds the helper exits.

**Getting an audio client as the shell user** needs scrcpy's setup code (the plain `AudioRecord` constructor fails with "Could not get audioflinger"). The helper is run with scrcpy's server jar on its classpath and calls `Workarounds.apply()`, `FakeContext`, and the hidden `AudioRecord.Builder.setContext(...)`. The system usage needs the hidden `AudioAttributes.Builder.setSystemUsage(17)` (the public `setUsage(17)` throws "Invalid usage 17"). scrcpy is Apache-2.0: https://github.com/Genymobile/scrcpy.

## Tuning that mattered (measured, not guessed)
- **No macOS voice processing** on the mic path; it squashed and chopped speech. (On macOS 27 it cannot run together with playback in one engine anyway.)
- **Jitter buffers with drift compensation.** Wireless adb and Android's capture arrive in bursts, and the clocks differ (the phone's caller capture ran ~4% fast, so a fixed buffer overflowed every ~3 s). Both ends steer the buffer toward ~150 ms by playing a little faster or slower (linear interpolation, +8% / -2%) and only skip ahead past 1 s.
- **No startup backlog.** The ready byte (above) fixed ~1 s of caller audio piling up while the Mac started; the Mac buffer now stays near 200 ms from the first second.
- **Level control.** The Mac mic level is steered to ~0.12 RMS with up to 12x gain for quiet mics (a MacBook's built-in mic is ~0.02 RMS) and cuts for hot ones; a soft limiter replaces hard clipping.
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

## Known limits
- One device and one Android version tested. Vendor builds may differ.
- Needs wireless debugging on. Android can switch it off by itself; the Mac app restarts adb and retries, then asks the user to turn it back on.
- No echo cancellation, so headphones are needed. Bluetooth headphones add ~0.25 s; a MacBook's built-in mic is quiet.
- The call-assistant volume group (separate from the call volume) is deliberately left alone: measured, the uplink matched the level we sent at its default.
- Reconnect handling is basic: if the adb link drops, call audio stops and can be started again.
