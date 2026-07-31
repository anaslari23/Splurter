import 'dart:async';

import 'package:flutter/services.dart';

const _clipboardChannel = MethodChannel('splurter/clipboard');

/// Read the current clipboard content.
/// Returns a map with keys: 'content' (String), 'mimeType' (String).
/// Throws PlatformException if the platform cannot read the clipboard.
Future<ClipboardData> readClipboard() async {
  final result = await _clipboardChannel.invokeMethod('read');
  return ClipboardData(
    content: result['content'] as String,
    mimeType: result['mimeType'] as String,
  );
}

/// Write text to the system clipboard.
Future<void> writeClipboard(String content, {String mimeType = 'text/plain'}) async {
  await _clipboardChannel.invokeMethod('write', {
    'content': content,
    'mimeType': mimeType,
  });
}

/// Write binary data (e.g. an image) to the system clipboard.
Future<void> writeClipboardBytes(Uint8List bytes, {String mimeType = 'image/png'}) async {
  await _clipboardChannel.invokeMethod('writeBytes', {
    'bytes': bytes,
    'mimeType': mimeType,
  });
}

/// Start listening for clipboard changes. Emits [ClipboardData] each time
/// the clipboard content changes. The listener must be stopped via
/// [stopListening] when no longer needed to avoid leaks.
Stream<ClipboardData> listenClipboardChanges() {
  final controller = StreamController<ClipboardData>.broadcast();

  _clipboardChannel.setMethodCallHandler((call) async {
    if (call.method == 'onClipboardChanged') {
      final args = call.arguments as Map;
      controller.add(ClipboardData(
        content: args['content'] as String,
        mimeType: args['mimeType'] as String,
      ));
    }
  });

  _clipboardChannel.invokeMethod('startListening');

  return controller.stream;
}

Future<void> stopListeningClipboardChanges() async {
  await _clipboardChannel.invokeMethod('stopListening');
}

/// Open Android System Input Method Settings to allow enabling Splurter Keyboard for background clipboard reads.
Future<bool> openImeSettings() async {
  try {
    final result = await _clipboardChannel.invokeMethod('openImeSettings');
    return result == true;
  } catch (_) {
    return false;
  }
}

/// Check if Splurter Keyboard IME is enabled on Android.
Future<bool> isImeEnabled() async {
  try {
    final result = await _clipboardChannel.invokeMethod('isImeEnabled');
    return result == true;
  } catch (_) {
    return false;
  }
}

class ClipboardData {
  const ClipboardData({required this.content, required this.mimeType});
  final String content;
  final String mimeType;
}
