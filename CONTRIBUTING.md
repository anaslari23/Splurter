# Contributing to Splurter

Thanks for helping. Splurter is two native apps that speak one encrypted protocol (a Swift menu-bar app for macOS and a Kotlin app for Android), so most changes touch both sides. Please read this page and the [Code of Conduct](CODE_OF_CONDUCT.md) before you start.

## Ways to help

- **Test on other phones.** The app has only been tested on a Pixel 9a (Android 17) and Google's emulators. Reports from Samsung, Xiaomi, OnePlus, older and foldable phones are the most valuable thing you can give (see the open "test" issues).
- **Report bugs and ideas** through [issues](https://github.com/anaslari23/Splurter/issues) (templates are provided).
- **Fix an issue.** Comment on it first so two people don't do the same work.
- **Improve docs.**

Security problems go to a private report, not a public issue: see [SECURITY.md](SECURITY.md).

## Before you start a change

1. Search the open issues. For anything bigger than a small fix, open or comment on an issue and agree on the approach first.
2. Fork the repo and create a branch from `main` (`fix/short-name`, `feat/short-name`, `docs/short-name`).
3. Keep one change per pull request. A bug fix and an unrelated refactor are two PRs.

## Setup

- A Mac with Xcode 16 or newer (Swift 6 toolchain, macOS 15 SDK). The Mac app needs macOS 15+.
- A JDK 17 and the Android SDK (Android Studio or the command-line tools). The build scripts look for a JDK on their own, or you can set `JAVA_HOME`.
- An Android 13+ phone and a Mac on the same Wi-Fi. During development, wireless debugging (`adb pair` / `adb connect`) is convenient, and it is required for the call-audio and phone-window features.

```bash
cd native/mac && ./build_app.sh --install      # build and install the Mac app into /Applications
cd native/android && ./gradlew :app:installDebug
```

Always install the Mac app with `--install`: it keeps a single registered copy, because extra copies on disk make macOS Notification Center show a blank icon.

Build the release files exactly as the release workflow does with `VERSION=0.3.0 sh native/package.sh` (Mac `.dmg` and `.pkg`, Android `.apk` in `native/release/`).

## Where things live

| Area | Mac | Android |
|---|---|---|
| Connection, handshake, framing | `Link.swift`, `Crypto.swift` | `Link.kt` |
| Notifications and the status-bar list | `Notifier.swift`, `FullMirror.swift` | `NotifService.kt` |
| Calls and texts | `Link.swift`, `CallPanel.swift` | `Phone.kt` |
| Files | `Link.swift` | `Files.kt`, `ShareActivity.kt` |
| Media controls and volume | `Link.swift`, `App.swift` | `Media.kt` |
| Phone window (virtual screen) | `FullMirror.swift`, `Adb.swift` | `PhoneHomeActivity.kt`, `Status.kt` |
| Basic screen mirror and remote control | `Mirror.swift` | `Mirror.kt`, `Control.kt` |
| Call audio (beta) | `CallAudio.swift`, `Adb.swift`, `CallAudioSetup.swift` | `native/callbridge/helper/Bridge.java` (runs on the phone as the adb shell user) |
| UI | `App.swift` | `Ui.kt`, `MainActivity.kt` |

If you change the wire format, update [docs/PROTOCOL.md](docs/PROTOCOL.md) and, for an incompatible change, bump `v` in the QR payload and the HKDF `info` string on both sides.

## Code style

- Match the surrounding code: naming, comment density, and idiom. Comments say *why*, not what.
- Prefer the platform's own features and the standard library over new dependencies. A new dependency needs a reason in the PR.
- Keep Swift expressions short and split long chains; GitHub's Mac compiler can give up on long `+` chains that build fine locally.
- User-visible text is plain language and honest about limits.

## Commits and pull requests

- Commit messages: a short summary in the style `type(scope): summary`, with the types the history already uses: `feat`, `fix`, `docs`, `ci`, `build`, `chore`. Explain *why* in the body when it isn't obvious.
- The pull-request template asks what changed, why, and what you tested on which devices. Fill it in honestly: say what is **untested**. This project talks to real phones and Macs, and a lot of behaviour only shows up there.
- Add screenshots only if they contain nothing private (notifications, messages, contacts and mirrored screens are personal).
- **CI must pass.** Every PR builds the Android app and the Mac app on GitHub. Fix failures in the same PR.
- Update the docs and the README feature table when behaviour changes.
- By contributing you agree that your work is released under the project's [MIT licence](LICENSE).

## Testing

There is no large automated suite yet, so a PR should describe how it was checked by hand:

- the exact steps you ran, and the phone model, Android version and macOS version;
- for UI changes, a screenshot or short description of the before and after;
- for anything touching the link, pairing, or call audio, check that a phone can still pair, reconnect after Wi-Fi drops, and that ending a call restores the phone's audio and microphone.

Adding tests for the parts that can be tested without a phone (protocol framing, parsing of `dumpsys` output, shape detection) is very welcome.

## Releases (maintainer)

Pushing a tag such as `v0.3.0` runs the **Release** workflow, which builds the APK, `.dmg` and `.pkg` and publishes a GitHub release. The Android signing key lives only as secrets of the protected `release` environment, which needs the maintainer's approval for each run, so contributors and forks never have access to it. Never commit keystores, `keystore.properties`, tokens, or `.jks` files, and never paste secrets into issues or PRs.

Local signed builds use `native/android/keystore.properties` (git-ignored):

```
storeFile=splurter-release.jks
storePassword=...
keyAlias=splurter
keyPassword=...
```

Create a keystore with `keytool -genkeypair -keystore native/android/splurter-release.jks -alias splurter -keyalg RSA -keysize 2048 -validity 10000`. Without them the release APK is debug-signed.

## Getting help

Open an issue or a draft PR with your question. Small, early drafts are welcome.
