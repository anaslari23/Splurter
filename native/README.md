# Splurter (native)

Android ↔ Mac Continuity: pair once with a QR code, then clipboard, notifications (with reply), calls, texts, files and screen mirroring work over a direct, encrypted Wi-Fi link. No cloud, no account.

- `mac/` — Swift/SwiftUI menu-bar app. `./build_app.sh` builds `Splurter.app` (macOS 15+).
- `android/` — Kotlin/Compose app. `./gradlew :app:assembleDebug` (needs Android Studio's JDK).

## Protocol
TCP, Bonjour `_splurter._tcp` for discovery. Handshake: phone sends `ephPub(32) | mode(1) | staticPub(32)`, Mac replies `ephPub(32)`; keys = HKDF-SHA256 over four X25519 DHs (salt = QR token when pairing). Then frames `[len:4 BE][ChaCha20-Poly1305 ciphertext]` whose plaintext starts with a type byte: `0` JSON message, `1` file chunk, `2` video.

Mac: `Crypto.swift` (session), `Link.swift` (connection + messages), `Notifier.swift`, `App.swift` (UI). Android: `Link.kt` (connection), `Service.kt`, `NotifService.kt`, `Phone.kt`, `Files.kt`, `Ui.kt`.

## Install a release
`./package.sh` builds `release/Splurter-<ver>.dmg` and `release/Splurter-<ver>.apk`.

- **Mac:** open the DMG, drag Splurter to Applications. It is ad-hoc signed, not notarized, so the first launch needs right-click → Open (or System Settings → Privacy & Security → Open Anyway). Allow notifications when asked.
- **Android:** install the APK (allow "install unknown apps" for your file manager or browser). Then enable the features you want in the app. **Screen control** is an accessibility service: Settings → Apps → Splurter → ⋮ → Allow restricted settings, then Settings → Accessibility → Splurter.
- Pair: Mac menu bar icon → Pair, then Scan QR code in the phone app.

The release key lives in `android/splurter-release.jks` (git-ignored, with `keystore.properties`). Back it up: a new key means uninstalling the app (and re-pairing) to update it.
