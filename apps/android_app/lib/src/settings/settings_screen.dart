import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:continuity_state/continuity_state.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifSync = ref.watch(notificationsEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SettingsSection(
            title: 'Devices & Pairing',
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Pair New Device'),
                subtitle: const Text('Scan QR code on macOS companion'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/scan'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Background Sync & Permissions',
            children: [
              SwitchListTile(
                value: notifSync,
                onChanged: (v) async {
                  if (v) {
                    await const MethodChannel('splurter/notifications').invokeMethod('requestPermission');
                  }
                  ref.read(notificationsEnabledProvider.notifier).state = v;
                },
                title: const Text('Notification Mirroring Toggle'),
                subtitle: const Text('Relay Android notifications to Mac desktop'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'About',
            children: [
              ListTile(
                leading: Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
                title: const Text('Splurter Continuity'),
                subtitle: const Text('Version 0.1.0'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: children),
        ),
      ],
    );
  }
}
