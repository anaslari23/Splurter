import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_types/shared_types.dart';
import 'package:continuity_ui/continuity_ui.dart';

// Placeholder state — real discovery/pairing logic lives in platform_bindings + continuity_api
final discoveredDevicesProvider = StateProvider<List<Device>>((_) => []);

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(discoveredDevicesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR to pair',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PairingScreen()),
              );
            },
          ),
        ],
      ),
      body: devices.isEmpty
          ? Center(
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
                    'No devices found',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure both devices are on the same Wi-Fi network',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return DeviceCard(
                  device: device,
                  onConnect: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Connecting to ${device.name}... (placeholder)'),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pairing screen coming soon')),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Pair Device'),
      ),
    );
  }
}
