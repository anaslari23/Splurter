import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'continuity_message.dart';

typedef MessageHandler = void Function(ContinuityMessage message);

class ContinuitySocketClient {
  ContinuitySocketClient({
    required this.deviceId,
    this.onMessage,
    this.onConnect,
    this.onDisconnect,
    this.onError,
  });

  final String deviceId;
  final MessageHandler? onMessage;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;
  final void Function(dynamic error)? onError;

  io.Socket? _socket;
  final StreamController<ContinuityMessage> _incomingMessages =
      StreamController<ContinuityMessage>.broadcast();
  Completer<void>? _connectCompleter;
  bool _isConnected = false;

  Stream<ContinuityMessage> get messages => _incomingMessages.stream;
  bool get isConnected => _isConnected;

  Future<void> connect({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isConnected) return;

    final wsUrl = 'ws://$host:$port';
    _connectCompleter = Completer<void>();

    _socket = io.io(
      wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({'x-device-id': deviceId})
          .enableReconnection()
          .setReconnectionAttempts(12)
          .setReconnectionDelay(const Duration(seconds: 1).inMilliseconds)
          .setReconnectionDelayMax(const Duration(seconds: 8).inMilliseconds)
          .build(),
    );

    _socket!
      ..onConnect((_) {
        _isConnected = true;
        if (!_connectCompleter!.isCompleted) {
          _connectCompleter!.complete(null);
        }
        _connectCompleter = null;

        _emit(ContinuityMessage(
          type: ContinuityMessageType.pairing,
          payload: {
            'action': 'hello',
            'deviceId': deviceId,
          },
        ));
        onConnect?.call();
      })
      ..onAny((event, data) {
        try {
          if (data is List && data.isNotEmpty && data.first is String) {
            final raw = data.first as String;
            final msg = ContinuityMessage.fromJsonString(raw);
            onMessage?.call(msg);
            _incomingMessages.add(msg);
          }
        } catch (e) {
          onError?.call('Failed to parse message: $e');
        }
      })
      ..onDisconnect((_) {
        _isConnected = false;
        _connectCompleter?.completeError(
          StateError('Connection closed by remote'),
        );
        _connectCompleter = null;
        onDisconnect?.call();
      })
      ..onError((error) {
        _isConnected = false;
        _connectCompleter?.completeError(error ?? 'Socket error');
        _connectCompleter = null;
        onError?.call(error);
      })
      ..onConnectError((error) {
        _isConnected = false;
        _connectCompleter?.completeError(error ?? 'Connect error');
        _connectCompleter = null;
      });

    _socket!.connect();

    try {
      await _connectCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          _socket?.dispose();
          _socket = null;
          _isConnected = false;
          throw TimeoutException(
            'Failed to connect to $wsUrl within ${timeout.inSeconds}s',
          );
        },
      );
    } catch (e) {
      _socket?.dispose();
      _socket = null;
      _isConnected = false;
      rethrow;
    }
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
  }

  /// Send a raw message envelope.
  void sendMessage(ContinuityMessage message) {
    _emit(message);
  }

  void _emit(ContinuityMessage message) {
    if (_socket == null) {
      throw StateError('Socket is not connected');
    }
    _socket!.emit('message', message.toJsonString());
  }

  void sendClipboard(String content, {String mimeType = 'text/plain'}) {
    _emit(ContinuityMessage(
      type: ContinuityMessageType.clipboard,
      payload: {
        'action': 'set',
        'content': content,
        'mimeType': mimeType,
      },
    ));
  }

  void requestClipboardHistory() {
    _emit(ContinuityMessage(
      type: ContinuityMessageType.clipboard,
      payload: {
        'action': 'history',
      },
    ));
  }

  void sendFile({
    required String name,
    required int size,
    required String mimeType,
  }) {
    _emit(ContinuityMessage(
      type: ContinuityMessageType.fileTransfer,
      payload: {
        'action': 'offer',
        'name': name,
        'size': size,
        'mimeType': mimeType,
      },
    ));
  }

  void acceptFile(String transferId, String savePath) {
    _emit(ContinuityMessage(
      type: ContinuityMessageType.fileTransfer,
      payload: {
        'action': 'accept',
        'transferId': transferId,
        'savePath': savePath,
      },
    ));
  }

  void rejectFile(String transferId) {
    _emit(ContinuityMessage(
      type: ContinuityMessageType.fileTransfer,
      payload: {
        'action': 'reject',
        'transferId': transferId,
      },
    ));
  }

  void cancelTransfer(String transferId) {
    _emit(ContinuityMessage(
      type: ContinuityMessageType.fileTransfer,
      payload: {
        'action': 'cancel',
        'transferId': transferId,
      },
    ));
  }

  void dispose() {
    _socket?.dispose();
    _incomingMessages.close();
  }
}
