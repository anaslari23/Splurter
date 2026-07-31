import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:continuity_core/continuity_core.dart';

/// Secure storage repository for paired device records and session encryption keys.
class PairingRepository {
  PairingRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, String> _memFallback = {};

  static const _pairedDeviceKey = 'splurter_paired_device';
  static const _sessionKeyKey = 'splurter_session_key';

  Future<void> savePairedDevice(PairedDevice device) async {
    final val = jsonEncode(device.toJson());
    _memFallback[_pairedDeviceKey] = val;
    try {
      await _storage.write(key: _pairedDeviceKey, value: val);
    } catch (_) {}
  }

  Future<PairedDevice?> getPairedDevice() async {
    String? raw;
    try {
      raw = await _storage.read(key: _pairedDeviceKey);
    } catch (_) {}
    raw ??= _memFallback[_pairedDeviceKey];
    if (raw == null || raw.isEmpty) return null;
    try {
      return PairedDevice.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSessionKey(String keyBase64) async {
    _memFallback[_sessionKeyKey] = keyBase64;
    try {
      await _storage.write(key: _sessionKeyKey, value: keyBase64);
    } catch (_) {}
  }

  Future<String?> getSessionKey() async {
    String? raw;
    try {
      raw = await _storage.read(key: _sessionKeyKey);
    } catch (_) {}
    return raw ?? _memFallback[_sessionKeyKey];
  }

  Future<void> clearPairing() async {
    _memFallback.remove(_pairedDeviceKey);
    _memFallback.remove(_sessionKeyKey);
    try {
      await _storage.delete(key: _pairedDeviceKey);
      await _storage.delete(key: _sessionKeyKey);
    } catch (_) {}
  }
}
