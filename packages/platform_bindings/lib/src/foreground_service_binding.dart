import 'dart:async';

import 'package:flutter/services.dart';

const _fgChannel = MethodChannel('splurter/foreground_service');

Future<void> startForegroundService() async {
  try {
    await _fgChannel.invokeMethod('start');
  } on PlatformException catch (_) {}
}

Future<void> stopForegroundService() async {
  try {
    await _fgChannel.invokeMethod('stop');
  } on PlatformException catch (_) {}
}

Future<void> updateForegroundNotification(String text) async {
  try {
    await _fgChannel.invokeMethod('updateNotification', {'text': text});
  } on PlatformException catch (_) {}
}
