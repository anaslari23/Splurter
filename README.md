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
| **Notifications** | Phone notifications appear as native Mac banners with the app's icon. Dismiss on the Mac clears them on the phone. Reply from the banner for apps that offer inline reply. | ✅ ² |
| **Calls** | Incoming-call popup on the Mac with the caller's name and Answer or Decline. Dial from the Mac. | ✅ |
| **Texts** | Send an SMS from the Mac. Incoming texts arrive as notifications. | ✅ |
| **Files** | Drag files onto the menu-bar popover to send to the phone. Share from the phone to send to the Mac. | ✅ |
| **Screen mirroring + control** | Live phone screen in a Mac window. Click, drag, scroll and type into it. Needs your explicit approval on the phone each time. | ✅ |
| **Call audio on the Mac** | Talk on a call through the Mac. | ⛔ blocked by Android ³ |
| **Phone as webcam** | Use the phone camera as a Mac camera. | ⏳ not built ⁴ |

¹ Android 10+ blocks background clipboard reads, so phone to Mac is deliberately a button or share action.
² Reply was built but is untested against a real chat app. Apps must expose an inline-reply action.
³ The audio bridge itself works (it streams both ways), but Android feeds apps silence from the microphone during a cellular call. See [Known limits](#known-limits).
⁴ Needs a macOS Camera Extension, which must be signed with an Apple Developer team ID.

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
| Hands-free call audio | Microphone permission (experimental) |

**Screen control** is an Android accessibility service. For a sideloaded app Android blocks it until you open Settings, Apps, Splurter, the **⋮** menu, **Allow restricted settings**, then Settings, Accessibility, Splurter, switch on. The phone only acts on remote input while a mirroring session you approved is running.

## Pair

1. Click the Splurter icon in the Mac menu bar and choose **Pair a phone** (a window with a QR code opens on first run).
2. In the phone app, tap **Scan QR code** and point it at the Mac screen.

Done. After that, both apps reconnect on their own whenever they are on the same network.

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
  mac/        Swift package + build_app.sh   (Link, Crypto, Notifier, Mirror, AudioBridge, App UI)
  android/    Gradle project                 (Link, NotifService, Phone, Files, Mirror, Control, Audio, Compose UI)
  icons/      make_icons.swift               (generates the Mac .icns and the Android icon layers)
  package.sh  release packaging
docs/         protocol and project docs
```

## Known limits

- **Call audio.** Android does not let apps tap or inject cellular call audio. The bridge is acoustic (phone microphone to Mac, Mac voice out of the phone speaker), and during a real call Android returned silence from the microphone. With Screen control (an accessibility service) running, every microphone source still returned silence. A helper running with `adb shell` privileges, which could in principle read the call audio directly, also failed on Android 17: even a plain `AudioRecord` from the shell cannot reach AudioFlinger (`Could not get audioflinger`). The per-source probe is behind `AudioService.PROBE`. Bluetooth Hands-Free was also tried: the Mac can connect to the phone as a hands-free unit (Apple's `IOBluetoothHandsFreeDevice`) and tracks calls through it, but macOS refuses to open the call audio channel in that role (`kIOReturnUnsupported`). The remaining idea is a USB Bluetooth dongle with a userspace stack such as BTstack; it is untried.
- **macOS 27 audio engine.** Voice processing and playback cannot run in one `AVAudioEngine` on macOS 27 (error -10875), so capture and playback use separate engines.
- **Clipboard.** Phone to Mac cannot be automatic on Android 10+.
- **Mirroring.** The video size is fixed when a session starts (rotating the phone mid-session is not handled). Secure screens such as banking apps block capture by design. Dragging is sent on release rather than live.
- **Typing into the mirror** appends to or deletes from the end of the focused field (no cursor positioning).
- **Single Mac per phone**, and one active phone connection at a time on the Mac.
- **Untested:** switching Wi-Fi networks, and replying to a real chat notification.

## Troubleshooting

- **Screen control won't switch on.** Allow restricted settings first (see Install). Reinstalling the app switches accessibility services off again.
- **No banners on the Mac.** Allow notifications for Splurter in System Settings, Notifications, and check Focus modes.
- **Blank icon on banners.** macOS caches notification icons per bundle ID and per registered copy of the app. Use `./mac/build_app.sh --install`, which keeps a single registered copy.
- **Phone does not reconnect.** Both devices must be on the same network and the Mac app must be running. Android reconnects with backoff up to 30 seconds.
- **Android stops the service** on aggressive vendor skins: exempt Splurter from battery optimisation.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

MIT, see [LICENSE](LICENSE).
