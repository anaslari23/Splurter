import 'package:flutter/material.dart';
import 'package:continuity_ui/continuity_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SettingsSection(
            title: 'Devices',
            children: [
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Manage Paired Devices'),
                subtitle: const Text('View and remove trusted devices'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Manage devices — coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Pair New Device'),
                subtitle: const Text('Scan a QR code to pair'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PairingScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Clipboard',
            children: [
              SwitchListTile(
                value: true,
                onChanged: (v) {},
                title: const Text('Auto-sync clipboard'),
                subtitle: const Text('Automatically copy between paired devices'),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Clipboard History'),
                subtitle: const Text('View and manage synced clipboard items'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Clipboard history — coming soon')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Notifications',
            children: [
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('Android Notification Access'),
                subtitle: const Text('Grant access to relay notifications to Mac'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notification access — coming soon')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'About',
            children: [
              ListTile(
                leading: Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
                title: const Text('Splurter'),
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
