import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_types/shared_types.dart';
import 'package:continuity_core/continuity_core.dart';
import 'pairing_repository.dart';

final pairingRepositoryProvider = Provider<PairingRepository>((ref) {
  return PairingRepository();
});

final pairingStateProvider =
    StateNotifierProvider<PairingNotifier, PairingState>((ref) {
  return PairingNotifier(ref.watch(pairingRepositoryProvider));
});

class PairingNotifier extends StateNotifier<PairingState> {
  PairingNotifier(this._repository) : super(const PairingIdle()) {
    _loadSavedPairing();
  }

  final PairingRepository _repository;

  Future<void> _loadSavedPairing() async {
    final paired = await _repository.getPairedDevice();
    if (paired != null) {
      final device = Device(
        id: paired.id,
        name: paired.name,
        platform: paired.platform,
        address: 'relay',
        port: 9876,
        version: '1.0',
        capabilities: paired.capabilities.map((c) => c.name).toList(),
        isPaired: true,
      );
      state = PairingConnected(device);
    }
  }

  void startDiscovery() {
    state = const PairingDiscovering();
  }

  void foundDevice(Device device) {
    state = PairingFoundDevice(device);
  }

  void showPairingConfirm(String pairingCode) {
    state = PairingAwaitingAccept(pairingCode);
  }

  Future<void> complete(Device device) async {
    state = PairingConnected(device);
    final paired = PairedDevice(
      id: device.id,
      name: device.name,
      platform: device.platform,
      publicKey: device.fingerprint ?? '',
      capabilities: device.capabilities
          .map((c) => Capability.values.firstWhere((e) => e.name == c, orElse: () => Capability.clipboard))
          .toSet(),
      pairedAt: DateTime.now(),
    );
    await _repository.savePairedDevice(paired);
  }

  Future<void> unpair() async {
    await _repository.clearPairing();
    state = const PairingIdle();
  }

  void cancel() {
    state = const PairingIdle();
  }

  void fail(String message) {
    state = PairingFailed(message);
  }
}

