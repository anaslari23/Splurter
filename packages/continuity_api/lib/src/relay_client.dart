import 'dart:async';

import 'package:continuity_core/continuity_core.dart';

/// Transport boundary for the Firebase relay implementation.
///
/// The client never receives plaintext peer data from Firebase: callers seal
/// payloads with [SessionCipher] before constructing an envelope.
abstract class RelayClient {
  bool get isConnected;
  Stream<RelayEnvelope> get messages;

  Future<void> connect();
  Future<void> send(RelayEnvelope envelope);
  Future<void> disconnect();
}

/// A small deterministic transport for local UI and protocol tests.
class InMemoryRelayClient implements RelayClient {
  final _messages = StreamController<RelayEnvelope>.broadcast();
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<RelayEnvelope> get messages => _messages.stream;

  @override
  Future<void> connect() async => _isConnected = true;

  @override
  Future<void> send(RelayEnvelope envelope) async {
    if (!_isConnected) throw StateError('Relay is not connected');
    _messages.add(envelope);
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
  }

  Future<void> dispose() => _messages.close();
}
