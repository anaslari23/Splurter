import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:continuity_api/continuity_api.dart';
import 'package:platform_bindings/platform_bindings.dart';

import 'settings_provider.dart' hide deviceIdProvider;

final platformControllerProvider = Provider<PlatformController>((ref) {
  throw UnimplementedError('platformControllerProvider must be overridden at app boot');
});

class PlatformController {
  PlatformController({
    required this.deviceId,
    required this.deviceInfo,
  });

  final String deviceId;
  final DeviceInfo deviceInfo;
  late final ContinuitySocketClient _socket;
  Timer? _clipDebounce;

  void initialize(String host, int port) {
    _socket = ContinuitySocketClient(
      deviceId: deviceId,
      onMessage: _handleIncoming,
      onConnect: _onConnect,
      onDisconnect: _onDisconnect,
      onError: _onError,
    );

    _socket.messages.listen(_handleIncoming);
    if (defaultTargetPlatform == TargetPlatform.android) {
      startForegroundService();
    }
    startClipboardSync();
  }

  Future<void> startForegroundMonitoring() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await startForegroundService();
    }
  }

  Future<void> stopForegroundMonitoring() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await stopForegroundService();
    }
  }

  StreamSubscription<void>? _nativeClipSub;

  void startClipboardSync() {
    _nativeClipSub = listenClipboardChanges().listen((_) {
      _clipDebounce?.cancel();
      _clipDebounce = Timer(const Duration(milliseconds: 600), () async {
        await _sendLocalClipboard();
      });
    });
  }

  Future<void> _sendLocalClipboard() async {
    try {
      final data = await readClipboard();
      if (_socket.isConnected && data.content.isNotEmpty) {
        _socket.sendClipboard(data.content, mimeType: data.mimeType);
      }
    } catch (_) {}
  }

  void stopClipboardSync() {
    _nativeClipSub?.cancel();
    _nativeClipSub = null;
  }

  StreamSubscription<Map<String, dynamic>>? _nativeNotifSub;

  void startNotificationSync(bool enabled) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!enabled) return;

    _nativeNotifSub = SplurterNotificationListener.stream.listen((raw) {
      if (!_socket.isConnected) return;
      _socket.sendMessage(ContinuityMessage(
        type: ContinuityMessageType.notification,
        payload: {
          'action': 'posted',
          'id': raw['id'],
          'packageName': raw['packageName'],
          'title': raw['title'] ?? '',
          'text': raw['text'] ?? '',
          'timestamp': raw['timestamp'],
        },
      ));
    });
  }

  void stopNotificationSync() {
    _nativeNotifSub?.cancel();
    _nativeNotifSub = null;
  }

  void _handleIncoming(ContinuityMessage msg) {
    switch (msg.type) {
      case ContinuityMessageType.clipboard:
        if (msg.payload['action'] == 'set') {
          final content = msg.payload['content'] as String;
          final mimeType = msg.payload['mimeType'] as String? ?? 'text/plain';
          _applyRemoteClipboard(content, mimeType);
        }
        break;
      default:
        break;
    }
  }

  Future<void> _applyRemoteClipboard(String content, String mimeType) async {
    try {
      await writeClipboard(content, mimeType: mimeType);
    } catch (_) {}
  }

  void _onConnect() {
    _socket.sendMessage(ContinuityMessage(
      type: ContinuityMessageType.pairing,
      payload: {
        'action': 'hello',
        'deviceId': deviceId,
        'deviceName': deviceInfo.name,
        'platform': deviceInfo.platform,
      },
    ));
  }

  void _onDisconnect() {}

  void _onError(dynamic error) {}

  void dispose() {
    _clipDebounce?.cancel();
    _nativeClipSub?.cancel();
    _nativeNotifSub?.cancel();
    stopClipboardSync();
    stopNotificationSync();
    _socket.dispose();
  }
}
