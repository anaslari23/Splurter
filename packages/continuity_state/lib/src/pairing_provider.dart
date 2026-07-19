import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_types/shared_types.dart';

final pairingStateProvider =
    StateNotifierProvider<PairingNotifier, PairingState>((ref) {
  return PairingNotifier();
});

class PairingNotifier extends StateNotifier<PairingState> {
  PairingNotifier() : super(const PairingIdle());

  void startDiscovery() {
    state = const PairingDiscovering();
  }

  void foundDevice(Device device) {
    state = PairingFoundDevice(device);
  }

  void showPairingConfirm(String pairingCode) {
    state = PairingAwaitingAccept(pairingCode);
  }

  void complete(Device device) {
    state = PairingConnected(device);
  }

  void cancel() {
    state = const PairingIdle();
  }

  void fail(String message) {
    state = PairingFailed(message);
  }
}
