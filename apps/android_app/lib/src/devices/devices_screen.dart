import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_types/shared_types.dart';
import 'package:continuity_ui/continuity_ui.dart';
import 'package:continuity_state/continuity_state.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  @override
  Widget build(BuildContext context) {
    final pairingState = ref.watch(pairingStateProvider);
    final theme = Theme.of(context);

    final Device? pairedDevice = pairingState is PairingConnected ? pairingState.device : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR to pair',
            onPressed: () => context.push('/scan'),
          ),
        ],
      ),
      body: pairedDevice != null
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connected to ${pairedDevice.name}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade300,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Always-On Continuity Active • Direct Wi-Fi & Cloud Relay',
                              style: TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                DeviceCard(device: pairedDevice),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(pairingStateProvider.notifier).unpair();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Disconnected from Mac')),
                      );
                    }
                  },
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect Device'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ],
            )

          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.devices,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No device paired',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scan the QR code displayed on your Mac Splurter app to pair.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.push('/scan'),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR Code'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

