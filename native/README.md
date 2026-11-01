# Splurter (native)

Android ↔ Mac Continuity: pair once with a QR code, then clipboard, notifications (with reply), calls, texts, files and screen mirroring work over a direct, encrypted Wi-Fi link. No cloud, no account.

- `mac/` — Swift/SwiftUI menu-bar app. `./build_app.sh` builds `Splurter.app` (macOS 15+).
- `android/` — Kotlin/Compose app. `./gradlew :app:assembleDebug` (needs Android Studio's JDK).

## Protocol
TCP, Bonjour `_splurter._tcp` for discovery. Handshake: phone sends `ephPub(32) | mode(1) | staticPub(32)`, Mac replies `ephPub(32)`; keys = HKDF-SHA256 over four X25519 DHs (salt = QR token when pairing). Then frames `[len:4 BE][ChaCha20-Poly1305 ciphertext]` whose plaintext starts with a type byte: `0` JSON message, `1` file chunk, `2` video.

Mac: `Crypto.swift` (session), `Link.swift` (connection + messages), `Notifier.swift`, `App.swift` (UI). Android: `Link.kt` (connection), `Service.kt`, `NotifService.kt`, `Phone.kt`, `Files.kt`, `Ui.kt`.
