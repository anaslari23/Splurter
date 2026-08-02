class Device {
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.version,
    required this.capabilities,
    required this.isPaired,
    this.fingerprint,
    this.batteryLevel = 88,
    this.isCharging = false,
    this.carrier = '5G',
    this.nowPlayingTitle,
    this.nowPlayingArtist,
    this.wallpaperTheme,
  });

  final String id;
  final String name;
  final String platform; // 'android' | 'macos'
  final String address;
  final int port;
  final String version;
  final List<String> capabilities; // ['clipboard', 'transfer', 'screen', ...]
  final bool isPaired;
  final String? fingerprint;
  final int batteryLevel;
  final bool isCharging;
  final String carrier;
  final String? nowPlayingTitle;
  final String? nowPlayingArtist;
  final String? wallpaperTheme;

  Device copyWith({
    String? id,
    String? name,
    String? platform,
    String? address,
    int? port,
    String? version,
    List<String>? capabilities,
    bool? isPaired,
    String? fingerprint,
    int? batteryLevel,
    bool? isCharging,
    String? carrier,
    String? nowPlayingTitle,
    String? nowPlayingArtist,
    String? wallpaperTheme,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      address: address ?? this.address,
      port: port ?? this.port,
      version: version ?? this.version,
      capabilities: capabilities ?? this.capabilities,
      isPaired: isPaired ?? this.isPaired,
      fingerprint: fingerprint ?? this.fingerprint,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      carrier: carrier ?? this.carrier,
      nowPlayingTitle: nowPlayingTitle ?? this.nowPlayingTitle,
      nowPlayingArtist: nowPlayingArtist ?? this.nowPlayingArtist,
      wallpaperTheme: wallpaperTheme ?? this.wallpaperTheme,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'address': address,
    'port': port,
    'version': version,
    'capabilities': capabilities,
    'isPaired': isPaired,
    'fingerprint': fingerprint,
    'batteryLevel': batteryLevel,
    'isCharging': isCharging,
    'carrier': carrier,
    'nowPlayingTitle': nowPlayingTitle,
    'nowPlayingArtist': nowPlayingArtist,
    'wallpaperTheme': wallpaperTheme,
  };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as String,
    name: json['name'] as String,
    platform: json['platform'] as String,
    address: json['address'] as String,
    port: json['port'] as int,
    version: json['version'] as String,
    capabilities: List<String>.from(json['capabilities'] as List),
    isPaired: json['isPaired'] as bool? ?? false,
    fingerprint: json['fingerprint'] as String?,
    batteryLevel: json['batteryLevel'] as int? ?? 88,
    isCharging: json['isCharging'] as bool? ?? false,
    carrier: json['carrier'] as String? ?? '5G',
    nowPlayingTitle: json['nowPlayingTitle'] as String?,
    nowPlayingArtist: json['nowPlayingArtist'] as String?,
    wallpaperTheme: json['wallpaperTheme'] as String?,
  );

  @override
  String toString() => 'Device(name: $name, platform: $platform, address: $address)';
}
