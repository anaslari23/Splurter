import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'relay_loop.dart';

enum TransportKind { local, firebase }

/// Selects the fastest available relay transport.
///
/// Strategy (mirrors Google Nearby Share):
/// 1. Try local TCP socket on LAN (via BLE-discovered IP) — <100ms
/// 2. Fall back to Firebase Firestore relay — works across internet
///
/// The selection is passive: [RelayLoop] already writes to Firestore.
/// When a local LAN connection is established via [BleLocalBridge] on
/// the Swift/Kotlin layer, it writes signals directly over TCP instead.
/// This provider tracks the current active transport for UI display.
final activeTransportProvider = StateProvider<TransportKind>((ref) {
  return TransportKind.firebase; // default until BLE discovers a local peer
});

/// Call this when BLE scanner on Mac confirms a direct LAN connection.
void setLocalTransportActive(WidgetRef ref) {
  ref.read(activeTransportProvider.notifier).state = TransportKind.local;
}

/// Call this when the local TCP connection drops.
void setFirebaseTransportActive(WidgetRef ref) {
  ref.read(activeTransportProvider.notifier).state = TransportKind.firebase;
}
