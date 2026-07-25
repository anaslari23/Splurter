import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:continuity_core/continuity_core.dart';

/// Secure storage repository for paired device records and session encryption keys.
class PairingRepository {
  PairingRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _pairedDeviceKey = 'splurter_paired_device';
  static const _sessionKeyKey = 'splurter_session_key';

  Future<void> savePairedDevice(PairedDevice device) async {
    await _storage.write(
      key: _pairedDeviceKey,
      value: jsonEncode(device.toJson()),
    );
  }

  Future<PairedDevice?> getPairedDevice() async {
    final raw = await _storage.read(key: _pairedDeviceKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PairedDevice.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSessionKey(String keyBase64) async {
    await _storage.write(key: _sessionKeyKey, value: keyBase64);
  }

  Future<String?> getSessionKey() async {
    return _storage.read(key: _sessionKeyKey);
  }

  Future<void> clearPairing() async {
    await _storage.delete(key: _pairedDeviceKey);
    await _storage.delete(key: _sessionKeyKey);
  }
}
