import 'dart:convert';

/// Message types for the Continuity protocol.
enum ContinuityMessageType {
  pairing('pairing'),
  clipboard('clipboard'),
  fileTransfer('fileTransfer'),
  screen('screen'),
  notification('notification'),
  hotspot('hotspot');

  const ContinuityMessageType(this.value);
  final String value;

  static ContinuityMessageType fromValue(String value) {
    return ContinuityMessageType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Unknown message type: $value'),
    );
  }
}

class ContinuityMessage {
  final ContinuityMessageType type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  ContinuityMessage({
    required this.type,
    required this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ContinuityMessage.fromJson(Map<String, dynamic> json) {
    return ContinuityMessage(
      type: ContinuityMessageType.fromValue(json['type'] as String),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
    );
  }

  factory ContinuityMessage.fromJsonString(String raw) {
    return ContinuityMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Map<String, dynamic> toJson() => {
        'type': type.value,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());
}
