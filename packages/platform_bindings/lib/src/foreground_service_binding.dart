import 'dart:async';

import 'package:flutter/services.dart';

const _fgChannel = MethodChannel('splurter/foreground_service');

Future<void> startForegroundService() async {
  try {
    await _fgChannel.invokeMethod('start');
  } catch (_) {}
}

Future<void> stopForegroundService() async {
  try {
    await _fgChannel.invokeMethod('stop');
  } catch (_) {}
}

Future<void> updateForegroundNotification(String text) async {
  try {
    await _fgChannel.invokeMethod('updateNotification', {'text': text});
  } catch (_) {}
}

Future<void> setHostUid(String? uid) async {
  try {
    await _fgChannel.invokeMethod('setHostUid', {'uid': uid});
  } catch (_) {}
}
