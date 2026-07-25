import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_types/shared_types.dart';
import 'package:continuity_ui/continuity_ui.dart' as ui;
import 'package:continuity_state/continuity_state.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class TransferScreen extends ConsumerWidget {
  const TransferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transfersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: ui.TransferScreen(
        transfers: transfers,
        onOpenFile: (id) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opening file $id...')),
          );
        },
        onCancel: (id) {
          ref.read(transfersProvider.notifier).cancel(id);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final transferId = _uuid.v4();
          final newFile = TransferFile(
            id: transferId,
            name: 'Sample_Document.pdf',
            path: '/downloads/Sample_Document.pdf',
            size: 2048576,
            mimeType: 'application/pdf',
            direction: TransferDirection.sending,
            status: TransferStatus.inProgress,
            startTime: DateTime.now(),
            bytesTransferred: 512000,
            deviceName: 'My Mac',
          );
          ref.read(transfersProvider.notifier).add(newFile);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Started file transfer to Mac')),
          );
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Send File'),
      ),
    );
  }
}

