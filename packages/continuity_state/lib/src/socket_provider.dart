import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:continuity_api/continuity_api.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
  return ConnectionStatusNotifier();
});

class ConnectionStatusNotifier extends StateNotifier<ConnectionStatus> {
  ConnectionStatusNotifier() : super(ConnectionStatus.disconnected);
}

final connectedDeviceProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

final socketProvider = Provider<ContinuitySocketClient?>((ref) => null);
