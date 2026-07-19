enum TransferStatus { pending, inProgress, paused, completed, failed, cancelled }

enum TransferDirection { sending, receiving }

class TransferFile {
  const TransferFile({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.mimeType,
    required this.direction,
    required this.status,
    required this.startTime,
    this.endTime,
    this.bytesTransferred = 0,
    this.deviceName,
    this.localPath,
  });

  final String id;
  final String name;
  final String path;
  final int size;
  final String mimeType;
  final TransferDirection direction;
  final TransferStatus status;
  final DateTime startTime;
  final DateTime? endTime;
  final int bytesTransferred;
  final String? deviceName;
  final String? localPath; // where the file ended up locally

  double get progress => size > 0 ? bytesTransferred / size : 0.0;

  TransferFile copyWith({
    String? id,
    String? name,
    String? path,
    int? size,
    String? mimeType,
    TransferDirection? direction,
    TransferStatus? status,
    DateTime? startTime,
    DateTime? endTime,
    int? bytesTransferred,
    String? deviceName,
    String? localPath,
  }) {
    return TransferFile(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      size: size ?? this.size,
      mimeType: mimeType ?? this.mimeType,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      deviceName: deviceName ?? this.deviceName,
      localPath: localPath ?? this.localPath,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'size': size,
    'mimeType': mimeType,
    'direction': direction.name,
    'status': status.name,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'bytesTransferred': bytesTransferred,
    'deviceName': deviceName,
    'localPath': localPath,
  };

  factory TransferFile.fromJson(Map<String, dynamic> json) => TransferFile(
    id: json['id'] as String,
    name: json['name'] as String,
    path: json['path'] as String,
    size: json['size'] as int,
    mimeType: json['mimeType'] as String,
    direction: TransferDirection.values.firstWhere(
      (e) => e.name == json['direction'],
    ),
    status: TransferStatus.values.firstWhere(
      (e) => e.name == json['status'],
    ),
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
    bytesTransferred: json['bytesTransferred'] as int? ?? 0,
    deviceName: json['deviceName'] as String?,
    localPath: json['localPath'] as String?,
  );

  @override
  String toString() => 'TransferFile(name: $name, direction: $direction, status: $status, progress: ${(progress * 100).toInt()}%)';
}
