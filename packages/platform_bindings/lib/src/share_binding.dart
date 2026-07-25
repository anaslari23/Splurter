import 'dart:async';

import 'package:flutter/services.dart';

const _shareChannel = MethodChannel('splurter/share');

Stream<String> sharedText() {
  final controller = StreamController<String>.broadcast();
  _shareChannel.setMethodCallHandler((call) async {
    if (call.method == 'onSharedText' && call.arguments is String) {
      controller.add(call.arguments as String);
    }
  });
  _shareChannel.invokeMethod<String>('consumeInitialText').then((value) {
    if (value != null && value.isNotEmpty) controller.add(value);
  });
  return controller.stream;
}
