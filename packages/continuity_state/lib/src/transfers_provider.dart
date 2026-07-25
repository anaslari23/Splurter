import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_types/shared_types.dart';

final transfersProvider =
    StateNotifierProvider<TransfersNotifier, List<TransferFile>>((ref) {
  return TransfersNotifier();
});

class TransfersNotifier extends StateNotifier<List<TransferFile>> {
  TransfersNotifier() : super([]);

  void add(TransferFile file) {
    state = [file, ...state.where((f) => f.id != file.id)];
  }

  void updateProgress(String id, int bytesTransferred, TransferStatus status) {
    state = [
      for (final f in state)
        if (f.id == id)
          f.copyWith(
            bytesTransferred: bytesTransferred,
            status: status,
            endTime: status == TransferStatus.completed || status == TransferStatus.failed
                ? DateTime.now()
                : f.endTime,
          )
        else
          f,
    ];
  }

  void cancel(String id) {
    state = [
      for (final f in state)
        if (f.id == id)
          f.copyWith(status: TransferStatus.cancelled, endTime: DateTime.now())
        else
          f,
    ];
  }

  void clear() => state = [];
}
