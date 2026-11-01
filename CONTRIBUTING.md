# Contributing

Thanks for helping. Splurter is two native apps that speak one protocol, so most changes touch both sides.

## Setup

- macOS with Xcode (Swift 6 toolchain, macOS 15 SDK). Built and tested with Xcode 27.
- Android Studio, for its JDK and SDK. Point `JAVA_HOME` at `/Applications/Android Studio.app/Contents/jbr/Contents/Home`.
- An Android 13+ phone and a Mac on the same Wi-Fi. For development, wireless debugging (`adb pair` / `adb connect`) is convenient.

```bash
cd native/mac && ./build_app.sh --install     # build and install the Mac app into /Applications
cd native/android && ./gradlew :app:installDebug
```

Always install the Mac app with `--install`: it keeps a single registered copy of the app, because extra copies on disk make macOS Notification Center show a blank icon.

## Where things live

| Area | Mac | Android |
|---|---|---|
| Connection, handshake, framing | `Link.swift`, `Crypto.swift` | `Link.kt` |
| Notifications | `Notifier.swift` | `NotifService.kt` |
| Calls and texts | `Link.swift`, `CallPanel.swift` | `Phone.kt` |
| Files | `Link.swift` | `Files.kt`, `ShareActivity.kt` |
| Mirroring and control | `Mirror.swift` | `Mirror.kt`, `Control.kt` |
| Call audio (prototype) | `native/callbridge/mac/main.swift` | `native/callbridge/helper/Bridge.java` (runs as the adb shell user) |
| UI | `App.swift` | `Ui.kt`, `MainActivity.kt` |

If you change the wire format, update [docs/PROTOCOL.md](docs/PROTOCOL.md) and, for an incompatible change, bump `v` in the QR payload and the HKDF `info` string on both sides.

## Release builds

`native/package.sh` builds the DMG and the APK. The APK is signed from `native/android/keystore.properties` (git-ignored):

```
storeFile=splurter-release.jks
storePassword=...
keyAlias=splurter
keyPassword=...
```

Create the keystore with `keytool -genkeypair -keystore native/android/splurter-release.jks -alias splurter -keyalg RSA -keysize 2048 -validity 10000`. Never commit either file. Without them the release APK falls back to the debug signature.

## Pull requests

- Keep changes small and focused; say what you tested on which devices.
- Be honest about what is untested. This project talks to real phones and Macs and a lot of behaviour only shows up there.
- No secrets, keystores or personal screenshots (notifications and screen mirroring show private content).
