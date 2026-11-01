import 'dart:async';
import 'package:flutter/services.dart';
import 'package:continuity_core/continuity_core.dart';

const _callChannel = MethodChannel('splurter/calls');

/// Answer an incoming phone call on Android via TelecomManager
Future<void> answerCall() async {
  try {
    await _callChannel.invokeMethod('answerCall');
  } catch (_) {}
}

/// Decline or end an active phone call on Android
Future<void> endCall() async {
  try {
    await _callChannel.invokeMethod('endCall');
  } catch (_) {}
}

/// Listen for incoming/ongoing/ended phone call events on Android
Stream<PhoneCallEvent> listenCallEvents() {
  final controller = StreamController<PhoneCallEvent>.broadcast();

  _callChannel.setMethodCallHandler((call) async {
    if (call.method == 'onCallEvent') {
      try {
        final payload = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        final event = PhoneCallEvent.fromJson(payload);
        controller.add(event);
      } catch (_) {}
    }
  });

  return controller.stream;
}
