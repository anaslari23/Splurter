import 'dart:convert';

enum Capability {
  clipboard,
  fileTransfer,
  notifications,
  screenShare,
  remoteControl,
  calls,
}

enum RelayKind {
  pairing,
  clipboard,
  transfer,
  notification,
  screen,
  remoteControl,
  presence,
  call,
}

class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.publicKey,
    required this.capabilities,
    required this.pairedAt,
  });

  final String id;
  final String name;
  final String platform;
  final String publicKey;
  final Set<Capability> capabilities;
  final DateTime pairedAt;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'publicKey': publicKey,
        'capabilities': capabilities.map((value) => value.name).toList(),
        'pairedAt': pairedAt.toUtc().toIso8601String(),
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        platform: json['platform'] as String,
        publicKey: json['publicKey'] as String,
        capabilities: (json['capabilities'] as List<dynamic>)
            .map((value) => Capability.values.byName(value as String))
            .toSet(),
        pairedAt: DateTime.parse(json['pairedAt'] as String),
      );
}

class PairingInvitation {
  const PairingInvitation({
    required this.version,
    required this.hostUid,
    required this.pairId,
    required this.device,
    required this.expiresAt,
  });

  final int version;
  final String hostUid;
  final String pairId;
  final PairedDevice device;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  String toCode() => base64UrlEncode(utf8.encode(jsonEncode(toJson())));

  Map<String, Object> toJson() => {
        'version': version,
        'hostUid': hostUid,
        'pairId': pairId,
        'device': device.toJson(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };

  factory PairingInvitation.fromCode(String code) {
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(code))))
        as Map<String, dynamic>;
    return PairingInvitation.fromJson(json);
  }

  factory PairingInvitation.fromJson(Map<String, dynamic> json) => PairingInvitation(
        version: json['version'] as int,
        hostUid: json['hostUid'] as String,
        pairId: json['pairId'] as String,
        device: PairedDevice.fromJson(json['device'] as Map<String, dynamic>),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}

class Transfer {
  const Transfer({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.status,
  });

  final String id;
  final String name;
  final String mimeType;
  final int size;
  final String status;
}

class NotificationMirror {
  const NotificationMirror({
    required this.id,
    required this.appName,
    required this.title,
    required this.body,
  });

  final String id;
  final String appName;
  final String title;
  final String body;
}

class ScreenSession {
  const ScreenSession({required this.id, required this.isActive, required this.remoteControlAllowed});

  final String id;
  final bool isActive;
  final bool remoteControlAllowed;
}

class RemoteControlCommand {
  const RemoteControlCommand(this.action, {this.x, this.y, this.text});

  final String action;
  final double? x;
  final double? y;
  final String? text;

  bool get isValid => switch (action) {
        'tap' || 'swipe' => x != null && y != null,
        'text' => text != null && text!.isNotEmpty,
        'back' || 'home' || 'stop' => true,
        _ => false,
      };
}

class PhoneCallEvent {
  const PhoneCallEvent({
    required this.callId,
    required this.number,
    this.callerName,
    required this.state,
    this.timestamp,
  });

  final String callId;
  final String number;
  final String? callerName;
  final String state; // 'ringing', 'offhook', 'idle', 'missed'
  final DateTime? timestamp;

  Map<String, Object?> toJson() => {
        'callId': callId,
        'number': number,
        if (callerName != null) 'callerName': callerName,
        'state': state,
        if (timestamp != null) 'timestamp': timestamp!.toUtc().toIso8601String(),
      };

  factory PhoneCallEvent.fromJson(Map<String, dynamic> json) => PhoneCallEvent(
        callId: json['callId'] as String? ?? '',
        number: json['number'] as String? ?? 'Unknown',
        callerName: json['callerName'] as String?,
        state: json['state'] as String? ?? 'idle',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String)
            : null,
      );
}
