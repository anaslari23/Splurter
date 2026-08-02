import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:continuity_core/continuity_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_bindings/platform_bindings.dart';

/// Manages the persistent Firestore signal subscription and direct LAN TCP socket stream
/// that drives all feature providers (clipboard, notifications, transfers).
class RelayLoop {
  RelayLoop._();
  static final RelayLoop instance = RelayLoop._();

  StreamSubscription<QuerySnapshot>? _sub;
  StreamSubscription<String>? _dismissSub;
  ServerSocket? _localServer;
  String? _uid;
  String? _deviceId;
  final _db = FirebaseFirestore.instance;

  String? get currentUid => _uid;
  bool get isConnected => _sub != null;

  // Callbacks set by feature providers / main.dart
  void Function(String text)? onClipboardReceived;
  void Function(Map<String, dynamic> notif)? onNotificationReceived;

  void start({required String uid, required String deviceId}) {
    if (_uid == uid && _sub != null) return;
    _uid = uid;
    _deviceId = deviceId;
    _sub?.cancel();

    _startLocalServer();

    _sub = _db
        .collection('users')
        .doc(uid)
        .collection('signals')
        .where('recipientId', isEqualTo: deviceId)
        .snapshots()
        .listen(_onSnapshot);

    // On macOS: listen for dismiss actions tapped in Notification Center
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _dismissSub = macNotificationDismissals.listen((notifId) {
        _sendDismiss(notifId);
      });
    }
  }

  void _startLocalServer() async {
    if (_localServer != null) return;
    try {
      _localServer = await ServerSocket.bind(InternetAddress.anyIPv4, 53317);
      _localServer?.listen((socket) {
        socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          try {
            final jsonMap = jsonDecode(line) as Map<String, dynamic>;
            final kindStr = jsonMap['kind'] as String? ?? '';
            final kind = RelayKind.values.where((k) => k.name == kindStr).firstOrNull;
            final payload = Map<String, dynamic>.from(jsonMap['payload'] as Map? ?? {});
            if (kind == RelayKind.clipboard) {
              final text = payload['text'] as String? ?? jsonMap['text'] as String?;
              if (text != null) onClipboardReceived?.call(text);
            } else if (kind == RelayKind.notification) {
              if (defaultTargetPlatform == TargetPlatform.macOS) {
                showNativeNotification(
                  id: payload['id'] as String? ?? '',
                  appName: payload['appName'] as String? ?? 'Android',
                  title: payload['title'] as String? ?? '',
                  text: payload['text'] as String? ?? '',
                );
              }
              onNotificationReceived?.call(payload);
            }
          } catch (_) {}
        });
      });
    } catch (_) {}
  }

  void switchUid(String newUid, {String? deviceId}) {
    if (_uid == newUid && _sub != null) return;
    _uid = newUid;
    if (deviceId != null) _deviceId = deviceId;
    _sub?.cancel();

    _sub = _db
        .collection('users')
        .doc(newUid)
        .collection('signals')
        .where('recipientId', isEqualTo: _deviceId)
        .snapshots()
        .listen(_onSnapshot);

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _dismissSub?.cancel();
      _dismissSub = macNotificationDismissals.listen((notifId) {
        _sendDismiss(notifId);
      });
    }
  }

  void stop() {
    _sub?.cancel();
    _dismissSub?.cancel();
    try {
      _localServer?.close();
    } catch (_) {}
    _localServer = null;
    _sub = null;
    _dismissSub = null;
    _uid = null;
    _deviceId = null;
  }

  void _onSnapshot(QuerySnapshot snapshot) {
    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final data = change.doc.data() as Map<String, dynamic>;

      final kindStr = data['kind'] as String? ?? '';
      final RelayKind? kind = RelayKind.values.where((k) => k.name == kindStr).firstOrNull;
      final payload = Map<String, dynamic>.from(data['payload'] as Map? ?? {});

      switch (kind) {
        case RelayKind.clipboard:
          final text = payload['text'] as String?;
          if (text != null) onClipboardReceived?.call(text);

        case RelayKind.notification:
          if (defaultTargetPlatform == TargetPlatform.macOS) {
            showNativeNotification(
              id: payload['id'] as String? ?? '',
              appName: payload['appName'] as String? ?? 'Android',
              title: payload['title'] as String? ?? '',
              text: payload['text'] as String? ?? '',
            );
          }
          onNotificationReceived?.call(payload);

        case RelayKind.remoteControl:
          if (defaultTargetPlatform == TargetPlatform.android) {
            final notifId = payload['notifId'] as String?;
            if (notifId != null && payload['action'] == 'dismiss') {
              dismissAndroidNotification(notifId);
            }
          }

        default:
          break;
      }

      change.doc.reference.delete().ignore();
    }
  }

  Future<void> send({
    required String uid,
    required String senderId,
    required String recipientId,
    required RelayKind kind,
    required Map<String, dynamic> payload,
  }) async {
    // 1. Attempt Sub-15ms Direct LAN TCP Socket Delivery
    try {
      final doc = await _db.collection('users').doc(uid).collection('devices').doc(recipientId).get();
      if (doc.exists) {
        final data = doc.data();
        final ip = data?['ipAddress'] as String?;
        final port = (data?['port'] as int?) ?? 53317;
        if (ip != null && ip.isNotEmpty && ip != 'relay') {
          final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 250));
          final envelopeJson = jsonEncode({
            'version': RelayEnvelope.currentVersion,
            'senderId': senderId,
            'recipientId': recipientId,
            'kind': kind.name,
            'payload': payload,
            'text': payload['text'] ?? '',
          });
          socket.writeln(envelopeJson);
          await socket.flush();
          await socket.close();
          return; // Instant LAN Socket Delivery Succeeded!
        }
      }
    } catch (_) {
      // Socket failed or unreachable -> Seamless fallback to Cloud Relay
    }

    // 2. Cloud Relay Fallback via Firestore Signals
    await _db.collection('users').doc(uid).collection('signals').add({
      'version': RelayEnvelope.currentVersion,
      'senderId': senderId,
      'recipientId': recipientId,
      'kind': kind.name,
      'payload': payload,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  void _sendDismiss(String notifId) async {
    final uid = _uid;
    final deviceId = _deviceId;
    if (uid == null || deviceId == null) return;

    final snap = await _db.collection('users').doc(uid).collection('devices').get();
    for (final doc in snap.docs) {
      if (doc.id != deviceId) {
        send(
          uid: uid,
          senderId: deviceId,
          recipientId: doc.id,
          kind: RelayKind.remoteControl,
          payload: {'action': 'dismiss', 'notifId': notifId},
        );
      }
    }
  }
}

final relayLoopProvider = Provider<RelayLoop>((ref) => RelayLoop.instance);
