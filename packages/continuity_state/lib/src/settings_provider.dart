import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.port,
  });

  final String id;
  final String name;
  final String platform;
  final int port;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'port': port,
  };
}

DeviceInfo buildDeviceInfo(String id, int port) {
  String name;
  String platform;
  if (Platform.isMacOS) {
    name = Platform.localHostname;
    if (name.isEmpty) name = 'Mac';
    platform = 'macos';
  } else if (Platform.isAndroid) {
    name = Platform.localHostname;
    if (name.isEmpty) name = 'Android';
    platform = 'android';
  } else if (Platform.isIOS) {
    name = Platform.localHostname;
    if (name.isEmpty) name = 'iPhone';
    platform = 'ios';
  } else {
    name = 'Unknown';
    platform = 'other';
  }
  return DeviceInfo(id: id, name: name, platform: platform, port: port);
}

const int kDefaultPort = 9876;

final deviceIdProvider = Provider<String>((ref) {
  throw UnimplementedError('deviceIdProvider must be overridden at app boot');
});

final serverPortProvider = StateProvider<int>((ref) => kDefaultPort);

final deviceInfoProvider = Provider<DeviceInfo>((ref) {
  throw UnimplementedError('deviceInfoProvider must be overridden at app boot');
});

const _uuid = Uuid();

String generateDeviceId() => _uuid.v4();

const _storage = FlutterSecureStorage();
const _deviceIdStorageKey = 'splurter_unique_device_id';

/// Fetch existing persistent unique device ID or generate a new one (e.g., 'android-a1b2c3d4', 'mac-e5f6g7h8').
Future<String> getOrCreateDeviceId(String platformPrefix) async {
  try {
    final existing = await _storage.read(key: _deviceIdStorageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
  } catch (_) {}
  final newId = '$platformPrefix-${_uuid.v4().substring(0, 8)}';
  try {
    await _storage.write(key: _deviceIdStorageKey, value: newId);
  } catch (_) {}
  return newId;
}

/// Discovers the active local IPv4 address (e.g. 192.168.x.x) for direct TCP socket connectivity.
Future<String?> getLocalIpAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final interface in interfaces) {
      if (interface.name.contains('wlan') ||
          interface.name.contains('en') ||
          interface.name.contains('eth')) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    }
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (!addr.isLoopback) {
          return addr.address;
        }
      }
    }
  } catch (_) {}
  return null;
}
