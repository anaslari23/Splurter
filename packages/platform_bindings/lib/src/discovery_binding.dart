import 'dart:async';
import 'package:flutter/services.dart';

const _discoveryChannel = MethodChannel('splurter/discovery');

/// Result of discovering a device via mDNS.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.platform,
    required this.version,
    required this.capabilities,
    required this.fingerprint,
  });

  final String id;
  final String name;
  final String address;
  final int port;
  final String platform;
  final String version;
  final List<String> capabilities;
  final String fingerprint;
}

/// Advertise this device on the local network via mDNS/Bonjour.
///
/// [serviceType] — the mDNS service type, e.g. `_splurter._tcp.local`.
/// [port] — the TCP port the device is listening on.
/// [deviceName] — human-readable name shown to other devices.
/// [version] — app version string.
/// [capabilities] — list of supported feature strings.
Future<void> advertiseService({
  required String serviceType,
  required int port,
  required String deviceName,
  required String version,
  required List<String> capabilities,
}) async {
  await _discoveryChannel.invokeMethod('advertise', {
    'serviceType': serviceType,
    'port': port,
    'deviceName': deviceName,
    'version': version,
    'capabilities': capabilities,
  });
}

/// Stop advertising the mDNS service.
Future<void> stopAdvertising() async {
  await _discoveryChannel.invokeMethod('stopAdvertising');
}

/// Start browsing for Splurter devices on the local network.
/// Returns a broadcast stream of [DiscoveredDevice] events.
Stream<DiscoveredDevice> browseServices({
  required String serviceType,
}) {
  final controller = StreamController<DiscoveredDevice>.broadcast();

  _discoveryChannel.setMethodCallHandler((call) async {
    if (call.method == 'onServiceFound') {
      final args = call.arguments as Map;
      controller.add(DiscoveredDevice(
        id: args['id'] as String,
        name: args['name'] as String,
        address: args['address'] as String,
        port: args['port'] as int,
        platform: args['platform'] as String,
        version: args['version'] as String,
        capabilities: List<String>.from(args['capabilities'] as List),
        fingerprint: args['fingerprint'] as String,
      ));
    } else if (call.method == 'onServiceLost') {
      // Could emit a "device lost" event; for MVP we just drop it.
    }
  });

  _discoveryChannel.invokeMethod('browse', {'serviceType': serviceType});

  return controller.stream;
}

/// Stop browsing for services.
Future<void> stopBrowsing() async {
  await _discoveryChannel.invokeMethod('stopBrowsing');
}
