import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:continuity_core/continuity_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_bindings/platform_bindings.dart';

/// Manages the persistent Firestore signal subscription that drives all
/// feature providers (clipboard, notifications, transfers).
class RelayLoop {
  RelayLoop._();
  static final RelayLoop instance = RelayLoop._();

  StreamSubscription<QuerySnapshot>? _sub;
  StreamSubscription<String>? _dismissSub;
  String? _uid;
  String? _deviceId;
  final _db = FirebaseFirestore.instance;

  // Callbacks set by feature providers / main.dart
  void Function(String text)? onClipboardReceived;
  void Function(Map<String, dynamic> notif)? onNotificationReceived;

  void start({required String uid, required String deviceId}) {
    if (_uid == uid && _sub != null) return;
    _uid = uid;
    _deviceId = deviceId;
    _sub?.cancel();

    _sub = _db
        .collection('users')
        .doc(uid)
        .collection('signals')
        .where('recipientId', isEqualTo: deviceId)
        .snapshots()
        .listen(_onSnapshot);


    // On macOS: listen for dismiss actions tapped in Notification Center
    // and send a dismiss signal back to the Android device
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _dismissSub = macNotificationDismissals.listen((notifId) {
        _sendDismiss(notifId);
      });
    }
  }

  void switchUid(String newUid) {
    if (_uid == newUid && _sub != null) return;
    _uid = newUid;
    _deviceId ??= 'android-device-id';
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
          // On macOS: show as a native system notification with Dismiss action
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
          // Dismiss command from Mac (user tapped "Dismiss on Android")
          if (defaultTargetPlatform == TargetPlatform.android) {
            final notifId = payload['notifId'] as String?;
            if (notifId != null && payload['action'] == 'dismiss') {
              dismissAndroidNotification(notifId);
            }
          }

        default:
          break;
      }

      // Inbox pattern — delete once processed
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
    await _db.collection('users').doc(uid).collection('signals').add({
      'version': RelayEnvelope.currentVersion,
      'senderId': senderId,
      'recipientId': recipientId,
      'kind': kind.name,
      'payload': payload,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  /// Bounce a notification dismiss from Mac → Android relay signal.
  void _sendDismiss(String notifId) {
    final uid = _uid;
    final deviceId = _deviceId;
    if (uid == null || deviceId == null) return;

    // Mac is sender, Android is recipient
    final androidDeviceId = deviceId == 'mac-device-id' ? 'android-device-id' : deviceId;
    send(
      uid: uid,
      senderId: deviceId,
      recipientId: androidDeviceId,
      kind: RelayKind.remoteControl,
      payload: {'action': 'dismiss', 'notifId': notifId},
    );
  }
}

final relayLoopProvider = Provider<RelayLoop>((ref) => RelayLoop.instance);
