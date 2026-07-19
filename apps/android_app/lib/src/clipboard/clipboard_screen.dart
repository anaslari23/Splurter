import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:continuity_ui/continuity_ui.dart';
import 'package:shared_types/shared_types.dart';

class ClipboardScreen extends ConsumerWidget {
  const ClipboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Placeholder history — swap for Riverpod state when the real clipboard
    // integration is wired up.
    final history = <ClipItem>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Clipboard')),
      body: ClipboardHistoryScreen(clipItems: history),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Trigger a manual "push current clipboard to paired device" action.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clipboard sync — coming soon')),
          );
        },
        icon: const Icon(Icons.send),
        label: const Text('Send Clipboard'),
      ),
    );
  }
}
