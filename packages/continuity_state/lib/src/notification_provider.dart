import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationsEnabledProvider =
    StateProvider<bool>((ref) => false);

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<SplurterNotification>>((ref) {
  return NotificationsNotifier();
});

class NotificationsNotifier extends StateNotifier<List<SplurterNotification>> {
  NotificationsNotifier() : super([]);

  void add(SplurterNotification n) {
    state = [n, ...state.where((i) => i.id != n.id)].take(100).toList();
  }

  void dismiss(String id) {
    state = state.where((i) => i.id != id).toList();
  }

  void clear() => state = [];
}

class SplurterNotification {
  const SplurterNotification({
    required this.id,
    required this.packageName,
    required this.title,
    required this.text,
    required this.timestamp,
    this.appIcon,
  });

  final String id;
  final String packageName;
  final String title;
  final String text;
  final DateTime timestamp;
  final String? appIcon;

  factory SplurterNotification.fromJson(Map<String, dynamic> json) {
    return SplurterNotification(
      id: json['id'] as String,
      packageName: json['packageName'] as String,
      title: json['title'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      appIcon: json['appIcon'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'packageName': packageName,
    'title': title,
    'text': text,
    'timestamp': timestamp.millisecondsSinceEpoch,
    if (appIcon != null) 'appIcon': appIcon,
  };
}
