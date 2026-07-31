import 'package:flutter/services.dart';

const _windowChannel = MethodChannel('splurter/window');

/// Toggle compact floating phone mode vs full dashboard mode on macOS
Future<void> setCompactWindowMode(bool isCompact) async {
  try {
    await _windowChannel.invokeMethod('setCompactMode', {'isCompact': isCompact});
  } catch (_) {}
}
