import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:continuity_api/continuity_api.dart';
import 'package:shared_types/shared_types.dart';
import 'package:uuid/uuid.dart';

import 'socket_provider.dart';

final _uuid = Uuid();

final clipHistoryProvider =
    StateNotifierProvider<ClipHistoryNotifier, List<ClipItem>>((ref) {
  return ClipHistoryNotifier();
});

class ClipHistoryNotifier extends StateNotifier<List<ClipItem>> {
  ClipHistoryNotifier() : super([]);

  void add(ClipItem item) {
    state = [item, ...state.where((i) => i.id != item.id)].take(200).toList();
  }

  void update(String id, {DateTime? timestamp, String? deviceName}) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(timestamp: timestamp ?? item.timestamp, deviceName: deviceName ?? item.deviceName)
        else
          item,
    ];
  }

  void remove(String id) {
    state = state.where((i) => i.id != id).toList();
  }

  void clear() => state = [];
}

final clipboardSyncEnabledProvider =
    StateProvider<bool>((ref) => false);

final incomingClipProvider =
    StreamProvider<ClipItem>((ref) {
  final socket = ref.watch(socketProvider);
  if (socket == null) return const Stream.empty();

  final controller = StreamController<ClipItem>.broadcast();

  final sub = socket.messages.listen((msg) {
    if (msg.kind == RelayKind.clipboard) {
      final content = msg.payload['content'] as String;
      final mimeType = msg.payload['mimeType'] as String? ?? 'text/plain';
      final item = ClipItem(
        id: _uuid.v4(),
        content: content,
        mimeType: mimeType,
        timestamp: DateTime.now(),
        deviceName: 'from remote',
      );
      if (!controller.isClosed) controller.add(item);
    }
  });

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});
