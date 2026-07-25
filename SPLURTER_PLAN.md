# Splurter — Complete Re-Engineering Plan

## What We're Building

A fully native Android-Mac companion that works **identically to iPhone Continuity**, using creative workarounds for every platform wall. You sign in once with Google, close both apps, and everything just works.

---

## Honest Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│                    GOOGLE ACCOUNT LAYER                    │
│  Firebase Auth (Google provider) → UID links both devices  │
│  Firestore signals/{uid}/ → encrypted RelayEnvelopes       │
│  FCM → wakes Android from deep sleep                       │
└──────────────────────┬─────────────────────────────────────┘
                       │
         ┌─────────────▼──────────────┐
         │   TRANSPORT LAYER          │
         │  Local Wi-Fi (BLE+TCP)     │  ← zero latency when same network
         │  Firebase Relay (fallback) │  ← works across internet
         └──────────┬─────────────────┘
                    │
     ┌──────────────┼──────────────┐
     ▼                             ▼
ANDROID (always-on)           macOS (menu-bar daemon)
Foreground service            NSApp.activationPolicy = .accessory
NotificationListener          ClipboardMonitor (NSPasteboard polling)
AccessibilityIME              SMAppService launch-at-login
BLE advertiser                NWListener + Bonjour
```

---

## Phase 1 — Google Sign-In & Real Device Linking
**Goal: Both devices are connected by UID. No QR required.**

### What exists:
- `FirebaseRelayClient` has `connect()` / `send()` / `messages` stream — but is injected with stub closures, never wired to real Firestore.
- Firestore rules exist for `/pairs/{pairId}/signals/` — but `pairs` are never created.
- macOS `AppDelegate.swift` already sets `NSApp.setActivationPolicy(.accessory)`, has menu-bar tray, and `applicationShouldTerminateAfterLastWindowClosed → false`. ✅

### What we build:
1. **Add `google_sign_in` + `firebase_auth`** to both apps' `pubspec.yaml`
2. **`SignInScreen`** (shared `continuity_ui` widget) — one button: *"Continue with Google"*. On success, writes to `Firestore /users/{uid}/devices/{deviceId}` with platform, name, FCM token.
3. **`firebase/functions/src/onDeviceLinked.ts`** — Cloud Function triggered on new device document. When same UID has ≥2 devices (one android, one macos), auto-creates `/users/{uid}/pair` linking them. No QR pairing needed — Google Account IS the pairing.
4. **Update `FirebaseRelayClient`** — inject real Firestore `collection('users').doc(uid).collection('signals').snapshots()` as the `incomingStream`. `onSend` writes a document there. Both devices listen to the same Firestore collection keyed by UID.

**Files:**
- `[MODIFY] apps/android_app/pubspec.yaml` — add `google_sign_in`, `firebase_auth`, `cloud_firestore`, `firebase_messaging`
- `[MODIFY] apps/mac_app/pubspec.yaml` — same
- `[NEW] packages/continuity_ui/lib/src/widgets/sign_in_screen.dart`
- `[NEW] packages/continuity_state/lib/src/auth_provider.dart` — `StreamProvider<User?>` watching FirebaseAuth
- `[MODIFY] packages/continuity_api/lib/src/firebase_relay_client.dart` — wire real Firestore streams
- `[NEW] firebase/functions/src/onDeviceLinked.ts`
- `[MODIFY] firebase/firestore.rules` — add `/users/{uid}/devices/` and `/users/{uid}/signals/`

---

## Phase 2 — Live Relay Loop (Data Actually Crosses Devices)
**Goal: Copy on Mac → appears on Android. Get notification on Android → pops on Mac.**

### What exists:
- `ClipboardMonitor.swift` polls NSPasteboard every 1s and fires `onClipboardChanged` to Flutter channel ✅
- `ClipboardChannelHandler.kt` registers `OnPrimaryClipChangedListener` — but **Android API 29+ throws `SecurityException` when read from background**. The handler already catches it.
- `NotificationListener.kt` intercepts all `onNotificationPosted` events and sends to Flutter channel ✅
- `SplurterForegroundService.kt` has a 1.5s polling loop trying background clipboard reads — **these throw SecurityException** and are silently swallowed.

### What we build:

#### 2a. Mac → Android Clipboard (This Actually Works)
Mac `ClipboardMonitor` detects NSPasteboard change → fires to Flutter → `platform_controller.dart` encrypts → writes `RelayEnvelope` to Firestore signal → Android relay loop receives → writes to `ClipboardManager` via foreground service. **This path is fully possible.**

#### 2b. Android → Mac Clipboard (The Creative Workaround)
Android OS 29+ blocks background clipboard reads. **Our re-engineering:**
- **`SplurterIME`** — a custom Input Method (keyboard) that runs as a system service, always active. The Android IME API gives clipboard access **without the background restriction** because it's classified as a system input service, not a background app.
- When the IME detects a clipboard change via `ClipboardManager.OnPrimaryClipChangedListener` (which fires even in background when called from an IME service), it writes directly to the `SplurterForegroundService` via a local broadcast, which relays to Firestore.
- User sets Splurter as their secondary/floating keyboard. They keep their main keyboard. Splurter IME runs invisible in background — it never shows as a keyboard unless explicitly chosen.
- **Result: true background clipboard sync Android → Mac**, same as iPhone.

#### 2c. Notifications Android → Mac
`NotificationListener.kt` already captures every notification. We wire it: notification arrives → `RelayEnvelope(kind: notification, payload: {title, body, app, iconBytes})` → Firestore → Mac `relay_loop.dart` receives → calls native macOS `UNUserNotificationCenter` to show a proper system notification with the Android app icon. Mac notification includes a **Dismiss** action that sends a `RemoteControlCommand(action: 'dismissNotification', id: notifId)` back to Android which calls `cancelNotification()`.

**Files:**
- `[NEW] apps/android_app/android/.../SplurterIME.kt` — custom InputMethodService for background clipboard access
- `[MODIFY] AndroidManifest.xml` — declare `<service android:name=".SplurterIME" android:permission="android.permission.BIND_INPUT_METHOD">`
- `[NEW] packages/continuity_state/lib/src/relay_loop.dart` — persistent subscription engine
- `[MODIFY] packages/continuity_state/lib/src/platform_controller.dart` — wire relay loop to clipboard and notification streams
- `[MODIFY] apps/mac_app/macos/Runner/AppDelegate.swift` — wire `UNUserNotificationCenter` for native Mac alerts with dismiss action

---

## Phase 3 — BLE Proximity for Instant Local Handoff
**Goal: When Mac and Android are near each other on same Wi-Fi, data flows at LAN speed with <100ms latency — no cloud relay. Like AirDrop.**

### The Creative Approach:
- **Android advertises as a BLE peripheral** with a Splurter UUID service. Mac scans via `CoreBluetooth`.
- BLE advertisement contains the Android's local Wi-Fi IP address and port in the manufacturer data payload (26 bytes, no pairing required).
- Mac sees the BLE advertisement, reads the IP, and opens a direct **NWConnection TCP socket** to the Android's `SplurterForegroundService` HTTP server (already has `NWListener` on port 53317).
- Once the local TCP socket is established, all relay traffic goes direct — Firestore is only the fallback when BLE can't see the device (different networks).
- **Transport negotiation**: `relay_loop.dart` tries local TCP first (10ms timeout), falls back to Firestore if unavailable.

This is exactly what Google's Nearby Share does: BLE for discovery, Wi-Fi Direct for data.

**Files:**
- `[NEW] apps/android_app/android/.../BleAdvertiser.kt` — BLE peripheral with Wi-Fi IP in manufacturer data
- `[NEW] apps/android_app/android/.../LocalRelayServer.kt` — NanoHTTP/raw TCP server accepting encrypted envelopes
- `[MODIFY] apps/mac_app/macos/Runner/AppDelegate.swift` — add `CBCentralManager` BLE scanner, connect via NWConnection when device found
- `[NEW] packages/continuity_state/lib/src/transport_selector.dart` — tries local TCP, falls back to Firebase

---

## Phase 4 — macOS Native Background Daemon (Already Mostly There)
**Goal: Mac app is invisible, always-on, never needs to be opened.**

### What exists already ✅:
- `NSApp.setActivationPolicy(.accessory)` — no dock icon ✅
- `applicationShouldTerminateAfterLastWindowClosed → false` — closing window keeps it alive ✅
- `SMAppService.mainApp.register()` — launch at login macOS 13+ ✅
- Menu-bar tray icon with Show/Quit ✅
- `ClipboardMonitor` polls NSPasteboard every 1s ✅
- `NWListener` on port 53317 + Bonjour advertisement ✅

### What we add:
1. **Start `ClipboardMonitor` automatically on launch** — currently `start()` is never called from Dart. Wire it in `relay_loop.dart` init.
2. **Menu-bar popover** showing: device name + status badge, last 3 clipboard items, a "Push Clipboard Now" button, connection quality indicator.
3. **macOS native notifications** with dismiss action wired to `UNUserNotificationCenter` directly in Swift.

**Files:**
- `[MODIFY] apps/mac_app/macos/Runner/AppDelegate.swift` — call `clipboardMonitor.start()` on launch, add `UNUserNotificationCenter` delegate, build rich popover
- `[MODIFY] packages/continuity_state/lib/src/relay_loop.dart` — trigger clipboard listening startup

---

## Phase 5 — Android Always-On Service with Boot Receiver
**Goal: Service survives reboots, OEM battery killers, and app force-stops.**

### What exists:
- `SplurterForegroundService.kt` with `START_STICKY` and foreground notification ✅
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission declared ✅

### What we add:
1. **`BootReceiver.kt`** — `RECEIVE_BOOT_COMPLETED` broadcast receiver that starts the foreground service after device reboot.
2. **`BatteryOptimizationHelper.kt`** — on first launch, calls `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` intent directly (opens system dialog automatically, no settings digging).
3. **WorkManager keepalive** — a periodic `PeriodicWorkRequest` every 15 minutes that checks if `SplurterForegroundService` is running and restarts it if OEM killed it. This is how Pushover, Signal, and WhatsApp survive aggressive battery killers.

**Files:**
- `[NEW] apps/android_app/android/.../BootReceiver.kt`
- `[NEW] apps/android_app/android/.../BatteryOptimizationHelper.kt`
- `[MODIFY] AndroidManifest.xml` — add `RECEIVE_BOOT_COMPLETED`, `BootReceiver` declaration
- `[MODIFY] apps/android_app/lib/main.dart` — request battery exemption on first launch

---

## What This Still Cannot Do

| Feature | Why | Creative Alternative |
|---|---|---|
| **Phone calls via Mac** | Carrier API, not available | Show Android incoming call as a Mac notification with "Open Phone" deeplink button — taps answer on Android |
| **Mac sends SMS from Android** | Android Telephony API requires device unlock | Mirror Android Messages app as a screen share panel on Mac |
| **Webcam replacement** | Requires macOS Virtual Camera driver (kernel extension) | Use Android screen share + crop to front camera region — a frame-in-frame preview |

---

## Implementation Order

1. Phase 1 — Google Sign-In + Firestore device linking (fixes "can't connect")
2. Phase 4 — Finalize macOS daemon (fix "must open app")
3. Phase 2 — Live relay loop + SplurterIME (fix clipboard Android→Mac)
4. Phase 3 — BLE local transport (instant LAN speed)
5. Phase 5 — Boot receiver + battery exemption (reliability)
