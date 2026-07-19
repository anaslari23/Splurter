import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_types/shared_types.dart';
import 'package:continuity_ui/continuity_ui.dart' as ui;

class TransferScreen extends ConsumerWidget {
  const TransferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Placeholder transfers — swap for Riverpod state when wired up.
    final transfers = <TransferFile>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: ui.TransferScreen(
        transfers: transfers,
        onOpenFile: (id) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Open file — coming soon')),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Open file picker, call ContinuitySocketClient.sendFile(),
          // then stream the file bytes over the WebSocket.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Send file — coming soon')),
          );
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Send File'),
      ),
    );
  }
}
