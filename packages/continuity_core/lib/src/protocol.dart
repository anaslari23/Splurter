import 'dart:convert';

import 'models.dart';

class RelayEnvelope {
  const RelayEnvelope({
    required this.version,
    required this.id,
    required this.kind,
    required this.senderId,
    required this.recipientId,
    required this.sentAt,
    required this.payload,
  });

  static const currentVersion = 1;

  final int version;
  final String id;
  final RelayKind kind;
  final String senderId;
  final String recipientId;
  final DateTime sentAt;
  final Map<String, dynamic> payload;

  Map<String, Object> toJson() => {
        'version': version,
        'id': id,
        'kind': kind.name,
        'senderId': senderId,
        'recipientId': recipientId,
        'sentAt': sentAt.toUtc().toIso8601String(),
        'payload': payload,
      };

  String encode() => jsonEncode(toJson());

  factory RelayEnvelope.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final version = json['version'] as int;
    if (version != currentVersion) {
      throw FormatException('Unsupported protocol version: $version');
    }
    return RelayEnvelope(
      version: version,
      id: json['id'] as String,
      kind: RelayKind.values.byName(json['kind'] as String),
      senderId: json['senderId'] as String,
      recipientId: json['recipientId'] as String,
      sentAt: DateTime.parse(json['sentAt'] as String),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
    );
  }
}
