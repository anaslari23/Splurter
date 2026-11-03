<p align="center"><img src="docs/icon.png" width="128" alt="Splurter"></p>

<h1 align="center">Splurter</h1>

<p align="center"><b>Continuity for Android and Mac.</b><br>
Scan a QR code once. Your phone's clipboard, notifications, calls, texts, files and screen then work with your Mac,
directly over your Wi-Fi, end-to-end encrypted. No account and no cloud.</p>

---

## What it does

| Feature | What you get | Status |
|---|---|---|
| **Pairing** | One QR scan, then it reconnects by itself (Bonjour discovery; verified across app restarts and a phone reboot). | ✅ |
| **Clipboard** | Copy on the Mac and paste on the phone. Phone to Mac with a button or the share sheet. | ✅ ¹ |
| **Media & volume** | Now-playing card on the Mac with cover art, a draggable progress bar, play/pause/next/previous, a switcher between players, and a volume slider that follows the phone's volume keys. | ✅ |
| **Notifications** | Phone notifications appear as native Mac banners with the app's icon. Dismiss on the Mac clears them on the phone. Reply from the banner for apps that offer inline reply. | ✅ ² |
| **Calls** | Incoming-call popup on the Mac with the caller's name and Answer or Decline. Dial from the Mac. | ✅ |
| **Texts** | Send an SMS from the Mac. Incoming texts arrive as notifications. | ✅ |
| **Files** | Drag files onto the menu-bar popover to send to the phone. Share from the phone to send to the Mac. | ✅ |
| **Phone on your Mac** | A Mac window shaped like your phone (its corner radius and camera hole; it turns sideways when an app rotates). Your phone's apps run on a separate virtual screen shown here, with a small home screen of its own, so the phone itself stays free in your hand. Unlock the phone once to start. If you then lock it, the phone stays awake behind a dark panel so the Mac keeps working; press the power button again to get it back. Click, drag, scroll and type. A right-click menu on the bar can instead mirror the phone's real screen. Needs Wireless debugging (the same setup as call audio); without it, a basic screen-share mirror (approved on the phone each time) is the fallback. | ✅ |
| **Call audio on the Mac** | Talk on a cellular call through the Mac: the caller plays on the Mac and your Mac mic goes into the call. | 🧪 beta ³ |
| **Phone as webcam** | Use the phone camera as a Mac camera. | ⏳ not built ⁴ |

