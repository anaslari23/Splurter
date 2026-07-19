import 'dart:async';
import 'package:flutter/services.dart';

const _networkChannel = MethodChannel('splurter/network');

class NetworkInfo {
  const NetworkInfo({
    required this.ipAddress,
    required this.isWifi,
    required this.isConnected,
  });

  final String ipAddress;
  final bool isWifi;
  final bool isConnected;
}

Future<NetworkInfo> getNetworkInfo() async {
  final result = await _networkChannel.invokeMethod('getNetworkInfo');
  return NetworkInfo(
    ipAddress: result['ipAddress'] as String,
    isWifi: result['isWifi'] as bool,
    isConnected: result['isConnected'] as bool,
  );
}

Stream<bool> get connectivityChanges {
  final controller = StreamController<bool>.broadcast();

  _networkChannel.setMethodCallHandler((call) async {
    if (call.method == 'onConnectivityChanged') {
      final args = call.arguments as Map;
      controller.add(args['isConnected'] as bool);
    }
  });

  _networkChannel.invokeMethod('startListening');

  return controller.stream;
}
