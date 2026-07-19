class ClipItem {
  const ClipItem({
    required this.id,
    required this.content,
    required this.mimeType,
    required this.timestamp,
    this.deviceName,
  });

  final String id;
  final String content;
  final String mimeType; // 'text/plain', 'image/png', 'text/html', etc.
  final DateTime timestamp;
  final String? deviceName; // which device this came from

  ClipItem copyWith({
    String? id,
    String? content,
    String? mimeType,
    DateTime? timestamp,
    String? deviceName,
  }) {
    return ClipItem(
      id: id ?? this.id,
      content: content ?? this.content,
      mimeType: mimeType ?? this.mimeType,
      timestamp: timestamp ?? this.timestamp,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'mimeType': mimeType,
    'timestamp': timestamp.toIso8601String(),
    'deviceName': deviceName,
  };

  factory ClipItem.fromJson(Map<String, dynamic> json) => ClipItem(
    id: json['id'] as String,
    content: json['content'] as String,
    mimeType: json['mimeType'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    deviceName: json['deviceName'] as String?,
  );

  @override
  String toString() => 'ClipItem(mimeType: $mimeType, deviceName: $deviceName, timestamp: $timestamp)';
}
