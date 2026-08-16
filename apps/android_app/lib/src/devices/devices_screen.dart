import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_types/shared_types.dart';
import 'package:continuity_ui/continuity_ui.dart';
import 'package:continuity_state/continuity_state.dart';
import 'package:platform_bindings/platform_bindings.dart';
import '../../main.dart';

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
    final remoteDevicesAsync = ref.watch(remoteDevicesStreamProvider('mac-channel-1'));
    final rawRemoteDevices = [
      ...?(remoteDevicesAsync.asData?.value),
    ].where((d) => d.platform == 'macos').toList();
    final seenKeys = <String>{};
    final remoteDevices = rawRemoteDevices.where((d) {
      final key = '${d.platform}_${d.name}_${d.address}';
      if (seenKeys.contains(key)) return false;
      seenKeys.add(key);
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined, color: Colors.amberAccent),
            tooltip: 'Grant Android Permissions',
            onPressed: () => _showPermissionsModal(context),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR to pair',
            onPressed: () => context.push('/scan'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: pairedDevice != null
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const AndroidPermissionBanner(),
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 16),
                  color: Colors.amber.shade900.withValues(alpha: 0.18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.amber.shade400.withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 28),
                    title: const Text(
                      'Continuity Permissions',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent),
                    ),
                    subtitle: const Text(
                      'Directly grant Notification, Keyboard & Battery permissions',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => _showPermissionsModal(context),
                      child: const Text('Manage'),
                    ),
                  ),
                ),
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
                            const SizedBox(height: 4),
                            Text(
                              'IP: ${pairedDevice.address}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Continuity Features Active', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        const ListTile(
                          leading: Icon(Icons.copy, color: Colors.blueAccent),
                          title: Text('Cross-Device Clipboard'),
                          subtitle: Text('Instantly synced between Mac & Android'),
                          dense: true,
                        ),
                        const ListTile(
                          leading: Icon(Icons.notifications_active, color: Colors.orangeAccent),
                          title: Text('Notification Mirroring'),
                          subtitle: Text('Android notifications forwarded to Mac'),
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    ref.read(relayLoopProvider).stop();
                    await setHostUid(null);
                    ref.read(pairingStateProvider.notifier).unpair();
                  },
                  icon: const Icon(Icons.link_off),
                  label: const Text('Unpair Device'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ],
            )
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AndroidPermissionBanner(),
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 16),
                  color: Colors.amber.shade900.withValues(alpha: 0.18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.amber.shade400.withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 28),
                    title: const Text(
                      'Continuity Permissions',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent),
                    ),
                    subtitle: const Text(
                      'Directly grant Notification, Keyboard & Battery permissions',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => _showPermissionsModal(context),
                      child: const Text('Manage'),
                    ),
                  ),
                ),
                    const SizedBox(height: 16),
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
                    if (remoteDevices.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.wifi_tethering_rounded, color: theme.colorScheme.primary, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Available Mac Devices on Local Network',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...remoteDevices.map((dev) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: theme.colorScheme.outlineVariant),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.laptop_mac_rounded, color: theme.colorScheme.primary, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          dev.name.isNotEmpty ? dev.name : 'Mac (${dev.platform})',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                        ),
                                        Text(
                                          dev.address.isNotEmpty ? 'IP: ${dev.address}' : 'Ready to pair via Wi-Fi',
                                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () async {
                                      ref.read(pairingStateProvider.notifier).complete(dev.copyWith(isPaired: true));
                                      final hostUid = dev.address.isNotEmpty ? dev.address : 'mac-channel-1';
                                      await setHostUid(hostUid);
                                      ref.read(relayLoopProvider).start(uid: hostUid, deviceId: kAndroidDeviceId);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Connected to ${dev.name} instantly!')),
                                        );
                                      }
                                    },
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Connect Instantly', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  void _showPermissionsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.amber, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Android Permissions',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a permission below to directly open Android Settings and enable it:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined, color: Colors.amberAccent),
                title: const Text('Notification Access Permission'),
                subtitle: const Text('Required to mirror notifications to Mac'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  Navigator.pop(ctx);
                  await openNotificationListenerSettings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.keyboard_outlined, color: Colors.amberAccent),
                title: const Text('Splurter Keyboard Permission'),
                subtitle: const Text('Required for cross-device clipboard sync'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  Navigator.pop(ctx);
                  await openInputMethodSettings();
                  await showInputMethodPicker();
                },
              ),
              ListTile(
                leading: const Icon(Icons.battery_charging_full_outlined, color: Colors.amberAccent),
                title: const Text('Unrestricted Battery Permission'),
                subtitle: const Text('Required for reliable background sync'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  Navigator.pop(ctx);
                  await requestBatteryExemption();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

