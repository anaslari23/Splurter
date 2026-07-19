import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_types/shared_types.dart';

class DiscoveredDevicesNotifier extends StateNotifier<List<Device>> {
  DiscoveredDevicesNotifier() : super(const []);

  void addDevice(Device device) {
    final existingIndex = state.indexWhere((d) => d.id == device.id);
    if (existingIndex >= 0) {
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == existingIndex) device else state[i],
      ];
    } else {
      state = [...state, device];
    }
  }

  void removeDevice(String deviceId) {
    state = state.where((d) => d.id != deviceId).toList();
  }

  void setPaired(String deviceId, {bool isPaired = true}) {
    state = state
        .map((d) => d.id == deviceId ? d.copyWith(isPaired: isPaired) : d)
        .toList();
  }
}

class DeviceCard extends ConsumerWidget {
  const DeviceCard({
    super.key,
    required this.device,
    this.onTap,
    this.onConnect,
  });

  final Device device;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap ?? onConnect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Platform icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: device.platform == 'android'
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  device.platform == 'android'
                      ? Icons.android
                      : Icons.laptop_mac,
                  size: 28,
                  color: device.platform == 'android'
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 16),

              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.address,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Capabilities
              if (device.capabilities.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: device.capabilities
                      .take(3)
                      .map((cap) => _CapabilityChip(label: cap))
                      .toList(),
                ),

              // Pairing status
              if (device.isPaired)
                Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                  size: 20,
                )
              else
                Icon(
                  Icons.radio_button_unchecked,
                  color: theme.colorScheme.outline,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        _labelForCapability(label),
        style: const TextStyle(fontSize: 10),
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _labelForCapability(String cap) {
    switch (cap) {
      case 'clipboard':
        return 'Clipboard';
      case 'transfer':
        return 'Transfer';
      case 'screen':
        return 'Screen';
      case 'notification':
        return 'Notifs';
      default:
        return cap;
    }
  }
}
