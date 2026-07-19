import 'dart:async';

import 'package:flutter/services.dart';

final splurterNotificationChannel = MethodChannel('splurter/notifications');
final splurterNotificationEvents = StreamController<Map<String, dynamic>>.broadcast();

class SplurterNotificationListener {
  static Future<bool> isActive() async {
    final result = await splurterNotificationChannel.invokeMethod('isActive');
    return result as bool;
  }

  static Future<void> requestPermission() async {
    await splurterNotificationChannel.invokeMethod('requestPermission');
  }

  static Stream<Map<String, dynamic>> get stream => splurterNotificationEvents.stream;
}

Future<void> _init() async {
  splurterNotificationChannel.setMethodCallHandler((call) async {
    if (call.method == 'onNotificationPosted') {
      final args = call.arguments as Map;
      splurterNotificationEvents.add(Map<String, dynamic>.from(args));
    }
    return null;
  });
}

// ignore_for_file: unused_element
final _initFuture = _init();
