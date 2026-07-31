import 'package:flutter/services.dart';

const _scrcpyChannel = MethodChannel('splurter/scrcpy');

/// Launch low-latency H.264 screen mirroring for paired Android device over TCP/ADB.
Future<bool> launchScreenMirroring({
  required String ipAddress,
  int port = 5555,
  String? deviceName,
}) async {
  try {
    final result = await _scrcpyChannel.invokeMethod<bool>('startMirroring', {
      'ipAddress': ipAddress,
      'port': port,
      'deviceName': deviceName ?? 'Android Device',
    });
    return result ?? false;
  } catch (_) {
    return false;
  }
}

/// Check if scrcpy / adb binaries are installed on macOS
Future<bool> isScrcpyAvailable() async {
  try {
    final result = await _scrcpyChannel.invokeMethod<bool>('checkAvailability');
    return result ?? false;
  } catch (_) {
    return false;
  }
}
