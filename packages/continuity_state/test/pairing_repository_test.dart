import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:continuity_core/continuity_core.dart';
import 'package:continuity_state/continuity_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PairingRepository', () {
    test('saves and loads paired device record cleanly', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final repository = PairingRepository();

      final device = PairedDevice(
        id: 'phone-123',
        name: 'Android Phone',
        platform: 'android',
        publicKey: 'pubkey-abc',
        capabilities: {Capability.clipboard, Capability.fileTransfer},
        pairedAt: DateTime.now(),
      );

      await repository.savePairedDevice(device);
      final loaded = await repository.getPairedDevice();

      expect(loaded, isNotNull);
      expect(loaded!.id, equals('phone-123'));
      expect(loaded.name, equals('Android Phone'));

      await repository.clearPairing();
      final cleared = await repository.getPairedDevice();
      expect(cleared, isNull);
    });
  });
}
