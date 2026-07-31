import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:continuity_api/continuity_api.dart';
import 'package:platform_bindings/platform_bindings.dart';
import 'package:uuid/uuid.dart';

import 'settings_provider.dart' hide deviceIdProvider;

final platformControllerProvider = Provider<PlatformController>((ref) {
  throw UnimplementedError('platformControllerProvider must be overridden at app boot');
});

class PlatformController {
  PlatformController({
    required this.deviceId,
    required this.deviceInfo,
    required this.relay,
  });

  final String deviceId;
  final DeviceInfo deviceInfo;
  final RelayClient relay;
  Timer? _clipDebounce;
  static const _uuid = Uuid();

  Future<void> initialize() async {
    await relay.connect();
    relay.messages.listen(_handleIncoming);
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

  StreamSubscription<ClipboardData>? _nativeClipSub;

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
      if (relay.isConnected && data.content.isNotEmpty) {
        await relay.send(RelayEnvelope(
          version: RelayEnvelope.currentVersion,
          id: _uuid.v4(),
          kind: RelayKind.clipboard,
          senderId: deviceId,
          recipientId: 'paired-device',
          sentAt: DateTime.now().toUtc(),
          payload: {'action': 'set', 'content': data.content, 'mimeType': data.mimeType},
        ));
      }
    } catch (_) {}
  }

  void stopClipboardSync() {
    _nativeClipSub?.cancel();
    _nativeClipSub = null;
  }

  StreamSubscription<dynamic>? _nativeNotifSub;
  static const _notifChannel = EventChannel('splurter/notifications_stream');

  void startNotificationSync(bool enabled) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!enabled) return;

    _nativeNotifSub = _notifChannel
        .receiveBroadcastStream()
        .listen((raw) {
      final map = Map<String, dynamic>.from(raw as Map? ?? {});
      if (!relay.isConnected) return;
      relay.send(RelayEnvelope(
        version: RelayEnvelope.currentVersion,
        id: _uuid.v4(),
        kind: RelayKind.notification,
        senderId: deviceId,
        recipientId: 'paired-device',
        sentAt: DateTime.now().toUtc(),
        payload: {
          'action': 'posted',
          'id': map['id'] ?? '',
          'packageName': map['packageName'] ?? '',
          'title': map['title'] ?? '',
          'text': map['text'] ?? '',
          'timestamp': map['timestamp'] ?? 0,
        },
      ));
    });
  }


  void stopNotificationSync() {
    _nativeNotifSub?.cancel();
    _nativeNotifSub = null;
  }

  void _handleIncoming(RelayEnvelope msg) {
    switch (msg.kind) {
      case RelayKind.clipboard:
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

  Future<void> sendTransfer({
    required String recipientId,
    required String name,
    required int size,
    required String mimeType,
  }) async {
    if (!relay.isConnected) return;
    await relay.send(RelayEnvelope(
      version: RelayEnvelope.currentVersion,
      id: _uuid.v4(),
      kind: RelayKind.transfer,
      senderId: deviceId,
      recipientId: recipientId,
      sentAt: DateTime.now().toUtc(),
      payload: {
        'action': 'offer',
        'name': name,
        'size': size,
        'mimeType': mimeType,
      },
    ));
  }

  Future<void> sendPresence(String status) async {
    if (!relay.isConnected) return;
    await relay.send(RelayEnvelope(
      version: RelayEnvelope.currentVersion,
      id: _uuid.v4(),
      kind: RelayKind.presence,
      senderId: deviceId,
      recipientId: 'all',
      sentAt: DateTime.now().toUtc(),
      payload: {'status': status, 'info': deviceInfo.toJson()},
    ));
  }

  Future<void> dispose() async {
    _clipDebounce?.cancel();
    _nativeClipSub?.cancel();
    _nativeNotifSub?.cancel();
    stopClipboardSync();
    stopNotificationSync();
    await relay.disconnect();
  }
}