¹ Android 10+ blocks background clipboard reads, so phone to Mac is deliberately a button or share action.
² Reply was built but is untested against a real chat app. Apps must expose an inline-reply action.
³ Works on a real call (Pixel 9a, Android 17) after a one-time Wireless debugging setup, with no extra hardware and no root. Tested on one phone. See [Call audio](#call-audio-beta).
⁴ Needs a macOS Camera Extension, which must be signed with an Apple Developer team ID.

## Screenshots

<p>
  <img src="docs/images/popover.png" alt="The Splurter menu-bar popover on the Mac: now playing with seek and volume, actions, recent activity" width="300">
  <img src="docs/images/phone-window.png" alt="The phone window on the Mac: the virtual phone's home screen" width="300">
  <img src="docs/images/phone-window-app.png" alt="An app (Settings) running in the phone window" width="300">
</p>

The menu-bar popover (left) is from a real Pixel 9a connected to a Mac. The phone window (middle and right) shows the virtual screen's content, captured on an Android emulator so that nothing personal is shown.

## How it works

```
 Android (Kotlin / Compose)                           macOS (Swift / SwiftUI)
 ┌──────────────────────────┐   Bonjour _splurter._tcp   ┌──────────────────────────┐
 │ foreground service        │ ◄────────────────────────► │ menu-bar app             │
 │ notification listener     │   direct TCP on your LAN   │ native banners + popup   │
 │ call / SMS / files        │   X25519 · ChaCha20-Poly1305│ clipboard · mirror window│
 │ MediaProjection (mirror)  │ ◄────────────────────────► │ VideoToolbox decode      │
 └──────────────────────────┘      one multiplexed link    └──────────────────────────┘
```

The Mac shows a QR code holding its address, a public key and a single-use token. The phone scans it, and both sides derive session keys with four X25519 key agreements. After pairing each side remembers the other's key, so reconnecting needs no QR. Everything (messages, files, video) travels as encrypted frames on that one link. Details: [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Install

Build the artifacts yourself (see [Build](#build)); there are no prebuilt releases yet.

**Mac** (macOS 15+): open `Splurter-<version>.dmg` and drag Splurter to Applications. The app is ad-hoc signed and not notarized, so the first launch needs right-click, then Open (or System Settings, Privacy & Security, Open Anyway). Allow notifications when asked.

**Android** (13+): install `Splurter-<version>.apk` (allow installs from your file manager or browser). Open the app and use the **Features** list to grant what you want:

| Feature | What to enable |
|---|---|
| Notifications | Notification access for Splurter |
| Calls, Texts, Contacts | The phone, SMS and contacts permissions |
| Screen control | Accessibility service (see below) |

**Screen control** is an Android accessibility service. For a sideloaded app Android blocks it until you open Settings, Apps, Splurter, the **⋮** menu, **Allow restricted settings**, then Settings, Accessibility, Splurter, switch on. The phone only acts on remote input while a mirroring session you approved is running.

## Pair

1. Click the Splurter icon in the Mac menu bar and choose **Pair a phone** (a window with a QR code opens on first run).
2. In the phone app, tap **Scan QR code** and point it at the Mac screen.

Done. After that, both apps reconnect on their own whenever they are on the same network.

## Call audio (beta)

Talk on a normal phone call through your Mac: the caller plays in your Mac's headphones and your Mac microphone goes into the call.

**One-time setup** (press **Use Mac audio** on the call card and the Mac app walks you through it):
1. Splurter drives Android's `adb` tool. It uses one it finds (Android Studio's or Homebrew's) or, only if you press the button, downloads Google's platform-tools (about 13 MB).
2. On the phone: Settings, Developer options, turn on **Wireless debugging**, tap **Pair device with pairing code**, and type the 6-digit code into the Mac window. (No Developer options? Tap Build number 7 times in About phone.)

**Using it:** during a call, press **Use Mac audio** in the Splurter menu (allow the microphone prompt the first time). It stops by itself when the call ends. While it runs, the phone's own microphone is muted so only your Mac voice goes out; it is unmuted afterwards.

**Best results:** wired earbuds with a microphone. Bluetooth headphones add about a quarter second of delay, a Mac's built-in mic is quiet, and Mac speakers would echo into the call (there is no echo cancellation yet). The call card shows a hint for your current setup, and the phone app has a **Call audio** row that shows whether Wireless debugging is on.

**How it works:** Android keeps cellular call audio away from apps, but the adb shell user holds permissions apps lack. Splurter starts a small helper on the phone as that user, over wireless debugging. It captures the caller (`VOICE_DOWNLINK`) and plays your voice into the call uplink using the system `CALL_ASSISTANT` usage. The helper talks to the Mac over a socket that adb forwards, with a random name and a one-time token. Details and the measurements behind the tuning: [native/callbridge/README.md](native/callbridge/README.md).

## Build

Needs Xcode (Swift 6 toolchain, macOS 15 SDK; built and tested with Xcode 27) and Android Studio (for its JDK and SDK).

```bash
cd native
./package.sh                 # builds release/Splurter-<ver>.dmg and release/Splurter-<ver>.apk
./mac/build_app.sh --install # or: build the Mac app and install it into /Applications
```

Android only: `cd native/android && ./gradlew :app:assembleDebug` (set `JAVA_HOME` to Android Studio's bundled JDK). For release builds, create `native/android/keystore.properties` and a keystore as described in [CONTRIBUTING.md](CONTRIBUTING.md); both files are git-ignored.

## Project layout

```
native/
  mac/        Swift package + build_app.sh   (Link, Crypto, Notifier, Mirror, App UI)
  android/    Gradle project                 (Link, NotifService, Phone, Files, Mirror, Control, Audio, Compose UI)
  callbridge/ phone-side call-audio helper (bundled into the Mac app) and a dev client
  icons/      make_icons.swift               (generates the Mac .icns and the Android icon layers)
  package.sh  release packaging
docs/         protocol and project docs
```

## Releases

Pushing a tag such as `v0.3.0` (or running the **Release** workflow by hand) builds everything on GitHub and publishes a release with:
the Android `.apk` and the Mac `.dmg` and `.pkg`. The installers carry a build-provenance attestation: `gh attestation verify <file> -R anaslari23/Splurter`.
The Mac app is ad-hoc signed and not notarized, so the first launch needs a right-click, **Open**. The APK is signed with the release key, which is stored only as secrets of the `release` environment (`ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` if it differs). That environment needs the owner's approval for every run and only accepts `v*` tags and `main`; without the secrets an APK is debug-signed and says so in its name.
Build the same files locally with `VERSION=0.3.0 sh native/package.sh`.

## Known limits

- **Call audio (beta).** It needs Wireless debugging, which Android can switch off by itself (after a Wi-Fi change or a reboot); the app restarts adb once and retries, then asks you to turn it back on. It has only been tested on one phone (Pixel 9a, Android 17), and other makers' builds may differ. No echo cancellation, so use headphones. Bluetooth routes were also tried and do not work on macOS: it refuses hands-free call audio, and its Bluetooth controller rejects the connection timing Android's hearing-aid protocol demands.
- **macOS 27 audio engine.** Voice processing and playback cannot run in one `AVAudioEngine` on macOS 27 (error -10875), so call audio uses separate capture and playback engines (and macOS voice processing stayed off).
- **Clipboard.** Phone to Mac cannot be automatic on Android 10+.
- **Phone on your Mac.** Needs Wireless debugging (same limits as call audio) and has only been tested on a Pixel 9a (Android 17). The virtual screen needs Android support for secondary displays, and some apps may not behave on a second screen. Android only offers a dock-style launcher on a second screen, so the home screen is Splurter's own (no widgets, folders or your icon layout). While the phone is locked and held awake, Splurter raises its screen-off timeout and restores it afterwards. A phone short of memory can be slow to start the helper (the Mac app times out after 25 seconds). Not tried with a PIN-locked phone or on secure screens. The basic fallback mirror fixes its video size at start (no rotation).
- **Typing into the mirror** appends to or deletes from the end of the focused field (no cursor positioning).
- **Single Mac per phone**, and one active phone connection at a time on the Mac.
- **Untested:** switching Wi-Fi networks, and replying to a real chat notification.

## Troubleshooting

- **Screen control won't switch on.** Allow restricted settings first (see Install). Reinstalling the app switches accessibility services off again.
- **No banners on the Mac.** Allow notifications for Splurter in System Settings, Notifications, and check Focus modes.
- **Blank icon on banners.** macOS caches notification icons per bundle ID and per registered copy of the app. Use `./mac/build_app.sh --install`, which keeps a single registered copy.
- **Phone does not reconnect.** Both devices must be on the same network and the Mac app must be running. Android reconnects with backoff up to 30 seconds.
- **Android stops the service** on aggressive vendor skins: exempt Splurter from battery optimisation.

- **"Use Mac audio" says the phone isn't reachable.** Turn Wireless debugging on again (Developer options) with the phone on the same Wi-Fi as the Mac. If it was paired before, there is no need to pair again.
- **Something else is wrong with call audio.** The app logs each step to `~/Library/Application Support/Splurter/call-audio.log`.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

MIT, see [LICENSE](LICENSE).
