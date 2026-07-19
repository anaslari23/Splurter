import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
