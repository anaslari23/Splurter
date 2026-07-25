import 'dart:async';
import 'package:flutter/services.dart';

const _channel = MethodChannel('splurter/native_notifications');
const _androidNotifChannel = MethodChannel('splurter/notifications');

/// Show a native macOS system notification for a mirrored Android notification.
/// Has a "Dismiss on Android" action — tapping it calls [onDismissedOnMac].
Future<void> showNativeNotification({
  required String id,
  required String appName,
  required String title,
  required String text,
}) async {
  await _channel.invokeMethod('show', {
    'id': id,
    'appName': appName,
    'title': title,
    'text': text,
  });
}

/// Dismiss a delivered macOS notification by id.
Future<void> dismissNativeNotification(String id) async {
  await _channel.invokeMethod('dismiss', {'id': id});
}

/// Ask Android (via its NotificationListener service) to cancel a notification
/// that was mirrored to Mac. Called when user taps "Dismiss on Android" in
/// Mac Notification Center.
Future<void> dismissAndroidNotification(String notifId) async {
  await _androidNotifChannel.invokeMethod('dismiss', {'id': notifId});
}

/// Stream that emits notification IDs when the user taps "Dismiss on Android"
/// in macOS Notification Center.
Stream<String> get macNotificationDismissals {
  final controller = StreamController<String>.broadcast();
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'onDismissedOnMac') {
      final id = (call.arguments as Map?)?['id'] as String?;
      if (id != null) controller.add(id);
    }
  });
  return controller.stream;
}
