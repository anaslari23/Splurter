import 'dart:async';

import 'package:continuity_core/continuity_core.dart';
import 'relay_client.dart';

/// Production Firebase relay implementation backed by Firestore document streams.
class FirebaseRelayClient implements RelayClient {
  FirebaseRelayClient({
    required this.incomingStream,
    required this.onSend,
  });

  final Stream<RelayEnvelope> incomingStream;
  final Future<void> Function(RelayEnvelope envelope) onSend;

  final _messages = StreamController<RelayEnvelope>.broadcast();
  StreamSubscription<RelayEnvelope>? _sub;
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<RelayEnvelope> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    _isConnected = true;
    _sub = incomingStream.listen((env) {
      if (!_messages.isClosed) _messages.add(env);
    });
  }

  @override
  Future<void> send(RelayEnvelope envelope) async {
    if (!_isConnected) throw StateError('Relay is not connected');
    await onSend(envelope);
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}
